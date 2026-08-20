local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")
local BoosterPackUI = require("booster_pack_ui")

local suite = T.suite()
local game = bootstrap.new_game(889)

suite.test("Garbage Tag pays every recorded unused discard immediately", function()
    game.money = 7
    game.discardsUnused = 4
    T.assert_true(Tag("garbage"):apply())
    T.assert_eq(game.money, 11)
end)

--- Boss Tag re-rolls the boss and is spent. It is a `new_blind_choice` tag
--- (`reference/Balatro/game.lua:233`), so it waits in the tray for the blind-select screen
--- and is consumed there. Firing it on `apply()` regardless of context meant a loaded run,
--- which re-applies its stored tags, handed out another free boss re-roll every save/load.
suite.test("Boss Tag is consumed when it re-rolls the blind", function()
    game.tags = {}
    local real_roll = game.roll_boss_blind
    local rolled = 0
    game.roll_boss_blind = function(_, opts)
        rolled = rolled + 1
        T.assert_true(opts and opts.exclude_current == true, "the current boss is excluded")
    end

    local ok, err = pcall(function()
        T.assert_false(Tag("boss"):apply(), "outside a blind choice the tag does not fire")
        T.assert_eq(rolled, 0)
        T.assert_true(Tag("boss"):apply("new_blind_choice"), "the blind choice spends it")
        T.assert_eq(rolled, 1)

        game:addTag("boss")
        T.assert_eq(rolled, 1, "adding the tag stores it rather than firing it")
        T.assert_eq(#game.tags, 1, "it waits in the tag list")
        game.STATE = game.STATES.BLIND_SELECT
        T.assert_true(game:apply_new_blind_choice_tags())
        T.assert_eq(rolled, 2, "the blind-select screen fires it")
        T.assert_eq(#game.tags, 0, "and it is not left in the tag list")
    end)
    game.roll_boss_blind = real_roll
    if not ok then error(err, 0) end
end)

suite.test("Top-up D6 and Skip tag prototypes map to skip ids", function()
    local original_tags = game.P_TAGS
    local original_ante = game.ante
    game.P_TAGS = {
        tag_top_up = { min_ante = nil },
        tag_d_six = { min_ante = nil },
        tag_skip = { min_ante = nil },
    }
    game.ante = 1

    local original_random = math.random
    math.random = function(_, _) return 1 end
    game:roll_skips()
    math.random = original_random

    local found = {}
    for _, id in ipairs(game.skips) do found[id] = true end
    T.assert_true(found[10] or found[18] or found[23], "at least one valid special tag is offered")
    T.assert_eq(game:tag_key_for_id(10), "tag_top_up")
    T.assert_eq(game:tag_key_for_id(18), "tag_skip")
    T.assert_eq(game:tag_key_for_id(23), "tag_d_six")
    game.P_TAGS = original_tags
    game.ante = original_ante
end)

suite.test("Buffoon and Spectral pack sizes are 2 normal and 4 jumbo or mega", function()
    for _, pack in ipairs({ "buffoon", "spectral" }) do
        T.assert_eq(BoosterPackUI.card_count_for_size("normal", pack), 2, pack .. " normal")
        T.assert_eq(BoosterPackUI.card_count_for_size("jumbo", pack), 4, pack .. " jumbo")
        T.assert_eq(BoosterPackUI.card_count_for_size("mega", pack), 4, pack .. " mega")
    end
end)

--- Buffoon Tag opens a Mega (`tag.lua` → `p_buffoon_mega_1`), but Ethereal Tag opens a plain
--- Spectral Pack — the reference hardcodes `p_spectral_normal_1`, `{extra = 2, choose = 1}`
--- (`tag.lua:239-241`, `game.lua:681`). Granting a Mega doubled both cards and picks.
suite.test("tag-granted packs match the reference pack each tag names", function()
    local opened
    local original = game.begin_booster_session
    game.begin_booster_session = function(_, offer) opened = offer end

    Tag("buffoon"):apply("new_blind_choice")
    T.assert_eq(opened.card_count, 4, "Buffoon Tag opens a Mega Buffoon Pack")
    T.assert_eq(opened.picks_granted, 2)

    Tag("ethereal"):apply("new_blind_choice")
    T.assert_eq(opened.size, "normal", "Ethereal Tag opens a plain Spectral Pack")
    T.assert_eq(opened.card_count, 2)
    T.assert_eq(opened.picks_granted, 1)

    game.begin_booster_session = original
end)

--- `tag.lua:184` adds `min(config.max, max(0, dollars))` with `max = 40`: a double capped at
--- a $40 gain, and nothing at all while in debt.
suite.test("Economy Tag doubles the balance rather than tripling it", function()
    game.money = 10
    T.assert_true(Tag("economy"):apply())
    T.assert_eq(game.money, 20, "$10 doubles to $20")

    game.money = 30
    Tag("economy"):apply()
    T.assert_eq(game.money, 60, "$30 doubles to $60")

    game.money = 100
    Tag("economy"):apply()
    T.assert_eq(game.money, 140, "the gain caps at $40")

    game.money = -5
    Tag("economy"):apply()
    T.assert_eq(game.money, -5, "debt is left alone, not deepened")
end)

suite.test("Standard Pack playing cards use enhancement seal and edition rolls", function()
    local draws = { 2, 1, 1, 1, 1, 1, 9999 }
    local original = game._pack_rand_int
    game._pack_rand_int = function(_, _, _)
        return table.remove(draws, 1)
    end
    local choice = game:_booster_build_choices({ pack = "standard", card_count = 1 })[1]
    game._pack_rand_int = original

    T.assert_eq(choice.playing_data.enhancement, "bonus")
    T.assert_eq(choice.playing_data.seal, "red")
    T.assert_eq(choice.playing_data.modifier.edition, "polychrome")
end)

suite.test("Omen Globe replaces Tarot choices only above the 80 percent threshold", function()
    game.vouchers = { v_omen_globe = true }
    local original_take = game._pack_pool_take
    local original_rand = game._pack_rand_int
    game._pack_pool_take = function(_, pool)
        return pool.kind == "tarot" and "tarot_strength" or "spectral_aura"
    end

    -- The only roll the arcana path makes here is the Omen Globe threshold; the draw is stubbed.
    game._pack_rand_int = function() return 80 end
    T.assert_eq(game:_booster_build_choices({ pack = "arcana", card_count = 1 })[1].kind, "tarot")
    game._pack_rand_int = function() return 81 end
    T.assert_eq(game:_booster_build_choices({ pack = "arcana", card_count = 1 })[1].kind, "spectral")

    game._pack_pool_take = original_take
    game._pack_rand_int = original_rand
end)

suite.test("edition Jokers sell from their edition-adjusted cost", function()
    local joker = Joker(0, 0, nil, nil, { id = "test", name = "Test", cost = 5 }, { edition = "polychrome" })
    T.assert_eq(joker.cost, 10)
    T.assert_eq(joker.sell_cost, 5)
end)

suite.test("negative edition chance is flat while Hone and Glow Up scale other editions", function()
    game.vouchers = {}
    local base = game:get_joker_edition_rates()
    game.vouchers = { v_hone = true }
    local hone = game:get_joker_edition_rates()
    game.vouchers = { v_glow_up = true }
    local glow = game:get_joker_edition_rates()
    T.assert_eq(base.negative, 0.3)
    T.assert_eq(hone.negative, 0.3)
    T.assert_eq(glow.negative, 0.3)
    T.assert_eq(hone.foil, base.foil * 2)
    T.assert_eq(glow.foil, base.foil * 4)
end)

suite.test("Magic Trick adds four playing-card shop weights", function()
    game.vouchers = { v_magic_trick = true }
    local max_roll
    local original = game._shop_rand_int
    game._shop_rand_int = function(_, lo, hi)
        if not max_roll then max_roll = hi end
        return hi
    end
    local offer = game:_generate_next_shop_queue_offer()
    game._shop_rand_int = original
    T.assert_eq(max_roll, 32, "20 Joker + 4 Tarot + 4 Planet + 4 Magic Trick")
    T.assert_eq(offer.kind, "playing_card")
end)

--- Buffoon Tag is a `new_blind_choice` tag (`reference/Balatro/game.lua:237`): earning it on
--- a skip must not open its pack mid-skip. The pack has to open against the blind-select
--- screen that follows, so it comes back to the next blind rather than to whatever the skip
--- was halfway out of.
suite.test("a pack tag waits for the blind-select screen and returns to the next blind", function()
    local g = bootstrap.new_game(4242)
    g.tags = {}
    g.STATE = g.STATES.SHOP
    g:addTag("buffoon")
    T.assert_eq(#g.tags, 1, "the tag sits in the tray outside blind select")
    T.assert_eq(g.booster_session, nil, "no pack opens in the shop")

    g.tags = {}
    g.STATE = g.STATES.BLIND_SELECT
    g.current_blind_index = 1
    g.selected_blind_index = 1
    local buffoon_id
    for id = 0, 40 do
        if g:tag_type_for_id(id) == "buffoon" then buffoon_id = id end
    end
    T.assert_not_nil(buffoon_id, "the tag catalog offers a Buffoon Tag")
    g.skips = { buffoon_id }

    T.assert_true(g:skip_blind(1))
    T.assert_eq(g.STATE, g.STATES.OPEN_BOOSTER, "the skip opens the pack")
    T.assert_eq(g.current_blind_index, 2, "the skip has already advanced past the small blind")
    T.assert_eq(#g.tags, 0, "the tag is spent, not left in the tray")

    local sess = g.booster_session
    T.assert_eq(sess.pack, "buffoon")
    T.assert_eq(sess.title, "Mega Buffoon Pack")
    T.assert_eq(sess.booster_sprite_index, 33, "the wrapper is the Mega Buffoon frame")

    sess.picks_remaining = 0
    g:end_booster_session()
    T.assert_eq(g.STATE, g.STATES.BLIND_SELECT, "closing the pack returns to blind select")
    T.assert_eq(g.current_blind_index, 2, "the big blind is next, not the boss")
end)

--- One tag per screen (`reference/Balatro/game.lua:3293-3294`).
suite.test("two pack tags open one pack per blind-select screen", function()
    local g = bootstrap.new_game(4243)
    g.tags = {}
    g.STATE = g.STATES.SHOP
    g:addTag("buffoon")
    g:addTag("charm")

    g.STATE = g.STATES.BLIND_SELECT
    T.assert_true(g:apply_new_blind_choice_tags())
    T.assert_eq(g.booster_session.pack, "buffoon")
    T.assert_eq(#g.tags, 1, "the Charm Tag is still waiting")

    g.booster_session = nil
    T.assert_true(g:apply_new_blind_choice_tags())
    T.assert_eq(g.booster_session.pack, "arcana")
    T.assert_eq(#g.tags, 0)
    T.assert_false(g:apply_new_blind_choice_tags(), "an empty tray fires nothing")
end)

--- Owning every Rare Joker empties the pool. The reference plays the tag's `nope()` and
--- hands out nothing (`reference/Balatro/tag.lua:363-370`); the port used to shelve the
--- id-less entry it built anyway, which read as a blank, nameless, free card.
suite.test("a Rare Tag with an exhausted pool fizzles instead of shelving a blank card", function()
    local g = bootstrap.new_game(4244)
    g.tags = {}
    g:addTag("rare")
    local original = g.random_joker_def_id_by_rarity
    g.random_joker_def_id_by_rarity = function(self, rarity, key)
        if rarity == 3 then return nil end
        return original(self, rarity, key)
    end
    g:roll_shop_offers()
    g.random_joker_def_id_by_rarity = original

    T.assert_eq(#g.tags, 0, "the tag is still spent")
    T.assert_true(#g.shop_offers > 0, "the shop still fills")
    for i, offer in ipairs(g.shop_offers) do
        T.assert_not_nil(offer.id, "shop slot " .. i .. " names a real item")
    end
end)

return suite
