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
function TopUI.draw_rounded_rect(x, y, w, h, radius, padding, mode)
    padding = padding or 0
    mode = mode or "fill"
    radius = math.min(radius or 0, w / 2, h / 2)
    if radius < 0 then radius = 0 end
    love.graphics.rectangle(mode, x, y, w, h, radius, radius)
    local pad = padding
    return x + pad, y + pad, w - (2 * pad), h - (2 * pad)
end

function TopUI.draw_rect_with_shadow(x, y, w, h, radius, padding, color, shadowColor, shadowSize)
    love.graphics.setColor(shadowColor)
    TopUI.draw_rounded_rect(x, y + shadowSize, w, h, radius, padding, "fill")
    love.graphics.setColor(color)
    return TopUI.draw_rounded_rect(x, y, w, h, radius, padding, "fill")
end

function TopUI.draw()
    panelHeight = 104;
    panelY = 4;
    -- Panel
    love.graphics.setColor(G.C.PANEL)
    love.graphics.rectangle("fill", 0, panelY, 400, panelHeight)

    love.graphics.setColor(G.C.BLIND_COLORS.Big)
    love.graphics.rectangle("line", 0, panelY, 401, panelHeight)

    -- Title
    titlePosX = 2;
    titlePosY = 5 + panelY;
    titleHeight = 90;
    titleWidth = 120;
    love.graphics.setColor(G.C.BLOCK.SHADOW)
    local ix, iy, iw, ih = TopUI.draw_rect_with_shadow(titlePosX, titlePosY, titleWidth, titleHeight , 4, 2, G.C.BLOCK.BACK, G.C.BLOCK.SHADOW, 2)

    -- Blind
    blindPosX, blindPosY = ix, iy
    blindWidth, blindHeight = iw, math.floor((ih/4) - 1)
    ix, iy, iw, ih = TopUI.draw_rect_with_shadow(blindPosX, blindPosY, blindWidth, blindHeight, 4, 4, G.C.BLIND_COLORS.Big, G.C.BLIND_COLORS.BigDark, 2)
    
    love.graphics.setColor(G.C.WHITE)
    love.graphics.setFont(G.FONTS.PIXEL.MEDIUM)
    TopUI.center_text("Big Blind", ix, iy -2, iw, ih)

    -- Score Requirements Box
    love.graphics.setColor(G.C.BLIND_COLORS.BigSign)
    ix, iy, iw, ih = TopUI.draw_rounded_rect(blindPosX, blindPosY + blindHeight + 4, blindWidth, blindHeight * 3, 4, 4, "fill")

    ix, iy, iw, ih = TopUI.draw_rect_with_shadow(ix + math.floor(iw/3), iy - 1, 72, ih, 4, 4, G.C.BLOCK.BACK, G.C.BLOCK.SHADOW, 2)
    love.graphics.setColor(G.C.WHITE)
    love.graphics.setFont(G.FONTS.PIXEL.SMALL)
    love.graphics.print("Score at least", ix, iy - 2)

    love.graphics.setColor(G.C.RED)
    love.graphics.setFont(G.FONTS.PIXEL.MEDIUM)
    scoreReq = "10000"
    offset = 6
    love.graphics.print(scoreReq, ix + math.floor(iw/2) - math.floor(love.graphics.getFont():getWidth(scoreReq)/2) + 5, iy + math.floor(G.FONTS.PIXEL.SMALL_HEIGHT/2) + 5)

    love.graphics.setColor(G.C.WHITE)
    love.graphics.setFont(G.FONTS.PIXEL.SMALL)
    rewardText = "Reward: "
    rewardY = iy + math.floor(G.FONTS.PIXEL.SMALL_HEIGHT/2) + 6 + G.FONTS.PIXEL.MEDIUM_HEIGHT
    love.graphics.print(rewardText, ix, rewardY)
    love.graphics.setColor(G.C.MONEY)
    moneyText = "$$$"
    love.graphics.print(moneyText, ix + love.graphics.getFont():getWidth(rewardText) + math.floor((iw - math.floor(love.graphics.getFont():getWidth(rewardText)))/2) - math.floor(love.graphics.getFont():getWidth(moneyText)/2), rewardY)

    -- Round Score, Chips and Mult
    love.graphics.setColor(G.C.BLOCK.SHADOW)
    width = iw
    ix, iy, iw, ih = TopUI.draw_rounded_rect(titlePosX + (width * 2) - 2, titlePosY, titleWidth, math.floor(titleHeight/3.5), 4, 4, "fill")
    
    love.graphics.setFont(G.FONTS.PIXEL.SMALL)
    love.graphics.setColor(G.C.WHITE)
    love.graphics.print("Round", ix, iy - 3)
    love.graphics.print("Score", ix, iy + 7)

    love.graphics.setColor(G.C.PANEL)
    paneOffset = 30
    ix, iy, iw, ih = TopUI.draw_rounded_rect(ix + paneOffset, iy, iw - paneOffset, ih, 2, 2, "fill")

    score = "0"
    love.graphics.setFont(G.FONTS.PIXEL.MEDIUM)
    love.graphics.setColor(G.C.WHITE)
    TopUI.center_text(score, ix, iy -1, iw, ih)


    love.graphics.setColor(G.C.BLOCK.SHADOW)
    ix, iy, iw, ih = TopUI.draw_rounded_rect(titlePosX + (width * 2) - 2, titlePosY + math.floor(titleHeight/3.5) + 4, titleWidth, titleHeight - math.floor(titleHeight/3.5) - 3, 4, 4, "fill")

    love.graphics.setColor(G.C.WHITE)
    love.graphics.setFont(G.FONTS.PIXEL.MEDIUM)
    handSelected = ""
    if G.selectedHand and G.selectedHand ~= -1 then
        handSelected = G.handlist[G.selectedHand]
    end
    if(love.graphics.getFont():getWidth(handSelected) > iw) then
        love.graphics.setFont(G.FONTS.PIXEL.SMALL)
    end
    posX, posY = TopUI.center_text(handSelected, ix, iy -2, iw -20, math.floor(ih/3))

    posX = posX + love.graphics.getFont():getWidth(handSelected) + 6
    posY = posY + math.floor(G.FONTS.PIXEL.MEDIUM_HEIGHT/6)
    love.graphics.setFont(G.FONTS.PIXEL.SMALL)
    handLevel = 1
    if(handSelected ~= "") then
        love.graphics.print("lvl." .. handLevel, posX, posY)
    end

    -- X
    love.graphics.setColor(G.C.RED)
    love.graphics.setFont(G.FONTS.PIXEL.MEDIUM)
    TopUI.center_text("X", ix, iy + math.floor(ih/5), iw, ih)
    -- Chip
    ChipX = ix
    ChipY = iy + ih/3 + 6
    ChipWidth = iw/2 - 8
    ChipHeight = ih/2 + 2
    totalW = iw
    TopUI.draw_rect_with_shadow(ChipX, ChipY, ChipWidth, ChipHeight, 4, 2, G.C.CHIPS, G.C.CHIPS_DARK, 2)

    --Mult
    TopUI.draw_rect_with_shadow(ChipX + totalW - ChipWidth, ChipY, ChipWidth, ChipHeight, 4, 2, G.C.MULT, G.C.MULT_DARK, 2)
    
    -- Hands, Discards, Money, Ante and Round
    fieldsPositionX = titlePosX + (titleWidth + 6) * 2
    fieldsPositionY = titlePosY
    fieldWidth = 50
    fieldHeight = 43
    padding = 4
    value = 0
    TopUI.LabeledField("Hands", value, fieldsPositionX, fieldsPositionY, fieldWidth, fieldHeight, G.C.BLUE)
    TopUI.LabeledField("Discards", value, fieldsPositionX + fieldWidth + padding, fieldsPositionY, fieldWidth, fieldHeight, G.C.RED)
    TopUI.LabeledField("Ante", value, fieldsPositionX, fieldsPositionY + fieldHeight + padding, fieldWidth, fieldHeight, G.C.ORANGE)
    TopUI.LabeledField("Round", value, fieldsPositionX + fieldWidth + padding, fieldsPositionY + fieldHeight + padding, fieldWidth, fieldHeight, G.C.RED)

end

function TopUI.LabeledField(string, value, x, y, iw, ih, fieldColor)
    love.graphics.setColor(G.C.BLOCK.SHADOW)
    local ix, iy, iw, ih = TopUI.draw_rounded_rect(x, y, iw, ih, 4, 4,"fill")
    
    love.graphics.setColor(G.C.WHITE)
    love.graphics.setFont(G.FONTS.PIXEL.SMALL)
    TopUI.center_text(string, ix, iy, iw, math.floor(ih/4))

    love.graphics.setColor(G.C.PANEL)
    ix, iy, iw, ih = TopUI.draw_rounded_rect(ix, iy + ih/4 + 4, iw, math.floor(ih/4 * 3) - 4, 4, 4,"fill")

    love.graphics.setFont(G.FONTS.PIXEL.MEDIUM)
    love.graphics.setColor(fieldColor)
    TopUI.center_text(value, ix, iy - 1, iw, ih)

end

function TopUI.center_text(string, x, y, iw, ih)
    xval = x + math.floor(iw/2) - math.floor(love.graphics.getFont():getWidth(string)/2)
    yval = y + math.floor(ih/2) - math.floor(love.graphics.getFont():getHeight()/2)
    love.graphics.print(string, xval, yval)
    return xval, yval
end