-- lvim-cycle.augends.int: integers in four bases — decimal (signed), hex 0x, binary 0b,
-- octal 0o. Zero-padded width is preserved (007 → 008, 0x0f → 0x10 but 0x0e → 0x0f), hex
-- letter case follows the existing digits (any uppercase digit → uppercase result), and
-- the non-decimal bases clamp at 0 — they have no sign to carry a negative value.
-- Decimal magnitudes are exact up to 2^53 (Lua doubles). All matching is at/after the
-- cursor only, mirroring native <C-a>.
--
---@module "lvim-cycle.augends.int"

local engine = require("lvim-cycle.engine")

local M = {}

-- Non-decimal literal shapes: Lua find-pattern + numeric base.
---@type { pat: string, base: integer }[]
local RADIX = {
    { pat = "0[xX]%x+", base = 16 },
    { pat = "0[bB][01]+", base = 2 },
    { pat = "0[oO][0-7]+", base = 8 },
}

--- Collect all matches of `pat` on `line` that end at/after `col` into `out`.
---@param line string
---@param pat string
---@param col integer
---@param out LvimCycleMatch[]
---@return nil
---@param guard_adjacent boolean?  reject a match that directly follows an alnum (a RADIX literal inside a
---                                longer token, e.g. `0x1080` starting at the `0` of `1920x1080`)
local function scan(line, pat, col, out, guard_adjacent)
    local init = 1
    while true do
        local s, e = line:find(pat, init)
        if not s or not e then
            break
        end
        local adjacent = guard_adjacent and s > 1 and line:sub(s - 1, s - 1):match("%w")
        if e >= col and not adjacent then
            out[#out + 1] = { s = s, e = e, text = line:sub(s, e) }
        end
        init = e + 1
    end
end

--- A non-negative integer as base-2 digits.
---@param n integer
---@return string
local function to_binary(n)
    if n == 0 then
        return "0"
    end
    local out = ""
    while n > 0 do
        out = tostring(n % 2) .. out
        n = math.floor(n / 2)
    end
    return out
end

--- Best integer candidate at/after the cursor. The bare decimal pattern also matches the
--- digits inside a radix literal (`0` and `1F` in `0x1F`), but the ranking prefers the
--- longer, earlier-starting radix span — no special casing needed.
---@param line string
---@param col integer
---@return LvimCycleMatch|nil
local function find(line, col)
    local cands = {} ---@type LvimCycleMatch[]
    for _, r in ipairs(RADIX) do
        scan(line, r.pat, col, cands, true) -- a radix literal must not start mid-token (1920x1080 → not 0x1080)
    end
    scan(line, "%-?%d+", col, cands) -- bare decimal stays unguarded; the ranking resolves runs (native <C-a>)
    return engine.pick(cands, col)
end

--- Add `delta`, preserving base, prefix case, zero-padded width and hex digit case.
---@param text string
---@param delta integer
---@return string|nil
---@return integer|nil
local function add(text, delta, _)
    local prefix, body = text:match("^(0[xX])(%x+)$")
    local base = 16
    if not prefix then
        prefix, body = text:match("^(0[bB])([01]+)$")
        base = 2
    end
    if not prefix then
        prefix, body = text:match("^(0[oO])([0-7]+)$")
        base = 8
    end
    if prefix and body then
        local value = tonumber(body, base) or 0
        local new = math.max(0, value + delta)
        local digits
        if base == 16 then
            digits = string.format(body:match("%u") and "%X" or "%x", new)
        elseif base == 8 then
            digits = string.format("%o", new)
        else
            digits = to_binary(new)
        end
        if #digits < #body then
            digits = string.rep("0", #body - #digits) .. digits
        end
        return prefix .. digits
    end
    local num = text:match("^%-?(%d+)$")
    if not num then
        return nil
    end
    local value = tonumber(text) or 0
    local new = value + delta
    local out = string.format("%d", math.abs(new))
    -- only explicit zero-padding ("007") is width-preserved; a plain number grows/shrinks freely
    if num:match("^0%d") and #out < #num then
        out = string.rep("0", #num - #out) .. out
    end
    if new < 0 then
        out = "-" .. out
    end
    return out
end

--- Factory (the int augend is stateless; the spec is accepted for interface uniformity).
---@return LvimCycleAugend
function M.new(_)
    return { find = find, add = add }
end

return M
