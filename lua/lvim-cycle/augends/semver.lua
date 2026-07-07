-- lvim-cycle.augends.semver: semantic versions ("1.2.3"). The segment under the cursor is
-- bumped and every LOWER segment is zeroed (major bump → x+1.0.0), matching how versions
-- are actually incremented; with the cursor before the match the PATCH segment is bumped
-- (the common case). Segments clamp at 0 on decrement — and when the clamp means no
-- change, nothing is touched (no surprise zeroing of the lower segments). A dotted run
-- adjacent to more digits/dots ("10.20.30.40") is rejected, so IPs are left to the int
-- augend. Matching is at/after the cursor only.
--
---@module "lvim-cycle.augends.semver"

local engine = require("lvim-cycle.engine")

local M = {}

--- Best semver candidate at/after the cursor.
---@param line string
---@param col integer
---@return LvimCycleMatch|nil
local function find(line, col)
    local cands = {} ---@type LvimCycleMatch[]
    local init = 1
    while true do
        local s, e = line:find("%d+%.%d+%.%d+", init)
        if not s or not e then
            break
        end
        local before = s > 1 and line:sub(s - 1, s - 1) or ""
        local after = line:sub(e + 1, e + 1)
        if e >= col and not before:match("[%d%.]") and not after:match("[%d%.]") then
            cands[#cands + 1] = { s = s, e = e, text = line:sub(s, e) }
        end
        init = s + 1
    end
    return engine.pick(cands, col)
end

--- Bump the segment under the cursor, zeroing the lower ones. Cursor lands on the end of
--- the changed segment (in the NEW text — segment widths may change).
---@param text string
---@param delta integer
---@param cur integer
---@return string|nil
---@return integer|nil
local function add(text, delta, cur)
    local maj, min, pat = text:match("^(%d+)%.(%d+)%.(%d+)$")
    if not maj then
        return nil
    end
    local v = { tonumber(maj) or 0, tonumber(min) or 0, tonumber(pat) or 0 }
    local min_s = #maj + 2
    local pat_s = min_s + #min + 1
    local f
    if cur < 1 or cur >= pat_s then
        f = 3
    elseif cur < min_s then
        f = 1
    else
        f = 2
    end
    local nv = math.max(0, v[f] + delta)
    if nv == v[f] then
        return nil
    end
    v[f] = nv
    for i = f + 1, 3 do
        v[i] = 0
    end
    local parts = { tostring(v[1]), tostring(v[2]), tostring(v[3]) }
    local endpos = 0
    for i = 1, f do
        endpos = endpos + #parts[i] + (i > 1 and 1 or 0)
    end
    return table.concat(parts, "."), endpos
end

--- Factory (the semver augend is stateless; the spec is accepted for interface uniformity).
---@return LvimCycleAugend
function M.new(_)
    return { find = find, add = add }
end

return M
