--- A debuffed card contributes nothing while it is held, either from its own enhancement or
--- through the jokers that read the hand. The reference gets this from `card.debuff` short-
--- circuiting every getter behind `eval_card`, plus explicit `context.other_card.debuff` checks
--- on Baron and Shoot the Moon (`reference/Balatro/card.lua:3272-3300`).
local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

--- The hand keeps itself sorted, so tests address cards by what they are, not by index.
local function node_of(hand, rank, suit)
    for _, node in ipairs(hand.card_nodes) do
        local cd = node.card_data
        if cd and cd.rank == rank and cd.suit == suit then return node end
    end
    return nil
end

local function hand_with(g, cards)
    local hand = Hand(g)
    g.hand = hand
    for _, cd in ipairs(cards) do
        hand:add_card(cd)
    end
    return hand
end

suite.test("a boss-debuffed card in hand reports itself debuffed", function()
    local g = bootstrap.new_game(4101)
    local hand = hand_with(g, {
        { rank = 13, suit = "Clubs" },
        { rank = 13, suit = "Hearts" },
    })
    T.assert_false(node_of(hand, 13, "Clubs"):is_debuffed(), "no boss, nothing is debuffed")

    g.get_active_boss_blind_id = function() return "bl_club" end
    T.assert_true(node_of(hand, 13, "Clubs"):is_debuffed(), "The Club debuffs the club King")
    T.assert_false(node_of(hand, 13, "Hearts"):is_debuffed(), "and leaves the heart King alone")
end)

suite.test("Smeared Joker widens a suit boss to the other suit of its colour", function()
    local g = bootstrap.new_game(4104)
    local hand = hand_with(g, {
        { rank = 5, suit = "Hearts" },
        { rank = 5, suit = "Diamonds" },
        { rank = 5, suit = "Spades" },
        { rank = 5, suit = "Clubs" },
        { rank = 5, suit = "Clubs", enhancement = "stone" },
    })
    local function debuffed(suit) return node_of(hand, 5, suit):is_debuffed() end

    g.get_active_boss_blind_id = function() return "bl_window" end
    T.assert_true(debuffed("Diamonds"), "The Window debuffs Diamonds")
    T.assert_false(debuffed("Hearts"), "and, without Smeared, not Hearts")

    g:add_joker_by_def("j_smeared")
    T.assert_true(debuffed("Hearts"), "with Smeared, a Heart is a Diamond too")
    T.assert_false(debuffed("Spades"), "black cards stay live")
    T.assert_false(debuffed("Clubs"), "black cards stay live")

    g.get_active_boss_blind_id = function() return "bl_club" end
    T.assert_true(debuffed("Spades"), "The Club takes the Spades with Smeared")
    T.assert_false(debuffed("Hearts"), "and leaves the red cards")
    local stone
    for _, node in ipairs(hand.card_nodes) do
        if node.card_data.enhancement == "stone" then stone = node end
    end
    T.assert_false(stone:is_debuffed(), "a Stone Card has no suit to debuff")
end)

suite.test("a debuffed Steel card pays no held-in-hand mult", function()
    local g = bootstrap.new_game(4102)
    local hand = hand_with(g, { { rank = 13, suit = "Clubs", enhancement = "steel" } })
    local node = node_of(hand, 13, "Clubs")
    _G.Top = { addPopup = function() end }

    local ctx = { chips = 0, mult = 1 }
    T.assert_true(node:emit_hand_event("held_in_hand", ctx), "Steel fires normally")
    T.assert_true(ctx.mult > 1, "and multiplies the mult")

    g.get_active_boss_blind_id = function() return "bl_club" end
    local debuffed_ctx = { chips = 0, mult = 1 }
    T.assert_false(node:emit_hand_event("held_in_hand", debuffed_ctx), "debuffed Steel does not fire")
    T.assert_eq(debuffed_ctx.mult, 1, "and leaves the mult where it was")
end)

--- Play a lone 2 of Spades with two cards of `rank` (one Club, one Heart) held and `joker_id`
--- out, and report the highest mult the scoring sequence reached. The sequence zeroes the
--- running total once it has committed the score, so the peak is what says how many of the held
--- cards the Joker actually saw.
---@param joker_id string
---@param rank integer
---@param boss_id string|nil
---@return number peak mult
local function held_peak_mult(joker_id, rank, boss_id)
    local g = bootstrap.new_game(4103)
    _G.Top = { addPopup = function() end }
    local hand = hand_with(g, {
        { rank = rank, suit = "Clubs" },
        { rank = rank, suit = "Hearts" },
        { rank = 2, suit = "Spades" },
    })
    g:add_joker_by_def(joker_id)
    g.STATE = g.STATES.SELECTING_HAND
    if boss_id then g.get_active_boss_blind_id = function() return boss_id end end

    hand:toggle_selection(node_of(hand, 2, "Spades"))
    hand:play_selected()

    local peak = 0
    for _ = 1, 5000 do
        if not hand._play_sequence then break end
        hand:update(1 / 60)
        peak = math.max(peak, tonumber(g.selectedHandMult) or 0)
    end
    T.assert_nil(hand._play_sequence, "the scoring sequence finished")
    return peak
end

suite.test("Baron skips debuffed Kings held in hand", function()
    T.assert_near(held_peak_mult("j_baron", 13, nil), 2.25, 1e-6, "both Kings feed Baron with no boss out")
    T.assert_near(held_peak_mult("j_baron", 13, "bl_club"), 1.5, 1e-6,
        "The Club's debuffed King pays nothing, so only one X1.5 lands")
end)

suite.test("Shoot the Moon skips debuffed Queens held in hand", function()
    T.assert_near(held_peak_mult("j_shoot_the_moon", 12, nil), 27, 1e-6,
        "both Queens feed Shoot the Moon with no boss out")
    T.assert_near(held_peak_mult("j_shoot_the_moon", 12, "bl_club"), 14, 1e-6,
        "The Club's debuffed Queen pays nothing, so only one +13 lands")
    T.assert_near(held_peak_mult("j_shoot_the_moon", 12, "bl_plant"), 1, 1e-6,
        "The Plant debuffs both Queens")
end)

return suite
