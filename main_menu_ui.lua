
local MainMenuUI = {}
local CollectionUI = require("collection_ui")
local ProfileUI = require("profile_ui")
local BuildFlags = require("build_flags")
local Benchmark = (not BuildFlags.release) and require("benchmark") or nil
-- The animated background, evaluated on the GPU; see backdrop.lua.
local Backdrop = require("backdrop")

MainMenuUI.KONAMI_CODE = {
    "up", "up", "down", "down", "left", "right", "left", "right", "b", "a", "start",
}

local KONAMI_ALIASES = {
    dpup = "up",
    dpdown = "down",
    dpleft = "left",
    dpright = "right",
    b = "b",
    ["return"] = "start",
    enter = "start",
}

function MainMenuUI.normalize_konami_input(btn)
    if type(btn) ~= "string" then return nil end
    return KONAMI_ALIASES[btn] or btn
end

function MainMenuUI.try_konami_cheat(game, btn)
    if not game or not game.STATES or game.STATE ~= game.STATES.MENU then return false end
    local input = MainMenuUI.normalize_konami_input(btn)
    if not input then return false end

    local seq = MainMenuUI.KONAMI_CODE
    local progress = (tonumber(game._konami_progress) or 0) + 1
    if seq[progress] == input then
        if progress >= #seq then
            game._konami_progress = 0
            if game.unlock_everything then
                game:unlock_everything()
            end
            return true
        end
        game._konami_progress = progress
        return false
    end

    game._konami_progress = (input == seq[1]) and 1 or 0
    return false
end

MainMenuUI.HOW_TO_PLAY_PAGES = {
    {
        title = "Touch Controls",
        lines = {
            "Tap hand cards to select or deselect them.",
            "Tap jokers, tarots, planets, and shop",
            "items to show tooltips and action buttons.",
            "Drag cards or jokers to reorder them.",
            "",
            "   Pause & Menus",
            "Start opens the Pause menu.",
            "Blind select, shop, and round win screens",
            "Use on-screen buttons or A/Y to continue.",
        },
    },
    {
        title = "Gamepad - Hand",
        lines = {
            "D-pad Left/Right: Move cursor",
            "A: Toggle card selection",
            "Hold A + Left/Right: Reorder cards",
            "Hold B + Left/Right: Sweep select",
            "B (tap): Deselect all, or sort the hand",
            "X: Discard selected cards",
            "Y: Play selected cards",
            "L: Toggle jokers down / back up",
            "R: Toggle consumables down / back up",
        },
    },
    {
        title = "Gamepad - Jokers & Consumables",
        lines = {
            "Pull jokers (L) or consumables (R) to the",
            "bottom screen to interact with them.",
            "",
            "While pulled:",
            "D-pad Left/Right: Cycle items",
            "A: Use consumable, or pick a joker",
            "   (pick two jokers to swap them)",
            "Hold A + Left/Right: Reorder",
            "B: Sell",
        },
    },
    {
        title = "Gamepad - Shop",
        lines = {
            "D-Pad Left/Right: Move shop cursor",
            "A: Buy     Y: Buy and Use",
            "X: Reroll Shop",
            "Hold B: Continue / exit shop",
            "",
            "Booster pack:",
            "D-pad Left/Right: Cycle pack cards",
            "A: Pick / Confirm card",
            "B: Skip Booster",
        },
    },
    {
        title = "Gamepad - Other",
        lines = {
            "Select: Open Deck View",
            "Press Right on Deck View to see Poker Hands",
            "Start: Pause Menu",
            "",
            "Rebind A/B/X/Y/L/R/ZL/ZR under",
            "Pause > Settings > Controls.",
        },
    },
    {
        title = "Gamepad - Other (2)",
        lines = {
            "Blind select:",
            "A: Start blind   B: Skip",
            "X: Reroll boss (with voucher)",
            "",
            "Deck select:",
            "Left/Right: Pick deck   Up/Down: Stake",
            "A: Begin   B/X: Back",
        },
    },
}

function MainMenuUI.open_how_to_play(game)
    game._menu_sub_state = "how_to_play"
    game._how_to_play_page = game._how_to_play_page or 1
    Sfx.play("paper1")
end

local MENU_ANIM_FPS = 12

local cia_build_timestamp = BuildFlags.timestamp

local function menu_ping_pong_frame(frame_count, fps, time)
    frame_count = math.max(1, tonumber(frame_count) or 1)
    if frame_count == 1 then return 0 end
    local cycle = (frame_count - 1) * 2
    local step = math.floor((time or love.timer.getTime()) * (fps or MENU_ANIM_FPS)) % cycle
    if step < frame_count then
        return step
    end
    return cycle - step
end

function MainMenuUI.draw_background(game, screen)
    local w = (screen == "bottom") and 320 or 400
    local h = 240

    if game._collection_open then
        love.graphics.setColor(game.C.PANEL)
        love.graphics.rectangle("fill", 0, 0, w, h)
        return
    end

    -- One draw call for the whole background, the field evaluated per vertex on the GPU. This
    -- replaces a 63-frame 1024x1024 sheet that cost 4 MiB resident and was reloaded on every
    -- entry to the menu. Returns false on any runtime without the binding -- desktop, nest --
    -- and the gradient below is the fallback for exactly that case.
    if Backdrop.draw(w) then return end

    do
        local top = G.C.MULT
        local bottom = G.C.BOOSTER
        local steps = 48
        love.graphics.setColor(top)
        love.graphics.rectangle("fill", 0, 0, w, h)
        for i = 0, steps - 1 do
            local t = i / (steps - 1)
            local r = top[1] + (bottom[1] - top[1]) * t
            local g = top[2] + (bottom[2] - top[2]) * t
            local b = top[3] + (bottom[3] - top[3]) * t
            love.graphics.setColor(r, g, b, 1.0)
            local y = math.floor((i / steps) * h + 0.5)
            local seg_h = math.ceil(h / steps)
            love.graphics.rectangle("fill", 0, y, w, seg_h)
        end
        return
    end
end

--- Kept for reference builds that still ship the sheet; nothing calls it now.
function MainMenuUI.draw_background_atlas(game, screen)
    local w = (screen == "bottom") and 320 or 400
    local h = 240
    local atlas = game.ensure_animation_atlas_loaded
        and game:ensure_animation_atlas_loaded("menu")
    if not atlas or not atlas.image then return end

    local frame_count = tonumber(atlas.frames) or 16
    local frame = menu_ping_pong_frame(frame_count, MENU_ANIM_FPS)

    -- Declared grid geometry and a cached quad, both through the shared helper: this runs
    -- once per screen per frame for the whole time the menu is up (`game.lua`,
    -- `Game:atlas_cell_quad`).
    local quad, cell_w, cell_h = game:atlas_cell_quad(atlas, frame)
    if not quad then return end

    local s = math.max(w / cell_w, h / cell_h)
    local draw_w = cell_w * s
    local draw_h = cell_h * s
    local dx = math.floor((w - draw_w) * 0.5 + 0.5)
    local dy = math.floor((h - draw_h) * 0.5 + 0.5)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(atlas.image, quad, dx, dy, 0, s, s)
end

--- Logo sheet geometry, declared rather than measured. `Image:getDimensions()` can report the
--- padded runtime size on hardware (512x256 for this sheet), which would put the ace in the wrong
--- place on console and the right place on desktop -- the same trap the consumable atlas carries a
--- `cols` field to avoid (`consumable.lua:25-43`).
local LOGO_W, LOGO_H = 336, 216
--- Where the ace sat when it was still painted into the sheet, so the restored art and the live
--- card line up exactly.
local ACE_X, ACE_Y, ACE_W, ACE_H = 130, 56, 72, 95

--- Drawn size of the logo as a fraction of the sheet. Sevenths and eighths land on whole source
--- pixels more often than an arbitrary fraction does, which matters at `nearest` filtering.
local LOGO_SCALE = 7 / 8

--- Idle motion for the title ace, from the single-card branch of `cardarea.lua:466-471`:
--- `T.r = 0.02*sin(2t)` and `T.y = base + 0.03*sin(0.666t)`, both in game units.
---
--- The rotation ports over unchanged. The bob does not: 0.03 units is 2.2 px against the
--- reference's 73 px tile on a 720p window, which is 0.83% of the card's height. The same
--- fraction of an 83 px card here is 0.7 px -- below the threshold where anything reads as
--- moving on a 240p panel. So the amplitude is set in pixels to keep the *visible* travel the
--- reference has, and the periods are kept exactly.
local ACE_TILT_RAD = 0.02
local ACE_TILT_HZ = 2.0
local ACE_BOB_PX = 1.2
local ACE_BOB_HZ = 0.666

function MainMenuUI.draw_top(screen, game)
    if game._menu_sub_state == "collection_menu" or game._menu_sub_state == "collection_grid" then
        CollectionUI.draw_top(screen,game)
        return
    end

    local sysDepth = -love.graphics.getDepth()
    if screen == "right" then
        sysDepth = -sysDepth
    end
    local titleDepth = 5

    local panel_x, panel_w = 24, 352

    local atlas = nil
    if game.ensure_asset_atlas_loaded then
        atlas = game:ensure_asset_atlas_loaded("balatro")
    end

    if atlas and atlas.image then
        -- This is a single logo atlas draw, not text. Keep it that way: replacing it
        -- with per-glyph bitmap text would cost more draws on the Old 3DS and lose its art.
        local s = LOGO_SCALE
        local draw_w, draw_h = LOGO_W * s, LOGO_H * s
        local dx = panel_x + math.floor((panel_w - draw_w) * 0.5 + 0.5)
        -- Centred in the strip above the build stamp rather than pinned to the top, so shrinking
        -- the logo takes slack off both ends instead of leaving it all at the bottom.
        local dy = math.floor((222 - draw_h) * 0.5 + 0.5)
        local depth = titleDepth * sysDepth
        love.graphics.setColor(game.C.WHITE)
        love.graphics.draw(atlas.image, dx - depth, dy, 0, s, s)

        local ace = game.ensure_asset_atlas_loaded and game:ensure_asset_atlas_loaded("title_ace")
        if ace and ace.image then
            local t = (love.timer and love.timer.getTime and love.timer.getTime()) or 0
            local r = ACE_TILT_RAD * math.sin(ACE_TILT_HZ * t)
            local bob = ACE_BOB_PX * math.sin(ACE_BOB_HZ * t)
            -- Rotate about the card's centre, which is where the reference's transform origin
            -- sits, so the tilt reads as a hinge rather than a swing from the corner. The ace
            -- shares the logo's parallax offset: it is a card lying on the logo, not in front
            -- of it, and a separate depth would need hardware to tune.
            love.graphics.draw(ace.image,
                dx - depth + (ACE_X + ACE_W * 0.5) * s,
                dy + (ACE_Y + ACE_H * 0.5) * s + bob,
                r, s, s, ACE_W * 0.5, ACE_H * 0.5)
        end
    end

    if cia_build_timestamp then
        love.graphics.setFont(game.FONTS.PIXEL.SMALL)
        love.graphics.setColor(game.C.WHITE)
        love.graphics.printf(cia_build_timestamp, 0, 226, 394, "right")
    end
end

function MainMenuUI.open_deck_select(game)
    game._deck_select_idx = game._deck_select_idx or 1
    game._stake_select_idx = game._stake_select_idx or 1
    game._menu_sub_state = "deck_select"
    Sfx.play("paper1")
end

function MainMenuUI.open_challenges(game)
    game._challenge_page = game._challenge_page or 1
    game._challenge_selected = game._challenge_selected or 1
    game._menu_sub_state = "challenges"
    Sfx.play("paper1")
end

local function has_screen_keyboard()
    return love.keyboard and love.keyboard.hasScreenKeyboard and love.keyboard.hasScreenKeyboard() == true
end

function MainMenuUI.is_editing_seed(game)
    return game._seed_entry_active == true or game._seed_entry_pending == true
end

--- The option table LövePotion accepts. The length key is `length`, not `maxLength`:
--- `love.keyboard.setTextInput` runs every field of the table through
--- `luax::CheckTableFields` first and raises "Invalid keyboard setting name" on anything
--- outside {type, password, hint, length}, so one wrong key means the keyboard never opens
--- (`source/modules/keyboard/wrap_keyboard.cpp:34`, `include/modules/keyboard/keyboard.tcc:77`).
--- The binding has no initial-text option, so the current seed cannot be pre-filled.
local SEED_KEYBOARD_OPTIONS = { type = "normal", hint = "8 character seed", length = 8 }

function MainMenuUI.begin_seed_entry(game)
    if MainMenuUI.is_editing_seed(game) then return false end
    local seed = game:normalize_run_seed(game._pending_run_seed) or ""
    if has_screen_keyboard() then
        game._seed_entry_pending = true
        game._seed_entry_pending_frames = 0
        -- If the runtime rejects the call, drop the pending flag rather than wedging the
        -- button: is_editing_seed gates re-entry, so a stuck flag kills seed entry for good.
        if not pcall(love.keyboard.setTextInput, true, SEED_KEYBOARD_OPTIONS) then
            game._seed_entry_pending = nil
            return false
        end
    else
        game._seed_entry_active = true
        game._seed_entry_buffer = seed
        if love.keyboard and love.keyboard.setTextInput then pcall(love.keyboard.setTextInput, true) end
    end
    return true
end

function MainMenuUI.finish_seed_entry(game, text)
    local seed = game:normalize_run_seed(text)
    game._seed_entry_active, game._seed_entry_pending = nil, nil
    game._seed_entry_buffer = nil
    if seed then game._pending_run_seed = seed end
    if not has_screen_keyboard() and love.keyboard and love.keyboard.setTextInput then pcall(love.keyboard.setTextInput, false) end
    return seed ~= nil
end

function MainMenuUI.handle_seed_textinput(game, text)
    if game._seed_entry_pending then
        -- The system keyboard hands back the whole string at once, and its own limit is a
        -- byte count three times the requested length (`platform/ctr/source/modules/
        -- keyboard_ext.cpp:14`), so apply the same filter inline typing uses.
        local typed = tostring(text or ""):upper():gsub("[^0-9A-Z]", ""):sub(1, 8)
        return MainMenuUI.finish_seed_entry(game, typed)
    end
    if not game._seed_entry_active then return false end
    local value = tostring(game._seed_entry_buffer or "") .. tostring(text or "")
    game._seed_entry_buffer = value:upper():gsub("[^0-9A-Z]", ""):sub(1, 8)
    return true
end

--- The system keyboard blocks until dismissed and its text lands in the next frame's event
--- pump, so nothing by then means the player cancelled it. Without this the pending flag
--- would never clear and the seed button would stay dead for the rest of the session.
function MainMenuUI.expire_pending_seed_entry(game)
    if not game._seed_entry_pending then return end
    local frames = (tonumber(game._seed_entry_pending_frames) or 0) + 1
    game._seed_entry_pending_frames = frames
    if frames >= 2 then
        game._seed_entry_pending = nil
    end
end

function MainMenuUI.handle_seed_key(game, key)
    if not game._seed_entry_active then return false end
    if key == "backspace" then
        game._seed_entry_buffer = tostring(game._seed_entry_buffer or ""):sub(1, -2)
    elseif key == "return" or key == "kpenter" then
        MainMenuUI.finish_seed_entry(game, game._seed_entry_buffer)
    elseif key == "escape" then
        MainMenuUI.finish_seed_entry(game, nil)
    end
    return true
end

--------------------------------------------------------------------------------
-- Menu entrance slide
--
-- The reference builds every menu as an overlay UIBox created below the visible room and
-- then eases it up to centre: `G.FUNCS.overlay_menu` hands the box an initial
-- `offset = {x=0, y=10}`, zeroes `alignment.offset.y`, bumps `G.ROOM.jiggle` and calls
-- `align_to_major`, leaving the Moveable spring to carry it in
-- (`reference/Balatro/functions/button_callbacks.lua:1328-1356`). Every page turn inside the
-- menu tree is a fresh overlay, so each one arrives with that pop rather than snapping.
--
-- This port draws its menus immediate-mode, so there is no Moveable to spring. Instead the
-- whole bottom-screen menu is drawn through one translate whose offset runs the same
-- overshooting curve the scene panels already use (`game.lua`, `slide_offset`), keyed on
-- which page is showing so any change to the visible screen retriggers it.
--------------------------------------------------------------------------------

local MENU_SLIDE_DURATION = 0.22
local MENU_SLIDE_DIST = 240
--- An asset load or a GC step can hand us a dt longer than the whole slide, which would
--- finish it in one frame and read as the snap this replaces.
local MENU_SLIDE_MAX_STEP = 1 / 30

local function ease_out_back(t)
    local c1 = 1.2
    local u = t - 1
    return 1 + (c1 + 1) * u * u * u + c1 * u * u
end

--- Identity of the screen currently on the bottom panel. Full screens live on
--- `_menu_sub_state`, the root menu's column lives on `_menu_page`, and settings opened from
--- the menu borrows the pause panel -- all three are separate screens to the player, so all
--- three slide.
local function menu_slide_key(game)
    if game._settings_over_menu then return "settings" end
    local sub = game._menu_sub_state
    if sub and sub ~= "main" then return sub end
    return "page:" .. MainMenuUI.current_page(game)
end

--- True while the panel is still moving. Its hitboxes were recorded at the settled position,
--- so a touch landing now would hit a button that is not under the finger yet.
function MainMenuUI.slide_active(game)
    return game._menu_slide ~= nil
end

function MainMenuUI.slide_dy(game)
    local slide = game._menu_slide
    if not slide then return 0 end
    -- The collection borrows this panel from the pause screen mid-run, where nothing ticks
    -- the slide; a stale offset there would park the panel off the bottom of the screen.
    if game.STATES and game.STATE ~= game.STATES.MENU then return 0 end
    return math.floor((1 - ease_out_back(slide.t)) * MENU_SLIDE_DIST + 0.5)
end

--- Restart the slide whenever the visible screen changes. Watching the key rather than
--- hooking every assignment to `_menu_sub_state` keeps the trigger in one place; the cost is
--- that the slide starts on the frame after the press, which is not visible at 0.22 s.
function MainMenuUI.update_slide(game, dt)
    local key = menu_slide_key(game)
    if key ~= game._menu_slide_key then
        game._menu_slide_key = key
        -- Nothing to slide on the very first menu frame of the session: the boot wipe is
        -- already covering that entrance.
        if game._menu_slide_seen then
            game._menu_slide = { t = 0 }
        end
        game._menu_slide_seen = true
    end

    local slide = game._menu_slide
    if not slide then return end
    if dt > MENU_SLIDE_MAX_STEP then dt = MENU_SLIDE_MAX_STEP end
    slide.t = math.min(1, slide.t + dt / MENU_SLIDE_DURATION)
    if slide.t >= 1 then
        game._menu_slide = nil
        -- `G.ROOM.jiggle + 1` on the reference's side of the same landing.
        if game.shake then game:shake(1) end
    end
end

function MainMenuUI.draw_bottom(game)
    MainMenuUI.expire_pending_seed_entry(game)
    local dy = MainMenuUI.slide_dy(game)
    if dy ~= 0 then
        love.graphics.push()
        love.graphics.translate(0, dy)
    end
    MainMenuUI._draw_bottom_panel(game)
    if dy ~= 0 then
        love.graphics.pop()
    end
end

function MainMenuUI._draw_bottom_panel(game)
    if game._settings_over_menu then
        game:draw_bottom_pause()
        return
    end
    if game._menu_sub_state == "deck_select" then
        MainMenuUI.draw_deck_select(game)
    elseif game._menu_sub_state == "how_to_play" then
        MainMenuUI.draw_how_to_play(game)
    elseif game._menu_sub_state == "collection_menu" or game._menu_sub_state == "collection_grid" then
        CollectionUI.draw_bottom(game)
    elseif game._menu_sub_state == "profile" then
        ProfileUI.draw_bottom(game)
    elseif game._menu_sub_state == "stats" then
        ProfileUI.draw_stats(game)
    elseif game._menu_sub_state == "challenges" then
        MainMenuUI.draw_challenges(game)
    elseif game._menu_sub_state == "benchmark" then
        MainMenuUI.draw_benchmark(game)
    else
        MainMenuUI.draw_main(game)
    end
end

--------------------------------------------------------------------------------
-- The main menu tree
--
-- The base game's main menu is four entries -- Play, Options, Collection and Quit
-- (`UI_definitions.lua:6216-6222`) -- with the run choices behind Play (`:5306-5330`, the
-- New Run / Continue / Challenges tabs) and the rest behind Options (`:2248-2260`). This
-- port had all seven flattened onto one screen. The pages below restore the base game's
-- shape; each page is a plain column of buttons because a 320x240 touch screen has no room
-- for the two-column arrangement the desktop menu uses, and a column is what every other
-- screen in this port already looks like.
--
-- Entry colours follow the base game's: Play blue, Options orange, Collection pale green,
-- Quit red (`:6216-6222`).
--------------------------------------------------------------------------------

--- `visible` is optional; an entry without one is always shown.
local MENU_PAGES = {
    main = {
        entries = {
            { kind = "play",       label = "Play",       colour = "BLUE" },
            { kind = "options",    label = "Options",    colour = "ORANGE" },
            { kind = "collection", label = "Collection", colour = "PALE_GREEN" },
            { kind = "quit",       label = "Quit",       colour = "RED" },
        },
    },
    play = {
        title = "Play",
        entries = {
            -- Continue leads when there is a run to resume, the way the base game pre-selects
            -- its Continue tab whenever `can_continue` passes (`UI_definitions.lua:5316`).
            {
                kind = "continue", label = "Continue", colour = "BLUE",
                visible = function(game)
                    return game.has_saved_run and game:has_saved_run() == true
                end,
            },
            { kind = "start",      label = "New Run",    colour = "GREEN" },
            { kind = "challenges", label = "Challenges", colour = "RED" },
        },
    },
    options = {
        title = "Options",
        entries = {
            { kind = "settings",    label = "Settings",    colour = "BOOSTER" },
            { kind = "stats",       label = "Stats",       colour = "ORANGE" },
            { kind = "profile",     label = "Profile",     colour = "MULT" },
            -- Not a base-game entry. The touch and gamepad schemes are this port's own, so the
            -- page that explains them lives with the other settings rather than at the top level.
            { kind = "how_to_play", label = "How to Play", colour = "MULT" },
            -- A developer tool, not a player-facing feature: it runs the on-device
            -- performance suite and writes the numbers to the save directory. It lives here
            -- because hardware is the only place the numbers mean anything, and the menu is
            -- the only way to reach anything on a console.
            { kind = "benchmark",   label = "Benchmark",   colour = "GREY",
                visible = function() return not BuildFlags.release end },
        },
    },
}

--- Which page of the tree the root menu is showing. Full screens (deck select, profile,
--- the collection) stay on `_menu_sub_state`; this only tracks the button column.
---@return string
function MainMenuUI.current_page(game)
    local page = game._menu_page
    return MENU_PAGES[page] and page or "main"
end

function MainMenuUI.open_page(game, page)
    if not MENU_PAGES[page] then page = "main" end
    -- Going deeper is a page turn, coming back out is a cancel -- the same pair every other
    -- screen in this port uses for the same movement.
    local cue = "paper1"
    if page == "main" then cue = "cancel" end
    Sfx.play(cue)
    game._menu_page = page
    game._menu_focus_index = 1
end

--- Entries on a page, minus the ones their `visible` predicate rules out.
---@return table[]
function MainMenuUI.page_entries(game, page)
    local def = MENU_PAGES[page] or MENU_PAGES.main
    local out = {}
    for _, entry in ipairs(def.entries) do
        if not entry.visible or entry.visible(game) then
            out[#out + 1] = entry
        end
    end
    return out
end

function MainMenuUI.draw_main(game)
    local C = game.C
    local page_name = MainMenuUI.current_page(game)
    local page = MENU_PAGES[page_name]
    local entries = MainMenuUI.page_entries(game, page_name)
    local is_root = page_name == "main"

    local btn_w, btn_h, btn_gap = 160, 28, 6
    local title_h = page.title and 22 or 0
    -- The root menu carries the profile chip in its footer; a sub-page carries Back instead.
    local foot_h = 28
    local panel_w = 220
    local panel_h = title_h + #entries * btn_h + (#entries - 1) * btn_gap + 40
    local panel_x = math.floor((320 - panel_w) * 0.5 + 0.5)
    local panel_y = math.floor((240 - foot_h - 8 - panel_h) * 0.5 + 0.5)

    if _G.draw_rect_with_shadow then
        draw_rect_with_shadow(panel_x, panel_y, panel_w, panel_h, 6, 3,
            C.PANEL, C.BLOCK.SHADOW, 3)
    else
        love.graphics.setColor(C.PANEL)
        love.graphics.rectangle("fill", panel_x, panel_y, panel_w, panel_h, 6, 6)
    end

    local font_m = game.FONTS.PIXEL.MEDIUM
    local function label_y(r)
        return r.y + math.floor((r.h - font_m:getHeight()) * 0.5 + 0.5)
    end

    local y = panel_y + 20
    if page.title then
        love.graphics.setFont(font_m)
        love.graphics.setColor(C.WHITE)
        love.graphics.printf(page.title, panel_x, y, panel_w, "center")
        y = y + title_h
    end

    local rects = {}
    local btn_x = panel_x + math.floor((panel_w - btn_w) * 0.5 + 0.5)
    for _, entry in ipairs(entries) do
        local rect = { x = btn_x, y = y, w = btn_w, h = btn_h }
        rects[#rects + 1] = { kind = entry.kind, rect = rect }
        draw_button_with_shadow(rect.x, rect.y, rect.w, rect.h, 4, 4,
            C[entry.colour] or C.BLUE, C.BLOCK.SHADOW, 2)
        love.graphics.setFont(font_m)
        love.graphics.setColor(C.WHITE)
        love.graphics.printf(entry.label, rect.x, label_y(rect), rect.w, "center")
        y = y + btn_h + btn_gap
    end

    -- Footer: the loaded profile's name on the root page, Back on a sub-page.
    local foot_w = 174
    local foot_x = math.floor((320 - foot_w) * 0.5 + 0.5)
    local foot_y = 240 - foot_h - 4
    local foot = { x = foot_x, y = foot_y, w = foot_w, h = foot_h }
    if is_root then
        rects[#rects + 1] = { kind = "profile", rect = foot }
        draw_button_with_shadow(foot.x, foot.y, foot.w, foot.h, 4, 4,
            C.MULT, C.BLOCK.SHADOW, 2)
        love.graphics.setFont(font_m)
        love.graphics.setColor(C.WHITE)
        local profile_name = game.get_profile_name and game:get_profile_name() or "Profile"
        love.graphics.printf(profile_name, foot.x, label_y(foot), foot.w, "center")
    else
        rects[#rects + 1] = { kind = "back", rect = foot }
        draw_button_with_shadow(foot.x, foot.y, foot.w, foot.h, 4, 4,
            C.MULT, C.BLOCK.SHADOW, 2)
        love.graphics.setFont(font_m)
        love.graphics.setColor(C.WHITE)
        love.graphics.printf("Back", foot.x, label_y(foot), foot.w, "center")
    end

    if is_root and game.SEED then
        love.graphics.setFont(game.FONTS.PIXEL.SMALL)
        love.graphics.setColor(C.DARK_WHITE or C.GREY)
        love.graphics.printf("Seed " .. tostring(game.SEED),
            panel_x, foot_y - 14, panel_w, "center")
    end

    game._main_menu_rects = rects

    local focus_idx = tonumber(game._menu_focus_index) or 1
    focus_idx = math.max(1, math.min(#rects, focus_idx))
    game._menu_focus_index = focus_idx
    local focused = rects[focus_idx]
    if focused then
        local r = focused.rect
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", r.x + 0.5, r.y + 0.5, r.w - 1, r.h - 1)
    end
end

--- Focus click for the menus' cursors and carousels. Silent when the index did not
--- actually move, so holding against the end of a carousel stays quiet. The held-d-pad
--- repeat in Game:update_dpad_horizontal_repeat never runs in MENU, so every call here
--- is one discrete press.
local function click_focus_move(before, after)
    if type(after) == "number" and after ~= before then
        Sfx.play("highlight1", nil, 0.2)
    end
end

--- Laid out by the last `draw_main`. Input runs after a frame has been drawn, so this is
--- populated by the time anything asks for it.
function MainMenuUI.build_main_menu_focus_targets(game)
    return game._main_menu_rects or {}
end

function MainMenuUI.main_menu_focus_move(game, delta)
    local targets = MainMenuUI.build_main_menu_focus_targets(game)
    if #targets == 0 then return nil end
    delta = math.floor(tonumber(delta) or 0)
    local from = tonumber(game._menu_focus_index) or 1
    local idx = from + delta
    if idx < 1 then idx = #targets elseif idx > #targets then idx = 1 end
    click_focus_move(from, idx)
    game._menu_focus_index = idx
    return targets[idx]
end

function MainMenuUI.activate_menu_entry(game, kind)
    if kind == "play" or kind == "options" then
        MainMenuUI.open_page(game, kind)
        return true
    elseif kind == "back" then
        MainMenuUI.open_page(game, "main")
        return true
    elseif kind == "continue" then
        Sfx.play_button()
        if game.begin_continue_saved_run then
            game:begin_continue_saved_run()
        elseif game.continue_saved_run_from_main_menu then
            game:continue_saved_run_from_main_menu()
        end
        return true
    elseif kind == "start" then
        MainMenuUI.open_deck_select(game)
        return true
    elseif kind == "challenges" then
        MainMenuUI.open_challenges(game)
        return true
    elseif kind == "how_to_play" then
        MainMenuUI.open_how_to_play(game)
        return true
    elseif kind == "collection" then
        CollectionUI.open(game)
        return true
    elseif kind == "stats" then
        ProfileUI.open_stats(game)
        return true
    elseif kind == "profile" then
        ProfileUI.open(game)
        return true
    elseif kind == "settings" then
        game:open_settings_from_menu()
        return true
    elseif kind == "benchmark" then
        Sfx.play("paper1")
        game._menu_sub_state = "benchmark"
        return true
    elseif kind == "quit" then
        Sfx.play_button()
        if love.event and love.event.quit then love.event.quit() end
        return true
    end
    return false
end

function MainMenuUI.activate_main_menu_focus(game)
    local targets = MainMenuUI.build_main_menu_focus_targets(game)
    local idx = tonumber(game._menu_focus_index) or 1
    idx = math.max(1, math.min(#targets, idx))
    local t = targets[idx]
    if not t then return false end
    return MainMenuUI.activate_menu_entry(game, t.kind)
end

function MainMenuUI.draw_how_to_play(game)
    local W, H = 320, 240
    local font_s = game.FONTS.PIXEL.SMALL
    local font_m = game.FONTS.PIXEL.MEDIUM
    local C = game.C
    local pages = MainMenuUI.HOW_TO_PLAY_PAGES
    local page_count = #pages
    local page_idx = tonumber(game._how_to_play_page) or 1
    page_idx = math.max(1, math.min(page_count, page_idx))
    game._how_to_play_page = page_idx
    local page = pages[page_idx]

    love.graphics.setColor(C.PANEL)
    draw_rect_with_shadow(0, 0, W, H, 6, 6, C.PANEL, C.BLOCK.SHADOW, 2)

    local margin = 12
    local nav_h = 24
    local back_h = 24
    local content_y = margin + 4
    local content_h = H - content_y - nav_h - back_h - margin - 8
    local content_x = margin
    local content_w = W - margin * 2

    love.graphics.setFont(font_m)
    love.graphics.setColor(C.WHITE)
    love.graphics.printf("How to Play", 0, margin, W, "center")

    love.graphics.setColor(C.BLOCK.BACK)
    love.graphics.rectangle("fill", content_x, content_y, content_w, content_h, 6, 6)

    love.graphics.setFont(font_m)
    love.graphics.setColor(C.WHITE)
    love.graphics.printf(page.title, content_x, content_y + 6, content_w, "center")

    love.graphics.setFont(font_s)
    love.graphics.setColor(C.DARK_WHITE or C.GREY)
    local line_h = love.graphics.getFont():getHeight() + 2
    local text_y = content_y + 32
    for _, line in ipairs(page.lines) do
        if text_y + line_h <= content_y + content_h - 4 then
            love.graphics.printf(line, content_x + 8, text_y, content_w - 16, "left")
        end
        text_y = text_y + line_h
    end

    local nav_y = content_y + content_h + 6
    local arrow_w = 28
    local prev_x = content_x
    local next_x = content_x + content_w - arrow_w

    game._how_to_play_rects = {
        prev = { x = prev_x, y = nav_y, w = arrow_w, h = nav_h },
        next = { x = next_x, y = nav_y, w = arrow_w, h = nav_h },
    }

    if page_idx > 1 then
        draw_button_with_shadow(prev_x, nav_y, arrow_w, nav_h, 4, 4, C.MULT, C.BLOCK.SHADOW, 2)
        love.graphics.setColor(C.WHITE)
        love.graphics.setFont(font_s)
        love.graphics.printf("<", prev_x, nav_y + 4, arrow_w, "center")
    end

    if page_idx < page_count then
        draw_button_with_shadow(next_x, nav_y, arrow_w, nav_h, 4, 4, C.MULT, C.BLOCK.SHADOW, 2)
        love.graphics.setColor(C.WHITE)
        love.graphics.setFont(font_s)
        love.graphics.printf(">", next_x, nav_y + 4, arrow_w, "center")
    end

    local dot_y = nav_y + math.floor(nav_h * 0.5)
    local dot_mid = math.floor(W * 0.5)
    local dot_gap = 10
    for i = 1, page_count do
        local dx = dot_mid + (i - math.floor(page_count / 2) - 1) * dot_gap
        if i == page_idx then
            love.graphics.setColor(C.WHITE)
        else
            love.graphics.setColor(C.BLOCK.BACK)
        end
        love.graphics.circle("fill", dx, dot_y, 2)
    end

    local back_w = 120
    local back_x = math.floor((W - back_w) * 0.5)
    local back_y = H - margin - back_h - 4
    game._how_to_play_back_rect = { x = back_x, y = back_y, w = back_w, h = back_h }
    draw_button_with_shadow(back_x, back_y, back_w, back_h, 4, 4, C.MULT, C.BLOCK.SHADOW, 2)
    love.graphics.setColor(C.WHITE)
    love.graphics.setFont(font_s)
    love.graphics.printf("Back", back_x, back_y + 5, back_w, "center")

    love.graphics.setFont(font_s)
    love.graphics.setColor(C.GREY)
    love.graphics.printf("B/X: Back   LEFT/RIGHT: Pages", 0, H - 14, W, "center")
end

--------------------------------------------------------------------------------
-- Deck-change pop
--
-- Cycling the deck in the base game swaps the back on ten live cards and the stack visibly
-- reacts. There is no card area here -- the deck is one sprite -- so the reaction is the
-- engine's own trigger animation instead, borrowed the way `topUI.lua:28-38` borrows it for
-- counter pops: a plain table holding the juice fields, driven by `Moveable.update_juice`.
--------------------------------------------------------------------------------

--- Strength of the pop. Lower than a card's default because the deck sprite is large and
--- fixed in place, so the same amplitude that reads as a flick on a hand card reads as a
--- lurch here.
local DECK_SWAP_JUICE = 0.5

--- Called when the selected deck actually changes; a press that runs into either end of the
--- carousel leaves the sprite alone.
function MainMenuUI.juice_deck_sprite(game)
    game._deck_swap_juice = game._deck_swap_juice or {}
    Moveable.juice_up(game._deck_swap_juice, DECK_SWAP_JUICE)
end

--- Menu-state animation tick, off `Game:update`'s real clock. Only the deck pop lives here;
--- the title ace and the background are both pure functions of wall time.
function MainMenuUI.update(game, dt)
    MainMenuUI.update_slide(game, dt)
    local state = game._deck_swap_juice
    if state and state.juice then
        Moveable.update_juice(state, dt)
    end
    if game._menu_sub_state == "benchmark" then
        Benchmark.update(game, dt)
    end
end

--- Current pop multiplier, or 1 while nothing is animating.
local function deck_juice_scale(game)
    local state = game._deck_swap_juice
    return (state and state.juice and state.juice_scale) or 1
end

--- `unlocked` defaults to the catalog flag, which `Game:apply_unlocks` does keep in step for
--- decks (`game.lua:1716-1721`); callers that already have the runtime answer pass it in.
function MainMenuUI.draw_deck_carousel_sprite(game, def, x, y, w, h, p, unlocked)
    local atlas = nil
    if game.ensure_asset_atlas_loaded then
        atlas = game:ensure_asset_atlas_loaded("centers")
    end
    if unlocked == nil then unlocked = def and def.unlocked end

    if atlas and atlas.image then
        local index = tonumber(def and def.pos) or 0
        if not unlocked then
            index = 4
        end
        local iw, ih = atlas.image:getDimensions()
        local cell_w = tonumber(atlas.px) or 72
        local cell_h = tonumber(atlas.py) or 95
        local cols = math.max(1, math.floor(iw / cell_w))
        local col = index % cols
        local row = math.floor(index / cols)
        local quad = love.graphics.newQuad(col * cell_w, row * cell_h, cell_w, cell_h, iw, ih)

        local scale = math.min((w - p) / cell_w, (h - p) / cell_h)
        if scale > 1 then scale = 1 end
        if scale < 0.45 then scale = 0.45 end
        local draw_w = cell_w * scale
        local draw_h = cell_h * scale
        local dx = x + math.floor((w - draw_w) * 0.5 + 0.5)
        local dy = y + math.floor((h - draw_h) * 0.5 + 0.5)

        -- The pop is applied to the rendered sprite only, about its own centre, and the
        -- unjuiced rect is what gets returned: the info card and the stake column are laid
        -- out from these numbers, and they must not breathe along with the deck.
        local juice = deck_juice_scale(game)
        local state = game._deck_swap_juice
        local jr = (state and state.juice and state.juice_r) or 0
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(atlas.image, quad,
            dx + draw_w * 0.5, dy + draw_h * 0.5,
            jr, scale * juice, scale * juice, cell_w * 0.5, cell_h * 0.5)
        return dx,dy, draw_w, draw_h
    end

    love.graphics.setColor(0.25, 0.25, 0.25, 1)
    love.graphics.rectangle("fill", x, y, w, h, 8, 8)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf("Sprite unavailable", x, y + math.floor(h * 0.5) - 6, w, "center")
    return false
end

--- Tint for a stake chip. A locked stake is knocked back rather than greyed out: the chips are
--- how the ladder is read at a glance, and the old 0.35 multiplier took the colour out of them
--- entirely.
---@param unlocked boolean|nil `false` only when the caller knows the stake is locked
---@return number, number, number, number
function MainMenuUI.stake_sprite_tint(unlocked)
    if unlocked == false then return 0.55, 0.55, 0.55, 1 end
    return 1, 1, 1, 1
end

--- `unlocked` is the caller's runtime answer, not `def.unlocked`. Stakes unlock per deck, so
--- the catalog's flag (`deck_catalog.lua:213`) is only ever the starting default and is never
--- synced back the way `DECK_DEFS.unlocked` is (`game.lua:1716-1721`). Reading it here dimmed
--- every chip above White for the whole game.
function MainMenuUI.draw_stake_carousel_sprite(game, def, x, y, w, h, p, unlocked)
    p = p or 0
    local atlas = nil
    if game.ensure_asset_atlas_loaded then
        atlas = game:ensure_asset_atlas_loaded("chips")
    end

    if atlas and atlas.image then
        local index = tonumber(def and def.pos) or 0
        local iw, ih = atlas.image:getDimensions()
        local cell_w = tonumber(atlas.px) or 30
        local cell_h = tonumber(atlas.py) or 30
        local cols = math.max(1, math.floor(iw / cell_w))
        local col = index % cols
        local row = math.floor(index / cols)
        local quad = love.graphics.newQuad(col * cell_w, row * cell_h, cell_w, cell_h, iw, ih)

        local scale = math.min((w - p) / cell_w, (h - p) / cell_h)
        if scale > 1 then scale = 1 end
        if scale < 0.45 then scale = 0.45 end
        local draw_w = cell_w * scale
        local draw_h = cell_h * scale
        local dx = x + math.floor((w - draw_w) * 0.5 + 0.5)
        local dy = y + math.floor((h - draw_h) * 0.5 + 0.5)

        love.graphics.setColor(MainMenuUI.stake_sprite_tint(unlocked))
        love.graphics.draw(atlas.image, quad, dx, dy, 0, scale, scale)
        return dx, dy, draw_w, draw_h
    end

    love.graphics.setColor(0.25, 0.25, 0.25, 1)
    love.graphics.rectangle("fill", x, y, w, h, 8, 8)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf("Sprite unavailable", x, y + math.floor(h * 0.5) - 6, w, "center")
    return false
end

function MainMenuUI._start_run(game)
    local deck_list = DECK_SELECT_DEFS or DECK_DEFS or {}
    local stake_list = STAKE_DEFS or {}
    local deck_idx = tonumber(game._deck_select_idx) or 1
    local stake_idx = tonumber(game._stake_select_idx) or 1
    local deck_def = deck_list[deck_idx]
    local stake_def = stake_list[stake_idx]
    if not deck_def or not game:is_deck_unlocked(deck_def.id) then return false end
    if not stake_def or not game:is_stake_unlocked(deck_def.id, stake_def.id) then return false end

    Sfx.play_button()
    game._pending_deck_id = deck_def.id
    game._pending_stake_id = stake_def.id
    -- The sub-state is retired by the first run-start step instead, under the cover: this
    -- screen keeps drawing through the wipe's fade-in (`Game:_run_start_leave_menu`).
    if game.start_new_run_from_main_menu then
        game:start_new_run_from_main_menu()
    elseif game.initialize_run_loop then
        game:initialize_run_loop()
    end
    return true
end

function MainMenuUI.draw_deck_select(game)
    local W, H    = 320, 240
    local font_s  = game.FONTS.PIXEL.SMALL
    local font_m  = game.FONTS.PIXEL.MEDIUM
    local C       = game.C

    love.graphics.setColor(C.PANEL)
    love.graphics.rectangle("fill", 0, 0, W, H)

    love.graphics.setFont(font_m)
    love.graphics.setColor(C.WHITE)

    local deck_list = DECK_SELECT_DEFS or DECK_DEFS or {}
    local stake_list = STAKE_DEFS or {}
    -- Clamped indices are written back rather than kept local: `_start_run` reads the stored
    -- ones, so an out-of-range value would draw a clamped screen and then refuse to start.
    local sel_idx = math.max(1, math.min(#deck_list, tonumber(game._deck_select_idx) or 1))
    game._deck_select_idx = sel_idx
    local def = deck_list[sel_idx]
    if not def then return end

    local stake_idx = math.max(1, math.min(#stake_list, tonumber(game._stake_select_idx) or 1))
    game._stake_select_idx = stake_idx
    local stake_def = stake_list[stake_idx]
    if not stake_def then return end
    local stake_unlocked = game:is_stake_unlocked(def.id, stake_def.id)
    local deck_unlocked = game:is_deck_unlocked(def.id)

    local startX, startY = 24, 4
    local endX, endY = W - 24, H - 128
    local padding = 4
    local buttonW = 24

    local frameW = endX - startX
    local frameH = endY - startY

    local prev_x, prev_y, prev_w, prev_h = startX, startY, buttonW, frameH
    local next_x = W - 52
    local card_x, card_y, card_w, card_h = startX + buttonW + padding, startY + padding, frameW - 2*buttonW - 3*padding, frameH - 4*padding -- Select Button

    local selectbuttonW = 140
    local selectX, selectY, selectW, selectH = startX + 32, 200, selectbuttonW, 24
    draw_button_with_shadow(selectX, selectY, selectW, selectH, 4, 4, G.C.CHIPS, G.C.BLOCK.SHADOW, 2)
    love.graphics.setFont(font_m)
    love.graphics.setColor(C.WHITE)
    love.graphics.printf("PLAY", selectX, selectY, selectW, "center")
    local seedX, seedW = selectX + selectW + 8, 80
    local seed = game:normalize_run_seed(game._pending_run_seed)
    draw_button_with_shadow(seedX, selectY, seedW, selectH, 4, 4, C.MULT, C.BLOCK.SHADOW, 2)
    love.graphics.setFont(font_s)
    love.graphics.setColor(C.WHITE)
    love.graphics.printf(seed and ("Seed " .. seed) or "Set Seed", seedX, selectY + 5, seedW, "center")

    game._deck_select_rects = {
        prev = { x = prev_x, y = prev_y, w = prev_w, h = prev_h, action = "prev" },
        next = { x = next_x, y = prev_y, w = prev_w, h = prev_h, action = "next" },
        card = { x = selectX, y = selectY, w = selectW, h = selectH, action = "select" },
        seed = { x = seedX, y = selectY, w = seedW, h = selectH, action = "seed" },
    }

    love.graphics.setColor(C.MULT)
    draw_button_with_shadow(prev_x, prev_y, prev_w, prev_h, 4, 4, G.C.MULT, G.C.BLOCK.SHADOW, 2)
    draw_button_with_shadow(next_x, prev_y, prev_w, prev_h, 4, 4, G.C.MULT, G.C.BLOCK.SHADOW, 2)
    love.graphics.setColor(C.WHITE)
    love.graphics.setFont(font_s)
    love.graphics.printf("<", prev_x, prev_y + math.floor(frameH/2) - 2*padding, prev_w, "center")
    love.graphics.printf(">", next_x, prev_y + math.floor(frameH/2) - 2*padding, prev_w, "center")

    love.graphics.setColor(C.BLOCK.BACK)
    love.graphics.rectangle("fill", card_x, card_y, card_w, card_h, 8, 8)
    local dx,dy,dw,dh = MainMenuUI.draw_deck_carousel_sprite(game, def, card_x + 4, card_y, 64, card_h, 0, deck_unlocked)

    -- Infocard
    love.graphics.setColor(C.PANEL)
    local infoX,infoY,infoW,infoH = dx+dw + padding, card_y + padding, 2*dw - 16, card_h - 2*padding
    love.graphics.rectangle("fill", infoX, infoY, infoW, infoH, 4, 4)

    love.graphics.setFont(font_m)
    love.graphics.setColor(C.WHITE)
    if love.graphics.getFont():getWidth(def.name) > infoW then
        love.graphics.setFont(font_s)
        love.graphics.printf(def.name, infoX, infoY + 6, infoW, "center")
    else
        love.graphics.printf(def.name, infoX, infoY, infoW, "center")
    end
    love.graphics.setFont(font_m)
    local offset = love.graphics.getFont():getHeight(def.name)
    love.graphics.rectangle("fill", infoX + padding, infoY + padding + offset, infoW - 2*padding, infoH - 2*padding - offset, 4, 4)
    
    love.graphics.setFont(font_s)
    love.graphics.setColor(C.PANEL)
    love.graphics.printf(
        deck_unlocked and (def.description or "") or def.unlock_condition and def.unlock_condition.text or "Complete the unlock condition to play this deck.",
        infoX + 2*padding, infoY + 2*padding + offset, infoW - 4*padding, "center"
    )

    -- Stake markers, in the reference's three states (`UI_definitions.lua:3168-3180`):
    -- a stake that has been *cleared* on this deck shows in its own colour, one that has not
    -- is a flat translucent bar whether or not it is unlocked, and one that is not yet
    -- reachable is drawn narrow. So the column reads as a progress ladder, not a lock list --
    -- the port was tinting uncleared stakes at 0.8 of their colour, which made an unplayed
    -- stake look almost the same as a beaten one.
    local space = 2
    local markerX = infoX + infoW + padding
    local markerY = card_y + padding
    local markerY2 = card_y + card_h - padding - space
    local markerW, markerNarrowW = 20, 11
    local markerH = (math.floor((markerY2 - markerY - (#stake_list + 1) * space) / #stake_list + 1))
    game._stake_marker_rects = {}
    for i = 1, #stake_list do
        local stake = stake_list[i]
        local unlocked = deck_unlocked and game:is_stake_unlocked(def.id, stake and stake.id)
        local cleared = unlocked and game:is_stake_defeated(def.id, stake and stake.id)
        local w = unlocked and markerW or markerNarrowW
        local my = markerY2 - math.floor(markerH/2) - space - (markerH + space) * (i - 1)

        -- Only an unlocked stake is worth aiming at, so only those get a touch rect.
        if unlocked then
            game._stake_marker_rects[#game._stake_marker_rects + 1] =
                { x = markerX, y = my, w = w, h = markerH, index = i }
        end

        love.graphics.setColor(cleared and (stake.colour or C.WHITE) or C.UI.TRANSPARENT_LIGHT)
        love.graphics.rectangle("fill", markerX, my, w, markerH, 4, 4)
        if stake_idx == i then
            love.graphics.setColor(C.WHITE)
            love.graphics.rectangle("line", markerX, my, w, markerH, 2, 2)
        end
    end


    local limitX1 = startX + buttonW + 3 * padding
    local limitX2 = endX - buttonW - 3 * padding
    local dotY = startY + frameH - padding
    local offset = 8
    local midX = math.floor((limitX2 - limitX1)/2 + limitX1)
    --love.graphics.circle("fill", midX, dotY, 2)
    for i = 1,#deck_list do
        local mid = math.floor(#deck_list/2)
        x = midX + offset * (i - mid - 1)
        if sel_idx == i then
            love.graphics.setColor(C.WHITE)
        else
            love.graphics.setColor(C.BLOCK.BACK)
        end
        love.graphics.circle("fill", x, dotY, 2)
    end

    -- Stake Select
    prev_y = prev_y + frameH + 1 * padding
    local stakeH = 80
    card_y = prev_y

    game._stake_select_rects = {
        prev = { x = prev_x, y = prev_y, w = prev_w, h = stakeH, action = "prev" },
        next = { x = next_x, y = prev_y, w = prev_w, h = stakeH, action = "next" },
    }
    draw_button_with_shadow(prev_x, prev_y, prev_w, stakeH, 4, 4, G.C.MULT, G.C.BLOCK.SHADOW, 2)
    draw_button_with_shadow(next_x, prev_y, prev_w, stakeH, 4, 4, G.C.MULT, G.C.BLOCK.SHADOW, 2)
    love.graphics.setColor(C.WHITE)
    love.graphics.setFont(font_s)
    love.graphics.printf("<", prev_x, prev_y + math.floor(stakeH/2) - 2*padding, prev_w, "center")
    love.graphics.printf(">", next_x, prev_y + math.floor(stakeH/2) - 2*padding, prev_w, "center")

    -- Stake Infocard
    love.graphics.setColor(C.BLOCK.BACK)
    love.graphics.rectangle("fill", card_x, card_y, card_w, stakeH - 2*padding, 8, 8)
    local sx, sy, sw, sh = MainMenuUI.draw_stake_carousel_sprite(game, stake_def, card_x - 12, card_y, 64, stakeH - 2*padding, 0, stake_unlocked)

    love.graphics.setColor(C.PANEL)
    local stake_info_x = sx + sw + padding
    local stake_info_y = card_y + padding
    local stake_info_w = card_w - sw - 3 * padding
    local stake_info_h = stakeH - 4 * padding
    love.graphics.rectangle("fill", stake_info_x, stake_info_y, stake_info_w, stake_info_h, 4, 4)

    love.graphics.setFont(font_m)
    love.graphics.setColor(stake_unlocked and C.WHITE or C.GREY)
    if love.graphics.getFont():getWidth(stake_def.name) > stake_info_w then
        love.graphics.setFont(font_s)
        love.graphics.printf(stake_def.name, stake_info_x, stake_info_y + 6, stake_info_w, "center")
    else
        love.graphics.printf(stake_def.name, stake_info_x, stake_info_y, stake_info_w, "center")
    end
    love.graphics.setFont(font_m)
    local stake_name_h = love.graphics.getFont():getHeight()
    love.graphics.setColor(C.WHITE)
    love.graphics.rectangle("fill", stake_info_x + padding, stake_info_y + padding + stake_name_h, stake_info_w - 2 * padding, stake_info_h - 2 * padding - stake_name_h, 4, 4)

    love.graphics.setFont(font_s)
    love.graphics.setColor(C.PANEL)
    love.graphics.printf(
        stake_unlocked and (stake_def.description or "") or "Clear the previous stake first.",
        stake_info_x + 2 * padding, stake_info_y + padding + stake_name_h, stake_info_w - 4 * padding, "center"
    )

    local stake_dot_y = prev_y + stakeH - 1 * padding
    local stake_mid_x = math.floor((limitX2 - limitX1) / 2 + limitX1)
    for i = 1, #stake_list do
        local x = stake_mid_x + offset * (i - math.floor(#stake_list / 2) - 1)
        if stake_idx == i then
            love.graphics.setColor(C.WHITE)
        else
            love.graphics.setColor(C.BLOCK.BACK)
        end
        love.graphics.circle("fill", x, stake_dot_y, 2)
    end

    love.graphics.setFont(font_s)
    love.graphics.setColor(C.GREY)
    love.graphics.printf("A/Y: Play  START: Seed  LEFT/RIGHT: Deck  B/X: Back", 0, H - 14, W, "center")
end

--- The benchmark screen: a progress readout while the suite runs, then paged results.
---
--- Two states, no separate menu. Entering starts the run; every case is timed on the frame
--- it runs, so the screen also has to keep drawing. Draw-phase cases are stepped from here
--- rather than from update, because a graphics call outside `love.draw` builds a command
--- nobody submits and would time nothing.
function MainMenuUI.draw_benchmark(game)
    local W, H = 320, 240
    local C = game.C
    local font_s = game.FONTS.PIXEL.SMALL
    local font_m = game.FONTS.PIXEL.MEDIUM
    local margin = 12

    -- The case runs first and paints straight onto the screen; the panel below covers it.
    -- That is deliberate: a case has to draw for real to be worth timing.
    Benchmark.draw_step(game)

    draw_rect_with_shadow(0, 0, W, H, 6, 6, C.PANEL, C.BLOCK.SHADOW, 2)

    love.graphics.setFont(font_m)
    love.graphics.setColor(C.WHITE)
    love.graphics.printf("Benchmark", 0, margin, W, "center")

    local body_y = margin + 22
    local body_h = H - body_y - 40
    love.graphics.setColor(C.BLOCK.BACK)
    love.graphics.rectangle("fill", margin, body_y, W - margin * 2, body_h, 6, 6)

    love.graphics.setFont(font_s)
    if Benchmark.is_running() then
        local done, total = Benchmark.progress()
        love.graphics.setColor(C.WHITE)
        love.graphics.printf(string.format("Running %d / %d", done, total),
            margin, body_y + 12, W - margin * 2, "center")
        love.graphics.setColor(C.DARK_WHITE or C.GREY)
        love.graphics.printf(Benchmark.current_name(), margin + 6, body_y + 34,
            W - margin * 2 - 12, "center")

        local bar_w = W - margin * 2 - 24
        local bar_x = margin + 12
        local bar_y = body_y + 60
        love.graphics.setColor(C.BLACK)
        love.graphics.rectangle("fill", bar_x, bar_y, bar_w, 8, 3, 3)
        love.graphics.setColor(C.BLUE)
        love.graphics.rectangle("fill", bar_x, bar_y,
            math.floor(bar_w * (done / math.max(1, total))), 8, 3, 3)

        love.graphics.setColor(C.DARK_WHITE or C.GREY)
        love.graphics.printf("Leave it alone until it finishes.",
            margin + 6, body_y + 84, W - margin * 2 - 12, "center")
    elseif Benchmark.is_finished() then
        local lines = Benchmark.lines(game)
        local per = Benchmark.LINES_PER_PAGE
        local page = Benchmark.page()
        local first = (page - 1) * per + 1
        local line_h = love.graphics.getFont():getHeight() + 1
        local ty = body_y + 6
        love.graphics.setColor(C.WHITE)
        for i = first, math.min(#lines, first + per - 1) do
            love.graphics.print(lines[i], margin + 6, ty)
            ty = ty + line_h
        end

        love.graphics.setColor(C.DARK_WHITE or C.GREY)
        love.graphics.printf(string.format("page %d/%d   %s",
            page, Benchmark.page_count(game), Benchmark.write_status() or ""),
            margin, body_y + body_h - 12, W - margin * 2, "center")
    else
        love.graphics.setColor(C.WHITE)
        love.graphics.printf("Press A to start.", margin, body_y + 24, W - margin * 2, "center")
        love.graphics.setColor(C.DARK_WHITE or C.GREY)
        love.graphics.printf("Takes a while and the screen will flicker; that is the suite drawing.",
            margin + 6, body_y + 46, W - margin * 2 - 12, "center")
    end

    local btn_h, btn_w = 24, 88
    local btn_y = H - margin - btn_h
    local gap = 8
    local total_w = btn_w * 3 + gap * 2
    local bx = math.floor((W - total_w) * 0.5)

    game._benchmark_rects = {
        prev  = { x = bx, y = btn_y, w = btn_w, h = btn_h },
        start = { x = bx + btn_w + gap, y = btn_y, w = btn_w, h = btn_h },
        back  = { x = bx + (btn_w + gap) * 2, y = btn_y, w = btn_w, h = btn_h },
    }

    local function button(rect, label, colour)
        draw_button_with_shadow(rect.x, rect.y, rect.w, rect.h, 4, 4, colour, C.BLOCK.SHADOW, 2)
        love.graphics.setColor(C.WHITE)
        love.graphics.setFont(font_s)
        love.graphics.printf(label, rect.x, rect.y + 5, rect.w, "center")
    end

    local r = game._benchmark_rects
    if Benchmark.is_finished() then
        button(r.prev, "< Page", C.MULT)
        button(r.start, "Page >", C.MULT)
    else
        button(r.start, Benchmark.is_running() and "..." or "Start", C.BLUE)
    end
    button(r.back, "Back", C.MULT)
end

function MainMenuUI._touch_benchmark(game, x, y)
    local r = game._benchmark_rects or {}
    if Benchmark.is_running() then return true end

    if Benchmark.is_finished() then
        if r.prev and game:_point_in_rect_simple(x, y, r.prev) then
            Benchmark.turn_page(game, -1); Sfx.play("highlight2", 0.685, 0.2); return true
        end
        if r.start and game:_point_in_rect_simple(x, y, r.start) then
            Benchmark.turn_page(game, 1); Sfx.play("highlight2", 0.685, 0.2); return true
        end
    elseif r.start and game:_point_in_rect_simple(x, y, r.start) then
        Benchmark.start(game); Sfx.play("button"); return true
    end

    if r.back and game:_point_in_rect_simple(x, y, r.back) then
        game._menu_sub_state = "main"
        Sfx.play("cancel")
        return true
    end
    return false
end

function MainMenuUI._button_benchmark(game, btn)
    -- The run owns the machine while it is timing; taking input mid-case would land in
    -- whichever measurement happened to be in flight.
    if Benchmark.is_running() then return end

    if game.is_menu_back and game:is_menu_back(btn) then
        game._menu_sub_state = "main"
        Sfx.play("cancel")
        return
    end
    if Benchmark.is_finished() then
        if btn == "dpleft" or btn == "left" then
            Benchmark.turn_page(game, -1); Sfx.play("highlight2", 0.685, 0.2)
        elseif btn == "dpright" or btn == "right" then
            Benchmark.turn_page(game, 1); Sfx.play("highlight2", 0.685, 0.2)
        elseif btn == "dpdown" or btn == "down" then
            Benchmark.turn_page(game, 1); Sfx.play("highlight2", 0.685, 0.2)
        elseif btn == "dpup" or btn == "up" then
            Benchmark.turn_page(game, -1); Sfx.play("highlight2", 0.685, 0.2)
        end
        return
    end
    if game.is_menu_activate and game:is_menu_activate(btn) then
        Benchmark.start(game)
        Sfx.play("button")
    end
end

function MainMenuUI.handle_touch(game, x, y)
    -- Swallowed rather than passed through: the rects under the finger belong to the settled
    -- layout, not the one on screen, so acting on them would fire the wrong button.
    if MainMenuUI.slide_active(game) then return true end
    if game._menu_sub_state == "deck_select" then
        return MainMenuUI._touch_deck_select(game, x, y)
    end
    if game._menu_sub_state == "how_to_play" then
        return MainMenuUI._touch_how_to_play(game, x, y)
    end
    if game._menu_sub_state == "collection_menu" then
        return CollectionUI.handle_touch_menu(game, x, y)
    end
    if game._menu_sub_state == "profile" then
        return ProfileUI.handle_touch(game, x, y)
    end
    if game._menu_sub_state == "stats" then
        return ProfileUI.handle_stats_touch(game, x, y)
    end
    if game._menu_sub_state == "challenges" then
        return MainMenuUI._touch_challenges(game, x, y)
    end
    if game._menu_sub_state == "benchmark" then
        return MainMenuUI._touch_benchmark(game, x, y)
    end
    return MainMenuUI._touch_main(game, x, y)
end

function MainMenuUI._touch_main(game, x, y)
    for i, target in ipairs(MainMenuUI.build_main_menu_focus_targets(game)) do
        if game:_point_in_rect_simple(x, y, target.rect) then
            game._menu_focus_index = i
            return MainMenuUI.activate_menu_entry(game, target.kind)
        end
    end
    return false
end

function MainMenuUI._touch_how_to_play(game, x, y)
    local rects = game._how_to_play_rects or {}
    local page_count = #(MainMenuUI.HOW_TO_PLAY_PAGES or {})
    local page_idx = tonumber(game._how_to_play_page) or 1

    if rects.prev and page_idx > 1 and game:_point_in_rect_simple(x, y, rects.prev) then
        game._how_to_play_page = page_idx - 1
        Sfx.play("highlight2", 0.685, 0.2)
        return true
    end

    if rects.next and page_idx < page_count and game:_point_in_rect_simple(x, y, rects.next) then
        game._how_to_play_page = page_idx + 1
        Sfx.play("highlight2", 0.685, 0.2)
        return true
    end

    local back = game._how_to_play_back_rect
    if back and game:_point_in_rect_simple(x, y, back) then
        game._menu_sub_state = "main"
        Sfx.play("cancel")
        return true
    end

    return false
end

--- Move the deck carousel, clamped, and pop the sprite if it actually moved. Both the arrows
--- and the d-pad go through here so the two paths cannot drift.
function MainMenuUI.set_deck_index(game, idx)
    local deck_list = DECK_SELECT_DEFS or DECK_DEFS or {}
    local from = tonumber(game._deck_select_idx) or 1
    idx = math.max(1, math.min(#deck_list, math.floor(tonumber(idx) or from)))
    game._deck_select_idx = idx
    if idx ~= from then
        MainMenuUI.juice_deck_sprite(game)
    end
    click_focus_move(from, idx)
    return idx
end

function MainMenuUI._touch_deck_select(game, x, y)
    local deck_rects = game._deck_select_rects or {}
    local stake_rects = game._stake_select_rects or {}
    local stake_list = STAKE_DEFS or {}
    local deck_idx = tonumber(game._deck_select_idx) or 1
    local stake_idx = tonumber(game._stake_select_idx) or 1

    if deck_rects.prev and game:_point_in_rect_simple(x, y, deck_rects.prev) then
        MainMenuUI.set_deck_index(game, deck_idx - 1)
        return true
    end

    if deck_rects.next and game:_point_in_rect_simple(x, y, deck_rects.next) then
        MainMenuUI.set_deck_index(game, deck_idx + 1)
        return true
    end

    if stake_rects.prev and game:_point_in_rect_simple(x, y, stake_rects.prev) then
        game._stake_select_idx = math.max(1, stake_idx - 1)
        click_focus_move(stake_idx, game._stake_select_idx)
        return true
    end

    if stake_rects.next and game:_point_in_rect_simple(x, y, stake_rects.next) then
        game._stake_select_idx = math.min(#stake_list, stake_idx + 1)
        click_focus_move(stake_idx, game._stake_select_idx)
        return true
    end

    -- The stake ladder is a control, not just a readout: tapping an unlocked rung selects it.
    -- Locked rungs get no rect, so a tap on one falls through instead of moving the selection.
    for _, marker in ipairs(game._stake_marker_rects or {}) do
        if game:_point_in_rect_simple(x, y, marker) then
            game._stake_select_idx = marker.index
            click_focus_move(stake_idx, marker.index)
            return true
        end
    end

    if deck_rects.card and game:_point_in_rect_simple(x, y, deck_rects.card) then
        MainMenuUI._start_run(game)
        return true
    end

    if deck_rects.seed and game:_point_in_rect_simple(x, y, deck_rects.seed) then
        MainMenuUI.begin_seed_entry(game)
        return true
    end

    return false
end

function MainMenuUI.handle_button(game, btn)
    MainMenuUI.try_konami_cheat(game, btn)
    -- Settings opened from the menu borrows the pause panel, so it borrows its button handling
    -- too; otherwise these presses would move the hidden main-menu focus behind it.
    if game._settings_over_menu then
        if game.handle_gamepad_pause then game:handle_gamepad_pause(btn) end
        return
    end
    if game._menu_sub_state == "deck_select" then
        MainMenuUI._button_deck_select(game, btn)
    elseif game._menu_sub_state == "how_to_play" then
        MainMenuUI._button_how_to_play(game, btn)
    elseif game._menu_sub_state == "collection_menu" or game._menu_sub_state == "collection_grid" then
        CollectionUI.handle_button(game, btn)
    elseif game._menu_sub_state == "profile" then
        ProfileUI.handle_button(game, btn)
    elseif game._menu_sub_state == "stats" then
        ProfileUI.handle_stats_button(game, btn)
    elseif game._menu_sub_state == "challenges" then
        MainMenuUI._button_challenges(game, btn)
    elseif game._menu_sub_state == "benchmark" then
        MainMenuUI._button_benchmark(game, btn)
    else
        MainMenuUI._button_main(game, btn)
    end
end

function MainMenuUI.draw_challenges(game)
    local W, H, C = 320, 240, game.C
    local defs = CHALLENGE_DEFS or {}
    local per_page = 10
    local pages = math.max(1, math.ceil(#defs / per_page))
    local page = math.max(1, math.min(pages, tonumber(game._challenge_page) or 1))
    local selected = math.max(1, math.min(#defs, tonumber(game._challenge_selected) or 1))
    game._challenge_page, game._challenge_selected = page, selected
    love.graphics.setColor(C.PANEL)
    love.graphics.rectangle("fill", 0, 0, W, H)
    love.graphics.setFont(game.FONTS.PIXEL.MEDIUM)
    love.graphics.setColor(C.WHITE)
    love.graphics.printf("Challenges", 0, 8, W, "center")
    love.graphics.setFont(game.FONTS.PIXEL.SMALL)
    local completed = 0
    for _, d in ipairs(defs) do if game:is_challenge_completed(d.id) then completed = completed + 1 end end
    love.graphics.printf(string.format("%d/%d complete  Page %d/%d", completed, #defs, page, pages), 0, 26, W, "center")
    local panel = { x = 20, y = 44, w = 280, h = 150 }
    love.graphics.setColor(C.BLOCK.BACK)
    love.graphics.rectangle("fill", panel.x, panel.y, panel.w, panel.h, 6, 6)
    game._challenge_rects = { rows = {}, prev = { x = 20, y = 202, w = 54, h = 24 }, next = { x = 246, y = 202, w = 54, h = 24 }, back = { x = 92, y = 202, w = 58, h = 24 }, play = { x = 170, y = 202, w = 58, h = 24 } }
    local start = (page - 1) * per_page + 1
    for row = 1, per_page do
        local idx = start + row - 1
        local d = defs[idx]
        if not d then break end
        local r = { x = 28, y = 46 + (row - 1) * 15, w = 264, h = 13, index = idx }
        game._challenge_rects.rows[#game._challenge_rects.rows + 1] = r
        local chosen = idx == selected
        love.graphics.setColor(chosen and C.RED or C.PANEL)
        love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 3, 3)
        love.graphics.setColor(C.WHITE)
        love.graphics.printf(d.name, r.x + 6, r.y + 2, r.w - 28, "left")
        if game:is_challenge_completed(d.id) then
            love.graphics.setColor(C.GREEN)
            love.graphics.printf("X", r.x + r.w - 18, r.y + 2, 12, "center")
        end
    end
    local function button(rect, label, color)
        draw_button_with_shadow(rect.x, rect.y, rect.w, rect.h, 4, 4, color, C.BLOCK.SHADOW, 2)
        love.graphics.setColor(C.WHITE); love.graphics.printf(label, rect.x, rect.y + 6, rect.w, "center")
    end
    button(game._challenge_rects.prev, "<", C.MULT)
    button(game._challenge_rects.next, ">", C.MULT)
    button(game._challenge_rects.back, "Back", C.MULT)
    button(game._challenge_rects.play, "Play", C.GREEN)
end

function MainMenuUI._touch_challenges(game, x, y)
    local r = game._challenge_rects or {}
    for _, row in ipairs(r.rows or {}) do
        if game:_point_in_rect_simple(x, y, row) then game._challenge_selected = row.index; Sfx.play("highlight1"); return true end
    end
    if r.prev and game:_point_in_rect_simple(x, y, r.prev) then game._challenge_page = math.max(1, (game._challenge_page or 1) - 1); return true end
    if r.next and game:_point_in_rect_simple(x, y, r.next) then game._challenge_page = math.min(2, (game._challenge_page or 1) + 1); return true end
    if r.back and game:_point_in_rect_simple(x, y, r.back) then game._menu_sub_state = "main"; Sfx.play("cancel"); return true end
    if r.play and game:_point_in_rect_simple(x, y, r.play) then return game:start_challenge_run((CHALLENGE_DEFS or {})[game._challenge_selected].id) end
    return false
end

function MainMenuUI._button_challenges(game, btn)
    local defs = CHALLENGE_DEFS or {}
    local selected = tonumber(game._challenge_selected) or 1
    if btn == "dpup" or btn == "up" then selected = math.max(1, selected - 1)
    elseif btn == "dpdown" or btn == "down" then selected = math.min(#defs, selected + 1)
    elseif btn == "dpleft" or btn == "left" then game._challenge_page = math.max(1, (game._challenge_page or 1) - 1)
    elseif btn == "dpright" or btn == "right" then game._challenge_page = math.min(2, (game._challenge_page or 1) + 1)
    elseif game.is_menu_activate and game:is_menu_activate(btn) and defs[selected] then game:start_challenge_run(defs[selected].id); return
    elseif game.is_menu_back and game:is_menu_back(btn) then game._menu_sub_state = "main"; Sfx.play("cancel"); return end
    game._challenge_selected = selected
    game._challenge_page = math.floor((selected - 1) / 10) + 1
end

function MainMenuUI._button_how_to_play(game, btn)
    local page_count = #(MainMenuUI.HOW_TO_PLAY_PAGES or {})
    local page_idx = tonumber(game._how_to_play_page) or 1

    if btn == "dpleft" or btn == "left" then
        if page_idx > 1 then
            game._how_to_play_page = page_idx - 1
            Sfx.play("highlight2", 0.685, 0.2)
        end
    elseif btn == "dpright" or btn == "right" then
        if page_idx < page_count then
            game._how_to_play_page = page_idx + 1
            Sfx.play("highlight2", 0.685, 0.2)
        end
    elseif game.is_menu_back and game:is_menu_back(btn) then
        game._menu_sub_state = "main"
        Sfx.play("cancel")
    end
end

function MainMenuUI._button_main(game, btn)
    if btn == "dpup" or btn == "up" then
        MainMenuUI.main_menu_focus_move(game, -1)
        return
    end
    if btn == "dpdown" or btn == "down" then
        MainMenuUI.main_menu_focus_move(game, 1)
        return
    end
    if btn == "dpleft" or btn == "left" then
        MainMenuUI.main_menu_focus_move(game, -1)
        return
    end
    if btn == "dpright" or btn == "right" then
        MainMenuUI.main_menu_focus_move(game, 1)
        return
    end
    if game.is_menu_activate and game:is_menu_activate(btn) then
        MainMenuUI.activate_main_menu_focus(game)
        return
    end
    -- Cancel walks back up the tree. The root has nowhere to go, so it stays put rather than
    -- chirping at a press that did nothing.
    if game.is_menu_back and game:is_menu_back(btn) then
        if MainMenuUI.current_page(game) ~= "main" then
            MainMenuUI.open_page(game, "main")
        end
        return
    end
end

function MainMenuUI._button_deck_select(game, btn)
    local stake_list = STAKE_DEFS or {}
    local deck_idx = tonumber(game._deck_select_idx) or 1
    local stake_idx = tonumber(game._stake_select_idx) or 1

    if btn == "start" then
        MainMenuUI.begin_seed_entry(game)
        return
    elseif btn == "dpleft" or btn == "left" then
        MainMenuUI.set_deck_index(game, deck_idx - 1)
        return
    elseif btn == "dpright" or btn == "right" then
        MainMenuUI.set_deck_index(game, deck_idx + 1)
        return
    -- Up climbs the ladder, down descends it, and both clamp to the list. The bounds used to
    -- be crossed (`max` on the way up, `min` on the way down), which let the index leave the
    -- list entirely; the screen redrew clamped but `_start_run` read the stored value and
    -- refused to start until the selection was nudged back in range.
    elseif btn == "dpup" or btn == "up" then
        game._stake_select_idx = math.min(#stake_list, stake_idx + 1)
    elseif btn == "dpdown" or btn == "down" then
        game._stake_select_idx = math.max(1, stake_idx - 1)
    elseif game.is_menu_activate and game:is_menu_activate(btn) then
        MainMenuUI._start_run(game)
        return
    elseif game.is_menu_back and game:is_menu_back(btn) then
        game._menu_sub_state = "main"
        Sfx.play("cancel")
        return
    end
    click_focus_move(stake_idx, game._stake_select_idx)
end

return MainMenuUI
