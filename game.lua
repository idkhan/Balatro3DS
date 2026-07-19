---@class Game
Game = Object:extend()

local ShopUI = require("shop_ui")
local DragZonesUI = require("drag_zones_ui")
local RoundWinUI = require("round_win_ui")
local GameOverUI = require("game_over_ui")
local BoosterPackUI = require("booster_pack_ui")
local MainMenuUI = require("main_menu_ui")
local DeckViewUI = require("deck_view_ui")
local CollectionUI = require("collection_ui")
local CollectionCatalog = require("collection_catalog")
local YouWinUI = require("you_win")
local TooltipDraw = require("tooltip_draw")

--- Seconds between revealing each payout line on the round-win screen.
local ROUND_WIN_LINE_DELAY = 0.38
local RUN_SAVE_DIR = "sdmc"
local PROFILE_COUNT = 3
local ACTIVE_PROFILE_PATH = "sdmc/Balatro3DS_active_profile.lua"
--- P1 keeps legacy filenames for older installs.
local SETTINGS_SAVE_PATH_P1 = "sdmc/Balatro3DS_settings.lua"
local RUN_SAVE_PATH_P1 = "sdmc/Balatro3DS_run_save_1.lua"

local function table_shallow_copy(src)
    if type(src) ~= "table" then return nil end
    local out = {}
    for k, v in pairs(src) do
        out[k] = v
    end
    return out
end

local function table_array_deep_copy(src)
    if type(src) ~= "table" then return {} end
    local out = {}
    for i, v in ipairs(src) do
        if type(v) == "table" then
            out[i] = copy_table(v)
        else
            out[i] = v
        end
    end
    return out
end

local function encode_lua_string(s)
    return string.format("%q", tostring(s))
end

local function serialize_lua_value(v)
    local tv = type(v)
    if tv == "nil" then return "nil" end
    if tv == "number" then
        if v ~= v or v == math.huge or v == -math.huge then
            return "0"
        end
        return tostring(v)
    end
    if tv == "boolean" then return v and "true" or "false" end
    if tv == "string" then return encode_lua_string(v) end
    if tv ~= "table" then return "nil" end

    local parts = {}
    local n = #v
    for i = 1, n do
        parts[#parts + 1] = serialize_lua_value(v[i])
    end
    for k, val in pairs(v) do
        if not (type(k) == "number" and k >= 1 and k <= n and math.floor(k) == k) then
            local key_expr
            if type(k) == "string" and k:match("^[%a_][%w_]*$") then
                key_expr = k
            else
                key_expr = "[" .. serialize_lua_value(k) .. "]"
            end
            parts[#parts + 1] = key_expr .. "=" .. serialize_lua_value(val)
        end
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

---@param seed number|nil Optional seed for the RNG. If nil, a seed is generated (os.time()).
function Game:init(seed)
    G = self
    -- core containers/state
    self.nodes = {}
    self.popups = {}
    self.tags = {}
    self.skips = {}
    self.skip_tag_orbital_hand = {}
    self._atlas_owner_counts = {}
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
    self.active_tooltip_skip_blind_index = nil
    self.active_tooltip_blind_index = nil
    self._pause_prev_state = nil
    self._pause_continue_rect = nil
    self._pause_new_run_rect = nil
    self._pause_save_quit_rect = nil
    self._pause_save_error = nil
    self._deck_view_open = false
    self._pause_settings_rect = nil
    self._pause_show_settings = false
    self._pause_speed_rects = {}
    self._pause_music_slider_rect = nil
    self._pause_music_slider_drag = false
    -- D-pad card cursor and gamepad focus layers (hand / jokers / consumables)
    self._dpad_cursor_index = nil
    self._gamepad_focus_layer = "hand"
    self._consumable_focus_index = nil
    self._l_held = false
    self._l_press_time = nil
    self._r_held = false
    self._r_press_time = nil
    self._r_dpad_used = false
    self._r_sweep_seeded = false
    self._pause_focus_index = nil
    self._main_menu_continue_rect = nil
    self._menu_focus_index = 1
    self.round_score = 0
    self.last_hand_score = 0
    self.last_played_hand_index = nil
    --- Run currency
    self.money = 0
    -- Run Discards
    self.discards = 4
    -- Run Hands
    self.hands = 4
    -- Permanent run modifier from Spectral cards (e.g. Ouija/Ectoplasm).
    self.hand_size_delta_spectral = 0
    self.hand_size_delta_juggle = 0
    self._shop_reroll_base_cost_override = nil
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
    self.shop_booster_offers = {}
    self.shop_booster_slots = 2
    self.active_shop_booster_slot = nil
    self.booster_session = nil
    self.shop_offer_slots = 2
    self.shop_reroll_base_cost = 5
    self.shop_reroll_count = 0
    --- Redeemed vouchers this run (array of ids); see `has_voucher` / `VOUCHER_DEFS`.
    self.vouchers = {}
    self.shop_voucher_offers = {}
    self.shop_voucher_nodes = {}
    self.shop_booster_nodes = {}
    self.shop_voucher_bought_pending_boss = false
    self.active_tooltip_shop_voucher_slot = nil
    self._gamepad_bottom_layer = nil
    self._shop_focus_index = nil
    self._joker_focus_index = nil
    self._joker_swap_pick_index = nil
    self.hand_size_delta_voucher = 0
    self.boss_rerolls_used_this_ante = 0
    self._boss_reroll_btn_rect = nil
    self.hand_play_counts = {}
    self.blind_hand_play_counts = {}
    self._ante_played_card_uids = {}
    self.current_boss_blind_id = nil
    self.bosses_used_this_cycle = {}
    self.boss_runtime = {}
    self._next_card_uid = 1
    self._collidables_buf = {}
    self._gc_timer = 0
    self._gc_discarded_nodes = 0
    --- Staggered joker resolution (left-to-right); see `begin_joker_emit` / `_update_joker_emit_queue`.
    self._joker_emit_queue = nil
    self._joker_emit_next = 1
    self._joker_emit_timer = 0
    self.JOKER_EMIT_INTERVAL = 0.25

    -- Run Consumables (Tarot / Planet cards held outside the deck).
    self.consumables = {}
    self.consumable_base_capacity = 2
    self.consumable_capacity = 2
    self._consumable_rects = {}
    self.consumable_nodes = {}
    self.tarots_used = 0
    --- Last consumable id used this run (Tarot except Fool, or Planet); for The Fool duplicate.
    self.last_consumable_use_id = nil

    self.joker_pool_replacements = {}
    self.joker_pool_swap_pairs = {
        { from = "j_gros_michel", to = "j_cavendish" },
    }

    self.handsPlayed = 0
    self.discardsUnused = 0
    self.skipsTaken = 0
    self:reset_run_stats()

    -- Pull all shared globals from globals.lua
    if self.set_globals then
        self:set_globals()
    end
    self._profile_id = 1
    self._delete_save_confirm = false
    if self.load_active_profile then
        self:load_active_profile()
    end
    if self.load_settings then
        self:load_settings()
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

function Game:reset_run_stats()
    self.run_best_hand_score = 0
    self.run_cards_played = 0
    self.run_cards_discarded = 0
    self.run_cards_purchased = 0
    self.run_times_rerolled = 0
end

--- Highest single-hand score this run.
function Game:record_hand_score(score)
    local s = math.floor(tonumber(score) or 0)
    if s > (tonumber(self.run_best_hand_score) or 0) then
        self.run_best_hand_score = s
    end
end

function Game:record_cards_played(count)
    local n = math.floor(tonumber(count) or 0)
    if n <= 0 then return end
    self.run_cards_played = (tonumber(self.run_cards_played) or 0) + n
end

function Game:record_cards_discarded(count)
    local n = math.floor(tonumber(count) or 0)
    if n <= 0 then return end
    self.run_cards_discarded = (tonumber(self.run_cards_discarded) or 0) + n
end

function Game:record_card_purchased(count)
    local n = math.floor(tonumber(count) or 1)
    if n <= 0 then return end
    self.run_cards_purchased = (tonumber(self.run_cards_purchased) or 0) + n
end

function Game:record_shop_reroll()
    self.run_times_rerolled = (tonumber(self.run_times_rerolled) or 0) + 1
end

--- Poker-hand name with the highest play count this run (handlist order breaks ties).
---@return string
function Game:get_most_played_hand_name()
    local best_idx, best_count = nil, 0
    for i, name in ipairs(self.handlist or {}) do
        local c = tonumber(self.hand_play_counts and self.hand_play_counts[i]) or 0
        if c > best_count then
            best_count = c
            best_idx = i
        end
    end
    if not best_idx or best_count <= 0 then return "None" end
    return tostring(self.handlist[best_idx] or "None")
end

function Game:increment_hand_play_count(hand_index)
    local hi = math.floor(tonumber(hand_index) or -1)
    if hi < 1 then return end
    self.hand_play_counts = self.hand_play_counts or {}
    self.blind_hand_play_counts = self.blind_hand_play_counts or {}
    self.hand_play_counts[hi] = (tonumber(self.hand_play_counts[hi]) or 0) + 1
    self.blind_hand_play_counts[hi] = (tonumber(self.blind_hand_play_counts[hi]) or 0) + 1
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
    if self.STATE ~= self.STATES.SELECTING_HAND then return nil end
    if tonumber(self.current_blind_index) ~= 3 then return nil end
    local proto = self:get_boss_blind_prototype()
    if not proto then return nil end
    if self:hasJoker("j_chicot") then return nil end
    if self.boss_runtime and self.boss_runtime.disable_current_boss_ability == true then return nil end
    return self.current_boss_blind_id
end

function Game:get_effective_hand_size_limit()
    local limit = 8
    limit = limit + (self.deck_hand_size or 0)
    limit = limit + (tonumber(self.hand_size_delta_spectral) or 0)
    limit = limit + (tonumber(self.hand_size_delta_voucher) or 0)
    limit = limit + (tonumber(self.hand_size_delta_juggle) or 0)
    for _, j in ipairs(self.jokers or {}) do
        local id = j and j.def and j.def.id
        if id == "j_juggler" then limit = limit + 1 end
        if id == "j_turtle_bean" then limit = limit + j.runtime_counter end
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
    local hands = 4 -- Base value
    if self:has_voucher("v_hieroglyph") then hands = hands - 1 end
    if self:has_voucher("v_grabber") then hands = hands + 1 end
    if self:has_voucher("v_nacho") then hands = hands + 1 end
    hands = hands + (self.deck_hands or 0)
    for _, j in ipairs(self.jokers or {}) do
        local id = j and j.def and j.def.id
        if id == "j_burglar" then hands = hands + 3 end
        if id == "j_troubadour" then hands = hands - 1 end
    end
    return math.max(1, hands)
end

function Game:get_effective_discards_per_round()
    local discards = 3 -- Base is 3 (Red Deck is 4)
    if self:has_voucher("v_wasteful") then discards = discards + 1 end
    if self:has_voucher("v_recyclomancy") then discards = discards + 1 end
    if self:has_voucher("v_petroglyph") then discards = discards - 1 end
    discards = discards  + (self.deck_discards or 0) + (self._stake_discard or 0)
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
        disable_current_boss_ability = false,
        clear_card_debuffs_after_win = false,
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
    if self:hasJoker("j_chicot") then return end

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
        self:notify_boss_effect_triggered({ reason = "on_card_drawn" })
    end
end

function Game:boss_consume_serpent_draws(default_limit, current_count)
    local boss_id = self:get_active_boss_blind_id()
    if boss_id ~= "bl_serpent" then return default_limit end
    local pending = math.max(0, math.floor(tonumber(self.boss_runtime.serpent_draws_pending) or 0))
    if pending <= 0 then return default_limit end
    self.boss_runtime.serpent_draws_pending = 0
    self:notify_boss_effect_triggered({ reason = "serpent_draw_pending" })
    return math.max(default_limit, current_count + pending)
end

function Game:boss_after_discard_or_play(reason)
    local boss_id = self:get_active_boss_blind_id()
    if not boss_id then return end
    if boss_id == "bl_serpent" then
        self.boss_runtime.serpent_draws_pending = 3
        self:notify_boss_effect_triggered({ reason = "serpent_after_" .. tostring(reason or "unknown") })
    end
    if reason == "play" and boss_id == "bl_fish" then
        self.boss_runtime.fish_face_down_draws = self:get_effective_hand_size_limit()
        self:notify_boss_effect_triggered({ reason = "fish_after_play" })
    end
end

function Game:boss_after_play_before_draw()
    local boss_id = self:get_active_boss_blind_id()
    if boss_id ~= "bl_hook" then return end
    local hand = self.hand
    if not hand or not hand.cards then return end
    local removed = 0
    for _ = 1, 2 do
        if #hand.cards <= 0 then break end
        local i = math.random(1, #hand.cards)
        if hand.discard_card_at_index then
            hand:discard_card_at_index(i)
            removed = removed + 1
        end
    end
    if removed > 0 then
        self:notify_boss_effect_triggered({ reason = "hook_discard", count = removed })
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
            self:notify_boss_effect_triggered({ reason = "mouth_void_play" })
        end
    end
    if boss_id == "bl_eye" then
        if self.boss_runtime.seen_hand_types[hand_name] then
            self.boss_runtime.eye_void_play = true
            self:notify_boss_effect_triggered({ reason = "eye_void_play" })
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
            if not has_forced then
                self:notify_boss_effect_triggered({ reason = "final_bell_missing_forced" })
                return false
            end
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
        local floor = self:get_money_loss_floor()
        local before = tonumber(self.money) or 0
        self.money = math.max(floor, (tonumber(self.money) or 0) - n)
        if (tonumber(self.money) or 0) < before then
            self:notify_boss_effect_triggered({ reason = "tooth_money_loss", amount = before - (tonumber(self.money) or 0) })
        end
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
            local before = tonumber(self.money) or 0
            self.money = 0
            if before ~= 0 then
                self:notify_boss_effect_triggered({ reason = "ox_zero_money", amount = before })
            end
        end
    elseif boss_id == "bl_arm" then
        local hs = self.hand_stats and self.hand_stats[hand_idx]
        if hs then
            local prev_level = tonumber(hs.level) or 1
            hs.level = math.max(1, (tonumber(hs.level) or 1) - 1)
            local level = tonumber(hs.level) or 1
            self.selectedHandLevel = level
            self.selectedHandChips = (tonumber(hs.base_chips) or 0) + ((level - 1) * (tonumber(hs.chips_per_level) or 0))
            self.selectedHandMult = (tonumber(hs.base_mult) or 0) + ((level - 1) * (tonumber(hs.mult_per_level) or 0))
            if level < prev_level then
                self:notify_boss_effect_triggered({ reason = "arm_level_down", from_level = prev_level, to_level = level })
            end
        end
    end

end

function Game:boss_is_card_debuffed_for_scoring(node)
    if self.boss_runtime and self.boss_runtime.clear_card_debuffs_after_win == true then return false end
    local boss_id = self:get_active_boss_blind_id()
    if not boss_id or not node then return false end
    local d = node.card_data or {}
    local rank = tonumber(d.rank) or 0
    local suit = d.suit
    local is_wild = d.enhancement == "wild"
    if boss_id == "bl_club" and (suit == "Clubs" or is_wild) then return true end
    if boss_id == "bl_goad" and (suit == "Spades" or is_wild) then return true end
    if boss_id == "bl_window" and (suit == "Diamonds" or is_wild) then return true end
    if boss_id == "bl_head" and (suit == "Hearts" or is_wild) then return true end
    if boss_id == "bl_plant" and ((rank >= 11 and rank <= 13) or self:hasJoker("j_pareidolia")) then return true end
    if boss_id == "bl_pillar" and d.uid and self._ante_played_card_uids[d.uid] then return true end
    if boss_id == "bl_final_leaf" and self.boss_runtime.verdant_leaf_active == true then return true end
    return false
end

function Game:boss_is_joker_debuffed(node)
    local boss_id = self:get_active_boss_blind_id()
    if boss_id ~= "bl_final_heart" or not node then return false end
    if type(self.jokers) ~= "table" then return false end

    local sorted = {}
    for _, j in ipairs(self.jokers) do
        if j then table.insert(sorted, j) end
    end
    table.sort(sorted, function(a, b)
        local ax = (a.T and a.T.x) or (a.VT and a.VT.x) or 0
        local bx = (b.T and b.T.x) or (b.VT and b.VT.x) or 0
        return ax < bx
    end)

    local blocked = tonumber(self.boss_runtime and self.boss_runtime.crimson_disabled_joker) or -1
    return blocked >= 1 and blocked <= #sorted and sorted[blocked] == node
end

function Game:boss_apply_hand_base_modifiers(chips, mult)
    local boss_id = self:get_active_boss_blind_id()
    chips = tonumber(chips) or 0
    mult = tonumber(mult) or 0
    if boss_id == "bl_flint" then
        chips = math.floor(chips * 0.5)
        mult = math.max(1, math.floor(mult * 0.5))
        self:notify_boss_effect_triggered({ reason = "flint_base_halved" })
    end
    return chips, mult
end

function Game:boss_on_joker_sold(sold_joker)
    if sold_joker and sold_joker.def and sold_joker.def.id == "j_luchador" and self:get_active_boss_blind_id() then
        self.boss_runtime = self.boss_runtime or {}
        self.boss_runtime.disable_current_boss_ability = true
        self.boss_runtime.verdant_leaf_active = false
        return
    end
    if self:get_active_boss_blind_id() == "bl_final_leaf" then
        self.boss_runtime.verdant_leaf_active = false
        self.boss_runtime.sold_joker_this_blind = true
    end
end

function Game:notify_boss_effect_triggered(meta)
    local boss_id = self:get_active_boss_blind_id()
    if not boss_id then return end
    self:emit_joker_event("on_boss_effect_triggered", {
        boss_id = boss_id,
        reason = meta and meta.reason or "",
        meta = meta,
    })
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
        local need_cons = (offer.kind == "tarot" or offer.kind == "planet" or offer.kind == "spectral")
        local need_pc = (offer.kind == "playing_card")

        if node then
            local is_j = Joker and node.is and node:is(Joker)
            local is_c = Consumable and node.is and node:is(Consumable)
            local is_pc = Card and node.is and node:is(Card)
            local ok = (need_joker and is_j) or (need_cons and is_c) or (need_pc and is_pc)
            if ok and need_joker and is_j and node.def and offer.id and node.def.id ~= offer.id then
                ok = false
            end
            if ok and need_cons and is_c and node.def and offer.id and node.def.id ~= offer.id then
                ok = false
            end
            if ok and need_pc and is_pc and offer.card_data and node.card_data then
                local a = offer.card_data.rank .. tostring(offer.card_data.suit)
                local b = (node.card_data.rank or "") .. tostring(node.card_data.suit or "")
                if a ~= b then ok = false end
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
                    local create_params = offer.create_params
                    if type(create_params) ~= "table" then
                        create_params = self:_build_joker_create_params(def, { edition = offer.edition }, offer.stickers)
                    end
                    if type(create_params) ~= "table" then
                        create_params = { face_up = true, edition = offer.edition }
                    else
                        create_params.face_up = true
                    end
                    node = Joker(0, 0, self.joker_slot_w, self.joker_slot_h, def, create_params)
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
            elseif need_pc and Card and copy_table then
                local cd = copy_table(offer.card_data)
                if type(cd) == "table" then
                    node = Card(0, 0, self.joker_slot_w, self.joker_slot_h, cd, nil, { face_up = true })
                    if node.sync_visual_from_card_data then
                        node:sync_visual_from_card_data()
                    end
                    self.shop_offer_nodes[i] = node
                    self:add(node)
                end
            end
        end
        if node then
            node.shop_offer_slot = i
            local active = (self.STATE == self.STATES.SHOP)
            node.states.visible = active
            node.states.click.can = active
            node.states.drag.can = active
            node.states.collide.can = false
        end
    end
end

function Game:layout_shop_offer_nodes(param)
    ShopUI.layout_shop_offer_nodes(self, param)
end

function Game:sync_shop_offer_interactivity()
    local active = (self.STATE == self.STATES.SHOP)
    local tooltip_is_shop_offer = false
    for _, node in ipairs(self.shop_offer_nodes or {}) do
        if node and node.states then
            node.states.visible = active
            node.states.click.can = active
            node.states.drag.can = active
        end
        if node and self.active_tooltip_joker == node then
            tooltip_is_shop_offer = true
        end
    end
    if not active and tooltip_is_shop_offer then
        self.active_tooltip_joker = nil
    end
    if self.sync_shop_booster_nodes then self:sync_shop_booster_nodes() end
    if self.sync_shop_voucher_nodes then self:sync_shop_voucher_nodes() end
end

function Game:clear_shop_booster_nodes()
    if type(self.shop_booster_nodes) ~= "table" then
        self.shop_booster_nodes = {}
        return
    end
    for _, node in ipairs(self.shop_booster_nodes) do
        if node then self:remove(node) end
    end
    self.shop_booster_nodes = {}
end

function Game:sync_shop_booster_nodes()
    if type(self.shop_booster_offers) ~= "table" then self.shop_booster_offers = {} end
    if type(self.shop_booster_nodes) ~= "table" then self.shop_booster_nodes = {} end
    if not ShopBoosterNode then return end

    for i = #self.shop_booster_nodes, #self.shop_booster_offers + 1, -1 do
        local node = self.shop_booster_nodes[i]
        if node then self:remove(node) end
        table.remove(self.shop_booster_nodes, i)
    end

    local active = (self.STATE == self.STATES.SHOP)
    for i, offer in ipairs(self.shop_booster_offers) do
        local node = self.shop_booster_nodes[i]
        if not node then
            node = ShopBoosterNode(0, 0, 72, 95, offer, i)
            self.shop_booster_nodes[i] = node
            self:add(node)
        else
            node.shop_booster_offer = offer
            node.shop_booster_slot = i
        end
        if node.states then
            node.states.visible = active
            node.states.click.can = active
            node.states.drag.can = active
        end
    end
end

function Game:clear_shop_voucher_nodes()
    if type(self.shop_voucher_nodes) ~= "table" then
        self.shop_voucher_nodes = {}
        return
    end
    for _, node in ipairs(self.shop_voucher_nodes) do
        if node then self:remove(node) end
    end
    self.shop_voucher_nodes = {}
end

function Game:sync_shop_voucher_nodes()
    if type(self.shop_voucher_offers) ~= "table" then self.shop_voucher_offers = {} end
    if type(self.shop_voucher_nodes) ~= "table" then self.shop_voucher_nodes = {} end
    if not ShopVoucherNode then return end

    for i = #self.shop_voucher_nodes, #self.shop_voucher_offers + 1, -1 do
        local node = self.shop_voucher_nodes[i]
        if node then self:remove(node) end
        table.remove(self.shop_voucher_nodes, i)
    end

    local active = (self.STATE == self.STATES.SHOP)
    for i, offer in ipairs(self.shop_voucher_offers) do
        local node = self.shop_voucher_nodes[i]
        if not node then
            node = ShopVoucherNode(0, 0, 72, 95, offer, i)
            self.shop_voucher_nodes[i] = node
            self:add(node)
        else
            node.shop_voucher_offer = offer
            node.shop_voucher_slot = i
        end
        if node.states then
            node.states.visible = active
            node.states.click.can = active
            node.states.drag.can = active
        end
    end
end

function Game:can_buy_shop_offer(slot_index)
    local offer = self.shop_offers and self.shop_offers[slot_index]
    if not offer then return false end
    if not self:can_afford_price(self:get_shop_offer_price(offer)) then return false end
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
        local cap_after = self:joker_base_capacity() + neg_owned + (new_neg and 1 or 0)
        return #self.jokers < cap_after
    elseif k == "tarot" or k == "planet" or k == "spectral" then
        local params = nil
        if offer.edition then
            params = { edition = offer.edition }
        end
        return self:can_add_consumable(params)
    elseif k == "playing_card" then
        return true
    end
    return false
end

function Game:resolve_drag_context(node)
    if not node then return nil end
    local slot = tonumber(node.shop_offer_slot)
    if slot and slot >= 1 and self.shop_offers and self.shop_offers[slot] then
        return { kind = "shop_offer", slot_index = slot, node = node }
    end
    for i, n in ipairs(self.shop_offer_nodes or {}) do
        if n == node then
            return { kind = "shop_offer", slot_index = i, node = node }
        end
    end
    if node.shop_booster_slot then
        return { kind = "shop_booster", slot_index = tonumber(node.shop_booster_slot), node = node }
    end
    if node.shop_voucher_slot then
        return { kind = "shop_voucher", slot_index = tonumber(node.shop_voucher_slot), node = node }
    end
    if node._booster_choice_index then
        return { kind = "booster_choice", choice_index = tonumber(node._booster_choice_index), node = node }
    end
    for i, j in ipairs(self.jokers or {}) do
        if j == node then
            return { kind = "owned_joker", index = i, node = node }
        end
    end
    for idx, cnode in ipairs(self.consumable_nodes or {}) do
        if cnode == node then
            return { kind = "owned_consumable", index = idx, node = node }
        end
    end
    return nil
end

function Game:get_drag_zones_for_context(ctx)
    if not ctx or not ctx.kind then return nil end
    local C = self.C or {}
    local zones = { top = nil, top_right = nil, bottom = nil }

    if ctx.kind == "shop_offer" then
        local offer = self.shop_offers and self.shop_offers[ctx.slot_index]
        local can_buy = self:can_buy_shop_offer(ctx.slot_index)
        zones.top = DragZonesUI.make_zone("BUY", can_buy, can_buy and C.MONEY or C.GREY, "buy", true)
        if offer and (offer.kind == "tarot" or offer.kind == "planet" or offer.kind == "spectral") then
            -- Instant-use does not need an inventory slot (planets, Hermit, Temperance, etc.).
            local can_afford = self:can_afford_price(self:get_shop_offer_price(offer))
            local can_buy_use = can_afford and self:shop_offer_consumable_use_enabled(offer)
            zones.top_right = DragZonesUI.make_zone("BUY and USE", can_buy_use, can_buy_use and C.GREEN or C.GREY, "buy_use", true)
        end
    elseif ctx.kind == "shop_booster" then
        local offer = self.shop_booster_offers and self.shop_booster_offers[ctx.slot_index]
        local can_buy = offer and self:can_afford_price(self:get_shop_booster_price(offer))
        zones.top = DragZonesUI.make_zone("BUY", can_buy, can_buy and C.MONEY or C.GREY, "buy", true)
    elseif ctx.kind == "shop_voucher" then
        local offer = self.shop_voucher_offers and self.shop_voucher_offers[ctx.slot_index]
        local can_buy = offer and self:can_afford_price(self:get_shop_voucher_price(offer))
            and not self:_voucher_already_owned(offer.id)
        zones.top = DragZonesUI.make_zone("BUY", can_buy, can_buy and C.MONEY or C.GREY, "buy", true)
    elseif ctx.kind == "owned_joker" then
        local joker = self.jokers and self.jokers[ctx.index]
        local eternal = joker and joker.eternal == true
        local sell_value = math.floor(tonumber(joker and joker.sell_cost) or 0)
        zones.bottom = DragZonesUI.make_zone(
            string.format("Sell $%d", sell_value),
            not eternal, eternal and C.GREY or C.MULT, "sell", true)
    elseif ctx.kind == "owned_consumable" then
        local can_use = self:consumable_use_enabled(ctx.index)
        zones.top = DragZonesUI.make_zone("USE", can_use, can_use and C.GREEN or C.GREY, "use", true)
        local c = self.consumables and self.consumables[ctx.index]
        local sell_value = math.floor(self:consumable_sell_value(c))
        zones.bottom = DragZonesUI.make_zone(
            string.format("Sell $%d", sell_value),
            true, C.MULT, "sell", true)
    elseif ctx.kind == "booster_choice" then
        -- Single full-width strip: USE for hand-targeting cards, PICK otherwise.
        local sess = self.booster_session
        local ch = sess and sess.choices and sess.choices[ctx.choice_index]
        local c = ch and ch.consumable_def
        local needs_use = ch and (ch.kind == "tarot" or ch.kind == "spectral")
            and c and (self:booster_tarot_needs_hand(c) or self:booster_spectral_needs_hand(c))
        if needs_use then
            local can_use = ch and not ch.taken and (tonumber(sess.picks_remaining) or 0) > 0
                and c and self:pack_consumable_can_apply(c)
            zones.full = DragZonesUI.make_zone("USE", can_use, can_use and C.GREEN or C.GREY, "use", true)
        else
            local can_pick = ch and not ch.taken and (tonumber(sess.picks_remaining) or 0) > 0
            if can_pick and ch.kind == "joker" then
                can_pick = self:joker_has_room_for_new(ch.edition or "base")
            elseif can_pick and (ch.kind == "planet" or ch.kind == "tarot" or ch.kind == "spectral") then
                can_pick = c and self:pack_consumable_can_apply(c)
            end
            zones.full = DragZonesUI.make_zone("PICK", can_pick, can_pick and C.GREEN or C.GREY, "pick", true)
        end
    end

    return DragZonesUI.attach_rects(zones)
end

function Game:perform_drag_zone_action(ctx, zone_id, zone)
    if not ctx or not zone_id or not zone or not zone.enabled then return false end
    local action = zone.action
    if ctx.kind == "shop_offer" then
        if zone_id == "top" and action == "buy" then
            return self:buy_shop_joker(ctx.slot_index)
        elseif zone_id == "top_right" and action == "buy_use" then
            return self:buy_and_use_shop_consumable(ctx.slot_index)
        end
    elseif ctx.kind == "shop_booster" and zone_id == "top" and action == "buy" then
        return self:buy_shop_booster(ctx.slot_index)
    elseif ctx.kind == "shop_voucher" and zone_id == "top" and action == "buy" then
        return self:buy_shop_voucher(ctx.slot_index)
    elseif ctx.kind == "owned_joker" and zone_id == "bottom" and action == "sell" then
        return self:perform_sell_for_target({ kind = "joker", index = ctx.index, node = ctx.node })
    elseif ctx.kind == "owned_consumable" then
        if zone_id == "top" and action == "use" then
            return self:use_consumable(ctx.index)
        elseif zone_id == "bottom" and action == "sell" then
            return self:perform_sell_for_target({ kind = "consumable", index = ctx.index, node = ctx.node })
        end
    elseif ctx.kind == "booster_choice" then
        if (zone_id == "full" or zone_id == "top") and action == "pick" then
            return self:pick_booster_choice(ctx.choice_index)
        elseif (zone_id == "full" or zone_id == "top_right") and action == "use" then
            return self:use_booster_tarot_choice(ctx.choice_index)
        end
    end
    return false
end

function Game:_snap_layout_after_drag(node)
    if self.STATE == self.STATES.SHOP then
        if self._shop_joker_panel then
            self:layout_shop_offer_nodes(self._shop_joker_panel)
        end
        if self._shop_booster_panel then
            ShopUI.layout_shop_booster_nodes(self, self._shop_booster_panel)
        end
        if self._shop_voucher_panel then
            ShopUI.layout_shop_voucher_nodes(self, self._shop_voucher_panel)
        end
    elseif self.STATE == self.STATES.OPEN_BOOSTER and self._booster_choice_area then
        BoosterPackUI.layout_choice_nodes(self, self._booster_choice_area)
    end
end

--- Clear all bottom-screen selection tooltips (shop offers, boosters, vouchers, owned items).
function Game:clear_bottom_tooltips()
    self.active_tooltip_joker = nil
    self.active_tooltip_card = nil
    self.active_tooltip_consumable_index = nil
    self.active_tooltip_skip_blind_index = nil
    self.active_tooltip_blind_index = nil
    self.active_shop_booster_slot = nil
    self.active_tooltip_shop_voucher_slot = nil
    if self.booster_session then
        self.booster_session.active_choice_index = nil
    end
end

function Game:draw_shop_offer_price_tags()
    ShopUI.draw_shop_offer_price_tags(self)
end

function Game:draw_shop_booster_price_tags()
    ShopUI.draw_shop_booster_price_tags(self)
end

function Game:draw_shop_voucher_price_tags()
    ShopUI.draw_shop_voucher_price_tags(self)
end

function Game:add(node)
    if Joker and node and node.is and node:is(Joker) then
        self:_register_joker_front_atlas_owner(node)
    end
    table.insert(self.nodes, node)
    return node
end

function Game:addPopup(node)
    if Popup and node and node.is and node:is(Popup) then
        table.insert(self.popups, node)
    end
end

function Game:addTag(tag_type, opts)
    local double_count = 0
    if tag_type ~= "double" then
        for i = #self.tags, 1, -1 do
            local tag = self.tags[i]
            if tag and tag.type == "double" then
                double_count = double_count + 1
                table.remove(self.tags, i)
            end
        end
        if double_count > 0 then
            self:updateTagList()
        end
    end

    t = Tag(tag_type)
    if type(opts) == "table" and opts.orbital_hand_index then
        t.orbital_hand_index = opts.orbital_hand_index
    end
    if t.Use and t:Use() then
        if double_count > 0 then
            for _ = 1, double_count do
                self:addTag(tag_type, opts)
            end
        end
        return
    end
    table.insert(self.tags, t)
    self:updateTagList()

    local tag_key = CollectionCatalog.TAG_KEY_FROM_TYPE and CollectionCatalog.TAG_KEY_FROM_TYPE[tag_type]
    if tag_key then
        self:discover_item(tag_key)
    end

    if double_count > 0 then
        for _ = 1, double_count do
            self:addTag(tag_type, opts)
        end
    end
end

function Game:hasTag(tag_type)
    for i, t in ipairs(self.tags) do
        if t and t.type == tag_type then return i end
    end
    return -1
end

function Game:removeTag(i)
    if type(i) ~= "number" then return end
    local t = self.tags[i]
    if t then
        table.remove(self.tags, i)
        self:updateTagList()
    end
end

function Game:updateTagList()
    local width, height = love.graphics.getDimensions()

    for i, t in ipairs(self.tags) do
        if t then
            t:setPosition(width - 28 * i, height - 25)
        end
    end
end

function Game:_is_managed_joker_sprite_key(name)
    return type(name) == "string" and string.sub(name, 1, 6) == "Jokers"
end

function Game:_inc_atlas_owner(name)
    if not self:_is_managed_joker_sprite_key(name) then return end
    if type(self._atlas_owner_counts) ~= "table" then self._atlas_owner_counts = {} end
    self._atlas_owner_counts[name] = (tonumber(self._atlas_owner_counts[name]) or 0) + 1
end

function Game:_dec_atlas_owner(name)
    if not self:_is_managed_joker_sprite_key(name) then return end
    if type(self._atlas_owner_counts) ~= "table" then self._atlas_owner_counts = {} end
    local n = (tonumber(self._atlas_owner_counts[name]) or 0) - 1
    if n > 0 then
        self._atlas_owner_counts[name] = n
        return
    end
    self._atlas_owner_counts[name] = nil

    local entry = self.JOKER_SPRITES and self.JOKER_SPRITES[name]
    if entry and entry.image then
        if entry.image.release then
            pcall(function() entry.image:release() end)
        end
        entry.image = nil
        entry.load_error = nil
    end
end

function Game:_register_joker_front_atlas_owner(joker)
    if not joker or joker._atlas_ref_registered == true then return end
    local name = joker._front_atlas_ref_name
    if type(name) ~= "string" or name == "" then
        name = joker.front_sprite_key
    end
    if type(name) == "string" and name ~= "" then
        self:_inc_atlas_owner(name)
        joker._front_atlas_ref_name = name
    end
    joker._atlas_ref_registered = true
end

function Game:_unregister_joker_front_atlas_owner(joker)
    if not joker or joker._atlas_ref_registered ~= true then return end
    local name = joker._front_atlas_ref_name
    if type(name) == "string" and name ~= "" then
        self:_dec_atlas_owner(name)
    end
    joker._atlas_ref_registered = false
end

function Game:on_joker_front_atlas_resolved(joker, old_name, new_name)
    if not joker then return end
    if type(new_name) ~= "string" or new_name == "" then return end
    joker._front_atlas_ref_name = new_name
    if joker._atlas_ref_registered ~= true then return end
    if type(old_name) == "string" and old_name ~= "" and old_name ~= new_name then
        self:_dec_atlas_owner(old_name)
    end
    if old_name ~= new_name then
        self:_inc_atlas_owner(new_name)
    end
end

function Game:set_state(state_id)
    local prev = self.STATE
    local menu = self.STATES and self.STATES.MENU
    if menu and prev == menu and state_id ~= menu then
        self:unload_animation_atlas("menu")
    end
    self.STATE = state_id
end

function Game:is_hand_scoring_active()
    return self.hand and self.hand.is_scoring_active and self.hand:is_scoring_active() == true
end

function Game:build_unlocks()
    local unlocks = {}
    for _, d in ipairs(DECK_DEFS or {}) do
        local deck_entry = {
            id = d.id,
            name = d.name,
            stakes = {},
            unlocked = d.id == "b_red",
        }
        for _, s in ipairs(STAKE_DEFS or {}) do
            deck_entry.stakes[s.id] = {
                id = s.id,
                name = s.name,
                unlocked = s.id == "stake_white",
                defeated = false,
            }
        end
        unlocks[d.id] = deck_entry
    end
    return unlocks
end

function Game:normalize_unlocks(data)
    local unlocks = self:build_unlocks()
    if type(data) ~= "table" then return unlocks end
    for deck_id, deck_entry in pairs(unlocks) do
        local saved_deck = data[deck_id]
        if type(saved_deck) == "table" then
            if saved_deck.unlocked ~= nil then
                deck_entry.unlocked = saved_deck.unlocked == true
            end
            if type(saved_deck.stakes) == "table" and type(deck_entry.stakes) == "table" then
                for stake_id, stake_entry in pairs(deck_entry.stakes) do
                    local saved_stake = saved_deck.stakes[stake_id]
                    if type(saved_stake) == "table" then
                        if saved_stake.unlocked ~= nil then
                            stake_entry.unlocked = saved_stake.unlocked == true
                        end
                        if saved_stake.defeated ~= nil then
                            stake_entry.defeated = saved_stake.defeated == true
                        end
                    end
                end
            end
        end
    end
    return unlocks
end

function Game:apply_unlocks(unlocks)
    self.unlocks = self:normalize_unlocks(unlocks)
    if self.SETTINGS then
        self.SETTINGS.UNLOCKS = self.unlocks
    end
    for _, d in ipairs(DECK_DEFS or {}) do
        local entry = self.unlocks[d.id]
        if entry then
            d.unlocked = entry.unlocked == true
        end
    end
end

function Game:is_deck_unlocked(deck_id)
    local deck = self.unlocks and self.unlocks[deck_id or ""]
    return deck and deck.unlocked == true
end

function Game:is_stake_unlocked(deck_id, stake_id)
    local deck = self.unlocks and self.unlocks[deck_id or ""]
    local stake = deck and deck.stakes and deck.stakes[stake_id or ""]
    return stake and stake.unlocked == true
end

function Game:is_stake_defeated(deck_id, stake_id)
    local deck = self.unlocks and self.unlocks[deck_id or ""]
    local stake = deck and deck.stakes and deck.stakes[stake_id or ""]
    return stake and stake.defeated == true
end

--- Secret-menu cheat: unlock every deck, stake, and collection discovery.
function Game:unlock_everything()
    if not self.unlocks then
        self:apply_unlocks(self:build_unlocks())
    end
    for _, deck_entry in pairs(self.unlocks) do
        deck_entry.unlocked = true
        if type(deck_entry.stakes) == "table" then
            for _, stake_entry in pairs(deck_entry.stakes) do
                stake_entry.unlocked = true
            end
        end
    end
    self:apply_unlocks(self.unlocks)

    local CollectionCatalog = require("collection_catalog")
    local discovered = self:normalize_discovered(self.Discovered)
    for _, cat in ipairs(CollectionCatalog.CATEGORIES) do
        if cat.id ~= "decks" and cat.id ~= "seals" and cat.id ~= "editions" then
            for _, entry in ipairs(CollectionCatalog.get_entries(cat.id)) do
                local did = CollectionCatalog.discovery_id_for_entry(entry)
                if did then discovered[did] = true end
            end
        end
    end
    self:apply_discovered(discovered)
    self:save_settings()
    return true
end

local DISCOVERY_DECK_THRESHOLDS = {
    b_blue = 20,
    b_yellow = 50,
    b_green = 75,
    b_black = 100,
}

function Game:build_discovered()
    return { j_joker = true }
end

function Game:normalize_discovered(data)
    local out = self:build_discovered()
    if type(data) ~= "table" then return out end
    for id, flag in pairs(data) do
        if type(id) == "string" and flag == true then
            out[id] = true
        end
    end
    return out
end

function Game:is_collection_discovery_id(id)
    if type(id) ~= "string" or id == "" then return false end
    if VOUCHER_DEFS and VOUCHER_DEFS[id] then return true end
    if self.P_TAGS and self.P_TAGS[id] then return true end
    if self.P_BLINDS and self.P_BLINDS[id] then return true end
    if id:sub(1, 12) == "enhancement_" then return true end
    if id:sub(1, 5) == "seal_" then return true end
    if id:sub(1, 8) == "edition_" then return true end
    if id:sub(1, 8) == "booster_" then return true end
    return false
end

function Game:is_trackable_discovery_id(id)
    if type(id) ~= "string" or id == "" then return false end
    if JOKER_DEFS and JOKER_DEFS[id] then return true end
    local def = CONSUMABLE_DEFS and CONSUMABLE_DEFS[id]
    if def then
        local kind = def.kind
        if kind == "tarot" or kind == "planet" or kind == "spectral" then
            return true
        end
    end
    return self:is_collection_discovery_id(id)
end

function Game:get_collection_progress(category_id)
    return CollectionCatalog.get_progress(self, category_id)
end

--- Discover enhancement, seal, or edition on a playing card.
---@param card_data table|nil
function Game:discover_card_properties(card_data)
    if type(card_data) ~= "table" then return end
    local enh = card_data.enhancement
    if type(enh) == "string" and enh ~= "" and enh ~= "none" then
        self:discover_item("enhancement_" .. enh)
    end
    local seal = card_data.seal
    if type(seal) == "string" and seal ~= "" then
        self:discover_item("seal_" .. seal)
    end
    local edition = card_data.edition
    if type(edition) == "string" and edition ~= "" then
        self:discover_item("edition_" .. edition)
    end
end

function Game:apply_discovered(discovered)
    self.Discovered = self:normalize_discovered(discovered)
    if self.SETTINGS then
        self.SETTINGS.DISCOVERED = self.Discovered
    end
    self:refresh_discovery_deck_unlocks()
end

function Game:count_discoveries()
    local n = 0
    for id, flag in pairs(self.Discovered or {}) do
        if flag == true and self:is_trackable_discovery_id(id) then
            n = n + 1
        end
    end
    return n
end

function Game:is_discovered(id)
    return type(id) == "string" and self.Discovered and self.Discovered[id] == true
end

function Game:refresh_discovery_deck_unlocks()
    if not self.unlocks then self:apply_unlocks(self:build_unlocks()) end
    local count = self:count_discoveries()
    for deck_id, required in pairs(DISCOVERY_DECK_THRESHOLDS) do
        if count >= required then
            local deck = self.unlocks[deck_id]
            if deck then deck.unlocked = true end
        end
    end
    for _, d in ipairs(DECK_DEFS or {}) do
        local entry = self.unlocks[d.id]
        if entry then
            d.unlocked = entry.unlocked == true
        end
    end
    if self.SETTINGS then
        self.SETTINGS.UNLOCKS = self.unlocks
    end
end

--- Record first-time discovery of a Joker, Tarot, Planet, or Spectral card.
---@return boolean true when newly discovered
function Game:discover_item(id)
    if not self:is_trackable_discovery_id(id) then return false end
    if not self.Discovered then self.Discovered = {} end
    if self.Discovered[id] == true then return false end

    self.Discovered[id] = true
    if self.SETTINGS then
        self.SETTINGS.DISCOVERED = self.Discovered
    end
    self:refresh_discovery_deck_unlocks()
    self:save_settings()
    return true
end

function Game:record_stake_victory()
    local deck_id = self.selected_deck_id or self._pending_deck_id
    local stake_id = self.selected_stake_id or self._pending_stake_id
    if type(deck_id) ~= "string" or type(stake_id) ~= "string" then return false end
    if not self.unlocks then self:apply_unlocks(self:build_unlocks()) end

    local deck = self.unlocks[deck_id]
    local stake = deck and deck.stakes and deck.stakes[stake_id]
    if not stake then return false end
    if stake.defeated == true then return true end

    stake.defeated = true
    local unlock_next = false
    for _, s in ipairs(STAKE_DEFS or {}) do
        if unlock_next then
            local next_stake = deck.stakes[s.id]
            if next_stake then next_stake.unlocked = true end
            break
        end
        if s.id == stake_id then unlock_next = true end
    end

    -- Deck Unlocks
    if deck.id == "b_red" then
        self.unlocks["b_magic"].unlocked = true
    elseif deck.id == "b_blue" then
        self.unlocks["b_nebula"].unlocked = true
    elseif deck.id == "b_yellow" then
        self.unlocks["b_ghost"].unlocked = true
    elseif deck.id == "b_green" then
        self.unlocks["b_abandoned"].unlocked = true
    elseif deck.id == "b_black" then
        self.unlocks["b_checkered"].unlocked = true
    end
    if stake.id == "stake_red" then
        self.unlocks["b_zodiac"].unlocked = true
    elseif stake.id == "stake_green" then
        self.unlocks["b_painted"].unlocked = true
    elseif stake.id == "stake_black" then
        self.unlocks["b_anaglyph"].unlocked = true
    elseif stake.id == "stake_blue" then
        self.unlocks["b_plasma"].unlocked = true
    elseif stake.id == "stake_orange" then
        self.unlocks["b_erratic"].unlocked = true
    end

    self:apply_unlocks(self.unlocks)
    self:save_settings()
    return true
end

function Game:build_joker_wins()
    return {}
end

function Game:normalize_joker_wins(data)
    local out = {}
    if type(data) ~= "table" then return out end
    for joker_id, entry in pairs(data) do
        if type(joker_id) == "string" and joker_id ~= "" and type(entry) == "table" then
            local normalized = {
                id = joker_id,
                name = entry.name,
                highest_stake_id = type(entry.highest_stake_id) == "string" and entry.highest_stake_id or nil,
                highest_stake_level = math.max(0, math.floor(tonumber(entry.highest_stake_level) or 0)),
            }
            if type(entry.win_snapshot) == "table" then
                normalized.win_snapshot = copy_table(entry.win_snapshot)
            end
            out[joker_id] = normalized
        end
    end
    return out
end

function Game:apply_joker_wins(data)
    self.joker_wins = self:normalize_joker_wins(data)
    if self.SETTINGS then
        self.SETTINGS.JOKER_WINS = self.joker_wins
    end
end

function Game:get_stake_order(stake_id)
    local def = STAKE_DEFS_BY_ID and STAKE_DEFS_BY_ID[stake_id or ""]
    return math.max(1, math.floor(tonumber(def and def.order) or 1))
end

function Game:snapshot_joker_for_victory(joker)
    local def = joker and joker.def
    local jid = def and def.id
    if type(jid) ~= "string" or jid == "" then return nil end
    local edition = joker.edition
    if Joker and Joker.normalize_edition then
        edition = Joker.normalize_edition(edition)
    end
    return {
        id = jid,
        name = def.name or joker.name,
        edition = edition,
        eternal = joker.eternal == true,
        rental = joker.rental == true,
        perishable = joker.perishable == true,
        stored_mult = tonumber(joker.stored_mult),
        stored_chips = tonumber(joker.stored_chips),
        stored_xmult = tonumber(joker.stored_xmult),
        runtime_counter = tonumber(joker.runtime_counter),
        sell_cost = tonumber(joker.sell_cost),
    }
end

--- Persist owned jokers from a winning run; keeps the highest stake won per joker id.
function Game:record_joker_wins_at_victory()
    local stake_id = self.selected_stake_id or self._pending_stake_id
    if type(stake_id) ~= "string" or stake_id == "" then return false end
    if not self.joker_wins then self:apply_joker_wins(self:build_joker_wins()) end

    local stake_order = self:get_stake_order(stake_id)
    local changed = false
    for _, joker in ipairs(self.jokers or {}) do
        local snap = self:snapshot_joker_for_victory(joker)
        if snap then
            local jid = snap.id
            local entry = self.joker_wins[jid] or {}
            local prev_level = tonumber(entry.highest_stake_level) or 0
            if stake_order >= prev_level then
                if stake_order > prev_level then
                    entry.highest_stake_id = stake_id
                    entry.highest_stake_level = stake_order
                end
                entry.id = jid
                entry.name = snap.name
                entry.win_snapshot = snap
                self.joker_wins[jid] = entry
                changed = true
            end
        end
    end

    if changed then
        self.SETTINGS.JOKER_WINS = self.joker_wins
        self:save_settings()
    end
    return changed
end

function Game:can_pause_now()
    local s = self.STATE
    if s == self.STATES.MENU or s == self.STATES.GAME_OVER or s == self.STATES.YOU_WIN then return false end
    if s == self.STATES.PAUSED then return true end
    return s == self.STATES.BLIND_SELECT
        or s == self.STATES.SELECTING_HAND
        or s == self.STATES.SHOP
        or s == self.STATES.ROUND_EVAL
end

function Game:enter_pause_menu()
    if not self:can_pause_now() then return false end
    if self._deck_view_open then
        self:exit_deck_view()
    end
    if self.STATE ~= self.STATES.PAUSED then
        self._pause_prev_state = self.STATE
    end
    self.dragging = nil
    self._pause_save_error = nil
    self._pause_continue_rect = nil
    self._pause_new_run_rect = nil
    self._pause_save_quit_rect = nil
    self._pause_settings_rect = nil
    self._pause_show_settings = false
    self._pause_speed_rects = {}
    self._pause_music_slider_rect = nil
    self._pause_music_slider_drag = false
    self._pause_focus_index = 1
    self:set_state(self.STATES.PAUSED)
    return true
end

function Game:build_pause_focus_targets()
    local targets = {}
    if self._pause_show_settings then
        for i, r in ipairs(self._pause_speed_rects or {}) do
            if r then targets[#targets + 1] = { kind = "speed", index = i, rect = r } end
        end
        if self._pause_back_rect then
            targets[#targets + 1] = { kind = "back", rect = self._pause_back_rect }
        end
        return targets
    end
    if self._pause_continue_rect then
        targets[#targets + 1] = { kind = "continue", rect = self._pause_continue_rect }
    end
    if self._pause_settings_rect then
        targets[#targets + 1] = { kind = "settings", rect = self._pause_settings_rect }
    end
    if self._pause_new_run_rect then
        targets[#targets + 1] = { kind = "new_run", rect = self._pause_new_run_rect }
    end
    if self._pause_save_quit_rect then
        targets[#targets + 1] = { kind = "save_quit", rect = self._pause_save_quit_rect }
    end
    return targets
end

function Game:pause_gamepad_move(delta)
    local targets = self:build_pause_focus_targets()
    if #targets == 0 then return nil end
    delta = math.floor(tonumber(delta) or 0)
    local idx = tonumber(self._pause_focus_index) or 1
    idx = idx + delta
    if idx < 1 then idx = #targets elseif idx > #targets then idx = 1 end
    self._pause_focus_index = idx
    return targets[idx]
end

function Game:activate_pause_focus()
    local targets = self:build_pause_focus_targets()
    local idx = tonumber(self._pause_focus_index) or 1
    idx = math.max(1, math.min(#targets, idx))
    local t = targets[idx]
    if not t then return false end
    if t.kind == "continue" then
        return self:exit_pause_menu()
    elseif t.kind == "settings" then
        self._pause_show_settings = true
        self._pause_focus_index = 1
        return true
    elseif t.kind == "new_run" then
        if self.enter_main_menu_deck_select then self:enter_main_menu_deck_select() end
        return true
    elseif t.kind == "save_quit" then
        if self.pause_save_and_quit then self:pause_save_and_quit() end
        return true
    elseif t.kind == "back" then
        self._pause_show_settings = false
        self._pause_focus_index = 2
        return true
    elseif t.kind == "speed" and t.rect and t.rect.speed then
        if self.set_game_speed then self:set_game_speed(t.rect.speed) end
        if self.save_settings then self:save_settings() end
        return true
    end
    return false
end

function Game:handle_gamepad_pause(button)
    if self.STATE ~= self.STATES.PAUSED then return false end
    if button == "up" or button == "dpup" then
        self:pause_gamepad_move(-1)
        return true
    end
    if button == "down" or button == "dpdown" then
        self:pause_gamepad_move(1)
        return true
    end
    if (button == "left" or button == "dpleft") and self._pause_show_settings then
        self:pause_gamepad_move(-1)
        return true
    end
    if (button == "right" or button == "dpright") and self._pause_show_settings then
        self:pause_gamepad_move(1)
        return true
    end
    if button == "b" and self._pause_show_settings then
        self._pause_show_settings = false
        self._pause_focus_index = 2
        return true
    end
    if button == "a" or button == "y" then
        return self:activate_pause_focus()
    end
    return false
end

function Game:exit_pause_menu()
    if self.STATE ~= self.STATES.PAUSED then return false end
    if self._pause_music_slider_drag then
        self:save_settings()
    end
    local resume = self._pause_prev_state or self.STATES.SELECTING_HAND
    self._pause_continue_rect = nil
    self._pause_new_run_rect = nil
    self._pause_save_quit_rect = nil
    self._pause_save_error = nil
    self._pause_prev_state = nil
    self._pause_settings_rect = nil
    self._pause_show_settings = false
    self._pause_speed_rects = {}
    self._pause_music_slider_rect = nil
    self._pause_music_slider_drag = false
    self:set_state(resume)
    return true
end

function Game:get_profile_count()
    return PROFILE_COUNT
end

function Game:get_profile_id()
    local id = math.floor(tonumber(self._profile_id) or 1)
    if id < 1 then id = 1 end
    if id > PROFILE_COUNT then id = PROFILE_COUNT end
    return id
end

function Game:settings_path_for_profile(profile_id)
    local id = math.floor(tonumber(profile_id) or 1)
    if id <= 1 then return SETTINGS_SAVE_PATH_P1 end
    return string.format("sdmc/Balatro3DS_settings_%d.lua", id)
end

function Game:run_save_path_for_profile(profile_id)
    local id = math.floor(tonumber(profile_id) or 1)
    if id <= 1 then return RUN_SAVE_PATH_P1 end
    return string.format("sdmc/Balatro3DS_run_save_%d.lua", id)
end

function Game:settings_save_path()
    return self:settings_path_for_profile(self:get_profile_id())
end

function Game:run_save_path()
    return self:run_save_path_for_profile(self:get_profile_id())
end

function Game:load_active_profile()
    self._profile_id = 1
    if not (love and love.filesystem and love.filesystem.load and love.filesystem.getInfo) then
        return false
    end
    if not love.filesystem.getInfo(ACTIVE_PROFILE_PATH, "file") then
        return false
    end
    local chunk = love.filesystem.load(ACTIVE_PROFILE_PATH)
    if not chunk then return false end
    local ok, data = pcall(chunk)
    if not ok or type(data) ~= "table" then return false end
    local id = math.floor(tonumber(data.profile) or 1)
    if id < 1 then id = 1 end
    if id > PROFILE_COUNT then id = PROFILE_COUNT end
    self._profile_id = id
    return true
end

function Game:save_active_profile()
    if not (love and love.filesystem and love.filesystem.write and love.filesystem.createDirectory) then
        return false
    end
    love.filesystem.createDirectory(RUN_SAVE_DIR)
    local encoded = "return " .. serialize_lua_value({ profile = self:get_profile_id() })
    local ok = love.filesystem.write(ACTIVE_PROFILE_PATH, encoded)
    return ok and true or false
end

--- Switch to another profile slot (1–3). Persists current settings first, then loads the target.
function Game:switch_profile(profile_id)
    local id = math.floor(tonumber(profile_id) or 1)
    if id < 1 then id = 1 end
    if id > PROFILE_COUNT then id = PROFILE_COUNT end
    if id == self:get_profile_id() then
        self._delete_save_confirm = false
        return true
    end
    self:save_settings()
    self._profile_id = id
    self._delete_save_confirm = false
    self:save_active_profile()
    self:load_settings()
    return true
end

--- Wipe unlocks, discoveries, and wins for the active profile, and clear its run save.
function Game:delete_profile_progress()
    self.unlocks = self:build_unlocks()
    self.Discovered = self:build_discovered()
    self.joker_wins = self:build_joker_wins()
    if self.SETTINGS then
        self.SETTINGS.UNLOCKS = self.unlocks
        self.SETTINGS.DISCOVERED = self.Discovered
        self.SETTINGS.JOKER_WINS = self.joker_wins
    end
    self:apply_unlocks(self.unlocks)
    self:apply_discovered(self.Discovered)
    self:apply_joker_wins(self.joker_wins)
    self:clear_run_snapshot()
    self:save_settings()
    self._delete_save_confirm = false
    return true
end

function Game:default_settings()
    return {
        GAMESPEED = 1,
        SOUND = { music_volume = 100 },
        GRAPHICS = { texture_scaling = 1 },
        UNLOCKS = self:build_unlocks(),
        DISCOVERED = self:build_discovered(),
        JOKER_WINS = self:build_joker_wins(),
    }
end

function Game:normalize_settings(data)
    local out = copy_table(self:default_settings())
    if type(data) ~= "table" then return out end

    local allowed_speeds = { [0.5] = true, [1] = true, [1.5] = true, [2] = true, [2.5] = true, [3] = true }
    local speed = tonumber(data.GAMESPEED)
    if speed and allowed_speeds[speed] then
        out.GAMESPEED = speed
    end

    if type(data.SOUND) == "table" then
        local mv = tonumber(data.SOUND.music_volume)
        if mv ~= nil then
            out.SOUND.music_volume = math.max(0, math.min(100, math.floor(mv)))
        end
    end

    if type(data.GRAPHICS) == "table" then
        local ts = tonumber(data.GRAPHICS.texture_scaling)
        if ts == 1 or ts == 2 then
            out.GRAPHICS.texture_scaling = ts
        end
    end

    out.UNLOCKS = self:normalize_unlocks(data.UNLOCKS)
    out.DISCOVERED = self:normalize_discovered(data.DISCOVERED)
    out.JOKER_WINS = self:normalize_joker_wins(data.JOKER_WINS)

    return out
end

function Game:snapshot_settings()
    return {
        GAMESPEED = tonumber(self.SETTINGS and self.SETTINGS.GAMESPEED) or 1,
        SOUND = { music_volume = self:get_music_volume() },
        GRAPHICS = {
            texture_scaling = tonumber(self.SETTINGS and self.SETTINGS.GRAPHICS and self.SETTINGS.GRAPHICS.texture_scaling) or 1,
        },
        UNLOCKS = self:normalize_unlocks(self.unlocks or (self.SETTINGS and self.SETTINGS.UNLOCKS)),
        DISCOVERED = self:normalize_discovered(self.Discovered or (self.SETTINGS and self.SETTINGS.DISCOVERED)),
        JOKER_WINS = self:normalize_joker_wins(self.joker_wins or (self.SETTINGS and self.SETTINGS.JOKER_WINS)),
    }
end

function Game:load_settings()
    self.SETTINGS = copy_table(self:default_settings())
    local function finish_load()
        self:apply_unlocks(self.SETTINGS.UNLOCKS)
        self:apply_discovered(self.SETTINGS.DISCOVERED)
        self:apply_joker_wins(self.SETTINGS.JOKER_WINS)
        if self.apply_music_volume then
            self:apply_music_volume()
        end
    end
    if not (love and love.filesystem and love.filesystem.load and love.filesystem.getInfo) then
        finish_load()
        return false
    end
    if not love.filesystem.getInfo(self:settings_save_path(), "file") then
        finish_load()
        return false
    end
    local chunk, err = love.filesystem.load(self:settings_save_path())
    if not chunk then
        finish_load()
        return false, tostring(err or "load_failed")
    end
    local ok, data = pcall(chunk)
    if not ok or type(data) ~= "table" then
        finish_load()
        return false, "decode_failed"
    end
    self.SETTINGS = self:normalize_settings(data)
    finish_load()
    return true
end

function Game:save_settings()
    if not (love and love.filesystem and love.filesystem.write and love.filesystem.createDirectory) then
        return false
    end
    love.filesystem.createDirectory(RUN_SAVE_DIR)
    local encoded = "return " .. serialize_lua_value(self:snapshot_settings())
    local ok, err = love.filesystem.write(self:settings_save_path(), encoded)
    if not ok then
        return false, tostring(err or "write_failed")
    end
    return true
end

function Game:set_game_speed(speed)
    if not self.SETTINGS then return end
    local allowed_speeds = { [0.5] = true, [1] = true, [1.5] = true, [2] = true, [2.5] = true, [3] = true }
    local s = tonumber(speed)
    if not s or not allowed_speeds[s] then return end
    self.SETTINGS.GAMESPEED = s
    self:save_settings()
end

function Game:get_music_volume()
    local sound = self.SETTINGS and self.SETTINGS.SOUND
    return math.max(0, math.min(100, math.floor(tonumber(sound and sound.music_volume) or 100)))
end

---@param pct number volume 0–100
---@param opts table|nil `{ skip_save = true }` to avoid SD writes while dragging the slider
function Game:set_music_volume(pct, opts)
    if not self.SETTINGS then return end
    if type(self.SETTINGS.SOUND) ~= "table" then self.SETTINGS.SOUND = {} end
    self.SETTINGS.SOUND.music_volume = math.max(0, math.min(100, math.floor(tonumber(pct) or 0)))
    self:apply_music_volume()
    -- Writing settings on every drag frame freezes/stutters on 3DS SD I/O.
    if not (opts and opts.skip_save) then
        self:save_settings()
    end
end

function Game:apply_music_volume()
    if not self.music then return end
    local vol = self:get_music_volume() / 100
    -- Mute with volume only. Source:pause/stop can freeze streaming audio on LovePotion/3DS.
    pcall(function()
        self.music:setVolume(vol)
    end)
    local playing = false
    pcall(function()
        playing = self.music:isPlaying() == true
    end)
    if not playing then
        pcall(function()
            self.music:play()
        end)
    end
end

function Game:_music_volume_from_slider_x(x)
    local r = self._pause_music_slider_rect
    if type(r) ~= "table" then return nil end
    local t = (tonumber(x) - r.track_x) / r.track_w
    t = math.max(0, math.min(1, t))
    return math.floor(t * 100 + 0.5)
end

function Game:toggle_pause()
    if self.STATE == self.STATES.PAUSED then
        return self:exit_pause_menu()
    end
    return self:enter_pause_menu()
end

function Game:can_open_deck_view()
    if self._deck_view_open then return true end
    if self.STATE == self.STATES.MENU or self.STATE == self.STATES.GAME_OVER or self.STATE == self.STATES.YOU_WIN then return false end
    if self.STATE == self.STATES.PAUSED then return false end
    return self.STATE == self.STATES.BLIND_SELECT
        or self.STATE == self.STATES.SELECTING_HAND
        or self.STATE == self.STATES.SHOP
        or self.STATE == self.STATES.ROUND_EVAL
        or self.STATE == self.STATES.OPEN_BOOSTER
        or self.STATE == self.STATES.HAND_PLAYED
        or self.STATE == self.STATES.DRAW_TO_HAND
        or self.STATE == self.STATES.NEW_ROUND
end

function Game:enter_deck_view()
    if self._deck_view_open or not self:can_open_deck_view() then return false end
    self.dragging = nil
    self.active_tooltip_card = nil
    self._deck_view_open = true
    DeckViewUI.build(self)
    return true
end

function Game:exit_deck_view()
    if not self._deck_view_open then return false end
    self.dragging = nil
    self.active_tooltip_card = nil
    DeckViewUI.destroy(self)
    self._deck_view_open = false
    return true
end

function Game:toggle_deck_view()
    if self._deck_view_open then
        return self:exit_deck_view()
    end
    return self:enter_deck_view()
end

function Game:current_resume_state()
    local s = self.STATE
    if s == self.STATES.PAUSED then
        s = self._pause_prev_state or self.STATES.SELECTING_HAND
    end
    if s == self.STATES.MENU or s == self.STATES.GAME_OVER then
        return self.STATES.BLIND_SELECT
    end
    -- YOU_WIN is a valid resume state (post Ante-8 win screen).
    return s
end

function Game:has_saved_run()
    local path = self:run_save_path()
    return love and love.filesystem and love.filesystem.getInfo and love.filesystem.getInfo(path, "file") ~= nil
end

function Game:clear_run_snapshot()
    if not (love and love.filesystem and love.filesystem.remove) then return false end
    if not self:has_saved_run() then return true end
    return love.filesystem.remove(self:run_save_path()) and true or false
end

function Game:build_run_snapshot()
    local jokers = {}
    for _, j in ipairs(self.jokers or {}) do
        local def = j and j.def
        local jid = def and def.id
        if type(jid) == "string" then
            jokers[#jokers + 1] = {
                id = jid,
                edition = j.edition,
                stored_mult = tonumber(j.stored_mult) or 0,
                stored_chips = tonumber(j.stored_chips) or 0,
                stored_xmult = tonumber(j.stored_xmult) or 1,
                runtime_counter = tonumber(j.runtime_counter) or 0,
                sell_cost = tonumber(j.sell_cost) or 0,
                loyalty_remaining = j.loyalty_remaining,
                free_joker_slots = j.free_joker_slots,
                perishable = j.perishable,
                perishable_counter = tonumber(j.perishable_counter) or 5,
                eternal = j.eternal,
                rental = j.rental,
                random_suit = j.random_suit,
                random_rank = j.random_rank,
                random_hand = j.random_hand,
            }
        end
    end
    local hand_cards = {}
    if self.hand and type(self.hand.cards) == "table" then
        hand_cards = table_array_deep_copy(self.hand.cards)
    end
    local hand_draw_queue = {}
    local hand_sort_mode = nil
    if self.hand then
        hand_sort_mode = self.hand.sort_mode
        if type(self.hand._draw_queue) == "table" then
            hand_draw_queue = table_array_deep_copy(self.hand._draw_queue)
        end
    end
    local selected_uids = {}
    if self.hand and type(self.hand.selected) == "table" then
        for _, node in ipairs(self.hand.selected) do
            local uid = node and node.card_data and node.card_data.uid
            if uid ~= nil then
                selected_uids[#selected_uids + 1] = uid
            end
        end
    end
    local tag_types = {}
    for _, tag in ipairs(self.tags or {}) do
        if tag and type(tag.type) == "string" then
            tag_types[#tag_types + 1] = tag.type
        end
    end
    return {
        version = 1,
        seed = tonumber(self.SEED) or os.time(),
        resume_state = self:current_resume_state(),
        stage = self.STAGES.RUN,
        ante = tonumber(self.ante) or 1,
        round = tonumber(self.round) or 1,
        money = tonumber(self.money) or 0,
        hands = tonumber(self.hands) or 0,
        discards = tonumber(self.discards) or 0,
        round_score = tonumber(self.round_score) or 0,
        last_hand_score = tonumber(self.last_hand_score) or 0,
        selectedHand = tonumber(self.selectedHand) or -1,
        selectedHandHidden = self.selectedHandHidden == true,
        selectedHandLevel = tonumber(self.selectedHandLevel) or 1,
        selectedHandChips = tonumber(self.selectedHandChips) or 0,
        selectedHandMult = tonumber(self.selectedHandMult) or 0,
        _next_card_uid = tonumber(self._next_card_uid) or 1,
        current_blind_index = tonumber(self.current_blind_index) or 1,
        selected_blind_index = tonumber(self.selected_blind_index) or 1,
        current_blind_target = tonumber(self.current_blind_target) or 0,
        current_blind_reward = tonumber(self.current_blind_reward) or 0,
        current_blind_name = tostring(self.current_blind_name or "Small Blind"),
        current_boss_blind_id = self.current_boss_blind_id,
        bosses_used_this_cycle = self:serialize_bosses_used_cycle(),
        _last_completed_blind_was_boss = self._last_completed_blind_was_boss == true,
        hand_size_delta_spectral = tonumber(self.hand_size_delta_spectral) or 0,
        last_consumable_use_id = self.last_consumable_use_id,
        hand_play_counts = copy_table(self.hand_play_counts or {}),
        blind_hand_play_counts = copy_table(self.blind_hand_play_counts or {}),
        _ante_played_card_uids = copy_table(self._ante_played_card_uids or {}),
        boss_runtime = copy_table(self.boss_runtime or {}),
        jokers_on_bottom = self.jokers_on_bottom == true,
        jokers = jokers,
        joker_shared_picks = copy_table(self.joker_shared_picks or {}),
        consumables = copy_table(self.consumables or {}),
        consumable_base_capacity = tonumber(self.consumable_base_capacity) or 2,
        deck_cards = table_array_deep_copy(self.deck and self.deck.cards or {}),
        deck_discard_pile = table_array_deep_copy(self.deck and self.deck.discard_pile or {}),
        hand_cards = hand_cards,
        hand_draw_queue = hand_draw_queue,
        hand_sort_mode = hand_sort_mode,
        hand_selected_uids = selected_uids,
        tags = tag_types,
        shop_offer_queue = copy_table(self.shop_offer_queue or {}),
        _shop_rng_state = tonumber(self._shop_rng_state) or 0,
        shop_reroll_count = tonumber(self.shop_reroll_count) or 0,
        shop_offers = copy_table(self.shop_offers or {}),
        shop_booster_offers = copy_table(self.shop_booster_offers or {}),
        shop_offer_slots = tonumber(self.shop_offer_slots) or 2,
        shop_booster_slots = tonumber(self.shop_booster_slots) or 2,
        active_shop_booster_slot = self.active_shop_booster_slot,
        tarots_used = tonumber(self.tarots_used) or 0,
        vouchers = copy_table(self.vouchers or {}),
        shop_voucher_offers = copy_table(self.shop_voucher_offers or {}),
        shop_voucher_bought_pending_boss = self.shop_voucher_bought_pending_boss == true,
        hand_size_delta_voucher = tonumber(self.hand_size_delta_voucher) or 0,
        hand_size_delta_juggle = tonumber(self.hand_size_delta_juggle) or 0,
        _shop_reroll_base_cost_override = tonumber(self._shop_reroll_base_cost_override) or nil,
        voucher_hands_delta = tonumber(self.voucher_hands_delta) or 0,
        boss_rerolls_used_this_ante = tonumber(self.boss_rerolls_used_this_ante) or 0,
        hand_stats = copy_table(self.hand_stats or {}),
        joker_pool_replacements = copy_table(self.joker_pool_replacements or {}),
        gros_michel_extinct = self:is_joker_pool_swap_active("j_gros_michel", "j_cavendish"),
        skips = self.skips,
        skip_tag_orbital_hand = copy_table(self.skip_tag_orbital_hand or {}),
        handsPlayed = self.handsPlayed,
        discardsUnused = self.discardsUnused,
        skipsTaken = self.skipsTaken,
        ectoplasm_used = self.ectoplasm_used,
        run_best_hand_score = tonumber(self.run_best_hand_score) or 0,
        run_cards_played = tonumber(self.run_cards_played) or 0,
        run_cards_discarded = tonumber(self.run_cards_discarded) or 0,
        run_cards_purchased = tonumber(self.run_cards_purchased) or 0,
        run_times_rerolled = tonumber(self.run_times_rerolled) or 0,
        _endless_mode = self._endless_mode == true,
    }
end

function Game:write_run_snapshot(snapshot)
    if type(snapshot) ~= "table" then return false, "invalid_snapshot" end
    if not (love and love.filesystem and love.filesystem.write and love.filesystem.createDirectory) then
        return false, "filesystem_unavailable"
    end
    love.filesystem.createDirectory(RUN_SAVE_DIR)
    local encoded = "return " .. serialize_lua_value(snapshot)
    local ok, err = love.filesystem.write(self:run_save_path(), encoded)
    if not ok then
        return false, tostring(err or "write_failed")
    end
    return true
end

function Game:read_run_snapshot()
    if not self:has_saved_run() then return nil, "missing" end
    if not (love and love.filesystem and love.filesystem.load) then
        return nil, "filesystem_unavailable"
    end
    local chunk, err = love.filesystem.load(self:run_save_path())
    if not chunk then return nil, tostring(err or "load_failed") end
    local ok, data = pcall(chunk)
    if not ok or type(data) ~= "table" then
        return nil, "decode_failed"
    end
    return data, nil
end

function Game:load_run_snapshot(snapshot)
    if type(snapshot) ~= "table" then return false, "invalid_snapshot" end
    local seed = tonumber(snapshot.seed)
    if seed == nil then return false, "missing_seed" end

    self.SEED = seed
    math.randomseed(self.SEED)
    self.STAGE = self.STAGES.RUN

    if type(self.jokers) == "table" then
        for i = #self.jokers, 1, -1 do
            self:remove_owned_joker_at(i,true)
        end
    end
    if type(self.consumables) == "table" then
        for i = #self.consumables, 1, -1 do
            self:remove_consumable_at(i)
        end
    end
    for _, n in ipairs(self.shop_offer_nodes or {}) do
        if n then self:remove(n) end
    end
    self.shop_offer_nodes = {}
    if self.hand and self.hand.clear then
        self.hand:clear()
    end
    self.pending_discard = {}
    self.dragging = nil
    self.active_tooltip_card = nil
    self.active_tooltip_joker = nil
    self.active_tooltip_consumable_index = nil
    self.active_tooltip_shop_voucher_slot = nil

    if not self.deck and Deck then
        self.deck = Deck()
    end
    if self.deck then
        self.deck.cards = table_array_deep_copy(snapshot.deck_cards or {})
        self.deck.discard_pile = table_array_deep_copy(snapshot.deck_discard_pile or {})
    end
    if not self.hand and Hand then
        self.hand = Hand(self)
    end
    if self.hand then
        self.hand:clear()
        local saved_sort_mode = snapshot.hand_sort_mode
        self.hand.sort_mode = false
        for _, card_data in ipairs(snapshot.hand_cards or {}) do
            self.hand:add_card(copy_table(card_data), true)
        end
        self.hand._draw_queue = table_array_deep_copy(snapshot.hand_draw_queue or {})
        self.hand.sort_mode = saved_sort_mode or "rank"
        if self.hand.layout then
            self.hand:layout(true)
        end
    end

    self.ante = tonumber(snapshot.ante) or 1
    self.round = tonumber(snapshot.round) or 1
    self.money = tonumber(snapshot.money) or 0
    self.hands = tonumber(snapshot.hands) or self:get_effective_hands_per_round()
    self.discards = tonumber(snapshot.discards) or self:get_effective_discards_per_round()
    self.round_score = tonumber(snapshot.round_score) or 0
    self.last_hand_score = tonumber(snapshot.last_hand_score) or 0
    self.selectedHand = tonumber(snapshot.selectedHand) or -1
    self.selectedHandHidden = snapshot.selectedHandHidden == true
    self.selectedHandLevel = tonumber(snapshot.selectedHandLevel) or 1
    self.selectedHandChips = tonumber(snapshot.selectedHandChips) or 0
    self.selectedHandMult = tonumber(snapshot.selectedHandMult) or 0
    self._next_card_uid = tonumber(snapshot._next_card_uid) or 1
    self.current_blind_index = tonumber(snapshot.current_blind_index) or 1
    self.selected_blind_index = tonumber(snapshot.selected_blind_index) or self.current_blind_index
    self.current_blind_target = tonumber(snapshot.current_blind_target) or 0
    self.current_blind_reward = tonumber(snapshot.current_blind_reward) or 0
    self.current_blind_name = snapshot.current_blind_name or "Small Blind"
    self.current_boss_blind_id = snapshot.current_boss_blind_id
    self:apply_bosses_used_cycle(snapshot.bosses_used_this_cycle)
    self._last_completed_blind_was_boss = snapshot._last_completed_blind_was_boss == true
    self.hand_size_delta_spectral = tonumber(snapshot.hand_size_delta_spectral) or 0
    self.last_consumable_use_id = snapshot.last_consumable_use_id
    self.hand_play_counts = copy_table(snapshot.hand_play_counts or {})
    self.blind_hand_play_counts = copy_table(snapshot.blind_hand_play_counts or {})
    self._ante_played_card_uids = copy_table(snapshot._ante_played_card_uids or {})
    self.boss_runtime = copy_table(snapshot.boss_runtime or {})
    self.jokers_on_bottom = snapshot.jokers_on_bottom == true
    self.tags = {}
    for _, tag_type in ipairs(snapshot.tags or {}) do
        if type(tag_type) == "string" and tag_type ~= "" then
            self:addTag(tag_type)
        end
    end
    self.shop_offer_queue = copy_table(snapshot.shop_offer_queue or {})
    self._shop_rng_state = tonumber(snapshot._shop_rng_state) or self._shop_rng_state
    self.shop_reroll_count = tonumber(snapshot.shop_reroll_count) or 0
    self.shop_offers = copy_table(snapshot.shop_offers or {})
    self.shop_booster_offers = copy_table(snapshot.shop_booster_offers or {})
    self.shop_offer_slots = tonumber(snapshot.shop_offer_slots) or self.shop_offer_slots or 2
    self.shop_booster_slots = tonumber(snapshot.shop_booster_slots) or self.shop_booster_slots or 2
    self.active_shop_booster_slot = snapshot.active_shop_booster_slot
    self.consumable_base_capacity = tonumber(snapshot.consumable_base_capacity) or 2
    self.tarots_used = tonumber(snapshot.tarots_used) or 0
    self.vouchers = copy_table(snapshot.vouchers or {})
    if type(snapshot.shop_voucher_offers) == "table" then
        self.shop_voucher_offers = copy_table(snapshot.shop_voucher_offers)
    elseif type(snapshot.shop_voucher_offer) == "table" then
        self.shop_voucher_offers = { copy_table(snapshot.shop_voucher_offer) }
    else
        self.shop_voucher_offers = {}
    end
    self.shop_voucher_nodes = {}
    self.shop_booster_nodes = {}
    self.shop_voucher_bought_pending_boss = snapshot.shop_voucher_bought_pending_boss == true
    self.hand_size_delta_voucher = tonumber(snapshot.hand_size_delta_voucher) or 0
    self.hand_size_delta_juggle = tonumber(snapshot.hand_size_delta_juggle) or 0
    self._shop_reroll_base_cost_override = snapshot._shop_reroll_base_cost_override
    self.voucher_hands_delta = tonumber(snapshot.voucher_hands_delta) or 0
    self.boss_rerolls_used_this_ante = tonumber(snapshot.boss_rerolls_used_this_ante) or 0
    self.hand_stats = copy_table(snapshot.hand_stats or {})
    self.joker_pool_replacements = copy_table(snapshot.joker_pool_replacements or {})
    if snapshot.gros_michel_extinct == true then
        self.joker_pool_replacements.j_gros_michel = "j_cavendish"
    end
    self.skips = snapshot.skips
    self.skip_tag_orbital_hand = copy_table(snapshot.skip_tag_orbital_hand or {})
    self.handsPlayed = snapshot.handsPlayed
    self.discardsUnused = snapshot.discardsUnused
    self.skipsTaken = snapshot.skipsTaken
    self.ectoplasm_used = snapshot.ectoplasm_used
    self.run_best_hand_score = tonumber(snapshot.run_best_hand_score) or 0
    self.run_cards_played = tonumber(snapshot.run_cards_played) or 0
    self.run_cards_discarded = tonumber(snapshot.run_cards_discarded) or 0
    self.run_cards_purchased = tonumber(snapshot.run_cards_purchased) or 0
    self.run_times_rerolled = tonumber(snapshot.run_times_rerolled) or 0
    self._endless_mode = snapshot._endless_mode == true
    self.joker_shared_picks = copy_table(snapshot.joker_shared_picks or {})

    for _, jrec in ipairs(snapshot.jokers or {}) do
        local params = nil
        if jrec.edition and jrec.edition ~= "base" then
            params = { edition = jrec.edition }
        end
        local ok = self:add_joker_by_def(jrec.id, params)
        if ok then
            local j = self.jokers[#self.jokers]
            if j then
                j.stored_mult = tonumber(jrec.stored_mult) or j.stored_mult
                j.stored_chips = tonumber(jrec.stored_chips) or j.stored_chips
                j.stored_xmult = tonumber(jrec.stored_xmult) or j.stored_xmult
                j.runtime_counter = tonumber(jrec.runtime_counter) or j.runtime_counter
                j.sell_cost = tonumber(jrec.sell_cost) or j.sell_cost
                j.loyalty_remaining = jrec.loyalty_remaining
                j.free_joker_slots = jrec.free_joker_slots
                j.perishable = jrec.perishable
                j.perishable_counter = jrec.perishable_counter or 5
                j.eternal = jrec.eternal
                j.rental = jrec.rental
                if jrec.random_suit ~= nil or jrec.random_rank ~= nil or jrec.random_hand ~= nil then
                    local restore = {}
                    if jrec.random_suit ~= nil then restore.random_suit = jrec.random_suit end
                    if jrec.random_rank ~= nil then restore.random_rank = jrec.random_rank end
                    if jrec.random_hand ~= nil then restore.random_hand = jrec.random_hand end
                    if not self:get_joker_shared_pick(jrec.id) then
                        self:set_joker_shared_picks(jrec.id, restore)
                    else
                        self:apply_joker_shared_picks_to_joker(j)
                    end
                else
                    self:apply_joker_shared_picks_to_joker(j)
                end
            end
        end
    end

    for _, c in ipairs(snapshot.consumables or {}) do
        local cid = c and c.id
        if type(cid) == "string" and cid ~= "" then
            local params = copy_table(c)
            params.id = nil
            self:add_consumable(cid, params)
        end
    end

    self:refresh_consumable_capacity_from_negatives()
    self:refresh_joker_capacity_from_negatives()

    if self.hand and type(snapshot.hand_selected_uids) == "table" then
        local sel_set = {}
        for _, uid in ipairs(snapshot.hand_selected_uids) do
            sel_set[uid] = true
        end
        self.hand.selected = {}
        for _, node in ipairs(self.hand.card_nodes or {}) do
            if node and node.card_data and sel_set[node.card_data.uid] then
                node.selected = true
                self.hand.selected[#self.hand.selected + 1] = node
            end
        end
        if self.hand.calculate_play then
            self.hand:calculate_play()
        end
    end

    if self.sync_shop_offer_nodes then
        self:purge_all_joker_pool_swaps_from_shop()
        self:sync_shop_offer_nodes()
    end
    if self.sync_shop_booster_nodes then
        self:sync_shop_booster_nodes()
    end
    if self.sync_shop_voucher_nodes then
        self:sync_shop_voucher_nodes()
    end

    local resume_state = tonumber(snapshot.resume_state) or self.STATES.BLIND_SELECT
    if resume_state == self.STATES.PAUSED or resume_state == self.STATES.MENU then
        resume_state = self.STATES.BLIND_SELECT
    elseif resume_state == self.STATES.OPEN_BOOSTER then
        resume_state = self.STATES.SHOP
    elseif resume_state == self.STATES.GAME_OVER then
        resume_state = self.STATES.BLIND_SELECT
    end
    -- YOU_WIN resumes on the win screen so the player can pick Endless / New Run / Menu again.
    self._pause_prev_state = nil
    self:set_state(resume_state)
    return true
end

function Game:continue_saved_run_from_main_menu()
    local snapshot, err = self:read_run_snapshot()
    if not snapshot then return false, err end
    local ok, load_err = self:load_run_snapshot(snapshot)
    if ok then
        self:clear_run_snapshot()
    end
    return ok, load_err
end

function Game:start_new_run_from_main_menu()
    self:clear_run_snapshot()
    return self:start_run_from_main_menu()
end

function Game:enter_main_menu_deck_select()
    if self:is_hand_scoring_active() then
        self._pause_save_error = "Cannot save while scoring."
        return false
    end
    local snapshot = self:build_run_snapshot()
    local ok, err = self:write_run_snapshot(snapshot)
    if not ok then
        self._pause_save_error = "Save failed: " .. tostring(err or "unknown")
        return false
    end
    self._pause_prev_state = nil
    self._pause_save_error = nil
    self:enter_main_menu()
    MainMenuUI.open_deck_select(self)
    return true
end

function Game:pause_save_and_quit()
    if self:is_hand_scoring_active() then
        self._pause_save_error = "Cannot save while scoring."
        return false
    end
    local snapshot = self:build_run_snapshot()
    local ok, err = self:write_run_snapshot(snapshot)
    if not ok then
        self._pause_save_error = "Save failed: " .. tostring(err or "unknown")
        return false
    end
    self._pause_prev_state = nil
    self._pause_save_error = nil
    self:enter_main_menu()
    return true
end

function Game:get_base_requirement_for_ante(ante)
    local base_table = self.BASE_REQUIREMENT_BY_ANTE or {}
    local a = math.max(1, tonumber(ante) or 1)
    local stake_offset = tonumber(self._stake_ante_mult) or 0
    local max_ante = 8
    local deckMult = 1
    if self._deck_special == "plasma" then
        deckMult = 2
    end
    a = a + (max_ante + 1) * stake_offset
    if base_table[a] and self.ante <= max_ante then
        return tonumber(base_table[a] * deckMult) or 0
    end
    -- Endless Formula
    local last_base = tonumber(base_table[max_ante + (max_ante + 1) * stake_offset] * deckMult) or 50000
    local overflow = math.max(0, a - max_ante)
    local raw_result = last_base * (1.6 + (0.75 * overflow)^(1 + (0.2 * overflow)))^(overflow)
    -- Cap to two significant figures, rounded down
    local magnitude = math.floor(math.log10(raw_result))
    local two_sig_fig = math.floor(raw_result / (10^(magnitude - 1))) * (10^(magnitude - 1))
    return two_sig_fig
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

---@param blind table|nil
---@param ante number|nil
---@return boolean
function Game:is_boss_blind_allowed_for_ante(blind, ante)
    if type(blind) ~= "table" then return false end
    local boss = blind.boss
    if type(boss) ~= "table" then return false end
    local a = math.max(1, tonumber(ante) or tonumber(self.ante) or 1)
    local allow_showdown = self:is_showdown_ante(a)
    local is_showdown_boss = (boss.showdown == true)
    if is_showdown_boss and not allow_showdown then
        return false
    end
    if (not is_showdown_boss) and allow_showdown then
        return false
    end
    if is_showdown_boss then
        return true
    end
    local bmin = tonumber(boss.min)
    if bmin and a < bmin then return false end
    return true
end

---Boss pool for rolling; blinds with `boss.showdown` only appear on ante 8, 16, 24, ...
---@param ante number|nil Defaults to `self.ante`
function Game:get_boss_blind_pool(ante)
    local out = {}
    for key, blind in pairs(self.P_BLINDS or {}) do
        if key ~= "bl_small" and key ~= "bl_big" and type(blind) == "table" and type(blind.boss) == "table" then
            if self:is_boss_blind_allowed_for_ante(blind, ante) then
                out[#out + 1] = key
            end
        end
    end
    table.sort(out)
    return out
end

function Game:mark_boss_used(boss_id)
    if type(boss_id) ~= "string" or boss_id == "" then return end
    if type(self.bosses_used_this_cycle) ~= "table" then
        self.bosses_used_this_cycle = {}
    end
    self.bosses_used_this_cycle[boss_id] = true
end

function Game:reset_bosses_used_cycle()
    self.bosses_used_this_cycle = {}
end

function Game:serialize_bosses_used_cycle()
    local out = {}
    for id in pairs(self.bosses_used_this_cycle or {}) do
        out[#out + 1] = id
    end
    table.sort(out)
    return out
end

function Game:apply_bosses_used_cycle(data)
    self.bosses_used_this_cycle = {}
    if type(data) ~= "table" then return end
    for _, id in ipairs(data) do
        if type(id) == "string" and id ~= "" then
            self.bosses_used_this_cycle[id] = true
        end
    end
end

---@param ante number|nil
---@return string[]
function Game:get_eligible_boss_pool(ante)
    local pool = self:get_boss_blind_pool(ante)
    if #pool == 0 then return pool end
    local used = self.bosses_used_this_cycle or {}
    local filtered = {}
    for _, id in ipairs(pool) do
        if not used[id] then
            filtered[#filtered + 1] = id
        end
    end
    if #filtered == 0 then
        self:reset_bosses_used_cycle()
        return pool
    end
    return filtered
end

---@param opts table|nil `{ exclude_current = true }` marks the current boss used before rolling (rerolls).
function Game:roll_boss_blind(opts)
    if type(opts) == "table" and opts.exclude_current == true and self.current_boss_blind_id then
        self:mark_boss_used(self.current_boss_blind_id)
    end
    local pool = self:get_eligible_boss_pool()
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
        if not self:is_boss_blind_allowed_for_ante(proto, self.ante) then
            key = self:roll_boss_blind({ exclude_current = true })
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

local BLIND_EFFECT_DESCRIPTIONS = {
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

function Game:get_blind_effect_text_for_key(blind_key)
    if type(blind_key) ~= "string" then return "" end
    return BLIND_EFFECT_DESCRIPTIONS[blind_key] or ""
end

function Game:get_blind_prototype_description(blind_key)
    if type(blind_key) ~= "string" then return "" end
    if blind_key == "bl_small" or blind_key == "bl_big" then
        return "No special effect."
    end
    return self:get_blind_effect_text_for_key(blind_key)
end

function Game:get_boss_effect_text()
    local boss_id = self.current_boss_blind_id
    if not boss_id then
        local p = self:get_boss_blind_prototype()
        if p then boss_id = self.current_boss_blind_id end
    end
    return self:get_blind_effect_text_for_key(boss_id)
end

function Game:get_blind_description(index)
    index = tonumber(index) or tonumber(self.current_blind_index) or tonumber(self.selected_blind_index) or 1
    local def = self:get_blind_def(index)
    if not def then return "" end
    if def.id == "boss" then
        if self.boss_runtime and self.boss_runtime.disable_current_boss_ability == true then
            return "Boss ability disabled this round."
        end
        local text = self:get_boss_effect_text()
        if text ~= "" then return text end
        local proto = self:get_boss_blind_prototype()
        if proto and proto.debuff_text and proto.debuff_text ~= "" then
            return proto.debuff_text
        end
        return "Boss blind effect."
    end
    local target = self:get_blind_target(index, self.ante)
    if target and target > 0 then
        return string.format("Score at least %d chips.", math.floor(target))
    end
    return def.name or "Blind"
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
            if Joker and node and node.is and node:is(Joker) then
                self:_unregister_joker_front_atlas_owner(node)
            end
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
    if self.STATE == self.STATES.MENU then
        MainMenuUI.draw_bottom(self)
    elseif self.STATE == self.STATES.BLIND_SELECT then
        self:draw_bottom_blind_select()
    elseif self.STATE == self.STATES.ROUND_EVAL then
        self:draw_bottom_round_win()
    elseif self.STATE == self.STATES.GAME_OVER then
        self:draw_bottom_game_over()
    elseif self.STATE == self.STATES.YOU_WIN then
        YouWinUI.drawBottom(self)
        return
    elseif self.STATE == self.STATES.SHOP then
        self:draw_bottom_shop()
    elseif self.STATE == self.STATES.OPEN_BOOSTER then
        BoosterPackUI.draw_bottom(self)
        if self.hand and self.hand.card_nodes and #self.hand.card_nodes > 0 and self.hand.layout then
            self.hand:layout(false)
        end
    end

    -- Dark panel behind the joker row (bottom screen): only as wide as owned jokers.
    -- Draw this after bottom-state UI so it remains visible, but before nodes.
    if self.jokers_on_bottom == true and self.jokers and #self.jokers > 0 then
        local slot_w = self.joker_slot_w or 70
        local slot_h = self.joker_slot_h or 94
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

    -- Hide consumables during blind select + round eval + booster pack.
    local show_consumables = not (self.STATE == self.STATES.BLIND_SELECT or self.STATE == self.STATES.ROUND_EVAL
        or self.STATE == self.STATES.GAME_OVER or self.STATE == self.STATES.YOU_WIN or self.STATE == self.STATES.OPEN_BOOSTER)
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
    -- 1) regular nodes, 2) consumables, 3) hand cards on top 4) Popups -- DONT FORGET THIS
    local cons_set = {}
    local hand_set = {}
    local joker_set = {}
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
    if self.jokers_on_bottom == true and self.jokers then
        for _, jj in ipairs(self.jokers) do
            joker_set[jj] = true
        end
    end
    local draw_consumables_first = (self.jokers_on_bottom == true)
    if draw_consumables_first and self.consumable_nodes then
        for _, cn in ipairs(self.consumable_nodes) do
            if cn and cn.draw then cn:draw() end
        end
    end
    for _, node in ipairs(self.nodes) do
        if not node._deck_view_card and not node._collection_node and not cons_set[node] and not hand_set[node] and not joker_set[node] then
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
    if self.jokers_on_bottom == true and self.jokers then
        for _, jj in ipairs(self.jokers) do
            if jj and jj.draw then jj:draw() end
        end
    end
    if self.STATE == self.STATES.SHOP then
        self:draw_shop_offer_price_tags()
        self:draw_shop_booster_price_tags()
        self:draw_shop_voucher_price_tags()
    end

    if self.dragging then
        local ctx = self:resolve_drag_context(self.dragging)
        if ctx then
            local zones = self:get_drag_zones_for_context(ctx)
            DragZonesUI.draw(self, zones)
        end
    end

    if self._deck_view_open then
        DeckViewUI.draw_bottom(self)
    end

    if self.STATE == self.STATES.MENU and self._menu_sub_state == "collection_grid" then
        CollectionUI.draw_grid_nodes(self)
    end

    self:draw_tooltips_on_top()

    -- Popups
    if self.popups then
        for _, popup in ipairs(self.popups) do
            if popup and popup.draw then
                popup:draw()
            end
        end
    end

    -- Pause menu must overlay every gameplay element, including hand/tooltips.
    if self.STATE == self.STATES.PAUSED then
        self:draw_bottom_pause()
    end
end

--- Draw all bottom-screen card / joker / consumable tooltips after other UI.
function Game:draw_tooltips_on_top()
    love.graphics.setColor(1, 1, 1, 1)
    if self._collection_open and self._menu_sub_state == "collection_grid" then
        return
    end
    if self:is_card_select_mode() then
        local node = self:dpad_cursor_node()
        if node and node.draw_tooltip_overlay then
            node:draw_tooltip_overlay()
        end
        return
    end
    local is_booster = (self.STATE == self.STATES.OPEN_BOOSTER)
    if self.nodes then
        for _, node in ipairs(self.nodes) do
            if Joker and node and node.is and node:is(Joker) and node.draw_tooltip_overlay then
                node:draw_tooltip_overlay()
            end
            local is_shop_cons = Consumable and node and node.is and node:is(Consumable) and node.shop_offer_slot
            local is_booster_cons = is_booster and Consumable and node and node.is and node:is(Consumable) and node._booster_choice_index
            if (is_shop_cons or is_booster_cons) and node.draw_tooltip_overlay then
                node:draw_tooltip_overlay()
            end
            if is_booster and Card and node and node.is and node:is(Card) and node._booster_choice_index and node.draw_tooltip_overlay then
                node:draw_tooltip_overlay()
            end
            local is_shop_pc = (self.STATE == self.STATES.SHOP) and Card and node and node.is and node:is(Card) and node.shop_offer_slot
            if is_shop_pc and node.draw_tooltip_overlay then
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
    if self.hand and self.hand.card_nodes and not self._deck_view_open then
        for _, hn in ipairs(self.hand.card_nodes) do
            if hn and hn.draw_tooltip_overlay then
                hn:draw_tooltip_overlay()
            end
        end
    end
    if self._deck_view_open then
        DeckViewUI.draw_tooltips(self)
    end
    if self.STATE == self.STATES.BLIND_SELECT and self.active_tooltip_blind_index then
        self:_draw_blind_info_tooltip()
    end
    if self.STATE == self.STATES.BLIND_SELECT and self.active_tooltip_skip_blind_index then
        self:_draw_skip_tag_tooltip()
    end
    if self.STATE == self.STATES.SHOP and self.active_tooltip_shop_voucher_slot then
        self:_draw_shop_voucher_tooltip()
    end
    if self.STATE == self.STATES.SHOP and tonumber(self.active_shop_booster_slot) then
        local slot = tonumber(self.active_shop_booster_slot)
        local offer = self.shop_booster_offers and self.shop_booster_offers[slot]
        local rect = self._shop_booster_rects and self._shop_booster_rects[slot]
        if offer and rect then
            self:_draw_shop_booster_tooltip(offer, rect)
        end
    end
end

function Game:_draw_shop_voucher_tooltip()
    local slot = tonumber(self.active_tooltip_shop_voucher_slot)
    local offer = slot and self.shop_voucher_offers and self.shop_voucher_offers[slot]
    local rect = slot and self._shop_voucher_rects and self._shop_voucher_rects[slot]
    if type(offer) ~= "table" or type(rect) ~= "table" then return end
    local title = tostring(offer.name or "Voucher")
    local desc = tostring(offer.description or "")
    local font = (self.FONTS and self.FONTS.PIXEL and self.FONTS.PIXEL.SMALL) or love.graphics.getFont()
    local resolved = TooltipDraw.resolved_lines_from_multiline(desc)
    TooltipDraw.draw_tooltip_layout(font, title, resolved, rect.x, rect.y, rect.w, rect.h)
end

function Game:_draw_shop_booster_tooltip(offer, rect)
    if type(offer) ~= "table" or type(rect) ~= "table" then return end
    local title = tostring(offer.name or "Booster Pack")
    local desc = BoosterPackUI.shop_tooltip_description(offer)
    local font = (self.FONTS and self.FONTS.PIXEL and self.FONTS.PIXEL.SMALL) or love.graphics.getFont()
    local resolved = TooltipDraw.resolved_lines_from_multiline(desc)
    TooltipDraw.draw_tooltip_layout(font, title, resolved, rect.x, rect.y, rect.w, rect.h)
end

--- Add a Consumable by definition id (see `CONSUMABLE_DEFS` in `consumable_catalog.lua`).
---@param def_id string
---@param create_params table|nil optional `{ edition = "negative" }`
---@return boolean
function Game:add_consumable(def_id, create_params)
    if type(def_id) ~= "string" or def_id == "" then return false end
    if not CONSUMABLE_DEFS or type(CONSUMABLE_DEFS) ~= "table" then return false end
    local def = CONSUMABLE_DEFS[def_id]
    if type(def) ~= "table" then return false end

    if not self.consumables then self.consumables = {} end
    if not self.consumable_nodes then self.consumable_nodes = {} end
    local params = type(create_params) == "table" and create_params or nil
    if (not params or params.edition == nil) and def.edition then
        params = params and copy_table(params) or {}
        params.edition = def.edition
    end
    if not self:can_add_consumable(params) then return false end

    local copy = copy_table(def)
    if type(params) == "table" then
        for k, v in pairs(params) do
            copy[k] = v
        end
    end
    table.insert(self.consumables, copy)

    local idx = #self.consumables
    local node = Consumable(0, 0, copy)
    self.consumable_nodes[idx] = node
    self:add(node)
    self:refresh_consumable_capacity_from_negatives()

    self:discover_item(def_id)
    self:draw_consumables_row()
    return true
end

function Game:consumable_is_negative(c)
    if type(c) ~= "table" then return false end
    local ed = tostring(c.edition or "base"):lower()
    return ed == "negative" or ed == "e_negative"
end

function Game:count_negative_consumables()
    local n = 0
    for _, c in ipairs(self.consumables or {}) do
        if self:consumable_is_negative(c) then
            n = n + 1
        end
    end
    return n
end

--- Base slots + deck/voucher bonuses + one extra slot per owned Negative consumable (same model as jokers).
function Game:get_effective_consumable_capacity()
    local cap = self.consumable_base_capacity or 2
    cap = cap + (self.deck_consumable_slots or 0)
    if self:has_voucher("v_crystal_ball") then
        cap = cap + 1
    end
    cap = cap + self:count_negative_consumables()
    return math.max(0, math.floor(cap))
end

function Game:refresh_consumable_capacity_from_negatives()
    self.consumable_capacity = self:get_effective_consumable_capacity()
end

---@param create_params table|nil optional edition for an incoming consumable
---@return boolean
function Game:can_add_consumable(create_params)
    local incoming_negative = false
    if type(create_params) == "table" then
        local ed = tostring(create_params.edition or ""):lower()
        incoming_negative = ed == "negative" or ed == "e_negative"
    end
    local n = #(self.consumables or {})
    local cap = self:get_effective_consumable_capacity()
    if incoming_negative then
        return n < cap + 1
    end
    return n < cap
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
    self:refresh_consumable_capacity_from_negatives()

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
    local cap = self:get_effective_consumable_capacity()
    local c = self.consumables and self.consumables[index]
    -- Using a Negative also removes its bonus slot.
    if self:consumable_is_negative(c) then
        return math.max(0, (cap - 1) - (n - 1))
    end
    return math.max(0, cap - (n - 1))
end

function Game:consumable_play_state_ok()
    local s = self.STATE
    return s == self.STATES.SELECTING_HAND or s == self.STATES.SHOP
end

function Game:hand_ready_for_tarot_selection()
    local state_ok = (self.STATE == self.STATES.SELECTING_HAND)
        or (self.STATE == self.STATES.OPEN_BOOSTER and self.booster_session and self.booster_session.hand_for_tarot)
    if not state_ok then return false end
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
    local cap_after = self:joker_base_capacity() + neg_owned + (new_is_neg and 1 or 0)
    return #self.jokers < cap_after
end

function Game:has_base_edition_joker()
    if not self.jokers then return false end
    for _, jj in ipairs(self.jokers) do
        if jj and Joker and Joker.normalize_edition and Joker.normalize_edition(jj.edition) == "base" then
            return true
        end
    end
    return false
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

    if c.kind == "spectral" then
        local sid = c.id
        if sid == "spectral_wraith" or sid == "spectral_soul" then
            if not self:joker_has_room_for_new("base") then return false end
        end
        if sid == "spectral_ectoplasm" and not self:has_base_edition_joker() then
            return false
        end
        local need_hand = false
        local s = c.select
        if type(s) == "table" and (s.exact or 0) > 0 then
            need_hand = true
        end
        if type(s) == "table" and s.min and tonumber(s.min) > 0 then
            need_hand = true
        end
        if need_hand then
            if not self:hand_ready_for_tarot_selection() then return false end
            return self:tarot_selection_requirement_met(c)
        end
        return true
    end

    return false
end

---@param c table|nil
---@return boolean
function Game:consumable_requires_selection(c)
    if type(c) ~= "table" then return false end
    local s = c.select
    if type(s) ~= "table" then return false end
    local exact = tonumber(s.exact)
    if exact and exact > 0 then return true end
    local smin = tonumber(s.min)
    if smin and smin > 0 then return true end
    return false
end

---@param offer table|nil
---@return boolean
function Game:shop_offer_consumable_use_enabled(offer)
    if type(offer) ~= "table" then return false end
    local kind = offer.kind
    if kind ~= "tarot" and kind ~= "planet" and kind ~= "spectral" then return false end
    local def = CONSUMABLE_DEFS and CONSUMABLE_DEFS[offer.id]
    if type(def) ~= "table" then return false end
    if self:consumable_requires_selection(def) then return false end
    local c = copy_table and copy_table(def) or nil
    if type(c) ~= "table" then return false end
    c.id = offer.id
    return self:pack_consumable_can_apply(c)
end

function Game:record_consumable_use_id(id)
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

--- Deep-copy `src` into existing table `dest` (keeps `dest` reference for hand/deck tracking).
---@param dest table
---@param src table
---@return table|nil
function Game:copy_card_data_into(dest, src)
    if type(dest) ~= "table" or type(src) ~= "table" then return dest end
    for k in pairs(dest) do
        dest[k] = nil
    end
    for k, v in pairs(src) do
        if type(v) == "table" then
            dest[k] = self:deep_copy_card_data(v)
        else
            dest[k] = v
        end
    end
    return dest
end

function Game:has_played_hand_name(hand_name)
    if type(hand_name) ~= "string" or hand_name == "" then return false end
    if type(self.handlist) ~= "table" then return false end
    local idx = nil
    for i, name in ipairs(self.handlist) do
        if name == hand_name then
            idx = i
            break
        end
    end
    if not idx then return false end
    return (self.hand_play_counts and tonumber(self.hand_play_counts[idx]) or 0) >= 1
end

function Game:planet_consumable_unlocked(def_id, def)
    if def_id == "planet_x" or def_id == "planet_ceres" or def_id == "planet_eris" then
        return self:has_played_hand_name(def and def.hand)
    end
    return true
end

function Game:random_consumable_id_of_kind(kind, exclude)
    exclude = exclude or {}
    local pool = {}
    if not CONSUMABLE_DEFS then return nil end
    for def_id, def in pairs(CONSUMABLE_DEFS) do
        if type(def) == "table" and def.kind == kind and not exclude[def_id] then
            if kind ~= "planet" or self:planet_consumable_unlocked(def_id, def) then
                pool[#pool + 1] = def_id
            end
        end
    end
    if #pool == 0 then return nil end
    return pool[math.random(1, #pool)]
end

function Game:random_non_fool_tarot_id()
    return self:random_consumable_id_of_kind("tarot", { tarot_fool = true })
end

---@param hand_name string|nil
---@return string|nil
function Game:random_planet_id_for_hand_name(hand_name)
    if type(hand_name) ~= "string" or hand_name == "" then return nil end
    if not CONSUMABLE_DEFS then return nil end
    local pool = {}
    for def_id, def in pairs(CONSUMABLE_DEFS) do
        if type(def) == "table" and def.kind == "planet" and def.hand == hand_name then
            pool[#pool + 1] = def_id
        end
    end
    if #pool == 0 then return nil end
    return pool[math.random(1, #pool)]
end

--- Register a joker pair that are mutually exclusive in random pools (only one may appear).
---@param from_id string
---@param to_id string
function Game:register_joker_pool_swap_pair(from_id, to_id)
    if type(from_id) ~= "string" or type(to_id) ~= "string" or from_id == "" or to_id == "" then
        return
    end
    self.joker_pool_swap_pairs = self.joker_pool_swap_pairs or {}
    for _, pair in ipairs(self.joker_pool_swap_pairs) do
        if pair.from == from_id and pair.to == to_id then
            return
        end
    end
    self.joker_pool_swap_pairs[#self.joker_pool_swap_pairs + 1] = { from = from_id, to = to_id }
end

---@param from_id string
---@param to_id string
---@return boolean
function Game:is_joker_pool_swap_active(from_id, to_id)
    return self.joker_pool_replacements
        and self.joker_pool_replacements[from_id] == to_id
end

--- Gros Michel / Cavendish and other registered pairs are mutually exclusive in random pools.
---@param joker_id string|nil
---@return boolean
function Game:joker_allowed_in_random_pool(joker_id)
    if type(joker_id) ~= "string" then return true end
    for from_id, to_id in pairs(self.joker_pool_replacements or {}) do
        if joker_id == from_id then return false end
        if joker_id == to_id then return true end
    end
    for _, pair in ipairs(self.joker_pool_swap_pairs or {}) do
        if joker_id == pair.to then return false end
    end
    return true
end

--- Rebuild a shop offer as `to_id`, preserving edition and free-price tags when possible.
---@param offer table
---@param from_id string
---@param to_id string
---@return table
function Game:replace_shop_joker_offer(offer, from_id, to_id)
    if type(offer) ~= "table" then return offer end
    if offer.kind ~= "joker" and offer.kind ~= nil then return offer end
    if offer.id ~= from_id then return offer end
    local def = JOKER_DEFS and JOKER_DEFS[to_id]
    if type(def) ~= "table" then return offer end

    local edition = offer.edition or "base"
    local sticker_params = offer.stickers or self:_build_joker_sticker_params(def)
    local preserved_price = tonumber(offer.price)
    offer.id = to_id
    offer.name = def.name or to_id
    offer.edition = edition
    offer.stickers = sticker_params
    offer.create_params = self:_build_joker_create_params(def, { edition = edition }, sticker_params)
    if preserved_price == 0 then
        offer.price = 0
    else
        offer.price = self:shop_price_for_joker_offer(def, edition, sticker_params)
    end
    offer.eternal = sticker_params.eternal == true or nil
    offer.perishable = sticker_params.perishable == true or nil
    offer.rental = sticker_params.rental == true or nil
    return offer
end

--- Apply any active joker pool swap to a queued or visible shop offer.
---@param offer table|nil
---@return table|nil
function Game:remap_shop_joker_offer(offer)
    if type(offer) ~= "table" then return offer end
    local from_id = offer.id
    if type(from_id) ~= "string" then return offer end
    local to_id = self.joker_pool_replacements and self.joker_pool_replacements[from_id]
    if not to_id then return offer end
    return self:replace_shop_joker_offer(offer, from_id, to_id)
end

--- Replace `from_id` with `to_id` in the shop queue and current offers.
---@param from_id string
---@param to_id string
function Game:purge_joker_pool_swap_from_shop(from_id, to_id)
    if not self:is_joker_pool_swap_active(from_id, to_id) then return end
    if type(self.shop_offer_queue) == "table" then
        for _, entry in ipairs(self.shop_offer_queue) do
            self:replace_shop_joker_offer(entry, from_id, to_id)
        end
    end
    if type(self.shop_offers) == "table" then
        for _, entry in ipairs(self.shop_offers) do
            self:replace_shop_joker_offer(entry, from_id, to_id)
        end
    end
end

function Game:purge_all_joker_pool_swaps_from_shop()
    for from_id, to_id in pairs(self.joker_pool_replacements or {}) do
        self:purge_joker_pool_swap_from_shop(from_id, to_id)
    end
end

--- Activate a joker pool swap (e.g. Gros Michel -> Cavendish after extinction).
---@param from_id string
---@param to_id string
function Game:activate_joker_pool_swap(from_id, to_id)
    if type(from_id) ~= "string" or type(to_id) ~= "string" or from_id == "" or to_id == "" then
        return
    end
    self:register_joker_pool_swap_pair(from_id, to_id)
    self.joker_pool_replacements = self.joker_pool_replacements or {}
    if self.joker_pool_replacements[from_id] == to_id then
        self:purge_joker_pool_swap_from_shop(from_id, to_id)
        return
    end
    self.joker_pool_replacements[from_id] = to_id
    self:purge_joker_pool_swap_from_shop(from_id, to_id)
    if self.sync_shop_offer_nodes then
        self:sync_shop_offer_nodes()
    end
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

---@param rarity integer
---@return string|nil
function Game:random_joker_def_id_by_rarity(rarity)
    local r = tonumber(rarity)
    if not r or not JOKER_DEFS then return nil end
    local allow_duplicates = self:hasJoker("j_ring_master")
    local pool = {}
    for id, def in pairs(JOKER_DEFS) do
        if type(def) == "table" and tonumber(def.rarity) == r and self:joker_allowed_in_random_pool(id) then
            if allow_duplicates or not self:_shop_joker_owned(id) then
                pool[#pool + 1] = id
            end
        end
    end
    if #pool == 0 then return nil end
    return pool[math.random(1, #pool)]
end

--- Increment stored level for poker hand index `idx` (1..12). If that hand is the current play, updates
--- `selectedHandLevel`, `selectedHandChips`, and `selectedHandMult` (including boss hand modifiers).
---@param idx integer
---@return boolean
function Game:upgrade_hand_level_at_index(idx)
    idx = tonumber(idx)
    if not idx or not self.hand_stats or not self.hand_stats[idx] then return false end
    local stats = self.hand_stats[idx]
    stats.level = (tonumber(stats.level) or 1) + 1
    local level = math.max(1, tonumber(stats.level) or 1)
    local chips = (tonumber(stats.base_chips) or 0) + ((level - 1) * (tonumber(stats.chips_per_level) or 0))
    local mult = (tonumber(stats.base_mult) or 0) + ((level - 1) * (tonumber(stats.mult_per_level) or 0))
    if self.boss_apply_hand_base_modifiers then
        chips, mult = self:boss_apply_hand_base_modifiers(chips, mult)
    end
    if tonumber(self.selectedHand) == idx then
        self.selectedHandLevel = level
        self.selectedHandChips = chips
        self.selectedHandMult = mult
    end
    return true
end

function Game:reset_hand_levels()
    for i = 1, #(self.hand_stats or {}) do
        self.hand_stats[i].level = 1
    end
end

--- Apply the runtime effect for a Consumable and play a simple SFX where appropriate.
---@param c table
function Game:apply_consumable_effect(c)
    if type(c) ~= "table" then return end
    local kind = c.kind
    local id = c.id
    if id then self:discover_item(id) end
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

    if kind == "spectral" then
        local ord = ordered_nodes()
        local function random_enhancement()
            local enh = { "bonus", "mult", "wild", "glass", "steel", "gold", "lucky" }
            return enh[math.random(1, #enh)]
        end
        local function add_generated_card(rank, suit, enhancement)
            if not hand or not hand.add_card then return nil end
            local cd = {
                rank = rank,
                suit = suit,
                enhancement = enhancement,
                seal = nil,
            }
            local node = hand:add_card(cd, true)
            if node then
                self:notify_cards_added_to_deck(1)
            end
            return node
        end

        if id == "spectral_black_hole" then
            for i = 1, #(self.handlist or {}) do
                self:upgrade_hand_level_at_index(i)
            end
        elseif id == "spectral_familiar" then
            if hand and #hand.card_nodes > 0 then
                hand:destroy_card_at_index(math.random(1, #hand.card_nodes))
            end
            local suits = { "Hearts", "Clubs", "Diamonds", "Spades" }
            for _ = 1, 3 do
                add_generated_card(math.random(11, 13), suits[math.random(1, #suits)], random_enhancement())
            end
        elseif id == "spectral_grim" then
            if hand and #hand.card_nodes > 0 then
                hand:destroy_card_at_index(math.random(1, #hand.card_nodes))
            end
            local suits = { "Hearts", "Clubs", "Diamonds", "Spades" }
            for _ = 1, 2 do
                add_generated_card(14, suits[math.random(1, #suits)], random_enhancement())
            end
        elseif id == "spectral_incantation" then
            if hand and #hand.card_nodes > 0 then
                hand:destroy_card_at_index(math.random(1, #hand.card_nodes))
            end
            local suits = { "Hearts", "Clubs", "Diamonds", "Spades" }
            for _ = 1, 4 do
                add_generated_card(math.random(2, 10), suits[math.random(1, #suits)], random_enhancement())
            end
        elseif id == "spectral_talisman" then
            if ord[1] and ord[1].set_seal then ord[1]:set_seal("gold") end
        elseif id == "spectral_deja_vu" then
            if ord[1] and ord[1].set_seal then ord[1]:set_seal("red") end
        elseif id == "spectral_trance" then
            if ord[1] and ord[1].set_seal then ord[1]:set_seal("blue") end
        elseif id == "spectral_medium" then
            if ord[1] and ord[1].set_seal then ord[1]:set_seal("purple") end
        elseif id == "spectral_cryptid" then
            if ord[1] and ord[1].card_data and hand and hand.add_card and self.deep_copy_card_data then
                local added = 0
                for _ = 1, 2 do
                    local copy = self:deep_copy_card_data(ord[1].card_data)
                    if copy then
                        copy.uid = nil
                        if hand:add_card(copy, true) then
                            added = added + 1
                        end
                    end
                end
                self:notify_cards_added_to_deck(added)
            end
        elseif id == "spectral_aura" then
            if ord[1] and ord[1].card_data then
                local picked = ({ "foil", "holo", "polychrome" })[math.random(1, 3)]
                ord[1].card_data.modifier = ord[1].card_data.modifier or {}
                if picked == "foil" then
                    ord[1].card_data.modifier.chip_bonus = 50
                    ord[1].card_data.modifier.mult_bonus = 0
                elseif picked == "holo" then
                    ord[1].card_data.modifier.chip_bonus = 0
                    ord[1].card_data.modifier.mult_bonus = 10
                else
                    ord[1].card_data.modifier.chip_bonus = 0
                    ord[1].card_data.modifier.mult_bonus = 15
                end
                ord[1].card_data.modifier.edition = picked
                if ord[1].sync_visual_from_card_data then
                    ord[1]:sync_visual_from_card_data()
                end
            end
        elseif id == "spectral_wraith" then
            local jid = self:random_joker_def_id_by_rarity(3)
            if jid and self:joker_has_room_for_new("base") then
                self:add_joker_by_def(jid)
            end
            self.money = 0
        elseif id == "spectral_soul" then
            local jid = self:random_joker_def_id_by_rarity(4)
            if jid and self:joker_has_room_for_new("base") then
                self:add_joker_by_def(jid)
            end
        elseif id == "spectral_sigil" then
            if hand and hand.card_nodes and #hand.card_nodes > 0 then
                local suit = ({ "Hearts", "Clubs", "Diamonds", "Spades" })[math.random(1, 4)]
                for _, node in ipairs(hand.card_nodes) do
                    if node and node.card_data then
                        node.card_data.suit = suit
                        node:sync_visual_from_card_data()
                    end
                end
            end
        elseif id == "spectral_ouija" then
            if hand and hand.card_nodes and #hand.card_nodes > 0 then
                local rank = math.random(2, 14)
                for _, node in ipairs(hand.card_nodes) do
                    if node and node.card_data then
                        node.card_data.rank = rank
                        node:sync_visual_from_card_data()
                    end
                end
            end
            self.hand_size_delta_spectral = (tonumber(self.hand_size_delta_spectral) or 0) - 1
        elseif id == "spectral_ectoplasm" then
            if self.jokers and #self.jokers > 0 then
                local attempts = 0
                while attempts < #self.jokers do
                    local j = self.jokers[math.random(1, #self.jokers)]
                    if j and Joker and Joker.normalize_edition and Joker.normalize_edition(j.edition) == "base" then
                        j.edition = Joker.normalize_edition("negative")
                        if j.refresh_quads then j:refresh_quads() end
                        self:refresh_joker_capacity_from_negatives()
                        break
                    end
                    attempts = attempts + 1
                end
            end
            self.ectoplasm_used = (self.ectoplasm_used or 0) + 1
            self.hand_size_delta_spectral = (tonumber(self.hand_size_delta_spectral) or 0) - self.ectoplasm_used
        elseif id == "spectral_immolate" then
            if hand and hand.card_nodes and #hand.card_nodes > 0 then
                local count = math.min(5, #hand.card_nodes)
                for _ = 1, count do
                    if #hand.card_nodes <= 0 then break end
                    hand:destroy_card_at_index(math.random(1, #hand.card_nodes))
                end
            end
            self.money = (tonumber(self.money) or 0) + 20
        elseif id == "spectral_ankh" then
            if self.jokers and #self.jokers > 0 then
                local src = self.jokers[math.random(1, #self.jokers)]
                local src_id = src and src.def and src.def.id
                local src_edition = Joker and Joker.normalize_edition(src and src.edition) or "base"
                if src_id and src then
                    for i = #self.jokers, 1, -1 do
                        local j = self.jokers[i]
                        if j ~= src then
                            self:remove_owned_joker_at(i)
                        end
                    end
                    if self:joker_has_room_for_new(src_edition) and self:add_joker_by_def(src_id, { edition = src_edition }) then
                        local clone = self.jokers[#self.jokers]
                        if clone then
                            for k, v in pairs(src) do
                                if type(v) ~= "function" and k ~= "def" and k ~= "params" and k ~= "effect_impl"
                                    and k ~= "T" and k ~= "VT" and k ~= "velocity" and k ~= "drag"
                                    and k ~= "hovering" and k ~= "_hover_last" and k ~= "_touch_state"
                                    and k ~= "children" and k ~= "parent" and k ~= "front_quads"
                                    and k ~= "back_quads" and k ~= "sprite_batch" then
                                    if type(v) == "table" then
                                        clone[k] = self:deep_copy_card_data(v)
                                    else
                                        clone[k] = v
                                    end
                                end
                            end
                            clone.edition = src_edition
                            if clone.refresh_quads then clone:refresh_quads() end
                        end
                    end
                end
            end
        elseif id == "spectral_hex" then
            if self.jokers and #self.jokers > 0 then
                local keep = math.random(1, #self.jokers)
                local target = self.jokers[keep]
                if target and Joker then
                    target.edition = Joker.normalize_edition("polychrome")
                    if target.refresh_quads then target:refresh_quads() end
                end
                for i = #self.jokers, 1, -1 do
                    if i ~= keep then
                        self:remove_owned_joker_at(i)
                    end
                end
            end
        end

        clear_tarot_hand_ui()
        if hand and hand.layout then
            hand:layout(false)
        end
        if Sfx and Sfx.play_mult then Sfx.play_mult() end
        return
    end

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
                self:upgrade_hand_level_at_index(target_idx)
            end
        end
        self:record_consumable_use_id(id)
        if Sfx and Sfx.play_mult then Sfx.play_mult() end
        return
    end

    if kind ~= "tarot" then return end

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
        local free = math.max(0, self:get_effective_consumable_capacity() - #(self.consumables or {}))
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
        local free = math.max(0, self:get_effective_consumable_capacity() - #(self.consumables or {}))
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
        if self.jokers and #self.jokers > 0 and self:do_random(0, 4, 1) then
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
            if right.card_data and left.card_data and self.copy_card_data_into then
                self:copy_card_data_into(left.card_data, right.card_data)
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
        local jid = self:_pick_joker_id_shop_rarity_distribution(function(lo, hi)
            return math.random(lo, hi)
        end)
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

--- Shared bookkeeping for any consumable that gets used (owned, shop instant-use, booster pick/use).
---@param c Consumable|table|nil
function Game:track_consumable_use(c)
    if type(c) ~= "table" then return end
    if c.kind == "tarot" then
        self.tarots_used = (tonumber(self.tarots_used) or 0) + 1
    end
    self:emit_joker_event("on_consumable_used", {
        consumable = c,
        consumable_id = c.id,
        consumable_kind = c.kind,
    })
end

--- Use (consume) a Consumable at the given index.
---@param index integer
---@return boolean
function Game:use_consumable(index)
    if not self:consumable_use_enabled(index) then return false end
    local c = self:remove_consumable_at(index)
    if not c then return false end
    self:track_consumable_use(c)
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
    local gap = 6
    local row_margin = 8
    local y = -30

    local n = #list
    local area_w = (draw_w + gap) * 2
    local area_x = sw - area_w + 2 * gap
    local step, span = self:_compute_fanned_joker_row(n, area_w, draw_w, gap, row_margin)
    local start_x = area_x + (area_w - row_margin) - span
    self._consumable_row_step = step
    self._consumable_row_span = span
    self._consumable_row_start_x = start_x
    self._consumable_row_card_w = draw_w

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

function Game:_consumable_nearest_slot_idx(release_x)
    local owned_count = self.consumable_nodes and #self.consumable_nodes or 0
    if owned_count <= 0 then return 1 end
    local step = tonumber(self._consumable_row_step)
    local start_x = tonumber(self._consumable_row_start_x)
    local slot_w_scaled = tonumber(self._consumable_row_card_w) or 72
    if not step or not start_x then
        local sw = 320
        if love.graphics.getWidth then
            sw = love.graphics.getWidth("bottom")
            if not sw or sw <= 0 then sw = love.graphics.getWidth() end
        end
        if not sw or sw <= 0 then sw = 320 end
        step, _, start_x = self:_compute_fanned_joker_row(owned_count, sw, slot_w_scaled, 6, 8)
    end
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

function Game:try_reorder_consumable_after_drag(consumable_node, release_x)
    if not consumable_node or not self.consumable_nodes or self.jokers_on_bottom == true then return false end

    local from_idx
    for i, c in ipairs(self.consumable_nodes) do
        if c == consumable_node then
            from_idx = i
            break
        end
    end
    if not from_idx then return false end

    local to_idx = self:_consumable_nearest_slot_idx(release_x)
    if to_idx == from_idx then return false end

    local node = table.remove(self.consumable_nodes, from_idx)
    table.insert(self.consumable_nodes, to_idx, node)
    local data = table.remove(self.consumables, from_idx)
    table.insert(self.consumables, to_idx, data)

    local tip = tonumber(self.active_tooltip_consumable_index)
    if tip and tip == from_idx then
        self.active_tooltip_consumable_index = to_idx
    elseif tip then
        if from_idx < tip and to_idx >= tip then
            self.active_tooltip_consumable_index = tip - 1
        elseif from_idx > tip and to_idx <= tip then
            self.active_tooltip_consumable_index = tip + 1
        end
    end

    self:draw_consumables_row()
    return true
end

---@param c Consumable|table|nil
---@return integer
function Game:consumable_sell_value(c)
    local kind = c and (c.kind or (c.def and c.def.kind)) or nil
    if kind == "spectral" then return 2 end
    return 1
end

function Game:perform_sell_for_target(sell_target)
    if not sell_target then return false end
    if sell_target.kind == "joker" then
        return self:sell_owned_joker(sell_target.index)
    elseif sell_target.kind == "consumable" then
        local idx = sell_target.index
        local c = self:remove_consumable_at(idx)
        if not c then return false end
        local value = self:consumable_sell_value(c)
        self.money = (tonumber(self.money) or 0) + value
        if self.active_tooltip_consumable_index == idx then
            self.active_tooltip_consumable_index = nil
        end
        return true
    end
    -- Future kinds: vouchers, boosters, etc.
    return false
end

function Game:_point_in_rect_simple(px, py, r)
    return r and px >= r.x and px <= (r.x + r.w) and py >= r.y and py <= (r.y + r.h)
end

function Game:draw_blind_chip_sprite(sprite_row, center_x, center_y, scale)
    local atlas = self.ANIMATION_ATLAS and self.ANIMATION_ATLAS.blind_chips
    if not atlas or not atlas.image then return end
    local cell_w = tonumber(atlas.px) or 36
    local cell_h = tonumber(atlas.py) or 36
    local frames_per_blind = tonumber(atlas.frames) or 1
    local blind_row = tonumber(sprite_row) or 0
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

function Game:draw_blind_chip_anim(blind_index, center_x, center_y, scale)
    local blind_row = tonumber(self:get_blind_sprite_index(blind_index)) or 0
    self:draw_blind_chip_sprite(blind_row, center_x, center_y, scale)
end

--- Horizontal strip: `animation_atli.shop_sign` (px×py per frame, `frames` count).
function Game:draw_shop_sign_anim(center_x, center_y, scale)
    ShopUI.draw_shop_sign_anim(self, center_x, center_y, scale)
end

function Game:tag_type_for_id(tag_id)
    local id = tonumber(tag_id)
    if id == 0 then return "uncommon" end
    if id == 1 then return "rare" end
    if id == 2 then return "negative" end
    if id == 3 then return "foil" end
    if id == 4 then return "coupon" end
    if id == 5 then return "double" end
    if id == 6 then return "holo" end
    if id == 7 then return "polychrome" end
    if id == 8 then return "investment" end
    if id == 9 then return "voucher" end
    if id == 10 then return "topup" end
    if id == 11 then return "juggle" end
    if id == 12 then return "boss" end
    if id == 13 then return "standard" end
    if id == 14 then return "charm" end
    if id == 15 then return "meteor" end
    if id == 16 then return "buffoon" end
    if id == 17 then return "orbital" end
    if id == 18 then return "speed" end
    if id == 19 then return "handy" end
    if id == 20 then return "garbage" end
    if id == 21 then return "ethereal" end
    if id == 22 then return "economy" end
    if id == 23 then return "d6" end
    return nil
end

function Game:ensure_skip_orbital_hand(blind_index)
    blind_index = tonumber(blind_index)
    if not blind_index or not self.skips or self.skips[blind_index] ~= 17 then return end
    if type(self.skip_tag_orbital_hand) ~= "table" then
        self.skip_tag_orbital_hand = {}
    end
    if not self.skip_tag_orbital_hand[blind_index] then
        self.skip_tag_orbital_hand[blind_index] = self:roll_orbital_hand_index()
    end
end

function Game:roll_orbital_hand_index()
    local handlist = self.handlist or {}
    local n = #handlist
    if n == 0 then return 1 end

    local eligible = {}
    for i = 1, n do
        if i <= 3 then
            if (tonumber(self.hand_play_counts and self.hand_play_counts[i]) or 0) > 0 then
                eligible[#eligible + 1] = i
            end
        else
            eligible[#eligible + 1] = i
        end
    end
    if #eligible == 0 then
        for i = 4, n do
            eligible[#eligible + 1] = i
        end
    end
    if #eligible == 0 then return math.min(4, n) end
    return eligible[math.random(1, #eligible)]
end

function Game:tag_key_for_id(tag_id)
    local type_name = self:tag_type_for_id(tag_id)
    if not type_name then return nil end
    if type_name == "d6" then return "tag_d_six" end
    return "tag_" .. type_name
end

function Game:get_skip_tag_tooltip(skip_id, blind_index)
    local type_name = self:tag_type_for_id(skip_id)
    if not type_name then return nil end
    local key = self:tag_key_for_id(skip_id)
    local def = key and self.P_TAGS and self.P_TAGS[key]
    local name = (def and def.name) or (type_name:sub(1, 1):upper() .. type_name:sub(2) .. " Tag")
    local description = Tag and Tag.get_description and Tag.get_description(type_name) or ""
    if type_name == "orbital" and blind_index then
        self:ensure_skip_orbital_hand(blind_index)
        local idx = self.skip_tag_orbital_hand and self.skip_tag_orbital_hand[blind_index]
        local hand_name = idx and self.handlist and self.handlist[idx]
        if hand_name then
            description = Tag.get_description(type_name, hand_name)
        end
    end
    return { name = name, description = description, type = type_name }
end

function Game:draw_skip_tag_icon(tag_type, x, y, scale)
    if type(tag_type) ~= "string" or tag_type == "" or not Tag then return end
    love.graphics.push()
    love.graphics.translate(x, y)
    love.graphics.scale(scale or 1, scale or 1)
    local tag = Tag(tag_type)
    tag.X = 0
    tag.Y = 0
    tag:draw()
    love.graphics.pop()
end

function Game:skip_blind(index)
    local blind_index = tonumber(index)
    if not blind_index or blind_index < 1 then return false end

    local skip_id = self.skips and self.skips[blind_index]
    local tag_type = self:tag_type_for_id(skip_id)
    if tag_type then
        if type(self.tags) ~= "table" then self.tags = {} end
        self.skipsTaken = self.skipsTaken + 1
        self:ensure_skip_orbital_hand(blind_index)
        local orbital_idx = self.skip_tag_orbital_hand and self.skip_tag_orbital_hand[blind_index]
        if orbital_idx then
            self:addTag(tag_type, { orbital_hand_index = orbital_idx })
        else
            self:addTag(tag_type)
        end
    end
    self.current_blind_index = math.min(3, blind_index + 1)
    self.selected_blind_index = self.current_blind_index
    return true
end

function Game:try_gamepad_skip_blind()
    if self.STATE ~= self.STATES.BLIND_SELECT then return false end
    local blind_index = tonumber(self.current_blind_index)
    if not blind_index then return false end
    local skip_id = self.skips and self.skips[blind_index]
    if skip_id == nil or not self:is_blind_selectable(blind_index) then return false end
    self.active_tooltip_skip_blind_index = nil
    self.active_tooltip_blind_index = nil
    return self:skip_blind(blind_index) == true
end

function Game:draw_bottom_blind_select()
    local card_w, card_h = 98, 300
    local gap = 8
    local start_x = 6
    local y = 8
    self._blind_select_tap_rects = {}
    self._blind_skip_tag_tap_rects = {}
    self._blind_info_tap_rects = {}
    for i = 1, 3 do
        local def = self:get_blind_def(i)
        local x = start_x + (i - 1) * (card_w + gap)
        local selectable = self:is_blind_selectable(i)
        local target = self:get_blind_target(i, self.ante)
        local card_color = self.C.PANEL
        if not selectable then
            y = 44
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
        self._blind_info_tap_rects[i] = {
            x = x + 4,
            y = btn_y + selectHeight + 4,
            w = card_w - 8,
            h = 78,
            blind_index = i,
        }

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
        love.graphics.printf("Score at Least", tx, ty, scoreWidth, "center")
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

        -- Skip UI
        if def and def.id ~= "boss" then
            love.graphics.push()
            love.graphics.setFont(self.FONTS.PIXEL.SMALL)
            love.graphics.setColor(self.C.WHITE)
            local w = love.graphics.getFont():getWidth("or")
            love.graphics.print("or", tx + math.floor(blindWidth/2) - math.floor(w/2) + 4, ty + 44)

            -- Skip Box
            local p = 4
            local sx = x + p
            local sw = card_w - 2 * p
            local sy = ty + 54 + p
            local sh = 24 + 2 * p
            love.graphics.setColor(self.C.BLOCK.BACK)
            love.graphics.rectangle("fill", sx, sy, sw, sh, 4, 4)

            --Tag Icon
            p = 2
            local skip_id = self.skips and self.skips[i]
            if skip_id ~= nil then
                local tag_type = self:tag_type_for_id(skip_id)
                if tag_type then
                    local icon_scale = 0.85
                    local icon_x = sx + p
                    local icon_y = sy + p
                    self:draw_skip_tag_icon(tag_type, icon_x, icon_y, icon_scale)
                    local tag_probe = Tag(tag_type)
                    local icon_w = math.floor((tag_probe.w or 34) * icon_scale)
                    local icon_h = math.floor((tag_probe.h or 34) * icon_scale)
                    self._blind_skip_tag_tap_rects[i] = {
                        x = icon_x, y = icon_y, w = icon_w, h = icon_h, blind_index = i,
                    }
                end
            end

            --Button
            p = 4
            local buttonX = sx + 32 + p
            local buttonY = sy + p
            local buttonW = sw - 32 - 2*p
            local buttonH = sh - 2 * p
            local can_skip = selectable and (self.skips and self.skips[i] ~= nil)
            if can_skip then
                draw_rect_with_shadow(buttonX, buttonY, buttonW, buttonH, 4, 4, self.C.MULT, self.C.BLOCK.SHADOW, 2)
            else
                draw_rect_with_shadow(buttonX, buttonY, buttonW, buttonH, 4, 4, self.C.GREY, self.C.BLOCK.SHADOW, 2)
            end
            self._blind_skip_tap_rects = self._blind_skip_tap_rects or {}
            self._blind_skip_tap_rects[i] = { x = buttonX, y = buttonY, w = buttonW, h = buttonH, blind_index = i }
            love.graphics.setColor(self.C.WHITE)
            local buttonText = "Skip Blind (X)"
            love.graphics.print(buttonText, buttonX + math.floor(buttonW/2) - math.floor(love.graphics.getFont():getWidth(buttonText)/2), buttonY + math.floor(buttonH/2) - math.floor(love.graphics.getFont():getHeight(buttonText)/2))

            love.graphics.pop()
        end
        
    end

    self._boss_reroll_btn_rect = nil
    if (self:has_voucher("v_directors_cut") or self:has_voucher("v_retcon")) then
        local bw, bh = 70, 24
        local bx = 200 - bw - 6
        local by = 8
        local can_afford = self:can_afford_price(10)
        local lim_ok = true
        if self:has_voucher("v_directors_cut") and not self:has_voucher("v_retcon") then
            lim_ok = (tonumber(self.boss_rerolls_used_this_ante) or 0) < 1
        end
        local col = (can_afford and lim_ok) and self.C.GREEN or self.C.GREY
        if _G.draw_rect_with_shadow then
            draw_rect_with_shadow(bx, by, bw, bh, 4, 2, col, self.C.BLOCK.SHADOW, 1)
        else
            love.graphics.setColor(col)
            love.graphics.rectangle("fill", bx, by, bw, bh, 4, 4)
        end
        self._boss_reroll_btn_rect = { x = bx, y = by, w = bw, h = bh }
        love.graphics.setColor(self.C.WHITE)
        love.graphics.setFont(self.FONTS.PIXEL.SMALL)
        love.graphics.printf("Reroll $10", bx, by + 5, bw, "center")
    end
end

function Game:draw_shop_button(param)
    ShopUI.draw_shop_button(self, param)
end

function Game:draw_bottom_shop()
    ShopUI.draw_bottom_shop(self)
end

function Game:_draw_blind_info_tooltip()
    local blind_index = tonumber(self.active_tooltip_blind_index)
    if not blind_index then return end
    local rect = self._blind_info_tap_rects and self._blind_info_tap_rects[blind_index]
    if not rect then return end
    local title = self:get_blind_display_name(blind_index)
    local desc = self:get_blind_description(blind_index)
    local font = (self.FONTS and self.FONTS.PIXEL and self.FONTS.PIXEL.SMALL) or love.graphics.getFont()
    local resolved = TooltipDraw.resolved_lines_from_multiline(desc)
    TooltipDraw.draw_tooltip_layout(font, title, resolved, rect.x, rect.y, rect.w, rect.h)
end

function Game:_draw_skip_tag_tooltip()
    local blind_index = tonumber(self.active_tooltip_skip_blind_index)
    if not blind_index then return end
    local skip_id = self.skips and self.skips[blind_index]
    local info = skip_id ~= nil and self:get_skip_tag_tooltip(skip_id, blind_index) or nil
    local rect = self._blind_skip_tag_tap_rects and self._blind_skip_tag_tap_rects[blind_index]
    if not info or not rect then return end
    local title = tostring(info.name or "Tag")
    local desc = tostring(info.description or "")
    local font = (self.FONTS and self.FONTS.PIXEL and self.FONTS.PIXEL.SMALL) or love.graphics.getFont()
    local resolved = TooltipDraw.resolved_lines_from_multiline(desc)
    TooltipDraw.draw_tooltip_layout(font, title, resolved, rect.x, rect.y, rect.w, rect.h)
end

function Game:handle_blind_select_touch(x, y)
    for _, r in ipairs(self._blind_info_tap_rects or {}) do
        if self:_point_in_rect_simple(x, y, r) then
            local blind_index = tonumber(r.blind_index)
            if blind_index then
                if self.active_tooltip_blind_index == blind_index then
                    self.active_tooltip_blind_index = nil
                else
                    self.active_tooltip_blind_index = blind_index
                    self.active_tooltip_skip_blind_index = nil
                    self.active_tooltip_joker = nil
                    self.active_tooltip_card = nil
                    self.active_tooltip_consumable_index = nil
                end
                return true
            end
        end
    end

    for _, r in ipairs(self._blind_skip_tag_tap_rects or {}) do
        if self:_point_in_rect_simple(x, y, r) then
            local blind_index = tonumber(r.blind_index)
            if blind_index and self.skips and self.skips[blind_index] ~= nil then
                if self.active_tooltip_skip_blind_index == blind_index then
                    self.active_tooltip_skip_blind_index = nil
                else
                    self.active_tooltip_skip_blind_index = blind_index
                    self.active_tooltip_blind_index = nil
                    self.active_tooltip_joker = nil
                    self.active_tooltip_card = nil
                    self.active_tooltip_consumable_index = nil
                end
                return true
            end
        end
    end

    for _, r in ipairs(self._blind_skip_tap_rects or {}) do
        if self:_point_in_rect_simple(x, y, r) then
            local blind_index = tonumber(r.blind_index)
            local skip_id = self.skips and self.skips[blind_index]
            if blind_index and skip_id ~= nil and self:is_blind_selectable(blind_index) then
                self.active_tooltip_skip_blind_index = nil
                self.active_tooltip_blind_index = nil
                self:skip_blind(blind_index)
                return true
            end
        end
    end

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
            self.active_tooltip_skip_blind_index = nil
            self.active_tooltip_blind_index = nil
            return true
        end
    end
    self.active_tooltip_skip_blind_index = nil
    self.active_tooltip_blind_index = nil
    return false
end

function Game:draw_bottom_round_win()
    RoundWinUI.draw_bottom(self, self._round_win_display_lines)
end

function Game:draw_bottom_game_over()
    GameOverUI.draw_bottom(self)
end

function Game:draw_bottom_pause()
    local panel_x, panel_y, panel_w, panel_h = 24, 26, 272, 188
    if _G.draw_rect_with_shadow then
        draw_rect_with_shadow(panel_x, panel_y, panel_w, panel_h, 6, 3, self.C.BLOCK.BACK, self.C.BLOCK.SHADOW, 3)
    else
        love.graphics.setColor(self.C.PANEL)
        love.graphics.rectangle("fill", panel_x, panel_y, panel_w, panel_h, 6, 6)
    end

    local function draw_btn(r, label, color, focused)
        love.graphics.setColor(color)
        draw_rect_with_shadow(r.x, r.y, r.w, r.h, 4, 4, color, self.C.BLOCK.SHADOW, 2)
        if focused then
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", r.x + 0.5, r.y + 0.5, r.w - 1, r.h - 1)
        end
        love.graphics.setColor(self.C.WHITE)
        love.graphics.setFont(self.FONTS.PIXEL.MEDIUM)
        local ty = r.y + math.floor((r.h - love.graphics.getFont():getHeight()) * 0.5 + 0.5)
        love.graphics.printf(label, r.x, ty, r.w, "center")
    end

    local function is_pause_focused(kind, index)
        local targets = self:build_pause_focus_targets()
        local pause_focus = tonumber(self._pause_focus_index) or 1
        for i, t in ipairs(targets) do
            if i == pause_focus and t.kind == kind then
                if index == nil or t.index == index then return true end
            end
        end
        return false
    end

    if self._pause_show_settings then
        -- ===== SETTINGS PAGE =====
        love.graphics.setColor(self.C.WHITE)
        love.graphics.setFont(self.FONTS.PIXEL.MEDIUM)
        love.graphics.printf("Settings", panel_x, panel_y + 10, panel_w, "center")

        love.graphics.setColor(self.C.GREY)
        love.graphics.setFont(self.FONTS.PIXEL.SMALL)
        love.graphics.printf("Game Speed", panel_x, panel_y + 38, panel_w, "center")

        local speeds = { 0.5, 1, 1.5, 2, 2.5, 3}
        local speed_labels = { "x0.5", "x1", "x1.5", "x2", "x2.5", "x3"}
        local cur_speed = (self.SETTINGS and self.SETTINGS.GAMESPEED) or 1
        local sb_w = 38
        local sb_h = 28
        local sb_gap = 6
        local total_sb = #speeds * sb_w + (#speeds - 1) * sb_gap
        local sb_start_x = panel_x + math.floor((panel_w - total_sb) * 0.5 + 0.5)
        local sb_y = panel_y + 56
        self._pause_speed_rects = {}
        for i, spd in ipairs(speeds) do
            local rx = sb_start_x + (i - 1) * (sb_w + sb_gap)
            local r = { x = rx, y = sb_y, w = sb_w, h = sb_h, speed = spd }
            self._pause_speed_rects[i] = r
            local is_active = math.abs(cur_speed - spd) < 0.01
            local btn_color = is_active and self.C.ORANGE or self.C.PANEL
            love.graphics.setColor(btn_color)
            draw_rect_with_shadow(rx, sb_y, sb_w, sb_h, 4, 4, btn_color, self.C.BLOCK.SHADOW, 4)
            if is_active then
                love.graphics.setColor(self.C.WHITE)
            else
                love.graphics.setColor(self.C.DARK_WHITE or self.C.GREY)
            end
            love.graphics.setFont(self.FONTS.PIXEL.SMALL)
            local ty = sb_y + math.floor((sb_h - love.graphics.getFont():getHeight()) * 0.5 + 0.5)
            love.graphics.printf(speed_labels[i], rx, ty, sb_w, "center")
            if is_pause_focused("speed", i) then
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.setLineWidth(2)
                love.graphics.rectangle("line", rx + 0.5, sb_y + 0.5, sb_w - 1, sb_h - 1)
            end
        end

        love.graphics.setColor(self.C.WHITE)
        love.graphics.setFont(self.FONTS.PIXEL.SMALL)
        local speed_str = string.format("Current: x%.4g", cur_speed)
        love.graphics.printf(speed_str, panel_x, panel_y + 96, panel_w, "center")

        love.graphics.setColor(self.C.GREY)
        love.graphics.printf("Music Volume", panel_x, panel_y + 114, panel_w, "center")

        local track_x = panel_x + 36
        local track_w = panel_w - 72
        local track_y = panel_y + 136
        local knob_r = 7
        local vol = self:get_music_volume()
        local knob_x = track_x + (vol / 100) * track_w
        local prev_lw = love.graphics.getLineWidth()
        love.graphics.setColor(self.C.GREY)
        love.graphics.setLineWidth(2)
        love.graphics.line(track_x, track_y, track_x + track_w, track_y)
        love.graphics.setColor(self.C.WHITE)
        love.graphics.circle("fill", knob_x, track_y, knob_r)
        love.graphics.setLineWidth(prev_lw)
        self._pause_music_slider_rect = {
            x = track_x - knob_r,
            y = track_y - 14,
            w = track_w + knob_r * 2,
            h = 28,
            track_x = track_x,
            track_w = track_w,
            track_y = track_y,
        }

        -- Back button
        local back_w, back_h = 120, 28
        local back_x = panel_x + math.floor((panel_w - back_w) * 0.5 + 0.5)
        self._pause_back_rect = { x = back_x, y = panel_y + 156, w = back_w, h = back_h }
        draw_btn(self._pause_back_rect, "Back", self.C.MULT, is_pause_focused("back"))
    else
        -- ===== MAIN PAUSE PAGE =====
        love.graphics.setColor(self.C.WHITE)
        love.graphics.setFont(self.FONTS.PIXEL.MEDIUM)
        love.graphics.printf("Paused", panel_x, panel_y + 10, panel_w, "center")

        local btn_w, btn_h = 176, 28
        local btn_x = panel_x + math.floor((panel_w - btn_w) * 0.5 + 0.5)
        self._pause_continue_rect  = { x = btn_x, y = panel_y + 42,  w = btn_w, h = btn_h }
        self._pause_settings_rect  = { x = btn_x, y = panel_y + 78,  w = btn_w, h = btn_h }
        self._pause_new_run_rect   = { x = btn_x, y = panel_y + 114, w = btn_w, h = btn_h }
        self._pause_save_quit_rect = { x = btn_x, y = panel_y + 150, w = btn_w, h = btn_h }

        local can_save = not self:is_hand_scoring_active()
        draw_btn(self._pause_continue_rect,  "Continue",      self.C.GREEN, is_pause_focused("continue"))
        draw_btn(self._pause_settings_rect,  "Settings",      self.C.BOOSTER, is_pause_focused("settings"))
        draw_btn(self._pause_new_run_rect,   "New Run",        self.C.RED, is_pause_focused("new_run"))
        draw_btn(self._pause_save_quit_rect, "Save and Quit",  can_save and self.C.BLUE or self.C.GREY, is_pause_focused("save_quit"))

        if not can_save then
            love.graphics.setColor(self.C.GREY)
            love.graphics.setFont(self.FONTS.PIXEL.SMALL)
            love.graphics.printf("Finish scoring before saving.", panel_x, panel_y + 182, panel_w, "center")
        elseif self._pause_save_error then
            love.graphics.setColor(self.C.RED)
            love.graphics.setFont(self.FONTS.PIXEL.SMALL)
            love.graphics.printf(tostring(self._pause_save_error), panel_x + 8, panel_y + 182, panel_w - 16, "center")
        end
    end
end

function Game:continue_from_game_over()
    self._game_over_blind_label = nil
    self._game_over_score = nil
    self._game_over_target = nil
    self._game_over_ante = nil
    self._game_over_round = nil
    self._game_over_continue_rect = nil
    self._blind_resolution_pending = false
    local run_seed = os.time()
    if love and love.timer and love.timer.getTime then
        run_seed = run_seed + math.floor((love.timer.getTime() % 1) * 1000000)
    end
    self.SEED = run_seed
    math.randomseed(self.SEED)
    self:enter_main_menu()
end

--- Tear down run objects and textures before returning to the main menu.
function Game:clear_run_assets_for_main_menu()
    self.dragging = nil
    self:clear_bottom_tooltips()

    if self.booster_session then
        if self.booster_session.hand_for_tarot then
            if self.hand and self.hand.return_all_cards_to_deck_draw_pile then
                self.hand:return_all_cards_to_deck_draw_pile()
            elseif self.hand and self.hand.clear then
                self.hand:clear()
            end
        end
        self:_booster_destroy_choice_nodes()
        self.booster_session = nil
        self._booster_return_state = nil
    end

    if self.hand and self.hand.clear then
        self.hand:clear()
    end

    if type(self.jokers) == "table" then
        for i = #self.jokers, 1, -1 do
            self:remove_owned_joker_at(i, true)
        end
    end
    self.jokers = {}
    self:clear_joker_shared_picks()

    if type(self.consumables) == "table" then
        for i = #self.consumables, 1, -1 do
            self:remove_consumable_at(i)
        end
    end
    self.consumables = {}
    if type(self.consumable_nodes) == "table" then
        for i = #self.consumable_nodes, 1, -1 do
            local node = self.consumable_nodes[i]
            if node then self:remove(node) end
            table.remove(self.consumable_nodes, i)
        end
    end
    self.consumable_nodes = {}

    if self.clear_shop_offer_nodes then
        self:clear_shop_offer_nodes()
    end
    self.shop_offer_nodes = {}
    self.shop_offers = {}

    if self.clear_shop_booster_nodes then
        self:clear_shop_booster_nodes()
    end
    self.shop_booster_nodes = {}
    self.shop_booster_offers = {}

    if self.clear_shop_voucher_nodes then
        self:clear_shop_voucher_nodes()
    end
    self.shop_voucher_nodes = {}
    self.shop_voucher_offers = {}

    if Deck then
        self.deck = Deck()
    else
        self.deck = nil
    end
    self.pending_discard = {}
    self:_clear_pending_discard_nodes()
    self.jokers_on_bottom = false

    local run_atlases = { "Tarot", "cards_1", "cards_2", "Booster", "Voucher", "stickers" }
    for _, name in ipairs(run_atlases) do
        if self.unload_asset_atlas then
            self:unload_asset_atlas(name)
        end
    end

    if type(self._atlas_owner_counts) == "table" then
        local keys = {}
        for name in pairs(self._atlas_owner_counts) do
            keys[#keys + 1] = name
        end
        for _, name in ipairs(keys) do
            self._atlas_owner_counts[name] = nil
            if self.unload_joker_sprite then
                self:unload_joker_sprite(name)
            end
        end
    end
end

function Game:enter_main_menu()
    self.STAGE = self.STAGES.MAIN_MENU
    self._menu_sub_state = "main"
    self._main_menu_start_rect = nil
    self._main_menu_continue_rect = nil
    self._main_menu_how_to_play_rect = nil
    self._how_to_play_back_rect = nil
    self._how_to_play_rects = nil
    self._delete_save_confirm = false
    self._menu_focus_index = 1
    self._pause_prev_state = nil
    self._blind_resolution_pending = false
    self.active_tooltip_card = nil
    self.active_tooltip_joker = nil
    self.active_tooltip_consumable_index = nil
    self.active_tooltip_shop_voucher_slot = nil

    self:clear_run_assets_for_main_menu()
    if self.ensure_animation_atlas_loaded then
        self:ensure_animation_atlas_loaded("menu")
    end
    self:set_state(self.STATES.MENU)
end

function Game:start_run_from_main_menu()
    if self.unload_asset_atlas then
        self:unload_asset_atlas("balatro")
    end
    if self.unload_animation_atlas then
        self:unload_animation_atlas("menu")
    end
    -- Starting a new run should always clear any existing run objects (especially owned jokers).
    if type(self.jokers) == "table" then
        for i = #self.jokers, 1, -1 do
            self:remove_owned_joker_at(i,true)
        end
    end
    if type(self.consumables) == "table" then
        for i = #self.consumables, 1, -1 do
            self:remove_consumable_at(i)
        end
    end

    self:reset_hand_levels()
    
    if self.hand and self.hand.clear then
        self.hand:clear()
    end
    if Deck then
        self.deck = Deck()
    end
    -- Fresh run: new seed and RNG.
    local run_seed = os.time()
    if love and love.timer and love.timer.getTime then
        run_seed = run_seed + math.floor((love.timer.getTime() % 1) * 1000000)
    end
    self.SEED = run_seed
    math.randomseed(self.SEED)
    
    -- Reset shop RNG/queue so offers change with the new seed.
    self.shop_offer_queue = nil
    self.vouchers = {}
    self._shop_rng_state = nil
    self._pause_prev_state = nil
    self._pause_save_error = nil
    self:initialize_run_loop()
end

function Game:handle_round_win_touch(x, y)
    return RoundWinUI.handle_touch(self, x, y)
end

function Game:handle_shop_touch(x, y)
    return ShopUI.handle_touch(self, x, y)
end

function Game:update(dt)
    if self.STATE == self.STATES.PAUSED then
        return
    end
    if self.sync_shoulder_input then
        self:sync_shoulder_input()
    end
    if self.update_sweep_seed then
        self:update_sweep_seed()
    end
    if self.update_dpad_horizontal_repeat then
        self:update_dpad_horizontal_repeat(dt)
    end
    if self._deck_view_open then
        for _, node in ipairs(self._deck_view_nodes or {}) do
            if node and node.update then
                node:update(dt)
            end
        end
        self:check_collisions(dt)
        return
    end
    self:_update_joker_emit_queue(dt)
    if self.STATE == self.STATES.ROUND_EVAL then
        self:update_round_win_eval(dt)
    end
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

    local to_remove = {}
    for i, popup in ipairs(self.popups or {}) do
        if popup.update then
            popup:update(dt)
            if popup.remove or popup.time <= 0 then
                table.insert(to_remove, i)
            end
        end
    end

    -- Remove in reverse order so indices stay valid
    for i = #to_remove, 1, -1 do
        table.remove(self.popups, to_remove[i])
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

--- Topmost owned joker under (x, y), or nil. Booster pack choice cards overlap the joker row; `get_node_at`
--- would prefer those nodes, so input that should hit owned jokers must test them first.
function Game:get_owned_joker_at(x, y)
    if not self.jokers then return nil end
    for i = #self.jokers, 1, -1 do
        local j = self.jokers[i]
        if j and j.states and j.states.click.can and self:point_in_rect(x, y, j) then
            return j
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
    self.joker_slot_w = self.joker_slot_w or 70
    self.joker_slot_h = self.joker_slot_h or 94
    self.joker_slot_gap = self.joker_slot_gap or 8
    self.joker_slot_y_top = self.joker_slot_y_top or 124
    self.joker_slot_y_bottom = self.joker_slot_y_bottom or 20

    local BOTTOM_SCREEN_W = 320
    local TOP_SCREEN_W = 400
    local n = #(self.jokers or {})
    local eff_n = math.max(n, 1)
    local card_w = self.joker_slot_w or 70
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

function Game:joker_base_capacity() 
    local base = 5
    if self:has_voucher("v_antimatter") then
        base = base + 1
    end
    base = base + (self.deck_joker_slots or 0)
    return base
end

--- `joker_base_capacity` + one slot per owned Joker with Negative edition.
function Game:refresh_joker_capacity_from_negatives()
    local bonus = 0
    for _, j in ipairs(self.jokers or {}) do
        if j and Joker.normalize_edition(j.edition) == "negative" then
            bonus = bonus + 1
        end
    end
    self.joker_capacity = self:joker_base_capacity() + bonus
    self:recompute_joker_slot_layout()
    self:_apply_joker_layout()
    self:sync_jokers_interactivity()
end

function Game:init_jokers()
    -- Owned Jokers live in `self.jokers` (packed left-to-right).
    self.jokers = {}

    if not Joker then return end

    self.joker_capacity = self:joker_base_capacity()

    self.jokers_on_bottom = false
    self.jokers_sliding = false
    self.jokers_slide_time_left = 0

    self.joker_slot_w, self.joker_slot_h = 70, 94
    self.joker_slot_gap = 8
    self.joker_slot_y_top = 124 - 10
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
end

--- Jokers with per-type random targets (duplicate copies share the same pick).
local JOKER_SHARED_RANDOM_IDS = {
    j_ancient_joker = true,
    j_castle = true,
    j_mail = true,
    j_idol = true,
    j_todo_list = true,
}

function Game:clear_joker_shared_picks()
    self.joker_shared_picks = {}
end

function Game:uses_joker_shared_picks(def_id)
    return type(def_id) == "string" and JOKER_SHARED_RANDOM_IDS[def_id] == true
end

function Game:get_joker_shared_pick(def_id)
    if not self:uses_joker_shared_picks(def_id) then return nil end
    self.joker_shared_picks = self.joker_shared_picks or {}
    return self.joker_shared_picks[def_id]
end

function Game:propagate_joker_shared_picks(def_id)
    local picks = self:get_joker_shared_pick(def_id)
    if type(picks) ~= "table" then return end
    for _, j in ipairs(self.jokers or {}) do
        if j and j.def and j.def.id == def_id then
            for k, v in pairs(picks) do
                j[k] = v
            end
        end
    end
end

function Game:set_joker_shared_picks(def_id, picks)
    if not self:uses_joker_shared_picks(def_id) or type(picks) ~= "table" then return end
    self.joker_shared_picks = self.joker_shared_picks or {}
    local slot = self.joker_shared_picks[def_id]
    if type(slot) ~= "table" then
        slot = {}
        self.joker_shared_picks[def_id] = slot
    end
    for k, v in pairs(picks) do
        slot[k] = v
    end
    self:propagate_joker_shared_picks(def_id)
end

function Game:roll_joker_shared_picks(def_id)
    if not self:uses_joker_shared_picks(def_id) then return nil end
    local suits = { "Hearts", "Clubs", "Diamonds", "Spades" }

    if def_id == "j_ancient_joker" then
        return { random_suit = suits[math.random(1, #suits)] }
    end

    if def_id == "j_castle" then
        local deck = self.deck
        if deck and deck.random_card then
            local card = deck:random_card()
            if card and card.suit then
                return { random_suit = card.suit }
            end
        end
        return { random_suit = suits[math.random(1, #suits)] }
    end

    if def_id == "j_mail" then
        return { random_rank = math.random(2, 14) }
    end

    if def_id == "j_idol" then
        local deck = self.deck
        if deck and deck.random_card then
            local card = deck:random_card()
            if card then
                return { random_rank = card.rank, random_suit = card.suit }
            end
        end
        return { random_rank = math.random(2, 14), random_suit = suits[math.random(1, #suits)] }
    end

    if def_id == "j_todo_list" then
        local handlist = self.handlist or {}
        if #handlist == 0 then return nil end
        local found = false
        local hand_name = nil
        while not found do
            local pos = math.random(1, #handlist)
            if pos < 4 then
                if self.hand_play_counts and self.hand_play_counts[pos] and self.hand_play_counts[pos] > 0 then
                    found = true
                    hand_name = handlist[pos]
                end
            else
                found = true
                hand_name = handlist[pos]
            end
        end
        return { random_hand = hand_name }
    end

    return nil
end

function Game:ensure_joker_shared_picks(def_id)
    if not self:uses_joker_shared_picks(def_id) then return nil end
    local existing = self:get_joker_shared_pick(def_id)
    if type(existing) == "table" then return existing end
    local picks = self:roll_joker_shared_picks(def_id)
    if picks then
        self:set_joker_shared_picks(def_id, picks)
        return picks
    end
    return nil
end

function Game:apply_joker_shared_picks_to_joker(joker)
    local def_id = joker and joker.def and joker.def.id
    if not def_id then return end
    local picks = self:ensure_joker_shared_picks(def_id)
    if type(picks) ~= "table" then return end
    for k, v in pairs(picks) do
        joker[k] = v
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

    if not self.joker_capacity then self.joker_capacity = self:joker_base_capacity() end
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
    local cap_after = self:joker_base_capacity() + neg_owned + (new_is_neg and 1 or 0)
    if #self.jokers >= cap_after then return false end

    local j = Joker(0, 0, self.joker_slot_w, self.joker_slot_h, def, merged)
    self:apply_joker_shared_picks_to_joker(j)
    table.insert(self.jokers, j)
    self:add(j)

    self:refresh_joker_capacity_from_negatives()

    self:discover_item(def_id)

    local edition = Joker.normalize_edition(merged.edition)
    if edition then
        self:discover_item("edition_" .. edition)
    end

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

--- Max debt while Credit Card is owned (from `JOKER_DEFS.j_credit_card.config.extra`, default 20).
function Game:get_credit_card_debt_limit()
    local d = JOKER_DEFS and JOKER_DEFS.j_credit_card
    local c = type(d) == "table" and d.config and d.config.extra
    return math.max(1, math.floor(tonumber(c) or 20))
end

function Game:has_credit_card()
    return self:hasJoker("j_credit_card")
end

--- Whether the player can pay `cost` from the shop (buy / reroll). Free costs (0) always allowed.
--- With Credit Card: may spend until money reaches -debt_limit.
--- Without Credit Card: if money is negative (e.g. sold Credit Card while in debt), no paid purchases until money is >= 0.
function Game:can_afford_price(cost)
    cost = math.max(0, tonumber(cost) or 0)
    if cost <= 0 then
        return true
    end
    local m = tonumber(self.money) or 0
    if self:has_credit_card() then
        local lim = self:get_credit_card_debt_limit()
        return (m - cost) >= -lim
    end
    if m < 0 then
        return false
    end
    return m >= cost
end

--- Floor for money when losing it to bosses etc. (-debt_limit with Credit Card, else 0).
function Game:get_money_loss_floor()
    if self:has_credit_card() then
        return -self:get_credit_card_debt_limit()
    end
    return 0
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
    if self.hand and type(self.hand._draw_queue) == "table" then
        count_in(self.hand._draw_queue)
    end
    return total
end

function Game:count_cards_in_deck(predicate)
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
    end
    return total
end

function Game:_apply_joker_layout()
    if not self.jokers then return end

    local TOP_SCREEN_W = 400
    local BOTTOM_SCREEN_W = 320
    local slot_w = self.joker_slot_w or 70
    local slot_h = self.joker_slot_h or 94
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

function Game:prepare_joker_event_ctx(event_name, ctx)
    if type(ctx) ~= "table" then ctx = {} end
    ctx.event_name = event_name
    if ctx.event == nil then
        ctx.event = event_name
    end
    return ctx
end

--- All owned jokers sorted left-to-right with active-slot filtering.
function Game:_collect_jokers_in_slot_order()
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

--- All owned jokers sorted left-to-right (for per-joker edition steps on `on_hand_scored`).
function Game:collect_all_jokers_sorted()
    return self:_collect_jokers_in_slot_order()
end

--- Jokers in slot order (left-to-right) that match `event_name` and have `apply_effect`.
---@param event_name string
---@param ctx table
---@return table[]
function Game:collect_matching_jokers(event_name, ctx)
    local out = {}
    if type(event_name) ~= "string" or event_name == "" then return out end
    if type(ctx) ~= "table" then ctx = {} end

    for _, j in ipairs(self:_collect_jokers_in_slot_order()) do
        if j and j.matches_trigger and j:matches_trigger(event_name, ctx) and j.apply_effect then
            table.insert(out, j)
        end
    end
    return out
end

--- Sum extra scoring passes from Red Seal (once) and each joker's `query_retrigger` (Balatro-style additive retriggers).
--- `retrigger_ctx` should include `card_node` (or `retrigger_card`), `played_cards` when scoring the play area, and `held` is set from the `held` argument.
---@param held boolean
---@param retrigger_ctx table|nil
---@return number
function Game:sum_retrigger_extras(held, retrigger_ctx)
    if type(retrigger_ctx) ~= "table" then return 0 end
    retrigger_ctx.held = not not held
    local card = retrigger_ctx.card_node or retrigger_ctx.retrigger_card
    local R = 0
    if card and card.seal == "red" then
        R = R + 1
    end

    local skip = {}
    local boss_id = self:get_active_boss_blind_id()
    if boss_id == "bl_final_heart" then
        local blocked = tonumber(self.boss_runtime and self.boss_runtime.crimson_disabled_joker) or -1
        local sorted = {}
        if self.jokers and type(self.jokers) == "table" then
            for _, j in ipairs(self.jokers) do
                if j then table.insert(sorted, j) end
            end
        end
        table.sort(sorted, function(a, b)
            local ax = (a.T and a.T.x) or (a.VT and a.VT.x) or 0
            local bx = (b.T and b.T.x) or (b.VT and b.VT.x) or 0
            return ax < bx
        end)
        if blocked >= 1 and blocked <= #sorted then
            skip[sorted[blocked]] = true
        end
    end

    if not self.jokers or type(self.jokers) ~= "table" then return R end
    for _, j in ipairs(self.jokers) do
        if j and not skip[j] and j.query_retrigger then
            R = R + (tonumber(j:query_retrigger(retrigger_ctx)) or 0)
        end
    end
    return R
end

--- Dispatch `event_name` to each playing-card node currently in the hand (`Card:emit_hand_event`).
--- Used for `"on_round_end"` before the hand is discarded (e.g. Gold enhancement, Blue seal).
---@param event_name string
---@param ctx table|nil
function Game:emit_hand_cards_event(event_name, ctx)
    if type(event_name) ~= "string" or event_name == "" then return end
    if not self.hand or not self.hand.card_nodes then return end
    ctx = type(ctx) == "table" and ctx or {}
    ctx.event_name = event_name
    ctx.event = ctx.event or event_name
    for _, node in ipairs(self.hand.card_nodes) do
        if node and node.emit_hand_event then
            node:emit_hand_event(event_name, ctx)
        end
    end
end

---Emit a joker event to all jokers and apply their effects to the context.
---`ctx` is a mutable table that joker effects can update (e.g. ctx.chips/ctx.mult).
---@param event_name string
---@param ctx table|nil
function Game:emit_joker_event(event_name, ctx)
    if not self.jokers or type(self.jokers) ~= "table" then return end
    if type(event_name) ~= "string" or event_name == "" then return end
    ctx = self:prepare_joker_event_ctx(event_name, ctx)

    if event_name == "on_hand_scored" then
        for _, j in ipairs(self:collect_all_jokers_sorted()) do
            if j and j.apply_edition_on_hand_scored then
                j:apply_edition_on_hand_scored(ctx)
            end
            self:_sync_joker_ctx(ctx)
            if j and j.matches_trigger and j:matches_trigger(event_name, ctx) and j.apply_effect then
                j:apply_effect(ctx)
                self:_sync_joker_ctx(ctx)
            end
        end
        self:_apply_observatory_voucher_to_hand_scored_ctx(ctx)
        return
    end

    for _, j in ipairs(self:collect_matching_jokers(event_name, ctx)) do
        self:_sync_joker_ctx(ctx)
        if j and j.apply_effect then
            j:apply_effect(ctx)
            self:_sync_joker_ctx(ctx)
        end
    end

    if event_name == "on_joker_sold" and type(ctx) == "table" then
        local sold = ctx.joker
        if sold and sold.matches_trigger and sold:matches_trigger(event_name, ctx) and sold.apply_effect then
            sold:apply_effect(ctx)
        end
    end
end

--- Playing cards removed from the run (destroyed, not sent to discard). `destroyed_cards` is an array of logical card data tables.
---@param destroyed_cards table[]
function Game:emit_on_destroy_cards(destroyed_cards)
    if type(destroyed_cards) ~= "table" or #destroyed_cards == 0 then return end
    self:emit_joker_event("on_destroy", {
        destroyed_cards = destroyed_cards,
    })
end

--- Permanent playing cards added to the run deck (shop, boosters, spectrals, Certificate, DNA, etc.).
--- Does not fire when recycling the hand back into the draw pile.
---@param count number|nil
function Game:notify_cards_added_to_deck(count)
    local n = math.floor(tonumber(count) or 0)
    if n <= 0 then return end
    self:emit_joker_event("on_cards_added_to_deck", { count = n })
end

function Game:_sync_joker_ctx(ctx)
    if type(ctx) ~= "table" then return end
    self.selectedHandChips = tonumber(ctx.chips) or self.selectedHandChips
    self.selectedHandMult = tonumber(ctx.mult) or self.selectedHandMult
end

function Game:_planet_consumable_id_for_most_played_hand()
    if type(self.handlist) ~= "table" or type(self.hand_play_counts) ~= "table" or not CONSUMABLE_DEFS then
        return nil
    end
    local best_i, best_c = nil, -1
    for i, _ in ipairs(self.handlist) do
        local c = tonumber(self.hand_play_counts[i]) or 0
        if c > best_c then
            best_c = c
            best_i = i
        end
    end
    if not best_i then return nil end
    local hand_name = self.handlist[best_i]
    if type(hand_name) ~= "string" then return nil end
    for id, def in pairs(CONSUMABLE_DEFS) do
        if type(def) == "table" and def.kind == "planet" and def.hand == hand_name and type(id) == "string" then
            return id
        end
    end
    return nil
end

function Game:_apply_observatory_voucher_to_hand_scored_ctx(ctx)
    if not self:has_voucher("v_observatory") then return end
    if type(ctx) ~= "table" or type(self.consumables) ~= "table" or not CONSUMABLE_DEFS then return end
    local hand_type = ctx.hand_type
    if type(hand_type) ~= "string" then return end
    for _, c in ipairs(self.consumables) do
        local id = c and c.id
        local def = id and CONSUMABLE_DEFS[id]
        if type(def) == "table" and def.kind == "planet" and def.hand == hand_type then
            ctx.mult = (tonumber(ctx.mult) or 1) * 1.5
            self:_sync_joker_ctx(ctx)
            return
        end
    end
end

--- True while a staggered joker batch (from `begin_joker_emit`) is still resolving.
function Game:joker_emit_busy()
    return self._joker_emit_queue ~= nil
end

--- Apply one joker from the stagger queue and sync chips/mult to `G`.
--- Returns true if the current joker actually triggered, false otherwise.
function Game:_apply_one_joker_emit()
    local q = self._joker_emit_queue
    if not q or type(q.list) ~= "table" then
        self._joker_emit_queue = nil
        self._joker_emit_timer = 0
        return false
    end
    local j = q.list[self._joker_emit_next]
    local did_trigger = false
    if j then
        q.ctx = self:prepare_joker_event_ctx(q.event_name, q.ctx)
        if q.event_name == "on_hand_scored" and j.apply_edition_on_hand_scored then
            j:apply_edition_on_hand_scored(q.ctx)
        end
        self:_sync_joker_ctx(q.ctx)
        if j.apply_effect then
            if q.pre_matched == true or (j.matches_trigger and q.event_name and j:matches_trigger(q.event_name, q.ctx)) then
                j:apply_effect(q.ctx)
                did_trigger = true
            end
        end
        self:_sync_joker_ctx(q.ctx)
    end
    self._joker_emit_next = self._joker_emit_next + 1
    if self._joker_emit_next > #q.list then
        if q.event_name == "on_hand_scored" and q.ctx then
            self:_apply_observatory_voucher_to_hand_scored_ctx(q.ctx)
        end
        self._joker_emit_queue = nil
        self._joker_emit_timer = 0
    end
    return did_trigger
end

--- Resolve matching jokers left-to-right; only add the stagger delay after a joker actually triggers.
--- Returns true if the queued sequence should pause for a later trigger (caller should wait until `joker_emit_busy()` is false).
---@param event_name string
---@param ctx table|nil
---@return boolean
function Game:begin_joker_emit(event_name, ctx)
    local pre_matched = false
    local list
    if event_name == "on_hand_scored" then
        list = self:collect_all_jokers_sorted()
    else
        list = self:collect_matching_jokers(event_name, ctx)
        pre_matched = true
    end
    if #list == 0 then return false end

    ctx = self:prepare_joker_event_ctx(event_name, ctx)
    self._joker_emit_queue = { list = list, ctx = ctx, event_name = event_name, pre_matched = pre_matched }
    self._joker_emit_next = 1
    self._joker_emit_timer = 0

    local had_trigger = false
    local did_trigger = self:_apply_one_joker_emit()
    if did_trigger then
        had_trigger = true
    end

    while self._joker_emit_queue and self._joker_emit_next <= #self._joker_emit_queue.list do
        local next_did_trigger = self:_apply_one_joker_emit()
        if next_did_trigger then
            had_trigger = true
            break
        end
        if self._joker_emit_queue == nil then
            break
        end
    end

    if not had_trigger then
        self._joker_emit_queue = nil
        self._joker_emit_timer = 0
        self._joker_emit_next = nil
        return false
    end

    return true
end

function Game:_update_joker_emit_queue(dt)
    if not self._joker_emit_queue then return end
    self._joker_emit_timer = self._joker_emit_timer + dt
    local interval = tonumber(self.JOKER_EMIT_INTERVAL) or 0.18
    if self._joker_emit_timer < interval then
        return
    end

    self._joker_emit_timer = 0
    local did_trigger = self:_apply_one_joker_emit()
    if not did_trigger then
        while self._joker_emit_queue and self._joker_emit_next <= #self._joker_emit_queue.list do
            local next_did_trigger = self:_apply_one_joker_emit()
            if next_did_trigger or self._joker_emit_queue == nil then
                break
            end
        end
    end
end

--- End Round — call once when the current round finishes (e.g. blind beaten).
--- Discards the hand, merges draw + discard piles, shuffles into the draw pile, then refills the hand.
function Game:_clear_pending_discard_nodes()
    for _, entry in ipairs(self.pending_discard or {}) do
        if entry and entry.node then
            self:remove(entry.node)
        end
    end
    self.pending_discard = {}
end

function Game:recycle_full_deck()
    if self.hand then
        self.hand._play_sequence = nil
    end
    self:_clear_pending_discard_nodes()

    local hand_cards, hand_queue = {}, {}
    if self.hand then
        if self.hand.sync_cards_from_nodes then
            self.hand:sync_cards_from_nodes()
        end
        hand_cards = self.hand.cards or {}
        hand_queue = self.hand._draw_queue or {}
        if self.hand.clear then
            self.hand:clear()
        end
    end

    local deck = self.deck
    if deck and deck.recycle_all then
        deck:recycle_all(hand_cards, hand_queue)
    elseif deck and deck.end_round then
        for _, c in ipairs(hand_queue) do
            if deck.push_discard then deck:push_discard(c) end
        end
        for _, c in ipairs(hand_cards) do
            if deck.push_discard then deck:push_discard(c) end
        end
        deck:end_round()
    end
end

function Game:end_round()
    self:recycle_full_deck()
    if self.hand and self.hand.fill_from_deck then
        self.hand:fill_from_deck()
    end
end

--- After beating a blind: return all cards to the deck and reshuffle; hand stays empty until the next blind starts.
function Game:recycle_full_deck_after_blind_win()
    self:recycle_full_deck()
end

function Game:prepare_hand_for_new_blind()
    if not self.deck and Deck then
        self.deck = Deck()
    end

    data = {
        blind_name = self.current_blind_name,
        is_boss_blind = (tonumber(self.current_blind_index) == 3),
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
    self:reset_gamepad_nav()
    self:ensure_dpad_cursor()

    self:emit_joker_event("on_round_begin", {})
end

function Game:initialize_run_loop()
    self:clear_joker_shared_picks()
    self.STAGE = self.STAGES.RUN
    self.ante = 1
    self.round = 1
    self.money = 4
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
    self.shop_booster_offers = {}
    self.shop_reroll_count = 0
    self.vouchers = {}
    self.shop_voucher_offers = {}
    self.shop_voucher_nodes = {}
    self.shop_booster_nodes = {}
    self.shop_voucher_bought_pending_boss = false
    self.active_tooltip_shop_voucher_slot = nil
    self.hand_size_delta_voucher = 0
    self.voucher_hands_delta = 0
    self.boss_rerolls_used_this_ante = 0
    self:reset_bosses_used_cycle()
    self.hand_play_counts = {}
    self.blind_hand_play_counts = {}
    self.tarots_used = 0
    self.handsPlayed = 0
    self.discardsUnused = 0
    self.skipsTaken = 0
    self._endless_mode = false
    self.hand_size_delta_spectral = 0
    self.hand_size_delta_juggle = 0
    self:reset_run_stats()
    
    if not self.hand and Hand then
        self.hand = Hand(self)
    end
    if self.hand and self.hand.clear then
        self.hand:clear()
    end
    self.consumables = {}
    self.tags = {}
    self.last_consumable_use_id = nil
    G:apply_deck_config(G._pending_deck_id   or "b_red")
    G:apply_stake_config(G._pending_stake_id or "stake_white")
    self:init_shop_offer_queue()
    self:roll_skips()
    self:set_state(self.STATES.BLIND_SELECT)
    self.joker_pool_replacements = {}
end

function Game:enter_blind_select()
    self:set_state(self.STATES.BLIND_SELECT)
    self.active_tooltip_skip_blind_index = nil
    self.active_tooltip_blind_index = nil
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
    if self.hand and self.hand.return_all_cards_to_deck_draw_pile then
        self.hand:return_all_cards_to_deck_draw_pile()
    elseif self.hand and self.hand.clear then
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
        if self.current_boss_blind_id then
            self:discover_item(self.current_boss_blind_id)
        end
    elseif idx == 1 then
        self:discover_item("bl_small")
    elseif idx == 2 then
        self:discover_item("bl_big")
    end
    local juggle_bonus = 0
    for i = #self.tags, 1, -1 do
        local tag = self.tags[i]
        if tag and tag.type == "juggle" then
            juggle_bonus = juggle_bonus + 3
            self:removeTag(i)
        end
    end
    if juggle_bonus > 0 then
        self.hand_size_delta_juggle = (tonumber(self.hand_size_delta_juggle) or 0) + juggle_bonus
    end
    self.hands = self:get_effective_hands_per_round()
    self.discards = self:get_effective_discards_per_round()
    self.blind_hand_play_counts = {}
    self.round_score = 0
    self.last_hand_score = 0
    self._blind_resolution_pending = false
    self:boss_reset_for_new_blind()
    self:prepare_hand_for_new_blind()

    return true
end

function Game:advance_after_shop()
    if self._last_completed_blind_was_boss then
        self.boss_rerolls_used_this_ante = 0
        if self.current_boss_blind_id then
            self:mark_boss_used(self.current_boss_blind_id)
        end
        self.ante = (tonumber(self.ante) or 1) + 1
        self._ante_played_card_uids = {}
        self.current_boss_blind_id = nil
        self.current_blind_index = 1
        self:roll_skips()
    else
        self.current_blind_index = math.min(3, (tonumber(self.current_blind_index) or 1) + 1)
    end
    self.selected_blind_index = self.current_blind_index
    self.round = (tonumber(self.round) or 0) + 1
    self._last_completed_blind_was_boss = false
    self:enter_blind_select()
end

function Game:continue_from_shop()
    self._shop_reroll_base_cost_override = nil
    self.hand_size_delta_juggle = 0
    self:clear_shop_selection()
    self:reset_gamepad_nav()
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

function Game:has_voucher(voucher_id)
    if type(voucher_id) ~= "string" or voucher_id == "" then return false end
    local vs = self.vouchers
    if type(vs) == "table" then
        if vs[voucher_id] == true then return true end
        for _, v in ipairs(vs) do
            if v == voucher_id then return true end
        end
    end
    return false
end

function Game:_voucher_already_owned(id)
    return self:has_voucher(id)
end

--- Shop discount: Liquidation overrides Clearance.
function Game:get_shop_discount_multiplier()
    if self:has_voucher("v_liquidation") then return 0.5 end
    if self:has_voucher("v_clearance_sale") then return 0.75 end
    return 1
end

function Game:apply_shop_discount_to_price(base)
    local p = math.max(0, math.floor(tonumber(base) or 0))
    local m = self:get_shop_discount_multiplier()
    return math.max(0, math.floor(p * m + 0.0001))
end

function Game:_shop_queue_tarot_planet_weights()
    local t, pl = 4, 4
    if self:has_voucher("v_tarot_tycoon") then
        t = 32
    elseif self:has_voucher("v_tarot_merchant") then
        t = 9.6
    end
    if self:has_voucher("v_planet_tycoon") then
        pl = 32
    elseif self:has_voucher("v_planet_merchant") then
        pl = 9.6
    end
    return t, pl
end

function Game:_roll_shop_playing_card_offer()
    if not self:has_voucher("v_magic_trick") then return nil end
    local suits = { "Hearts", "Clubs", "Diamonds", "Spades" }
    local rank = self:_shop_rand_int(2, 14)
    local suit = suits[self:_shop_rand_int(1, #suits)]
    local data = { rank = rank, suit = suit, enhancement = nil, seal = nil }
    if self:has_voucher("v_illusion") then
        if self:_shop_rand_int(1, 100) <= 40 then
            local enhs = { "bonus", "mult", "wild", "glass", "steel", "gold", "lucky" }
            data.enhancement = enhs[self:_shop_rand_int(1, #enhs)]
        end
        if self:_shop_rand_int(1, 100) <= 25 then
            local seals = { "gold", "red", "blue", "purple" }
            data.seal = seals[self:_shop_rand_int(1, #seals)]
        end
        if self:_shop_rand_int(1, 100) <= 30 then
            local r = self:_shop_rand_int(1, 100)
            local ed = nil
            if r <= 20 then ed = "foil"
            elseif r <= 45 then ed = "holo"
            elseif r <= 70 then ed = "polychrome"
            end
            if ed then
                data.modifier = { edition = ed }
            end
        end
    end
    local rank_name = tostring(rank)
    local name = string.format("%s %s", rank_name, suit)
    local base_price = 4
    return {
        kind = "playing_card",
        id = "playing_card",
        name = name,
        price = self:apply_shop_discount_to_price(base_price),
        card_data = data,
    }
end

--- Eligible unowned voucher ids, excluding any already listed in `exclude_ids`.
function Game:_shop_voucher_candidate_ids(exclude_ids)
    exclude_ids = exclude_ids or {}
    local candidates = {}
    if type(VOUCHER_DEFS) ~= "table" then return candidates end
    for vid, def in pairs(VOUCHER_DEFS) do
        if type(def) == "table" and type(vid) == "string" and not exclude_ids[vid] then
            if self:_voucher_already_owned(vid) then
                -- skip
            else
                local tier = tonumber(def.tier) or 1
                if tier == 2 then
                    local req = def.depends_on
                    if type(req) == "string" and req ~= "" and self:has_voucher(req) then
                        candidates[#candidates + 1] = vid
                    end
                else
                    candidates[#candidates + 1] = vid
                end
            end
        end
    end
    table.sort(candidates)
    return candidates
end

function Game:_make_shop_voucher_offer(vid)
    local d = VOUCHER_DEFS and VOUCHER_DEFS[vid]
    local price = tonumber(d and d.price) or 10
    price = self:apply_shop_discount_to_price(price)
    return {
        id = vid,
        name = (d and d.name) or vid,
        description = (d and d.description) or "",
        price = price,
    }
end

--- Pick one unowned voucher not already in `shop_voucher_offers`.
---@return table|nil offer
function Game:_roll_one_shop_voucher_offer()
    local exclude = {}
    for _, offer in ipairs(self.shop_voucher_offers or {}) do
        if offer and offer.id then
            exclude[offer.id] = true
        end
    end
    local candidates = self:_shop_voucher_candidate_ids(exclude)
    local pick
    if #candidates == 0 then
        if exclude["v_blank"] or self:_voucher_already_owned("v_blank") then
            return nil
        end
        pick = "v_blank"
    else
        pick = candidates[self:_shop_rand_int(1, #candidates)]
    end
    return self:_make_shop_voucher_offer(pick)
end

--- Consume each voucher tag: append one extra unowned voucher offer per tag.
function Game:apply_voucher_tags_to_shop()
    if type(self.tags) ~= "table" then return end
    local to_remove = {}
    for i, tag in ipairs(self.tags) do
        if tag and tag.type == "voucher" then
            to_remove[#to_remove + 1] = i
        end
    end
    if #to_remove == 0 then return end
    -- Remove highest indices first so indices stay valid.
    table.sort(to_remove, function(a, b) return a > b end)
    for _, i in ipairs(to_remove) do
        local offer = self:_roll_one_shop_voucher_offer()
        if offer then
            if not self.shop_voucher_offers then self.shop_voucher_offers = {} end
            self.shop_voucher_offers[#self.shop_voucher_offers + 1] = offer
        end
        self:removeTag(i)
    end
end

function Game:maybe_roll_shop_voucher_on_shop_enter()
    if self._last_completed_blind_was_boss == true then
        self.shop_voucher_bought_pending_boss = false
        self.shop_voucher_offers = {}
        local offer = self:_roll_one_shop_voucher_offer()
        if offer then
            self.shop_voucher_offers[1] = offer
        end
        self:apply_voucher_tags_to_shop()
        self:sync_shop_voucher_nodes()
        return
    end
    -- Standard ante voucher already bought: keep any remaining offers, still apply new voucher tags.
    if self.shop_voucher_bought_pending_boss == true then
        self:apply_voucher_tags_to_shop()
        self:sync_shop_voucher_nodes()
        return
    end
    -- Normal slot: roll one if empty, then add any voucher tags.
    if not self.shop_voucher_offers or #self.shop_voucher_offers == 0 then
        self.shop_voucher_offers = {}
        local offer = self:_roll_one_shop_voucher_offer()
        if offer then
            self.shop_voucher_offers[1] = offer
        end
    end
    self:apply_voucher_tags_to_shop()
    self:sync_shop_voucher_nodes()
end

--- Roll a single standard shop voucher (replaces offers). Prefer `maybe_roll_shop_voucher_on_shop_enter`.
function Game:roll_shop_voucher()
    self.shop_voucher_offers = {}
    local offer = self:_roll_one_shop_voucher_offer()
    if offer then
        self.shop_voucher_offers[1] = offer
    end
    self:sync_shop_voucher_nodes()
end

function Game:buy_shop_voucher(slot_index)
    if type(slot_index) ~= "number" or slot_index < 1 then return false end
    if self.STATE ~= self.STATES.SHOP then return false end
    local offer = self.shop_voucher_offers and self.shop_voucher_offers[slot_index]
    if type(offer) ~= "table" or type(offer.id) ~= "string" then return false end
    if not self:can_afford_price(self:get_shop_voucher_price(offer)) then return false end
    if self:_voucher_already_owned(offer.id) then return false end

    local voucher_id = offer.id
    self.money = (tonumber(self.money) or 0) - self:get_shop_voucher_price(offer)
    if not self.vouchers then self.vouchers = {} end
    self.vouchers[#self.vouchers + 1] = voucher_id
    self:apply_voucher_effect(voucher_id)
    table.remove(self.shop_voucher_offers, slot_index)
    if self.shop_voucher_nodes and self.shop_voucher_nodes[slot_index] then
        local removed = self.shop_voucher_nodes[slot_index]
        if removed then self:remove(removed) end
        table.remove(self.shop_voucher_nodes, slot_index)
    end
    self:sync_shop_voucher_nodes()
    if voucher_id == "v_overstock" or voucher_id == "v_overstock_plus" then
        self:extend_shop_offers_to_slot_count()
    elseif voucher_id == "v_clearance_sale" or voucher_id == "v_liquidation" then
        self:refresh_shop_prices()
        self:layout_shop_panels()
    end
    self.shop_voucher_bought_pending_boss = true
    self.active_tooltip_shop_voucher_slot = nil
    self:discover_item(offer.id)
    self:emit_joker_event("on_shop_buy", {
        offer = offer,
        offer_kind = "voucher",
        offer_id = offer.id,
        offer_price = tonumber(offer.price) or 0,
    })
    return true
end

--- Debug / test helper: grant one random voucher the player does not already own.
---@return string|nil voucher id granted, or nil if every voucher is owned
function Game:give_random_unowned_voucher()
    if type(VOUCHER_DEFS) ~= "table" then return nil end
    local candidates = {}
    for vid, def in pairs(VOUCHER_DEFS) do
        if type(vid) == "string" and type(def) == "table" and not self:has_voucher(vid) then
            candidates[#candidates + 1] = vid
        end
    end
    local pick
    if #candidates == 0 then 
        pick = "v_blank"
    else
        pick = candidates[math.random(1, #candidates)]
    end
    if not self.vouchers then self.vouchers = {} end
    self.vouchers[#self.vouchers + 1] = pick
    self:apply_voucher_effect(pick)
    return pick
end

function Game:apply_voucher_effect(id)
    if id == "v_wasteful" or id == "v_recyclomancy" then return end
    if id == "v_tarot_merchant" or id == "v_tarot_tycoon" then return end
    if id == "v_planet_merchant" or id == "v_planet_tycoon" then return end
    if id == "v_seed_money" or id == "v_money_tree" then return end
    if id == "v_blank" then return end
    if id == "v_antimatter" then
        if self.refresh_joker_capacity_from_negatives then
            self:refresh_joker_capacity_from_negatives()
        end
        return
    end
    if id == "v_magic_trick" or id == "v_illusion" then return end
    if id == "v_hieroglyph" then
        self.ante = (tonumber(self.ante) or 1) - 1
        self.boss_rerolls_used_this_ante = 0
        if self.current_boss_blind_id and self.roll_boss_blind then
            self:roll_boss_blind({ exclude_current = true })
        end
        return
    end
    if id == "v_petroglyph" then
        self.ante = (tonumber(self.ante) or 1) - 1
        self.boss_rerolls_used_this_ante = 0
        if self.current_boss_blind_id and self.roll_boss_blind then
            self:roll_boss_blind({ exclude_current = true })
        end
        return
    end
    if id == "v_directors_cut" or id == "v_retcon" then return end
    if id == "v_paint_brush" or id == "v_palette" then
        self.hand_size_delta_voucher = (tonumber(self.hand_size_delta_voucher) or 0) + 1
        return
    end
    if id == "v_overstock" or id == "v_overstock_plus" then
        self.shop_offer_slots = math.max(1, (tonumber(self.shop_offer_slots) or 2) + 1)
        return
    end
    if id == "v_clearance_sale" or id == "v_liquidation" then return end
    if id == "v_hone" or id == "v_glow_up" then return end
    if id == "v_reroll" or id == "v_reroll_glut" then return end
    if id == "v_crystal_ball" then
        if self.refresh_consumable_capacity_from_negatives then
            self:refresh_consumable_capacity_from_negatives()
        end
        return
    end
    if id == "v_omen_globe" then return end
    if id == "v_telescope" or id == "v_observatory" then return end
end

function Game:get_interest_round_cap_dollars()
    if self:has_voucher("v_money_tree") then return 20 end
    if self:has_voucher("v_seed_money") then return 10 end
    return 5
end

function Game:_deck_inject_playing_card(card_data)
    if not Deck or not Deck.copy_card_data then return false end
    local d = Deck.copy_card_data(card_data)
    if not d then return false end
    if self.ensure_card_uid then
        self:ensure_card_uid(d, true)
    end
    local deck = self.deck
    if not deck or type(deck.cards) ~= "table" then return false end
    local n = #deck.cards
    local pos = self:_shop_rand_int(1, math.max(1, n + 1))
    if pos > n then
        deck.cards[#deck.cards + 1] = d
    else
        table.insert(deck.cards, pos, d)
    end
    self:notify_cards_added_to_deck(1)
    return true
end

function Game:try_boss_reroll_press(x, y)
    if self.STATE ~= self.STATES.BLIND_SELECT then return false end
    local r = self._boss_reroll_btn_rect
    if not r or not self:_point_in_rect_simple(x, y, r) then return false end
    if not (self:has_voucher("v_directors_cut") or self:has_voucher("v_retcon")) then return true end
    if tonumber(self.selected_blind_index) ~= 3 then return true end
    if not self:can_afford_price(10) then return true end
    if self:has_voucher("v_directors_cut") and not self:has_voucher("v_retcon") then
        if (tonumber(self.boss_rerolls_used_this_ante) or 0) >= 1 then return true end
    end
    self.money = (tonumber(self.money) or 0) - 10
    self.boss_rerolls_used_this_ante = (tonumber(self.boss_rerolls_used_this_ante) or 0) + 1
    self:roll_boss_blind({ exclude_current = true })
    return true
end

function Game:get_joker_edition_rates()
    local has_hone = self:has_voucher("v_hone") or self:has_voucher("hone")
    local has_glow_up = self:has_voucher("v_glow_up") or self:has_voucher("glow_up")

    local rates = {
        negative = 0.0,
        polychrome = 0.3,
        holo = 1.4,
        foil = 2.0,
    }

    if has_glow_up then
        rates.polychrome = 2.1
        rates.holo = 5.6
        rates.foil = 8.0
    elseif has_hone then
        rates.polychrome = 0.9
        rates.holo = 2.8
        rates.foil = 4.0
    end

    if has_hone then
        rates.negative = 0.3
    end

    return rates
end

function Game:roll_joker_offer_edition()
    local rates = self:get_joker_edition_rates()
    local r = self:_shop_rand_int(1, 10000) / 100
    local acc = tonumber(rates.negative) or 0
    if r <= acc then return "negative" end
    acc = acc + (tonumber(rates.polychrome) or 0)
    if r <= acc then return "polychrome" end
    acc = acc + (tonumber(rates.holo) or 0)
    if r <= acc then return "holo" end
    acc = acc + (tonumber(rates.foil) or 0)
    if r <= acc then return "foil" end
    return "base"
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

function Game:_shop_consumable_owned(id)
    if type(id) ~= "string" then return false end
    for _, c in ipairs(self.consumables or {}) do
        if type(c) == "table" and c.id == id then
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
    local entry = table.remove(self.shop_offer_queue, 1)
    if entry then
        self:remap_shop_joker_offer(entry)
    end
    return entry
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
    local tw, pw = self:_shop_queue_tarot_planet_weights()
    local sw = self.deck_spectral_rate or 0
    local cw = self:has_voucher("v_magic_trick") and 6 or 0
    local total = 20 + tw + pw + sw + cw
    local max_attempts = 32

    for _ = 1, max_attempts do
        local roll = self:_shop_rand_int(1, total)
        local kind = "planet"
        if roll <= 20 then
            kind = "joker"
        elseif roll <= 20 + tw then
            kind = "tarot"
        elseif roll <= 20 + tw + pw then
            kind = "planet"
        elseif roll <= 20 + tw + pw + sw then
            kind = "spectral"
        else
            kind = "playing_card"
        end

        if kind == "joker" then
            local joker_offer = self:_roll_shop_queue_joker_offer()
            if joker_offer then return joker_offer end
        elseif kind == "tarot" then
            local c = self:_roll_shop_queue_consumable_offer("tarot")
            if c then return c end
        elseif kind == "planet" then
            local c = self:_roll_shop_queue_consumable_offer("planet")
            if c then return c end
        elseif kind == "spectral" then
            local c = self:_roll_shop_queue_consumable_offer("spectral")
            if c then return c end
        else
            local pc = self:_roll_shop_playing_card_offer()
            if pc then return pc end
        end
    end

    local j2 = self:_roll_shop_queue_joker_offer()
    if j2 then return j2 end
    return self:_shop_queue_emergency_joker_offer()
end

--- Shop joker rarity: Common 70%, Uncommon 25%, Rare 5% (no Legendary). `rand_int` isolates RNG source.
---@param rand_int fun(lo: integer, hi: integer): integer
---@return string|nil
function Game:_pick_joker_id_shop_rarity_distribution(rand_int)
    if type(JOKER_DEFS) ~= "table" then return nil end
    if type(rand_int) ~= "function" then return nil end
    local rar_roll = rand_int(1, 100)
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
            if rv == target_rar and rv >= 1 and rv <= 3 and self:joker_allowed_in_random_pool(id) then
                candidates[#candidates + 1] = id
            end
        end
    end
    table.sort(candidates)
    if #candidates == 0 then
        for id, def in pairs(JOKER_DEFS) do
            if type(def) == "table" and type(id) == "string" then
                local rv = tonumber(def.rarity) or 1
                if rv >= 1 and rv <= 3 and self:joker_allowed_in_random_pool(id) then
                    candidates[#candidates + 1] = id
                end
            end
        end
        table.sort(candidates)
    end
    if #candidates == 0 then return nil end
    return candidates[rand_int(1, #candidates)]
end

function Game:_roll_shop_queue_joker_offer()
    if type(JOKER_DEFS) ~= "table" then return nil end
    local pick = self:_pick_joker_id_shop_rarity_distribution(function(lo, hi)
        return self:_shop_rand_int(lo, hi)
    end)
    if not pick then return nil end
    local def = JOKER_DEFS[pick]
    local edition = self:roll_joker_offer_edition()
    local sticker_params = self:_build_joker_sticker_params(def)
    local create_params = self:_build_joker_create_params(def, { edition = edition }, sticker_params)
    local offer = {
        kind = "joker",
        id = pick,
        name = def and def.name or pick,
        price = self:shop_price_for_joker_offer(def, edition, sticker_params),
        edition = edition,
        stickers = sticker_params,
        create_params = create_params,
    }
    if sticker_params.eternal then offer.eternal = true end
    if sticker_params.perishable then offer.perishable = true end
    if sticker_params.rental then offer.rental = true end
    return offer
end

function Game:_roll_shop_queue_consumable_offer(wanted_kind)
    if type(CONSUMABLE_DEFS) ~= "table" then return nil end
    local ids = {}
    for id, def in pairs(CONSUMABLE_DEFS) do
        if type(def) == "table" and def.kind == wanted_kind and type(id) == "string" then
            if wanted_kind ~= "planet" or self:planet_consumable_unlocked(id, def) then
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
        price = self:shop_price_for_consumable_offer(def, wanted_kind),
    }
end

--- Buy price for a shop row: `def.cost` plus edition bonus (same as a spawned `Joker`).
---@param def table|nil
---@param edition string|nil
function Game:shop_price_for_joker_offer(def, edition, sticker_params)
    if type(def) ~= "table" then return 1 end
    local sticker_data = type(sticker_params) == "table" and sticker_params or nil
    if (sticker_data and sticker_data.rental == true) or def.rental == true or (type(def.stickers) == "table" and def.stickers.rental == true) then
        return 1
    end
    local base = tonumber(def.cost) or 1
    if not Joker then
        return self:apply_shop_discount_to_price(math.max(1, base))
    end
    local ec = select(1, Joker.edition_price_deltas(edition))
    local raw = math.max(1, base + (tonumber(ec) or 0))
    return self:apply_shop_discount_to_price(raw)
end

---@param def table|nil
function Game:_build_joker_sticker_params(def)
    local params = {}
    if type(def) == "table" then
        local sticker_def = def.stickers
        if type(sticker_def) == "table" then
            for k, v in pairs(sticker_def) do
                if v == true then params[k] = true end
            end
        end
        if def.eternal == true then params.eternal = true end
        if def.perishable == true then params.perishable = true end
        if def.rental == true then params.rental = true end
    end

    if self._stake_eternal_jokers == true and params.eternal ~= true and self:_shop_rand_int(1, 100) <= 30 then
        params.eternal = true
    end
    if params.eternal ~= true and self._stake_perishable_jokers == true and self:_shop_rand_int(1, 100) <= 30 then
        params.perishable = true
    end
    if self._stake_rental_jokers == true and self:_shop_rand_int(1, 100) <= 30 then
        params.rental = true
    end
    if params.eternal then params.perishable = nil end
    return params
end

function Game:_build_joker_create_params(def, base_params, sticker_params)
    local params = type(base_params) == "table" and copy_table(base_params) or {}
    local sticker_data = type(sticker_params) == "table" and sticker_params or self:_build_joker_sticker_params(def)
    if next(sticker_data) ~= nil then
        params.stickers = sticker_data
        for k, v in pairs(sticker_data) do
            params[k] = v
        end
    end
    return next(params) ~= nil and params or nil
end

function Game:shop_price_for_consumable_offer(def, kind_fallback)
    local kind = (type(def) == "table" and def.kind) or kind_fallback
    if self:hasJoker("j_astronomer") and kind == "planet" then
        return 0
    end
    if type(def) ~= "table" then return 3 end
    local by_kind = {
        tarot = 3,
        planet = 3,
        spectral = 4,
    }
    local raw = by_kind[kind] or 3
    return self:apply_shop_discount_to_price(raw)
end

--- Live buy price for a shop row (recomputes Astronomer / discount effects).
--- Preserves stored $0 offers (coupon, rare/uncommon tags, edition tags).
function Game:get_shop_offer_price(offer)
    if type(offer) ~= "table" then return 0 end
    local stored = tonumber(offer.price) or 0
    if stored == 0 then return 0 end

    local k = offer.kind
    if k == nil or k == "joker" then
        local def = JOKER_DEFS and JOKER_DEFS[offer.id]
        return self:shop_price_for_joker_offer(def, offer.edition, offer.stickers)
    elseif k == "tarot" or k == "planet" or k == "spectral" then
        if self:hasJoker("j_astronomer") and k == "planet" then
            return 0
        end
        local def = CONSUMABLE_DEFS and CONSUMABLE_DEFS[offer.id]
        return self:shop_price_for_consumable_offer(def, k)
    elseif k == "playing_card" then
        return self:apply_shop_discount_to_price(4)
    end
    return stored
end

function Game:get_shop_booster_price(offer)
    if type(offer) ~= "table" then return 0 end
    local stored = tonumber(offer.price) or 0
    if stored == 0 then return 0 end
    return self:_booster_offer_price(offer.pack, offer.size)
end

function Game:get_shop_voucher_price(offer)
    if type(offer) ~= "table" then return 0 end
    local stored = tonumber(offer.price) or 0
    if stored == 0 then return 0 end
    local d = VOUCHER_DEFS and VOUCHER_DEFS[offer.id]
    local base = tonumber(d and d.price) or 10
    return self:apply_shop_discount_to_price(base)
end

function Game:refresh_shop_prices()
    if self.STATE ~= self.STATES.SHOP then return end
    for _, offer in ipairs(self.shop_offers or {}) do
        offer.price = self:get_shop_offer_price(offer)
    end
    for _, offer in ipairs(self.shop_booster_offers or {}) do
        offer.price = self:get_shop_booster_price(offer)
    end
    for _, offer in ipairs(self.shop_voucher_offers or {}) do
        offer.price = self:get_shop_voucher_price(offer)
    end
end

function Game:layout_shop_panels()
    if self.STATE ~= self.STATES.SHOP then return end
    if self._shop_joker_panel then
        self:layout_shop_offer_nodes(self._shop_joker_panel)
    end
    if self._shop_booster_panel and ShopUI then
        ShopUI.layout_shop_booster_nodes(self, self._shop_booster_panel)
    end
    if self._shop_voucher_panel and ShopUI then
        ShopUI.layout_shop_voucher_nodes(self, self._shop_voucher_panel)
    end
end

function Game:extend_shop_offers_to_slot_count()
    if self.STATE ~= self.STATES.SHOP then return end
    if type(self.shop_offer_queue) ~= "table" then
        self:init_shop_offer_queue()
    end
    if type(self.shop_offers) ~= "table" then
        self.shop_offers = {}
    end

    local allow_duplicates = self:hasJoker("j_ring_master")
    local slots = math.max(1, math.floor(tonumber(self.shop_offer_slots) or 2))
    local guard = 0
    local guard_limit = math.max(250, slots * 125)
    local seen_ids = {}
    for _, offer in ipairs(self.shop_offers) do
        if (offer.kind == nil or offer.kind == "joker") and offer.id then
            seen_ids[offer.id] = true
        end
    end

    local tagUsed = nil
    while #self.shop_offers < slots and guard < guard_limit do
        guard = guard + 1
        local entry = nil
        tagUsed = nil

        for _, tag in ipairs(self.tags or {}) do
            if tag.type == "uncommon" then
                entry = self:generate_joker_from_rarity(2)
                entry.price = 0
                tagUsed = "uncommon"
                break
            elseif tag.type == "rare" then
                entry = self:generate_joker_from_rarity(3)
                entry.price = 0
                tagUsed = "rare"
                break
            end
        end
        if tagUsed == nil then
            entry = self:_pop_shop_queue_entry()
        end

        if not entry then break end
        if entry.kind == "joker" or entry.kind == nil then
            if entry.kind == nil then
                entry.kind = "joker"
            end
            local id = entry.id
            local dup = false
            if (not allow_duplicates) then
                if self:_shop_joker_owned(id) then
                    dup = true
                elseif id ~= nil and seen_ids[id] then
                    dup = true
                end
            end
            if not dup then
                local ed = entry.edition or "base"
                if ed == "base" then
                    local edition_from_tag = nil
                    for i, tag in ipairs(self.tags or {}) do
                        if tag and (tag.type == "negative" or tag.type == "foil"
                            or tag.type == "holo" or tag.type == "polychrome") then
                            edition_from_tag = tag.type
                            self:removeTag(i)
                            break
                        end
                    end
                    if edition_from_tag then
                        entry.edition = edition_from_tag
                        entry.price = 0
                        local def = JOKER_DEFS and JOKER_DEFS[entry.id]
                        entry.create_params = self:_build_joker_create_params(
                            def, { edition = edition_from_tag }, entry.stickers)
                        if type(entry.create_params) == "table" then
                            entry.create_params.face_up = true
                        end
                    end
                end

                if self:hasTag("coupon") ~= -1 and self.shop_reroll_count == 0 then entry.price = 0 end
                self.shop_offers[#self.shop_offers + 1] = entry
                if id ~= nil then seen_ids[id] = true end
                if tagUsed ~= nil then
                    local ti = self:hasTag(tagUsed)
                    if ti ~= -1 then
                        self:removeTag(ti)
                    end
                    tagUsed = nil
                end
            end
        elseif entry.kind == "playing_card" then
            if self:hasTag("coupon") ~= -1 and self.shop_reroll_count == 0 then entry.price = 0 end
            self.shop_offers[#self.shop_offers + 1] = entry
        else
            if (not allow_duplicates) and self:_shop_consumable_owned(entry.id) then
                -- Owned: consume queue slot, no visible offer.
            else
                if self:hasTag("coupon") ~= -1 and self.shop_reroll_count == 0 then entry.price = 0 end
                self.shop_offers[#self.shop_offers + 1] = entry
            end
        end
    end

    self:refresh_shop_prices()
    self:sync_shop_offer_nodes()
    self:layout_shop_panels()
end

function Game:shop_current_reroll_cost()
    local base
    if self._shop_reroll_base_cost_override ~= nil then
        base = tonumber(self._shop_reroll_base_cost_override) or 0
    else
        base = tonumber(self.shop_reroll_base_cost) or 5
    end
    local n = math.max(0, math.floor(tonumber(self.shop_reroll_count) or 0))
    if (self.shop_reroll_count == 0 and self:hasJoker("j_chaos")) then return 0 end
    local sub = 0
    if self:has_voucher("v_reroll_glut") then sub = sub + 2 end
    if self:has_voucher("v_reroll") then sub = sub + 2 end
    if self._shop_reroll_base_cost_override ~= nil then
        return math.max(0, base + n - sub)
    end
    return math.max(1, base + n - sub)
end

function Game:generate_joker_from_rarity(rarity)
    local id = self:random_joker_def_id_by_rarity(rarity)
    local def = id and JOKER_DEFS[id]
    local name = def and def.name or id
    local edition = self:roll_joker_offer_edition()
    return {
        kind = "joker",
        id = id,
        name = name,
        price = self:shop_price_for_joker_offer(def, edition),
        edition = edition
    }
end

function Game:roll_shop_offers()
    if type(self.shop_offer_queue) ~= "table" then
        self:init_shop_offer_queue()
    end
    self.shop_offers = {}
    local allow_duplicates = self:hasJoker("j_ring_master")
    local slots = math.max(1, math.floor(tonumber(self.shop_offer_slots) or 2))
    local guard = 0
    local guard_limit = math.max(250, slots * 125)
    local seen_ids = {}
    local tagUsed = nil -- Only for rare and uncommon tags (DO NOT USE FOR SOMETHING ELSE)
    while #self.shop_offers < slots and guard < guard_limit do
        guard = guard + 1
        local entry = nil

        -- Logic should work in sequence, this prioritizes uncommon over rare jokers 
        --[[ 
        if self:hasTag("uncommon") ~= -1 then
            entry = self:generate_joker_from_rarity(2)
            entry.price = 0
            tagUsed = "uncommon"
        elseif self:hasTag("rare") ~= -1 then
            entry = self:generate_joker_from_rarity(3)
            entry.price = 0
            tagUsed = "rare"
        else
            entry = self:_pop_shop_queue_entry()
        end 
        ]]

        for i, tag in ipairs(self.tags or {}) do
            if tag.type == "uncommon" then
                entry = self:generate_joker_from_rarity(2)
                entry.price = 0
                tagUsed = "uncommon"
                break
            elseif tag.type == "rare" then
                entry = self:generate_joker_from_rarity(3)
                entry.price = 0
                tagUsed = "rare"
                break
            end
        end
        if tagUsed == nil then
            entry = self:_pop_shop_queue_entry()
        end

        if not entry then break end
        if entry.kind == "joker" or entry.kind == nil then
            if entry.kind == nil then
                entry.kind = "joker"
            end
            local id = entry.id
            local dup = false
            if (not allow_duplicates) then
                if self:_shop_joker_owned(id) then
                    dup = true
                elseif id ~= nil and seen_ids[id] then
                    dup = true
                end
            end
            if not dup then
                local ed = entry.edition or "base"
                if ed == "base" then
                    local edition_from_tag = nil
                    for i, tag in ipairs(self.tags or {}) do
                        if tag and (tag.type == "negative" or tag.type == "foil"
                            or tag.type == "holo" or tag.type == "polychrome") then
                            edition_from_tag = tag.type
                            self:removeTag(i)
                            break
                        end
                    end
                    if edition_from_tag then
                        entry.edition = edition_from_tag
                        entry.price = 0
                        local def = JOKER_DEFS and JOKER_DEFS[entry.id]
                        entry.create_params = self:_build_joker_create_params(
                            def, { edition = edition_from_tag }, entry.stickers)
                        if type(entry.create_params) == "table" then
                            entry.create_params.face_up = true
                        end
                    end
                end

                if self:hasTag("coupon") ~= -1 and self.shop_reroll_count == 0 then entry.price = 0 end
                self.shop_offers[#self.shop_offers + 1] = entry
                if id ~= nil then seen_ids[id] = true end
                if tagUsed ~= nil then
                    i = self:hasTag(tagUsed)
                    if i ~= -1 then
                        self:removeTag(i)
                    end
                    tagUsed = nil
                end
            end
        elseif entry.kind == "playing_card" then
            if self:hasTag("coupon") ~= -1 and self.shop_reroll_count == 0 then entry.price = 0 end
            self.shop_offers[#self.shop_offers + 1] = entry
        else
            if (not allow_duplicates) and self:_shop_consumable_owned(entry.id) then
                -- Owned: consume queue slot, no visible offer.
            else
            if self:hasTag("coupon") ~= -1 and self.shop_reroll_count == 0 then entry.price = 0 end
                self.shop_offers[#self.shop_offers + 1] = entry
            end
        end
    end
    self:refresh_shop_prices()
    self:sync_shop_offer_nodes()
end

function Game:reroll_shop_offers()
    if self.STATE ~= self.STATES.SHOP then return false end
    local cost = self:shop_current_reroll_cost()
    if not self:can_afford_price(cost) then
        return false
    end
    self.money = (tonumber(self.money) or 0) - cost
    self.shop_reroll_count = (tonumber(self.shop_reroll_count) or 0) + 1
    self:record_shop_reroll()
    self:emit_joker_event("on_shop_reroll", {
        reroll_cost = cost,
        reroll_count = self.shop_reroll_count,
    })
    self.active_tooltip_joker = nil
    self.active_tooltip_shop_voucher_slot = nil
    self:roll_shop_offers()
    self:clear_shop_selection()
    return true
end

function Game:roll_skips()
    local ante = tonumber(self.ante) or 1
    local eligible_tags = {}

    local function tag_key_to_id(tag_key)
        if type(tag_key) ~= "string" then return -1 end
        local type_name = tag_key:match("^tag_(.+)$")
        if type_name == "uncommon" then return 0 end
        if type_name == "rare" then return 1 end
        if type_name == "negative" then return 2 end
        if type_name == "foil" then return 3 end
        if type_name == "coupon" then return 4 end
        if type_name == "double" then return 5 end
        if type_name == "holo" then return 6 end
        if type_name == "polychrome" then return 7 end
        if type_name == "investment" then return 8 end
        if type_name == "voucher" then return 9 end
        if type_name == "topup" then return 10 end
        if type_name == "juggle" then return 11 end
        if type_name == "boss" then return 12 end
        if type_name == "standard" then return 13 end
        if type_name == "charm" then return 14 end
        if type_name == "meteor" then return 15 end
        if type_name == "buffoon" then return 16 end
        if type_name == "orbital" then return 17 end
        if type_name == "speed" then return 18 end
        if type_name == "handy" then return 19 end
        if type_name == "garbage" then return 20 end
        if type_name == "ethereal" then return 21 end
        if type_name == "economy" then return 22 end
        if type_name == "d6" then return 23 end
        return -1
    end

    if type(self.P_TAGS) == "table" then
        for tag_key, def in pairs(self.P_TAGS) do
            if type(def) == "table" and type(tag_key) == "string" then
                local min_ante = tonumber(def.min_ante)
                if (not min_ante) or ante >= min_ante then
                    local id = tag_key_to_id(tag_key)
                    if id ~= -1 then
                        eligible_tags[#eligible_tags + 1] = tag_key
                    end
                end
            end
        end
    end

    if #eligible_tags == 0 then
        eligible_tags = { "tag_uncommon" }
    end

    self.skips = {}
    self.skip_tag_orbital_hand = {}
    for slot = 1, 2 do
        local tag_key = eligible_tags[math.random(1, #eligible_tags)]
        self.skips[slot] = tag_key_to_id(tag_key)
        if self.skips[slot] == 17 then
            self.skip_tag_orbital_hand[slot] = self:roll_orbital_hand_index()
        end
    end
end

-- ---------------------------------------------------------------------------
-- Shop booster packs (two dedicated slots below main offers).
-- ---------------------------------------------------------------------------

function Game:_spectral_consumable_defs_count()
    if not CONSUMABLE_DEFS then return 0 end
    local n = 0
    for _, def in pairs(CONSUMABLE_DEFS) do
        if type(def) == "table" and def.kind == "spectral" then
            n = n + 1
        end
    end
    return n
end

function Game:_roll_booster_pack_type()
    local profile = self:_roll_booster_offer_profile()
    return profile.pack
end

function Game:_roll_booster_size()
    local profile = self:_roll_booster_offer_profile()
    return profile.size
end

function Game:_roll_booster_offer_profile()
    -- Scaled by 100 to keep integer RNG while preserving ratios
    local entries = {
        { pack = "standard",  size = "normal", weight = 400 },
        { pack = "arcana",    size = "normal", weight = 400 },
        { pack = "celestial", size = "normal", weight = 400 },
        { pack = "buffoon",   size = "normal", weight = 120 },
        { pack = "spectral",  size = "normal", weight = 60 },

        { pack = "standard",  size = "jumbo",  weight = 200 },
        { pack = "arcana",    size = "jumbo",  weight = 200 },
        { pack = "celestial", size = "jumbo",  weight = 200 },
        { pack = "buffoon",   size = "jumbo",  weight = 60 },
        { pack = "spectral",  size = "jumbo",  weight = 30 },

        { pack = "standard",  size = "mega",   weight = 50 },
        { pack = "arcana",    size = "mega",   weight = 50 },
        { pack = "celestial", size = "mega",   weight = 50 },
        { pack = "buffoon",   size = "mega",   weight = 15 },
        { pack = "spectral",  size = "mega",   weight = 7 },
    }

    local spectral_ok = self:_spectral_consumable_defs_count() > 0
    local pool = {}
    local total = 0
    for _, e in ipairs(entries) do
        if spectral_ok or e.pack ~= "spectral" then
            pool[#pool + 1] = e
            total = total + e.weight
        end
    end
    if total <= 0 or #pool == 0 then
        return { pack = "arcana", size = "normal" }
    end

    local r = self:_shop_rand_int(1, total)
    local acc = 0
    for _, e in ipairs(pool) do
        acc = acc + e.weight
        if r <= acc then
            return { pack = e.pack, size = e.size }
        end
    end
    local last = pool[#pool]
    return { pack = last.pack, size = last.size }
end

function Game:_booster_offer_price(pack, size)
    if self:hasJoker("j_astronomer") and pack == "celestial" then
        return 0
    end
    local by_size = {
        normal = 4,
        jumbo = 6,
        mega = 8,
    }
    local raw = by_size[size] or 4
    return self:apply_shop_discount_to_price(raw)
end

function Game:_booster_offer_display_name(pack, size)
    return BoosterPackUI.display_label(pack, size) .. " Pack"
end

function Game:roll_shop_boosters()
    if type(self.shop_offer_queue) ~= "table" then
        self:init_shop_offer_queue()
    end
    local slots = math.max(1, math.floor(tonumber(self.shop_booster_slots) or 2))
    self.shop_booster_offers = {}
    for _ = 1, slots do
        local profile = self:_roll_booster_offer_profile()
        local pack = profile.pack
        local size = profile.size
        local n_cards = BoosterPackUI.card_count_for_size(size)
        local n_picks = BoosterPackUI.picks_for_size(size)
        local frames = ShopUI.booster_frames_for_pack_size(pack, size)
        local sprite_idx = nil
        if type(frames) == "table" and #frames > 0 then
            sprite_idx = frames[self:_shop_rand_int(1, #frames)]
        end
        local new_price = self:_booster_offer_price(pack, size)
        if self:hasTag("coupon") ~= -1 then
            new_price = 0
        end
        self.shop_booster_offers[#self.shop_booster_offers + 1] = {
            kind = "booster",
            pack = pack,
            size = size,
            price = new_price,
            name = self:_booster_offer_display_name(pack, size),
            card_count = n_cards,
            picks_granted = n_picks,
            booster_sprite_index = sprite_idx,
        }
    end
    self.active_shop_booster_slot = nil
    self:refresh_shop_prices()
    self:sync_shop_booster_nodes()
end

function Game:buy_shop_booster(slot_index)
    if type(slot_index) ~= "number" or slot_index < 1 then return false end
    if self.STATE ~= self.STATES.SHOP then return false end
    local offer = self.shop_booster_offers and self.shop_booster_offers[slot_index]
    if not offer or offer.kind ~= "booster" then return false end
    local price = self:get_shop_booster_price(offer)
    if not self:can_afford_price(price) then return false end

    self.money = (tonumber(self.money) or 0) - price
    local sprite_idx = tonumber(offer.booster_sprite_index) or 0
    if offer.pack and offer.size then
        self:discover_item(string.format("booster_%s_%s", offer.pack, offer.size))
    end
    self:emit_joker_event("on_shop_buy", {
        offer = offer,
        offer_kind = "booster",
        offer_id = offer.pack .. "_" .. offer.size,
        offer_price = price,
    })
    table.remove(self.shop_booster_offers, slot_index)
    self.active_shop_booster_slot = nil
    self:sync_shop_booster_nodes()
    self:begin_booster_session(offer)
    return true
end

function Game:_booster_destroy_choice_nodes()
    local sess = self.booster_session
    if not sess or type(sess.choice_nodes) ~= "table" then return end
    for _, node in pairs(sess.choice_nodes) do
        if node then
            if self.active_tooltip_joker == node then
                self.active_tooltip_joker = nil
            end
            self:remove(node)
        end
    end
    sess.choice_nodes = {}
end

function Game:_shop_pick_unique_consumable_ids(wanted_kind, count)
    local pool = {}
    local allow_duplicates = self:hasJoker("j_ring_master")
    if not CONSUMABLE_DEFS then return pool end
    for id, def in pairs(CONSUMABLE_DEFS) do
        if type(def) == "table" and type(id) == "string" and def.kind == wanted_kind then
            local incl = true
            if wanted_kind == "spectral" and (id == "spectral_soul" or id == "spectral_black_hole") then
                -- Soul / Black Hole are replacement-only in booster packs.
                incl = false
            end
            if wanted_kind == "planet" and not self:planet_consumable_unlocked(id, def) then
                incl = false
            end
            if incl then
                pool[#pool + 1] = id
            end
        end
    end
    table.sort(pool)
    local out = {}
    if allow_duplicates then
        for _ = 1, count do
            if #pool == 0 then break end
            local idx = self:_shop_rand_int(1, #pool)
            out[#out + 1] = pool[idx]
        end
        return out
    end
    for _ = 1, math.min(count, #pool) do
        if #pool == 0 then break end
        local idx = self:_shop_rand_int(1, #pool)
        out[#out + 1] = table.remove(pool, idx)
    end
    return out
end

function Game:_shop_pick_unique_joker_ids(count)
    local out = {}
    local allow_duplicates = self:hasJoker("j_ring_master")
    local function joker_already_picked(id)
        if not id then return true end
        if not allow_duplicates and self:_shop_joker_owned(id) then return true end
        for _, e in ipairs(out) do
            if e and e.id == id then return true end
        end
        return false
    end

    if allow_duplicates then
        for _ = 1, count do
            local offer = self:_roll_shop_queue_joker_offer()
            if offer and offer.id then
                out[#out + 1] = { id = offer.id, edition = offer.edition or "base" }
            end
        end
        return out
    end

    local guard = 0
    while #out < count and guard < 80 do
        guard = guard + 1
        local offer = self:_roll_shop_queue_joker_offer()
        if offer and offer.id and not joker_already_picked(offer.id) then
            out[#out + 1] = { id = offer.id, edition = offer.edition or "base" }
        end
    end
    return out
end

function Game:_booster_build_choices(offer)
    local choices = {}
    local n = math.max(1, math.floor(tonumber(offer.card_count) or 3))
    local pack = offer.pack
    local function maybe_replace_with_rare_spectral(base_kind, def_copy)
        if type(def_copy) ~= "table" then return base_kind, def_copy end
        local soul_def = CONSUMABLE_DEFS and CONSUMABLE_DEFS.spectral_soul
        local black_hole_def = CONSUMABLE_DEFS and CONSUMABLE_DEFS.spectral_black_hole

        local can_soul = (pack == "arcana" or pack == "spectral")
        local can_black_hole = (pack == "celestial" or pack == "spectral")

        -- 0.3% chance each per card slot (replacement behavior).
        if can_black_hole and black_hole_def and self:_shop_rand_int(1, 1000) <= 3 then
            local c = copy_table and copy_table(black_hole_def) or nil
            if c then
                c.id = "spectral_black_hole"
                return "spectral", c
            end
        end
        if can_soul and soul_def and self:_shop_rand_int(1, 1000) <= 3 then
            local c = copy_table and copy_table(soul_def) or nil
            if c then
                c.id = "spectral_soul"
                return "spectral", c
            end
        end
        return base_kind, def_copy
    end

    if pack == "arcana" then
        local ids = self:_shop_pick_unique_consumable_ids("tarot", n)
        for _, id in ipairs(ids) do
            local def = CONSUMABLE_DEFS and CONSUMABLE_DEFS[id]
            if type(def) == "table" and copy_table then
                local c = copy_table(def)
                c.id = id
                local kind0, def0 = "tarot", c
                if self:has_voucher("v_omen_globe") and self:_shop_rand_int(1, 4) == 1 then
                    local sids = self:_shop_pick_unique_consumable_ids("spectral", 1)
                    local sid = sids and sids[1]
                    local sd = sid and CONSUMABLE_DEFS[sid]
                    if type(sd) == "table" then
                        local sc = copy_table(sd)
                        sc.id = sid
                        kind0, def0 = "spectral", sc
                    end
                end
                local kind, out_def = maybe_replace_with_rare_spectral(kind0, def0)
                choices[#choices + 1] = { kind = kind, consumable_def = out_def, taken = false }
            end
        end
    elseif pack == "celestial" then
        local ids = self:_shop_pick_unique_consumable_ids("planet", n)
        if self:has_voucher("v_telescope") and #ids > 0 then
            local pref = self:_planet_consumable_id_for_most_played_hand()
            if pref and CONSUMABLE_DEFS[pref] then
                ids[1] = pref
            end
        end
        for _, id in ipairs(ids) do
            local def = CONSUMABLE_DEFS and CONSUMABLE_DEFS[id]
            if type(def) == "table" and copy_table then
                local c = copy_table(def)
                c.id = id
                local kind, out_def = maybe_replace_with_rare_spectral("planet", c)
                choices[#choices + 1] = { kind = kind, consumable_def = out_def, taken = false }
            end
        end
    elseif pack == "spectral" then
        local ids = self:_shop_pick_unique_consumable_ids("spectral", n)
        for _, id in ipairs(ids) do
            local def = CONSUMABLE_DEFS and CONSUMABLE_DEFS[id]
            if type(def) == "table" and copy_table then
                local c = copy_table(def)
                c.id = id
                local kind, out_def = maybe_replace_with_rare_spectral("spectral", c)
                choices[#choices + 1] = { kind = kind, consumable_def = out_def, taken = false }
            end
        end
    elseif pack == "buffoon" then
        local entries = self:_shop_pick_unique_joker_ids(n)
        for _, e in ipairs(entries) do
            if e and e.id then
                local sticker_params = self:_build_joker_sticker_params(JOKER_DEFS and JOKER_DEFS[e.id])
                choices[#choices + 1] = {
                    kind = "joker",
                    joker_id = e.id,
                    edition = e.edition or "base",
                    taken = false,
                    create_params = self:_build_joker_create_params(JOKER_DEFS and JOKER_DEFS[e.id], { edition = e.edition or "base" }, sticker_params),
                    stickers = sticker_params,
                }
            end
        end
    elseif pack == "standard" then
        local suits = { "Hearts", "Clubs", "Diamonds", "Spades" }
        for _ = 1, n do
            local rank = self:_shop_rand_int(2, 14)
            local suit = suits[self:_shop_rand_int(1, #suits)]
            choices[#choices + 1] = {
                kind = "playing",
                playing_data = { rank = rank, suit = suit, enhancement = nil, seal = nil },
                taken = false,
            }
        end
    end

    return choices
end

function Game:_booster_spawn_choice_nodes(choices)
    local nodes = {}
    for i, ch in ipairs(choices) do
        if ch.taken then
            nodes[i] = nil
        elseif ch.kind == "tarot" or ch.kind == "planet" or ch.kind == "spectral" then
            local def = ch.consumable_def
            if Consumable and type(def) == "table" then
                local node = Consumable(0, 0, def)
                node._booster_choice_index = i
                node.states.drag.can = true
                nodes[i] = node
                self:add(node)
            end
        elseif ch.kind == "joker" and Joker then
            local jd = JOKER_DEFS and JOKER_DEFS[ch.joker_id]
            if type(jd) == "table" then
                local create_params = type(ch.create_params) == "table" and copy_table(ch.create_params) or { edition = ch.edition or "base" }
                create_params.face_up = true
                local node = Joker(0, 0, self.joker_slot_w, self.joker_slot_h, jd, create_params)
                node._booster_choice_index = i
                node.states.drag.can = true
                nodes[i] = node
                self:add(node)
            end
        elseif ch.kind == "playing" and Card then
            local node = Card(0, 0, nil, nil, ch.playing_data, nil, { face_up = true })
            node._booster_choice_index = i
            node.states.drag.can = true
            nodes[i] = node
            self:add(node)
        end
    end
    return nodes
end

function Game:begin_booster_session(offer)
    if type(offer) ~= "table" then return end
    self:_booster_destroy_choice_nodes()
    self.booster_session = nil
    self:emit_joker_event("on_booster_open",{})
    local choices = self:_booster_build_choices(offer)
    local return_state = (self.STATE ~= self.STATES.OPEN_BOOSTER) and self.STATE or self.STATES.SHOP
    self._booster_return_state = return_state
    if #choices == 0 then
        self:set_state(return_state)
        return
    end

    local needs_hand = BoosterPackUI.pack_needs_hand(offer.pack)
    self.booster_session = {
        pack = offer.pack,
        size = offer.size,
        title = self:_booster_offer_display_name(offer.pack, offer.size),
        choices = choices,
        choice_nodes = {},
        picks_remaining = math.max(0, math.floor(tonumber(offer.picks_granted) or 1)),
        hand_for_tarot = needs_hand,
        active_choice_index = nil,
        booster_sprite_index = offer.booster_sprite_index,
    }
    self.booster_session.choice_nodes = self:_booster_spawn_choice_nodes(choices)

    -- OPEN_BOOSTER + hand_for_tarot must be set before fill so Hand:layout uses the pack top row
    -- and so fill can run with the correct state (was still SHOP before).
    self:set_state(self.STATES.OPEN_BOOSTER)

    if needs_hand then
        if self.hand and self.hand.return_all_cards_to_deck_draw_pile then
            self.hand:return_all_cards_to_deck_draw_pile()
        elseif self.hand and self.hand.clear then
            self.hand:clear()
        end
        if self.hand and self.hand.fill_from_deck then
            self.hand:fill_from_deck(true)
        end
    end
    self:init_booster_gamepad_nav()
end

function Game:end_booster_session()
    local sess = self.booster_session
    if sess and sess.hand_for_tarot then
        if self.hand and self.hand.clear_selection then
            self.hand:clear_selection()
        end
        if self.hand and self.hand.return_all_cards_to_deck_draw_pile then
            self.hand:return_all_cards_to_deck_draw_pile()
        elseif self.hand and self.hand.clear then
            self.hand:clear()
        end
        self.active_tooltip_card = nil
    end
    self:_booster_destroy_choice_nodes()
    self.booster_session = nil
    self.dragging = nil
    self:reset_gamepad_nav()
    local return_state = self._booster_return_state or self.STATES.SHOP
    self._booster_return_state = nil
    self:set_state(return_state)
    if return_state == self.STATES.SHOP then
        self:init_shop_gamepad_nav()
    end
    self:sync_shop_offer_interactivity()
end

--- After a tarot/spectral from an Arcana/Spectral pack: keep the preview hand in place so
--- effects can mutate it without replacing the hand between picks.
function Game:_booster_discard_pack_hand_maybe_refill()
    local sess = self.booster_session
    if not sess or not sess.hand_for_tarot then return end

    if self.hand and self.hand.clear_selection then
        self.hand:clear_selection()
    end
    self.active_tooltip_card = nil
end

function Game:booster_tarot_needs_hand(c)
    if type(c) ~= "table" or c.kind ~= "tarot" then return false end
    local need_hand = false
    local s = c.select
    if type(s) == "table" and (s.exact or 0) > 0 then
        need_hand = true
    end
    if type(s) == "table" and s.min and tonumber(s.min) > 0 then
        need_hand = true
    end
    return need_hand
end

function Game:booster_spectral_needs_hand(c)
    if type(c) ~= "table" or c.kind ~= "spectral" then return false end
    local s = c.select
    if type(s) ~= "table" then return false end
    if (s.exact or 0) > 0 then return true end
    if s.min and tonumber(s.min) > 0 then return true end
    return false
end

function Game:pack_consumable_can_apply(c)
    if type(c) ~= "table" then return false end
    local kind = c.kind
    if kind == "planet" then
        return true
    end
    if kind == "spectral" then
        local sid = c.id
        if sid == "spectral_wraith" or sid == "spectral_soul" then
            if not self:joker_has_room_for_new("base") then return false end
        end
        if sid == "spectral_ectoplasm" and not self:has_base_edition_joker() then
            return false
        end
        if self:booster_spectral_needs_hand(c) then
            if not self:hand_ready_for_tarot_selection() then return false end
            return self:tarot_selection_requirement_met(c)
        end
        return true
    end
    if kind ~= "tarot" then return false end

    if c.spawn then
        local cap = self:get_effective_consumable_capacity()
        local free = math.max(0, cap - #(self.consumables or {}))
        if free < 1 then return false end
    end
    if c.fool_duplicate then
        local last = self.last_consumable_use_id
        if not last or last == "tarot_fool" then return false end
        if not CONSUMABLE_DEFS or not CONSUMABLE_DEFS[last] then return false end
        local cap = self:get_effective_consumable_capacity()
        if math.max(0, cap - #(self.consumables or {})) < 1 then return false end
    end
    if c.spawn_joker and not self:joker_has_room_for_new("base") then return false end
    if c.wheel_of_fortune then
        if not self.jokers or #self.jokers < 1 then return false end
    end

    if self:booster_tarot_needs_hand(c) then
        if not self:hand_ready_for_tarot_selection() then return false end
        return self:tarot_selection_requirement_met(c)
    end
    return true
end

--- Pick a non-targeting choice (joker, planet, playing card, or non-hand-needing tarot/spectral).
function Game:pick_booster_choice(idx)
    local sess = self.booster_session
    if not sess or type(sess.choices) ~= "table" then return false end
    local ch = sess.choices[idx]
    if not ch or ch.taken then return false end
    if (tonumber(sess.picks_remaining) or 0) <= 0 then return false end

    if ch.kind == "planet" then
        local c = ch.consumable_def
        if not self:pack_consumable_can_apply(c) then return false end
        self:track_consumable_use(c)
        self:apply_consumable_effect(c)
    elseif ch.kind == "joker" then
        local ed = ch.edition or "base"
        if not self:joker_has_room_for_new(ed) then return false end
        local create_params = type(ch.create_params) == "table" and copy_table(ch.create_params) or ((ed ~= "base") and { edition = ed } or nil)
        self:add_joker_by_def(ch.joker_id, create_params)
    elseif ch.kind == "playing" then
        if self.deck and self.deck.insert_random then
            self.deck:insert_random(ch.playing_data)
            self:notify_cards_added_to_deck(1)
        end
    elseif ch.kind == "tarot" or ch.kind == "spectral" then
        local c = ch.consumable_def
        if not self:pack_consumable_can_apply(c) then return false end
        self:track_consumable_use(c)
        self:apply_consumable_effect(c)
    else
        return false
    end

    ch.taken = true
    local node = sess.choice_nodes and sess.choice_nodes[idx]
    if node then
        self:remove(node)
        sess.choice_nodes[idx] = nil
    end
    sess.active_choice_index = nil
    sess.picks_remaining = (tonumber(sess.picks_remaining) or 0) - 1
    if ch.kind == "tarot" or ch.kind == "spectral" then
        if sess.hand_for_tarot then
            self:_booster_discard_pack_hand_maybe_refill()
        end
    end
    if sess.picks_remaining <= 0 then self:end_booster_session() end
    return true
end

--- Use a tarot/spectral that needs hand targeting (hand is already drawn).
function Game:use_booster_tarot_choice(idx)
    local sess = self.booster_session
    if not sess or type(sess.choices) ~= "table" then return false end
    local ch = sess.choices[idx]
    if not ch or ch.taken then return false end
    if (tonumber(sess.picks_remaining) or 0) <= 0 then return false end

    local c = ch.consumable_def
    if not c then return false end
    if not self:pack_consumable_can_apply(c) then return false end

    self:track_consumable_use(c)
    self:apply_consumable_effect(c)

    ch.taken = true
    local node = sess.choice_nodes and sess.choice_nodes[idx]
    if node then
        self:remove(node)
        sess.choice_nodes[idx] = nil
    end
    sess.active_choice_index = nil
    if self.hand and self.hand.clear_selection then
        self.hand:clear_selection()
    end
    self.active_tooltip_card = nil
    sess.picks_remaining = math.max(0, (tonumber(sess.picks_remaining) or 0) - 1)
    if sess.hand_for_tarot then
        self:_booster_discard_pack_hand_maybe_refill()
    end
    if (tonumber(sess.picks_remaining) or 0) <= 0 then
        self:end_booster_session()
    end
    return true
end

--- Blind just beaten: recycle deck, pay reward, show round-win screen (then shop).
--- Interest: +$1 per full $5 held (only the first $25 counts toward the divisor; max +$5).
function Game:apply_joker_sticker_round_end()
    if type(self.jokers) ~= "table" then return end
    for _, joker in ipairs(self.jokers) do
        if joker then
            if joker.perishable == true then
                local counter = math.max(0, (tonumber(joker.perishable_counter) or 5) - 1)
                joker.perishable_counter = counter
                if counter <= 0 then
                    joker.perishable_debuffed = true
                end
            end
            if joker.rental == true then
                self.money = (tonumber(self.money) or 0) - 3
            end
        end
    end
end

function Game:enter_round_win_after_blind()
    Sfx.play("resources/sounds/win.ogg")
    if tonumber(self.current_blind_index) == 3 then
        self.boss_runtime = self.boss_runtime or {}
        self.boss_runtime.clear_card_debuffs_after_win = true
    end
    local hands_left = math.max(0, math.floor(tonumber(self.hands) or 0))
    self._round_win_joker_payout_lines = {}

    self:apply_joker_sticker_round_end()

    local ctx = self:prepare_joker_event_ctx("on_round_end", {
        hands_left = hands_left,
        is_boss_blind = (tonumber(self.current_blind_index) == 3),
        round_score = tonumber(self.round_score) or 0,
        blind_name = self.current_blind_name,
        last_played_hand_index = tonumber(self.last_played_hand_index) or nil,
    })
    function ctx.add_round_win_payout(label, amt)
        amt = math.floor(tonumber(amt) or 0)
        if amt <= 0 then return end
        self.money = (tonumber(self.money) or 0) + amt
        table.insert(self._round_win_joker_payout_lines, { label, amt, "info" })
        if JokerEffects and JokerEffects.mark_effect_applied then
            JokerEffects.mark_effect_applied(ctx)
        end
        if Sfx and Sfx.play_money then Sfx.play_money() end
    end
    self:emit_joker_event("on_round_end", ctx)
    self:emit_hand_cards_event("on_round_end", ctx)

    if tonumber(self.current_blind_index) == 3 then
        for _, tag in ipairs(self.tags or {}) do
            if tag and tag.type == "investment" then
                ctx.add_round_win_payout("Investment Tag", 25)
            end
        end
        for i = #self.tags, 1, -1 do
            local tag = self.tags[i]
            if tag and tag.type == "investment" then
                self:removeTag(i)
            end
        end

        -- If Anaglyph Deck - Add Double Tag
        if (G._deck_special or nil) == "anaglyph" then
            self:addTag("double")
        end
    end

    self:recycle_full_deck_after_blind_win()
    local cap_dollars = self:get_interest_round_cap_dollars()
    local interest_count_cap = cap_dollars * 5
    local interest = math.floor(math.min(math.max(0, self.money), interest_count_cap) / 5)
    interest = math.min(interest, cap_dollars)
    if self._deck_no_interest then interest = 0 end

    if self.extra_hand_bonus or 0 ~= 0 then
        ctx.add_round_win_payout("Hand Bonus", self.extra_hand_bonus * self.hands)
    end

    if self.extra_discard_bonus or 0 ~= 0 then
        ctx.add_round_win_payout("Discard Bonus", self.extra_discard_bonus * self.discards)
    end

    local blind_pay = math.max(0, math.floor(tonumber(self.current_blind_reward) or 0))

    self._round_win_display_lines = {
        { "Blind reward", blind_pay, "pending" },
        { string.format("Hands left (%d)", hands_left), hands_left, "pending" },
        { string.format("Interest ($1 / $5 held, max $%d)", cap_dollars), interest, "pending" },
    }
    for _, row in ipairs(self._round_win_joker_payout_lines) do
        self._round_win_display_lines[#self._round_win_display_lines + 1] = row
    end
    self._round_win_joker_payout_lines = nil

    self._round_win_line_timer = 0
    self._round_win_lines_revealed = 0
    if self._round_win_display_lines and #self._round_win_display_lines > 0 then
        self:_reveal_one_round_win_line()
    end
    self:set_state(self.STATES.ROUND_EVAL)
end

--- Apply the next visible payout line; pending lines add money here (first line also runs from `enter_round_win_after_blind`).
function Game:_reveal_one_round_win_line()
    local lines = self._round_win_display_lines
    if not lines or #lines == 0 then return end
    local i = (self._round_win_lines_revealed or 0) + 1
    if i > #lines then return end
    self._round_win_lines_revealed = i
    local row = lines[i]
    local kind = row[3]
    if kind == "pending" then
        local amt = math.floor(tonumber(row[2]) or 0)
        if amt ~= 0 then
            self.money = (tonumber(self.money) or 0) + amt
            if Sfx and Sfx.play_money then Sfx.play_money() end
        end
    end
end

--- Add any remaining blind/hands/interest before leaving the round-win screen.
function Game:flush_round_win_pending_payouts()
    local lines = self._round_win_display_lines
    if not lines then return end
    local r = self._round_win_lines_revealed or 0
    for i = r + 1, #lines do
        local row = lines[i]
        if row[3] == "pending" then
            local amt = math.floor(tonumber(row[2]) or 0)
            if amt ~= 0 then
                self.money = (tonumber(self.money) or 0) + amt
            end
        end
    end
    self._round_win_lines_revealed = #lines
end

function Game:update_round_win_eval(dt)
    local lines = self._round_win_display_lines
    if not lines or #lines == 0 then return end
    local revealed = self._round_win_lines_revealed or 0
    if revealed >= #lines then return end
    self._round_win_line_timer = (self._round_win_line_timer or 0) + dt
    while (self._round_win_line_timer >= ROUND_WIN_LINE_DELAY) and revealed < #lines do
        self._round_win_line_timer = self._round_win_line_timer - ROUND_WIN_LINE_DELAY
        self:_reveal_one_round_win_line()
        revealed = self._round_win_lines_revealed or 0
    end
end

function Game:enter_shop_after_blind()
    self:set_state(self.STATES.SHOP)
    self:init_shop_gamepad_nav()
    self.shop_reroll_count = 0
    for i = #self.tags, 1, -1 do
        local tag = self.tags[i]
        if tag and tag.type == "d6" then
            self._shop_reroll_base_cost_override = 0
            self:removeTag(i)
        end
    end
    self:roll_shop_offers()
    self:roll_shop_boosters()
    if self:hasTag("coupon") ~= -1 then -- Coupon effect is added when calculating prices so its safe to remove after shop is rolled
        self:removeTag(self:hasTag("coupon"))
    end
    self:maybe_roll_shop_voucher_on_shop_enter()
    self:sync_shop_booster_nodes()
    self:sync_shop_voucher_nodes()
    self:emit_joker_event("on_shop_enter", {
        offers = self.shop_offers,
        reroll_count = self.shop_reroll_count,
    })
end

function Game:continue_from_round_win()
    self:flush_round_win_pending_payouts()
    self._round_win_display_lines = nil
    self._round_win_lines_revealed = nil
    self._round_win_line_timer = nil
    -- Ante 8 boss beaten: show You Win before the shop (Endless continues into shop).
    if self._last_completed_blind_was_boss and (tonumber(self.ante) or 1) == 8 and not self._endless_mode then
        self:enter_you_win()
        return
    end
    self:enter_shop_after_blind()
end

function Game:enter_you_win()
    self.active_tooltip_card = nil
    self.active_tooltip_joker = nil
    self.active_tooltip_consumable_index = nil
    self.dragging = nil
    self._you_win_button_rects = nil
    self:record_stake_victory()
    self:record_joker_wins_at_victory()
    self:set_state(self.STATES.YOU_WIN)
end

function Game:save_you_win_run()
    local snapshot = self:build_run_snapshot()
    if not snapshot then return false end
    snapshot.resume_state = self.STATES.YOU_WIN
    return self:write_run_snapshot(snapshot)
end

function Game:continue_from_you_win_new_run()
    -- Save the won run first; clear only happens when a new run actually starts.
    self:save_you_win_run()
    self._pause_prev_state = nil
    self._pause_save_error = nil
    self:enter_main_menu()
    MainMenuUI.open_deck_select(self)
end

function Game:continue_from_you_win_main_menu()
    -- Persist the won run so Continue Run can return to the You Win screen.
    self:save_you_win_run()
    self:enter_main_menu()
end

function Game:continue_from_you_win_endless()
    self._endless_mode = true
    self:enter_shop_after_blind()
end

function Game:do_random(min,max,goal)
    local g = goal or 1
    if(G:hasJoker("j_oops")) then
        print("OOPS")
        return math.random(min,max) <= g * self:count_jokers_with_id("j_oops")
    else
        return math.random(min,max) == g
    end

end

function Game:remove_owned_joker_at(index, force)
    if not force then force = false end
    if type(index) ~= "number" or index < 1 then return nil end
    if type(self.jokers) ~= "table" then return nil end
    local joker = self.jokers[index]
    if not joker then return nil end
    if self.active_tooltip_joker == joker then
        self.active_tooltip_joker = nil
    end
    if joker.eternal and not force then
        return nil
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
    local price = self:get_shop_offer_price(offer)
    if not self:can_afford_price(price) then return false end

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
        local cap_after = self:joker_base_capacity() + neg_owned + (new_neg and 1 or 0)
        if #self.jokers >= cap_after then return false end
        local create_params = nil
        local def = JOKER_DEFS and JOKER_DEFS[offer.id]
        if type(offer.create_params) == "table" then
            create_params = copy_table and copy_table(offer.create_params) or nil
        elseif offer.edition and offer.edition ~= "base" then
            create_params = { edition = offer.edition }
        end
        if type(def) == "table" and type(create_params) ~= "table" then
            local sticker_flags = {}
            local sticker_def = def.stickers
            if def.rental == true or (type(sticker_def) == "table" and sticker_def.rental == true) then
                sticker_flags.rental = true
            end
            if def.perishable == true or (type(sticker_def) == "table" and sticker_def.perishable == true) then
                sticker_flags.perishable = true
            end
            if def.eternal == true or (type(sticker_def) == "table" and sticker_def.eternal == true) then
                sticker_flags.eternal = true
            end
            if next(sticker_flags) ~= nil then
                create_params = create_params or {}
                for k, v in pairs(sticker_flags) do
                    create_params[k] = v
                end
            end
        end
        ok = self:add_joker_by_def(offer.id, create_params) and true or false
    elseif k == "tarot" or k == "planet" or k == "spectral" then
        local params = offer.edition and { edition = offer.edition } or nil
        if not self:can_add_consumable(params) then return false end
        ok = self:add_consumable(offer.id, params)
    elseif k == "playing_card" then
        ok = self:_deck_inject_playing_card(offer.card_data)
    else
        return false
    end

    if not ok then return false end

    self.money = (tonumber(self.money) or 0) - price
    self.active_shop_booster_slot = nil
    self:record_card_purchased(1)
    self:emit_joker_event("on_shop_buy", {
        offer = offer,
        offer_kind = offer.kind or "joker",
        offer_id = offer.id,
        offer_price = price,
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
    self:refresh_shop_prices()
    self:layout_shop_panels()
    return true
end

function Game:buy_and_use_shop_consumable(slot_index)
    if type(slot_index) ~= "number" or slot_index < 1 then return false end
    local offer = self.shop_offers and self.shop_offers[slot_index]
    if type(offer) ~= "table" then return false end
    local kind = offer.kind
    if kind ~= "tarot" and kind ~= "planet" and kind ~= "spectral" then return false end
    local price = self:get_shop_offer_price(offer)
    if not self:can_afford_price(price) then return false end
    if not self:shop_offer_consumable_use_enabled(offer) then return false end
    local def = CONSUMABLE_DEFS and CONSUMABLE_DEFS[offer.id]
    if type(def) ~= "table" then return false end
    local c = copy_table and copy_table(def) or nil
    if type(c) ~= "table" then return false end
    c.id = offer.id

    self.money = (tonumber(self.money) or 0) - price
    self.active_shop_booster_slot = nil
    self:record_card_purchased(1)
    self:emit_joker_event("on_shop_buy", {
        offer = offer,
        offer_kind = offer.kind or "consumable",
        offer_id = offer.id,
        offer_price = price,
    })
    self:track_consumable_use(c)
    self:apply_consumable_effect(c)

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
    self:refresh_shop_prices()
    self:layout_shop_panels()
    return true
end

function Game:sell_owned_joker(index)
    local joker = self.jokers and self.jokers[index]
    local invisible_ready = false
    if joker and joker.def and joker.def.id == "j_invisible" then
        local rounds = math.floor(tonumber(joker.runtime_counter) or 0)
        local required = math.max(1, math.floor(tonumber(joker.def and joker.def.config and joker.def.config.extra) or 2))
        if rounds < required then
            invisible_ready = false
        else 
            invisible_ready = true
        end
    end
    joker = self:remove_owned_joker_at(index)
    if not joker then return false end
    local value = tonumber(joker.sell_cost) or 0
    self.money = (tonumber(self.money) or 0) + value
    local duplicated_from_invisible = false
    if invisible_ready and type(self.jokers) == "table" and #self.jokers > 0 then
        local src = self.jokers[math.random(1, #self.jokers)]
        if src and src.def and src.def.id and self.add_joker_by_def then
            local src_edition = Joker and Joker.normalize_edition and Joker.normalize_edition(src.edition) or tostring(src.edition or "base")
            local clone_edition = (src_edition == "negative") and "base" or src_edition
            if self:add_joker_by_def(src.def.id, { edition = clone_edition }) then
                local clone = self.jokers[#self.jokers]
                if clone and self.deep_copy_card_data then
                    for k, v in pairs(src) do
                        if type(v) ~= "function" and k ~= "def" and k ~= "params" and k ~= "effect_impl"
                            and k ~= "T" and k ~= "VT" and k ~= "velocity" and k ~= "drag"
                            and k ~= "hovering" and k ~= "_hover_last" and k ~= "_touch_state"
                            and k ~= "children" and k ~= "parent" and k ~= "front_quads"
                            and k ~= "back_quads" and k ~= "sprite_batch" then
                            if type(v) == "table" then
                                clone[k] = self:deep_copy_card_data(v)
                            else
                                clone[k] = v
                            end
                        end
                    end
                    clone.edition = clone_edition
                    if clone.refresh_quads then clone:refresh_quads() end
                    duplicated_from_invisible = true
                end
            end
        end
    end
    self:emit_joker_event("on_joker_sold", {
        joker = joker,
        sold_value = value,
        invisible_duplicated = duplicated_from_invisible,
    })
    self:boss_on_joker_sold(joker)
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
    local mr_bones_index = nil
    local goal = (tonumber(self.current_blind_target) or 0) * 0.25
    local score = tonumber(self.round_score) or 0
    if type(self.jokers) == "table" and score >= goal then
        for i, j in ipairs(self.jokers) do
            if j and j.def and j.def.id == "j_mr_bones" then
                mr_bones_index = i
                break
            end
        end
    end
    if mr_bones_index then
        self:remove_owned_joker_at(mr_bones_index,true)
        if Sfx and Sfx.play then
            Sfx.play("resources/sounds/slice1.ogg")
        end
        self._blind_resolution_pending = false
        self:recycle_full_deck_after_blind_win()

        local cap_dollars = self:get_interest_round_cap_dollars()
        local interest_count_cap = cap_dollars * 5
        local interest = math.floor(math.min(math.max(0, self.money), interest_count_cap) / 5)
        interest = math.min(interest, cap_dollars)
        self.money = (tonumber(self.money) or 0) + interest
        self:enter_shop_after_blind()
        return
    end

    self._game_over_blind_label = self:get_blind_display_name(self.current_blind_index) or "Blind"
    self._game_over_score = tonumber(self.round_score) or 0
    self._game_over_target = tonumber(self.current_blind_target) or 0
    self._game_over_ante = tonumber(self.ante) or 1
    self._game_over_round = tonumber(self.round) or 1
    self.active_tooltip_card = nil
    self.active_tooltip_joker = nil
    self.active_tooltip_consumable_index = nil
    self.dragging = nil
    if type(self.consumables) == "table" then
        for i = #self.consumables, 1, -1 do
            self:remove_consumable_at(i)
        end
    end
    if self.hand and self.hand.clear then
        self.hand:clear()
    end
    if Sfx and Sfx.play then
        Sfx.play("resources/sounds/cancel.ogg")
    end
    self:clear_run_snapshot()
    self:set_state(self.STATES.GAME_OVER)
end

function Game:set_jokers_location(on_bottom)
    if self.jokers_on_bottom == (on_bottom == true) then return end
    local from_bottom = self.jokers_on_bottom == true
    local to_bottom = on_bottom == true

    self._joker_swap_pick_index = nil
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
            local slot_h = self.joker_slot_h or 94
            local h = slot_h * s
            local delta_y = (slot_h * s * (1 - s)) / 2
            start_y = -(h + 60) - delta_y -- guaranteed < 0 (effective visible)
        else
            -- Start below the bottom slots so it feels like sliding up.
            local s = self.joker_slot_scale_bottom or 1
            local slot_h = self.joker_slot_h or 94
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

function Game:swap_jokers_at_indices(from_idx, to_idx)
    if not self.jokers then return false end
    from_idx = math.floor(tonumber(from_idx) or 0)
    to_idx = math.floor(tonumber(to_idx) or 0)
    if from_idx < 1 or to_idx < 1 or from_idx > #self.jokers or to_idx > #self.jokers then
        return false
    end
    if from_idx == to_idx then return false end
    self.jokers[from_idx], self.jokers[to_idx] = self.jokers[to_idx], self.jokers[from_idx]
    self:_apply_joker_layout()
    if self.jokers_sliding ~= true then
        for _, j in ipairs(self.jokers) do
            if j and j.VT and j.T then
                j.VT.x = j.T.x
                j.VT.y = j.T.y
                j.VT.scale = j.T.scale
            end
        end
    end
    return true
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

    local node = table.remove(self.jokers, from_idx)
    table.insert(self.jokers, to_idx, node)

    self:_apply_joker_layout()

    if self.jokers_sliding ~= true then
        for _, j in ipairs(self.jokers) do
            if j and j.VT and j.T then
                j.VT.x = j.T.x
                j.VT.y = j.T.y
                j.VT.scale = j.T.scale
            end
        end
    end
    return true
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

local function node_is_hand_card(self, node)
    if not node or not self or not self.hand or not self.hand.card_nodes then return false end
    for _, hn in ipairs(self.hand.card_nodes) do
        if hn == node then return true end
    end
    return false
end

local function node_is_owned_joker(self, node)
    if not node or not self or not self.jokers then return false end
    for _, j in ipairs(self.jokers) do
        if j == node then return true end
    end
    return false
end

local function node_is_shop_offer(self, node)
    if not node or not self or not self.shop_offer_nodes then return false end
    for _, j in ipairs(self.shop_offer_nodes) do
        if j == node then return true end
    end
    return false
end

local function node_is_shop_booster_node(node)
    return node and node.shop_booster_slot ~= nil
end

local function node_is_shop_voucher_node(node)
    return node and node.shop_voucher_slot ~= nil
end

local function node_is_booster_choice(node)
    return node and node._booster_choice_index ~= nil
end

local function node_is_owned_consumable(self, node)
    if not node or not self or not self.consumable_nodes then return false end
    for idx, cnode in ipairs(self.consumable_nodes) do
        if cnode == node then return true, idx end
    end
    return false, nil
end

local function node_is_zone_draggable(self, node)
    if not node then return false end
    if node_is_shop_offer(self, node) then return true end
    if node_is_shop_booster_node(node) then return true end
    if node_is_shop_voucher_node(node) then return true end
    if node_is_booster_choice(node) then return true end
    if node_is_owned_joker(self, node) then return true end
    if node_is_owned_consumable(self, node) then return true end
    return false
end

local function begin_node_drag(self, id, x, y, node)
    self.touch_start_x = x
    self.touch_start_y = y
    if node.touchpressed then
        node:touchpressed(id, x, y)
    end
    self.dragging = node
    self:move_to_front(node)
end

function Game:touchpressed(id, x, y)
    if self.STATE == self.STATES.MENU then
        if self._menu_sub_state == "collection_grid" then
            CollectionUI.handle_touchpressed(self, id, x, y)
            return
        end
        if self._menu_sub_state == "collection_menu" then
            CollectionUI.handle_touch_menu(self, x, y)
            return
        end
        MainMenuUI.handle_touch(self, x, y)
        return
    end
    if self._deck_view_open then
        DeckViewUI.handle_touchpressed(self, id, x, y)
        return
    end
    if self.STATE == self.STATES.PAUSED then
        if self._pause_show_settings then
            -- Settings page touch
            for _, r in ipairs(self._pause_speed_rects or {}) do
                if self:_point_in_rect_simple(x, y, r) then
                    if self.set_game_speed then
                        self:set_game_speed(r.speed)
                    elseif self.SETTINGS then
                        self.SETTINGS.GAMESPEED = r.speed
                    end
                    return
                end
            end
            local slider = self._pause_music_slider_rect
            if slider and self:_point_in_rect_simple(x, y, slider) then
                self._pause_music_slider_drag = true
                local vol = self:_music_volume_from_slider_x(x)
                if vol ~= nil then self:set_music_volume(vol, { skip_save = true }) end
                return
            end
            if self._pause_back_rect and self:_point_in_rect_simple(x, y, self._pause_back_rect) then
                if self._pause_music_slider_drag then
                    self:save_settings()
                end
                self._pause_show_settings = false
                self._pause_music_slider_drag = false
                return
            end
            return
        end
        -- Main pause page touch
        if self._pause_continue_rect and self:_point_in_rect_simple(x, y, self._pause_continue_rect) then
            self:exit_pause_menu()
            return
        end
        if self._pause_settings_rect and self:_point_in_rect_simple(x, y, self._pause_settings_rect) then
            self._pause_show_settings = true
            return
        end
        if self._pause_new_run_rect and self:_point_in_rect_simple(x, y, self._pause_new_run_rect) then
            self:enter_main_menu_deck_select()
            return
        end
        if self._pause_save_quit_rect and self:_point_in_rect_simple(x, y, self._pause_save_quit_rect) then
            self:pause_save_and_quit()
            return
        end
        return
    end
    if self.STATE == self.STATES.GAME_OVER then
        return
    end
    if self.STATE == self.STATES.YOU_WIN then
        return
    end
    if self.STATE == self.STATES.OPEN_BOOSTER then
        if BoosterPackUI.handle_touch_pressed(self, id, x, y) then
            return
        end
        if self.booster_session and self.booster_session.hand_for_tarot and self.hand and self.hand.card_nodes then
            self.touch_start_x = x
            self.touch_start_y = y
            local node = self:get_node_at(x, y)
            if node and node.touchpressed and node_is_hand_card(self, node) then
                node:touchpressed(id, x, y)
                self.dragging = node
                self:move_to_front(node)
                return
            end
        end
        if self.jokers_on_bottom == true then
            local node = self:get_owned_joker_at(x, y)
            if node and node_is_owned_joker(self, node) then
                begin_node_drag(self, id, x, y, node)
                return
            end
        end
        return
    end
    if self.STATE == self.STATES.BLIND_SELECT then
        if self:try_boss_reroll_press(x, y) then
            return
        end
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
        local node = self:get_node_at(x, y)
        if node and node_is_shop_offer(self, node) then
            begin_node_drag(self, id, x, y, node)
            return
        end
        if node and node_is_shop_booster_node(node) then
            begin_node_drag(self, id, x, y, node)
            return
        end
        if node and node_is_shop_voucher_node(node) then
            begin_node_drag(self, id, x, y, node)
            return
        end
        if node and select(1, node_is_owned_consumable(self, node)) then
            begin_node_drag(self, id, x, y, node)
            return
        end
        if node and self.jokers_on_bottom == true and node_is_owned_joker(self, node) then
            begin_node_drag(self, id, x, y, node)
            return
        end
        if self:handle_shop_touch(x, y) then return end
        self:clear_shop_selection()
        return
    end
    local pack_hand_move = (self.STATE == self.STATES.OPEN_BOOSTER and self.booster_session and self.booster_session.hand_for_tarot)
    local selecting_hand = (self.STATE == self.STATES.SELECTING_HAND) or pack_hand_move
    local joker_touch_state = (self.STATE == self.STATES.BLIND_SELECT or self.STATE == self.STATES.ROUND_EVAL or self.STATE == self.STATES.OPEN_BOOSTER) and self.jokers_on_bottom == true
    local consumable_touch_state = (self.STATE ~= self.STATES.BLIND_SELECT and self.STATE ~= self.STATES.ROUND_EVAL and self.STATE ~= self.STATES.OPEN_BOOSTER and self.STATE ~= self.STATES.SHOP) and self.jokers_on_bottom ~= true
    if not selecting_hand and not joker_touch_state and not consumable_touch_state then return end
    if selecting_hand and self.hand and self.hand.is_scoring_active and self.hand:is_scoring_active() then return end
    -- Owned jokers on the bottom row take priority over hand cards / other nodes.
    if self.jokers_on_bottom == true and not pack_hand_move then
        local joker = self:get_owned_joker_at(x, y)
        if joker and node_is_owned_joker(self, joker) then
            begin_node_drag(self, id, x, y, joker)
            return
        end
    end
    self.touch_start_x = x
    self.touch_start_y = y
    local node = self:get_node_at(x, y)
    if node and joker_touch_state and not pack_hand_move
        and (not node_is_owned_joker(self, node)) and (not node_is_owned_consumable(self, node)) then
        node = nil
    end
    if node and consumable_touch_state then
        local is_cons = select(1, node_is_owned_consumable(self, node))
        if is_cons then
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
    if self.STATE == self.STATES.MENU and self._menu_sub_state == "collection_grid" then
        CollectionUI.handle_touchmoved(self, id, x, y, dx, dy)
        return
    end
    if self._deck_view_open then
        DeckViewUI.handle_touchmoved(self, id, x, y, dx, dy)
        return
    end
    if self.STATE == self.STATES.PAUSED then
        if self._pause_show_settings and self._pause_music_slider_drag then
            local vol = self:_music_volume_from_slider_x(x)
            if vol ~= nil then self:set_music_volume(vol, { skip_save = true }) end
        end
        return
    end
    if self.STATE == self.STATES.GAME_OVER or self.STATE == self.STATES.YOU_WIN then
        return
    end
    local pack_hand_move = (self.STATE == self.STATES.OPEN_BOOSTER and self.booster_session and self.booster_session.hand_for_tarot)
    local selecting_hand = (self.STATE == self.STATES.SELECTING_HAND) or pack_hand_move
    local joker_touch_state = (self.STATE == self.STATES.BLIND_SELECT or self.STATE == self.STATES.SHOP or self.STATE == self.STATES.ROUND_EVAL or self.STATE == self.STATES.OPEN_BOOSTER) and self.jokers_on_bottom == true
    local consumable_touch_state = (self.STATE ~= self.STATES.BLIND_SELECT and self.STATE ~= self.STATES.ROUND_EVAL and self.STATE ~= self.STATES.OPEN_BOOSTER and self.STATE ~= self.STATES.SHOP)
    local zone_drag_state = (self.STATE == self.STATES.SHOP or self.STATE == self.STATES.OPEN_BOOSTER)
        and self.dragging and node_is_zone_draggable(self, self.dragging)
    -- Owned jokers can also be dragged while selecting a hand (reorder / sell).
    local owned_joker_drag = self.jokers_on_bottom == true and self.dragging and node_is_owned_joker(self, self.dragging)
    if not selecting_hand and not joker_touch_state and not consumable_touch_state and not zone_drag_state and not owned_joker_drag then return end
    if selecting_hand and self.hand and self.hand.is_scoring_active and self.hand:is_scoring_active() then return end
    if zone_drag_state then
        if self.dragging.touchmoved then
            self.dragging:touchmoved(id, x, y, dx, dy)
        end
        return
    end
    if self.dragging and select(1, node_is_owned_consumable(self, self.dragging)) and self.jokers_on_bottom ~= true then
        if self.dragging.touchmoved then
            self.dragging:touchmoved(id, x, y, dx, dy)
        end
        return
    end
    if self.dragging and joker_touch_state then
        if not node_is_owned_joker(self, self.dragging)
            and not (pack_hand_move and node_is_hand_card(self, self.dragging)) then
            return
        end
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
    if self.STATE == self.STATES.MENU and self._menu_sub_state == "collection_grid" then
        CollectionUI.handle_touchreleased(self, id, x, y)
        return
    end
    if self._deck_view_open then
        DeckViewUI.handle_touchreleased(self, id, x, y)
        return
    end
    if self.STATE == self.STATES.PAUSED then
        if self._pause_music_slider_drag then
            self:save_settings()
        end
        self._pause_music_slider_drag = false
        self.dragging = nil
        return
    end
    if self.STATE == self.STATES.GAME_OVER then
        GameOverUI.handle_touch(self, x, y)
        self.dragging = nil
        return
    end
    if self.STATE == self.STATES.YOU_WIN then
        YouWinUI.handle_touch(self, x, y)
        self.dragging = nil
        return
    end
    local pack_hand_move = (self.STATE == self.STATES.OPEN_BOOSTER and self.booster_session and self.booster_session.hand_for_tarot)
    local selecting_hand = (self.STATE == self.STATES.SELECTING_HAND) or pack_hand_move
    local shop_offer_touch_state = (self.STATE == self.STATES.SHOP)
    local joker_touch_state = (self.STATE == self.STATES.BLIND_SELECT or self.STATE == self.STATES.SHOP or self.STATE == self.STATES.ROUND_EVAL or self.STATE == self.STATES.OPEN_BOOSTER) and self.jokers_on_bottom == true
    local tapped_consumable = false
    if self.STATE ~= self.STATES.BLIND_SELECT and self.STATE ~= self.STATES.ROUND_EVAL and self.STATE ~= self.STATES.OPEN_BOOSTER and self.jokers_on_bottom ~= true then
        local node_at = self:get_node_at(x, y)
        local is_c = select(1, node_is_owned_consumable(self, node_at))
        tapped_consumable = is_c == true
    end
    local zone_drag_touch_state = (self.STATE == self.STATES.SHOP or self.STATE == self.STATES.OPEN_BOOSTER)
        and self.dragging and node_is_zone_draggable(self, self.dragging)
    if not selecting_hand and not joker_touch_state and not tapped_consumable and not shop_offer_touch_state and not zone_drag_touch_state then
        self.dragging = nil
        return
    end
    if selecting_hand and self.hand and self.hand.is_scoring_active and self.hand:is_scoring_active() then
        self.dragging = nil
        return
    end
    if joker_touch_state and self.dragging and not node_is_owned_joker(self, self.dragging) and not node_is_zone_draggable(self, self.dragging) then
        if not (pack_hand_move and node_is_hand_card(self, self.dragging)) then
            self.dragging = nil
            return
        end
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
    local zone_action_done = false

    if released then
        local ctx = self:resolve_drag_context(released)
        if ctx then
            local rect = released.get_collision_rect and released:get_collision_rect()
            local cx = rect and (rect.x + rect.w * 0.5) or x
            local cy = rect and (rect.y + rect.h * 0.5) or y
            local zones = self:get_drag_zones_for_context(ctx)
            local zone_id, zone = DragZonesUI.hit_test(zones, cx, cy)
            if zone_id and zone and zone.enabled then
                zone_action_done = self:perform_drag_zone_action(ctx, zone_id, zone) or false
            end
            -- Snap shop/booster merchandise back; owned jokers/consumables use reorder below.
            local is_merchandise = ctx.kind == "shop_offer" or ctx.kind == "shop_booster"
                or ctx.kind == "shop_voucher" or ctx.kind == "booster_choice"
            if not zone_action_done and is_merchandise then
                self:_snap_layout_after_drag(released)
            end
        end
    end

    -- Reorder owned inventory unless a zone action (sell/use) already consumed the drop.
    if not zone_action_done and released and self.jokers and self.jokers_on_bottom and node_is_owned_joker(self, released) then
        local rmin = self.joker_reorder_drag_threshold and self.joker_reorder_drag_threshold() or 22
        if dist >= rmin then
            reordered = self:try_reorder_joker_after_drag(released, x) or false
            if reordered then
                self.active_tooltip_joker = nil
            end
        end
    end
    if not zone_action_done and released and self.consumable_nodes and self.jokers_on_bottom ~= true then
        local is_cons = node_is_owned_consumable(self, released)
        if is_cons then
            local rmin = 22
            if dist >= rmin then
                reordered = self:try_reorder_consumable_after_drag(released, x) or reordered
                if reordered then
                    self.active_tooltip_joker = nil
                    self.active_tooltip_card = nil
                end
            end
        end
    end

    if not zone_action_done and dist < TAP_THRESHOLD and self.STATE == self.STATES.SHOP and released then
        if node_is_shop_offer(self, released) then
            local was_selected = (self.active_tooltip_joker == released)
            self:clear_shop_selection()
            if not was_selected then
                self.active_tooltip_joker = released
                self:sync_shop_focus_index_from_selection()
            end
        elseif node_is_shop_booster_node(released) then
            local slot = tonumber(released.shop_booster_slot)
            local was_selected = (self.active_shop_booster_slot == slot)
            self:clear_shop_selection()
            if not was_selected then
                self.active_shop_booster_slot = slot
                self:sync_shop_focus_index_from_selection()
            end
        elseif node_is_shop_voucher_node(released) then
            local slot = tonumber(released.shop_voucher_slot)
            local was_selected = (self.active_tooltip_shop_voucher_slot == slot)
            self:clear_shop_selection()
            if not was_selected then
                self.active_tooltip_shop_voucher_slot = slot
                self:sync_shop_focus_index_from_selection()
            end
        elseif select(1, node_is_owned_consumable(self, released)) then
            local _, idx = node_is_owned_consumable(self, released)
            local was_selected = (self.active_tooltip_consumable_index == idx)
            self:clear_shop_selection()
            if not was_selected then
                self.active_tooltip_consumable_index = idx
            end
        elseif self.jokers_on_bottom and node_is_owned_joker(self, released) then
            local was_selected = (self.active_tooltip_joker == released)
            self:clear_shop_selection()
            if not was_selected then
                self.active_tooltip_joker = released
                self:move_to_front(released)
            end
        end
    end

    -- Tap (no reorder drag): toggle owned joker tooltip (non-shop states).
    if released and self.STATE ~= self.STATES.SHOP and self.jokers_on_bottom and node_is_owned_joker(self, released) and not reordered and not zone_action_done and dist < TAP_THRESHOLD then
        local was_selected = (self.active_tooltip_joker == released)
        self:clear_bottom_tooltips()
        if not was_selected then
            self.active_tooltip_joker = released
            self:move_to_front(released)
        end
    end

    -- Tap booster choice: toggle its tooltip.
    if not zone_action_done and dist < TAP_THRESHOLD and self.STATE == self.STATES.OPEN_BOOSTER and released and node_is_booster_choice(released) then
        local idx = tonumber(released._booster_choice_index)
        local sess = self.booster_session
        local was_selected = sess and tonumber(sess.active_choice_index) == idx
        self:clear_bottom_tooltips()
        if not was_selected and sess then
            sess.active_choice_index = idx
            self.active_tooltip_joker = released
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
                self:set_dpad_cursor_for_node(node)
                self.hand:toggle_selection(node)
                self.active_tooltip_consumable_index = nil
                break
            end
        end
    end
    -- Joker selection toggles in `touchpressed`; card-body tap does not buy.
    -- Tap on a Consumable node (Tarot / Planet) in the top-right of the bottom screen.
    -- Selecting shows the Use/Sell buttons; the button performs the action.
    if dist < TAP_THRESHOLD and self.STATE ~= self.STATES.SHOP and self.STATE ~= self.STATES.BLIND_SELECT and self.STATE ~= self.STATES.ROUND_EVAL and self.jokers_on_bottom ~= true then
        local node_at = self:get_node_at(x, y)
        local is_c, idx = node_is_owned_consumable(self, node_at)
        if is_c and idx and not reordered and not zone_action_done then
            local was_selected = (self.active_tooltip_consumable_index == idx)
            self:clear_bottom_tooltips()
            if not was_selected then
                self.active_tooltip_consumable_index = idx
            end
            self.dragging = nil
            return
        end
    end

    if not released and dist < TAP_THRESHOLD then
        local node_at = self:get_node_at(x, y)
        if node_at and (node_is_shop_offer(self, node_at) or node_is_owned_joker(self, node_at)) then
            self.dragging = nil
            return
        end
        self:clear_bottom_tooltips()
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

function Game:reset_gamepad_nav()
    self._gamepad_bottom_layer = nil
    self._gamepad_focus_layer = "hand"
    self._consumable_focus_index = nil
    self._shop_focus_index = nil
    self._joker_focus_index = nil
    self._joker_swap_pick_index = nil
    self._dpad_cursor_index = nil
end

function Game:is_booster_hand_mode()
    if self.STATE ~= self.STATES.OPEN_BOOSTER then return false end
    local sess = self.booster_session
    return sess and sess.hand_for_tarot == true
end

function Game:get_gamepad_focus_layer()
    return self._gamepad_focus_layer or "hand"
end

function Game:set_gamepad_focus_layer(layer)
    self._joker_swap_pick_index = nil
    if layer == "jokers" then
        self._gamepad_focus_layer = "jokers"
        if #(self.jokers or {}) > 0 then
            self:joker_gamepad_focus_at(tonumber(self._joker_focus_index) or 1)
        end
    elseif layer == "consumables" then
        self._gamepad_focus_layer = "consumables"
        if self.jokers_on_bottom then
            self:set_jokers_location(false)
        end
        local n = self.consumable_nodes and #self.consumable_nodes or 0
        if n > 0 then
            self:consumable_gamepad_focus_at(tonumber(self._consumable_focus_index) or 1)
        end
    elseif layer == "booster" then
        self._gamepad_focus_layer = "booster"
        self:booster_gamepad_focus_first()
    else
        self._gamepad_focus_layer = "hand"
        self.active_tooltip_joker = nil
        self.active_tooltip_consumable_index = nil
        self:ensure_dpad_cursor()
    end
end

function Game:handle_gamepad_overlay_joker_vertical(button, return_layer)
    if button ~= "up" and button ~= "dpup" and button ~= "down" and button ~= "dpdown" then
        return false
    end
    if #(self.jokers or {}) == 0 then return false end
    local up = (button == "up" or button == "dpup")

    if up then
        if not self.jokers_on_bottom then
            self:set_jokers_location(true)
            self._gamepad_bottom_layer = "jokers"
            self._joker_swap_pick_index = nil
            self:joker_gamepad_focus_at(1)
            return true
        end
        if self._gamepad_bottom_layer ~= "jokers" then
            self._gamepad_bottom_layer = "jokers"
            self._joker_swap_pick_index = nil
            self:joker_gamepad_focus_at(tonumber(self._joker_focus_index) or 1)
            return true
        end
        return false
    end

    if not up then
        if self.jokers_on_bottom or self._gamepad_bottom_layer == "jokers" then
            if self.jokers_on_bottom then
                self:set_jokers_location(false)
            end
            self._gamepad_bottom_layer = return_layer
            self._joker_swap_pick_index = nil
            self.active_tooltip_joker = nil
            if return_layer == "shop" and tonumber(self._shop_focus_index) then
                self:sync_shop_gamepad_focus()
            end
            return true
        end
        return false
    end
end

function Game:handle_gamepad_focus_vertical(button)
    if button ~= "up" and button ~= "dpup" and button ~= "down" and button ~= "dpdown" then
        return false
    end
    local up = (button == "up" or button == "dpup")

    if self.STATE == self.STATES.SHOP then
        return self:handle_gamepad_shop(button)
    end

    if self.STATE == self.STATES.OPEN_BOOSTER and not self:is_booster_hand_mode() then
        return self:handle_gamepad_overlay_joker_vertical(button, "booster")
    end

    if self:is_booster_hand_mode() then
        if up then
            self:set_gamepad_focus_layer("booster")
        else
            self:set_gamepad_focus_layer("hand")
        end
        return true
    end

    if self.STATE ~= self.STATES.SELECTING_HAND then
        return false
    end

    if up then
        if self.jokers_on_bottom then
            self:set_jokers_location(false)
            self:set_gamepad_focus_layer("hand")
        else
            self:set_jokers_location(true)
            self:set_gamepad_focus_layer("jokers")
        end
        return true
    end

    local layer = self:get_gamepad_focus_layer()
    if layer == "consumables" then
        self:set_gamepad_focus_layer("hand")
    else
        if self.jokers_on_bottom then
            self:set_jokers_location(false)
        end
        self:set_gamepad_focus_layer("consumables")
    end
    return true
end

function Game:clear_shop_selection()
    self:clear_bottom_tooltips()
    self._shop_focus_index = nil
    self._joker_focus_index = nil
    self._joker_swap_pick_index = nil
end

function Game:sync_shop_focus_index_from_selection()
    if self.STATE ~= self.STATES.SHOP then return end
    local targets = self:build_shop_focus_targets()
    for i, t in ipairs(targets) do
        if t.kind == "offer" and self.active_tooltip_joker == t.node then
            self._shop_focus_index = i
            return
        end
        if t.kind == "voucher" and tonumber(self.active_tooltip_shop_voucher_slot) == t.slot then
            self._shop_focus_index = i
            return
        end
        if t.kind == "booster" and tonumber(self.active_shop_booster_slot) == t.slot then
            self._shop_focus_index = i
            return
        end
    end
    if self.jokers_on_bottom and self.active_tooltip_joker then
        for _, j in ipairs(self.jokers or {}) do
            if j == self.active_tooltip_joker then
                self._shop_focus_index = nil
                return
            end
        end
    end
    self._shop_focus_index = nil
end

function Game:is_shop_item_selected(node)
    if self.STATE ~= self.STATES.SHOP or not node then return false end
    if node.shop_offer_slot and self.active_tooltip_joker == node then return true end
    if node.shop_voucher_slot and tonumber(self.active_tooltip_shop_voucher_slot) == tonumber(node.shop_voucher_slot) then
        return true
    end
    if node.shop_booster_slot and tonumber(self.active_shop_booster_slot) == tonumber(node.shop_booster_slot) then
        return true
    end
    local idx = self.active_tooltip_consumable_index
    if idx and self.consumable_nodes and self.consumable_nodes[idx] == node then return true end
    if self.jokers_on_bottom and self.active_tooltip_joker == node then
        for _, j in ipairs(self.jokers or {}) do
            if j == node then return true end
        end
    end
    return false
end

function Game:shop_joker_selection_lift_y(node)
    if not node then return 0 end
    if self:is_joker_swap_pick(node) then return -8 end
    if self:is_gamepad_joker_focused(node) then return -8 end
    if not self:is_shop_item_selected(node) then return 0 end
    if Joker and node.is and node:is(Joker) and node.shop_offer_slot == nil and self.jokers_on_bottom then
        return -8
    end
    return 0
end

function Game:init_shop_gamepad_nav()
    self._gamepad_bottom_layer = "shop"
    self._shop_focus_index = nil
    self._joker_focus_index = nil
    self._joker_swap_pick_index = nil
end

function Game:init_booster_gamepad_nav()
    self._gamepad_bottom_layer = "booster"
    self._joker_swap_pick_index = nil
    if self:is_booster_hand_mode() then
        self._gamepad_focus_layer = "booster"
    else
        self._gamepad_focus_layer = "hand"
    end
    self:booster_gamepad_focus_first()
end

function Game:ensure_shop_gamepad_nav()
    if self._gamepad_bottom_layer == nil then
        self._gamepad_bottom_layer = "shop"
    end
end

function Game:build_shop_focus_targets()
    local targets = {}
    for i, node in ipairs(self.shop_offer_nodes or {}) do
        local offer = self.shop_offers and self.shop_offers[i]
        if node and offer then
            targets[#targets + 1] = { kind = "offer", slot = i, node = node }
        end
    end
    for i, node in ipairs(self.shop_voucher_nodes or {}) do
        local offer = self.shop_voucher_offers and self.shop_voucher_offers[i]
        if node and offer then
            targets[#targets + 1] = { kind = "voucher", slot = i, node = node }
        end
    end
    for i, node in ipairs(self.shop_booster_nodes or {}) do
        local offer = self.shop_booster_offers and self.shop_booster_offers[i]
        if node and offer then
            targets[#targets + 1] = { kind = "booster", slot = i, node = node }
        end
    end
    return targets
end

function Game:get_shop_gamepad_focus()
    if self.STATE ~= self.STATES.SHOP or self._gamepad_bottom_layer ~= "shop" then
        return nil
    end
    local idx = tonumber(self._shop_focus_index)
    if not idx then return nil end
    local targets = self:build_shop_focus_targets()
    if #targets == 0 then return nil end
    idx = math.max(1, math.min(#targets, idx))
    return targets[idx]
end

function Game:sync_shop_gamepad_tooltips(target)
    self.active_tooltip_joker = nil
    self.active_tooltip_card = nil
    self.active_tooltip_consumable_index = nil
    self.active_shop_booster_slot = nil
    self.active_tooltip_shop_voucher_slot = nil
    if not target then return end
    if target.kind == "offer" and target.node then
        self.active_tooltip_joker = target.node
        self:move_to_front(target.node)
    elseif target.kind == "voucher" then
        self.active_tooltip_shop_voucher_slot = target.slot
    elseif target.kind == "booster" then
        self.active_shop_booster_slot = target.slot
    end
end

function Game:sync_shop_gamepad_focus()
    local idx = tonumber(self._shop_focus_index)
    if not idx then return end
    local targets = self:build_shop_focus_targets()
    if #targets == 0 then
        self:clear_shop_selection()
        return
    end
    idx = math.max(1, math.min(#targets, idx))
    self._shop_focus_index = idx
    self:sync_shop_gamepad_tooltips(targets[idx])
end

function Game:shop_gamepad_move(delta)
    local targets = self:build_shop_focus_targets()
    if #targets == 0 then return nil end
    self:ensure_shop_gamepad_nav()
    delta = math.floor(tonumber(delta) or 0)
    local idx = tonumber(self._shop_focus_index)
    if not idx then
        idx = (delta >= 0) and 1 or #targets
    else
        idx = idx + delta
        if idx < 1 then idx = #targets elseif idx > #targets then idx = 1 end
    end
    self._shop_focus_index = idx
    local target = targets[idx]
    self:sync_shop_gamepad_tooltips(target)
    return target
end

function Game:joker_gamepad_focus_at(idx)
    if not self.jokers or #self.jokers == 0 then return nil end
    idx = math.max(1, math.min(#self.jokers, math.floor(tonumber(idx) or 1)))
    self._joker_focus_index = idx
    self:clear_bottom_tooltips()
    local node = self.jokers[idx]
    if node then
        self.active_tooltip_joker = node
        self:move_to_front(node)
    end
    return node
end

function Game:joker_gamepad_move(delta)
    if not self.jokers or #self.jokers == 0 then return nil end
    delta = math.floor(tonumber(delta) or 0)
    local idx = tonumber(self._joker_focus_index)
    if not idx then
        idx = (delta >= 0) and 1 or #self.jokers
    else
        idx = idx + delta
        if idx < 1 then idx = #self.jokers elseif idx > #self.jokers then idx = 1 end
    end
    return self:joker_gamepad_focus_at(idx)
end

function Game:consumable_gamepad_focus_at(idx)
    local nodes = self.consumable_nodes or {}
    if #nodes == 0 then return nil end
    idx = math.max(1, math.min(#nodes, math.floor(tonumber(idx) or 1)))
    self._consumable_focus_index = idx
    self.active_tooltip_joker = nil
    self.active_tooltip_card = nil
    self.active_tooltip_consumable_index = idx
    local node = nodes[idx]
    if node then
        self:move_to_front(node)
    end
    return node
end

function Game:consumable_gamepad_move(delta)
    local nodes = self.consumable_nodes or {}
    if #nodes == 0 then return nil end
    delta = math.floor(tonumber(delta) or 0)
    local idx = tonumber(self._consumable_focus_index)
    if not idx then
        idx = (delta >= 0) and 1 or #nodes
    else
        idx = idx + delta
        if idx < 1 then idx = #nodes elseif idx > #nodes then idx = 1 end
    end
    return self:consumable_gamepad_focus_at(idx)
end

function Game:consumable_reorder_gamepad_step(delta)
    if self.jokers_on_bottom == true then return false end
    local idx = tonumber(self._consumable_focus_index)
    if not idx or not self.consumable_nodes or not self.consumables then return false end
    delta = math.floor(tonumber(delta) or 0)
    if delta == 0 then return false end
    local from_idx = idx
    local to_idx = from_idx + delta
    if to_idx < 1 or to_idx > #self.consumable_nodes then return false end
    local node = table.remove(self.consumable_nodes, from_idx)
    table.insert(self.consumable_nodes, to_idx, node)
    local data = table.remove(self.consumables, from_idx)
    table.insert(self.consumables, to_idx, data)
    self._consumable_focus_index = to_idx
    self.active_tooltip_consumable_index = to_idx
    self:draw_consumables_row()
    return true
end

function Game:joker_reorder_gamepad_step(delta)
    if not self.jokers_on_bottom or not self.jokers then return false end
    local idx = tonumber(self._joker_focus_index)
    if not idx then return false end
    delta = math.floor(tonumber(delta) or 0)
    if delta == 0 then return false end
    local from_idx = idx
    local to_idx = from_idx + delta
    if to_idx < 1 or to_idx > #self.jokers then return false end
    local node = table.remove(self.jokers, from_idx)
    table.insert(self.jokers, to_idx, node)
    self._joker_focus_index = to_idx
    self:joker_gamepad_focus_at(to_idx)
    self:_apply_joker_layout()
    if self.jokers_sliding ~= true then
        for _, j in ipairs(self.jokers) do
            if j and j.VT and j.T then
                j.VT.x = j.T.x
                j.VT.y = j.T.y
                j.VT.scale = j.T.scale
            end
        end
    end
    return true
end

function Game:gamepad_joker_press_select()
    if self.jokers_on_bottom ~= true then return false end
    local layer_ok = false
    if self.STATE == self.STATES.SELECTING_HAND then
        layer_ok = self:get_gamepad_focus_layer() == "jokers"
    elseif self.STATE == self.STATES.SHOP or self.STATE == self.STATES.OPEN_BOOSTER then
        layer_ok = self._gamepad_bottom_layer == "jokers"
    end
    if not layer_ok then return false end
    return self:gamepad_joker_press_a()
end

function Game:gamepad_joker_sell()
    if self.jokers_on_bottom ~= true then return false end
    local layer_ok = false
    if self.STATE == self.STATES.SELECTING_HAND then
        layer_ok = self:get_gamepad_focus_layer() == "jokers"
    elseif self.STATE == self.STATES.SHOP or self.STATE == self.STATES.OPEN_BOOSTER then
        layer_ok = self._gamepad_bottom_layer == "jokers"
    end
    if not layer_ok then return false end
    local idx = tonumber(self._joker_focus_index) or 1
    local node = self.jokers and self.jokers[idx]
    if not node then return false end
    return self:perform_sell_for_target({ kind = "joker", index = idx, node = node }) == true
end

function Game:gamepad_consumable_use()
    if self:get_gamepad_focus_layer() ~= "consumables" then return false end
    local idx = tonumber(self._consumable_focus_index) or tonumber(self.active_tooltip_consumable_index)
    if not idx then return false end
    return self:use_consumable(idx) == true
end

function Game:gamepad_consumable_sell()
    if self:get_gamepad_focus_layer() ~= "consumables" then return false end
    local idx = tonumber(self._consumable_focus_index) or tonumber(self.active_tooltip_consumable_index)
    if not idx then return false end
    local node = self.consumable_nodes and self.consumable_nodes[idx]
    if not node then return false end
    return self:perform_sell_for_target({ kind = "consumable", index = idx, node = node }) == true
end

function Game:handle_gamepad_selecting_hand(button)
    if self.STATE ~= self.STATES.SELECTING_HAND then return false end
    if self.hand and self.hand.is_scoring_active and self.hand:is_scoring_active() then
        return false
    end

    local layer = self:get_gamepad_focus_layer()

    if button == "a" then
        if layer == "hand" then
            local node = self:dpad_cursor_node()
            if node and self.hand then
                self.hand:toggle_selection(node)
            end
            return true
        elseif layer == "jokers" then
            return self:gamepad_joker_press_select()
        elseif layer == "consumables" then
            return self:gamepad_consumable_use()
        end
    end

    if button == "b" then
        if layer == "jokers" then
            return self:gamepad_joker_sell()
        elseif layer == "consumables" then
            return self:gamepad_consumable_sell()
        end
        return false
    end

    if button == "rightshoulder" and layer == "jokers" then
        return self:gamepad_joker_press_select()
    end

    if layer == "hand" then
        if button == "x" and self.hand then
            self.hand:sort_by_suit()
            return true
        end
        if button == "y" and self.hand then
            self.hand:sort_by_rank()
            return true
        end
    end

    return false
end

function Game:handle_gamepad_booster_hand_button(button)
    if not self:is_booster_hand_mode() then return false end
    local layer = self:get_gamepad_focus_layer()

    if button == "a" and layer == "hand" then
        local node = self:dpad_cursor_node()
        if node and self.hand then
            self.hand:toggle_selection(node)
        end
        return true
    end

    if layer == "hand" then
        if button == "x" and self.hand then
            self.hand:sort_by_suit()
            return true
        end
        if button == "y" and self.hand then
            self.hand:sort_by_rank()
            return true
        end
    end

    return false
end

function Game:is_gamepad_joker_focused(joker)
    if self.jokers_on_bottom ~= true then return false end
    if self.STATE == self.STATES.SHOP or self.STATE == self.STATES.OPEN_BOOSTER then
        if self._gamepad_bottom_layer ~= "jokers" then return false end
    elseif self.STATE == self.STATES.SELECTING_HAND then
        if self:get_gamepad_focus_layer() ~= "jokers" then return false end
    else
        return false
    end
    return self.active_tooltip_joker == joker
end

function Game:is_joker_swap_pick(joker)
    local pick = tonumber(self._joker_swap_pick_index)
    if not pick or not self.jokers then return false end
    return self.jokers[pick] == joker
end

function Game:should_draw_gamepad_focus_outline(node)
    if not node then return false end
    if self:is_hand_cursor_active() and self:dpad_cursor_node() == node then
        return true
    end
    if self.STATE == self.STATES.SELECTING_HAND then
        local layer = self:get_gamepad_focus_layer()
        if layer == "jokers" and self:is_gamepad_joker_focused(node) then
            return true
        end
        if layer == "consumables" then
            local idx = tonumber(self._consumable_focus_index) or tonumber(self.active_tooltip_consumable_index)
            if idx and self.consumable_nodes and self.consumable_nodes[idx] == node then
                return true
            end
        end
        if self:is_joker_swap_pick(node) then
            return true
        end
    end
    if self.STATE == self.STATES.SHOP then
        if self:is_shop_item_selected(node) or self:is_joker_swap_pick(node) then
            return true
        end
        return self:is_gamepad_joker_focused(node)
    end
    if self.STATE == self.STATES.OPEN_BOOSTER then
        if self:is_hand_cursor_active() and self:dpad_cursor_node() == node then
            return true
        end
        if self:is_gamepad_joker_focused(node) or self:is_joker_swap_pick(node) then
            return true
        end
        if self._gamepad_bottom_layer ~= "jokers" and not self:is_hand_cursor_active() then
            local sess = self.booster_session
            if sess and node._booster_choice_index then
                return tonumber(sess.active_choice_index) == node._booster_choice_index
            end
        end
    end
    return false
end

function Game:draw_node_gamepad_focus_outline(node)
    if not node or not self:should_draw_gamepad_focus_outline(node) then return end
    local r = node.get_collision_rect and node:get_collision_rect()
    if not r then return end
    local lift_y = self:shop_joker_selection_lift_y(node)
    r = { x = r.x, y = r.y + lift_y, w = r.w, h = r.h }
    local lw = love.graphics.getLineWidth()
    love.graphics.setLineWidth(2)
    if self:is_joker_swap_pick(node) then
        love.graphics.setColor(0.9, 0.7, 0.1, 1)
    else
        love.graphics.setColor(0, 0, 0, 1)
    end
    love.graphics.push()
    local rot = (node.VT and node.VT.r) or 0
    local cx = r.x + r.w / 2
    local cy = r.y + r.h / 2
    love.graphics.translate(cx, cy)
    love.graphics.rotate(rot)
    love.graphics.translate(-cx, -cy)
    love.graphics.rectangle("line", r.x, r.y, r.w, r.h)
    love.graphics.pop()
    love.graphics.setLineWidth(lw)
end

function Game:gamepad_shop_buy()
    local target = self:get_shop_gamepad_focus()
    if not target or not target.node then return false end
    local ctx = self:resolve_drag_context(target.node)
    if not ctx then return false end
    local zones = self:get_drag_zones_for_context(ctx)
    if not zones or not zones.top then return false end
    local ok = self:perform_drag_zone_action(ctx, "top", zones.top)
    if ok then
        self:sync_shop_gamepad_focus()
    end
    return ok == true
end

function Game:gamepad_shop_buy_use()
    local target = self:get_shop_gamepad_focus()
    if not target or not target.node then return false end
    local ctx = self:resolve_drag_context(target.node)
    if not ctx then return false end
    local zones = self:get_drag_zones_for_context(ctx)
    if not zones or not zones.top_right then return false end
    local ok = self:perform_drag_zone_action(ctx, "top_right", zones.top_right)
    if ok then
        self:sync_shop_gamepad_focus()
    end
    return ok == true
end

function Game:gamepad_joker_press_a()
    if self._gamepad_bottom_layer ~= "jokers" or self.jokers_on_bottom ~= true then
        return false
    end
    local idx = tonumber(self._joker_focus_index) or 1
    local pick = tonumber(self._joker_swap_pick_index)
    if not pick then
        self._joker_swap_pick_index = idx
        return true
    end
    if pick == idx then
        self._joker_swap_pick_index = nil
        return true
    end
    self:swap_jokers_at_indices(pick, idx)
    self._joker_swap_pick_index = nil
    self:joker_gamepad_focus_at(idx)
    return true
end

function Game:booster_gamepad_untaken_indices()
    local sess = self.booster_session
    if not sess then return {} end
    local indices = {}
    for i, ch in ipairs(sess.choices or {}) do
        if ch and not ch.taken then
            indices[#indices + 1] = i
        end
    end
    return indices
end

function Game:booster_gamepad_focus_first()
    local sess = self.booster_session
    if not sess then return nil end
    local indices = self:booster_gamepad_untaken_indices()
    if #indices == 0 then return nil end
    sess.active_choice_index = indices[1]
    local node = sess.choice_nodes and sess.choice_nodes[indices[1]]
    if node then self:move_to_front(node) end
    return indices[1]
end

function Game:booster_gamepad_move(delta)
    local sess = self.booster_session
    if not sess then return nil end
    local indices = self:booster_gamepad_untaken_indices()
    if #indices == 0 then return nil end
    local current = tonumber(sess.active_choice_index)
    local pos = 1
    for j, i in ipairs(indices) do
        if i == current then
            pos = j
            break
        end
    end
    if not current then
        pos = 1
    else
        pos = pos + math.floor(tonumber(delta) or 0)
        if pos < 1 then pos = #indices elseif pos > #indices then pos = 1 end
    end
    local idx = indices[pos]
    sess.active_choice_index = idx
    self.active_tooltip_card = nil
    self.active_tooltip_joker = nil
    local node = sess.choice_nodes and sess.choice_nodes[idx]
    if node then self:move_to_front(node) end
    return idx
end

function Game:gamepad_booster_confirm()
    local sess = self.booster_session
    if not sess then return false end
    local idx = tonumber(sess.active_choice_index)
    if not idx then
        idx = self:booster_gamepad_focus_first()
    end
    if not idx then return false end
    local ch = sess.choices and sess.choices[idx]
    if not ch or ch.taken then return false end

    if ch.kind == "tarot" or ch.kind == "spectral" then
        local c = ch.consumable_def
        local needs_hand = false
        if sess.hand_for_tarot then
            if ch.kind == "tarot" then
                needs_hand = self:booster_tarot_needs_hand(c)
            else
                needs_hand = self:booster_spectral_needs_hand(c)
            end
        end
        if needs_hand then
            if self.hand and self.hand.has_selection and self.hand:has_selection() then
                local ok = self:use_booster_tarot_choice(idx)
                if ok then self:booster_gamepad_focus_next_after_pick() end
                return ok == true
            end
            self:set_gamepad_focus_layer("hand")
            return false
        end
    end

    local ok = self:pick_booster_choice(idx)
    if ok then self:booster_gamepad_focus_next_after_pick() end
    return ok == true
end

--- After a pick in a multi-pick (Mega) pack, focus the next untaken card.
function Game:booster_gamepad_focus_next_after_pick()
    local sess = self.booster_session
    if not sess then return nil end
    if (tonumber(sess.picks_remaining) or 0) <= 0 then return nil end
    return self:booster_gamepad_focus_first()
end

function Game:is_booster_mega_pack()
    local sess = self.booster_session
    return sess and tostring(sess.size) == "mega"
end

function Game:handle_gamepad_shop(button)
    if self.STATE ~= self.STATES.SHOP then return false end
    self:ensure_shop_gamepad_nav()

    if button == "up" or button == "dpup" or button == "down" or button == "dpdown" then
        if self:handle_gamepad_overlay_joker_vertical(button, "shop") then
            return true
        end
    end

    if button == "y" and self._gamepad_bottom_layer == "shop" then
        if self._l_held then
            return self:gamepad_shop_buy_use()
        end
        return self:gamepad_shop_buy()
    end

    if button == "a" then
        if self:gamepad_joker_press_a() then return true end
    end

    if button == "b" and self._gamepad_bottom_layer == "jokers" then
        return self:gamepad_joker_sell()
    end

    if button == "rightshoulder" then
        if self._gamepad_bottom_layer == "jokers" then
            return self:gamepad_joker_press_select()
        end
    end

    if button == "x" and self._gamepad_bottom_layer == "shop" then
        if self:reroll_shop_offers() then
            self:clear_shop_selection()
        end
        return true
    end

    return false
end

function Game:gamepad_booster_apply_hand_targeted()
    local sess = self.booster_session
    if not sess or not sess.hand_for_tarot then return false end
    if not self.hand or not self.hand.has_selection or not self.hand:has_selection() then
        return false
    end
    local idx = tonumber(sess.active_choice_index)
    if not idx then
        idx = self:booster_gamepad_focus_first()
    end
    if not idx then return false end
    local ch = sess.choices and sess.choices[idx]
    if not ch or ch.taken then return false end
    if ch.kind ~= "tarot" and ch.kind ~= "spectral" then return false end
    local c = ch.consumable_def
    local needs_hand = false
    if ch.kind == "tarot" then
        needs_hand = self:booster_tarot_needs_hand(c)
    else
        needs_hand = self:booster_spectral_needs_hand(c)
    end
    if not needs_hand then
        local ok = self:pick_booster_choice(idx)
        if ok then self:booster_gamepad_focus_next_after_pick() end
        return ok == true
    end
    local ok = self:use_booster_tarot_choice(idx)
    if ok then self:booster_gamepad_focus_next_after_pick() end
    return ok == true
end

function Game:handle_gamepad_booster(button)
    if self.STATE ~= self.STATES.OPEN_BOOSTER then return false end
    local sess = self.booster_session
    local hand_pack = sess and sess.hand_for_tarot

    if hand_pack then
        if self:handle_gamepad_focus_vertical(button) then return true end
        if self:handle_gamepad_booster_hand_button(button) then return true end
    end

    if button == "a" then
        if self._gamepad_bottom_layer == "jokers" then
            return self:gamepad_joker_press_select()
        end
        if (not hand_pack or not self:is_hand_cursor_active()) and tonumber(sess.active_choice_index) then
            return self:gamepad_booster_confirm()
        end
    end
    if button == "b" and self._gamepad_bottom_layer == "jokers" then
        return self:gamepad_joker_sell()
    end

    if hand_pack and self:is_hand_cursor_active() then
        if button == "rightshoulder" then
            return false
        end
    end

    if button == "rightshoulder" then
        if self._gamepad_bottom_layer == "jokers" then
            return self:gamepad_joker_press_select()
        end
        -- Mega packs: pick on press so one tap uses the card and selects the next.
        if self:is_booster_mega_pack() then
            self._r_booster_confirmed = true
            return self:gamepad_booster_confirm()
        end
        return false
    end

    if (button == "a" or button == "y") and hand_pack and self.hand and self.hand:has_selection() then
        return self:gamepad_booster_apply_hand_targeted()
    end

    return false
end

function Game:_gamepad_horizontal_nav_active()
    if self.STATE == self.STATES.SELECTING_HAND then
        local layer = self:get_gamepad_focus_layer()
        if layer == "hand" and self.hand and #(self.hand.card_nodes or {}) > 0 then
            return true
        end
        if layer == "jokers" and self.jokers_on_bottom and #(self.jokers or {}) > 0 then
            return true
        end
        if layer == "consumables" and self.consumable_nodes and #self.consumable_nodes > 0 then
            return true
        end
        return false
    end
    if self.STATE == self.STATES.SHOP then
        self:ensure_shop_gamepad_nav()
        if self._gamepad_bottom_layer == "shop" and #self:build_shop_focus_targets() > 0 then
            return true
        end
        if self._gamepad_bottom_layer == "jokers" and self.jokers_on_bottom and #(self.jokers or {}) > 0 then
            return true
        end
    end
    if self.STATE == self.STATES.OPEN_BOOSTER and self.booster_session then
        if self:is_hand_cursor_active() then
            return self.hand and #(self.hand.card_nodes or {}) > 0
        end
        if self._gamepad_bottom_layer == "jokers" and self.jokers_on_bottom and #(self.jokers or {}) > 0 then
            return true
        end
        return #self:booster_gamepad_untaken_indices() > 0
    end
    return false
end

function Game:ensure_dpad_cursor()
    if not self.hand or not self.hand.card_nodes then return nil end
    local n = #(self.hand.card_nodes)
    if n == 0 then return nil end
    if not self._dpad_cursor_index then
        self._dpad_cursor_index = 1
    else
        self._dpad_cursor_index = math.max(1, math.min(n, self._dpad_cursor_index))
    end
    return self._dpad_cursor_index
end

function Game:dpad_cursor_node()
    local idx = self:ensure_dpad_cursor()
    if not idx then return nil end
    return self.hand.card_nodes[idx]
end

function Game:set_dpad_cursor_for_node(node)
    if not self.hand or not self.hand.card_nodes or not node then return end
    for i, n in ipairs(self.hand.card_nodes) do
        if n == node then
            self._dpad_cursor_index = i
            return
        end
    end
end

function Game:dpad_cursor_move(delta)
    if not self.hand or not self.hand.card_nodes then return nil end
    local n = #self.hand.card_nodes
    if n == 0 then return nil end
    self:ensure_dpad_cursor()
    local idx = self._dpad_cursor_index + delta
    if idx < 1 then
        idx = n
    elseif idx > n then
        idx = 1
    end
    self._dpad_cursor_index = idx
    return self:dpad_cursor_node()
end

function Game:_dpad_horizontal_dir()
    if not self:_gamepad_horizontal_nav_active() then return 0 end
    local joysticks = love.joystick.getJoysticks()
    local joy = joysticks and joysticks[1]
    if joy and joy.isGamepad and joy:isGamepad() then
        if joy:isGamepadDown("dpleft") then return -1 end
        if joy:isGamepadDown("dpright") then return 1 end
    end
    if love.keyboard.isDown then
        if love.keyboard.isDown("left") or love.keyboard.isDown("l") then return -1 end
        if love.keyboard.isDown("right") or love.keyboard.isDown("r") then return 1 end
    end
    return 0
end

function Game:_reset_dpad_horizontal_repeat()
    self._dpad_h_repeat_dir = nil
    self._dpad_h_repeat_timer = 0
    self._dpad_h_repeat_initial = true
end

function Game:_sweep_toggle_card(node)
    if not self.hand or not node then return end
    if self.hand:is_selected(node) then
        self.hand:toggle_selection(node)
    elseif not self.hand:selection_at_capacity() then
        self.hand:toggle_selection(node)
    end
end

function Game:ensure_sweep_seed()
    if not self:is_sweep_select_mode() or self._r_sweep_seeded then return end
    local node = self:dpad_cursor_node()
    if node then
        self:_sweep_toggle_card(node)
        self._r_sweep_seeded = true
    end
end

--- After tap threshold, seed sweep on the cursor card (quick R tap still plays).
function Game:update_sweep_seed()
    if not self:is_sweep_select_mode() or self._r_sweep_seeded then return end
    local press_time = self._r_press_time
    if not press_time then return end
    if love.timer.getTime() - press_time >= 0.25 then
        self:ensure_sweep_seed()
    end
end

function Game:_dpad_sweep_toggle(node)
    if not self.hand or not node then return end
    self._r_dpad_used = true
    self:_sweep_toggle_card(node)
end

function Game:_dpad_horizontal_step(dir, sweep)
    if self.STATE == self.STATES.SHOP then
        self:ensure_shop_gamepad_nav()
        if self._gamepad_bottom_layer == "jokers" then
            self:joker_gamepad_move(dir)
        else
            self:shop_gamepad_move(dir)
        end
        return
    end

    if self.STATE == self.STATES.SELECTING_HAND then
        local layer = self:get_gamepad_focus_layer()
        if layer == "jokers" then
            if self:is_joker_reorder_mode() then
                self:joker_reorder_gamepad_step(dir)
            else
                self:joker_gamepad_move(dir)
            end
            return
        end
        if layer == "consumables" then
            if self:is_consumable_reorder_mode() then
                self:consumable_reorder_gamepad_step(dir)
            else
                self:consumable_gamepad_move(dir)
            end
            return
        end
    end

    if self.STATE == self.STATES.OPEN_BOOSTER then
        if self._gamepad_bottom_layer == "jokers" and self.jokers_on_bottom then
            if self:is_joker_reorder_mode() then
                self:joker_reorder_gamepad_step(dir)
            else
                self:joker_gamepad_move(dir)
            end
            return
        end
        if not self:is_hand_cursor_active() then
            self:booster_gamepad_move(dir)
            return
        end
    end

    if self:is_hand_reorder_mode() then
        local cursor = self:dpad_cursor_node()
        if self.hand and self.hand.reorder_gamepad_step then
            self.hand:reorder_gamepad_step(dir, cursor)
        end
        return
    end
    if sweep then
        self:ensure_sweep_seed()
    end
    local node = self:dpad_cursor_move(dir)
    if not node or not self.hand then return end
    if sweep then
        self:_dpad_sweep_toggle(node)
    end
end

--- Repeat D-pad left/right while held: navigate, sweep-select (R), or reorder (L).
function Game:update_dpad_horizontal_repeat(dt)
    local reorder = self:is_hand_reorder_mode() or self:is_joker_reorder_mode() or self:is_consumable_reorder_mode()
    local sweep = self:is_sweep_select_mode() and not reorder
    local card_nav = self:is_hand_cursor_active() and not sweep and not reorder
    local horiz_nav = self:_gamepad_horizontal_nav_active() and not card_nav and not sweep and not reorder
    if not sweep and not card_nav and not horiz_nav and not reorder then
        self:_reset_dpad_horizontal_repeat()
        return
    end
    local dir = self:_dpad_horizontal_dir()
    if dir == 0 then
        self:_reset_dpad_horizontal_repeat()
        return
    end
    if self._dpad_h_repeat_dir ~= dir then
        self._dpad_h_repeat_dir = dir
        self._dpad_h_repeat_timer = 0
        self._dpad_h_repeat_initial = true
        self:_dpad_horizontal_step(dir, sweep)
        return
    end
    self._dpad_h_repeat_timer = (self._dpad_h_repeat_timer or 0) + dt
    local threshold = self._dpad_h_repeat_initial and 0.35 or 0.2
    if self._dpad_h_repeat_timer >= threshold then
        self._dpad_h_repeat_timer = 0
        self._dpad_h_repeat_initial = false
        self:_dpad_horizontal_step(dir, sweep)
    end
end

function Game:is_hand_reorder_mode()
    if self._l_held ~= true then return false end
    if not self:is_hand_cursor_active() then return false end
    return true
end

function Game:is_joker_reorder_mode()
    if self._l_held ~= true or self.jokers_on_bottom ~= true then return false end
    if self.STATE == self.STATES.SELECTING_HAND then
        return self:get_gamepad_focus_layer() == "jokers"
    end
    if self.STATE == self.STATES.SHOP or self.STATE == self.STATES.OPEN_BOOSTER then
        return self._gamepad_bottom_layer == "jokers"
    end
    return false
end

function Game:is_consumable_reorder_mode()
    if self._l_held ~= true then return false end
    if self:get_gamepad_focus_layer() ~= "consumables" then return false end
    return self.jokers_on_bottom ~= true
end

function Game:is_sweep_select_mode()
    if self._r_held ~= true then return false end
    if not self:is_hand_cursor_active() then return false end
    return true
end

function Game:is_hand_cursor_active()
    if self.STATE == self.STATES.SELECTING_HAND then
        return self:get_gamepad_focus_layer() == "hand" and self.hand ~= nil
    end
    if self:is_booster_hand_mode() then
        return self:get_gamepad_focus_layer() == "hand" and self.hand ~= nil
    end
    return false
end

---@deprecated use is_hand_cursor_active
function Game:is_card_select_mode()
    return self:is_hand_cursor_active()
end

function Game:enter_card_select_mode()
    self:ensure_dpad_cursor()
end

--- Keep shoulder flags aligned with hardware (release events can be dropped mid-play).
function Game:sync_shoulder_input()
    local l_down, r_down = false, false
    local joysticks = love.joystick.getJoysticks()
    local joy = joysticks and joysticks[1]
    if joy and joy.isGamepad and joy:isGamepad() then
        l_down = joy:isGamepadDown("leftshoulder")
        r_down = joy:isGamepadDown("rightshoulder")
    elseif love.keyboard.isDown then
        l_down = love.keyboard.isDown("q")
        r_down = love.keyboard.isDown("e")
    end
    if not l_down then
        self._l_held = false
        self._l_press_time = nil
    end
    if not r_down then
        self._r_held = false
        self._r_sweep_seeded = false
    end
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

function Game:ensure_joker_sprite_loaded(key)
    if not key then return nil end
    if type(self.JOKER_SPRITES) ~= "table" then self.JOKER_SPRITES = {} end
    local entry = self.JOKER_SPRITES[key]
    if entry and entry.image then return entry end
    if not entry then
        entry = {
            name = key,
            path = "resources/textures/1x/Jokers/" .. key .. ".png",
            image = nil,
            w = (Joker and Joker.SPRITE_W) or 70,
            h = (Joker and Joker.SPRITE_H) or 94,
        }
        self.JOKER_SPRITES[key] = entry
    end
    if not entry.path then return entry end

    local ok, img = pcall(love.graphics.newImage, entry.path, { dpiscale = self.SETTINGS.GRAPHICS.texture_scaling, mipmaps = false })
    local err = ok and nil or img
    if not ok then
        ok, img = pcall(love.graphics.newImage, entry.path, {})
        if not ok then err = img end
    end
    entry.image = ok and img or nil
    entry.load_error = ok and nil or tostring(err)
    return entry
end

function Game:unload_joker_sprite(key)
    if not key or type(self.JOKER_SPRITES) ~= "table" then return false end
    local entry = self.JOKER_SPRITES[key]
    if not entry or not entry.image then return false end
    if entry.image.release then
        pcall(function() entry.image:release() end)
    end
    entry.image = nil
    entry.load_error = nil
    return true
end

function Game:ensure_asset_atlas_loaded(name)
    if not name or not self.ASSET_ATLAS then return nil end
    local atlas = self.ASSET_ATLAS[name]
    if not atlas then return nil end
    if atlas.image then return atlas end
    if not atlas.path then return atlas end

    local ok, img = pcall(love.graphics.newImage, atlas.path, { dpiscale = atlas.dpiscale or self.SETTINGS.GRAPHICS.texture_scaling, mipmaps = false })
    local err = ok and nil or img
    if not ok then
        ok, img = pcall(love.graphics.newImage, atlas.path, {})
        if not ok then err = img end
    end
    atlas.image = ok and img or nil
    atlas.load_error = ok and nil or tostring(err)
    return atlas
end

function Game:ensure_animation_atlas_loaded(name)
    if not name or not self.ANIMATION_ATLAS then return nil end
    local atlas = self.ANIMATION_ATLAS[name]
    if not atlas then return nil end
    if atlas.image then return atlas end
    if not atlas.path then return atlas end

    local ok, img = pcall(love.graphics.newImage, atlas.path, { dpiscale = atlas.dpiscale or self.SETTINGS.GRAPHICS.texture_scaling, mipmaps = false })
    local err = ok and nil or img
    if not ok then
        ok, img = pcall(love.graphics.newImage, atlas.path, {})
        if not ok then err = img end
    end
    atlas.image = ok and img or nil
    atlas.load_error = ok and nil or tostring(err)
    return atlas
end

function Game:unload_animation_atlas(name)
    if not name or not self.ANIMATION_ATLAS then return false end
    local atlas = self.ANIMATION_ATLAS[name]
    if not atlas or not atlas.image then return false end
    if atlas.image.release then
        pcall(function() atlas.image:release() end)
    end
    atlas.image = nil
    atlas.load_error = nil
    return true
end

function Game:unload_asset_atlas(name)
    if not name or not self.ASSET_ATLAS then return false end
    local atlas = self.ASSET_ATLAS[name]
    if not atlas or not atlas.image then return false end
    if atlas.image.release then
        pcall(function() atlas.image:release() end)
    end
    atlas.image = nil
    atlas.load_error = nil
    return true
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
            {name = "shop_sign", path = "resources/textures/1x/ShopSignAnimation.png",px=113,py=60, frames = 4},
            {name = "menu", path = "resources/textures/1x/menu.png", px=128, py=128, frames = 63},
        }
        self.asset_atli = {
            {name = "cards_1", path = "resources/textures/1x/8BitDeck.png",px=72,py=95},
            {name = "cards_2", path = "resources/textures/1x/8BitDeck_opt2.png",px=72,py=95},
            {name = "centers", path = "resources/textures/1x/Enhancers.png",px=72,py=95},
            {name = "Tarot", path = "resources/textures/1x/Tarots.png",px=64,py=96},
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

        -- Animation atlases: menu is large and only needed on the main menu.
        for i=1, #self.animation_atli do
            local entry = self.animation_atli[i]
            local name = entry.name
            self.ANIMATION_ATLAS[name] = {}
            self.ANIMATION_ATLAS[name].name = name
            self.ANIMATION_ATLAS[name].path = entry.path
            self.ANIMATION_ATLAS[name].dpiscale = self.SETTINGS.GRAPHICS.texture_scaling
            self.ANIMATION_ATLAS[name].px = entry.px
            self.ANIMATION_ATLAS[name].py = entry.py
            self.ANIMATION_ATLAS[name].frames = entry.frames
            local eager = name ~= "menu"
            self.ANIMATION_ATLAS[name].image = eager and load_image(entry.path, {dpiscale = self.SETTINGS.GRAPHICS.texture_scaling, mipmaps = false}) or nil
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
