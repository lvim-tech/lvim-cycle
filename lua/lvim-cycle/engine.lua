-- lvim-cycle.engine: match selection and application — the heart of the plugin.
-- Every enabled augend proposes ITS best candidate for the current line/cursor (find);
-- better()/pick() rank candidates with a three-tier rule: a span CONTAINING the cursor
-- beats a span AFTER it, which beats a span BEFORE it. Only an augend that deliberately
-- returns a before-cursor match (markdown_header — the hashes sit at column 1 while the
-- cursor is anywhere on the header line) ever lands in the last tier; the numeric augends
-- never match backwards, preserving native <C-a> semantics ("123 foo|" stays untouched).
-- Within a tier: earlier start, then the LONGER span (so `0x1F` beats the bare `0` inside
-- it), then the earlier augend in the group list (the caller iterates in order and only
-- replaces on a STRICT improvement). apply_at() performs the single-line buffer edit and
-- reports where the cursor should land — dial semantics: the end of the new text, or the
-- end of the changed FIELD when the augend picks one (date/semver/hexcolor). flash()
-- confirms WHAT changed with a short extmark tint.
--
---@module "lvim-cycle.engine"

local config = require("lvim-cycle.config")

---@class LvimCycleMatch
---@field s integer   1-based byte column of the first character of the match
---@field e integer   1-based byte column of the last character (inclusive)
---@field text string matched text (exactly line:sub(s, e))

---@class LvimCycleAugend
---@field find fun(line: string, col: integer): LvimCycleMatch|nil  the augend's best candidate for this line and 1-based cursor column (nil = no match)
---@field add fun(text: string, delta: integer, cur: integer): string|nil, integer|nil  new text (nil / unchanged = no-op) and the 1-based cursor position within it (nil = its end); `cur` is the cursor position within `text` (< 1 when the match starts after the cursor)

local M = {}

---@type integer
local ns = vim.api.nvim_create_namespace("lvim-cycle-flash")
---@type uv.uv_timer_t|nil  shared one-shot timer clearing every pending flash
local flash_timer = nil
---@type table<integer, boolean>  buffers with pending flash extmarks
local flashed = {}

--- Rank tier of a candidate relative to the cursor: 1 = contains it, 2 = after it, 3 = before it.
---@param m LvimCycleMatch
---@param col integer
---@return integer
local function tier(m, col)
    if m.s <= col and col <= m.e then
        return 1
    end
    if m.s > col then
        return 2
    end
    return 3
end

--- Whether candidate `a` STRICTLY beats `b` for the cursor at `col`.
---@param a LvimCycleMatch
---@param b LvimCycleMatch
---@param col integer
---@return boolean
function M.better(a, b, col)
    local ta, tb = tier(a, col), tier(b, col)
    if ta ~= tb then
        return ta < tb
    end
    if ta == 3 then
        -- both end before the cursor: the one ending NEAREST to it wins
        return a.e > b.e
    end
    if a.s ~= b.s then
        return a.s < b.s
    end
    return a.e > b.e
end

--- The best of `candidates` for the cursor at `col`. Augends use this to pre-select among
--- their own matches with the same ranking the engine applies across augends.
---@param candidates LvimCycleMatch[]
---@param col integer
---@return LvimCycleMatch|nil
function M.pick(candidates, col)
    local best = nil ---@type LvimCycleMatch|nil
    for _, m in ipairs(candidates) do
        if not best or M.better(m, best, col) then
            best = m
        end
    end
    return best
end

--- Tint the changed span for `config.flash_ms`. One shared timer serves every flash: a burst
--- (visual mode over many lines) restarts it once and a single sweep clears them all.
---@param buf integer
---@param row integer   0-based row
---@param scol integer  0-based start byte column
---@param ecol integer  0-based end byte column (exclusive)
---@return nil
function M.flash(buf, row, scol, ecol)
    if not config.flash then
        return
    end
    vim.api.nvim_buf_set_extmark(buf, ns, row, scol, {
        end_col = ecol,
        hl_group = "LvimCycleFlash",
        priority = 500,
    })
    flashed[buf] = true
    if not flash_timer then
        flash_timer = assert(vim.uv.new_timer())
    end
    flash_timer:stop()
    flash_timer:start(
        config.flash_ms,
        0,
        vim.schedule_wrap(function()
            for b in pairs(flashed) do
                if vim.api.nvim_buf_is_valid(b) then
                    vim.api.nvim_buf_clear_namespace(b, ns, 0, -1)
                end
            end
            flashed = {}
        end)
    )
end

---@class LvimCycleApplyOpts
---@field max_s? integer        reject candidates starting past this byte column (visual charwise/blockwise right bound)
---@field at_or_after? boolean  reject candidates ending before `col` (visual semantics: only matches inside the selection)

---@class LvimCycleApplyResult
---@field s integer       1-based start column of the changed span
---@field cursor integer  1-based line column where the cursor should land

--- Apply `delta` to the best match of `augs` on one line of `buf`.
---@param buf integer
---@param row integer   0-based row
---@param col integer   1-based reference (cursor) column
---@param delta integer
---@param augs LvimCycleAugend[]
---@param opts? LvimCycleApplyOpts
---@return LvimCycleApplyResult|nil  nil when nothing matched or the augend reported no change
function M.apply_at(buf, row, col, delta, augs, opts)
    opts = opts or {}
    local line = (vim.api.nvim_buf_get_lines(buf, row, row + 1, false) or {})[1]
    if not line or line == "" then
        return nil
    end
    local best = nil ---@type LvimCycleMatch|nil
    local best_aug = nil ---@type LvimCycleAugend|nil
    for _, aug in ipairs(augs) do
        local m = aug.find(line, col)
        if m and (not opts.max_s or m.s <= opts.max_s) and not (opts.at_or_after and m.e < col) then
            if not best or M.better(m, best, col) then
                best, best_aug = m, aug
            end
        end
    end
    if not best or not best_aug then
        return nil
    end
    local newtext, newcur = best_aug.add(best.text, delta, col - best.s + 1)
    if not newtext or newtext == best.text then
        return nil
    end
    vim.api.nvim_buf_set_text(buf, row, best.s - 1, row, best.e, { newtext })
    M.flash(buf, row, best.s - 1, best.s - 1 + #newtext)
    return { s = best.s, cursor = best.s + (newcur or #newtext) - 1 }
end

--- Normal-mode application at the current cursor, moving the cursor onto the result.
---@param delta integer
---@param augs LvimCycleAugend[]
---@return nil
function M.apply(delta, augs)
    local pos = vim.api.nvim_win_get_cursor(0)
    local res = M.apply_at(vim.api.nvim_get_current_buf(), pos[1] - 1, pos[2] + 1, delta, augs)
    if res then
        vim.api.nvim_win_set_cursor(0, { pos[1], res.cursor - 1 })
    end
end

return M
