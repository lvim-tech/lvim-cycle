-- lvim-cycle.augends.markdown_header: the ATX heading level ("#" ⇄ "##" … "######").
-- Unlike the numeric augends, find() returns the hash run for ANY cursor position on the
-- line — the hashes sit at column 1 while the cursor is usually inside the heading text.
-- That match ranks in the engine's LAST tier (before-cursor), so a number in the heading
-- still wins when the cursor is at/before it. The level clamps at 1 and 6.
--
---@module "lvim-cycle.augends.markdown_header"

local M = {}

--- The line's hash run when it is an ATX heading (1–6 hashes followed by a space or EOL).
---@param line string
---@return LvimCycleMatch|nil
local function find(line, _)
    local hashes = line:match("^#+")
    if not hashes or #hashes > 6 then
        return nil
    end
    local nextc = line:sub(#hashes + 1, #hashes + 1)
    if nextc ~= "" and nextc ~= " " then
        return nil
    end
    return { s = 1, e = #hashes, text = hashes }
end

--- Change the heading level by `delta`, clamped to 1–6.
---@param text string
---@param delta integer
---@return string|nil
---@return integer|nil
local function add(text, delta, _)
    local n = math.min(6, math.max(1, #text + delta))
    if n == #text then
        return nil
    end
    return string.rep("#", n), n
end

--- Factory (the markdown_header augend is stateless; the spec is accepted for interface uniformity).
---@return LvimCycleAugend
function M.new(_)
    return { find = find, add = add }
end

return M
