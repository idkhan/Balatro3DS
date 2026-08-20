--- Bottom-screen shop panel, offer overlays, and shop-related touch targets.

local ShopUI = {}

function ShopUI.layout_shop_offer_nodes(game, param)
    local nodes = game.shop_offer_nodes or {}
    local offers = game.shop_offers or {}
    local n = math.min(#nodes, #offers)
    game._shop_offer_rects = {}
    if n <= 0 then return end

    local padding = 4
    local area_x = param.x + padding
    local area_y = param.y + padding
    local area_w = param.w - 2 * padding
    local area_h = param.h - 2 * padding

    local card_w = game.joker_slot_w or 71
    local card_h = game.joker_slot_h or 95
    local scale = math.min(1, math.max(0.55, (area_h - 4) / card_h))
    local eff_w = card_w * scale
    local eff_h = card_h * scale
    local gap_w = (game.joker_slot_gap or 8) * scale
    local step, _, start_x = game:_compute_fanned_joker_row(n, area_w, eff_w, gap_w, 2)
    local y = area_y + math.floor((area_h - eff_h) * 0.5 - 4)

    local interactive = (game.STATE == game.STATES.SHOP)
    for i = 1, n do
        local node = nodes[i]
        if node and node.T and node.VT then
            local x = area_x + start_x + ((i - 1) * step)
            node.T.x = x
            node.T.y = y
            node.T.scale = scale
            if game.dragging ~= node then
                node.VT.x = x
                node.VT.y = y
                node.VT.scale = scale
            end
            node.states.visible = interactive
            node.states.click.can = interactive
            node.states.drag.can = interactive
            node.shop_offer_slot = i
            game._shop_offer_rects[i] = node:get_collision_rect()
        end
    end
end

function ShopUI.layout_shop_booster_nodes(game, param)
    local nodes = game.shop_booster_nodes or {}
    local offers = game.shop_booster_offers or {}
    local n = math.min(#nodes, #offers)
    game._shop_booster_rects = {}
    if n <= 0 or type(param) ~= "table" then return end

    local padding = 4
    local area_x = param.x + padding
    local area_y = param.y + padding
    local area_w = param.w - 2 * padding
    local area_h = param.h - 2 * padding

    local pack_w, pack_h = 72, 95
    local scale = math.min(1, math.max(0.55, (area_h - 4) / pack_h))
    local eff_w = pack_w * scale
    local eff_h = pack_h * scale
    local step, _, start_x = game:_compute_fanned_joker_row(n, area_w, eff_w, 4 * scale, 2)
    local y = area_y + math.floor((area_h - eff_h) * 0.5 + 0.5)
    local interactive = (game.STATE == game.STATES.SHOP)

    for i = 1, n do
        local node = nodes[i]
        if node and node.T and node.VT then
            local x = area_x + start_x + ((i - 1) * step)
            node.T.w = pack_w
            node.T.h = pack_h
            node.T.x = x
            node.T.y = y
            node.T.scale = scale
            if game.dragging ~= node then
                node.VT.x = x
                node.VT.y = y
                node.VT.scale = scale
            end
            node.states.visible = interactive
            node.states.click.can = interactive
            node.states.drag.can = interactive
            node.shop_booster_slot = i
            game._shop_booster_rects[i] = node:get_collision_rect()
        end
    end
end

function ShopUI.layout_shop_voucher_nodes(game, param)
    local nodes = game.shop_voucher_nodes or {}
    local offers = game.shop_voucher_offers or {}
    local n = math.min(#nodes, #offers)
    game._shop_voucher_rects = {}
    if n <= 0 or type(param) ~= "table" then return end

    local padding = 4
    local area_x = param.x + padding
    local area_y = param.y + padding
    local area_w = param.w - 2 * padding
    local area_h = param.h - 2 * padding

    local pack_w, pack_h = 72, 95
    local scale = math.min(1, math.max(0.55, (area_h - 4) / pack_h))
    local eff_w = pack_w * scale
    local eff_h = pack_h * scale
    local step, _, start_x = game:_compute_fanned_joker_row(n, area_w, eff_w, 4 * scale, 2)
    local y = area_y + math.floor((area_h - eff_h) * 0.5 + 0.5)
    local interactive = (game.STATE == game.STATES.SHOP)

    for i = 1, n do
        local node = nodes[i]
        if node and node.T and node.VT then
            local x = area_x + start_x + ((i - 1) * step)
            node.T.w = pack_w
            node.T.h = pack_h
            node.T.x = x
            node.T.y = y
            node.T.scale = scale
            if game.dragging ~= node then
                node.VT.x = x
                node.VT.y = y
                node.VT.scale = scale
            end
            node.states.visible = interactive
            node.states.click.can = interactive
            node.states.drag.can = interactive
            node.shop_voucher_slot = i
            game._shop_voucher_rects[i] = {
                x = x, y = y, w = eff_w, h = eff_h,
            }
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
            love.graphics.printf(label, math.floor(tx), math.floor(ty + 2), tag_w, "center")
        end
    end
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

function ShopUI.draw_shop_booster_price_tags(game)
    if game.STATE ~= game.STATES.SHOP then return end
    for i, offer in ipairs(game.shop_booster_offers or {}) do
        local rect = game._shop_booster_rects and game._shop_booster_rects[i]
        if rect then
            local label = "$" .. tostring(offer.price or 0)
            local font = game.FONTS.PIXEL.SMALL
            local tw = font:getWidth(label)
            local tag_w = tw + 12
            local tag_h = font:getHeight() + 8
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
            love.graphics.printf(label, math.floor(tx), math.floor(ty + 2), tag_w, "center")
        end
    end
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

    game._shop_joker_panel = jokerPanel

    local bp_w, bp_h = 123, 90
    local boosterPanel = {
        x = jokerPanel.x + math.floor(jokerPanel.w * 0.5) - 10,
        y = jokerPanel.y + jokerPanel.h + padding,
        w = bp_w,
        h = bp_h,
    }
    love.graphics.setColor(game.C.PANEL)
    love.graphics.rectangle("fill", boosterPanel.x, boosterPanel.y, boosterPanel.w, boosterPanel.h, 4, 4)
    game._shop_booster_panel = boosterPanel
    ShopUI.layout_shop_booster_nodes(game, boosterPanel)

    local voucherPanel = {
        x = panel_x + padding,
        y = boosterPanel.y,
        w = 177,
        h = bp_h,
    }
    love.graphics.setColor(game.C.PANEL)
    love.graphics.rectangle("fill", voucherPanel.x, voucherPanel.y, voucherPanel.w, voucherPanel.h, 4, 4)
    game._shop_voucher_panel = voucherPanel
    ShopUI.layout_shop_voucher_nodes(game, voucherPanel)

    love.graphics.setColor(game.C.BLOCK.BACK)
    love.graphics.setFont(game.FONTS.PIXEL.MEDIUM)
    local text = "VOUCHER"
    love.graphics.print(text, panel_x -1 , voucherPanel.y + love.graphics.getFont():getWidth(text) / 2 + voucherPanel.h / 2 ,math.rad(-90))
end

function ShopUI.draw_shop_voucher_price_tags(game)
    if game.STATE ~= game.STATES.SHOP then return end
    for i, offer in ipairs(game.shop_voucher_offers or {}) do
        local rect = game._shop_voucher_rects and game._shop_voucher_rects[i]
        if offer and rect then
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
            love.graphics.printf(label, math.floor(tx), math.floor(ty + 2), tag_w, "center")
        end
    end
end

function ShopUI.handle_touch(game, x, y)
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
