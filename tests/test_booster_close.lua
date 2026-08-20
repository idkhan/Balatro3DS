--- Closing a booster pack. The last pick used to end the session on the same frame it fired, so
--- anything it started -- Immolate taking five cards apart, a conversion ripple, the used card
--- flying out -- was cut off, and the preview hand vanished instead of un-dealing.
local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

local function arcana_offer()
    return {
        kind = "booster",
        pack = "arcana",
        size = "normal",
        card_count = 2,
        picks_granted = 1,
    }
end

--- A game sitting in an opened Arcana pack with a preview hand dealt.
local function open_pack(seed)
    local game = bootstrap.new_game(seed)
    game.STATE = game.STATES.SHOP
    game:begin_booster_session(arcana_offer())
    -- Skip the wrapper animation; this file is about what happens on the way out.
    for _ = 1, 200 do
        if game.booster_session.opening_phase == "ready" then break end
        game:_update_booster_opening(0.5)
    end
    return game
end

suite.test("the pack holds open while the last pick's effects play out", function()
    local game = open_pack(6001)
    local sess = game.booster_session
    sess.picks_remaining = 0
    game:begin_booster_close()
    T.assert_true(game._booster_closing ~= nil, "the close is pending")

    -- Something is still coming apart, so the hold does not expire.
    game._dissolving_nodes = { {} }
    game:_update_booster_close(2.0)
    T.assert_eq(game.booster_session, sess, "the pack is still open while cards dissolve")

    game._dissolving_nodes = nil
    game:_update_booster_close(0.1)
    T.assert_nil(game.booster_session, "and closes once the board is quiet")
end)

suite.test("the pack always holds a beat, even with nothing animating", function()
    local game = open_pack(6002)
    local sess = game.booster_session
    sess.picks_remaining = 0
    game:begin_booster_close()

    game:_update_booster_close(0.1)
    T.assert_eq(game.booster_session, sess, "a pick does not read as the pack blinking shut")
    game:_update_booster_close(1.0)
    T.assert_nil(game.booster_session, "the beat passes and it closes")
end)

suite.test("a stuck animation cannot strand the player in a spent pack", function()
    local game = open_pack(6003)
    game.booster_session.picks_remaining = 0
    game:begin_booster_close()
    game._dissolving_nodes = { {} } -- never finishes

    game:_update_booster_close(10)
    T.assert_nil(game.booster_session, "the hold has a ceiling")
end)

suite.test("the pack hand un-deals to the deck instead of vanishing", function()
    local game = open_pack(6004)
    game.booster_session.hand_for_tarot = true
    game.deck = game.deck or Deck(game)
    local hand = Hand(game)
    game.hand = hand
    hand:add_card({ rank = 10, suit = "Spades" })
    hand:add_card({ rank = 4, suit = "Hearts" })
    local nodes = { hand.card_nodes[1], hand.card_nodes[2] }
    local deck_before = #game.deck.cards

    game:end_booster_session()

    T.assert_eq(#game.pending_discard, 2, "both cards are in flight")
    for i, entry in ipairs(game.pending_discard) do
        T.assert_true(entry.target ~= nil, "flight " .. i .. " targets the deck origin")
    end
    T.assert_eq(#hand.card_nodes, 0, "the hand is empty")
    T.assert_eq(#game.deck.cards, deck_before + 2, "and both cards went back to the deck")
    for _, node in ipairs(nodes) do
        T.assert_false(node.selected, "a returning card is not still selected")
    end
end)

return suite
