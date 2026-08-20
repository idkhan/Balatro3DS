local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

bootstrap.load()

suite.test("card shadow is a subtle parallaxed silhouette", function()
    local x, y, alpha = Card.shadow_draw_params(124, 72, false)
    T.assert_near(x, 0, 1e-9, "screen-centred card has no sideways shadow offset")
    T.assert_near(y, 1.5, 1e-9, "resting card shadow sits just below the card")
    T.assert_near(alpha, 0.5, 1e-9, "resting card shadow remains visible")

    local left_x = Card.shadow_draw_params(0, 72, false)
    local right_x = Card.shadow_draw_params(248, 72, false)
    T.assert_true(left_x < 0 and right_x > 0, "shadow shifts with the card's screen position")
end)

suite.test("dragged card raises its shadow", function()
    local _, resting_y, resting_alpha = Card.shadow_draw_params(124, 72, false)
    local _, drag_y, drag_alpha = Card.shadow_draw_params(124, 72, true)
    T.assert_true(drag_y > resting_y, "drag shadow sits farther below the lifted card")
    T.assert_true(drag_alpha < resting_alpha, "lifted shadow softens with height")
end)

return suite
