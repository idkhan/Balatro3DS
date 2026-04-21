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
    local scale = math.max(0.8, (area_h - 8) / card_h)
    local eff_w = card_w * scale
    local gap = 2
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
    if game.jokers_on_bottom then return end
    for i, offer in ipairs(game.shop_offers or {}) do
        local node = game.shop_offer_nodes and game.shop_offer_nodes[i]
        local rect = node and node.get_collision_rect and node:get_collision_rect() or game._shop_offer_rects[i]
        if rect then
            local label = "$" .. tostring(offer.price or 0)
            local font = game.FONTS.PIXEL.SMALL
            local tw = font:getWidth(label)
            local th = font:getHeight()
            local tag_w = math.floor(tw + 12)
            local tag_h = math.floor(th + 4)
            local tx = math.floor(rect.x + math.floor((rect.w - tag_w) * 0.5 + 0.5))
            local ty = math.floor(rect.y - tag_h - 2)
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
    local is_playing_card = offer.kind == "playing_card"
    local can_buy = can_afford and ((not is_consumable_offer and not is_playing_card) or (is_consumable_offer and game:can_add_consumable()) or is_playing_card)
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

function ShopUI.draw_shop_offer_use_button(game)
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
    local kind = offer.kind
    if kind ~= "tarot" and kind ~= "planet" and kind ~= "spectral" then return end
    if not (game.shop_offer_consumable_use_enabled and game:shop_offer_consumable_use_enabled(offer)) then return end

    local rect = selected.get_collision_rect and selected:get_collision_rect() or nil
    if not rect then return end

    local font = (game.FONTS and game.FONTS.PIXEL and game.FONTS.PIXEL.SMALL) or love.graphics.getFont()
    local prev_font = love.graphics.getFont()
    local prev_r, prev_g, prev_b, prev_a = love.graphics.getColor()
    love.graphics.setFont(font)

    local can_afford = game:can_afford_price(tonumber(offer.price) or 0)
    local label = "Buy and Use"
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
    local buy_h = math.max(14, font:getHeight() + 4)
    local by = rect.y + math.floor((rect.h - buy_h) * 0.5 + 0.5) + buy_h + 3
    if by < margin then by = margin end
    local can_use = can_afford
    local fill_c = can_use and (game.C and game.C.ORANGE) or (game.C and game.C.GREY)
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

    if can_use then
        game._shop_use_button_hit = { x = bx, y = by, w = btn_w, h = btn_h, slot_index = slot }
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

function ShopUI.try_use_button_press(game, x, y)
    local hit = game._shop_use_button_hit
    if not hit then return false end
    if not game:_point_in_rect_simple(x, y, hit) then return false end
    game.touch_start_x = x
    game.touch_start_y = y
    return game:buy_and_use_shop_consumable(hit.slot_index)
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

ShopUI.BOOSTER_ATLAS_FRAMES = {
    arcana = { normal = { 0, 1, 2, 3 }, jumbo = { 8, 9 }, mega = { 10, 11 } },
    celestial = { normal = { 4, 5, 6, 7 }, jumbo = { 12, 13 }, mega = { 14, 15 } },
    spectral = { normal = { 16, 17 }, jumbo = { 18 }, mega = { 19 } },
    standard = { normal = { 22, 23, 24, 25 }, jumbo = { 26, 27 }, mega = { 28, 29 } },
    buffoon = { normal = { 30, 31 }, jumbo = { 32 }, mega = { 33 } },
}

function ShopUI.booster_frames_for_pack_size(pack, size)
    local row = ShopUI.BOOSTER_ATLAS_FRAMES[pack]
    if not row then return nil end
    return row[size] or row.normal
end

---@return boolean
function ShopUI.draw_booster_atlas_frame(game, rect, frame_index_zero_based)
    if not game or not rect or type(frame_index_zero_based) ~= "number" then return false end
    if game.ensure_asset_atlas_loaded then
        game:ensure_asset_atlas_loaded("Booster")
    end
    local atlas = game.ASSET_ATLAS and game.ASSET_ATLAS.Booster
    if not atlas or not atlas.image then return false end

    local px = tonumber(atlas.px) or 72
    local py = tonumber(atlas.py) or 95
    local iw, ih = atlas.image:getDimensions()
    local cols = math.max(1, math.floor(iw / px))
    local idx = math.max(0, math.floor(frame_index_zero_based))
    local col = idx % cols
    local row = math.floor(idx / cols)
    local qx, qy = col * px, row * py
    if qx + px > iw + 0.5 or qy + py > ih + 0.5 then return false end

    atlas._pack_quads = atlas._pack_quads or {}
    local quad = atlas._pack_quads[idx]
    if not quad then
        quad = love.graphics.newQuad(qx, qy, px, py, iw, ih)
        atlas._pack_quads[idx] = quad
    end

    local s = math.min(1, rect.w / px, rect.h / py)
    local dw, dh = px * s, py * s
    local dx = rect.x + math.floor((rect.w - dw) * 0.5 + 0.5)
    local dy = rect.y + math.floor((rect.h - dh) * 0.5 + 0.5)
    local pr, pg, pb, pa = love.graphics.getColor()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(atlas.image, quad, dx, dy, 0, s, s)
    love.graphics.setColor(pr, pg, pb, pa)
    return true
end

--- Lay out up to two booster hit rects inside `boosterPanel`.
function ShopUI.layout_shop_booster_slots(game, param)
    game._shop_booster_rects = {}
    local offers = game.shop_booster_offers or {}
    local n = math.min(2, #offers)
    if n <= 0 or type(param) ~= "table" then return end

    local padding = 4
    local area_x = param.x + padding
    local area_y = param.y + padding
    local area_w = param.w - 2 * padding
    local area_h = param.h - 2 * padding

    local gap = 4
    local px, py = 72, 95
    local max_sw = ((area_w - (n - 1) * gap) / n) / px
    local max_sh = (area_h - 2) / py
    local scale = math.max(0.8, max_sw, max_sh)
    local pack_w = math.max(1, math.floor(px * scale))
    local pack_h = math.max(1, math.floor(py * scale))
    local total_w = n * pack_w + (n - 1) * gap
    local start_x = area_x + math.floor((area_w - total_w) * 0.5 + 0.5)
    local y = area_y + math.floor((area_h - pack_h) * 0.5 + 0.5)

    for i = 1, n do
        local x = start_x + (i - 1) * (pack_w + gap)
        game._shop_booster_rects[i] = { x = x, y = y, w = pack_w, h = pack_h }
    end
end

function ShopUI.draw_shop_booster_slots(game)
    if game.STATE ~= game.STATES.SHOP then return end
    for i, rect in ipairs(game._shop_booster_rects or {}) do
        local offer = game.shop_booster_offers and game.shop_booster_offers[i]
        if offer and rect then
            local sel = (game.active_shop_booster_slot == i)
            local c = game.C and game.C.BOOSTER or { 0.4, 0.43, 0.72 }
            local idx = offer.booster_sprite_index
            local drew = (type(idx) == "number") and ShopUI.draw_booster_atlas_frame(game, rect, idx)
            if not drew then
                if _G.draw_rect_with_shadow then
                    draw_rect_with_shadow(rect.x, rect.y, rect.w, rect.h, 3, 2, c, game.C.BLOCK.SHADOW, 1)
                else
                    love.graphics.setColor(c)
                    love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 3, 3)
                end
                love.graphics.setColor(game.C.WHITE)
                love.graphics.setFont(game.FONTS.PIXEL.SMALL)
                love.graphics.printf(offer.name or "Booster", rect.x + 2, rect.y + 3, rect.w - 4, "center")
            end
            love.graphics.setColor(game.C.WHITE)
            love.graphics.setFont(game.FONTS.PIXEL.SMALL)
            local sz = ({ normal = "N", jumbo = "J", mega = "M" })[offer.size] or ""
            love.graphics.printf(sz, rect.x + 2, rect.y + rect.h - 12, rect.w - 4, "center")
        end
    end
end

function ShopUI.draw_shop_booster_price_tags(game)
    if game.STATE ~= game.STATES.SHOP then return end
    for i, offer in ipairs(game.shop_booster_offers or {}) do
        local rect = game._shop_booster_rects and game._shop_booster_rects[i]
        if rect then
            local label = "$" .. tostring(offer.price or 0)
            local font = game.FONTS.PIXEL.SMALL
            local tw = font:getWidth(label)
            local tag_w = tw + 12
            local tag_h = font:getHeight() + 4
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

function ShopUI.draw_shop_booster_buy_button(game)
    if game.STATE ~= game.STATES.SHOP then return end
    local slot = tonumber(game.active_shop_booster_slot)
    if not slot or slot < 1 then return end
    local offer = game.shop_booster_offers and game.shop_booster_offers[slot]
    local rect = game._shop_booster_rects and game._shop_booster_rects[slot]
    if not offer or not rect then return end

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
    local fill_c = can_afford and game.C.MONEY or game.C.GREY
    local shadow_c = game.C and game.C.BLOCK and game.C.BLOCK.SHADOW

    if _G.draw_rect_with_shadow and fill_c and shadow_c then
        draw_rect_with_shadow(bx, by, btn_w, btn_h, 3, 2, fill_c, shadow_c, 1)
    else
        love.graphics.setColor(fill_c)
        love.graphics.rectangle("fill", bx, by, btn_w, btn_h, 3, 3)
    end
    love.graphics.setColor(game.C.WHITE)
    love.graphics.printf(label, bx, by + math.floor((btn_h - font:getHeight()) * 0.5 + 0.5), btn_w, "center")

    if can_afford then
        game._shop_booster_buy_button_hit = { x = bx, y = by, w = btn_w, h = btn_h, slot_index = slot }
    end

    love.graphics.setFont(prev_font)
    love.graphics.setColor(prev_r, prev_g, prev_b, prev_a)
end

function ShopUI.try_shop_booster_buy_press(game, x, y)
    local hit = game._shop_booster_buy_button_hit
    if not hit or not game:_point_in_rect_simple(x, y, hit) then return false end
    game.touch_start_x = x
    game.touch_start_y = y
    return game:buy_shop_booster(hit.slot_index)
end

--- Tap a pack to select/deselect (tooltip + Buy). Call before shop-offer node hits.
---@return boolean
function ShopUI.try_shop_booster_slot_press(game, x, y)
    if game.STATE ~= game.STATES.SHOP then return false end
    for i, rect in ipairs(game._shop_booster_rects or {}) do
        if rect and game:_point_in_rect_simple(x, y, rect) then
            if game.active_shop_booster_slot == i then
                game.active_shop_booster_slot = nil
            else
                game.active_shop_booster_slot = i
            end
            game.active_tooltip_joker = nil
            game.active_tooltip_card = nil
            game.active_tooltip_consumable_index = nil
            game.active_tooltip_shop_voucher = false
            return true
        end
    end
    return false
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
    local panel_x, panel_y, panel_w, panel_h = 4, 45, 312, 200
    if _G.draw_rect_with_shadow then
        draw_rect_with_shadow(panel_x, panel_y, panel_w, panel_h, 4, 2, game.C.BLOCK.BACK, game.C.BLOCK.SHADOW, 2)
    else
        love.graphics.setColor(game.C.PANEL)
        love.graphics.rectangle("fill", panel_x, panel_y, panel_w, panel_h, 4, 4)
    end

    love.graphics.setColor(game.C.RED)
    love.graphics.rectangle("line", panel_x, panel_y, panel_w, panel_h, 4, 4)

    local padding = 4
    local shop_continue_rect = { x = panel_x + padding, y = panel_y + padding, w = 74, h = 45, color = game.C.RED, text = "Next\nRound", lines = 2 }
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

    local bp_w, bp_h = 123, 90
    local boosterPanel = {
        x = jokerPanel.x + math.floor(jokerPanel.w * 0.5) - 10,
        y = jokerPanel.y + jokerPanel.h + padding,
        w = bp_w,
        h = bp_h,
    }
    love.graphics.setColor(game.C.PANEL)
    love.graphics.rectangle("fill", boosterPanel.x, boosterPanel.y, boosterPanel.w, boosterPanel.h, 4, 4)
    ShopUI.layout_shop_booster_slots(game, boosterPanel)

    --Voucher
    local voucherPanel = {
        x = panel_x + padding,
        y = boosterPanel.y,
        w = 177,
        h = bp_h,
    }
    love.graphics.setColor(game.C.PANEL)
    love.graphics.rectangle("fill", voucherPanel.x, voucherPanel.y, voucherPanel.w, voucherPanel.h, 4, 4)
    ShopUI.layout_shop_voucher_panel(game, voucherPanel)

    love.graphics.setColor(game.C.BLOCK.BACK)
    love.graphics.setFont(game.FONTS.PIXEL.MEDIUM)
    local text = "VOUCHER"
    love.graphics.print(text, panel_x -1 , voucherPanel.y + love.graphics.getFont():getWidth(text) / 2 + voucherPanel.h / 2 ,math.rad(-90))
end

function ShopUI.layout_shop_voucher_panel(game, voucherPanel)
    game._shop_voucher_rect = nil
    if type(voucherPanel) ~= "table" then return end
    if not (game.shop_voucher_offer and type(game.shop_voucher_offer) == "table") then return end

    local padding = 4
    local area_x = voucherPanel.x + padding
    local area_y = voucherPanel.y + padding
    local area_w = voucherPanel.w - 2 * padding
    local area_h = voucherPanel.h - 2 * padding

    local px, py = 72, 95
    local scale = 1
    local w = math.floor(px * scale)
    local h = math.floor(py * scale)
    local x = area_x + math.floor((area_w - w) * 0.5 + 0.5)
    local y = area_y + math.floor((area_h - h) * 0.5 + 0.5)
    game._shop_voucher_rect = { x = x, y = y, w = w, h = h }
end

function ShopUI.draw_shop_voucher_slot(game)
    if game.STATE ~= game.STATES.SHOP then return end
    local rect = game._shop_voucher_rect
    local offer = game.shop_voucher_offer
    if not rect then return end
    if not offer then return end
    local drew = false
    local def = VOUCHER_DEFS and offer.id and VOUCHER_DEFS[offer.id]
    local pos = def and tonumber(def.pos)
    if pos and game.ensure_asset_atlas_loaded and game.ASSET_ATLAS and game.ASSET_ATLAS.Voucher then
        game:ensure_asset_atlas_loaded("Voucher")
        local atlas = game.ASSET_ATLAS.Voucher
        if atlas and atlas.image then
            local cell_w = tonumber(atlas.px) or 71
            local cell_h = tonumber(atlas.py) or 95
            local iw, ih = atlas.image:getDimensions()
            local cols = math.max(1, math.floor(iw / cell_w))
            local idx = math.max(0, math.floor(pos))
            local col = idx % cols
            local row = math.floor(idx / cols)
            local qx, qy = col * cell_w, row * cell_h
            if qx + cell_w <= iw + 0.5 and qy + cell_h <= ih + 0.5 then
                atlas._voucher_quads = atlas._voucher_quads or {}
                local quad = atlas._voucher_quads[idx]
                if not quad then
                    quad = love.graphics.newQuad(qx, qy, cell_w, cell_h, iw, ih)
                    atlas._voucher_quads[idx] = quad
                end
                local s = math.min(rect.w / cell_w, rect.h / cell_h) * 0.85
                local dw, dh = cell_w * s, cell_h * s
                local dx = rect.x + math.floor((rect.w - dw) * 0.5 + 0.5)
                local dy = rect.y + math.floor((rect.h - dh) * 0.5 + 0.5)
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.draw(atlas.image, quad, dx, dy, 0, s, s)
                drew = true
            end
        end
    end
    if not drew then
        love.graphics.setColor(game.C.WHITE)
        love.graphics.setFont(game.FONTS.PIXEL.SMALL)
        love.graphics.printf(offer.name or "Voucher", rect.x + 2, rect.y + math.floor(rect.h * 0.35), rect.w - 4, "center")
    end
end

function ShopUI.draw_shop_voucher_price_tags(game)
    if game.STATE ~= game.STATES.SHOP then return end
    local offer = game.shop_voucher_offer
    local rect = game._shop_voucher_rect
    if not offer or not rect then return end
    local label = "$" .. tostring(offer.price or 0)
    local font = game.FONTS.PIXEL.SMALL
    local tw = font:getWidth(label)
    local tag_w = tw + 12
    local tag_h = font:getHeight() + 4
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

function ShopUI.draw_shop_voucher_buy_button(game)
    if game.STATE ~= game.STATES.SHOP then return end
    if not game.active_tooltip_shop_voucher then return end
    local offer = game.shop_voucher_offer
    local rect = game._shop_voucher_rect
    if not offer or not rect then return end

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
    local fill_c = can_afford and game.C.MONEY or game.C.GREY
    local shadow_c = game.C and game.C.BLOCK and game.C.BLOCK.SHADOW
    if _G.draw_rect_with_shadow and fill_c and shadow_c then
        draw_rect_with_shadow(bx, by, btn_w, btn_h, 3, 2, fill_c, shadow_c, 1)
    else
        love.graphics.setColor(0.3, 0.3, 0.3, 1)
        love.graphics.rectangle("fill", bx, by, btn_w, btn_h, 3, 3)
    end
    love.graphics.setColor(game.C.WHITE)
    local text_y = by + math.floor((btn_h - font:getHeight()) * 0.5 + 0.5)
    love.graphics.printf(label, bx, text_y, btn_w, "center")

    if can_afford then
        game._shop_voucher_buy_button_hit = { x = bx, y = by, w = btn_w, h = btn_h }
    end

    love.graphics.setFont(prev_font)
    love.graphics.setColor(prev_r, prev_g, prev_b, prev_a)
end

---@return boolean
function ShopUI.try_shop_voucher_buy_press(game, x, y)
    local hit = game._shop_voucher_buy_button_hit
    if not hit then return false end
    if not game:_point_in_rect_simple(x, y, hit) then return false end
    return game:buy_shop_voucher()
end

---@return boolean
function ShopUI.try_shop_voucher_press(game, x, y)
    if game.STATE ~= game.STATES.SHOP then return false end
    local rect = game._shop_voucher_rect
    if not rect or not game:_point_in_rect_simple(x, y, rect) then return false end
    if not game.shop_voucher_offer then return false end
    if game.active_tooltip_shop_voucher then
        game.active_tooltip_shop_voucher = false
    else
        game.active_tooltip_shop_voucher = true
    end
    game.active_tooltip_joker = nil
    game.active_tooltip_card = nil
    game.active_tooltip_consumable_index = nil
    game.active_shop_booster_slot = nil
    return true
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
