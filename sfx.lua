--- Cue playback: pooled voices, per-call pitch and volume, settings-aware mixing.
--- Cues are named ("chips1"), never paths, so a typo warns once in debug instead of
--- failing silently forever. Mirrors the reference game's sound_manager semantics.
---
--- LövePotion does run a pool thread (`audio.cpp:19`), but it is created without affinity
--- and so shares core 0 with the game; and `AudioPool::Update` holds the pool mutex across
--- a whole decode, which `Source::Play` then blocks on. Treat mixing as main-thread work.

local M = {}

local SOUND_DIR = "resources/sounds/"

--- Peak simultaneous voices per cue, sized from how many can legitimately overlap
--- during a scoring run. Anything unlisted gets DEFAULT_VOICES.
--- Voices past the first are allocated on demand, so this is a ceiling, not a cost.
local VOICES = {
    chips1 = 4, chips2 = 4, multhit1 = 4, multhit2 = 3, generic1 = 4,
    card1 = 4, cardSlide1 = 3, cardSlide2 = 3,
    coin1 = 2, coin2 = 2, coin3 = 3, coin6 = 2, coin7 = 2,
    tarot1 = 2, tarot2 = 3, foil1 = 2, foil2 = 2, holo1 = 2,
    polychrome1 = 2, paper1 = 3, whoosh1 = 3, whoosh2 = 2,
    highlight1 = 2, highlight2 = 2, button = 2, cancel = 3, gold_seal = 2,
    slice1 = 3, glass1 = 2, glass2 = 2, glass3 = 2, glass4 = 2, glass5 = 2, glass6 = 2,
    crumple1 = 2, crumple2 = 2, crumple3 = 2, crumple4 = 2, crumple5 = 2,
}
local DEFAULT_VOICES = 1

--- Long cues. These are streamed by the music manager, never pooled or decoded into
--- RAM: five concurrent Vorbis decodes is not viable on a 268 MHz ARM11.
local STREAMED = {
    music1 = true, music2 = true, music3 = true, music4 = true, music5 = true,
    ambientFire1 = true, ambientFire2 = true, ambientFire3 = true,
    ambientOrgan1 = true, splash_buildup = true,
}

--- Every non-streamed cue shipped in resources/sounds. This is the preload manifest,
--- not a whitelist: `play` still tries to load a code that is missing from here, it
--- just pays the SD read on first use. Add new sound files to this list.
local CUES = {
    "button", "cancel", "card1", "cardFan2", "cardSlide1",
    "cardSlide2", "chips1", "chips2", "coin1", "coin2", "coin3",
    "coin6", "coin7", "crumple1", "crumple2",
    "crumple3", "crumple4", "crumple5",
    "explosion_buildup1", "explosion_release1", "foil1", "foil2", "generic1", "glass1",
    "glass2", "glass3", "glass4", "glass5", "glass6", "gold_seal",
    "gong", "highlight1", "highlight2", "holo1", "multhit1", "multhit2",
    "negative", "other1", "paper1", "polychrome1", "slice1", "tarot1",
    "tarot2", "whoosh1", "whoosh2", "win",
}

--- Shared cue lists for the convenience wrappers. Module scope so a play call never
--- allocates a table.
local GLASS = { "glass1", "glass2", "glass3", "glass4", "glass5", "glass6" }

local pools = {}    -- code -> { voices, n, max, next, missing }
local data = {}     -- code -> SoundData|false (one decode per cue; released once no
                    -- further voice can be built from it, which on a runtime without
                    -- Source:clone means it stays resident for polyphonic cues)
local pitch_ok = nil -- nil until probed; false if LovePotion has no Source:setPitch
local clone_ok = nil -- nil until probed; false if LovePotion has no Source:clone

local function random(n)
    if love and love.math and love.math.random then return love.math.random(1, n) end
    return math.random(1, n)
end

--- Packaged 3DS builds ship PCM16 WAV; the repository keeps Vorbis sources because they
--- are a twentieth of the size and desktop has cycles to burn. WAV costs romfs bytes and
--- buys back the decode entirely — a static cue becomes a memcpy instead of ~15 ms of
--- Tremor at load, and a streamed bed stops competing with the soundtrack for the ARM11.
--- `dev/build.sh` does the conversion, so resolve per cue and cache the answer.
local path_cache = {}
local function sound_path(code)
    local path = path_cache[code]
    if path then return path end
    path = SOUND_DIR .. code .. ".wav"
    local fs = love and love.filesystem
    if not (fs and fs.getInfo and fs.getInfo(path)) then
        path = SOUND_DIR .. code .. ".ogg"
    end
    path_cache[code] = path
    return path
end

--- Decode a cue once. Returns false when love.sound is unavailable or the file will
--- not decode, in which case each voice loads from the path instead.
---@param code string
---@return love.SoundData|boolean
local function sound_data(code)
    local sd = data[code]
    if sd ~= nil then return sd end
    sd = false
    if love and love.sound and love.sound.newSoundData then
        local ok, res = pcall(love.sound.newSoundData, sound_path(code))
        if ok and res then sd = res end
    end
    data[code] = sd
    return sd
end

--- Release a cue's shared decode once nothing more will be built from it.
---@param code string
local function free_sound_data(code)
    local sd = data[code]
    if sd and sd.release then pcall(sd.release, sd) end
    data[code] = false
end

--- Build one Source for a cue from its own decode. Everything is pcall'd: this is a
--- 3DS target and API gaps are expected.
---@param code string
---@return love.Source|nil
local function new_voice(code)
    if not (love and love.audio and love.audio.newSource) then return nil end
    local path = sound_path(code)
    if sound_data(code) then
        local ok, src = pcall(love.audio.newSource, data[code], "static")
        if ok and src then return src end
        -- SoundData sources are not supported here; drop the decode, it is dead weight.
        free_sound_data(code)
    end
    local ok, src = pcall(love.audio.newSource, path, "static")
    if ok and src then return src end
    return nil
end

--- Source:clone shares the decoded buffer between voices; newSource(SoundData) copies
--- the PCM again. Probe once so the pools know which one they get, and so `preload`
--- knows whether the shared decodes can be handed back.
---@param src love.Source|nil a source to probe with
---@return boolean
local function clone_supported(src)
    if clone_ok ~= nil then return clone_ok end
    clone_ok = false
    if src and src.clone then
        local ok, c = pcall(src.clone, src)
        if ok and c then
            clone_ok = true
            if c.release then pcall(c.release, c) end
        end
    end
    return clone_ok
end

--- Add a voice to a pool that is fully busy but still under its ceiling.
---@param code string
---@param p table
---@return love.Source|nil
local function grow_voice(code, p)
    local template = p.voices[1]
    if clone_supported(template) then
        local ok, src = pcall(template.clone, template)
        if ok and src then return src end
    end
    return new_voice(code)
end

--- Fetch (and on first use create) the voice pool for a cue. Unknown cues are cached
--- as missing so repeat calls stay cheap.
---@param code string
---@return table|nil
local function pool_for(code)
    local p = pools[code]
    if p then return p end
    if STREAMED[code] then return nil end

    local first = new_voice(code)
    -- Read this after new_voice, which drops the decode if SoundData-backed Sources
    -- turn out to be unsupported.
    local shared = data[code] and true or false
    p = {
        voices = {},
        n = 0,
        max = VOICES[code] or DEFAULT_VOICES,
        next = 1,
    }
    if first then
        p.voices[1] = first
        p.n = 1
        if p.max == 1 then
            -- Monophonic cue: nothing else will ever be built from the decode.
            free_sound_data(code)
        elseif not shared then
            -- No shared decode to grow from, so build the pool now rather than paying
            -- a Vorbis decode mid-scoring.
            for _ = 2, p.max do
                local v = new_voice(code)
                if not v then break end
                p.n = p.n + 1
                p.voices[p.n] = v
            end
        end
    else
        p.missing = true
        if G and G.DEBUG then print("sfx: unknown cue '" .. tostring(code) .. "'") end
    end

    pools[code] = p
    return p
end

---@param code string cue name, e.g. "chips1"
---@param pitch number|nil playback rate, 1 = unmodified
---@param vol number|nil cue volume 0-1, before the master/sfx settings scale
---@return boolean played True if a voice was found and :play() was called
function M.play(code, pitch, vol)
    if G and G.F_MUTE then return false end
    if type(code) ~= "string" then return false end
    if STREAMED[code] then
        -- Streamed cues belong to the music manager, which does not exist yet.
        if G and G.DEBUG then print("sfx: '" .. code .. "' is streamed; Sfx.play does not play it") end
        return false
    end

    local p = pool_for(code)
    if not p or p.missing then return false end

    local sound = G and G.SETTINGS and G.SETTINGS.SOUND
    local master = tonumber(sound and sound.volume) or 100
    local game_sounds = tonumber(sound and sound.sfx_volume) or 100
    -- master/100 * sfx/100, folded into one multiply.
    local v = (tonumber(vol) or 1) * master * game_sounds * 0.0001
    if v <= 0.001 then return false end
    if v > 1 then v = 1 end

    local voices = p.voices
    local src
    for i = 1, p.n do
        local s = voices[i]
        if not s:isPlaying() then
            src = s
            break
        end
    end
    if not src and p.n < p.max then
        src = grow_voice(code, p)
        if src then
            p.n = p.n + 1
            voices[p.n] = src
        end
    end
    if not src then
        -- Every voice is busy: steal round-robin so a burst still layers instead of
        -- collapsing onto a single Source.
        local i = p.next
        if i > p.n then i = 1 end
        src = voices[i]
        p.next = (i % p.n) + 1
        src:stop()
    end

    if pitch_ok == nil then
        pitch_ok = pcall(src.setPitch, src, 1) and true or false
    end
    if pitch_ok then
        -- OpenAL rejects a pitch of 0 or less and the 3DS DSP divides by it.
        local per = tonumber(pitch) or 1
        src:setPitch(per > 0.05 and per or 0.05)
    end
    src:setVolume(v)
    src:play()
    return true
end

--- Play one cue picked at random.
--- Two forms: `play_random({ "a", "b" }, pitch, vol)` or `play_random("a", "b", "c")`.
--- The varargs form carries no pitch/vol; pass a list if you need them.
---@param codes string|string[]
---@param ... any pitch and vol, or further cue codes
---@return boolean played
function M.play_random(codes, ...)
    if type(codes) == "table" then
        local n = #codes
        if n == 0 then return false end
        return M.play(codes[random(n)], ...)
    end
    local extra = select("#", ...)
    if extra == 0 or type((select(1, ...))) ~= "string" then
        return M.play(codes, ...)
    end
    local idx = random(extra + 1)
    if idx == 1 then return M.play(codes) end
    return M.play((select(idx - 1, ...)))
end

--- Decode every non-streamed cue up front so nothing pays an SD read plus a Vorbis
--- decode mid-game. Safe to call before `G` exists.
---@param on_progress fun(done: integer, total: integer)|nil Called after each cue. This
---   is the slowest step of boot, so it is what drives the loading bar.
---@return integer loaded Count of cues with at least one usable voice.
function M.preload(on_progress)
    local loaded = 0
    local probe = nil
    for i = 1, #CUES do
        local p = pool_for(CUES[i])
        if p and not p.missing then
            loaded = loaded + 1
            probe = probe or p.voices[1]
        end
        if on_progress then on_progress(i, #CUES) end
    end
    -- If clones share the decoded buffer, the SoundDatas are a second copy of the same
    -- PCM and every extra voice can come from a clone instead. Give the RAM back.
    if clone_supported(probe) then
        for code in pairs(data) do free_sound_data(code) end
    end
    return loaded
end

--- Silence every pooled voice. Does not touch streamed music.
function M.stop_all()
    for _, p in pairs(pools) do
        local voices = p.voices
        for i = 1, p.n do
            pcall(voices[i].stop, voices[i])
        end
    end
end

--------------------------------------------------------------------------------
-- Music
--------------------------------------------------------------------------------
--
-- The reference game keeps all five stems playing at once and crossfades by volume.
-- That is five concurrent Vorbis decodes; on a 268 MHz ARM11 it is not an option, so
-- this manager keeps at most two streaming Sources alive at any instant: one outgoing
-- and one incoming.
--
-- Source:stop and Source:pause can wedge streaming audio on LovePotion (the same bug
-- the old Game:apply_music_volume worked around by muting with volume alone). So a
-- handoff is: open the incoming stream at volume 0, seek it to the outgoing stream's
-- timeline, ease the two past each other, and only stop the outgoing one once it has
-- been at volume 0 for a full frame. stop() is never called on an audible source.
--
-- The desired track is recomputed from live state every frame, so there is no queue to
-- keep: while a handoff is in flight a further change is simply not acted on until the
-- flight lands. The one exception is a change straight back to the outgoing track,
-- which reverses the crossfade in place instead of opening a third stream.

--- Per-second easing rate used by the reference game's soundtrack mixer. At 60 FPS
--- each stem moves 5% of the remaining distance toward its target every frame.
local MUSIC_FADE_RATE = 3
--- RESTART_MUSIC in the reference sound manager starts every theme at pitch 0.7 and
--- volume 0.6. The 3DS mixer does not reliably apply a live rate change to a Vorbis
--- stream, so the shipped music assets have the 0.7 pitch baked in and play at 1 here.
local MUSIC_BASE_PITCH = 1
local MUSIC_BASE_VOLUME = 0.6
--- Poll interval for the "did the stream stop on its own" watchdog. Looping is meant
--- to handle this; LovePotion is not always reliable about it, and isPlaying is not
--- cheap enough to call on both sources every frame.
local MUSIC_WATCHDOG = 0.5
--- Volume/pitch deltas smaller than this are not worth an audio API call. Without this
--- the steady state would setVolume twice a frame forever.
local MUSIC_EPSILON = 0.002

--- The two slots. Preallocated: a track change must not allocate, and neither must the
--- per-frame update.
local MUSIC_SLOTS = {
    { src = nil, code = nil, fade = 0, silent = 0, vol_set = -1, pitch_set = -1 },
    { src = nil, code = nil, fade = 0, silent = 0, vol_set = -1, pitch_set = -1 },
}
--- Slot index of the outgoing (or sole) track. Always valid.
local music_out = 1
--- Slot index of the incoming track, or nil when no handoff is in flight.
local music_in = nil
local music_pitch_ok = nil  -- nil until probed; false if streams reject setPitch
local music_watchdog = 0
--- Seconds to wait before retrying a stream that failed to open. Without it a bad SD
--- read would retry sixty times a second for the rest of the run.
local music_retry = 0

--- Master * music, 0-1. F_MUTE folds in here rather than into track selection, so a
--- muted run still tracks the right state and comes back in on the right track.
---@return number
local function music_gain()
    if G and G.F_MUTE then return 0 end
    local sound = G and G.SETTINGS and G.SETTINGS.SOUND
    local master = tonumber(sound and sound.volume) or 100
    local music = tonumber(sound and sound.music_volume) or 100
    local v = MUSIC_BASE_VOLUME * master * music * 0.0001
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

--- The track the current game state calls for, or nil to leave whatever is playing
--- alone. Mirrors reference/Balatro/functions/misc_functions.lua:724 mapped onto this
--- port: there is no live Blind object here, so "boss blind" is blind index 3 while a
--- blind is actually being played, and the pack particle systems the reference tests
--- for become booster_session.pack (celestial is the meteor pack, hence music3).
---@return string|nil
local function music_desired()
    local S = G and G.STATES
    if not S then return nil end
    local st = G.STATE
    -- The pause menu is an overlay, not a scene. Hold the underlying scene's track so
    -- pausing mid-handoff does not itself count as a track change.
    if st == S.PAUSED then st = G._pause_prev_state or st end
    if st == S.SPLASH then return nil end

    local sess = G.booster_session
    if sess then
        return (sess.pack == "celestial") and "music3" or "music2"
    end
    if st == S.SHOP then return "music4" end
    if (tonumber(G.current_blind_index) or 0) == 3
        and (st == S.SELECTING_HAND or st == S.HAND_PLAYED or st == S.DRAW_TO_HAND
            or st == S.PLAY_TAROT or st == S.NEW_ROUND or st == S.ROUND_EVAL
            or st == S.GAME_OVER) then
        return "music5"
    end
    return "music1"
end

--- Put a new stem at the same point in the composition as the stem already playing.
--- Balatro's themes are alternate arrangements of one timeline; crossfading two stems
--- from different timestamps sounds like a tempo jump even when both files are the
--- correct speed.
---@param src love.Source
---@param sync_src love.Source|nil
local function music_sync(src, sync_src)
    if not (sync_src and sync_src.tell and src.seek) then return end
    local ok, position = pcall(sync_src.tell, sync_src, "seconds")
    if not ok or type(position) ~= "number" or position < 0 then return end

    -- The stems differ by a few encoded samples. Keep a position at the very end of
    -- one stream inside the bounds of the incoming stream.
    if src.getDuration then
        local duration_ok, duration = pcall(src.getDuration, src, "seconds")
        if duration_ok and type(duration) == "number" and duration > 0 then
            position = position % duration
        end
    end
    pcall(src.seek, src, position, "seconds")
end

-- Streaming decode happens in one uninterruptible burst, and on ctr that burst blocks
-- everything else that wants to make noise: `AudioPool::Update` holds the pool mutex
-- across the whole decode (`sources.cpp:42-55`) and `Source::Play` needs that same mutex.
-- LövePotion's default decoder buffer is 16 KiB, which at 11025 Hz mono PCM16 is 0.74 s
-- of audio produced in a single call — tens of milliseconds of ARM11 held at once, and
-- twice that mid-crossfade, which is the frame drop `dev/build.sh` works around by
-- downsampling. A 4 KiB buffer quarters both the burst length and the linear-heap cost
-- per stream, and still leaves the pool thread refilling ~38x faster than it drains.
local STREAM_BUFFER_BYTES = 4096

--- Open a streaming Source with a small decoder buffer, falling back to the default path
--- on any runtime whose `love.sound.newDecoder` does not take a buffer size.
---@param path string
---@return love.Source|nil
local function new_stream(path)
    if love.sound and love.sound.newDecoder then
        local dec_ok, dec = pcall(love.sound.newDecoder, path, STREAM_BUFFER_BYTES)
        if dec_ok and dec then
            local src_ok, src = pcall(love.audio.newSource, dec, "stream")
            if src_ok and src then return src end
        end
    end
    local ok, src = pcall(love.audio.newSource, path, "stream")
    if ok then return src end
    return nil
end

--- Open a stream into a slot, playing but silent.
---@param slot table
---@param code string
---@param sync_src love.Source|nil stem whose playback position should be inherited
---@return boolean opened
local function music_open(slot, code, sync_src)
    if not (love and love.audio and love.audio.newSource) then return false end
    local src = new_stream(sound_path(code))
    if not src then
        if G and G.DEBUG then print("sfx: could not stream '" .. tostring(code) .. "'") end
        return false
    end
    pcall(src.setLooping, src, true)
    pcall(src.setVolume, src, 0)
    if music_pitch_ok == nil then
        music_pitch_ok = pcall(src.setPitch, src, MUSIC_BASE_PITCH) and true or false
    elseif music_pitch_ok then
        pcall(src.setPitch, src, MUSIC_BASE_PITCH)
    end
    slot.src = src
    slot.code = code
    slot.fade = 0
    slot.silent = 0
    slot.vol_set = 0
    slot.pitch_set = MUSIC_BASE_PITCH
    music_sync(src, sync_src)
    pcall(src.play, src)
    return true
end

--- Stop and drop a slot's stream. Only ever called on a source already at volume 0.
---@param slot table
local function music_close(slot)
    local src = slot.src
    slot.src = nil
    slot.code = nil
    slot.fade = 0
    slot.silent = 0
    slot.vol_set = -1
    slot.pitch_set = -1
    if not src then return end
    pcall(src.stop, src)
    if src.release then pcall(src.release, src) end
end

--- Push a slot's fade and the soundtrack pitch out to its Source, skipping the call
--- when nothing moved.
---@param slot table
---@param gain number
---@param pitch number
local function music_apply(slot, gain, pitch)
    local src = slot.src
    if not src then return end
    local v = slot.fade * gain
    if v > 1 then v = 1 end
    local prev = slot.vol_set
    if prev < 0 or v - prev > MUSIC_EPSILON or prev - v > MUSIC_EPSILON
        or (v == 0 and prev ~= 0) or (v == 1 and prev ~= 1) then
        slot.vol_set = v
        pcall(src.setVolume, src, v)
    end
    if music_pitch_ok then
        prev = slot.pitch_set
        if prev < 0 or pitch - prev > MUSIC_EPSILON or prev - pitch > MUSIC_EPSILON then
            slot.pitch_set = pitch
            pcall(src.setPitch, src, pitch)
        end
    end
end

--- Ease G.PITCH_MOD toward its target. The reference drops the whole soundtrack to
--- half speed on game over (misc_functions.lua:734); this is the same easing.
---@param dt number
---@return number
local function music_step_pitch(dt)
    if not G then return 1 end
    local S = G.STATES
    local target = (S and G.STATE == S.GAME_OVER) and 0.5 or 1
    local pm = tonumber(G.PITCH_MOD) or 1
    pm = pm * (1 - dt) + dt * target
    if pm < 0.05 then pm = 0.05 elseif pm > 1 then pm = 1 end
    G.PITCH_MOD = pm
    return pm
end

--- Drive the crossfade. Called every frame from `M.update` with unscaled dt, so a
--- GAMESPEED change never retunes the soundtrack.
---@param dt number
local function music_update(dt)
    dt = tonumber(dt) or 0
    -- A frame hitch (SD read, HOME menu resume) must not blow past the fade in one go
    -- and it must not run the pitch easing unstable.
    if dt < 0 then dt = 0 elseif dt > 0.1 then dt = 0.1 end

    local gain = music_gain()
    local pitch = MUSIC_BASE_PITCH * music_step_pitch(dt)
    local out = MUSIC_SLOTS[music_out]
    local inc = music_in and MUSIC_SLOTS[music_in] or nil
    local want = music_desired()

    if music_retry > 0 then music_retry = music_retry - dt end

    if want and want ~= out.code then
        if not inc and music_retry <= 0 then
            -- Nothing in flight: open the new track alongside and start the handoff.
            local slot = MUSIC_SLOTS[3 - music_out]
            if music_open(slot, want, out.src) then
                music_in = 3 - music_out
                inc = slot
            else
                music_retry = 1
            end
        end
        -- With a handoff already in flight, a third target waits: acting now would mean
        -- either three streams or a stop() on an audible one. The desire is recomputed
        -- every frame, so it is picked up as soon as this handoff lands.
    elseif want and inc and want == out.code then
        -- Snapped back to the outgoing track mid-handoff (shop -> blind -> shop). Swap
        -- the roles and the crossfade simply runs the other way.
        music_out, music_in = music_in, music_out
        out, inc = inc, out
    end

    local blend = dt * MUSIC_FADE_RATE
    if blend > 1 then blend = 1 end
    if inc then
        -- Match SET_SFX in the reference sound manager: ease by a fraction of the
        -- remaining distance instead of ending a linear ramp abruptly.
        out.fade = out.fade * (1 - blend)
        inc.fade = blend + inc.fade * (1 - blend)
        if out.fade < MUSIC_EPSILON then out.fade = 0 end
        if inc.fade > 1 - MUSIC_EPSILON then inc.fade = 1 end
    elseif out.fade < 1 then
        out.fade = blend + out.fade * (1 - blend)
        if out.fade > 1 - MUSIC_EPSILON then out.fade = 1 end
    end

    music_apply(out, gain, pitch)
    if inc then music_apply(inc, gain, pitch) end

    if inc and out.fade <= 0 then
        -- Volume 0 has been pushed to the Source above. Give it one whole frame at zero
        -- before stopping it: stop() on an audible stream is what wedges the mixer.
        if out.silent >= 1 then
            music_close(out)
            music_out, music_in = music_in, nil
        else
            out.silent = out.silent + 1
        end
    elseif inc then
        out.silent = 0
    end

    -- Looping is supposed to make this impossible, but a stream that ends and stays
    -- ended is silent for the rest of the run, which is worse than an occasional poll.
    music_watchdog = music_watchdog + dt
    if music_watchdog >= MUSIC_WATCHDOG then
        music_watchdog = 0
        local slot = MUSIC_SLOTS[music_out]
        if slot.src and slot.fade > 0 then
            local ok, playing = pcall(slot.src.isPlaying, slot.src)
            if ok and playing == false then
                pcall(slot.src.setLooping, slot.src, true)
                pcall(slot.src.play, slot.src)
            end
        end
    end
end

--- Start the soundtrack. Opens the track the current state calls for at full volume
--- rather than fading it in, so boot and a resumed run both start on the beat.
function M.music_start()
    local want = music_desired()
    if not want then return false end
    local slot = MUSIC_SLOTS[music_out]
    if slot.code == want then return true end
    if slot.src then music_close(slot) end
    if not music_open(slot, want) then return false end
    slot.fade = 1
    music_apply(slot, music_gain(), MUSIC_BASE_PITCH * (tonumber(G and G.PITCH_MOD) or 1))
    return true
end

--- Re-read the volume settings and push them out now. Called from
--- Game:apply_music_volume so the pause slider tracks the drag without a frame of lag.
function M.music_refresh()
    local gain = music_gain()
    local pitch = MUSIC_BASE_PITCH * (tonumber(G and G.PITCH_MOD) or 1)
    music_apply(MUSIC_SLOTS[music_out], gain, pitch)
    if music_in then music_apply(MUSIC_SLOTS[music_in], gain, pitch) end
end

--- The track currently being faded up, for tests and debug overlays.
---@return string|nil code
---@return number fade 0-1
function M.music_track()
    local slot = music_in and MUSIC_SLOTS[music_in] or MUSIC_SLOTS[music_out]
    return slot.code, slot.fade
end

M.music_update = music_update

-- Ambient beds: the reference runs continuous fire/organ loops whose volume tracks the
-- score flames (`reference/Balatro/functions/misc_functions.lua:750-759`) — the "score is
-- getting scary" layer under a big hand. Two beds only (the reference's main fire plus the
-- organ), because each is one more stream competing for the audio pool's mutex.
local AMBIENT_BEDS = {
    -- Per-bed pitch offsets are the reference's (`misc_functions.lua:759`).
    { code = "ambientFire2", pitch = 1.05 },
    { code = "ambientOrgan1", pitch = 0.7 },
}
local ambient_slots = nil
local ambient_targets = { fire = 0, organ = 0 }
local ambient_target_age = 1

--- Feed the beds this frame's intensity, 0-1 each. Called from the flame update; if the
--- caller goes away (menu, game over) the targets age out and the beds fade to silence.
---@param fire number
---@param organ number
function M.ambient_set_levels(fire, organ)
    ambient_targets.fire = tonumber(fire) or 0
    ambient_targets.organ = tonumber(organ) or 0
    ambient_target_age = 0
end

local function ambient_update(dt)
    if dt < 0 then dt = 0 elseif dt > 0.1 then dt = 0.1 end
    ambient_target_age = ambient_target_age + dt
    local fire = ambient_targets.fire
    local organ = ambient_targets.organ
    if ambient_target_age > 0.25 then
        fire, organ = 0, 0
    end
    -- Reference volume curves (`misc_functions.lua:751,754`), against the music gain so the
    -- beds ride the same sliders as the soundtrack they sit under.
    local gain = music_gain()
    local want = {
        fire * 0.9 * gain,
        organ * 0.6 * gain,
    }
    if not ambient_slots then
        -- Don't open the streams until a bed first wants to be audible.
        if want[1] <= 0.01 and want[2] <= 0.01 then return end
        ambient_slots = {}
        for i, bed in ipairs(AMBIENT_BEDS) do
            local src = new_stream(sound_path(bed.code))
            if src then
                pcall(src.setLooping, src, true)
                pcall(src.setVolume, src, 0)
                pcall(src.setPitch, src, bed.pitch)
                pcall(src.play, src)
                ambient_slots[i] = { src = src, vol = 0 }
            end
        end
    end
    for i, slot in pairs(ambient_slots) do
        -- The reference's smoothing: v = v*(1-dt) + dt*target (`misc_functions.lua:751`).
        slot.vol = slot.vol * (1 - dt) + dt * (want[i] or 0)
        pcall(slot.src.setVolume, slot.src, slot.vol)
    end
end

--- Test seam: report whether the beds may run here, without touching audio. The beds were
--- New 3DS only while they were Vorbis — a third decoder under a music crossfade is more
--- than an Old 3DS can carry. Packaged builds ship them as PCM16 WAV, which costs no
--- decode at all, so every console now runs them.
function M.ambient_enabled()
    return true
end

--- Called once per frame from love.update with unscaled dt.
--- Voices are reclaimed on demand in `play` (a busy pool is only walked when that cue
--- fires again), so there is deliberately no per-frame sweep: polling isPlaying across
--- every pooled Source every frame costs more on ARM11 than it saves.
---@param dt number seconds since the last frame, unaffected by GAMESPEED
function M.update(dt)
    -- Music manager seam: the streamed-track crossfade ticks from here.
    if M.music_update then M.music_update(dt) end
    ambient_update(tonumber(dt) or 0)
end

---@param pitch number|nil
---@param vol number|nil
--- A scoring payout. The reference always uses `coin3` for a `dollars` status text, pitched
--- up the scoring ladder (`common_events.lua:893`). Randomising across all seven coins meant
--- `coin7` (the cash-out chime) and `coin6` (the row total) turned up mid-scoring, where they
--- read as a different event entirely.
---@param pitch number|nil ladder pitch
---@param vol number|nil
function M.play_money(pitch, vol)
    return M.play("coin3", pitch, vol)
end

--- A UI button press. The reference fires the cue and a room jiggle from the same place
--- (`engine/ui.lua:989-990`: `play_sound('button', 1, 0.3)` alongside `G.ROOM.jiggle += 0.5`),
--- so every click nudges the world a little. Playing the cue without the nudge is what made
--- the port's buttons read as flat, so the two are bound together here rather than left to
--- each of the sixteen call sites to remember.
---@param pitch number|nil defaults to the reference's 1
---@param vol number|nil defaults to the reference's 0.3
function M.play_button(pitch, vol)
    local voice = M.play("button", pitch or 1, vol or 0.3)
    if G and G.shake then G:shake(0.5) end
    return voice
end

---@param pitch number|nil
---@param vol number|nil
function M.play_chips(pitch, vol)
    -- chips2 is the total-commit sting (`hand.lua`), never a scoring-ladder hit.
    return M.play("chips1", pitch, vol)
end

---@param pitch number|nil
---@param vol number|nil
function M.play_mult(pitch, vol)
    return M.play("multhit1", pitch, vol)
end

---@param pitch number|nil
---@param vol number|nil
function M.play_mult2(pitch, vol)
    return M.play("multhit2", pitch, vol)
end

---@param pitch number|nil
---@param vol number|nil
function M.play_glass_break(pitch, vol)
    return M.play_random(GLASS, pitch, vol)
end

return M
