-- lvim-cycle: :checkhealth lvim-cycle.
-- Diagnoses what makes a <C-a> replacement misbehave invisibly: an invalid group spec
-- (skipped silently at runtime once setup() is past — reported precisely here, per
-- groups.<name>[<index>]), default keys that did not land because another plugin mapped
-- <C-a>/<C-x> over them later, and the lvim-utils dependency state (palette-derived flash
-- + array-replace merge, both with fallbacks). Read-only reporting — never mutates
-- config or state.
--
---@module "lvim-cycle.health"

local config = require("lvim-cycle.config")
local augends = require("lvim-cycle.augends")

local M = {}

--- Validate every configured group spec; per-spec errors, ok with augend counts when clean.
---@param health table  the vim.health reporter
---@return nil
local function check_groups(health)
    local groups = config.groups
    if type(groups) ~= "table" or next(groups) == nil then
        health.error("groups must be a non-empty table of augend-spec lists")
        return
    end
    if type(groups.default) ~= "table" then
        health.warn('no "default" group — buffers without a matching filetype group have no augends')
    end
    local problems = 0
    local summary = {}
    for name, list in pairs(groups) do
        if type(list) ~= "table" then
            health.error(("groups.%s: must be a list of augend specs (got %s)"):format(name, type(list)))
            problems = problems + 1
        else
            local n = 0
            for i, spec in ipairs(list) do
                local aug, err = augends.resolve(spec)
                if aug then
                    n = n + 1
                else
                    health.error(("groups.%s[%d]: %s"):format(name, i, err))
                    problems = problems + 1
                end
            end
            summary[#summary + 1] = ("%s (%d)"):format(name, n)
        end
    end
    if problems == 0 then
        table.sort(summary)
        health.ok("groups valid: " .. table.concat(summary, ", "))
    end
end

--- Verify a default key still points at our <Plug> map (another plugin may have mapped over it).
---@param health table  the vim.health reporter
---@param mode string
---@param lhs string
---@return nil
local function check_key(health, mode, lhs)
    local rhs = vim.fn.maparg(lhs, mode)
    if rhs:find("lvim-cycle", 1, true) then
        health.ok(("%s-mode %s → %s"):format(mode, lhs, rhs))
    elseif rhs == "" then
        health.warn(("%s-mode %s is unmapped — was setup() called with map_default_keys?"):format(mode, lhs))
    else
        health.warn(("%s-mode %s is mapped elsewhere: %s"):format(mode, lhs, rhs))
    end
end

--- Run the health report.
---@return nil
function M.check()
    local health = vim.health
    health.start("lvim-cycle")

    if vim.fn.has("nvim-0.10") == 1 then
        health.ok("Neovim >= 0.10")
    else
        health.error("Neovim >= 0.10 is required (vim.uv, vim.islist, extmark end_col)")
    end

    local ok_utils = pcall(require, "lvim-utils.utils")
    local ok_hl, hl = pcall(require, "lvim-utils.highlight")
    if ok_utils and ok_hl and type(hl.bind) == "function" then
        health.ok("lvim-utils found (palette flash + array-replace merge)")
    else
        health.warn("lvim-utils not found — flash links to IncSearch, merge falls back to the bundled one")
    end

    check_groups(health)

    if config.map_default_keys then
        check_key(health, "n", "<C-a>")
        check_key(health, "n", "<C-x>")
        check_key(health, "x", "<C-a>")
        check_key(health, "x", "g<C-a>")
    else
        health.info("map_default_keys = false — map the <Plug>(lvim-cycle-…) maps yourself")
    end

    if config.flash then
        if vim.fn.hlexists("LvimCycleFlash") == 1 then
            health.ok("flash on (LvimCycleFlash defined)")
        else
            health.warn("flash on but LvimCycleFlash is undefined — was setup() called?")
        end
    else
        health.info("flash off")
    end

    -- Per-buffer group override: report it when checkhealth runs from such a buffer —
    -- otherwise "wrong augends here" looks like a bug.
    local override = vim.b.lvim_cycle_group
    if override ~= nil then
        if type(override) == "string" and type((config.groups or {})[override]) == "table" then
            health.info(("current buffer overrides the group: vim.b.lvim_cycle_group = %q"):format(override))
        else
            health.warn(
                ("vim.b.lvim_cycle_group = %s does not name a configured group — falling back to filetype/default"):format(
                    vim.inspect(override)
                )
            )
        end
    end
end

return M
