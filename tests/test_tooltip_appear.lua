--- Tooltips open with a short scale pop instead of snapping to full size. The reference pops
--- its info boxes in through the UI spring; on a 240p screen a hard cut reads as a flicker.
local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")
local TooltipDraw = require("tooltip_draw")

local suite = T.suite()

--- Draw a tooltip and report the uniform scale the transform was pushed with, or nil if the
--- box was drawn untransformed (which is what "fully open" looks like).
local function drawn_scale(title)
    local captured = nil
    local real_scale = love.graphics.scale
    love.graphics.scale = function(sx, sy)
        captured = sx
        return real_scale(sx, sy)
    end
    local font = G.FONTS.PIXEL.SMALL
    local lines = { TooltipDraw.build_segments_from_text("body") }
    local ok, err = pcall(TooltipDraw.draw_tooltip_layout,
        font, title, lines, 40, 40, 71, 95)
    love.graphics.scale = real_scale
    if not ok then error(err, 0) end
    return captured
end

--- Advance the appear clock the way `Game:update` does.
local function tick(dt)
    TooltipDraw.update(dt)
end

--- The appear slot is module state and outlives a single test. A frame with no tooltip drawn
--- is exactly how the game clears it, so that is how the tests clear it too.
local function reset_appear()
    tick(0)
    tick(0)
end

suite.test("a tooltip opens small and settles at full size", function()
    bootstrap.new_game(4242)
    reset_appear()

    local first = drawn_scale("Joker")
    T.assert_not_nil(first, "the first frame is transformed")
    T.assert_true(first < 1, "the tooltip starts smaller than full size")

    -- Run it well past the duration; it has to land exactly on 1 and stop transforming.
    for _ = 1, 30 do
        tick(0.016)
        drawn_scale("Joker")
    end
    T.assert_eq(drawn_scale("Joker"), nil, "a settled tooltip is drawn untransformed")
end)

--- The overshoot is what makes it read as opening rather than as a fade.
suite.test("the pop overshoots before it settles", function()
    bootstrap.new_game(4242)
    reset_appear()

    drawn_scale("Joker")
    local peak = 0
    for _ = 1, 12 do
        tick(0.016)
        local s = drawn_scale("Joker") or 1
        if s > peak then peak = s end
    end
    T.assert_true(peak > 1, "the box passes through a size larger than its final one")
end)

--- Switching cards has to restart the animation, or the second tooltip appears already open
--- and the two read as one box teleporting.
suite.test("a different tooltip restarts the pop", function()
    bootstrap.new_game(4242)
    reset_appear()

    drawn_scale("Joker")
    for _ = 1, 30 do
        tick(0.016)
        drawn_scale("Joker")
    end
    T.assert_eq(drawn_scale("Joker"), nil, "the first tooltip is settled")

    -- A new title mid-frame is a new tooltip.
    local restarted = drawn_scale("Tarot")
    T.assert_not_nil(restarted, "the new tooltip is transformed again")
    T.assert_true(restarted < 1, "and it starts small")
end)

--- Letting go of a card and touching the same one again should replay the pop, not resume it.
suite.test("closing and reopening the same tooltip replays the pop", function()
    bootstrap.new_game(4242)
    reset_appear()

    drawn_scale("Joker")
    for _ = 1, 30 do
        tick(0.016)
        drawn_scale("Joker")
    end
    T.assert_eq(drawn_scale("Joker"), nil, "settled")

    -- A frame where nothing draws a tooltip clears the slot.
    tick(0.016)
    tick(0.016)

    local reopened = drawn_scale("Joker")
    T.assert_not_nil(reopened, "the reopened tooltip is transformed")
    T.assert_true(reopened < 1, "and starts small again")
end)

return suite
