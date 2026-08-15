--- Where cards come from and where they go.
---
--- The reference puts the deck at the bottom right, level with the hand -- `G.deck.T.y` and
--- `G.hand.T.y` are both `G.TILE_H - 0.95*G.CARD_H`, and `G.deck.T.x` is half a tile in from
--- the right edge (`common_events.lua:22-24`). Its discard pile is off the right of the room
--- and well above that: `G.discard.T.x` works out to roughly 25 tiles across a 20-tile room
--- at `T.y = 4.2` of 11.5 (`:26-27`).
---
--- The port dealt from the top right and discarded to the top left, so both ends of a hand's
--- life pointed at corners with nothing in them.
local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

bootstrap.load()

local SCREEN_W, SCREEN_H = 320, 240

local function fake_card_node(rank, suit)
    return {
        T = { x = 0, y = 0, r = 0, w = 72, h = 95 },
        VT = { x = 0, y = 0, r = 0, w = 72, h = 95 },
        card_data = { rank = rank, suit = suit },
    }
end

--- Where the hand's cards sit, so "level with the hand" can be checked rather than asserted
--- against a copied constant.
local function hand_card_top(g)
    g.hand.card_nodes = { fake_card_node(5, "Hearts") }
    local m = g.hand:_layout_metrics()
    g.hand.card_nodes = {}
    return m.y
end

suite.test("a dealt card comes in from the deck at the bottom right", function()
    local g = bootstrap.new_game(4201)
    g.deck = g.deck or Deck(g)
    g.hand = g.hand or Hand(g)
    local hand_y = hand_card_top(g)

    g.hand:add_card({ rank = 10, suit = "Spades" })
    local node = g.hand.card_nodes[1]
    T.assert_not_nil(node, "the card became a node")

    -- The node starts at the deck and springs to its slot, so the *visible* transform is the
    -- origin on the frame it is created.
    T.assert_true(node.VT.x >= SCREEN_W, "off the right edge, where the deck is")
    T.assert_near(node.VT.y, hand_y, 1e-6, "level with the hand, not above the screen")
end)

suite.test("a discarded card is thrown off to the right, above the hand", function()
    local g = bootstrap.new_game(4202)
    g.deck = g.deck or Deck(g)
    g.hand = g.hand or Hand(g)
    local hand_y = hand_card_top(g)

    local node = fake_card_node(3, "Clubs")
    g.pending_discard = { { node = node, fly_after = 0, percent = 0.5 } }
    g.discard_timer = 0
    g.remove = function() end
    g:update(1 / 60, 1 / 60)

    T.assert_true(node.T.x > SCREEN_W, "off the right edge of the playfield")
    T.assert_true(node.T.y > 0 and node.T.y < hand_y,
        "above the hand, where the reference's discard pile sits")
end)

--- The two destinations must stay distinguishable: an un-deal funnels back into the deck and a
--- discard is thrown at the pile, and the reference puts those in different places.
suite.test("an un-deal goes to the deck, not to the discard pile", function()
    local g = bootstrap.new_game(4203)
    g.deck = g.deck or Deck(g)
    g.hand = g.hand or Hand(g)
    local hand_y = hand_card_top(g)

    g.hand.card_nodes = { fake_card_node(7, "Diamonds") }
    g.hand.cards = { g.hand.card_nodes[1].card_data }
    local flights = g.hand:take_undeal_flights()
    T.assert_eq(#flights, 1)

    local target = flights[1].target
    T.assert_not_nil(target, "an un-deal carries an explicit target")
    T.assert_true(target.x >= SCREEN_W, "the deck is off the right edge")
    T.assert_near(target.y, hand_y, 1e-6, "and level with the hand")

    -- A discard of the same card lands somewhere clearly higher.
    local node = fake_card_node(7, "Diamonds")
    g.pending_discard = { { node = node, fly_after = 0, percent = 0.5 } }
    g.discard_timer = 0
    g.remove = function() end
    g:update(1 / 60, 1 / 60)
    T.assert_true(node.T.y < target.y - 20,
        "the discard pile is well clear of the deck, so the two flights read differently")
end)

suite.test("a discarded card still clears the screen inside its flight budget", function()
    local g = bootstrap.new_game(4204)
    g.deck = g.deck or Deck(g)
    g.hand = g.hand or Hand(g)

    local removed = 0
    local node = fake_card_node(9, "Hearts")
    g.pending_discard = { { node = node, fly_after = 0, percent = 0.5 } }
    g.discard_timer = 0
    g.remove = function() removed = removed + 1 end

    -- The queue drops a card once it arrives or after the flight cap, whichever comes first.
    for _ = 1, 180 do
        g:update(1 / 60, 1 / 60)
        if #g.pending_discard == 0 then break end
    end
    T.assert_eq(#g.pending_discard, 0, "the flight does not linger in the queue")
    T.assert_eq(removed, 1, "and the node is released")
    T.assert_true(node.T.x > SCREEN_W or node.T.y < 0 or node.T.y > SCREEN_H,
        "its destination is off screen")
end)

return suite
