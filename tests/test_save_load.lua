--- Save/load round-trip through the Lua-source serialiser in game.lua.
---
--- The game persists state by emitting a `return { ... }` Lua chunk and loading it back
--- with love.filesystem.load. That is compact and fast on a 3DS but it is also a
--- hand-written encoder: unescaped strings, non-identifier keys, sparse arrays and
--- non-finite numbers are all ways it can silently corrupt a save.
---
--- `serialize_lua_value` is file-local, so these tests reach it the way the game does --
--- through `write_run_snapshot` / `read_run_snapshot` and `save_settings` /
--- `load_settings` -- and the love stub's in-memory filesystem stands in for the SD card.

local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

local love = bootstrap.load()
local game = bootstrap.new_game(4242)

--- Round-trip an arbitrary table through the run-save encoder.
---@param snapshot table
---@return table decoded
local function roundtrip(snapshot)
    local ok, err = game:write_run_snapshot(snapshot)
    T.assert_true(ok, "write_run_snapshot failed: " .. tostring(err))
    local decoded, read_err = game:read_run_snapshot()
    T.assert_not_nil(decoded, "read_run_snapshot failed: " .. tostring(read_err))
    return decoded
end

--------------------------------------------------------------------------------
-- Encoder behaviour
--------------------------------------------------------------------------------

suite.test("a flat table of scalars survives the round trip", function()
    local snap = {
        seed = 4242,
        ante = 3,
        money = 17,
        hands = 4,
        discards = 2,
        round_score = 1234,
        endless = false,
        deck_id = "d_red",
    }
    T.assert_deep_eq(roundtrip(snap), snap)
end)

suite.test("nested tables survive the round trip", function()
    local snap = {
        seed = 1,
        jokers = {
            { id = "j_joker", edition = "foil", stored_mult = 4, runtime_counter = 0 },
            { id = "j_oops", edition = nil, stored_xmult = 1.5, runtime_counter = 12 },
        },
        deck_cards = {
            { rank = 14, suit = "Spades", enhancement = "wild", seal = "gold" },
            { rank = 2, suit = "Hearts" },
        },
        hand_levels = { [1] = 3, [7] = 2, [12] = 1 },
    }
    T.assert_deep_eq(roundtrip(snap), snap)
end)

suite.test("booleans keep their type rather than becoming strings", function()
    local snap = { seed = 1, a = true, b = false, nested = { c = true, d = false } }
    local out = roundtrip(snap)
    T.assert_eq(out.a, true, "true must survive as a boolean")
    T.assert_eq(out.b, false, "false must survive as a boolean")
    T.assert_eq(out.nested.c, true)
    T.assert_eq(out.nested.d, false)
end)

suite.test("negative and fractional numbers survive", function()
    local snap = { seed = 1, money = -20, xmult = 1.25, tiny = 0.0009765625, big = 2 ^ 40 }
    local out = roundtrip(snap)
    T.assert_eq(out.money, -20)
    T.assert_near(out.xmult, 1.25, 1e-12)
    T.assert_near(out.tiny, 0.0009765625, 1e-15)
    T.assert_eq(out.big, 2 ^ 40)
end)

suite.test("strings with quotes, backslashes and newlines survive", function()
    -- Profile names are player-entered, so the encoder has to escape properly or a
    -- quote in a name produces a save file that will not parse.
    local snap = {
        seed = 1,
        names = {
            [[he said "hi"]],
            "back\\slash",
            "line\nbreak",
            "tab\there",
            "quote'single",
            "nul\0byte",
        },
    }
    T.assert_deep_eq(roundtrip(snap), snap)
end)

suite.test("keys that are not valid identifiers survive", function()
    local snap = {
        seed = 1,
        map = {
            ["with space"] = 1,
            ["with-dash"] = 2,
            ["3leading_digit"] = 3,
            ["ok_key"] = 4,
            ["a.b"] = 5,
            [""] = 6,
        },
    }
    T.assert_deep_eq(roundtrip(snap), snap)
end)

suite.test("keys that are Lua keywords survive", function()
    -- The encoder emits a bare `k=v` for any key matching ^[%a_][%w_]*$, which also
    -- matches every reserved word. `{end=1}` is a syntax error, so a single such key
    -- makes the whole save file unloadable -- the run is lost, not just that field.
    local keywords = {
        "and", "break", "do", "else", "elseif", "end", "false", "for", "function",
        "if", "in", "local", "nil", "not", "or", "repeat", "return", "then", "true",
        "until", "while",
    }
    local broken = {}
    for _, kw in ipairs(keywords) do
        local ok = game:write_run_snapshot({ seed = 1, [kw] = 1 })
        local decoded = ok and game:read_run_snapshot() or nil
        if not decoded or decoded[kw] ~= 1 then
            broken[#broken + 1] = kw
        end
    end
    if #broken > 0 then
        error({
            __test_failure = true,
            message = string.format(
                "%d Lua keyword(s) used as a table key produce an unloadable save: %s",
                #broken, table.concat(broken, ", ")),
        }, 0)
    end
end)

suite.test("numeric keys outside the array part survive", function()
    local snap = { seed = 1, sparse = { [1] = "a", [2] = "b", [10] = "j", [-1] = "neg" } }
    T.assert_deep_eq(roundtrip(snap), snap)
end)

suite.test("an empty table survives as an empty table", function()
    local out = roundtrip({ seed = 1, nothing = {}, list = {} })
    T.assert_eq(type(out.nothing), "table", "an empty table must not decode as nil")
    T.assert_eq(next(out.nothing), nil, "an empty table must stay empty")
    T.assert_eq(type(out.list), "table")
end)

suite.test("array order is preserved", function()
    local snap = { seed = 1, order = { "first", "second", "third", "fourth", "fifth" } }
    local out = roundtrip(snap)
    T.assert_eq(#out.order, 5, "array length must be preserved")
    for i, v in ipairs(snap.order) do
        T.assert_eq(out.order[i], v, "element " .. i)
    end
end)

suite.test("non-finite numbers degrade to zero rather than corrupting the file", function()
    -- The encoder maps NaN and +/-inf to 0 on purpose: `tostring(0/0)` is not valid Lua
    -- source, so emitting it verbatim would produce an unloadable save. Lossy, but the
    -- alternative is a save that will not parse at all.
    local out = roundtrip({ seed = 1, nan = 0 / 0, inf = math.huge, ninf = -math.huge })
    T.assert_eq(out.nan, 0, "NaN should be written as 0")
    T.assert_eq(out.inf, 0, "infinity should be written as 0")
    T.assert_eq(out.ninf, 0, "negative infinity should be written as 0")
end)

suite.test("a deeply nested structure survives", function()
    local snap = { seed = 1, a = { b = { c = { d = { e = { value = "bottom" } } } } } }
    T.assert_deep_eq(roundtrip(snap), snap)
end)

--------------------------------------------------------------------------------
-- The real run snapshot
--------------------------------------------------------------------------------

suite.test("a snapshot built from live state round-trips unchanged", function()
    -- This is the case that actually ships: whatever build_run_snapshot produces must
    -- come back byte-for-byte equivalent.
    game.jokers = {}
    game.money = 33
    game.ante = 4
    local built = game:build_run_snapshot()
    T.assert_eq(type(built), "table", "build_run_snapshot should return a table")
    T.assert_deep_eq(roundtrip(built), built)
end)

suite.test("loading a legacy stone card removes its gameplay rank and suit", function()
    local game = bootstrap.new_game(4243)
    game.deck = {
        cards = { { rank = 14, suit = "Spades", enhancement = "stone" } },
        discard_pile = { { rank = 2, suit = "Clubs", enhancement = "stone" } },
    }
    local snapshot = game:build_run_snapshot()

    T.assert_true(game:load_run_snapshot(snapshot), "legacy snapshot should load")
    local deck_stone = game.deck.cards[1]
    local discard_stone = game.deck.discard_pile[1]
    T.assert_nil(deck_stone.rank, "saved deck Stone Card rank is migrated away")
    T.assert_nil(deck_stone.suit, "saved deck Stone Card suit is migrated away")
    T.assert_eq(deck_stone._stone_rank, 14, "saved deck face remains recoverable")
    T.assert_nil(discard_stone.rank, "saved discard Stone Card rank is migrated away")
    T.assert_nil(discard_stone.suit, "saved discard Stone Card suit is migrated away")
end)

--- `set_state(SELECTING_HAND)` check-points the run before `prepare_hand_for_new_blind` has
--- queued the deal, so a snapshot taken there describes a blind with no hand and no draw queue.
--- Nothing else refills a hand mid-blind, so resuming used to land on an empty playfield.
suite.test("resuming a blind that was saved before its deal deals the hand", function()
    local game = bootstrap.new_game(4245)
    game.STAGE = game.STAGES.RUN
    game.deck = Deck(game)
    game.hand = Hand(game)
    game.current_blind_index = 3
    local snapshot = game:build_run_snapshot()
    snapshot.resume_state = game.STATES.SELECTING_HAND
    T.assert_eq(#(snapshot.hand_cards or {}), 0, "the snapshot under test has no hand in it")

    T.assert_true(game:load_run_snapshot(snapshot), "snapshot should load")
    T.assert_eq(game.STATE, game.STATES.SELECTING_HAND)
    T.assert_true(#game.hand.cards + #game.hand._draw_queue > 0, "the hand is dealt on resume")
end)

suite.test("resuming a blind whose deck ran out leaves the hand empty", function()
    local game = bootstrap.new_game(4246)
    game.STAGE = game.STAGES.RUN
    game.deck = Deck(game)
    game.deck.cards = {}
    game.hand = Hand(game)
    local snapshot = game:build_run_snapshot()
    snapshot.resume_state = game.STATES.SELECTING_HAND

    T.assert_true(game:load_run_snapshot(snapshot), "snapshot should load")
    T.assert_eq(#game.hand.cards, 0)
    T.assert_eq(#game.hand._draw_queue, 0)
end)

suite.test("unique consumable usage survives a run snapshot", function()
    local game = bootstrap.new_game(4244)
    game:track_consumable_use({ id = "planet_mercury", kind = "planet" })
    game:track_consumable_use({ id = "planet_mercury", kind = "planet" })
    game:track_consumable_use({ id = "planet_venus", kind = "planet" })
    local snapshot = game:build_run_snapshot()

    T.assert_true(game:load_run_snapshot(snapshot), "snapshot should load")
    T.assert_eq(game.consumable_usage.planet_mercury.count, 2, "usage count is retained")
    T.assert_eq(game.consumable_usage.planet_venus.kind, "planet", "usage kind is retained")
end)

suite.test("write then read reports a saved run, and clearing removes it", function()
    love._test.reset_files()
    T.assert_false(game:has_saved_run(), "no run should be saved on a clean filesystem")

    T.assert_true(game:write_run_snapshot({ seed = 9 }), "write should succeed")
    T.assert_true(game:has_saved_run(), "a written run should be detected")

    T.assert_true(game:clear_run_snapshot(), "clear should succeed")
    T.assert_false(game:has_saved_run(), "a cleared run should no longer be detected")

    local decoded, err = game:read_run_snapshot()
    T.assert_nil(decoded, "reading a cleared run should return nil")
    T.assert_eq(err, "missing", "reading a cleared run should report why")
end)

suite.test("write_run_snapshot rejects a non-table", function()
    local ok, err = game:write_run_snapshot("not a snapshot")
    T.assert_false(ok, "a string is not a snapshot")
    T.assert_eq(err, "invalid_snapshot")
end)

suite.test("a corrupt save file is reported, not raised", function()
    love._test.reset_files()
    love.filesystem.createDirectory("sdmc")
    love.filesystem.write(game:run_save_path(), "return {this is not lua")
    local decoded, err = game:read_run_snapshot()
    T.assert_nil(decoded, "a syntactically broken save must not decode")
    T.assert_not_nil(err, "a broken save must report an error rather than raising")
end)

suite.test("a save that decodes to a non-table is rejected", function()
    love._test.reset_files()
    love.filesystem.createDirectory("sdmc")
    love.filesystem.write(game:run_save_path(), "return 42")
    local decoded, err = game:read_run_snapshot()
    T.assert_nil(decoded, "a save decoding to a number must be rejected")
    T.assert_eq(err, "decode_failed")
end)

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

suite.test("settings survive save then load", function()
    love._test.reset_files()

    game.SETTINGS = game.SETTINGS or {}
    game.SETTINGS.GAMESPEED = 2
    game.SETTINGS.SOUND = { volume = 70, music_volume = 40, sfx_volume = 90 }
    game.SETTINGS.GRAPHICS = { texture_scaling = 2 }

    local before = game:snapshot_settings()
    T.assert_true(game:save_settings(), "save_settings should succeed")

    -- Scramble live state so a no-op load cannot masquerade as a successful one.
    game.SETTINGS.GAMESPEED = 99
    game.SETTINGS.SOUND = { volume = 1, music_volume = 1, sfx_volume = 1 }

    T.assert_true(game:load_settings(), "load_settings should report a real load")
    local after = game:snapshot_settings()

    T.assert_deep_eq(after, before, "settings changed across a save/load cycle")
end)

suite.test("individual sound settings come back with their values", function()
    love._test.reset_files()
    game.SETTINGS.GAMESPEED = 4
    game.SETTINGS.SOUND = { volume = 55, music_volume = 25, sfx_volume = 85 }
    T.assert_true(game:save_settings())
    game.SETTINGS.SOUND = { volume = 0, music_volume = 0, sfx_volume = 0 }
    game:load_settings()

    T.assert_eq(game:get_master_volume(), 55, "master volume")
    T.assert_eq(game:get_music_volume(), 25, "music volume")
    T.assert_eq(game:get_sfx_volume(), 85, "sfx volume")
    T.assert_eq(tonumber(game.SETTINGS.GAMESPEED), 4, "game speed")
end)

suite.test("loading with no settings file falls back to defaults without raising", function()
    love._test.reset_files()
    local ok = game:load_settings()
    T.assert_false(ok, "a missing settings file should report that nothing was loaded")
    T.assert_eq(type(game.SETTINGS), "table", "defaults must still be installed")
    T.assert_not_nil(game.SETTINGS.GAMESPEED, "defaults must include a game speed")
end)

suite.test("a corrupt settings file falls back to defaults without raising", function()
    love._test.reset_files()
    love.filesystem.createDirectory("sdmc")
    love.filesystem.write(game:settings_save_path(), "return {{{")
    local ok = game:load_settings()
    T.assert_false(ok, "a corrupt settings file should not report success")
    T.assert_eq(type(game.SETTINGS), "table", "defaults must still be installed")
end)

suite.test("settings and run saves live at different paths per profile", function()
    local s1 = game:settings_path_for_profile(1)
    local s2 = game:settings_path_for_profile(2)
    local r1 = game:run_save_path_for_profile(1)
    local r2 = game:run_save_path_for_profile(2)

    T.assert_ne(s1, s2, "profiles must not share a settings file")
    T.assert_ne(r1, r2, "profiles must not share a run save")
    T.assert_ne(s1, r1, "settings and run save must not collide")
end)

--- The reference check-points on every state transition (`state_events.lua` `save_run()` at
--- draw-to-hand, shop, blind select and round eval). The port only wrote on deck-select,
--- save-and-quit and victory, so closing the lid mid-run lost the run.
suite.test("arriving at a stable state autosaves the run", function()
    local g = bootstrap.new_game(4101)
    g.STAGE = g.STAGES.RUN
    local writes = 0
    g.write_run_snapshot = function() writes = writes + 1 return true end

    g.STATE = g.STATES.MENU
    g:set_state(g.STATES.BLIND_SELECT)
    T.assert_eq(writes, 1, "blind select is a checkpoint")

    g:set_state(g.STATES.SELECTING_HAND)
    T.assert_eq(writes, 2, "so is the hand")

    g:set_state(g.STATES.SHOP)
    T.assert_eq(writes, 3, "and the shop")

    g:set_state(g.STATES.ROUND_EVAL)
    T.assert_eq(writes, 4, "and the cash-out")

    -- Re-entering the same state is not a new transition.
    g:set_state(g.STATES.ROUND_EVAL)
    T.assert_eq(writes, 4)

    -- Mid-scoring and mid-pack are not safe check-points.
    g.is_hand_scoring_active = function() return true end
    g:set_state(g.STATES.SELECTING_HAND)
    T.assert_eq(writes, 4, "scoring never autosaves")
    g.is_hand_scoring_active = function() return false end

    g:set_state(g.STATES.OPEN_BOOSTER)
    T.assert_eq(writes, 5, "an open pack check-points too, since its session serialises")

    -- Nothing is written outside a run.
    g.STAGE = g.STAGES.MENU
    g:set_state(g.STATES.BLIND_SELECT)
    T.assert_eq(writes, 5, "menu transitions never autosave")

    -- A restore drives the same transitions and must not write back over its own file.
    g.STAGE = g.STAGES.RUN
    g._restoring_run_snapshot = true
    g:set_state(g.STATES.SHOP)
    T.assert_eq(writes, 5, "restoring is silent")
    g._restoring_run_snapshot = nil
end)

--- Buying a pack removes it from the shop and takes the money before the session opens, so
--- a save inside the pack has to carry the session or the player loses both. The reference
--- serialises its pack CardArea with the rest of the run (`misc_functions.lua:1454-1459`).
suite.test("an open booster pack survives a save and reopens on its choices", function()
    local g = bootstrap.new_game(4102)
    g.STAGE = g.STAGES.RUN
    g.booster_session = {
        pack = "arcana",
        size = "normal",
        title = "Arcana Pack",
        picks_remaining = 1,
        hand_for_tarot = true,
        booster_sprite_index = 3,
        opening_phase = "buildup",
        opening_t = 0.2,
        choice_nodes = { "a live node that must not be serialised" },
        choices = {
            { kind = "tarot", consumable_def = { id = "tarot_magician" }, taken = false },
            { kind = "tarot", consumable_def = { id = "tarot_fool" }, taken = true },
        },
    }
    g._booster_return_state = g.STATES.SHOP

    local data = g:_serialize_booster_session()
    T.assert_eq(#data.choices, 2, "both choices are carried")
    T.assert_eq(data.choices[1].consumable_def.id, "tarot_magician")
    T.assert_true(data.choices[2].taken, "an already-taken choice stays taken")
    T.assert_eq(data.picks_remaining, 1)
    T.assert_eq(data.choice_nodes, nil, "live nodes are not serialised")

    -- It must survive the real encoder, not just an in-memory copy.
    local encoded = g:build_run_snapshot()
    T.assert_true(encoded.booster_session ~= nil, "the snapshot carries the session")

    local fresh = bootstrap.new_game(4103)
    fresh._booster_spawn_choice_nodes = function(_, choices) return { #choices } end
    T.assert_true(fresh:_restore_booster_session(data))
    T.assert_eq(fresh.booster_session.pack, "arcana")
    T.assert_eq(#fresh.booster_session.choices, 2)
    T.assert_eq(fresh.booster_session.picks_remaining, 1)
    T.assert_eq(fresh.booster_session.opening_phase, "ready", "it reopens past the buildup")
    T.assert_eq(fresh._booster_return_state, fresh.STATES.SHOP)

    T.assert_false(fresh:_restore_booster_session(nil), "an older save falls back to the shop")
    T.assert_false(fresh:_restore_booster_session({ choices = {} }))
end)

suite.test("two profiles' run saves do not overwrite each other", function()
    love._test.reset_files()
    love.filesystem.createDirectory("sdmc")
    love.filesystem.write(game:run_save_path_for_profile(1), "return { seed = 111 }")
    love.filesystem.write(game:run_save_path_for_profile(2), "return { seed = 222 }")

    local one = love.filesystem.load(game:run_save_path_for_profile(1))()
    local two = love.filesystem.load(game:run_save_path_for_profile(2))()
    T.assert_eq(one.seed, 111, "profile 1's run save")
    T.assert_eq(two.seed, 222, "profile 2's run save")
end)

return suite
