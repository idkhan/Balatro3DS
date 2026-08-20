---@class TopUI
TopUI = Object:extend()

sysDepth = 0
buttonHeight = 1
textHeight = 2
signHeight = 3
jokerHeight = 2
PopupHeight = 4

--- Top-screen UI: draw content for the 3DS top screen (or equivalent when screen ~= "bottom").

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

function draw_rect_with_shadow(x, y, w, h, radius, padding, color, shadowColor, shadowSize, offset)
    local ox = tonumber(offset) or 0
    local rx = x - ox
    love.graphics.setColor(shadowColor)
    draw_rounded_rect(rx, y + shadowSize, w, h, radius, padding, "fill")
    love.graphics.setColor(color)
    return draw_rounded_rect(rx, y, w, h, radius, padding, "fill")
end

function TopUI:draw(screen)
    sysDepth = -love.graphics.getDepth()
    if screen == "right" then
        sysDepth = -sysDepth
    end
    local depthOffset = sysDepth * buttonHeight
    local jokerDepthOffset = sysDepth * jokerHeight
    local popupDepthOffset = sysDepth * PopupHeight
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
    local factor = 0.5
    local blind_dark = {blind_color[1] * factor, blind_color[2] * factor, blind_color[3] * factor, blind_color[4]}
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
    local ix, iy, iw, ih = draw_rect_with_shadow(titlePosX, titlePosY, titleWidth, titleHeight , 4, 2, G.C.BLOCK.BACK, G.C.BLOCK.SHADOW, 2, depthOffset)

    -- Blind
    local blindPosX, blindPosY = ix, iy
    local blindWidth, blindHeight = iw, math.floor((ih/4) - 1)
    
    love.graphics.setColor(G.C.WHITE)
    love.graphics.setFont(G.FONTS.PIXEL.MEDIUM)
    
    
    if is_blind_select then
        TopUI.center_text("Choose blind", ix - sysDepth * textHeight, iy -2, iw, ih)

    elseif G.STATE == G.STATES.ROUND_EVAL then
        love.graphics.setColor(G.C.WHITE)
        love.graphics.setFont(G.FONTS.PIXEL.MEDIUM)
        TopUI.center_text("Round won!", ix - sysDepth * textHeight, iy - 6, iw, math.floor(ih * 0.55))
        local bi = G.current_blind_index or 1
        G:draw_blind_chip_anim(bi, ix + math.floor(iw / 2) - sysDepth * signHeight, iy + math.floor(ih * 0.72), 1.05)

    elseif G.STATE == G.STATES.GAME_OVER then
        love.graphics.setColor(G.C.MULT or G.C.WHITE)
        love.graphics.setFont(G.FONTS.PIXEL.MEDIUM)
        TopUI.center_text("Game Over", ix, iy - 6, iw, math.floor(ih * 0.55))
        local bi = G.current_blind_index or 1
        G:draw_blind_chip_anim(bi, ix + math.floor(iw / 2) - sysDepth * signHeight, iy + math.floor(ih * 0.72), 0.9)

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
        G:draw_shop_sign_anim(ix + math.floor(iw / 2) - sysDepth * signHeight, iy + math.floor(ih / 2), s)

    elseif G.STATE == G.STATES.OPEN_BOOSTER then
        love.graphics.setColor(G.C.WHITE)
        love.graphics.setFont(G.FONTS.PIXEL.MEDIUM)
        local sess = G.booster_session
        local t1 = (sess and sess.title) or "Booster Pack"
        TopUI.center_text(t1, ix, iy - 4, iw, math.floor(ih * 0.45))
        love.graphics.setFont(G.FONTS.PIXEL.MEDIUM)
        local pr = sess and tonumber(sess.picks_remaining) or 0
        TopUI.center_text("Picks left: " .. tostring(pr), ix - sysDepth * textHeight, iy + math.floor(ih * 0.6), iw, math.floor(ih * 0.35))

    else
        -- Score Requirements Box
        ix, iy, iw, ih = draw_rect_with_shadow(blindPosX, blindPosY, blindWidth, blindHeight, 4, 4, blind_color, blind_dark, 2, depthOffset)
        love.graphics.setColor(G.C.WHITE)
        TopUI.center_text(blind_name, ix - sysDepth * textHeight, iy -2, iw, ih)
        
        love.graphics.setColor(blind_sign)
        ix, iy, iw, ih = draw_rounded_rect(blindPosX, blindPosY + blindHeight + 4, blindWidth, blindHeight * 3, 4, 4, "fill")
        local score_box_ix, score_box_iy, score_box_iw, score_box_ih = ix, iy, iw, ih

        
        ix, iy, iw, ih = draw_rect_with_shadow(score_box_ix + math.floor(score_box_iw/3), score_box_iy - 1, 72, score_box_ih, 4, 4, G.C.BLOCK.BACK, G.C.BLOCK.SHADOW, 2, depthOffset)

        G:draw_blind_chip_anim(
            blind_index,
            score_box_ix + math.floor(score_box_iw / 6) - 2,
            score_box_iy + math.floor(score_box_ih / 2),
            1.1
        )
        
        love.graphics.setColor(G.C.WHITE)
        love.graphics.setFont(G.FONTS.PIXEL.SMALL)
        love.graphics.print("Score at least", ix - sysDepth * textHeight, iy - 2)

        love.graphics.setColor(G.C.RED)
        love.graphics.setFont(G.FONTS.PIXEL.MEDIUM)
        local scoreReq = tostring(math.floor(blind_target))
        local scoreReqY = iy + math.floor(G.FONTS.PIXEL.SMALL_HEIGHT/2) + 5
        love.graphics.printf(scoreReq, ix - sysDepth * textHeight, scoreReqY, iw, "center")

        love.graphics.setColor(G.C.WHITE)
        love.graphics.setFont(G.FONTS.PIXEL.SMALL)
        local rewardText = "Reward: "
        local rewardY = iy + math.floor(G.FONTS.PIXEL.SMALL_HEIGHT/2) + 6 + G.FONTS.PIXEL.MEDIUM_HEIGHT
        love.graphics.print(rewardText, ix - sysDepth * textHeight, rewardY)
        love.graphics.setColor(G.C.MONEY)
        local moneyText = "$"..string.rep("$", blind_reward).."+"
        local rewardLabelW = love.graphics.getFont():getWidth(rewardText)
        love.graphics.print(moneyText, ix + rewardLabelW - sysDepth * textHeight, rewardY)
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
    if (tonumber(G.round_score) or 0) > 99999999 then
        love.graphics.setFont(G.FONTS.PIXEL.SMALL)
    else
        love.graphics.setFont(G.FONTS.PIXEL.MEDIUM)
    end
    love.graphics.setColor(G.C.WHITE)
    TopUI.center_text(score, ix - sysDepth * textHeight, iy -1, iw, ih)


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
    local _, posY = TopUI.center_text(handSelected, ix - sysDepth * textHeight, iy -2, iw -20, math.floor(ih/3))
    posY = posY + math.floor(G.FONTS.PIXEL.MEDIUM_HEIGHT/6)
    love.graphics.setFont(G.FONTS.PIXEL.SMALL)
    local handLevel = G.selectedHandLevel or 1
    if(handSelected ~= "" and not handHidden) then
        love.graphics.printf("lvl." .. handLevel, ix - sysDepth * textHeight, posY, iw, "right")
    elseif handSelected ~= "" then
        love.graphics.printf("lvl.?", ix - sysDepth * textHeight, posY, iw, "right")
    end

    -- X
    love.graphics.setColor(G.C.RED)
    love.graphics.setFont(G.FONTS.PIXEL.MEDIUM)
    TopUI.center_text("X", ix - sysDepth * textHeight, iy + math.floor(ih/5), iw, ih)
    -- Chip
    local ChipX = ix
    local ChipY = iy + ih/3 + 6
    local ChipWidth = iw/2 - 8
    local ChipHeight = ih/2 + 2
    local totalW = iw
    draw_rect_with_shadow(ChipX, ChipY, ChipWidth, ChipHeight, 4, 2, G.C.CHIPS, G.C.CHIPS_DARK, 2, depthOffset)

    --Mult
    draw_rect_with_shadow(ChipX + totalW - ChipWidth, ChipY, ChipWidth, ChipHeight, 4, 2, G.C.MULT, G.C.MULT_DARK, 2, depthOffset)

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
    TopUI.center_text(handChips, ChipX - sysDepth * textHeight, ChipY - 1, ChipWidth, ChipHeight)
    TopUI.center_text(handMult, ChipX + totalW - ChipWidth - sysDepth * textHeight, ChipY - 1, ChipWidth, ChipHeight)
    
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
    TopUI.LabeledField("", "$"..tostring(G.money), fieldsPositionX, fieldsPositionY + fieldHeight + padding, fieldWidth * 2 + padding, fieldHeight, G.C.MONEY)

    -- Joker panel (left 2/3 of top screen).
    local dims = G.get_top_inventory_dims and G:get_top_inventory_dims() or { joker_panel_w = 266, consumable_panel_w = 132, consumable_panel_x = 268, panel_gap = 2 }
    local n = G and G.jokers and #G.jokers or 0
    local slot_w, slot_h = G.joker_slot_w or 71, G.joker_slot_h or 95
    local slot_gap = G.joker_slot_gap or 8
    local slot_y = G.joker_slot_y_top or (panelY + panelHeight + 6)
    local total_w = tonumber(G.joker_row_span_top)
        or select(2, G:_compute_fanned_joker_row(n, dims.joker_panel_w, slot_w, slot_gap, 4))
    local start_x = G.joker_slot_start_x or 4

    -- Extra padding so jokers don't touch the panel edges.
    local panel_pad = 3
    local joker_panel_w = dims.joker_panel_w
    local joker_panel_x = 0
    total_w = math.min(total_w + (panel_pad * 2), joker_panel_w)
    start_x = math.max(joker_panel_x + panel_pad, start_x - panel_pad)
    slot_y = slot_y - panel_pad
    slot_h = slot_h + (panel_pad * 2)

    -- Dark panel background.
    if G.jokers and #G.jokers > 0 then
        if _G.draw_rect_with_shadow then
            draw_rect_with_shadow(
                joker_panel_x,
                slot_y,
                joker_panel_w,
                slot_h,
                4,
                2,
                G and G.C and G.C.BLOCK and G.C.BLOCK.BACK or { 0, 0, 0, 1 },
                G and G.C and G.C.BLOCK and G.C.BLOCK.SHADOW or { 0, 0, 0, 1 },
                2,
                depthOffset
            )
        else
            love.graphics.setColor(G and G.C and G.C.PANEL or { 0.2, 0.2, 0.2, 1 })
            love.graphics.rectangle("fill", joker_panel_x, slot_y, joker_panel_w, slot_h, 4, 4)
        end
    end

    -- Consumable panel (right 1/3 of top screen).
    local cn = G and G.consumables and #G.consumables or 0
    if cn > 0 and G.consumables_on_bottom ~= true then
        if G.draw_consumables_row then G:draw_consumables_row() end
        local cslot_h = G.consumable_slot_h or 95
        local cslot_y = G.joker_slot_y_top or slot_y + panel_pad
        local c_panel_pad = 3
        cslot_y = cslot_y - c_panel_pad
        cslot_h = cslot_h + (c_panel_pad * 2)
        local c_panel_x = dims.consumable_panel_x
        local c_panel_w = dims.consumable_panel_w
        if _G.draw_rect_with_shadow then
            draw_rect_with_shadow(
                c_panel_x,
                cslot_y,
                c_panel_w,
                cslot_h,
                4,
                2,
                G and G.C and G.C.BLOCK and G.C.BLOCK.BACK or { 0, 0, 0, 1 },
                G and G.C and G.C.BLOCK and G.C.BLOCK.SHADOW or { 0, 0, 0, 1 },
                2,
                depthOffset
            )
        else
            love.graphics.setColor(G and G.C and G.C.PANEL or { 0.2, 0.2, 0.2, 1 })
            love.graphics.rectangle("fill", c_panel_x, cslot_y, c_panel_w, cslot_h, 4, 4)
        end
    end

    for _, t in ipairs(G.tags) do
        if t and t.draw then
            local scale = 0.75
            love.graphics.push()
            love.graphics.translate(t.X,t.Y)
            love.graphics.scale(scale,scale)
            local Tag = Tag(t.type)
            Tag.X = 0
            Tag.Y = 0
            Tag:draw()
            love.graphics.pop()
        end
    end

    -- Owned inventory on top screen (same layer as jokers; above tags / bottom-screen content).
    local draw_jokers_top = G and G.jokers_on_bottom ~= true and n > 0
    local draw_cons_top = G and G.consumables_on_bottom ~= true and cn > 0 and G.consumable_nodes
    if draw_jokers_top or draw_cons_top then
        love.graphics.setFont(G.FONTS.PIXEL.MEDIUM)
        love.graphics.setColor(G.C.WHITE)

        if draw_jokers_top then
            love.graphics.push()
            love.graphics.translate(-jokerDepthOffset, 0)
            for _, joker in ipairs(G.jokers) do
                if joker and joker.draw then
                    local prev_visible = joker.states and joker.states.visible
                    if joker.states then joker.states.visible = true end
                    joker:draw()
                    if joker.states then joker.states.visible = prev_visible end
                end
            end
            love.graphics.pop()
        end

        if draw_cons_top then
            love.graphics.push()
            love.graphics.translate(-jokerDepthOffset, 0)
            for _, cons in ipairs(G.consumable_nodes) do
                if cons and cons.draw then
                    local prev_visible = cons.states and cons.states.visible
                    if cons.states then cons.states.visible = true end
                    cons:draw()
                    if cons.states then cons.states.visible = prev_visible end
                end
            end
            love.graphics.pop()
        end
    end

    if self.popups then
        for _, popup in ipairs(self.popups) do
            if popup and popup.draw then
                popup:draw(popupDepthOffset)
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
    TopUI.center_text(value, ix - sysDepth * textHeight, iy - 1, iw, ih)

end

function TopUI.center_text(string, x, y, iw, ih)
    local s = tostring(string or "")
    local font = love.graphics.getFont()
    local yval = y + math.floor(ih/2) - math.floor(font:getHeight()/2)
    love.graphics.printf(s, x, yval, iw, "center")
    local xval = x
    return xval, yval
end

function TopUI:init()
    self.popups = {}
end

function TopUI:update(dt)
    local to_remove = {}
    for i, popup in ipairs(self.popups or {}) do
        if popup.update then
            popup:update(dt)
            if popup.remove or popup.time <= 0 then
                table.insert(to_remove, i)
            end
        end
    end

    -- Remove in reverse order so indices stay valid
    for i = #to_remove, 1, -1 do
        table.remove(self.popups, to_remove[i])
    end
end

function TopUI:addPopup(node)
    if Popup and node and node.is and node:is(Popup) then
        table.insert(self.popups, node)
    end
end