-- lvim-cycle.visual: visual-mode application — plain (every selected line's first match
-- gets the same delta) and SEQUENTIAL (the k-th line WITH a match gets k × count — the
-- numbered-list use case, mirroring native g<C-a>). Invoked from <Cmd> maps, so the mode
-- is STILL visual here: v:count1 is intact and the live selection is read from
-- getpos("v")/getpos("."). The selection is then left via feedkeys(<Esc>, "nx") BEFORE
-- editing — the "x" flag flushes immediately, so the buffer edits happen in normal mode.
-- Per line, the search starts at the selection's left bound (column 1 for linewise and
-- charwise middle lines) and a match must START inside the selection's right bound on
-- bounded lines; matches ending before the bound are rejected (at_or_after), so only
-- values inside the selection change.
--
---@module "lvim-cycle.visual"

local engine = require("lvim-cycle.engine")
local augends = require("lvim-cycle.augends")

local M = {}

---@type string
local ESC = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)

--- Selection geometry (1-based rows and byte cols), normalised so start <= end.
---@return integer sr, integer sc, integer er, integer ec
local function selection()
    local v = vim.fn.getpos("v")
    local c = vim.fn.getpos(".")
    local sr, sc, er, ec = v[2], v[3], c[2], c[3]
    if sr > er or (sr == er and sc > ec) then
        sr, sc, er, ec = er, ec, sr, sc
    end
    return sr, sc, er, ec
end

--- Apply direction × count over the selection; sequential multiplies per matched line.
---@param dir 1|-1
---@param sequential boolean
---@return nil
local function run(dir, sequential)
    local count = vim.v.count1
    local mode = vim.fn.mode()
    if mode ~= "v" and mode ~= "V" and mode ~= "\22" then
        return
    end
    local sr, sc, er, ec = selection()
    vim.api.nvim_feedkeys(ESC, "nx", false)
    local buf = vim.api.nvim_get_current_buf()
    local augs = augends.for_buffer(buf)
    local k = 0
    local first = nil ---@type { row: integer, col: integer }|nil
    for row = sr, er do
        local col, max_s
        if mode == "V" then
            col = 1
        elseif mode == "\22" then
            -- block corners may be column-crossed independently of the rows
            col = math.min(sc, ec)
            max_s = math.max(sc, ec)
        else
            col = (row == sr) and sc or 1
            max_s = (row == er) and ec or nil
        end
        local delta = dir * count * (sequential and (k + 1) or 1)
        local res = engine.apply_at(buf, row - 1, col, delta, augs, { max_s = max_s, at_or_after = true })
        if res then
            k = k + 1
            first = first or { row = row, col = res.cursor }
        end
    end
    if first then
        vim.api.nvim_win_set_cursor(0, { first.row, first.col - 1 })
    end
end

--- Increment the first match on every selected line by v:count1.
---@return nil
function M.increment()
    run(1, false)
end

--- Decrement the first match on every selected line by v:count1.
---@return nil
function M.decrement()
    run(-1, false)
end

--- Sequential increment: the k-th matched line gets k × v:count1.
---@return nil
function M.increment_sequential()
    run(1, true)
end

--- Sequential decrement: the k-th matched line gets -k × v:count1.
---@return nil
function M.decrement_sequential()
    run(-1, true)
end

return M
