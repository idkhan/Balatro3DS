local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

bootstrap.load()

local function with_popups(fn)
    local old = _G.Top
    _G.Top = { addPopup = function() end }
    local ok, err = pcall(fn)
    _G.Top = old
    if not ok then error(err, 0) end
end

local function fake_joker(id)
    local def = JOKER_DEFS[id]
    return { def = def, config = def and def.config, stored_mult = 0, stored_chips = 0,
        stored_xmult = 1, runtime_counter = 0, VT = { x = 0, y = 0, w = 10, h = 10, scale = 1 } }
end

local function node(rank, suit, enhancement, debuffed)
    return { card_data = { rank = rank, suit = suit, enhancement = enhancement }, face_up = true,
        debuffed_for_scoring = debuffed or nil }
end

--- `Card:is_suit(..., flush_calc)` only treats an undebuffed Wild as every suit
--- (`card.lua:4069`); a suit boss debuffs every Wild, so this decides real hands.
suite.test("a debuffed Wild Card is its printed suit when finding a Flush", function()
    local game = bootstrap.new_game(9101)
    game.jokers = {}
    local function classify(cards)
        local h = Hand(game)
        h.card_nodes, h.selected = {}, {}
        for _, nd in ipairs(cards) do
            h.card_nodes[#h.card_nodes + 1] = nd
            h.selected[#h.selected + 1] = nd
        end
        h:calculate_play()
        return game.handlist[game.selectedHand]
    end
    local hearts = function() return { node(2, "Hearts"), node(5, "Hearts"), node(8, "Hearts"), node(11, "Hearts") } end

    local cards = hearts()
    cards[#cards + 1] = node(13, "Spades", "wild")
    T.assert_eq(classify(cards), "Flush", "a live Wild completes it")

    -- `debuffed` is the card's own flag; `calculate_play` rebuilds the scoring marks itself.
    local function debuffed_wild(suit)
        local nd = node(13, suit, "wild")
        nd.debuffed = true
        return nd
    end
    cards = hearts()
    cards[#cards + 1] = debuffed_wild("Spades")
    T.assert_eq(classify(cards), "High Card", "a debuffed Wild does not")

    cards = hearts()
    cards[#cards + 1] = debuffed_wild("Hearts")
    T.assert_eq(classify(cards), "Flush", "but its own printed suit still counts")
end)

--- Flower Pot reads a normal card with `is_suit(suit, true)` -- debuff ignored -- and a Wild
--- with plain `is_suit`, which a debuffed Wild fails (`card.lua:3816-3827`).
suite.test("Flower Pot counts debuffed cards but not a debuffed Wild", function()
    bootstrap.new_game(9102)
    local function mult(scoring_hand)
        local j = fake_joker("j_flower_pot")
        local ctx = { event_name = "on_hand_scored", cards = {}, scoring_hand = scoring_hand,
            mult = 1, VT = j.VT }
        with_popups(function() JokerEffects.get(j).apply_effect(j, ctx) end)
        return ctx.mult
    end
    T.assert_eq(mult({ node(2, "Hearts"), node(3, "Diamonds"), node(4, "Spades"),
        node(5, "Clubs", nil, true) }), 3, "a Club debuffed by The Club still fills Clubs")
    T.assert_eq(mult({ node(2, "Hearts"), node(3, "Diamonds"), node(4, "Spades"),
        node(5, "Spades", "wild", true) }), 1, "a debuffed Wild fills nothing")
    T.assert_eq(mult({ node(2, "Hearts"), node(3, "Diamonds"), node(4, "Spades"),
        node(5, "Spades", "wild") }), 3, "a live Wild fills the missing suit")
end)

--- `Card:is_face()` answers nothing for a debuffed card (`card.lua:965`).
suite.test("Faceless Joker does not count debuffed face cards", function()
    local game = bootstrap.new_game(9103)
    game.money = 0
    local j = fake_joker("j_faceless")
    local discarded = { { rank = 11 }, { rank = 12 }, { rank = 13 } }
    local nodes = { {}, {}, { debuffed_for_scoring = true } }
    with_popups(function()
        JokerEffects.get(j).apply_effect(j, { event_name = "on_discard", discard_reason = "discard",
            discarded_cards = discarded, discarded_nodes = nodes, is_last = true, VT = j.VT })
    end)
    T.assert_eq(game.money, 0, "two live faces are not three")
    nodes[3] = {}
    with_popups(function()
        JokerEffects.get(j).apply_effect(j, { event_name = "on_discard", discard_reason = "discard",
            discarded_cards = discarded, discarded_nodes = nodes, is_last = true, VT = j.VT })
    end)
    T.assert_true(game.money > 0, "three live faces pay")
end)

--- `poker_hands` comes from every played card (`get_poker_hand_info(G.play.cards)`), so a Pair
--- among a Four Fingers Flush's odd card counts for The Duo.
suite.test("contained hands are read from every played card", function()
    local game = bootstrap.new_game(9104)
    game.jokers = { { def = { id = "j_four_fingers" } } }
    local h = Hand(game)
    local played = { node(2, "Hearts"), node(5, "Hearts"), node(8, "Hearts"), node(11, "Hearts"),
        node(2, "Spades") }
    local contained = h:build_contained_hand_types(played)
    T.assert_true(contained["Pair"], "the odd Spade pairs a Heart")
    T.assert_true(contained["Flush"])
end)

--- Hanging Chad repeats `scoring_hand[1]`, which can be a debuffed card (`card.lua:3353`).
suite.test("Hanging Chad's retriggers stay on a debuffed first card", function()
    bootstrap.new_game(9105)
    local j = fake_joker("j_hanging_chad")
    local eff = JokerEffects.get(j)
    local first, second = node(5, "Clubs", nil, true), node(9, "Hearts")
    second.counts_for_play_score = true
    local played = { first, second }
    T.assert_eq(eff.query_retrigger(j, { card_node = second, played_cards = played }), 0,
        "the second card is not promoted")
    T.assert_true(eff.query_retrigger(j, { card_node = first, played_cards = played }) > 0)
end)

--------------------------------------------------------------------------------
-- Joker unlocks (`check_for_unlock`, common_events.lua:1163-1626)
--------------------------------------------------------------------------------

local function unlock_game(seed)
    local game = bootstrap.new_game(seed)
    game._pending_deck_id = "b_red"
    game._pending_stake_id = "stake_white"
    game:start_run_from_main_menu()
    -- `evaluate` skips anything already earned; ask as a fresh profile would.
    game.is_joker_unlocked = function() return false end
    return game
end

suite.test("Shoot the Moon unlocks when the Hearts left are the ones being played", function()
    local game = unlock_game(9106)
    local hearts = {}
    for r = 2, 6 do hearts[#hearts + 1] = { rank = r, suit = "Hearts" } end
    game.deck.cards = { { rank = 2, suit = "Spades" } }
    -- Hearts already discarded or played are gone, not held back.
    game.deck.discard_pile = { { rank = 9, suit = "Hearts" } }
    game.hand.cards = hearts
    game.hand._draw_queue = {}
    T.assert_eq(JokerUnlocks.evaluate(game, "play_all_hearts", { played = hearts })[1], "j_shoot_the_moon")
    game.deck.cards[#game.deck.cards + 1] = { rank = 4, suit = "Hearts" }
    T.assert_nil(JokerUnlocks.evaluate(game, "play_all_hearts", { played = hearts })[1],
        "a Heart still in the draw pile holds it back")
end)

suite.test("Invisible Joker's unlock reads the most Jokers held, not the slots", function()
    local game = unlock_game(9107)
    for _ = 1, 4 do game:add_joker_by_def("j_joker") end
    T.assert_eq(game.run_max_jokers, 4)
    T.assert_true(JokerUnlocks.evaluate(game, "win_custom")[1] ~= nil)
    local found = false
    for _, id in ipairs(JokerUnlocks.evaluate(game, "win_custom")) do
        if id == "j_invisible" then found = true end
    end
    T.assert_true(found, "four held, five slots: unlocked")
    game:add_joker_by_def("j_joker")
    game:remove_owned_joker_at(5, true)
    for _, id in ipairs(JokerUnlocks.evaluate(game, "win_custom")) do
        T.assert_ne(id, "j_invisible", "five held once this run is too many, even after selling")
    end
end)

suite.test("Seeing Double's unlock counts 7s the way is_suit('Clubs') does", function()
    local game = unlock_game(9108)
    local function sevens(suit, enhancement)
        local out = {}
        for i = 1, 4 do
            out[i] = { card_data = { rank = 7, suit = suit, enhancement = enhancement } }
        end
        return out
    end
    local function unlocks(cards)
        for _, id in ipairs(JokerUnlocks.evaluate(game, "hand_contents", { cards = cards })) do
            if id == "j_seeing_double" then return true end
        end
        return false
    end
    T.assert_true(unlocks(sevens("Clubs")))
    T.assert_true(unlocks(sevens("Hearts", "wild")), "Wild 7s are Clubs")
    T.assert_false(unlocks(sevens("Spades")))
    game.hasJoker = function(_, id) return id == "j_smeared" end
    T.assert_true(unlocks(sevens("Spades")), "Smeared Spade 7s are Clubs")
    game.hasJoker = function() return false end
    local debuffed = sevens("Clubs")
    debuffed[1].is_debuffed = function() return true end
    T.assert_false(unlocks(debuffed), "a debuffed 7 does not count")
end)

suite.test("suit-count unlocks count a Stone Card by its printed suit", function()
    local game = unlock_game(9109)
    game.deck.cards, game.deck.discard_pile, game.hand.cards = {}, {}, {}
    for i = 1, 29 do game.deck.cards[i] = { rank = 2, suit = "Spades" } end
    game.deck.cards[30] = { enhancement = "stone", _stone_suit = "Spades" }
    local ids = JokerUnlocks.evaluate(game, "modify_deck")
    local found = false
    for _, id in ipairs(ids) do if id == "j_arrowhead" then found = true end end
    T.assert_true(found, "the Stone Spade is the thirtieth")
end)

suite.test("ante unlocks match the ante exactly", function()
    local game = unlock_game(9110)
    local function ring_master(ante)
        for _, id in ipairs(JokerUnlocks.evaluate(game, "ante_up", { ante = ante })) do
            if id == "j_ring_master" then return true end
        end
        return false
    end
    T.assert_true(ring_master(4))
    T.assert_false(ring_master(5))
end)

--- A fresh Joker shows the reference's starting value before it has ever triggered: in the
--- shop, a pack or the collection (`game.lua:470`, Popcorn `config = {mult = 20}`).
suite.test("a new Popcorn reads +20 Mult, and Erosion reads +0 with no run deck", function()
    local game = bootstrap.new_game(9111)
    local popcorn = Joker(0, 0, nil, nil, JOKER_DEFS.j_popcorn, {})
    T.assert_eq(popcorn.stored_mult, 20)
    T.assert_true(tostring(popcorn:get_live_current_tooltip_text()):find("20", 1, true) ~= nil)

    game.deck = nil
    local erosion = Joker(0, 0, nil, nil, JOKER_DEFS.j_erosion, {})
    T.assert_true(tostring(erosion:get_live_current_tooltip_text()):find("+0", 1, true) ~= nil)
end)

--- Popcorn still loses 4 a round from its starting 20, and a save from before the fix (which
--- started at 0) is repaired rather than eaten.
suite.test("Popcorn decays from 20 and repairs an old zeroed save", function()
    bootstrap.new_game(9112)
    local j = Joker(0, 0, nil, nil, JOKER_DEFS.j_popcorn, {})
    local eff = JokerEffects.get(j)
    with_popups(function() eff.apply_effect(j, { event_name = "on_round_end", VT = j.VT }) end)
    T.assert_eq(j.stored_mult, 16)

    local old = Joker(0, 0, nil, nil, JOKER_DEFS.j_popcorn, {})
    old.stored_mult, old.runtime_counter = 0, 0
    with_popups(function() eff.apply_effect(old, { event_name = "on_hand_scored", mult = 0, VT = old.VT }) end)
    T.assert_eq(old.stored_mult, 20)
end)

return suite
