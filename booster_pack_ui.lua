--- Bottom-screen UI while `Game.STATE == OPEN_BOOSTER`.
--- Cards are shown like shop items: tap to select (tooltip), then Pick/Use button next to selected.
--- Tarot/Spectral: hand drawn at the top, cards below; select hand first, then tap tarot, then Use.

local BoosterPackUI = {}

function BoosterPackUI.card_count_for_size(size)
    if size == "jumbo" or size == "mega" then
        return 5
    end
    return 3
end

function BoosterPackUI.picks_for_size(size)
    if size == "mega" then
        return 2
    end
    return 1
end

function BoosterPackUI.display_label(pack, size)
    local pn = ({ arcana = "Arcana", celestial = "Celestial", standard = "Standard", buffoon = "Buffoon", spectral = "Spectral" })[pack] or tostring(pack)
    return pn
end

--- Shop tooltip body (Balatro-style): "Choose X of Y Type Cards …".
function BoosterPackUI.shop_tooltip_description(offer)
    if type(offer) ~= "table" then return "" end
    local pack = tostring(offer.pack or "")
    local n = tonumber(offer.card_count)
    if not n or n <= 0 then
        n = BoosterPackUI.card_count_for_size(offer.size)
    end
    local picks = tonumber(offer.picks_granted)
    if picks == nil or picks < 0 then
        picks = BoosterPackUI.picks_for_size(offer.size)
    end

    local kind_label
    local tail
    if pack == "standard" then
        kind_label = "Playing"
        tail = "to add to your Deck."
    elseif pack == "arcana" then
        kind_label = "Tarot"
        tail = "to be used immediately."
    elseif pack == "celestial" then
        kind_label = "Planet"
        tail = "to be used immediately."
    elseif pack == "spectral" then
        kind_label = "Spectral"
        tail = "to be used immediately."
    elseif pack == "buffoon" then
        kind_label = "Joker"
        tail = "to add to your Jokers."
    else
        kind_label = "Cards"
        tail = "to be used immediately."
    end

    if picks == 2 then
        return string.format("Choose up to %d of %d %s Cards %s", picks, n, kind_label, tail)
    end
    return string.format("Choose %d of %d %s Cards %s", picks, n, kind_label, tail)
end

function BoosterPackUI.pack_needs_hand(pack)
    return pack == "arcana" or pack == "tarot" or pack == "spectral"
end

--- Position choice cards in the given area; selected card lifts up.
function BoosterPackUI.layout_choice_nodes(game, area)
    local sess = game.booster_session
    if not sess or type(area) ~= "table" then return end
    local nodes = sess.choice_nodes
    if type(nodes) ~= "table" then return end

    local card_w = game.joker_slot_w or 71
    local card_h = game.joker_slot_h or 95
    local padding = 4
    local area_x = area.x + padding
    local area_y = area.y + padding
    local area_w = area.w - padding * 2
    local area_h = area.h - padding * 2

    local indices = {}
    for i, ch in ipairs(sess.choices or {}) do
        if ch and not ch.taken then
            indices[#indices + 1] = i
        end
    end
    local n = #indices
    if n <= 0 then return end

    local scale = n > 4 and 0.9 or 1
    local eff_w = card_w * scale
    local eff_h = card_h * scale
    local min_margin = 2
    local max_span = math.max(eff_w, area_w - min_margin * 2)
    local natural_gap = 6 * scale
    local natural_step = eff_w + natural_gap
    local natural_span = n == 1 and eff_w or (eff_w + (n - 1) * natural_step)
    local step
    if n <= 1 then
        step = 0
    elseif natural_span <= max_span then
        step = natural_step
    else
        -- Tight packs overlap by reducing horizontal step.
        step = (max_span - eff_w) / (n - 1)
    end
    local total_span = n == 1 and eff_w or ((n - 1) * step + eff_w)
    local start_x = area_x + math.floor((area_w - total_span) * 0.5 + 0.5)
    local base_y = area_y + math.floor((area_h - eff_h) * 0.5 + 0.5)
    local half = (n + 1) * 0.5
    local max_dist = n > 1 and (n - 1) * 0.5 or 0
    local fan_drop = 8 * scale

    local active = tonumber(sess.active_choice_index)
    sess._choice_rects = {}

    local col = 0
    for _, i in ipairs(indices) do
        local node = nodes[i]
        if node and node.T and node.VT then
            col = col + 1
            local x = start_x + (col - 1) * step
            local selected = (active == i)
            local dist_from_center = math.abs(col - half)
            local t = max_dist > 0 and (dist_from_center / max_dist) or 0
            local y_drop = fan_drop * (t * t)
            local card_y = base_y + y_drop
            local y = selected and (card_y - 8) or card_y
            node.T.x = x
            node.T.y = y
            node.T.scale = scale
            if game.dragging ~= node then
                node.VT.x = x
                node.VT.y = y
                node.VT.scale = scale
            end
            node.states.visible = true
            node.states.click.can = true
            node.states.drag.can = true
            sess._choice_rects[i] = { x = x, y = y, w = card_w * scale, h = card_h * scale }
        end
    end
end

--- Draw the bottom info bar and place choice cards.
function BoosterPackUI.draw_bottom(game)
    local sess = game.booster_session
    if not sess then return end

    local padding = 4
    local width = 320
    local height = 240

    local info_h = 48
    local info_w = 128
    local info_y = height - info_h - padding

    love.graphics.setColor(game.C.PANEL)
    love.graphics.rectangle("fill", math.floor(width/2) - math.floor(info_w/2), height - info_h, info_w, info_h, 4, 4)
    
    love.graphics.setColor(game.C.RED)
    love.graphics.rectangle("line", math.floor(width/2) - math.floor(info_w/2), height - info_h, info_w, info_h + 10, 2, 2)
    love.graphics.setFont(game.FONTS.PIXEL.MEDIUM)
    love.graphics.setColor(game.C.WHITE)
    local title = sess.title or "Pack"
    local pr = tonumber(sess.picks_remaining) or 0
    love.graphics.printf(title, math.floor(width/2) - math.floor(info_w/2), info_y + 6, info_w, "center")
    love.graphics.setFont(game.FONTS.PIXEL.SMALL)
    love.graphics.printf("Picks left: " .. tostring(pr), math.floor(width/2) - math.floor(info_w/2), info_y + 32, info_w, "center")

    local skip_w = 60
    local skip_h = info_h - 4
    local skip_x = width - padding - skip_w
    local skip_y = info_y + 8
    local skip_rect = { x = skip_x, y = skip_y, w = skip_w, h = skip_h, color = game.C.RED, text = "Skip", lines = 1 }
    BoosterPackUI._draw_small_button(game, skip_rect)
    game._booster_skip_rect = { x = skip_x, y = skip_y, w = skip_w, h = skip_h }

    local choice_area = {
        x = padding,
        y = padding + 42,
        w = 320 - 2 * padding,
        h = height - info_h - 3 * padding,
    }
    game._booster_choice_area = choice_area
    BoosterPackUI.layout_choice_nodes(game, choice_area)
end

function BoosterPackUI._draw_small_button(game, param)
    if _G.draw_rect_with_shadow then
        local ix, iy, iw, ih = draw_rect_with_shadow(param.x, param.y, param.w, param.h, 4, 2, param.color, game.C.BLOCK.SHADOW, 2)
        love.graphics.setColor(game.C.WHITE)
        love.graphics.setFont(game.FONTS.PIXEL.MEDIUM)
        local textHeight = love.graphics.getFont():getHeight()
        local lines = param.lines or 1
        local textY = iy + math.floor(ih / 2) - math.floor((textHeight / 2) * lines)
        love.graphics.printf(param.text, ix, textY, iw, "center")
    else
        love.graphics.setColor(param.color)
        love.graphics.rectangle("fill", param.x, param.y, param.w, param.h, 4, 4)
    end
end

function BoosterPackUI.try_skip_press(game, x, y)
    local r = game._booster_skip_rect
    if not r or not game:_point_in_rect_simple(x, y, r) then return false end
    if game.end_booster_session then
        game:emit_joker_event("on_booster_skip",{})
        game:end_booster_session()
    end
    return true
end

---@return boolean True if the touch was consumed.
function BoosterPackUI.handle_touch_pressed(game, id, x, y)
    if BoosterPackUI.try_skip_press(game, x, y) then return true end

    local sess = game.booster_session
    if not sess then return false end

    local node = game:get_node_at(x, y)
    if node and node._booster_choice_index and node.touchpressed then
        game.touch_start_x = x
        game.touch_start_y = y
        node:touchpressed(id, x, y)
        game.dragging = node
        game:move_to_front(node)
        return true
    end

    sess.active_choice_index = nil
    game.active_tooltip_card = nil
    game.active_tooltip_joker = nil
    game.active_tooltip_consumable_index = nil
    return false
end

return BoosterPackUI
