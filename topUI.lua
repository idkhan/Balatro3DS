--- Top-screen UI: draw content for the 3DS top screen (or equivalent when screen ~= "bottom").
TopUI = {}

--- Draw a rounded rectangle and return the inner area (with padding) for placing content.
--- @param x number Left edge
--- @param y number Top edge
--- @param w number Width
--- @param h number Height
--- @param radius number Corner radius (rx and ry)
--- @param padding number|nil Inset from all sides for content (default 0)
--- @param mode "fill"|"line"|nil Draw mode (default "fill")
--- @return number inner_x, number inner_y, number inner_w, number inner_h Content bounds inside the rect
function draw_rounded_rect(x, y, w, h, radius, padding, mode)
    padding = padding or 0
    mode = mode or "fill"
    if(mode == "line" and padding ~= 0) then
        love.graphics.setLineWidth(padding)
    end
    radius = math.min(radius or 0, w / 2, h / 2)
    if radius < 0 then radius = 0 end
    love.graphics.rectangle(mode, x, y, w, h, radius, radius)
    local pad = padding
    love.graphics.setLineWidth(1)
    return x + pad, y + pad, w - (2 * pad), h - (2 * pad)
end

function draw_rect_with_shadow(x, y, w, h, radius, padding, color, shadowColor, shadowSize)
    love.graphics.setColor(shadowColor)
    draw_rounded_rect(x, y + shadowSize, w, h, radius, padding, "fill")
    love.graphics.setColor(color)
    return draw_rounded_rect(x, y, w, h, radius, padding, "fill")
end

function TopUI.draw()
    local panelHeight = 104
    local panelY = 4
    local is_blind_select = (G.STATE == G.STATES.BLIND_SELECT)
    local blind_def = nil
    if G and G.get_blind_def then
        if G.STATE == G.STATES.SELECTING_HAND then
            blind_def = G:get_blind_def(G.current_blind_index or 1)
        else
            blind_def = G:get_preview_blind()
        end
    end
    local blind_index = G.selected_blind_index or G.current_blind_index or 1
    if G.STATE == G.STATES.SELECTING_HAND or G.STATE == G.STATES.ROUND_EVAL or G.STATE == G.STATES.GAME_OVER then
        blind_index = G.current_blind_index or blind_index
    end
    local blind_name = (G.get_blind_display_name and G:get_blind_display_name(blind_index)) or ((blind_def and blind_def.name) or (G.current_blind_name or "Blind"))
    
    local blind_target = tonumber(G.current_blind_target) or 0
    if G.STATE == G.STATES.BLIND_SELECT and G.get_blind_target then
        blind_target = G:get_blind_target(G.selected_blind_index or G.current_blind_index or 1, G.ante)
    end
    local blind_reward = tonumber(G.current_blind_reward) or 0
    if G.STATE == G.STATES.BLIND_SELECT and blind_def then
        blind_reward = tonumber(blind_def.reward) or blind_reward
        if blind_def.id == "boss" and G.get_boss_blind_prototype then
            local proto = G:get_boss_blind_prototype()
            blind_reward = tonumber(proto and proto.dollars) or blind_reward
        end
    end
    local blind_key = (blind_def and blind_def.key) or "Big"
    local blind_color = G.C.BLIND_COLORS.Big
    if not is_blind_select then
        blind_color = (G.get_blind_color and G:get_blind_color(blind_index)) or G.C.BLIND_COLORS.Big
    end
    local blind_dark = is_blind_select and G.C.BLIND_COLORS.BigDark
        or (G.C.BLIND_COLORS[blind_key .. "Dark"] or G.C.BLIND_COLORS.BigDark)
    local blind_sign = blind_dark

    -- Panel
    love.graphics.setColor(G.C.PANEL)
    love.graphics.rectangle("fill", 0, panelY, 400, panelHeight)

    love.graphics.setColor(G.C.BLIND_COLORS.Big)
    love.graphics.rectangle("line", 0, panelY, 401, panelHeight)

    -- Title
    local titlePosX = 2
    local titlePosY = 5 + panelY
    local titleHeight = 90
    local titleWidth = 120
    love.graphics.setColor(G.C.BLOCK.SHADOW)
    local ix, iy, iw, ih = draw_rect_with_shadow(titlePosX, titlePosY, titleWidth, titleHeight , 4, 2, G.C.BLOCK.BACK, G.C.BLOCK.SHADOW, 2)

    -- Blind
    local blindPosX, blindPosY = ix, iy
    local blindWidth, blindHeight = iw, math.floor((ih/4) - 1)
    
    love.graphics.setColor(G.C.WHITE)
    love.graphics.setFont(G.FONTS.PIXEL.MEDIUM)
    
    
    if is_blind_select then
        TopUI.center_text("Choose blind", ix, iy -2, iw, ih)

    elseif G.STATE == G.STATES.ROUND_EVAL then
        love.graphics.setColor(G.C.WHITE)
        love.graphics.setFont(G.FONTS.PIXEL.MEDIUM)
        TopUI.center_text("Round won!", ix, iy - 6, iw, math.floor(ih * 0.55))
        local bi = G.current_blind_index or 1
        G:draw_blind_chip_anim(bi, ix + math.floor(iw / 2), iy + math.floor(ih * 0.72), 1.05)

    elseif G.STATE == G.STATES.GAME_OVER then
        love.graphics.setColor(G.C.MULT or G.C.WHITE)
        love.graphics.setFont(G.FONTS.PIXEL.MEDIUM)
        TopUI.center_text("Game Over", ix, iy - 6, iw, math.floor(ih * 0.55))
        local bi = G.current_blind_index or 1
        G:draw_blind_chip_anim(bi, ix + math.floor(iw / 2), iy + math.floor(ih * 0.72), 0.9)

    elseif G.STATE == G.STATES.SHOP then
        local cell_w = 113
        local cell_h = 60
        if G.ANIMATION_ATLAS and G.ANIMATION_ATLAS.shop_sign then
            local a = G.ANIMATION_ATLAS.shop_sign
            cell_w = tonumber(a.px) or cell_w
            cell_h = tonumber(a.py) or cell_h
        end
        local s = math.min(iw / cell_w, ih / cell_h) * 0.92
        if s > 1.25 then s = 1.25 end
        G:draw_shop_sign_anim(ix + math.floor(iw / 2), iy + math.floor(ih / 2), s)

    elseif G.STATE == G.STATES.OPEN_BOOSTER then
        love.graphics.setColor(G.C.WHITE)
        love.graphics.setFont(G.FONTS.PIXEL.MEDIUM)
        local sess = G.booster_session
        local t1 = (sess and sess.title) or "Booster Pack"
        TopUI.center_text(t1, ix, iy - 4, iw, math.floor(ih * 0.45))
        love.graphics.setFont(G.FONTS.PIXEL.MEDIUM)
        local pr = sess and tonumber(sess.picks_remaining) or 0
        TopUI.center_text("Picks left: " .. tostring(pr), ix, iy + math.floor(ih * 0.6), iw, math.floor(ih * 0.35))

    else
        -- Score Requirements Box
        ix, iy, iw, ih = draw_rect_with_shadow(blindPosX, blindPosY, blindWidth, blindHeight, 4, 4, blind_color, blind_dark, 2)
        love.graphics.setColor(G.C.WHITE)
        TopUI.center_text(blind_name, ix, iy -2, iw, ih)
        
        love.graphics.setColor(blind_sign)
        ix, iy, iw, ih = draw_rounded_rect(blindPosX, blindPosY + blindHeight + 4, blindWidth, blindHeight * 3, 4, 4, "fill")
        local score_box_ix, score_box_iy, score_box_iw, score_box_ih = ix, iy, iw, ih

        
        ix, iy, iw, ih = draw_rect_with_shadow(score_box_ix + math.floor(score_box_iw/3), score_box_iy - 1, 72, score_box_ih, 4, 4, G.C.BLOCK.BACK, G.C.BLOCK.SHADOW, 2)

        G:draw_blind_chip_anim(
            blind_index,
            score_box_ix + math.floor(score_box_iw / 6) - 2,
            score_box_iy + math.floor(score_box_ih / 2),
            1.1
        )
        
        love.graphics.setColor(G.C.WHITE)
        love.graphics.setFont(G.FONTS.PIXEL.SMALL)
        love.graphics.print("Score at least", ix, iy - 2)

        love.graphics.setColor(G.C.RED)
        love.graphics.setFont(G.FONTS.PIXEL.MEDIUM)
        local scoreReq = tostring(math.floor(blind_target))
        local scoreReqY = iy + math.floor(G.FONTS.PIXEL.SMALL_HEIGHT/2) + 5
        love.graphics.printf(scoreReq, ix, scoreReqY, iw, "center")

        love.graphics.setColor(G.C.WHITE)
        love.graphics.setFont(G.FONTS.PIXEL.SMALL)
        local rewardText = "Reward: "
        local rewardY = iy + math.floor(G.FONTS.PIXEL.SMALL_HEIGHT/2) + 6 + G.FONTS.PIXEL.MEDIUM_HEIGHT
        love.graphics.print(rewardText, ix, rewardY)
        love.graphics.setColor(G.C.MONEY)
        local moneyText = "$"..string.rep("$", blind_reward).."+"
        local rewardLabelW = love.graphics.getFont():getWidth(rewardText)
        love.graphics.print(moneyText, ix + rewardLabelW, rewardY)
    end

    -- Round Score, Chips and Mult
    love.graphics.setColor(G.C.BLOCK.SHADOW)
    local width = 64
    ix, iy, iw, ih = draw_rounded_rect(titlePosX + (width * 2) - 4, titlePosY, titleWidth, math.floor(titleHeight/3.5), 4, 4, "fill")
    
    love.graphics.setFont(G.FONTS.PIXEL.SMALL)
    love.graphics.setColor(G.C.WHITE)
    love.graphics.print("Round", ix, iy - 3)
    love.graphics.print("Score", ix, iy + 7)

    love.graphics.setColor(G.C.PANEL)
    local paneOffset = 30
    ix, iy, iw, ih = draw_rounded_rect(ix + paneOffset, iy, iw - paneOffset, ih, 2, 2, "fill")

    local score = tostring(G.round_score or 0)
    love.graphics.setFont(G.FONTS.PIXEL.MEDIUM)
    love.graphics.setColor(G.C.WHITE)
    TopUI.center_text(score, ix, iy -1, iw, ih)


    love.graphics.setColor(G.C.BLOCK.SHADOW)
    ix, iy, iw, ih = draw_rounded_rect(titlePosX + (width * 2) - 4, titlePosY + math.floor(titleHeight/3.5) + 4, titleWidth, titleHeight - math.floor(titleHeight/3.5) - 3, 4, 4, "fill")

    love.graphics.setColor(G.C.WHITE)
    love.graphics.setFont(G.FONTS.PIXEL.MEDIUM)
    local handSelected = ""
    local handHidden = (G.selectedHandHidden == true)
    if G.selectedHand and G.selectedHand ~= -1 then
        handSelected = G.handlist[G.selectedHand]
    end
    if handHidden then
        handSelected = "???"
    end
    if(love.graphics.getFont():getWidth(handSelected) > (iw - 20)) then
        love.graphics.setFont(G.FONTS.PIXEL.SMALL)
    end
    local _, posY = TopUI.center_text(handSelected, ix, iy -2, iw -20, math.floor(ih/3))
    posY = posY + math.floor(G.FONTS.PIXEL.MEDIUM_HEIGHT/6)
    love.graphics.setFont(G.FONTS.PIXEL.SMALL)
    local handLevel = G.selectedHandLevel or 1
    if(handSelected ~= "" and not handHidden) then
        love.graphics.printf("lvl." .. handLevel, ix, posY, iw, "right")
    elseif handSelected ~= "" then
        love.graphics.printf("lvl.?", ix, posY, iw, "right")
    end

    -- X
    love.graphics.setColor(G.C.RED)
    love.graphics.setFont(G.FONTS.PIXEL.MEDIUM)
    TopUI.center_text("X", ix, iy + math.floor(ih/5), iw, ih)
    -- Chip
    local ChipX = ix
    local ChipY = iy + ih/3 + 6
    local ChipWidth = iw/2 - 8
    local ChipHeight = ih/2 + 2
    local totalW = iw
    draw_rect_with_shadow(ChipX, ChipY, ChipWidth, ChipHeight, 4, 2, G.C.CHIPS, G.C.CHIPS_DARK, 2)

    --Mult
    draw_rect_with_shadow(ChipX + totalW - ChipWidth, ChipY, ChipWidth, ChipHeight, 4, 2, G.C.MULT, G.C.MULT_DARK, 2)

    local handChips = tostring(G.selectedHandChips or 0)
    local rawMult = tonumber(G.selectedHandMult) or 0
    local handMult
    if math.abs(rawMult) >= 100000 then
        handMult = string.format("%.1e", rawMult)
    elseif rawMult % 1 == 0 then
        handMult = string.format("%.0f", rawMult)
    else
        handMult = string.format("%.1f", rawMult)
    end
    love.graphics.setFont(G.FONTS.PIXEL.MEDIUM)
    love.graphics.setColor(G.C.WHITE)
    TopUI.center_text(handChips, ChipX, ChipY - 1, ChipWidth, ChipHeight)
    TopUI.center_text(handMult, ChipX + totalW - ChipWidth, ChipY - 1, ChipWidth, ChipHeight)
    
    -- Hands, Discards, Money, Ante and Round
    local fieldsPositionX = titlePosX + (titleWidth + 4) * 2
    local fieldsPositionY = titlePosY
    local fieldWidth = 46
    local fieldHeight = 43
    local padding = 4
    TopUI.LabeledField("Hands", G.hands, fieldsPositionX, fieldsPositionY, fieldWidth, fieldHeight, G.C.BLUE)
    TopUI.LabeledField("Discards", G.discards, fieldsPositionX + fieldWidth + padding, fieldsPositionY, fieldWidth, fieldHeight, G.C.RED)
    TopUI.LabeledField("Ante", G.ante, fieldsPositionX + (fieldWidth + padding) * 2, fieldsPositionY, fieldWidth, fieldHeight, G.C.ORANGE)
    TopUI.LabeledField("Round", G.round, fieldsPositionX + (fieldWidth + padding) * 2, fieldsPositionY + fieldHeight + padding, fieldWidth, fieldHeight, G.C.RED)
    TopUI.LabeledField("", tostring(G.money), fieldsPositionX, fieldsPositionY + fieldHeight + padding, fieldWidth * 2 + padding, fieldHeight, G.C.MONEY)

    -- Joker panel behind owned jokers only (top screen); width matches fanned row from `Game`.
    local n = G and G.jokers and #G.jokers or 0
    local slot_w, slot_h = G.joker_slot_w or 71, G.joker_slot_h or 95
    local slot_gap = G.joker_slot_gap or 8
    local slot_y = G.joker_slot_y_top or (panelY + panelHeight + 6)
    local total_w = tonumber(G.joker_row_span_top)
        or select(2, G:_compute_fanned_joker_row(n, 400, slot_w, slot_gap, 8))
    local start_x = G.joker_slot_start_x or math.floor((400 - total_w) * 0.5 + 0.5)

    -- Extra padding so jokers don't touch the panel edges.
    local panel_pad = 4
    total_w = total_w + (panel_pad * 2)
    start_x = start_x - panel_pad
    slot_y = slot_y - panel_pad
    slot_h = slot_h + (panel_pad * 2)

    -- Dark panel background.
    if #G.jokers > 0 then
        if _G.draw_rect_with_shadow then
            draw_rect_with_shadow(
                start_x,
                slot_y,
                total_w,
                slot_h,
                4,
                2,
                G and G.C and G.C.BLOCK and G.C.BLOCK.BACK or { 0, 0, 0, 1 },
                G and G.C and G.C.BLOCK and G.C.BLOCK.SHADOW or { 0, 0, 0, 1 },
                2
            )
        else
            love.graphics.setColor(G and G.C and G.C.PANEL or { 0.2, 0.2, 0.2, 1 })
            love.graphics.rectangle("fill", start_x, slot_y, total_w, slot_h, 4, 4)
        end
    end
    if G and G.jokers_on_bottom ~= true and n > 0 then

        love.graphics.setFont(G.FONTS.PIXEL.MEDIUM)
        love.graphics.setColor(G.C.WHITE)

        -- Jokers are normally invisible on top; force visibility while drawing this row.
        for _, joker in ipairs(G.jokers) do
            if joker and joker.draw then
                local prev_visible = joker.states and joker.states.visible
                if joker.states then joker.states.visible = true end
                joker:draw()
                if joker.states then joker.states.visible = prev_visible end
            end
        end
    end

end

function TopUI.LabeledField(string, value, x, y, iw, ih, fieldColor)
    love.graphics.setColor(G.C.BLOCK.SHADOW)
    local ix, iy, iw, ih = draw_rounded_rect(x, y, iw, ih, 4, 4,"fill")
    
    if(string ~= "") then
        love.graphics.setColor(G.C.WHITE)
        love.graphics.setFont(G.FONTS.PIXEL.SMALL)
        TopUI.center_text(string, ix, iy, iw, math.floor(ih/4))
    end

    love.graphics.setColor(G.C.PANEL)
    if(string ~= "") then
        ix, iy, iw, ih = draw_rounded_rect(ix, iy + ih/4 + 4, iw, math.floor(ih/4 * 3) - 4, 4, 4,"fill")
    else
        ix, iy, iw, ih = draw_rounded_rect(ix, iy, iw, ih, 4, 4,"fill")
    end

    love.graphics.setFont(G.FONTS.PIXEL.MEDIUM)
    love.graphics.setColor(fieldColor)
    TopUI.center_text(value, ix, iy - 1, iw, ih)

end

function TopUI.center_text(string, x, y, iw, ih)
    local s = tostring(string or "")
    local font = love.graphics.getFont()
    local yval = y + math.floor(ih/2) - math.floor(font:getHeight()/2)
    love.graphics.printf(s, x, yval, iw, "center")
    local xval = x
    return xval, yval
end