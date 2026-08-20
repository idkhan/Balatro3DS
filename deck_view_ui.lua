--- Bottom-screen overlay: remaining draw-pile cards as interactable Card nodes (one row per non-empty suit).
local DeckViewUI = {}
local SCREEN_W, SCREEN_H = 320, 240
local CARD_W, CARD_H = 71, 95
local TAP_THRESHOLD = 15

local TOP_W, TOP_H = 400, 240

local SUITS = { "Hearts", "Clubs", "Diamonds", "Spades" }

local SUIT_SYMBOLS = {
    Hearts = "H",
    Clubs = "C",
    Diamonds = "D",
    Spades = "S",
}

sysDepth = 0
buttonHeight = 1
textHeight = 2
signHeight = 3
jokerHeight = 2
PopupHeight = 4

---@param cards table[]
---@return table<string, table[]>
function DeckViewUI.group_by_suit(cards)
    local by_suit = {}
    for _, suit in ipairs(SUITS) do
        by_suit[suit] = {}
    end
    for _, card_data in ipairs(cards or {}) do
        local suit = card_data and card_data.suit
        if suit and by_suit[suit] then
            by_suit[suit][#by_suit[suit] + 1] = card_data
        end
    end
    for _, suit in ipairs(SUITS) do
        table.sort(by_suit[suit], function(a, b)
            return (tonumber(a.rank) or 0) < (tonumber(b.rank) or 0)
        end)
    end
    return by_suit
end

--- Suits that still have at least one card in the draw pile, in standard order.
---@param rows table<string, table[]>
---@return string[]
function DeckViewUI.active_suits(rows)
    local active = {}
    for _, suit in ipairs(SUITS) do
        if rows[suit] and #rows[suit] > 0 then
            active[#active + 1] = suit
        end
    end
    return active
end

local ROW_GAP = 2
local ROW_PAD_Y = 1

--- Overlapping row step (same idea as `Game:_compute_fanned_joker_row`).
---@return number step
---@return number total_span
---@return number start_x offset within `area_w`
local function compute_fanned_step(n, area_w, card_w, gap)
    gap = gap or ROW_GAP
    n = tonumber(n) or 0
    card_w = tonumber(card_w) or CARD_W
    area_w = tonumber(area_w) or SCREEN_W
    if n <= 0 then return 0, 0, 0 end
    if n == 1 then
        return 0, card_w, math.floor((area_w - card_w) * 0.5 + 0.5)
    end
    local natural_step = card_w + gap
    local natural_span = card_w + (n - 1) * natural_step
    local step, total_span
    if natural_span <= area_w then
        step = natural_step
        total_span = natural_span
    else
        step = (area_w - card_w) / (n - 1)
        total_span = (n - 1) * step + card_w
    end
    local start_x = math.floor((area_w - total_span) * 0.5 + 0.5)
    return step, total_span, start_x
end

function DeckViewUI._chrome_metrics(row_count)
    local margin_x = 2
    local label_w = 2
    local header_h = 16
    local footer_h = 16
    row_count = tonumber(row_count) or 0
    local content_h = SCREEN_H - header_h - footer_h
    local row_h = row_count > 0 and (content_h / row_count) or 0
    local area_w = SCREEN_W - margin_x * 4 - label_w
    local scale = row_count > 0 and math.min(1, (row_h - ROW_PAD_Y * 2) / CARD_H) or 1
    local card_w = CARD_W * scale
    local card_h = CARD_H * scale
    return {
        margin_x = margin_x,
        label_w = label_w,
        header_h = header_h,
        footer_h = footer_h,
        row_h = row_h,
        area_w = area_w,
        row_start_x = margin_x + label_w,
        scale = scale,
        card_w = card_w,
        card_h = card_h,
    }
end

function DeckViewUI._layout_row(nodes, m, row_y)
    local n = #(nodes or {})
    if n == 0 then return end
    local step, _, rel_start = compute_fanned_step(n, m.area_w, m.card_w, ROW_GAP)
    local card_y = row_y + math.floor((m.row_h - m.card_h) * 0.5 + 0.5)
    local x = m.row_start_x + rel_start
    for i, node in ipairs(nodes) do
        if node and node.T then
            local px = x + (i - 1) * step
            node.T.x = px
            node.T.y = card_y
            node.T.r = 0
            node.T.scale = m.scale
            if node.collision_offset then
                node.collision_offset.x = 0
                node.collision_offset.y = 0
            end
            if not (node.states and node.states.drag and node.states.drag.is) then
                node.VT.x = px
                node.VT.y = card_y
                node.VT.r = 0
                node.VT.scale = m.scale
            end
        end
    end
end

function DeckViewUI.layout(game)
    local rows = game._deck_view_rows
    if type(rows) ~= "table" then return end
    local active = DeckViewUI.active_suits(rows)
    local m = DeckViewUI._chrome_metrics(#active)
    for row_i, suit in ipairs(active) do
        local row_y = m.header_h + (row_i - 1) * m.row_h
        DeckViewUI._layout_row(rows[suit], m, row_y)
    end
end

function DeckViewUI.build(game)
    DeckViewUI.destroy(game)
    if not game or not game.deck then return end

    game._deck_view_rows = {}
    game._deck_view_nodes = {}
    for _, suit in ipairs(SUITS) do
        game._deck_view_rows[suit] = {}
    end

    local by_suit = DeckViewUI.group_by_suit(game.deck.cards)
    for _, suit in ipairs(SUITS) do
        for _, card_data in ipairs(by_suit[suit]) do
            local copy = Deck.copy_card_data(card_data)
            if copy and game.ensure_card_uid then
                game:ensure_card_uid(copy)
            end
            local node = Card(0, 0, CARD_W, CARD_H, copy, nil, { face_up = true })
            node._deck_view_card = true
            node.states.click.can = true
            node.states.drag.can = true
            game:add(node)
            game._deck_view_rows[suit][#game._deck_view_rows[suit] + 1] = node
            game._deck_view_nodes[#game._deck_view_nodes + 1] = node
        end
    end

    DeckViewUI.layout(game)

    if game.hand and game.hand.card_nodes then
        for _, node in ipairs(game.hand.card_nodes) do
            node.states.visible = false
            node._deck_view_hidden = true
        end
    end
end

function DeckViewUI.destroy(game)
    if not game then return end
    for _, node in ipairs(game._deck_view_nodes or {}) do
        if node then
            node.selected = false
            game:remove(node)
        end
    end
    game._deck_view_rows = nil
    game._deck_view_nodes = nil

    if game.hand and game.hand.card_nodes then
        for _, node in ipairs(game.hand.card_nodes) do
            if node and node._deck_view_hidden then
                node.states.visible = true
                node._deck_view_hidden = nil
            end
        end
    end
end

function DeckViewUI.toggle_tooltip(game, node)
    if not game or not node or not node._deck_view_card then return end
    if game.active_tooltip_card == node then
        game.active_tooltip_card = nil
    else
        game.active_tooltip_card = node
        game.active_tooltip_joker = nil
        game.active_tooltip_consumable_index = nil
        if game.move_to_front then
            game:move_to_front(node)
        end
    end
end

function DeckViewUI.get_node_at(game, x, y)
    for i = #(game._deck_view_nodes or {}), 1, -1 do
        local node = game._deck_view_nodes[i]
        if node and node.states and node.states.click.can and game:point_in_rect(x, y, node) then
            return node
        end
    end
    return nil
end

function DeckViewUI.handle_touchpressed(game, id, x, y)
    game.touch_start_x = x
    game.touch_start_y = y
    local node = DeckViewUI.get_node_at(game, x, y)
    if node and node.touchpressed then
        node:touchpressed(id, x, y)
        game.dragging = node
        game:move_to_front(node)
    else
        game.dragging = nil
    end
end

function DeckViewUI.handle_touchmoved(game, id, x, y, dx, dy)
    if game.dragging and game.dragging.touchmoved then
        game.dragging:touchmoved(id, x, y, dx, dy)
    end
end

function DeckViewUI.handle_touchreleased(game, id, x, y)
    local released = game.dragging
    if released and released.touchreleased then
        released:touchreleased(id, x, y)
    end
    local start_x = game.touch_start_x or x
    local start_y = game.touch_start_y or y
    local dx = x - start_x
    local dy = y - start_y
    local dist = math.sqrt(dx * dx + dy * dy)
    if released and released._deck_view_card and dist < TAP_THRESHOLD then
        DeckViewUI.toggle_tooltip(game, released)
    elseif released and released._deck_view_card and dist >= TAP_THRESHOLD then
        DeckViewUI.layout(game)
    elseif dist < TAP_THRESHOLD then
        game.active_tooltip_card = nil
    end
    game.dragging = nil
end

function DeckViewUI.update(game, dt)
    if not game then return end
    local target = game._deck_view_hand_panel_open and 1 or 0
    local t = tonumber(game._deck_view_hand_panel_t) or 0
    local speed = math.min(1, 10 * (tonumber(dt) or 0))
    t = t + (target - t) * speed
    if math.abs(t - target) < 0.001 then
        t = target
    end
    game._deck_view_hand_panel_t = t
end

---@return boolean handled
function DeckViewUI.handle_gamepad(game, button)
    if not game or not game._deck_view_open then return false end
    if button == "dpright" or button == "right" then
        game._deck_view_hand_panel_open = true
        return true
    end
    if button == "dpleft" or button == "left" then
        game._deck_view_hand_panel_open = false
        return true
    end
    if button == "back" or (game.is_menu_back and game:is_menu_back(button)) then
        if game._deck_view_hand_panel_open then
            game._deck_view_hand_panel_open = false
            return true
        end
        game:exit_deck_view()
        return true
    end
    if button == "select" or (game.is_menu_activate and game:is_menu_activate(button)) then
        game:exit_deck_view()
        return true
    end
    return false
end

local function center_text_in_rect(text, x, y, w, h)
    local font = love.graphics.getFont()
    local ty = y + math.floor(h * 0.5 - font:getHeight() * 0.5 + 0.5)
    love.graphics.printf(tostring(text or ""), x, ty, w, "center")
end

local function format_hand_mult(mult)
    local raw = tonumber(mult) or 0
    if math.abs(raw) >= 100000 then
        return string.format("%.1e", raw)
    end
    if raw % 1 == 0 then
        return string.format("%.0f", raw)
    end
    return string.format("%.1f", raw)
end

local HAND_PANEL_W = 340
local HAND_PANEL_HEADER_H = 20
local HAND_ROW_H = 18
local HAND_ROW_GAP = 2
local HAND_LEVEL_W = 44
local HAND_COUNT_W = 24
local HAND_CHIP_W = 40
local HAND_MULT_W = 40
local HAND_X_W = 12

function DeckViewUI.draw_hand_level_row(game, x, y, w, hand_name, level, chips, mult, play_count, textDepth, buttonDepth)
    textDepth = tonumber(textDepth) or 0
    buttonDepth = tonumber(buttonDepth) or 0
    local gap = 2
    local inner_pad = 2

    if draw_rect_with_shadow then
        draw_rect_with_shadow(x, y, w, HAND_ROW_H, 4, 0, game.C.GREY, game.C.BLOCK.SHADOW, 2, buttonDepth)
    end

    local inner_x = x + inner_pad
    local inner_y = y + inner_pad
    local inner_h = HAND_ROW_H - inner_pad * 2
    local inner_w = w - inner_pad * 2

    local chips_x = inner_x + inner_w - HAND_COUNT_W - gap - HAND_MULT_W - gap - HAND_X_W - gap - HAND_CHIP_W
    local mult_x = chips_x + HAND_CHIP_W + gap + HAND_X_W + gap
    local count_x = inner_x + inner_w - HAND_COUNT_W
    local name_x = inner_x + HAND_LEVEL_W + gap
    local name_w = math.max(0, chips_x - gap - name_x)

    if draw_rounded_rect then
        if level <= 0 then
            love.graphics.setColor(G.C.WHITE)
        else
            if G.C.HAND_LEVELS and G.C.HAND_LEVELS[level] then
                love.graphics.setColor(G.C.HAND_LEVELS[level])
            else 
                love.graphics.setColor(G.C.HAND_LEVELS[#G.C.HAND_LEVELS])
            end
        end
        draw_rounded_rect(inner_x, inner_y, HAND_LEVEL_W, inner_h, 4, 0, "fill")
        love.graphics.setColor(G.C.CHIPS)
        draw_rounded_rect(chips_x, inner_y, HAND_CHIP_W, inner_h, 4, 0, "fill")
        love.graphics.setColor(G.C.MULT)
        draw_rounded_rect(mult_x, inner_y, HAND_MULT_W, inner_h, 4, 0, "fill")
        love.graphics.setColor(G.C.PANEL)
        draw_rounded_rect(count_x, inner_y, HAND_COUNT_W, inner_h, 4, 0, "fill")
    end

    love.graphics.setFont(G.FONTS.PIXEL.SMALL)
    love.graphics.setColor(G.C.PANEL)
    center_text_in_rect("lvl." .. tostring(level), inner_x - textDepth, inner_y, HAND_LEVEL_W, inner_h)
    love.graphics.setColor(G.C.WHITE)
    center_text_in_rect(hand_name or "", name_x - textDepth, inner_y, name_w, inner_h)
    center_text_in_rect(tostring(chips), chips_x - textDepth, inner_y, HAND_CHIP_W, inner_h)
    love.graphics.setColor(G.C.RED)
    center_text_in_rect("X", chips_x + HAND_CHIP_W + gap - textDepth, inner_y, HAND_X_W, inner_h)
    love.graphics.setColor(G.C.WHITE)
    center_text_in_rect(format_hand_mult(mult), mult_x - textDepth, inner_y, HAND_MULT_W, inner_h)
    love.graphics.setColor(G.C.MONEY)
    center_text_in_rect(tostring(play_count or 0), count_x - textDepth, inner_y, HAND_COUNT_W, inner_h)
end

function DeckViewUI.draw_hand_level_panel(screen, game, textDepth, buttonDepth)
    local panel_t = tonumber(game._deck_view_hand_panel_t) or 0
    if panel_t <= 0 then return end

    local panel_x = math.floor(TOP_W - HAND_PANEL_W * panel_t + 0.5)
    local panel_y = 4
    local panel_h = TOP_H - 8

    love.graphics.setColor(game.C.PANEL)
    love.graphics.rectangle("fill", panel_x, panel_y, HAND_PANEL_W, panel_h, 8, 8)
    love.graphics.setColor(game.C.WHITE)
    love.graphics.rectangle("line", panel_x, panel_y, HAND_PANEL_W, panel_h, 8, 8)

    local pad = 6
    local content_x = panel_x + pad
    local content_w = HAND_PANEL_W - pad * 2
    local row_y = panel_y + pad

    love.graphics.setFont(game.FONTS.PIXEL.SMALL)
    love.graphics.setColor(game.C.WHITE)
    love.graphics.printf("Poker Hands", content_x - textDepth, row_y, content_w, "center")
    row_y = row_y + HAND_PANEL_HEADER_H

    local handlist = game.handlist or {}
    for i, hand_name in ipairs(handlist) do
        if game.is_hand_stats_visible and game:is_hand_stats_visible(i) then
            local level, chips, mult = 1, 0, 0
            if game.get_hand_level_stats then
                level, chips, mult = game:get_hand_level_stats(i)
            end
            local play_count = tonumber(game.hand_play_counts and game.hand_play_counts[i]) or 0
            DeckViewUI.draw_hand_level_row(
                game, content_x, row_y, content_w,
                hand_name, level, chips, mult, play_count,
                textDepth, buttonDepth
            )
            row_y = row_y + HAND_ROW_H + HAND_ROW_GAP
            if row_y + HAND_ROW_H > panel_y + panel_h - pad then
                break
            end
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
end

function DeckViewUI.draw_bottom(game)
    love.graphics.setColor(G.C.PANEL)
    love.graphics.rectangle("fill", 0, 0, SCREEN_W, SCREEN_H)

    local count = game.deck and game.deck:size() or #(game._deck_view_nodes or {})
    love.graphics.setColor(game.C.WHITE)
    love.graphics.setFont(game.FONTS.PIXEL.SMALL)
    love.graphics.printf("Draw pile (" .. tostring(count) .. ")", 0, 4, SCREEN_W, "center")

    local SUIT_COLORS = {
        Hearts = G.C.Hearts or { 0.92, 0.25, 0.28 },
        Diamonds = G.C.Diamonds or { 0.92, 0.25, 0.28 },
        Clubs = G.C.Clubs or { 0.2, 0.2, 0.22 },
        Spades = G.C.Spades or { 0.2, 0.2, 0.22 },
    }

    local rows = game._deck_view_rows or {}
    local active = DeckViewUI.active_suits(rows)
    local m = DeckViewUI._chrome_metrics(#active)
    love.graphics.setFont(game.FONTS.PIXEL.MEDIUM)
    local font_h = love.graphics.getFont():getHeight()
    for row_i, suit in ipairs(active) do
        local row_y = m.header_h + (row_i - 1) * m.row_h
        local sc = SUIT_COLORS[suit]
        love.graphics.setColor(sc[1], sc[2], sc[3], 1)
        --[[ love.graphics.print(
            SUIT_SYMBOLS[suit],
            m.margin_x,
            row_y + math.floor((m.row_h - font_h) * 0.5 + 0.5)
        ) ]]
    end

    love.graphics.setColor(1, 1, 1, 1)
    for _, node in ipairs(game._deck_view_nodes or {}) do
        if node and node.draw then
            node:draw()
        end
    end

    love.graphics.setFont(game.FONTS.PIXEL.SMALL)
    love.graphics.setColor(game.C.WHITE or { 0.65, 0.65, 0.65, 1 })
    local footer = "SELECT / B to close"
    if not game._deck_view_hand_panel_open and (tonumber(game._deck_view_hand_panel_t) or 0) <= 0.01 then
        footer = footer .. "  Right: Hand Levels"
    end
    love.graphics.printf(footer, 0, SCREEN_H - m.footer_h, SCREEN_W, "center")
    love.graphics.setColor(1, 1, 1, 1)
end


local RANKS = {}
local RANK_LABELS = {}
for r = 2, 14 do
    RANKS[#RANKS + 1] = r
    if r <= 10 then
        RANK_LABELS[r] = tostring(r)
    elseif r == 11 then
        RANK_LABELS[r] = "J"
    elseif r == 12 then
        RANK_LABELS[r] = "Q"
    elseif r == 13 then
        RANK_LABELS[r] = "K"
    else
        RANK_LABELS[r] = "A"
    end
end

---@param cards table[]
---@return table<number, integer>
function DeckViewUI.count_ranks(cards)
    local counts = {}
    for _, r in ipairs(RANKS) do
        counts[r] = 0
    end
    for _, card_data in ipairs(cards or {}) do
        local rank = tonumber(card_data and card_data.rank)
        if rank and counts[rank] ~= nil then
            counts[rank] = counts[rank] + 1
        end
    end
    return counts
end

local VOUCHER_CELL_W = 71
local VOUCHER_CELL_H = 95
local VOUCHER_ROW_H = VOUCHER_CELL_H
local VOUCHER_GAP = 2
local DECK_HEADER_H = 84
local DECK_SPRITE_BOX_W = 52
local DECK_SPRITE_BOX_H = 68

local function draw_deck_sprite(game, def, x, y, w, h)
    if not def then return nil end
    if game.ensure_asset_atlas_loaded then
        game:ensure_asset_atlas_loaded("centers")
    end
    local atlas = game.ASSET_ATLAS and game.ASSET_ATLAS.centers
    if not atlas or not atlas.image then return nil end

    local index = tonumber(def.pos) or 0
    local cell_w = tonumber(atlas.px) or 72
    local cell_h = tonumber(atlas.py) or 95
    local iw, ih = atlas.image:getDimensions()
    local cols = math.max(1, math.floor(iw / cell_w))
    local col = index % cols
    local row = math.floor(index / cols)
    local quad = love.graphics.newQuad(col * cell_w, row * cell_h, cell_w, cell_h, iw, ih)

    local scale = math.min(w / cell_w, h / cell_h)
    if scale > 1 then scale = 1 end
    local draw_w = cell_w * scale
    local draw_h = cell_h * scale
    local dx = x + math.floor((w - draw_w) * 0.5 + 0.5)
    local dy = y + math.floor((h - draw_h) * 0.5 + 0.5)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(atlas.image, quad, dx, dy, 0, scale, scale)
    return dx, dy, draw_w, draw_h
end

local function draw_voucher_icon(game, voucher_id, x, y)
    local def = VOUCHER_DEFS and voucher_id and VOUCHER_DEFS[voucher_id]
    local pos = def and tonumber(def.pos)
    if pos and game.ensure_asset_atlas_loaded and game.ASSET_ATLAS and game.ASSET_ATLAS.Voucher then
        game:ensure_asset_atlas_loaded("Voucher")
        local atlas = game.ASSET_ATLAS.Voucher
        if atlas and atlas.image then
            local cell_w = tonumber(atlas.px) or VOUCHER_CELL_W
            local cell_h = tonumber(atlas.py) or VOUCHER_CELL_H
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
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.draw(atlas.image, quad, x, y, 0, 1, 1)
                return true
            end
        end
    end
    love.graphics.setColor(game.C.WHITE)
    love.graphics.setFont(game.FONTS.PIXEL.SMALL)
    local label = (def and def.name) or "?"
    love.graphics.printf(label, x, y + math.floor(VOUCHER_CELL_H * 0.3), VOUCHER_CELL_W, "center")
    return false
end

function DeckViewUI.draw_top(screen, game)
    sysDepth = -love.graphics.getDepth()
    if screen == "right" then
        sysDepth = -sysDepth
    end
    local textDepth = sysDepth * textHeight
    local buttonDepth = sysDepth * buttonHeight
    local signDepth = sysDepth * signHeight
    local margin_x = 8
    local panel_y = DECK_HEADER_H
    local panel_h = TOP_H - panel_y
    local padding = 4
    local deck_width = 100
    local currentY = padding
    -- Deck (and blind header row above the stats panel)
    local deck_id = game.selected_deck_id or game._pending_deck_id or "b_red"
    local deck_def = DECK_DEFS_BY_ID and DECK_DEFS_BY_ID[deck_id]
    if not deck_def and DECK_DEFS then
        deck_def = DECK_DEFS[1]
    end

    love.graphics.setColor(game.C.BLOCK.BACK)
    love.graphics.rectangle("fill", 0, 0, TOP_W, DECK_HEADER_H, 8, 8)

    local deck_sprite_x = margin_x - signDepth
    local deck_sprite_y = math.floor((DECK_HEADER_H - DECK_SPRITE_BOX_H) * 0.5 + 0.5)
    draw_deck_sprite(game, deck_def, deck_sprite_x, deck_sprite_y, DECK_SPRITE_BOX_W, DECK_SPRITE_BOX_H)

    love.graphics.setFont(game.FONTS.PIXEL.SMALL)
    local label_x = margin_x + DECK_SPRITE_BOX_W + padding * 2
    
    love.graphics.setColor(game.C.PANEL)
    draw_rect_with_shadow(label_x - padding, currentY, deck_width, DECK_HEADER_H - 2 * padding, 4, 4, game.C.PANEL, game.C.BLOCK.SHADOW, 2, buttonDepth)
    currentY = currentY + padding

    love.graphics.setColor(game.C.WHITE)
    love.graphics.print(deck_def and deck_def.name or "Deck", label_x + padding - textDepth, currentY)
    currentY = currentY + love.graphics.getFont():getHeight() + padding

    if deck_def and deck_def.description then
        love.graphics.setColor(game.C.PANEL)
        draw_rect_with_shadow(label_x, currentY, deck_width - 2 * padding, DECK_HEADER_H - currentY - 2 * padding, 4, 4, game.C.BLOCK.BACK, game.C.BLOCK.SHADOW, 2, buttonDepth)
        
        love.graphics.setColor(game.C.WHITE)
        love.graphics.printf(deck_def.description, label_x + padding - textDepth, deck_sprite_y + 18, deck_width - padding * 2, "left")
        currentY = currentY + love.graphics.getFont():getHeight() + padding
    end

    -- Stake Information
    currentY = padding
    local stake_label_x = margin_x + deck_width + DECK_SPRITE_BOX_W + 2 * padding
    local stake_width = 120

    draw_rect_with_shadow(stake_label_x, currentY, stake_width, DECK_HEADER_H - 2 * padding, 4, 4, game.C.PANEL, game.C.BLOCK.SHADOW, 2, buttonDepth)
    currentY = currentY + padding

    local stake_id = game.selected_stake_id or game._pending_stake_id or "stake_white"
    local stake_def = STAKE_DEFS_BY_ID and STAKE_DEFS_BY_ID[stake_id]
    if stake_def and stake_def.name then
        love.graphics.setColor(game.C.WHITE)
        love.graphics.print(stake_def.name, stake_label_x + padding * 2 - textDepth, currentY)
        currentY = currentY + love.graphics.getFont():getHeight() + padding
        draw_rect_with_shadow(stake_label_x + padding, currentY, stake_width - 2 * padding, DECK_HEADER_H - currentY - 2 * padding, 4, 4, game.C.BLOCK.BACK, game.C.BLOCK.SHADOW, 2, buttonDepth)
        currentY = currentY + padding

        love.graphics.setColor(game.C.WHITE)
        love.graphics.printf(stake_def.description, stake_label_x + padding * 2 - textDepth, currentY, stake_width - 2 * padding, "left")
        currentY = currentY + love.graphics.getFont():getHeight() + padding
    end

    -- Blind Information
    currentY = padding
    local blind_label_x = stake_label_x + stake_width + padding
    local blind_width = 104
    draw_rect_with_shadow(blind_label_x, currentY, blind_width, DECK_HEADER_H - 2 * padding, 4, 4, game.C.PANEL, game.C.BLOCK.SHADOW, 2, buttonDepth)
    currentY = currentY + padding

    local blind_index = game.current_blind_index or game.selected_blind_index or 1
    local blind_name = (game.get_blind_display_name and game:get_blind_display_name(blind_index)) or "Blind"
    local blind_desc = (game.get_blind_description and game:get_blind_description(blind_index)) or ""

    love.graphics.setColor(game.C.WHITE)
    love.graphics.print(blind_name, blind_label_x + padding * 2 - textDepth, currentY)
    currentY = currentY + love.graphics.getFont():getHeight() + padding
    draw_rect_with_shadow(blind_label_x + padding, currentY, blind_width - 2 * padding, DECK_HEADER_H - currentY - 2 * padding, 4, 4, game.C.BLOCK.BACK, game.C.BLOCK.SHADOW, 2, buttonDepth)
    currentY = currentY + padding

    love.graphics.setColor(game.C.WHITE)
    love.graphics.printf(blind_desc, blind_label_x + padding * 2 - textDepth, currentY, blind_width - 4 * padding, "left")

    love.graphics.setColor(game.C.PANEL)
    love.graphics.rectangle("fill", 0, panel_y, TOP_W, panel_h, 8, 8)

    local inner_w = TOP_W - margin_x * 2
    local vouchers = game.vouchers or {}
    local n_vouchers = #vouchers
    local voucher_row_y = panel_y + 14
    local voucher_icon_y = voucher_row_y + math.floor((VOUCHER_ROW_H - VOUCHER_CELL_H) * 0.5 + 0.5)

    love.graphics.setFont(game.FONTS.PIXEL.SMALL)
    love.graphics.setColor(game.C.WHITE or game.C.GREY)
    love.graphics.print("Vouchers", margin_x - textDepth, panel_y + 2)

    if n_vouchers > 0 then
        local step, _, rel_start = compute_fanned_step(n_vouchers, inner_w, VOUCHER_CELL_W, VOUCHER_GAP)
        local start_x = margin_x + rel_start
        for i, vid in ipairs(vouchers) do
            local x = start_x + (i - 1) * step
            draw_voucher_icon(game, vid, x, voucher_icon_y)
        end
    else
        love.graphics.setColor(game.C.WHITE)
        love.graphics.printf("None", margin_x - textDepth, voucher_row_y + math.floor(VOUCHER_ROW_H * 0.35), inner_w, "center")
    end

    local rank_section_y = voucher_row_y + VOUCHER_ROW_H + 8
    local counts = DeckViewUI.count_ranks(game.deck and game.deck.cards or {})
    local col_w = inner_w / #RANKS
    local label_font = game.FONTS.PIXEL.SMALL
    local count_font = game.FONTS.PIXEL.SMALL
    local label_h = label_font:getHeight()
    local count_h = count_font:getHeight()
    local label_y = rank_section_y
    local count_y = label_y + label_h + 6
    local padding = 4
    
    love.graphics.setFont(label_font)
    for i, rank in ipairs(RANKS) do
        local cx = margin_x + (i - 1) * col_w
        -- Draw rectangle
        if draw_rect_with_shadow then
            draw_rect_with_shadow(cx + padding, label_y - padding, col_w - 2 * padding, count_y - label_y + label_h + 2 * padding, 4, 4, game.C.BLOCK.BACK, game.C.BLOCK.SHADOW, 2, buttonDepth)
        end
        love.graphics.setColor(game.C.WHITE)
        love.graphics.printf(RANK_LABELS[rank], cx - textDepth, label_y, col_w, "center")
    end

    for i, rank in ipairs(RANKS) do
        local cx = margin_x + (i - 1) * col_w
        love.graphics.setColor(game.C.WHITE)
        love.graphics.rectangle("fill", cx + padding, count_y - padding/2, col_w - 2 * padding, label_h + padding, 4, 4)
        
        love.graphics.setColor(game.C.BLACK)
        love.graphics.printf(tostring(counts[rank] or 0), cx - textDepth, count_y, col_w, "center")
    end

    local total = game.deck and game.deck:size() or 0
    love.graphics.setFont(game.FONTS.PIXEL.SMALL)
    love.graphics.setColor(game.C.GREY or game.C.DARK_WHITE)
    love.graphics.setColor(1, 1, 1, 1)

    DeckViewUI.draw_hand_level_panel(screen, game, textDepth, buttonDepth)
end

function DeckViewUI.draw_tooltips(game)
    for _, node in ipairs(game._deck_view_nodes or {}) do
        if node and node.draw_tooltip_overlay then
            node:draw_tooltip_overlay()
        end
    end
end

return DeckViewUI
