local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

bootstrap.load()

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

local function card(suit, enhancement)
    return { card_data = { rank = 2, suit = suit, enhancement = enhancement or "none" } }
end

--------------------------------------------------------------------------------
-- Seeing Double under Smeared Joker
--------------------------------------------------------------------------------

local function seeing_double_mult(game, cards)
    local j = fake_joker("j_seeing_double")
    local ctx = { event_name = "on_hand_scored", cards = cards, mult = 1, VT = j.VT }
    with_popups(function() JokerEffects.get(j).apply_effect(j, ctx) end)
    return ctx.mult
end

suite.test("Seeing Double: a Club with any other suit triggers, with or without Smeared", function()
    local game = bootstrap.new_game(8001)
    local smeared = false
    game.hasJoker = function(_, id) return smeared and id == "j_smeared" end

    for _, other in ipairs({ "Spades", "Hearts", "Diamonds" }) do
        smeared = false
        T.assert_eq(seeing_double_mult(game, { card("Clubs"), card(other) }), 2, "plain Clubs+" .. other)
        smeared = true
        T.assert_eq(seeing_double_mult(game, { card("Clubs"), card(other) }), 2, "smeared Clubs+" .. other)
    end

    smeared = false
    T.assert_eq(seeing_double_mult(game, { card("Hearts"), card("Diamonds") }), 1, "no Club, no trigger")
    T.assert_eq(seeing_double_mult(game, { card("Clubs"), card("Clubs") }), 1, "Clubs alone do not")
    -- Under Smeared a Club is also a Spade, so Clubs alone qualify (the reference counts every
    -- suit a card matches here, unlike Flower Pot).
    smeared = true
    T.assert_eq(seeing_double_mult(game, { card("Clubs"), card("Clubs") }), 2, "smeared Clubs alone")
    T.assert_eq(seeing_double_mult(game, { card("Hearts"), card("Diamonds") }), 1, "smeared reds alone")
    T.assert_eq(seeing_double_mult(game, { card("Hearts"), card("Spades", "wild") }), 2,
        "a Wild fills Clubs first")
end)

--------------------------------------------------------------------------------
-- Run-level fixes
--------------------------------------------------------------------------------

local function run_game(seed, deck)
    local game = bootstrap.new_game(seed)
    game._pending_deck_id = deck or "b_red"
    game._pending_stake_id = "stake_white"
    game:start_run_from_main_menu()
    return game
end

suite.test("The Tooth takes $1 per card played, into debt", function()
    local game = run_game(8002)
    game.STATE = game.STATES.SELECTING_HAND
    game.current_blind_index = 3
    game.current_boss_blind_id = "bl_tooth"
    game.ante = 5 -- The Tooth is not a legal Boss before Ante 3
    game.money = 2
    game:boss_apply_on_hand_submitted({ {}, {}, {}, {}, {} })
    T.assert_eq(game.money, 2, "nothing is taken until the play sequence charges each card")
    T.assert_eq(game:take_tooth_pending(), 5)
    T.assert_eq(game:take_tooth_pending(), 0, "handed over once")

    local popups, sounds, juiced = {}, {}, 0
    local old_add, old_play = game.addPopup, Sfx.play
    game.addPopup = function(_, p) popups[#popups + 1] = p end
    Sfx.play = function(name) sounds[#sounds + 1] = name end
    local card = { VT = { x = 0, y = 0, w = 10, h = 10, scale = 1 }, juice_up = function() juiced = juiced + 1 end }
    local ok, err = pcall(function()
        for _ = 1, 5 do game:boss_tooth_charge_card(card) end
    end)
    game.addPopup, Sfx.play = old_add, old_play
    if not ok then error(err, 0) end
    T.assert_eq(game.money, -3, "into debt, $1 a card")
    T.assert_eq(#popups, 5)
    T.assert_eq(popups[1].text, "-$1")
    T.assert_eq(juiced, 5)
    T.assert_eq(sounds[1], "coin1")
end)

suite.test("Ante 0 and below use a flat 100 base at every stake", function()
    local game = run_game(8003)
    T.assert_eq(game:get_base_requirement_for_ante(0), 100)
    T.assert_eq(game:get_base_requirement_for_ante(-1), 100)
    T.assert_eq(game:get_base_requirement_for_ante(1), 300)
    game._stake_ante_mult = 2
    T.assert_eq(game:get_base_requirement_for_ante(0), 100, "Purple Stake too")
    T.assert_eq(game:get_blind_target(2, 0), 150)
end)

suite.test("Erosion measures against the deck the run started with", function()
    local game = run_game(8004, "b_abandoned")
    T.assert_eq(game.STARTING_DECK_SIZE, game:count_cards_in_full_deck())
    T.assert_true(game.STARTING_DECK_SIZE < 52, "Abandoned Deck has no face cards")
    local j = fake_joker("j_erosion")
    local ctx = { event_name = "on_hand_scored", mult = 0, VT = j.VT }
    with_popups(function() JokerEffects.get(j).apply_effect(j, ctx) end)
    T.assert_eq(ctx.mult, 0, "an untouched deck gives nothing")

    local snap = game:build_run_snapshot()
    local fresh = bootstrap.new_game(8005)
    T.assert_true(fresh:load_run_snapshot(snap))
    T.assert_eq(fresh.STARTING_DECK_SIZE, game.STARTING_DECK_SIZE, "and it survives a save")
end)

suite.test("a card put back in the deck goes to the bottom of the draw pile", function()
    local game = run_game(8006)
    local top = game.deck.cards[#game.deck.cards]
    game.deck:insert_random({ rank = 2, suit = "Hearts", uid = "returned" })
    T.assert_eq(game.deck.cards[1].uid, "returned")
    T.assert_eq(game.deck.cards[#game.deck.cards].uid, top.uid, "the next draw is unchanged")
end)

suite.test("Wheel of Fortune needs an editionless Joker from the shop and packs too", function()
    local game = run_game(8007)
    local wheel = CONSUMABLE_DEFS.tarot_wheel_of_fortune
    game:add_joker_by_def("j_joker", { edition = "foil" })
    T.assert_false(game:pack_consumable_can_apply(wheel), "only an editioned Joker")
    game:add_joker_by_def("j_joker")
    T.assert_true(game:pack_consumable_can_apply(wheel), "a plain one to land on")
end)

suite.test("Sigil and Ouija cannot be spent without a hand", function()
    local game = run_game(8008)
    game.STATE = game.STATES.SHOP
    T.assert_false(game:spectral_hand_requirement_met("spectral_sigil"))
    T.assert_false(game:spectral_hand_requirement_met("spectral_ouija"))
end)

suite.test("a Joker made by an effect rolls an edition like a shop card", function()
    local game = run_game(8009)
    local streams = {}
    game.roll_joker_offer_edition = function(_, append)
        streams[#streams + 1] = append
        return "holo"
    end
    T.assert_true(game:add_created_joker("j_joker", "jud"))
    T.assert_eq(streams[1], "jud")
    T.assert_eq(Joker.normalize_edition(game.jokers[#game.jokers].edition), "holo")
end)

suite.test("dropping a drag releases the node so it can spring home", function()
    local game = run_game(8010)
    local node = { states = { drag = { is = true } }, drag_velocity = { x = 3, y = 4 } }
    game.dragging = node
    game:drop_drag()
    T.assert_nil(game.dragging)
    T.assert_false(node.states.drag.is)
end)

suite.test("a Stone Card given another enhancement shows its own face again", function()
    local game = run_game(8011)
    local card = Card(0, 0, 71, 95, { rank = 14, suit = "Clubs", enhancement = "stone" }, nil,
        { face_up = true })
    card.card_data = { rank = nil, suit = nil, _stone_rank = 14, _stone_suit = "Clubs",
        enhancement = "stone" }
    card.rank_index = 0
    card:set_enhancement("lucky")
    T.assert_eq(card.card_data.rank, 14)
    T.assert_eq(card.rank_index, (14 - 2) + 13, "the Ace of Clubs cell, not the 2 of Hearts")
end)

suite.test("a Boss just beaten is not rerolled once the ante has moved on", function()
    local game = run_game(8012)
    game.ante = 8
    game.current_boss_blind_id = "bl_hook"
    game._last_completed_blind_was_boss = true
    T.assert_eq(game:get_boss_blind_prototype(), game.P_BLINDS.bl_hook)
    T.assert_eq(game.current_boss_blind_id, "bl_hook")
    game._last_completed_blind_was_boss = false
    T.assert_ne(game:get_boss_blind_prototype(), game.P_BLINDS.bl_hook,
        "an ordinary Boss is still replaced on a showdown ante that has not been played")
end)

suite.test("The Fish only turns over the draw after a play", function()
    local game = run_game(8013)
    game.STATE = game.STATES.SELECTING_HAND
    game.current_blind_index = 3
    game.current_boss_blind_id = "bl_fish"
    game.ante = 5
    game:boss_after_discard_or_play("play")
    T.assert_true(game.boss_runtime.fish_face_down_draws > 0)
    game:boss_on_hand_deal_complete()
    T.assert_eq(game.boss_runtime.fish_face_down_draws, 0, "cleared once the draw lands")
    game:boss_after_discard_or_play("play")
    game:boss_after_discard_or_play("discard")
    T.assert_eq(game.boss_runtime.fish_face_down_draws, 0, "a discard never inherits it")
end)

suite.test("the hand that beats the blind is not refilled", function()
    local game = run_game(8014)
    local hand = game.hand
    local fills = 0
    hand.fill_from_deck = function() fills = fills + 1 end
    hand._skip_refill_after_play = true
    hand:_refill_after("play")
    T.assert_eq(fills, 0)
    T.assert_nil(hand._skip_refill_after_play, "and the flag does not linger")
    hand:_refill_after("play")
    T.assert_eq(fills, 1, "the next play refills as normal")

    game.current_blind_target = 300
    game.round_score = 300
    game.hands = 2
    T.assert_true(game:round_ends_after_play(), "the blind is beaten")
    game.round_score = 299
    T.assert_false(game:round_ends_after_play(), "hands left and short of the target")
    game.hands = 0
    T.assert_true(game:round_ends_after_play(), "the last hand draws nothing either")
end)

suite.test("a debuffed held card stays debuffed through the end-of-round pass", function()
    local game = run_game(8015)
    game.STATE = game.STATES.SELECTING_HAND
    game.current_blind_index = 3
    game.current_boss_blind_id = "bl_club"
    local seen
    game.emit_hand_cards_event = function(g, ev)
        if ev == "on_round_end" then
            seen = g:boss_is_card_debuffed_for_scoring({ card_data = { rank = 5, suit = "Clubs" } })
        end
    end
    game._lift_boss_debuffs_after_round_end = true
    game._round_win_joker_payout_lines = {}
    game:_finish_round_win_eval({ add_round_win_payout = function() end }, 0)
    T.assert_true(seen, "The Club still debuffs Clubs while held cards pay out")
    T.assert_true(game.boss_runtime.clear_card_debuffs_after_win, "and lifts after")
end)

suite.test("Mr. Bones on a Boss moves the ante on", function()
    local game = run_game(8016)
    game.STATE = game.STATES.SELECTING_HAND
    game.current_blind_index = 3
    game.current_boss_blind_id = "bl_hook"
    game.ante = 2
    game.current_blind_target = 1000
    game.round_score = 600
    game.hands = 0
    game:add_joker_by_def("j_mr_bones")
    game.current_blind_reward = 5
    game:handle_failed_blind_reset()
    if game._pending_round_win_eval then
        local p = game._pending_round_win_eval
        game._pending_round_win_eval = nil
        game:_finish_round_win_eval(p.ctx, p.hands_left)
    end
    T.assert_eq(game.ante, 3)
    T.assert_true(game._last_completed_blind_was_boss)
    -- A round won in all but the blind's own reward (`evaluate_round`, `saved = true`).
    local first = game._round_win_display_lines[1]
    T.assert_eq(first[1], "Saved by Mr. Bones")
    T.assert_eq(first[2], 0)
    for _, j in ipairs(game.jokers) do
        T.assert_ne(j.def.id, "j_mr_bones", "Mr. Bones is spent")
    end
end)

suite.test("the win screen's Most Played Hand and Seed rows have a coloured stub", function()
    bootstrap.new_game(8017)
    local YouWinUI = require("you_win")
    for _, info in ipairs(YouWinUI.information) do
        T.assert_not_nil(info.color, tostring(info.key) .. " has a stub colour")
    end
end)

return suite
