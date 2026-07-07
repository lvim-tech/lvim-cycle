-- lvim-cycle.highlights: the flash tint. LvimCycleFlash is a subtle yellow background —
-- blend(yellow, bg, 0.3) — laid over the changed span for ~120 ms, a confirmation of WHAT
-- changed. build() reads the LIVE palette on every call; init binds it via
-- lvim-utils.highlight.bind, so it re-derives on ColorScheme / palette sync (a plain
-- IncSearch link is the fallback when lvim-utils is absent — see init.lua).
--
---@module "lvim-cycle.highlights"

local c = require("lvim-utils.colors")
local hl = require("lvim-utils.highlight")

local M = {}

--- The flash highlight from the live palette.
---@return table<string, table>
function M.build()
    return {
        LvimCycleFlash = { bg = hl.blend(c.yellow, c.bg, 0.3) },
    }
end

return M
