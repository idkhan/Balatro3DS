--- Collection discovery.
---
--- Seals and editions were reported as discovered unconditionally, which both hid the
--- reveal and inflated the collection percentage that feeds the deck unlock thresholds.
--- The discovery data was already being recorded — the collection just ignored it.
local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

bootstrap.load()
local CollectionCatalog = require("collection_catalog")

suite.test("a seal is undiscovered until a card carrying it is seen", function()
    local g = bootstrap.new_game(5101)
    g.Discovered = {}

    local entry = { category = "seals", id = "seal_gold", discovery_id = "seal_gold" }
    T.assert_false(CollectionCatalog.is_entry_discovered(g, entry),
        "an unseen seal must not fill its slot")

    g:discover_card_properties({ rank = 5, suit = "Hearts", seal = "gold" })
    T.assert_true(CollectionCatalog.is_entry_discovered(g, entry), "seeing one reveals it")

    local unseen = { category = "seals", id = "seal_red", discovery_id = "seal_red" }
    T.assert_false(CollectionCatalog.is_entry_discovered(g, unseen), "and only that one")
end)

--- A playing card's edition hangs off `card_data.modifier`, not the top level, so reading
--- only `card_data.edition` meant a Foil card never registered at all.
suite.test("a playing card's edition is discovered from its modifier table", function()
    local g = bootstrap.new_game(5102)
    g.Discovered = {}

    local foil = { category = "editions", id = "edition_foil", discovery_id = "edition_foil" }
    T.assert_false(CollectionCatalog.is_entry_discovered(g, foil))

    g:discover_card_properties({ rank = 7, suit = "Clubs", modifier = { edition = "foil" } })
    T.assert_true(CollectionCatalog.is_entry_discovered(g, foil))
end)

--- `normalize_edition` answers "base" for an ordinary Joker; that is not an edition and
--- must not occupy a collection slot.
suite.test("an ordinary card does not discover a base edition", function()
    local g = bootstrap.new_game(5103)
    g.Discovered = {}
    g:discover_card_properties({ rank = 3, suit = "Spades" })
    T.assert_false(g:is_discovered("edition_base"), "there is no such edition to find")

    local enhanced = { category = "enhanced", id = "enhancement_gold", discovery_id = "enhancement_gold" }
    g:discover_card_properties({ rank = 3, suit = "Spades", enhancement = "gold" })
    T.assert_true(CollectionCatalog.is_entry_discovered(g, enhanced),
        "enhancements still record as they always did")
end)

--- Hex, Wheel of Fortune, Ectoplasm and Aura stamp an edition onto a Joker or card that
--- already exists, so neither `add_joker` nor `Hand:add_card` ever sees it. Polychrome is
--- the one players hit: it is the rarest shop roll, so Hex and the Wheel are usually
--- where it first turns up, and it stayed locked in the collection either way.
local function editionless_joker(game)
    game.jokers = {}
    T.assert_true(game:add_joker_by_def("j_joker"), "a plain Joker to modify")
    return game.jokers[1]
end

suite.test("Hex discovers the Polychrome it applies", function()
    local g = bootstrap.new_game(5104)
    editionless_joker(g)
    g.Discovered = {}

    g:apply_consumable_effect({ kind = "spectral", id = "spectral_hex" })

    T.assert_eq(Joker.normalize_edition(g.jokers[1].edition), "polychrome", "Hex applied")
    T.assert_true(g:is_discovered("edition_polychrome"), "and the collection heard about it")
end)

suite.test("Ectoplasm discovers the Negative it applies", function()
    local g = bootstrap.new_game(5105)
    editionless_joker(g)
    g.Discovered = {}

    g:apply_consumable_effect({ kind = "spectral", id = "spectral_ectoplasm" })

    T.assert_eq(Joker.normalize_edition(g.jokers[1].edition), "negative", "Ectoplasm applied")
    T.assert_true(g:is_discovered("edition_negative"))
end)

suite.test("Aura discovers the edition it applies to a card in hand", function()
    local g = bootstrap.new_game(5106)
    local data = { rank = 10, suit = "Hearts" }
    g.hand = {
        ordered_selected_nodes = function()
            return { { card_data = data, sync_visual_from_card_data = function() end } }
        end,
        clear_selection = function() end,
        layout = function() end,
    }
    g.Discovered = {}

    g:apply_consumable_effect({ kind = "spectral", id = "spectral_aura" })

    local applied = data.modifier and data.modifier.edition
    T.assert_not_nil(applied, "Aura applied an edition")
    T.assert_true(g:is_discovered("edition_" .. applied),
        "the card is already in hand, so nothing re-adds it later")
end)

suite.test("the Wheel discovers the edition it lands", function()
    local g = bootstrap.new_game(5108)
    local j = editionless_joker(g)
    g.Discovered = {}
    -- The Wheel is a 1-in-4; force the hit so the test is about discovery, not the roll.
    g.do_random = function() return true end

    g:apply_consumable_effect({ kind = "tarot", id = "tarot_wheel_of_fortune" })

    local applied = Joker.normalize_edition(j.edition)
    T.assert_true(applied ~= "base", "the Wheel landed an edition")
    T.assert_true(g:is_discovered("edition_" .. applied))
end)

suite.test("discover_edition ignores the absence of an edition", function()
    local g = bootstrap.new_game(5107)
    g.Discovered = {}
    g:discover_edition(nil)
    g:discover_edition("")
    g:discover_edition("base")
    T.assert_false(g:is_discovered("edition_base"), "base is not an edition")
    T.assert_eq(next(g.Discovered), nil, "and nothing else was recorded")
end)

return suite
