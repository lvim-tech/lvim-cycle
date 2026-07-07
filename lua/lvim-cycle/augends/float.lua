-- lvim-cycle.augends.float: fixed-point decimals ("3.14", "-0.5"). The delta is added to
-- the VALUE (an integer step: 3.14 → 4.14) and the result is re-formatted with the same
-- number of fraction digits, so the written precision is preserved exactly. Scientific
-- notation is out of scope. Matching is at/after the cursor only; when the semver augend
-- is enabled it outranks the "1.2" this pattern sees inside "1.2.3" (longer span).
--
---@module "lvim-cycle.augends.float"

local engine = require("lvim-cycle.engine")

local M = {}

--- Best float candidate at/after the cursor.
---@param line string
---@param col integer
---@return LvimCycleMatch|nil
local function find(line, col)
    local cands = {} ---@type LvimCycleMatch[]
    local init = 1
    while true do
        local s, e = line:find("%-?%d+%.%d+", init)
        if not s or not e then
            break
        end
        if e >= col then
            cands[#cands + 1] = { s = s, e = e, text = line:sub(s, e) }
        end
        init = e + 1
    end
    return engine.pick(cands, col)
end

--- Add `delta` to the value, keeping the fraction-digit count.
---@param text string
---@param delta integer
---@return string|nil
---@return integer|nil
local function add(text, delta, _)
    local frac = text:match("%.(%d+)$")
    local value = tonumber(text)
    if not frac or not value then
        return nil
    end
    return string.format("%." .. #frac .. "f", value + delta)
end

--- Factory (the float augend is stateless; the spec is accepted for interface uniformity).
---@return LvimCycleAugend
function M.new(_)
    return { find = find, add = add }
end

return M
