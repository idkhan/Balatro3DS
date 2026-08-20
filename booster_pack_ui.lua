--- Bottom-screen UI while `Game.STATE == OPEN_BOOSTER`.
--- Cards are shown like shop items: tap to select (tooltip), then Pick/Use button next to selected.
--- Tarot/Spectral: hand drawn at the top, cards below; select hand first, then tap tarot, then Use.

local ShopUI = require("shop_ui")
local Particles = require("particles")

local BoosterPackUI = {}

-- Ambient particle field behind each pack type, standing in for the reference's per-pack
-- systems (`reference/Balatro/game.lua:3351-3550`: sparkles for arcana/celestial, stars
-- for standard, meteors for spectral). The shared Particles update/draw already runs in
-- OPEN_BOOSTER.
--- Ambient fields behind an open pack. A field's steady-state population is `rate * lifetime`,
--- which is the number that actually decides whether it reads as an atmosphere or as a few
--- specks - so that product, not `rate`, is what these are tuned on.
---
--- The reference's fields are denser still, but `Particles` is a fixed pool of 96 shared by
--- every effect in the game, and `emit` silently drops once it is empty. At ~30 per field there
--- is room for a dissolve or materialise burst (8-10 shards) to land during a pack without the
--- pack's own atmosphere eating the shards - which is the failure the reference never has to
--- think about, because it allocates particles freely and the 3DS cannot.
local AMBIENT_FIELDS = {
    arcana = {
        rate = 14, colour = { 0.63, 0.48, 0.86, 0.8 },
        vy_min = -14, vy_max = -26, vx_spread = 8, gravity = 0, lifetime = 2.2, size = 2,
    },
    celestial = {
        rate = 10, colour = { 0.75, 0.85, 1.0, 0.9 },
        vy_min = -4, vy_max = -10, vx_spread = 3, gravity = 0, lifetime = 3.0, size = 1,
    },
    spectral = {
        -- Streaks are short-lived by design, so this needs the highest rate of the five to put
        -- the same number of meteors on screen at once.
        rate = 24, colour = { 0.35, 0.72, 1.0, 0.9 },
        vy_min = 55, vy_max = 95, vx_spread = 70, gravity = 0, lifetime = 1.1, size = 2,
        streak = true,
    },
    standard = {
        rate = 15, colour = { 0.95, 0.35, 0.35, 0.7 },
        vy_min = -8, vy_max = -18, vx_spread = 6, gravity = 0, lifetime = 2.0, size = 2,
    },
    buffoon = {
        rate = 15, colour = { 1.0, 0.68, 0.25, 0.8 },
        vy_min = -10, vy_max = -20, vx_spread = 10, gravity = 0, lifetime = 2.0, size = 2,
    },
}
--- Ceiling on a field's steady-state population, enforced by a test so a future rate bump
--- cannot quietly starve the burst effects.
BoosterPackUI.AMBIENT_POPULATION_CAP = 34
BoosterPackUI.AMBIENT_FIELDS = AMBIENT_FIELDS
local AMBIENT_SPEC = { shape = "rect", fade = true }

local function ambient_random()
    if love.math and love.math.random then return love.math.random() end
    return math.random()
end

local function update_ambient_field(game, sess)
    local field = AMBIENT_FIELDS[sess.pack]
    if not field then return end
    local dt = tonumber(game.real_dt) or 0
    sess._ambient_timer = (sess._ambient_timer or 0) + dt * field.rate
    while sess._ambient_timer >= 1 do
        sess._ambient_timer = sess._ambient_timer - 1
        local r = ambient_random()
        AMBIENT_SPEC.colour = field.colour
        AMBIENT_SPEC.x = ambient_random() * 320
        -- Risers start below the bottom edge; fallers (spectral meteors) above the top.
        AMBIENT_SPEC.y = (field.vy_min < 0) and (240 + 4) or -4
        AMBIENT_SPEC.vx = (ambient_random() - 0.5) * 2 * field.vx_spread
        AMBIENT_SPEC.vy = field.vy_min + r * (field.vy_max - field.vy_min)
        AMBIENT_SPEC.gravity = field.gravity
        AMBIENT_SPEC.lifetime = field.lifetime
        if field.streak then
            AMBIENT_SPEC.w = 1
            AMBIENT_SPEC.h = 5 + math.floor(r * 4)
        else
            AMBIENT_SPEC.w = field.size
            AMBIENT_SPEC.h = field.size
        end
        Particles.emit(AMBIENT_SPEC)
    end
end

BoosterPackUI.PACK_MOVE_DURATION = 0.4
BoosterPackUI.PACK_BURST_DURATION = 1.3
BoosterPackUI.CARD_REVEAL_DURATION = 0.45

local function ease_out_cubic(t)
    t = math.max(0, math.min(1, t))
    return 1 - (1 - t) ^ 3
end

local function pack_target_rect()
    return { x = 124, y = 48, w = 72, h = 95 }
end

function BoosterPackUI.card_count_for_size(size, pack)
    -- Buffoon/Spectral packs are 2/4/4, unlike the other 3/5/5 packs
    -- (reference game.lua:681-696).
    if pack == "buffoon" or pack == "spectral" then
        if size == "jumbo" or size == "mega" then
            return 4
        end
        return 2
    end
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
    -- The size is part of the name in the reference (`localization/en-us.lua`: "Mega Buffoon
    -- Pack"), and it is the only thing distinguishing three otherwise identical collection
    -- entries. Dropping it made every size read as the plain pack.
    local prefix = ({ jumbo = "Jumbo ", mega = "Mega " })[size]
    return prefix and (prefix .. pn) or pn
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
    local reveal = sess.opening_phase == "reveal"
        and math.min(1, (tonumber(sess.opening_t) or 0) / BoosterPackUI.CARD_REVEAL_DURATION)
        or 1
    local reveal_eased = ease_out_cubic(reveal)
    local source = sess.opening_pack_rect or pack_target_rect()
    local source_x = source.x + source.w * 0.5 - card_w * 0.5
    local source_y = source.y + source.h * 0.5 - card_h * 0.5
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
            local draw_x = source_x + (x - source_x) * reveal_eased
            local draw_y = source_y + (y - source_y) * reveal_eased
            local draw_scale = scale * (0.18 + 0.82 * reveal_eased)
            node.T.x = draw_x
            node.T.y = draw_y
            node.T.scale = draw_scale
            if game.dragging ~= node then
                node.VT.x = draw_x
                node.VT.y = draw_y
                node.VT.scale = draw_scale
            end
            node.states.visible = true
            node.states.click.can = reveal >= 1
            node.states.drag.can = reveal >= 1
            if reveal >= 1 then
                sess._choice_rects[i] = { x = x, y = y, w = card_w * scale, h = card_h * scale }
            end
        end
    end
end

local PACK_COLOURS = {
    arcana = { 0.78, 0.48, 1, 1 },
    celestial = { 0.65, 0.85, 1, 1 },
    spectral = { 1, 0.9, 0.55, 1 },
    standard = { 0.95, 0.25, 0.25, 1 },
    buffoon = { 0.95, 0.7, 0.2, 1 },
}

--- Draw the purchased wrapper while it travels to centre and builds toward its burst.
--- Primitive shards replace the reference particle systems on the shaderless 3DS.
function BoosterPackUI.draw_opening(game)
    local sess = game.booster_session
    if not sess then return end
    local target = pack_target_rect()
    local phase = sess.opening_phase
    local elapsed = tonumber(sess.opening_t) or 0

    if phase == "move" or phase == "buildup" then
        local origin = sess.opening_origin_rect or target
        local move_p = phase == "move" and ease_out_cubic(elapsed / BoosterPackUI.PACK_MOVE_DURATION) or 1
        local x = origin.x + (target.x - origin.x) * move_p
        local y = origin.y + (target.y - origin.y) * move_p
        local buildup_p = phase == "buildup"
            and math.min(1, elapsed / (BoosterPackUI.PACK_BURST_DURATION * math.sqrt(tonumber(game.SETTINGS.GAMESPEED) or 1)))
            or 0
        local pulse = buildup_p * (2 + 3 * math.sin(elapsed * 34))
        local scale = 1 + buildup_p * 0.15
        local w, h = target.w * scale, target.h * scale
        local rect = {
            x = x + target.w * 0.5 - w * 0.5 + pulse,
            y = y + target.h * 0.5 - h * 0.5,
            w = w,
            h = h,
        }
        sess.opening_pack_rect = rect
        if not ShopUI.draw_booster_atlas_frame(game, rect, tonumber(sess.booster_sprite_index) or 0) then
            love.graphics.setColor((game.C and game.C.BOOSTER) or { 0.4, 0.43, 0.72, 1 })
            love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 3, 3)
            love.graphics.setColor(1, 1, 1, 1)
        end
        return
    end

    if phase == "reveal" and elapsed < BoosterPackUI.CARD_REVEAL_DURATION then
        local p = elapsed / BoosterPackUI.CARD_REVEAL_DURATION
        local cx, cy = target.x + target.w * 0.5, target.y + target.h * 0.5
        local colour = PACK_COLOURS[sess.pack] or game.C.WHITE
        love.graphics.setColor(colour)
        for i = 1, 18 do
            local angle = i * 2.399963 + (tonumber(sess.booster_sprite_index) or 0) * 0.17
            local distance = (12 + (i % 5) * 5) * ease_out_cubic(p)
            local size = math.max(1, math.floor((1 - p) * (3 + i % 3)))
            love.graphics.rectangle("fill",
                math.floor(cx + math.cos(angle) * distance),
                math.floor(cy + math.sin(angle) * distance), size, size)
        end
        love.graphics.setColor(1, 1, 1, 1)
    end
end

--- Draw the bottom info bar and place choice cards.
function BoosterPackUI.draw_bottom(game)
    local sess = game.booster_session
    if not sess then return end

    if sess.opening_phase == "move" or sess.opening_phase == "buildup" then
        BoosterPackUI.draw_opening(game)
        return
    end

    update_ambient_field(game, sess)

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
    BoosterPackUI.draw_opening(game)
end

function BoosterPackUI._draw_small_button(game, param)
    if _G.draw_rect_with_shadow then
        local ix, iy, iw, ih = draw_button_with_shadow(param.x, param.y, param.w, param.h, 4, 2, param.color, game.C.BLOCK.SHADOW, 2)
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
    if not game.booster_session or game.booster_session.opening_phase ~= "ready" then return false end
    local r = game._booster_skip_rect
    if not r or not game:_point_in_rect_simple(x, y, r) then return false end
    Sfx.play_button()
    if game.end_booster_session then
        -- A pack whose last pick has already been taken is closing on its own; this press only
        -- cuts the hold short. Nothing was skipped, so nothing hears about a skip.
        if not game._booster_closing then
            game:emit_joker_event("on_booster_skip",{})
        end
        game:end_booster_session()
    end
    return true
end

---@return boolean True if the touch was consumed.
function BoosterPackUI.handle_touch_pressed(game, id, x, y)
    local sess = game.booster_session
    if not sess or sess.opening_phase ~= "ready" then return true end
    if BoosterPackUI.try_skip_press(game, x, y) then return true end

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
