--- Bottom-screen Game Over summary when the blind is lost.

local GameOverUI = {}

function GameOverUI.draw_bottom(game)
    local blind_label = game._game_over_blind_label or "Blind"
    local final_score = tonumber(game._game_over_score) or tonumber(game.round_score) or 0
    local target = tonumber(game._game_over_target) or tonumber(game.current_blind_target) or 0
    local ante = tonumber(game._game_over_ante) or tonumber(game.ante) or 1
    local round_n = tonumber(game._game_over_round) or tonumber(game.round) or 1

    local panel_x, panel_y, panel_w = 8, 8, 304
    local panel_h = 132

    if _G.draw_rect_with_shadow then
        draw_rect_with_shadow(panel_x, panel_y, panel_w, panel_h, 4, 2, game.C.BLOCK.BACK, game.C.BLOCK.SHADOW, 2)
    else
        love.graphics.setColor(game.C.PANEL)
        love.graphics.rectangle("fill", panel_x, panel_y, panel_w, panel_h, 4, 4)
    end

    love.graphics.setColor(game.C.MULT or game.C.ORANGE)
    love.graphics.setFont(game.FONTS.PIXEL.MEDIUM)
    love.graphics.print("Game Over", panel_x + 8, panel_y + 6)

    love.graphics.setColor(game.C.WHITE)
    love.graphics.setFont(game.FONTS.PIXEL.SMALL)
    love.graphics.print(blind_label, panel_x + 8, panel_y + 30)

    love.graphics.setColor(game.C.GREY)
    love.graphics.print(string.format("Score %d / %d", final_score, target), panel_x + 8, panel_y + 44)
    love.graphics.print(string.format("Ante %d  ·  Round %d", ante, round_n), panel_x + 8, panel_y + 58)

    love.graphics.setColor(game.C.WHITE)
    love.graphics.printf("You ran out of hands before beating this blind.", panel_x + 8, panel_y + 78, panel_w - 16, "left")

    game._game_over_continue_rect = { x = panel_x + panel_w - 84, y = panel_y + panel_h - 26, w = 74, h = 18 }
    love.graphics.setColor(game.C.ORANGE)
    love.graphics.rectangle("fill", game._game_over_continue_rect.x, game._game_over_continue_rect.y, game._game_over_continue_rect.w, game._game_over_continue_rect.h, 3, 3)
    love.graphics.setFont(game.FONTS.PIXEL.SMALL)
    love.graphics.setColor(game.C.WHITE)
    local cty = game._game_over_continue_rect.y + math.floor((game._game_over_continue_rect.h - love.graphics.getFont():getHeight()) * 0.5 + 0.5)
    love.graphics.printf("Continue", game._game_over_continue_rect.x, cty, game._game_over_continue_rect.w, "center")
end

function GameOverUI.handle_touch(game, x, y)
    if not game._game_over_continue_rect then return false end
    if game:_point_in_rect_simple(x, y, game._game_over_continue_rect) then
        if game.continue_from_game_over then
            game:continue_from_game_over()
        end
        return true
    end
    return false
end

return GameOverUI
