--- The cached-text module.
---
--- What matters is not that it draws -- it is that it draws the SAME thing a plain printf
--- would have, and that it actually reuses its batches. A cache that rebuilds every frame is
--- slower than no cache, and one that gets the colour wrong is a visual regression on
--- hardware only, because the 3DS backend bakes colour at set time while desktop applies it
--- at draw time. Both of those are asserted here rather than discovered on a console.

local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

-- Installs the love stub, which is what supplies the graphics table these tests swap out.
bootstrap.load()

local suite = T.suite()

--- Stand in for love.graphics.newTextBatch. The stub has no such call -- the module falls
--- back to printf without one, which is itself worth testing -- so the batch is modelled
--- here, recording what it was set to and what was drawn.
local function with_textbatch(body)
    local g = love.graphics
    -- Restored by this explicit list, never by `pairs(saved)`: the stub has no
    -- `newTextBatch`, so that key's saved value is nil, and a pairs loop skips absent keys
    -- entirely -- leaving the fake installed for every later test in the suite. That leak
    -- made two unrelated top-readout tests fail, because the text they look for went to the
    -- fake batch instead of to printf.
    local KEYS = { "newTextBatch", "newText", "draw", "printf", "print",
                   "getFont", "getColor", "setColor" }
    local saved = {}
    for _, k in ipairs(KEYS) do saved[k] = g[k] end
    local log = { made = 0, sets = 0, draws = {}, printfs = 0, prints = 0, colors = {} }
    local colour = { 1, 1, 1, 1 }

    g.newTextBatch = function(font, text)
        log.made = log.made + 1
        local batch = { _font = font, _text = text }
        function batch:set(t) log.sets = log.sets + 1; self._text = t end
        function batch:setf(t, limit, align)
            log.sets = log.sets + 1
            self._text, self._limit, self._align = t, limit, align
        end
        function batch:type() return "TextBatch" end
        function batch:typeOf(k) return k == "TextBatch" or k == "Drawable" end
        return batch
    end
    g.draw = function(d, x, y)
        if type(d) == "table" and d.typeOf and d:typeOf("TextBatch") then
            log.draws[#log.draws + 1] = { batch = d, x = x, y = y, colour = { unpack(colour) } }
        end
    end
    g.printf = function() log.printfs = log.printfs + 1 end
    g.print = function() log.prints = log.prints + 1 end
    g.getFont = function() return saved.getFont and saved.getFont() or { id = "font" } end
    g.getColor = function() return colour[1], colour[2], colour[3], colour[4] end
    g.setColor = function(r, gg, b, a)
        if type(r) == "table" then r, gg, b, a = r[1], r[2], r[3], r[4] end
        colour = { r, gg or 1, b or 1, a or 1 }
        log.colors[#log.colors + 1] = { unpack(colour) }
    end

    local TextCache = require("text_cache")
    TextCache.reset()
    local ok, err = pcall(body, TextCache, log, function(c) colour = c end)
    TextCache.reset()

    for _, k in ipairs(KEYS) do g[k] = saved[k] end
    if not ok then error(err, 0) end
end

suite.test("a repeated string is shaped once and redrawn", function()
    with_textbatch(function(TextCache, log)
        for _ = 1, 10 do TextCache.printf("Score", 4, 8, 100, "center") end
        T.assert_eq(log.made, 1, "one batch for ten identical draws")
        T.assert_eq(#log.draws, 10, "but drawn every time")
        T.assert_eq(log.printfs, 0, "and never falls back to printf")
    end)
end)

suite.test("different strings get their own entries", function()
    with_textbatch(function(TextCache, log)
        TextCache.printf("Score", 0, 0, 60, "left")
        TextCache.printf("Round", 0, 0, 60, "left")
        TextCache.printf("Score", 0, 0, 60, "left")
        T.assert_eq(log.made, 2, "two distinct strings, two batches")
        T.assert_eq(#log.draws, 3, "three draws")
    end)
end)

--- The colour is baked into the batch on hardware, so it has to be part of what an entry
--- matches. Reusing an entry across a colour change would silently draw last frame's colour.
suite.test("a colour change re-bakes rather than reusing the old colour", function()
    with_textbatch(function(TextCache, log, set_colour)
        set_colour({ 1, 1, 1, 1 })
        TextCache.printf("Ante", 0, 0, 40, "left")
        local made_after_first = log.made
        local sets_after_first = log.sets

        set_colour({ 1, 0, 0, 1 })
        TextCache.printf("Ante", 0, 0, 40, "left")

        T.assert_eq(log.made, made_after_first, "same string, so no new batch")
        T.assert_true(log.sets > sets_after_first, "but the text is re-set to re-bake colour")

        local last = log.draws[#log.draws]
        T.assert_eq(last.batch._text[1][1], 1, "baked red channel")
        T.assert_eq(last.batch._text[1][2], 0, "baked green channel")
    end)
end)

--- Baked colour only renders correctly if the draw is issued at white: on desktop the
--- current colour multiplies the baked one, so drawing a red-baked batch under a red colour
--- would come out doubly dark.
suite.test("the draw is issued at white and the colour restored", function()
    with_textbatch(function(TextCache, log, set_colour)
        set_colour({ 0.5, 0.25, 0.75, 0.8 })
        TextCache.printf("Blind", 0, 0, 40, "left")

        local drawn = log.draws[1].colour
        T.assert_eq(drawn[1], 1, "drawn at white r")
        T.assert_eq(drawn[2], 1, "drawn at white g")
        T.assert_eq(drawn[3], 1, "drawn at white b")

        local r, g, b, a = love.graphics.getColor()
        T.assert_eq(r, 0.5, "colour restored r")
        T.assert_eq(g, 0.25, "colour restored g")
        T.assert_eq(b, 0.75, "colour restored b")
        T.assert_eq(a, 0.8, "colour restored a")
    end)
end)

suite.test("wrap limit and alignment reach the batch", function()
    with_textbatch(function(TextCache, log)
        TextCache.printf("Discards", 0, 0, 120, "right")
        local batch = log.draws[1].batch
        T.assert_eq(batch._limit, 120, "wrap limit is applied")
        T.assert_eq(batch._align, "right", "alignment is applied")
    end)
end)

--- A runaway cache would hold native text buffers for strings nobody draws again. The cap
--- starting over is deliberate: cheap, and it cannot grow without bound.
suite.test("the cache is capped", function()
    with_textbatch(function(TextCache, log)
        for i = 1, TextCache.MAX_ENTRIES + 5 do
            TextCache.printf("label " .. i, 0, 0, 40, "left")
        end
        local font = love.graphics.getFont()
        T.assert_true(TextCache.count(font) <= TextCache.MAX_ENTRIES,
            "held " .. TextCache.count(font) .. " entries, cap is " .. TextCache.MAX_ENTRIES)
    end)
end)

--- The headless stub has no newTextBatch, and neither will some runtimes. Committed code
--- must degrade to the plain call rather than erroring.
suite.test("without runtime support it falls back to printf", function()
    local TextCache = require("text_cache")
    local saved_new = love.graphics.newTextBatch
    local saved_newtext = love.graphics.newText
    local saved_printf = love.graphics.printf
    local calls = 0
    love.graphics.newTextBatch, love.graphics.newText = nil, nil
    love.graphics.printf = function() calls = calls + 1 end
    TextCache.reset()

    local ok, err = pcall(function()
        T.assert_eq(TextCache.is_supported(), false, "reports itself unsupported")
        TextCache.printf("Score", 0, 0, 40, "left")
        T.assert_eq(calls, 1, "the plain printf still happens")
    end)

    love.graphics.newTextBatch, love.graphics.newText = saved_new, saved_newtext
    love.graphics.printf = saved_printf
    TextCache.reset()
    if not ok then error(err, 0) end
end)

return suite
