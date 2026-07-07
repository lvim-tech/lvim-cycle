-- lvim-cycle.augends.constant: configurable word groups ("true" ⇄ "false", "&&" ⇄ "||",
-- weekday names, …). Cycling steps `delta` positions through the elements list, wrapping
-- when `cyclic` (default) or clamping at the ends otherwise. `word` (default true)
-- requires word boundaries — set it to false for operator-like elements ("&&"), whose
-- neighbours ARE word characters. `preserve_case` (default true) matches
-- case-insensitively and transfers the original casing onto the result (TRUE → FALSE,
-- True → False); elements that differ only by case need `preserve_case = false`.
-- Matching is at/after the cursor only.
--
---@module "lvim-cycle.augends.constant"

local engine = require("lvim-cycle.engine")

local M = {}

---@class LvimCycleConstantSpec
---@field elements string[]       the cycle, in order (at least 2 entries)
---@field cyclic? boolean         wrap around the ends (default true)
---@field word? boolean           match only on word boundaries (default true)
---@field preserve_case? boolean  case-insensitive matching, original casing transferred (default true)

--- Transfer the ORIGINAL match's casing onto the replacement: ALL-UPPER stays upper,
--- Title-case stays Title; anything else uses the element as defined.
---@param from string
---@param to string
---@return string
local function transfer_case(from, to)
    if from:match("%a") and from == from:upper() and from ~= from:lower() then
        return to:upper()
    end
    if from:sub(1, 1):match("%u") then
        return to:sub(1, 1):upper() .. to:sub(2)
    end
    return to
end

--- Build a constant augend from its spec (validated here — setup() surfaces the message).
---@param spec LvimCycleConstantSpec
---@return LvimCycleAugend|nil
---@return string|nil error
function M.new(spec)
    local elements = spec and spec.elements
    if type(elements) ~= "table" or #elements < 2 then
        return nil, "`elements` must be a list of at least 2 strings"
    end
    for i, el in ipairs(elements) do
        if type(el) ~= "string" or el == "" then
            return nil, ("`elements[%d]` must be a non-empty string"):format(i)
        end
    end
    local cyclic = spec.cyclic ~= false
    local word = spec.word ~= false
    local preserve_case = spec.preserve_case ~= false

    --- Best element occurrence at/after the cursor.
    ---@param line string
    ---@param col integer
    ---@return LvimCycleMatch|nil
    local function find(line, col)
        local hay = preserve_case and line:lower() or line
        local cands = {} ---@type LvimCycleMatch[]
        for _, el in ipairs(elements) do
            local needle = preserve_case and el:lower() or el
            local init = 1
            while true do
                local s, e = hay:find(needle, init, true)
                if not s or not e then
                    break
                end
                local ok = e >= col
                if ok and word then
                    local before = s > 1 and hay:sub(s - 1, s - 1) or ""
                    local after = hay:sub(e + 1, e + 1)
                    if before:match("[%w_]") or after:match("[%w_]") then
                        ok = false
                    end
                end
                if ok then
                    cands[#cands + 1] = { s = s, e = e, text = line:sub(s, e) }
                end
                init = s + 1
            end
        end
        return engine.pick(cands, col)
    end

    --- Step `delta` positions through the cycle.
    ---@param text string
    ---@param delta integer
    ---@return string|nil
    ---@return integer|nil
    local function add(text, delta, _)
        local key = preserve_case and text:lower() or text
        local idx
        for i, el in ipairs(elements) do
            if (preserve_case and el:lower() or el) == key then
                idx = i
                break
            end
        end
        if not idx then
            return nil
        end
        local n = #elements
        local ni
        if cyclic then
            ni = ((idx - 1 + delta) % n) + 1
        else
            ni = math.min(n, math.max(1, idx + delta))
        end
        local out = elements[ni]
        if preserve_case then
            out = transfer_case(text, out)
        end
        return out
    end

    return { find = find, add = add }
end

return M
