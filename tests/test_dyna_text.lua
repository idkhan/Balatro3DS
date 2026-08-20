--- DynaText's glyph loop.
---
--- Every enabled glyph is a CPU transform and a separate `print`, and the loop used to rebuild
--- the string's decomposition every frame: `text:sub(i, i)` per character, `font:getWidth`
--- per character, and the whole string measured again for alignment. None of it changes while
--- the string does not, and a DynaText string is a headline that changes a few times a round.
---
--- The other half is trig. Float and rotation are two amplitudes on one sine whenever their
--- speed and phase agree -- which is the default and every call site in this port -- so the
--- second `math.sin`, at 2.56 us a call on hardware, was computing an answer it already had.

local T = require("tests.testlib")
require("tests.bootstrap").load()

local DynaText = require("dyna_text")
local suite = T.suite()

--- A font that counts what is asked of it, so the caching can be observed rather than assumed.
local function counting_font(width_per_char)
    local font = { widths = 0 }
    function font:getWidth(text)
        font.widths = font.widths + 1
        return #tostring(text or "") * (width_per_char or 6)
    end
    function font:getHeight() return 12 end
    return font
end

--- Draw through a stubbed graphics module so the test can run the real loop without a device.
local function with_font(font, body)
    local g = love.graphics
    local saved = { getFont = g.getFont, print = g.print, printf = g.printf,
                    getColor = g.getColor, setColor = g.setColor }
    local prints = {}
    g.getFont = function() return font end
    g.print = function(glyph, px, py, r, sx, sy, ox, oy)
        prints[#prints + 1] = { glyph = glyph, x = px, y = py, r = r, sx = sx }
    end
    g.printf = function(text) prints[#prints + 1] = { glyph = text, wrapped = true } end
    g.getColor = function() return 1, 1, 1, 1 end
    g.setColor = function() end

    local ok, err = pcall(body, prints)

    for name, fn in pairs(saved) do g[name] = fn end
    if not ok then error(err, 0) end
    return prints
end

suite.test("a stable string is decomposed once, however many frames it is drawn for", function()
    local state = DynaText.new({ float_amount = 2 })
    local font = counting_font()

    with_font(font, function()
        DynaText.draw(state, "Game Over", 0, 0, 200, "left", 0)
        local after_first = font.widths
        T.assert_true(after_first > 0, "the first draw has to measure something")

        for frame = 1, 30 do
            DynaText.draw(state, "Game Over", 0, 0, 200, "left", frame / 60)
        end
        T.assert_eq(font.widths, after_first, "thirty more frames must measure nothing")
    end)
end)

suite.test("changing the value re-decomposes", function()
    local state = DynaText.new({ float_amount = 2 })
    local font = counting_font()

    with_font(font, function()
        DynaText.draw(state, "Ante 1", 0, 0, 200, "left", 0)
        local after_first = font.widths
        DynaText.draw(state, "Ante 2", 0, 0, 200, "left", 1 / 60)
        T.assert_true(font.widths > after_first, "a new string has to be measured")
    end)
end)

suite.test("changing the font re-decomposes", function()
    local state = DynaText.new({ float_amount = 2 })
    local small, large = counting_font(6), counting_font(10)

    local first = with_font(small, function()
        DynaText.draw(state, "Score", 0, 0, 200, "left", 0)
    end)
    local second = with_font(large, function()
        DynaText.draw(state, "Score", 0, 0, 200, "left", 1 / 60)
    end)

    T.assert_true(large.widths > 0, "the second font must be measured, not assumed")
    -- The glyphs advance further in the wider font, which is the observable consequence.
    T.assert_true(second[2].x - second[1].x > first[2].x - first[1].x,
        "the wider font should space the glyphs further apart")
end)

suite.test("the cached decomposition draws the same glyphs in the same places", function()
    local state = DynaText.new({ float_amount = 2, rotation_amount = 0.1 })
    local font = counting_font()

    with_font(font, function()
        local first = {}
        for _, p in ipairs(with_font(font, function()
            DynaText.draw(state, "Blind", 0, 0, 200, "center", 0.25)
        end)) do first[#first + 1] = p end

        -- Same time, same string: the cached pass must be indistinguishable from the cold one.
        local fresh = DynaText.new({ float_amount = 2, rotation_amount = 0.1 })
        local cold = with_font(counting_font(), function()
            DynaText.draw(fresh, "Blind", 0, 0, 200, "center", 0.25)
        end)

        T.assert_eq(#first, #cold, "same number of glyphs")
        for i = 1, #cold do
            T.assert_eq(first[i].glyph, cold[i].glyph, "glyph " .. i)
            T.assert_near(first[i].x, cold[i].x, 1e-9, "glyph " .. i .. " x")
            T.assert_near(first[i].y, cold[i].y, 1e-9, "glyph " .. i .. " y")
            T.assert_near(first[i].r, cold[i].r, 1e-9, "glyph " .. i .. " rotation")
        end
    end)
end)

--- The shared-wave path must produce exactly what two separate sines produced, or every
--- animated headline in the game shifts by a hair.
suite.test("sharing the sine gives the same float and rotation as two of them", function()
    local state = DynaText.new({
        float_amount = 3, rotation_amount = 0.12,
        float_speed = 2.666, float_phase = 1.7,
        rotation_speed = 2.666, rotation_phase = 1.7,
    })
    T.assert_true(state.shared_wave, "matching speed and phase should share the wave")

    for index = 1, 8 do
        for _, time in ipairs({ 0, 0.37, 1.9, 12.5 }) do
            local y, rotation = DynaText.letter_transform(state, index, time)
            local phase = index - 1
            local expected_y = 3 * math.sin(2.666 * time + phase * 1.7)
            local expected_r = 0.12 * math.sin(2.666 * time + phase * 1.7)
            T.assert_near(y, expected_y, 1e-12, "float at glyph " .. index)
            T.assert_near(rotation, expected_r, 1e-12, "rotation at glyph " .. index)
        end
    end
end)

suite.test("independent speeds keep two independent waves", function()
    local state = DynaText.new({
        float_amount = 3, rotation_amount = 0.12,
        float_speed = 2.666, float_phase = 1.7,
        rotation_speed = 1.1, rotation_phase = 0.4,
    })
    T.assert_false(state.shared_wave, "differing speed must not share the wave")

    local y, rotation = DynaText.letter_transform(state, 3, 0.8)
    T.assert_near(y, 3 * math.sin(2.666 * 0.8 + 2 * 1.7), 1e-12, "float keeps its own wave")
    T.assert_near(rotation, 0.12 * math.sin(1.1 * 0.8 + 2 * 0.4), 1e-12,
        "and rotation keeps its own")
end)

suite.test("an unanimated state still falls through to printf", function()
    local state = DynaText.new({})
    local font = counting_font()
    local prints = with_font(font, function()
        DynaText.draw(state, "Plain label", 4, 5, 100, "left", 0)
    end)
    T.assert_eq(#prints, 1, "one call, not one per glyph")
    T.assert_true(prints[1].wrapped, "and it should be the printf path")
end)

--- The reveal chirps on a schedule keyed off the string length, which now comes from the
--- cached decomposition rather than from `#text` at the call site.
suite.test("the reveal still chirps once per letter for a short string", function()
    local state = DynaText.new({ pop_on_change = true })
    local font = counting_font()
    local chirps = 0
    local previous = _G.Sfx
    _G.Sfx = { play = function() chirps = chirps + 1 end }

    with_font(font, function()
        DynaText.draw(state, "Win", 0, 0, 200, "left", 0)
        for frame = 1, 60 do
            DynaText.draw(state, "Win", 0, 0, 200, "left", frame / 60)
        end
    end)

    _G.Sfx = previous
    T.assert_eq(chirps, 3, "three letters, three chirps")
end)

return suite
