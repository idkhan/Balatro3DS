--- Deck view: the full deck, the Remaining/Full modes, the tallies, and the voucher page.
---
--- The view used to build from the draw pile alone, so a card you had just enhanced vanished
--- from it, there was no way to count suits for a flush, and a redeemed voucher was a bare
--- sprite on the non-touch screen. The reference lists the whole deck and greys what is no
--- longer drawable (`UI_definitions.lua:3260-3266`), shows suit/face/ace tallies beside the
--- ranks (`:3390-3420`), and keeps a Vouchers tab on its run-info screen (`:3426`).
local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

bootstrap.load()
local DeckViewUI = require("deck_view_ui")

local function game_with_deck()
    local g = bootstrap.new_game(8101)
    g.deck = Deck(g)
    g.deck.cards = {
        { rank = 2, suit = "Hearts" },
        { rank = 5, suit = "Hearts" },
        { rank = 14, suit = "Spades" },
    }
    g.deck.discard_pile = {
        { rank = 11, suit = "Clubs" },
    }
    g.hand = Hand(g)
    g.hand.cards = { { rank = 7, suit = "Diamonds" } }
    return g
end

suite.test("the view lists every card in the run, not just the draw pile", function()
    local g = game_with_deck()
    local entries = DeckViewUI.collect_run_cards(g)
    T.assert_eq(#entries, 5, "3 drawable + 1 discarded + 1 in hand")

    local drawable = 0
    for _, e in ipairs(entries) do if e.in_draw then drawable = drawable + 1 end end
    T.assert_eq(drawable, 3, "only the draw pile counts as drawable")
end)

suite.test("Remaining greys spent cards; Full Deck greys nothing", function()
    local g = game_with_deck()
    DeckViewUI.build(g)
    T.assert_eq(#g._deck_view_nodes, 5, "a node per card in the run")

    T.assert_eq(DeckViewUI.mode(g), "remaining", "Remaining is the default")
    DeckViewUI.draw_bottom(g)
    local greyed = 0
    for _, n in ipairs(g._deck_view_nodes) do if n.greyed then greyed = greyed + 1 end end
    T.assert_eq(greyed, 2, "the discarded card and the one in hand are greyed")

    DeckViewUI.toggle_mode(g)
    T.assert_eq(DeckViewUI.mode(g), "full")
    DeckViewUI.draw_bottom(g)
    for _, n in ipairs(g._deck_view_nodes) do
        T.assert_eq(n.greyed, nil, "Full Deck greys nothing")
    end

    DeckViewUI.destroy(g)
end)

suite.test("tallies count suits, faces, aces and numbered cards", function()
    local g = game_with_deck()

    -- Remaining: the draw pile only.
    local t = DeckViewUI.count_tallies(DeckViewUI.tally_source(g))
    T.assert_eq(t.suits.Hearts, 2)
    T.assert_eq(t.suits.Spades, 1)
    T.assert_eq(t.suits.Clubs, 0, "the discarded Jack is not drawable")
    T.assert_eq(t.ace, 1)
    T.assert_eq(t.numbered, 2)
    T.assert_eq(t.face, 0)

    -- Full Deck: everything.
    g._deck_view_mode = "full"
    t = DeckViewUI.count_tallies(DeckViewUI.tally_source(g))
    T.assert_eq(t.suits.Clubs, 1, "the discarded Jack counts here")
    T.assert_eq(t.suits.Diamonds, 1, "so does the card in hand")
    T.assert_eq(t.face, 1)
    T.assert_eq(t.total, 5)
end)

--- Stone cards have no rank or suit, so the reference leaves them out of every tally
--- (`UI_definitions.lua:3363`).
suite.test("stone cards are excluded from the tallies", function()
    local t = DeckViewUI.count_tallies({
        { rank = 5, suit = "Hearts" },
        { rank = 9, suit = "Hearts", enhancement = "stone" },
    })
    T.assert_eq(t.suits.Hearts, 1)
    T.assert_eq(t.total, 1)
end)

suite.test("the header toggles between tallies and per-rank counts", function()
    local g = game_with_deck()
    DeckViewUI.build(g)
    DeckViewUI.draw_bottom(g)

    T.assert_not_nil(g._deck_view_mode_rect, "the mode button has a rect")
    T.assert_not_nil(g._deck_view_tally_rect, "so does the tally strip")
    T.assert_false(g._deck_view_show_ranks == true, "tallies show first")

    local r = g._deck_view_tally_rect
    T.assert_true(DeckViewUI.handle_header_touch(g, r.x + r.w * 0.5, r.y + r.h * 0.5))
    T.assert_true(g._deck_view_show_ranks, "tapping the strip reveals the ranks")
    T.assert_true(DeckViewUI.handle_header_touch(g, r.x + r.w * 0.5, r.y + r.h * 0.5))
    T.assert_false(g._deck_view_show_ranks, "and tapping again puts them back")

    -- The mode button is its own target.
    local mr = g._deck_view_mode_rect
    T.assert_true(DeckViewUI.handle_header_touch(g, mr.x + mr.w * 0.5, mr.y + mr.h * 0.5))
    T.assert_eq(DeckViewUI.mode(g), "full")

    DeckViewUI.destroy(g)
end)

suite.test("the voucher page lists what has been redeemed", function()
    local g = game_with_deck()
    g.vouchers = { "v_overstock" }

    local owned = DeckViewUI.owned_vouchers(g)
    T.assert_eq(#owned, 1)
    T.assert_eq(owned[1].id, "v_overstock")
    T.assert_true(owned[1].description ~= "", "the description is what the page is for")

    -- The set-keyed shape is also in use around the codebase.
    g.vouchers = { v_overstock = true }
    T.assert_eq(#DeckViewUI.owned_vouchers(g), 1, "a set of ids works too")

    -- Unknown ids are dropped rather than rendered as blanks.
    g.vouchers = { "v_not_a_real_voucher" }
    T.assert_eq(#DeckViewUI.owned_vouchers(g), 0)
end)

suite.test("the footer switches to the voucher page and hides the cards", function()
    local g = game_with_deck()
    g.vouchers = { "v_overstock" }
    DeckViewUI.build(g)
    DeckViewUI.draw_bottom(g)

    T.assert_eq(DeckViewUI.page(g), "deck", "the deck shows first")
    local pr = g._deck_view_page_rect
    T.assert_not_nil(pr, "the page switch has a rect")

    T.assert_true(DeckViewUI.handle_header_touch(g, pr.x + pr.w * 0.5, pr.y + pr.h * 0.5))
    T.assert_eq(DeckViewUI.page(g), "vouchers")

    DeckViewUI.draw_bottom(g)
    for _, n in ipairs(g._deck_view_nodes) do
        T.assert_false(n.states.visible, "cards are hidden behind the voucher page")
    end

    -- The deck-only controls do not respond while the voucher page is up.
    local mr = g._deck_view_mode_rect
    T.assert_false(DeckViewUI.handle_header_touch(g, mr.x + mr.w * 0.5, mr.y + mr.h * 0.5))
    T.assert_eq(DeckViewUI.mode(g), "remaining", "the mode was not flipped")

    DeckViewUI.destroy(g)
end)

return suite
