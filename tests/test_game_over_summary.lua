local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

bootstrap.load()
local GameOverUI = require("game_over_ui")

suite.test("game-over summary selects the tracked run statistics", function()
    local out = {}
    GameOverUI.populate_summary({
        run_best_hand_score = 12345,
        run_cards_played = 47,
        run_cards_discarded = 13,
        _game_over_blind_label = "The Wall",
        get_most_played_hand_name = function() return "Flush" end,
        run_cards_purchased = 9,
        run_times_rerolled = 4,
        SEED = "ALEEB123",
    }, out)

    T.assert_eq(out.best_hand_score, 12345)
    T.assert_eq(out.most_played_hand, "Flush")
    T.assert_eq(out.cards_played, 47)
    T.assert_eq(out.cards_discarded, 13)
    T.assert_eq(out.defeated_by, "The Wall")
    -- The reference's game-over readout carries the shop counters and the seed too
    -- (`UI_definitions.lua:2877-2893`, `:3013`); the port tracked them but only ever showed
    -- them on the victory screen.
    T.assert_eq(out.cards_purchased, 9)
    T.assert_eq(out.times_rerolled, 4)
    T.assert_eq(out.seed, "ALEEB123")
end)

suite.test("game-over summary has safe values for an untouched run", function()
    local out = GameOverUI.populate_summary({})
    T.assert_eq(out.best_hand_score, 0)
    T.assert_eq(out.most_played_hand, "None")
    T.assert_eq(out.cards_played, 0)
    T.assert_eq(out.cards_discarded, 0)
    T.assert_eq(out.defeated_by, "Blind")
    T.assert_eq(out.cards_purchased, 0)
    T.assert_eq(out.times_rerolled, 0)
    T.assert_eq(out.seed, "Unknown")
end)

return suite
