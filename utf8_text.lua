--- UTF-8 aware text helpers, for the places that take strings apart.
---
--- Lua strings are bytes. Taking one apart a byte at a time (`text:sub(i, i)`) is fine while every
--- character is ASCII and splits a Chinese character into three meaningless bytes the moment one
--- is not. And Chinese has no spaces, so code that wraps on spaces sees a whole sentence as one
--- unbreakable word. These helpers give both a character view and the break opportunities a line
--- wrapper needs.
---
--- Plain Lua 5.1 (LovePotion's interpreter): no `utf8` library and no `\x` escapes, so the byte
--- ranges below are decimal.

local Utf8 = {}

--- One UTF-8 character: an ASCII byte or a lead byte, then its continuation bytes. A stray
--- continuation byte matches on its own, so malformed input still splits into pieces.
local CHAR = "[%z\1-\127\194-\244][\128-\191]*"
local ANY = "[\128-\191]"

--- @return string[] the string's characters
function Utf8.chars(text)
    local out = {}
    text = tostring(text or "")
    local pos, n = 1, #text
    while pos <= n do
        local s, e = text:find(CHAR, pos)
        if s ~= pos then s, e = text:find(ANY, pos) end   -- a stray continuation byte
        if not s then break end
        out[#out + 1] = text:sub(s, e)
        pos = e + 1
    end
    return out
end

--- @return number characters in the string, not bytes
function Utf8.len(text)
    return #Utf8.chars(text)
end

--- The code point of one character.
function Utf8.codepoint(ch)
    local b1, b2, b3, b4 = ch:byte(1, 4)
    if not b1 then return 0 end
    if b1 < 128 then return b1 end
    if b1 < 224 then return (b1 - 192) * 64 + ((b2 or 128) - 128) end
    if b1 < 240 then return ((b1 - 224) * 64 + ((b2 or 128) - 128)) * 64 + ((b3 or 128) - 128) end
    return (((b1 - 240) * 64 + ((b2 or 128) - 128)) * 64 + ((b3 or 128) - 128)) * 64 + ((b4 or 128) - 128)
end

--- Scripts written without spaces, where a line may break between any two characters: CJK
--- ideographs and their punctuation, kana, hangul and full-width forms.
function Utf8.is_cjk(cp)
    return (cp >= 0x2E80 and cp <= 0x9FFF)      -- CJK radicals .. unified ideographs, incl. kana
        or (cp >= 0xAC00 and cp <= 0xD7AF)      -- hangul syllables
        or (cp >= 0xF900 and cp <= 0xFAFF)      -- compatibility ideographs
        or (cp >= 0xFE30 and cp <= 0xFE4F)      -- compatibility forms
        or (cp >= 0xFF00 and cp <= 0xFFEF)      -- full-width forms
        or (cp >= 0x20000 and cp <= 0x2FFFF)    -- supplementary ideographs
end

--- Punctuation that must not begin a line, and punctuation that must not end one (the usual
--- kinsoku rules, kept to the marks the translations actually use).
local NO_LINE_START = {}
for _, p in ipairs({ "，", "。", "、", "；", "：", "！", "？", "）", "》", "」", "』", "】", "〉",
    "”", "’", "…", ",", ".", ";", ":", "!", "?", ")", "%" }) do
    NO_LINE_START[p] = true
end
local NO_LINE_END = {}
for _, p in ipairs({ "（", "《", "「", "『", "【", "〈", "“", "‘", "(", "$" }) do
    NO_LINE_END[p] = true
end

--- Split one run of non-space text into the pieces a line may break between. Latin text stays
--- whole (it breaks at the spaces around it, as before); each CJK character is its own piece,
--- with closing punctuation held to the character before it and opening punctuation to the one
--- after, so a line never starts with "，" or ends with "（".
--- @param chunk string text containing no spaces
--- @return string[] pieces whose concatenation is `chunk`
function Utf8.break_pieces(chunk)
    local pieces = {}
    local latin = nil        -- the Latin run being built
    local hold = ""          -- opening punctuation waiting for the next character
    local function push(piece)
        pieces[#pieces + 1] = hold .. piece
        hold = ""
    end
    for _, ch in ipairs(Utf8.chars(chunk)) do
        if NO_LINE_START[ch] and (latin or #pieces > 0) then
            -- Closing punctuation stays with whatever came before it.
            if latin then latin = latin .. ch else pieces[#pieces] = pieces[#pieces] .. ch end
        elseif NO_LINE_END[ch] then
            if latin then push(latin); latin = nil end
            hold = hold .. ch
        elseif Utf8.is_cjk(Utf8.codepoint(ch)) then
            if latin then push(latin); latin = nil end
            push(ch)
        else
            latin = (latin or "") .. ch
        end
    end
    if latin then push(latin) end
    if hold ~= "" then
        if #pieces > 0 then pieces[#pieces] = pieces[#pieces] .. hold else pieces[1] = hold end
    end
    return pieces
end

--- Wrap plain text at CJK break opportunities, keeping punctuation with its neighbour.
function Utf8.wrap_lines(font, text, limit)
    local lines = {}
    for paragraph in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
        local line = ""
        for chunk, gap in paragraph:gmatch("(%S+)(%s*)") do
            for _, piece in ipairs(Utf8.break_pieces(chunk)) do
                if line ~= "" and font:getWidth(line .. piece) > limit then
                    lines[#lines + 1] = line:gsub("%s+$", "")
                    line = ""
                end
                line = line .. piece
            end
            line = line .. gap
        end
        lines[#lines + 1] = line:gsub("%s+$", "")
    end
    return lines
end

return Utf8
