--- Career high scores and the profile's stats panel.
---
--- The base game keeps six lifetime high scores per profile (`game.lua:864-874`) and shows
--- them beside the progress box (`UI_definitions.lua:2591-2617`). This port tracked per-run
--- counters only, so nothing survived the run that produced it.
local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

bootstrap.load()
local ProfileUI = require("profile_ui")

local function fresh(seed)
    local g = bootstrap.new_game(seed)
    g.career_stats = g:build_career_stats()
    g.career_hand_usage = {}
    g.seeded = false
    g.challenge_id = nil
    return g
end

suite.test("run high scores are high-water marks, not the latest value", function()
    local g = fresh(9101)
    g.round, g.ante, g.money = 12, 5, 300
    g:record_run_high_scores()
    T.assert_eq(g:get_career_stat("c_furthest_round"), 12)
    T.assert_eq(g:get_career_stat("c_furthest_ante"), 5)
    T.assert_eq(g:get_career_stat("c_most_money"), 300)

    -- A worse run must not lower them.
    g.round, g.ante, g.money = 3, 1, 12
    g:record_run_high_scores()
    T.assert_eq(g:get_career_stat("c_furthest_round"), 12)
    T.assert_eq(g:get_career_stat("c_furthest_ante"), 5)
    T.assert_eq(g:get_career_stat("c_most_money"), 300)

    -- A better one does.
    g.ante = 9
    g:record_run_high_scores()
    T.assert_eq(g:get_career_stat("c_furthest_ante"), 9)
end)

suite.test("most-played hand is counted across runs", function()
    local g = fresh(9102)
    local pair_idx, flush_idx
    for i, name in ipairs(g.handlist) do
        if name == "Pair" then pair_idx = i end
        if name == "Flush" then flush_idx = i end
    end

    local name, count = g:career_most_played_hand()
    T.assert_eq(name, "None")
    T.assert_eq(count, 0)

    for _ = 1, 3 do g:increment_hand_play_count(pair_idx) end
    g:increment_hand_play_count(flush_idx)
    name, count = g:career_most_played_hand()
    T.assert_eq(name, "Pair")
    T.assert_eq(count, 3)

    -- A new run resets the per-run counts but not the career tally.
    g.hand_play_counts = {}
    for _ = 1, 5 do g:increment_hand_play_count(flush_idx) end
    name, count = g:career_most_played_hand()
    T.assert_eq(name, "Flush", "the career leader spans runs")
    T.assert_eq(count, 6)
end)

suite.test("career stats and hand usage survive a settings round-trip", function()
    local g = fresh(9103)
    g.round, g.ante, g.money = 7, 4, 250
    g:record_run_high_scores()
    for i, name in ipairs(g.handlist) do
        if name == "Two Pair" then g:increment_hand_play_count(i) end
    end

    local snap = g:snapshot_settings()
    T.assert_eq(snap.CAREER_STATS.c_furthest_round, 7)
    T.assert_eq(snap.CAREER_HAND_USAGE["Two Pair"], 1)

    local restored = g:normalize_settings(snap)
    T.assert_eq(restored.CAREER_STATS.c_most_money, 250)
    T.assert_eq(restored.CAREER_HAND_USAGE["Two Pair"], 1)

    -- A hand name that is not in the handlist is dropped rather than persisted forever.
    local junk = g:normalize_career_hand_usage({ ["Not A Hand"] = 4, Pair = 2 })
    T.assert_eq(junk["Not A Hand"], nil)
    T.assert_eq(junk.Pair, 2)
end)

suite.test("the profile page lists the reference's six career rows", function()
    local g = fresh(9104)
    g.round, g.ante, g.money = 9, 6, 412
    g:record_run_high_scores()
    g:record_career_best("c_best_hand_chips", 1240500)
    g:record_career_best("c_win_streak", 3)

    local rows = ProfileUI.career_rows(g)
    T.assert_eq(#rows, 6)
    local labels = {}
    for _, r in ipairs(rows) do labels[r[1]] = r[2] end
    T.assert_eq(labels["Best Hand"], "1,240,500", "big numbers get separators")
    T.assert_eq(labels["Highest Round"], "9")
    T.assert_eq(labels["Highest Ante"], "6")
    T.assert_eq(labels["Most Money"], "$412")
    T.assert_eq(labels["Best Streak"], "3")
    T.assert_eq(labels["Most Played"], "None", "with nothing played yet")
end)

--- Career stats belong to the loaded profile, so another slot shows its progress bars.
suite.test("the career panel is only offered on the active profile", function()
    local g = fresh(9105)
    g._profile_show_stats = true
    T.assert_true(ProfileUI.showing_stats(g, 1, 1), "the loaded slot can show stats")
    T.assert_false(ProfileUI.showing_stats(g, 2, 1), "another slot falls back to progress")

    g._profile_show_stats = false
    T.assert_false(ProfileUI.showing_stats(g, 1, 1), "and the toggle still governs")
end)

suite.test("a win extends the streak and a loss ends it", function()
    local g = fresh(9106)
    g:add_career_stat("c_current_streak", 2)
    g:record_career_best("c_win_streak", 2)

    g:add_career_stat("c_current_streak", 1)
    g:record_career_best("c_win_streak", g:get_career_stat("c_current_streak"))
    T.assert_eq(g:get_career_stat("c_win_streak"), 3)

    g.career_stats.c_current_streak = 0
    T.assert_eq(g:get_career_stat("c_win_streak"), 3, "the best is kept after a loss")
    T.assert_eq(g:get_career_stat("c_current_streak"), 0)
end)

return suite
