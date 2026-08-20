local raw_print = print
function print(...)
    if G and G.DEBUG then
        raw_print(...)
    end
end

local nest_ok, nest = pcall(function()
    return require("nest").init({ console = "3ds" })
end)

-- Startup is slow enough on hardware to look like a hang, so the bar goes up before
-- anything else is required and is stepped through the rest of boot. Loading is
-- deliberately free of dependencies; see the header there.
local Loading = require "loading"
Loading.step(0)

require "engine.object"
require "engine.node"
require "engine.moveable"
require "engine.sprite"
require "card"
require "deck"
require "hand"
Loading.step(0.08)
require "joker"
require "joker_catalog"
require "joker_unlocks"
require "shop_nodes"
require "consumable"
Loading.step(0.16)
-- game.lua is ~490 KB of source on its own; it is the single longest require.
require "game"
Loading.step(0.34)
require "globals"
require "consumable_catalog"
require "voucher_catalog"
require "topUI"
require "popup"
require "tag"
require("deck_catalog")
require("challenge_catalog")
Loading.step(0.42)
local YouWinUI = require "you_win"
local MainMenuUI = require "main_menu_ui"
local ProfileUI = require "profile_ui"
local DeckViewUI = require "deck_view_ui"
local InputBindings = require "input_bindings"
local RenderProfiler = require "render_profiler"
local PerformanceLab = require "performance_lab"
local Stereo = require "stereo"
local Backdrop = require("backdrop")
local Tilt = require "tilt"
local ScreenWipe = require "screen_wipe"
Sfx = require "sfx"
Fx = require "fx"
Loading.step(0.5)

-- Keyboard aliases for gamepad buttons (desktop testing).
local KEY_TO_GAMEPAD = {
    z = "a",
    x = "b",
    c = "x",
    v = "y",
    q = "leftshoulder",
    e = "rightshoulder",
    a = "lefttrigger",
    d = "righttrigger",
    up = "dpup",
    down = "dpdown",
    left = "dpleft",
    right = "dpright",
    escape = "start",
    rshift = "back",
}

local function key_to_gamepad_button(key)
    return KEY_TO_GAMEPAD[key]
end

local function set_role_hold_from_button(game, button, held)
    if not game or not game.get_role_for_button then return end
    local role = game:get_role_for_button(button)
    if not role or not InputBindings.HOLD_ROLES[role] then return end
    if held then
        game:set_role_held(role, true, love.timer.getTime())
    else
        game:set_role_held(role, false)
    end
end

function love.load()
    if InputBindings.detect_console_capabilities then
        InputBindings.detect_console_capabilities()
    end

    G = Game()
    Loading.step(0.6)
    -- After Game() so a cue that fails to decode can warn through G.DEBUG. 69 Vorbis
    -- decodes off SD is the longest single step of boot, so it drives the bar itself.
    Sfx.preload(Loading.slice(0.6, 0.9))
    G:enter_main_menu()
    Loading.step(0.97)
    Top = TopUI()

    -- Bakes the coarse dissolve fields a crowded animation falls back to, so a Mega pack's
    -- five simultaneous materialises do not all bake one on their first frame.
    Fx.prewarm_dissolve()

    -- The music manager owns every streamed track from here. It picks one from G.STATE
    -- and crossfades on its own off Sfx.update; this only kicks the first one off.
    Sfx.music_start()

    Loading.step(1)
end

--- The active blind controls the playfield wash. Bosses carry their own palette colour
--- (`reference/Balatro/game.lua:2144-2173`); read the selected boss directly so drawing never
--- invokes `get_boss_blind_prototype`, which may roll and mutate the seeded run RNG.
local function blind_background_color(game)
    local def = game:get_blind_def(tonumber(game.current_blind_index) or 2)
    if def and def.id == "boss" then
        local boss_id = game.current_boss_blind_id
        local boss = boss_id and game.P_BLINDS and game.P_BLINDS[boss_id]
        if boss and boss.boss_colour then return boss.boss_colour end
    end
    return (def and game.C.BLIND_COLORS[def.key]) or game.C.BLIND.Big
end

--- Per-state wash target. The reference re-eases the background on every state entry
--- (`reference/Balatro/functions/common_events.lua:311-345`): packs get their set's colour,
--- the shop and menus fall back to the Small Blind wash, everything else takes the blind.
local function background_target_color(game)
    local S = game.STATES
    if game.STATE == S.OPEN_BOOSTER and game.booster_session then
        local pack = game.booster_session.pack
        if pack == "arcana" then return game.C.PURPLE end
        if pack == "spectral" then return game.C.SECONDARY_SET.Spectral end
        if pack == "celestial" or pack == "standard" then return game.C.BLACK end
        if pack == "buffoon" then return game.C.L_BLACK end
        return game.C.BLACK
    end
    if game.STATE == S.SHOP then
        return game.C.BLIND_COLORS.Small
    end
    return blind_background_color(game)
end

--- Current eased wash, stored on the game so a fresh Game starts at its own target. Every
--- channel chases the target so state changes arrive as a ~0.6 s colour sweep instead of a
--- hard cut (`common_events.lua:291-293`). Advanced once per frame from `love.update`; it
--- used to run off the bottom-screen draw pass, guarded so the other passes did not double
--- the rate, which is a guard the update-time call does not need.
local function eased_background_color(game)
    local target = background_target_color(game)
    local wash = game._bg_wash
    if not wash then
        wash = { target[1], target[2], target[3], 1 }
        game._bg_wash = wash
        return wash
    end
    local dt = game.real_dt or 0
    local k = 1 - math.exp(-dt / 0.2)
    for i = 1, 3 do
        wash[i] = wash[i] + (target[i] - wash[i]) * k
    end
    return wash
end

function love.update(dt)
    -- Polled before anything draws. Switching stereo destroys and recreates the
    -- framebuffers (`renderer_ext.hpp:194-199`), so it can only happen outside the run
    -- loop's screen walk -- which is exactly where `love.update` sits.
    Stereo.update()

    -- Rolls the dissolve crowd count that picks the mask resolution. Here rather than in
    -- `love.draw`, which runs once per screen; see `Fx.begin_frame`.
    Fx.begin_frame()

    -- The backdrop runs on wall time and never pauses: the reference advances REAL_SHADER from
    -- G.real_dt, so the background keeps flowing while the game is paused or a modal is up.
    Backdrop.update(dt)

    -- Two clocks, as in the original (`game.lua:2495-2498`). `real_dt` is wall time; the
    -- scaled clock drives run sequencing and object updates. Physical motion, juice, input,
    -- shake and audio explicitly use real time at their update sites.
    G.real_dt = dt
    G.TIMERS.REAL = G.TIMERS.REAL + dt
    local logic_dt = dt * G:speed_factor(dt)
    G.TIMERS.TOTAL = G.TIMERS.TOTAL + logic_dt
    G:update(logic_dt, dt)
    -- The readout is not drawn under an opaque wipe and it reads run state the wipe is still
    -- assembling a step at a time, so it sits the covered frames out. `Game:update` bows out
    -- of them on its own. Audio never does -- the point of the whole transition is that the
    -- stream keeps being fed.
    if not ScreenWipe.hides_scene(G) then
        Top:update(logic_dt)
    end
    Sfx.update(dt)

    -- The run loop already clears every screen with the background colour before it calls
    -- `love.draw` (`callbacks.lua:276`), and nothing ever set that colour, so the playfield
    -- was cleared black and then cleared again with the wash -- a discarded full-screen
    -- fill per screen per frame. Handing the wash to the runtime makes the first clear the
    -- only clear. The menu paints its own background over the whole screen, so it is left
    -- out and its wash stays frozen where it was, as before.
    if G.STATE ~= G.STATES.MENU then
        local wash = eased_background_color(G)
        love.graphics.setBackgroundColor(wash[1], wash[2], wash[3], 1)
    end
end

function love.draw(screen)
    -- Nothing under an opaque wipe is worth drawing, and drawing it is not merely wasted: the
    -- first run-start step frees the menu sheets and several menu draw paths reload an atlas
    -- they find missing, so a menu frame in between would undo the free. See `screen_wipe.lua`.
    if ScreenWipe.hides_scene(G) then
        ScreenWipe.draw(G, screen)
        return
    end
    -- The backdrop is not a menu decoration in the reference: it is behind every screen, and
    -- the palette it uses is part of how a state reads. It only became menu-only here because
    -- the old implementation was a 4 MiB sprite sheet that could not stay resident during a
    -- run. It is generated now, so it goes everywhere.
    --
    -- The menu keeps its own path because that screen also paints a gradient fallback when the
    -- backdrop is unavailable, which every other screen already has its own background for.
    if G and G.STATE == G.STATES.MENU then
        MainMenuUI.draw_background(G, screen)
    elseif G then
        Backdrop.draw((screen == "bottom") and 320 or 400)
    end
    if screen == "bottom" then
        love.graphics.setColor(1, 1, 1)
        -- Screen shake is the playfield only: the top screen is a readout, and jittering
        -- text is just hard to read.
        local sx, sy = 0, 0
        if G and G.get_shake_offset then sx, sy = G:get_shake_offset() end
        if sx ~= 0 or sy ~= 0 then
            love.graphics.push()
            love.graphics.translate(sx, sy)
            G:draw()
            love.graphics.pop()
        else
            G:draw()
        end
    else
        if G and G.STATE == G.STATES.MENU then
            MainMenuUI.draw_top(screen, G)
        elseif G and G.STATE == G.STATES.YOU_WIN then
            YouWinUI.drawTop(G)
        elseif G._deck_view_open then
            DeckViewUI.draw_top(screen, G)
        else
            Top:draw(screen)
        end
    end

    -- Over everything, and outside the shake translate above: the cover is not part of the
    -- playfield. Only reached while the wipe is still fading in or out; once it is opaque the
    -- early-out at the top of this function has already drawn it.
    ScreenWipe.draw(G, screen)

    -- Capture before drawing the profiler itself. The counters accumulate across
    -- both 3DS screens and are committed when present() resets them next frame.
    --
    -- Gated with the draw, not just around it: `capture` allocates a stats table through
    -- pcall and shifts a 120-entry ring buffer, twice per frame (once per screen), and it was
    -- doing that in shipping builds where nothing ever reads the samples.
    if PerformanceLab.is_enabled("profiler") then
        RenderProfiler.capture()
        if screen == "bottom" and G then
            RenderProfiler.draw(G)
        end
    end
end

--- Button input takes the focus outline back from the touch screen.
local function note_button_input()
    if G and G.note_input_mode then G:note_input_mode("gamepad") end
end

--- Profile renaming swallows keys so letters do not double as gamepad shortcuts.
local function renaming_profile()
    return G and G.STATE == G.STATES.MENU and G._menu_sub_state == "profile"
        and ProfileUI.is_renaming(G)
end

function love.textinput(text)
    if G and MainMenuUI.is_editing_seed and MainMenuUI.is_editing_seed(G) then
        MainMenuUI.handle_seed_textinput(G, text)
        return
    end
    if renaming_profile() then
        ProfileUI.handle_textinput(G, text)
    end
end

function love.keypressed(key)
    if ScreenWipe.active(G) then return end
    if G and MainMenuUI.is_editing_seed and MainMenuUI.is_editing_seed(G) then
        MainMenuUI.handle_seed_key(G, key)
        return
    end
    if renaming_profile() then
        ProfileUI.handle_key(G, key)
        return
    end
    note_button_input()
    if key == "f1" then
        if G then G.DEBUG = not G.DEBUG end
        return
    end
    if key == "p" and G and G.DEBUG then
        if G.popups then
            local p = Popup()
            p:spawn("Nope!", "Nope", 160, 120, 3)
            G:addPopup(p)
            Top:addPopup(p)
        end
        return
    end

    if G and G.DEBUG then
        if key == "1" then
            G:add_joker_by_def(G:random_joker_def_id_by_rarity(1))
        elseif key == "2" then
            G:add_joker_by_def(G:random_joker_def_id_by_rarity(2))
        elseif key == "3" then
            G:add_joker_by_def(G:random_joker_def_id_by_rarity(3))
        elseif key == "4" then
            G:add_consumable(G:random_consumable_id_of_kind("tarot"))
       
        elseif key == "5" then
            G.money = G.money + 100
        elseif key == "6" then
            G:addTag("voucher")
        elseif key == "7" and G.give_random_unowned_voucher then
            G:give_random_unowned_voucher()
        elseif key == "8" and G.round_score then
            G.round_score = G.round_score + 100000000
        end
    end

    local button = key_to_gamepad_button(key)
    if button then
        love.gamepadpressed(nil, button)
    end
end

function love.keyreleased(key)
    local button = key_to_gamepad_button(key)
    if button and G and G.get_role_for_button then
        local role = G:get_role_for_button(button)
        if role and InputBindings.HOLD_ROLES[role] then
            love.gamepadreleased(nil, button)
        end
    end
end

function love.gamepadpressed(_, button)
    -- Locked for exactly as long as a wipe exists, which is how the reference locks its
    -- controller (`reference/Balatro/engine/controller.lua:190`). The scene under the cover is
    -- half built and its hitboxes are wherever the last frame left them.
    if ScreenWipe.active(G) then return end
    note_button_input()
    button = InputBindings.normalize_gamepad_button(button)
    if G and G.STATE == G.STATES.PAUSED and G.handle_controls_listen_press then
        if G:handle_controls_listen_press(button) then
            return
        end
    end

    if G and G.STATE == G.STATES.MENU then
        MainMenuUI.handle_button(G, button)
        return
    end

    if button == "start" and G then
        if G.toggle_pause then
            G:toggle_pause()
            return
        end
    end

    if G then
        set_role_hold_from_button(G, button, true)
        local role = G:get_role_for_button(button)
        if role == "confirm" and G.enter_card_select_mode and G.ensure_dpad_cursor then
            G:enter_card_select_mode()
        end
        -- Cancel's hand gestures (tap to deselect or sort, hold to sweep) are decided here,
        -- while the button is going down and before any handler can move the focus. Cancel is
        -- also sell and back, and those can hand focus to the hand mid-press.
        if role == "cancel" then
            G._sweep_seeded = false
            G._cancel_gesture_armed = G.hand_cancel_gesture_available
                and G:hand_cancel_gesture_available() or false
        end
    end

    if G and G:is_role(button, "shoulder_l") and G.toggle_jokers_pulled then
        G:toggle_jokers_pulled()
    end
    if G and G:is_role(button, "shoulder_r") and G.toggle_consumables_pulled then
        G:toggle_consumables_pulled()
    end

    if not G then return end
    if G.STATE == G.STATES.YOU_WIN then
        YouWinUI.handle_button(G, button)
        return
    end
    if G.STATE == G.STATES.PAUSED then
        if G.handle_gamepad_pause and G:handle_gamepad_pause(button) then
            return
        end
        return
    end
    if G._deck_view_open then
        if DeckViewUI.handle_gamepad(G, button) then
            return
        end
        return
    end
    if button == "back" and G.toggle_deck_view then
        G:toggle_deck_view()
        return
    end

    if button == "up" or button == "dpup" or button == "down" or button == "dpdown" then
        if G.handle_gamepad_focus_vertical and G:handle_gamepad_focus_vertical(button) then
            return
        end
    end

    if G.STATE == G.STATES.BLIND_SELECT then
        if G.handle_gamepad_blind_select and G:handle_gamepad_blind_select(button) then
            return
        end
        if G:is_role(button, "cancel") and G.try_gamepad_skip_blind then
            G:try_gamepad_skip_blind()
            return
        end
        if G:is_role(button, "discard") and G.try_gamepad_boss_reroll then
            G:try_gamepad_boss_reroll()
            return
        end
        if G:is_menu_activate(button) then
            G:start_selected_blind()
        end
        return
    end
    if G.STATE == G.STATES.ROUND_EVAL then
        -- A pulled-down joker panel owns confirm/cancel here; otherwise browsing
        -- jokers would cash out from under you.
        if G.handle_bottom_inventory_button and G:handle_bottom_inventory_button(button) then
            return
        end
        if G:is_menu_activate(button) and not (G._bottom_inventory_focus_locked and G:_bottom_inventory_focus_locked())
            and not (G.scene_transition_active and G:scene_transition_active()) then
            G:continue_from_round_win()
        end
        return
    end
    if G.STATE == G.STATES.SHOP then
        if G.handle_gamepad_shop and G:handle_gamepad_shop(button) then
            return
        end
        return
    end
    if G.STATE == G.STATES.OPEN_BOOSTER then
        if G.handle_gamepad_booster and G:handle_gamepad_booster(button) then
            return
        end
        if G:is_role(button, "cancel") and G.end_booster_session then
            G:end_booster_session()
        end
        return
    end
    if G.STATE == G.STATES.SELECTING_HAND then
        if G.handle_gamepad_selecting_hand and G:handle_gamepad_selecting_hand(button) then
            return
        end
    end
end

function love.gamepadreleased(_, button)
    if not G then return end
    button = InputBindings.normalize_gamepad_button(button)

    local role = G:get_role_for_button(button)
    local press_time = role and G:get_role_press_time(role) or nil

    -- A wipe swallows the gesture but never the bookkeeping. The button that started the
    -- transition goes down before it and comes up under it, so dropping this outright would
    -- leave the role latched held and the cancel gesture armed for the rest of the run.
    if ScreenWipe.active(G) then
        G._sweep_seeded = false
        G._cancel_gesture_armed = false
        set_role_hold_from_button(G, button, false)
        return
    end

    -- Cancel is a tap and two holds. The tap drops the selection (or sorts, if there is
    -- nothing to drop) and only fires on release, so holding the button to sweep-select does
    -- not throw the selection away on the way in.
    if role == "cancel" then
        local armed = G._cancel_gesture_armed == true
        local swept = G._sweep_seeded == true
        local held = press_time and (love.timer.getTime() - press_time) or nil
        local tap_threshold = InputBindings.GESTURES.cancel_tap_max_ms / 1000
        if armed and not swept and held and held < tap_threshold and G.try_gamepad_hand_cancel_tap then
            G:try_gamepad_hand_cancel_tap()
        end
        G._sweep_seeded = false
        G._cancel_gesture_armed = false

        local hold_threshold = InputBindings.GESTURES.shop_exit_hold_ms / 1000
        if G.STATE == G.STATES.SHOP and held and held >= hold_threshold
            and G.get_gamepad_focus_layer and G:get_gamepad_focus_layer() == "hand" then
            G:continue_from_shop()
        end
    end

    set_role_hold_from_button(G, button, false)
end

function love.gamepadaxis(joystick, axis, value)
    if not G or not InputBindings.triggers_enabled or not InputBindings.triggers_enabled() then return end
    local trigger_btn = InputBindings.axis_to_trigger_button(axis)
    if not trigger_btn or not InputBindings.is_rebindable_button(trigger_btn) then return end

    local threshold = InputBindings.TRIGGER_AXIS_THRESHOLD
    local pressed = (tonumber(value) or 0) > threshold
    if pressed then note_button_input() end
    G._trigger_axis_held = G._trigger_axis_held or {}
    local was = G._trigger_axis_held[trigger_btn] == true

    if pressed and not was then
        G._trigger_axis_held[trigger_btn] = true
        love.gamepadpressed(joystick, trigger_btn)
    elseif not pressed and was then
        G._trigger_axis_held[trigger_btn] = false
        love.gamepadreleased(joystick, trigger_btn)
    end
end

--- The 3DS HID poll reads every enabled sensor once a frame and pushes the sample as an event
--- (`platform/ctr/source/utilities/driver/hid_ext.cpp:107-113`), so taking it here costs nothing
--- the runtime was not already spending. `Tilt.update` polls only for the frames this misses.
function love.joysticksensorupdated(_, sensor, x, y, z)
    if sensor == "accelerometer" then
        Tilt.on_sample(x, y, z)
    end
end

function love.touchpressed(id, x, y, dx, dy, pressure)
    if ScreenWipe.active(G) then return end
    -- Press record for button depression (see draw_button_with_shadow): buttons drawn
    -- under the active touch sink onto their shadow while held.
    G._ui_press = { x = x, y = y, held = true, released_at = nil }
    G:touchpressed(id, x, y)
end

function love.touchmoved(id, x, y, dx, dy, pressure)
    if ScreenWipe.active(G) then return end
    -- Track the finger so dragging off a button releases its depression.
    if G._ui_press and G._ui_press.held then
        G._ui_press.x, G._ui_press.y = x, y
    end
    G:touchmoved(id, x, y, dx, dy)
end

function love.touchreleased(id, x, y, dx, dy, pressure)
    -- The press record is closed even under a wipe: the button that started the transition
    -- was pressed before it and would otherwise stay drawn depressed after it. Only the
    -- handler below is dropped.
    if G._ui_press then
        G._ui_press.held = false
        G._ui_press.released_at = love.timer.getTime()
    end
    if ScreenWipe.active(G) then return end
    G:touchreleased(id, x, y)
end
