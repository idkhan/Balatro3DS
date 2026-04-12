--- Bottom-screen round win summary (ROUND_EVAL).
--- `payout_lines` is a list of `{ label, amount, kind }` where `kind` is `"pending"` (blind/hands/interest)
--- or `"info"` (e.g. joker money already applied during `on_round_end`).

local RoundWinUI = {}

local function sum_payout_amounts(lines)
    local t = 0
    for _, row in ipairs(lines or {}) do
        t = t + math.max(0, math.floor(tonumber(row[2]) or 0))
    end
    return t
end

function RoundWinUI.draw_bottom(game, payout_lines)
    payout_lines = payout_lines or game._round_win_display_lines or {}
    local revealed = math.min(tonumber(game._round_win_lines_revealed) or 0, #payout_lines)
    local total_payout = sum_payout_amounts(payout_lines)

    local line_h = 12
    local header_block = 50
    local total_h = 14
    local btn_h = 26
    local panel_h = math.min(220, math.max(124, header_block + math.max(1, #payout_lines) * line_h + total_h + btn_h))
    local panel_x, panel_y, panel_w = 8, 8, 304

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

    love.graphics.setColor(game.C.WHITE)
    love.graphics.setFont(game.FONTS.PIXEL.MEDIUM)
    love.graphics.print("Round won!", panel_x + 8, panel_y + 4)
    love.graphics.setFont(game.FONTS.PIXEL.SMALL)
    love.graphics.print(blind_label, panel_x + 8, panel_y + 26)

    love.graphics.setColor(game.C.GREY)
    love.graphics.print(string.format("Score %d / %d", final_score, target), panel_x + 8, panel_y + 38)

    love.graphics.setColor(game.C.MONEY)
    local y = panel_y + header_block
    for i = 1, revealed do
        local row = payout_lines[i]
        local label = tostring(row[1] or "?")
        local amt = math.max(0, math.floor(tonumber(row[2]) or 0))
        love.graphics.print(string.format("%s: +$%d", label, amt), panel_x + 8, y)
        y = y + line_h
    end

    love.graphics.setColor(game.C.WHITE)
    love.graphics.print(string.format("Total: +$%d", total_payout), panel_x + 8, y + 2)

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
