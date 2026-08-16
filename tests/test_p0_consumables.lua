local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()
local game = bootstrap.new_game(888)

suite.test("planet hand increments match the reference table", function()
    T.assert_eq(game.hand_stats[1].chips_per_level, 50, "Flush Five chips")
    T.assert_eq(game.hand_stats[2].mult_per_level, 4, "Flush House mult")
    T.assert_eq(game.hand_stats[4].mult_per_level, 4, "Straight Flush mult")
    T.assert_eq(game.hand_stats[8].mult_per_level, 3, "Straight mult")
end)

suite.test("Strength wraps an Ace to 2", function()
    local data = { rank = 14, suit = "Spades" }
    local node = {
        card_data = data,
        sync_visual_from_card_data = function() end,
    }
    game.hand = {
        ordered_selected_nodes = function() return { node } end,
        clear_selection = function() end,
        layout = function() end,
    }

    game:apply_consumable_effect({ kind = "tarot", id = "tarot_strength" })
    T.assert_eq(data.rank, 2)
end)

suite.test("The Tower removes rank and suit from its Stone Card", function()
    local data = { rank = 12, suit = "Clubs", enhancement = nil }
    local node = setmetatable({
        card_data = data,
        refresh_quads = function() end,
    }, { __index = Card })
    game.hand = {
        ordered_selected_nodes = function() return { node } end,
        clear_selection = function() end,
        layout = function() end,
    }

    game:apply_consumable_effect({ kind = "tarot", id = "tarot_tower" })
    T.assert_eq(data.enhancement, "stone")
    T.assert_nil(data.rank, "The Tower Stone Card has no rank")
    T.assert_nil(data.suit, "The Tower Stone Card has no suit")
end)

suite.test("playing-card editions score through the shared modifier path", function()
    local hand = Hand(game)
    local chips, mult = hand:apply_playing_card_edition(10, 2, { modifier = { edition = "foil" } })
    T.assert_eq(chips, 60, "foil chips")
    T.assert_eq(mult, 2, "foil mult")

    chips, mult = hand:apply_playing_card_edition(10, 2, { modifier = { edition = "holo" } })
    T.assert_eq(chips, 10, "holo chips")
    T.assert_eq(mult, 12, "holo mult")

    chips, mult = hand:apply_playing_card_edition(10, 12, { modifier = { edition = "polychrome" } })
    T.assert_eq(chips, 10, "polychrome chips")
    T.assert_eq(mult, 18, "polychrome applies after existing mult")
end)

suite.test("Observatory multiplies once for every matching held Planet", function()
    game.vouchers = { v_observatory = true }
    game.consumables = {
        { id = "planet_mercury" },
        { id = "planet_mercury" },
    }
    local ctx = { hand_type = "Pair", mult = 4 }
    game:_apply_observatory_voucher_to_hand_scored_ctx(ctx)
    T.assert_eq(ctx.mult, 9)
end)

--- The reference gates consumables on state only for mid-play / mid-deal / mid-tarot
--- (`card.lua:1528`), so a Planet is usable at blind select. Hand-targeting cards stay
--- gated per card, because they need a hand to point at.
suite.test("a Planet is usable at blind select but a targeting Tarot is not", function()
    local g = bootstrap.new_game(2403)
    g.consumables = {
        { id = "planet_pluto", kind = "planet" },
        { id = "tarot_magician", kind = "tarot", select = { exact = 2 } },
    }

    g.STATE = g.STATES.BLIND_SELECT
    T.assert_true(g:consumable_play_state_ok(), "blind select accepts consumables")
    T.assert_true(g:consumable_use_enabled(1), "a Planet needs no hand")
    T.assert_false(g:consumable_use_enabled(2), "a targeting Tarot still needs the play screen")

    g.STATE = g.STATES.SHOP
    T.assert_true(g:consumable_use_enabled(1), "and the shop still works")

    g.STATE = g.STATES.MENU
    T.assert_false(g:consumable_play_state_ok(), "the menu does not")
end)

--- `poll_edition(key, nil, true, true)` (`common_events.lua:2055-2067`) bands the guaranteed
--- tier at Polychrome 15% / Holographic 35% / Foil 50%. The port rolled 1-in-3.
suite.test("guaranteed edition rolls follow the reference bands", function()
    local g = bootstrap.new_game(2401)
    local rolls = {}
    g.random = function(_, key)
        T.assert_eq(key, "aura")
        return table.remove(rolls, 1)
    end

    rolls = { 0.99 }
    T.assert_eq(g:poll_guaranteed_edition("aura"), "polychrome", "the top 15% is Polychrome")
    rolls = { 0.86 }
    T.assert_eq(g:poll_guaranteed_edition("aura"), "polychrome", "just inside the Polychrome band")
    rolls = { 0.84 }
    T.assert_eq(g:poll_guaranteed_edition("aura"), "holo", "the next 35% is Holographic")
    rolls = { 0.51 }
    T.assert_eq(g:poll_guaranteed_edition("aura"), "holo")
    rolls = { 0.49 }
    T.assert_eq(g:poll_guaranteed_edition("aura"), "foil", "the bottom half is Foil")
    rolls = { 0.0 }
    T.assert_eq(g:poll_guaranteed_edition("aura"), "foil")
end)

--- Wheel of Fortune, Hex and Ectoplasm all draw from Jokers that carry no edition
--- (`card.lua:4209-4223`), so the Wheel can never overwrite a Negative.
suite.test("only editionless Jokers are eligible for an edition consumable", function()
    local g = bootstrap.new_game(2402)
    g.jokers = {
        { edition = "negative" },
        { edition = nil },
        { edition = "foil" },
        { edition = "base" },
    }
    local nodes, indices = g:editionless_jokers()
    T.assert_eq(#nodes, 2, "the Negative and Foil Jokers are excluded")
    T.assert_eq(indices[1], 2)
    T.assert_eq(indices[2], 4, "a 'base' edition still counts as editionless")

    g.jokers = { { edition = "polychrome" } }
    T.assert_eq(#g:editionless_jokers(), 0, "a fully editioned row offers no target")
end)

return suite
