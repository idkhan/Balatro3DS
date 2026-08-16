--- Joker unlock progression.
---
--- The catalog carried `unlocked = false` on 45 Jokers and nothing read it, so every Joker
--- was available from run one. Conditions are transcribed from the reference's
--- `unlock_condition` fields; evaluators follow `check_for_unlock`
--- (`reference/Balatro/functions/common_events.lua:1163-1620`).
local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

--- A game with a clean, unearned profile.
local function fresh(seed)
    local g = bootstrap.new_game(seed)
    g.joker_unlocks = {}
    g.career_stats = g:build_career_stats()
    g.seeded = false
    g.challenge_id = nil
    return g
end

--- Every Joker the catalog locks must be reachable somehow: either it carries a condition,
--- or it is a Legendary, which the pool filter exempts because only The Soul spawns one.
--- The reference marks those five `hidden = true` with no condition, for the same reason.
suite.test("every locked catalog Joker is reachable", function()
    bootstrap.load()
    local locked, unreachable, exempt = 0, {}, 0
    for id, def in pairs(JOKER_DEFS) do
        if def and def.unlocked == false then
            locked = locked + 1
            if JokerUnlocks.is_exempt(def) then
                exempt = exempt + 1
            elseif not JokerUnlocks.condition_for(id) then
                unreachable[#unreachable + 1] = id
            end
        end
    end
    T.assert_eq(locked, 45, "the catalog's locked set")
    T.assert_eq(exempt, 5, "the five Legendaries")
    T.assert_eq(#unreachable, 0, "unreachable Jokers: " .. table.concat(unreachable, ", "))

    -- And no condition may name a Joker the catalog does not lock, which would be a typo
    -- that silently gates nothing.
    for id in pairs(JokerUnlocks.CONDITIONS) do
        T.assert_not_nil(JOKER_DEFS[id], "condition names an unknown Joker: " .. id)
        T.assert_eq(JOKER_DEFS[id].unlocked, false, id .. " has a condition but is not locked")
    end
end)

suite.test("a locked Joker is out of the pool until it is earned", function()
    local g = fresh(6101)
    T.assert_false(g:is_joker_unlocked("j_acrobat"))
    T.assert_false(g:joker_allowed_in_random_pool("j_acrobat"), "locked Jokers cannot be rolled")
    T.assert_true(g:joker_allowed_in_random_pool("j_joker"), "unconditional Jokers are unaffected")

    g:add_career_stat("c_hands_played", 199)
    g:check_unlock("career_stat")
    T.assert_false(g:is_joker_unlocked("j_acrobat"), "199 hands is not 200")

    g:add_career_stat("c_hands_played", 1)
    local earned = g:check_unlock("career_stat")
    T.assert_eq(earned[1], "j_acrobat")
    T.assert_true(g:is_joker_unlocked("j_acrobat"))
    T.assert_true(g:joker_allowed_in_random_pool("j_acrobat"), "and it joins the pool")
    T.assert_true(g:is_discovered("j_acrobat"), "an earned Joker is no longer a silhouette")
end)

--- `get_current_pool` exempts rarity 4 (`common_events.lua:1987`): a Legendary is only ever
--- spawned by The Soul, never rolled, so the unlock filter must not touch it.
suite.test("Legendaries bypass the unlock filter", function()
    local g = fresh(6102)
    for _, id in ipairs({ "j_perkeo", "j_canio", "j_chicot", "j_triboulet", "j_yorick" }) do
        T.assert_eq(tonumber(JOKER_DEFS[id].rarity), 4, id .. " should be Legendary")
        T.assert_true(g:joker_allowed_in_random_pool(id), id .. " must stay reachable")
    end
end)

--- `check_for_unlock` refuses to grant anything on a seeded or challenge run
--- (`common_events.lua:1165-1177`).
suite.test("seeded and challenge runs earn nothing", function()
    local g = fresh(6103)
    g:add_career_stat("c_cards_sold", 100)

    g.seeded = true
    g:check_unlock("career_stat")
    T.assert_false(g:is_joker_unlocked("j_burnt"), "a seeded run cannot earn unlocks")

    g.seeded = false
    g.challenge_id = "c_some_challenge"
    g:check_unlock("career_stat")
    T.assert_false(g:is_joker_unlocked("j_burnt"), "nor can a challenge run")

    g.challenge_id = nil
    g:check_unlock("career_stat")
    T.assert_true(g:is_joker_unlocked("j_burnt"), "an ordinary run does")
end)

suite.test("deck composition unlocks count the whole run's cards", function()
    local g = fresh(6104)
    g.deck = Deck(g)
    g:check_unlock("modify_deck")
    T.assert_false(g:is_joker_unlocked("j_arrowhead"), "a starting deck has only 13 Spades")

    for _ = 1, 17 do table.insert(g.deck.cards, { rank = 5, suit = "Spades" }) end
    g:check_unlock("modify_deck")
    T.assert_true(g:is_joker_unlocked("j_arrowhead"), "30 Spades earns Arrowhead")
    T.assert_false(g:is_joker_unlocked("j_bloodstone"), "and only Arrowhead")

    -- The discard pile and hand count too, not just the draw pile.
    local g2 = fresh(6105)
    g2.deck = Deck(g2)
    g2.deck.cards = {}
    for _ = 1, 30 do table.insert(g2.deck.discard_pile, { rank = 5, suit = "Hearts" }) end
    g2:check_unlock("modify_deck")
    T.assert_true(g2:is_joker_unlocked("j_bloodstone"), "cards in the discard pile still count")
end)

suite.test("enhancement tallies drive Glass, Smeared and Driver's License", function()
    local g = fresh(6106)
    g.deck = Deck(g)
    g.deck.cards = {}
    for _ = 1, 5 do table.insert(g.deck.cards, { rank = 5, suit = "Hearts", enhancement = "glass" }) end
    g:check_unlock("modify_deck")
    T.assert_true(g:is_joker_unlocked("j_glass"), "5 Glass Cards")
    T.assert_false(g:is_joker_unlocked("j_smeared"), "Wild Cards are a different tally")

    for _ = 1, 3 do table.insert(g.deck.cards, { rank = 5, suit = "Hearts", enhancement = "wild" }) end
    g:check_unlock("modify_deck")
    T.assert_true(g:is_joker_unlocked("j_smeared"), "3 Wild Cards")

    -- Driver's License counts any enhancement, so the eight above are already a third of it.
    for _ = 1, 8 do table.insert(g.deck.cards, { rank = 5, suit = "Clubs", enhancement = "steel" }) end
    g:check_unlock("modify_deck")
    T.assert_true(g:is_joker_unlocked("j_drivers_license"), "16 enhanced cards of any kind")
end)

suite.test("hand and discard contents unlock their Jokers", function()
    local g = fresh(6107)

    g:check_unlock("hand_contents", { cards = {
        { rank = 7, suit = "Clubs" }, { rank = 7, suit = "Clubs" },
        { rank = 7, suit = "Clubs" }, { rank = 7, suit = "Hearts" },
    } })
    T.assert_false(g:is_joker_unlocked("j_seeing_double"), "three Clubs sevens is not four")

    g:check_unlock("hand_contents", { cards = {
        { rank = 7, suit = "Clubs" }, { rank = 7, suit = "Clubs" },
        { rank = 7, suit = "Clubs" }, { rank = 7, suit = "Clubs" },
    } })
    T.assert_true(g:is_joker_unlocked("j_seeing_double"))

    local gold = {}
    for _ = 1, 5 do gold[#gold + 1] = { rank = 4, suit = "Spades", enhancement = "gold" } end
    g:check_unlock("hand_contents", { cards = gold })
    T.assert_true(g:is_joker_unlocked("j_ticket"), "five Gold Cards played")

    local jacks = {}
    for _ = 1, 5 do jacks[#jacks + 1] = { rank = 11, suit = "Spades" } end
    g:check_unlock("discard_custom", { cards = jacks })
    T.assert_true(g:is_joker_unlocked("j_hit_the_road"), "five Jacks discarded")
end)

suite.test("ante, money and chip-score thresholds each unlock their own Joker", function()
    local g = fresh(6108)

    g:check_unlock("ante_up", { ante = 4 })
    T.assert_true(g:is_joker_unlocked("j_ring_master"), "ante 4")
    T.assert_false(g:is_joker_unlocked("j_flower_pot"), "ante 8 is still ahead")
    g:check_unlock("ante_up", { ante = 8 })
    T.assert_true(g:is_joker_unlocked("j_flower_pot"))

    g.money = 399
    g:check_unlock("money")
    T.assert_false(g:is_joker_unlocked("j_satellite"))
    g.money = 400
    g:check_unlock("money")
    T.assert_true(g:is_joker_unlocked("j_satellite"))

    g:check_unlock("chip_score", { chips = 9999 })
    T.assert_false(g:is_joker_unlocked("j_oops"))
    g:check_unlock("chip_score", { chips = 10000 })
    T.assert_true(g:is_joker_unlocked("j_oops"))
    T.assert_false(g:is_joker_unlocked("j_idol"), "the million-chip tier is separate")
end)

suite.test("win conditions read the finished run", function()
    local g = fresh(6109)
    g.hand_play_counts = {}

    g:check_unlock("win", { rounds = 20 })
    T.assert_false(g:is_joker_unlocked("j_wee"), "20 rounds is slower than Wee Joker's 18")
    g:check_unlock("win", { rounds = 12 })
    T.assert_true(g:is_joker_unlocked("j_wee"))
    T.assert_true(g:is_joker_unlocked("j_merry_andy"), "12 rounds clears both tiers")

    -- win_no_hand: a hand type never played across the run.
    local pair_idx
    for i, name in ipairs(g.handlist) do if name == "Pair" then pair_idx = i end end
    g.hand_play_counts[pair_idx] = 3
    g:check_unlock("win_no_hand")
    T.assert_false(g:is_joker_unlocked("j_duo"), "Pairs were played")
    T.assert_true(g:is_joker_unlocked("j_trio"), "Three of a Kind never was")
end)

suite.test("round-win rules distinguish Matador, Hanging Chad and Troubadour", function()
    local g = fresh(6110)

    g:check_unlock("round_win", { is_boss_blind = false, hands_played = 1, discards_used = 0 })
    T.assert_false(g:is_joker_unlocked("j_matador"), "Matador wants a Boss blind")

    g:check_unlock("round_win", { is_boss_blind = true, hands_played = 1, discards_used = 2 })
    T.assert_false(g:is_joker_unlocked("j_matador"), "and no discards spent")

    g:check_unlock("round_win", { is_boss_blind = true, hands_played = 1, discards_used = 0 })
    T.assert_true(g:is_joker_unlocked("j_matador"))

    g:check_unlock("round_win", { is_boss_blind = true, last_hand = "High Card" })
    T.assert_true(g:is_joker_unlocked("j_hanging_chad"))

    g.career_stats.c_single_hand_round_streak = 5
    g:check_unlock("round_win", {})
    T.assert_true(g:is_joker_unlocked("j_troubadour"), "five single-hand rounds in a row")
end)

suite.test("unlocks and career stats survive a settings round-trip", function()
    local g = fresh(6111)
    g:add_career_stat("c_jokers_sold", 20)
    g:check_unlock("career_stat")
    T.assert_true(g:is_joker_unlocked("j_swashbuckler"))

    local snap = g:snapshot_settings()
    T.assert_true(snap.JOKER_UNLOCKS.j_swashbuckler)
    T.assert_eq(snap.CAREER_STATS.c_jokers_sold, 20)

    local restored = g:normalize_settings(snap)
    T.assert_true(restored.JOKER_UNLOCKS.j_swashbuckler)
    T.assert_eq(restored.CAREER_STATS.c_jokers_sold, 20)

    -- A key for a Joker that is not gated must not survive: it would be dead weight in
    -- every future save.
    local junk = g:normalize_joker_unlocks({ j_joker = true, j_swashbuckler = true })
    T.assert_eq(junk.j_joker, nil, "ungated ids are dropped")
    T.assert_true(junk.j_swashbuckler)
end)

suite.test("the collection separates locked from merely unseen", function()
    bootstrap.load()
    local CollectionCatalog = require("collection_catalog")
    local g = fresh(6112)

    local entry = { category = "jokers", id = "j_acrobat" }
    T.assert_true(CollectionCatalog.is_entry_locked(g, entry), "unearned reads as locked")

    g.joker_unlocks = { j_acrobat = true }
    T.assert_false(CollectionCatalog.is_entry_locked(g, entry),
        "earned but unseen is a silhouette, not a lock")

    T.assert_false(CollectionCatalog.is_entry_locked(g, { category = "jokers", id = "j_joker" }),
        "a Joker that was never gated is never locked")
    T.assert_false(CollectionCatalog.is_entry_locked(g, { category = "tarots", id = "tarot_fool" }),
        "only Jokers have unlock conditions")
end)

return suite
