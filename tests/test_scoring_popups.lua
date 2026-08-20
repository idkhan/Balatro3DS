--- Per-effect scoring status text. The reference gives every effect on a played card its own
--- status text (`common_events.lua:779-935`): the rank's chips, the enhancement's chips, a
--- modifier's mult and the edition are four separate announcements. The port added them up and
--- showed one number, so a Bonus card and a plain card of the same rank read identically.
local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

--- Collect the popups a scoring pass raises, in spawn order.
local function with_recorded_popups(fn)
    local spawned = {}
    local real_add = nil
    local g = G
    real_add = g.addPopup
    g.addPopup = function(self, p)
        spawned[#spawned + 1] = { text = p.text, delay = p.delay, colour = p.Color }
        return real_add(self, p)
    end
    local ok, err = pcall(fn, spawned)
    g.addPopup = real_add
    if not ok then error(err, 0) end
    return spawned
end

--- A card node the scoring path can read without a real hand behind it.
local function card_node(card_data)
    return Card(0, 0, 71, 95, card_data, nil, { face_up = true })
end

suite.test("a card's rank and its enhancement are announced separately", function()
    local g = bootstrap.new_game(3300)
    local hand = Hand(g)

    -- A ten carrying a Bonus enhancement: 10 chips from the rank, 30 from the enhancement.
    local node = card_node({ rank = 10, suit = "Hearts", Bonus = 30 })
    local spawned = with_recorded_popups(function()
        hand:accumulate_card_score(0, 1, node, false)
    end)

    T.assert_eq(#spawned, 2, "two effects, two popups")
    T.assert_eq(spawned[1].text, "+10", "the rank's own chips")
    T.assert_eq(spawned[2].text, "+30", "the enhancement's chips")
end)

--- The whole point of the stagger: two popups from the same card centre would otherwise be
--- drawn on the same pixels.
suite.test("effects on one card are staggered rather than stacked", function()
    local g = bootstrap.new_game(3300)
    local hand = Hand(g)

    local node = card_node({ rank = 10, suit = "Hearts", Bonus = 30 })
    local spawned = with_recorded_popups(function()
        hand:accumulate_card_score(0, 1, node, false)
    end)

    T.assert_eq(spawned[1].delay, 0, "the first effect lands immediately")
    T.assert_true(spawned[2].delay > 0, "the second waits its turn")
end)

--- A plain card has exactly one thing to say and must not gain a spurious second popup.
suite.test("a plain card raises a single popup", function()
    local g = bootstrap.new_game(3300)
    local hand = Hand(g)

    local node = card_node({ rank = 7, suit = "Spades" })
    local spawned = with_recorded_popups(function()
        hand:accumulate_card_score(0, 1, node, false)
    end)

    T.assert_eq(#spawned, 1)
    T.assert_eq(spawned[1].text, "+7")
end)

--- The old guard was `mod_mult_bonus > 1`, which silently swallowed a modifier worth exactly
--- one mult.
suite.test("a plus-one mult modifier is announced", function()
    local g = bootstrap.new_game(3300)
    local hand = Hand(g)

    local node = card_node({ rank = 4, suit = "Clubs", mult_bonus = 1 })
    local spawned = with_recorded_popups(function()
        hand:accumulate_card_score(0, 1, node, false)
    end)

    local found = false
    for _, p in ipairs(spawned) do
        if p.text == "+1" then found = true end
    end
    T.assert_true(found, "the +1 mult is on screen")
end)

--- The edition had no status text at all, so a Polychrome card multiplied the mult with
--- nothing to say so.
suite.test("an edition announces itself", function()
    local g = bootstrap.new_game(3300)
    local hand = Hand(g)

    -- The edition hangs off `modifier`, not off the card data directly.
    local node = card_node({ rank = 5, suit = "Hearts", modifier = { edition = "polychrome" } })
    local spawned = with_recorded_popups(function()
        hand:announce_playing_card_edition(node, node.card_data)
    end)

    T.assert_true(#spawned >= 1, "the edition raised a popup")
    local has_x = false
    for _, p in ipairs(spawned) do
        if tostring(p.text):sub(1, 1) == "x" then has_x = true end
    end
    T.assert_true(has_x, "a polychrome card announces its xMult")
end)

--- A neutral edition multiplier is 1 and is not an effect.
suite.test("a base card's edition says nothing", function()
    local g = bootstrap.new_game(3300)
    local hand = Hand(g)

    local node = card_node({ rank = 5, suit = "Hearts" })
    local spawned = with_recorded_popups(function()
        hand:announce_playing_card_edition(node, node.card_data)
    end)

    T.assert_eq(#spawned, 0, "no edition, no popup")
end)

--- Each card restarts the queue; otherwise the fifth card's popups would be four beats late.
suite.test("each card restarts the stagger", function()
    local g = bootstrap.new_game(3300)
    local hand = Hand(g)

    local first = card_node({ rank = 10, suit = "Hearts", Bonus = 30 })
    local second = card_node({ rank = 9, suit = "Spades", Bonus = 20 })
    local spawned = with_recorded_popups(function()
        hand:accumulate_card_score(0, 1, first, false)
        hand:accumulate_card_score(0, 1, second, false)
    end)

    T.assert_eq(#spawned, 4)
    T.assert_eq(spawned[3].delay, 0, "the second card starts from zero again")
end)

--- A delayed popup must get its full hold once it appears, not a hold eaten by the wait.
suite.test("a delayed popup holds for its full duration", function()
    bootstrap.new_game(3300)

    local p = Popup()
    p:spawn(30, "chips", 0, 0, 1, 0.5)
    T.assert_true(p:is_pending(), "it starts out waiting")

    local full = p.duration
    p:update(0.5)
    T.assert_false(p:is_pending(), "the wait is spent")
    T.assert_near(p.time, full, 1e-9, "the hold has not started counting down yet")

    p:update(0.1)
    T.assert_near(p.time, full - 0.1, 1e-9)
end)

--- A single update that overshoots the delay must not lose the excess.
suite.test("a long frame past the delay carries its remainder into the hold", function()
    bootstrap.new_game(3300)

    local p = Popup()
    p:spawn(30, "chips", 0, 0, 1, 0.2)
    local full = p.duration
    p:update(0.3)
    T.assert_false(p:is_pending())
    T.assert_near(p.time, full - 0.1, 1e-9, "the 0.1 s past the delay counted against the hold")
end)

return suite
