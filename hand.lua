---@class Hand
Hand = Object:extend()

local SCREEN_W = 320
local SCREEN_H = 240
local CARD_W = 72
local CARD_H = 95
-- Gradual scaling: scale = min(1, CARDS_AT_FULL_SCALE / n), clamped to MIN_HAND_SCALE
local CARDS_AT_FULL_SCALE = 6
local MIN_HAND_SCALE = 1
local FAN_ANGLE = 0 --0.08
local FAN_DROP = 8
local OFFSCREEN_START_X = SCREEN_W + 0
local OFFSCREEN_START_Y = -80

local MAX_SELECTED = 5
local MAX_HAND_SIZE = 8
local DISCARD_ANIM_DURATION = 0.35
local DRAW_DELAY = 0.2

-- Play / scoring sequence (bottom screen)
local PLAY_MOVE_MIN_TIME = 0.35
local PLAY_MOVE_MAX_TIME = 0.85
local PLAY_MOVE_ARRIVE_EPS = 2.5
local PLAY_TRIGGER_INTERVAL = 0.38
local PLAY_SHAKE_DURATION = 0.22
local PLAY_AFTER_SCORE_PAUSE = 0.28
local PLAY_CENTER_SCALE = 1

local function hand_size_limit()
    if G and G.get_effective_hand_size_limit then
        return math.max(1, tonumber(G:get_effective_hand_size_limit()) or MAX_HAND_SIZE)
    end
    return MAX_HAND_SIZE
end

function Hand:init(game)
    self.game = game or G
    self.cards = {}
    self.card_nodes = {}
    self.selected = {}
    self._draw_queue = {}
    self._draw_timer = 0
    self.sort_mode = "rank"
    self._play_sequence = nil
end

function Hand:play_sfx_trigger()
    Sfx.play("resources/sounds/generic1.ogg")
    Sfx.play_chips()
end

function Hand:is_scoring_active()
    return self._play_sequence ~= nil
end

---@param bypass_limit boolean|nil if true, allow one card over normal hand cap (e.g. Certificate)
function Hand:add_card(card_data, bypass_limit)
    if not card_data or not self.game then return nil end
    if self.game and self.game.ensure_card_uid then
        self.game:ensure_card_uid(card_data)
    end
    local limit = hand_size_limit()
    if self.game and self.game.get_active_boss_blind_id and self.game:get_active_boss_blind_id() == "bl_serpent" then
        limit = math.max(limit, 999)
    end
    if not bypass_limit and #self.cards >= limit then return nil end
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
    Sfx.play_random("resources/sounds/cardSlide1.ogg", "resources/sounds/cardSlide2.ogg")

    if self.sort_mode == "rank" then
        self:sort_by_rank(new_node)
    elseif self.sort_mode == "suit" then
        self:sort_by_suit(new_node)
    end

    if self.game and self.game.boss_on_card_drawn then
        self.game:boss_on_card_drawn(new_node)
    end

    return node
end

--- Fan geometry for hit-testing and reorder (same math as layout).
function Hand:_layout_metrics()
    local nodes = self.card_nodes
    local n = #nodes
    if n == 0 then return nil end
    local scale = math.max(MIN_HAND_SCALE, math.min(1, CARDS_AT_FULL_SCALE / n))
    local card_w = CARD_W * scale
    local card_h = CARD_H * scale
    local step = (SCREEN_W - card_w) / math.max(1, n - 1)
    local total_w = n == 1 and card_w or (card_w + (n - 1) * step)
    local start_x = (SCREEN_W - total_w) * 0.5
    local y = SCREEN_H - card_h - 20
    return {
        n = n,
        scale = scale,
        card_w = card_w,
        card_h = card_h,
        step = step,
        start_x = start_x,
        y = y,
    }
end

--- Nearest hand slot index (1..n) for a screen x (center of card column).
function Hand:slot_index_from_screen_x(screen_x)
    local m = self:_layout_metrics()
    if not m then return 1 end
    if m.n <= 1 then return 1 end
    local best_i, best_d = 1, 1e9
    for i = 1, m.n do
        local cx = m.start_x + (i - 1) * m.step + m.card_w / 2
        local d = math.abs(screen_x - cx)
        if d < best_d then
            best_d = d
            best_i = i
        end
    end
    return best_i
end

--- Move card node to the slot under release_x (hand order). Returns true if order changed.
function Hand:try_reorder_card_after_drag(node, release_x)
    if self._play_sequence or not node then return false end
    local from_idx
    for i, n in ipairs(self.card_nodes) do
        if n == node then
            from_idx = i
            break
        end
    end
    if not from_idx then return false end

    local to_idx = self:slot_index_from_screen_x(release_x)
    if to_idx == from_idx then return false end

    local card = table.remove(self.cards, from_idx)
    local inode = table.remove(self.card_nodes, from_idx)
    table.insert(self.cards, to_idx, card)
    table.insert(self.card_nodes, to_idx, inode)

    self:layout(false)
    if self.game and self.game.restore_hand_draw_order then
        self.game:restore_hand_draw_order()
    end
    if self.game and self.game.move_selected_hand_cards_to_front then
        self.game:move_selected_hand_cards_to_front()
    end
    Sfx.play_random("resources/sounds/cardSlide1.ogg", "resources/sounds/cardSlide2.ogg")
    return true
end
---@param update_visual boolean|nil If true or omitted, VT is set to match T (instant). If false, only T is updated so cards interpolate to new positions.
---@param skip_vt_node Card|nil If set, that node's VT is left unchanged (e.g. animating in from off-screen).
function Hand:layout(update_visual, skip_vt_node)
    local nodes = self.card_nodes
    if #nodes == 0 then return end
    if update_visual == nil then update_visual = true end

    if self.game and self.game.STATE == self.game.STATES.OPEN_BOOSTER and self.game.booster_session and self.game.booster_session.hand_for_tarot then
        self:layout_booster_pack_row(update_visual, skip_vt_node)
        return
    end

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
        local set_vt = update_visual and (skip_vt_node == nil or node ~= skip_vt_node)
        if set_vt then
            node.VT.x = x
            node.VT.y = card_y
            node.VT.r = r
            node.VT.scale = scale
        end
    end
end

--- Compact fan at the top of the bottom screen while resolving Arcana/Spectral boosters (pack choices stay below).
function Hand:layout_booster_pack_row(update_visual, skip_vt_node)
    local nodes = self.card_nodes
    if #nodes == 0 then return end
    if update_visual == nil then update_visual = true end

    local n = #nodes
    local scale = math.max(MIN_HAND_SCALE, math.min(1, CARDS_AT_FULL_SCALE / math.max(n, 1)))
    local card_w = CARD_W * scale
    local card_h = CARD_H * scale

    local step = (SCREEN_W - card_w) / math.max(1, n - 1)
    local total_w = n == 1 and card_w or (card_w + (n - 1) * step)
    local start_x = (SCREEN_W - total_w) * 0.5
    local y = 6

    local half = (n + 1) * 0.5
    local angle_step = n > 1 and (FAN_ANGLE / (n - 1) * 2) or 0
    local max_dist = n > 1 and (n - 1) * 0.5 or 0

    for i, node in ipairs(nodes) do
        local x = start_x + (i - 1) * step
        local r = (i - half) * angle_step
        local dist_from_center = math.abs(i - half)
        local t = max_dist > 0 and (dist_from_center / max_dist) or 0
        local y_drop = (FAN_DROP * 0.35) * (t * t)
        local card_y = y + y_drop
        node.T.x = x
        node.T.y = card_y
        node.T.r = r
        node.T.scale = scale
        local set_vt = update_visual and (skip_vt_node == nil or node ~= skip_vt_node)
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
    self._play_sequence = nil
end

--- Push every card still in the hand (and queued draws) to the deck discard pile, then clear hand nodes. Used when a blind is beaten.
function Hand:send_entire_hand_to_discard_pile()
    local deck = self.game and self.game.deck
    if not deck or not deck.push_discard then
        self:clear()
        return
    end
    for _, c in ipairs(self._draw_queue or {}) do
        deck:push_discard(c)
    end
    for i = 1, #self.cards do
        deck:push_discard(self.cards[i])
    end
    self:clear()
end

--- Selected cards in left-to-right hand order (card_nodes index), not toggle order.
function Hand:ordered_selected_nodes()
    local sel = {}
    for _, n in ipairs(self.selected) do
        sel[n] = true
    end
    local out = {}
    for _, node in ipairs(self.card_nodes) do
        if sel[node] then
            table.insert(out, node)
        end
    end
    return out
end

function Hand:is_selected(node)
    for _, n in ipairs(self.selected) do
        if n == node then return true end
    end
    return false
end

function Hand:toggle_selection(node)
    if self._play_sequence then return end
    if not node or not self.game then return end
    for i, n in ipairs(self.selected) do
        if n == node then
            if self.game and self.game.get_active_boss_blind_id and self.game:get_active_boss_blind_id() == "bl_final_bell" then
                local forced_uid = self.game.boss_runtime and self.game.boss_runtime.forced_card_uid
                local uid = node.card_data and node.card_data.uid
                if forced_uid ~= nil and uid == forced_uid then
                    return
                end
            end
            node.selected = false
            Sfx.play("resources/sounds/card3.ogg")
            table.remove(self.selected, i)
            if self.game then self.game.active_tooltip_card = nil end
            if self.game.move_selected_hand_cards_to_front then self.game:move_selected_hand_cards_to_front() end
            self:calculate_play()
            return
        end
    end
    if #self.selected >= MAX_SELECTED then return end
    node.selected = true
    Sfx.play("resources/sounds/card1.ogg")
    table.insert(self.selected, node)
    if self.game then
        self.game.active_tooltip_card = node
        self.game.active_tooltip_joker = nil
    end
    if self.game.move_selected_hand_cards_to_front then self.game:move_selected_hand_cards_to_front() end
    self:calculate_play()
end

function Hand:has_selection()
    return #self.selected > 0
end

function Hand:clear_selection()
    for _, n in ipairs(self.selected) do
        if n then n.selected = false end
    end
    self.selected = {}
    if self.game then
        self.game.active_tooltip_card = nil
    end
    if self.game and self.game.move_selected_hand_cards_to_front then
        self.game:move_selected_hand_cards_to_front()
    end
    self:calculate_play()
end

function Hand:discard_selected()
    if self._play_sequence then return end
    if #self.selected == 0 or not self.game or G.discards <= 0 then return end
    G.discards = G.discards - 1
    self:_discard_selected_impl("discard")
end

--- Internal discard used after play sequence (or directly when not scoring).
function Hand:_discard_selected_impl(reason)
    if not self.game then return end
    -- Played cards may have been destroyed during scoring (e.g. Sixth Sense); still finish the play.
    if #self.selected == 0 then
        if reason == "play" then
            self.game.active_tooltip_card = nil
            self:layout(false)
            if self.game.restore_hand_draw_order then
                self.game:restore_hand_draw_order()
            end
            if self.game.boss_after_discard_or_play then
                self.game:boss_after_discard_or_play(reason)
            end
            if self.game.boss_after_play_before_draw then
                self.game:boss_after_play_before_draw()
            end
            self:fill_from_deck()
            if self.game.boss_on_hand_refilled then
                self.game:boss_on_hand_refilled(false)
            end
            self:calculate_play()
        end
        return
    end
    local deck = self.game.deck
    local discarded_nodes = {}
    local discarded_cards = {}
    if deck and deck.push_discard then
        for _, node in ipairs(self.selected) do
            for i, n in ipairs(self.card_nodes) do
                if n == node then
                    table.insert(discarded_nodes, node)
                    table.insert(discarded_cards, self.cards[i])
                    deck:push_discard(self.cards[i])
                    break
                end
            end
        end
    end
    local selected_set = {}
    for _, n in ipairs(self.selected) do selected_set[n] = true end
    if self.game and self.game.emit_joker_event then
        self.game:emit_joker_event("on_discard", {
            event = "on_discard",
            event_name = "on_discard",
            discarded_nodes = discarded_nodes,
            discarded_cards = discarded_cards,
            discard_reason = reason,
        })
    end
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
    if self.game then self.game.active_tooltip_card = nil end
    self:layout(false)
    if self.game.restore_hand_draw_order then
        self.game:restore_hand_draw_order()
    end
    if self.game and self.game.boss_after_discard_or_play then
        self.game:boss_after_discard_or_play(reason)
    end
    if reason == "play" and self.game and self.game.boss_after_play_before_draw then
        self.game:boss_after_play_before_draw()
    end
    self:fill_from_deck()
    if self.game and self.game.boss_on_hand_refilled then
        self.game:boss_on_hand_refilled(false)
    end
    self:calculate_play()
end

--- Insert a duplicate of the card at index (shallow copy of card data). Returns the new Card node or nil.
---@param index integer
---@return Card|nil
function Hand:duplicate_card_at_index(index)
    if not self.game then return nil end
    local cd = self.cards[index]
    if not cd then return nil end
    local copy = Deck.copy_card_data(cd)
    if not copy then return nil end
    copy.uid = nil
    return self:add_card(copy)
end

--- Create a new hand card from logical `card_data` (rank/suit/extras). Returns the new `Card` node or nil if full.
---@param card_data table
---@return Card|nil
function Hand:create_card(card_data)
    return self:add_card(card_data)
end

--- Destroy a hand card: removed from the game entirely (no discard pile). Use `discard_card_at_index` to send to the discard pile instead.
---@param index integer
---@return boolean
function Hand:destroy_card_at_index(index)
    return self:remove_card_at_index(index)
end

--- Same as `destroy_card_at_index`, but by `Card` node reference.
---@param node Card|nil
---@return boolean
function Hand:destroy_card_node(node)
    if not node then return false end
    for i, n in ipairs(self.card_nodes) do
        if n == node then
            return self:remove_card_at_index(i)
        end
    end
    return false
end

--- Send one hand card to the discard pile, then remove it from the hand (same logical outcome as discarding). Destroy/break effects must use `destroy_card_*` instead.
---@param index integer
---@return boolean
function Hand:discard_card_at_index(index)
    if not self.game then return false end
    local deck = self.game.deck
    local cd = self.cards[index]
    if not cd then return false end
    if deck and deck.push_discard then
        deck:push_discard(cd)
    end
    return self:remove_card_at_index(index)
end

--- Remove a card from the hand by index without sending it to the discard pile (destroyed / gone from the run).
---@param index integer
---@return boolean
function Hand:remove_card_at_index(index)
    if not self.game then return false end
    local node = self.card_nodes[index]
    local cd = self.cards[index]
    if not node or not cd then return false end

    for i, sel in ipairs(self.selected) do
        if sel == node then
            table.remove(self.selected, i)
            break
        end
    end
    node.selected = false
    self.game:remove(node)
    table.remove(self.cards, index)
    table.remove(self.card_nodes, index)
    if self.game.emit_on_destroy_cards and Deck and Deck.copy_card_data then
        local snap = Deck.copy_card_data(cd)
        if snap then
            self.game:emit_on_destroy_cards({ snap })
        end
    end
    if self.game.active_tooltip_card == node then
        self.game.active_tooltip_card = nil
    end
    self:layout(false)
    if self.game.restore_hand_draw_order then
        self.game:restore_hand_draw_order()
    end
    self:calculate_play()
    return true
end

--- Lay out played cards in a horizontal row near the vertical center of the bottom screen.
--- Only updates targets (T); VT lerps via Moveable for a smooth move from the hand.
function Hand:layout_play_cards_at_center(nodes)
    local n = #nodes
    if n == 0 then return end
    local scale = PLAY_CENTER_SCALE
    local card_w = CARD_W * scale
    local card_h = CARD_H * scale
    local max_step = (SCREEN_W - card_w) / math.max(1, n - 1)
    local step = n == 1 and 0 or math.min(74 * scale, max_step)
    local total_w = n == 1 and card_w or (card_w + (n - 1) * step)
    local start_x = (SCREEN_W - total_w) * 0.5
    local y = math.floor(SCREEN_H * 0.25) - card_h * 0.5
    for i, node in ipairs(nodes) do
        node.T.x = start_x + (i - 1) * step
        if(node.counts_for_play_score == true) then
            node.T.y = y
        else 
            node.T.y = y + math.floor(card_h * 0.3)
        end
        node.T.r = 0
        node.T.scale = scale
    end
end

---@param immediate boolean|nil If true, move all queued draws into the hand in this call (no per-frame delay).
function Hand:fill_from_deck(immediate)
    local deck = self.game and self.game.deck
    if not deck then return end
    local limit = hand_size_limit()
    local current_count = #self.cards + #self._draw_queue
    if self.game and self.game.boss_consume_serpent_draws then
        limit = self.game:boss_consume_serpent_draws(limit, current_count)
    end
    while #self.cards + #self._draw_queue < limit and not deck:empty() do
        local card = deck:draw()
        if card then
            if #self._draw_queue == 0 and #self.cards == 0 then
                self:add_card(card)
            else
                table.insert(self._draw_queue, card)
            end
        end
    end
    if immediate then
        while #self._draw_queue > 0 do
            local card = table.remove(self._draw_queue, 1)
            if card then self:add_card(card) end
        end
    end
end

function Hand:_cards_reached_play_targets(nodes)
    for _, node in ipairs(nodes) do
        local dx = math.abs((node.VT.x or 0) - (node.T.x or 0))
        local dy = math.abs((node.VT.y or 0) - (node.T.y or 0))
        if dx > PLAY_MOVE_ARRIVE_EPS or dy > PLAY_MOVE_ARRIVE_EPS then
            return false
        end
    end
    return true
end

--- Build a map of lower hand types contained by these cards.
--- Example: a Flush with rank pattern 2,2,1 will contain Pair and Two Pair.
function Hand:build_contained_hand_types(nodes)
    local contained = {}
    if type(nodes) ~= "table" then return contained end

    local rank_counts = {}
    local suit_counts = {}
    local n = 0

    for _, node in ipairs(nodes) do
        local data = (node and node.card_data) or {}
        local rank = data.rank
        local suit = data.suit
        if rank ~= nil then
            rank_counts[rank] = (rank_counts[rank] or 0) + 1
        end
        if suit ~= nil then
            suit_counts[suit] = (suit_counts[suit] or 0) + 1
        end
        n = n + 1
    end

    local pairs_count = 0
    local max_of_a_kind = 0
    for _, c in pairs(rank_counts) do
        if c > max_of_a_kind then max_of_a_kind = c end
        if c == 2 then pairs_count = pairs_count + 1 end
    end

    local suit_kinds = 0
    for _ in pairs(suit_counts) do
        suit_kinds = suit_kinds + 1
    end
    local flush = (suit_kinds == 1 and n > 0)

    if pairs_count >= 1 then contained["Pair"] = true end
    if pairs_count >= 2 or (max_of_a_kind >= 3 and pairs_count >= 1) then
        contained["Two Pair"] = true
    end
    if max_of_a_kind >= 3 then contained["Three of a Kind"] = true end
    if max_of_a_kind >= 4 then contained["Four of a Kind"] = true end
    if flush then contained["Flush"] = true end

    return contained
end

local function printTable(t, level, seen)
    level = level or 0
    seen = seen or {}
    if type(t) == "table" then
        if seen[t] then io.write(" {*circular*}") return end
        seen[t] = true
        print(string.rep("\t", level) .. "{")
        for k, v in pairs(t) do
            io.write(string.rep("\t", level + 1), tostring(k), " = ")
            printTable(v, level + 1, seen)
        end
        print(string.rep("\t", level) .. "}")
    else
        print(tostring(t))
    end
end


--- After one played-card trigger (including jokers), advance repeat counter or move to next card.
local function hand_advance_play_trigger(seq)
    seq.play_rep = (tonumber(seq.play_rep) or 0) + 1
    if seq.play_rep > (tonumber(seq.play_rep_total) or 1) then
        seq.play_rep = nil
        seq.play_rep_total = nil
    end
    seq.trigger_wait = (seq.trigger_wait or 0) + PLAY_TRIGGER_INTERVAL
end

function Hand:_update_play_sequence(dt)
    local seq = self._play_sequence
    if not seq then return end
    seq.timer = seq.timer + dt

    if seq.phase == "move_center" then
        if seq.timer >= PLAY_MOVE_MIN_TIME and self:_cards_reached_play_targets(seq.cards) then
            seq.phase = "trigger"
            seq.timer = 0
            seq.idx = 0
            seq.trigger_wait = 0
            seq.play_rep = nil
            seq.play_rep_total = nil
        elseif seq.timer >= PLAY_MOVE_MAX_TIME then
            seq.phase = "trigger"
            seq.timer = 0
            seq.idx = 0
            seq.trigger_wait = 0
            seq.play_rep = nil
            seq.play_rep_total = nil
        end
    elseif seq.phase == "trigger" then
        seq.trigger_wait = (seq.trigger_wait or 0) - dt
        if seq.trigger_wait <= 0 then
            if seq.play_rep == nil then
                -- Pick next scored card and start its repeat cycle.
                while true do
                    seq.idx = (tonumber(seq.idx) or 0) + 1
                    if seq.idx > #seq.cards then
                        seq.phase = "inhand_trigger"
                        seq.timer = 0
                        seq.play_rep = nil
                        seq.play_rep_total = nil
                        break
                    end
                    local node = seq.cards[seq.idx]
                    if node and node.counts_for_play_score == true then
                        seq.play_rep_total = node.play_trigger_total and node:play_trigger_total(seq) or 1
                        seq.play_rep = 1
                        break
                    end
                end
            end

            if seq.phase == "trigger" and seq.play_rep and seq.play_rep_total then
                local node = seq.cards[seq.idx]
                local score_this = node and node.counts_for_play_score == true 

                if node and score_this then
                    node.scoring_shake_timer = PLAY_SHAKE_DURATION
                    node.scoring_shake_t0 = love.timer.getTime()
                    self:play_sfx_trigger()
                    local chips, mult = self:accumulate_card_score(
                        tonumber(G.selectedHandChips) or 0,
                        tonumber(G.selectedHandMult) or 1,
                        node
                    )
                    G.selectedHandChips = chips
                    G.selectedHandMult = mult

                    local data = (node and node.card_data) or {}
                    chips = tonumber(G.selectedHandChips) or 0
                    mult = tonumber(G.selectedHandMult) or 1
                    local card_ctx = {
                        event = "card_played",
                        rank = data.rank,
                        suit = data.suit,
                        chips = chips,
                        mult = mult,
                        hand_index = G.selectedHand,
                        hand_level = G.selectedHandLevel,
                        card_node = node,
                        photograph_first_face_node = seq.photograph_first_face_node,
                        photograph_pareidolia = seq.photograph_pareidolia,
                    }
                    if node.emit_hand_event then
                        node:emit_hand_event("card_played", card_ctx)
                    end
                    chips = tonumber(card_ctx.chips) or chips
                    mult = tonumber(card_ctx.mult) or mult
                    G.selectedHandChips = chips
                    G.selectedHandMult = mult

                    local glass_broke = false
                    if card_ctx.glass_broken_node == node then
                        card_ctx.glass_broken_node = nil
                        self:destroy_card_node(node)
                        glass_broke = true
                    end

                    local jctx = {
                        event = "card_played",
                        event_name = "card_played",
                        rank = data.rank,
                        suit = data.suit,
                        chips = tonumber(G.selectedHandChips) or 0,
                        mult = tonumber(G.selectedHandMult) or 1,
                        hand_index = G.selectedHand,
                        hand_level = G.selectedHandLevel,
                        card_node = node,
                        photograph_first_face_node = seq.photograph_first_face_node,
                        photograph_pareidolia = seq.photograph_pareidolia,
                    }
                    if glass_broke then
                        seq.play_rep = seq.play_rep_total
                    end
                    if G and G.begin_joker_emit and G:begin_joker_emit("card_played", jctx) then
                        seq.phase = "wait_jokers"
                        seq.joker_wait_resume = { phase = "trigger", bump_trigger_wait = true, advance_play_repeat = true }
                    else
                        if G and G.emit_joker_event then
                            G:emit_joker_event("card_played", jctx)
                            G.selectedHandChips = tonumber(jctx.chips) or G.selectedHandChips
                            G.selectedHandMult = tonumber(jctx.mult) or G.selectedHandMult
                        end
                        hand_advance_play_trigger(seq)
                    end
                end
            end
        end
    elseif seq.phase == "wait_jokers" then
        if G and G.joker_emit_busy and G:joker_emit_busy() then
            -- Stagger runs in `Game:update` (`_update_joker_emit_queue`).
        else
            local r = seq.joker_wait_resume
            seq.joker_wait_resume = nil
            if r and r.phase == "trigger" then
                seq.phase = "trigger"
                if r.bump_trigger_wait then
                    seq.trigger_wait = (seq.trigger_wait or 0) + PLAY_TRIGGER_INTERVAL
                end
                if r.advance_play_repeat then
                    hand_advance_play_trigger(seq)
                end
            elseif r and r.phase == "finalize" then
                seq.phase = "finalize"
                seq.finalize_step = r.finalize_step
                seq.timer = 0
            end
        end
    elseif seq.phase == "inhand_trigger" then
        -- After played cards finish triggering, notify cards still held (staggered like play triggers).
        -- Queue is flattened: each entry is one in-hand trigger pass (retriggers from Mime, Red Seal, etc.).
        if not seq.inhand_queue then
            local played = {}
            for _, n in ipairs(seq.cards) do
                played[n] = true
            end
            local by_node = {}
            for _, node in ipairs(self.card_nodes or {}) do
                if not played[node] and node.card_data then
                    table.insert(by_node, node)
                end
            end
            table.sort(by_node, function(a, b)
                local ax = (a.VT and a.VT.x) or (a.T and a.T.x) or 0
                local bx = (b.VT and b.VT.x) or (b.T and b.T.x) or 0
                return ax < bx
            end)
            seq.inhand_queue = {}
            for _, node in ipairs(by_node) do
                local tot = node.held_trigger_total and node:held_trigger_total(seq) or 1
                for _ = 1, tot do
                    table.insert(seq.inhand_queue, node)
                end
            end
            seq.inhand_i = 0
            seq.inhand_wait = 0
        end
        seq.inhand_wait = (seq.inhand_wait or 0) - dt
        local chips = tonumber(G and G.selectedHandChips) or 0
        local mult = tonumber(G and G.selectedHandMult) or 1
        local ctx = {
            event = "inhand_trigger",
            hand_index = G and G.selectedHand,
            hand_level = G and G.selectedHandLevel,
            chips = chips,
            mult = mult,
            played_cards = seq.cards,
        }
        local q = seq.inhand_queue or {}
        if seq.inhand_wait <= 0 then
            if seq.inhand_i < #q then
                seq.inhand_i = seq.inhand_i + 1
                local node = q[seq.inhand_i]
                ctx.chips = tonumber(G.selectedHandChips) or ctx.chips
                ctx.mult = tonumber(G.selectedHandMult) or ctx.mult
                if node and node.emit_hand_event then
                    node:emit_hand_event("held_in_hand", ctx)
                end
                G.selectedHandChips = tonumber(ctx.chips) or G.selectedHandChips
                G.selectedHandMult = tonumber(ctx.mult) or G.selectedHandMult
                if G and G.emit_joker_event then
                    local data = (node and node.card_data) or {}
                    G:emit_joker_event("card_held", 
                    {
                        event = "card_held",
                        event_name = "card_held",
                        card_node = node,
                        rank = data.rank,
                        suit = data.suit,
                        chips = tonumber(G.selectedHandChips) or 0,
                        mult = tonumber(G.selectedHandMult) or 1,
                    })
                end
                if seq.inhand_i < #q then
                    seq.inhand_wait = PLAY_TRIGGER_INTERVAL
                end
            end
            if seq.inhand_i >= #q then
                seq.inhand_queue = nil
                seq.inhand_i = nil
                seq.inhand_wait = nil
                seq.phase = "finalize"
                seq.timer = 0
                seq.finalize_step = nil
            end
        end
    elseif seq.phase == "finalize" then
        local chips = tonumber(G.selectedHandChips) or 0
        local mult = tonumber(G.selectedHandMult) or 1

        if seq.finalize_step == nil then
            seq.finalize_step = 1
        end

        -- Step 1: single scored-hand joker event.
        if seq.finalize_step == 1 then
            local hand_type = nil
            if G and G.handlist and G.selectedHand and G.handlist[G.selectedHand] then
                hand_type = G.handlist[G.selectedHand]
            end
            hand_type = hand_type or tostring(G.selectedHand or "unknown")
            local free_joker_slots = 0
            if G then
                local cap = tonumber(G.joker_capacity) or tonumber(G.joker_slot_count) or 0
                local used = (type(G.jokers) == "table") and #G.jokers or 0
                free_joker_slots = math.max(0, cap - used)
            end
            local ctx = {
                event = "on_hand_scored",
                event_name = "on_hand_scored",
                chips = chips,
                mult = mult,
                hand_index = G.selectedHand,
                hand_type = hand_type,
                contains_hand_types = self:build_contained_hand_types(seq.cards),
                hand_level = G.selectedHandLevel,
                cards = seq.cards,
                free_joker_slots = free_joker_slots,
                discards_left = tonumber(G and G.discards) or 0,
            }
            if G and G.begin_joker_emit and G:begin_joker_emit("on_hand_scored", ctx) then
                seq.phase = "wait_jokers"
                seq.joker_wait_resume = { phase = "finalize", finalize_step = 2 }
                seq.timer = 0
                return
            elseif G and G.emit_joker_event then
                G:emit_joker_event("on_hand_scored", ctx)
            end
            seq.finalize_step = 2
        end

        -- Step 2: final score.
        if seq.finalize_step == 2 then
            chips = tonumber(G.selectedHandChips) or 0
            mult = tonumber(G.selectedHandMult) or 1
            G.selectedHandChips = chips
            G.selectedHandMult = mult

            local final_score = math.floor(chips * mult)
            G.last_hand_score = final_score
            G.round_score = (G.round_score or 0) + final_score
            seq.phase = "discard_wait"
            seq.timer = 0
        end
    elseif seq.phase == "discard_wait" then
        if seq.timer >= PLAY_AFTER_SCORE_PAUSE then
            for _, node in ipairs(seq.cards) do
                node.scoring_center = false
            end
            self._play_sequence = nil
            self:_discard_selected_impl("play")
            if G and G.evaluate_blind_progress then
                G:evaluate_blind_progress()
            end
        end
    end
end

function Hand:update(dt)
    if self._play_sequence then
        self:_update_play_sequence(dt)
    end
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
    return #self.cards >= hand_size_limit()
end

local SUIT_ORDER = { Hearts = 1, Clubs = 2, Diamonds = 3, Spades = 4 }
-- Order: A, K, Q, J, 10, 9, 8, 7, 6, 5, 4, 3, 2 (Ace first, then descending)
local function rank_sort_key(rank)
    return 14 - (rank or 2)
end

local function base_card_chips(rank)
    if rank == 14 then return 11 end -- Ace
    if rank == 11 or rank == 12 or rank == 13 then return 10 end -- J/Q/K
    if type(rank) == "number" then return rank end
    return 0
end

--- Permanent extra chips on `card_data` (field `Bonus`, lowercase `bonus` accepted).
local function card_data_bonus_chips(data)
    if type(data) ~= "table" then return 0 end
    return math.floor(tonumber(data.Bonus) or tonumber(data.bonus) or 0)
end

function Hand:get_modifier_bonus(card_data)
    if type(card_data) ~= "table" then return 0, 0 end

    local chip_bonus = 0
    local mult_bonus = 0

    -- Common direct fields on card data
    chip_bonus = chip_bonus + (tonumber(card_data.chip_bonus) or 0)
    chip_bonus = chip_bonus + (tonumber(card_data.chips_bonus) or 0)
    mult_bonus = mult_bonus + (tonumber(card_data.mult_bonus) or 0)
    mult_bonus = mult_bonus + (tonumber(card_data.multiplier_bonus) or 0)

    -- Generic single modifier table shape
    if type(card_data.modifier) == "table" then
        chip_bonus = chip_bonus + (tonumber(card_data.modifier.chip_bonus) or tonumber(card_data.modifier.chips) or 0)
        mult_bonus = mult_bonus + (tonumber(card_data.modifier.mult_bonus) or tonumber(card_data.modifier.mult) or 0)
    end

    -- Generic list of modifier tables
    if type(card_data.modifiers) == "table" then
        for _, mod in ipairs(card_data.modifiers) do
            if type(mod) == "table" then
                chip_bonus = chip_bonus + (tonumber(mod.chip_bonus) or tonumber(mod.chips) or 0)
                mult_bonus = mult_bonus + (tonumber(mod.mult_bonus) or tonumber(mod.mult) or 0)
            end
        end
    end

    return chip_bonus, mult_bonus
end

--- Apply one card's chips and mult bonuses (hand base chips/mult should already be in G).
function Hand:accumulate_card_score(chips, mult, node)
    local data = node.card_data or {}
    local rank = data.rank
    local suit = data.suit
    local bonus = card_data_bonus_chips(data)

    local card_chips = base_card_chips(rank) + bonus
    chips = chips + card_chips

    local mod_chip_bonus, mod_mult_bonus = self:get_modifier_bonus(data)
    chips = chips + mod_chip_bonus
    mult = mult + mod_mult_bonus

    return chips, mult
end

function Hand:score_selected_hand()
    if #self.selected == 0 then return nil end

    local chips = tonumber(G.selectedHandChips) or 0
    local mult = tonumber(G.selectedHandMult) or 1
    local ordered = self:ordered_selected_nodes()

    print(string.format("Scoring hand start: chips=%d mult=%d", chips, mult))

    for i, node in ipairs(ordered) do
        local score_this = node.counts_for_play_score == true
        local data = node.card_data or {}
        local rank = data.rank
        local suit = data.suit
        local card_chips = base_card_chips(rank) + card_data_bonus_chips(data)
        local mod_chip_bonus, mod_mult_bonus = self:get_modifier_bonus(data)

        if score_this then
            chips, mult = self:accumulate_card_score(chips, mult, node)
        end

        print(string.format(
            "Card %d [%s of %s]: +%d chips, modifier +%d chips / +%d mult -> chips=%d mult=%d%s",
            i, tostring(rank), tostring(suit), card_chips, mod_chip_bonus, mod_mult_bonus, chips, mult,
            score_this and "" or " (kicker — not scored)"
        ))
    end

    local final_score = math.floor(chips * mult)
    G.selectedHandChips = chips
    G.selectedHandMult = mult
    G.last_hand_score = final_score
    G.round_score = (G.round_score or 0) + final_score

    print(string.format("Hand result: %d x %d = %d", chips, mult, final_score))
    print(string.format("Round score: %d", G.round_score))

    return { chips = chips, mult = mult, score = final_score }
end

function Hand:play_selected()
    if #self.selected == 0 or G.hands <= 0 then return end
    if self._play_sequence then return end

    if self.game then self.game.active_tooltip_card = nil end

    self:calculate_play()
    local cards = self:ordered_selected_nodes()
    if self.game and self.game.boss_before_play_selected and not self.game:boss_before_play_selected(cards) then
        return
    end

    local flipped_any = false
    for _, n in ipairs(cards) do
        if n and n.face_up == false and n.set_face_up then
            n:set_face_up(true)
            flipped_any = true
        end
    end
    if flipped_any then
        self:calculate_play()
        cards = self:ordered_selected_nodes()
    end

    G.hands = G.hands - 1
    if self.game and self.game.boss_apply_on_hand_submitted then
        self.game:boss_apply_on_hand_submitted(cards)
    end
    if self.game and self.game.emit_joker_event then
        self.game:emit_joker_event("on_hand_played", {
            event = "on_hand_played",
            event_name = "on_hand_played",
            cards = cards,
            hand_index = G and G.selectedHand,
            hand_level = G and G.selectedHandLevel,
            hand_type = (G and G.handlist and G.selectedHand and G.handlist[G.selectedHand]) or nil,
        })
    end
    if self.game and self.game.boss_should_void_current_play and self.game:boss_should_void_current_play() then
        self:_discard_selected_impl("play")
        if G and G.evaluate_blind_progress then
            G:evaluate_blind_progress()
        end
        return
    end
    if self.game and self.game.increment_hand_play_count then
        self.game:increment_hand_play_count(G and G.selectedHand)
    end

    for _, n in ipairs(cards) do
        n.scoring_center = true
    end

    local chad_count = self.game and self.game.count_jokers_with_id and self.game:count_jokers_with_id("j_hanging_chad") or 0
    local hanging_chad_first = nil
    if chad_count > 0 then
        for _, n in ipairs(cards) do
            if n and n.counts_for_play_score == true then
                hanging_chad_first = n
                break
            end
        end
    end

    -- Photograph: first scoring face card in play order; x2 applies on every scoring pass (retriggers included).
    local photograph_pareidolia = self.game and self.game:hasJoker("j_pareidolia")
    local photograph_first_face = nil
    for _, n in ipairs(cards) do
        if n and n.counts_for_play_score == true then
            local d = n.card_data or {}
            local r = tonumber(d.rank)
            if photograph_pareidolia or r == 11 or r == 12 or r == 13 then
                photograph_first_face = n
                break
            end
        end
    end

    self._play_sequence = {
        phase = "move_center",
        timer = 0,
        cards = cards,
        photograph_first_face_node = photograph_first_face,
        photograph_pareidolia = photograph_pareidolia and true or false,
    }

    self:layout_play_cards_at_center(cards)
    if self.game and self.game.move_selected_hand_cards_to_front then
        self.game:move_selected_hand_cards_to_front()
    end
end

function Hand:sort_by_rank(layout_skip_vt_node)
    self.sort_mode = "rank"
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
    self:layout(false, layout_skip_vt_node)
    if self.game and self.game.restore_hand_draw_order then
        self.game:restore_hand_draw_order()
    end
end

function Hand:sort_by_suit(layout_skip_vt_node)
    self.sort_mode = "suit"
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
    self:layout(false, layout_skip_vt_node)
    if self.game and self.game.restore_hand_draw_order then
        self.game:restore_hand_draw_order()
    end
end

function Hand:calculate_play()
    local n_sel = #self.selected
    if n_sel == 0 then
        for _, node in ipairs(self.card_nodes) do
            node.counts_for_play_score = false
        end
        print("No cards selected")
        G.selectedHandHidden = false
        G.selectedHand = -1
        G.selectedHandLevel = 1
        G.selectedHandChips = 0
        G.selectedHandMult = 0
        return
    end

    print("Selected cards:")

    local sel_set = {}
    for _, node in ipairs(self.selected) do
        sel_set[node] = true
    end

    -- One pass: clear scoring flags + build left-to-right order of selected cards
    local ordered = {}
    for _, node in ipairs(self.card_nodes) do
        node.counts_for_play_score = false
        if sel_set[node] then
            table.insert(ordered, node)
        end
    end

    local n = #ordered
    local has_four_fingers = false
    local has_shortcut = false
    local has_smeared = false
    if self.game and self.game:hasJoker("j_four_fingers") then
        has_four_fingers = true
    end
    if self.game and self.game:hasJoker("j_shortcut") then
        has_shortcut = true
    end
    if self.game and self.game:hasJoker("j_smeared") then
        has_smeared = true
    end

    local function normalized_suit_for_scoring(suit)
        if not has_smeared then return suit end
        if suit == "Hearts" or suit == "Diamonds" then return "Red" end
        if suit == "Spades" or suit == "Clubs" then return "Black" end
        return suit
    end

    -- Collect ranks / suits (hand order); track high rank for marking high card later
    local ranks = {}
    local suits = {}
    local rank_counts = {}
    local suit_counts = {}
    local max_rank_for_high = nil
    local has_face_down_selected = false

    for _, node in ipairs(ordered) do
        local data = node.card_data or {}
        local rank = data.rank
        local suit = data.suit
        if node and node.face_up == false then
            has_face_down_selected = true
        end

        table.insert(ranks, rank)
        table.insert(suits, suit)

        rank_counts[rank] = (rank_counts[rank] or 0) + 1
        local normalized_suit = normalized_suit_for_scoring(suit)
        suit_counts[normalized_suit] = (suit_counts[normalized_suit] or 0) + 1

        if type(rank) == "number" then
            if max_rank_for_high == nil or rank > max_rank_for_high then
                max_rank_for_high = rank
            end
        end
    end

    local min_straight_flush_cards = has_four_fingers and 4 or 5

    local function is_flush()
        if n < min_straight_flush_cards then return false end
        return next(suit_counts) ~= nil and next(suit_counts, next(suit_counts)) == nil
    end

    -- Rank pattern: one pass over rank_counts (also used for scoring marks later)
    local max_of_a_kind = 0
    local pairs_count = 0
    local has_three = false
    local has_two = false
    for _, c in pairs(rank_counts) do
        if c > max_of_a_kind then max_of_a_kind = c end
        if c == 2 then
            pairs_count = pairs_count + 1
            has_two = true
        end
        if c == 3 then has_three = true end
    end

    -- A straight usually needs 5 cards, but Four Fingers allows 4-card straights.
    local function is_straight()
        if n < min_straight_flush_cards then return false end
        local function has_valid_run(sorted_unique_ranks)
            if #sorted_unique_ranks < min_straight_flush_cards then return false end
            local run_len = 1
            for i = 2, #sorted_unique_ranks do
                local diff = sorted_unique_ranks[i] - sorted_unique_ranks[i - 1]
                local is_run_step = (diff == 1) or (has_shortcut and diff == 2)
                if is_run_step then
                    run_len = run_len + 1
                    if run_len >= min_straight_flush_cards then
                        return true
                    end
                else
                    run_len = 1
                end
            end
            return false
        end

        local uniq = {}
        for _, r in ipairs(ranks) do
            if r == nil then return false end
            uniq[r] = true
        end

        local uniq_ranks = {}
        for r in pairs(uniq) do
            table.insert(uniq_ranks, r)
        end
        table.sort(uniq_ranks)

        if has_valid_run(uniq_ranks) then return true end

        -- Ace-low variants (A as 1), including Shortcut gap runs (e.g. A-3-5-7-9).
        if uniq[14] then
            local ace_low = {}
            for _, rr in ipairs(uniq_ranks) do
                ace_low[#ace_low + 1] = (rr == 14) and 1 or rr
            end
            table.sort(ace_low)
            local dedup = {}
            local prev = nil
            for _, rr in ipairs(ace_low) do
                if rr ~= prev then
                    dedup[#dedup + 1] = rr
                    prev = rr
                end
            end
            if has_valid_run(dedup) then return true end
        end

        local hasA = uniq[14] or uniq["A"]
        local wheel5 = hasA and uniq[2] and uniq[3] and uniq[4] and uniq[5]
        local wheel4 = hasA and uniq[2] and uniq[3] and uniq[4]
        return wheel5 or (min_straight_flush_cards <= 4 and wheel4)
    end

    local flush = is_flush()
    local straight = is_straight()

    -- Determine hand according to Balatro order in globals.handlist:
    -- 1  Flush Five      (five of same rank & same suit)
    -- 2  Flush House     (full house, all same suit)
    -- 3  Five of a Kind  (five of same rank, not all same suit)
    -- 4  Straight Flush
    -- 5  Four of a Kind
    -- 6  Full House
    -- 7  Flush
    -- 8  Straight
    -- 9  Three of a Kind
    -- 10 Two Pair
    -- 11 Pair
    -- 12 High Card

    local hand_index

    if n == 5 then
        -- Secret hands first
        if max_of_a_kind == 5 and flush then
            hand_index = 1 -- Flush Five
        elseif flush then
            -- Check for Flush House: 3-of-a-kind + 2-of-a-kind, all same suit
            if has_three and has_two then
                hand_index = 2 -- Flush House
            end
        end

        if not hand_index then
            if max_of_a_kind == 5 then
                hand_index = 3 -- Five of a Kind
            elseif flush and straight then
                hand_index = 4 -- Straight Flush
            elseif max_of_a_kind == 4 then
                hand_index = 5 -- Four of a Kind
            else
                if has_three and has_two then
                    hand_index = 6 -- Full House
                elseif flush then
                    hand_index = 7 -- Flush
                elseif straight then
                    hand_index = 8 -- Straight
                elseif max_of_a_kind == 3 then
                    hand_index = 9 -- Three of a Kind
                elseif pairs_count == 2 then
                    hand_index = 10 -- Two Pair
                elseif pairs_count == 1 then
                    hand_index = 11 -- Pair
                else
                    hand_index = 12 -- High Card
                end
            end
        end
    else
        -- Fewer than 5 cards: fall back to best matching category we can infer
        if flush and straight then
            hand_index = 4 -- Straight Flush (Four Fingers 4-card enable)
        elseif max_of_a_kind >= 4 then
            hand_index = 5 -- Four of a Kind (partial)
        elseif flush then
            hand_index = 7 -- Flush (Four Fingers 4-card enable)
        elseif straight then
            hand_index = 8 -- Straight (Four Fingers 4-card enable)
        elseif max_of_a_kind == 3 then
            hand_index = 9 -- Three of a Kind
        elseif pairs_count >= 2 then
            hand_index = 10 -- Two Pair
        elseif pairs_count == 1 then
            hand_index = 11 -- Pair
        else
            hand_index = 12 -- High Card
        end
    end

    G.selectedHand = hand_index or 12

    local hand_stats = G.hand_stats and G.hand_stats[G.selectedHand] or nil
    if hand_stats then
        local level = math.max(1, tonumber(hand_stats.level) or 1)
        local chips = (hand_stats.base_chips or 0) + ((level - 1) * (hand_stats.chips_per_level or 0))
        local mult = (hand_stats.base_mult or 0) + ((level - 1) * (hand_stats.mult_per_level or 0))
        if G and G.boss_apply_hand_base_modifiers then
            chips, mult = G:boss_apply_hand_base_modifiers(chips, mult)
        end
        G.selectedHandLevel = level
        G.selectedHandChips = chips
        G.selectedHandMult = mult
    else
        G.selectedHandLevel = 1
        G.selectedHandChips = 0
        G.selectedHandMult = 0
    end

    if G.selectedHand and G.handlist and G.handlist[G.selectedHand] then
        print("Detected hand: " .. tostring(G.handlist[G.selectedHand]))
    else
        print("Detected hand index: " .. tostring(G.selectedHand))
    end
    G.selectedHandHidden = has_face_down_selected == true

    print("Hand level: " .. tostring(G.selectedHandLevel))
    print("Hand chips: " .. tostring(G.selectedHandChips))
    print("Hand mult: " .. tostring(G.selectedHandMult))

    -- Mark which selected cards actually score (ordered built above).
    local hi = G.selectedHand

    local function mark_all_ordered()
        for _, node in ipairs(ordered) do
            node.counts_for_play_score = true
        end
    end

    local function mark_rank_scoring(r)
        for _, node in ipairs(ordered) do
            if (node.card_data or {}).rank == r then
                node.counts_for_play_score = true
            end
        end
    end

    if G:hasJoker("j_splash") then
        mark_all_ordered()
    elseif hi == 1 or hi == 2 or hi == 3 or hi == 4 or hi == 6 or hi == 7 or hi == 8 then
        mark_all_ordered()
    elseif hi == 5 then
        for r, c in pairs(rank_counts) do
            if c == 4 then
                mark_rank_scoring(r)
                break
            end
        end
    elseif hi == 9 then
        for r, c in pairs(rank_counts) do
            if c == 3 then
                mark_rank_scoring(r)
                break
            end
        end
    elseif hi == 10 then
        for r, c in pairs(rank_counts) do
            if c == 2 then
                mark_rank_scoring(r)
            end
        end
    elseif hi == 11 then
        for r, c in pairs(rank_counts) do
            if c == 2 then
                mark_rank_scoring(r)
                break
            end
        end
    elseif hi == 12 then
        if max_rank_for_high ~= nil then
            mark_rank_scoring(max_rank_for_high)
        end
    else
        mark_all_ordered()
    end

    if G and G.boss_is_card_debuffed_for_scoring then
        local any_debuffed = false
        for _, node in ipairs(ordered) do
            if node.counts_for_play_score == true and G:boss_is_card_debuffed_for_scoring(node) then
                node.counts_for_play_score = false
                any_debuffed = true
            end
        end
        if any_debuffed and G.notify_boss_effect_triggered then
            G:notify_boss_effect_triggered({ reason = "card_debuffed_for_scoring" })
        end
    end
    if G and G.get_active_boss_blind_id and G:get_active_boss_blind_id() == "bl_psychic" and #ordered < 5 then
        for _, node in ipairs(ordered) do
            node.counts_for_play_score = false
        end
        if G.notify_boss_effect_triggered then
            G:notify_boss_effect_triggered({ reason = "psychic_min_cards" })
        end
    end
end