--- Bottom-screen round win summary (ROUND_EVAL).

local RoundWinUI = {}

function RoundWinUI.draw_bottom(game)
    local panel_x, panel_y, panel_w, panel_h = 8, 8, 304, 124
    if _G.draw_rect_with_shadow then
        draw_rect_with_shadow(panel_x, panel_y, panel_w, panel_h, 4, 2, game.C.BLOCK.BACK, game.C.BLOCK.SHADOW, 2)
    else
        love.graphics.setColor(game.C.PANEL)
        love.graphics.rectangle("fill", panel_x, panel_y, panel_w, panel_h, 4, 4)
    end

    local blind_idx = tonumber(game.current_blind_index) or 1
    local blind_label = game:get_blind_display_name(blind_idx) or "Blind"
    local target = tonumber(game.current_blind_target) or 0
    local final_score = tonumber(game.round_score) or 0
    local reward = tonumber(game.current_blind_reward) or 0
    local hands_bonus = math.max(0, math.floor(tonumber(game._round_win_hands_bonus) or 0))
    local interest = math.max(0, math.floor(tonumber(game._round_win_interest) or 0))
    local total_payout = reward + hands_bonus + interest

    love.graphics.setColor(game.C.WHITE)
    love.graphics.setFont(game.FONTS.PIXEL.MEDIUM)
    love.graphics.print("Round won!", panel_x + 8, panel_y + 4)
    love.graphics.setFont(game.FONTS.PIXEL.SMALL)
    love.graphics.print(blind_label, panel_x + 8, panel_y + 22)

    love.graphics.setColor(game.C.GREY)
    love.graphics.print(string.format("Score %d / %d", final_score, target), panel_x + 8, panel_y + 38)

    love.graphics.setColor(game.C.MONEY)
    love.graphics.print(string.format("Blind reward: +$%d", reward), panel_x + 8, panel_y + 50)
    love.graphics.print(string.format("Hands left: %d (+$%d)", hands_bonus, hands_bonus), panel_x + 8, panel_y + 62)
    love.graphics.print(string.format("Interest: +$%d ($1 / $5, max $25)", interest), panel_x + 8, panel_y + 74)
    love.graphics.print(string.format("Total: +$%d", total_payout), panel_x + 8, panel_y + 86)

    game._round_win_continue_rect = { x = panel_x + panel_w - 84, y = panel_y + panel_h - 24, w = 74, h = 18 }
    love.graphics.setColor(game.C.ORANGE)
    love.graphics.rectangle("fill", game._round_win_continue_rect.x, game._round_win_continue_rect.y, game._round_win_continue_rect.w, game._round_win_continue_rect.h, 3, 3)
    love.graphics.setFont(game.FONTS.PIXEL.SMALL)
    love.graphics.setColor(game.C.WHITE)
    local cty = game._round_win_continue_rect.y + math.floor((game._round_win_continue_rect.h - love.graphics.getFont():getHeight()) * 0.5 + 0.5)
    love.graphics.printf("Continue", game._round_win_continue_rect.x, cty, game._round_win_continue_rect.w, "center")
end

function RoundWinUI.handle_touch(game, x, y)
    if not game._round_win_continue_rect then return false end
    if game:_point_in_rect_simple(x, y, game._round_win_continue_rect) then
        game:continue_from_round_win()
        return true
    end
    return false
end

return RoundWinUI
