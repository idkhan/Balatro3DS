local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite("pixel_grid")

local function fresh()
    bootstrap.load()
    package.loaded.pixel_grid = nil
    return require("pixel_grid")
end

--- Run `fn` with love.graphics.rectangle recording its arguments at the given line width.
local function stroked(line_width, fn)
    local g = love.graphics
    local saved_rect, saved_lw = g.rectangle, g.getLineWidth
    local calls = {}
    g.rectangle = function(...) calls[#calls + 1] = { ... } end
    g.getLineWidth = function() return line_width end
    local ok, err = pcall(fn)
    g.rectangle, g.getLineWidth = saved_rect, saved_lw
    if not ok then error(err, 0) end
    return calls
end

suite.test("art_scale rounds a layout upscale to whole pixels and keeps a downscale", function()
    local PixelGrid = fresh()
    T.assert_eq(PixelGrid.art_scale(1.05), 1, "the blind chip's 1.05")
    T.assert_eq(PixelGrid.art_scale(1.3), 1)
    T.assert_eq(PixelGrid.art_scale(1.6), 2)
    T.assert_eq(PixelGrid.art_scale(2.4), 2)
    T.assert_eq(PixelGrid.art_scale(0.85), 0.85, "no whole number is left below 1")
end)

suite.test("at_rest is true only while no drawn pixel would move half a pixel", function()
    local PixelGrid = fresh()
    -- A 30 px label scaled about its centre: its edges are 15 px from the anchor.
    T.assert_true(PixelGrid.at_rest(1.015, 15), "1.015 moves the edge 0.225 px")
    T.assert_true(PixelGrid.at_rest(0.99, 15), "0.99 moves the edge 0.15 px")
    T.assert_false(PixelGrid.at_rest(1.05, 15), "1.05 moves the edge 0.75 px")
    T.assert_false(PixelGrid.at_rest(1.3, 15), "the pop itself")
    -- The same 1.015 on a 160 px tooltip moves its far edge more than a pixel.
    T.assert_false(PixelGrid.at_rest(1.015, 80))
    T.assert_true(PixelGrid.at_rest(1, 1000))
end)

suite.test("a 1 px outline is stroked on the half pixel inside its box", function()
    local PixelGrid = fresh()
    local calls = stroked(1, function() PixelGrid.outline(10, 20, 30, 40) end)
    T.assert_eq(#calls, 1)
    -- Covers columns 10..39 and rows 20..59: exactly the box.
    T.assert_deep_eq(calls[1], { "line", 10.5, 20.5, 29, 39, 0, 0 })
end)

suite.test("a 2 px outline is stroked on whole pixels inside its box", function()
    local PixelGrid = fresh()
    -- The `x + 0.5, w - 1` workaround this replaces centred a 2 px stroke on 10.5: 9.5..11.5.
    local calls = stroked(2, function() PixelGrid.outline(10, 20, 30, 40) end)
    T.assert_deep_eq(calls[1], { "line", 11, 21, 28, 38, 0, 0 })
end)

suite.test("a rounded outline keeps the box's outer corner radius", function()
    local PixelGrid = fresh()
    -- 3 px stroke, radius 4: the path runs 1.5 px in, so its own radius is 2.5 and the stroke's
    -- outer edge rounds at 4, matching a fill drawn with the same rectangle.
    local calls = stroked(3, function() PixelGrid.outline(0, 0, 50, 60, 4) end)
    T.assert_deep_eq(calls[1], { "line", 1.5, 1.5, 47, 57, 2.5, 2.5 })
    -- A radius smaller than the inset clamps to a square path rather than going negative.
    calls = stroked(3, function() PixelGrid.outline(0, 0, 50, 60, 1) end)
    T.assert_eq(calls[1][6], 0)
end)

suite.test("a fractional box is snapped edge by edge before it is stroked", function()
    local PixelGrid = fresh()
    -- Edges 10.4 -> 10, 20.6 -> 21, 40.6 -> 41, 60.4 -> 60: a 31 x 39 box.
    local calls = stroked(1, function() PixelGrid.outline(10.4, 20.6, 30.2, 39.8) end)
    T.assert_deep_eq(calls[1], { "line", 10.5, 21.5, 30, 38, 0, 0 })
end)

return suite
