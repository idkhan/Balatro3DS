--- Run Info: the four things the reference's tabbed dialog carries, spread over two screens.
---
--- The port had no Run Info at all -- ZL reopened the deck view with a hand-level panel slid
--- over it, so Blinds were nowhere and Vouchers lived on the deck screen. The reference lists
--- Poker Hands, Blinds, Vouchers and Stake (`UI_definitions.lua:3129-3151`); all four are
--- here now, with the blinds and vouchers on the readout and the hand list on the touch
--- screen.
local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

bootstrap.load()
local RunInfoUI = require("run_info_ui")
local DeckViewUI = require("deck_view_ui")

local function playing_game()
    local g = bootstrap.new_game(4242)
    g.deck = Deck(g)
    g.hand = Hand(g)
    g.STATE = g.STATES.SELECTING_HAND
    return g
end

suite.test("ZL opens Run Info as its own overlay, building no cards", function()
    local g = playing_game()

    T.assert_true(g:toggle_run_info())
    T.assert_true(g._run_info_open)
    T.assert_false(g._deck_view_open, "the deck view is not involved")
    T.assert_eq(g._deck_view_nodes, nil, "no Card nodes are built to read a list of numbers")

    T.assert_true(g:toggle_run_info(), "ZL closes it again")
    T.assert_false(g._run_info_open)
end)

suite.test("the two overlays are mutually exclusive", function()
    local g = playing_game()

    T.assert_true(g:enter_deck_view())
    T.assert_true(g._deck_view_open)

    T.assert_true(g:enter_run_info(), "opening Run Info takes over from the deck view")
    T.assert_true(g._run_info_open)
    T.assert_false(g._deck_view_open)
    T.assert_eq(g._deck_view_nodes, nil, "and tears its cards down on the way out")

    T.assert_true(g:enter_deck_view(), "and back the other way")
    T.assert_true(g._deck_view_open)
    T.assert_false(g._run_info_open)

    g:exit_deck_view()
end)

--- On an Old 3DS the ZL/ZR triggers do not physically exist (`input_bindings.lua:331`), so
--- SELECT has to reach both overlays on its own.
suite.test("SELECT steps deck view to run info to closed", function()
    local g = playing_game()

    T.assert_true(g:toggle_deck_view())
    T.assert_true(g._deck_view_open)

    T.assert_true(DeckViewUI.handle_gamepad(g, "back"))
    T.assert_false(g._deck_view_open)
    T.assert_true(g._run_info_open)

    T.assert_true(RunInfoUI.handle_gamepad(g, "back"))
    T.assert_false(g._run_info_open)
end)

suite.test("B closes the deck view outright rather than stepping on", function()
    local g = playing_game()
    T.assert_true(g:toggle_deck_view())
    T.assert_true(DeckViewUI.handle_gamepad(g, "b"))
    T.assert_false(g._deck_view_open)
    T.assert_false(g._run_info_open)
end)

--- The pause menu draws over an overlay but the touch router checks the overlay flags first,
--- so an overlay left open made every pause button visible and unreachable. Deck View had a
--- guard from the start; Run Info shipped without one.
suite.test("opening the pause menu closes whichever overlay is up", function()
    for _, open in ipairs({ "enter_deck_view", "enter_run_info" }) do
        local g = playing_game()
        T.assert_true(g[open](g))
        T.assert_true(g:enter_pause_menu(), open .. " then pause")
        T.assert_false(g:modal_overlay_open(), "no overlay survives into the pause menu")
        T.assert_false(g._deck_view_open)
        T.assert_false(g._run_info_open)
    end
end)

--- Six guards in game.lua asked `_deck_view_open` when they meant "is a modal up". Run Info
--- has to answer them all, or it leaks input and animation to the playfield behind it.
suite.test("run info blocks everything the deck view blocks", function()
    local g = playing_game()
    T.assert_false(g:modal_overlay_open(), "nothing is up to begin with")
    T.assert_false(g:_panel_toggle_blocked(), "the trays are reachable while playing")

    T.assert_true(g:enter_run_info())
    T.assert_true(g:modal_overlay_open())
    T.assert_true(g:_panel_toggle_blocked(), "the shoulders drive the dialog, not the trays")
    T.assert_false(g:hand_cancel_gesture_available(), "the hand is not taking gestures")
    T.assert_false(g:consumes_focus_restore_press("a"), "and not taking a focus-restore press")

    g:exit_run_info()
    T.assert_false(g:modal_overlay_open())
    T.assert_false(g:_panel_toggle_blocked(), "and everything comes back")
end)

suite.test("blind state is derived from where the ante has got to", function()
    local g = playing_game()
    g.current_blind_index = 2

    T.assert_eq(RunInfoUI.blind_state(g, 1), "Defeated")
    T.assert_eq(RunInfoUI.blind_state(g, 2), "Current")
    T.assert_eq(RunInfoUI.blind_state(g, 3), "Upcoming")
end)

--- `Game.skips` holds the tag a skip *would* award, not a record that one was taken, so a
--- skipped Big Blind used to be indistinguishable from a defeated one.
suite.test("a skipped blind reads as Skipped, not Defeated", function()
    local g = playing_game()
    g.current_blind_index = 3
    g.blinds_skipped = { [2] = true }

    T.assert_eq(RunInfoUI.blind_state(g, 1), "Defeated")
    T.assert_eq(RunInfoUI.blind_state(g, 2), "Skipped")
    T.assert_eq(RunInfoUI.blind_state(g, 3), "Current")
end)

suite.test("skipping a blind marks it, and rolling a new ante clears the marks", function()
    local g = playing_game()
    g.current_blind_index = 1
    g.skips = { [1] = 0, [2] = 0 }

    T.assert_true(g:skip_blind(1))
    T.assert_true(g.blinds_skipped[1], "the skip is recorded")
    T.assert_eq(RunInfoUI.blind_state(g, 1), "Skipped")

    g:roll_skips()
    T.assert_eq(next(g.blinds_skipped), nil, "a fresh ante starts with nothing skipped")
end)

suite.test("the blind row carries a name, target and reward for all three", function()
    local g = playing_game()
    g.ante = 3
    g.current_blind_index = 2

    local blinds = RunInfoUI.blinds(g)
    T.assert_eq(#blinds, 3)
    for i, b in ipairs(blinds) do
        T.assert_true(type(b.name) == "string" and b.name ~= "", "blind " .. i .. " is named")
        T.assert_true(b.target > 0, "blind " .. i .. " has a target")
        T.assert_true(type(b.sprite_row) == "number", "blind " .. i .. " has a token")
    end
    -- Not strictly greater: The Needle's multiplier is 1, the same as the Small Blind's
    -- (`game.lua` P_BLINDS `bl_needle`), because what it takes away is hands, not headroom.
    T.assert_true(blinds[3].target >= blinds[1].target, "the boss never asks for less")
    T.assert_true(blinds[2].target > blinds[1].target, "the big blind always does ask for more")
end)

suite.test("vouchers are listed here, not on the deck screen", function()
    local g = playing_game()
    g.vouchers = { "v_overstock" }

    local owned = RunInfoUI.owned_vouchers(g)
    T.assert_eq(#owned, 1)
    T.assert_eq(owned[1].id, "v_overstock")
    T.assert_true(owned[1].description ~= "", "the description is what the panel is for")
    T.assert_true(type(owned[1].pos) == "number", "and its sprite cell, so it draws as a card")

    -- The set-keyed shape is also in use around the codebase.
    g.vouchers = { v_overstock = true }
    T.assert_eq(#RunInfoUI.owned_vouchers(g), 1, "a set of ids works too")

    -- Unknown ids are dropped rather than rendered as blanks.
    g.vouchers = { "v_not_a_real_voucher" }
    T.assert_eq(#RunInfoUI.owned_vouchers(g), 0)

    T.assert_eq(DeckViewUI.owned_vouchers, nil, "the deck screen no longer carries them")
end)

suite.test("only discovered hands are listed, with their live level and count", function()
    local g = playing_game()
    g.hand_play_counts = g.hand_play_counts or {}

    local hidden = RunInfoUI.visible_hands(g)
    for _, h in ipairs(hidden) do
        T.assert_true(h.index >= 4, "the three secret hands stay hidden until played")
    end

    -- Play a Flush Five once and it joins the list.
    g.hand_play_counts[1] = 1
    local shown = RunInfoUI.visible_hands(g)
    T.assert_eq(shown[1].index, 1)
    T.assert_eq(shown[1].name, "Flush Five")
    T.assert_eq(shown[1].played, 1)
    T.assert_true(shown[1].chips > 0 and shown[1].mult > 0, "chips and mult come from the level")
end)

--- Twelve hands is the ceiling (`globals.lua:370`) and the list has 168 px, so the rows have
--- to shrink rather than scroll -- a list you can see all of should not need driving.
suite.test("every visible hand fits the list without scrolling", function()
    local LIST_TOP, LIST_BOTTOM = 34, 202
    for n = 1, 12 do
        local step, row_h = RunInfoUI.row_metrics(n)
        T.assert_true(row_h >= 11, n .. " rows still clear a line of text")
        T.assert_true(LIST_TOP + (n - 1) * step + row_h <= LIST_BOTTOM,
            n .. " rows fit above the Back button")
    end
    local step_few = RunInfoUI.row_metrics(4)
    T.assert_eq(step_few, 24, "a short list does not stretch past the comfortable row height")
end)

suite.test("the voucher fan overlaps only once the row would overflow", function()
    local step_two = RunInfoUI._fanned_step(2, 248, 56, 4)
    T.assert_eq(step_two, 60, "two vouchers keep their natural gap")

    local step_nine = RunInfoUI._fanned_step(9, 248, 56, 4)
    T.assert_true(step_nine < 60, "nine tuck under each other")
    T.assert_true(8 * step_nine + 56 <= 248 + 0.5, "and the fan still fits its slot")
end)

suite.test("Back closes from a touch as well as a button", function()
    local g = playing_game()
    T.assert_true(g:enter_run_info())
    RunInfoUI.draw_bottom(g)

    local r = g._run_info_back_rect
    T.assert_not_nil(r, "the Back button has a rect")
    T.assert_true(RunInfoUI.handle_touchpressed(g, 1, r.x + r.w * 0.5, r.y + r.h * 0.5))
    T.assert_false(g._run_info_open)
end)

suite.test("the touch-screen hint stays in the voucher column in Spanish", function()
    local I18N = require("localization")
    local Fonts = require("fonts")
    local TextCache = require("text_cache")
    local g = playing_game()
    I18N.set_language("es")
    -- The hardware faces: at the shared profile's LABEL the Spanish hint already fits.
    g.FONTS.PIXEL = Fonts.build("native", "es")
    local hint = I18N.text("run_info.hands_hint")
    local right
    local real = TextCache.print
    TextCache.print = function(text, x, y, ...)
        if text == hint then right = x + love.graphics.getFont():getWidth(text) end
        return real(text, x, y, ...)
    end
    local ok, err = pcall(RunInfoUI.draw_top, "top", g)
    TextCache.print = real
    I18N.set_language("en")
    if not ok then error(err, 0) end
    T.assert_not_nil(right, "the hint is drawn")
    -- The stake chip and its rules start at x = 268.
    T.assert_true(right <= 266, "the hint ends at x=" .. tostring(right))
end)

return suite
