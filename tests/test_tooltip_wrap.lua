local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite("tooltip wrapping")

--- Records what `draw_tooltip_layout` prints, so a test can assert on the wrapped result without
--- a real renderer. The stub font is a fixed-advance one (`tests/love_stub.lua`), which makes the
--- expected break points arithmetic rather than guesswork.
local function capture(title, resolved_lines, font)
    bootstrap.load()
    local TooltipDraw = require("tooltip_draw")
    local printed = {}
    local real_print = love.graphics.print
    love.graphics.print = function(text, x, y, ...)
        printed[#printed + 1] = { text = tostring(text), x = x, y = y }
        return real_print(text, x, y, ...)
    end
    local ok, err = pcall(TooltipDraw.draw_tooltip_layout, font, title, resolved_lines, 10, 10, 72, 95)
    love.graphics.print = real_print
    T.assert_true(ok, tostring(err))
    return printed
end

--- Everything the layout printed except the header, grouped back into visual lines by y.
local function body_lines(printed, title)
    local rows, order = {}, {}
    for _, item in ipairs(printed) do
        if item.text ~= title then
            if not rows[item.y] then
                rows[item.y] = {}
                order[#order + 1] = item.y
            end
            table.insert(rows[item.y], item)
        end
    end
    table.sort(order)
    local lines = {}
    for _, y in ipairs(order) do
        local row = rows[y]
        table.sort(row, function(a, b) return a.x < b.x end)
        local parts = {}
        for _, item in ipairs(row) do parts[#parts + 1] = item.text end
        lines[#lines + 1] = table.concat(parts)
    end
    return lines
end

suite.test("a line that already fits is left alone", function()
    bootstrap.load()
    local font = love.graphics.newFont(11)
    local printed = capture("Joker", { { { text = "+20 Mult" } } }, font)
    T.assert_deep_eq(body_lines(printed, "Joker"), { "+20 Mult" })
end)

suite.test("a line wider than the screen breaks onto further lines", function()
    bootstrap.load()
    local font = love.graphics.newFont(11)
    -- The stub advances 5 px per character, so ~60 characters is roughly two screens wide.
    local text = "Add Foil Holographic or Polychrome effect to one selected playing card now"
    local printed = capture("Spectral", { { { text = text } } }, font)
    local lines = body_lines(printed, "Spectral")

    T.assert_true(#lines > 1, "expected a break, got " .. tostring(#lines) .. " line(s)")
    -- Nothing is dropped: today the box just grows until the screen clamp and the overflow is
    -- drawn off the edge, which is silent.
    T.assert_eq(table.concat(lines, " "), text)
    for _, line in ipairs(lines) do
        T.assert_true(font:getWidth(line) <= 320, "wrapped line still wider than the screen: " .. line)
    end
end)

suite.test("wrapping carries each word's colour rather than repainting the remainder", function()
    bootstrap.load()
    local font = love.graphics.newFont(11)
    local segments = {
        { text = "This Joker gains plus three chips for every single ", color_key = nil },
        { text = "discarded", color_key = "RED" },
        { text = " Hearts card that you play this round", color_key = nil },
    }
    local printed = capture("Joker", { segments }, font)

    local reds = 0
    for _, item in ipairs(printed) do
        if item.text:find("discarded", 1, true) then reds = reds + 1 end
    end
    -- The coloured run survives the split as exactly one piece; if wrapping split mid-run without
    -- carrying the colour it would either vanish or be duplicated.
    T.assert_eq(reds, 1, "the coloured run should appear once")

    local lines = body_lines(printed, "Joker")
    local joined = table.concat(lines, " ")
    T.assert_true(joined:find("discarded", 1, true) ~= nil, joined)
end)

suite.test("a rarity badge is never broken", function()
    bootstrap.load()
    local font = love.graphics.newFont(11)
    local long = "Legendary Rarity Badge That Is Absurdly Long And Would Otherwise Wrap"
    -- A badge is a fixed pill drawn around its label, so breaking it would draw a broken pill.
    local printed = capture("Joker", { { { text = long, rarity_badge = true, rarity_index = 4 } } }, font)
    local found = false
    for _, item in ipairs(printed) do
        if item.text == long then found = true end
    end
    T.assert_true(found, "the badge label should be printed whole")
end)

suite.test("wrapping is inert at the shipped ladder", function()
    bootstrap.load()
    local Fonts = require("fonts")
    local font = love.graphics.newFont(Fonts.PROFILES.shared.SMALL)
    -- Catalog copy is pre-broken for this size, so the A/B against the crisp-font ladder is not
    -- muddied by the wrapper changing the baseline out from under it.
    local text = "Retrigger all card held in hand abilities"
    local printed = capture("Joker", { { { text = text } } }, font)
    T.assert_deep_eq(body_lines(printed, "Joker"), { text })
end)

suite.test("an empty body does not raise", function()
    bootstrap.load()
    local font = love.graphics.newFont(11)
    T.assert_no_error(function() capture("Joker", {}, font) end)
    T.assert_no_error(function() capture("Joker", { { { text = "" } } }, font) end)
end)

suite.test("a line's segments are built once and reused", function()
    bootstrap.load()
    local TooltipDraw = require("tooltip_draw")
    local text = "+4 Mult for each Joker card"
    local first = TooltipDraw.build_segments_from_text(text)
    local second = TooltipDraw.build_segments_from_text(text)
    T.assert_true(rawequal(first, second), "the same text should not be re-lexed")

    local other = TooltipDraw.build_segments_from_text("Retrigger all played cards")
    T.assert_true(not rawequal(first, other), "different text gets its own segments")
end)

suite.test("bare Mult and Chips are coloured", function()
    bootstrap.load()
    local TooltipDraw = require("tooltip_draw")
    -- These two passes used to search for the literal string "[Mm]ult", which appears in no
    -- description, so a bare "Mult" with no number in front of it was left uncoloured.
    local function colour_of(text, word)
        for _, seg in ipairs(TooltipDraw.build_segments_from_text(text)) do
            if tostring(seg.text):lower():find(word, 1, true) then return seg.color_key end
        end
        return nil
    end
    T.assert_eq(colour_of("Doubles Mult", "mult"), "MULT")
    T.assert_eq(colour_of("Adds Chips instead", "chips"), "CHIPS")
end)

return suite
