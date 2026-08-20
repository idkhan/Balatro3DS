local t = require("tests.testlib")
local challenges = require("challenge_catalog")
local bootstrap = require("tests.bootstrap")
local suite = t.suite()

suite.test("all shipped challenges are catalogued with localized names", function()
    local names = {
        "The Omelette", "15 Minute City", "Rich get Richer", "On a Knife's Edge", "X-ray Vision",
        "Mad World", "Luxury Tax", "Non-Perishable", "Medusa", "Double or Nothing", "Typecast",
        "Inflation", "Bram Poker", "Fragile", "Monolith", "Blast Off", "Five-Card Draw",
        "Golden Needle", "Cruelty", "Jokerless",
    }
    t.assert_eq(#challenges, 20)
    for i, name in ipairs(names) do t.assert_eq(challenges[i].name, name) end
end)

suite.test("challenge application supplies rules, bans, deck preset, and starting items", function()
    local game = bootstrap.new_game(919)
    game._pending_challenge_id = "c_bram_poker_1"
    game:initialize_run_loop()
    t.assert_eq(game.challenge_id, "c_bram_poker_1")
    t.assert_true(game.challenge_modifiers.no_shop_jokers)
    t.assert_true(game:is_challenge_banned("v_magic_trick") == false)
    t.assert_true(game:has_voucher("v_magic_trick"))
    t.assert_eq(#game.jokers, 1)
    t.assert_eq(game.jokers[1].def.id, "j_vampire")
    t.assert_true(game.jokers[1].eternal)
end)

suite.test("challenge bans reach every random pool and challenge state survives a snapshot", function()
    local game = bootstrap.new_game(920)
    game._pending_challenge_id = "c_jokerless_1"
    game:initialize_run_loop()
    t.assert_eq(game:joker_base_capacity(), 0)
    t.assert_true(game:is_challenge_banned("p_buffoon_normal_1"))
    t.assert_true(game:is_challenge_banned("tag_buffoon"))
    local snapshot = game:build_run_snapshot()
    local resumed = bootstrap.new_game(921)
    local ok, err = resumed:load_run_snapshot(snapshot)
    t.assert_true(ok, err)
    t.assert_eq(resumed.challenge_id, "c_jokerless_1")
    t.assert_true(resumed:is_challenge_banned("tag_buffoon"))
end)

suite.test("challenge mechanics affect existing systems", function()
    local game = bootstrap.new_game(922)
    game.challenge_rules = { hand_size = 10 }
    game.challenge_modifiers = { minus_hand_size_per_X_dollar = 5, all_eternal = true }
    game.money = 15
    t.assert_eq(game:get_effective_hand_size_limit(), 7)
    t.assert_true(game:add_joker_by_def("j_joker"))
    t.assert_true(game.jokers[#game.jokers].eternal)
    game.challenge_modifiers.inflation = true
    local before = game.inflation or 0
    game:increment_challenge_inflation()
    t.assert_eq(game.inflation, before + 1)
    t.assert_eq(game:_make_shop_voucher_offer("v_blank").price, 11)
end)

suite.test("challenge completion is profile-scoped and reloadable", function()
    local game = bootstrap.new_game(923)
    game.challenge_id = "c_omelette_1"
    t.assert_true(game:ensure_victory_progress_recorded())
    t.assert_true(game:is_challenge_completed("c_omelette_1"))
    local progress = game:get_profile_progress(game:get_profile_id())
    t.assert_eq(progress.rows[2].have, 1)
    t.assert_eq(progress.rows[2].total, 20)
    local resumed = bootstrap.new_game(924)
    resumed:load_settings()
    t.assert_true(resumed:is_challenge_completed("c_omelette_1"))
end)

return suite
