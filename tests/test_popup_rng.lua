local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()
local love = bootstrap.load()

suite.test("popup spawn is deterministic and leaves the gameplay stream untouched", function()
    local original_math_random = math.random
    local original_love_random = love.math.random
    local gameplay_calls = 0
    local visual_calls = 0
    math.random = function()
        gameplay_calls = gameplay_calls + 1
        return 0
    end
    love.math.random = function(a)
        visual_calls = visual_calls + 1
        return a
    end

    local original_g = G
    G = { C = { CHIPS = { 1, 1, 1, 1 } } }
    local popup = Popup()
    popup:spawn(30, "chips", 50, 60)
    G = original_g
    love.math.random = original_love_random
    math.random = original_math_random

    T.assert_eq(gameplay_calls, 0, "popups must never touch the run RNG")
    T.assert_eq(visual_calls, 0, "popups anchor to their card; no scatter at all")
    T.assert_eq(popup.speed, nil, "popups do not rotate (common_events.lua:779-935)")
    T.assert_eq(popup.pos.x, 50, "anchored to the spawn x")
    T.assert_eq(popup.pos.y, 28, "anchored a fixed height above the spawn point")
end)

suite.test("popup hold times follow the reference per-type beats", function()
    local original_g = G
    G = { C = { CHIPS = { 1, 1, 1, 1 }, BOOSTER = { 1, 1, 1, 1 }, MULT = { 1, 1, 1, 1 } } }
    local chips = Popup()
    chips:spawn(30, "chips", 0, 0)
    local mult = Popup()
    mult:spawn(4, "mult", 0, 0)
    local msg = Popup()
    msg:spawn("Eaten!", "Nope", 0, 0)
    G = original_g

    T.assert_eq(chips.duration, 0.75, "chips hold is 0.6 * 1.25")
    T.assert_eq(mult.duration, 0.8125, "general hold is 0.65 * 1.25")
    T.assert_eq(msg.duration, 0.9375, "joker-message hold is 0.75 * 1.25")
end)

return suite
