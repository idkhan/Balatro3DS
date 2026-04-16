local MainMenuUI = {}

function MainMenuUI.draw_background(game, screen)
    local w = (screen == "bottom") and 320 or 400
    local h = 240
    local top = G.C.BOOSTER
    local bottom = G.C.CLEAR
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
end

function MainMenuUI.draw_top(game)
    local panel_x, panel_y, panel_w, panel_h = 24, 10, 352, 220
    
    local atlas = nil
    if game.ensure_asset_atlas_loaded then
        atlas = game:ensure_asset_atlas_loaded("balatro")
    end
    if atlas and atlas.image then
        local iw, ih = atlas.image:getDimensions()
        local max_w = panel_w - 24
        local max_h = 132
        local s = math.min(max_w / iw, max_h / ih)
        if s > 1 then s = 1 end
        local draw_w = iw * s
        local draw_h = ih * s
        local dx = panel_x + math.floor((panel_w - draw_w) * 0.5 + 0.5)
        local dy = panel_y + 16
        love.graphics.setColor(game.C.WHITE)
        love.graphics.draw(atlas.image, dx, dy, 0, s, s)
    end

    love.graphics.setColor(game.C.WHITE)
    love.graphics.setFont(game.FONTS.PIXEL.LARGE)
    love.graphics.printf("Balatro 3DS", panel_x, panel_y + 152, panel_w, "center")

    love.graphics.setFont(game.FONTS.PIXEL.MEDIUM)
    love.graphics.setColor(game.C.GREY)
    love.graphics.printf("Press A / Y", panel_x, panel_y + 184, panel_w, "center")

    if game.SEED then
        love.graphics.setFont(game.FONTS.PIXEL.SMALL)
        love.graphics.setColor(game.C.DARK_WHITE or game.C.GREY)
        love.graphics.printf("Seed " .. tostring(math.floor(tonumber(game.SEED) or 0)), panel_x, panel_y + 204, panel_w, "center")
    end
end

function MainMenuUI.draw_bottom(game)
    local panel_x, panel_y, panel_w, panel_h = 8, 12, 304, 168
    if _G.draw_rect_with_shadow then
        draw_rect_with_shadow(panel_x, panel_y, panel_w, panel_h, 6, 3, game.C.BLOCK.BACK, game.C.BLOCK.SHADOW, 3)
    else
        love.graphics.setColor(game.C.PANEL)
        love.graphics.rectangle("fill", panel_x, panel_y, panel_w, panel_h, 6, 6)
    end

    love.graphics.setColor(game.C.WHITE)
    love.graphics.setFont(game.FONTS.PIXEL.MEDIUM)
    love.graphics.printf("Main Menu", panel_x, panel_y + 16, panel_w, "center")

    local has_save = game.has_saved_run and game:has_saved_run() == true
    local btn_w, btn_h = 160, 32
    local btn_x = panel_x + math.floor((panel_w - btn_w) * 0.5 + 0.5)
    if has_save then
        game._main_menu_continue_rect = { x = btn_x, y = panel_y + 78, w = btn_w, h = btn_h }
        game._main_menu_start_rect = { x = btn_x, y = panel_y + 118, w = btn_w, h = btn_h }

        love.graphics.setColor(game.C.BLUE)
        love.graphics.rectangle("fill", game._main_menu_continue_rect.x, game._main_menu_continue_rect.y, game._main_menu_continue_rect.w, game._main_menu_continue_rect.h, 4, 4)
        love.graphics.setColor(game.C.GREEN)
        love.graphics.rectangle("fill", game._main_menu_start_rect.x, game._main_menu_start_rect.y, game._main_menu_start_rect.w, game._main_menu_start_rect.h, 4, 4)

        love.graphics.setColor(game.C.WHITE)
        love.graphics.setFont(game.FONTS.PIXEL.MEDIUM)
        local cy = game._main_menu_continue_rect.y + math.floor((game._main_menu_continue_rect.h - love.graphics.getFont():getHeight()) * 0.5 + 0.5)
        love.graphics.printf("Continue Run", game._main_menu_continue_rect.x, cy, game._main_menu_continue_rect.w, "center")
        local sy = game._main_menu_start_rect.y + math.floor((game._main_menu_start_rect.h - love.graphics.getFont():getHeight()) * 0.5 + 0.5)
        love.graphics.printf("Start Run", game._main_menu_start_rect.x, sy, game._main_menu_start_rect.w, "center")
    else
        game._main_menu_continue_rect = nil
        game._main_menu_start_rect = { x = btn_x, y = panel_y + 98, w = btn_w, h = btn_h }
        love.graphics.setColor(game.C.GREEN)
        love.graphics.rectangle("fill", game._main_menu_start_rect.x, game._main_menu_start_rect.y, game._main_menu_start_rect.w, game._main_menu_start_rect.h, 4, 4)

        love.graphics.setColor(game.C.WHITE)
        love.graphics.setFont(game.FONTS.PIXEL.MEDIUM)
        local by = game._main_menu_start_rect.y + math.floor((game._main_menu_start_rect.h - love.graphics.getFont():getHeight()) * 0.5 + 0.5)
        love.graphics.printf("Start Run", game._main_menu_start_rect.x, by, game._main_menu_start_rect.w, "center")
    end
end

function MainMenuUI.handle_touch(game, x, y)
    local cr = game._main_menu_continue_rect
    if cr and game:_point_in_rect_simple(x, y, cr) then
        if game.continue_saved_run_from_main_menu then
            game:continue_saved_run_from_main_menu()
        end
        return true
    end
    local r = game._main_menu_start_rect
    if not r then return false end
    if game:_point_in_rect_simple(x, y, r) then
        if game.start_new_run_from_main_menu then
            game:start_new_run_from_main_menu()
        elseif game.start_run_from_main_menu then
            game:start_run_from_main_menu()
        else
            game:initialize_run_loop()
        end
        return true
    end
    return false
end

return MainMenuUI