-- lvim-cycle.augends.hexcolor: hex colors "#rrggbb" / "#rrggbbaa". The channel under the
-- cursor is stepped by the delta and clamped to 0–255; with the cursor on the "#" (or
-- before the match), or with `all_channels = true`, EVERY channel is stepped — a quick
-- lighten/darken. Digit case follows the existing digits (any uppercase → uppercase
-- result). The 3-digit short form is not matched (a channel step cannot be represented
-- in one digit). Matching is at/after the cursor only.
--
---@module "lvim-cycle.augends.hexcolor"

local engine = require("lvim-cycle.engine")

local M = {}

--- Build the hexcolor augend.
---@param spec? { all_channels?: boolean }
---@return LvimCycleAugend
function M.new(spec)
    local all = (spec and spec.all_channels) == true

    --- Best hex-color candidate at/after the cursor.
    ---@param line string
    ---@param col integer
    ---@return LvimCycleMatch|nil
    local function find(line, col)
        local cands = {} ---@type LvimCycleMatch[]
        local init = 1
        while true do
            local s, e = line:find("#%x+", init)
            if not s or not e then
                break
            end
            local n = e - s -- digit count (the run is greedy, so an odd-length run is simply not a color)
            if e >= col and (n == 6 or n == 8) then
                cands[#cands + 1] = { s = s, e = e, text = line:sub(s, e) }
            end
            init = e + 1
        end
        return engine.pick(cands, col)
    end

    --- Step the channel under the cursor (or all), clamped to 0–255 each.
    ---@param text string
    ---@param delta integer
    ---@param cur integer
    ---@return string|nil
    ---@return integer|nil
    local function add(text, delta, cur)
        local digits = text:sub(2)
        local n = #digits / 2
        local from_ch, to_ch
        if all or cur <= 1 then
            from_ch, to_ch = 1, n
        else
            local ch = math.min(n, math.ceil((cur - 1) / 2))
            from_ch, to_ch = ch, ch
        end
        local fmt = digits:match("%u") and "%02X" or "%02x"
        local out = {}
        for i = 1, n do
            local v = tonumber(digits:sub(i * 2 - 1, i * 2), 16) or 0
            if i >= from_ch and i <= to_ch then
                v = math.max(0, math.min(255, v + delta))
            end
            out[i] = string.format(fmt, v)
        end
        local newtext = "#" .. table.concat(out)
        local newcur = (from_ch == to_ch) and (1 + to_ch * 2) or #newtext
        return newtext, newcur
    end

    return { find = find, add = add }
end

return M
