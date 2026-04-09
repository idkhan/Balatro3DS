---@class Game
Game = Object:extend()

---@param seed number|nil Optional seed for the RNG. If nil, a seed is generated (os.time()).
function Game:init(seed)
    G = self
    -- core containers/state
    self.nodes = {}
    self.dragging = nil
    self.touch_start_x = 0
    self.touch_start_y = 0
    self.pending_discard = {}
    self.discard_timer = 0
    self.selectedHand = -1
    self.selectedHandHidden = false
    self.selectedHandLevel = 1
    self.selectedHandChips = 0
    self.selectedHandMult = 0
    self.active_tooltip_card = nil
    self.active_tooltip_joker = nil
    self.active_tooltip_consumable_index = nil
    --- Hit rect + payload for the optional Sell control (`draw_sell_button` / `try_sell_button_press`).
    self._sell_button_hit = nil
    --- Hit rect + payload for the optional Use control (`draw_use_button` / `try_use_button_press`).
    self._use_button_hit = nil
    --- Hit rect + payload for Buy control under selected shop Joker.
    self._shop_buy_button_hit = nil
    self.round_score = 0
    self.last_hand_score = 0
    --- Run currency
    self.money = 0
    -- Run Discards
    self.discards = 5
    -- Run Hands
    self.hands = 5
    -- Round Count
    self.round = 1
    -- Ante Count
    self.ante = 1
    self._last_completed_blind_was_boss = false
    self.current_blind_index = 1
    self.current_blind_target = 0
    self.current_blind_reward = 0
    self.current_blind_name = "Small Blind"
    self.selected_blind_index = 1
    self._blind_resolution_pending = false
    self.shop_offers = {}
    self.shop_offer_nodes = {}
    self.shop_offer_slots = 4
    self.shop_reroll_base_cost = 5
    self.shop_reroll_count = 0
    self.hand_play_counts = {}
    self._ante_played_card_uids = {}
    self.current_boss_blind_id = nil
    self.boss_runtime = {}
    self._next_card_uid = 1
    self._collidables_buf = {}
    self._gc_timer = 0
    self._gc_discarded_nodes = 0
    --- Staggered joker resolution (left-to-right); see `begin_joker_emit` / `_update_joker_emit_queue`.
    self._joker_emit_queue = nil
    self._joker_emit_next = 1
    self._joker_emit_timer = 0
    self.JOKER_EMIT_INTERVAL = 0.5

    -- Run Consumables (Tarot / Planet cards held outside the deck).
    self.consumables = {}
    self.consumable_capacity = 2
    self._consumable_rects = {}
    self.consumable_nodes = {}
    --- Last consumable id used this run (Tarot except Fool, or Planet); for The Fool duplicate.
    self.last_consumable_use_id = nil

    -- Pull all shared globals from globals.lua
    if self.set_globals then
        self:set_globals()
    end
    if self.init_item_prototypes then
        self:init_item_prototypes()
    end

    if seed ~= nil then
        self.SEED = seed
    end
    if self.SEED == nil then
        self.SEED = os.time()
    end
    math.randomseed(self.SEED)
    collectgarbage("setpause", 110)
    collectgarbage("setstepmul", 200)

    -- set filters and load atlases
    self:set_render_settings()

    -- Create joker slots + initial joker instances.
    -- (Top-screen rendering is handled by `TopUI.draw()`)
    self:init_jokers()
end

function Game:increment_hand_play_count(hand_index)
    local hi = math.floor(tonumber(hand_index) or -1)
    if hi < 1 then return end
    self.hand_play_counts = self.hand_play_counts or {}
    self.hand_play_counts[hi] = (tonumber(self.hand_play_counts[hi]) or 0) + 1
end

function Game:ensure_card_uid(card_data, force_new)
    if type(card_data) ~= "table" then return nil end
    if force_new == true or card_data.uid == nil then
        local n = math.floor(tonumber(self._next_card_uid) or 1)
        if n < 1 then n = 1 end
        card_data.uid = n
        self._next_card_uid = n + 1
    end
    return card_data.uid
end

function Game:get_active_boss_blind_id()
    if tonumber(self.current_blind_index) ~= 3 then return nil end
    local proto = self:get_boss_blind_prototype()
    if not proto then return nil end
    return self.current_boss_blind_id
end

function Game:get_effective_hand_size_limit()
    local limit = 8
    for _, j in ipairs(self.jokers or {}) do
        local id = j and j.def and j.def.id
        if id == "j_juggler" then limit = limit + 1 end
        if id == "j_turtle_bean" then limit = limit + 5 end
        if id == "j_troubadour" then limit = limit + 2 end
        if id == "j_stuntman" then limit = limit - 2 end
        if id == "j_merry_andy" then limit = limit - 1 end
    end
    local boss_id = self:get_active_boss_blind_id()
    if boss_id == "bl_manacle" then
        limit = limit - 1
    end
    return math.max(1, limit)
end

function Game:get_effective_hands_per_round()
    local hands = 5
    for _, j in ipairs(self.jokers or {}) do
        local id = j and j.def and j.def.id
        if id == "j_burglar" then hands = hands + 3 end
        if id == "j_troubadour" then hands = hands - 1 end
    end
    return math.max(1, hands)
end

function Game:get_effective_discards_per_round()
    local discards = 5
    for _, j in ipairs(self.jokers or {}) do
        local id = j and j.def and j.def.id
        if id == "j_drunkard" then discards = discards + 1 end
        if id == "j_merry_andy" then discards = discards + 3 end
        if id == "j_burglar" then discards = 0 end
    end
    return math.max(0, discards)
end

function Game:_boss_pick_random_hand_card_uid()
    local cards = self.hand and self.hand.cards or nil
    if type(cards) ~= "table" or #cards <= 0 then return nil end
    local i = math.random(1, #cards)
    local c = cards[i]
    return c and c.uid or nil
end

function Game:_boss_find_hand_node_by_uid(uid)
    if uid == nil or not self.hand or not self.hand.card_nodes then return nil end
    for _, node in ipairs(self.hand.card_nodes) do
        local d = node and node.card_data
        if d and d.uid == uid then return node end
    end
    return nil
end

function Game:_boss_select_forced_card_if_needed()
    if self:get_active_boss_blind_id() ~= "bl_final_bell" then return end
    if not self.hand or not self.hand.cards then return end
    self.boss_runtime = self.boss_runtime or {}
    local uid = self.boss_runtime.forced_card_uid
    if uid == nil or self:_boss_find_hand_node_by_uid(uid) == nil then
        uid = self:_boss_pick_random_hand_card_uid()
        self.boss_runtime.forced_card_uid = uid
    end
    local forced = self:_boss_find_hand_node_by_uid(uid)
    if forced and self.hand and self.hand.is_selected and not self.hand:is_selected(forced) then
        self.hand:toggle_selection(forced)
    end
end

function Game:boss_reset_for_new_blind()
    self.boss_runtime = {
        hand_count = 0,
        seen_hand_types = {},
        locked_hand_type = nil,
        mouth_void_play = false,
        eye_void_play = false,
        forced_card_uid = nil,
        house_face_down_draws = 0,
        fish_face_down_draws = 0,
        serpent_draws_pending = 0,
        sold_joker_this_blind = false,
        crimson_disabled_joker = nil,
    }
    local boss_id = self:get_active_boss_blind_id()
    if type(self.jokers) == "table" then
        for _, j in ipairs(self.jokers) do
            if j and j.set_face_up then
                j:set_face_up(true)
            end
        end
    end
    if not boss_id then return end

    if boss_id == "bl_needle" then
        self.hands = 1
    end
    if boss_id == "bl_water" then
        self.discards = 0
    end
    if boss_id == "bl_final_leaf" then
        self.boss_runtime.verdant_leaf_active = true
    end
    if boss_id == "bl_house" then
        self.boss_runtime.house_face_down_draws = self:get_effective_hand_size_limit()
    end
    if boss_id == "bl_final_acorn" and type(self.jokers) == "table" and #self.jokers > 1 then
        for i = #self.jokers, 2, -1 do
            local j = math.random(1, i)
            self.jokers[i], self.jokers[j] = self.jokers[j], self.jokers[i]
        end
        for _, j in ipairs(self.jokers) do
            if j and j.set_face_up then
                j:set_face_up(false)
            end
        end
        self:_apply_joker_layout()
    end
end

function Game:boss_on_hand_refilled(is_new_blind)
    local boss_id = self:get_active_boss_blind_id()
    if not boss_id or not self.hand or not self.hand.card_nodes then return end
    if boss_id == "bl_final_heart" then
        local count = #self.jokers
        if count > 0 then
            self.boss_runtime.crimson_disabled_joker = math.random(1, count)
        else
            self.boss_runtime.crimson_disabled_joker = nil
        end
    end
    self:_boss_select_forced_card_if_needed()
end

function Game:boss_on_card_drawn(card_node)
    local boss_id = self:get_active_boss_blind_id()
    if not boss_id or not card_node then return end
    local data = card_node.card_data or {}
    local force_down = false

    if boss_id == "bl_mark" then
        local r = tonumber(data.rank) or 0
        if r >= 11 and r <= 13 then force_down = true end
    end
    if boss_id == "bl_house" and (tonumber(self.boss_runtime.house_face_down_draws) or 0) > 0 then
        force_down = true
        self.boss_runtime.house_face_down_draws = math.max(0, (tonumber(self.boss_runtime.house_face_down_draws) or 0) - 1)
    end
    if boss_id == "bl_wheel" and math.random(1, 7) == 1 then
        force_down = true
    end
    if boss_id == "bl_fish" and (tonumber(self.boss_runtime.fish_face_down_draws) or 0) > 0 then
        force_down = true
        self.boss_runtime.fish_face_down_draws = math.max(0, (tonumber(self.boss_runtime.fish_face_down_draws) or 0) - 1)
    end
    if force_down and card_node.set_face_up then
        card_node:set_face_up(false)
    end
end

function Game:boss_consume_serpent_draws(default_limit, current_count)
    local boss_id = self:get_active_boss_blind_id()
    if boss_id ~= "bl_serpent" then return default_limit end
    local pending = math.max(0, math.floor(tonumber(self.boss_runtime.serpent_draws_pending) or 0))
    if pending <= 0 then return default_limit end
    self.boss_runtime.serpent_draws_pending = 0
    return math.max(default_limit, current_count + pending)
end

function Game:boss_after_discard_or_play(reason)
    local boss_id = self:get_active_boss_blind_id()
    if not boss_id then return end
    if boss_id == "bl_serpent" then
        self.boss_runtime.serpent_draws_pending = 3
    end
    if reason == "play" and boss_id == "bl_fish" then
        self.boss_runtime.fish_face_down_draws = self:get_effective_hand_size_limit()
    end
end

function Game:boss_after_play_before_draw()
    local boss_id = self:get_active_boss_blind_id()
    if boss_id ~= "bl_hook" then return end
    local hand = self.hand
    if not hand or not hand.cards then return end
    for _ = 1, 2 do
        if #hand.cards <= 0 then break end
        local i = math.random(1, #hand.cards)
        if hand.discard_card_at_index then
            hand:discard_card_at_index(i)
        end
    end
end

function Game:boss_before_play_selected(selected_nodes)
    local boss_id = self:get_active_boss_blind_id()
    if not boss_id then return true end
    local n = type(selected_nodes) == "table" and #selected_nodes or 0
    local hand_idx = tonumber(self.selectedHand) or -1
    local hand_name = self.handlist and self.handlist[hand_idx] or tostring(hand_idx)
    self.boss_runtime.hand_count = (tonumber(self.boss_runtime.hand_count) or 0) + 1
    self.boss_runtime.mouth_void_play = false
    self.boss_runtime.eye_void_play = false
    if boss_id == "bl_mouth" then
        if self.boss_runtime.locked_hand_type == nil then
            self.boss_runtime.locked_hand_type = hand_name
        elseif self.boss_runtime.locked_hand_type ~= hand_name then
            self.boss_runtime.mouth_void_play = true
        end
    end
    if boss_id == "bl_eye" then
        if self.boss_runtime.seen_hand_types[hand_name] then
            self.boss_runtime.eye_void_play = true
        end
        self.boss_runtime.seen_hand_types[hand_name] = true
    end
    if boss_id == "bl_final_bell" then
        local forced_uid = self.boss_runtime.forced_card_uid
        if forced_uid ~= nil then
            local has_forced = false
            for _, node in ipairs(selected_nodes or {}) do
                local d = node and node.card_data
                if d and d.uid == forced_uid then
                    has_forced = true
                    break
                end
            end
            if not has_forced then return false end
        end
    end
    return true
end

function Game:boss_should_void_current_play()
    if not self.boss_runtime then return false end
    return self.boss_runtime.mouth_void_play == true or self.boss_runtime.eye_void_play == true
end

function Game:boss_apply_on_hand_submitted(selected_nodes)
    local boss_id = self:get_active_boss_blind_id()
    local hand_idx = tonumber(self.selectedHand) or -1

    if type(selected_nodes) == "table" and tonumber(self.current_blind_index) ~= 3 then
        for _, node in ipairs(selected_nodes) do
            local d = node and node.card_data
            if d and d.uid then
                self._ante_played_card_uids[d.uid] = true
            end
        end
    end
    if not boss_id then return end

    if boss_id == "bl_tooth" then
        local n = type(selected_nodes) == "table" and #selected_nodes or 0
        self.money = math.max(0, (tonumber(self.money) or 0) - n)
    elseif boss_id == "bl_ox" then
        local target_idx, target_count = -1, -1
        for k, v in pairs(self.hand_play_counts or {}) do
            local c = tonumber(v) or 0
            if c > target_count then
                target_count = c
                target_idx = tonumber(k) or -1
            end
        end
        if target_idx > 0 and hand_idx == target_idx then
            self.money = 0
        end
    elseif boss_id == "bl_arm" then
        local hs = self.hand_stats and self.hand_stats[hand_idx]
        if hs then
            hs.level = math.max(1, (tonumber(hs.level) or 1) - 1)
            local level = tonumber(hs.level) or 1
            self.selectedHandLevel = level
            self.selectedHandChips = (tonumber(hs.base_chips) or 0) + ((level - 1) * (tonumber(hs.chips_per_level) or 0))
            self.selectedHandMult = (tonumber(hs.base_mult) or 0) + ((level - 1) * (tonumber(hs.mult_per_level) or 0))
        end
    end

end

function Game:boss_is_card_debuffed_for_scoring(node)
    local boss_id = self:get_active_boss_blind_id()
    if not boss_id or not node then return false end
    local d = node.card_data or {}
    local rank = tonumber(d.rank) or 0
    local suit = d.suit
    if boss_id == "bl_club" and suit == "Clubs" then return true end
    if boss_id == "bl_goad" and suit == "Spades" then return true end
    if boss_id == "bl_window" and suit == "Diamonds" then return true end
    if boss_id == "bl_head" and suit == "Hearts" then return true end
    if boss_id == "bl_plant" and rank >= 11 and rank <= 13 then return true end
    if boss_id == "bl_pillar" and d.uid and self._ante_played_card_uids[d.uid] then return true end
    if boss_id == "bl_final_leaf" and self.boss_runtime.verdant_leaf_active == true then return true end
    return false
end

function Game:boss_apply_hand_base_modifiers(chips, mult)
    local boss_id = self:get_active_boss_blind_id()
    chips = tonumber(chips) or 0
    mult = tonumber(mult) or 0
    if boss_id == "bl_flint" then
        chips = math.floor(chips * 0.5)
        mult = math.max(1, math.floor(mult * 0.5))
    end
    return chips, mult
end

function Game:boss_on_joker_sold()
    if self:get_active_boss_blind_id() == "bl_final_leaf" then
        self.boss_runtime.verdant_leaf_active = false
        self.boss_runtime.sold_joker_this_blind = true
    end
end

function Game:clear_shop_offer_nodes()
    if type(self.shop_offer_nodes) ~= "table" then
        self.shop_offer_nodes = {}
        return
    end
    for _, node in ipairs(self.shop_offer_nodes) do
        if node then
            if self.active_tooltip_joker == node then
                self.active_tooltip_joker = nil
            end
            self:remove(node)
        end
    end
    self.shop_offer_nodes = {}
end

function Game:sync_shop_offer_nodes()
    if type(self.shop_offers) ~= "table" then
        self.shop_offers = {}
    end
    if type(self.shop_offer_nodes) ~= "table" then
        self.shop_offer_nodes = {}
    end
    if not Joker and not Consumable then
        self:clear_shop_offer_nodes()
        return
    end

    for i = #self.shop_offer_nodes, #self.shop_offers + 1, -1 do
        local node = self.shop_offer_nodes[i]
        if node then
            if self.active_tooltip_joker == node then
                self.active_tooltip_joker = nil
            end
            self:remove(node)
        end
        table.remove(self.shop_offer_nodes, i)
    end

    for i, offer in ipairs(self.shop_offers) do
        local node = self.shop_offer_nodes[i]
        local need_joker = (offer.kind == nil or offer.kind == "joker")
        local need_cons = (offer.kind == "tarot" or offer.kind == "planet")

        if node then
            local is_j = Joker and node.is and node:is(Joker)
            local is_c = Consumable and node.is and node:is(Consumable)
            local ok = (need_joker and is_j) or (need_cons and is_c)
            if ok and need_joker and is_j and node.def and offer.id and node.def.id ~= offer.id then
                ok = false
            end
            if ok and need_cons and is_c and node.def and offer.id and node.def.id ~= offer.id then
                ok = false
            end
            if not ok then
                if self.active_tooltip_joker == node then
                    self.active_tooltip_joker = nil
                end
                self:remove(node)
                self.shop_offer_nodes[i] = nil
                node = nil
            end
        end

        if not node then
            if need_joker and Joker then
                local def = JOKER_DEFS and JOKER_DEFS[offer.id]
                if type(def) == "table" then
                    node = Joker(0, 0, self.joker_slot_w, self.joker_slot_h, def, { face_up = true, edition = offer.edition })
                    self.shop_offer_nodes[i] = node
                    self:add(node)
                end
            elseif need_cons and Consumable and CONSUMABLE_DEFS then
                local def = CONSUMABLE_DEFS[offer.id]
                if type(def) == "table" and copy_table then
                    node = Consumable(0, 0, copy_table(def))
                    self.shop_offer_nodes[i] = node
                    self:add(node)
                end
            end
        end
        if node then
            node.shop_offer_slot = i
            node.states.visible = false
            node.states.click.can = false
            node.states.drag.can = false
            node.states.collide.can = false
        end
    end
end

function Game:layout_shop_offer_nodes(param)
    local nodes = self.shop_offer_nodes or {}
    local offers = self.shop_offers or {}
    local n = math.min(#nodes, #offers)
    self._shop_offer_rects = {}
    if n <= 0 then return end

    
    local panel_x, panel_y, panel_w = param.x, param.y, param.w
    local padding = 4
    local area_x = param.x - padding
    local area_y = param.y + padding
    local area_w = param.w 
    local area_h = param.h - padding

    local card_w = self.joker_slot_w or 71
    local card_h = self.joker_slot_h or 95
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

    local interactive = (self.STATE == self.STATES.SHOP)
    for i = 1, n do
        local node = nodes[i]
        if node and node.T and node.VT then
            local x = start_x + ((i - 1) * (eff_w + gap))
            local selected = (self.active_tooltip_joker == node)
            node.T.x = x
            node.T.y = y - (selected and 8 or 0)
            node.T.scale = scale
            if self.dragging ~= node then
                node.VT.x = x
                node.VT.y = node.T.y
                node.VT.scale = scale
            end
            node.states.visible = interactive
            node.states.click.can = interactive
            node.states.drag.can = false
            node.shop_offer_slot = i
            self._shop_offer_rects[i] = node:get_collision_rect()
        end
    end
end

function Game:sync_shop_offer_interactivity()
    local active = (self.STATE == self.STATES.SHOP)
    local tooltip_is_shop_offer = false
    for _, node in ipairs(self.shop_offer_nodes or {}) do
        if node and node.states then
            node.states.visible = active
            node.states.click.can = active
            node.states.drag.can = false
        end
        if node and self.active_tooltip_joker == node then
            tooltip_is_shop_offer = true
        end
    end
    if not active and tooltip_is_shop_offer then
        self.active_tooltip_joker = nil
    end
end

function Game:draw_shop_offer_price_tags()
    if self.STATE ~= self.STATES.SHOP then return end
    for i, offer in ipairs(self.shop_offers or {}) do
        local node = self.shop_offer_nodes and self.shop_offer_nodes[i]
        local rect = node and node.get_collision_rect and node:get_collision_rect() or self._shop_offer_rects[i]
        if rect then
            local label = "$" .. tostring(offer.price or 0)
            local font = self.FONTS.PIXEL.SMALL
            local tw = font:getWidth(label)
            local th = font:getHeight()
            local tag_w = tw + 12
            local tag_h = th + 4
            local tx = rect.x + math.floor((rect.w - tag_w) * 0.5 + 0.5)
            local ty = rect.y - tag_h - 2
            if _G.draw_rect_with_shadow then
                draw_rect_with_shadow(tx, ty, tag_w, tag_h, 3, 2, self.C.BLOCK.BACK, self.C.BLOCK.SHADOW, 1)
            else
                love.graphics.setColor(self.C.BLOCK.BACK)
                love.graphics.rectangle("fill", tx, ty, tag_w, tag_h, 3, 3)
            end
            love.graphics.setFont(font)
            love.graphics.setColor(self.C.MONEY)
            love.graphics.printf(label, tx, ty + 2, tag_w, "center")
        end
    end
end

function Game:draw_shop_offer_buy_button()
    if self.STATE ~= self.STATES.SHOP then return end
    local selected = self.active_tooltip_joker
    local is_shop_offer = false
    for _, n in ipairs(self.shop_offer_nodes or {}) do
        if n == selected then
            is_shop_offer = true
            break
        end
    end
    if not selected or not is_shop_offer then return end
    local slot = tonumber(selected.shop_offer_slot)
    local offer = slot and self.shop_offers and self.shop_offers[slot] or nil
    if not offer then return end
    local rect = selected.get_collision_rect and selected:get_collision_rect() or nil
    if not rect then return end

    local font = (self.FONTS and self.FONTS.PIXEL and self.FONTS.PIXEL.SMALL) or love.graphics.getFont()
    local prev_font = love.graphics.getFont()
    local prev_r, prev_g, prev_b, prev_a = love.graphics.getColor()
    love.graphics.setFont(font)

    local can_afford = (tonumber(self.money) or 0) >= (tonumber(offer.price) or 0)
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
    -- Prefer right side of card; fallback left.
    local bx = rect.x + rect.w + gap
    if bx + btn_w > (sw - margin) then
        bx = rect.x - btn_w - gap
    end
    if bx < margin then bx = margin end
    local by = rect.y + math.floor((rect.h - btn_h) * 0.5 + 0.5)
    if by < margin then by = margin end
    local is_consumable_offer = offer.kind == "tarot" or offer.kind == "planet"
    local can_buy = can_afford and (not is_consumable_offer or self:can_add_consumable())
    local fill_c = can_buy and self.C.MONEY or self.C.GREY
    local shadow_c = self.C and self.C.BLOCK and self.C.BLOCK.SHADOW

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
    love.graphics.setColor(self.C.WHITE)
    local text_y = by + math.floor((btn_h - font:getHeight()) * 0.5 + 0.5)
    love.graphics.printf(label, bx, text_y, btn_w, "center")

    if can_buy then
        self._shop_buy_button_hit = { x = bx, y = by, w = btn_w, h = btn_h, slot_index = slot }
    end

    love.graphics.setFont(prev_font)
    love.graphics.setColor(prev_r, prev_g, prev_b, prev_a)
end

function Game:add(node)
    table.insert(self.nodes, node)
    return node
end

function Game:set_state(state_id)
    self.STATE = state_id
end

function Game:get_base_requirement_for_ante(ante)
    local base_table = self.BASE_REQUIREMENT_BY_ANTE or {}
    local a = math.max(1, tonumber(ante) or 1)
    if base_table[a] then
        return tonumber(base_table[a]) or 0
    end
    local max_ante = 1
    for k, _ in pairs(base_table) do
        if k > max_ante then max_ante = k end
    end
    local last_base = tonumber(base_table[max_ante]) or 300
    local overflow = math.max(0, a - max_ante)
    return math.floor(last_base * (1 + overflow * 0.6))
end

function Game:get_blind_def(index)
    local defs = self.BLIND_DEFS or {}
    return defs[index]
end

--- Blinds with `boss.showdown` are legal only on ante 8, 16, 24, …
function Game:is_showdown_ante(ante)
    local a = math.max(1, tonumber(ante) or tonumber(self.ante) or 1)
    return a >= 8 and (a % 8) == 0
end

---Boss pool for rolling; blinds with `boss.showdown` only appear on ante 8, 16, 24, ...
---@param ante number|nil Defaults to `self.ante`
function Game:get_boss_blind_pool(ante)
    local allow_showdown = self:is_showdown_ante(ante)
    local out = {}
    for key, blind in pairs(self.P_BLINDS or {}) do
        if key ~= "bl_small" and key ~= "bl_big" and type(blind) == "table" and type(blind.boss) == "table" then
            if blind.boss.showdown == true then
                if allow_showdown then
                    out[#out + 1] = key
                end
            else
                out[#out + 1] = key
            end
        end
    end
    table.sort(out)
    return out
end

function Game:roll_boss_blind()
    local pool = self:get_boss_blind_pool()
    if #pool == 0 then
        self.current_boss_blind_id = nil
        return nil
    end
    self.current_boss_blind_id = pool[math.random(#pool)]
    return self.current_boss_blind_id
end

function Game:get_boss_blind_prototype()
    local key = self.current_boss_blind_id
    if not key or not self.P_BLINDS or not self.P_BLINDS[key] then
        key = self:roll_boss_blind()
    else
        local proto = self.P_BLINDS[key]
        local boss = type(proto) == "table" and proto.boss
        if type(boss) == "table" then
            local is_showdown_ante = self:is_showdown_ante()
            local is_showdown_boss = (boss.showdown == true)
            if is_showdown_ante ~= is_showdown_boss then
                key = self:roll_boss_blind()
            end
        end
    end
    return key and self.P_BLINDS and self.P_BLINDS[key] or nil
end

function Game:get_blind_display_name(index)
    local def = self:get_blind_def(index)
    if not def then return "Blind" end
    if def.id == "boss" then
        local proto = self:get_boss_blind_prototype()
        if proto and proto.name then return proto.name end
    end
    return def.name or "Blind"
end

function Game:get_boss_effect_text()
    local boss_id = self.current_boss_blind_id
    if not boss_id then
        local p = self:get_boss_blind_prototype()
        if p then boss_id = self.current_boss_blind_id end
    end
    local t = {
        bl_hook = "After each hand, discard 2 random held cards.",
        bl_ox = "Playing your most played hand sets money to $0.",
        bl_house = "First hand is drawn face down.",
        bl_wall = "Extra large blind.",
        bl_wheel = "1 in 7 drawn cards are face down.",
        bl_arm = "Decrease level of played poker hand by 1.",
        bl_club = "All Club cards are debuffed.",
        bl_fish = "Cards drawn after each hand are face down.",
        bl_psychic = "Must play 5 cards.",
        bl_goad = "All Spade cards are debuffed.",
        bl_water = "Start with 0 discards.",
        bl_window = "All Diamond cards are debuffed.",
        bl_manacle = "-1 hand size.",
        bl_eye = "No repeat hand types this round.",
        bl_mouth = "Can only score one hand type this round.",
        bl_plant = "All face cards are debuffed.",
        bl_serpent = "After play/discard, always draw 3 cards.",
        bl_pillar = "Cards played this Ante are debuffed.",
        bl_needle = "Play only 1 hand.",
        bl_head = "All Heart cards are debuffed.",
        bl_tooth = "Lose $1 per card played.",
        bl_flint = "Base chips and mult are halved.",
        bl_mark = "All face cards are drawn face down.",
        bl_final_acorn = "Flips and shuffles all Jokers.",
        bl_final_leaf = "All cards debuffed until 1 Joker sold.",
        bl_final_vessel = "Very large blind.",
        bl_final_heart = "One random Joker disabled each hand.",
        bl_final_bell = "Forces 1 selected card each hand.",
    }
    return t[boss_id] or ""
end

function Game:get_blind_color(index)
    local def = self:get_blind_def(index)
    if not def then return self.C.BLIND_COLORS.Big end
    if def.id == "boss" then
        local proto = self:get_boss_blind_prototype()
        if proto and proto.boss_colour then
            return proto.boss_colour
        end
    end
    return self.C.BLIND_COLORS[def.key] or self.C.BLIND_COLORS.Big
end

function Game:get_blind_reward(index)
    local def = self:get_blind_def(index)
    if not def then return 0 end
    return tonumber(def.reward) or 0
end

function Game:get_blind_sprite_index(index)
    local def = self:get_blind_def(index)
    if not def then return 0 end
    if def.id == "small" then
        return tonumber(self.P_BLINDS and self.P_BLINDS.bl_small and self.P_BLINDS.bl_small.pos) or 0
    end
    if def.id == "big" then
        return tonumber(self.P_BLINDS and self.P_BLINDS.bl_big and self.P_BLINDS.bl_big.pos) or 1
    end
    local proto = self:get_boss_blind_prototype()
    return tonumber(proto and proto.pos) or 2
end

function Game:get_blind_target(index, ante)
    local def = self:get_blind_def(index)
    if not def then return 0 end
    local base = self:get_base_requirement_for_ante(ante or self.ante or 1)
    local mult = tonumber(def.multiplier) or 1
    if def.id == "boss" then
        local proto = self:get_boss_blind_prototype()
        mult = tonumber(proto and proto.mult) or mult
    end
    return math.floor(base * mult)
end

function Game:get_preview_blind()
    return self:get_blind_def(self.selected_blind_index or self.current_blind_index or 1)
end

function Game:is_blind_selectable(index)
    return tonumber(index) == tonumber(self.current_blind_index)
end

function Game:remove(node)
    for i, n in ipairs(self.nodes) do
        if n == node then
            table.remove(self.nodes, i)
            return true
        end
    end
    return false
end

function Game:init_item_prototypes()
    self.P_TAGS = {
        tag_uncommon =      {name = 'Uncommon Tag',     set = 'Tag', discovered = false, min_ante = nil, order = 1, config = {type = 'store_joker_create'}, pos = {x = 0,y = 0}},
        tag_rare =          {name = 'Rare Tag',         set = 'Tag', discovered = false, min_ante = nil, order = 2, config = {type = 'store_joker_create', odds = 3}, requires = 'j_blueprint', pos = {x = 1,y = 0}},
        tag_negative =      {name = 'Negative Tag',     set = 'Tag', discovered = false, min_ante = 2,   order = 3, config = {type = 'store_joker_modify', edition = 'negative', odds = 5}, requires = 'e_negative', pos = {x = 2, y = 0}},
        tag_foil =          {name = 'Foil Tag',         set = 'Tag', discovered = false, min_ante = nil, order = 4, config = {type = 'store_joker_modify', edition = 'foil', odds = 2}, requires = 'e_foil', pos = {x = 3,y = 0}},
        tag_holo =          {name = 'Holographic Tag',  set = 'Tag', discovered = false, min_ante = nil, order = 5, config = {type = 'store_joker_modify', edition = 'holo', odds = 3}, requires = 'e_holo', pos = {x = 0,y = 1}},
        tag_polychrome =    {name = 'Polychrome Tag',   set = 'Tag', discovered = false, min_ante = nil, order = 6, config = {type = 'store_joker_modify', edition = 'polychrome', odds = 4}, requires = 'e_polychrome', pos = {x = 1,y = 1}},
        tag_investment =    {name = 'Investment Tag',   set = 'Tag', discovered = false, min_ante = nil, order = 7, config = {type = 'eval', dollars = 25}, pos = {x = 2,y = 1}},
        tag_voucher =       {name = 'Voucher Tag',      set = 'Tag', discovered = false, min_ante = nil, order = 8, config = {type = 'voucher_add'}, pos = {x = 3,y = 1}},
        tag_boss =          {name = 'Boss Tag',         set = 'Tag', discovered = false, min_ante = nil, order = 9, config = {type = 'new_blind_choice', }, pos = {x = 0,y = 2}},
        tag_standard =      {name = 'Standard Tag',     set = 'Tag', discovered = false, min_ante = 2,   order = 10, config = {type = 'new_blind_choice', }, pos = {x = 1,y = 2}},
        tag_charm =         {name = 'Charm Tag',        set = 'Tag', discovered = false, min_ante = nil, order = 11, config = {type = 'new_blind_choice', }, pos = {x = 2,y = 2}},
        tag_meteor =        {name = 'Meteor Tag',       set = 'Tag', discovered = false, min_ante = 2,   order = 12, config = {type = 'new_blind_choice', }, pos = {x = 3,y = 2}},
        tag_buffoon =       {name = 'Buffoon Tag',      set = 'Tag', discovered = false, min_ante = 2,   order = 13, config = {type = 'new_blind_choice', }, pos = {x = 4,y = 2}},
        tag_handy =         {name = 'Handy Tag',        set = 'Tag', discovered = false, min_ante = 2,   order = 14, config = {type = 'immediate', dollars_per_hand = 1}, pos = {x = 1,y = 3}},
        tag_garbage =       {name = 'Garbage Tag',      set = 'Tag', discovered = false, min_ante = 2,   order = 15, config = {type = 'immediate', dollars_per_discard = 1}, pos = {x = 2,y = 3}},
        tag_ethereal =      {name = 'Ethereal Tag',     set = 'Tag', discovered = false, min_ante = 2,   order = 16, config = {type = 'new_blind_choice'}, pos = {x = 3,y = 3}},
        tag_coupon =        {name = 'Coupon Tag',       set = 'Tag', discovered = false, min_ante = nil, order = 17, config = {type = 'shop_final_pass', }, pos = {x = 4,y = 0}},
        tag_double =        {name = 'Double Tag',       set = 'Tag', discovered = false, min_ante = nil, order = 18, config = {type = 'tag_add', }, pos = {x = 5,y = 0}},
        tag_juggle =        {name = 'Juggle Tag',       set = 'Tag', discovered = false, min_ante = nil, order = 19, config = {type = 'round_start_bonus', h_size = 3}, pos = {x = 5,y = 1}},
        tag_d_six =         {name = 'D6 Tag',           set = 'Tag', discovered = false, min_ante = nil, order = 20, config = {type = 'shop_start', }, pos = {x = 5,y = 3}},
        tag_top_up =        {name = 'Top-up Tag',       set = 'Tag', discovered = false, min_ante = 2,   order = 21, config = {type = 'immediate', spawn_jokers = 2}, pos = {x = 4,y = 1}},
        tag_skip =          {name = 'Skip Tag',         set = 'Tag', discovered = false, min_ante = nil, order = 22, config = {type = 'immediate', skip_bonus = 5}, pos = {x = 0,y = 3}},
        tag_orbital =       {name = 'Orbital Tag',      set = 'Tag', discovered = false, min_ante = 2,   order = 23, config = {type = 'immediate', levels = 3}, pos = {x = 5,y = 2}},
        tag_economy =       {name = 'Economy Tag',      set = 'Tag', discovered = false, min_ante = nil, order = 24, config = {type = 'immediate', max = 40}, pos = {x = 4,y = 3}},
    }
    self.tag_undiscovered = {name = 'Not Discovered', order = 1, config = {type = ''}, pos = {x=3,y=4}}

    self.P_STAKES = {
        stake_white =   {name = 'White Chip',   unlocked = true,  order = 1, pos = {x = 0,y = 0}, stake_level = 1, set = 'Stake'},
        stake_red =     {name = 'Red Chip',     unlocked = false, order = 2, pos = {x = 1,y = 0}, stake_level = 2, set = 'Stake'},
        stake_green =   {name = 'Green Chip',   unlocked = false, order = 3, pos = {x = 2,y = 0}, stake_level = 3, set = 'Stake'},  
        stake_black =   {name = 'Black Chip',   unlocked = false, order = 4, pos = {x = 4,y = 0}, stake_level = 4, set = 'Stake'},
        stake_blue =    {name = 'Blue Chip',    unlocked = false, order = 5, pos = {x = 3,y = 0}, stake_level = 5, set = 'Stake'},
        stake_purple =  {name = 'Purple Chip',  unlocked = false, order = 6, pos = {x = 0,y = 1}, stake_level = 6, set = 'Stake'},
        stake_orange =  {name = 'Orange Chip',  unlocked = false, order = 7, pos = {x = 1,y = 1}, stake_level = 7, set = 'Stake'},
        stake_gold =    {name = 'Gold Chip',    unlocked = false, order = 8, pos = {x = 2,y = 1}, stake_level = 8, set = 'Stake'},
    }

    self.P_BLINDS = {
        bl_small =           {name = 'Small Blind',  defeated = false, order = 1, dollars = 3, mult = 1,  vars = {}, debuff_text = '', debuff = {}, pos = 0},
        bl_big =             {name = 'Big Blind',    defeated = false, order = 2, dollars = 4, mult = 1.5,vars = {}, debuff_text = '', debuff = {}, pos = 1},
        bl_ox =              {name = 'The Ox',       defeated = false, order = 4, dollars = 5, mult = 2,  vars = {'ph_most_played'}, debuff = {}, pos = 2, boss = {min = 6, max = 10}, boss_colour = HEX('b95b08')},
        bl_hook =            {name = 'The Hook',     defeated = false, order = 3, dollars = 5, mult = 2,  vars = {}, debuff = {}, pos = 7, boss = {min = 1, max = 10}, boss_colour = HEX('a84024')},
        bl_mouth =           {name = 'The Mouth',    defeated = false, order = 17, dollars = 5, mult = 2, vars = {}, debuff = {}, pos = 18, boss = {min = 2, max = 10}, boss_colour = HEX('ae718e')},
        bl_fish =            {name = 'The Fish',     defeated = false, order = 10, dollars = 5, mult = 2, vars = {}, debuff = {}, pos = 5, boss = {min = 2, max = 10}, boss_colour = HEX('3e85bd')},
        bl_club =            {name = 'The Club',     defeated = false, order = 9, dollars = 5, mult = 2,  vars = {}, debuff = {suit = 'Clubs'}, pos = 4, boss = {min = 1, max = 10}, boss_colour = HEX('b9cb92')},
        bl_manacle =         {name = 'The Manacle',  defeated = false, order = 15, dollars = 5, mult = 2, vars = {}, debuff = {}, pos = 8, boss = {min = 1, max = 10}, boss_colour = HEX('575757')},
        bl_tooth =           {name = 'The Tooth',    defeated = false, order = 23, dollars = 5, mult = 2, vars = {}, debuff = {}, pos = 22, boss = {min = 3, max = 10}, boss_colour = HEX('b52d2d')},
        bl_wall =            {name = 'The Wall',     defeated = false, order = 6, dollars = 5, mult = 4,  vars = {}, debuff = {}, pos = 9, boss = {min = 2, max = 10}, boss_colour = HEX('8a59a5')},
        bl_house =           {name = 'The House',    defeated = false, order = 5, dollars = 5, mult = 2,  vars = {}, debuff = {}, pos = 3, boss ={min = 2, max = 10}, boss_colour = HEX('5186a8')},
        bl_mark =            {name = 'The Mark',     defeated = false, order = 25, dollars = 5, mult = 2, vars = {}, debuff = {}, pos = 23, boss = {min = 2, max = 10}, boss_colour = HEX('6a3847')},
        bl_final_bell =      {name = 'Cerulean Bell',defeated = false, order = 30, dollars = 8, mult = 2, vars = {}, debuff = {}, pos = 26, boss = {showdown = true, min = 10, max = 10}, boss_colour = HEX('009cfd')},
        bl_wheel =           {name = 'The Wheel',    defeated = false, order = 7, dollars = 5, mult = 2,  vars = {}, debuff = {}, pos = 10, boss = {min = 2, max = 10}, boss_colour = HEX('50bf7c')},
        bl_arm =             {name = 'The Arm',      defeated = false, order = 8, dollars = 5, mult = 2,  vars = {}, debuff = {}, pos = 11, boss = {min = 2, max = 10}, boss_colour = HEX('6865f3')},
        bl_psychic =         {name = 'The Psychic',  defeated = false, order = 11, dollars = 5, mult = 2, vars = {}, debuff = {h_size_ge = 5}, pos = 12, boss = {min = 1, max = 10}, boss_colour = HEX('efc03c')},
        bl_goad =            {name = 'The Goad',     defeated = false, order = 12, dollars = 5, mult = 2, vars = {}, debuff = {suit = 'Spades'}, pos = 13, boss = {min = 1, max = 10}, boss_colour = HEX('b95c96')},
        bl_water =           {name = 'The Water',    defeated = false, order = 13, dollars = 5, mult = 2, vars = {}, debuff = {}, pos = 14, boss = {min = 2, max = 10}, boss_colour = HEX('c6e0eb')},
        bl_eye =             {name = 'The Eye',      defeated = false, order = 16, dollars = 5, mult = 2, vars = {}, debuff = {}, pos = 17, boss = {min = 3, max = 10}, boss_colour = HEX('4b71e4')},
        bl_plant =           {name = 'The Plant',    defeated = false, order = 18, dollars = 5, mult = 2, vars = {}, debuff = {is_face = 'face'}, pos = 19, boss = {min = 4, max = 10}, boss_colour = HEX('709284')},
        bl_needle =          {name = 'The Needle',   defeated = false, order = 21, dollars = 5, mult = 1, vars = {}, debuff = {}, pos = 20, boss = {min = 2, max = 10}, boss_colour = HEX('5c6e31')},
        bl_head =            {name = 'The Head',     defeated = false, order = 22, dollars = 5, mult = 2, vars = {}, debuff = {suit = 'Hearts'}, pos = 21, boss = {min = 1, max = 10}, boss_colour = HEX('ac9db4')},
        bl_final_leaf =      {name = 'Verdant Leaf', defeated = false, order = 27, dollars = 8, mult = 2, vars = {}, debuff = {}, pos = 28, boss = {showdown = true, min = 10, max = 10}, boss_colour = HEX('56a786')},
        bl_final_vessel =    {name = 'Violet Vessel',defeated = false, order = 28, dollars = 8, mult = 6, vars = {}, debuff = {}, pos = 29, boss = {showdown = true, min = 10, max = 10}, boss_colour = HEX('8a71e1')},
        bl_window =          {name = 'The Window',   defeated = false, order = 14, dollars = 5, mult = 2, vars = {}, debuff = {suit = 'Diamonds'}, pos = 6, boss = {min = 1, max = 10}, boss_colour = HEX('a9a295')},
        bl_serpent =         {name = 'The Serpent',  defeated = false, order = 19, dollars = 5, mult = 2, vars = {}, debuff = {}, pos = 15, boss = {min = 5, max = 10}, boss_colour = HEX('439a4f')},
        bl_pillar =          {name = 'The Pillar',   defeated = false, order = 20, dollars = 5, mult = 2, vars = {}, debuff = {}, pos = 16, boss = {min = 1, max = 10}, boss_colour = HEX('7e6752')},
        bl_flint =           {name = 'The Flint',    defeated = false, order = 24, dollars = 5, mult = 2, vars = {}, debuff = {}, pos = 24, boss = {min = 2, max = 10}, boss_colour = HEX('e56a2f')},
        bl_final_acorn =     {name = 'Amber Acorn',  defeated = false, order = 26, dollars = 8, mult = 2, vars = {}, debuff = {}, pos = 27, boss = {showdown = true, min = 10, max = 10}, boss_colour = HEX('fda200')},
        bl_final_heart =     {name = 'Crimson Heart',defeated = false, order = 29, dollars = 8, mult = 2, vars = {}, debuff = {}, pos = 25, boss = {showdown = true, min = 10, max = 10}, boss_colour = HEX('ac3232')},
        
    }
end

function Game:draw()
    if self.STATE == self.STATES.BLIND_SELECT then
        self:draw_bottom_blind_select()
    elseif self.STATE == self.STATES.ROUND_EVAL then
        self:draw_bottom_round_win()
    elseif self.STATE == self.STATES.SHOP then
        self:draw_bottom_shop()
    end

    -- Dark panel behind the joker row (bottom screen): only as wide as owned jokers.
    -- Draw this after bottom-state UI so it remains visible, but before nodes.
    if self.jokers_on_bottom == true and self.jokers and #self.jokers > 0 then
        local slot_w = self.joker_slot_w or 71
        local slot_h = self.joker_slot_h or 95
        local slot_gap = self.joker_slot_gap or 8
        local s = self.joker_slot_scale_bottom or 1

        -- Span is already in screen pixels (fan uses scaled card width when s ~= 1).
        local total_w_base = tonumber(self.joker_row_span_bottom)
            or select(2, self:_compute_fanned_joker_row(
                #self.jokers, 320, slot_w * s, slot_gap * s, 8))
        local panel_x = self.joker_slot_start_x_bottom or 0
        local panel_y = self.joker_slot_y_bottom or 20
        local panel_w = total_w_base
        local panel_h = slot_h * s

        -- Extra padding so jokers don't touch the panel edges.
        local panel_pad = 4
        local panel_pad_scaled = panel_pad * s
        panel_x = panel_x - panel_pad_scaled
        panel_y = panel_y - panel_pad_scaled
        panel_w = panel_w + (panel_pad_scaled * 2)
        panel_h = panel_h + (panel_pad_scaled * 2)

        local prev_r, prev_g, prev_b, prev_a = love.graphics.getColor()
        
        love.graphics.setColor(prev_r, prev_g, prev_b, prev_a)
    end

    self:sync_shop_offer_interactivity()

    -- Hide consumables during blind select + round eval.
    local show_consumables = not (self.STATE == self.STATES.BLIND_SELECT or self.STATE == self.STATES.ROUND_EVAL)
    if not show_consumables then
        self._consumable_rects = {}
        self.active_tooltip_consumable_index = nil
        if self.consumable_nodes then
            for _, node in ipairs(self.consumable_nodes) do
                if node and node.states then
                    node.states.visible = false
                end
            end
        end
    else
        if self.consumable_nodes then
            for _, node in ipairs(self.consumable_nodes) do
                if node and node.states then
                    node.states.visible = true
                end
            end
        end
        -- Layout consumable nodes (top-right) before drawing.
        self:draw_consumables_row()
    end

    -- Ensure node sprites (especially jokers/cards/consumables) are not tinted by prior UI draws.
    love.graphics.setColor(1, 1, 1, 1)

    -- Keep layering stable:
    -- 1) regular nodes, 2) consumables, 3) hand cards on top -- DONT FORGET THIS
    local cons_set = {}
    local hand_set = {}
    if self.consumable_nodes then
        for _, cn in ipairs(self.consumable_nodes) do
            cons_set[cn] = true
        end
    end
    if self.hand and self.hand.card_nodes then
        for _, hn in ipairs(self.hand.card_nodes) do
            hand_set[hn] = true
        end
    end
    local draw_consumables_first = (self.jokers_on_bottom == true)
    if draw_consumables_first and self.consumable_nodes then
        for _, cn in ipairs(self.consumable_nodes) do
            if cn and cn.draw then cn:draw() end
        end
    end
    for _, node in ipairs(self.nodes) do
        if not cons_set[node] and not hand_set[node] then
            node:draw()
        end
    end
    if (not draw_consumables_first) and self.consumable_nodes then
        for _, cn in ipairs(self.consumable_nodes) do
            if cn and cn.draw then cn:draw() end
        end
    end
    if self.hand and self.hand.card_nodes then
        for _, hn in ipairs(self.hand.card_nodes) do
            if hn and hn.draw then hn:draw() end
        end
    end
    self:draw_shop_offer_price_tags()
    self._shop_buy_button_hit = nil
    self:draw_shop_offer_buy_button()

    self._sell_button_hit = nil
    self:draw_sell_button()

    self._use_button_hit = nil
    self:draw_use_button()

    -- Tooltips last so they paint over sprites, hand, and Use/Sell (etc.).
    self:draw_tooltips_on_top()
end

--- Draw all bottom-screen card / joker / consumable tooltips after other UI.
function Game:draw_tooltips_on_top()
    love.graphics.setColor(1, 1, 1, 1)
    if self.nodes then
        for _, node in ipairs(self.nodes) do
            if Joker and node and node.is and node:is(Joker) and node.draw_tooltip_overlay then
                node:draw_tooltip_overlay()
            end
            if Consumable and node and node.is and node:is(Consumable) and node.shop_offer_slot and node.draw_tooltip_overlay then
                node:draw_tooltip_overlay()
            end
        end
    end
    if self.consumable_nodes then
        for _, cn in ipairs(self.consumable_nodes) do
            if cn and cn.draw_tooltip_overlay then
                cn:draw_tooltip_overlay()
            end
        end
    end
    if self.hand and self.hand.card_nodes then
        for _, hn in ipairs(self.hand.card_nodes) do
            if hn and hn.draw_tooltip_overlay then
                hn:draw_tooltip_overlay()
            end
        end
    end
end

--- Add a Consumable by definition id (see `CONSUMABLE_DEFS` in `consumable_catalog.lua`).
---@param def_id string
---@return boolean
function Game:add_consumable(def_id)
    if type(def_id) ~= "string" or def_id == "" then return false end
    if not CONSUMABLE_DEFS or type(CONSUMABLE_DEFS) ~= "table" then return false end
    local def = CONSUMABLE_DEFS[def_id]
    if type(def) ~= "table" then return false end

    if not self.consumables then self.consumables = {} end
    if not self.consumable_nodes then self.consumable_nodes = {} end
    local cap = tonumber(self.consumable_capacity) or 3
    if #self.consumables >= cap then return false end

    local copy = copy_table(def)
    table.insert(self.consumables, copy)

    local idx = #self.consumables
    local node = Consumable(0, 0, copy)
    self.consumable_nodes[idx] = node
    self:add(node)

    self:draw_consumables_row()
    return true
end

---@return boolean
function Game:can_add_consumable()
    local cap = tonumber(self.consumable_capacity) or 2
    return #(self.consumables or {}) < cap
end

---@param index integer
---@return table|nil
function Game:remove_consumable_at(index)
    if type(index) ~= "number" or index < 1 then return nil end
    if not self.consumables or type(self.consumables) ~= "table" then return nil end
    local c = self.consumables[index]
    if not c then return nil end
    table.remove(self.consumables, index)

    if self.consumable_nodes and self.consumable_nodes[index] then
        local node = self.consumable_nodes[index]
        self:remove(node)
        table.remove(self.consumable_nodes, index)
    end

    if self.active_tooltip_consumable_index and
       self.active_tooltip_consumable_index >= index then
        self.active_tooltip_consumable_index =
            math.min(#self.consumables, self.active_tooltip_consumable_index)
    end

    self:draw_consumables_row()
    return c
end

function Game:consumable_slots_after_use_index(index)
    local n = #(self.consumables or {})
    local cap = tonumber(self.consumable_capacity) or 2
    return math.max(0, cap - (n - 1))
end

function Game:consumable_play_state_ok()
    local s = self.STATE
    return s == self.STATES.SELECTING_HAND or s == self.STATES.SHOP
end

function Game:hand_ready_for_tarot_selection()
    if self.STATE ~= self.STATES.SELECTING_HAND then return false end
    if not self.hand then return false end
    if self.hand.is_scoring_active and self.hand:is_scoring_active() then return false end
    return true
end

function Game:ordered_selected_hand_count()
    if not self.hand or not self.hand.ordered_selected_nodes then return 0 end
    return #self.hand:ordered_selected_nodes()
end

function Game:joker_has_room_for_new(edition)
    edition = Joker and Joker.normalize_edition(edition) or "base"
    if not self.jokers then return true end
    local neg_owned = 0
    for _, jj in ipairs(self.jokers) do
        if jj and Joker.normalize_edition(jj.edition) == "negative" then
            neg_owned = neg_owned + 1
        end
    end
    local new_is_neg = edition == "negative"
    local cap_after = (self.joker_base_capacity or 5) + neg_owned + (new_is_neg and 1 or 0)
    return #self.jokers < cap_after
end

function Game:tarot_selection_requirement_met(c)
    local sel = c and c.select
    if type(sel) ~= "table" then return true end
    local n = self:ordered_selected_hand_count()
    if sel.exact ~= nil then
        return n == tonumber(sel.exact)
    end
    local smin = tonumber(sel.min)
    local smax = tonumber(sel.max)
    if smin and n < smin then return false end
    if smax and n > smax then return false end
    return true
end

function Game:consumable_use_enabled(idx)
    if self.jokers_on_bottom == true then return false end
    if not self:consumable_play_state_ok() then return false end
    local c = self.consumables and self.consumables[idx]
    if not c or type(c) ~= "table" then return false end

    if c.kind == "tarot" then
        local need_hand = false
        local s = c.select
        if type(s) == "table" and (s.exact or 0) > 0 then
            need_hand = true
        end
        if type(s) == "table" and s.min and tonumber(s.min) > 0 then
            need_hand = true
        end
        if c.spawn or c.spawn_joker or c.wheel_of_fortune or c.fool_duplicate
            or c.hermit_money or c.temperance_money then
            -- no hand required
        elseif need_hand and not self:hand_ready_for_tarot_selection() then
            return false
        end
        if need_hand and not self:tarot_selection_requirement_met(c) then
            return false
        end
        if c.spawn then
            if self:consumable_slots_after_use_index(idx) < 1 then return false end
        end
        if c.fool_duplicate then
            local last = self.last_consumable_use_id
            if not last or last == "tarot_fool" then return false end
            if not CONSUMABLE_DEFS or not CONSUMABLE_DEFS[last] then return false end
            if self:consumable_slots_after_use_index(idx) < 1 then return false end
        end
        if c.spawn_joker and not self:joker_has_room_for_new("base") then return false end
        if c.wheel_of_fortune then
            if not self.jokers or #self.jokers < 1 then return false end
        end
        return true
    end

    if c.kind == "planet" then
        return true
    end

    return false
end

function Game:record_consumable_use_id(id)
    if id == "tarot_fool" or not id then return end
    self.last_consumable_use_id = id
end

function Game:deep_copy_card_data(data)
    if type(data) ~= "table" then return nil end
    local c = {}
    for k, v in pairs(data) do
        if type(v) == "table" then
            c[k] = self:deep_copy_card_data(v)
        else
            c[k] = v
        end
    end
    return c
end

function Game:random_consumable_id_of_kind(kind, exclude)
    exclude = exclude or {}
    local pool = {}
    if not CONSUMABLE_DEFS then return nil end
    for def_id, def in pairs(CONSUMABLE_DEFS) do
        if type(def) == "table" and def.kind == kind and not exclude[def_id] then
            pool[#pool + 1] = def_id
        end
    end
    if #pool == 0 then return nil end
    return pool[math.random(1, #pool)]
end

function Game:random_non_fool_tarot_id()
    return self:random_consumable_id_of_kind("tarot", { tarot_fool = true })
end

function Game:random_joker_def_id()
    if not JOKER_DEFS then return nil end
    local pool = {}
    for id, def in pairs(JOKER_DEFS) do
        if type(def) == "table" then
            pool[#pool + 1] = id
        end
    end
    if #pool == 0 then return nil end
    return pool[math.random(1, #pool)]
end

--- Apply the runtime effect for a Consumable and play a simple SFX where appropriate.
---@param c table
function Game:apply_consumable_effect(c)
    if type(c) ~= "table" then return end
    local kind = c.kind
    local id = c.id

    if kind == "planet" then
        local target_hand_name = c.hand
        if target_hand_name and self.handlist and self.hand_stats then
            local target_idx = nil
            for i, name in ipairs(self.handlist) do
                if name == target_hand_name then
                    target_idx = i
                    break
                end
            end

            if target_idx then
                local stats = self.hand_stats[target_idx]
                if stats then
                    local next_level = (tonumber(stats.level) or 1) + 1
                    stats.level = next_level
                    if self.selectedHand == target_idx then
                        local level = tonumber(stats.level) or 1
                        local chips = (tonumber(stats.base_chips) or 0) + ((level - 1) * (tonumber(stats.chips_per_level) or 0))
                        local mult = (tonumber(stats.base_mult) or 0) + ((level - 1) * (tonumber(stats.mult_per_level) or 0))
                        self.selectedHandLevel = level
                        self.selectedHandChips = chips
                        self.selectedHandMult = mult
                    end
                end
            end
        end
        self:record_consumable_use_id(id)
        if Sfx and Sfx.play_mult then Sfx.play_mult() end
        return
    end

    if kind ~= "tarot" then return end

    local hand = self.hand
    local function ordered_nodes()
        return (hand and hand.ordered_selected_nodes and hand:ordered_selected_nodes()) or {}
    end

    local function clear_tarot_hand_ui()
        if hand and hand.clear_selection then
            hand:clear_selection()
        end
        self.active_tooltip_card = nil
    end

    if id == "tarot_fool" then
        local last_id = self.last_consumable_use_id
        if last_id and last_id ~= "tarot_fool" then
            self:add_consumable(last_id)
            if Sfx and Sfx.play_money then Sfx.play_money() end
        end
        clear_tarot_hand_ui()
        return
    end

    local ord = ordered_nodes()

    if id == "tarot_magician" then
        for i = 1, math.min(2, #ord) do
            ord[i]:set_enhancement("lucky")
        end
    elseif id == "tarot_high_priestess" then
        local free = math.max(0, (tonumber(self.consumable_capacity) or 2) - #(self.consumables or {}))
        local k = math.min(2, free)
        for _ = 1, k do
            local pid = self:random_consumable_id_of_kind("planet", {})
            if pid then self:add_consumable(pid) end
        end
    elseif id == "tarot_empress" then
        for i = 1, math.min(2, #ord) do
            ord[i]:set_enhancement("mult")
        end
    elseif id == "tarot_emperor" then
        local free = math.max(0, (tonumber(self.consumable_capacity) or 2) - #(self.consumables or {}))
        local k = math.min(2, free)
        for _ = 1, k do
            local tid = self:random_consumable_id_of_kind("tarot")
            if tid then self:add_consumable(tid) end
        end
    elseif id == "tarot_hierophant" then
        for i = 1, math.min(2, #ord) do
            ord[i]:set_enhancement("bonus")
        end
    elseif id == "tarot_lovers" then
        if ord[1] then ord[1]:set_enhancement("wild") end
    elseif id == "tarot_chariot" then
        if ord[1] then ord[1]:set_enhancement("steel") end
    elseif id == "tarot_justice" then
        if ord[1] then ord[1]:set_enhancement("glass") end
    elseif id == "tarot_strength" then
        for i = 1, math.min(2, #ord) do
            local data = ord[i].card_data
            if data and type(data.rank) == "number" then
                data.rank = math.min(14, data.rank + 1)
                ord[i]:sync_visual_from_card_data()
            end
        end
    elseif id == "tarot_hermit" then
        local m = tonumber(self.money) or 0
        local gain = math.min(m, 20)
        self.money = m + gain
        if Sfx and Sfx.play_money then Sfx.play_money() end
    elseif id == "tarot_wheel_of_fortune" then
        if self.jokers and #self.jokers > 0 and math.random(4) == 1 then
            local j = self.jokers[math.random(1, #self.jokers)]
            local opts = { "foil", "holo", "polychrome" }
            if Joker and j then
                j.edition = Joker.normalize_edition(opts[math.random(1, #opts)])
                if j.refresh_quads then j:refresh_quads() end
                self:refresh_joker_capacity_from_negatives()
            end
        end
    elseif id == "tarot_hanged_man" then
        local to_destroy = {}
        for i = 1, math.min(2, #ord) do
            to_destroy[#to_destroy + 1] = ord[i]
        end
        for _, node in ipairs(to_destroy) do
            if hand and hand.destroy_card_node then
                hand:destroy_card_node(node)
            end
        end
    elseif id == "tarot_death" then
        if #ord >= 2 then
            local left, right = ord[1], ord[2]
            if right.card_data then
                left.card_data = self:deep_copy_card_data(right.card_data)
                left:sync_visual_from_card_data()
            end
        end
    elseif id == "tarot_temperance" then
        local total = 0
        for _, j in ipairs(self.jokers or {}) do
            total = total + (tonumber(j and j.sell_cost) or 0)
        end
        local gain = math.min(total, 50)
        self.money = (tonumber(self.money) or 0) + gain
        if Sfx and Sfx.play_money then Sfx.play_money() end
    elseif id == "tarot_devil" then
        if ord[1] then ord[1]:set_enhancement("gold") end
    elseif id == "tarot_tower" then
        if ord[1] then ord[1]:set_enhancement("stone") end
    elseif id == "tarot_star" then
        for i = 1, math.min(3, #ord) do
            local cd = ord[i].card_data
            if cd then cd.suit = "Diamonds" end
            ord[i]:sync_visual_from_card_data()
        end
    elseif id == "tarot_moon" then
        for i = 1, math.min(3, #ord) do
            local cd = ord[i].card_data
            if cd then cd.suit = "Clubs" end
            ord[i]:sync_visual_from_card_data()
        end
    elseif id == "tarot_sun" then
        for i = 1, math.min(3, #ord) do
            local cd = ord[i].card_data
            if cd then cd.suit = "Hearts" end
            ord[i]:sync_visual_from_card_data()
        end
    elseif id == "tarot_world" then
        for i = 1, math.min(3, #ord) do
            local cd = ord[i].card_data
            if cd then cd.suit = "Spades" end
            ord[i]:sync_visual_from_card_data()
        end
    elseif id == "tarot_judgement" then
        local jid = self:random_joker_def_id()
        if jid then self:add_joker_by_def(jid) end
    end

    self:record_consumable_use_id(id)
    if id ~= "tarot_hanged_man" then
        clear_tarot_hand_ui()
    else
        self.active_tooltip_card = nil
        if hand and hand.calculate_play then hand:calculate_play() end
    end

    local sfx_mult = id ~= "tarot_hermit" and id ~= "tarot_temperance"
        and id ~= "tarot_wheel_of_fortune" and id ~= "tarot_high_priestess"
        and id ~= "tarot_emperor" and id ~= "tarot_judgement"
    if sfx_mult and Sfx and Sfx.play_mult then
        Sfx.play_mult()
    end
end

--- Use (consume) a Consumable at the given index.
---@param index integer
---@return boolean
function Game:use_consumable(index)
    if not self:consumable_use_enabled(index) then return false end
    local c = self:remove_consumable_at(index)
    if not c then return false end
    self:emit_joker_event("on_consumable_used", {
        consumable = c,
        consumable_id = c.id,
        consumable_kind = c.kind,
    })
    self:apply_consumable_effect(c)
    return true
end

--- Draw Consumable cards (Tarot / Planet) as small sprites in the top-right area of the bottom screen.
function Game:draw_consumables_row()
    local list = self.consumables or {}
    local nodes = self.consumable_nodes or {}
    self._consumable_rects = {}
    if #list == 0 then return end

    local sw = 320
    if love.graphics.getWidth then
        sw = love.graphics.getWidth("bottom")
        if not sw or sw <= 0 then sw = love.graphics.getWidth() end
    end
    if not sw or sw <= 0 then sw = 320 end

    local card_w, card_h = 72, 95
    local cons_scale = (self.STATE == self.STATES.SHOP) and 0.85 or 1
    local draw_w, draw_h = card_w * cons_scale, card_h * cons_scale
    local gap = -4
    local right_margin = 0
    local y = -30

    local n = #list
    local max_span = math.max(draw_w, sw - right_margin)

    local step, span
    if n <= 1 then
        step = 0
        span = draw_w
    else
        local natural_span = n * draw_w + (n - 1) * gap
        if natural_span <= max_span then
            step = draw_w + gap
            span = natural_span
        else
            step = (max_span - draw_w) / (n - 1)
            span = (n - 1) * step + draw_w
        end
    end

    -- Right-align the row so it's always in the top-right corner.
    local start_x = (sw - right_margin) - span

    for i = 1, n do
        local node = nodes[i]
        local x = start_x + (i - 1) * step
        if node then
            node.T.x = x
            node.T.y = y
            node.T.r = 0
            node.T.scale = cons_scale
            if node.VT then
                -- Snap VT when not being dragged so layout updates immediately.
                if self.dragging ~= node then
                    node.VT.x = x
                    node.VT.y = y
                    node.VT.r = 0
                    node.VT.scale = cons_scale
                end
            end
        end

        self._consumable_rects[i] = { x = x, y = y, w = draw_w, h = draw_h }
    end

end

--- What can be sold this frame (extend with new `kind` values later).
---@return { kind: string, index: number, node: Joker|nil }|nil
function Game:get_active_sell_target()
    -- Consumable sell button (enabled whenever a consumable is selected).
    local idx = self.active_tooltip_consumable_index
    local c = idx and self.consumables and self.consumables[idx]
    if c then
        return { kind = "consumable", index = idx, node = nil }
    end

    if self.jokers_on_bottom ~= true then return nil end
    local j = self.active_tooltip_joker
    if j then
        for i, jj in ipairs(self.jokers or {}) do
            if jj == j then
                return { kind = "joker", index = i, node = j }
            end
        end
    end
    return nil
end

function Game:get_sell_anchor_rect(sell_target)
    if not sell_target then return nil end
    if sell_target.kind == "joker" then
        local node = sell_target.node
        if node and node.get_collision_rect then
            return node:get_collision_rect()
        end
    elseif sell_target.kind == "consumable" then
        local idx = sell_target.index
        if self._consumable_rects and self._consumable_rects[idx] then
            return self._consumable_rects[idx]
        end
    end
    return nil
end

function Game:perform_sell_for_target(sell_target)
    if not sell_target then return false end
    if sell_target.kind == "joker" then
        return self:sell_owned_joker(sell_target.index)
    elseif sell_target.kind == "consumable" then
        local idx = sell_target.index
        local c = self:remove_consumable_at(idx)
        if not c then return false end
        local value = tonumber(c.sell_cost) or 0
        self.money = (tonumber(self.money) or 0) + value
        if self.active_tooltip_consumable_index == idx then
            self.active_tooltip_consumable_index = nil
        end
        return true
    end
    -- Future kinds: vouchers, boosters, etc.
    return false
end

--- One Sell control under the currently selected sellable item (joker tooltip = selection for now).
function Game:draw_sell_button()
    local target = self:get_active_sell_target()
    local anchor = self:get_sell_anchor_rect(target)
    if not anchor then return end

    local font = (self.FONTS and self.FONTS.PIXEL and self.FONTS.PIXEL.SMALL) or love.graphics.getFont()
    local prev_font = love.graphics.getFont()
    local prev_r, prev_g, prev_b, prev_a = love.graphics.getColor()
    love.graphics.setFont(font)

    local sell_cost = 0
    if target.kind == "joker" and target.node then
        local n = target.node
        sell_cost = math.max(0, math.floor(tonumber(n.sell_cost) or tonumber(n.def and n.def.sell_cost) or 0))
    elseif target.kind == "consumable" then
        local c = self.consumables and self.consumables[target.index]
        sell_cost = math.max(0, math.floor(tonumber(c and c.sell_cost) or 0))
    end
    local label = string.format("Sell $%d", sell_cost)
    local btn_w = math.max(34, font:getWidth(label) + 10)
    local btn_h = math.max(14, font:getHeight() + 4)
    local fill_c = self.C and self.C.PALE_GREEN
    local shadow_c = self.C and self.C.BLOCK and self.C.BLOCK.SHADOW
    local text_c = self.C and self.C.WHITE or { 1, 1, 1, 1 }

    local gap = 4
    local margin = 2
    local sw = 320
    if love.graphics.getWidth then
        sw = love.graphics.getWidth("bottom")
        if not sw or sw <= 0 then sw = love.graphics.getWidth() end
    end
    if not sw or sw <= 0 then sw = 320 end

    -- Prefer placing Sell on the right side of selected item; fallback to left.
    local bx = anchor.x + anchor.w + gap
    if bx + btn_w > (sw - margin) then
        bx = anchor.x - btn_w - gap
    end
    if bx < margin then bx = margin end

    local by = anchor.y + math.floor((anchor.h - btn_h) * 0.5 + 0.5)
    if target.kind == "consumable" then
        -- Place Sell below the consumable
        local by_use = by
        by = by_use + btn_h + 2
    end
    if by < margin then by = margin end
    if _G.draw_rect_with_shadow and fill_c and shadow_c then
        draw_rect_with_shadow(bx, by, btn_w, btn_h, 3, 2, fill_c, shadow_c, 1)
    else
        if type(fill_c) == "table" then
            love.graphics.setColor(fill_c[1], fill_c[2], fill_c[3], fill_c[4] or 1)
        else
            love.graphics.setColor(0.15, 0.15, 0.18, 1)
        end
        love.graphics.rectangle("fill", bx, by, btn_w, btn_h, 3, 3)
    end
    love.graphics.setColor(self.C.WHITE)
    local text_y = by + math.floor((btn_h - font:getHeight()) * 0.5 + 0.5)
    love.graphics.printf(label, bx, text_y, btn_w, "center")

    self._sell_button_hit = {
        x = bx, y = by, w = btn_w, h = btn_h,
        target = { kind = target.kind, index = target.index, node = target.node },
    }

    love.graphics.setFont(prev_font)
    love.graphics.setColor(prev_r, prev_g, prev_b, prev_a)
end

--- One Use control under the currently selected consumable.
function Game:draw_use_button()
    if not self.active_tooltip_consumable_index then return end
    if not self.consumables or type(self.consumables) ~= "table" then return end
    local c = self.consumables[self.active_tooltip_consumable_index]
    if not c then return end
    if not self._consumable_rects or not self._consumable_rects[self.active_tooltip_consumable_index] then return end

    local anchor = self._consumable_rects[self.active_tooltip_consumable_index]
    local idx = self.active_tooltip_consumable_index
    local enabled = self:consumable_use_enabled(idx)

    local font = (self.FONTS and self.FONTS.PIXEL and self.FONTS.PIXEL.SMALL) or love.graphics.getFont()
    local prev_font = love.graphics.getFont()
    local prev_r, prev_g, prev_b, prev_a = love.graphics.getColor()
    love.graphics.setFont(font)

    local label = "Use"
    local btn_w = math.max(34, font:getWidth(label) + 10)
    local btn_h = math.max(14, font:getHeight() + 4)
    local fill_c = enabled and (self.C and self.C.ORANGE) or (self.C and self.C.GREY)
    local shadow_c = self.C and self.C.BLOCK and self.C.BLOCK.SHADOW

    local gap = 4
    local margin = 2
    local sw = 320
    if love.graphics.getWidth then
        sw = love.graphics.getWidth("bottom")
        if not sw or sw <= 0 then sw = love.graphics.getWidth() end
    end
    if not sw or sw <= 0 then sw = 320 end

    -- Prefer placing Use on the right side of selected item; fallback to left.
    local bx = anchor.x + anchor.w + gap
    if bx + btn_w > (sw - margin) then
        bx = anchor.x - btn_w - gap
    end
    if bx < margin then bx = margin end

    local by = anchor.y + math.floor((anchor.h - btn_h) * 0.5 + 0.5)
    if by < margin then by = margin end

    if _G.draw_rect_with_shadow and fill_c and shadow_c then
        draw_rect_with_shadow(bx, by, btn_w, btn_h, 3, 2, fill_c, shadow_c, 1)
    else
        if type(fill_c) == "table" then
            love.graphics.setColor(fill_c[1], fill_c[2], fill_c[3], fill_c[4] or 1)
        else
            love.graphics.setColor(0.15, 0.15, 0.18, 1)
        end
        love.graphics.rectangle("fill", bx, by, btn_w, btn_h, 3, 3)
    end

    local text_c = enabled and (self.C and self.C.WHITE) or (self.C and self.C.DARK_WHITE)
    love.graphics.setColor(text_c or { 0.85, 0.85, 0.85, 1 })
    local text_y = by + math.floor((btn_h - font:getHeight()) * 0.5 + 0.5)
    love.graphics.printf(label, bx, text_y, btn_w, "center")

    if enabled then
        self._use_button_hit = {
            x = bx, y = by, w = btn_w, h = btn_h,
            target = { kind = "consumable", index = idx },
        }
    else
        self._use_button_hit = nil
    end

    love.graphics.setFont(prev_font)
    love.graphics.setColor(prev_r, prev_g, prev_b, prev_a)
end

function Game:try_sell_button_press(x, y)
    local hit = self._sell_button_hit
    if not hit or not hit.target then return false end
    if not self:_point_in_rect_simple(x, y, hit) then return false end
    -- Consumables become non-interactive when jokers are on bottom.
    if hit.target.kind == "consumable" and self.jokers_on_bottom == true then
        return false
    end
    self.touch_start_x = x
    self.touch_start_y = y
    return self:perform_sell_for_target(hit.target)
end

function Game:try_use_button_press(x, y)
    local hit = self._use_button_hit
    if not hit or not hit.target then return false end
    if not self:_point_in_rect_simple(x, y, hit) then return false end
    -- Consumables become non-interactive when jokers are on bottom.
    if self.jokers_on_bottom == true then
        return false
    end
    local idx = hit.target.index
    if not self:consumable_use_enabled(idx) then
        return false
    end
    local ok = self:use_consumable(idx)
    if ok and self.active_tooltip_consumable_index == idx then
        self.active_tooltip_consumable_index = nil
    end
    self.active_tooltip_card = nil
    self.active_tooltip_joker = nil
    return ok
end

function Game:try_shop_buy_button_press(x, y)
    local hit = self._shop_buy_button_hit
    if not hit then return false end
    if not self:_point_in_rect_simple(x, y, hit) then return false end
    self.touch_start_x = x
    self.touch_start_y = y
    return self:buy_shop_joker(hit.slot_index)
end

function Game:_point_in_rect_simple(px, py, r)
    return r and px >= r.x and px <= (r.x + r.w) and py >= r.y and py <= (r.y + r.h)
end

function Game:draw_blind_chip_anim(blind_index, center_x, center_y, scale)
    local atlas = self.ANIMATION_ATLAS and self.ANIMATION_ATLAS.blind_chips
    if not atlas or not atlas.image then return end
    local cell_w = tonumber(atlas.px) or 36
    local cell_h = tonumber(atlas.py) or 36
    local frames_per_blind = tonumber(atlas.frames) or 1
    local blind_row = tonumber(self:get_blind_sprite_index(blind_index)) or 0
    local anim_fps = 10
    local t = love.timer.getTime()
    local frame = math.floor(t * anim_fps) % math.max(1, frames_per_blind)
    local sprite_index = (blind_row * frames_per_blind) + frame
    local iw, ih = atlas.image:getDimensions()
    local cols = math.max(1, math.floor(iw / cell_w))
    local total_cells = math.floor((iw / cell_w) * (ih / cell_h))
    if sprite_index >= total_cells then
        sprite_index = 0
    end
    local col = sprite_index % cols
    local row = math.floor(sprite_index / cols)
    local qx = col * cell_w
    local qy = row * cell_h
    local quad = love.graphics.newQuad(qx, qy, cell_w, cell_h, iw, ih)
    local s = scale or 1
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(atlas.image, quad, center_x - (cell_w * s * 0.5), center_y - (cell_h * s * 0.5), 0, s, s)
end

--- Horizontal strip: `animation_atli.shop_sign` (px×py per frame, `frames` count).
function Game:draw_shop_sign_anim(center_x, center_y, scale)
    local atlas = self.ANIMATION_ATLAS and self.ANIMATION_ATLAS.shop_sign
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

function Game:draw_bottom_blind_select()
    local card_w, card_h = 98, 300
    local gap = 8
    local start_x = 6
    local y = 8
    self._blind_select_tap_rects = {}
    for i = 1, 3 do
        local def = self:get_blind_def(i)
        local x = start_x + (i - 1) * (card_w + gap)
        local selectable = self:is_blind_selectable(i)
        local target = self:get_blind_target(i, self.ante)
        local card_color = self.C.PANEL
        if not selectable then
            y = 60
        else 
            y = 8
        end
        
        love.graphics.setColor(card_color)
        love.graphics.rectangle("fill", x, y, card_w, card_h, 4, 4)
        local blind_color = self:get_blind_color(i) or self.C.BLOCK.BACK
        love.graphics.setColor(blind_color)
        love.graphics.setLineWidth(3)
        love.graphics.rectangle("line", x, y, card_w, card_h, 4, 4)


        local padding = 16
        love.graphics.setLineWidth(2)
        love.graphics.setColor(self.C.GREY)

        local scorePosY = 105
        local addedHeight = 0
        if def and def.id == "boss" then
            local effect = self:get_boss_effect_text()
            if effect ~= "" then
                local info_w = card_w - 10
                local info_h = 118
                local info_x = x + 5
                local info_y = y + 105
                love.graphics.setColor(self.C.WHITE)
                love.graphics.setFont(self.FONTS.PIXEL.SMALL)
                local num_lines = select(2, string.gsub(effect, "\n", "")) + 1
                love.graphics.printf(effect, info_x + 4, info_y + 4, info_w - 8, "center")
                addedHeight = love.graphics.getFont():getHeight() * num_lines + 2 * padding
            end
            scorePosY = 105 + addedHeight
        end

        if def and def.id == "boss" then
            love.graphics.rectangle("line", x + padding/2, y + padding/2, card_w - padding, 142 + addedHeight, 4, 4)
        else 
            love.graphics.rectangle("line", x + padding/2, y + padding/2, card_w - padding, 142, 4, 4)
        end
        love.graphics.setLineWidth(1)


        local selectText = "Upcoming"
        if selectable then
            selectText = "Select"
        end
        local selectWidth = 60
        local selectHeight = 16
        local offset = 6
        local btn_x = x + math.floor(card_w / 2) - math.floor(selectWidth / 2)
        local btn_y = y + padding/2 + offset
        if selectable then
            draw_rect_with_shadow(btn_x, btn_y, selectWidth, selectHeight, 4, 4, self.C.ORANGE, self.C.BLOCK.SHADOW, 2)
        else
            draw_rect_with_shadow(btn_x, btn_y, selectWidth, selectHeight, 4, 4, self.C.GREY, self.C.BLOCK.SHADOW, 2)
        end
        self._blind_select_tap_rects[i] = { x = btn_x, y = btn_y, w = selectWidth, h = selectHeight }

        love.graphics.setColor(self.C.WHITE)
        love.graphics.setFont(self.FONTS.PIXEL.SMALL)
        local tx = x + math.floor(card_w / 2) - math.floor(selectWidth / 2)
        love.graphics.printf(selectText, tx, btn_y + 2, selectWidth, "center")

        local blindWidth = 70
        local label = self:get_blind_display_name(i)
        love.graphics.setColor(blind_color)
        tx = x + math.floor(card_w / 2) - math.floor(blindWidth / 2)
        love.graphics.rectangle("fill", tx, btn_y + selectHeight + 8, blindWidth, selectHeight, 4, 4)

        tx = x + math.floor(card_w / 2) - math.floor(blindWidth / 2)
        love.graphics.setColor(self.C.WHITE)
        love.graphics.printf(label, tx, btn_y + selectHeight + 8 + 2, blindWidth, "center")
        self:draw_blind_chip_anim(i, x + math.floor(card_w / 2), y + 80, 1.1)

        local scoreWidth = 78
        local scoreHeight = 28
        local reward = self:get_blind_reward(i)

        if reward > 0 then 
            scoreHeight = 44
        end
        love.graphics.setFont(self.FONTS.PIXEL.SMALL)
        love.graphics.setColor(self.C.BLOCK.BACK)
        tx = x + math.floor(card_w / 2) - math.floor(scoreWidth / 2)
        love.graphics.rectangle("fill", tx, y + scorePosY, scoreWidth, scoreHeight, 4, 4)

        love.graphics.setColor(self.C.WHITE)
        ty = y + scorePosY + 3
        love.graphics.print("Score at Least", tx + 6, ty)
        love.graphics.setColor(self.C.RED)
        local req = tostring(target)
        local rx = x + math.floor(card_w / 2) - math.floor(scoreWidth / 2)
        love.graphics.printf(req, rx, ty + 12, scoreWidth, "center")
        
        love.graphics.setColor(self.C.WHITE)
        req = "Reward: "..string.rep("$", reward).."+"
        rx = x + math.floor(card_w / 2) - math.floor(love.graphics.getFont():getWidth(req) / 2)

        love.graphics.print("Reward: ", rx, ty + 24)
        love.graphics.setColor(self.C.MONEY)
        love.graphics.print("$"..string.rep("$", reward).."+", rx + love.graphics.getFont():getWidth("Reward: "), ty + 24)
        
    end
end

function Game:draw_shop_button(param)
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
        local ix, iy, iw, ih = draw_rect_with_shadow(x, y, w, h, 4, 2, color, self.C.BLOCK.SHADOW, 2)
        love.graphics.setColor(self.C.WHITE)
        love.graphics.setFont(self.FONTS.PIXEL.SMALL)
        local textHeight = love.graphics.getFont():getHeight()
        local textY = iy + math.floor(ih / 2) - math.floor((textHeight / 2) * lines)
        love.graphics.printf(text, ix, textY, iw, "center")
    else
        love.graphics.setColor(color)
        love.graphics.rectangle("fill", x, y, w, h, 4, 4)
    end

end

function Game:draw_bottom_shop()
    local panel_x, panel_y, panel_w, panel_h = 4, 65, 312, 200
    if _G.draw_rect_with_shadow then
        draw_rect_with_shadow(panel_x, panel_y, panel_w, panel_h, 4, 2, self.C.BLOCK.BACK, self.C.BLOCK.SHADOW, 2)
    else
        love.graphics.setColor(self.C.PANEL)
        love.graphics.rectangle("fill", panel_x, panel_y, panel_w, panel_h, 4, 4)
    end

    love.graphics.setColor(self.C.RED)
    love.graphics.rectangle("line", panel_x, panel_y, panel_w, panel_h, 4, 4)

    local padding = 4
    local shop_continue_rect = { x = panel_x + padding, y = panel_y + padding, w = 74, h = 40, color = self.C.RED, text = "Next\nRound", lines = 2}
    local reroll_cost = self:shop_current_reroll_cost()
    local can_reroll = (tonumber(self.money) or 0) >= reroll_cost
    local reroll_color = can_reroll and self.C.GREEN or self.C.GREY
    local shop_reroll_rect = {
        x = panel_x + padding,
        y = shop_continue_rect.y + shop_continue_rect.h + padding,
        w = shop_continue_rect.w,
        h = shop_continue_rect.h,
        color = reroll_color,
        text = "Reroll\n$" .. tostring(reroll_cost),
        lines = 2
    }
    self._shop_continue_rect = { x = shop_continue_rect.x, y = shop_continue_rect.y, w = shop_continue_rect.w, h = shop_continue_rect.h }
    self._shop_reroll_rect = { x = shop_reroll_rect.x, y = shop_reroll_rect.y, w = shop_reroll_rect.w, h = shop_reroll_rect.h }
    if self.draw_shop_button then
        self:draw_shop_button(shop_continue_rect)
        self:draw_shop_button(shop_reroll_rect)
    end

    -- Joker Area
    love.graphics.setColor(self.C.PANEL)
    local jokerPanel = {x = shop_continue_rect.x + shop_continue_rect.w + padding, y = shop_continue_rect.y, w = panel_w - 3 * padding - shop_continue_rect.w, h = (shop_reroll_rect.y + shop_reroll_rect.h) - shop_continue_rect.y}
    love.graphics.rectangle("fill", jokerPanel.x, jokerPanel.y, jokerPanel.w, jokerPanel.h, 4, 4)

    self:layout_shop_offer_nodes(jokerPanel)
end

function Game:handle_blind_select_touch(x, y)
    for i, r in ipairs(self._blind_select_tap_rects or {}) do
        if self:_point_in_rect_simple(x, y, r) then
            if not self:is_blind_selectable(i) then
                return true
            end
            if self.selected_blind_index == i then
                self:start_selected_blind()
            else
                self.selected_blind_index = i
            end
            return true
        end
    end
    return false
end

function Game:draw_bottom_round_win()
    local panel_x, panel_y, panel_w, panel_h = 8, 8, 304, 124
    if _G.draw_rect_with_shadow then
        draw_rect_with_shadow(panel_x, panel_y, panel_w, panel_h, 4, 2, self.C.BLOCK.BACK, self.C.BLOCK.SHADOW, 2)
    else
        love.graphics.setColor(self.C.PANEL)
        love.graphics.rectangle("fill", panel_x, panel_y, panel_w, panel_h, 4, 4)
    end

    local blind_idx = tonumber(self.current_blind_index) or 1
    local blind_label = self:get_blind_display_name(blind_idx) or "Blind"
    local target = tonumber(self.current_blind_target) or 0
    local final_score = tonumber(self.round_score) or 0
    local reward = tonumber(self.current_blind_reward) or 0
    local hands_bonus = math.max(0, math.floor(tonumber(self._round_win_hands_bonus) or 0))
    local interest = math.max(0, math.floor(tonumber(self._round_win_interest) or 0))
    local total_payout = reward + hands_bonus + interest

    love.graphics.setColor(self.C.WHITE)
    love.graphics.setFont(self.FONTS.PIXEL.MEDIUM)
    love.graphics.print("Round won!", panel_x + 8, panel_y + 4)
    love.graphics.setFont(self.FONTS.PIXEL.SMALL)
    love.graphics.print(blind_label, panel_x + 8, panel_y + 22)

    love.graphics.setColor(self.C.GREY)
    love.graphics.print(string.format("Score %d / %d", final_score, target), panel_x + 8, panel_y + 38)

    love.graphics.setColor(self.C.MONEY)
    love.graphics.print(string.format("Blind reward: +$%d", reward), panel_x + 8, panel_y + 50)
    love.graphics.print(string.format("Hands left: %d (+$%d)", hands_bonus, hands_bonus), panel_x + 8, panel_y + 62)
    love.graphics.print(string.format("Interest: +$%d ($1 / $5, max $25)", interest), panel_x + 8, panel_y + 74)
    love.graphics.print(string.format("Total: +$%d", total_payout), panel_x + 8, panel_y + 86)

    self._round_win_continue_rect = { x = panel_x + panel_w - 84, y = panel_y + panel_h - 24, w = 74, h = 18 }
    love.graphics.setColor(self.C.ORANGE)
    love.graphics.rectangle("fill", self._round_win_continue_rect.x, self._round_win_continue_rect.y, self._round_win_continue_rect.w, self._round_win_continue_rect.h, 3, 3)
    love.graphics.setColor(self.C.WHITE)
    love.graphics.setFont(self.FONTS.PIXEL.SMALL)
    love.graphics.rectangle("line", self._round_win_continue_rect.x, self._round_win_continue_rect.y, self._round_win_continue_rect.w, self._round_win_continue_rect.h, 3, 3)
    local cty = self._round_win_continue_rect.y + math.floor((self._round_win_continue_rect.h - love.graphics.getFont():getHeight()) * 0.5 + 0.5)
    love.graphics.printf("Continue", self._round_win_continue_rect.x, cty, self._round_win_continue_rect.w, "center")
end

function Game:handle_round_win_touch(x, y)
    if not self._round_win_continue_rect then return false end
    if self:_point_in_rect_simple(x, y, self._round_win_continue_rect) then
        self:continue_from_round_win()
        return true
    end
    return false
end

function Game:handle_shop_touch(x, y)
    for i, r in ipairs(self._shop_owned_rects or {}) do
        if self:_point_in_rect_simple(x, y, r) then
            self:sell_owned_joker(i)
            return true
        end
    end
    if self:_point_in_rect_simple(x, y, self._shop_continue_rect) then
        self:continue_from_shop()
        return true
    end
    if self:_point_in_rect_simple(x, y, self._shop_reroll_rect) then
        self:reroll_shop_offers()
        return true
    end
    return false
end

function Game:update(dt)
    self:_update_joker_emit_queue(dt)
    for _, node in ipairs(self.nodes) do
        if node.update then
            node:update(dt)
        end
    end
    if self.hand and self.hand.update then
        self.hand:update(dt)
    end
    self:check_collisions(dt)

    -- Determine whether the joker slide animation is still running.
    -- While sliding, guides should move with jokers; afterward, guides lock to slot geometry.
    if self.jokers_sliding == true then
        self.jokers_slide_time_left = (self.jokers_slide_time_left or 0) - dt
        local all_snapped = true
        if self.jokers then
            for _, j in ipairs(self.jokers) do
                if j and j.VT and j.T then
                    local dx = math.abs((j.VT.x or 0) - (j.T.x or 0))
                    local dy = math.abs((j.VT.y or 0) - (j.T.y or 0))
                    local ds = math.abs((j.VT.scale or 0) - (j.T.scale or 0))
                    if dx > 0.6 or dy > 0.6 or ds > 0.02 then
                        all_snapped = false
                        break
                    end
                end
            end
        end

        if all_snapped == true or (self.jokers_slide_time_left or 0) <= 0 then
            self.jokers_sliding = false
            self.jokers_slide_time_left = 0
        end
    end

    local removed_nodes = 0
    self.discard_timer = self.discard_timer + dt
    for i = #self.pending_discard, 1, -1 do
        local entry = self.pending_discard[i]
        if self.discard_timer >= entry.remove_after then
            self:remove(entry.node)
            table.remove(self.pending_discard, i)
            removed_nodes = removed_nodes + 1
        end
    end

    if removed_nodes > 0 then
        self._gc_discarded_nodes = self._gc_discarded_nodes + removed_nodes
        if self._gc_discarded_nodes >= 24 then
            self._gc_discarded_nodes = 0
            collectgarbage("collect")
        end
    end

    -- Small periodic incremental GC step to smooth frame spikes on 3DS.
    self._gc_timer = self._gc_timer + dt
    if self._gc_timer >= 0.2 then
        self._gc_timer = 0
        collectgarbage("step", 96)
    end
end

function Game:rects_overlap(a, b)
    return a.x < b.x + b.w and
           a.x + a.w > b.x and
           a.y < b.y + b.h and
           a.y + a.h > b.y
end

function Game:get_overlap(a, b)
    local ox = math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x)
    local oy = math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y)
    return ox, oy
end

function Game:check_collisions(dt)
    if not self.dragging then
        for _, node in ipairs(self.nodes) do
            if node.states then
                node.states.collide.is = false
            end
        end
        return
    end
    
    local collidables = self._collidables_buf
    for i = #collidables, 1, -1 do
        collidables[i] = nil
    end
    for _, node in ipairs(self.nodes) do
        if node.states and node.states.collide.can then
            table.insert(collidables, node)
        end
    end
    
    local nudge_strength = 200 * dt
    local deadzone = 3
    local max_overlap = 40

    local held = self.dragging
    local rect_held = held:get_collision_rect()

    for _, other in ipairs(collidables) do
        if other ~= held then
            local rect_other = other:get_collision_rect()

            if self:rects_overlap(rect_held, rect_other) then
                local ox, oy = self:get_overlap(rect_held, rect_other)
                local min_overlap = math.min(ox, oy)

                if min_overlap > max_overlap then
                    other.states.collide.is = false
                elseif min_overlap < deadzone then
                    other.states.collide.is = true
                else
                    other.states.collide.is = true

                    local center_hx = rect_held.x + rect_held.w / 2
                    local center_hy = rect_held.y + rect_held.h / 2
                    local center_ox = rect_other.x + rect_other.w / 2
                    local center_oy = rect_other.y + rect_other.h / 2

                    local dx = center_ox - center_hx
                    local dy = center_oy - center_hy

                    if ox < oy then
                        local nudge = (dx > 0 and 1 or -1) * nudge_strength
                        other.collision_offset.x = other.collision_offset.x + nudge
                    else
                        local nudge = (dy > 0 and 1 or -1) * nudge_strength
                        other.collision_offset.y = other.collision_offset.y + nudge
                    end
                end
            else
                other.states.collide.is = false
            end
        end
    end

    -- Decay offset so cards return to original position when collision ends
    for _, node in ipairs(collidables) do
        local decay = 5 * dt
        node.collision_offset.x = node.collision_offset.x * (1 - decay)
        node.collision_offset.y = node.collision_offset.y * (1 - decay)
    end
end

function Game:point_in_rect(px, py, node)
    local r = node.get_collision_rect and node:get_collision_rect() or nil
    if not r then
        local t = node.VT or node.T
        r = { x = t.x, y = t.y, w = t.w * t.scale, h = t.h * t.scale }
    end
    return px >= r.x and px <= r.x + r.w and py >= r.y and py <= r.y + r.h
end

function Game:get_node_at(x, y)
    for i = #self.nodes, 1, -1 do
        local node = self.nodes[i]
        if node.states and node.states.click.can and self:point_in_rect(x, y, node) then
            return node
        end
    end
    return nil
end

--- Horizontal step and span for `n` jokers in `screen_w`, overlapping (fanned) when natural width exceeds `screen_wdt`.
---@return number step x-distance between successive joker left edges
---@return number total_span width from first to last joker's right edge
---@return number start_x left edge of first joker, centered in screen
function Game:_compute_fanned_joker_row(n, screen_w, card_w, gap_w, margin)
    margin = tonumber(margin) or 8
    n = tonumber(n) or 0
    card_w = tonumber(card_w) or 71
    gap_w = tonumber(gap_w) or 8
    screen_w = tonumber(screen_w) or 400
    if n <= 0 then return 0, 0, math.floor(screen_w * 0.5 + 0.5) end
    local max_w = math.max(card_w, screen_w - 2 * margin)
    local natural_step = card_w + gap_w
    local natural_span = n * card_w + (n - 1) * gap_w
    local step, total_span
    if n == 1 then
        step = 0
        total_span = card_w
    elseif natural_span <= max_w then
        step = natural_step
        total_span = natural_span
    else
        step = (max_w - card_w) / (n - 1)
        total_span = (n - 1) * step + card_w
    end
    local start_x = math.floor((screen_w - total_span) * 0.5 + 0.5)
    return step, total_span, start_x
end

--- Rough top/bottom start positions before `_apply_joker_layout` (uses owned count).
function Game:recompute_joker_slot_layout()
    self.joker_slot_w = self.joker_slot_w or 71
    self.joker_slot_h = self.joker_slot_h or 95
    self.joker_slot_gap = self.joker_slot_gap or 8
    self.joker_slot_y_top = self.joker_slot_y_top or 124
    self.joker_slot_y_bottom = self.joker_slot_y_bottom or 20

    local BOTTOM_SCREEN_W = 320
    local TOP_SCREEN_W = 400
    local n = #(self.jokers or {})
    local eff_n = math.max(n, 1)
    local card_w = self.joker_slot_w or 71
    local gap = self.joker_slot_gap or 8

    local _, _, top_x = self:_compute_fanned_joker_row(eff_n, TOP_SCREEN_W, card_w, gap, 8)
    self.joker_slot_start_x = top_x

    self.joker_slot_scale_bottom = 1
    local s = self.joker_slot_scale_bottom
    local eff_w = card_w * s
    local eff_gap = gap * s
    local _, _, bot_x = self:_compute_fanned_joker_row(eff_n, BOTTOM_SCREEN_W, eff_w, eff_gap, 8)
    self.joker_slot_start_x_bottom = bot_x
end

--- `joker_base_capacity` + one slot per owned Joker with Negative edition.
function Game:refresh_joker_capacity_from_negatives()
    if not self.joker_base_capacity then self.joker_base_capacity = 5 end
    local bonus = 0
    for _, j in ipairs(self.jokers or {}) do
        if j and Joker.normalize_edition(j.edition) == "negative" then
            bonus = bonus + 1
        end
    end
    self.joker_capacity = (self.joker_base_capacity or 5) + bonus
    self:recompute_joker_slot_layout()
    self:_apply_joker_layout()
    self:sync_jokers_interactivity()
end

function Game:init_jokers()
    -- Owned Jokers live in `self.jokers` (packed left-to-right).
    self.jokers = {}

    if not Joker then return end

    self.joker_base_capacity = self.joker_base_capacity or 5
    self.joker_capacity = self.joker_base_capacity

    self.jokers_on_bottom = false
    self.jokers_sliding = false
    self.jokers_slide_time_left = 0

    self.joker_slot_w, self.joker_slot_h = 71, 95
    self.joker_slot_gap = 8
    self.joker_slot_y_top = 124
    self.joker_slot_y_bottom = 20

    self:recompute_joker_slot_layout()

    -- Demo-owned jokers (randomized for testing).
    -- Replace this with your shop/buy system later.
    local pool = {}
    if JOKER_DEFS and type(JOKER_DEFS) == "table" then
        for def_id, _ in pairs(JOKER_DEFS) do
            pool[#pool + 1] = def_id
        end
    end

    -- -- Fisher–Yates shuffle
    -- for i = #pool, 2, -1 do
    --     local j = math.random(i)
    --     pool[i], pool[j] = pool[j], pool[i]
    -- end

    -- local want = math.min(self.joker_capacity or 0, #pool)
    -- for i = 1, want do
    --     self:add_joker_by_def(pool[i])
    -- end
    self:add_joker_by_def("j_photograph")
    self:add_joker_by_def("j_hanging_chad")
    self:add_joker_by_def("j_hanging_chad")
    self:add_joker_by_def("j_photograph")
    self:add_joker_by_def("j_blueprint")
    self.jokers[1].edition = "holo"
    self.jokers[2].edition = "foil"
    self.jokers[3].edition = "polychrome"
    self.jokers[4].edition = "negative"
    for _, jj in ipairs(self.jokers) do
        if jj and jj.refresh_quads then jj:refresh_quads() end
    end
end

---Add an owned Joker by definition id.
---Owned Jokers are packed left-to-right and never exceed `self.joker_capacity`.
---@param def_id string
---@param create_params table|nil optional `{ edition = "foil"|"holo"|... }` (single edition only)
---@return boolean
function Game:add_joker_by_def(def_id, create_params)
    if type(def_id) ~= "string" or def_id == "" then return false end
    if not JOKER_DEFS or type(JOKER_DEFS) ~= "table" then return false end
    local def = JOKER_DEFS[def_id]
    if type(def) ~= "table" then return false end

    if not self.joker_base_capacity then self.joker_base_capacity = 5 end
    if not self.joker_capacity then self.joker_capacity = self.joker_base_capacity end
    if not self.jokers then self.jokers = {} end

    local merged = { face_up = true }
    if type(create_params) == "table" then
        for k, v in pairs(create_params) do
            merged[k] = v
        end
    end

    local neg_owned = 0
    for _, jj in ipairs(self.jokers) do
        if jj and Joker.normalize_edition(jj.edition) == "negative" then
            neg_owned = neg_owned + 1
        end
    end
    local new_is_neg = Joker.normalize_edition(merged.edition) == "negative"
    local cap_after = (self.joker_base_capacity or 5) + neg_owned + (new_is_neg and 1 or 0)
    if #self.jokers >= cap_after then return false end

    local j = Joker(0, 0, self.joker_slot_w, self.joker_slot_h, def, merged)
    table.insert(self.jokers, j)
    self:add(j)

    self:refresh_joker_capacity_from_negatives()

    -- Snap immediately if we're not in a DPAD slide transition.
    if self.jokers_sliding ~= true then
        for _, jj in ipairs(self.jokers) do
            if jj and jj.VT and jj.T then
                jj.VT.x = jj.T.x
                jj.VT.y = jj.T.y
                jj.VT.scale = jj.T.scale
            end
        end
    end

    return true
end

function Game:hasJoker(joker_id)
    return self:count_jokers_with_id(joker_id) > 0
end

---@param joker_id string
---@return integer
function Game:count_jokers_with_id(joker_id)
    if type(self.jokers) ~= "table" or type(joker_id) ~= "string" or joker_id == "" then return 0 end
    local n = 0
    for _, j in ipairs(self.jokers) do
        local def = j and j.def
        if type(def) == "table" and def.id == joker_id then
            n = n + 1
        end
    end
    return n
end

function Game:count_cards_in_full_deck(predicate)
    local total = 0
    local function count_in(list)
        if type(list) ~= "table" then return end
        for _, card in ipairs(list) do
            if type(card) == "table" then
                if not predicate or predicate(card) then
                    total = total + 1
                end
            end
        end
    end
    local deck = self.deck
    if deck then
        count_in(deck.cards)
        count_in(deck.discard_pile)
    end
    if self.hand and type(self.hand.cards) == "table" then
        count_in(self.hand.cards)
    end
    return total
end

function Game:_apply_joker_layout()
    if not self.jokers then return end

    local TOP_SCREEN_W = 400
    local BOTTOM_SCREEN_W = 320
    local slot_w = self.joker_slot_w or 71
    local slot_h = self.joker_slot_h or 95
    local gap = self.joker_slot_gap or 8

    if self.jokers_on_bottom == true then
        local n = #self.jokers
        if n <= 0 then return end

        local s = self.joker_slot_scale_bottom or 1
        local y = self.joker_slot_y_bottom or 20
        local eff_w = slot_w * s
        local eff_gap = gap * s
        local step, total_span, start_x =
            self:_compute_fanned_joker_row(n, BOTTOM_SCREEN_W, eff_w, eff_gap, 8)

        self._joker_row_step_bottom = step
        self._joker_row_start_x_bottom = start_x
        self.joker_row_span_bottom = total_span
        self.joker_slot_start_x_bottom = start_x

        local delta_x = (slot_w * s * (1 - s)) / 2
        local delta_y = (slot_h * s * (1 - s)) / 2

        for i, j in ipairs(self.jokers) do
            if j and j.T then
                local desired_left = start_x + (i - 1) * step
                j.T.x = desired_left - delta_x
                j.T.y = y - delta_y
                j.T.scale = s
            end
        end
    else
        local n = #self.jokers
        if n <= 0 then return end

        local s = 1
        local y = self.joker_slot_y_top or 124
        local step, total_span, start_x = self:_compute_fanned_joker_row(n, TOP_SCREEN_W, slot_w, gap, 8)

        self._joker_row_step_top = step
        self.joker_row_span_top = total_span
        self.joker_slot_start_x = start_x

        for i, j in ipairs(self.jokers) do
            if j and j.T then
                j.T.x = start_x + (i - 1) * step
                j.T.y = y
                j.T.scale = s
            end
        end
    end
end

function Game:sync_jokers_interactivity()
    local on_bottom = self.jokers_on_bottom == true
    if not self.jokers then return end
    for _, j in ipairs(self.jokers) do
        if j and j.states then
            j.states.click.can = on_bottom
            j.states.drag.can = on_bottom
            -- Bottom screen draw path uses `j:draw()`, which checks `states.visible`.
            -- Top screen draw is handled by `TopUI.draw()` which temporarily overrides visibility.
            j.states.visible = on_bottom
        end
    end
end

--- All owned jokers sorted left-to-right (for per-joker edition steps on `on_hand_scored`).
function Game:collect_all_jokers_sorted()
    local out = {}
    if not self.jokers or type(self.jokers) ~= "table" then return out end
    for _, j in ipairs(self.jokers) do
        if j then table.insert(out, j) end
    end
    table.sort(out, function(a, b)
        local ax = (a.T and a.T.x) or (a.VT and a.VT.x) or 0
        local bx = (b.T and b.T.x) or (b.VT and b.VT.x) or 0
        return ax < bx
    end)
    local boss_id = self:get_active_boss_blind_id()
    if boss_id == "bl_final_heart" then
        local blocked = tonumber(self.boss_runtime and self.boss_runtime.crimson_disabled_joker) or -1
        if blocked >= 1 and blocked <= #out then
            table.remove(out, blocked)
        end
    end
    return out
end

--- Jokers in slot order (left-to-right) that match `event_name` and have `apply_effect`.
---@param event_name string
---@param ctx table
---@return table[]
function Game:collect_matching_jokers(event_name, ctx)
    local out = {}
    if not self.jokers or type(self.jokers) ~= "table" then return out end
    if type(event_name) ~= "string" or event_name == "" then return out end
    if type(ctx) ~= "table" then ctx = {} end

    for _, j in ipairs(self.jokers) do
        if j and j.matches_trigger and j:matches_trigger(event_name, ctx) and j.apply_effect then
            table.insert(out, j)
        end
    end
    -- Resolve left-to-right on screen (array order can diverge after drag-reorder).
    table.sort(out, function(a, b)
        local ax = (a.T and a.T.x) or (a.VT and a.VT.x) or 0
        local bx = (b.T and b.T.x) or (b.VT and b.VT.x) or 0
        return ax < bx
    end)
    local boss_id = self:get_active_boss_blind_id()
    if boss_id == "bl_final_heart" then
        local blocked = tonumber(self.boss_runtime and self.boss_runtime.crimson_disabled_joker) or -1
        if blocked >= 1 and blocked <= #out then
            table.remove(out, blocked)
        end
    end
    return out
end

---Emit a joker event to all jokers and apply their effects to the context.
---`ctx` is a mutable table that joker effects can update (e.g. ctx.chips/ctx.mult).
---@param event_name string
---@param ctx table|nil
function Game:emit_joker_event(event_name, ctx)
    if not self.jokers or type(self.jokers) ~= "table" then return end
    if type(event_name) ~= "string" or event_name == "" then return end
    if type(ctx) ~= "table" then ctx = {} end
    ctx.event_name = event_name

    if event_name == "on_hand_scored" then
        for _, j in ipairs(self:collect_all_jokers_sorted()) do
            if j and j.apply_edition_on_hand_scored then
                j:apply_edition_on_hand_scored(ctx)
            end
            self:_sync_joker_ctx(ctx)
            if j and j.matches_trigger and j:matches_trigger(event_name, ctx) and j.apply_effect then
                print("Joker event: " .. event_name .. " matched by " .. (j.def and j.def.name or "?"))
                j:apply_effect(ctx)
                self:_sync_joker_ctx(ctx)
            end
        end
        return
    end

    for _, j in ipairs(self.jokers) do
        if j and j.matches_trigger and j:matches_trigger(event_name, ctx) then
            print("Joker event: " .. event_name .. " matched by " .. (j.def and j.def.name or "?"))
            if j.apply_effect then
                j:apply_effect(ctx)
            end
        end
    end
end

function Game:_sync_joker_ctx(ctx)
    if type(ctx) ~= "table" then return end
    self.selectedHandChips = tonumber(ctx.chips) or self.selectedHandChips
    self.selectedHandMult = tonumber(ctx.mult) or self.selectedHandMult
end

--- True while a staggered joker batch (from `begin_joker_emit`) is still resolving.
function Game:joker_emit_busy()
    return self._joker_emit_queue ~= nil
end

--- Apply one joker from the stagger queue and sync chips/mult to `G`.
function Game:_apply_one_joker_emit()
    local q = self._joker_emit_queue
    if not q or type(q.list) ~= "table" then
        self._joker_emit_queue = nil
        self._joker_emit_timer = 0
        return
    end
    local j = q.list[self._joker_emit_next]
    if j then
        if type(q.ctx) == "table" then
            q.ctx.event_name = q.event_name
        end
        if q.event_name == "on_hand_scored" and j.apply_edition_on_hand_scored then
            j:apply_edition_on_hand_scored(q.ctx)
        end
        self:_sync_joker_ctx(q.ctx)
        if j.apply_effect and j.matches_trigger and q.event_name and j:matches_trigger(q.event_name, q.ctx) then
            j:apply_effect(q.ctx)
        end
        self:_sync_joker_ctx(q.ctx)
    end
    self._joker_emit_next = self._joker_emit_next + 1
    if self._joker_emit_next > #q.list then
        self._joker_emit_queue = nil
        self._joker_emit_timer = 0
    end
end

--- Resolve matching jokers left-to-right with a delay between each trigger (first applies immediately).
--- Returns true if any joker was queued (caller should wait until `joker_emit_busy()` is false).
---@param event_name string
---@param ctx table|nil
---@return boolean
function Game:begin_joker_emit(event_name, ctx)
    local list
    if event_name == "on_hand_scored" then
        list = self:collect_all_jokers_sorted()
    else
        list = self:collect_matching_jokers(event_name, ctx)
    end
    if #list == 0 then return false end
    if type(ctx) ~= "table" then ctx = {} end
    ctx.event_name = event_name
    self._joker_emit_queue = { list = list, ctx = ctx, event_name = event_name }
    self._joker_emit_next = 1
    self._joker_emit_timer = 0
    self:_apply_one_joker_emit()
    return true
end

function Game:_update_joker_emit_queue(dt)
    if not self._joker_emit_queue then return end
    self._joker_emit_timer = self._joker_emit_timer + dt
    local interval = tonumber(self.JOKER_EMIT_INTERVAL) or 0.18
    if self._joker_emit_timer >= interval then
        self._joker_emit_timer = 0
        self:_apply_one_joker_emit()
    end
end

--- End Round — call once when the current round finishes (e.g. blind beaten).
--- Discards the hand, merges draw + discard piles, shuffles into the draw pile, then refills the hand.
function Game:end_round()
    if self.hand and self.hand.send_entire_hand_to_discard_pile then
        self.hand:send_entire_hand_to_discard_pile()
    end
    local deck = self.deck
    if deck and deck.end_round then
        deck:end_round()
    end
    if self.hand and self.hand.fill_from_deck then
        self.hand:fill_from_deck()
    end
end

--- After beating a blind: return all cards to the deck and reshuffle; hand stays empty until the next blind starts.
function Game:recycle_full_deck_after_blind_win()
    if self.hand and self.hand.send_entire_hand_to_discard_pile then
        self.hand:send_entire_hand_to_discard_pile()
    end
    local deck = self.deck
    if deck and deck.end_round then
        deck:end_round()
    end
end

function Game:prepare_hand_for_new_blind()
    if not self.deck and Deck then
        self.deck = Deck()
    end

    data = {

    }
    
    self:emit_joker_event("on_blind_selected", data)

    self:set_state(self.STATES.SELECTING_HAND)
    if self.deck and self.deck.shuffle then
        self.deck:shuffle()
    end
    if not self.hand and Hand then
        self.hand = Hand(self)
    end
    if self.hand and self.hand.clear then
        self.hand:clear()
    end
    if self.hand and self.hand.fill_from_deck then
        self.hand:fill_from_deck()
    end
    self:boss_on_hand_refilled(true)

    self:emit_joker_event("on_round_begin", {})
end

function Game:initialize_run_loop()
    self.STAGE = self.STAGES.RUN
    self.ante = 1
    self.round = 1
    self.money = 10
    self.hands = self:get_effective_hands_per_round()
    self.discards = self:get_effective_discards_per_round()
    self.round_score = 0
    self.last_hand_score = 0
    self.selectedHandHidden = false
    self.current_blind_index = 1
    self.selected_blind_index = 1
    self._blind_resolution_pending = false
    self.current_blind_target = 0
    self.current_blind_reward = 0
    self.current_blind_name = "Small Blind"
    self.shop_offers = {}
    self.shop_reroll_count = 0
    self.hand_play_counts = {}
    if self.hand and self.hand.clear then
        self.hand:clear()
    end
    -- Start each run with a couple of simple Consumables for testing.
    self.consumables = {}
    self.last_consumable_use_id = nil
    self:add_consumable("tarot_death")
    self:add_consumable("planet_pluto")
    self:init_shop_offer_queue()
    self:set_state(self.STATES.BLIND_SELECT)
end

function Game:enter_blind_select()
    self:set_state(self.STATES.BLIND_SELECT)
    self.selected_blind_index = self.current_blind_index or 1
    if self.selected_blind_index == 3 then
        if not self.current_boss_blind_id then
            self:roll_boss_blind()
        end
    end
    self.round_score = 0
    self.last_hand_score = 0
    self.current_blind_target = 0
    self.current_blind_reward = 0
    self._blind_resolution_pending = false
    if self.hand and self.hand.clear then
        self.hand:clear()
    end
end

function Game:start_selected_blind()
    local idx = tonumber(self.selected_blind_index) or tonumber(self.current_blind_index) or 1
    if not self:is_blind_selectable(idx) then
        return false
    end
    local def = self:get_blind_def(idx)
    if not def then return false end

    self.current_blind_index = idx
    self.current_blind_target = self:get_blind_target(idx, self.ante)
    self.current_blind_reward = tonumber(def.reward) or 0
    self.current_blind_name = def.name or "Blind"
    if def.id == "boss" then
        local proto = self:get_boss_blind_prototype()
        if proto then
            self.current_blind_name = proto.name or self.current_blind_name
            self.current_blind_reward = tonumber(proto.dollars) or self.current_blind_reward
        end
    end
    self.hands = 5
    self.discards = 5
    self.round_score = 0
    self.last_hand_score = 0
    self._blind_resolution_pending = false
    self:boss_reset_for_new_blind()
    self:prepare_hand_for_new_blind()

    return true
end

function Game:advance_after_shop()
    if self._last_completed_blind_was_boss then
        self.ante = (tonumber(self.ante) or 1) + 1
        self._ante_played_card_uids = {}
        self.current_boss_blind_id = nil
        self.current_blind_index = 1
    else
        self.current_blind_index = math.min(3, (tonumber(self.current_blind_index) or 1) + 1)
    end
    self.selected_blind_index = self.current_blind_index
    self.round = (tonumber(self.round) or 0) + 1
    self._last_completed_blind_was_boss = false
    self:enter_blind_select()
end

function Game:continue_from_shop()
    self:advance_after_shop()
end

-- ---------------------------------------------------------------------------
-- Shop offers: sequential queue driven only by SEED (isolated from math.random).
-- Pool weights: Joker 20, Tarot 4, Planet 4. Shop jokers: Common/Uncommon/Rare only.
-- ---------------------------------------------------------------------------

function Game:init_shop_offer_queue()
    self.shop_offer_queue = {}
    local s = tonumber(self.SEED) or 0
    s = math.floor(s) % 4294967296
    if s < 0 then s = s + 4294967296 end
    self._shop_rng_state = (s * 2654435769) % 4294967296
    if self._shop_rng_state == 0 then
        self._shop_rng_state = 2463534242
    end
    self:_refill_shop_offer_queue(128)
end

function Game:_shop_rng_advance()
    local st = tonumber(self._shop_rng_state) or 1
    st = (st * 1664525 + 1013904223) % 4294967296
    self._shop_rng_state = st
    return st
end

function Game:_shop_rand_int(lo, hi)
    lo = math.floor(tonumber(lo) or 1)
    hi = math.floor(tonumber(hi) or lo)
    if hi < lo then return lo end
    local span = hi - lo + 1
    local u = self:_shop_rng_advance()
    return lo + math.floor((u / 4294967296) * span)
end

function Game:_shop_joker_owned(id)
    if type(id) ~= "string" then return false end
    for _, j in ipairs(self.jokers or {}) do
        if j and j.def and j.def.id == id then
            return true
        end
    end
    return false
end

function Game:_refill_shop_offer_queue(target_len)
    self.shop_offer_queue = self.shop_offer_queue or {}
    target_len = math.max(0, math.floor(tonumber(target_len) or 0))
    while #self.shop_offer_queue < target_len do
        self.shop_offer_queue[#self.shop_offer_queue + 1] = self:_generate_next_shop_queue_offer()
    end
end

function Game:_pop_shop_queue_entry()
    self:_refill_shop_offer_queue(64)
    return table.remove(self.shop_offer_queue, 1)
end

function Game:_shop_queue_emergency_joker_offer()
    local fallback_id = "j_joker"
    if type(JOKER_DEFS) == "table" then
        local ks = {}
        for jid, def in pairs(JOKER_DEFS) do
            if type(def) == "table" and type(jid) == "string" then
                ks[#ks + 1] = jid
            end
        end
        table.sort(ks)
        if #ks > 0 then fallback_id = ks[1] end
    end
    local fd = JOKER_DEFS and JOKER_DEFS[fallback_id]
    return {
        kind = "joker",
        id = fallback_id,
        name = fd and fd.name or fallback_id,
        price = self:shop_price_for_joker_offer(fd, "base"),
        edition = "base",
    }
end

function Game:_generate_next_shop_queue_offer()
    local roll = self:_shop_rand_int(1, 28)
    local kind = "planet"
    if roll <= 20 then
        kind = "joker"
    elseif roll <= 24 then
        kind = "tarot"
    else
        kind = "planet"
    end

    if kind == "joker" then
        local joker_offer = self:_roll_shop_queue_joker_offer()
        if joker_offer then return joker_offer end
        kind = self:_shop_rand_int(1, 2) == 1 and "tarot" or "planet"
    end

    if kind == "tarot" then
        local c = self:_roll_shop_queue_consumable_offer("tarot")
        if c then return c end
        local c2 = self:_roll_shop_queue_consumable_offer("planet")
        if c2 then return c2 end
    else
        local c = self:_roll_shop_queue_consumable_offer("planet")
        if c then return c end
        local c2 = self:_roll_shop_queue_consumable_offer("tarot")
        if c2 then return c2 end
    end

    local j2 = self:_roll_shop_queue_joker_offer()
    if j2 then return j2 end
    return self:_shop_queue_emergency_joker_offer()
end

function Game:_roll_shop_queue_joker_offer()
    if type(JOKER_DEFS) ~= "table" then return nil end
    local rar_roll = self:_shop_rand_int(1, 100)
    local target_rar = 3
    if rar_roll <= 70 then
        target_rar = 1
    elseif rar_roll <= 95 then
        target_rar = 2
    end
    local candidates = {}
    for id, def in pairs(JOKER_DEFS) do
        if type(def) == "table" and type(id) == "string" then
            local rv = tonumber(def.rarity) or 1
            if rv == target_rar and rv >= 1 and rv <= 3 then
                candidates[#candidates + 1] = id
            end
        end
    end
    table.sort(candidates)
    if #candidates == 0 then
        for id, def in pairs(JOKER_DEFS) do
            if type(def) == "table" and type(id) == "string" then
                local rv = tonumber(def.rarity) or 1
                if rv >= 1 and rv <= 3 then
                    candidates[#candidates + 1] = id
                end
            end
        end
        table.sort(candidates)
    end
    if #candidates == 0 then return nil end
    local pick = candidates[self:_shop_rand_int(1, #candidates)]
    local def = JOKER_DEFS[pick]
    local edition = "base"
    return {
        kind = "joker",
        id = pick,
        name = def and def.name or pick,
        price = self:shop_price_for_joker_offer(def, edition),
        edition = edition,
    }
end

function Game:_roll_shop_queue_consumable_offer(wanted_kind)
    if type(CONSUMABLE_DEFS) ~= "table" then return nil end
    local ids = {}
    for id, def in pairs(CONSUMABLE_DEFS) do
        if type(def) == "table" and def.kind == wanted_kind and type(id) == "string" then
            if id == "planet_x" then
                if self.hand_play_counts[3] and self.hand_play_counts[3] >= 1 then
                    ids[#ids + 1] = id
                end
            elseif id == "planet_ceres" then
                if self.hand_play_counts[2] and self.hand_play_counts[2] >= 1 then
                    ids[#ids + 1] = id
                end
            elseif id == "planet_eris" then
                if self.hand_play_counts[1] and self.hand_play_counts[1] >= 1 then
                    ids[#ids + 1] = id
                end
            else
                ids[#ids + 1] = id
            end
        end
    end
    table.sort(ids)
    if #ids == 0 then return nil end
    local pick = ids[self:_shop_rand_int(1, #ids)]
    local def = CONSUMABLE_DEFS[pick]
    return {
        kind = wanted_kind,
        id = pick,
        name = def and def.name or pick,
        price = self:shop_price_for_consumable_offer(def),
    }
end

--- Buy price for a shop row: `def.cost` plus edition bonus (same as a spawned `Joker`).
---@param def table|nil
---@param edition string|nil
function Game:shop_price_for_joker_offer(def, edition)
    if type(def) ~= "table" then return 1 end
    local base = tonumber(def.cost) or 1
    if not Joker then
        return math.max(1, base)
    end
    local ec = select(1, Joker.edition_price_deltas(edition))
    return math.max(1, base + (tonumber(ec) or 0))
end

---@param def table|nil
function Game:shop_price_for_consumable_offer(def)
    if type(def) ~= "table" then return 3 end
    local sc = tonumber(def.sell_cost) or 3
    return math.max(2, sc + 1)
end

function Game:shop_current_reroll_cost()
    local base = tonumber(self.shop_reroll_base_cost) or 5
    local n = math.max(0, math.floor(tonumber(self.shop_reroll_count) or 0))
    return base + n
end

function Game:roll_shop_offers()
    if type(self.shop_offer_queue) ~= "table" then
        self:init_shop_offer_queue()
    end
    self.shop_offers = {}
    local slots = math.max(1, math.floor(tonumber(self.shop_offer_slots) or 2))
    local guard = 0
    local guard_limit = math.max(250, slots * 125)
    while #self.shop_offers < slots and guard < guard_limit do
        guard = guard + 1
        local entry = self:_pop_shop_queue_entry()
        if not entry then break end
        if entry.kind == "joker" or entry.kind == nil then
            if entry.kind == nil then
                entry.kind = "joker"
            end
            if self:_shop_joker_owned(entry.id) then
                -- Owned: consume queue slot, no visible offer.
            else
                self.shop_offers[#self.shop_offers + 1] = entry
            end
        else
            self.shop_offers[#self.shop_offers + 1] = entry
        end
    end
    self:sync_shop_offer_nodes()
end

function Game:reroll_shop_offers()
    if self.STATE ~= self.STATES.SHOP then return false end
    local cost = self:shop_current_reroll_cost()
    if (tonumber(self.money) or 0) < cost then
        return false
    end
    self.money = (tonumber(self.money) or 0) - cost
    self.shop_reroll_count = (tonumber(self.shop_reroll_count) or 0) + 1
    self:emit_joker_event("on_shop_reroll", {
        reroll_cost = cost,
        reroll_count = self.shop_reroll_count,
    })
    self.active_tooltip_joker = nil
    self:roll_shop_offers()
    return true
end

--- Blind just beaten: recycle deck, pay reward, show round-win screen (then shop).
--- Interest: +$1 per full $5 held after blind + hands payout; only the first $25 counts (max +$5).
function Game:enter_round_win_after_blind()
    local hands_left = math.max(0, math.floor(tonumber(self.hands) or 0))
    self._round_win_hands_bonus = hands_left
    self:emit_joker_event("on_round_end", {
        hands_left = hands_left,
        is_boss_blind = (tonumber(self.current_blind_index) == 3),
        round_score = tonumber(self.round_score) or 0,
        blind_name = self.current_blind_name,
    })
    self:recycle_full_deck_after_blind_win()
    local interest_count_cap = 25
    local interest = math.floor(math.min(math.max(0, self.money), interest_count_cap) / 5)
    self._round_win_interest = interest
    local blind_pay = tonumber(self.current_blind_reward) or 0
    self.money = (tonumber(self.money) or 0) + blind_pay + hands_left + interest
    self:set_state(self.STATES.ROUND_EVAL)
end

function Game:enter_shop_after_blind()
    self:set_state(self.STATES.SHOP)
    self.shop_reroll_count = 0
    self:roll_shop_offers()
    self:emit_joker_event("on_shop_enter", {
        offers = self.shop_offers,
        reroll_count = self.shop_reroll_count,
    })
end

function Game:continue_from_round_win()
    self:enter_shop_after_blind()
end

function Game:remove_owned_joker_at(index)
    if type(index) ~= "number" or index < 1 then return nil end
    if type(self.jokers) ~= "table" then return nil end
    local joker = self.jokers[index]
    if not joker then return nil end
    if self.active_tooltip_joker == joker then
        self.active_tooltip_joker = nil
    end
    table.remove(self.jokers, index)
    self:remove(joker)
    self:refresh_joker_capacity_from_negatives()
    return joker
end

function Game:buy_shop_joker(slot_index)
    if type(slot_index) ~= "number" or slot_index < 1 then return false end
    local offer = self.shop_offers and self.shop_offers[slot_index]
    if not offer then return false end
    if (tonumber(self.money) or 0) < (tonumber(offer.price) or 0) then return false end

    local ok = false
    local k = offer.kind
    if k == nil or k == "joker" then
        local neg_owned = 0
        if Joker then
            for _, jj in ipairs(self.jokers or {}) do
                if jj and Joker.normalize_edition(jj.edition) == "negative" then
                    neg_owned = neg_owned + 1
                end
            end
        end
        local new_neg = Joker and Joker.normalize_edition(offer.edition) == "negative"
        local cap_after = (self.joker_base_capacity or 5) + neg_owned + (new_neg and 1 or 0)
        if #self.jokers >= cap_after then return false end
        local create_params = nil
        if offer.edition and offer.edition ~= "base" then
            create_params = { edition = offer.edition }
        end
        ok = self:add_joker_by_def(offer.id, create_params) and true or false
    elseif k == "tarot" or k == "planet" then
        if not self:can_add_consumable() then return false end
        ok = self:add_consumable(offer.id)
    else
        return false
    end

    if not ok then return false end

    self.money = (tonumber(self.money) or 0) - (tonumber(offer.price) or 0)
    self:emit_joker_event("on_shop_buy", {
        offer = offer,
        offer_kind = offer.kind or "joker",
        offer_id = offer.id,
        offer_price = tonumber(offer.price) or 0,
    })
    table.remove(self.shop_offers, slot_index)
    if self.shop_offer_nodes and self.shop_offer_nodes[slot_index] then
        local removed = self.shop_offer_nodes[slot_index]
        if self.active_tooltip_joker == removed then
            self.active_tooltip_joker = nil
        end
        self:remove(removed)
        table.remove(self.shop_offer_nodes, slot_index)
    end
    for i, node in ipairs(self.shop_offer_nodes or {}) do
        if node then node.shop_offer_slot = i end
    end
    return true
end

function Game:sell_owned_joker(index)
    local joker = self:remove_owned_joker_at(index)
    if not joker then return false end
    local value = tonumber(joker.sell_cost) or 0
    self.money = (tonumber(self.money) or 0) + value
    self:emit_joker_event("on_joker_sold", {
        joker = joker,
        sold_value = value,
    })
    self:boss_on_joker_sold()
    return true
end

function Game:evaluate_blind_progress()
    if self.STATE ~= self.STATES.SELECTING_HAND then
        return
    end
    if self._blind_resolution_pending then
        return
    end
    local target = tonumber(self.current_blind_target) or 0
    local score = tonumber(self.round_score) or 0
    if score >= target and target > 0 then
        self._blind_resolution_pending = true
        self._last_completed_blind_was_boss = (self.current_blind_index == 3)
        self:enter_round_win_after_blind()
        return
    end
    if (tonumber(self.hands) or 0) <= 0 and score < target then
        self._blind_resolution_pending = true
        self:handle_failed_blind_reset()
    end
end

function Game:handle_failed_blind_reset()
    self:set_state(self.STATES.GAME_OVER)
    self:initialize_run_loop()
end

function Game:set_jokers_location(on_bottom)
    if self.jokers_on_bottom == (on_bottom == true) then return end
    local from_bottom = self.jokers_on_bottom == true
    local to_bottom = on_bottom == true

    self.jokers_on_bottom = to_bottom
    if not to_bottom then
        self.active_tooltip_joker = nil
    else
        -- When jokers are on bottom, consumables become non-interactive (no Use/Sell).
        self.active_tooltip_consumable_index = nil
    end
    self:sync_jokers_interactivity()

    -- Update target transforms first.
    self:_apply_joker_layout()

    -- Guide rectangles should move with jokers during this transition.
    -- They'll lock back to stationary slot geometry once the jokers snap.
    self.jokers_sliding = true
    self.jokers_slide_time_left = 0.6

    -- Then force VT to the previous layout so the slide always starts
    -- from a consistent top/bottom position (independent of prior VT drift).
    if self.jokers then
        local start_y
        if to_bottom then
            -- Start above the bottom screen so it feels like sliding down from the top.
            local s = self.joker_slot_scale_bottom or 1
            local slot_h = self.joker_slot_h or 95
            local h = slot_h * s
            local delta_y = (slot_h * s * (1 - s)) / 2
            start_y = -(h + 60) - delta_y -- guaranteed < 0 (effective visible)
        else
            -- Start below the bottom slots so it feels like sliding up.
            local s = self.joker_slot_scale_bottom or 1
            local slot_h = self.joker_slot_h or 95
            local h = slot_h * s
            local delta_y = (slot_h * s * (1 - s)) / 2
            start_y = (self.joker_slot_y_bottom or 20) + h + 60 - delta_y
        end

        for i, j in ipairs(self.jokers) do
            if j and j.VT then
                -- Keep VT centered and sized like the final slot;
                -- this prevents extra horizontal/scale drift during the slide.
                if j.T then
                    j.VT.x = j.T.x
                    j.VT.scale = j.T.scale
                end
                j.VT.y = start_y
            end
        end
    end
end

function Game:_joker_nearest_slot_idx(release_x)
    local owned_count = self.jokers and #self.jokers or 0
    if owned_count <= 0 then return 1 end

    if self.jokers_on_bottom == true then
        local s = self.joker_slot_scale_bottom or 1
        local start_x = self._joker_row_start_x_bottom or self.joker_slot_start_x_bottom or 0
        local step = self._joker_row_step_bottom
        if step == nil then
            step = (self.joker_slot_w + self.joker_slot_gap) * s
        end
        local slot_w_scaled = self.joker_slot_w * s
        local best_i, best_d = 1, 1e9
        for i = 1, owned_count do
            local cx = start_x + (i - 1) * step + slot_w_scaled / 2
            local d = math.abs(release_x - cx)
            if d < best_d then
                best_d = d
                best_i = i
            end
        end
        return best_i
    end

    local best_i, best_d = 1, 1e9
    local start_x = self.joker_slot_start_x or 0
    local step = self._joker_row_step_top
    if step == nil then
        step = self.joker_slot_w + self.joker_slot_gap
    end
    for i = 1, owned_count do
        local cx = start_x + (i - 1) * step + self.joker_slot_w / 2
        local d = math.abs(release_x - cx)
        if d < best_d then
            best_d = d
            best_i = i
        end
    end
    return best_i
end

function Game:try_reorder_joker_after_drag(joker_node, release_x)
    if not joker_node or not self.jokers or not self.jokers_on_bottom then return false end

    local from_idx
    for i, j in ipairs(self.jokers) do
        if j == joker_node then
            from_idx = i
            break
        end
    end
    if not from_idx then return false end

    local to_idx = self:_joker_nearest_slot_idx(release_x)
    if to_idx == from_idx then return false end

    local reordered = false
    local node = table.remove(self.jokers, from_idx)
    table.insert(self.jokers, to_idx, node)
    reordered = true

    -- Update target positions to reflect new slot order.
    self:_apply_joker_layout()

    -- Snap immediately to avoid visible overshoot beyond the bottom screen.
    -- We only do this when the slide transition is not active.
    if self.jokers_sliding ~= true then
        for _, j in ipairs(self.jokers) do
            if j and j.VT and j.T then
                j.VT.x = j.T.x
                j.VT.y = j.T.y
                j.VT.scale = j.T.scale
            end
        end
    end
    return reordered
end

function Game:move_to_front(node)
    for i, n in ipairs(self.nodes) do
        if n == node then
            table.remove(self.nodes, i)
            table.insert(self.nodes, node)
            return
        end
    end
end

local TAP_THRESHOLD = 15

local function node_is_owned_joker(self, node)
    if not node or not self or not self.jokers then return false end
    for _, j in ipairs(self.jokers) do
        if j == node then return true end
    end
    return false
end

local function node_is_shop_offer_joker(self, node)
    if not node or not self or not self.shop_offer_nodes then return false end
    for _, j in ipairs(self.shop_offer_nodes) do
        if j == node then return true end
    end
    return false
end

local function node_is_owned_consumable(self, node)
    if not node or not self or not self.consumable_nodes then return false end
    for idx, cnode in ipairs(self.consumable_nodes) do
        if cnode == node then return true, idx end
    end
    return false, nil
end

function Game:touchpressed(id, x, y)
    if self:try_use_button_press(x, y) then
        return
    end
    if self:try_sell_button_press(x, y) then
        return
    end
    if self:try_shop_buy_button_press(x, y) then
        return
    end
    if self.STATE == self.STATES.BLIND_SELECT then
        -- When jokers are at the bottom, prioritize joker input over blind-select panel taps.
        if self.jokers_on_bottom == true then
            local node = self:get_node_at(x, y)
            if node and node_is_owned_joker(self, node) then
                self.touch_start_x = x
                self.touch_start_y = y
                if node.touchpressed then
                    node:touchpressed(id, x, y)
                    self.dragging = node
                    self:move_to_front(node)
                end
                return
            end
        end
        if self:handle_blind_select_touch(x, y) then return end
    end
    if self.STATE == self.STATES.ROUND_EVAL then
        if self.jokers_on_bottom == true then
            local node = self:get_node_at(x, y)
            if node and node_is_owned_joker(self, node) then
                self.touch_start_x = x
                self.touch_start_y = y
                if node.touchpressed then
                    node:touchpressed(id, x, y)
                    self.dragging = node
                    self:move_to_front(node)
                end
                return
            end
        end
        if self:handle_round_win_touch(x, y) then return end
    end
    if self.STATE == self.STATES.SHOP then
        -- Shop offers: tap toggles tooltip + Buy; owned jokers stay draggable/reorderable.
        local node = self:get_node_at(x, y)
        if node and node_is_shop_offer_joker(self, node) then
            if self.active_tooltip_joker == node then self.active_tooltip_joker = nil else self.active_tooltip_joker = node end
            self.active_tooltip_card = nil
            self.active_tooltip_consumable_index = nil
            self:move_to_front(node)
            return
        end
        if node and self.jokers_on_bottom == true and node_is_owned_joker(self, node) then
            self.touch_start_x = x
            self.touch_start_y = y
            if node.touchpressed then
                node:touchpressed(id, x, y)
                self.dragging = node
                self:move_to_front(node)
            end
            return
        end
        if self:handle_shop_touch(x, y) then return end
    end
    local selecting_hand = (self.STATE == self.STATES.SELECTING_HAND)
    local joker_touch_state = (self.STATE == self.STATES.BLIND_SELECT or self.STATE == self.STATES.SHOP or self.STATE == self.STATES.ROUND_EVAL) and self.jokers_on_bottom == true
    local consumable_touch_state = (self.STATE ~= self.STATES.BLIND_SELECT and self.STATE ~= self.STATES.ROUND_EVAL) and self.jokers_on_bottom ~= true
    if not selecting_hand and not joker_touch_state and not consumable_touch_state then return end
    if selecting_hand and self.hand and self.hand.is_scoring_active and self.hand:is_scoring_active() then return end
    self.touch_start_x = x
    self.touch_start_y = y
    local node = self:get_node_at(x, y)
    if node and node_is_shop_offer_joker(self, node) then
        if self.active_tooltip_joker == node then self.active_tooltip_joker = nil else self.active_tooltip_joker = node end
        self.active_tooltip_card = nil
        self.active_tooltip_consumable_index = nil
        self:move_to_front(node)
        return
    end
    if node and joker_touch_state and (not node_is_owned_joker(self, node)) and (not node_is_owned_consumable(self, node)) then
        node = nil
    end
    if node and consumable_touch_state then
        local is_cons = select(1, node_is_owned_consumable(self, node))
        if is_cons then
            -- Allow dragging consumables even when jokers are not on bottom.
            self.touch_start_x = x
            self.touch_start_y = y
        end
    end
    if node and node.touchpressed then
        local is_c = select(1, node_is_owned_consumable(self, node))
        if not (is_c and self.jokers_on_bottom == true) then
            node:touchpressed(id, x, y)
            self.dragging = node
            self:move_to_front(node)
        end
    end
end

function Game:touchmoved(id, x, y, dx, dy)
    local selecting_hand = (self.STATE == self.STATES.SELECTING_HAND)
    local joker_touch_state = (self.STATE == self.STATES.BLIND_SELECT or self.STATE == self.STATES.SHOP or self.STATE == self.STATES.ROUND_EVAL) and self.jokers_on_bottom == true
    local consumable_touch_state = (self.STATE ~= self.STATES.BLIND_SELECT and self.STATE ~= self.STATES.ROUND_EVAL)
    if not selecting_hand and not joker_touch_state and not consumable_touch_state then return end
    if selecting_hand and self.hand and self.hand.is_scoring_active and self.hand:is_scoring_active() then return end
    if self.dragging and node_is_shop_offer_joker(self, self.dragging) then
        return
    end
    if self.dragging and joker_touch_state then
        if not node_is_owned_joker(self, self.dragging) then return end
    end
    if self.dragging and self.jokers_on_bottom == true then
        local is_c = select(1, node_is_owned_consumable(self, self.dragging))
        if is_c then
            -- Consumables are non-interactive while jokers are on bottom.
            return
        end
    end
    if self.dragging and self.dragging.touchmoved then
        self.dragging:touchmoved(id, x, y, dx, dy)
    end
end

function Game:touchreleased(id, x, y)
    local selecting_hand = (self.STATE == self.STATES.SELECTING_HAND)
    local shop_offer_touch_state = (self.STATE == self.STATES.SHOP)
    local joker_touch_state = (self.STATE == self.STATES.BLIND_SELECT or self.STATE == self.STATES.SHOP or self.STATE == self.STATES.ROUND_EVAL) and self.jokers_on_bottom == true
    local tapped_consumable = false
    if self.STATE ~= self.STATES.BLIND_SELECT and self.STATE ~= self.STATES.ROUND_EVAL and self.jokers_on_bottom ~= true then
        local node_at = self:get_node_at(x, y)
        local is_c = select(1, node_is_owned_consumable(self, node_at))
        tapped_consumable = is_c == true
    end
    if not selecting_hand and not joker_touch_state and not tapped_consumable and not shop_offer_touch_state then
        self.dragging = nil
        return
    end
    if selecting_hand and self.hand and self.hand.is_scoring_active and self.hand:is_scoring_active() then
        self.dragging = nil
        return
    end
    if joker_touch_state and self.dragging and not node_is_owned_joker(self, self.dragging) and not node_is_shop_offer_joker(self, self.dragging) then
        self.dragging = nil
        return
    end
    local released = self.dragging
    if released and released.touchreleased then
        released:touchreleased(id, x, y)
    end
    local start_x = self.touch_start_x or x
    local start_y = self.touch_start_y or y
    local dx = x - start_x
    local dy = y - start_y
    local dist = math.sqrt(dx * dx + dy * dy)
    local reordered = false

    if released and self.jokers and self.jokers_on_bottom and node_is_owned_joker(self, released) then
        local rmin = self.joker_reorder_drag_threshold and self.joker_reorder_drag_threshold() or 22
        if dist >= rmin then
            reordered = self:try_reorder_joker_after_drag(released, x) or false
            if reordered then
                self.active_tooltip_joker = nil
            end
        end
    end

    -- Tap (no reorder drag): toggle owned joker tooltip.
    if released and self.jokers_on_bottom and node_is_owned_joker(self, released) and not reordered and dist < TAP_THRESHOLD then
        if self.active_tooltip_joker == released then
            self.active_tooltip_joker = nil
        else
            self.active_tooltip_joker = released
            self.active_tooltip_card = nil
            self.active_tooltip_consumable_index = nil
            self:move_to_front(released)
        end
    end

    if released and self.hand and self.hand.try_reorder_card_after_drag then
        local rmin = self.hand.reorder_drag_threshold and self.hand:reorder_drag_threshold() or 22
        if dist >= rmin then
            for _, node in ipairs(self.hand.card_nodes) do
                if node == released then
                    reordered = self.hand:try_reorder_card_after_drag(node, x)
                    break
                end
            end
        end
    end
    -- Tap on hand cards toggles selection.
    if released and self.hand and not reordered and dist < TAP_THRESHOLD then
        for _, node in ipairs(self.hand.card_nodes) do
            if node == released then
                self.hand:toggle_selection(node)
                self.active_tooltip_consumable_index = nil
                break
            end
        end
    end
    -- Joker selection toggles in `touchpressed`; card-body tap does not buy.
    -- Tap on a Consumable node (Tarot / Planet) in the top-right of the bottom screen.
    -- Selecting shows the Use/Sell buttons; the button performs the action.
    if dist < TAP_THRESHOLD and self.STATE ~= self.STATES.BLIND_SELECT and self.STATE ~= self.STATES.ROUND_EVAL and self.jokers_on_bottom ~= true then
        local node_at = self:get_node_at(x, y)
        local is_c, idx = node_is_owned_consumable(self, node_at)
        if is_c and idx then
            if self.active_tooltip_consumable_index == idx then
                self.active_tooltip_consumable_index = nil
            else
                self.active_tooltip_consumable_index = idx
            end
            self.active_tooltip_card = nil
            self.active_tooltip_joker = nil
            self.dragging = nil
            return
        end
    end

    if not released and dist < TAP_THRESHOLD then
        local node_at = self:get_node_at(x, y)
        if node_at and (node_is_shop_offer_joker(self, node_at) or node_is_owned_joker(self, node_at)) then
            self.dragging = nil
            return
        end
        self.active_tooltip_card = nil
        self.active_tooltip_joker = nil
        self.active_tooltip_consumable_index = nil
    end
    self.dragging = nil
    if released and self.hand then
        for _, node in ipairs(self.hand.card_nodes) do
            if node == released then
                self:restore_hand_draw_order()
                break
            end
        end
    end
end

function Game:restore_hand_draw_order()
    if not self.hand or #self.hand.card_nodes == 0 then return end
    local hand_set = {}
    for _, node in ipairs(self.hand.card_nodes) do
        hand_set[node] = true
    end
    local ordered = {}
    for _, node in ipairs(self.nodes) do
        if not hand_set[node] then
            table.insert(ordered, node)
        end
    end
    for _, node in ipairs(self.hand.card_nodes) do
        table.insert(ordered, node)
    end
    self.nodes = ordered
end

--- Puts selected hand cards at the end of the draw list so they render on top.
function Game:move_selected_hand_cards_to_front()
    if not self.hand or #self.hand.selected == 0 then return end
    local sel = {}
    for _, n in ipairs(self.hand.selected) do sel[n] = true end
    local ordered = {}
    for _, node in ipairs(self.nodes) do
        if not sel[node] then
            table.insert(ordered, node)
        end
    end
    for _, node in ipairs(self.hand.selected) do
        table.insert(ordered, node)
    end
    self.nodes = ordered
end

function Game:ensure_asset_atlas_loaded(name)
    if not name or not self.ASSET_ATLAS then return nil end
    local atlas = self.ASSET_ATLAS[name]
    if not atlas then return nil end
    if atlas.image then return atlas end
    if not atlas.path then return atlas end

    local ok, img = pcall(love.graphics.newImage, atlas.path, { dpiscale = atlas.dpiscale or self.SETTINGS.GRAPHICS.texture_scaling })
    local err = ok and nil or img
    if not ok then
        ok, img = pcall(love.graphics.newImage, atlas.path, {})
        if not ok then err = img end
    end
    atlas.image = ok and img or nil
    atlas.load_error = ok and nil or tostring(err)
    return atlas
end

function Game:set_render_settings()
    self.SETTINGS.GRAPHICS.texture_scaling = self.SETTINGS.GRAPHICS.texture_scaling or 1

    love.graphics.setDefaultFilter(
        self.SETTINGS.GRAPHICS.texture_scaling == 1 and 'nearest' or 'linear',
        self.SETTINGS.GRAPHICS.texture_scaling == 1 and 'nearest' or 'linear', 1
    )
    love.graphics.setLineStyle("rough")

        --spritesheets
        self.animation_atli = {
            {name = "blind_chips", path = "resources/textures/1x/BlindChips.png",px=36,py=36, frames = 21},
            {name = "shop_sign", path = "resources/textures/1x/ShopSignAnimation.png",px=113,py=60, frames = 4}
        }
        self.asset_atli = {
            {name = "cards_1", path = "resources/textures/1x/8BitDeck.png",px=72,py=95},
            {name = "cards_2", path = "resources/textures/1x/8BitDeck_opt2.png",px=72,py=95},
            {name = "centers", path = "resources/textures/1x/Enhancers.png",px=72,py=95},
            {name = "Joker1", path = "resources/textures/1x/Jokers1.png",px=71,py=95},
            {name = "Joker2", path = "resources/textures/1x/Jokers2.png",px=71,py=95},
            {name = "Joker1_negative", path = "resources/textures/1x/Jokers1_negative.png",px=71,py=95},
            {name = "Joker2_negative", path = "resources/textures/1x/Jokers2_negative.png",px=71,py=95},
            {name = "Tarot", path = "resources/textures/1x/Tarots.png",px=71,py=95},
            {name = "Voucher", path = "resources/textures/1x/Vouchers.png",px=72,py=95},
            {name = "Booster", path = "resources/textures/1x/boosters.png",px=72,py=95},
            {name = "ui_1", path = "resources/textures/1x/ui_assets.png",px=18,py=18},
            {name = "ui_2", path = "resources/textures/1x/ui_assets_opt2.png",px=18,py=18},
            {name = "balatro", path = "resources/textures/1x/balatro.png",px=336,py=216},        
            {name = 'gamepad_ui', path = "resources/textures/1x/gamepad_ui.png",px=32,py=32},
            {name = 'icons', path = "resources/textures/1x/icons.png",px=66,py=66},
            {name = 'tags', path = "resources/textures/1x/tags.png",px=34,py=34},
            {name = 'stickers', path = "resources/textures/1x/stickers.png",px=72,py=95},
            {name = 'chips', path = "resources/textures/1x/chips.png",px=30,py=30},
    
            --[[ {name = 'collab_AU_1', path = "resources/textures/1x/collabs/collab_AU_1.png",px=71,py=95},
            {name = 'collab_AU_2', path = "resources/textures/1x/collabs/collab_AU_2.png",px=71,py=95},
            {name = 'collab_TW_1', path = "resources/textures/1x/collabs/collab_TW_1.png",px=71,py=95},
            {name = 'collab_TW_2', path = "resources/textures/1x/collabs/collab_TW_2.png",px=71,py=95},
            {name = 'collab_VS_1', path = "resources/textures/1x/collabs/collab_VS_1.png",px=71,py=95},
            {name = 'collab_VS_2', path = "resources/textures/1x/collabs/collab_VS_2.png",px=71,py=95},
            {name = 'collab_DTD_1', path = "resources/textures/1x/collabs/collab_DTD_1.png",px=71,py=95},
            {name = 'collab_DTD_2', path = "resources/textures/1x/collabs/collab_DTD_2.png",px=71,py=95},
    
            {name = 'collab_CYP_1', path = "resources/textures/1x/collabs/collab_CYP_1.png",px=71,py=95},
            {name = 'collab_CYP_2', path = "resources/textures/1x/collabs/collab_CYP_2.png",px=71,py=95},
            {name = 'collab_STS_1', path = "resources/textures/1x/collabs/collab_STS_1.png",px=71,py=95},
            {name = 'collab_STS_2', path = "resources/textures/1x/collabs/collab_STS_2.png",px=71,py=95},
            {name = 'collab_TBoI_1', path = "resources/textures/1x/collabs/collab_TBoI_1.png",px=71,py=95},
            {name = 'collab_TBoI_2', path = "resources/textures/1x/collabs/collab_TBoI_2.png",px=71,py=95},
            {name = 'collab_SV_1', path = "resources/textures/1x/collabs/collab_SV_1.png",px=71,py=95},
            {name = 'collab_SV_2', path = "resources/textures/1x/collabs/collab_SV_2.png",px=71,py=95},
            
            {name = 'collab_SK_1', path = "resources/textures/1x/collabs/collab_SK_1.png",px=71,py=95},
            {name = 'collab_SK_2', path = "resources/textures/1x/collabs/collab_SK_2.png",px=71,py=95},
            {name = 'collab_DS_1', path = "resources/textures/1x/collabs/collab_DS_1.png",px=71,py=95},
            {name = 'collab_DS_2', path = "resources/textures/1x/collabs/collab_DS_2.png",px=71,py=95},
            {name = 'collab_CL_1', path = "resources/textures/1x/collabs/collab_CL_1.png",px=71,py=95},
            {name = 'collab_CL_2', path = "resources/textures/1x/collabs/collab_CL_2.png",px=71,py=95},
            {name = 'collab_D2_1', path = "resources/textures/1x/collabs/collab_D2_1.png",px=71,py=95},
            {name = 'collab_D2_2', path = "resources/textures/1x/collabs/collab_D2_2.png",px=71,py=95},
            {name = 'collab_PC_1', path = "resources/textures/1x/collabs/collab_PC_1.png",px=71,py=95},
            {name = 'collab_PC_2', path = "resources/textures/1x/collabs/collab_PC_2.png",px=71,py=95},
            {name = 'collab_WF_1', path = "resources/textures/1x/collabs/collab_WF_1.png",px=71,py=95},
            {name = 'collab_WF_2', path = "resources/textures/1x/collabs/collab_WF_2.png",px=71,py=95},
            {name = 'collab_EG_1', path = "resources/textures/1x/collabs/collab_EG_1.png",px=71,py=95},
            {name = 'collab_EG_2', path = "resources/textures/1x/collabs/collab_EG_2.png",px=71,py=95},
            {name = 'collab_XR_1', path = "resources/textures/1x/collabs/collab_XR_1.png",px=71,py=95},
            {name = 'collab_XR_2', path = "resources/textures/1x/collabs/collab_XR_2.png",px=71,py=95},
    
            {name = 'collab_CR_1', path = "resources/textures/1x/collabs/collab_CR_1.png",px=71,py=95},
            {name = 'collab_CR_2', path = "resources/textures/1x/collabs/collab_CR_2.png",px=71,py=95},
            {name = 'collab_BUG_1', path = "resources/textures/1x/collabs/collab_BUG_1.png",px=71,py=95},
            {name = 'collab_BUG_2', path = "resources/textures/1x/collabs/collab_BUG_2.png",px=71,py=95},
            {name = 'collab_FO_1', path = "resources/textures/1x/collabs/collab_FO_1.png",px=71,py=95},
            {name = 'collab_FO_2', path = "resources/textures/1x/collabs/collab_FO_2.png",px=71,py=95},
            {name = 'collab_DBD_1', path = "resources/textures/1x/collabs/collab_DBD_1.png",px=71,py=95},
            {name = 'collab_DBD_2', path = "resources/textures/1x/collabs/collab_DBD_2.png",px=71,py=95},
            {name = 'collab_C7_1', path = "resources/textures/1x/collabs/collab_C7_1.png",px=71,py=95},
            {name = 'collab_C7_2', path = "resources/textures/1x/collabs/collab_C7_2.png",px=71,py=95},
            {name = 'collab_R_1', path = "resources/textures/1x/collabs/collab_R_1.png",px=71,py=95},
            {name = 'collab_R_2', path = "resources/textures/1x/collabs/collab_R_2.png",px=71,py=95},
            {name = 'collab_AC_1', path = "resources/textures/1x/collabs/collab_AC_1.png",px=71,py=95},
            {name = 'collab_AC_2', path = "resources/textures/1x/collabs/collab_AC_2.png",px=71,py=95},
            {name = 'collab_STP_1', path = "resources/textures/1x/collabs/collab_STP_1.png",px=71,py=95},
            {name = 'collab_STP_2', path = "resources/textures/1x/collabs/collab_STP_2.png",px=71,py=95}, ]]
        }
        self.asset_images = {
            {name = "playstack_logo", path = "resources/textures/1x/playstack-logo.png", px=1416,py=1416},
            {name = "localthunk_logo", path = "resources/textures/1x/localthunk-logo.png", px=1390,py=560}
        }
    
        -- Helper: load image with no mipmaps for pixel-art memory savings.
        local function load_image(path, options)
            local ok, img = pcall(love.graphics.newImage, path, options or {})
            if not ok and options and options.dpiscale then
                ok, img = pcall(love.graphics.newImage, path, {})
            end
            return ok and img or nil
        end

        -- Animation atlases are small; load eagerly (no mipmaps).
        for i=1, #self.animation_atli do
            self.ANIMATION_ATLAS[self.animation_atli[i].name] = {}
            self.ANIMATION_ATLAS[self.animation_atli[i].name].name = self.animation_atli[i].name
            self.ANIMATION_ATLAS[self.animation_atli[i].name].path = self.animation_atli[i].path
            self.ANIMATION_ATLAS[self.animation_atli[i].name].image = load_image(self.animation_atli[i].path, {dpiscale = self.SETTINGS.GRAPHICS.texture_scaling})
            self.ANIMATION_ATLAS[self.animation_atli[i].name].px = self.animation_atli[i].px
            self.ANIMATION_ATLAS[self.animation_atli[i].name].py = self.animation_atli[i].py
            self.ANIMATION_ATLAS[self.animation_atli[i].name].frames = self.animation_atli[i].frames
        end

        -- Register all asset atlases, lazy-load textures on first use.
        for i=1, #self.asset_atli do
            self.ASSET_ATLAS[self.asset_atli[i].name] = {}
            self.ASSET_ATLAS[self.asset_atli[i].name].name = self.asset_atli[i].name
            self.ASSET_ATLAS[self.asset_atli[i].name].path = self.asset_atli[i].path
            self.ASSET_ATLAS[self.asset_atli[i].name].dpiscale = self.SETTINGS.GRAPHICS.texture_scaling
            self.ASSET_ATLAS[self.asset_atli[i].name].image = nil
            self.ASSET_ATLAS[self.asset_atli[i].name].type = self.asset_atli[i].type
            self.ASSET_ATLAS[self.asset_atli[i].name].px = self.asset_atli[i].px
            self.ASSET_ATLAS[self.asset_atli[i].name].py = self.asset_atli[i].py
        end
        for i=1, #self.asset_images do
            self.ASSET_ATLAS[self.asset_images[i].name] = {}
            self.ASSET_ATLAS[self.asset_images[i].name].name = self.asset_images[i].name
            self.ASSET_ATLAS[self.asset_images[i].name].path = self.asset_images[i].path
            self.ASSET_ATLAS[self.asset_images[i].name].dpiscale = 1
            self.ASSET_ATLAS[self.asset_images[i].name].image = nil
            self.ASSET_ATLAS[self.asset_images[i].name].type = self.asset_images[i].type
            self.ASSET_ATLAS[self.asset_images[i].name].px = self.asset_images[i].px
            self.ASSET_ATLAS[self.asset_images[i].name].py = self.asset_images[i].py
        end

        self.ASSET_ATLAS.Planet = self.ASSET_ATLAS.Tarot
        self.ASSET_ATLAS.Spectral = self.ASSET_ATLAS.Tarot

        for _, v in pairs(G.I.SPRITE) do
            v:reset()
        end
end
