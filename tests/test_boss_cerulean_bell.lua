--- Cerulean Bell forces one card of the hand to stay selected. The pick has to happen once the
--- deal has landed, not when the refill was queued: the reference picks in `Blind:drawn_to_hand`
--- (`reference/Balatro/blind.lua:574-586`), which runs off the draw event.
local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

local function bell_game()
    local g = bootstrap.new_game(9091)
    g.STATE = g.STATES.SELECTING_HAND
    -- Cerulean Bell is a showdown boss, so it is only legal on a showdown ante (8, 16, ...);
    -- `get_boss_blind_prototype` re-rolls an illegal one out from under the test.
    g.ante = 8
    g.current_blind_index = 3
    g.current_boss_blind_id = "bl_final_bell"
    g.boss_runtime = g.boss_runtime or {}
    -- `bootstrap.new_game` stops short of starting a run, so there is no deck to deal from.
    g.deck = Deck(g)
    g.hand = Hand(g)
    return g
end

--- Drain a queued deal the way `Hand:update` does, without waiting out the beat.
local function land_deal(g)
    g.hand:flush_draw_queue()
end

suite.test("the forced card is picked from the opening hand, not from an empty one", function()
    local g = bell_game()
    T.assert_eq(g:get_active_boss_blind_id(), "bl_final_bell", "the boss is live")

    -- The deal is queued, exactly as `prepare_hand_for_new_blind` leaves it.
    g.hand:fill_from_deck()
    g:boss_on_hand_refilled(true)
    T.assert_eq(g.boss_runtime.forced_card_uid, nil, "nothing to pick from while the deal is queued")

    land_deal(g)

    local uid = g.boss_runtime.forced_card_uid
    T.assert_not_nil(uid, "a card is forced once the hand has landed")
    local forced = g:_boss_find_hand_node_by_uid(uid)
    T.assert_not_nil(forced, "the forced card is in the hand")
    T.assert_true(g.hand:is_selected(forced), "and it is selected for the player")
end)

suite.test("a refill re-picks only when the forced card has left the hand", function()
    local g = bell_game()
    g.hand:fill_from_deck()
    land_deal(g)
    local first = g.boss_runtime.forced_card_uid

    -- A refill that leaves the forced card in place must not move the force onto another card.
    g.hand:fill_from_deck()
    land_deal(g)
    T.assert_eq(g.boss_runtime.forced_card_uid, first, "the force stays put")

    local node = g:_boss_find_hand_node_by_uid(first)
    for i, n in ipairs(g.hand.card_nodes) do
        if n == node then
            g.hand:remove_card_at_index(i)
            break
        end
    end
    g.hand:fill_from_deck()
    land_deal(g)
    local second = g.boss_runtime.forced_card_uid
    T.assert_not_nil(second, "the boss re-picks once its card is gone")
    T.assert_true(second ~= first, "and it picks a card that is actually in the hand")
    T.assert_not_nil(g:_boss_find_hand_node_by_uid(second))
end)

suite.test("no boss, no forced selection", function()
    local g = bell_game()
    -- Big Blind, so `get_boss_blind_id_for_blind` refuses before any boss can be rolled.
    g.current_blind_index = 2
    g.hand:fill_from_deck()
    land_deal(g)
    T.assert_eq(g.boss_runtime.forced_card_uid, nil)
    T.assert_eq(#g.hand.selected, 0, "the hand comes up unselected")
end)

return suite
