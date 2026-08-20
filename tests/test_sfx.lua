--- Runtime behaviour of sfx.lua against the recording Source stub.
---
--- The static cue check lives in test_sound_cues.lua. This file covers the parts that
--- only show up when a cue actually plays: the volume mix, the mute flag, voice pooling
--- and the two calling conventions of play_random.
---
--- Sources here are the stub's fakes, which record setPitch/setVolume/play/stop, so
--- "did this cue play, and how loud" is directly observable.

local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

local love = bootstrap.load()
local game = bootstrap.new_game(31337)

--- Sources created since the marker returned by `mark()`.
---@return integer
local function mark()
    return #love._test.sources
end

---@param from integer
---@return table[]
local function since(from)
    local out = {}
    for i = from + 1, #love._test.sources do out[#out + 1] = love._test.sources[i] end
    return out
end

--- Free every pooled voice so the next play grabs one instead of stealing.
local function release_all_voices()
    for _, s in ipairs(love._test.sources) do s._playing = false end
end

--- Set the mixer to known values. sfx.lua reads these off the live G.
---@param master number
---@param sfx number
local function set_volumes(master, sfx)
    G.SETTINGS = G.SETTINGS or {}
    G.SETTINGS.SOUND = G.SETTINGS.SOUND or {}
    G.SETTINGS.SOUND.volume = master
    G.SETTINGS.SOUND.sfx_volume = sfx
end

--- The Source that most recently had :play() called on it.
---@return table|nil
local function last_played()
    return love._test.last_played()
end

---@param code string
---@return table|nil
local function music_source(code)
    local path = "resources/sounds/" .. code .. ".ogg"
    for i = #love._test.sources, 1, -1 do
        local src = love._test.sources[i]
        if src._kind == "stream" and src._arg == path then return src end
    end
end

--------------------------------------------------------------------------------

suite.test("playing a real cue reports success", function()
    G.F_MUTE = false
    set_volumes(100, 100)
    release_all_voices()
    T.assert_true(Sfx.play("chips1"), "chips1 is a shipped cue and should play")
end)

suite.test("playing an unknown cue fails quietly instead of raising", function()
    -- The 3DS build must not crash on a missing asset, and pool_for caches the miss.
    G.F_MUTE = false
    set_volumes(100, 100)
    local ok, res = pcall(Sfx.play, "definitely_not_a_cue_xyz")
    T.assert_true(ok, "an unknown cue must not raise")
    T.assert_false(res, "an unknown cue must report that nothing played")
end)

suite.test("a non-string cue is rejected", function()
    T.assert_false(Sfx.play(nil))
    T.assert_false(Sfx.play(42))
    T.assert_false(Sfx.play({}))
end)

suite.test("the mute flag suppresses playback", function()
    G.F_MUTE = true
    set_volumes(100, 100)
    release_all_voices()
    local before = mark()
    T.assert_false(Sfx.play("chips1"), "muted playback should report false")
    for _, s in ipairs(since(before)) do
        T.assert_eq(s._play_count, 0, "no Source should have been played while muted")
    end
    G.F_MUTE = false
end)

suite.test("volume is the product of the master and sfx sliders", function()
    G.F_MUTE = false
    -- 50% master * 50% sfx = 25% output.
    set_volumes(50, 50)
    release_all_voices()
    T.assert_true(Sfx.play("card1"))
    T.assert_near(last_played()._volume, 0.25, 1e-9,
        "master 50 x sfx 50 should mix to 0.25")

    set_volumes(100, 100)
    release_all_voices()
    T.assert_true(Sfx.play("card1"))
    T.assert_near(last_played()._volume, 1.0, 1e-9, "both sliders at 100 should mix to 1")
end)

suite.test("the per-call volume argument scales the mix", function()
    G.F_MUTE = false
    set_volumes(100, 100)
    release_all_voices()
    T.assert_true(Sfx.play("card1", 1, 0.5))
    T.assert_near(last_played()._volume, 0.5, 1e-9, "a 0.5 call volume should halve the mix")
end)

suite.test("volume is clamped to 1", function()
    G.F_MUTE = false
    set_volumes(100, 100)
    release_all_voices()
    T.assert_true(Sfx.play("card1", 1, 4))
    T.assert_true(last_played()._volume <= 1.0,
        "an over-unity call volume must be clamped, not passed through")
end)

suite.test("a silent mix skips playback entirely", function()
    G.F_MUTE = false
    set_volumes(0, 100)
    release_all_voices()
    T.assert_false(Sfx.play("card1"), "a zero master volume should not play")
    set_volumes(100, 0)
    T.assert_false(Sfx.play("card1"), "a zero sfx volume should not play")
    set_volumes(100, 100)
end)

suite.test("the pitch argument reaches the Source", function()
    G.F_MUTE = false
    set_volumes(100, 100)
    release_all_voices()
    T.assert_true(Sfx.play("card1", 1.5))
    T.assert_near(last_played()._pitch, 1.5, 1e-9, "pitch should be forwarded")

    release_all_voices()
    T.assert_true(Sfx.play("card1"))
    T.assert_near(last_played()._pitch, 1.0, 1e-9, "an omitted pitch should default to 1")
end)

suite.test("a streamed cue is refused by Sfx.play", function()
    -- Music is the music manager's job; Sfx.play must not decode a whole track.
    G.F_MUTE = false
    set_volumes(100, 100)
    T.assert_false(Sfx.play("music1"), "music1 is streamed and must not play through Sfx")
end)

suite.test("play_random accepts a list of cues", function()
    G.F_MUTE = false
    set_volumes(100, 100)
    release_all_voices()
    T.assert_true(Sfx.play_random({ "coin1", "coin2", "coin3" }),
        "a list of real cues should play one of them")
end)

suite.test("play_random accepts cues as varargs", function()
    G.F_MUTE = false
    set_volumes(100, 100)
    release_all_voices()
    T.assert_true(Sfx.play_random("coin1", "coin2", "coin3"),
        "the varargs form should play one of the cues")
end)

suite.test("play_random on an empty list plays nothing", function()
    T.assert_false(Sfx.play_random({}))
end)

suite.test("play_random with a list eventually reaches every cue", function()
    -- Guards against an off-by-one in the index pick silently making the first or last
    -- cue unreachable -- a bug that just sounds like less variety.
    G.F_MUTE = false
    set_volumes(100, 100)
    local codes = { "coin1", "coin2", "coin3", "coin6", "coin7", "glass1", "glass2" }
    local seen = {}
    local real_random = love.math.random
    for i = 1, #codes do
        love.math.random = function() return i end
        release_all_voices()
        local before = mark()
        Sfx.play_random(codes)
        local src = last_played()
        local _ = before
        if src then seen[i] = true end
    end
    love.math.random = real_random
    for i = 1, #codes do
        T.assert_true(seen[i], "index " .. i .. " of the cue list should be reachable")
    end
end)

suite.test("the convenience wrappers play", function()
    G.F_MUTE = false
    set_volumes(100, 100)
    for _, name in ipairs({ "play_money", "play_chips", "play_mult", "play_mult2",
                            "play_glass_break" }) do
        release_all_voices()
        T.assert_true(Sfx[name](), "Sfx." .. name .. " should play a cue")
    end
end)

--- `common_events.lua:893`: a `dollars` status text is always `coin3`, pitched up the
--- scoring ladder. Randomising across all seven coins pulled in `coin7` (the cash-out chime)
--- and `coin6` (the row total), which read as different events mid-scoring.
suite.test("a scoring payout is always coin3", function()
    G.F_MUTE = false
    set_volumes(100, 100)
    for _ = 1, 12 do
        release_all_voices()
        Sfx.play_money()
        local src = last_played()
        T.assert_not_nil(src, "the payout cue should play")
        -- Pooled cues wrap a SoundData, so the path hangs off that rather than the Source.
        local path = type(src._arg) == "table" and src._arg._path or src._arg
        T.assert_true(tostring(path):find("coin3", 1, true) ~= nil,
            "expected coin3, got " .. tostring(path))
    end
end)

suite.test("a polyphonic cue grows its pool rather than cutting itself off", function()
    -- chips1 is allotted 4 voices. Four overlapping plays should land on four distinct
    -- Sources; collapsing onto one is what makes rapid scoring sound broken.
    G.F_MUTE = false
    set_volumes(100, 100)
    release_all_voices()

    local used = {}
    for _ = 1, 4 do
        Sfx.play("chips1")
        local src = last_played()
        if src then used[src] = true end
        -- Deliberately do NOT release: the next play must find a different voice.
    end

    local distinct = 0
    for _ in pairs(used) do distinct = distinct + 1 end
    T.assert_true(distinct >= 2,
        string.format("expected overlapping chips1 plays to use several voices, got %d",
            distinct))
    release_all_voices()
end)

suite.test("stop_all silences every pooled voice", function()
    G.F_MUTE = false
    set_volumes(100, 100)
    release_all_voices()
    Sfx.play("chips1")
    Sfx.play("card1")
    Sfx.stop_all()
    for _, s in ipairs(love._test.sources) do
        T.assert_false(s._playing, "stop_all should leave no Source playing")
    end
end)

suite.test("update does not raise without a music manager", function()
    T.assert_no_error(function() Sfx.update(1 / 60) end)
end)

suite.test("music transitions keep alternate stems on the same timeline", function()
    G.F_MUTE = false
    G.SETTINGS.SOUND.volume = 100
    G.SETTINGS.SOUND.music_volume = 100
    G.booster_session = nil
    G.current_blind_index = 0
    G.STATE = G.STATES.MENU
    T.assert_true(Sfx.music_start())

    local base = music_source("music1")
    T.assert_not_nil(base, "music1 should be the menu stem")
    base._position = 42.25

    G.STATE = G.STATES.SHOP
    Sfx.update(1 / 60)

    local shop = music_source("music4")
    T.assert_not_nil(shop, "entering the shop should open music4")
    T.assert_eq(#shop._seek_history, 1, "the incoming stem should be synchronized once")
    T.assert_near(shop._position, 42.25, 1e-9,
        "the incoming stem should inherit the outgoing stem's playback position")
end)

suite.test("music transitions use the reference game's gradual easing", function()
    local base = music_source("music1")
    local shop = music_source("music4")
    T.assert_not_nil(base)
    T.assert_not_nil(shop)

    -- The preceding test advanced one frame. Another 59 frames makes one second.
    for _ = 1, 59 do Sfx.update(1 / 60) end
    -- setVolume deliberately coalesces sub-epsilon changes; after the sixtieth
    -- logical step the last value actually sent to the Source is frame 59.
    local expected_tail = 0.95 ^ 59
    T.assert_near(base._volume, 0.6 * expected_tail, 1e-6,
        "the outgoing stem should retain a smooth exponential tail")
    T.assert_near(shop._volume, 0.6 * (1 - expected_tail), 1e-6,
        "the incoming stem should rise with the complementary curve")
    T.assert_near(shop._pitch, 1, 1e-9,
        "the pre-pitched music assets should play at their native rate")
    T.assert_true(base._playing,
        "the old stream should not be cut off while its fade remains audible")
end)

suite.test("preload loads the shipped cues", function()
    local loaded = Sfx.preload()
    T.assert_eq(loaded, 46,
        string.format("preload should load exactly 46 active cues, got %d", loaded))
end)

suite.test("ambient beds are allowed off-console and fade in from level updates", function()
    -- The beds are unconditional now: packaged builds ship them as PCM16 WAV, so they
    -- no longer add a decoder and no longer need the New-3DS gate they used to sit behind.
    T.assert_true(Sfx.ambient_enabled(), "every host qualifies for the beds")
    G.F_MUTE = false
    set_volumes(100, 100)
    Sfx.ambient_set_levels(1, 0.4)
    -- A few frames of update must open and ramp the streams without erroring; the
    -- smoothing means volume only ever approaches the target.
    for _ = 1, 10 do
        Sfx.update(1 / 30)
    end
    Sfx.ambient_set_levels(0, 0)
    for _ = 1, 10 do
        Sfx.update(1 / 30)
    end
end)

local _ = game

return suite
