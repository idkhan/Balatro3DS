local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")
local DynaText = require("dyna_text")

local suite = T.suite()

suite.test("per-letter float and rotation use independent sine phases", function()
    local text = DynaText.new({
        float_amount = 2,
        float_speed = 1,
        float_phase = 0.5,
        rotation_amount = 0.1,
        rotation_speed = 2,
        rotation_phase = 0.25,
    })
    local y, rotation, scale = DynaText.letter_transform(text, 2, math.pi)
    T.assert_near(y, 2 * math.sin(math.pi + 0.5), 1e-9, "vertical float")
    T.assert_near(rotation, 0.1 * math.sin(math.pi * 2 + 0.25), 1e-9, "rotation")
    T.assert_eq(scale, 1, "idle letters keep their scale")
end)

suite.test("changed values trigger a bump that decays to rest", function()
    local text = DynaText.new({ bump_amount = 0.2, bump_duration = 0.5 })
    DynaText.update(text, "Small", 2)
    DynaText.update(text, "Boss", 3)

    local _, _, start_scale = DynaText.letter_transform(text, 1, 3)
    local _, _, peak_scale = DynaText.letter_transform(text, 1, 3.25)
    local _, _, rest_scale = DynaText.letter_transform(text, 1, 3.5)
    T.assert_eq(start_scale, 1, "bump starts at rest")
    T.assert_near(peak_scale, 1.2, 1e-9, "bump peaks halfway through")
    T.assert_eq(rest_scale, 1, "bump decays fully")
end)

suite.test("unanimated text retains the ordinary printf path", function()
    local love = bootstrap.load()
    local text = DynaText.new()
    local printf_calls, print_calls = 0, 0
    local old_printf, old_print = love.graphics.printf, love.graphics.print
    love.graphics.printf = function(value, x, y, width, align)
        printf_calls = printf_calls + 1
        T.assert_eq(value, "Plain", "text passes through unchanged")
        T.assert_eq(align, "center", "legacy alignment remains intact")
    end
    love.graphics.print = function() print_calls = print_calls + 1 end

    local ok, err = pcall(function()
        DynaText.draw(text, "Plain", 10, 20, 100, "center", 1)
    end)
    love.graphics.printf, love.graphics.print = old_printf, old_print
    if not ok then error(err) end

    T.assert_eq(printf_calls, 1, "one ordinary text draw")
    T.assert_eq(print_calls, 0, "no per-glyph draws without effects")
end)

return suite
