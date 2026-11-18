--- Save writes that do not stall the game (issue #94).
---
--- On some SD cards a truncating write spends over a second allocating a cluster, and the
--- autosave ran on every state change. These cover the fixes: in-place writes (`save_io.lua`),
--- the deferred and coalesced autosave, saving on pause instead of unpause, one check-point per
--- blind start, coalesced settings writes during a run, and the single-buffer encoder.

local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")
local SaveIO = require("save_io")

local suite = T.suite()

local love = bootstrap.load()

local function fresh_fs()
    love._test.reset_files()
    SaveIO.reset()
end

local function strip_padding(s)
    return (s:gsub("%s+$", ""))
end

--------------------------------------------------------------------------------
-- In-place writes
--------------------------------------------------------------------------------

suite.test("a save is written over the existing file, never truncated", function()
    fresh_fs()
    local truncating = 0
    local original = love.filesystem.write
    love.filesystem.write = function(...) truncating = truncating + 1 return original(...) end
    local ok, err = pcall(function()
        T.assert_true(SaveIO.write("sdmc/x.lua", "return { a = 1 }"))
        T.assert_true(SaveIO.write("sdmc/x.lua", "return { a = 2 }"))
    end)
    love.filesystem.write = original
    if not ok then error(err, 0) end
    T.assert_eq(truncating, 0, "no write went through the truncating path")
    T.assert_false(SaveIO.is_disabled())
    T.assert_eq(love.filesystem.load("sdmc/x.lua")().a, 2)
end)

suite.test("the file is padded to the unit and a shorter save leaves no stale tail", function()
    fresh_fs()
    local long = "return { s = \"" .. string.rep("x", 5000) .. "\" }"
    T.assert_true(SaveIO.write("sdmc/y.lua", long))
    local size = #love._test.files["sdmc/y.lua"]
    T.assert_eq(size % SaveIO.PAD_UNIT, 0, "padded to a whole unit")
    T.assert_true(size >= #long)

    T.assert_true(SaveIO.write("sdmc/y.lua", "return { s = \"short\" }"))
    local raw = love._test.files["sdmc/y.lua"]
    T.assert_eq(#raw, size, "the file does not shrink")
    T.assert_eq(strip_padding(raw), "return { s = \"short\" }", "only padding follows the new save")
    T.assert_eq(love.filesystem.load("sdmc/y.lua")().s, "short")
end)

suite.test("a runtime that ignores the seek falls back to plain writes", function()
    fresh_fs()
    local original = love.filesystem.openFile
    -- An append handle that always appends, as a POSIX O_APPEND handle would.
    love.filesystem.openFile = function(path, mode)
        local h = original(path, mode)
        local seek = h.seek
        h.seek = function(self) return seek(self, #(love._test.files[path] or "")) end
        return h
    end
    local ok, err = pcall(function()
        T.assert_true(SaveIO.write("sdmc/z.lua", "return { v = 1 }"))
        T.assert_true(SaveIO.write("sdmc/z.lua", "return { v = 2 }"))
    end)
    love.filesystem.openFile = original
    if not ok then error(err, 0) end
    T.assert_true(SaveIO.is_disabled(), "the read-back caught it")
    T.assert_eq(love.filesystem.load("sdmc/z.lua")().v, 2, "and the file is still right")
    SaveIO.reset()
end)

--------------------------------------------------------------------------------
-- Encoder
--------------------------------------------------------------------------------

--- The encoder this replaced, kept verbatim as the reference for its output.
local KEYWORDS = {}
for w in ("and break do else elseif end false for function goto if in local nil not or "
    .. "repeat return then true until while"):gmatch("%a+") do KEYWORDS[w] = true end
local function reference_encode(v)
    local tv = type(v)
    if tv == "nil" then return "nil" end
    if tv == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return "0" end
        return tostring(v)
    end
    if tv == "boolean" then return v and "true" or "false" end
    if tv == "string" then return string.format("%q", v) end
    if tv ~= "table" then return "nil" end
    local parts, n = {}, #v
    for i = 1, n do parts[#parts + 1] = reference_encode(v[i]) end
    for k, val in pairs(v) do
        if not (type(k) == "number" and k >= 1 and k <= n and math.floor(k) == k) then
            local key
            if type(k) == "string" and k:match("^[%a_][%w_]*$") and not KEYWORDS[k] then
                key = k
            else
                key = "[" .. reference_encode(k) .. "]"
            end
            parts[#parts + 1] = key .. "=" .. reference_encode(val)
        end
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

local function encoded_run_save(game, snapshot)
    T.assert_true(game:write_run_snapshot(snapshot))
    local raw = love._test.files[game:run_save_path()]
    return strip_padding(raw):gsub("^return ", "")
end

suite.test("the encoder's output is byte-identical to the one it replaced", function()
    fresh_fs()
    local game = bootstrap.new_game(5101)
    local tricky = {
        1, "two", { 3, { 4 } }, true,
        ["end"] = 1, ["with space"] = "q\"uote\\\n", [10] = 0.5, [-1] = -2,
        [1.5] = "frac", [true] = false, nan = 0 / 0, inf = math.huge, empty = {},
        nested = { a = { b = { c = { "deep" } } } },
    }
    T.assert_eq(encoded_run_save(game, tricky), reference_encode(tricky))

    game._pending_deck_id = "b_red"
    game._pending_stake_id = "stake_white"
    game:start_run_from_main_menu()
    local live = game:build_run_snapshot()
    T.assert_eq(encoded_run_save(game, live), reference_encode(live), "a live run snapshot")
end)

--------------------------------------------------------------------------------
-- Deferred autosave
--------------------------------------------------------------------------------

local function run_game(seed)
    fresh_fs()
    local game = bootstrap.new_game(seed)
    game._pending_deck_id = "b_red"
    game._pending_stake_id = "stake_white"
    game:start_run_from_main_menu()
    game:flush_pending_saves()
    love._test.reset_files()
    SaveIO.reset()
    game:forget_saved_run()
    return game
end

suite.test("a check-point's write waits, then lands once", function()
    local game = run_game(5102)
    local path = game:run_save_path()
    game.money = 11
    T.assert_true(game:autosave_run())
    game.money = 22
    T.assert_true(game:autosave_run(), "a second check-point in the same window")
    T.assert_nil(love._test.files[path], "nothing written yet")
    T.assert_true(game:has_saved_run(), "but Continue already counts it")

    game:update_pending_saves(0.3)
    T.assert_nil(love._test.files[path], "still waiting")
    game:update_pending_saves(0.4)
    T.assert_not_nil(love._test.files[path], "written once the delay passes")
    T.assert_eq(love.filesystem.load(path)().money, 22, "the newer check-point won")
    T.assert_false(game:has_pending_saves())
end)

suite.test("the check-point records its own moment, not the moment of the write", function()
    local game = run_game(5103)
    game.money = 7
    game:autosave_run()
    game.money = 99
    game:flush_pending_saves()
    T.assert_eq(love.filesystem.load(game:run_save_path())().money, 7)
end)

suite.test("clearing the run drops a held autosave so a finished run stays gone", function()
    local game = run_game(5104)
    game:autosave_run()
    game:clear_run_snapshot()
    game:update_pending_saves(5)
    T.assert_nil(love._test.files[game:run_save_path()])
    T.assert_false(game:has_saved_run())
end)

suite.test("an explicit save supersedes a held autosave", function()
    local game = run_game(5105)
    game.money = 1
    game:autosave_run()
    T.assert_true(game:write_run_snapshot({ seed = "EXPLICIT", money = 2 }))
    game:flush_pending_saves()
    T.assert_eq(love.filesystem.load(game:run_save_path())().money, 2)
end)

suite.test("reading the run save flushes a held autosave first", function()
    local game = run_game(5106)
    game.money = 33
    game:autosave_run()
    local snap = game:read_run_snapshot()
    T.assert_not_nil(snap)
    T.assert_eq(snap.money, 33)
end)

--------------------------------------------------------------------------------
-- Pause, blind start, settings
--------------------------------------------------------------------------------

suite.test("pausing check-points and writes; unpausing does not save", function()
    local game = run_game(5107)
    game:set_state(game.STATES.SHOP, { skip_autosave = true })
    local queued = 0
    local queue = game.queue_run_save
    game.queue_run_save = function(...) queued = queued + 1 return queue(...) end

    T.assert_true(game:enter_pause_menu())
    T.assert_eq(queued, 1, "entering pause check-points")
    T.assert_not_nil(love._test.files[game:run_save_path()], "and writes straight away")

    T.assert_true(game:exit_pause_menu())
    T.assert_eq(game.STATE, game.STATES.SHOP)
    T.assert_eq(queued, 1, "leaving pause does not")
end)

suite.test("a blind start check-points once, after the deal", function()
    local game = run_game(5108)
    local queued = 0
    local queue = game.queue_run_save
    game.queue_run_save = function(...) queued = queued + 1 return queue(...) end
    game.STATE = game.STATES.BLIND_SELECT
    game:prepare_hand_for_new_blind()
    T.assert_eq(game.STATE, game.STATES.SELECTING_HAND)
    T.assert_eq(queued, 1)
    game:flush_pending_saves()
    local snap = love.filesystem.load(game:run_save_path())()
    T.assert_eq(snap.resume_state, game.STATES.SELECTING_HAND)
end)

suite.test("settings writes during play wait for the next check-point", function()
    local game = run_game(5109)
    local path = game:settings_save_path()
    game.STATE = game.STATES.SHOP
    T.assert_true(game:save_settings())
    T.assert_true(game:save_settings())
    T.assert_nil(love._test.files[path], "deferred mid-run")
    T.assert_true(game:has_pending_saves())

    game:autosave_run()
    game:update_pending_saves(1)
    T.assert_not_nil(love._test.files[path], "went out with the run check-point")
    T.assert_false(game:has_pending_saves())
end)

suite.test("settings changed on the pause menu or outside a run save at once", function()
    local game = run_game(5110)
    local path = game:settings_save_path()
    game.STATE = game.STATES.PAUSED
    game:save_settings()
    T.assert_not_nil(love._test.files[path], "paused")

    love._test.reset_files()
    game.STAGE = game.STAGES.MAIN_MENU
    game.STATE = game.STATES.MENU
    game:save_settings()
    T.assert_not_nil(love._test.files[path], "main menu")
end)

suite.test("the end of a run writes whatever is held", function()
    local game = run_game(5111)
    game.STATE = game.STATES.SHOP
    game:save_settings()
    game:set_state(game.STATES.GAME_OVER)
    T.assert_not_nil(love._test.files[game:settings_save_path()])
    T.assert_false(game:has_pending_saves())
end)

return suite
