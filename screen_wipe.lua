--- The cover a run is built behind.
---
--- Two problems, one module.
---
--- Starting a run is a few hundred milliseconds of blocking work -- two atlas uploads, the
--- deck rebuild, the autosave `set_state` fires on arrival at blind select -- and it all used
--- to land inside a single frame. Music cannot survive that. `sfx.lua` opens streams with a
--- 4 KiB decoder buffer (`sfx.lua:444`), which at the 11025 Hz mono `dev/build.sh` packages is
--- 0.19 s of audio per NDSP buffer, and a ctr Source gets two of them
--- (`platform/ctr/include/objects/source_ext.hpp:96`). Refills happen on LovePotion's
--- `PoolThread` (`source/utilities/pool/poolthread.cpp:23-38`), a `std::thread` that inherits
--- the main thread's priority and core, so it only runs when the main thread blocks. One frame
--- longer than the runway and the channel plays out -- an audible dropout on every new run.
---
--- The reference has the same work and covers it the same way: `G.FUNCS.start_run` brackets the
--- run build with `wipe_on`/`wipe_off` and runs it out of the event queue
--- (`reference/Balatro/functions/button_callbacks.lua:2958-2979`). Doing that here fixes the
--- audio as a consequence rather than as a separate patch: the work arrives as a list of steps,
--- one per frame, so every chunk ends in a `present` and the pool thread gets scheduled in
--- between.
---
--- What is not ported: the reference's cover is a single particle at scale 40 with a soft edge,
--- and the card dissolves out through a shader. Neither exists on the 3DS, so the cover is a
--- flat fill and the card leaves with it.

local ScreenWipe = {}

--- Cover fade in, minimum time covered, cover fade out. The reference runs about 1.8 s end to
--- end -- `wipe_on` flips its card at 0.7 s and `wipe_off` tears down at 1.1 s -- which is
--- tuned for a full-size window and a longer run build. A second is enough here.
local COVER_IN = 0.3
local HOLD_MIN = 0.35
local COVER_OUT = 0.35

--- The pinch rate every other card in the game flips at (`engine/moveable.lua:38`). Duplicated
--- rather than borrowed because the wipe has to draw while the scene graph is half torn down,
--- so it owns no `Moveable`.
local FLIP_RATE = 6
local FLIP_MIN_SX = 0.05

--- A step that uploads an atlas hands the *next* frame a dt larger than the whole transition.
--- Capped for the same reason `Game:_update_scene_transitions` caps its own (`game.lua:7572`):
--- running slightly long beats skipping the animation outright.
local MAX_STEP = 1 / 30

--- Base playing-card face in the `centers` atlas -- what `Card` defaults `face_index` to
--- (`card.lua:206`). The back comes from the selected deck instead.
local FACE_CENTER_INDEX = 1

--- Screen geometry, declared rather than measured. `love.graphics.getWidth` indexes the active
--- screen list by screen *id*, and with stereo off `Screen::BOTTOM` is 2 against a two-entry
--- list, so the runtime answers 400 for the 320-wide bottom screen -- the trap `stereo.lua`
--- documents at length and probes for. Every other draw site in the port declares its own
--- dimensions for the same reason (`main_menu_ui.lua:928`).
local TOP_W, BOTTOM_W = 400, 320
local SCREEN_H = 240

--- Suit block offsets into `cards_2`, as `Card:init` computes them (`card.lua:180-186`).
local SUIT_OFFSETS = { 0, 13, 26, 39 }

--- A random rank/suit cell for the card the wipe turns over, matching the reference's
--- `pseudorandom_element(G.P_CARDS)` (`button_callbacks.lua:3072`).
---
--- Drawn from `love.math.random`, never `math.random`: the run reseeds the latter for
--- reproducibility and a decoration must not advance it. Same reasoning as `card.lua:53`.
---@return integer
local function random_rank_index()
    local rnd = (love and love.math and love.math.random) or math.random
    local rank = rnd(2, 14)
    return (rank - 2) + SUIT_OFFSETS[rnd(1, 4)]
end

--- Begin a wipe over `steps`.
---
--- Each step is called with the game as its only argument, one per frame, and only while the
--- cover is fully opaque. A step that returns `false` abandons the ones after it and the cover
--- lifts on whatever state is there -- which is how a failed load gets back to the menu instead
--- of sitting under a cover forever.
---
--- `on_reveal` runs once, on the frame the cover starts lifting. It exists for entrance
--- animations: a slide started inside a step would have played out unseen.
---@param game Game
---@param steps function[]
---@param on_reveal fun(game: Game)|nil
---@return boolean started
function ScreenWipe.begin(game, steps, on_reveal)
    if not game then return false end
    -- A second wipe over a live one would run its steps against state the first is still
    -- building. The button that asked is behind the cover anyway (see `ScreenWipe.active`).
    if game.screenwipe then return false end

    game.screenwipe = {
        phase = "in",
        t = 0,
        alpha = 0,
        steps = type(steps) == "table" and steps or {},
        next_step = 1,
        on_reveal = on_reveal,
        flip = nil,
        flip_sx = 1,
        face_shown = false,
        -- The deck the player just picked, so the card under the cover is the one they chose.
        -- Asked for by id rather than through `get_selected_deck_back_index`, which prefers the
        -- *run's* deck: `apply_deck_config` is several steps away, so on the second run of a
        -- session that would still be the deck the last run used.
        back_index = (game.get_deck_back_index and game:get_deck_back_index(game._pending_deck_id)) or 0,
        face_index = FACE_CENTER_INDEX,
        rank_index = random_rank_index(),
    }
    return true
end

--- True while a wipe exists. Input is locked for exactly this long, as the reference locks it
--- for exactly as long as `G.screenwipe` is set (`engine/controller.lua:190`).
---@param game Game|nil
---@return boolean
function ScreenWipe.active(game)
    return game ~= nil and game.screenwipe ~= nil
end

--- True while the cover is opaque, meaning the scene behind it is not worth drawing.
---
--- Not just a saving. The first step frees the menu sheets, and several menu draw paths call
--- `ensure_asset_atlas_loaded`, so a menu frame between that step and the state change would
--- load them straight back in and the wipe would cost memory instead of saving it.
---@param game Game|nil
---@return boolean
function ScreenWipe.hides_scene(game)
    local w = game and game.screenwipe
    return w ~= nil and w.alpha >= 1
end

---@param w table
---@param dt number
local function update_flip(w, dt)
    if not w.flip then return end
    if w.flip == "in" then
        w.flip_sx = w.flip_sx - FLIP_RATE * dt
        if w.flip_sx <= FLIP_MIN_SX then
            w.flip_sx = FLIP_MIN_SX
            w.face_shown = true
            w.flip = "out"
        end
    else
        w.flip_sx = w.flip_sx + FLIP_RATE * dt
        if w.flip_sx >= 1 then
            w.flip_sx = 1
            w.flip = nil
        end
    end
end

--- Advance the wipe.
---
--- Returns true while the rest of the frame's game update should be skipped, which is the
--- reference holding `G.SETTINGS.paused` across the wipe (`button_callbacks.lua:2959`). Nothing
--- behind an opaque cover needs to animate, and a step leaves run state half built until the
--- next one runs. The uncover phase returns false so the scene comes back moving.
---@param game Game
---@param dt number real seconds
---@return boolean suppress_scene_update
function ScreenWipe.update(game, dt)
    local w = game and game.screenwipe
    if not w then return false end
    dt = tonumber(dt) or 0
    if dt > MAX_STEP then dt = MAX_STEP end

    update_flip(w, dt)

    if w.phase == "in" then
        w.t = w.t + dt
        w.alpha = w.t / COVER_IN
        if w.alpha >= 1 then
            w.alpha = 1
            w.phase = "work"
            w.t = 0
            -- The reference turns its card over once the cover is up, with the same cue
            -- (`button_callbacks.lua:3113-3119`).
            w.flip = "in"
            if Sfx and Sfx.play then Sfx.play("cardFan2") end
        end
        return true
    end

    if w.phase == "work" then
        w.t = w.t + dt
        local step = w.steps[w.next_step]
        if step then
            w.next_step = w.next_step + 1
            if step(game) == false then
                w.next_step = #w.steps + 1
            end
            -- One step per frame, always: the point of the split is the `present` between
            -- them. Falling through to the phase change here would put the last step and the
            -- uncover in the same frame and hand the audio thread nothing.
            return true
        end
        if w.t >= HOLD_MIN then
            w.phase = "out"
            w.t = 0
            if w.on_reveal then
                local reveal = w.on_reveal
                w.on_reveal = nil
                reveal(game)
            end
        end
        return true
    end

    w.t = w.t + dt
    w.alpha = 1 - w.t / COVER_OUT
    if w.alpha <= 0 then
        game.screenwipe = nil
    end
    return false
end

--- The card, on the bottom screen only -- it is the playfield, and the top screen is a readout.
---@param game Game
---@param w table
---@param cx number
---@param cy number
local function draw_card(game, w, cx, cy)
    local atlas = game.ASSET_ATLAS and game.ASSET_ATLAS.centers
    if not (atlas and atlas.image and game.atlas_cell_quad) then return end

    local index = w.face_shown and w.face_index or w.back_index
    local quad, cw, ch = game:atlas_cell_quad(atlas, index)
    if not quad then return end

    love.graphics.setColor(1, 1, 1, w.alpha)
    love.graphics.draw(atlas.image, quad, cx, cy, 0, w.flip_sx, 1, cw * 0.5, ch * 0.5)

    -- Rank and suit are a second sheet laid over the face (`card.lua:1044-1078`). `cards_2` is
    -- one of the sheets the run start is loading, so early in the wipe it may not be resident
    -- yet -- the face just reads blank for those frames rather than the draw failing.
    if not w.face_shown then return end
    local ranks = game.ASSET_ATLAS.cards_2
    if not (ranks and ranks.image) then return end
    local rquad, rw, rh = game:atlas_cell_quad(ranks, w.rank_index)
    if not rquad then return end
    love.graphics.draw(ranks.image, rquad, cx, cy, 0, w.flip_sx, 1, rw * 0.5, rh * 0.5)
end

--- Draw the cover over whichever screen is being walked. Called once per screen per frame from
--- `love.draw`, outside the shake translate: the wipe is not part of the playfield.
---@param game Game|nil
---@param screen string|nil screen name from `love.draw`
function ScreenWipe.draw(game, screen)
    local w = game and game.screenwipe
    if not w or w.alpha <= 0 then return end
    if not (love and love.graphics and love.graphics.rectangle) then return end

    local sw = (screen == "bottom") and BOTTOM_W or TOP_W

    local c = (game.C and game.C.BLACK) or { 0, 0, 0, 1 }
    love.graphics.setColor(c[1], c[2], c[3], w.alpha)
    love.graphics.rectangle("fill", 0, 0, sw, SCREEN_H)

    if screen == "bottom" then
        draw_card(game, w, sw * 0.5, SCREEN_H * 0.5)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

return ScreenWipe
