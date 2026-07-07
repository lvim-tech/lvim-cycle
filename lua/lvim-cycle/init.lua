-- lvim-cycle: a smarter <C-a>/<C-x> — increment / decrement / cycle the value under (or
-- after) the cursor: integers in any base, floats, dates, semver, hex colors and
-- configurable word groups ("true" ⇄ "false"), with counts, visual mode, g<C-a>-style
-- sequential increments and dot-repeat. This module is the public entry point: setup()
-- merges user opts into the live config, validates every group spec with a precise error,
-- self-themes the flash from the lvim-utils palette, and installs the <Plug> maps (plus
-- the default keys when map_default_keys).
--
-- Dot-repeat rides the NATIVE operatorfunc seam: the normal-mode <Plug> triggers are expr
-- maps that stash direction × v:count1, set 'operatorfunc' and return "g@l" — so `.`
-- repeats the exact operation with its count, with no repeat.vim and no feedkeys tricks.
-- (The g@ range is a single ignored `l`; opfunc re-reads the stash.) Visual triggers go
-- through <Cmd>, where v:count1 and the live selection are still readable — see visual.lua.
--
---@module "lvim-cycle"

local config = require("lvim-cycle.config")
local engine = require("lvim-cycle.engine")
local augends = require("lvim-cycle.augends")

-- shared merge (clean array REPLACE) when lvim-utils is installed; the fallback keeps the
-- same semantics so a user group list always replaces the default wholesale.
local ok_utils, uu = pcall(require, "lvim-utils.utils")

local M = {}

---@type boolean  one-time registration (maps, highlight bind) done
local registered = false
---@type integer  signed delta stashed by the last normal-mode trigger (direction × count); re-read by opfunc on `.`
local pending_delta = 1

--- Array-replacing deep merge (mirrors lvim-utils.utils.merge) for a standalone install:
--- list values REPLACE — a user group list is the list, not an index-merge with stale
--- default entries left in the tail.
---@param target table
---@param opts? table
---@return table target
local function merge(target, opts)
    for k, v in pairs(opts or {}) do
        if type(v) == "table" and type(target[k]) == "table" and not vim.islist(v) then
            merge(target[k], v)
        else
            target[k] = v
        end
    end
    return target
end

--- Validate the INCOMING group specs; error() with ALL problems at once, each pin-pointed
--- to groups.<name>[<index>], so a broken custom augend fails loudly at setup, not
--- silently at the first keypress. Runs BEFORE the merge: the defaults are known-good and
--- group lists replace wholesale, so a rejected opts table never pollutes the live config.
---@param groups table<string, LvimCycleSpec[]>
---@return nil
local function validate_groups(groups)
    local errs = {}
    for name, list in pairs(groups) do
        if type(list) ~= "table" then
            errs[#errs + 1] = ("groups.%s: must be a list of augend specs (got %s)"):format(name, type(list))
        else
            for i, spec in ipairs(list) do
                local _, err = augends.resolve(spec)
                if err then
                    errs[#errs + 1] = ("groups.%s[%d]: %s"):format(name, i, err)
                end
            end
        end
    end
    if #errs > 0 then
        error("lvim-cycle: invalid config:\n  " .. table.concat(errs, "\n  "), 0)
    end
end

--- Self-theme the flash from the lvim-utils palette (re-derived on ColorScheme / palette
--- sync); a plain IncSearch link keeps the flash visible without lvim-utils.
---@return nil
local function set_highlights()
    local ok_hl, hl = pcall(require, "lvim-utils.highlight")
    if ok_hl and type(hl.bind) == "function" then
        hl.bind(require("lvim-cycle.highlights").build)
    else
        vim.api.nvim_set_hl(0, "LvimCycleFlash", { link = "IncSearch", default = true })
    end
end

--- The operatorfunc target: applies the stashed delta at the cursor. Public only because
--- 'operatorfunc' needs a reachable v:lua name.
---@return nil
function M.opfunc(_)
    engine.apply(pending_delta, augends.for_buffer(0))
end

--- Build a normal-mode expr trigger: stash direction × count, arm operatorfunc, "g@l".
---@param dir 1|-1
---@return fun(): string
local function trigger(dir)
    return function()
        pending_delta = dir * vim.v.count1
        vim.go.operatorfunc = "v:lua.require'lvim-cycle'.opfunc"
        return "g@l"
    end
end

--- Install the <Plug> maps (always available, independent of map_default_keys).
---@return nil
local function set_plug_maps()
    vim.keymap.set("n", "<Plug>(lvim-cycle-increment)", trigger(1), {
        expr = true,
        silent = true,
        desc = "Increment value under cursor",
    })
    vim.keymap.set("n", "<Plug>(lvim-cycle-decrement)", trigger(-1), {
        expr = true,
        silent = true,
        desc = "Decrement value under cursor",
    })
    vim.keymap.set("x", "<Plug>(lvim-cycle-increment)", "<Cmd>lua require('lvim-cycle.visual').increment()<CR>", {
        silent = true,
        desc = "Increment values in selection",
    })
    vim.keymap.set("x", "<Plug>(lvim-cycle-decrement)", "<Cmd>lua require('lvim-cycle.visual').decrement()<CR>", {
        silent = true,
        desc = "Decrement values in selection",
    })
    vim.keymap.set(
        "x",
        "<Plug>(lvim-cycle-increment-sequential)",
        "<Cmd>lua require('lvim-cycle.visual').increment_sequential()<CR>",
        { silent = true, desc = "Sequentially increment values in selection" }
    )
    vim.keymap.set(
        "x",
        "<Plug>(lvim-cycle-decrement-sequential)",
        "<Cmd>lua require('lvim-cycle.visual').decrement_sequential()<CR>",
        { silent = true, desc = "Sequentially decrement values in selection" }
    )
end

--- Map the default keys onto the <Plug> maps.
---@return nil
local function set_default_keys()
    vim.keymap.set("n", "<C-a>", "<Plug>(lvim-cycle-increment)", { silent = true, desc = "Increment value" })
    vim.keymap.set("n", "<C-x>", "<Plug>(lvim-cycle-decrement)", { silent = true, desc = "Decrement value" })
    vim.keymap.set("x", "<C-a>", "<Plug>(lvim-cycle-increment)", { silent = true, desc = "Increment values" })
    vim.keymap.set("x", "<C-x>", "<Plug>(lvim-cycle-decrement)", { silent = true, desc = "Decrement values" })
    vim.keymap.set("x", "g<C-a>", "<Plug>(lvim-cycle-increment-sequential)", {
        silent = true,
        desc = "Sequentially increment values",
    })
    vim.keymap.set("x", "g<C-x>", "<Plug>(lvim-cycle-decrement-sequential)", {
        silent = true,
        desc = "Sequentially decrement values",
    })
end

--- Configure and start (idempotent — a second call re-merges config and re-validates,
--- but maps and the highlight bind are installed once).
---@param opts? LvimCycleConfig
---@return nil
function M.setup(opts)
    opts = opts or {}
    if type(opts.groups) == "table" then
        validate_groups(opts.groups)
    end
    if ok_utils then
        uu.merge(config, opts)
    else
        merge(config, opts)
    end
    if registered then
        return
    end
    registered = true
    set_highlights()
    set_plug_maps()
    if config.map_default_keys then
        set_default_keys()
    end
end

--- Increment the value under (or after) the cursor. Programmatic twin of the normal-mode
--- <Plug> map (no dot-repeat — map the <Plug> for that).
---@param count? integer  defaults to 1
---@return nil
function M.increment(count)
    engine.apply(count or 1, augends.for_buffer(0))
end

--- Decrement the value under (or after) the cursor.
---@param count? integer  defaults to 1
---@return nil
function M.decrement(count)
    engine.apply(-(count or 1), augends.for_buffer(0))
end

return M
