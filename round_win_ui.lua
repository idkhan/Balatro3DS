--- Bottom-screen round win summary (ROUND_EVAL): the Cash Out panel.
--- `payout_lines` is the reveal order used by `Game:_reveal_one_round_win_line`. Row shape:
--- `{ label, amount, kind, badge = string|nil, badge_color = table|nil, slot = "blind"|nil }`
--- `kind` is `"pending"` (credited together when Cash Out is confirmed). The `slot = "blind"`
--- row is the blind requirement header, not a list row.

local Particles = require("particles")
local DynaText = require("dyna_text")
local NumberFormat = require("number_format")

local RoundWinUI = {}

local PANEL_X, PANEL_Y, PANEL_W = 6, 6, 308
local PANEL_PAD = 7
local PANEL_MIN_H = 150
local PANEL_MAX_H = 228

local BTN_H = 32
local BTN_INSET = 10
local BLIND_H = 34
local DIVIDER_H = 8
local ROW_H = 15
local ROW_H_TIGHT = 13

-- Payouts read as repeated '$'. Past `MONEY_PER_LINE` they wrap, and each extra line steps the
-- glyph down a size so a big payout stays a block instead of a wall. Past `MONEY_MAX_LINES`
-- (an amount no vanilla effect reaches) it degrades to "$42".
local MONEY_PER_LINE = 15
local MONEY_MAX_LINES = 3
local MONEY_COL_W = 104
local CASH_CONFETTI_COLOUR = { 1, 0.84, 0.24, 1 }
local CASH_CONFETTI_SPEC = {
    shape = "rect",
    colour = CASH_CONFETTI_COLOUR,
    fade = true,
    gravity = 42,
    lifetime = 1.15,
    w = 2,
    h = 3,
}
local CASH_CONFETTI_COUNT = 20

local function visual_random()
    if love.math and love.math.random then return love.math.random() end
    return math.random()
end

--- Start the short payout burst once all cash-out rows are visible. The reference
--- cash-out celebrates with money particles (`reference/Balatro/functions/button_callbacks.lua:2945`);
--- these primitives keep the equivalent feedback within the 3DS fill-rate budget.
function RoundWinUI.emit_cash_out_confetti(game)
    for _ = 1, CASH_CONFETTI_COUNT do
        CASH_CONFETTI_SPEC.x = 154 + (visual_random() - 0.5) * 70
        CASH_CONFETTI_SPEC.y = 33 + visual_random() * 10
        CASH_CONFETTI_SPEC.vx = (visual_random() - 0.5) * 75
        CASH_CONFETTI_SPEC.vy = -18 - visual_random() * 42
        CASH_CONFETTI_SPEC.w = 1 + math.floor(visual_random() * 3)
        CASH_CONFETTI_SPEC.h = 2 + math.floor(visual_random() * 3)
        Particles.emit(CASH_CONFETTI_SPEC)
    end
end

-- Boss defeat burst in the reference's black/red (`reference/Balatro/blind.lua:282`),
-- centred on the panel's blind chip. Fired once when the round-eval panel lands.
local BOSS_BURST_COLOURS = {
    { 0.15, 0.12, 0.12, 1 },
    { 0.99, 0.27, 0.27, 1 },
}
local BOSS_BURST_SPEC = { shape = "rect", fade = true, gravity = 55, lifetime = 0.9 }
local BOSS_BURST_COUNT = 26

function RoundWinUI.emit_boss_defeat_burst(game)
    -- Matches the chip position in draw_bottom: inner_x + 15, mid of the blind band.
    local cx, cy = 28, 68
    for i = 1, BOSS_BURST_COUNT do
        BOSS_BURST_SPEC.colour = BOSS_BURST_COLOURS[(i % 2) + 1]
        BOSS_BURST_SPEC.x = cx + (visual_random() - 0.5) * 12
        BOSS_BURST_SPEC.y = cy + (visual_random() - 0.5) * 12
        BOSS_BURST_SPEC.vx = (visual_random() - 0.5) * 160
        BOSS_BURST_SPEC.vy = -20 - visual_random() * 80
        BOSS_BURST_SPEC.w = 1 + math.floor(visual_random() * 3)
        BOSS_BURST_SPEC.h = 1 + math.floor(visual_random() * 3)
        Particles.emit(BOSS_BURST_SPEC)
    end
end

local function money_steps(game, base_font)
    local P = game.FONTS.PIXEL
    return { base_font or P.SMALL, P.TINY, P.MICRO }
end

--- @return string[] lines, love.Font font
local function money_layout(game, amount, base_font, tight)
    local n = math.max(1, math.floor(tonumber(amount) or 0))
    local steps = money_steps(game, base_font)
    local line_count = math.ceil(n / MONEY_PER_LINE)
    if line_count > MONEY_MAX_LINES then
        return { "$" .. n }, steps[1]
    end

    local step = line_count
    local row_h = tight and ROW_H_TIGHT or ROW_H
    if tight then
        while step < #steps and (line_count * steps[step]:getHeight()) > row_h do
            step = step + 1
        end
    end
    local widest = string.rep("$", math.min(n, MONEY_PER_LINE))
    while step < #steps and steps[step]:getWidth(widest) > MONEY_COL_W do
        step = step + 1
    end

    local lines = {}
    local left = n
    while left > 0 do
        local take = math.min(left, MONEY_PER_LINE)
        lines[#lines + 1] = string.rep("$", take)
        left = left - take
    end
    return lines, steps[step]
end

local function money_height(game, amount, base_font, tight)
    local lines, font = money_layout(game, amount, base_font, tight)
    return #lines * font:getHeight()
end

--- Right-aligned at `right_x`, vertically centred in [y, y + h].
local function draw_money(game, right_x, y, h, amount, base_font, tight)
    local lines, font = money_layout(game, amount, base_font, tight)
    local line_h = font:getHeight()
    local ty = y + math.floor((h - #lines * line_h) * 0.5 + 0.5)
    love.graphics.setFont(font)
    love.graphics.setColor(game.C.MONEY)
    for _, s in ipairs(lines) do
        love.graphics.print(s, right_x - font:getWidth(s), ty)
        ty = ty + line_h
    end
end

local function is_blind_row(row)
    return row and row.slot == "blind"
end

local function sum_payout_amounts(lines)
    local t = 0
    for _, row in ipairs(lines or {}) do
        t = t + math.max(0, math.floor(tonumber(row[2]) or 0))
    end
    return t
end

--- Payout rows in draw order (everything but the blind header), paired with the reveal index
--- that brings each one in.
local function list_rows(lines)
    local rows = {}
    for i, row in ipairs(lines or {}) do
        if not is_blind_row(row) then
            rows[#rows + 1] = { row = row, reveal_index = i }
        end
    end
    return rows
end

function RoundWinUI.draw_bottom(game, payout_lines)
    -- Entrance slide, shared with the other scene panels (input is suppressed mid-slide).
    love.graphics.push()
    if game.get_round_eval_slide_dy then
        love.graphics.translate(0, game:get_round_eval_slide_dy())
    end
    payout_lines = payout_lines or game._round_win_display_lines or {}
    local revealed = math.min(tonumber(game._round_win_lines_revealed) or 0, #payout_lines)
    local P = game.FONTS.PIXEL
    Particles.update(game.real_dt or 0)
    if revealed == #payout_lines and #payout_lines > 0 and not game._round_win_row_tick
        and game._round_win_confetti_lines ~= payout_lines then
        game._round_win_confetti_lines = payout_lines
        RoundWinUI.emit_cash_out_confetti(game)
    end

    local blind_row = nil
    for _, row in ipairs(payout_lines) do
        if is_blind_row(row) then
            blind_row = row
            break
        end
    end
    local rows = list_rows(payout_lines)

    -- Size for the finished list so the panel doesn't jitter as rows reveal.
    local chrome = PANEL_PAD + BTN_H + 6 + BLIND_H + DIVIDER_H + PANEL_PAD
    local function measure_rows(tight)
        local heights, total = {}, 0
        local base = tight and ROW_H_TIGHT or ROW_H
        for i, entry in ipairs(rows) do
            local h = math.max(base, money_height(game, entry.row[2], P.SMALL, tight) + 3)
            heights[i] = h
            total = total + h
        end
        return heights, total
    end

    local tight = false
    local row_heights, rows_h = measure_rows(false)
    local panel_h = math.max(PANEL_MIN_H, math.min(PANEL_MAX_H, chrome + rows_h))
    if chrome + rows_h > panel_h then
        tight = true
        row_heights, rows_h = measure_rows(true)
    end

    if _G.draw_rect_with_shadow then
        draw_rect_with_shadow(PANEL_X, PANEL_Y, PANEL_W, panel_h, 5, 2, game.C.BLOCK.BACK, game.C.BLOCK.SHADOW, 2)
    else
        love.graphics.setColor(game.C.BLOCK.BACK)
        love.graphics.rectangle("fill", PANEL_X, PANEL_Y, PANEL_W, panel_h, 5, 5)
    end

    local inner_x = PANEL_X + PANEL_PAD
    local inner_w = PANEL_W - PANEL_PAD * 2
    local right_x = inner_x + inner_w
    local y = PANEL_Y + PANEL_PAD

    -- Cash Out button
    local btn = {
        x = PANEL_X + BTN_INSET,
        y = y,
        w = PANEL_W - BTN_INSET * 2,
        h = BTN_H,
    }
    game._round_win_continue_rect = btn
    if _G.draw_rect_with_shadow then
        draw_button_with_shadow(btn.x, btn.y, btn.w, btn.h, 5, 2, game.C.ORANGE, game.C.BLOCK.SHADOW, 2)
    else
        love.graphics.setColor(game.C.ORANGE)
        love.graphics.rectangle("fill", btn.x, btn.y, btn.w, btn.h, 5, 5)
    end
    love.graphics.setFont(P.BUTTON_PRICE)
    love.graphics.setColor(game.C.WHITE)
    local btn_label = string.format("Cash Out: $%d", sum_payout_amounts(payout_lines))
    love.graphics.printf(btn_label, btn.x,
        btn.y + math.floor((btn.h - P.BUTTON_PRICE:getHeight()) * 0.5 + 0.5), btn.w, "center")
    y = y + BTN_H + 6

    -- Blind requirement + its reward
    game:draw_blind_chip_anim(tonumber(game.current_blind_index) or 1,
        inner_x + 15, y + math.floor(BLIND_H * 0.5), 0.82)
    local text_x = inner_x + 34
    love.graphics.setFont(P.SMALL)
    love.graphics.setColor(game.C.WHITE)
    love.graphics.print("Score at least", text_x, y + 3)
    love.graphics.setFont(P.MEDIUM)
    love.graphics.setColor(game.C.RED)
    love.graphics.print(NumberFormat.format(math.floor(tonumber(game.current_blind_target) or 0)), text_x, y + 15)
    if blind_row and revealed >= 1 then
        -- The header has its own 34px band, so it never takes the squeezed row treatment.
        local blind_reveal_index
        for ri, row in ipairs(payout_lines) do
            if row == blind_row then blind_reveal_index = ri break end
        end
        local shown = game:round_win_row_display_amount(blind_reveal_index, blind_row)
        if shown >= 1 then
            draw_money(game, right_x, y, BLIND_H, shown, P.PRICE, false)
        end
    end
    y = y + BLIND_H + 3

    -- Dotted rule
    love.graphics.setColor(game.C.WHITE)
    for dx = 0, inner_w - 2, 6 do
        love.graphics.rectangle("fill", inner_x + dx, y, 2, 2)
    end
    y = y + 5

    -- Everything else that paid out
    love.graphics.setFont(P.SMALL)
    for i, entry in ipairs(rows) do
        if entry.reveal_index > revealed then break end
        local row = entry.row
        local h = row_heights[i]
        local ty = y + math.floor((h - P.SMALL:getHeight()) * 0.5 + 0.5)
        local label_x = inner_x
        if row.badge then
            love.graphics.setFont(P.SMALL)
            love.graphics.setColor(row.badge_color or game.C.WHITE)
            love.graphics.print(row.badge, label_x, ty)
            label_x = label_x + P.SMALL:getWidth(row.badge) + 5
        end
        love.graphics.setFont(P.SMALL)
        love.graphics.setColor(game.C.WHITE)
        local label = tostring(row[1] or "?")
        local dyna = game._round_win_row_dyna and game._round_win_row_dyna[entry.reveal_index]
        if dyna then
            -- Left-aligned, so the width argument is unused.
            DynaText.draw(dyna, label, label_x, ty, 0, "left")
        else
            love.graphics.print(label, label_x, ty)
        end
        -- Rows count up one $ at a time while their tick runs (`common_events.lua:1043-1062`).
        local shown = game:round_win_row_display_amount(entry.reveal_index, row)
        if shown >= 1 then
            draw_money(game, right_x, y, h, shown, P.SMALL, tight)
        end
        y = y + h
    end
    Particles.draw()
    love.graphics.pop()
end

function RoundWinUI.handle_touch(game, x, y)
    if not game._round_win_continue_rect then return false end
    if game:_point_in_rect_simple(x, y, game._round_win_continue_rect) then
        -- continue_from_round_win plays the cash-out cue for both the touch and the
        -- gamepad path, so the press must not add a second `button` here.
        game:continue_from_round_win()
        return true
    end
    return false
end

return RoundWinUI
