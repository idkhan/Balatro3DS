--- Phase-ordering tests for jokers whose slot in the scoring pipeline is load-bearing.
---
--- The reference evaluates a played hand in fixed phases (`before`, per-card `individual`,
--- `joker_main`, `after`); see `reference/Balatro/functions/state_events.lua:571-1090`.
--- Putting a joker in the wrong phase usually still produces a plausible-looking number,
--- which is exactly why it needs asserting rather than eyeballing.

local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

bootstrap.load()

--- A played-card node with just enough surface for the effect closures.
---@param rank number
---@param enhancement string|nil
---@param scoring boolean|nil defaults to true
---@return table
local function play_node(rank, enhancement, scoring)
    local node
    node = {
        card_data = { rank = rank, suit = "Spades", enhancement = enhancement or "none" },
        counts_for_play_score = scoring ~= false,
        debuffed_for_scoring = false,
        set_enhancement = function(self, e) self.card_data.enhancement = e end,
        juice_up = function() end,
    }
    return node
end

local function fake_joker(id)
    local def = JOKER_DEFS[id]
    return {
        def = def,
        config = def and def.config,
        stored_mult = 0,
        stored_chips = 0,
        stored_xmult = 1,
        runtime_counter = 0,
        VT = { x = 0, y = 0, w = 10, h = 10, scale = 1 },
    }
end

local function with_popups(fn)
    local old = _G.Top
    _G.Top = { addPopup = function() end }
    local ok, err = pcall(fn)
    _G.Top = old
    if not ok then error(err, 0) end
end

--------------------------------------------------------------------------------
-- Midas Mask
--------------------------------------------------------------------------------

suite.test("Midas Mask golds every scoring face card in the before pass, not as each card scores", function()
    bootstrap.new_game(4101)
    local midas = fake_joker("j_midas_mask")
    local eff = JokerEffects.get(midas)

    T.assert_true(eff.matches_trigger(midas, "on_hand_played"),
        "Midas Mask belongs to the before pass (reference card.lua:3442)")
    T.assert_true(not eff.matches_trigger(midas, "card_played"),
        "Midas Mask must not fire again per scored card")

    local king = play_node(13, "bonus")
    local queen = play_node(12)
    local nine = play_node(9)
    local unscored_jack = play_node(11, nil, false)
    local full_hand = { king, queen, nine, unscored_jack }

    with_popups(function()
        eff.apply_effect(midas, { event_name = "on_hand_played", full_hand = full_hand })
    end)

    -- The Bonus is gone before it can pay: this is the whole point of the phase.
    T.assert_eq(king.card_data.enhancement, "gold", "a Bonus King is gold before it scores")
    T.assert_eq(queen.card_data.enhancement, "gold", "a plain Queen is gold")
    T.assert_eq(nine.card_data.enhancement, "none", "a nine is untouched")
    T.assert_eq(unscored_jack.card_data.enhancement, "none",
        "a Jack outside the scoring hand is untouched")
end)

suite.test("a Vampire to Midas Mask's right drains the gold it just applied", function()
    bootstrap.new_game(4102)
    local midas = fake_joker("j_midas_mask")
    local vampire = fake_joker("j_vampire")
    local king = play_node(13)
    local full_hand = { king }
    local ctx = { event_name = "on_hand_played", full_hand = full_hand }

    with_popups(function()
        -- Both are `before` jokers, so they resolve left to right in slot order.
        JokerEffects.get(midas).apply_effect(midas, ctx)
        JokerEffects.get(vampire).apply_effect(vampire, ctx)
    end)

    T.assert_eq(king.card_data.enhancement, "none", "Vampire ate the gold Midas Mask made")
    T.assert_true(vampire.stored_xmult > 0, "Vampire scaled off the drained card")
end)

--------------------------------------------------------------------------------
-- Ice Cream
--------------------------------------------------------------------------------

suite.test("Ice Cream pays in full at joker_main and only melts in the after pass", function()
    bootstrap.new_game(4103)
    local ice = fake_joker("j_ice_cream")
    ice.runtime_counter = 100
    local eff = JokerEffects.get(ice)

    T.assert_true(eff.matches_trigger(ice, "on_hand_scored"), "Ice Cream scores at joker_main")
    T.assert_true(eff.matches_trigger(ice, "on_hand_after"), "Ice Cream melts in the after pass")

    local ctx = { event_name = "on_hand_scored", chips = 0, VT = ice.VT }
    with_popups(function() eff.apply_effect(ice, ctx) end)
    T.assert_eq(ctx.chips, 100, "the full counter is paid this hand")
    T.assert_eq(ice.runtime_counter, 100, "joker_main must not decrement")

    with_popups(function() eff.apply_effect(ice, { event_name = "on_hand_after", VT = ice.VT }) end)
    T.assert_eq(ice.runtime_counter, 95, "the after pass takes the 5")
end)

--------------------------------------------------------------------------------
-- Matador
--------------------------------------------------------------------------------

suite.test("Matador pays once per hand at joker_main, gated on the blind having triggered", function()
    local game = bootstrap.new_game(4104)
    local matador = fake_joker("j_matador")
    local eff = JokerEffects.get(matador)

    T.assert_true(eff.matches_trigger(matador, "on_hand_scored"), "Matador is a joker_main joker")
    T.assert_true(not eff.matches_trigger(matador, "on_boss_effect_triggered"),
        "Matador must not pay per boss trigger")

    local before = tonumber(game.money) or 0
    game.blind_triggered_this_hand = false
    with_popups(function()
        eff.apply_effect(matador, { event_name = "on_hand_scored", VT = matador.VT })
    end)
    T.assert_eq(game.money, before, "no payout when the blind did not trigger")

    game.blind_triggered_this_hand = true
    with_popups(function()
        eff.apply_effect(matador, { event_name = "on_hand_scored", VT = matador.VT })
    end)
    T.assert_eq(game.money, before + 8, "one payout when it did")
end)

--------------------------------------------------------------------------------
-- joker_main card creators
--------------------------------------------------------------------------------

suite.test("Vagabond, Superposition and Seance create their card at joker_main", function()
    bootstrap.new_game(4105)
    for _, id in ipairs({ "j_vagabond", "j_superposition", "j_seance" }) do
        local j = fake_joker(id)
        local eff = JokerEffects.get(j)
        T.assert_true(eff.matches_trigger(j, "on_hand_scored"),
            id .. " reads the run state after the cards have scored")
        T.assert_true(not eff.matches_trigger(j, "on_hand_played"),
            id .. " must not run in the before pass")
    end
end)

--------------------------------------------------------------------------------
-- The discard beat
--------------------------------------------------------------------------------

suite.test("a player discard walks a pre-discard batch then one batch per card", function()
    local game = bootstrap.new_game(4106)
    local hand = game.hand or Hand(game)
    game.hand = hand
    -- The discarded set is built as the cards are pushed to the discard pile.
    game.deck = game.deck or Deck(game)
    for i = 1, 5 do
        hand:add_card({ rank = 2 + i, suit = "Spades", enhancement = "none" }, true)
    end
    T.assert_true(#hand.card_nodes > 2, "the hand was stocked")

    local size_before = #hand.card_nodes
    local picked = { hand.card_nodes[1], hand.card_nodes[2] }
    hand.selected = { picked[1], picked[2] }
    picked[1].selected, picked[2].selected = true, true
    G.discards = 3

    local busy = false
    local batches = {}
    game.begin_joker_emit = function(_, event, ctx)
        batches[#batches + 1] = { event = event, index = ctx.card_index, last = ctx.is_last }
        busy = true
        return true
    end
    game.joker_emit_busy = function() return busy end

    hand:discard_selected()
    T.assert_eq(#batches, 1, "the pre-discard batch runs first")
    T.assert_eq(batches[1].event, "on_pre_discard",
        "Burnt Joker's pass precedes every card (reference state_events.lua:395)")
    T.assert_eq(#hand.card_nodes, size_before, "nothing has left the hand yet")

    -- Each batch drains, then the next one starts.
    busy = false
    hand:update(0.016)
    T.assert_eq(#batches, 2, "the first card's batch follows")
    T.assert_eq(batches[2].event, "on_discard")
    T.assert_eq(batches[2].index, 1, "it carries the first discarded card")
    T.assert_eq(batches[2].last, false, "and knows it is not the last")

    busy = false
    hand:update(0.016)
    T.assert_eq(#batches, 3, "then the second card's batch")
    T.assert_eq(batches[3].index, 2)
    T.assert_eq(batches[3].last, true, "the last card carries the once-per-discard flag")
    T.assert_true(hand._discard_sequence ~= nil, "the pass is still in flight")
    T.assert_eq(#hand.card_nodes, size_before, "and the cards are still in hand")

    -- A second discard must not start on top of one in flight.
    hand.selected = { hand.card_nodes[3] }
    hand:discard_selected()
    T.assert_eq(#batches, 3, "a second discard is refused while a pass is draining")

    busy = false
    hand:update(0.016)
    T.assert_eq(hand._discard_sequence, nil, "the pass finished")
    T.assert_true(#hand.card_nodes < size_before or #hand._draw_queue > 0,
        "the cards left the hand once the pass was done")
end)

suite.test("a play-cleanup discard does not stage anything", function()
    local game = bootstrap.new_game(4107)
    local hand = game.hand or Hand(game)
    game.hand = hand
    game.deck = game.deck or Deck(game)
    hand:add_card({ rank = 5, suit = "Spades", enhancement = "none" }, true)
    hand.selected = { hand.card_nodes[1] }

    local staggered = 0
    game.begin_joker_emit = function() staggered = staggered + 1; return true end
    game.joker_emit_busy = function() return true end

    hand:_discard_selected_impl("play")
    T.assert_eq(staggered, 0,
        "every on_discard joker gates on discard_reason, so play cleanup has nothing to announce")
    T.assert_eq(hand._discard_sequence, nil, "and nothing is left in flight")
end)

suite.test("Green Joker and Faceless fire once per discard, on its last card", function()
    local game = bootstrap.new_game(4108)
    local old_top = _G.Top
    _G.Top = { addPopup = function() end }

    local green = fake_joker("j_green_joker")
    green.stored_mult = 5
    local faceless = fake_joker("j_faceless")
    game.money = 0

    local cards = {
        { rank = 11, suit = "Spades" },
        { rank = 12, suit = "Spades" },
        { rank = 13, suit = "Spades" },
    }
    for i, c in ipairs(cards) do
        local ctx = {
            event_name = "on_discard",
            discard_reason = "discard",
            discarded_cards = cards,
            discarded_nodes = {},
            card = c,
            card_index = i,
            is_last = (i == #cards),
            VT = { x = 0, y = 0, w = 10, h = 10, scale = 1 },
        }
        JokerEffects.get(green).apply_effect(green, ctx)
        JokerEffects.get(faceless).apply_effect(faceless, ctx)
    end

    T.assert_eq(green.stored_mult, 4, "Green Joker loses one Mult for the discard, not one per card")
    T.assert_eq(game.money, 5, "Faceless pays once for three discarded face cards")
    _G.Top = old_top
end)

return suite
