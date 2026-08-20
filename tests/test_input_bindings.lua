--- The face buttons follow Balatro's Switch layout: A selects, B deselects, X discards, Y
--- plays. Sorting has no button of its own there, so it rides on a B tap with nothing selected.
local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

bootstrap.load()
local InputBindings = require("input_bindings")

local suite = T.suite()

local function hand_game(seed)
    local g = bootstrap.new_game(seed or 5150)
    _G.G = g
    g.STATE = g.STATES.SELECTING_HAND
    g.hands = 4
    g.discards = 3
    g.deck = Deck(g)
    g.hand = Hand(g)
    g.hand:fill_from_deck(true)
    g:set_gamepad_focus_layer("hand")
    return g
end

suite.test("the default layout is the Switch one", function()
    local b = InputBindings.default_settings().bindings
    T.assert_eq(InputBindings.get_button_for_role("confirm", b), "a")
    T.assert_eq(InputBindings.get_button_for_role("cancel", b), "b")
    T.assert_eq(InputBindings.get_button_for_role("discard", b), "x")
    T.assert_eq(InputBindings.get_button_for_role("play", b), "y")
end)

suite.test("menus take either button of each pair", function()
    local b = InputBindings.default_settings().bindings
    T.assert_true(InputBindings.is_menu_activate("a", b))
    T.assert_true(InputBindings.is_menu_activate("y", b))
    T.assert_true(InputBindings.is_menu_back("b", b))
    T.assert_true(InputBindings.is_menu_back("x", b))
    T.assert_false(InputBindings.is_menu_activate("b", b))
    T.assert_false(InputBindings.is_menu_back("a", b))
end)

suite.test("bindings saved against the old role set are dropped", function()
    -- X was Play and Y was Sort; carrying those buttons over would leave a half-old layout.
    local out = InputBindings.normalize_bindings({ use = { "y" }, sort = { "x" }, confirm = { "b" } })
    T.assert_eq(InputBindings.get_button_for_role("confirm", out), "a", "the whole block is dropped")
    T.assert_eq(InputBindings.get_button_for_role("play", out), "y")
    T.assert_eq(InputBindings.get_button_for_role("discard", out), "x")

    -- A file written against the current roles is still honoured.
    local kept = InputBindings.normalize_bindings({ confirm = { "b" } })
    T.assert_eq(InputBindings.get_button_for_role("confirm", kept), "b")
end)

suite.test("X discards and Y plays the selection", function()
    local g = hand_game()
    g.hand:toggle_selection(g.hand.card_nodes[1])
    g.hand:toggle_selection(g.hand.card_nodes[2])

    T.assert_true(g:handle_gamepad_selecting_hand("x"), "X discards")
    T.assert_eq(g.discards, 2, "a discard was spent")

    g.hand:toggle_selection(g.hand.card_nodes[1])
    T.assert_true(g:handle_gamepad_selecting_hand("y"), "Y plays")
    T.assert_true(g.hand:is_scoring_active(), "the hand is being scored")
end)

suite.test("B on the hand waits for the release rather than acting on the press", function()
    local g = hand_game()
    local node = g.hand.card_nodes[1]
    g.hand:toggle_selection(node)

    T.assert_false(g:handle_gamepad_selecting_hand("b"), "the press does nothing on the hand")
    T.assert_eq(#g.hand.selected, 1, "the selection survives the press")
    T.assert_eq(g.discards, 3, "and B never discards")

    T.assert_true(g:try_gamepad_hand_cancel_tap(), "the release drops the selection")
    T.assert_eq(#g.hand.selected, 0)
end)

suite.test("a B tap with nothing selected sorts the hand instead", function()
    local g = hand_game()
    T.assert_eq(#g.hand.selected, 0)
    local by_rank = g._hand_sort_by_rank

    T.assert_true(g:try_gamepad_hand_cancel_tap())
    T.assert_true(g._hand_sort_by_rank ~= by_rank, "the sort flipped")

    T.assert_true(g:try_gamepad_hand_cancel_tap())
    T.assert_eq(g._hand_sort_by_rank, by_rank, "and flips back")
end)

suite.test("B still sells from a pulled-down row", function()
    local g = hand_game()
    T.assert_true(g:add_joker_by_def("j_joker"))
    T.assert_true(g:toggle_jokers_pulled())
    T.assert_eq(g:get_gamepad_focus_layer(), "jokers")
    local money = g.money

    T.assert_true(g:handle_gamepad_selecting_hand("b"), "B sells the focused joker")
    T.assert_eq(#g.jokers, 0)
    T.assert_true(g.money > money)
end)

suite.test("holding B is the sweep, and its release does not deselect", function()
    local g = hand_game()
    -- `main.lua` arms the gesture as the button goes down.
    g._cancel_gesture_armed = g:hand_cancel_gesture_available()
    g:set_role_held("cancel", true, 0)
    T.assert_true(g:is_sweep_select_mode(), "holding cancel over the hand sweeps")

    g:ensure_sweep_seed()
    T.assert_true(g._sweep_seeded, "the card under the cursor seeds the sweep")
    T.assert_eq(#g.hand.selected, 1)

    g:_dpad_horizontal_step(1, true)
    T.assert_eq(#g.hand.selected, 2, "and the D-pad extends it")
end)

--- B is sell as well as deselect, and selling the last joker hands focus straight back to the
--- hand. Neither the tap nor the sweep may follow it there.
suite.test("a B press that began on the joker row keeps its hands off the hand", function()
    local g = hand_game(5153)
    T.assert_true(g:add_joker_by_def("j_joker"))
    T.assert_true(g:toggle_jokers_pulled())
    g.hand:toggle_selection(g.hand.card_nodes[1])

    local armed = g:hand_cancel_gesture_available()
    T.assert_false(armed, "the press is not the hand's")
    g._cancel_gesture_armed = armed
    g:set_role_held("cancel", true, 0)

    T.assert_true(g:handle_gamepad_selecting_hand("b"), "it sells")
    T.assert_eq(g:get_gamepad_focus_layer(), "hand", "and the empty row gives focus back")
    T.assert_false(g:is_sweep_select_mode(), "the hold does not become a sweep")
    T.assert_eq(#g.hand.selected, 1, "and the selection is untouched")
end)

suite.test("a B tap is refused while the hand is being scored", function()
    local g = hand_game(5154)
    g.hand:toggle_selection(g.hand.card_nodes[1])
    g.hand:play_selected()
    T.assert_true(g.hand:is_scoring_active())

    T.assert_false(g:hand_cancel_gesture_available())
    T.assert_false(g:try_gamepad_hand_cancel_tap(), "no re-sorting a hand mid-score")
end)

suite.test("B in a pack does not skip it while cards are picked", function()
    local g = hand_game(5152)
    g.STATE = g.STATES.OPEN_BOOSTER
    g.booster_session = { pack = "arcana", hand_for_tarot = true, opening_phase = "ready", choices = {} }
    T.assert_true(g:is_booster_hand_mode())
    g:set_gamepad_focus_layer("hand")

    T.assert_false(g:handle_gamepad_booster_hand_button("b"), "nothing picked: B falls through to skip")

    g.hand:toggle_selection(g.hand.card_nodes[1])
    T.assert_true(g:handle_gamepad_booster_hand_button("b"), "a selection swallows the press")
    T.assert_eq(#g.hand.selected, 1, "and the release is what drops it")
    T.assert_true(g:try_gamepad_hand_cancel_tap())
    T.assert_eq(#g.hand.selected, 0)
end)

suite.test("the shop puts Buy & Use on Y and the reroll on X", function()
    local g = bootstrap.new_game(5151)
    _G.G = g
    g.STATE = g.STATES.SHOP
    g.money = 40
    g.shop_offer_slots = 3
    g:roll_shop_offers()
    g:sync_shop_offer_nodes()
    g:set_gamepad_shop_focus()

    local rerolled = false
    g.reroll_shop_offers = function() rerolled = true return true end
    T.assert_true(g:handle_gamepad_shop("x"), "X rerolls the shelf")
    T.assert_true(rerolled)

    local bought_use = false
    g.gamepad_shop_buy_use = function() bought_use = true return true end
    T.assert_true(g:handle_gamepad_shop("y"), "Y buys and uses")
    T.assert_true(bought_use)
end)

return suite
