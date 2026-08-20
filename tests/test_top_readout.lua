local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite("top readout")

--- Everything `TopUI:draw` printed, plus the rectangles it filled, so a test can tell which of
--- the chips/mult layouts ran without a renderer.
local function capture_top(game, top)
    local printed, rects = {}, {}
    local real_print, real_printf = love.graphics.print, love.graphics.printf
    local real_rect = love.graphics.rectangle
    love.graphics.print = function(text, x, y, ...)
        printed[#printed + 1] = tostring(text); return real_print(text, x, y, ...)
    end
    love.graphics.printf = function(text, x, y, w, ...)
        printed[#printed + 1] = tostring(text); return real_printf(text, x, y, w, ...)
    end
    love.graphics.rectangle = function(mode, x, y, w, h, ...)
        rects[#rects + 1] = { mode = mode, x = x, y = y, w = w, h = h }
        return real_rect(mode, x, y, w, h, ...)
    end
    local ok, err = pcall(top.draw, top, "top")
    love.graphics.print, love.graphics.printf = real_print, real_printf
    love.graphics.rectangle = real_rect
    T.assert_true(ok, tostring(err))
    return printed, rects
end

local function contains(list, value)
    for _, item in ipairs(list) do
        if item == value then return true end
    end
    return false
end

local function fresh_game()
    bootstrap.load()
    local g = Game()
    _G.G = g
    g.STATE = g.STATES.SELECTING_HAND
    return g, TopUI()
end

suite.test("the X shows while a hand is being built", function()
    local g, top = fresh_game()
    g.chip_total_display = nil
    top:update_chip_total(0)
    local printed = capture_top(g, top)
    T.assert_true(contains(printed, "X"), "the operator between chips and mult")
end)

suite.test("the landed product replaces the operand pair rather than the X", function()
    local g, top = fresh_game()
    g.chip_total_display = 1500
    top:update_chip_total(0)

    local printed, rects = capture_top(g, top)
    -- The gap between the two panels is 16 px; a four-digit product drawn there ran straight
    -- through both of them, which is what this replaced.
    T.assert_false(contains(printed, "X"), "the X is gone once the product has landed")
    T.assert_true(contains(printed, "1,500"), "the product is drawn, grouped")

    -- One panel spanning the row, not two half-width ones. ChipWidth is iw/2 - 8, so a panel
    -- wider than that on the chips/mult line can only be the collapsed one.
    local wide = 0
    for _, r in ipairs(rects) do
        if r.mode == "fill" and r.w and r.w > 60 and r.h and r.h > 20 and r.h < 40 then
            wide = wide + 1
        end
    end
    T.assert_true(wide > 0, "expected a full-width total panel")
end)

suite.test("the product's own panel is wide enough for a large product", function()
    local g, top = fresh_game()
    -- Balatro products run past a billion in a real run; the old 16 px gap could not hold four
    -- digits, let alone ten.
    g.chip_total_display = 1234567890
    top:update_chip_total(0)
    local printed = capture_top(g, top)
    T.assert_true(contains(printed, "1,234,567,890"), "the whole product is drawn, not a clipped part")
end)

suite.test("draining the product restores the chips and mult pair", function()
    local g, top = fresh_game()
    g.chip_total_display = 400
    g.chip_total_drain = true
    top:update_chip_total(0)
    T.assert_not_nil(top.chip_total_value)

    -- The reference drains over 0.5 s; step past it and the row has to come back.
    top:update_chip_total(0.6)
    T.assert_nil(top.chip_total_value, "the product cleared")

    local printed = capture_top(g, top)
    T.assert_true(contains(printed, "X"), "the operator is back")
end)

--- The reference prints the win ante beside the current one (`UI_definitions.lua:1319-1326`)
--- and a used/limit count under every card area (`cardarea.lua:283-289`). Neither was here,
--- so nothing on screen said how long a run is or how many slots the player had.
suite.test("the HUD shows the win ante and the joker and consumable slot counts", function()
    local g, top = fresh_game()
    g.ante = 3
    g.joker_capacity = 5
    g.jokers = {}
    g.consumables = { { id = "planet_pluto" } }
    g.consumables_on_bottom = false

    local printed = capture_top(g, top)
    T.assert_true(contains(printed, "3/8"), "the ante reads against the win ante")
    T.assert_true(contains(printed, "0/5"), "empty joker slots still report their limit")
    T.assert_true(contains(printed, "1/2"), "consumables report used over limit")
end)

--- Endless drops the denominator. "10/8" wrapped in the 46 px Ante field, and past the win
--- ante there is nothing left to count towards anyway.
suite.test("the ante loses its denominator once the run is past the win ante", function()
    local g, top = fresh_game()

    g.ante = 8
    T.assert_eq(top:ante_readout(), "8/8", "the last ante of a normal run still counts against 8")

    g.ante = 9
    T.assert_eq(top:ante_readout(), "9", "endless drops the denominator")

    g.ante = 12
    T.assert_eq(top:ante_readout(), "12")

    local printed = capture_top(g, top)
    T.assert_true(contains(printed, "12"), "the bare ante reaches the HUD")
    T.assert_false(contains(printed, "12/8"), "and never with the win ante beside it")
end)

--- The memo covers both halves: the suffix appearing and disappearing is exactly what a
--- one-value memo would miss.
suite.test("the ante memo rebuilds when the ante or the win ante changes", function()
    local g, top = fresh_game()
    g.ante = 3
    local first = top:ante_readout()
    T.assert_eq(first, "3/8")
    T.assert_true(rawequal(first, top:ante_readout()), "unchanged is not rebuilt")

    g.ante = 4
    T.assert_eq(top:ante_readout(), "4/8", "a new ante rebuilds")

    g.get_win_ante = function() return 4 end
    T.assert_eq(top:ante_readout(), "4/4", "a new win ante rebuilds too")
    g.get_win_ante = function() return 3 end
    T.assert_eq(top:ante_readout(), "4", "and a win ante that falls behind drops the suffix")
end)

suite.test("the slot readout memo rebuilds when either half changes", function()
    local _, top = fresh_game()
    local first = top:cached_ratio_label("slots", 1, 5)
    T.assert_eq(first, "1/5")
    T.assert_true(rawequal(first, top:cached_ratio_label("slots", 1, 5)), "unchanged is not rebuilt")
    T.assert_eq(top:cached_ratio_label("slots", 2, 5), "2/5", "a new count rebuilds")
    T.assert_eq(top:cached_ratio_label("slots", 2, 6), "2/6", "a new limit rebuilds too")
end)

suite.test("a level-up takes over the readout and shows its deltas", function()
    local g, top = fresh_game()
    -- Nothing selected, which is the normal case for using a Planet: without the takeover the
    -- hand block is blank and the level-up has nowhere to show.
    g.selectedHand = nil
    g:begin_hand_levelup_flourish("Pair", 3, 30, 6, 4, 45, 8)

    local printed = capture_top(g, top)
    T.assert_true(contains(printed, "Pair"), "the hand being levelled owns the name slot")
    T.assert_true(contains(printed, "lvl.3"), "starting from the level it had")
    T.assert_true(contains(printed, "30"))
    T.assert_true(contains(printed, "6"))

    g:_update_hand_levelup(0.5)
    printed = capture_top(g, top)
    T.assert_true(contains(printed, "+2"), "the mult gain is plated over its readout")

    g:_update_hand_levelup(0.9)
    printed = capture_top(g, top)
    T.assert_true(contains(printed, "+15"), "then the chips gain")

    g:_update_hand_levelup(0.9)
    printed = capture_top(g, top)
    T.assert_true(contains(printed, "lvl.4"), "and the level lands")

    g:_update_hand_levelup(0.7)
    printed = capture_top(g, top)
    T.assert_false(contains(printed, "Pair"), "then the readout is handed back")
end)

suite.test("a level-up outranks the booster blanking", function()
    local g, top = fresh_game()
    -- A Celestial pack levels hands from inside the pack, where the readout is otherwise
    -- forced blank because a pack pick is not a play.
    g.STATE = g.STATES.OPEN_BOOSTER
    g:begin_hand_levelup_flourish("Flush", 2, 40, 8, 3, 55, 10)
    local printed = capture_top(g, top)
    T.assert_true(contains(printed, "Flush"))
    T.assert_true(contains(printed, "lvl.2"))
end)

suite.test("a long boss name steps down one rung rather than overrunning its block", function()
    bootstrap.load()
    local Fonts = require("fonts")
    local game = { FONTS = { PIXEL = Fonts.build("native") } }
    local pixel = game.FONTS.PIXEL
    -- "Crimson Heart" and "Verdant Leaf" are wider than the top readout's blind block at MEDIUM.
    local wide = string.rep("W", 30)
    local fitted = Fonts.fit(game, pixel.MEDIUM, wide, 112)
    T.assert_ne(fitted, pixel.MEDIUM, "a name that does not fit must step down")

    -- One rung, not straight to the floor: BUTTON (18) sits between MEDIUM (22) and SMALL (13).
    local narrow = pixel.MEDIUM:getWidth(wide) - 1
    local one_step = Fonts.fit(game, pixel.MEDIUM, wide, narrow)
    T.assert_eq(one_step, pixel.BUTTON, "stepped further than needed")
end)

--- The hand name was the one readout on this panel that never moved, so building up to a Full
--- House looked exactly like building up to a High Card.
suite.test("the hand name pops when the detected hand changes", function()
    local g = bootstrap.new_game(6060)
    _G.G = g
    local top = TopUI()

    g.handlist = g.handlist or { "High Card", "Pair", "Two Pair" }

    -- First hand seen: registers, but there was nothing before it to change from.
    g.selectedHand = 1
    top:update_counters(0.016)
    T.assert_eq(top.hand_juice, nil, "the first hand does not pop out of nowhere")

    -- Selecting a card that turns a Pair into Two Pair is the beat worth showing.
    g.selectedHand = 3
    top:update_counters(0.016)
    T.assert_not_nil(top.hand_juice, "a new hand name pops")

    -- Re-detecting the same hand must not re-pop every frame.
    for _ = 1, 40 do top:update_counters(0.016) end
    T.assert_eq(top.hand_juice, nil, "an unchanged hand settles and stays settled")
end)

--- Clearing the selection blanks the readout; that is not a hand arriving, so it must not pop.
suite.test("clearing the hand selection does not pop the name", function()
    local g = bootstrap.new_game(6060)
    _G.G = g
    local top = TopUI()
    g.handlist = g.handlist or { "High Card", "Pair" }

    g.selectedHand = 2
    top:update_counters(0.016)
    for _ = 1, 40 do top:update_counters(0.016) end

    g.selectedHand = -1
    top:update_counters(0.016)
    T.assert_eq(top.hand_juice, nil, "an emptied readout is not a new hand")
end)

--- A fill-mode rounded rect never reads the line width, and nearly every rect on screen is a
--- fill -- around 28 a frame on the top screen alone, at 2.04 us a call on hardware. The
--- reset used to run unconditionally. Line mode still has to set it, and still has to put it
--- back, because callers that follow are entitled to a width of 1.
suite.test("a fill rounded rect sets no line width, a styled line rect sets and restores", function()
    local widths = {}
    local real = love.graphics.setLineWidth
    love.graphics.setLineWidth = function(w) widths[#widths + 1] = w; return real(w) end

    local ok, err = pcall(function()
        draw_rounded_rect(0, 0, 40, 20, 4, 0, "fill")
        T.assert_eq(#widths, 0, "a fill must not touch the line width")

        draw_rounded_rect(0, 0, 40, 20, 4, 2, "fill")
        T.assert_eq(#widths, 0, "padding on a fill is an inset, not a stroke")

        draw_rounded_rect(0, 0, 40, 20, 4, 2, "line")
        T.assert_eq(#widths, 2, "a styled line rect sets and restores")
        T.assert_eq(widths[1], 2, "set to the padding")
        T.assert_eq(widths[2], 1, "and put back to 1")
    end)

    love.graphics.setLineWidth = real
    if not ok then error(err, 0) end
end)

return suite
