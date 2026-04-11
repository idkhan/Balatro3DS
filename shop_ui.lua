--- Bottom-screen shop panel, offer overlays, and shop-related touch targets.

local ShopUI = {}

function ShopUI.layout_shop_offer_nodes(game, param)
    local nodes = game.shop_offer_nodes or {}
    local offers = game.shop_offers or {}
    local n = math.min(#nodes, #offers)
    game._shop_offer_rects = {}
    if n <= 0 then return end

    local padding = 4
    local area_x = param.x - padding
    local area_y = param.y + padding
    local area_w = param.w
    local area_h = param.h - padding

    local card_w = game.joker_slot_w or 71
    local card_h = game.joker_slot_h or 95
    local scale = math.min(0.8, (area_h - 8) / card_h)
    local eff_w = card_w * scale
    local gap = 4
    local total_w = (n * eff_w) + ((n - 1) * gap)
    if total_w > (area_w - 8) and n > 1 then
        gap = math.max(2, ((area_w - 8) - (n * eff_w)) / (n - 1))
        total_w = (n * eff_w) + ((n - 1) * gap)
    end
    local start_x = area_x + math.floor((area_w - total_w) * 0.5 + 0.5)
    local y = area_y + math.floor(area_h - (card_h * scale) - 13 + 0.5)

    local interactive = (game.STATE == game.STATES.SHOP)
    for i = 1, n do
        local node = nodes[i]
        if node and node.T and node.VT then
            local x = start_x + ((i - 1) * (eff_w + gap))
            local selected = (game.active_tooltip_joker == node)
            node.T.x = x
            node.T.y = y - (selected and 8 or 0)
            node.T.scale = scale
            if game.dragging ~= node then
                node.VT.x = x
                node.VT.y = node.T.y
                node.VT.scale = scale
            end
            node.states.visible = interactive
            node.states.click.can = interactive
            node.states.drag.can = false
            node.shop_offer_slot = i
            game._shop_offer_rects[i] = node:get_collision_rect()
        end
    end
end

function ShopUI.draw_shop_offer_price_tags(game)
    if game.STATE ~= game.STATES.SHOP then return end
    for i, offer in ipairs(game.shop_offers or {}) do
        local node = game.shop_offer_nodes and game.shop_offer_nodes[i]
        local rect = node and node.get_collision_rect and node:get_collision_rect() or game._shop_offer_rects[i]
        if rect then
            local label = "$" .. tostring(offer.price or 0)
            local font = game.FONTS.PIXEL.SMALL
            local tw = font:getWidth(label)
            local th = font:getHeight()
            local tag_w = tw + 12
            local tag_h = th + 4
            local tx = rect.x + math.floor((rect.w - tag_w) * 0.5 + 0.5)
            local ty = rect.y - tag_h - 2
            if _G.draw_rect_with_shadow then
                draw_rect_with_shadow(tx, ty, tag_w, tag_h, 3, 2, game.C.BLOCK.BACK, game.C.BLOCK.SHADOW, 1)
            else
                love.graphics.setColor(game.C.BLOCK.BACK)
                love.graphics.rectangle("fill", tx, ty, tag_w, tag_h, 3, 3)
            end
            love.graphics.setFont(font)
            love.graphics.setColor(game.C.MONEY)
            love.graphics.printf(label, tx, ty + 2, tag_w, "center")
        end
    end
end

function ShopUI.draw_shop_offer_buy_button(game)
    if game.STATE ~= game.STATES.SHOP then return end
    local selected = game.active_tooltip_joker
    local is_shop_offer = false
    for _, n in ipairs(game.shop_offer_nodes or {}) do
        if n == selected then
            is_shop_offer = true
            break
        end
    end
    if not selected or not is_shop_offer then return end
    local slot = tonumber(selected.shop_offer_slot)
    local offer = slot and game.shop_offers and game.shop_offers[slot] or nil
    if not offer then return end
    local rect = selected.get_collision_rect and selected:get_collision_rect() or nil
    if not rect then return end

    local font = (game.FONTS and game.FONTS.PIXEL and game.FONTS.PIXEL.SMALL) or love.graphics.getFont()
    local prev_font = love.graphics.getFont()
    local prev_r, prev_g, prev_b, prev_a = love.graphics.getColor()
    love.graphics.setFont(font)

    local can_afford = game:can_afford_price(tonumber(offer.price) or 0)
    local label = "Buy"
    local btn_w = math.max(32, font:getWidth(label) + 14)
    local btn_h = math.max(14, font:getHeight() + 4)
    local gap = 4
    local margin = 2
    local sw = 320
    if love.graphics.getWidth then
        sw = love.graphics.getWidth("bottom")
        if not sw or sw <= 0 then sw = love.graphics.getWidth() end
    end
    if not sw or sw <= 0 then sw = 320 end
    local bx = rect.x + rect.w + gap
    if bx + btn_w > (sw - margin) then
        bx = rect.x - btn_w - gap
    end
    if bx < margin then bx = margin end
    local by = rect.y + math.floor((rect.h - btn_h) * 0.5 + 0.5)
    if by < margin then by = margin end
    local is_consumable_offer = offer.kind == "tarot" or offer.kind == "planet"
    local can_buy = can_afford and (not is_consumable_offer or game:can_add_consumable())
    local fill_c = can_buy and game.C.MONEY or game.C.GREY
    local shadow_c = game.C and game.C.BLOCK and game.C.BLOCK.SHADOW

    if _G.draw_rect_with_shadow and fill_c and shadow_c then
        draw_rect_with_shadow(bx, by, btn_w, btn_h, 3, 2, fill_c, shadow_c, 1)
    else
        if type(fill_c) == "table" then
            love.graphics.setColor(fill_c[1], fill_c[2], fill_c[3], fill_c[4] or 1)
        else
            love.graphics.setColor(0.2, 0.2, 0.2, 1)
        end
        love.graphics.rectangle("fill", bx, by, btn_w, btn_h, 3, 3)
    end
    love.graphics.setColor(game.C.WHITE)
    local text_y = by + math.floor((btn_h - font:getHeight()) * 0.5 + 0.5)
    love.graphics.printf(label, bx, text_y, btn_w, "center")

    if can_buy then
        game._shop_buy_button_hit = { x = bx, y = by, w = btn_w, h = btn_h, slot_index = slot }
    end

    love.graphics.setFont(prev_font)
    love.graphics.setColor(prev_r, prev_g, prev_b, prev_a)
end

function ShopUI.try_buy_button_press(game, x, y)
    local hit = game._shop_buy_button_hit
    if not hit then return false end
    if not game:_point_in_rect_simple(x, y, hit) then return false end
    game.touch_start_x = x
    game.touch_start_y = y
    return game:buy_shop_joker(hit.slot_index)
end

--- Top-screen shop sign (`animation_atli.shop_sign`).
function ShopUI.draw_shop_sign_anim(game, center_x, center_y, scale)
    local atlas = game.ANIMATION_ATLAS and game.ANIMATION_ATLAS.shop_sign
    if not atlas or not atlas.image then return end
    local cell_w = tonumber(atlas.px) or 113
    local cell_h = tonumber(atlas.py) or 60
    local frame_count = tonumber(atlas.frames) or 4
    local anim_fps = 8
    local t = love.timer.getTime()
    local frame = math.floor(t * anim_fps) % math.max(1, frame_count)
    local iw, ih = atlas.image:getDimensions()
    local cols = math.max(1, math.floor(iw / cell_w))
    local col = frame % cols
    local row = math.floor(frame / cols)
    local qx = col * cell_w
    local qy = row * cell_h
    local quad = love.graphics.newQuad(qx, qy, cell_w, cell_h, iw, ih)
    local s = scale or 1
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(atlas.image, quad, center_x - (cell_w * s * 0.5), center_y - (cell_h * s * 0.5), 0, s, s)
end

function ShopUI.draw_shop_button(game, param)
    if type(param) ~= "table" then
        print(type(param))
        return
    end

    local x = param.x
    local y = param.y
    local w = param.w
    local h = param.h
    local color = param.color
    local text = param.text
    local lines = param.lines

    if _G.draw_rect_with_shadow then
        local ix, iy, iw, ih = draw_rect_with_shadow(x, y, w, h, 4, 2, color, game.C.BLOCK.SHADOW, 2)
        love.graphics.setColor(game.C.WHITE)
        love.graphics.setFont(game.FONTS.PIXEL.SMALL)
        local textHeight = love.graphics.getFont():getHeight()
        local textY = iy + math.floor(ih / 2) - math.floor((textHeight / 2) * lines)
        love.graphics.printf(text, ix, textY, iw, "center")
    else
        love.graphics.setColor(color)
        love.graphics.rectangle("fill", x, y, w, h, 4, 4)
    end
end

function ShopUI.draw_bottom_shop(game)
    local panel_x, panel_y, panel_w, panel_h = 4, 65, 312, 200
    if _G.draw_rect_with_shadow then
        draw_rect_with_shadow(panel_x, panel_y, panel_w, panel_h, 4, 2, game.C.BLOCK.BACK, game.C.BLOCK.SHADOW, 2)
    else
        love.graphics.setColor(game.C.PANEL)
        love.graphics.rectangle("fill", panel_x, panel_y, panel_w, panel_h, 4, 4)
    end

    love.graphics.setColor(game.C.RED)
    love.graphics.rectangle("line", panel_x, panel_y, panel_w, panel_h, 4, 4)

    local padding = 4
    local shop_continue_rect = { x = panel_x + padding, y = panel_y + padding, w = 74, h = 40, color = game.C.RED, text = "Next\nRound", lines = 2 }
    local reroll_cost = game:shop_current_reroll_cost()
    local can_reroll = game:can_afford_price(reroll_cost)
    local reroll_color = can_reroll and game.C.GREEN or game.C.GREY
    local shop_reroll_rect = {
        x = panel_x + padding,
        y = shop_continue_rect.y + shop_continue_rect.h + padding,
        w = shop_continue_rect.w,
        h = shop_continue_rect.h,
        color = reroll_color,
        text = "Reroll\n$" .. tostring(reroll_cost),
        lines = 2
    }
    game._shop_continue_rect = { x = shop_continue_rect.x, y = shop_continue_rect.y, w = shop_continue_rect.w, h = shop_continue_rect.h }
    game._shop_reroll_rect = { x = shop_reroll_rect.x, y = shop_reroll_rect.y, w = shop_reroll_rect.w, h = shop_reroll_rect.h }
    ShopUI.draw_shop_button(game, shop_continue_rect)
    ShopUI.draw_shop_button(game, shop_reroll_rect)

    love.graphics.setColor(game.C.PANEL)
    local jokerPanel = { x = shop_continue_rect.x + shop_continue_rect.w + padding, y = shop_continue_rect.y, w = panel_w - 3 * padding - shop_continue_rect.w, h = (shop_reroll_rect.y + shop_reroll_rect.h) - shop_continue_rect.y }
    love.graphics.rectangle("fill", jokerPanel.x, jokerPanel.y, jokerPanel.w, jokerPanel.h, 4, 4)

    ShopUI.layout_shop_offer_nodes(game, jokerPanel)
end

function ShopUI.handle_touch(game, x, y)
    for i, r in ipairs(game._shop_owned_rects or {}) do
        if game:_point_in_rect_simple(x, y, r) then
            game:sell_owned_joker(i)
            return true
        end
    end
    if game:_point_in_rect_simple(x, y, game._shop_continue_rect) then
        game:continue_from_shop()
        return true
    end
    if game:_point_in_rect_simple(x, y, game._shop_reroll_rect) then
        game:reroll_shop_offers()
        return true
    end
    return false
end

return ShopUI
