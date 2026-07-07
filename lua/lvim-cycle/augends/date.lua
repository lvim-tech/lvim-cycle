-- lvim-cycle.augends.date: dates and times as data-driven strftime-like patterns. Each
-- pattern ("%Y-%m-%d", "%H:%M", …) compiles to a FIXED-WIDTH Lua pattern with static
-- field offsets (every supported token has a fixed digit width), so the field under the
-- cursor is found by plain column arithmetic. The delta is added to THAT field and the
-- result is normalised via an os.time → os.date("*t") round-trip — month-end, leap years
-- and DST come out right because `isdst` is deliberately left unset (mktime auto-detects).
-- Missing fields default to 2000-01-01 00:00:00; a time-only pattern therefore wraps
-- within the day (23:59 + 1min → 00:00) since only its own tokens are re-rendered.
-- Candidates are validated by field range (month 1–12, hour 0–23, …) and must not touch
-- adjacent digits, so "12024-01-15" never half-matches.
--
---@module "lvim-cycle.augends.date"

local engine = require("lvim-cycle.engine")

local M = {}

---@class LvimCycleDateToken
---@field width integer  digit count in the rendered text
---@field pat string     Lua pattern for the digits
---@field field string   os.date("*t") field name
---@field fmt string     string.format spec for re-rendering
---@field min integer    smallest valid value
---@field max integer    largest valid value

-- Supported pattern tokens. All fixed-width, which is what makes cursor→field mapping
-- and re-rendering purely positional.
---@type table<string, LvimCycleDateToken>
local TOKENS = {
    Y = { width = 4, pat = "%d%d%d%d", field = "year", fmt = "%04d", min = 0, max = 9999 },
    m = { width = 2, pat = "%d%d", field = "month", fmt = "%02d", min = 1, max = 12 },
    d = { width = 2, pat = "%d%d", field = "day", fmt = "%02d", min = 1, max = 31 },
    H = { width = 2, pat = "%d%d", field = "hour", fmt = "%02d", min = 0, max = 23 },
    M = { width = 2, pat = "%d%d", field = "min", fmt = "%02d", min = 0, max = 59 },
    S = { width = 2, pat = "%d%d", field = "sec", fmt = "%02d", min = 0, max = 59 },
}

-- Default formats, most specific first (the ranking prefers the longer datetime span
-- over the bare %H:%M it contains anyway).
---@type string[]
local DEFAULT_PATTERNS = { "%Y-%m-%dT%H:%M", "%Y-%m-%d", "%d/%m/%Y", "%H:%M" }

---@class LvimCycleDateCompiled
---@field segs ({ literal: string }|{ token: string })[]  the format split into literal chars and tokens
---@field pat string                                      the whole format as a Lua pattern
---@field fields { key: string, offset: integer, width: integer }[]  token spans, in order
---@field width integer                                   total rendered width

--- Compile a format string into pattern + static field offsets.
---@param fmt string
---@return LvimCycleDateCompiled|nil
---@return string|nil error
local function compile(fmt)
    local segs, pat, fields, off = {}, "", {}, 1
    local i = 1
    while i <= #fmt do
        local c = fmt:sub(i, i)
        if c == "%" then
            local t = fmt:sub(i + 1, i + 1)
            local tok = TOKENS[t]
            if not tok then
                return nil, ("unsupported date token %%%s in %q (supported: %%Y %%m %%d %%H %%M %%S)"):format(t, fmt)
            end
            segs[#segs + 1] = { token = t }
            fields[#fields + 1] = { key = t, offset = off, width = tok.width }
            pat = pat .. tok.pat
            off = off + tok.width
            i = i + 2
        else
            segs[#segs + 1] = { literal = c }
            pat = pat .. c:gsub("(%W)", "%%%1")
            off = off + 1
            i = i + 1
        end
    end
    if #fields == 0 then
        return nil, ("date pattern %q has no tokens"):format(fmt)
    end
    return { segs = segs, pat = pat, fields = fields, width = off - 1 }
end

--- Parse the field values out of a text known to match `c.pat`; nil when any is out of range.
---@param c LvimCycleDateCompiled
---@param text string
---@return integer[]|nil
local function parse(c, text)
    local vals = {}
    for i, f in ipairs(c.fields) do
        local tok = TOKENS[f.key]
        local v = tonumber(text:sub(f.offset, f.offset + f.width - 1))
        if not v or v < tok.min or v > tok.max then
            return nil
        end
        vals[i] = v
    end
    return vals
end

--- Build the date augend for a list of format strings.
---@param spec? { patterns?: string[] }
---@return LvimCycleAugend|nil
---@return string|nil error
function M.new(spec)
    local patterns = (spec and spec.patterns) or DEFAULT_PATTERNS
    if type(patterns) ~= "table" or #patterns == 0 then
        return nil, "`patterns` must be a non-empty list of date format strings"
    end
    local compiled = {} ---@type LvimCycleDateCompiled[]
    for i, fmt in ipairs(patterns) do
        if type(fmt) ~= "string" then
            return nil, ("`patterns[%d]` must be a string"):format(i)
        end
        local c, err = compile(fmt)
        if not c then
            return nil, ("`patterns[%d]`: %s"):format(i, err)
        end
        compiled[#compiled + 1] = c
    end

    --- Best valid date/time candidate at/after the cursor, across all formats.
    ---@param line string
    ---@param col integer
    ---@return LvimCycleMatch|nil
    local function find(line, col)
        local cands = {} ---@type LvimCycleMatch[]
        for _, c in ipairs(compiled) do
            local init = 1
            while true do
                local s, e = line:find(c.pat, init)
                if not s or not e then
                    break
                end
                -- must not extend adjacent digit runs ("12024-…" is not a year)
                local before = s > 1 and line:sub(s - 1, s - 1) or ""
                local after = line:sub(e + 1, e + 1)
                local text = line:sub(s, e)
                if e >= col and not before:match("%d") and not after:match("%d") and parse(c, text) then
                    cands[#cands + 1] = { s = s, e = e, text = text }
                end
                init = s + 1
            end
        end
        return engine.pick(cands, col)
    end

    --- Add `delta` to the field under the cursor (day — or the last field — when the
    --- match sits after the cursor), then normalise and re-render. Cursor lands on the
    --- end of the changed field.
    ---@param text string
    ---@param delta integer
    ---@param cur integer
    ---@return string|nil
    ---@return integer|nil
    local function add(text, delta, cur)
        for _, c in ipairs(compiled) do
            if #text == c.width and text:match("^" .. c.pat .. "$") then
                local vals = parse(c, text)
                if vals then
                    -- target field: the one containing the cursor (a separator belongs
                    -- to the field on its left); day / the last field as the default
                    local ti
                    if cur >= 1 then
                        for i, f in ipairs(c.fields) do
                            if f.offset <= cur then
                                ti = i
                            end
                        end
                        ti = ti or 1
                    else
                        for i, f in ipairs(c.fields) do
                            if f.key == "d" then
                                ti = i
                            end
                        end
                        ti = ti or #c.fields
                    end
                    local tt = { year = 2000, month = 1, day = 1, hour = 0, min = 0, sec = 0 }
                    for i, f in ipairs(c.fields) do
                        tt[TOKENS[f.key].field] = vals[i]
                    end
                    local fname = TOKENS[c.fields[ti].key].field
                    tt[fname] = tt[fname] + delta
                    local t = os.time(tt)
                    if not t then
                        return nil
                    end
                    local nt = os.date("*t", t) --[[@as osdate]]
                    local pieces, pos, cursor_end, ord = {}, 0, nil, 0
                    for _, seg in ipairs(c.segs) do
                        local piece
                        if seg.literal then
                            piece = seg.literal
                        else
                            ord = ord + 1
                            local tok = TOKENS[seg.token]
                            piece = string.format(tok.fmt, nt[tok.field])
                        end
                        pos = pos + #piece
                        pieces[#pieces + 1] = piece
                        if seg.token and ord == ti and not cursor_end then
                            cursor_end = pos
                        end
                    end
                    return table.concat(pieces), cursor_end
                end
            end
        end
        return nil
    end

    return { find = find, add = add }
end

return M
