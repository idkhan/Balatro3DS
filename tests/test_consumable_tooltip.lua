--- The planet tooltip draws four distinct lines, and stays inside its box.

local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite("consumable tooltips")

--- Everything the tooltip printed, grouped back into visual lines by y.
local function capture(card)
    local printed = {}
    local real_print = love.graphics.print
    love.graphics.print = function(text, x, y, ...)
        printed[#printed + 1] = { text = tostring(text), x = x, y = y }
        return real_print(text, x, y, ...)
    end
    local ok, err = pcall(card.draw_tooltip, card, 10, 10)
    love.graphics.print = real_print
    T.assert_true(ok, tostring(err))

    local rows, order = {}, {}
    for _, item in ipairs(printed) do
        if not rows[item.y] then
            rows[item.y] = {}
            order[#order + 1] = item.y
        end
        table.insert(rows[item.y], item)
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

suite.test("a planet prints its own four lines, not one line four times", function()
    local game = bootstrap.new_game(4242)
    local card = Consumable(0, 0, CONSUMABLE_DEFS.planet_venus)
    game:add(card)

    local body = card:get_tooltip_body_lines()
    T.assert_eq(#body, 4, "the reference body is four lines")

    -- The bespoke drawer this replaced ignored `line` for planets and reprinted a hardcoded
    -- "Increases the value of <hand>" once per body line, measured against the real lines, so
    -- the box was too narrow for what went in it.
    local lines = capture(card)
    local seen = {}
    for _, line in ipairs(lines) do
        T.assert_true(not seen[line], "line repeated: " .. line)
        seen[line] = true
    end
    for _, expected in ipairs(body) do
        T.assert_true(seen[expected] ~= nil, "missing body line: " .. expected)
    end

    game:remove(card)
end)

suite.test("a planet's tooltip text fits on the bottom screen", function()
    local game = bootstrap.new_game(4242)
    local font = G.FONTS.PIXEL.SMALL
    for _, id in ipairs({ "planet_venus", "planet_jupiter", "planet_mercury" }) do
        local card = Consumable(0, 0, CONSUMABLE_DEFS[id])
        game:add(card)
        for _, line in ipairs(capture(card)) do
            T.assert_true(font:getWidth(line) <= 320, id .. ": line wider than the screen: " .. line)
        end
        game:remove(card)
    end
end)

return suite
