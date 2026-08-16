--- Bottom-screen overlay: remaining draw-pile cards as interactable Card nodes (one row per non-empty suit).
local DeckViewUI = {}
local NumberFormat = require("number_format")
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

--- Every playing card in the run, tagged with whether it is still in the draw pile.
---
--- The deck view used to build from the draw pile alone, so a card you had just enhanced
--- vanished from it. The reference always lists the whole deck and greys what is no longer
--- drawable (`UI_definitions.lua:3260-3266`), which is both tabs' shared behaviour: the
--- Remaining tab greys, the Full Deck tab does not.
---@param game table
---@return table[] entries `{ data = card_data, in_draw = boolean }`
function DeckViewUI.collect_run_cards(game)
    local entries = {}
    local deck = game and game.deck
    for _, c in ipairs((deck and deck.cards) or {}) do
        entries[#entries + 1] = { data = c, in_draw = true }
    end
    for _, c in ipairs((deck and deck.discard_pile) or {}) do
        entries[#entries + 1] = { data = c, in_draw = false }
    end
    -- Cards sitting in the player's hand are out of the draw pile but still in the deck.
    for _, c in ipairs((game and game.hand and game.hand.cards) or {}) do
        entries[#entries + 1] = { data = c, in_draw = false }
    end
    return entries
end

--- Group tagged entries by suit, ranked low to high, mirroring `group_by_suit`.
---@param entries table[]
---@return table<string, table[]>
function DeckViewUI.group_entries_by_suit(entries)
    local by_suit = {}
    for _, suit in ipairs(SUITS) do
        by_suit[suit] = {}
    end
    for _, entry in ipairs(entries or {}) do
        local suit = entry and entry.data and entry.data.suit
        if suit and by_suit[suit] then
            by_suit[suit][#by_suit[suit] + 1] = entry
        end
    end
    for _, suit in ipairs(SUITS) do
        table.sort(by_suit[suit], function(a, b)
            local ra, rb = tonumber(a.data.rank) or 0, tonumber(b.data.rank) or 0
            if ra ~= rb then return ra < rb end
            -- Stable within a rank: drawable copies first, so the gaps read left to right.
            return (a.in_draw and 1 or 0) > (b.in_draw and 1 or 0)
        end)
    end
    return by_suit
end

---@param game table
---@return string "remaining" | "full"
function DeckViewUI.mode(game)
    return game and game._deck_view_mode == "full" and "full" or "remaining"
end

---@param game table
---@return string "deck" | "vouchers"
function DeckViewUI.page(game)
    return game and game._deck_view_page == "vouchers" and "vouchers" or "deck"
end

--- Redeemed vouchers, in the order they were taken, with their catalog text.
---
--- Once bought, a voucher drew as a bare sprite on the top screen with no way to read it.
--- The reference keeps a Vouchers tab on its run-info screen (`UI_definitions.lua:3426`,
--- listed alongside poker hands and blinds at `:3128-3149`) — this is the port's equivalent,
--- on the screen that already carries the run's reference material.
---@param game table
---@return table[] `{ id, name, description }`
function DeckViewUI.owned_vouchers(game)
    local out = {}
    local seen = {}
    local function add(id)
        if type(id) ~= "string" or id == "" or seen[id] then return end
        local def = VOUCHER_DEFS and VOUCHER_DEFS[id]
        if type(def) ~= "table" then return end
        seen[id] = true
        out[#out + 1] = { id = id, name = def.name or id, description = def.description or "" }
    end
    local vs = (game and game.vouchers) or {}
    -- Both shapes are in use: an ordered list, and a set keyed by id.
    for _, id in ipairs(vs) do add(id) end
    local keys = {}
    for id, flag in pairs(vs) do
        if flag == true and type(id) == "string" then keys[#keys + 1] = id end
    end
    table.sort(keys)
    for _, id in ipairs(keys) do add(id) end
    return out
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

    local by_suit = DeckViewUI.group_entries_by_suit(DeckViewUI.collect_run_cards(game))
    for _, suit in ipairs(SUITS) do
        for _, entry in ipairs(by_suit[suit]) do
            local copy = Deck.copy_card_data(entry.data)
            if copy and game.ensure_card_uid then
                game:ensure_card_uid(copy)
            end
            local node = Card(0, 0, CARD_W, CARD_H, copy, nil, { face_up = true })
            node._deck_view_card = true
            node._deck_view_in_draw = entry.in_draw and true or false
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

--- Point-in-rect without depending on `Game`, so the header controls can be hit-tested from
--- a test as well as from a touch.
local function in_rect(r, x, y)
    return type(r) == "table" and x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
end

--- Flip between Remaining and Full Deck.
---@param game table
function DeckViewUI.toggle_mode(game)
    game._deck_view_mode = DeckViewUI.mode(game) == "full" and "remaining" or "full"
    Sfx.play("cardSlide1")
end

--- Swap the header between the suit/face tallies and the per-rank counts.
---@param game table
function DeckViewUI.toggle_tally_view(game)
    game._deck_view_show_ranks = not game._deck_view_show_ranks
    Sfx.play("paper1")
end

--- Header controls, checked before the cards so a tap on the strip never grabs a card behind
--- it. Returns true when the press was consumed.
---@return boolean
function DeckViewUI.handle_header_touch(game, x, y)
    if in_rect(game._deck_view_page_rect, x, y) then
        game._deck_view_page = DeckViewUI.page(game) == "vouchers" and "deck" or "vouchers"
        Sfx.play("cardSlide1")
        return true
    end
    -- The deck-only controls are not present on the voucher page.
    if DeckViewUI.page(game) == "vouchers" then return false end
    if in_rect(game._deck_view_mode_rect, x, y) then
        DeckViewUI.toggle_mode(game)
        return true
    end
    if in_rect(game._deck_view_tally_rect, x, y) then
        DeckViewUI.toggle_tally_view(game)
        return true
    end
    return false
end

function DeckViewUI.handle_touchpressed(game, id, x, y)
    if DeckViewUI.handle_header_touch(game, x, y) then
        game.dragging = nil
        return
    end
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
        -- Only on the transition, or holding right would retrigger the slide cue.
        if not game._deck_view_hand_panel_open then Sfx.play("paper1") end
        game._deck_view_hand_panel_open = true
        return true
    end
    if button == "dpleft" or button == "left" then
        if game._deck_view_hand_panel_open then Sfx.play("cancel") end
        game._deck_view_hand_panel_open = false
        return true
    end
    if button == "back" or (game.is_menu_back and game:is_menu_back(button)) then
        Sfx.play("cancel")
        if game._deck_view_hand_panel_open then
            game._deck_view_hand_panel_open = false
            return true
        end
        game:exit_deck_view()
        return true
    end
    if button == "select" or (game.is_menu_activate and game:is_menu_activate(button)) then
        Sfx.play("cancel")
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
    return NumberFormat.format(tonumber(mult) or 0)
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
    center_text_in_rect(NumberFormat.format(tonumber(chips) or 0), chips_x - textDepth, inner_y, HAND_CHIP_W, inner_h)
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

--- Header strip: the mode toggle on the left, the tally chips across the rest. Tapping the
--- chips swaps them for the per-rank counts and back, which is how the rank column survives
--- on a 320 px screen without taking a permanent row.
---@param game table
local function draw_deck_view_header(game)
    local mode = DeckViewUI.mode(game)
    local cards = DeckViewUI.tally_source(game)

    love.graphics.setFont(game.FONTS.PIXEL.SMALL)
    local toggle_w, toggle_h = 74, 13
    game._deck_view_mode_rect = { x = 2, y = 1, w = toggle_w, h = toggle_h }
    if _G.draw_button_with_shadow then
        draw_button_with_shadow(2, 1, toggle_w, toggle_h, 3, 3,
            mode == "full" and game.C.BOOSTER or game.C.BLUE, game.C.BLOCK.SHADOW, 1)
    end
    love.graphics.setColor(game.C.WHITE)
    love.graphics.printf(mode == "full" and "Full Deck" or "Remaining", 2, 3, toggle_w, "center")

    -- The rest of the strip is the tally readout, and is itself the tap target.
    local strip_x = toggle_w + 6
    local strip_w = SCREEN_W - strip_x - 2
    game._deck_view_tally_rect = { x = strip_x, y = 1, w = strip_w, h = toggle_h }

    love.graphics.setColor(game.C.DARK_WHITE or game.C.GREY)
    if game._deck_view_show_ranks then
        local counts = DeckViewUI.count_ranks(cards)
        local n = #RANKS
        local cell = strip_w / n
        for i, r in ipairs(RANKS) do
            local cx = strip_x + (i - 1) * cell
            love.graphics.setColor(game.C.GREY)
            love.graphics.printf(RANK_LABELS[r] or "?", cx, 1, cell, "center")
            love.graphics.setColor((counts[r] or 0) > 0 and game.C.WHITE or game.C.GREY)
            love.graphics.printf(tostring(counts[r] or 0), cx, 8, cell, "center")
        end
    else
        local t = DeckViewUI.count_tallies(cards)
        local cells = {
            { "H " .. t.suits.Hearts, game.C.RED },
            { "C " .. t.suits.Clubs, game.C.WHITE },
            { "D " .. t.suits.Diamonds, game.C.RED },
            { "S " .. t.suits.Spades, game.C.WHITE },
            { "Face " .. t.face, game.C.DARK_WHITE or game.C.GREY },
            { "Ace " .. t.ace, game.C.DARK_WHITE or game.C.GREY },
            { "Num " .. t.numbered, game.C.DARK_WHITE or game.C.GREY },
        }
        local cell = strip_w / #cells
        for i, entry in ipairs(cells) do
            love.graphics.setColor(entry[2])
            love.graphics.printf(entry[1], strip_x + (i - 1) * cell, 3, cell, "center")
        end
    end
end

function DeckViewUI.draw_bottom(game)
    love.graphics.setColor(G.C.PANEL)
    love.graphics.rectangle("fill", 0, 0, SCREEN_W, SCREEN_H)

    local on_vouchers = DeckViewUI.page(game) == "vouchers"
    -- Greying is what distinguishes the two deck modes; both list every card in the run.
    local grey_spent = DeckViewUI.mode(game) == "remaining"
    for _, node in ipairs(game._deck_view_nodes or {}) do
        if node then
            node.greyed = (not on_vouchers) and grey_spent and node._deck_view_in_draw == false or nil
            if node.states then node.states.visible = not on_vouchers end
        end
    end

    if on_vouchers then
        DeckViewUI.draw_voucher_page(game)
        return
    end

    draw_deck_view_header(game)

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

    DeckViewUI.draw_footer(game, m.footer_h)
    love.graphics.setColor(1, 1, 1, 1)
end

--- Footer: the page switch on the left, the close/panel hints filling the rest.
---@param game table
---@param footer_h number
function DeckViewUI.draw_footer(game, footer_h)
    local y = SCREEN_H - footer_h
    love.graphics.setFont(game.FONTS.PIXEL.SMALL)

    local on_vouchers = DeckViewUI.page(game) == "vouchers"
    local sw_w, sw_h = 74, 13
    game._deck_view_page_rect = { x = 2, y = y + 1, w = sw_w, h = sw_h }
    if _G.draw_button_with_shadow then
        draw_button_with_shadow(2, y + 1, sw_w, sw_h, 3, 3,
            on_vouchers and game.C.BLUE or game.C.VOUCHER, game.C.BLOCK.SHADOW, 1)
    end
    love.graphics.setColor(game.C.WHITE)
    local n = #DeckViewUI.owned_vouchers(game)
    love.graphics.printf(on_vouchers and "Deck" or ("Vouchers " .. n), 2, y + 3, sw_w, "center")

    love.graphics.setColor(game.C.WHITE or { 0.65, 0.65, 0.65, 1 })
    local footer = "SELECT / B to close"
    if not on_vouchers and not game._deck_view_hand_panel_open
        and (tonumber(game._deck_view_hand_panel_t) or 0) <= 0.01 then
        footer = footer .. "  Right: Hand Levels"
    end
    love.graphics.printf(footer, sw_w + 6, y + 3, SCREEN_W - sw_w - 8, "center")
end

--- Owned vouchers as a readable list. Names and full descriptions, because the point of the
--- page is that a redeemed voucher is otherwise unreadable.
---@param game table
function DeckViewUI.draw_voucher_page(game)
    local vouchers = DeckViewUI.owned_vouchers(game)
    local m = DeckViewUI._chrome_metrics(0)

    love.graphics.setFont(game.FONTS.PIXEL.SMALL)
    love.graphics.setColor(game.C.WHITE)
    love.graphics.printf("Redeemed Vouchers", 0, 3, SCREEN_W, "center")

    if #vouchers == 0 then
        love.graphics.setColor(game.C.DARK_WHITE or game.C.GREY)
        love.graphics.printf("None redeemed yet.", 0, 100, SCREEN_W, "center")
        DeckViewUI.draw_footer(game, m.footer_h)
        love.graphics.setColor(1, 1, 1, 1)
        return
    end

    -- Two columns: eight rows fit the 208 px between the header and the footer, and a run
    -- can hold more vouchers than one column would take.
    local top_y = 18
    local avail_h = SCREEN_H - top_y - m.footer_h - 2
    local per_col = 8
    local row_h = math.floor(avail_h / per_col)
    local col_w = math.floor((SCREEN_W - 6) / 2)
    for i, v in ipairs(vouchers) do
        local col = (i - 1) >= per_col and 1 or 0
        local row = (i - 1) % per_col
        local x = 2 + col * (col_w + 2)
        local y = top_y + row * row_h
        if _G.draw_rect_with_shadow then
            draw_rect_with_shadow(x, y, col_w, row_h - 2, 3, 1,
                game.C.BLOCK.BACK, game.C.BLOCK.SHADOW, 1)
        end
        love.graphics.setColor(game.C.VOUCHER or game.C.ORANGE)
        love.graphics.printf(v.name, x + 3, y + 1, col_w - 6, "left")
        love.graphics.setColor(game.C.DARK_WHITE or game.C.GREY)
        love.graphics.printf(v.description, x + 3, y + 9, col_w - 6, "left")
    end

    DeckViewUI.draw_footer(game, m.footer_h)
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

--- Descriptions of every stake below `stake_id`, strongest first.
---
--- Stakes stack: a Blue Stake run is also running Red, Green and Black. The reference lists
--- the inherited ones under "Also applied:" (`UI_definitions.lua:3181-3204`). White is
--- skipped because "No modifiers." is not a modifier.
---@param stake_id string
---@return string[]
function DeckViewUI.inherited_stake_descriptions(stake_id)
    local out = {}
    local current = STAKE_DEFS_BY_ID and STAKE_DEFS_BY_ID[stake_id]
    local current_order = tonumber(current and current.order)
    if not current_order then return out end
    for _, def in ipairs(STAKE_DEFS or {}) do
        local order = tonumber(def.order)
        if order and order < current_order and def.id ~= "stake_white"
            and type(def.description) == "string" and def.description ~= "" then
            out[#out + 1] = def.description
        end
    end
    -- Nearest stake first: those are the ones the player just stepped up from.
    for i = 1, math.floor(#out / 2) do
        out[i], out[#out - i + 1] = out[#out - i + 1], out[i]
    end
    return out
end

--- Suit, face, numbered and ace counts over a set of cards. The reference shows all of these
--- beside the rank column (`UI_definitions.lua:3390-3420`); the port counted ranks only, so
--- there was nothing to plan a flush against. Stone cards are excluded from every tally
--- because they have no rank or suit (`UI_definitions.lua:3363`).
---@param cards table[]
---@return table
function DeckViewUI.count_tallies(cards)
    local out = {
        suits = { Hearts = 0, Clubs = 0, Diamonds = 0, Spades = 0 },
        face = 0, numbered = 0, ace = 0, total = 0,
    }
    for _, card_data in ipairs(cards or {}) do
        local enh = card_data and card_data.enhancement
        if card_data and enh ~= "stone" then
            local suit = card_data.suit
            if suit and out.suits[suit] ~= nil then
                out.suits[suit] = out.suits[suit] + 1
            end
            local rank = tonumber(card_data.rank)
            if rank then
                if rank >= 11 and rank <= 13 then
                    out.face = out.face + 1
                elseif rank == 14 then
                    out.ace = out.ace + 1
                elseif rank >= 2 then
                    out.numbered = out.numbered + 1
                end
            end
            out.total = out.total + 1
        end
    end
    return out
end

--- Card data the tallies and rank counts should describe: the draw pile in Remaining mode,
--- every card in the run in Full Deck mode.
---@param game table
---@return table[]
function DeckViewUI.tally_source(game)
    local out = {}
    for _, entry in ipairs(DeckViewUI.collect_run_cards(game)) do
        if DeckViewUI.mode(game) == "full" or entry.in_draw then
            out[#out + 1] = entry.data
        end
    end
    return out
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

        -- Stakes are cumulative, so the run also carries every lower stake's modifier. The
        -- reference lists them under an "Also applied:" heading (`UI_definitions.lua:3181-3204`);
        -- showing only the top stake's own line hid most of what the run is actually running.
        local inherited = DeckViewUI.inherited_stake_descriptions(stake_id)
        if #inherited > 0 then
            love.graphics.setColor(game.C.GREY)
            love.graphics.printf("Also applied:", stake_label_x + padding * 2 - textDepth, currentY,
                stake_width - 2 * padding, "left")
            currentY = currentY + love.graphics.getFont():getHeight()
            love.graphics.setColor(game.C.DARK_WHITE or game.C.GREY)
            for _, line in ipairs(inherited) do
                love.graphics.printf(line, stake_label_x + padding * 2 - textDepth, currentY,
                    stake_width - 2 * padding, "left")
                currentY = currentY + love.graphics.getFont():getHeight()
            end
        end
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
