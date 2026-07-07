-- lvim-cycle.augends: spec → augend resolution and the per-buffer group lookup.
-- A spec is: a built-in name string ("int", "float", "date", "semver", "hexcolor",
-- "markdown_header"); a table with `elements` (a constant word group); a table with
-- `kind` = a built-in name plus that augend's options (e.g. { kind = "date", patterns =
-- { "%d.%m.%Y" } }, { kind = "hexcolor", all_channels = true }); or a raw augend table
-- with its own find/add functions. Resolution is cached per spec VALUE (weak keys), so
-- the config tables resolve once and dropped group tables release their augends. Group
-- lookup order: vim.b.lvim_cycle_group (a groups key) → the buffer's filetype → default.
--
---@module "lvim-cycle.augends"

local config = require("lvim-cycle.config")
local constant = require("lvim-cycle.augends.constant")

local M = {}

-- Built-in augend module names (under lvim-cycle.augends.*). "constant" is addressable
-- via { kind = "constant", elements = … } — its bare-string form fails validation with a
-- precise message because it needs elements.
---@type table<string, boolean>
local BUILTIN = {
    int = true,
    float = true,
    date = true,
    semver = true,
    hexcolor = true,
    constant = true,
    markdown_header = true,
}

---@type table<string|table, LvimCycleAugend>  resolved specs
local cache = setmetatable({}, { __mode = "k" })

--- Resolve a spec into an augend (cached). On failure returns nil + a precise message —
--- setup() and health surface it with the group/index context prepended.
---@param spec LvimCycleSpec
---@return LvimCycleAugend|nil
---@return string|nil error
function M.resolve(spec)
    local hit = cache[spec]
    if hit then
        return hit
    end
    local aug, err
    if type(spec) == "string" then
        if BUILTIN[spec] then
            -- dynamic require by spec name (the one inline-require case)
            aug, err = require("lvim-cycle.augends." .. spec).new({})
        else
            err = ("unknown built-in augend %q"):format(spec)
        end
    elseif type(spec) == "table" then
        if type(spec.find) == "function" and type(spec.add) == "function" then
            aug = spec --[[@as LvimCycleAugend]]
        elseif spec.elements ~= nil then
            aug, err = constant.new(spec --[[@as LvimCycleConstantSpec]])
        elseif type(spec.kind) == "string" then
            if BUILTIN[spec.kind] then
                aug, err = require("lvim-cycle.augends." .. spec.kind).new(spec)
            else
                err = ("unknown augend kind %q"):format(spec.kind)
            end
        else
            err = "a table spec needs `elements`, a `kind`, or `find` + `add` functions"
        end
    else
        err = ("an augend spec must be a string or a table (got %s)"):format(type(spec))
    end
    if aug then
        cache[spec] = aug
    end
    return aug, err
end

--- The resolved augend list for `buf`, honouring vim.b.lvim_cycle_group and per-filetype
--- groups. Invalid specs are skipped here — setup() has already reported them.
---@param buf integer
---@return LvimCycleAugend[]
function M.for_buffer(buf)
    local groups = config.groups or {}
    local name = vim.b[buf].lvim_cycle_group
    local list
    if type(name) == "string" and type(groups[name]) == "table" then
        list = groups[name]
    else
        list = groups[vim.bo[buf].filetype] or groups.default or {}
    end
    local out = {} ---@type LvimCycleAugend[]
    for _, spec in ipairs(list) do
        local aug = M.resolve(spec)
        if aug then
            out[#out + 1] = aug
        end
    end
    return out
end

return M
