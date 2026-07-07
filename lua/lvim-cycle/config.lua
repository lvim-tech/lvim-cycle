-- lvim-cycle.config: the LIVE configuration for lvim-cycle. setup() merges the user's opts
-- into THIS table in place (via lvim-utils.utils.merge, or an array-replacing fallback when
-- lvim-utils is absent); every reader does `require("lvim-cycle.config")` and sees the
-- effective values. Group lists are ARRAYS, so a user-supplied group replaces the default
-- wholesale — no stale tail entries from an index-merge.
--
---@module "lvim-cycle.config"

---@alias LvimCycleSpec string|LvimCycleConstantSpec|LvimCycleAugend|{ kind: string }
--- An augend spec inside a group list is one of:
---   • a built-in name: "int" | "float" | "date" | "semver" | "hexcolor" | "markdown_header"
---   • a constant word group: { elements = { "true", "false" }, cyclic?, word?, preserve_case? }
---   • a built-in with options: { kind = "date", patterns = { "%d.%m.%Y" } },
---     { kind = "hexcolor", all_channels = true }, { kind = "constant", elements = ... }
---   • a raw custom augend: { find = fun(line, col), add = fun(text, delta, cur) }

---@class LvimCycleConfig
---@field map_default_keys boolean               map <C-a>/<C-x> (normal + visual) and g<C-a>/g<C-x> (visual sequential)
---@field flash boolean                          briefly tint the changed span (LvimCycleFlash) as confirmation
---@field groups table<string, LvimCycleSpec[]>  augend groups: "default" + per-FILETYPE lists (key = filetype) + named lists selectable via vim.b.lvim_cycle_group

---@type LvimCycleConfig
return {
    map_default_keys = true,
    flash = true,
    -- Group resolution per buffer: vim.b.lvim_cycle_group (a key of this table) → the
    -- buffer's filetype → "default". Order inside a list matters: when two augends
    -- propose equally-placed matches, the EARLIER one wins.
    --   groups = {
    --       markdown = { "markdown_header", "int", "date" },
    --       css = { "hexcolor", "int", "float" },
    --   },
    groups = {
        default = {
            "int",
            "float",
            "date",
            "semver",
            "hexcolor",
            { elements = { "true", "false" } },
            { elements = { "on", "off" } },
            { elements = { "&&", "||" }, word = false },
        },
    },
}
