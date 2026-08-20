local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

local function expected_endless(last_base, ante)
    local overflow = ante - 8
    local raw = last_base * (1.6 + (0.75 * overflow) ^ (1 + 0.2 * overflow)) ^ overflow
    local magnitude = math.floor(math.log10(raw))
    return math.floor(raw / (10 ^ (magnitude - 1))) * (10 ^ (magnitude - 1))
end

suite.test("Green and Purple stakes select their alternate ante tables", function()
    local game = bootstrap.new_game(900)
    game:apply_stake_config("stake_green")
    T.assert_eq(game:get_base_requirement_for_ante(2), 900)
    game:apply_stake_config("stake_purple")
    T.assert_eq(game:get_base_requirement_for_ante(2), 1000)

    game.ante = 9
    game:apply_stake_config("stake_green")
    T.assert_eq(game:get_base_requirement_for_ante(2), 900, "use requested ante, not self.ante")
end)

suite.test("endless stake growth starts with ante-nine overflow one", function()
    local game = bootstrap.new_game(901)
    game:apply_stake_config("stake_purple")
    T.assert_eq(game:get_base_requirement_for_ante(9), expected_endless(200000, 9))
end)

suite.test("Red Stake removes the Small Blind reward", function()
    local game = bootstrap.new_game(902)
    game:apply_stake_config("stake_red")
    game.current_blind_index = 1
    game.selected_blind_index = 1
    T.assert_true(game:_commit_selected_blind())
    T.assert_eq(game.current_blind_reward, 0)
end)

--- An illegal hand under these three bosses is played and consumed, then scores nothing
--- (`state_events.lua:475` spends the hand before the `debuff_hand` gate at `:614`).
--- It must not be refused, and it must not record itself against the boss
--- (`blind.lua:535-547` returns before `self.hands[handname]` / `self.only_hand` are set).
suite.test("Mouth Eye and Psychic void invalid plays instead of refusing them", function()
    local game = bootstrap.new_game(903)
    local boss
    game.get_active_boss_blind_id = function() return boss end
    game.boss_runtime = { hand_count = 0, seen_hand_types = {}, locked_hand_type = nil }
    game.handlist = { "Pair", "Straight" }
    game.selectedHand = 1

    boss = "bl_mouth"
    T.assert_true(game:boss_before_play_selected({ {}, {} }))
    T.assert_false(game:boss_should_void_current_play(), "the first hand type is legal")
    T.assert_eq(game.boss_runtime.locked_hand_type, "Pair", "and locks the Mouth to it")
    game.selectedHand = 2
    T.assert_true(game:boss_before_play_selected({ {}, {} }), "a mismatched hand is still played")
    T.assert_true(game:boss_should_void_current_play(), "but it is voided")
    T.assert_eq(game.boss_runtime.locked_hand_type, "Pair", "a voided hand does not relock the Mouth")

    boss = "bl_eye"
    game.boss_runtime = { hand_count = 0, seen_hand_types = { Pair = true }, locked_hand_type = nil }
    game.selectedHand = 1
    T.assert_true(game:boss_before_play_selected({ {}, {} }))
    T.assert_true(game:boss_should_void_current_play(), "a repeat hand type is voided")
    game.selectedHand = 2
    T.assert_true(game:boss_before_play_selected({ {}, {} }))
    T.assert_false(game:boss_should_void_current_play(), "a fresh type scores")
    T.assert_true(game.boss_runtime.seen_hand_types["Straight"], "and is recorded")

    boss = "bl_psychic"
    game.boss_runtime = { hand_count = 0, seen_hand_types = {}, locked_hand_type = nil }
    T.assert_true(game:boss_before_play_selected({ {}, {}, {} }))
    T.assert_true(game:boss_should_void_current_play(), "fewer than five cards is voided")
    T.assert_true(game:boss_before_play_selected({ {}, {}, {}, {}, {} }))
    T.assert_false(game:boss_should_void_current_play(), "five cards scores")
end)

--- `blind.lua:510-516` rounds each half up. Flooring took a second bite out of an odd mult.
suite.test("The Flint rounds the halved base up", function()
    local game = bootstrap.new_game(905)
    game.get_active_boss_blind_id = function() return "bl_flint" end

    -- Three of a Kind, level 1: 30 chips / 3 mult.
    local chips, mult = game:boss_apply_hand_base_modifiers(30, 3)
    T.assert_eq(chips, 15)
    T.assert_eq(mult, 2, "3 mult halves to 2, not 1")

    -- High Card, level 1: 5 chips / 1 mult.
    chips, mult = game:boss_apply_hand_base_modifiers(5, 1)
    T.assert_eq(chips, 3, "5 chips rounds up to 3")
    T.assert_eq(mult, 1, "mult never drops below 1")

    -- Even values are unaffected by the rounding change.
    chips, mult = game:boss_apply_hand_base_modifiers(40, 4)
    T.assert_eq(chips, 20)
    T.assert_eq(mult, 2)
end)

--- `state_events.lua:362-368` replaces the refill with a flat 3-card draw, so the hand
--- shrinks across a round instead of topping back up.
suite.test("The Serpent draws exactly three rather than refilling", function()
    local game = bootstrap.new_game(906)
    game.get_active_boss_blind_id = function() return "bl_serpent" end
    game.boss_runtime = { serpent_draws_pending = 0 }

    T.assert_eq(game:boss_consume_serpent_draws(), nil, "no override before a play or discard")

    game:boss_after_discard_or_play("play")
    T.assert_eq(game.boss_runtime.serpent_draws_pending, 3)
    T.assert_eq(game:boss_consume_serpent_draws(), 3, "an absolute draw count, not a limit")
    T.assert_eq(game:boss_consume_serpent_draws(), nil, "and it is consumed once")

    game.get_active_boss_blind_id = function() return "bl_hook" end
    game.boss_runtime.serpent_draws_pending = 3
    T.assert_eq(game:boss_consume_serpent_draws(), nil, "other bosses refill normally")
end)

--- The Ox targets the hand frozen when the last Boss fell, defaulting to High Card at run
--- start (`state_events.lua:132-138`, `blind.lua:560-570`). A live count let the player
--- re-target it mid-ante, and left it inert on the first hand of a run.
suite.test("The Ox targets a frozen most-played hand", function()
    local game = bootstrap.new_game(907)
    game.frozen_most_played_hand_index = nil
    game.hand_play_counts = {}

    local high_card = game:default_most_played_hand_index()
    T.assert_eq(game.handlist[high_card], "High Card")
    T.assert_eq(game:most_played_hand_index(), high_card, "a fresh run targets High Card")

    -- Playing Pairs does not re-aim the Ox until a Boss blind is beaten.
    local pair_idx
    for i, name in ipairs(game.handlist) do
        if name == "Pair" then pair_idx = i end
    end
    game.hand_play_counts[pair_idx] = 5
    T.assert_eq(game:most_played_hand_index(), high_card, "the target holds mid-ante")

    game:freeze_most_played_hand()
    T.assert_eq(game:most_played_hand_index(), pair_idx, "beating the Boss re-fixes it")

    -- Ties resolve to the earlier (stronger) handlist entry, deterministically.
    game.hand_play_counts = {}
    game.hand_play_counts[3] = 2
    game.hand_play_counts[9] = 2
    game:freeze_most_played_hand()
    T.assert_eq(game:most_played_hand_index(), 3)
end)

suite.test("Wheel routes its face-down chance through do_random", function()
    local game = bootstrap.new_game(904)
    game.get_active_boss_blind_id = function() return "bl_wheel" end
    local call
    game.do_random = function(_, min, max, goal)
        call = { min, max, goal }
        return true
    end
    local card = { card_data = {} }
    card.set_face_up = function(_, value) card.face_up = value end
    game:boss_on_card_drawn(card)
    T.assert_eq(call[1], 1)
    T.assert_eq(call[2], 7)
    T.assert_eq(call[3], 1)
    T.assert_false(card.face_up)
end)

suite.test("loading a snapshot resumes the gameplay RNG stream", function()
    local uninterrupted = bootstrap.new_game(905)
    uninterrupted:seed_rng_stream(123456)
    math.random(1, 1000000)
    math.random(1, 1000000)
    local snapshot = uninterrupted:build_run_snapshot()
    local expected = math.random(1, 1000000)

    local resumed = bootstrap.new_game(906)
    local ok, err = resumed:load_run_snapshot(snapshot)
    T.assert_true(ok, err)
    T.assert_eq(math.random(1, 1000000), expected)
end)

return suite
