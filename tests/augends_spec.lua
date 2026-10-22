-- Incrementing what is under the cursor, which is the plugin's whole job.
--
-- Each augend is a pair of pure functions — `find(line, col)` and `add(text, delta, cur)` — so
-- what each one promises can be stated without a buffer. The promises with edges: zero padding
-- survives (007 → 008), hex letter case follows the digits already there, a radix literal inside
-- a longer token is not a number (`0x1080` in `1920x1080`), a constant cycles round and carries
-- the case it was written in, and a semver bump touches one component and zeroes the ones below.

local int = require("lvim-cycle.augends.int")
local constant = require("lvim-cycle.augends.constant")
local semver = require("lvim-cycle.augends.semver")

--- Apply an augend to a line as the engine would: find at `col`, then add.
---@param aug table
---@param line string
---@param col integer  1-based
---@param delta integer
---@return string|nil  the whole line after the change, or nil when nothing matched
local function bump(aug, line, col, delta)
    local m = aug.find(line, col)
    if not m then
        return nil
    end
    local text = aug.add(m.text, delta, col - m.s + 1)
    if not text then
        return nil
    end
    return line:sub(1, m.s - 1) .. text .. line:sub(m.e + 1)
end

describe("lvim-cycle.augends.int")

local ints = int.new({})

it("increments and decrements a decimal", function()
    eq("x = 2", bump(ints, "x = 1", 5, 1))
    eq("x = 0", bump(ints, "x = 1", 5, -1))
    eq("x = 10", bump(ints, "x = 9", 5, 1))
end)

it("keeps the zero padding", function()
    eq("008", bump(ints, "007", 1, 1))
    eq("010", bump(ints, "009", 1, 1), "the width is kept when the carry lands")
    eq("99", bump(ints, "100", 1, -1), "a number with no leading zero gains none on the way down")
end)

it("carries a negative decimal", function()
    eq("-1", bump(ints, "0", 1, -1))
    eq("0", bump(ints, "-1", 1, 1))
end)

it("follows the letter case of a hex literal", function()
    eq("0x10", bump(ints, "0x0f", 1, 1))
    eq("0x0F", bump(ints, "0x0E", 1, 1), "uppercase digits give an uppercase result")
end)

it("counts in binary and octal too", function()
    eq("0b11", bump(ints, "0b10", 1, 1))
    eq("0o10", bump(ints, "0o7", 1, 1))
end)

it("clamps a non-decimal base at zero, having no sign to carry", function()
    eq("0x0", bump(ints, "0x0", 1, -1))
    eq("0b0", bump(ints, "0b0", 1, -1))
end)

it("does not read a radix literal out of a longer token", function()
    -- `1920x1080` holds no number starting `0x`: the `0x1080` is part of the resolution.
    local got = bump(ints, "1920x1080", 1, 1)
    eq("1921x1080", got, "the leading 1920 is the number here, got " .. tostring(got))
end)

it("matches at or after the cursor, like native <C-a>", function()
    eq(nil, bump(ints, "42 end", 4), "nothing at or after column 4")
    eq("43 end", bump(ints, "42 end", 1, 1))
    eq("43 end", bump(ints, "42 end", 2, 1), "the cursor inside the number still counts")
end)

describe("lvim-cycle.augends.constant")

it("refuses a spec with fewer than two elements", function()
    local aug, err = constant.new({ elements = { "only" } })
    eq(nil, aug)
    truthy(err and err ~= "", "a refusal must say why")
    aug, err = constant.new({ elements = { "a", 2 } })
    eq(nil, aug)
    truthy(err and err:find("2", 1, true) ~= nil, "the reason should name the bad element: " .. tostring(err))
end)

it("cycles through its elements and wraps round", function()
    local aug = constant.new({ elements = { "true", "false" } })
    eq("x = false", bump(aug, "x = true", 5, 1))
    eq("x = true", bump(aug, "x = false", 5, 1), "the last wraps to the first")
    eq("x = false", bump(aug, "x = true", 5, -1), "and backwards too")
end)

it("carries the case the word was written in", function()
    local aug = constant.new({ elements = { "true", "false" } })
    eq("TRUE", bump(aug, "FALSE", 1, 1), "all caps stays all caps")
    eq("True", bump(aug, "False", 1, 1), "capitalised stays capitalised")
end)

it("cycles a list of more than two", function()
    local aug = constant.new({ elements = { "one", "two", "three" } })
    eq("two", bump(aug, "one", 1, 1))
    eq("three", bump(aug, "two", 1, 1))
    eq("one", bump(aug, "three", 1, 1))
end)

describe("lvim-cycle.augends.semver")

local ver = semver.new({})

it("bumps the component the cursor is on", function()
    -- In `"1.2.3"` the version occupies columns 2..6; column 7 is the closing quote, and a match
    -- must END at or after the cursor.
    eq('"1.2.4"', bump(ver, '"1.2.3"', 6, 1), "the patch")
    eq('"1.3.0"', bump(ver, '"1.2.3"', 4, 1), "the minor, zeroing the patch")
    eq('"2.0.0"', bump(ver, '"1.2.3"', 2, 1), "the major, zeroing both below it")
end)

it("decrements without going below zero", function()
    eq('"1.2.2"', bump(ver, '"1.2.3"', 6, -1))
    -- A zero patch has nothing to give, and the augend says so by answering nil rather than
    -- handing back the same text — which is how the engine knows not to rewrite the buffer or
    -- flash a change that did not happen.
    eq(nil, bump(ver, '"1.2.0"', 6, -1))
end)

it("will not read a version out of a longer number", function()
    eq(nil, bump(ver, "11.2.3.4", 1, 1), "a four-part version is not a semver")
end)

it("leaves something that is not a version alone", function()
    eq(nil, bump(ver, "not a version", 1, 1))
end)
