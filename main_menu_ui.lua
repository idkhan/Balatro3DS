
local MainMenuUI = {}
local CollectionUI = require("collection_ui")

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
            "Hold Y + Left/Right: Sweep select",
            "B: Discard selected cards",
            "X: Play selected cards",
            "Y (tap): Toggle rank/suit sort",
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
            "A: Select joker (pick two to swap)",
            "Hold A + Left/Right: Reorder",
            "B: Sell",
            "X: Use consumable",
        },
    },
    {
        title = "Gamepad - Shop",
        lines = {
            "D-Pad Left/Right: Move shop cursor",
            "A: Buy     X: Buy and Use",
            "Y: Reroll Shop",
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
            "Confirm: Start blind   Cancel: Skip",
            "Sort: Reroll boss (with voucher)",
            "",
            "Deck select:",
            "Left/Right: Pick deck   Up/Down: Stake",
            "Confirm: Begin   Cancel/Use: Back",
        },
    },
}

function MainMenuUI.open_how_to_play(game)
    game._menu_sub_state = "how_to_play"
    game._how_to_play_page = game._how_to_play_page or 1
end

local MENU_ANIM_FPS = 12

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

    local atlas = nil
    if game.ensure_animation_atlas_loaded then
        atlas = game:ensure_animation_atlas_loaded("menu")
    else
        atlas = game.ANIMATION_ATLAS and game.ANIMATION_ATLAS.menu
    end
    if not atlas or not atlas.image then
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

    local cell_w = tonumber(atlas.px) or 256
    local cell_h = tonumber(atlas.py) or 256
    local frame_count = tonumber(atlas.frames) or 16
    local frame = menu_ping_pong_frame(frame_count, MENU_ANIM_FPS)

    local iw, ih = atlas.image:getDimensions()
    local cols = math.max(1, math.floor(iw / cell_w))
    local col = frame % cols
    local row = math.floor(frame / cols)
    local quad = love.graphics.newQuad(col * cell_w, row * cell_h, cell_w, cell_h, iw, ih)

    local s = math.max(w / cell_w, h / cell_h)
    local draw_w = cell_w * s
    local draw_h = cell_h * s
    local dx = math.floor((w - draw_w) * 0.5 + 0.5)
    local dy = math.floor((h - draw_h) * 0.5 + 0.5)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(atlas.image, quad, dx, dy, 0, s, s)
end

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

    local panel_x, panel_y, panel_w = 24, 10, 352

    local atlas = nil
    if game.ensure_asset_atlas_loaded then
        atlas = game:ensure_asset_atlas_loaded("balatro")
    end

    if atlas and atlas.image then
        local iw, ih = atlas.image:getDimensions()
        local max_w, max_h = 336, 216
        local s = math.min(max_w / iw, max_h / ih)
        if s > 1 then s = 1 end
        local draw_w = iw * s
        local draw_h = ih * s
        local dx = panel_x + math.floor((panel_w - draw_w) * 0.5 + 0.5)
        local dy = panel_y 
        love.graphics.setColor(game.C.WHITE)
        love.graphics.draw(atlas.image, dx - titleDepth * sysDepth, dy, 0, s, s)
    end
end

function MainMenuUI.open_deck_select(game)
    game._deck_select_idx = game._deck_select_idx or 1
    game._stake_select_idx = game._stake_select_idx or 1
    game._menu_sub_state = "deck_select"
end

function MainMenuUI.draw_bottom(game)
    if game._menu_sub_state == "deck_select" then
        MainMenuUI.draw_deck_select(game)
    elseif game._menu_sub_state == "how_to_play" then
        MainMenuUI.draw_how_to_play(game)
    elseif game._menu_sub_state == "collection_menu" or game._menu_sub_state == "collection_grid" then
        CollectionUI.draw_bottom(game)
    else
        MainMenuUI.draw_main(game)
    end
end

function MainMenuUI.draw_main(game)
    local has_save = game.has_saved_run and game:has_saved_run() == true
    local panel_w, panel_h = 220, (has_save and 168) or 138
    local panel_y = 240/2 - panel_h/2 - 22
    local panel_x = 320/2 - panel_w/2

    if _G.draw_rect_with_shadow then
        draw_rect_with_shadow(panel_x, panel_y, panel_w, panel_h, 6, 3,
            game.C.PANEL, game.C.BLOCK.SHADOW, 3)
    else
        love.graphics.setColor(game.C.PANEL)
        love.graphics.rectangle("fill", panel_x, panel_y, panel_w, panel_h, 6, 6)
    end

    love.graphics.setColor(game.C.WHITE)
    love.graphics.setFont(game.FONTS.PIXEL.MEDIUM)

    local btn_w, btn_h = 160, 28
    local btn_gap = 6
    local btn_x = panel_x + math.floor((panel_w - btn_w) * 0.5 + 0.5)
    game._main_menu_how_to_play_rect = nil

    if has_save then
        local y0 = panel_y + 20
        game._main_menu_continue_rect = { x = btn_x, y = y0, w = btn_w, h = btn_h }
        game._main_menu_start_rect    = { x = btn_x, y = y0 + btn_h + btn_gap, w = btn_w, h = btn_h }
        game._main_menu_how_to_play_rect = { x = btn_x, y = y0 + (btn_h + btn_gap) * 2, w = btn_w, h = btn_h }
        game._main_menu_collection_rect = { x = btn_x, y = y0 + (btn_h + btn_gap) * 3, w = btn_w, h = btn_h }

        draw_rect_with_shadow(
            game._main_menu_continue_rect.x, game._main_menu_continue_rect.y,
            game._main_menu_continue_rect.w, game._main_menu_continue_rect.h, 4, 4,
            game.C.BLUE, game.C.BLOCK.SHADOW, 2)

        draw_rect_with_shadow(
            game._main_menu_start_rect.x, game._main_menu_start_rect.y,
            game._main_menu_start_rect.w, game._main_menu_start_rect.h, 4, 4,
            game.C.GREEN, game.C.BLOCK.SHADOW, 2)

        draw_rect_with_shadow(
            game._main_menu_how_to_play_rect.x, game._main_menu_how_to_play_rect.y,
            game._main_menu_how_to_play_rect.w, game._main_menu_how_to_play_rect.h, 4, 4,
            game.C.MULT, game.C.BLOCK.SHADOW, 2)

        draw_rect_with_shadow(
            game._main_menu_collection_rect.x, game._main_menu_collection_rect.y,
            game._main_menu_collection_rect.w, game._main_menu_collection_rect.h, 4, 4,
            game.C.ORANGE or game.C.BLUE, game.C.BLOCK.SHADOW, 2)

        love.graphics.setColor(game.C.WHITE)
        love.graphics.setFont(game.FONTS.PIXEL.MEDIUM)

        local function btn_label_y(r)
            return r.y + math.floor((r.h - love.graphics.getFont():getHeight()) * 0.5 + 0.5)
        end

        love.graphics.printf("Continue Run",
            game._main_menu_continue_rect.x, btn_label_y(game._main_menu_continue_rect),
            game._main_menu_continue_rect.w, "center")

        love.graphics.printf("New Run",
            game._main_menu_start_rect.x, btn_label_y(game._main_menu_start_rect),
            game._main_menu_start_rect.w, "center")

        love.graphics.setFont(game.FONTS.PIXEL.MEDIUM)
        love.graphics.printf("How to Play",
            game._main_menu_how_to_play_rect.x, btn_label_y(game._main_menu_how_to_play_rect),
            game._main_menu_how_to_play_rect.w, "center")

        love.graphics.printf("Collection",
            game._main_menu_collection_rect.x, btn_label_y(game._main_menu_collection_rect),
            game._main_menu_collection_rect.w, "center")
    else
        game._main_menu_continue_rect = nil
        local y0 = panel_y + 20
        game._main_menu_start_rect = { x = btn_x, y = y0, w = btn_w, h = btn_h }
        game._main_menu_how_to_play_rect = { x = btn_x, y = y0 + btn_h + btn_gap, w = btn_w, h = btn_h }
        game._main_menu_collection_rect = { x = btn_x, y = y0 + (btn_h + btn_gap) * 2, w = btn_w, h = btn_h }

        draw_rect_with_shadow(
            game._main_menu_start_rect.x, game._main_menu_start_rect.y,
            game._main_menu_start_rect.w, game._main_menu_start_rect.h, 4, 4,
            game.C.GREEN, game.C.BLOCK.SHADOW, 2)

        draw_rect_with_shadow(
            game._main_menu_how_to_play_rect.x, game._main_menu_how_to_play_rect.y,
            game._main_menu_how_to_play_rect.w, game._main_menu_how_to_play_rect.h, 4, 4,
            game.C.MULT, game.C.BLOCK.SHADOW, 2)

        draw_rect_with_shadow(
            game._main_menu_collection_rect.x, game._main_menu_collection_rect.y,
            game._main_menu_collection_rect.w, game._main_menu_collection_rect.h, 4, 4,
            game.C.ORANGE or game.C.BLUE, game.C.BLOCK.SHADOW, 2)

        love.graphics.setColor(game.C.WHITE)
        love.graphics.setFont(game.FONTS.PIXEL.MEDIUM)
        local function btn_label_y(r)
            return r.y + math.floor((r.h - love.graphics.getFont():getHeight()) * 0.5 + 0.5)
        end
        love.graphics.printf("Start Run",
            game._main_menu_start_rect.x, btn_label_y(game._main_menu_start_rect),
            game._main_menu_start_rect.w, "center")

        love.graphics.setFont(game.FONTS.PIXEL.MEDIUM)
        love.graphics.printf("How to Play",
            game._main_menu_how_to_play_rect.x, btn_label_y(game._main_menu_how_to_play_rect),
            game._main_menu_how_to_play_rect.w, "center")

        love.graphics.printf("Collection",
            game._main_menu_collection_rect.x, btn_label_y(game._main_menu_collection_rect),
            game._main_menu_collection_rect.w, "center")

        if game.SEED then
            love.graphics.setFont(game.FONTS.PIXEL.SMALL)
            love.graphics.setColor(game.C.DARK_WHITE or game.C.GREY)
            love.graphics.printf(
                "Seed " .. tostring(math.floor(tonumber(game.SEED) or 0)),
                panel_x, 240 - 50, panel_w, "center"
            )
        end
    end

    -- Profile Buttons
    local profile_count = game.get_profile_count and game:get_profile_count() or 3
    local profile_padding = 4
    local profile_btn_w = ((320 - profile_padding * 2) - (profile_padding * (profile_count))) / (profile_count + 1)
    local profile_btn_h = 28
    local profile_btn_x = profile_padding
    local profile_btn_y = 240 - profile_btn_h - profile_padding
    local active_profile = game.get_profile_id and game:get_profile_id() or 1
    game._main_menu_profile_rects = {}
    for i = 1, profile_count do
        local is_active = (i == active_profile)
        local color = is_active and game.C.GREEN or game.C.MULT
        draw_rect_with_shadow(profile_btn_x, profile_btn_y, profile_btn_w, profile_btn_h, 4, 4, color, game.C.BLOCK.SHADOW, 2)
        love.graphics.setColor(game.C.WHITE)
        love.graphics.setFont(game.FONTS.PIXEL.MEDIUM)
        local label_y = profile_btn_y + math.floor((profile_btn_h - love.graphics.getFont():getHeight()) * 0.5 + 0.5)
        love.graphics.printf("P" .. i, profile_btn_x, label_y, profile_btn_w, "center")
        game._main_menu_profile_rects[i] = { x = profile_btn_x, y = profile_btn_y, w = profile_btn_w, h = profile_btn_h }
        profile_btn_x = profile_btn_x + profile_btn_w + profile_padding
    end

    -- Delete Save (confirm on second tap)
    local delete_confirm = game._delete_save_confirm == true
    local delete_color = delete_confirm and game.C.RED or game.C.BOOSTER
    draw_rect_with_shadow(profile_btn_x, profile_btn_y, profile_btn_w, profile_btn_h, 4, 4, delete_color, game.C.BLOCK.SHADOW, 2)
    love.graphics.setColor(game.C.WHITE)
    love.graphics.setFont(game.FONTS.PIXEL.SMALL)
    local delete_label = delete_confirm and "Confirm?" or "Delete Save"
    love.graphics.printf(delete_label, profile_btn_x, profile_btn_y + math.floor((profile_btn_h - love.graphics.getFont():getHeight()) * 0.5 + 0.5), profile_btn_w, "center")
    game._main_menu_delete_save_rect = { x = profile_btn_x, y = profile_btn_y, w = profile_btn_w, h = profile_btn_h }

    local targets = MainMenuUI.build_main_menu_focus_targets(game)
    local focus_idx = tonumber(game._menu_focus_index) or 1
    focus_idx = math.max(1, math.min(#targets, focus_idx))
    game._menu_focus_index = focus_idx
    local focused = targets[focus_idx]
    if focused and focused.rect then
        local r = focused.rect
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", r.x + 0.5, r.y + 0.5, r.w - 1, r.h - 1)
    end
end

function MainMenuUI.build_main_menu_focus_targets(game)
    local targets = {}
    if game._main_menu_continue_rect then
        targets[#targets + 1] = { kind = "continue", rect = game._main_menu_continue_rect }
    end
    if game._main_menu_start_rect then
        targets[#targets + 1] = { kind = "start", rect = game._main_menu_start_rect }
    end
    if game._main_menu_how_to_play_rect then
        targets[#targets + 1] = { kind = "how_to_play", rect = game._main_menu_how_to_play_rect }
    end
    if game._main_menu_collection_rect then
        targets[#targets + 1] = { kind = "collection", rect = game._main_menu_collection_rect }
    end
    for i, pr in ipairs(game._main_menu_profile_rects or {}) do
        if pr then
            targets[#targets + 1] = { kind = "profile", index = i, rect = pr }
        end
    end
    if game._main_menu_delete_save_rect then
        targets[#targets + 1] = { kind = "delete", rect = game._main_menu_delete_save_rect }
    end
    return targets
end

function MainMenuUI.main_menu_focus_move(game, delta)
    local targets = MainMenuUI.build_main_menu_focus_targets(game)
    if #targets == 0 then return nil end
    delta = math.floor(tonumber(delta) or 0)
    local idx = tonumber(game._menu_focus_index) or 1
    idx = idx + delta
    if idx < 1 then idx = #targets elseif idx > #targets then idx = 1 end
    game._menu_focus_index = idx
    return targets[idx]
end

function MainMenuUI.activate_main_menu_focus(game)
    local targets = MainMenuUI.build_main_menu_focus_targets(game)
    local idx = tonumber(game._menu_focus_index) or 1
    idx = math.max(1, math.min(#targets, idx))
    local t = targets[idx]
    if not t then return false end
    if t.kind == "continue" then
        if game.continue_saved_run_from_main_menu then
            game:continue_saved_run_from_main_menu()
        end
        return true
    elseif t.kind == "start" then
        MainMenuUI.open_deck_select(game)
        return true
    elseif t.kind == "how_to_play" then
        MainMenuUI.open_how_to_play(game)
        return true
    elseif t.kind == "collection" then
        CollectionUI.open(game)
        return true
    elseif t.kind == "profile" and t.index and game.switch_profile then
        game:switch_profile(t.index)
        return true
    elseif t.kind == "delete" then
        if game._delete_save_confirm then
            if game.delete_profile_progress then
                game:delete_profile_progress()
            end
        else
            game._delete_save_confirm = true
        end
        return true
    end
    return false
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
        draw_rect_with_shadow(prev_x, nav_y, arrow_w, nav_h, 4, 4, C.MULT, C.BLOCK.SHADOW, 2)
        love.graphics.setColor(C.WHITE)
        love.graphics.setFont(font_s)
        love.graphics.printf("<", prev_x, nav_y + 4, arrow_w, "center")
    end

    if page_idx < page_count then
        draw_rect_with_shadow(next_x, nav_y, arrow_w, nav_h, 4, 4, C.MULT, C.BLOCK.SHADOW, 2)
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
    draw_rect_with_shadow(back_x, back_y, back_w, back_h, 4, 4, C.MULT, C.BLOCK.SHADOW, 2)
    love.graphics.setColor(C.WHITE)
    love.graphics.setFont(font_s)
    love.graphics.printf("Back", back_x, back_y + 5, back_w, "center")

    love.graphics.setFont(font_s)
    love.graphics.setColor(C.GREY)
    love.graphics.printf("B/X: Back   LEFT/RIGHT: Pages", 0, H - 14, W, "center")
end

function MainMenuUI.draw_deck_carousel_sprite(game, def, x, y, w, h, p)
    local atlas = nil
    if game.ensure_asset_atlas_loaded then
        atlas = game:ensure_asset_atlas_loaded("centers")
    end

    if atlas and atlas.image then
        local index = tonumber(def and def.pos) or 0
        if def and not def.unlocked then
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

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(atlas.image, quad, dx, dy, 0, scale, scale)
        return dx,dy, draw_w, draw_h
    end

    love.graphics.setColor(0.25, 0.25, 0.25, 1)
    love.graphics.rectangle("fill", x, y, w, h, 8, 8)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf("Sprite unavailable", x, y + math.floor(h * 0.5) - 6, w, "center")
    return false
end

function MainMenuUI.draw_stake_carousel_sprite(game, def, x, y, w, h, p)
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

        if def and not def.unlocked then
            love.graphics.setColor(0.35, 0.35, 0.35, 1)
        else
            love.graphics.setColor(1, 1, 1, 1)
        end
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
    local deck_list = DECK_DEFS or {}
    local stake_list = STAKE_DEFS or {}
    local deck_idx = tonumber(game._deck_select_idx) or 1
    local stake_idx = tonumber(game._stake_select_idx) or 1
    local deck_def = deck_list[deck_idx]
    local stake_def = stake_list[stake_idx]
    if not deck_def or not game:is_deck_unlocked(deck_def.id) then return false end
    if not stake_def or not game:is_stake_unlocked(deck_def.id, stake_def.id) then return false end

    game._pending_deck_id = deck_def.id
    game._pending_stake_id = stake_def.id
    game._menu_sub_state = nil
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

    local deck_list = DECK_DEFS or {}
    local stake_list = STAKE_DEFS or {}
    local sel_idx = tonumber(game._deck_select_idx) or 1
    sel_idx = math.max(1, math.min(#deck_list, sel_idx))
    local def = deck_list[sel_idx]
    if not def then return end

    local stake_idx = tonumber(game._stake_select_idx) or 1
    stake_idx = math.max(1, math.min(#stake_list, stake_idx))
    local stake_def = stake_list[stake_idx]
    if not stake_def then return end
    local stake_unlocked = game:is_stake_unlocked(def.id, stake_def.id)

    local startX, startY = 24, 4
    local endX, endY = W - 24, H - 128
    local padding = 4
    local buttonW = 24

    local frameW = endX - startX
    local frameH = endY - startY

    local prev_x, prev_y, prev_w, prev_h = startX, startY, buttonW, frameH
    local next_x = W - 52
    local card_x, card_y, card_w, card_h = startX + buttonW + padding, startY + padding, frameW - 2*buttonW - 3*padding, frameH - 4*padding -- Select Button

    local selectbuttonW = frameW - padding - 64
    local selectX, selectY, selectW, selectH = startX + 32, 200, selectbuttonW, 24
    draw_rect_with_shadow(selectX, selectY, selectW, selectH, 4, 4, G.C.CHIPS, G.C.BLOCK.SHADOW, 2)
    love.graphics.setFont(font_m)
    love.graphics.setColor(C.WHITE)
    love.graphics.printf("PLAY", selectX, selectY, selectW, "center")

    game._deck_select_rects = {
        prev = { x = prev_x, y = prev_y, w = prev_w, h = prev_h, action = "prev" },
        next = { x = next_x, y = prev_y, w = prev_w, h = prev_h, action = "next" },
        card = { x = selectX, y = selectY, w = selectW, h = selectH, action = "select" },
    }

    love.graphics.setColor(C.MULT)
    draw_rect_with_shadow(prev_x, prev_y, prev_w, prev_h, 4, 4, G.C.MULT, G.C.BLOCK.SHADOW, 2)
    draw_rect_with_shadow(next_x, prev_y, prev_w, prev_h, 4, 4, G.C.MULT, G.C.BLOCK.SHADOW, 2)
    love.graphics.setColor(C.WHITE)
    love.graphics.setFont(font_s)
    love.graphics.printf("<", prev_x, prev_y + math.floor(frameH/2) - 2*padding, prev_w, "center")
    love.graphics.printf(">", next_x, prev_y + math.floor(frameH/2) - 2*padding, prev_w, "center")

    love.graphics.setColor(C.BLOCK.BACK)
    love.graphics.rectangle("fill", card_x, card_y, card_w, card_h, 8, 8)
    local dx,dy,dw,dh = MainMenuUI.draw_deck_carousel_sprite(game, def, card_x + 4, card_y, 64, card_h, 0)

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
        def.unlocked and (def.description or "") or def.unlock_condition and def.unlock_condition.text or "Complete the unlock condition to play this deck.",
        infoX + 2*padding, infoY + 2*padding + offset, infoW - 4*padding, "center"
    )

    -- Stake Markers
    local space = 2
    local markerX = infoX + infoW + padding
    local markerY = card_y + padding
    local markerY2 = card_y + card_h - padding - space
    for i = 1,#stake_list do
        if game:is_stake_unlocked(def.id, stake_list[i] and stake_list[i].id) and game:is_deck_unlocked(def.id) then
            if game:is_stake_defeated(def.id, stake_list[i] and stake_list[i].id) then
                love.graphics.setColor(stake_list[i].colour or C.WHITE)
            else 
                local color = stake_list[i].colour or C.WHITE
                local factor = 0.8
                color = {color[1] * factor, color[2] * factor, color[3] * factor, 1}
                love.graphics.setColor(color)
            end
        else
            love.graphics.setColor(C.GREY)
        end
        local markerH = (math.floor((markerY2 - markerY - (#stake_list + 1) * space) / #stake_list + 1))
        love.graphics.rectangle("fill", markerX, markerY2 - math.floor(markerH/2) - space - (markerH + space) * (i - 1), 20, markerH, 4, 4)
        if stake_idx == i then
            love.graphics.setColor(C.WHITE)
            love.graphics.rectangle("line", markerX, markerY2 - math.floor(markerH/2) - space - (markerH + space) * (i - 1), 20, markerH, 2, 2)
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
    draw_rect_with_shadow(prev_x, prev_y, prev_w, stakeH, 4, 4, G.C.MULT, G.C.BLOCK.SHADOW, 2)
    draw_rect_with_shadow(next_x, prev_y, prev_w, stakeH, 4, 4, G.C.MULT, G.C.BLOCK.SHADOW, 2)
    love.graphics.setColor(C.WHITE)
    love.graphics.setFont(font_s)
    love.graphics.printf("<", prev_x, prev_y + math.floor(stakeH/2) - 2*padding, prev_w, "center")
    love.graphics.printf(">", next_x, prev_y + math.floor(stakeH/2) - 2*padding, prev_w, "center")

    -- Stake Infocard
    love.graphics.setColor(C.BLOCK.BACK)
    love.graphics.rectangle("fill", card_x, card_y, card_w, stakeH - 2*padding, 8, 8)
    local sx, sy, sw, sh = MainMenuUI.draw_stake_carousel_sprite(game, stake_def, card_x - 12, card_y, 64, stakeH - 2*padding, 0)

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
    love.graphics.printf("A/Y: Play  LEFT/RIGHT: Deck  UP/DOWN: Stake  B/X: Back", 0, H - 14, W, "center")
end

function MainMenuUI.handle_touch(game, x, y)
    if game._menu_sub_state == "deck_select" then
        return MainMenuUI._touch_deck_select(game, x, y)
    end
    if game._menu_sub_state == "how_to_play" then
        return MainMenuUI._touch_how_to_play(game, x, y)
    end
    if game._menu_sub_state == "collection_menu" then
        return CollectionUI.handle_touch_menu(game, x, y)
    end
    return MainMenuUI._touch_main(game, x, y)
end

function MainMenuUI._touch_main(game, x, y)
    local profile_rects = game._main_menu_profile_rects or {}
    for i, pr in ipairs(profile_rects) do
        if pr and game:_point_in_rect_simple(x, y, pr) then
            if game.switch_profile then
                game:switch_profile(i)
            end
            return true
        end
    end

    local del = game._main_menu_delete_save_rect
    if del and game:_point_in_rect_simple(x, y, del) then
        if game._delete_save_confirm then
            if game.delete_profile_progress then
                game:delete_profile_progress()
            end
        else
            game._delete_save_confirm = true
        end
        return true
    end
    -- Any other main-menu tap cancels delete confirm.
    game._delete_save_confirm = false

    local cr = game._main_menu_continue_rect
    if cr and game:_point_in_rect_simple(x, y, cr) then
        if game.continue_saved_run_from_main_menu then
            game:continue_saved_run_from_main_menu()
        end
        return true
    end

    local r = game._main_menu_start_rect
    if r and game:_point_in_rect_simple(x, y, r) then
        MainMenuUI.open_deck_select(game)
        return true
    end

    local hr = game._main_menu_how_to_play_rect
    if hr and game:_point_in_rect_simple(x, y, hr) then
        MainMenuUI.open_how_to_play(game)
        return true
    end

    local colr = game._main_menu_collection_rect
    if colr and game:_point_in_rect_simple(x, y, colr) then
        CollectionUI.open(game)
        return true
    end

    return false
end

function MainMenuUI._touch_how_to_play(game, x, y)
    local rects = game._how_to_play_rects or {}
    local page_count = #(MainMenuUI.HOW_TO_PLAY_PAGES or {})
    local page_idx = tonumber(game._how_to_play_page) or 1

    if rects.prev and page_idx > 1 and game:_point_in_rect_simple(x, y, rects.prev) then
        game._how_to_play_page = page_idx - 1
        return true
    end

    if rects.next and page_idx < page_count and game:_point_in_rect_simple(x, y, rects.next) then
        game._how_to_play_page = page_idx + 1
        return true
    end

    local back = game._how_to_play_back_rect
    if back and game:_point_in_rect_simple(x, y, back) then
        game._menu_sub_state = "main"
        return true
    end

    return false
end

function MainMenuUI._touch_deck_select(game, x, y)
    local deck_rects = game._deck_select_rects or {}
    local stake_rects = game._stake_select_rects or {}
    local deck_list = DECK_DEFS or {}
    local stake_list = STAKE_DEFS or {}
    local deck_idx = tonumber(game._deck_select_idx) or 1
    local stake_idx = tonumber(game._stake_select_idx) or 1

    if deck_rects.prev and game:_point_in_rect_simple(x, y, deck_rects.prev) then
        game._deck_select_idx = math.max(1, deck_idx - 1)
        return true
    end

    if deck_rects.next and game:_point_in_rect_simple(x, y, deck_rects.next) then
        game._deck_select_idx = math.min(#deck_list, deck_idx + 1)
        return true
    end

    if stake_rects.prev and game:_point_in_rect_simple(x, y, stake_rects.prev) then
        game._stake_select_idx = math.max(1, stake_idx - 1)
        return true
    end

    if stake_rects.next and game:_point_in_rect_simple(x, y, stake_rects.next) then
        game._stake_select_idx = math.min(#stake_list, stake_idx + 1)
        return true
    end

    if deck_rects.card and game:_point_in_rect_simple(x, y, deck_rects.card) then
        MainMenuUI._start_run(game)
        return true
    end

    return false
end

function MainMenuUI.handle_button(game, btn)
    MainMenuUI.try_konami_cheat(game, btn)
    if game._menu_sub_state == "deck_select" then
        MainMenuUI._button_deck_select(game, btn)
    elseif game._menu_sub_state == "how_to_play" then
        MainMenuUI._button_how_to_play(game, btn)
    elseif game._menu_sub_state == "collection_menu" or game._menu_sub_state == "collection_grid" then
        CollectionUI.handle_button(game, btn)
    else
        MainMenuUI._button_main(game, btn)
    end
end

function MainMenuUI._button_how_to_play(game, btn)
    local page_count = #(MainMenuUI.HOW_TO_PLAY_PAGES or {})
    local page_idx = tonumber(game._how_to_play_page) or 1

    if btn == "dpleft" or btn == "left" then
        if page_idx > 1 then
            game._how_to_play_page = page_idx - 1
        end
    elseif btn == "dpright" or btn == "right" then
        if page_idx < page_count then
            game._how_to_play_page = page_idx + 1
        end
    elseif game.is_menu_back and game:is_menu_back(btn) then
        game._menu_sub_state = "main"
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
    if game.is_role and game:is_role(btn, "use") then
        MainMenuUI.open_how_to_play(game)
    end
end

function MainMenuUI._button_deck_select(game, btn)
    local deck_list = DECK_DEFS or {}
    local stake_list = STAKE_DEFS or {}
    local deck_idx = tonumber(game._deck_select_idx) or 1
    local stake_idx = tonumber(game._stake_select_idx) or 1

    if btn == "dpleft" or btn == "left" then
        game._deck_select_idx = math.max(1, deck_idx - 1)
    elseif btn == "dpright" or btn == "right" then
        game._deck_select_idx = math.min(#deck_list, deck_idx + 1)
    elseif btn == "dpup" or btn == "up" then
        game._stake_select_idx = math.max(1, stake_idx + 1)
    elseif btn == "dpdown" or btn == "down" then
        game._stake_select_idx = math.min(#stake_list, stake_idx - 1)
    elseif game.is_menu_activate and game:is_menu_activate(btn) then
        MainMenuUI._start_run(game)
    elseif game.is_menu_back and game:is_menu_back(btn) then
        game._menu_sub_state = "main"
    end
end

return MainMenuUI
