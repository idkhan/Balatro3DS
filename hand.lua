---@class Hand
Hand = Object:extend()

local SCREEN_W = 320
local SCREEN_H = 240
local CARD_W = 72
local CARD_H = 95
-- Gradual scaling: scale = min(1, CARDS_AT_FULL_SCALE / n), clamped to MIN_HAND_SCALE
local CARDS_AT_FULL_SCALE = 6
local MIN_HAND_SCALE = 1
local FAN_ANGLE = 0.08
local FAN_DROP = 8
local OFFSCREEN_START_X = SCREEN_W + 0
local OFFSCREEN_START_Y = -80

local MAX_SELECTED = 5
local MAX_HAND_SIZE = 8
local DISCARD_ANIM_DURATION = 0.35
local DRAW_DELAY = 0.2

function Hand:init(game)
    self.game = game or G
    self.cards = {}
    self.card_nodes = {}
    self.selected = {}
    self._draw_queue = {}
    self._draw_timer = 0
end

function Hand:add_card(card_data)
    if not card_data or not self.game then return nil end
    if #self.cards >= MAX_HAND_SIZE then return nil end
    table.insert(self.cards, card_data)
    local node = Card(0, 0, nil, nil, card_data, nil, { face_up = true })
    self.game:add(node)
    table.insert(self.card_nodes, node)
    self:layout(false)
    -- New card animates in from off-screen; existing cards interpolate to new T
    local new_node = self.card_nodes[#self.card_nodes]
    new_node.VT.x = OFFSCREEN_START_X
    new_node.VT.y = OFFSCREEN_START_Y
    new_node.VT.r = 0
    new_node.VT.scale = new_node.T.scale
    return node
end

---@param update_visual boolean|nil If true or omitted, VT is set to match T (instant). If false, only T is updated so cards interpolate to new positions.
---@param skip_vt_for_last boolean|nil If true, VT is not set for the last card (so it can animate in from off-screen).
function Hand:layout(update_visual, skip_vt_for_last)
    local nodes = self.card_nodes
    if #nodes == 0 then return end
    if update_visual == nil then update_visual = true end
    if skip_vt_for_last == nil then skip_vt_for_last = false end

    local n = #nodes
    local scale = math.max(MIN_HAND_SCALE, math.min(1, CARDS_AT_FULL_SCALE / n))
    local card_w = CARD_W * scale
    local card_h = CARD_H * scale

    local step = (SCREEN_W - card_w) / math.max(1, n - 1)
    local total_w = n == 1 and card_w or (card_w + (n - 1) * step)
    local start_x = (SCREEN_W - total_w) * 0.5
    local y = SCREEN_H - card_h - 20

    local half = (n + 1) * 0.5
    local angle_step = n > 1 and (FAN_ANGLE / (n - 1) * 2) or 0
    local max_dist = n > 1 and (n - 1) * 0.5 or 0

    for i, node in ipairs(nodes) do
        local x = start_x + (i - 1) * step
        local r = (i - half) * angle_step
        local dist_from_center = math.abs(i - half)
        local t = max_dist > 0 and (dist_from_center / max_dist) or 0
        local y_drop = FAN_DROP * (t * t)
        local card_y = y + y_drop
        node.T.x = x
        node.T.y = card_y
        node.T.r = r
        node.T.scale = scale
        local set_vt = update_visual and not (skip_vt_for_last and i == n)
        if set_vt then
            node.VT.x = x
            node.VT.y = card_y
            node.VT.r = r
            node.VT.scale = scale
        end
    end
end

function Hand:clear()
    for _, node in ipairs(self.card_nodes) do
        self.game:remove(node)
    end
    self.cards = {}
    self.card_nodes = {}
    self.selected = {}
    self._draw_queue = {}
    self._draw_timer = 0
end

function Hand:is_selected(node)
    for _, n in ipairs(self.selected) do
        if n == node then return true end
    end
    return false
end

function Hand:toggle_selection(node)
    if not node or not self.game then return end
    for i, n in ipairs(self.selected) do
        if n == node then
            node.selected = false
            table.remove(self.selected, i)
            if self.game.move_selected_hand_cards_to_front then self.game:move_selected_hand_cards_to_front() end
            return
        end
    end
    if #self.selected >= MAX_SELECTED then return end
    node.selected = true
    table.insert(self.selected, node)
    if self.game.move_selected_hand_cards_to_front then self.game:move_selected_hand_cards_to_front() end
end

function Hand:has_selection()
    return #self.selected > 0
end

function Hand:discard_selected()
    if #self.selected == 0 or not self.game then return end
    local selected_set = {}
    for _, n in ipairs(self.selected) do selected_set[n] = true end
    local new_cards, new_nodes = {}, {}
    for i, node in ipairs(self.card_nodes) do
        if not selected_set[node] then
            table.insert(new_cards, self.cards[i])
            table.insert(new_nodes, node)
        end
    end
    self.cards = new_cards
    self.card_nodes = new_nodes
    local t = self.game.discard_timer or 0
    for _, node in ipairs(self.selected) do
        node.selected = false
        node.T.x = -120
        node.T.y = -120
        table.insert(self.game.pending_discard, { node = node, remove_after = t + DISCARD_ANIM_DURATION })
    end
    self.selected = {}
    self:layout(false)
    if self.game.restore_hand_draw_order then
        self.game:restore_hand_draw_order()
    end
    self:fill_from_deck()
end

function Hand:fill_from_deck()
    local deck = self.game and self.game.deck
    if not deck then return end
    while #self.cards + #self._draw_queue < MAX_HAND_SIZE and not deck:empty() do
        local card = deck:draw()
        if card then
            if #self._draw_queue == 0 and #self.cards == 0 then
                self:add_card(card)
            else
                table.insert(self._draw_queue, card)
            end
        end
    end
end

function Hand:update(dt)
    if #self._draw_queue == 0 then return end
    self._draw_timer = self._draw_timer + dt
    if self._draw_timer >= DRAW_DELAY then
        self._draw_timer = 0
        local card = table.remove(self._draw_queue, 1)
        if card then self:add_card(card) end
    end
end

function Hand:size()
    return #self.cards
end

function Hand:is_full()
    return #self.cards >= MAX_HAND_SIZE
end

local SUIT_ORDER = { Hearts = 1, Clubs = 2, Diamonds = 3, Spades = 4 }
-- Order: A, K, Q, J, 10, 9, 8, 7, 6, 5, 4, 3, 2 (Ace first, then descending)
local function rank_sort_key(rank)
    return 14 - (rank or 2)
end

function Hand:sort_by_rank()
    if #self.cards == 0 then return end
    local pairs = {}
    for i = 1, #self.cards do
        table.insert(pairs, { card = self.cards[i], node = self.card_nodes[i] })
    end
    table.sort(pairs, function(a, b)
        local ra, rb = rank_sort_key(a.card.rank), rank_sort_key(b.card.rank)
        if ra ~= rb then return ra < rb end
        return (SUIT_ORDER[a.card.suit] or 0) < (SUIT_ORDER[b.card.suit] or 0)
    end)
    self.cards = {}
    self.card_nodes = {}
    for _, p in ipairs(pairs) do
        table.insert(self.cards, p.card)
        table.insert(self.card_nodes, p.node)
    end
    self:layout(false)
    if self.game and self.game.restore_hand_draw_order then
        self.game:restore_hand_draw_order()
    end
end

function Hand:sort_by_suit()
    if #self.cards == 0 then return end
    local pairs = {}
    for i = 1, #self.cards do
        table.insert(pairs, { card = self.cards[i], node = self.card_nodes[i] })
    end
    table.sort(pairs, function(a, b)
        local sa, sb = SUIT_ORDER[a.card.suit] or 0, SUIT_ORDER[b.card.suit] or 0
        if sa ~= sb then return sa < sb end
        return rank_sort_key(a.card.rank) < rank_sort_key(b.card.rank)
    end)
    self.cards = {}
    self.card_nodes = {}
    for _, p in ipairs(pairs) do
        table.insert(self.cards, p.card)
        table.insert(self.card_nodes, p.node)
    end
    self:layout(false)
    if self.game and self.game.restore_hand_draw_order then
        self.game:restore_hand_draw_order()
    end
end
