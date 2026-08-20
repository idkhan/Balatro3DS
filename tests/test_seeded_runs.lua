--- Run-seed regression coverage: streams are intentionally port-local, but must be stable.
local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

local function run_decisions(seed)
    local game = bootstrap.new_game(seed)
    game:seed_rng_stream(seed)
    game.deck = Deck(game)
    game.deck:shuffle()
    local deck = {}
    for i, c in ipairs(game.deck.cards) do deck[i] = tostring(c.rank) .. c.suit:sub(1, 1) end
    local boss = game:roll_boss_blind()
    local shop = game:_generate_next_shop_queue_offer()
    local pack = game:_booster_build_choices({ pack = "arcana", size = "normal", picks_granted = 1 })
    local choices = {}
    for i, choice in ipairs(pack) do choices[i] = choice.id or choice.kind end
    return table.concat(deck, ","), boss, shop and shop.id, table.concat(choices, ",")
end

suite.test("only a user-typed seed marks the run seeded", function()
    local game = bootstrap.new_game(9001)
    game._pending_run_seed = "ALEEB123"
    game:start_run_from_main_menu()
    T.assert_true(game.seeded == true, "a typed seed marks the run seeded")
    T.assert_eq(game.SEED, "ALEEB123")

    game._pending_run_seed = nil
    game:start_run_from_main_menu()
    T.assert_true(game.seeded == false, "an auto-generated identity does not")
end)

suite.test("the seeded flag survives a save round-trip", function()
    local game = bootstrap.new_game(9002)
    game._pending_run_seed = "ALEEB123"
    game:start_run_from_main_menu()

    local snapshot = game:build_run_snapshot()
    T.assert_true(snapshot.seeded == true, "the snapshot records the seeded run")

    local fresh = bootstrap.new_game(9003)
    T.assert_true(fresh:load_run_snapshot(snapshot))
    T.assert_true(fresh.seeded == true, "a restored seeded run stays marked")
end)

suite.test("the same seed reproduces deck boss shop and pack decisions", function()
    local a = { run_decisions("A1B2C3D4") }
    local b = { run_decisions("A1B2C3D4") }
    for i = 1, #a do T.assert_eq(a[i], b[i]) end
end)

suite.test("different seeds diverge", function()
    local a = { run_decisions("A1B2C3D4") }
    local b = { run_decisions("Z9Y8X7W6") }
    local different = false
    for i = 1, #a do if a[i] ~= b[i] then different = true end end
    T.assert_true(different)
end)

suite.test("named streams do not shift each other", function()
    local a = bootstrap.new_game("A1B2C3D4")
    local b = bootstrap.new_game("A1B2C3D4")
    for _ = 1, 20 do a:random("shop", 1, 100) end
    T.assert_eq(a:random("boss", 1, 1000000), b:random("boss", 1, 1000000))
end)

suite.test("saving mid-run preserves every named stream position", function()
    local uninterrupted = bootstrap.new_game("A1B2C3D4")
    uninterrupted:random("shop", 1, 100)
    uninterrupted:random("boss", 1, 100)
    uninterrupted:random("pack", 1, 100)
    local snapshot = uninterrupted:build_run_snapshot()
    local expected = { uninterrupted:random("shop", 1, 100), uninterrupted:random("boss", 1, 100), uninterrupted:random("pack", 1, 100) }
    local resumed = bootstrap.new_game("Z9Y8X7W6")
    local ok, err = resumed:load_run_snapshot(snapshot)
    T.assert_true(ok, err)
    T.assert_eq(resumed:random("shop", 1, 100), expected[1])
    T.assert_eq(resumed:random("boss", 1, 100), expected[2])
    T.assert_eq(resumed:random("pack", 1, 100), expected[3])
end)

return suite
