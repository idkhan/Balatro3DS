---@class Game
Game = Object:extend()

local ShopUI = require("shop_ui")
local DragZonesUI = require("drag_zones_ui")
local RoundWinUI = require("round_win_ui")
local GameOverUI = require("game_over_ui")
local BoosterPackUI = require("booster_pack_ui")
local HandActionsUI = require("hand_actions_ui")
local MainMenuUI = require("main_menu_ui")
local DeckViewUI = require("deck_view_ui")
local CollectionUI = require("collection_ui")
local DynaText = require("dyna_text")
local CollectionCatalog = require("collection_catalog")
local YouWinUI = require("you_win")
local TooltipDraw = require("tooltip_draw")
local InputBindings = require("input_bindings")
local BuildFlags = require("build_flags")
local PerformanceLab = require("performance_lab")
local RenderProfiler = require("render_profiler")
local Particles = require("particles")
local Fonts = require("fonts")
local NumberFormat = require("number_format")
local Tilt = require("tilt")
local ScreenWipe = require("screen_wipe")
local JokerDisplay = require("joker_display")

--- Seconds between revealing each payout line on the round-win screen.
---
--- The reference sits on `delay(0.2)` and then queues the row itself at `trigger = 'before',
--- delay = 0.5` (`common_events.lua:953-957`), so a row lands about 0.7 s after the one before
--- it. This was 0.38, which ran the whole cash-out at nearly double speed - and cash-out is the
--- one screen in the game that exists to be read rather than played, so hurrying it is the
--- opposite of what it is for. The per-dollar coin ladder underneath already matches the
--- reference exactly (`round_win_dollar_interval`) and blocks the next row, as it does there.
local ROUND_WIN_LINE_DELAY = 0.7
Game.ROUND_WIN_LINE_DELAY = ROUND_WIN_LINE_DELAY

--- Y of a pulled-down joker / consumable row on the bottom screen.
---
--- The rows are 94-95 px tall, so this is most of the upper half of the screen. It sat at 20
--- until the hand rose 18 px to make room for the action bar (`hand.lua`'s
--- `HAND_BOTTOM_MARGIN`), which pushed a selected card's rank pip up behind the row.
---
--- Pulled-down inventory draws over the hand deliberately (see the deferred-node pass in
--- `Game:draw`): if the player pulled it down, that is what they want to be looking at. So the
--- row moves down by exactly what the hand moved up, which keeps the overlap where it already
--- was rather than merely reducing the growth. A selected card's pip band ends up 5 px under
--- the row - the same 5 px as before either change.
local BOTTOM_INVENTORY_Y = 2
local RUN_SAVE_DIR = "sdmc"
local PROFILE_COUNT = 3
local PROFILE_NAME_MAX_LENGTH = 14
local ACTIVE_PROFILE_PATH = "sdmc/Balatro3DS_active_profile.lua"
--- P1 keeps legacy filenames for older installs.
local SETTINGS_SAVE_PATH_P1 = "sdmc/Balatro3DS_settings.lua"
local RUN_SAVE_PATH_P1 = "sdmc/Balatro3DS_run_save_1.lua"

--- 0-1 roll for cue pitch jitter. Deliberately not `math.random`: that stream is
--- reseeded from `self.SEED` so a run replays identically, and audio must never
--- consume from it. Falls back to a fixed midpoint when love.math is absent.
local function sfx_jitter()
    if love and love.math and love.math.random then return love.math.random() end
    return 0.5
end

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

--- Identifier-shaped strings that are still reserved, so they cannot be emitted as a bare
--- `key=value`. Missing one costs the whole save file rather than one field: `{end=1}` is a
--- syntax error, so the chunk fails to load and the run is gone.
local LUA_KEYWORDS = {
    ["and"] = true, ["break"] = true, ["do"] = true, ["else"] = true,
    ["elseif"] = true, ["end"] = true, ["false"] = true, ["for"] = true,
    ["function"] = true, ["goto"] = true, ["if"] = true, ["in"] = true,
    ["local"] = true, ["nil"] = true, ["not"] = true, ["or"] = true,
    ["repeat"] = true, ["return"] = true, ["then"] = true, ["true"] = true,
    ["until"] = true, ["while"] = true,
}

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
            if type(k) == "string" and k:match("^[%a_][%w_]*$") and not LUA_KEYWORDS[k] then
                key_expr = k
            else
                key_expr = "[" .. serialize_lua_value(k) .. "]"
            end
            parts[#parts + 1] = key_expr .. "=" .. serialize_lua_value(val)
        end
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

---@param seed string|nil Optional eight-character run seed.
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
    self.input_mode = "gamepad"
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
    self._deck_view_hand_panel_open = false
    self._deck_view_hand_panel_t = 0
    self._pause_settings_rect = nil
    self._pause_show_settings = false
    self._pause_speed_rects = {}
    self._pause_music_slider_rect = nil
    self._pause_music_slider_drag = false
    self._pause_sfx_slider_rect = nil
    self._pause_sfx_slider_drag = false
    -- D-pad card cursor and gamepad focus layers (hand / jokers / consumables)
    self._dpad_cursor_index = nil
    self._gamepad_focus_layer = "hand"
    self._consumable_focus_index = nil
    self._role_held = {}
    self._role_press_time = {}
    self._hand_sort_by_rank = true
    self._sweep_seeded = false
    self._cancel_gesture_armed = false
    self._pause_settings_tab = "general"
    self._pause_performance_open_rect = nil
    self._perf_focus_index = 1
    self._perf_toggle_rects = {}
    self._perf_reset_rect = nil
    self._perf_disable_rect = nil
    self._controls_listen_role = nil
    self._controls_listen_slot = nil
    self._controls_role_rects = {}
    self._controls_focus_zone = "list"
    self._controls_focus_col = 1
    self._controls_focus_row = 1
    self._controls_focus_footer = "reset"
    self._pause_focus_index = nil
    self._main_menu_rects = nil
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
    self._booster_closing = nil
    self.shop_offer_slots = 2
    self.shop_reroll_base_cost = 5
    self.shop_reroll_count = 0
    --- Rerolls this shop that were granted for free (Chaos the Clown); these do
    --- not advance the cost escalation.
    self.shop_free_rerolls_used = 0
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
    --- Screen shake accumulator; see Game:shake.
    self.jiggle = 0
    self._jiggle_t = 0
    --- Staggered joker resolution (left-to-right); see `begin_joker_emit` / `_update_joker_emit_queue`.
    self._joker_emit_queue = nil
    self._joker_emit_next = 1
    self._joker_emit_timer = 0
    --- Beat between jokers in a staggered batch. The reference announces a joker through
    --- `card_eval_status_text`'s `extra` branch, which holds for `0.75*1.25`
    --- (`common_events.lua:859,878`) - noticeably longer than a played card's chip pop,
    --- because a joker firing is the thing the player is actually watching for.
    self.JOKER_EMIT_INTERVAL = 0.9375

    -- Run Consumables (Tarot / Planet cards held outside the deck).
    self.consumables = {}
    self.consumable_base_capacity = 2
    self.consumable_capacity = 2
    self._consumable_rects = {}
    self.consumable_nodes = {}
    self.tarots_used = 0
    -- Every distinct consumable used in this run. Satellite counts unique Planets,
    -- not hand levels (reference/Balatro/card.lua:1667-1673).
    self.consumable_usage = {}
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
    self._profile_delete_confirm = false
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
    if self.SEED == nil then self.SEED = self:generate_run_seed() end
    self:seed_rng_stream(self.SEED)
    collectgarbage("setpause", 110)
    collectgarbage("setstepmul", 200)

    -- set filters and load atlases
    self:set_render_settings()

    -- Create joker slots + initial joker instances.
    -- (Top-screen rendering is handled by `TopUI.draw()`)
    self:init_jokers()
end

local RUN_SEED_ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
local RNG_MODULUS = 4294967296

--- Keep only alphanumeric upper-case run identities, matching the reference's visible seed form.
--- `reference/Balatro/functions/misc_functions.lua:270-277`
function Game:normalize_run_seed(seed)
    local value = tostring(seed or ""):upper():gsub("[^0-9A-Z]", "")
    if #value ~= 8 then return nil end
    return value
end

function Game:generate_run_seed()
    local value = ""
    local entropy = os.time()
    if love and love.timer and love.timer.getTime then
        entropy = entropy + math.floor((love.timer.getTime() % 1) * 1000000)
    end
    for i = 1, 8 do
        entropy = (entropy * 1664525 + 1013904223 + i) % RNG_MODULUS
        value = value .. RUN_SEED_ALPHABET:sub((entropy % #RUN_SEED_ALPHABET) + 1, (entropy % #RUN_SEED_ALPHABET) + 1)
    end
    return value
end

--- Cheap numeric hash derived from the reference's pseudohash recurrence.
--- This is deliberately not reference-compatible: this port has different pools and roll order.
--- `reference/Balatro/functions/misc_functions.lua:279-319`
function Game:pseudohash(value)
    local num = 1
    value = tostring(value or "")
    for i = #value, 1, -1 do
        num = ((1.1239285023 / num) * string.byte(value, i) * math.pi + math.pi * i) % 1
    end
    return num
end

function Game:seed_rng_stream(seed)
    if not Game._rng_original_random then
        Game._rng_original_random = math.random
        math.random = function(min, max)
            if G and G._rng_streams then return G:random("default", min, max) end
            return Game._rng_original_random(min, max)
        end
    end
    self.SEED = self:normalize_run_seed(seed) or self:generate_run_seed()
    self._rng_streams = {}
end

--- Draw from a named stream. Stream state, rather than a global draw count, is saved verbatim.
function Game:random(key, min, max)
    key = tostring(key or "default")
    local streams = self._rng_streams
    if type(streams) ~= "table" then
        streams = {}
        self._rng_streams = streams
    end
    local state = streams[key]
    if state == nil then
        state = math.floor(self:pseudohash(key .. self.SEED) * (RNG_MODULUS - 1))
        if state == 0 then state = 1 end
    end
    state = (state * 1664525 + 1013904223) % RNG_MODULUS
    streams[key] = state
    local unit = state / RNG_MODULUS
    if min == nil then return unit end
    if max == nil then
        max, min = min, 1
    end
    min, max = math.floor(min), math.floor(max)
    if max < min then return min end
    return min + math.floor(unit * (max - min + 1))
end

--- Saved streams already contain their exact positions; no replay loop is required.
function Game:restore_rng_stream(seed, streams)
    self:seed_rng_stream(seed)
    if type(streams) == "table" then self._rng_streams = copy_table(streams) end
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

--- The ante that ends the run in victory. The reference carries this as
--- `G.GAME.win_ante` and prints it beside the current ante (`UI_definitions.lua:1319-1326`),
--- which is the only thing on screen telling a new player how long a run is.
---@return integer
function Game:get_win_ante()
    return 8
end

--- Index into `handlist` of the hand The Ox punishes.
---
--- The reference freezes this: `most_played_poker_hand` is recomputed only as a Boss blind is
--- defeated (`state_events.lua:132-138`) and starts the run as High Card (`game.lua:1964`),
--- so the target holds for a whole ante. Recomputing it live let the player re-target the Ox
--- mid-ante by overtaking their own leader, and left it disarmed for the first hand of a run.
---@return integer index into `self.handlist`
function Game:most_played_hand_index()
    local idx = math.floor(tonumber(self.frozen_most_played_hand_index) or 0)
    if idx >= 1 then return idx end
    return self:default_most_played_hand_index()
end

---@return integer handlist index of High Card, the reference's run-start default
function Game:default_most_played_hand_index()
    for i, name in ipairs(self.handlist or {}) do
        if name == "High Card" then return i end
    end
    return #(self.handlist or {})
end

--- Freeze the current leader. Ties go to the earlier handlist entry, which keeps the pick
--- deterministic — `pairs` order is not, and the reference's own tie-break is inert.
function Game:freeze_most_played_hand()
    local best_idx, best_count = nil, 0
    for i in ipairs(self.handlist or {}) do
        local c = tonumber(self.hand_play_counts and self.hand_play_counts[i]) or 0
        if c > best_count then
            best_count = c
            best_idx = i
        end
    end
    self.frozen_most_played_hand_index = best_idx or self:default_most_played_hand_index()
end

function Game:increment_hand_play_count(hand_index)
    local hi = math.floor(tonumber(hand_index) or -1)
    if hi < 1 then return end
    self.hand_play_counts = self.hand_play_counts or {}
    self.blind_hand_play_counts = self.blind_hand_play_counts or {}
    self.hand_play_counts[hi] = (tonumber(self.hand_play_counts[hi]) or 0) + 1
    self.blind_hand_play_counts[hi] = (tonumber(self.blind_hand_play_counts[hi]) or 0) + 1
    -- Career hand usage drives the stats page's "Most Played Hand", which spans runs
    -- (reference `hand_usage`, `game.lua:876+`).
    local name = self.handlist and self.handlist[hi]
    if name then
        if type(self.career_hand_usage) ~= "table" then self.career_hand_usage = {} end
        self.career_hand_usage[name] = (tonumber(self.career_hand_usage[name]) or 0) + 1
        if self.SETTINGS then self.SETTINGS.CAREER_HAND_USAGE = self.career_hand_usage end
    end
end

--- Career bests behind the stats page. Called wherever the underlying value can rise; each
--- is a high-water mark rather than a running total.
function Game:record_run_high_scores()
    self:record_career_best("c_furthest_round", tonumber(self.round) or 0)
    self:record_career_best("c_furthest_ante", tonumber(self.ante) or 0)
    self:record_career_best("c_most_money", tonumber(self.money) or 0)
end

--- Most-played hand across every run on the profile.
---@return string name, integer count
function Game:career_most_played_hand()
    local best, best_count = "None", 0
    for _, name in ipairs(self.handlist or {}) do
        local c = tonumber(self.career_hand_usage and self.career_hand_usage[name]) or 0
        if c > best_count then
            best, best_count = name, c
        end
    end
    return best, best_count
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

function Game:get_boss_blind_id_for_blind()
    if tonumber(self.current_blind_index) ~= 3 then return nil end
    if not self.current_boss_blind_id then return nil end
    if self:hasJoker("j_chicot") then return nil end
    if self.boss_runtime and self.boss_runtime.disable_current_boss_ability == true then return nil end
    return self.current_boss_blind_id
end

function Game:get_active_boss_blind_id()
    if self.STATE ~= self.STATES.SELECTING_HAND then return nil end
    if not self:get_boss_blind_prototype() then return nil end
    return self:get_boss_blind_id_for_blind()
end

function Game:get_effective_hand_size_limit()
    local limit = (self.challenge_rules and tonumber(self.challenge_rules.hand_size)) or 8
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
    local per_dollar = self.challenge_modifiers and tonumber(self.challenge_modifiers.minus_hand_size_per_X_dollar)
    if per_dollar and per_dollar > 0 then
        -- Luxury Tax continuously polls the current balance, rather than applying a
        -- one-shot penalty (reference/Balatro/cardarea.lua:245-250).
        limit = limit - math.floor(math.max(0, tonumber(self.money) or 0) / per_dollar)
    end
    return math.max(1, limit)
end

function Game:get_effective_hands_per_round()
    local hands = (self.challenge_rules and tonumber(self.challenge_rules.hands)) or 4
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
    local discards = (self.challenge_rules and tonumber(self.challenge_rules.discards)) or 3
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
    local i = self:random("cerulean_bell", 1, #cards)
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

--- Turn every owned Joker face up again. Amber Acorn is the only thing that flips them, and
--- the reference undoes the flip in three places rather than one: at the blind's defeat
--- (`reference/Balatro/blind.lua:338`), when the boss ability is disabled mid-round
--- (`:357`), and defensively when the next blind is set. Doing it only at the next blind
--- left the Jokers face down through the cash out, the shop and blind select.
function Game:restore_joker_facing()
    if type(self.jokers) ~= "table" then return end
    for _, j in ipairs(self.jokers) do
        if j and j.face_up == false and j.set_face_up then
            j:set_face_up(true)
        end
    end
end

function Game:boss_reset_for_new_blind()
    self.boss_runtime = {
        hand_count = 0,
        seen_hand_types = {},
        locked_hand_type = nil,
        mouth_void_play = false,
        eye_void_play = false,
        psychic_void_play = false,
        forced_card_uid = nil,
        house_face_down_draws = 0,
        fish_face_down_draws = 0,
        serpent_draws_pending = 0,
        sold_joker_this_blind = false,
        crimson_disabled_joker = nil,
        disable_current_boss_ability = false,
        clear_card_debuffs_after_win = false,
    }
    local boss_id = self:get_boss_blind_id_for_blind()
    self:restore_joker_facing()
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
            local j = self:random("acorn", 1, i)
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

function Game:boss_on_hand_refilled(is_new_blind, refill_reason)
    local boss_id = self:get_active_boss_blind_id()
    if not boss_id or not self.hand or not self.hand.card_nodes then return end
    if boss_id == "bl_final_heart" and (is_new_blind == true or refill_reason == "play") then
        local sorted = {}
        for _, j in ipairs(self.jokers or {}) do
            if j then sorted[#sorted + 1] = j end
        end
        table.sort(sorted, function(a, b)
            local ax = (a.T and a.T.x) or (a.VT and a.VT.x) or 0
            local bx = (b.T and b.T.x) or (b.VT and b.VT.x) or 0
            return ax < bx
        end)
        local count = #sorted
        if count <= 0 then
            self.boss_runtime.crimson_disabled_joker = nil
        elseif count == 1 then
            self.boss_runtime.crimson_disabled_joker = 1
        else
            local prev_idx = tonumber(self.boss_runtime.crimson_disabled_joker)
            local prev_joker = (prev_idx and prev_idx >= 1 and prev_idx <= count) and sorted[prev_idx] or nil
            local candidates = {}
            for i = 1, count do
                if sorted[i] ~= prev_joker then
                    candidates[#candidates + 1] = i
                end
            end
            if #candidates == 0 then
                self.boss_runtime.crimson_disabled_joker = self:random("crimson_heart", 1, count)
            else
                self.boss_runtime.crimson_disabled_joker = candidates[self:random("crimson_heart", 1, #candidates)]
            end
        end
    end
    -- Cerulean Bell forces its card once the hand it is choosing from is actually in front of
    -- the player. The reference picks in `Blind:drawn_to_hand` (`blind.lua:574-586`), which
    -- runs off the draw event, so it sees the finished hand; this used to pick the moment the
    -- refill was *queued*. On a new blind that meant an empty hand and no forced card at all
    -- for the whole first hand, and mid-round it meant picking only from the cards the play
    -- left behind. `Game:boss_on_hand_deal_complete` does it when the queue drains.
    if not (self.hand._draw_queue and #self.hand._draw_queue > 0) then
        self:_boss_select_forced_card_if_needed()
    end
end

--- Every queued draw has landed: the hand is whole again.
function Game:boss_on_hand_deal_complete()
    self:_boss_select_forced_card_if_needed()
end

function Game:boss_on_card_drawn(card_node)
    local boss_id = self:get_active_boss_blind_id()
    if not boss_id or not card_node then return end
    local data = card_node.card_data or {}
    local force_down = false

    if boss_id == "bl_mark" then
        -- Pareidolia makes every card a face card, and the reference's `is_face(true)` honours
        -- it even for a boss check (`blind.lua:615-617`, `card.lua:966-972`) — so under The
        -- Mark the whole hand is dealt face down. The Plant already reads it this way.
        local r = tonumber(data.rank) or 0
        if self:hasJoker("j_pareidolia") or (r >= 11 and r <= 13) then force_down = true end
    end
    if boss_id == "bl_house" and (tonumber(self.boss_runtime.house_face_down_draws) or 0) > 0 then
        force_down = true
        self.boss_runtime.house_face_down_draws = math.max(0, (tonumber(self.boss_runtime.house_face_down_draws) or 0) - 1)
    end
    -- Wheel uses the normal probability value, so Oops! All 6s doubles its odds
    -- (reference functions/button_callbacks.lua:160-168).
    if boss_id == "bl_wheel" and self:do_random(1, 7, 1, "wheel") then
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

--- Absolute number of cards The Serpent draws after a play or discard, or nil to refill the
--- hand as normal. The reference replaces the fill-to-limit with a flat count
--- (`state_events.lua:362-368`: `hand_space = math.min(#G.deck.cards, 3)`), so the hand
--- shrinks over a round. Returning a limit here instead made the boss a no-op, because the
--- hand size is almost always already at or above `current + 3`.
function Game:boss_consume_serpent_draws()
    local boss_id = self:get_active_boss_blind_id()
    if boss_id ~= "bl_serpent" then return nil end
    local pending = math.max(0, math.floor(tonumber(self.boss_runtime.serpent_draws_pending) or 0))
    if pending <= 0 then return nil end
    self.boss_runtime.serpent_draws_pending = 0
    self:notify_boss_effect_triggered({ reason = "serpent_draw_pending" })
    return pending
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
        local i = self:random("hook", 1, #hand.cards)
        if hand.discard_card_at_index then
            hand:discard_card_at_index(i, { hook = true })
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
    self.boss_runtime.mouth_void_play = false
    self.boss_runtime.eye_void_play = false
    self.boss_runtime.psychic_void_play = false
    -- Mouth / Eye / Psychic do not reject the play: the reference consumes the hand and then
    -- skips the entire scoring block, so an illegal hand costs you the hand and scores zero
    -- (`state_events.lua:475` decrements before the `debuff_hand` gate at `:614`;
    -- `blind.lua:519-548` is the gate). Rejecting it here instead made these three bosses
    -- free to retry against.
    local voided = false
    if boss_id == "bl_mouth" then
        if self.boss_runtime.locked_hand_type ~= nil and self.boss_runtime.locked_hand_type ~= hand_name then
            self.boss_runtime.mouth_void_play = true
            voided = true
            self:notify_boss_effect_triggered({ reason = "mouth_void_play" })
        end
    end
    if boss_id == "bl_eye" then
        if self.boss_runtime.seen_hand_types[hand_name] then
            self.boss_runtime.eye_void_play = true
            voided = true
            self:notify_boss_effect_triggered({ reason = "eye_void_play" })
        end
    end
    if boss_id == "bl_psychic" and n < 5 then
        self.boss_runtime.psychic_void_play = true
        voided = true
        self:notify_boss_effect_triggered({ reason = "psychic_min_cards" })
    end
    -- A voided hand is never recorded: the reference returns out of `debuff_hand` before
    -- `self.hands[handname]` / `self.only_hand` are set (`blind.lua:535-547`), so a wasted
    -- hand neither locks the Mouth's type nor burns a type against the Eye.
    if not voided and boss_id == "bl_mouth" and self.boss_runtime.locked_hand_type == nil then
        self.boss_runtime.locked_hand_type = hand_name
    end
    if not voided and boss_id == "bl_eye" then
        self.boss_runtime.seen_hand_types[hand_name] = true
    end
    self.boss_runtime.hand_count = (tonumber(self.boss_runtime.hand_count) or 0) + 1
    if boss_id == "bl_final_bell" then
        local forced_uid = self.boss_runtime.forced_card_uid
        -- Only enforce while the forced card is still in hand
        if forced_uid ~= nil and self:_boss_find_hand_node_by_uid(forced_uid) ~= nil then
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
        elseif forced_uid ~= nil then
            self.boss_runtime.forced_card_uid = nil
        end
    end
    return true
end

function Game:boss_should_void_current_play()
    if not self.boss_runtime then return false end
    return self.boss_runtime.mouth_void_play == true
        or self.boss_runtime.eye_void_play == true
        or self.boss_runtime.psychic_void_play == true
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
        local target_idx = self:most_played_hand_index()
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
    if not node then return false end
    local d = node.card_data or {}
    -- Double or Nothing permanently debuffs cards that have scored.  Keep this in
    -- the normal debuff predicate so display, previews, scoring and Glass agree.
    if d.perma_debuff == true then return true end
    if not boss_id then return false end
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

local function joker_left_of(a, b)
    local ax = (a.T and a.T.x) or (a.VT and a.VT.x) or 0
    local bx = (b.T and b.T.x) or (b.VT and b.VT.x) or 0
    return ax < bx
end

--- Which joker Crimson Heart has disabled, or nil.
---
--- Answered once per frame and cached. `Joker:draw` asks this for every joker, and it used to
--- copy and sort the whole joker list - with a freshly allocated comparator - on each of those
--- calls, which is O(n^2 log n) with n allocations during precisely the blind where the board
--- is busiest. The answer is the same for every joker asking, so it is computed once.
---@return Joker|nil
function Game:boss_crimson_disabled_joker_node()
    if self:get_active_boss_blind_id() ~= "bl_final_heart" then return nil end
    if type(self.jokers) ~= "table" then return nil end

    local frame = self._frame_id or 0
    local cache = self._crimson_disabled_cache
    if cache and cache.frame == frame then return cache.node end

    local sorted = self._crimson_sort_scratch or {}
    self._crimson_sort_scratch = sorted
    for i = #sorted, 1, -1 do sorted[i] = nil end
    for _, j in ipairs(self.jokers) do
        if j then sorted[#sorted + 1] = j end
    end
    table.sort(sorted, joker_left_of)

    local blocked = tonumber(self.boss_runtime and self.boss_runtime.crimson_disabled_joker) or -1
    local node = (blocked >= 1 and blocked <= #sorted) and sorted[blocked] or nil
    self._crimson_disabled_cache = { frame = frame, node = node }
    return node
end

function Game:boss_is_joker_debuffed(node)
    if not node then return false end
    return self:boss_crimson_disabled_joker_node() == node
end

function Game:boss_apply_hand_base_modifiers(chips, mult)
    local boss_id = self:get_active_boss_blind_id()
    chips = tonumber(chips) or 0
    mult = tonumber(mult) or 0
    if boss_id == "bl_flint" then
        -- Round half up, not down (`blind.lua:513`). Flooring halved an odd mult a second
        -- time: Three of a Kind (30/3) landed on 15x1 instead of 15x2.
        chips = math.max(0, math.floor(chips * 0.5 + 0.5))
        mult = math.max(1, math.floor(mult * 0.5 + 0.5))
        self:notify_boss_effect_triggered({ reason = "flint_base_halved" })
    end
    return chips, mult
end

function Game:boss_on_joker_sold(sold_joker)
    if sold_joker and sold_joker.def and sold_joker.def.id == "j_luchador" and self:get_active_boss_blind_id() then
        self.boss_runtime = self.boss_runtime or {}
        self.boss_runtime.disable_current_boss_ability = true
        self.boss_runtime.verdant_leaf_active = false
        -- Disabling the boss undoes its effects, including a face-down Joker row
        -- (`blind.lua:357`).
        self:restore_joker_facing()
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
    -- The reference juices the blind chip and HUD debuff text every time a boss ability
    -- fires (`reference/Balatro/functions/state_events.lua:492-494`, `blind.lua:417-423`) —
    -- without it a card scoring zero is illegible. The port's blind chip lives on the top
    -- readout, so the playfield rattle carries the beat.
    self:shake(1)
    -- Mirrors `G.GAME.blind.triggered` (`reference/Balatro/blind.lua:484`): set when a boss
    -- ability fires, cleared when the next hand is played. Matador reads it at `joker_main`.
    self.blind_triggered_this_hand = true
    self:emit_joker_event("on_boss_effect_triggered", {
        boss_id = boss_id,
        reason = meta and meta.reason or "",
        meta = meta,
    })
end

function Game:clear_shop_offer_nodes()
    self._shop_nodes_gen = (self._shop_nodes_gen or 0) + 1
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
    self._shop_nodes_gen = (self._shop_nodes_gen or 0) + 1
    if type(self.shop_offers) ~= "table" then
        self.shop_offers = {}
    end
    if type(self.shop_offer_nodes) ~= "table" then
        self.shop_offer_nodes = {}
    end
    self._shop_layout_dirty = true
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

    -- Cards that materialise on the shelf this pass and carry an edition: the reference
    -- announces every one of them (`card.lua:430-452`), so the shop is where a player
    -- most often hears foil/holo/polychrome/negative.
    local revealed = nil

    for i, offer in ipairs(self.shop_offers) do
        local node = self.shop_offer_nodes[i]
        local existing = node
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
            node.states.visible = self:shop_nodes_visible()
            node.states.click.can = self:shop_nodes_interactive()
            node.states.drag.can = self:shop_nodes_interactive()
            node.states.collide.can = false
            if node ~= existing then
                local ed = self:shop_offer_edition(offer)
                if ed then
                    node.edition_reveal_pending = ed
                    revealed = revealed or {}
                    revealed[#revealed + 1] = node
                end
            end
        end
    end

    if revealed then self:begin_edition_reveals(revealed) end
end

--- The edition a shop offer will show, or nil for a plain one. Jokers and consumables
--- carry it on the offer; a playing card carries it on its card data, the same split the
--- rest of the shop code uses.
---@param offer table
---@return string|nil
function Game:shop_offer_edition(offer)
    if type(offer) ~= "table" then return nil end
    local ed = offer.edition
    if ed == nil and type(offer.card_data) == "table" then
        local mod = offer.card_data.modifier
        ed = type(mod) == "table" and mod.edition or nil
    end
    if type(ed) ~= "string" then return nil end
    if Joker and Joker.normalize_edition then ed = Joker.normalize_edition(ed) end
    if ed == "base" then return nil end
    return ed
end

function Game:layout_shop_offer_nodes(param)
    ShopUI.layout_shop_offer_nodes(self, param)
end

local function set_shop_node_interactivity(list, visible, interactive)
    for _, node in ipairs(list or {}) do
        if node and node.states then
            node.states.visible = visible
            node.states.click.can = interactive
            node.states.drag.can = interactive
        end
    end
end

function Game:sync_shop_offer_interactivity()
    local active = (self.STATE == self.STATES.SHOP)
    local visible = self:shop_nodes_visible()
    local interactive = self:shop_nodes_interactive()

    -- This runs from Game:draw in every state, but the writes below only change when
    -- one of these three booleans flips or a shop node list is rebuilt (each rebuild
    -- and clear bumps `_shop_nodes_gen`, and rebuilt nodes get their states set at
    -- creation). Everything else is a frame spent rewriting identical fields.
    local memo = self._shop_interactivity_memo
    local gen = self._shop_nodes_gen or 0
    if memo and memo.active == active and memo.visible == visible
        and memo.interactive == interactive and memo.gen == gen then
        return
    end
    if not memo then
        memo = {}
        self._shop_interactivity_memo = memo
    end
    memo.active, memo.visible, memo.interactive, memo.gen = active, visible, interactive, gen

    local tooltip_is_shop_offer = false
    set_shop_node_interactivity(self.shop_offer_nodes, visible, interactive)
    set_shop_node_interactivity(self.shop_booster_nodes, visible, interactive)
    set_shop_node_interactivity(self.shop_voucher_nodes, visible, interactive)
    for _, node in ipairs(self.shop_offer_nodes or {}) do
        if node and self.active_tooltip_joker == node then
            tooltip_is_shop_offer = true
            break
        end
    end
    if not active and tooltip_is_shop_offer then
        self.active_tooltip_joker = nil
    end
end

function Game:clear_shop_booster_nodes()
    self._shop_nodes_gen = (self._shop_nodes_gen or 0) + 1
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
    self._shop_nodes_gen = (self._shop_nodes_gen or 0) + 1
    if type(self.shop_booster_offers) ~= "table" then self.shop_booster_offers = {} end
    if type(self.shop_booster_nodes) ~= "table" then self.shop_booster_nodes = {} end
    self._shop_layout_dirty = true
    if not ShopBoosterNode then return end

    for i = #self.shop_booster_nodes, #self.shop_booster_offers + 1, -1 do
        local node = self.shop_booster_nodes[i]
        if node then self:remove(node) end
        table.remove(self.shop_booster_nodes, i)
    end

    local visible = self:shop_nodes_visible()
    local interactive = self:shop_nodes_interactive()
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
            node.states.visible = visible
            node.states.click.can = interactive
            node.states.drag.can = interactive
        end
    end
end

function Game:clear_shop_voucher_nodes()
    self._shop_nodes_gen = (self._shop_nodes_gen or 0) + 1
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
    self._shop_nodes_gen = (self._shop_nodes_gen or 0) + 1
    if type(self.shop_voucher_offers) ~= "table" then self.shop_voucher_offers = {} end
    if type(self.shop_voucher_nodes) ~= "table" then self.shop_voucher_nodes = {} end
    self._shop_layout_dirty = true
    if not ShopVoucherNode then return end

    for i = #self.shop_voucher_nodes, #self.shop_voucher_offers + 1, -1 do
        local node = self.shop_voucher_nodes[i]
        if node then self:remove(node) end
        table.remove(self.shop_voucher_nodes, i)
    end

    local visible = self:shop_nodes_visible()
    local interactive = self:shop_nodes_interactive()
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
            node.states.visible = visible
            node.states.click.can = interactive
            node.states.drag.can = interactive
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

function Game:draw_shop_price_tags(skip_node)
    ShopUI.draw_shop_price_tags(self, skip_node)
end

function Game:draw_price_tag_for_node(node)
    return ShopUI.draw_price_tag_for_node(self, node)
end

--- The shop node currently being dragged, if any. A dragged card is drawn above the price
--- tags rather than with the rest of the shelf, so it has to be pulled out of the node pass.
function Game:dragged_shop_node()
    local node = self.dragging
    if not node or self.STATE ~= self.STATES.SHOP then return nil end
    if node.shop_offer_slot or node.shop_booster_slot or node.shop_voucher_slot then
        return node
    end
    return nil
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

--- States whose arrival is a safe, meaningful checkpoint. These mirror the reference's
--- `save_run()` call sites — entering the hand, the shop, blind select and the cash-out
--- (`game.lua:3066,3171,3265,3313`) — which is what makes the real game survive being closed
--- at any moment. Scoring is deliberately excluded — a hand mid-ladder does not serialise,
--- and the reference does not check-point inside one either. An open pack does check-point,
--- because `_serialize_booster_session` can rebuild it.
local AUTOSAVE_STATES = {
    SELECTING_HAND = true,
    SHOP = true,
    BLIND_SELECT = true,
    ROUND_EVAL = true,
    OPEN_BOOSTER = true,
}

--- Which backdrop palette a game state calls for, following `ease_background_colour_blind`
--- (`common_events.lua:332-358`). The reference recolours the background on every state
--- change; this is that table, minus the states it leaves alone.
---
--- Absent from this map means "leave the backdrop as it is", which is what the reference does
--- for transient states -- HAND_PLAYED, DRAW_TO_HAND and the like keep whatever the blind set,
--- and recolouring on each of them would strobe.
local BACKDROP_STATES = {
    MENU          = "menu",
    SPLASH        = "menu",
    TAROT_PACK    = "tarot",
    PLANET_PACK   = "planet",
    SPECTRAL_PACK = "spectral",
    STANDARD_PACK = "standard",
    BUFFOON_PACK  = "buffoon",
    SHOP          = "shop",
    GAME_OVER     = "boss",
    BLIND_SELECT  = "blind",
}

--- Point the backdrop at the palette a state calls for.
---
--- Boss blinds are resolved from the blind's own colour rather than the table, because
--- `ease_background_colour_blind` derives theirs from `boss_colour` per blind, and the
--- showdown bosses get the blue-and-red pair outright (`common_events.lua:352`).
function Game:sync_backdrop_state(state_id)
    local Backdrop = self._backdrop or require("backdrop")
    self._backdrop = Backdrop
    if not Backdrop.is_supported() then return end

    if state_id == self.STATES.MENU or state_id == self.STATES.SPLASH then
        Backdrop.set_menu()
        return
    end

    if state_id == self.STATES.WON or (self.GAME and self.GAME.won) then
        Backdrop.set_state("won")
        return
    end

    local name
    for key, palette in pairs(BACKDROP_STATES) do
        if self.STATES[key] == state_id then name = palette break end
    end

    -- A live boss blind outranks the table: its colour is per-blind.
    local blind = self.GAME and self.GAME.blind
    if blind and (state_id == self.STATES.SELECTING_HAND or state_id == self.STATES.NEW_ROUND
        or name == "blind") then
        if blind.boss then
            if blind.showdown then
                Backdrop.set_state("showdown")
            else
                Backdrop.set_boss_colour(blind.boss_colour or blind.colour)
            end
            return
        end
        Backdrop.set_state("blind")
        return
    end

    if name then Backdrop.set_state(name) end
end

function Game:set_state(state_id)
    local prev = self.STATE
    local menu = self.STATES and self.STATES.MENU
    if menu and prev == menu and state_id ~= menu then
        self:unload_animation_atlas("menu")
    end
    self.STATE = state_id
    if prev ~= state_id and self.sync_backdrop_state then
        self:sync_backdrop_state(state_id)
    end
    -- Check-point on arrival at a stable state, the way the reference saves on every state
    -- transition. Without this the only saves were deck-select, save-and-quit and victory,
    -- so closing the lid mid-run lost the run.
    if prev ~= state_id and self.autosave_run then
        for name in pairs(AUTOSAVE_STATES) do
            if self.STATES and state_id == self.STATES[name] then
                self:autosave_run()
                break
            end
        end
    end
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

--- Flag every deck and stake in an unlocks table as available (wins are left untouched).
local function unlock_all_decks_and_stakes(unlocks)
    for _, deck_entry in pairs(unlocks or {}) do
        deck_entry.unlocked = true
        if type(deck_entry.stakes) == "table" then
            for _, stake_entry in pairs(deck_entry.stakes) do
                stake_entry.unlocked = true
            end
        end
    end
    return unlocks
end

--- Mark every collection entry discovered. Decks come from unlocks; seals and
--- editions are always visible, so both are skipped here.
local function discover_all_entries(discovered)
    for _, cat in ipairs(CollectionCatalog.CATEGORIES) do
        if cat.id ~= "decks" and cat.id ~= "seals" and cat.id ~= "editions" then
            for _, entry in ipairs(CollectionCatalog.get_entries(cat.id)) do
                local did = CollectionCatalog.discovery_id_for_entry(entry)
                if did then discovered[did] = true end
            end
        end
    end
    return discovered
end

--- Unlock every deck, stake, and collection discovery on the active profile.
function Game:unlock_everything()
    if not self.unlocks then
        self:apply_unlocks(self:build_unlocks())
    end
    self:apply_unlocks(unlock_all_decks_and_stakes(self.unlocks))
    self:apply_discovered(discover_all_entries(self:normalize_discovered(self.Discovered)))
    self:save_settings()
    return true
end

--- Same as unlock_everything, but targets any profile slot.
function Game:unlock_everything_for_profile(profile_id)
    local id = math.floor(tonumber(profile_id) or self:get_profile_id())
    if id < 1 then id = 1 end
    if id > PROFILE_COUNT then id = PROFILE_COUNT end
    if id == self:get_profile_id() then
        return self:unlock_everything()
    end
    local settings = self:peek_profile_settings(id) or self:default_settings()
    settings.UNLOCKS = unlock_all_decks_and_stakes(self:normalize_unlocks(settings.UNLOCKS))
    settings.DISCOVERED = discover_all_entries(self:normalize_discovered(settings.DISCOVERED))
    return self:write_profile_settings(id, settings)
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

--- Record an edition in the collection. Call this wherever an edition is *applied*, not
--- just where a card carrying one is created: Hex, Wheel of Fortune, Ectoplasm and Aura
--- all stamp an edition onto something that already exists, and none of them pass back
--- through `add_joker` or `Hand:add_card`, so Polychrome could be played for a whole run
--- and still read as undiscovered.
---
--- `normalize_edition` answers "base" for an ordinary card; that is not an edition and
--- must not fill in a collection slot.
---@param edition string|nil
function Game:discover_edition(edition)
    local ed = Joker and Joker.normalize_edition and Joker.normalize_edition(edition) or edition
    if type(ed) ~= "string" or ed == "" or ed == "base" then return end
    self:discover_item("edition_" .. ed)
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
    -- A playing card's edition lives on its modifier table, not at the top level
    -- (`card_edition_for_display` in card.lua reads the same place), so reading only
    -- `card_data.edition` meant a Foil card never registered as discovered.
    local modifier = card_data.modifier
    self:discover_edition(card_data.edition or (type(modifier) == "table" and modifier.edition) or nil)
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
    -- Cartomancer and Astronomer count discovered Tarots / Planets
    -- (`common_events.lua:1424-1441`). Guarded against re-entry: `check_unlock` discovers
    -- the Joker it grants, which lands back here.
    if not self._discovering_item then
        self._discovering_item = true
        self:check_unlock("discover_amount")
        self._discovering_item = nil
    end
    self:save_settings()
    return true
end

--- Jokers earned on this profile. Persisted alongside the deck/stake unlocks.
---@return table<string, boolean>
function Game:build_joker_unlocks()
    return {}
end

---@return table<string, number>
function Game:build_career_stats()
    local out = {}
    for _, name in ipairs(JokerUnlocks.CAREER_STATS) do
        out[name] = 0
    end
    return out
end

---@param data table|nil
---@return table<string, number>
function Game:normalize_career_stats(data)
    local out = self:build_career_stats()
    if type(data) ~= "table" then return out end
    for _, name in ipairs(JokerUnlocks.CAREER_STATS) do
        local v = tonumber(data[name])
        if v and v > 0 then out[name] = math.floor(v) end
    end
    return out
end

---@param data table|nil
---@return table<string, boolean>
function Game:normalize_joker_unlocks(data)
    local out = {}
    if type(data) ~= "table" then return out end
    for id, flag in pairs(data) do
        -- Only ids that are actually gated: a stale key must not resurrect a Joker that has
        -- since been made unconditional, and must not linger in the save forever.
        if flag == true and JokerUnlocks.condition_for(id) then
            out[id] = true
        end
    end
    return out
end

---@param data table|nil
function Game:apply_joker_unlocks(data)
    self.joker_unlocks = self:normalize_joker_unlocks(data)
    if self.SETTINGS then self.SETTINGS.JOKER_UNLOCKS = self.joker_unlocks end
end

---@param data table|nil
---@return table<string, number>
function Game:normalize_career_hand_usage(data)
    local out = {}
    if type(data) ~= "table" then return out end
    for _, name in ipairs(self.handlist or {}) do
        local v = tonumber(data[name])
        if v and v > 0 then out[name] = math.floor(v) end
    end
    return out
end

---@param data table|nil
function Game:apply_career_hand_usage(data)
    self.career_hand_usage = self:normalize_career_hand_usage(data)
    if self.SETTINGS then self.SETTINGS.CAREER_HAND_USAGE = self.career_hand_usage end
end

---@param data table|nil
function Game:apply_career_stats(data)
    self.career_stats = self:normalize_career_stats(data)
    if self.SETTINGS then self.SETTINGS.CAREER_STATS = self.career_stats end
end

---@param id string|nil
---@return boolean
function Game:is_joker_unlocked(id)
    if type(id) ~= "string" then return true end
    local cond = JokerUnlocks.condition_for(id)
    -- No condition means it was never locked.
    if not cond then return true end
    return self.joker_unlocks ~= nil and self.joker_unlocks[id] == true
end

--- Career counters, kept per profile because the conditions that read them span runs.
---@param name string
---@return number
function Game:get_career_stat(name)
    local stats = self.career_stats
    if type(stats) ~= "table" then return 0 end
    return tonumber(stats[name]) or 0
end

---@param name string
---@param amount number|nil defaults to 1
function Game:add_career_stat(name, amount)
    if type(name) ~= "string" then return end
    if type(self.career_stats) ~= "table" then self.career_stats = {} end
    local delta = tonumber(amount) or 1
    self.career_stats[name] = (tonumber(self.career_stats[name]) or 0) + delta
    if self.SETTINGS then self.SETTINGS.CAREER_STATS = self.career_stats end
end

--- Raise a career high-water mark rather than accumulating it.
---@param name string
---@param value number
function Game:record_career_best(name, value)
    if type(name) ~= "string" then return end
    if type(self.career_stats) ~= "table" then self.career_stats = {} end
    local v = tonumber(value) or 0
    if v > (tonumber(self.career_stats[name]) or 0) then
        self.career_stats[name] = v
        if self.SETTINGS then self.SETTINGS.CAREER_STATS = self.career_stats end
    end
end

---@return integer how many consumables of `kind` have been discovered
function Game:count_discovered_consumables(kind)
    local n = 0
    for id, def in pairs(CONSUMABLE_DEFS or {}) do
        if type(def) == "table" and def.kind == kind and self:is_discovered(id) then
            n = n + 1
        end
    end
    return n
end

--- Evaluate joker unlock conditions for one run event, and record anything earned.
---
--- The reference refuses to grant unlocks on a seeded or challenge run
--- (`common_events.lua:1165-1177`), so those runs are skipped here too.
---@param event_type string
---@param data table|nil
---@return string[] newly unlocked joker ids
function Game:check_unlock(event_type, data)
    if type(event_type) ~= "string" or event_type == "" then return {} end
    if self.seeded == true then return {} end
    if self.challenge_id ~= nil then return {} end

    local earned = JokerUnlocks.evaluate(self, event_type, data)
    if #earned == 0 then return earned end

    if type(self.joker_unlocks) ~= "table" then self.joker_unlocks = {} end
    for _, id in ipairs(earned) do
        self.joker_unlocks[id] = true
        -- An unlocked Joker is also a discovered one, so it stops reading as a silhouette.
        self:discover_item(id)
    end
    if self.SETTINGS then self.SETTINGS.JOKER_UNLOCKS = self.joker_unlocks end
    self._newly_unlocked_jokers = self._newly_unlocked_jokers or {}
    for _, id in ipairs(earned) do
        self._newly_unlocked_jokers[#self._newly_unlocked_jokers + 1] = id
    end
    self:save_settings()
    return earned
end

function Game:get_run_deck_id()
    local deck_id = self.selected_deck_id or self._pending_deck_id
    if type(deck_id) == "string" and deck_id ~= "" then return deck_id end
    return nil
end

function Game:get_run_stake_id()
    local stake_id = self.selected_stake_id or self._pending_stake_id
    if type(stake_id) == "string" and stake_id ~= "" then return stake_id end
    return nil
end

function Game:restore_run_deck_stake_from_snapshot(snapshot)
    if type(snapshot) ~= "table" then return end
    local deck_id = snapshot.selected_deck_id
    if type(deck_id) == "string" and deck_id ~= "" then
        self.selected_deck_id = deck_id
    end
    local stake_id = snapshot.selected_stake_id
    if type(stake_id) == "string" and stake_id ~= "" then
        if self.apply_stake_config then
            self:apply_stake_config(stake_id)
        else
            self.selected_stake_id = stake_id
        end
    end
end

--- Persist deck/stake unlocks and owned jokers after Ante 8 victory (idempotent).
function Game:ensure_victory_progress_recorded()
    if self._victory_progress_recorded == true then return true end
    if type(self.challenge_id) == "string" and self.challenge_id ~= "" then
        self:record_challenge_victory(self.challenge_id)
        self._victory_progress_recorded = true
        return true
    end
    if not self:get_run_stake_id() then return false end
    self:record_stake_victory()
    self:record_joker_wins_at_victory()
    self:record_win()
    -- Win conditions read the finished run: how few rounds it took, which hand types were
    -- never played, and the joker slot count (`common_events.lua:1583-1601`).
    self:record_run_high_scores()
    self:add_career_stat("c_current_streak", 1)
    self:record_career_best("c_win_streak", self:get_career_stat("c_current_streak"))
    self:check_unlock("win", { rounds = tonumber(self.round) or 0 })
    self:check_unlock("win_no_hand")
    self:check_unlock("win_custom")
    self._victory_progress_recorded = true
    return true
end

function Game:record_challenge_victory(challenge_id)
    if type(challenge_id) ~= "string" or challenge_id == "" or type(self.SETTINGS) ~= "table" then return false end
    if type(self.SETTINGS.CHALLENGE_WINS) ~= "table" then self.SETTINGS.CHALLENGE_WINS = {} end
    self.SETTINGS.CHALLENGE_WINS[challenge_id] = true
    self:save_settings()
    return true
end

function Game:is_challenge_completed(challenge_id)
    return type(challenge_id) == "string" and self.SETTINGS and type(self.SETTINGS.CHALLENGE_WINS) == "table"
        and self.SETTINGS.CHALLENGE_WINS[challenge_id] == true
end

function Game:get_win_count()
    return math.max(0, math.floor(tonumber(self.SETTINGS and self.SETTINGS.WINS) or 0))
end

--- Bump the profile's lifetime run-win counter and persist it.
function Game:record_win()
    if type(self.SETTINGS) ~= "table" then return false end
    self.SETTINGS.WINS = self:get_win_count() + 1
    self:save_settings()
    return true
end

function Game:record_stake_victory()
    local deck_id = self:get_run_deck_id()
    local stake_id = self:get_run_stake_id()
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

function Game:get_joker_wins_for_save()
    if type(self.joker_wins) == "table" and next(self.joker_wins) ~= nil then
        return self.joker_wins
    end
    if self.SETTINGS and type(self.SETTINGS.JOKER_WINS) == "table" then
        return self.SETTINGS.JOKER_WINS
    end
    return self.joker_wins or self:build_joker_wins()
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
    local stake_id = self:get_run_stake_id()
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
    self._pause_settings_tab = "general"
    self._pause_performance_open_rect = nil
    self._perf_toggle_rects = {}
    self._perf_reset_rect = nil
    self._perf_disable_rect = nil
    self._controls_listen_role = nil
    self._controls_listen_slot = nil
    self._controls_role_rects = {}
    self._controls_focus_zone = "list"
    self._controls_focus_col = 1
    self._controls_focus_row = 1
    self._controls_focus_footer = "reset"
    self._pause_controls_open_rect = nil
    self._pause_controls_reset_rect = nil
    self._pause_speed_rects = {}
    self._pause_music_slider_rect = nil
    self._pause_music_slider_drag = false
    self._pause_sfx_slider_rect = nil
    self._pause_sfx_slider_drag = false
    self._pause_reduced_motion_rect = nil
    self._pause_tilt_rect = nil
    self._pause_joker_display_rect = nil
    self._pause_focus_index = 1
    self:set_state(self.STATES.PAUSED)
    return true
end

function Game:controls_list_at(col, row)
    col = math.floor(tonumber(col) or 1)
    row = math.floor(tonumber(row) or 1)
    local role = InputBindings.ROLES[row]
    if not role then return nil, nil end
    if col < 1 or col > InputBindings.SLOTS_PER_ROLE then return nil, nil end
    return role, col
end

function Game:controls_list_dims()
    return InputBindings.SLOTS_PER_ROLE, #InputBindings.ROLES
end

function Game:reset_controls_grid_focus()
    self._controls_focus_zone = "list"
    self._controls_focus_col = 1
    self._controls_focus_row = 1
    self._controls_focus_footer = "reset"
end

function Game:pause_controls_nav(button)
    if self._pause_settings_tab ~= "controls" then return false end
    local cols, rows = self:controls_list_dims()

    if self._controls_focus_zone == "footer" then
        if button == "left" or button == "dpleft" then
            self._controls_focus_footer = "reset"
            return true
        end
        if button == "right" or button == "dpright" then
            self._controls_focus_footer = "back"
            return true
        end
        if button == "up" or button == "dpup" then
            self._controls_focus_zone = "list"
            self._controls_focus_row = rows
            return true
        end
        return true
    end

    local col = math.floor(tonumber(self._controls_focus_col) or 1)
    local row = math.floor(tonumber(self._controls_focus_row) or 1)

    if button == "left" or button == "dpleft" then
        col = math.max(1, col - 1)
    elseif button == "right" or button == "dpright" then
        col = math.min(cols, col + 1)
    elseif button == "up" or button == "dpup" then
        if row > 1 then
            row = row - 1
        end
    elseif button == "down" or button == "dpdown" then
        if row < rows then
            row = row + 1
        else
            self._controls_focus_zone = "footer"
            self._controls_focus_footer = "reset"
            return true
        end
    else
        return false
    end

    self._controls_focus_col = col
    self._controls_focus_row = row
    return true
end

function Game:activate_controls_focus()
    if self._controls_focus_zone == "footer" then
        if self._controls_focus_footer == "reset" then
            self:reset_control_bindings()
            self._controls_listen_role = nil
            self._controls_listen_slot = nil
            return true
        end
        if self._controls_focus_footer == "back" then
            self._pause_settings_tab = "general"
            self._controls_listen_role = nil
            self._controls_listen_slot = nil
            self:reset_controls_grid_focus()
            self._pause_focus_index = 1
            return true
        end
        return false
    end

    local role, slot = self:controls_list_at(self._controls_focus_col, self._controls_focus_row)
    if role and slot then
        self._controls_listen_role = role
        self._controls_listen_slot = slot
        return true
    end
    return false
end

function Game:build_pause_focus_targets()
    local targets = {}
    if self._pause_show_settings then
        if self._pause_settings_tab == "controls" then
            return targets
        end
        if self._pause_settings_tab == "performance" then
            for i, r in ipairs(self._perf_toggle_rects or {}) do
                targets[#targets + 1] = { kind = "perf_toggle", index = i, rect = r }
            end
            if self._perf_reset_rect then
                targets[#targets + 1] = { kind = "perf_reset", rect = self._perf_reset_rect }
            end
            if self._perf_disable_rect then
                targets[#targets + 1] = { kind = "perf_disable", rect = self._perf_disable_rect }
            end
            if self._pause_back_rect then
                targets[#targets + 1] = { kind = "back", rect = self._pause_back_rect }
            end
            return targets
        end
        for i, r in ipairs(self._pause_speed_rects or {}) do
            if r then targets[#targets + 1] = { kind = "speed", index = i, rect = r } end
        end
        if self._pause_controls_open_rect then
            targets[#targets + 1] = { kind = "controls_open", rect = self._pause_controls_open_rect }
        end
        if self._pause_performance_open_rect then
            targets[#targets + 1] = { kind = "performance_open", rect = self._pause_performance_open_rect }
        end
        -- The volume sliders stay touch-only, as they always have been; the toggles are buttons, so
        -- the pad reaches them like any other.
        if self._pause_reduced_motion_rect then
            targets[#targets + 1] = { kind = "reduced_motion", rect = self._pause_reduced_motion_rect }
        end
        if self._pause_tilt_rect then
            targets[#targets + 1] = { kind = "tilt", rect = self._pause_tilt_rect }
        end
        if self._pause_joker_display_rect then
            targets[#targets + 1] = { kind = "joker_display", rect = self._pause_joker_display_rect }
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
    if self._pause_collection_rect then
        targets[#targets + 1] = { kind = "collection", rect = self._pause_collection_rect }
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
        self._pause_settings_tab = "general"
        self._controls_listen_role = nil
        self._pause_focus_index = 1
        return true
    elseif t.kind == "controls_open" then
        self:end_pause_slider_drag()
        self._pause_settings_tab = "controls"
        self._controls_listen_role = nil
        self:reset_controls_grid_focus()
        self._pause_focus_index = 1
        return true
    elseif t.kind == "performance_open" then
        self:end_pause_slider_drag()
        self._pause_settings_tab = "performance"
        self._pause_focus_index = 1
        return true
    elseif t.kind == "tilt" then
        self:set_tilt_enabled(not self:tilt_enabled())
        return true
    elseif t.kind == "joker_display" then
        self:set_joker_display_enabled(not self:joker_display_enabled())
        return true
    elseif t.kind == "perf_toggle" and t.rect and t.rect.experiment_id then
        PerformanceLab.toggle(t.rect.experiment_id)
        RenderProfiler.reset()
        return true
    elseif t.kind == "reduced_motion" then
        self:set_reduced_motion(not self:reduced_motion_enabled())
        return true
    elseif t.kind == "perf_reset" then
        RenderProfiler.reset()
        return true
    elseif t.kind == "perf_disable" then
        PerformanceLab.disable_all()
        RenderProfiler.reset()
        return true
    elseif t.kind == "control_role" and t.role then
        self._controls_listen_role = t.role
        return true
    elseif t.kind == "controls_reset" then
        self:reset_control_bindings()
        self._controls_listen_role = nil
        return true
    elseif t.kind == "collection" then
        self:open_collection_over_run()
        return true
    elseif t.kind == "new_run" then
        if self.enter_main_menu_deck_select then self:enter_main_menu_deck_select() end
        return true
    elseif t.kind == "save_quit" then
        if self.pause_save_and_quit then self:pause_save_and_quit() end
        return true
    elseif t.kind == "back" then
        if self._pause_settings_tab == "controls" then
            self._pause_settings_tab = "general"
            self._controls_listen_role = nil
            self:reset_controls_grid_focus()
            self._pause_focus_index = 1
        elseif self._pause_settings_tab == "performance" then
            self._pause_settings_tab = "general"
            self._pause_focus_index = 1
        else
            self:leave_settings_panel()
        end
        return true
    elseif t.kind == "speed" and t.rect and t.rect.speed then
        if self.set_game_speed then self:set_game_speed(t.rect.speed) end
        if self.save_settings then self:save_settings() end
        return true
    end
    return false
end

function Game:handle_gamepad_pause(button)
    if self.STATE ~= self.STATES.PAUSED and not self._settings_over_menu then return false end
    -- The collection sits on top of the pause panel and takes the buttons while it is up;
    -- its own back handler returns focus here.
    if self._collection_over_run then
        CollectionUI.handle_button(self, button)
        return true
    end
    if self._controls_listen_role and self:handle_controls_listen_press(button) then
        return true
    end
    if self._pause_show_settings and self._pause_settings_tab == "controls" then
        if button == "up" or button == "dpup" or button == "down" or button == "dpdown"
            or button == "left" or button == "dpleft" or button == "right" or button == "dpright" then
            return self:pause_controls_nav(button)
        end
        if self:is_role(button, "cancel") then
            if self._controls_listen_role then
                self._controls_listen_role = nil
                self._controls_listen_slot = nil
            else
                self._pause_settings_tab = "general"
                self:reset_controls_grid_focus()
                self._pause_focus_index = 1
            end
            return true
        end
        if self:is_menu_activate(button) then
            return self:activate_controls_focus()
        end
        return false
    end
    if self._pause_show_settings and self._pause_settings_tab == "performance"
        and self:is_role(button, "cancel") then
        self._pause_settings_tab = "general"
        self._pause_focus_index = 1
        return true
    end
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
    if self:is_role(button, "cancel") and self._pause_show_settings then
        self:leave_settings_panel()
        return true
    end
    if self:is_menu_activate(button) then
        return self:activate_pause_focus()
    end
    return false
end

function Game:exit_pause_menu()
    if self.STATE ~= self.STATES.PAUSED then return false end
    self:end_pause_slider_drag()
    local resume = self._pause_prev_state or self.STATES.SELECTING_HAND
    self._pause_continue_rect = nil
    self._pause_new_run_rect = nil
    self._pause_save_quit_rect = nil
    self._pause_save_error = nil
    self._pause_prev_state = nil
    self._pause_settings_rect = nil
    self._pause_show_settings = false
    self._pause_settings_tab = "general"
    self._pause_performance_open_rect = nil
    self._perf_toggle_rects = {}
    self._perf_reset_rect = nil
    self._perf_disable_rect = nil
    self._controls_listen_role = nil
    self._controls_listen_slot = nil
    self._controls_role_rects = {}
    self._controls_focus_zone = "list"
    self._controls_focus_col = 1
    self._controls_focus_row = 1
    self._controls_focus_footer = "reset"
    self._pause_controls_open_rect = nil
    self._pause_controls_reset_rect = nil
    self._pause_speed_rects = {}
    self._pause_music_slider_rect = nil
    self._pause_music_slider_drag = false
    self._pause_sfx_slider_rect = nil
    self._pause_sfx_slider_drag = false
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

function Game:default_profile_name(profile_id)
    local id = math.floor(tonumber(profile_id) or 1)
    if id < 1 then id = 1 end
    if id > PROFILE_COUNT then id = PROFILE_COUNT end
    return "P" .. id
end

--- Strip unprintable characters and clamp length; returns nil when nothing usable remains.
function Game:sanitize_profile_name(name)
    if type(name) ~= "string" then return nil end
    local out = {}
    for i = 1, #name do
        local byte = name:byte(i)
        if byte >= 32 and byte <= 126 then
            out[#out + 1] = string.char(byte)
        end
        if #out >= PROFILE_NAME_MAX_LENGTH then break end
    end
    local cleaned = table.concat(out):gsub("^%s+", ""):gsub("%s+$", "")
    if cleaned == "" then return nil end
    return cleaned
end

function Game:get_profile_name(profile_id)
    local id = math.floor(tonumber(profile_id) or self:get_profile_id())
    if id < 1 then id = 1 end
    if id > PROFILE_COUNT then id = PROFILE_COUNT end
    local name = self._profile_names and self._profile_names[id]
    if type(name) == "string" and name ~= "" then return name end
    return self:default_profile_name(id)
end

function Game:set_profile_name(profile_id, name)
    local id = math.floor(tonumber(profile_id) or self:get_profile_id())
    if id < 1 then id = 1 end
    if id > PROFILE_COUNT then id = PROFILE_COUNT end
    if type(self._profile_names) ~= "table" then self._profile_names = {} end
    self._profile_names[id] = self:sanitize_profile_name(name) or self:default_profile_name(id)
    self:save_active_profile()
    return self._profile_names[id]
end

function Game:load_active_profile()
    self._profile_id = 1
    self._profile_names = {}
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
    if type(data.names) == "table" then
        for i = 1, PROFILE_COUNT do
            self._profile_names[i] = self:sanitize_profile_name(data.names[i])
        end
    end
    return true
end

function Game:save_active_profile()
    if not (love and love.filesystem and love.filesystem.write and love.filesystem.createDirectory) then
        return false
    end
    love.filesystem.createDirectory(RUN_SAVE_DIR)
    local names = {}
    for i = 1, PROFILE_COUNT do
        names[i] = self:get_profile_name(i)
    end
    local encoded = "return " .. serialize_lua_value({ profile = self:get_profile_id(), names = names })
    local ok = love.filesystem.write(ACTIVE_PROFILE_PATH, encoded)
    return ok and true or false
end

--- Switch to another profile slot (1–3). Persists current settings first, then loads the target.
function Game:switch_profile(profile_id)
    local id = math.floor(tonumber(profile_id) or 1)
    if id < 1 then id = 1 end
    if id > PROFILE_COUNT then id = PROFILE_COUNT end
    if id == self:get_profile_id() then
        self._profile_delete_confirm = false
        return true
    end
    self:save_settings()
    self._profile_id = id
    self._profile_delete_confirm = false
    self:save_active_profile()
    self:load_settings()
    return true
end

--- Wipe unlocks, discoveries, and wins for the active profile, and clear its run save.
function Game:delete_profile_progress()
    self.unlocks = self:build_unlocks()
    self.Discovered = self:build_discovered()
    self.joker_wins = self:build_joker_wins()
    self.joker_unlocks = self:build_joker_unlocks()
    self.career_stats = self:build_career_stats()
    self.career_hand_usage = {}
    if self.SETTINGS then
        self.SETTINGS.CAREER_HAND_USAGE = self.career_hand_usage
        self.SETTINGS.UNLOCKS = self.unlocks
        self.SETTINGS.DISCOVERED = self.Discovered
        self.SETTINGS.JOKER_WINS = self.joker_wins
        self.SETTINGS.JOKER_UNLOCKS = self.joker_unlocks
        self.SETTINGS.CAREER_STATS = self.career_stats
        self.SETTINGS.WINS = 0
    end
    self:apply_unlocks(self.unlocks)
    self:apply_discovered(self.Discovered)
    self:apply_joker_wins(self.joker_wins)
    self:clear_run_snapshot()
    self:save_settings()
    self._profile_delete_confirm = false
    return true
end

--- Wipe any profile slot; the active one is reset in place, others are erased on disk.
function Game:delete_profile(profile_id)
    local id = math.floor(tonumber(profile_id) or self:get_profile_id())
    if id < 1 then id = 1 end
    if id > PROFILE_COUNT then id = PROFILE_COUNT end

    if type(self._profile_names) == "table" then
        self._profile_names[id] = nil
    end
    self:save_active_profile()

    if id == self:get_profile_id() then
        return self:delete_profile_progress()
    end

    if love and love.filesystem and love.filesystem.remove then
        love.filesystem.remove(self:settings_path_for_profile(id))
        love.filesystem.remove(self:run_save_path_for_profile(id))
    end
    self._profile_delete_confirm = false
    return true
end

--- Read another profile's settings without switching to it; nil when the slot is empty.
function Game:peek_profile_settings(profile_id)
    local id = math.floor(tonumber(profile_id) or self:get_profile_id())
    if id < 1 then id = 1 end
    if id > PROFILE_COUNT then id = PROFILE_COUNT end
    if id == self:get_profile_id() then
        return self:snapshot_settings()
    end
    if not (love and love.filesystem and love.filesystem.load and love.filesystem.getInfo) then
        return nil
    end
    local path = self:settings_path_for_profile(id)
    if not love.filesystem.getInfo(path, "file") then return nil end
    local chunk = love.filesystem.load(path)
    if not chunk then return nil end
    local ok, data = pcall(chunk)
    if not ok or type(data) ~= "table" then return nil end
    return self:normalize_settings(data)
end

--- Persist a settings table to another profile's slot.
function Game:write_profile_settings(profile_id, settings)
    local id = math.floor(tonumber(profile_id) or self:get_profile_id())
    if id < 1 then id = 1 end
    if id > PROFILE_COUNT then id = PROFILE_COUNT end
    if id == self:get_profile_id() then
        self.SETTINGS = self:normalize_settings(settings)
        self:apply_unlocks(self.SETTINGS.UNLOCKS)
        self:apply_discovered(self.SETTINGS.DISCOVERED)
        self:apply_joker_wins(self.SETTINGS.JOKER_WINS)
        return self:save_settings()
    end
    if not (love and love.filesystem and love.filesystem.write and love.filesystem.createDirectory) then
        return false
    end
    love.filesystem.createDirectory(RUN_SAVE_DIR)
    local encoded = "return " .. serialize_lua_value(self:normalize_settings(settings))
    local ok = love.filesystem.write(self:settings_path_for_profile(id), encoded)
    return ok and true or false
end

--- Discovery lookups backed by a settings table instead of the live game state.
local function settings_discovery_view(settings)
    local unlocks = type(settings.UNLOCKS) == "table" and settings.UNLOCKS or {}
    local discovered = type(settings.DISCOVERED) == "table" and settings.DISCOVERED or {}
    return {
        is_deck_unlocked = function(_, deck_id)
            local deck = unlocks[deck_id or ""]
            return deck and deck.unlocked == true
        end,
        is_discovered = function(_, id)
            return type(id) == "string" and discovered[id] == true
        end,
    }
end

--- Collection, challenge, sticker, and deck-stake tallies for a profile slot.
--- Stake progress is cumulative: a Blue Stake win counts every stake up to Blue.
function Game:get_profile_progress(profile_id)
    local saved = self:peek_profile_settings(profile_id)
    local settings = saved or self:default_settings()
    local view = settings_discovery_view(settings)
    local stake_count = #(STAKE_DEFS or {})

    local collection_have, collection_total = 0, 0
    for _, cat in ipairs(CollectionCatalog.CATEGORIES) do
        for _, entry in ipairs(CollectionCatalog.get_entries(cat.id)) do
            collection_total = collection_total + 1
            if CollectionCatalog.is_entry_discovered(view, entry) then
                collection_have = collection_have + 1
            end
        end
    end

    local joker_entries = CollectionCatalog.get_entries("jokers")
    local sticker_total = #joker_entries * stake_count
    local sticker_have = 0
    local joker_wins = type(settings.JOKER_WINS) == "table" and settings.JOKER_WINS or {}
    for _, entry in ipairs(joker_entries) do
        local win = joker_wins[entry.id]
        local level = math.floor(tonumber(win and win.highest_stake_level) or 0)
        sticker_have = sticker_have + math.max(0, math.min(stake_count, level))
    end

    local deck_defs = DECK_SELECT_DEFS or DECK_DEFS or {}
    local stake_total = #deck_defs * stake_count
    local stake_have = 0
    local unlocks = type(settings.UNLOCKS) == "table" and settings.UNLOCKS or {}
    local all_stakes_unlocked = true
    for _, deck in ipairs(deck_defs) do
        local entry = unlocks[deck.id]
        local best = 0
        if entry and type(entry.stakes) == "table" then
            for stake_id, stake in pairs(entry.stakes) do
                if stake.defeated == true then
                    best = math.max(best, self:get_stake_order(stake_id))
                end
                if stake.unlocked ~= true then
                    all_stakes_unlocked = false
                end
            end
        else
            all_stakes_unlocked = false
        end
        stake_have = stake_have + math.min(stake_count, best)
    end

    local rows = {
        { key = "collection", label = "Collection",    have = collection_have, total = collection_total },
        { key = "challenges", label = "Challenges",    have = 0,               total = #(CHALLENGE_DEFS or {}) },
        { key = "stickers",   label = "Joker Stickers", have = sticker_have,   total = sticker_total },
        { key = "stakes",     label = "Deck Stake Wins", have = stake_have,    total = stake_total },
    }
    for _, challenge in ipairs(CHALLENGE_DEFS or {}) do
        if type(settings.CHALLENGE_WINS) == "table" and settings.CHALLENGE_WINS[challenge.id] == true then
            rows[2].have = rows[2].have + 1
        end
    end

    local ratio_sum, ratio_count = 0, 0
    for _, row in ipairs(rows) do
        row.ratio = row.total > 0 and (row.have / row.total) or 0
        if row.total > 0 then
            ratio_sum = ratio_sum + row.ratio
            ratio_count = ratio_count + 1
        end
    end

    return {
        rows = rows,
        overall = ratio_count > 0 and (ratio_sum / ratio_count) or 0,
        wins = math.max(0, math.floor(tonumber(settings.WINS) or 0)),
        fully_unlocked = collection_total > 0 and collection_have >= collection_total and all_stakes_unlocked,
        exists = saved ~= nil,
    }
end

--- Sound settings that are plain 0-100 percentages, normalized the same way.
local SOUND_VOLUME_KEYS = { "volume", "music_volume", "sfx_volume" }

function Game:default_settings()
    return {
        GAMESPEED = 1,
        SOUND = { volume = 100, music_volume = 100, sfx_volume = 100 },
        -- Reference `UI_definitions.lua:2305,2308`: a 0-100 screenshake slider and a
        -- reduced-motion toggle. Both are accessibility settings, and this port shakes the
        -- playfield on run death and pack opens with no way to turn it down.
        SCREENSHAKE = 100,
        REDUCED_MOTION = false,
        -- Accelerometer tilt. Independent of the shake, the way the reference keeps each board
        -- movement setting separate (`UI_definitions.lua:2303-2309`); the shake's own off switch is
        -- SCREENSHAKE at 0.
        TILT = true,
        -- Live per-Joker readouts under the Joker row (`joker_display.lua`). Off by default:
        -- it is an information overlay the base game does not have, and it costs the 20 px
        -- under the row.
        JOKER_DISPLAY = false,
        GRAPHICS = { texture_scaling = 1 },
        CONTROLS = InputBindings.default_settings(),
        UNLOCKS = self:build_unlocks(),
        JOKER_UNLOCKS = self:build_joker_unlocks(),
        CAREER_STATS = self:build_career_stats(),
        CAREER_HAND_USAGE = {},
        DISCOVERED = self:build_discovered(),
        JOKER_WINS = self:build_joker_wins(),
        CHALLENGE_WINS = {},
        WINS = 0,
    }
end

function Game:normalize_settings(data)
    local out = copy_table(self:default_settings())
    if type(data) ~= "table" then return out end

    local allowed_speeds = { [0.5] = true, [1] = true, [2] = true, [4] = true }
    local speed = tonumber(data.GAMESPEED)
    if speed and allowed_speeds[speed] then
        out.GAMESPEED = speed
    end

    if type(data.SOUND) == "table" then
        -- `volume` and `sfx_volume` post-date the first saves; absent means 100.
        for _, key in ipairs(SOUND_VOLUME_KEYS) do
            local v = tonumber(data.SOUND[key])
            if v ~= nil then
                out.SOUND[key] = math.max(0, math.min(100, math.floor(v)))
            end
        end
    end

    if type(data.GRAPHICS) == "table" then
        local ts = tonumber(data.GRAPHICS.texture_scaling)
        if ts == 1 or ts == 2 then
            out.GRAPHICS.texture_scaling = ts
        end
    end

    local shake = tonumber(data.SCREENSHAKE)
    if shake then
        out.SCREENSHAKE = math.max(0, math.min(100, math.floor(shake)))
    end
    if type(data.REDUCED_MOTION) == "boolean" then
        out.REDUCED_MOTION = data.REDUCED_MOTION
    end
    if type(data.TILT) == "boolean" then
        out.TILT = data.TILT
    end
    if type(data.JOKER_DISPLAY) == "boolean" then
        out.JOKER_DISPLAY = data.JOKER_DISPLAY
    end

    out.CONTROLS = InputBindings.normalize_controls(data.CONTROLS)
    out.UNLOCKS = self:normalize_unlocks(data.UNLOCKS)
    out.JOKER_UNLOCKS = self:normalize_joker_unlocks(data.JOKER_UNLOCKS)
    out.CAREER_STATS = self:normalize_career_stats(data.CAREER_STATS)
    out.CAREER_HAND_USAGE = self:normalize_career_hand_usage(data.CAREER_HAND_USAGE)
    out.DISCOVERED = self:normalize_discovered(data.DISCOVERED)
    out.JOKER_WINS = self:normalize_joker_wins(data.JOKER_WINS)
    out.CHALLENGE_WINS = type(data.CHALLENGE_WINS) == "table" and copy_table(data.CHALLENGE_WINS) or {}
    out.WINS = math.max(0, math.floor(tonumber(data.WINS) or 0))

    return out
end

function Game:snapshot_settings()
    return {
        GAMESPEED = tonumber(self.SETTINGS and self.SETTINGS.GAMESPEED) or 1,
        SOUND = {
            volume = self:get_master_volume(),
            music_volume = self:get_music_volume(),
            sfx_volume = self:get_sfx_volume(),
        },
        GRAPHICS = {
            texture_scaling = tonumber(self.SETTINGS and self.SETTINGS.GRAPHICS and self.SETTINGS.GRAPHICS.texture_scaling) or 1,
        },
        SCREENSHAKE = self:get_screenshake_percent(),
        REDUCED_MOTION = self:reduced_motion_enabled(),
        TILT = self:tilt_enabled(),
        JOKER_DISPLAY = self:joker_display_enabled(),
        CONTROLS = InputBindings.normalize_controls(self.SETTINGS and self.SETTINGS.CONTROLS),
        UNLOCKS = self:normalize_unlocks(self.unlocks or (self.SETTINGS and self.SETTINGS.UNLOCKS)),
        JOKER_UNLOCKS = self:normalize_joker_unlocks(self.joker_unlocks
            or (self.SETTINGS and self.SETTINGS.JOKER_UNLOCKS)),
        CAREER_STATS = self:normalize_career_stats(self.career_stats
            or (self.SETTINGS and self.SETTINGS.CAREER_STATS)),
        CAREER_HAND_USAGE = self:normalize_career_hand_usage(self.career_hand_usage
            or (self.SETTINGS and self.SETTINGS.CAREER_HAND_USAGE)),
        DISCOVERED = self:normalize_discovered(self.Discovered or (self.SETTINGS and self.SETTINGS.DISCOVERED)),
        JOKER_WINS = self:normalize_joker_wins(self:get_joker_wins_for_save()),
        CHALLENGE_WINS = copy_table(self.SETTINGS and self.SETTINGS.CHALLENGE_WINS or {}),
        WINS = self:get_win_count(),
    }
end

function Game:load_settings()
    self.SETTINGS = copy_table(self:default_settings())
    local function finish_load()
        self:apply_unlocks(self.SETTINGS.UNLOCKS)
        self:apply_discovered(self.SETTINGS.DISCOVERED)
        self:apply_joker_wins(self.SETTINGS.JOKER_WINS)
        self:apply_joker_unlocks(self.SETTINGS.JOKER_UNLOCKS)
        self:apply_career_stats(self.SETTINGS.CAREER_STATS)
        self:apply_career_hand_usage(self.SETTINGS.CAREER_HAND_USAGE)
        InputBindings.apply_to_game(self)
        if self.apply_music_volume then
            self:apply_music_volume()
        end
        self:refresh_tilt_sensor()
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

function Game:control_bindings()
    return InputBindings.get_bindings(self)
end

function Game:get_role_for_button(button)
    return InputBindings.get_role_for_button(button, self:control_bindings())
end

function Game:get_button_for_role(role)
    return InputBindings.get_button_for_role(role, self:control_bindings())
end

function Game:is_role(button, role)
    return InputBindings.is_role(button, role, self:control_bindings())
end

function Game:is_menu_activate(button)
    return InputBindings.is_menu_activate(button, self:control_bindings())
end

function Game:is_menu_back(button)
    return InputBindings.is_menu_back(button, self:control_bindings())
end

function Game:is_role_held(role)
    return self._role_held and self._role_held[role] == true
end

function Game:get_role_press_time(role)
    return self._role_press_time and self._role_press_time[role] or nil
end

function Game:set_role_held(role, held, press_time)
    if not InputBindings.HOLD_ROLES[role] then return end
    if type(self._role_held) ~= "table" then self._role_held = {} end
    if type(self._role_press_time) ~= "table" then self._role_press_time = {} end
    if held then
        self._role_held[role] = true
        self._role_press_time[role] = press_time or (love and love.timer and love.timer.getTime())
    else
        self._role_held[role] = nil
        self._role_press_time[role] = nil
    end
end

function Game:set_control_binding(role, slot, button)
    if type(self.SETTINGS) ~= "table" then return false end
    if type(self.SETTINGS.CONTROLS) ~= "table" then
        self.SETTINGS.CONTROLS = InputBindings.default_settings()
    end
    if type(self.SETTINGS.CONTROLS.bindings) ~= "table" then
        self.SETTINGS.CONTROLS.bindings = InputBindings.normalize_bindings(nil)
    end
    slot = math.floor(tonumber(slot) or 1)
    local ok = InputBindings.set_role_slot_binding(self.SETTINGS.CONTROLS.bindings, role, slot, button)
    if ok then
        self.SETTINGS.CONTROLS.bindings = InputBindings.normalize_bindings(self.SETTINGS.CONTROLS.bindings)
        self:save_settings()
    end
    return ok
end

function Game:reset_control_bindings()
    if type(self.SETTINGS) ~= "table" then return false end
    self.SETTINGS.CONTROLS = InputBindings.default_settings()
    self:save_settings()
    return true
end

function Game:handle_controls_listen_press(button)
    if self.STATE ~= self.STATES.PAUSED then return false end
    if type(self._controls_listen_role) ~= "string" then return false end
    local slot = math.floor(tonumber(self._controls_listen_slot) or 1)
    if self:is_role(button, "cancel") then
        self._controls_listen_role = nil
        self._controls_listen_slot = nil
        return true
    end
    if InputBindings.is_rebindable_button(button) then
        self:set_control_binding(self._controls_listen_role, slot, button)
        self._controls_listen_role = nil
        self._controls_listen_slot = nil
        return true
    end
    return true
end

function Game:set_game_speed(speed)
    if not self.SETTINGS then return end
    local allowed_speeds = { [0.5] = true, [1] = true, [2] = true, [4] = true }
    local s = tonumber(speed)
    if not s or not allowed_speeds[s] then return end
    self.SETTINGS.GAMESPEED = s
    self:save_settings()
end

--- Master volume. No slider yet; it scales both music and SFX.
function Game:get_master_volume()
    local sound = self.SETTINGS and self.SETTINGS.SOUND
    return math.max(0, math.min(100, math.floor(tonumber(sound and sound.volume) or 100)))
end

function Game:get_music_volume()
    local sound = self.SETTINGS and self.SETTINGS.SOUND
    return math.max(0, math.min(100, math.floor(tonumber(sound and sound.music_volume) or 100)))
end

function Game:get_sfx_volume()
    local sound = self.SETTINGS and self.SETTINGS.SOUND
    return math.max(0, math.min(100, math.floor(tonumber(sound and sound.sfx_volume) or 100)))
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

---@param pct number volume 0–100
---@param opts table|nil `{ skip_save = true }` to avoid SD writes while dragging the slider
function Game:set_sfx_volume(pct, opts)
    if not self.SETTINGS then return end
    if type(self.SETTINGS.SOUND) ~= "table" then self.SETTINGS.SOUND = {} end
    self.SETTINGS.SOUND.sfx_volume = math.max(0, math.min(100, math.floor(tonumber(pct) or 0)))
    -- Sfx.play reads the setting directly, so there is nothing to re-apply here.
    if not (opts and opts.skip_save) then
        self:save_settings()
    end
end

---@param pct number 0-100
---@param opts table|nil `{ skip_save = true }` while a drag is in flight
function Game:set_screenshake_percent(pct, opts)
    if not self.SETTINGS then return end
    self.SETTINGS.SCREENSHAKE = math.max(0, math.min(100, math.floor(tonumber(pct) or 0)))
    if not (opts and opts.skip_save) then
        self:save_settings()
    end
end

---@param enabled boolean
function Game:set_reduced_motion(enabled)
    if not self.SETTINGS then return end
    self.SETTINGS.REDUCED_MOTION = enabled == true
    -- Reduced motion stills the tilt as well, so the sensor comes down with it rather than being
    -- read every frame into an offset that is discarded.
    self:refresh_tilt_sensor()
    self:save_settings()
end

--- Accelerometer tilt, the playfield's answer to how the console is being held.
---@return boolean
function Game:tilt_enabled()
    return (self.SETTINGS and self.SETTINGS.TILT) == true
end

---@param enabled boolean
function Game:set_tilt_enabled(enabled)
    if not self.SETTINGS then return end
    self.SETTINGS.TILT = enabled == true
    self:refresh_tilt_sensor()
    self:save_settings()
end

--- Live per-Joker readouts under the Joker row; see `joker_display.lua`.
---@return boolean
function Game:joker_display_enabled()
    return (self.SETTINGS and self.SETTINGS.JOKER_DISPLAY) == true
end

---@param enabled boolean
function Game:set_joker_display_enabled(enabled)
    if not self.SETTINGS then return end
    self.SETTINGS.JOKER_DISPLAY = enabled == true
    -- Nothing has been recomputed while the readouts were off, so the first frame after
    -- turning them on must not trust the cached signature.
    JokerDisplay.invalidate()
    self:save_settings()
end

--- Power the accelerometer to match the current settings. Idempotent; safe to call whenever
--- anything that feeds into it changes.
---@return boolean active
function Game:refresh_tilt_sensor()
    return Tilt.set_active(self:tilt_enabled() and not self:reduced_motion_enabled())
end

--- The music manager reads the volume settings itself every frame; this only pushes the
--- new value out immediately so the pause slider tracks a drag without a frame of lag.
--- Muting is still volume-only: Source:pause/stop can freeze streaming audio on
--- LovePotion/3DS, which is why the manager never stops an audible source either.
function Game:apply_music_volume()
    if Sfx and Sfx.music_refresh then
        Sfx.music_refresh()
    end
end

function Game:_volume_from_slider_x(r, x)
    if type(r) ~= "table" then return nil end
    local t = (tonumber(x) - r.track_x) / r.track_w
    t = math.max(0, math.min(1, t))
    return math.floor(t * 100 + 0.5)
end

function Game:_music_volume_from_slider_x(x)
    return self:_volume_from_slider_x(self._pause_music_slider_rect, x)
end

function Game:_sfx_volume_from_slider_x(x)
    return self:_volume_from_slider_x(self._pause_sfx_slider_rect, x)
end

function Game:_screenshake_from_slider_x(x)
    return self:_volume_from_slider_x(self._pause_screenshake_slider_rect, x)
end


--- Leave the general settings tab: flush the deferred slider save and drop the rects,
--- so a touchrelease lost to a HOME-menu suspend cannot keep dragging against stale
--- coordinates on another screen.
function Game:end_pause_slider_drag()
    if self._pause_music_slider_drag or self._pause_sfx_slider_drag
        or self._pause_screenshake_slider_drag then
        self:save_settings()
    end
    self._pause_music_slider_drag = false
    self._pause_sfx_slider_drag = false
    self._pause_screenshake_slider_drag = false
    self._pause_music_slider_rect = nil
    self._pause_sfx_slider_rect = nil
    self._pause_screenshake_slider_rect = nil
end

--- Open the settings panel from the main menu. The panel itself is the pause menu's, which
--- is the only settings UI there is; `_settings_over_menu` lets it draw and take input while
--- `STATE` is MENU. The base game exposes Options at the top level (`UI_definitions.lua:2295`);
--- here it was reachable only from an in-run pause.
function Game:open_settings_from_menu()
    if self.STATE ~= self.STATES.MENU then return false end
    Sfx.play_button()
    self._settings_over_menu = true
    self._pause_show_settings = true
    self._pause_settings_tab = "general"
    self._controls_listen_role = nil
    self._pause_focus_index = 1
    return true
end

--- Leave the menu-side settings panel and hand the screen back to the main menu.
function Game:close_settings_from_menu()
    if not self._settings_over_menu then return false end
    self:end_pause_slider_drag()
    self._settings_over_menu = nil
    self._pause_show_settings = false
    self._pause_settings_tab = "general"
    self._menu_focus_index = 1
    return true
end

--- Back out of the settings panel's general tab. Where that lands depends on how the panel was
--- opened: from an in-run pause it drops back to the pause list, but from the main menu there is
--- no pause list behind it, so the panel has to close all the way out. Dropping `_pause_show_settings`
--- alone in the menu case left the pause list drawing over the main menu with no way out, since
--- `exit_pause_menu` refuses to run while `STATE` is MENU.
function Game:leave_settings_panel()
    if self._settings_over_menu then
        return self:close_settings_from_menu()
    end
    self:end_pause_slider_drag()
    self._pause_show_settings = false
    self._pause_focus_index = 2
    return true
end

--- Open the collection on top of a paused run. The run state is untouched: the collection
--- borrows the bottom screen and `CollectionUI.back_to_main` hands it back to the pause menu
--- (see `_collection_over_run` there). The reference reaches its collection the same way,
--- from the in-run options overlay (`UI_definitions.lua:2223`).
function Game:open_collection_over_run()
    if self.STATE ~= self.STATES.PAUSED then return false end
    self:end_pause_slider_drag()
    self._pause_show_settings = false
    self._collection_over_run = true
    CollectionUI.open(self)
    return true
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
    self._deck_view_hand_panel_open = false
    self._deck_view_hand_panel_t = 0
    self._deck_view_open = true
    DeckViewUI.build(self)
    return true
end

function Game:exit_deck_view()
    if not self._deck_view_open then return false end
    self.dragging = nil
    self.active_tooltip_card = nil
    self._deck_view_hand_panel_open = false
    self._deck_view_hand_panel_t = 0
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
        seed = self.SEED,
        seeded = self.seeded == true or nil,
        rng_streams = copy_table(self._rng_streams or {}),
        resume_state = self:current_resume_state(),
        stage = self.STAGES.RUN,
        selected_deck_id = self:get_run_deck_id(),
        selected_stake_id = self:get_run_stake_id(),
        challenge_id = self.challenge_id,
        challenge_rules = copy_table(self.challenge_rules or {}),
        challenge_modifiers = copy_table(self.challenge_modifiers or {}),
        challenge_banned_keys = copy_table(self.challenge_banned_keys or {}),
        challenge_joker_slots_disabled = self.challenge_joker_slots_disabled == true,
        inflation = tonumber(self.inflation) or 0,
        _victory_progress_recorded = self._victory_progress_recorded == true,
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
        consumable_usage = copy_table(self.consumable_usage or {}),
        hand_play_counts = copy_table(self.hand_play_counts or {}),
        frozen_most_played_hand_index = self.frozen_most_played_hand_index,
        blind_hand_play_counts = copy_table(self.blind_hand_play_counts or {}),
        _ante_played_card_uids = copy_table(self._ante_played_card_uids or {}),
        boss_runtime = copy_table(self.boss_runtime or {}),
        jokers_on_bottom = self.jokers_on_bottom == true,
        consumables_on_bottom = self.consumables_on_bottom == true,
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
        shop_reroll_count = tonumber(self.shop_reroll_count) or 0,
        shop_free_rerolls_used = tonumber(self.shop_free_rerolls_used) or 0,
        shop_offers = copy_table(self.shop_offers or {}),
        shop_booster_offers = copy_table(self.shop_booster_offers or {}),
        shop_offer_slots = tonumber(self.shop_offer_slots) or 2,
        shop_booster_slots = tonumber(self.shop_booster_slots) or 2,
        active_shop_booster_slot = self.active_shop_booster_slot,
        booster_session = self:_serialize_booster_session(),
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
    local seed = self:normalize_run_seed(snapshot.seed)
    if seed == nil then return false, "missing_seed" end
    -- Restoring drives the same state transitions play does; suppress the autosave they
    -- would otherwise trigger, so a half-rebuilt run never overwrites the file it came from.
    self._restoring_run_snapshot = true

    self.SEED = seed
    self.seeded = snapshot.seeded == true
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
        self.deck = Deck(self)
    end
    if self.deck then
        self.deck.cards = table_array_deep_copy(snapshot.deck_cards or {})
        self.deck.discard_pile = table_array_deep_copy(snapshot.deck_discard_pile or {})
        -- Migrate pre-parity saves whose stone cards still serialized a real rank/suit.
        for _, cards in ipairs({ self.deck.cards, self.deck.discard_pile }) do
            for _, card_data in ipairs(cards) do
                if Card and Card.normalize_gameplay_data then
                    Card.normalize_gameplay_data(card_data)
                end
            end
        end
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
    self:restore_run_deck_stake_from_snapshot(snapshot)
    self.challenge_id = snapshot.challenge_id
    self.challenge_rules = copy_table(snapshot.challenge_rules or {})
    self.challenge_modifiers = copy_table(snapshot.challenge_modifiers or {})
    self.challenge_banned_keys = copy_table(snapshot.challenge_banned_keys or {})
    self.challenge_joker_slots_disabled = snapshot.challenge_joker_slots_disabled == true
    self.inflation = tonumber(snapshot.inflation) or 0
    self._victory_progress_recorded = snapshot._victory_progress_recorded == true
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
    self.consumable_usage = copy_table(snapshot.consumable_usage or {})
    self.hand_play_counts = copy_table(snapshot.hand_play_counts or {})
    self.frozen_most_played_hand_index = tonumber(snapshot.frozen_most_played_hand_index) or nil
    self.blind_hand_play_counts = copy_table(snapshot.blind_hand_play_counts or {})
    self._ante_played_card_uids = copy_table(snapshot._ante_played_card_uids or {})
    self.boss_runtime = copy_table(snapshot.boss_runtime or {})
    self.jokers_on_bottom = snapshot.jokers_on_bottom == true
    self.consumables_on_bottom = snapshot.consumables_on_bottom == true
    self.tags = {}
    for _, tag_type in ipairs(snapshot.tags or {}) do
        if type(tag_type) == "string" and tag_type ~= "" then
            self:addTag(tag_type)
        end
    end
    self.shop_offer_queue = copy_table(snapshot.shop_offer_queue or {})
    self.shop_reroll_count = tonumber(snapshot.shop_reroll_count) or 0
    self.shop_free_rerolls_used = tonumber(snapshot.shop_free_rerolls_used) or 0
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
    self:recompute_consumable_slot_layout()
    self:_apply_joker_layout()
    self:_apply_consumable_layout()
    self:sync_jokers_interactivity()
    self:sync_consumables_interactivity()

    if #(self.jokers or {}) == 0 then
        self.jokers_on_bottom = false
        -- The bottom consumable row is panel-width when jokers share the screen and
        -- full-width otherwise, so this flip invalidates the consumable layout too.
        self._consumable_layout_dirty = true
    end
    if #(self.consumables or {}) == 0 then
        self.consumables_on_bottom = false
    end

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
        -- Restoring a save rebuilds every shop node at once. Those cards are not
        -- appearing, they are being put back, so they announce nothing.
        self._suppress_edition_reveals = true
        self:purge_all_joker_pool_swaps_from_shop()
        self:sync_shop_offer_nodes()
        self._suppress_edition_reveals = nil
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
        -- Reopen the pack the player was in. Only fall back to the shop if the session
        -- could not be rebuilt (an older save, or an empty pack).
        if not self:_restore_booster_session(snapshot.booster_session) then
            resume_state = self.STATES.SHOP
        end
    elseif resume_state == self.STATES.GAME_OVER then
        resume_state = self.STATES.BLIND_SELECT
    end
    -- YOU_WIN resumes on the win screen so the player can pick Endless / New Run / Menu again.
    self._pause_prev_state = nil
    if resume_state == self.STATES.YOU_WIN then
        self:ensure_victory_progress_recorded()
    end
    self:set_state(resume_state)
    -- Restore the draw position only after loading has rebuilt cards and UI state
    -- (reference saves retain deterministic RNG state rather than reseeding).
    self:restore_rng_stream(seed, snapshot.rng_streams)

    -- A blind that was check-pointed between `set_state(SELECTING_HAND)` and the deal has no
    -- hand and no draw queue in it (see `prepare_hand_for_new_blind`), and nothing else ever
    -- refills a hand mid-blind, so the run would resume onto an empty playfield. Saves written
    -- before that was fixed are still on players' cards, so deal them out here. Drawing off the
    -- deck array consumes no RNG, and a hand that is legitimately empty because the deck ran
    -- out stays empty.
    if resume_state == self.STATES.SELECTING_HAND and self.hand
        and #(self.hand.cards or {}) == 0 and #(self.hand._draw_queue or {}) == 0
        and self.deck and not self.deck:empty() then
        self.hand:fill_from_deck()
        self:boss_on_hand_refilled(true)
    end

    self._restoring_run_snapshot = nil
    return true
end

function Game:continue_saved_run_from_main_menu()
    local snapshot, err = self:read_run_snapshot()
    if not snapshot then return false, err end
    local ok, load_err = self:load_run_snapshot(snapshot)
    if ok then
        self:check_unlock("continue_game")
        -- Re-write rather than clear: with autosaving on, there should always be a current
        -- copy on disk. Clearing here meant a resumed run was unprotected until the player
        -- next reached a manual save.
        self:autosave_run()
    end
    return ok, load_err
end

--- Resuming, cut up the same way a fresh run start is (`Game:run_start_steps`). The read, the
--- restore and the write-back are each a blocking chunk, and together they overrun the music
--- stream exactly as starting a run does.
---
--- A failed read or restore returns false, which abandons the remaining steps and lifts the
--- cover on the menu that was already there -- the same nothing-happened the synchronous
--- version gives, minus the freeze.
---@return function[]
function Game:continue_saved_run_steps()
    local snapshot = nil
    return {
        function()
            snapshot = self:read_run_snapshot()
            return snapshot ~= nil
        end,
        function()
            if not self:load_run_snapshot(snapshot) then return false end
            self:check_unlock("continue_game")
        end,
        function() self:autosave_run() end,
    }
end

--- Resume the saved run behind the wipe. What the Continue button calls.
---@return boolean started
function Game:begin_continue_saved_run()
    return ScreenWipe.begin(self, self:continue_saved_run_steps())
end

--- Start a fresh run behind the wipe. What Play, a challenge and the deck-select confirm call;
--- `start_run_from_main_menu` is the same work with no cover, for the headless tests.
---@return boolean started
function Game:start_new_run_from_main_menu()
    -- Checked before the snapshot is dropped, not after: a second call that lost the race
    -- would otherwise throw the save away and then decline to start anything.
    if ScreenWipe.active(self) then return false end
    self:clear_run_snapshot()
    return ScreenWipe.begin(self, self:run_start_steps(), function(game)
        -- Re-pin blind select's entrance to the reveal frame. The last step starts it
        -- (`Game:initialize_run_loop`), and today nothing advances it under the cover, but the
        -- 0.25 s slide is short enough that any extra covered frame would eat it -- so it is
        -- pinned here rather than left to depend on that.
        game:begin_blind_select_intro()
    end)
end

--- Write a run snapshot if one makes sense right now. Quiet by design: a failed autosave
--- must never interrupt play, and the next checkpoint will try again.
---@return boolean written
function Game:autosave_run()
    if self.STAGE ~= self.STAGES.RUN then return false end
    -- Loading a run replays state transitions; do not write back over the file mid-restore.
    if self._restoring_run_snapshot == true then return false end
    if self:is_hand_scoring_active() then return false end
    if type(self.build_run_snapshot) ~= "function" then return false end
    local ok = self:write_run_snapshot(self:build_run_snapshot())
    return ok == true
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
    -- Deck select is reached through Play now, so backing out of it should land there rather
    -- than at the root of the menu.
    self._menu_page = "play"
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
    local requested_ante = math.max(1, tonumber(ante) or 1)
    local stake_offset = tonumber(self._stake_ante_mult) or 0
    local max_ante = 8
    local deckMult = 1
    if self._deck_special == "plasma" then
        deckMult = 2
    end
    local table_ante = requested_ante + (max_ante + 1) * stake_offset
    if base_table[table_ante] and requested_ante <= max_ante then
        return tonumber(base_table[table_ante] * deckMult) or 0
    end
    -- Endless Formula
    local last_base = tonumber(base_table[max_ante + (max_ante + 1) * stake_offset] * deckMult) or 50000
    -- Endless growth begins at Ante 9 regardless of Green/Purple's table offset
    -- (reference misc_functions.lua:919-951).
    local overflow = math.max(0, requested_ante - max_ante)
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
        if key ~= "bl_small" and key ~= "bl_big" and not self:is_challenge_banned(key)
            and type(blind) == "table" and type(blind.boss) == "table" then
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
    self.current_boss_blind_id = pool[self:random("boss", #pool)]
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
        return "Score at least " .. NumberFormat.format(math.floor(target)) .. " chips."
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
            if Consumable and node and node.is and node:is(Consumable) and node.release_texture then
                node:release_texture()
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
    elseif self.STATE == self.STATES.SELECTING_HAND then
        -- Before the nodes, so a card dragged over the bar passes in front of it rather than
        -- disappearing behind it.
        HandActionsUI.draw(self)
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

    self:sync_shop_offer_interactivity()

    -- Hide consumables during blind select + round eval (still visible on top during play/shop/booster).
    local show_consumables = not (self.STATE == self.STATES.ROUND_EVAL
        or self.STATE == self.STATES.GAME_OVER or self.STATE == self.STATES.YOU_WIN)
    if not show_consumables then
        -- Truncate rather than replace; this runs every frame on the cash-out screen.
        local rects = self._consumable_rects
        if rects then
            for i = #rects, 1, -1 do rects[i] = nil end
        end
        self.active_tooltip_consumable_index = nil
        if self.consumable_nodes then
            for _, node in ipairs(self.consumable_nodes) do
                if node and node.states then
                    node.states.visible = false
                end
            end
        end
    else
        -- Layout only on bottom; owned consumables render on TopUI when not pulled down.
        self:draw_consumables_row()
        self:sync_consumables_interactivity()
    end

    -- Ensure node sprites (especially jokers/cards/consumables) are not tinted by prior UI draws.
    love.graphics.setColor(1, 1, 1, 1)

    -- Keep layering stable:
    -- 1) regular nodes, 2) hand cards, 3) shop tags, 4) the dragged shop node and its own tag,
    -- 5) pulled-down jokers + consumables, 6) popups
    -- Marked on the nodes rather than gathered into three lookup tables every frame: the loop
    -- below already tests `_deck_view_card` / `_collection_node` this way, and building the
    -- sets meant three allocations plus a hash insert per node on every frame.
    local scratch = self._draw_deferred_scratch or {}
    self._draw_deferred_scratch = scratch
    local deferred = 0
    -- A lifted shop card belongs above the shelf it came from, tags included. Its own tag
    -- follows it up, which is what the reference gets for free by parenting the price to the
    -- card (`UI_definitions.lua:813`).
    local dragged_shop = self:dragged_shop_node()
    if dragged_shop then
        dragged_shop._draw_deferred = true
        deferred = deferred + 1
        scratch[deferred] = dragged_shop
    end
    if self.consumables_on_bottom == true and self.consumable_nodes then
        for _, node in ipairs(self.consumable_nodes) do
            node._draw_deferred = true
            deferred = deferred + 1
            scratch[deferred] = node
        end
    end
    if self.hand and self.hand.card_nodes then
        for _, node in ipairs(self.hand.card_nodes) do
            node._draw_deferred = true
            deferred = deferred + 1
            scratch[deferred] = node
        end
    end
    if self.jokers_on_bottom == true and self.jokers then
        for _, node in ipairs(self.jokers) do
            node._draw_deferred = true
            deferred = deferred + 1
            scratch[deferred] = node
        end
    end

    for _, node in ipairs(self.nodes) do
        -- `_draw_screen == "top"` is a node that left its owner row while it was still being
        -- rendered on the readout (a used consumable, a destroyed joker); `TopUI` draws it.
        if not node._deck_view_card and not node._collection_node and not node._draw_deferred
            and node._draw_screen ~= "top" then
            node:draw()
        end
    end

    for i = 1, deferred do
        scratch[i]._draw_deferred = nil
        scratch[i] = nil
    end
    -- A selected card is lifted 20 px (`hand.lua`'s `SELECTED_LIFT`) straight into the band a
    -- pulled-down row occupies (`BOTTOM_INVENTORY_Y`), so the tray swallowed most of the only
    -- thing on screen that says the card is chosen - opening a drawer read as the game
    -- deselecting the hand. The row still covers the rest of the fan, which is the point of
    -- pulling it down; the selection comes out on top of it.
    local rows_pulled = (self.jokers_on_bottom == true) or (self.consumables_on_bottom == true)
    if self.hand and self.hand.card_nodes then
        for _, hn in ipairs(self.hand.card_nodes) do
            if hn and hn.draw and not (rows_pulled and hn.selected) then hn:draw() end
        end
    end
    if self.STATE ~= self.STATES.ROUND_EVAL then
        Particles.draw()
    end
    if self.STATE == self.STATES.SHOP then
        self:draw_shop_price_tags(dragged_shop)
        if dragged_shop and dragged_shop.draw then
            dragged_shop:draw()
            self:draw_price_tag_for_node(dragged_shop)
        end
    end
    -- The trays the pulled-down rows sit on, drawn here rather than with the rest of the
    -- bottom UI: a tray drawn before the node pass would end up under the hand, and the point
    -- of it is to separate the row from what it is covering.
    self:draw_bottom_inventory_trays()
    if self.jokers_on_bottom == true and self.jokers then
        -- The row is fanned, so neighbours overlap. A joker being dragged has to come out on
        -- top of the ones it is being pulled past, otherwise it slides *under* them the moment
        -- the live reorder puts it earlier in the list.
        local dragged = self.dragging
        for _, jj in ipairs(self.jokers) do
            if jj and jj.draw and jj ~= dragged then jj:draw() end
        end
        for _, jj in ipairs(self.jokers) do
            if jj == dragged and jj.draw then jj:draw() end
        end
        JokerDisplay.draw_row(self, self.jokers, self._joker_row_step_bottom)
    end
    if self.consumables_on_bottom == true and self.consumable_nodes then
        for _, cn in ipairs(self.consumable_nodes) do
            if cn and cn.draw then cn:draw() end
        end
    end
    -- The other half of the selection lift (see the hand pass above).
    if rows_pulled and self.hand and self.hand.card_nodes then
        for _, hn in ipairs(self.hand.card_nodes) do
            if hn and hn.selected and hn.draw then hn:draw() end
        end
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

    self:draw_boss_announce()

    -- Pause menu must overlay every gameplay element, including hand/tooltips.
    if self.STATE == self.STATES.PAUSED then
        if self._collection_over_run then
            -- The collection borrows the whole bottom screen; the pause panel is underneath
            -- it and comes back when the collection closes.
            MainMenuUI.draw_bottom(self)
        else
            self:draw_bottom_pause()
        end
    end
end

-- Boss announcement: the reference makes starting a boss an event — the chip pops out
-- and the debuff text scrolls in with per-character pings (`reference/Balatro/blind.lua:218-268`).
-- The port banners the boss name and effect over the playfield for a beat, spelled out
-- through the DynaText pop-in (which carries the chirps).
local BOSS_ANNOUNCE_HOLD = 2.4
local BOSS_ANNOUNCE_FADE = 0.5

function Game:begin_boss_announce()
    self._boss_announce = {
        age = 0,
        name = tostring(self.current_blind_name or "Boss Blind"),
        effect = (self.get_boss_effect_text and self:get_boss_effect_text()) or "",
    }
    if not self._boss_announce_text then
        self._boss_announce_text = DynaText.new({
            float_amount = 1,
            rotation_amount = 0.03,
            pop_on_change = true,
        })
    end
    DynaText.pop_in(self._boss_announce_text)

    -- The sting the reference fires with the debuff alert (`blind.lua:232-240`): a whoosh, then
    -- four rising `cancel` pings a tenth of a second apart. The banner already carried the
    -- boss's name and effect text; it landed in silence.
    Sfx.play("whoosh1", 0.55, 0.62)
    local pings = {}
    for i = 1, 4 do
        pings[i] = { at = 0.1 * (i - 1), pitch = 0.7 + 0.05 * i }
    end
    self._boss_announce_pings = { t = 0, next = 1, queue = pings }
end

--- Ring the boss announce sting. Driven from `Game:update` rather than the banner's draw,
--- because draw runs once per screen and would double every ping.
---@param dt number real seconds
function Game:_update_boss_announce_sting(dt)
    local s = self._boss_announce_pings
    if not s then return end
    if self.STATE == self.STATES.PAUSED then return end
    s.t = s.t + dt
    while s.next <= #s.queue and s.t >= s.queue[s.next].at do
        Sfx.play("cancel", s.queue[s.next].pitch, 0.7)
        s.next = s.next + 1
    end
    if s.next > #s.queue then self._boss_announce_pings = nil end
end

function Game:draw_boss_announce()
    local a = self._boss_announce
    if not a then return end
    -- Leaving the run mid-banner (pause is fine; menu/shop is not) retires it.
    if self.STATE == self.STATES.MENU or self.STATE == self.STATES.SHOP then
        self._boss_announce = nil
        return
    end
    if self.STATE ~= self.STATES.PAUSED then
        a.age = a.age + (tonumber(self.real_dt) or 0)
    end
    if a.age > BOSS_ANNOUNCE_HOLD + BOSS_ANNOUNCE_FADE then
        self._boss_announce = nil
        return
    end
    local alpha = 1
    if a.age > BOSS_ANNOUNCE_HOLD then
        alpha = 1 - (a.age - BOSS_ANNOUNCE_HOLD) / BOSS_ANNOUNCE_FADE
    end
    local has_effect = a.effect ~= ""
    local band_h = has_effect and 46 or 30
    local band_y = 70
    love.graphics.setColor(0, 0, 0, 0.55 * alpha)
    love.graphics.rectangle("fill", 0, band_y, 320, band_h)
    love.graphics.setFont(self.FONTS.PIXEL.MEDIUM)
    love.graphics.setColor(self.C.RED[1], self.C.RED[2], self.C.RED[3], alpha)
    DynaText.draw(self._boss_announce_text, a.name, 0, band_y + 4, 320, "center")
    if has_effect then
        love.graphics.setFont(self.FONTS.PIXEL.SMALL)
        love.graphics.setColor(1, 1, 1, alpha)
        love.graphics.printf(a.effect, 10, band_y + 28, 300, "center")
    end
    love.graphics.setColor(1, 1, 1, 1)
end

--- Draw all bottom-screen card / joker / consumable tooltips after other UI.
function Game:draw_tooltips_on_top()
    if self:is_hand_scoring_active() then
        return
    end
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
---@param arrive_from Moveable|nil node this one replaces; see `Game:add_joker_by_def`
function Game:add_consumable(def_id, create_params, arrive_from)
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
    self:recompute_consumable_slot_layout()
    self:draw_consumables_row()
    self:_snap_consumables_vt()
    self:sync_consumables_interactivity()
    if arrive_from and arrive_from.VT and node.VT then
        node.VT.x, node.VT.y = arrive_from.VT.x, arrive_from.VT.y
        node.VT.scale = arrive_from.VT.scale or node.VT.scale
        node.VT.r = arrive_from.VT.r or node.VT.r
    else
        -- After the layout snap, so the burst converges on where the node actually landed
        -- rather than on the origin it was constructed at.
        self:begin_materializing_node(node)
    end
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
--- Remove an owned consumable.
---@param index number
---@param retain boolean|nil keep the node alive and return it, for the caller to animate out
---@return table|nil consumable the removed consumable
---@return Consumable|nil node the retained node, only when `retain` is set
function Game:remove_consumable_at(index, retain)
    if type(index) ~= "number" or index < 1 then return nil end
    if not self.consumables or type(self.consumables) ~= "table" then return nil end
    local c = self.consumables[index]
    if not c then return nil end
    table.remove(self.consumables, index)

    local freed_node = nil
    if self.consumable_nodes and self.consumable_nodes[index] then
        freed_node = self.consumable_nodes[index]
        table.remove(self.consumable_nodes, index)
        -- `retain` hands the node back to the caller to animate; it stays in `self.nodes` and
        -- is unlinked once it has finished. Everything else drops it here as before.
        if not retain then
            self:remove(freed_node)
            freed_node = nil
        end
    end
    self:refresh_consumable_capacity_from_negatives()
    self._consumable_layout_dirty = true

    if self.active_tooltip_consumable_index and
       self.active_tooltip_consumable_index >= index then
        self.active_tooltip_consumable_index =
            math.min(#self.consumables, self.active_tooltip_consumable_index)
    end

    self:draw_consumables_row()
    self:_snap_consumables_vt()
    self:sync_consumables_interactivity()
    if #(self.consumables or {}) == 0 and self.consumables_on_bottom then
        self:set_consumables_location(false)
    end
    self:sync_gamepad_focus_after_inventory_change()
    return c, freed_node
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

--- The reference allows a consumable in any state except mid-play, mid-deal and mid-tarot
--- (`card.lua:1528`), so levelling a hand at blind select — before committing to a boss —
--- is legal there. Cards that need a hand selection are still gated per card by
--- `hand_ready_for_tarot_selection`, which only accepts the play screen.
---
--- Cash-out is the one reference state deliberately left out: this port hides the consumable
--- row on that screen (see `show_consumables` in `Game:draw`) because the panel has nowhere
--- to sit on a 320x240 playfield, so allowing use there would be unreachable, not useful.
function Game:consumable_play_state_ok()
    local s = self.STATE
    return s == self.STATES.SELECTING_HAND or s == self.STATES.SHOP
        or s == self.STATES.OPEN_BOOSTER or s == self.STATES.BLIND_SELECT
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
            -- Needs a Joker it could actually edition (`card.lua:1533-1535`).
            if #self:editionless_jokers() < 1 then return false end
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
        -- Ectoplasm and Hex both draw from the editionless pool (`card.lua:1546-1548`).
        if (sid == "spectral_ectoplasm" or sid == "spectral_hex") and #self:editionless_jokers() < 1 then
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

--- Secret hands (indices 1–3) only appear in stats UI after being played once.
---@param hand_index integer
---@return boolean
function Game:is_hand_stats_visible(hand_index)
    hand_index = tonumber(hand_index)
    if not hand_index then return false end
    if hand_index <= 3 then
        return (tonumber(self.hand_play_counts and self.hand_play_counts[hand_index]) or 0) > 0
    end
    return hand_index >= 4 and hand_index <= #(self.handlist or {})
end

--- Level-scaled chips/mult for a poker hand (no boss modifiers).
---@param hand_index integer
---@return integer level, integer chips, number mult
function Game:get_hand_level_stats(hand_index)
    hand_index = tonumber(hand_index)
    local stats = hand_index and self.hand_stats and self.hand_stats[hand_index]
    if not stats then return 1, 0, 0 end
    local level = math.max(1, tonumber(stats.level) or 1)
    local chips = (tonumber(stats.base_chips) or 0) + ((level - 1) * (tonumber(stats.chips_per_level) or 0))
    local mult = (tonumber(stats.base_mult) or 0) + ((level - 1) * (tonumber(stats.mult_per_level) or 0))
    return level, math.floor(chips), mult
end

--- `get_hand_level_stats` with the active boss's base-chip/mult modifiers folded in, i.e. the
--- numbers the top readout would show for that hand. The level-up flourish walks these so the
--- ladder it plays lands on the same values the readout returns to afterwards.
---@param hand_index integer
---@return integer level, integer chips, number mult
function Game:get_hand_display_stats(hand_index)
    local level, chips, mult = self:get_hand_level_stats(hand_index)
    if self.boss_apply_hand_base_modifiers then
        chips, mult = self:boss_apply_hand_base_modifiers(chips, mult)
    end
    return level, chips, mult
end

function Game:planet_consumable_unlocked(def_id, def)
    if def_id == "planet_x" or def_id == "planet_ceres" or def_id == "planet_eris" then
        return self:has_played_hand_name(def and def.hand)
    end
    return true
end

--- Is a consumable with this id already in the player's hands?
---
--- The reference tracks this as `G.GAME.used_jokers`, set whenever a card of that centre is
--- created and cleared when the last copy leaves (`card.lua:352`, `card.lua:4745`). Deriving it
--- from the current inventory is equivalent for pool culling and cannot fall out of sync.
---@param id string
---@return boolean
function Game:consumable_center_in_play(id)
    for _, c in ipairs(self.consumables or {}) do
        if type(c) == "table" and c.id == id then return true end
    end
    return false
end

--- Reference `common_events.lua:2038-2043`: culling can empty a pool, and rather than create
--- nothing the reference falls back to one fixed centre per type.
local CONSUMABLE_POOL_FALLBACK = {
    tarot = "tarot_strength",
    planet = "planet_pluto",
    spectral = "spectral_incantation",
}

--- Pick a random consumable of `kind`.
---
--- Anything already in play is culled, which is what stops The High Priestess handing you two
--- Venus cards or the shop offering a tarot you are holding
--- (`reference/functions/common_events.lua:1987`). Showman is the documented escape hatch and
--- turns the whole cull off, exactly as it does in the reference.
---@param kind string
---@param exclude table|nil extra ids to leave out, keyed by id
---@param key string|nil RNG stream name
---@return string|nil
function Game:random_consumable_id_of_kind(kind, exclude, key)
    exclude = exclude or {}
    local pool = {}
    if not CONSUMABLE_DEFS then return nil end
    local allow_duplicates = self:hasJoker("j_ring_master")
    for def_id, def in pairs(CONSUMABLE_DEFS) do
        if type(def) == "table" and def.kind == kind and not exclude[def_id] then
            if kind ~= "planet" or self:planet_consumable_unlocked(def_id, def) then
                if allow_duplicates or not self:consumable_center_in_play(def_id) then
                    pool[#pool + 1] = def_id
                end
            end
        end
    end
    -- Deterministic order: `pairs` is unordered, so without this the same seed would draw
    -- differently between runs.
    table.sort(pool)
    if #pool == 0 then
        -- Only the cull can empty an otherwise valid pool, so fall back rather than create
        -- nothing. An explicitly excluded id is still honoured.
        local fallback = CONSUMABLE_POOL_FALLBACK[kind]
        if fallback and not exclude[fallback] then return fallback end
        return nil
    end
    return pool[self:random(key or "consumable", 1, #pool)]
end

function Game:random_non_fool_tarot_id(key)
    return self:random_consumable_id_of_kind("tarot", { tarot_fool = true }, key or "fool")
end

---@param hand_name string|nil
---@return string|nil
function Game:random_planet_id_for_hand_name(hand_name, key)
    if type(hand_name) ~= "string" or hand_name == "" then return nil end
    if not CONSUMABLE_DEFS then return nil end
    local pool = {}
    for def_id, def in pairs(CONSUMABLE_DEFS) do
        if type(def) == "table" and def.kind == "planet" and def.hand == hand_name then
            pool[#pool + 1] = def_id
        end
    end
    if #pool == 0 then return nil end
    return pool[self:random(key or "celestial", 1, #pool)]
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

--- Jokers that only enter random pools when the full deck contains a matching enhancement.
local JOKER_DECK_ENHANCEMENT_REQUIREMENTS = {
    j_lucky_cat = "lucky",
    j_stone_joker = "stone",
    j_glass = "glass",
    j_ticket = "gold",
    j_steel_joker = "steel",
}

---@param enhancement string|nil
---@return boolean
function Game:deck_has_enhancement(enhancement)
    if type(enhancement) ~= "string" or enhancement == "" then return false end
    return self:count_cards_in_full_deck(function(c) return c.enhancement == enhancement end) > 0
end

---@param joker_id string|nil
---@return boolean
function Game:joker_meets_deck_requirement(joker_id)
    if type(joker_id) ~= "string" then return true end
    local required = JOKER_DECK_ENHANCEMENT_REQUIREMENTS[joker_id]
    if not required then return true end
    return self:deck_has_enhancement(required)
end

function Game:reset_joker_pool_replacements()
    self.joker_pool_replacements = {}
end

--- Gros Michel / Cavendish and other registered pairs are mutually exclusive in random pools.
---@param joker_id string|nil
---@return boolean
function Game:joker_allowed_in_random_pool(joker_id)
    if type(joker_id) ~= "string" then return true end
    -- A Joker that has not been earned is out of the pool. The reference culls the same way
    -- in `get_current_pool` (`common_events.lua:1987`), exempting Legendaries, which are
    -- spawned by The Soul rather than rolled.
    if not JokerUnlocks.is_exempt(JOKER_DEFS and JOKER_DEFS[joker_id])
        and not self:is_joker_unlocked(joker_id) then
        return false
    end
    if not self:joker_meets_deck_requirement(joker_id) then return false end
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

function Game:random_joker_def_id(key)
    if not JOKER_DEFS then return nil end
    local pool = {}
    for id, def in pairs(JOKER_DEFS) do
        if type(def) == "table" then
            pool[#pool + 1] = id
        end
    end
    if #pool == 0 then return nil end
    return pool[self:random(key or "joker", 1, #pool)]
end

---@param rarity integer
---@return string|nil
function Game:random_joker_def_id_by_rarity(rarity, key)
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
    return pool[self:random(key or "joker", 1, #pool)]
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

--- Cap on what Temperance pays out (`c_temperance.config.extra` in the reference).
local TEMPERANCE_MAX = 50

--- What Temperance would pay if it were used right now: every owned Joker's sell value, capped.
---
--- The card's own tooltip quotes this back to the player -- "(Currently $12)" -- which is the
--- second localisation variable the reference fills in for it
--- (`reference/Balatro/functions/common_events.lua:2687-2696`), so the same sum has to serve
--- both the readout and the payout.
---@return integer
function Game:temperance_payout()
    local total = 0
    for _, j in ipairs(self.jokers or {}) do
        total = total + (tonumber(j and j.sell_cost) or 0)
    end
    return math.min(math.floor(total), TEMPERANCE_MAX)
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
            return enh[self:random("spe_card", 1, #enh)]
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
            -- Every hand at once has no single number to climb, so the reference points the
            -- readout at "All Hands" and runs the same ladder with `...` for the operands and
            -- `+` for each delta (`card.lua:1154-1176`).
            self:begin_hand_levelup_flourish("All Hands")
        elseif id == "spectral_familiar" then
            if hand and #hand.card_nodes > 0 then
                hand:destroy_card_at_index(self:random("random_destroy", 1, #hand.card_nodes))
            end
            local suits = { "Hearts", "Clubs", "Diamonds", "Spades" }
            for _ = 1, 3 do
                add_generated_card(self:random("familiar_create", 11, 13), suits[self:random("familiar_create", 1, #suits)], random_enhancement())
            end
        elseif id == "spectral_grim" then
            if hand and #hand.card_nodes > 0 then
                hand:destroy_card_at_index(self:random("random_destroy", 1, #hand.card_nodes))
            end
            local suits = { "Hearts", "Clubs", "Diamonds", "Spades" }
            for _ = 1, 2 do
                add_generated_card(14, suits[self:random("grim_create", 1, #suits)], random_enhancement())
            end
        elseif id == "spectral_incantation" then
            if hand and #hand.card_nodes > 0 then
                hand:destroy_card_at_index(self:random("random_destroy", 1, #hand.card_nodes))
            end
            local suits = { "Hearts", "Clubs", "Diamonds", "Spades" }
            for _ = 1, 4 do
                add_generated_card(self:random("incantation_create", 2, 10), suits[self:random("incantation_create", 1, #suits)], random_enhancement())
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
                -- `poll_edition('aura', nil, true, true)` (`card.lua:1195`).
                local picked = self:poll_guaranteed_edition("aura")
                ord[1].card_data.modifier = ord[1].card_data.modifier or {}
                -- Playing-card edition scoring is resolved by Hand so Aura and shop editions
                -- follow the same foil/holo/polychrome path (reference state_events.lua:759-776).
                ord[1].card_data.modifier.edition = picked
                self:discover_edition(picked)
                if ord[1].sync_visual_from_card_data then
                    ord[1]:sync_visual_from_card_data()
                end
                -- `set_edition` is never silent here (`card.lua:1195` passes no `silent`),
                -- so Aura's result announces itself like any other edition.
                self:announce_edition(ord[1], picked)
            end
        elseif id == "spectral_wraith" then
            local jid = self:random_joker_def_id_by_rarity(3, "wraith")
            if jid and self:joker_has_room_for_new("base") then
                self:add_joker_by_def(jid)
            end
            self.money = 0
        elseif id == "spectral_soul" then
            local jid = self:random_joker_def_id_by_rarity(4, "soul")
            if jid and self:joker_has_room_for_new("base") then
                self:add_joker_by_def(jid)
            end
        elseif id == "spectral_sigil" then
            if hand and hand.card_nodes and #hand.card_nodes > 0 then
                local suit = ({ "Hearts", "Clubs", "Diamonds", "Spades" })[self:random("sigil", 1, 4)]
                for _, node in ipairs(hand.card_nodes) do
                    if node and node.card_data then
                        node.card_data.suit = suit
                        node:sync_visual_from_card_data()
                    end
                end
            end
        elseif id == "spectral_ouija" then
            if hand and hand.card_nodes and #hand.card_nodes > 0 then
                local rank = self:random("ouija", 2, 14)
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
                    local j = self.jokers[self:random("ectoplasm", 1, #self.jokers)]
                    if j and Joker and Joker.normalize_edition and Joker.normalize_edition(j.edition) == "base" then
                        j.edition = Joker.normalize_edition("negative")
                        self:discover_edition(j.edition)
                        if j.refresh_quads then j:refresh_quads() end
                        self:refresh_joker_capacity_from_negatives()
                        self:announce_edition(j, j.edition)
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
                    hand:destroy_card_at_index(self:random("random_destroy", 1, #hand.card_nodes))
                end
            end
            self.money = (tonumber(self.money) or 0) + 20
        elseif id == "spectral_ankh" then
            if self.jokers and #self.jokers > 0 then
                local src = self.jokers[self:random("ankh_choice", 1, #self.jokers)]
                local src_id = src and src.def and src.def.id
                local src_edition = Joker and Joker.normalize_edition(src and src.edition) or "base"
                if src_id and src then
                    for i = #self.jokers, 1, -1 do
                        local j = self.jokers[i]
                        if j ~= src then
                            self:remove_owned_joker_at(i, false, true)
                        end
                    end
                    local clone_edition = (src_edition == "negative") and "base" or src_edition
                    if self:joker_has_room_for_new(clone_edition) and self:add_joker_by_def(src_id, { edition = clone_edition }) then
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
                            -- The copy never keeps Negative: the reference strips it straight
                            -- back off the clone (`card.lua:1448-1450`), so Ankh cannot turn
                            -- one extra Joker slot into two.
                            clone.edition = Joker.normalize_edition(clone_edition)
                            if clone.refresh_quads then clone:refresh_quads() end
                        end
                    end
                end
            end
        elseif id == "spectral_hex" then
            -- Hex draws from the editionless pool too (`card.lua:1469`).
            local _, hex_indices = self:editionless_jokers()
            if #hex_indices > 0 then
                local keep = hex_indices[self:random("hex", 1, #hex_indices)]
                local target = self.jokers[keep]
                if target and Joker then
                    target.edition = Joker.normalize_edition("polychrome")
                    self:discover_edition(target.edition)
                    if target.refresh_quads then target:refresh_quads() end
                end
                for i = #self.jokers, 1, -1 do
                    if i ~= keep then
                        self:remove_owned_joker_at(i, false, true)
                    end
                end
            end
        end

        clear_tarot_hand_ui()
        if hand and hand.layout then
            hand:layout(false)
        end
        -- Spectrals use `tarot1` like every other consumable (`card.lua:1292`, `:1349`).
        -- `tarot2` at (1, 0.4) is specifically the boss-debuff / "Nope" sting
        -- (`blind.lua:420-421`, `card.lua:1514-1515`), so it read as a rejection.
        if Sfx and Sfx.play then Sfx.play("tarot1") end
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
                -- Captured either side of the upgrade so the readout can walk from the old
                -- numbers to the new ones the way the reference does (`card.lua:1265-1267`).
                local from_level, from_chips, from_mult = self:get_hand_display_stats(target_idx)
                self:upgrade_hand_level_at_index(target_idx)
                local to_level, to_chips, to_mult = self:get_hand_display_stats(target_idx)
                self:begin_hand_levelup_flourish(target_hand_name,
                    from_level, from_chips, from_mult,
                    to_level, to_chips, to_mult)
            end
        end
        self:record_consumable_use_id(id)
        -- No cue of its own: the whole of a Planet is the level-up, and
        -- `begin_hand_levelup_flourish` owns that ladder. `timpani` belongs to the tarots that
        -- create cards (`card.lua:1376-1456`), not to levelling a hand.
        return
    end

    if kind ~= "tarot" then return end

    if id == "tarot_fool" then
        local last_id = self.last_consumable_use_id
        if last_id and last_id ~= "tarot_fool" then
            self:add_consumable(last_id)
        end
        if Sfx and Sfx.play then Sfx.play("tarot1") end
        clear_tarot_hand_ui()
        self:record_consumable_use_id("tarot_fool")
        return
    end

    local ord = ordered_nodes()

    if id == "tarot_magician" then
        self:convert_enhancement_ripple(ord, "lucky", 2)
    elseif id == "tarot_high_priestess" then
        local free = math.max(0, self:get_effective_consumable_capacity() - #(self.consumables or {}))
        local k = math.min(2, free)
        for _ = 1, k do
            local pid = self:random_consumable_id_of_kind("planet", {}, "high_priestess")
            if pid then self:add_consumable(pid) end
        end
    elseif id == "tarot_empress" then
        self:convert_enhancement_ripple(ord, "mult", 2)
    elseif id == "tarot_emperor" then
        local free = math.max(0, self:get_effective_consumable_capacity() - #(self.consumables or {}))
        local k = math.min(2, free)
        for _ = 1, k do
            local tid = self:random_consumable_id_of_kind("tarot", nil, "emperor")
            if tid then self:add_consumable(tid) end
        end
    elseif id == "tarot_hierophant" then
        self:convert_enhancement_ripple(ord, "bonus", 2)
    elseif id == "tarot_lovers" then
        self:convert_enhancement_ripple(ord, "wild", 1)
    elseif id == "tarot_chariot" then
        self:convert_enhancement_ripple(ord, "steel", 1)
    elseif id == "tarot_justice" then
        self:convert_enhancement_ripple(ord, "glass", 1)
    elseif id == "tarot_strength" then
        for i = 1, math.min(2, #ord) do
            local data = ord[i].card_data
            if data and type(data.rank) == "number" then
                -- Strength wraps Ace to 2 instead of clamping it (reference card.lua:1121-1135).
                data.rank = data.rank == 14 and 2 or math.min(14, data.rank + 1)
                ord[i]:sync_visual_from_card_data()
            end
        end
    elseif id == "tarot_hermit" then
        local m = tonumber(self.money) or 0
        local gain = math.min(m, 20)
        self.money = m + gain
        if Sfx and Sfx.play_money then Sfx.play_money() end
    elseif id == "tarot_wheel_of_fortune" then
        -- `do_random` includes Oops! All 6s; Wheel is normal/4 (reference card.lua:1467-1485).
        -- Only editionless Jokers are eligible (`card.lua:1468`).
        local eligible = self:editionless_jokers()
        if #eligible > 0 and self:do_random(1, 4, 1, "wheel_of_fortune") then
            local j = eligible[self:random("wheel_of_fortune", 1, #eligible)]
            if Joker and j then
                j.edition = Joker.normalize_edition(self:poll_guaranteed_edition("wheel_of_fortune"))
                self:discover_edition(j.edition)
                if j.refresh_quads then j:refresh_quads() end
                self:refresh_joker_capacity_from_negatives()
                self:announce_edition(j, j.edition)
            end
        else 
            local p = Popup()
            p:spawn("Nope!", "Nope", 160, 120, 3)
            G:addPopup(p)
            if Sfx and Sfx.play then
                -- Reference `card.lua:1513-1515`.
                Sfx.play("tarot2", 1, 0.4)
                self._nope_sfx_timer = 0.06
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
        self.money = (tonumber(self.money) or 0) + self:temperance_payout()
        if Sfx and Sfx.play_money then Sfx.play_money() end
    elseif id == "tarot_devil" then
        self:convert_enhancement_ripple(ord, "gold", 1)
    elseif id == "tarot_tower" then
        -- `Card:set_enhancement` removes the old rank/suit for Stone Card parity
        -- (reference/Balatro/card.lua:957-981).
        self:convert_enhancement_ripple(ord, "stone", 1)
    elseif id == "tarot_star" then
        self:convert_suit_ripple(ord, "Diamonds")
    elseif id == "tarot_moon" then
        self:convert_suit_ripple(ord, "Clubs")
    elseif id == "tarot_sun" then
        self:convert_suit_ripple(ord, "Hearts")
    elseif id == "tarot_world" then
        self:convert_suit_ripple(ord, "Spades")
    elseif id == "tarot_judgement" then
        local jid = nil
        for _ = 1, 32 do
            jid = self:_pick_joker_id_shop_rarity_distribution(function(lo, hi)
                return self:random("judgement", lo, hi)
            end)
            if jid then break end
        end
        if jid then self:add_joker_by_def(jid) end
    end

    self:record_consumable_use_id(id)
    if id ~= "tarot_hanged_man" then
        clear_tarot_hand_ui()
    else
        self.active_tooltip_card = nil
        if hand and hand.calculate_play then hand:calculate_play() end
    end

    -- Every tarot use gets the same cue, matching the reference's 19 `tarot1` sites.
    -- The money tarots layer their coin cue over it rather than replacing it.
    if Sfx and Sfx.play then
        Sfx.play("tarot1")
    end
end

--- Shared bookkeeping for any consumable that gets used (owned, shop instant-use, booster pick/use).
---@param c Consumable|table|nil
function Game:track_consumable_use(c)
    if type(c) ~= "table" then return end
    if c.kind == "tarot" then
        self.tarots_used = (tonumber(self.tarots_used) or 0) + 1
    end
    if type(c.id) == "string" and c.id ~= "" then
        -- Reference records usage by center key, preserving one entry across repeats
        -- (`reference/Balatro/functions/misc_functions.lua:1191-1203`).
        self.consumable_usage = self.consumable_usage or {}
        local usage = self.consumable_usage[c.id]
        if type(usage) ~= "table" then
            usage = { kind = c.kind, count = 0 }
            self.consumable_usage[c.id] = usage
        end
        usage.kind = usage.kind or c.kind
        usage.count = (tonumber(usage.count) or 0) + 1
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
    -- The node is retained so it can fly out and dissolve; the effect below still resolves on
    -- this frame (see `Game:begin_consumable_use_flight`).
    local c, node = self:remove_consumable_at(index, true)
    if not c then return false end
    self:begin_consumable_use_flight(node)
    self:track_consumable_use(c)
    self:apply_consumable_effect(c)
    self:sync_gamepad_focus_after_inventory_change()
    return true
end

--- Layout owned consumable nodes (top or bottom screen depending on `consumables_on_bottom`).
--- Lay out the owned consumable row and refresh its touch rects.
---
--- Called from both `Game:draw` and `TopUI:draw`, so twice a frame. The rect list is truncated
--- and its entries rewritten in place rather than rebuilt, which is what stops that costing a
--- table per consumable per call.
function Game:draw_consumables_row()
    local rects = self._consumable_rects
    if not rects then
        rects = {}
        self._consumable_rects = rects
    end
    for i = #rects, (self.consumables and #self.consumables or 0) + 1, -1 do
        rects[i] = nil
    end
    if not self.consumables or #self.consumables == 0 then return end
    -- The layout is pure arithmetic over the consumable list, its order and the two
    -- on-bottom flags, none of which change between the two screen draws of a frame,
    -- yet this ran from both Game:draw and TopUI:draw every frame. Every mutation
    -- point sets `_consumable_layout_dirty` (ShopUI.shop_layout_needs_refresh is the
    -- same pattern); direct `_apply_consumable_layout` calls stay unconditional.
    if self._consumable_layout_dirty ~= false then
        self:_apply_consumable_layout()
    end
end

--- Write a touch rect without allocating one if the slot already has a table.
local function set_rect(list, i, x, y, w, h)
    local r = list[i]
    if r then
        r.x, r.y, r.w, r.h = x, y, w, h
    else
        list[i] = { x = x, y = y, w = w, h = h }
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
    if not consumable_node or not self.consumable_nodes or self.consumables_on_bottom ~= true then return false end

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
    self._consumable_layout_dirty = true

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
    self:_snap_consumables_vt()
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
    local sold = false
    if sell_target.kind == "joker" then
        sold = self:sell_owned_joker(sell_target.index) and true or false
    elseif sell_target.kind == "consumable" then
        local idx = sell_target.index
        local node = self.consumable_nodes and self.consumable_nodes[idx]
        if node and node.juice_up then node:juice_up(0.3, 0.4) end
        local c, freed = self:remove_consumable_at(idx, true)
        -- Same gold dissolve a sold joker gets (`card.lua:1590-1612`).
        if freed then self:retain_dissolving_node(freed, self.C and self.C.GOLD) end
        if c then
            local value = self:consumable_sell_value(c)
            self.money = (tonumber(self.money) or 0) + value
            if self.active_tooltip_consumable_index == idx then
                self.active_tooltip_consumable_index = nil
            end
            sold = true
        end
    end
    -- Future kinds: vouchers, boosters, etc.
    if not sold then return false end
    -- One sell cue for both kinds; this is the only path that reaches sell_owned_joker.
    -- Jokers and cards are counted separately: Swashbuckler wants 20 Jokers sold, Burnt
    -- Joker wants 50 cards.
    if sell_target.kind == "joker" then
        self:add_career_stat("c_jokers_sold", 1)
    else
        self:add_career_stat("c_cards_sold", 1)
    end
    self:check_unlock("career_stat")
    self:check_unlock("modify_jokers")
    if Sfx and Sfx.play then
        -- Reference `card.lua:1602`, then the payout coin from `ease_dollars`
        -- (`common_events.lua:96`) and the card's own dissolve (`card.lua:1610-1611` →
        -- `card.lua:2156`). Only the first of the three was playing, so selling sounded
        -- like a menu blip rather than a card being torn up for money.
        Sfx.play("coin2")
        Sfx.play("coin1")
    end
    if Card and Card.play_dissolve_sfx then
        Card.play_dissolve_sfx()
    end
    self:sync_gamepad_focus_after_inventory_change()
    return true
end

function Game:_point_in_rect_simple(px, py, r)
    return r and px >= r.x and px <= (r.x + r.w) and py >= r.y and py <= (r.y + r.h)
end

function Game:draw_blind_chip_sprite(sprite_row, center_x, center_y, scale)
    -- The sheet is lazy, so the first blind drawn pays the load unless something warmed it
    -- first. `ensure` returns immediately once the image is resident, so this is a table
    -- lookup per frame after that.
    local atlas = self:ensure_animation_atlas_loaded("blind_chips")
    if not atlas or not atlas.image then return end
    local frames_per_blind = tonumber(atlas.frames) or 1
    local blind_row = tonumber(sprite_row) or 0
    local anim_fps = 10
    local t = love.timer.getTime()
    local frame = math.floor(t * anim_fps) % math.max(1, frames_per_blind)
    local sprite_index = (blind_row * frames_per_blind) + frame
    local quad, cell_w, cell_h = self:atlas_cell_quad(atlas, sprite_index)
    if not quad then return end
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
    return eligible[self:random("orbital", 1, #eligible)]
end

function Game:tag_key_for_id(tag_id)
    local type_name = self:tag_type_for_id(tag_id)
    if not type_name then return nil end
    if type_name == "d6" then return "tag_d_six" end
    if type_name == "topup" then return "tag_top_up" end
    if type_name == "speed" then return "tag_skip" end
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
    -- Skipping announces itself (`button_callbacks.lua:2763`), on top of whatever the tag
    -- itself plays. Taking a blind's reward was silent here.
    if Sfx and Sfx.play then Sfx.play("generic1") end
    -- The reference rebuilds the blind-select UI after a skip and runs the pack tags against
    -- the fresh screen (`reference/Balatro/game.lua:3282-3294`). Doing it here, after the
    -- blind index has moved on, is what makes a pack opened by a skip return to the next
    -- blind rather than to whatever state the skip was mid-way through leaving.
    self:apply_new_blind_choice_tags()
    return true
end

--- Fire the first pending pack tag, if any. One per blind-select screen: the reference
--- breaks out of the loop as soon as a tag reports it fired
--- (`reference/Balatro/game.lua:3293-3294`), so two Buffoon Tags open one pack now and the
--- other at the next blind choice.
---@return boolean fired
function Game:apply_new_blind_choice_tags()
    if type(self.tags) ~= "table" then return false end
    for i, tag in ipairs(self.tags) do
        if tag and Tag.NEW_BLIND_CHOICE_TYPES[tag.type] then
            -- Removed before firing: the tag opens a pack, which changes state, and a tag
            -- still in the tray at that point would draw over the pack and fire again.
            self:removeTag(i)
            if tag.Use then tag:Use("new_blind_choice") end
            return true
        end
    end
    return false
end

function Game:try_gamepad_skip_blind()
    if self.STATE ~= self.STATES.BLIND_SELECT then return false end
    if self._blind_slide then return false end
    local blind_index = tonumber(self.current_blind_index)
    if not blind_index then return false end
    local skip_id = self.skips and self.skips[blind_index]
    if skip_id == nil or not self:is_blind_selectable(blind_index) then return false end
    self.active_tooltip_skip_blind_index = nil
    self.active_tooltip_blind_index = nil
    return self:skip_blind(blind_index) == true
end

function Game:draw_bottom_blind_select()
    love.graphics.push()
    love.graphics.translate(0, self:get_blind_slide_dy())
    local card_w, card_h = 98, 300
    local gap = 8
    local start_x = 6
    local y = 8
    self._blind_select_tap_rects = {}
    self._blind_skip_tag_tap_rects = {}
    self._blind_info_tap_rects = {}
    for i = 1, 3 do
        love.graphics.push()
        love.graphics.translate(0, self:get_blind_slide_dy(i))
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
            draw_button_with_shadow(btn_x, btn_y, selectWidth, selectHeight, 4, 4, self.C.ORANGE, self.C.BLOCK.SHADOW, 2)
        else
            draw_button_with_shadow(btn_x, btn_y, selectWidth, selectHeight, 4, 4, self.C.GREY, self.C.BLOCK.SHADOW, 2)
        end
        self._blind_select_tap_rects[i] = { x = btn_x, y = btn_y, w = selectWidth, h = selectHeight }

        love.graphics.setColor(self.C.WHITE)
        love.graphics.setFont(self.FONTS.PIXEL.SMALL)
        local tx = x + math.floor(card_w / 2) - math.floor(selectWidth / 2)
        love.graphics.printf(selectText, tx, btn_y + 2, selectWidth, "center")

        -- Wide enough for the longest boss name ("Crimson Heart"), which overran the old 70 px
        -- pill. The card's inner border sits at x+8..x+90, so this keeps a 4 px margin inside it.
        local blindWidth = 82
        local label = self:get_blind_display_name(i)
        love.graphics.setColor(blind_color)
        tx = x + math.floor(card_w / 2) - math.floor(blindWidth / 2)
        love.graphics.rectangle("fill", tx, btn_y + selectHeight + 8, blindWidth, selectHeight, 4, 4)

        love.graphics.setColor(self.C.WHITE)
        love.graphics.setFont(Fonts.fit(self, self.FONTS.PIXEL.SMALL, label, blindWidth - 4))
        love.graphics.printf(label, tx, btn_y + selectHeight + 8 + 2, blindWidth, "center")
        love.graphics.setFont(self.FONTS.PIXEL.SMALL)
        self:draw_blind_chip_anim(i, x + math.floor(card_w / 2), y + 80, 1.1)
        self._blind_info_tap_rects[i] = {
            x = x + 4,
            y = btn_y + selectHeight + 4,
            w = card_w - 8,
            h = 78,
            blind_index = i,
        }

        -- Sized for "Reward: $$$$$$+" (a reward of 5, the maximum, prints six signs plus a plus),
        -- which is the widest thing this box ever holds and used to spill past both its edges.
        local scoreWidth = 86
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
        local req = NumberFormat.format(math.floor(tonumber(target) or 0))
        local rx = x + math.floor(card_w / 2) - math.floor(scoreWidth / 2)
        love.graphics.setFont(Fonts.fit(self, self.FONTS.PIXEL.SMALL, req, scoreWidth - 2))
        love.graphics.printf(req, rx, ty + 12, scoreWidth, "center")
        love.graphics.setFont(self.FONTS.PIXEL.SMALL)

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
            -- The tag icon takes the left 32 px of the box; a 4 px gutter on both sides of the
            -- button left only 50 px for the label, which "Skip Blind" overran. Two pixels either
            -- side of the button is enough separation and buys back the width.
            p = 2
            local buttonX = sx + 32 + p
            local buttonY = sy + p
            local buttonW = sw - 32 - 2*p
            local buttonH = sh - 2 * p
            local can_skip = selectable and (self.skips and self.skips[i] ~= nil)
            if can_skip then
                draw_button_with_shadow(buttonX, buttonY, buttonW, buttonH, 4, 4, self.C.MULT, self.C.BLOCK.SHADOW, 2)
            else
                draw_button_with_shadow(buttonX, buttonY, buttonW, buttonH, 4, 4, self.C.GREY, self.C.BLOCK.SHADOW, 2)
            end
            self._blind_skip_tap_rects = self._blind_skip_tap_rects or {}
            self._blind_skip_tap_rects[i] = { x = buttonX, y = buttonY, w = buttonW, h = buttonH, blind_index = i }
            love.graphics.setColor(self.C.WHITE)
            -- No "(B)": cancel is rebindable (`InputBindings.ROLES`), so a baked-in button letter
            -- goes stale the moment it is remapped, and it was what pushed this label past its
            -- button. The gamepad hint belongs with the bindings, not printed on a touch target.
            local buttonText = "Skip Blind"
            love.graphics.setFont(Fonts.fit(self, self.FONTS.PIXEL.SMALL, buttonText, buttonW - 4))
            local button_font = love.graphics.getFont()
            love.graphics.print(buttonText, buttonX + math.floor(buttonW/2) - math.floor(button_font:getWidth(buttonText)/2), buttonY + math.floor(buttonH/2) - math.floor(button_font:getHeight(buttonText)/2))
            love.graphics.setFont(self.FONTS.PIXEL.SMALL)

            love.graphics.pop()
        end
        love.graphics.pop()
    end

    self._boss_reroll_btn_rect = nil
    -- Rides in with the last blind card.
    love.graphics.push()
    love.graphics.translate(0, self:get_blind_slide_dy(3))
    if (self:has_voucher("v_directors_cut") or self:has_voucher("v_retcon")) then
        -- Anchored to the boss column, not to a screen-centre guess: at 200 - w - 6 this sat
        -- squarely over the Big Blind's Select button. The three columns are 6/112/218, so the
        -- boss card runs 218..316 and the button rides above it in the strip the upcoming
        -- blinds leave free (their cards start at y = 44). When the boss is the selectable
        -- blind its card comes up to y = 8 and the button is clamped to the top edge, where it
        -- overlaps nothing but that card's own padding — its Select button starts at y = 22.
        local bw, bh = 64, 16
        local boss_x = start_x + 2 * (card_w + gap)
        local boss_y = self:is_blind_selectable(3) and 8 or 44
        local bx = boss_x + card_w - bw - 6
        local by = math.max(2, boss_y - bh - 6)
        local can_afford = self:can_afford_price(10)
        local lim_ok = true
        if self:has_voucher("v_directors_cut") and not self:has_voucher("v_retcon") then
            lim_ok = (tonumber(self.boss_rerolls_used_this_ante) or 0) < 1
        end
        local col = (can_afford and lim_ok) and self.C.GREEN or self.C.GREY
        if _G.draw_rect_with_shadow then
            draw_button_with_shadow(bx, by, bw, bh, 4, 2, col, self.C.BLOCK.SHADOW, 1)
        else
            love.graphics.setColor(col)
            love.graphics.rectangle("fill", bx, by, bw, bh, 4, 4)
        end
        self._boss_reroll_btn_rect = { x = bx, y = by, w = bw, h = bh }
        love.graphics.setColor(self.C.WHITE)
        local reroll_label = "Reroll $10"
        love.graphics.setFont(Fonts.fit(self, self.FONTS.PIXEL.SMALL, reroll_label, bw - 6))
        local reroll_font = love.graphics.getFont()
        love.graphics.printf(reroll_label, bx, by + math.floor((bh - reroll_font:getHeight()) / 2), bw, "center")
        love.graphics.setFont(self.FONTS.PIXEL.SMALL)
    end
    love.graphics.pop()
    love.graphics.pop()
end

function Game:draw_shop_button(param)
    ShopUI.draw_shop_button(self, param)
end

function Game:draw_bottom_shop()
    ShopUI.draw_bottom_shop(self)
end

function Game:_draw_blind_info_tooltip()
    -- Tooltips draw outside the slide transform and anchor to un-offset rects,
    -- so they would hang in place while the cards travel.
    if self._blind_slide then return end
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
    if self._blind_slide then return end
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
    if self._blind_slide then return true end
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
    local BOTTOM_H = 240
    local panel_w = 304
    local panel_x = math.floor((320 - panel_w) * 0.5 + 0.5)
    local panel_y = 26
    local panel_h = 188
    if self._pause_show_settings then
        local tab = self._pause_settings_tab
        if tab == "controls" or tab == "performance" or tab == "motion" or tab == "tilt" then
            panel_y = 4
            panel_h = BOTTOM_H - panel_y - 4
        else
            -- Taller than the pause page: two volume sliders plus the speed row.
            panel_y = 12
            panel_h = 224
        end
    end
    if _G.draw_rect_with_shadow then
        draw_rect_with_shadow(panel_x, panel_y, panel_w, panel_h, 6, 3, self.C.BLOCK.BACK, self.C.BLOCK.SHADOW, 3)
    else
        love.graphics.setColor(self.C.PANEL)
        love.graphics.rectangle("fill", panel_x, panel_y, panel_w, panel_h, 6, 6)
    end

    local function draw_btn(r, label, color, focused)
        love.graphics.setColor(color)
        draw_button_with_shadow(r.x, r.y, r.w, r.h, 4, 4, color, self.C.BLOCK.SHADOW, 2)
        if focused then
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", r.x + 0.5, r.y + 0.5, r.w - 1, r.h - 1)
        end
        love.graphics.setColor(self.C.WHITE)
        local btn_font = (r.h and r.h <= 20) and self.FONTS.PIXEL.SMALL or self.FONTS.PIXEL.MEDIUM
        love.graphics.setFont(btn_font)
        local ty = r.y + math.floor((r.h - love.graphics.getFont():getHeight()) * 0.5 + 0.5)
        love.graphics.printf(label, r.x, ty - 1, r.w, "center")
    end

    local function draw_cell(r, label, value, hint, focused, listening)
        local fill = self.C.CHIPS
        if listening then
            fill = self.C.ORANGE
        elseif focused then
            fill = self.C.MONEY or self.C.ORANGE
        end
        love.graphics.setColor(fill)
        draw_button_with_shadow(r.x, r.y, r.w, r.h, 3, 3, fill, self.C.BLOCK.SHADOW, 2)
        if focused or listening then
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", r.x + 0.5, r.y + 0.5, r.w - 1, r.h - 1)
        end
        love.graphics.setFont(self.FONTS.PIXEL.SMALL)
        love.graphics.setColor(self.C.WHITE)
        love.graphics.printf(string.format("%s (%s)", label, value), r.x + 4, r.y + 4, r.w - 8, "center")
        if hint and hint ~= "" then
            love.graphics.setColor(self.C.WHITE)
            love.graphics.printf(hint, r.x + 4, r.y + 15, r.w - 8, "left")
        end
    end

    local function is_controls_bind_focused(col, row)
        if self._controls_listen_role then return false end
        return self._controls_focus_zone == "list"
            and self._controls_focus_col == col
            and self._controls_focus_row == row
    end

    local function is_controls_bind_listening(role, slot)
        return self._controls_listen_role == role and self._controls_listen_slot == slot
    end

    local function is_controls_footer_focused(which)
        if self._controls_listen_role then return false end
        return self._controls_focus_zone == "footer" and self._controls_focus_footer == which
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
        love.graphics.setColor(self.C.WHITE)
        love.graphics.setFont(self.FONTS.PIXEL.MEDIUM)
        if self._pause_settings_tab == "controls" then
            love.graphics.printf("Controls", panel_x, panel_y + 4, panel_w, "center")
            if self._controls_listen_role then
                love.graphics.setColor(self.C.ORANGE)
                love.graphics.setFont(self.FONTS.PIXEL.SMALL)
                local listen_label = string.format(
                    "Press button for %s (slot %d)",
                    InputBindings.role_label(self._controls_listen_role),
                    math.floor(tonumber(self._controls_listen_slot) or 1)
                )
                love.graphics.printf(listen_label, panel_x, panel_y + 24, panel_w , "center")
            else
                love.graphics.setColor(self.C.GREY)
                love.graphics.setFont(self.FONTS.PIXEL.SMALL)
                love.graphics.printf("D-pad: move  A: rebind  B: back", panel_x, panel_y + 24, panel_w, "center")
            end

            local bindings = self:control_bindings()
            local slot_cols, role_rows = self:controls_list_dims()
            local list_pad = 8
            local list_x = panel_x + list_pad
            local list_w = panel_w - list_pad * 2
            local row_h = 28
            local list_y = panel_y + 40
            local bind_w = 28
            local bind_h = 18
            local bind_gap = 4
            local footer_h = 18
            self._controls_role_rects = {}

            for row = 1, role_rows do
                local role = InputBindings.ROLES[row]
                if role then
                    local ry = list_y + (row - 1) * row_h
                    local text_w = list_w - slot_cols * bind_w - (slot_cols - 1) * bind_gap - 6
                    love.graphics.setFont(self.FONTS.PIXEL.SMALL)
                    love.graphics.setColor(self.C.WHITE)
                    love.graphics.printf(InputBindings.role_label(role), list_x, ry + 1, text_w, "left")
                    local hint = InputBindings.role_hint(role)
                    if hint and hint ~= "" then
                        love.graphics.setColor(self.C.GREY)
                        love.graphics.printf(hint, list_x, ry + 12, text_w, "left")
                    end
                    for slot = 1, slot_cols do
                        local bx = list_x + list_w - (slot_cols - slot + 1) * bind_w - (slot_cols - slot) * bind_gap
                        local by = ry + 3
                        local r = {
                            x = bx,
                            y = by,
                            w = bind_w,
                            h = bind_h,
                            role = role,
                            slot = slot,
                            col = slot,
                            row = row,
                        }
                        self._controls_role_rects[#self._controls_role_rects + 1] = r
                        local label = InputBindings.slot_label(role, slot, bindings)
                        local listening = is_controls_bind_listening(role, slot)
                        local focused = is_controls_bind_focused(slot, row)
                        local color = self.C.RED
                        if listening then
                            color = self.C.ORANGE
                        end
                        draw_btn(r, label, color, focused or listening)
                    end
                end
            end

            local footer_y = list_y + role_rows * row_h + 4
            local footer_w = math.floor((list_w - bind_gap) * 0.5)
            self._pause_controls_reset_rect = {
                x = list_x,
                y = footer_y,
                w = footer_w,
                h = footer_h,
            }
            self._pause_back_rect = {
                x = list_x + footer_w + bind_gap,
                y = footer_y,
                w = footer_w,
                h = footer_h,
            }
            draw_btn(self._pause_controls_reset_rect, "Reset", self.C.RED, is_controls_footer_focused("reset"))
            draw_btn(self._pause_back_rect, "Back", self.C.MULT, is_controls_footer_focused("back"))
        elseif self._pause_settings_tab == "performance" then
            love.graphics.printf("Performance Lab", panel_x, panel_y + 4, panel_w, "center")
            love.graphics.setColor(self.C.GREY)
            love.graphics.setFont(self.FONTS.PIXEL.SMALL)
            love.graphics.printf("Session only - restart restores baseline", panel_x, panel_y + 24, panel_w, "center")

            local stats = RenderProfiler.snapshot()
            local stat_y = panel_y + 42
            love.graphics.setColor(self.C.PANEL)
            love.graphics.rectangle("fill", panel_x + 8, stat_y, panel_w - 16, 42, 4, 4)
            love.graphics.setColor(self.C.WHITE)
            love.graphics.printf(string.format("DRAW %.0f / %.0f peak", stats.drawcalls, stats.drawcalls_peak),
                panel_x + 14, stat_y + 5, 132, "left")
            love.graphics.printf(string.format("GPU %.2f / %.2f ms", stats.gpu, stats.gpu_peak),
                panel_x + 150, stat_y + 5, 136, "left")
            love.graphics.printf(string.format("CALL %.0f / %.0f peak", stats.submissions, stats.submissions_peak),
                panel_x + 14, stat_y + 21, 132, "left")
            love.graphics.printf(string.format("CPU %.2f / %.2f ms", stats.cpu, stats.cpu_peak),
                panel_x + 150, stat_y + 21, 136, "left")

            self._perf_toggle_rects = {}
            local definitions = PerformanceLab.available_definitions()
            local row_y = panel_y + 91
            local row_h = 23
            for i, definition in ipairs(definitions) do
                local r = {
                    x = panel_x + 10,
                    y = row_y + (i - 1) * (row_h + 3),
                    w = panel_w - 20,
                    h = row_h,
                    experiment_id = definition.id,
                }
                self._perf_toggle_rects[i] = r
                local active = PerformanceLab.is_enabled(definition.id)
                local color = active and self.C.GREEN or self.C.PANEL
                local state = active and "ON" or "OFF"
                draw_btn(r, definition.label .. "  " .. state, color, is_pause_focused("perf_toggle", i))
            end

            -- Which font ladder is live, and whether its per-size sheets were actually found.
            -- "Crisp fonts" changes metrics on every platform but only changes sharpness where
            -- the sheets shipped, so the toggle alone does not tell you whether it worked.
            love.graphics.setFont(self.FONTS.PIXEL.SMALL)
            love.graphics.setColor(self.C.GREY)
            love.graphics.printf(Fonts.status_line(self), panel_x + 10,
                row_y + #definitions * (row_h + 3) + 2, panel_w - 20, "center")

            local footer_y = panel_y + 198
            local gap = 4
            local footer_w = math.floor((panel_w - 20 - gap * 2) / 3)
            self._perf_reset_rect = { x = panel_x + 10, y = footer_y, w = footer_w, h = 24 }
            self._perf_disable_rect = { x = self._perf_reset_rect.x + footer_w + gap, y = footer_y, w = footer_w, h = 24 }
            self._pause_back_rect = { x = self._perf_disable_rect.x + footer_w + gap, y = footer_y, w = footer_w, h = 24 }
            draw_btn(self._perf_reset_rect, "Reset", self.C.BOOSTER, is_pause_focused("perf_reset"))
            draw_btn(self._perf_disable_rect, "All Off", self.C.RED, is_pause_focused("perf_disable"))
            draw_btn(self._pause_back_rect, "Back", self.C.MULT, is_pause_focused("back"))
        else
            -- ===== SETTINGS GENERAL TAB =====
            love.graphics.printf("Settings", panel_x, panel_y + 10, panel_w, "center")

            love.graphics.setColor(self.C.GREY)
            love.graphics.setFont(self.FONTS.PIXEL.SMALL)
            love.graphics.printf("Game Speed", panel_x, panel_y + 34, panel_w, "center")

            -- Reference `UI_definitions.lua:2302`: these are the shipping game's four options.
            local speeds = { 0.5, 1, 2, 4 }
            local speed_labels = { "x0.5", "x1", "x2", "x4" }
            local cur_speed = (self.SETTINGS and self.SETTINGS.GAMESPEED) or 1
            local sb_w = 38
            local sb_h = 24
            local sb_gap = 4
            local total_sb = #speeds * sb_w + (#speeds - 1) * sb_gap
            local sb_start_x = panel_x + math.floor((panel_w - total_sb) * 0.5 + 0.5)
            local sb_y = panel_y + 50
            self._pause_speed_rects = {}
            for i, spd in ipairs(speeds) do
                local rx = sb_start_x + (i - 1) * (sb_w + sb_gap)
                local r = { x = rx, y = sb_y, w = sb_w, h = sb_h, speed = spd }
                self._pause_speed_rects[i] = r
                local is_active = math.abs(cur_speed - spd) < 0.01
                local btn_color = is_active and self.C.ORANGE or self.C.PANEL
                love.graphics.setColor(btn_color)
                draw_button_with_shadow(rx, sb_y, sb_w, sb_h, 4, 4, btn_color, self.C.BLOCK.SHADOW, 4)
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

            -- The active speed button is already highlighted, so a "Current: xN" line under
            -- it was saying the same thing twice; the room it frees is what the screenshake
            -- slider and the reduced-motion toggle sit in.
            local track_x = panel_x + 36
            local track_w = panel_w - 72
            local knob_r = 7
            local function draw_volume_slider(label, label_y, track_y, vol)
                love.graphics.setColor(self.C.GREY)
                love.graphics.setFont(self.FONTS.PIXEL.SMALL)
                love.graphics.printf(label, panel_x, label_y, panel_w, "center")
                local knob_x = track_x + (vol / 100) * track_w
                local prev_lw = love.graphics.getLineWidth()
                love.graphics.setColor(self.C.GREY)
                love.graphics.setLineWidth(2)
                love.graphics.line(track_x, track_y, track_x + track_w, track_y)
                love.graphics.setColor(self.C.WHITE)
                love.graphics.circle("fill", knob_x, track_y, knob_r)
                love.graphics.setLineWidth(prev_lw)
                return {
                    x = track_x - knob_r,
                    y = track_y - 12,
                    w = track_w + knob_r * 2,
                    h = 24,
                    track_x = track_x,
                    track_w = track_w,
                    track_y = track_y,
                }
            end

            self._pause_music_slider_rect =
                draw_volume_slider("Music Volume", panel_y + 80, panel_y + 96, self:get_music_volume())
            self._pause_sfx_slider_rect =
                draw_volume_slider("SFX Volume", panel_y + 108, panel_y + 124, self:get_sfx_volume())
            -- Reference `UI_definitions.lua:2305`: screenshake is a 0-100 slider, alongside
            -- the volumes, not a hidden constant.
            self._pause_screenshake_slider_rect =
                draw_volume_slider("Screenshake", panel_y + 136, panel_y + 152, self:get_screenshake_percent())

            -- Board movement, as the reference arranges it (`UI_definitions.lua:2306-2309`): each
            -- setting is its own control in the list rather than one combined mode. Screenshake is
            -- the slider above; reduced motion and tilt are toggles.
            local row_w, row_h = 140, 22
            local row_gap = 8
            local reduced = self:reduced_motion_enabled()
            -- The tilt toggle is hidden where there is no accelerometer to read, the way the
            -- reference gates rumble on `G.F_RUMBLE` rather than showing a setting that does
            -- nothing (`UI_definitions.lua:2303`).
            local show_tilt = Tilt.supported()
            local jd_on = self:joker_display_enabled()
            -- Three toggles do not fit at the old 140 px, and 22 px tall buttons take the
            -- MEDIUM face (`draw_btn`), which does not fit either. The row is laid out to the
            -- panel's full width at 20 px tall so all three read at SMALL.
            local toggle_row = {
                { key = "reduced_motion", label = "Reduce", on = reduced, on_is_good = false },
            }
            if show_tilt then
                toggle_row[#toggle_row + 1] = { key = "tilt", label = "Tilt", on = self:tilt_enabled() }
            end
            toggle_row[#toggle_row + 1] = { key = "joker_display", label = "Joker Info", on = jd_on }

            local toggle_h = 20
            local toggle_margin = 2
            local toggle_count = #toggle_row
            local toggle_w = math.floor(
                (panel_w - toggle_margin * 2 - row_gap * (toggle_count - 1)) / toggle_count)
            local toggle_span = toggle_w * toggle_count + row_gap * (toggle_count - 1)
            local toggle_x = panel_x + math.floor((panel_w - toggle_span) * 0.5 + 0.5)
            self._pause_reduced_motion_rect = nil
            self._pause_tilt_rect = nil
            self._pause_joker_display_rect = nil
            for i, t in ipairs(toggle_row) do
                local r = {
                    x = toggle_x + (i - 1) * (toggle_w + row_gap),
                    y = panel_y + 164,
                    w = toggle_w,
                    h = toggle_h,
                }
                -- Reduced motion is the one toggle whose "on" is a reduction, so it keeps the
                -- inverted colouring it has always had.
                local good = (t.on_is_good == false) and not t.on or (t.on_is_good ~= false and t.on)
                draw_btn(r, t.label .. " " .. (t.on and "ON" or "OFF"),
                    good and self.C.GREEN or self.C.PANEL,
                    is_pause_focused(t.key))
                if t.key == "reduced_motion" then
                    self._pause_reduced_motion_rect = r
                elseif t.key == "tilt" then
                    self._pause_tilt_rect = r
                else
                    self._pause_joker_display_rect = r
                end
            end

            local open_x
            self._pause_controls_open_rect = { x = 0, y = panel_y + 190, w = row_w, h = row_h }
            if BuildFlags.release then
                open_x = panel_x + math.floor((panel_w - row_w) * 0.5 + 0.5)
                self._pause_controls_open_rect.x = open_x
                self._pause_performance_open_rect = nil
            else
                open_x = panel_x + math.floor((panel_w - row_w * 2 - row_gap) * 0.5 + 0.5)
                self._pause_controls_open_rect.x = open_x
                self._pause_performance_open_rect = {
                    x = open_x + row_w + row_gap, y = panel_y + 190, w = row_w, h = row_h,
                }
            end
            draw_btn(self._pause_controls_open_rect, "Controls", self.C.BOOSTER, is_pause_focused("controls_open"))
            if self._pause_performance_open_rect then
                draw_btn(self._pause_performance_open_rect, "Performance", self.C.ORANGE,
                    is_pause_focused("performance_open"))
            end

            self._pause_back_rect = {
                x = panel_x + math.floor((panel_w - row_w) * 0.5 + 0.5), y = panel_y + 216,
                w = row_w, h = 18,
            }
            draw_btn(self._pause_back_rect, "Back", self.C.MULT, is_pause_focused("back"))
        end
    else
        -- ===== MAIN PAUSE PAGE =====
        love.graphics.setColor(self.C.WHITE)
        love.graphics.setFont(self.FONTS.PIXEL.MEDIUM)
        love.graphics.printf("Paused", panel_x, panel_y + 10, panel_w, "center")

        -- Five rows now: the reference offers the collection from its in-run options overlay
        -- (`UI_definitions.lua:2223`), so a Joker you are being offered can be looked up
        -- mid-run. Rows are 30 px apart rather than 36 to keep the panel the same height.
        local btn_w, btn_h = 176, 26
        local btn_x = panel_x + math.floor((panel_w - btn_w) * 0.5 + 0.5)
        self._pause_continue_rect   = { x = btn_x, y = panel_y + 36,  w = btn_w, h = btn_h }
        self._pause_settings_rect   = { x = btn_x, y = panel_y + 66,  w = btn_w, h = btn_h }
        self._pause_collection_rect = { x = btn_x, y = panel_y + 96,  w = btn_w, h = btn_h }
        self._pause_new_run_rect    = { x = btn_x, y = panel_y + 126, w = btn_w, h = btn_h }
        self._pause_save_quit_rect  = { x = btn_x, y = panel_y + 156, w = btn_w, h = btn_h }

        local can_save = not self:is_hand_scoring_active()
        draw_btn(self._pause_continue_rect,   "Continue",      self.C.GREEN, is_pause_focused("continue"))
        draw_btn(self._pause_settings_rect,   "Settings",      self.C.BOOSTER, is_pause_focused("settings"))
        draw_btn(self._pause_collection_rect, "Collection",    self.C.PURPLE, is_pause_focused("collection"))
        draw_btn(self._pause_new_run_rect,    "New Run",        self.C.RED, is_pause_focused("new_run"))
        draw_btn(self._pause_save_quit_rect,  "Save and Quit",  can_save and self.C.BLUE or self.C.GREY, is_pause_focused("save_quit"))

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
    self:seed_rng_stream(self:generate_run_seed())
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
        self._booster_closing = nil
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
        self.deck = Deck(self)
    else
        self.deck = nil
    end
    self.pending_discard = {}
    self:_clear_pending_discard_nodes()
    self.jokers_on_bottom = false
    self.consumables_on_bottom = false
    self._consumable_layout_dirty = true
    self:reset_joker_pool_replacements()

    -- Every atlas a run can touch, not just the ones a run opens first. `centers` is the
    -- notable addition at 2 MiB: nothing here had an unload path at all, so once a run
    -- had touched these they stayed resident until the process exited. All are lazy, so
    -- over-freeing costs one reload on next use and under-freeing costs permanent
    -- residency out of 64 MB. `chips` is deliberately absent — the main menu itself
    -- draws it (main_menu_ui.lua:871), so freeing it here would only churn.
    local run_atlases = {
        "cards_1", "cards_2", "Booster", "Voucher", "stickers",
        "centers", "tags", "edition_foil", "edition_holo",
    }
    for _, name in ipairs(run_atlases) do
        if self.unload_asset_atlas then
            self:unload_asset_atlas(name)
        end
    end
    for _, name in ipairs({ "blind_chips", "shop_sign" }) do
        if self.unload_animation_atlas then
            self:unload_animation_atlas(name)
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

    -- Consumable sprites are refcounted the same way, and are balanced by `Game:remove`.
    -- Sweeping them here is the same insurance the joker sprites get above: nothing should
    -- be outstanding by now, and anything that is would otherwise stay resident for good.
    if Consumable and Consumable.release_all_sprites then
        Consumable.release_all_sprites()
    end
end

function Game:enter_main_menu()
    self.STAGE = self.STAGES.MAIN_MENU
    self._menu_sub_state = "main"
    self._menu_page = "main"
    self._main_menu_rects = nil
    self._how_to_play_back_rect = nil
    self._how_to_play_rects = nil
    self._stats_back_rect = nil
    self._profile_delete_confirm = false
    self._profile_selected = nil
    self._profile_focus_index = 1
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

--- Leaving the menu: its screen retired and its sheets freed. First, so the menu's 4 MiB and
--- the run's 4 MiB never both sit in a 64 MB budget at once.
---
--- The sub-state is dropped here rather than at the button press for the same reason the
--- sheets are: the scene still draws through the wipe's fade-in, and clearing it early popped
--- deck select back to the root main menu in front of the player.
function Game:_run_start_leave_menu()
    self._menu_sub_state = nil
    if self.unload_asset_atlas then
        self:unload_asset_atlas("balatro")
        self:unload_asset_atlas("title_ace")
    end
    if self.unload_animation_atlas then
        self:unload_animation_atlas("menu")
    end
end

--- Clearing the previous run and seeding the new one.
function Game:_run_start_reset_objects()
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
        self.deck = Deck(self)
    end
    -- Fresh run: use the seed typed in deck select, or create a shareable identity.
    -- A user-typed seed marks the run seeded, which is the only case the seed is shown
    -- during play (reference `game.lua:2163`, `UI_definitions.lua:2254`).
    self.seeded = self._pending_run_seed ~= nil
    self:seed_rng_stream(self._pending_run_seed or self:generate_run_seed())
    self._pending_run_seed = nil
    -- Reset the shop queue for the new named stream.
    self.shop_offer_queue = nil
    self._pause_prev_state = nil
    self._pause_save_error = nil
    self:reset_joker_pool_replacements()
    if self._pending_challenge_id == nil then
        self.challenge_id = nil
        self.challenge_rules = nil
        self.challenge_modifiers = nil
        self.challenge_banned_keys = nil
        self.challenge_joker_slots_disabled = nil
        self.inflation = 0
    end
end

--- Starting a run, cut into the chunks the screen wipe feeds one per frame.
---
--- The cut points are the blocking calls. Each atlas is an SD read, a t3x decode and a texture
--- upload; `initialize_run_loop` ends in `set_state`, which autosaves, which is a serialise and
--- a file write. Back to back inside one frame they overrun the music stream's buffer runway
--- and the audio drops out -- see the header in `screen_wipe.lua` for the arithmetic. A frame
--- apart, each chunk ends in a `present` and the audio pool thread gets scheduled.
---
--- Order matters beyond the split. The menu sheets go before the run sheets are loaded, and
--- `centers` goes before `cards_2` because the wipe draws its card back out of `centers` and
--- may as well have it early. The title screen deliberately avoids both run sheets (that is
--- what `title_ace.png` exists for) and the first deal needs them within a second of here, so
--- warming them under a cover the player is already watching beats a dropped frame mid-deal.
---@return function[]
function Game:run_start_steps()
    return {
        function() self:_run_start_leave_menu() end,
        function() self:warm_atlases({ "centers" }) end,
        function() self:warm_atlases({ "cards_2" }) end,
        function() self:_run_start_reset_objects() end,
        function()
            self:initialize_run_loop()
            -- Cleared here rather than by `start_challenge_run`: with the steps spread over
            -- frames, that caller returns long before `apply_pending_challenge` has read it.
            self._pending_challenge_id = nil
        end,
    }
end

--- The whole run start, with no cover and no frames in between. Kept for the headless tests,
--- which have neither; everything the player can press goes through `start_new_run_from_main_menu`.
function Game:start_run_from_main_menu()
    local steps = self:run_start_steps()
    for i = 1, #steps do steps[i]() end
end

function Game:start_challenge_run(challenge_id)
    if not (CHALLENGE_DEFS_BY_ID and CHALLENGE_DEFS_BY_ID[challenge_id]) then return false end
    self._pending_challenge_id = challenge_id
    self._pending_deck_id = "b_challenge"
    self._pending_stake_id = "stake_white"
    -- The pending id is cleared by the last run-start step, not here: the run is built behind
    -- the wipe over several frames and this returns before `apply_pending_challenge` reads it.
    self:start_new_run_from_main_menu()
    return true
end

function Game:handle_round_win_touch(x, y)
    -- Mid-slide the button is drawn away from its stored rect; a press must not cash out
    -- through the entrance animation (same gate the blind/shop slides use).
    if self:scene_transition_active() then return true end
    return RoundWinUI.handle_touch(self, x, y)
end

function Game:handle_shop_touch(x, y)
    return ShopUI.handle_touch(self, x, y)
end

-- ---------------------------------------------------------------------------
-- Scene transitions: the blind-select cards and the shop panel slide in from
-- the bottom of the screen with a little overshoot and slide back out on
-- exit. Shop contents stay hidden while the panel travels, then pop in with a
-- decaying rotation jiggle. Input for the affected screen is gated while a
-- slide is running.
-- ---------------------------------------------------------------------------

local SCENE_SLIDE_DURATION = 0.25
local MAX_TRANSITION_STEP = 1 / 30
local SHOP_POP_DURATION = 0.25
local BLIND_SLIDE_DIST = 240
local SHOP_SLIDE_DIST = 200

local function ease_out_back(t)
    local c1 = 1.2
    local u = t - 1
    return 1 + (c1 + 1) * u * u * u + c1 * u * u
end

local function ease_in_cubic(t)
    return t * t * t
end

local function slide_offset(slide, dist)
    if not slide then return 0 end
    local dy
    if slide.mode == "in" then
        dy = (1 - ease_out_back(slide.t)) * dist
    else
        dy = ease_in_cubic(slide.t) * dist
    end
    return math.floor(dy + 0.5)
end

function Game:begin_blind_select_intro()
    self._blind_slide = { mode = "in", t = 0 }
end

--- Slide offset for blind select. With a card index, the entrance staggers: each card runs
--- the same curve 0.06 s behind the last, so the three blinds arrive as dealt cards with
--- their own spring overshoot rather than one rigid sheet (the reference's panels are
--- independent Moveables, `reference/Balatro/game.lua:3252-3290`). The slide-out stays
--- uniform. Index nil returns 0 during a staggered entrance — callers then apply the
--- per-card offset themselves.
function Game:get_blind_slide_dy(card_index)
    local bs = self._blind_slide
    if not bs then return 0 end
    if bs.mode ~= "in" then
        -- Slide-out stays uniform and is applied once, by the panel-level (nil index)
        -- caller; indexed callers sit inside that translate already.
        if card_index then return 0 end
        return slide_offset(bs, BLIND_SLIDE_DIST)
    end
    if not card_index then return 0 end
    local stagger = 0.24 -- 0.06 s per card over the 0.25 s slide, normalized
    local t = (bs.t - stagger * (card_index - 1)) / (1 - stagger * 2)
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    return slide_offset({ mode = "in", t = t }, BLIND_SLIDE_DIST)
end

function Game:get_shop_slide_dy()
    return slide_offset(self._shop_slide, SHOP_SLIDE_DIST)
end

--- The round-eval and game-over panels enter on the same slide the shop and blind select
--- use (reference `game.lua:3296-3330` slides round eval up from below the room).
function Game:get_round_eval_slide_dy()
    return slide_offset(self._round_eval_slide, BLIND_SLIDE_DIST)
end

function Game:get_game_over_slide_dy()
    return slide_offset(self._game_over_slide, BLIND_SLIDE_DIST)
end

--- True while any scene is mid-slide; input for the bottom screen is
--- suppressed so a press cannot land on rects that have moved out from under it.
function Game:scene_transition_active()
    return self._blind_slide ~= nil or self._shop_slide ~= nil
        or self._round_eval_slide ~= nil or self._game_over_slide ~= nil
        -- The blind-defeat hold keeps STATE at SELECTING_HAND while it rings out, so without
        -- this the player could play another hand into an already-won blind.
        or self._blind_defeat ~= nil
end

--- Shop contents (offers, packs, vouchers, price tags) are invisible while
--- the panel slides in; they pop in once it lands.
function Game:shop_contents_hidden()
    local s = self._shop_slide
    return (s ~= nil) and s.mode == "in"
end

function Game:shop_nodes_visible()
    return self.STATE == self.STATES.SHOP and not self:shop_contents_hidden()
end

--- Hitboxes track VT.scale, which the pop-in drives up from zero, so items
--- only become clickable once they have settled at full size. Otherwise a tap
--- on a freshly-popped offer lands outside its shrunken rect and is dropped.
function Game:shop_nodes_interactive()
    return self.STATE == self.STATES.SHOP
        and self._shop_slide == nil
        and not self:shop_pop_in_active()
end

function Game:_clear_shop_settle_flags(list)
    if type(list) ~= "table" then return end
    for _, node in ipairs(list) do
        if node then node._shop_settling = nil end
    end
end

function Game:begin_shop_pop_in(...)
    for i = 1, select("#", ...) do
        local list = select(i, ...)
        if type(list) == "table" then
            for _, node in ipairs(list) do
                if node then
                    node._shop_pop_t = 0
                    -- A node dropped moments ago is still lerping home; the pop
                    -- re-pins it, so drop the settle flag or it would chase a
                    -- target that the slide-out is about to move 200px away.
                    node._shop_settling = nil
                    self._shop_pops_active = true
                end
            end
        end
    end
end

--- Scale multiplier + rotation for a shop node mid pop-in, or nil once settled.
function Game:shop_pop_in_transform(node)
    local t = node and node._shop_pop_t
    if not t or t >= 1 then return nil end
    local scale = math.max(0, ease_out_back(t))
    local slot = tonumber(node.shop_offer_slot or node.shop_booster_slot or node.shop_voucher_slot) or 1
    local rot = (1 - t) * 0.3 * math.sin(t * 4 * math.pi + slot * 1.7)
    return scale, rot
end

--- Clearing _shop_pop_t (rather than parking it at 1) keeps finished pops off
--- the per-frame path for the rest of the run.
local function tick_shop_pop_list(list, dt)
    if type(list) ~= "table" then return end
    local active = false
    for _, node in ipairs(list) do
        local t = node and node._shop_pop_t
        if t then
            t = t + dt / SHOP_POP_DURATION
            if t >= 1 then
                node._shop_pop_t = nil
            else
                node._shop_pop_t = t
                active = true
            end
        end
    end
    return active
end

function Game:shop_pop_in_active()
    return self._shop_pops_active == true
end

--- A slide commits real run state (starting a blind, advancing the round) a
--- quarter second after the press, so it must not survive leaving the screen
--- that started it: pausing out to the menu mid-slide would otherwise fire the
--- commit from the menu. Anything but the owning state cancels it outright.
function Game:_update_scene_transitions(dt)
    if self._deck_view_open then return end
    -- Advance by capped steps: an asset-load or GC hitch can hand us a dt
    -- larger than the whole animation, which would finish it in one frame and
    -- read as no animation at all. Better to run slightly long than to skip.
    if dt > MAX_TRANSITION_STEP then dt = MAX_TRANSITION_STEP end

    local bs = self._blind_slide
    if bs then
        if self.STATE ~= self.STATES.BLIND_SELECT then
            self._blind_slide = nil
        else
            bs.t = math.min(1, bs.t + dt / SCENE_SLIDE_DURATION)
            if bs.t >= 1 then
                if bs.mode == "in" then
                    -- Reference `game.lua:3283-3290` jiggles the room and fans the cards
                    -- when blind select lands; the port's slide previously ended silent.
                    self:shake(2)
                    if Sfx and Sfx.play then Sfx.play("cardFan2") end
                end
                self._blind_slide = nil
                if bs.mode == "out" then
                    self:_commit_selected_blind()
                end
            end
        end
    end

    local rs = self._round_eval_slide
    if rs then
        if self.STATE ~= self.STATES.ROUND_EVAL then
            self._round_eval_slide = nil
        else
            rs.t = math.min(1, rs.t + dt / SCENE_SLIDE_DURATION)
            if rs.t >= 1 then
                self._round_eval_slide = nil
                -- Reference `game.lua:3296-3330` jiggles the room and fans the cards
                -- once the round-eval panel settles.
                self:shake(2)
                if Sfx and Sfx.play then Sfx.play("cardFan2") end
                -- A beaten boss bursts in black and red (`blind.lua:282`) — the run's
                -- biggest beat gets a visual payoff on the chip that just broke.
                if self._last_completed_blind_was_boss then
                    self:shake(1)
                    RoundWinUI.emit_boss_defeat_burst(self)
                end
            end
        end
    end

    local gs = self._game_over_slide
    if gs then
        if self.STATE ~= self.STATES.GAME_OVER then
            self._game_over_slide = nil
        else
            gs.t = math.min(1, gs.t + dt / SCENE_SLIDE_DURATION)
            if gs.t >= 1 then
                self._game_over_slide = nil
            end
        end
    end

    local ss = self._shop_slide
    if ss then
        if self.STATE ~= self.STATES.SHOP then
            self._shop_slide = nil
        else
            ss.t = math.min(1, ss.t + dt / SCENE_SLIDE_DURATION)
            if ss.t >= 1 then
                self._shop_slide = nil
                if ss.mode == "in" then
                    -- Reference `game.lua:3089-3094`, including the room jiggle.
                    self:shake(2)
                    if Sfx and Sfx.play then Sfx.play("cardFan2") end
                    self:begin_shop_pop_in(self.shop_offer_nodes, self.shop_booster_nodes, self.shop_voucher_nodes)
                else
                    self:_commit_continue_from_shop()
                end
            end
        end
    end

    if self._shop_pops_active then
        local a = tick_shop_pop_list(self.shop_offer_nodes, dt)
        local b = tick_shop_pop_list(self.shop_booster_nodes, dt)
        local c = tick_shop_pop_list(self.shop_voucher_nodes, dt)
        self._shop_pops_active = (a or b or c) or nil
        -- The last animated draw may have left VT.scale just below its target.
        -- Force one final layout pass to pin every node at full size.
        if not self._shop_pops_active then
            self._shop_layout_dirty = true
        end
    end
end

--- Peak displacement in pixels at one unit of jiggle, before the accumulator is
--- clamped. This is a 320x240 panel: past a couple of pixels a shake stops reading as
--- impact and starts reading as a rendering glitch.
local SHAKE_PIXELS_PER_UNIT = 1.4
--- Ceiling on the accumulator, so a long scoring run cannot stack into a seizure.
local SHAKE_MAX = 2.2
--- Per-second decay, matching the reference's `jiggle*(1 - 5*dt)`.
local SHAKE_DECAY = 5
--- Below this the shake is sub-pixel anyway; snap to rest so the translate drops out.
local SHAKE_FLOOR = 0.05
--- Rattle rates in rad/s, straight from the reference's room translation
--- (`common_events.lua:1144`). Two mutually prime-ish frequencies so x and y never trace a
--- straight line. About 3 Hz - a wobble, not a buzz; the faster 39.9 in the reference drives
--- room *rotation*, which is a fraction of a degree and has nothing to port to here.
local SHAKE_FREQ_X = 19.913
local SHAKE_FREQ_Y = 21.913

--- Always-on room drift, from the reference's unconditional room translation
--- (`common_events.lua:1142-1145`, `0.015*sin(0.913*t)` in tile units). Rates are the
--- reference's; the amplitude is raised to a whole pixel because this screen rounds to
--- nearest-neighbour and 0.015 tiles would quantise to zero motion. The two rates are close
--- but not equal, so the drift traces a slow Lissajous instead of a diagonal.
local IDLE_DRIFT_PX = 1
local IDLE_DRIFT_RATE_X = 0.913
local IDLE_DRIFT_RATE_Y = 0.766

-- A discard leaves the hand on the TOTAL-clock queue, but the card spring itself is driven by
-- real time (`engine/moveable.lua`). Do not remove it after a scaled fixed duration: at 4x that
-- was 87.5 ms, cutting the visible flight off before the spring could settle. The reference
-- retains the card in its discard CardArea and lets that real-time motion finish
-- (`reference/functions/common_events.lua:386-423`).
local DISCARD_ARRIVE_EPS = 2.5
local DISCARD_MAX_FLIGHT_TIME = 1.2

--- Where discarded cards are thrown. The reference's discard pile is off the right edge of the
--- room and well above the deck: `G.discard.T.x` resolves to roughly 25 tiles across a 20-tile
--- room, and its card centre sits at 48% of the room's height against the hand's 89%
--- (`common_events.lua:26-27`). Anything past 320 here is off the right edge.
---
--- The height is not a straight 48% of 240. This port's cards are about 2.2x larger relative to
--- its screen than the reference's are to theirs (`Game:get_shake_offset`'s note), so the hand
--- already sits at 64% rather than 89% and there is far less room above it. These land the pile
--- clearly above the deck -- which is the thing that has to read, since both are off the same
--- edge -- without pushing it off the top.
local DISCARD_TARGET_X = 344
local DISCARD_TARGET_Y = 62
local DISCARD_SCATTER_X = 40
local DISCARD_SCATTER_Y = 20

local function discard_node_has_arrived(node)
    if not node or not node.VT or not node.T then return true end
    return math.abs((node.VT.x or 0) - (node.T.x or 0)) <= DISCARD_ARRIVE_EPS
        and math.abs((node.VT.y or 0) - (node.T.y or 0)) <= DISCARD_ARRIVE_EPS
end

--- Add to the screen shake. The playfield (bottom screen only) rattles for a moment
--- and decays back to rest; nothing else in the game reads this.
---
--- Units match the reference game's `G.ROOM.jiggle`, so its call sites port directly:
--- 0.7 per scoring trigger, 1 for a button, 2-3 for a blind reveal or a pack opening.
--- Calls stack, up to a clamp.
---
---     G:shake(0.7)
---
---@param amount number jiggle units to add; non-positive or non-numeric is ignored
--- Screenshake strength, 0-100 (`UI_definitions.lua:2305`).
---@return integer
function Game:get_screenshake_percent()
    local v = tonumber(self.SETTINGS and self.SETTINGS.SCREENSHAKE)
    if not v then return 100 end
    return math.max(0, math.min(100, math.floor(v)))
end

--- Reduced motion (`UI_definitions.lua:2308`). Stills the idle room drift as well as the
--- shake, which is the whole of this port's ambient board movement.
---@return boolean
function Game:reduced_motion_enabled()
    return (self.SETTINGS and self.SETTINGS.REDUCED_MOTION) == true
end

function Game:shake(amount)
    amount = tonumber(amount)
    if not amount or amount <= 0 then return end
    local j = (tonumber(self.jiggle) or 0) + amount
    if j > SHAKE_MAX then j = SHAKE_MAX end
    self.jiggle = j
end

--- Decay the accumulator. Runs before the PAUSED early-out so a game paused mid-shake
--- settles instead of freezing off-centre.
---@param dt number
function Game:update_shake(dt)
    -- The drift clock runs whether or not anything is shaking, and is never reset - the
    -- reference's room drift is a function of absolute time, so it must not restart each
    -- time a shake decays out or the board would visibly jump back to centre.
    self._room_drift_t = (tonumber(self._room_drift_t) or 0) + dt

    -- Unconditional, including while the sensor is off: `Tilt.update` springs a standing offset
    -- back to rest rather than dropping it, so switching tilt off mid-lean settles the board
    -- instead of snapping it.
    self._tilt_x, self._tilt_y = Tilt.update(dt)

    local j = tonumber(self.jiggle) or 0
    if j <= 0 then
        self._jiggle_t = 0
        return
    end
    self._jiggle_t = (self._jiggle_t or 0) + dt
    j = j - j * SHAKE_DECAY * dt
    self.jiggle = (j > SHAKE_FLOOR) and j or 0
end

--- Current shake offset in whole pixels. Rounded: the 3DS samples nearest-neighbour, so
--- a fractional translate would blur the whole playfield instead of moving it.
---@return number ox
---@return number oy
function Game:get_shake_offset()
    -- Reduced motion stills the board entirely: no shake, and no idle drift either, since
    -- the drift is the ambient motion the setting exists to stop.
    if self:reduced_motion_enabled() then return 0, 0 end

    local t = self._jiggle_t or 0
    local ox, oy = 0, 0

    local shake_scale = self:get_screenshake_percent() / 100
    local j = (tonumber(self.jiggle) or 0) * shake_scale
    if j > 0 then
        local amp = j * SHAKE_PIXELS_PER_UNIT
        ox = amp * math.sin(SHAKE_FREQ_X * t)
        oy = amp * math.sin(SHAKE_FREQ_Y * t)
    end

    -- Idle drift. The reference runs this every frame regardless of jiggle
    -- (`common_events.lua:1142-1145`): a slow sine on both axes that never stops. Without it
    -- the playfield is pixel-frozen between events, which is most of why a resting board reads
    -- as a screenshot rather than a game. Amplitude is deliberately above 1 px, because the
    -- rounding below would otherwise quantise the whole drift away to nothing.
    local dt_clock = tonumber(self._room_drift_t) or 0
    ox = ox + IDLE_DRIFT_PX * math.sin(IDLE_DRIFT_RATE_X * dt_clock)
    oy = oy + IDLE_DRIFT_PX * math.sin(IDLE_DRIFT_RATE_Y * dt_clock)

    local rx = (ox >= 0) and math.floor(ox + 0.5) or -math.floor(-ox + 0.5)
    local ry = (oy >= 0) and math.floor(oy + 0.5) or -math.floor(-oy + 0.5)

    -- The tilt is summed as whole pixels rather than folded in above it: it carries its own
    -- rounding, with hysteresis, because it is a slow value that would otherwise sit on a .5
    -- boundary and flicker. The shake is a fast oscillation and wants the plain rounding it has
    -- always had.
    if self:tilt_enabled() then
        rx = rx + (tonumber(self._tilt_x) or 0)
        ry = ry + (tonumber(self._tilt_y) or 0)
    end

    return rx, ry
end

--- Multiplier on the logic clock for this frame: the game speed setting, plus the original's
--- self-accelerating scoring ramp (`game.lua:2490`).
---
--- A hand with a wall of jokers on it can take half a minute to resolve at the beat the
--- original scores at, so it does not hold that beat: once a scoring sequence has been running
--- for ten seconds the whole queue starts speeding up, and keeps speeding up the longer it
--- goes. The accumulator resets the moment scoring ends, so an ordinary hand never sees it.
--- Without this the reference cadence is correct for one hand and unbearable for a built deck.
---
--- Motion and juice do not read this - see `Moveable:update`.
---@param dt number real frame time
---@return number
function Game:speed_factor(dt)
    -- Reference `game.lua:2495`: game speed is scoped to an active, unpaused run. Menus,
    -- pause overlays and screen wipes all advance at 1x regardless of the saved setting.
    if self.STATE == self.STATES.PAUSED then
        self.ACC = 0
        -- Reference zeroes `dt` while paused before advancing TIMERS.TOTAL (`game.lua:2485`).
        return 0
    end
    if self.STAGE ~= self.STAGES.RUN or self.screenwipe then
        self.ACC = 0
        return 1
    end

    local speed = tonumber(self.SETTINGS and self.SETTINGS.GAMESPEED) or 1
    if speed <= 0 then speed = 1 end

    if self:is_hand_scoring_active() then
        -- 0.2 per second, so the ramp starts biting at 10 s and is at 3x by 20 s.
        self.ACC = math.min((tonumber(self.ACC) or 0) + dt * 0.2 * speed, 16)
    else
        self.ACC = 0
    end

    return speed + math.max(0, self.ACC - 2)
end

--- The reference's card cadences top out at four game-speed on a large screen, where a 25 ms
--- stagger between cards still reads because the cards are small relative to the playfield.
--- Here they are 2.2x larger relative to the 320 px screen (see `engine/moveable.lua:74`), and
--- a sub-frame stagger collapses into one visual clump. Port decision: the clocks that pace
--- per-card beats (deal queue, play release, discard sweep) scale with game speed but never
--- run faster than this multiple of real time, so 4x keeps a legible ripple. Motion itself is
--- already real-time and is untouched.
local CARD_BEAT_MAX_SPEED = 2

--- Clamp a scaled-clock step for card cadence timers to `CARD_BEAT_MAX_SPEED` x real time.
---@param dt number game-speed-scaled frame time
---@return number
function Game:card_beat_dt(dt)
    local real = tonumber(self.real_dt)
    if not real then return dt end
    return math.min(dt, real * CARD_BEAT_MAX_SPEED)
end

function Game:update(dt, real_dt)
    real_dt = tonumber(real_dt) or tonumber(self.real_dt) or dt
    -- Ticks before the PAUSED early-out so per-frame caches keyed on it stay valid while
    -- paused rather than recomputing every frame behind the pause menu.
    self._frame_id = (self._frame_id or 0) + 1
    self:update_shake(real_dt)
    -- Ahead of the PAUSED early-out, not behind it: a wipe that could not advance would never
    -- lift. While it holds the frame it is running the run build a chunk at a time and nothing
    -- underneath should animate or read half-built state -- the reference holds
    -- `G.SETTINGS.paused` across the same span (`button_callbacks.lua:2959`).
    if ScreenWipe.update(self, real_dt) then
        return
    end
    if self.STATE == self.STATES.PAUSED then
        return
    end
    if self.STATE ~= self.STATES.ROUND_EVAL then
        Particles.update(real_dt)
    end
    -- These are direct motion/input/maintenance paths, corresponding to reference updates
    -- that consume `real_dt` rather than the game-speed-scaled TOTAL clock.
    self:_update_scene_transitions(real_dt)
    self:_update_blind_defeat(real_dt)
    self:_update_card_ripple(real_dt)
    self:_update_edition_reveals(real_dt)
    self:_update_boss_announce_sting(real_dt)
    -- The level-up ladder is an event-queue sequence in the reference, and events run off the
    -- `TOTAL` timer by default (`engine/event.lua:22`), so it scales with the game-speed
    -- setting like every other beat of a run. It was running on wall time here, which left a
    -- Planet taking three seconds at 4x while the rest of the run flew past.
    self:_update_hand_levelup(dt)
    -- Flight is motion (real time); the hold before the card comes apart is sequencing, so it
    -- rides the same scaled clock as the ladder it is waiting on.
    self:_update_consumable_flight(real_dt, dt)
    self:_update_dissolving_nodes(real_dt)
    self:_update_materializing_nodes(real_dt)
    -- Once per frame, not per screen: `love.draw` runs per screen and the tooltip would open at
    -- double speed if the clock were advanced from the draw path.
    TooltipDraw.update(real_dt)
    self:_update_booster_opening(dt)
    self:_update_booster_close(real_dt)
    if self.sync_shoulder_input then
        self:sync_shoulder_input()
    end
    if self.update_sweep_seed then
        self:update_sweep_seed()
    end
    if self.update_dpad_horizontal_repeat then
        self:update_dpad_horizontal_repeat(real_dt)
    end
    if self.STATE == self.STATES.MENU and MainMenuUI.update then
        MainMenuUI.update(self, real_dt)
    end
    if self._deck_view_open then
        if DeckViewUI.update then
            DeckViewUI.update(self, real_dt)
        end
        for _, node in ipairs(self._deck_view_nodes or {}) do
            if node and node.update then
                node:update(dt)
            end
        end
        self:check_collisions(real_dt)
        return
    end
    self:_update_joker_emit_queue(dt)
    -- The Cash Out panel is built only once the staggered `on_round_end` batch has drained.
    if self._pending_round_win_eval and not self:joker_emit_busy() then
        local pending = self._pending_round_win_eval
        self._pending_round_win_eval = nil
        self:_finish_round_win_eval(pending.ctx, pending.hands_left)
    end
    if self._nope_sfx_timer then
        self._nope_sfx_timer = self._nope_sfx_timer - dt
        if self._nope_sfx_timer <= 0 then
            self._nope_sfx_timer = nil
            -- Reference `card.lua:1513-1515`.
            if Sfx and Sfx.play then Sfx.play("tarot2", 0.76, 0.4) end
        end
    end
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
    self:check_collisions(real_dt)

    -- Determine whether the joker slide animation is still running.
    -- While sliding, guides should move with jokers; afterward, guides lock to slot geometry.
    if self.jokers_sliding == true then
        self.jokers_slide_time_left = (self.jokers_slide_time_left or 0) - real_dt
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

    if self.consumables_sliding == true then
        self.consumables_slide_time_left = (self.consumables_slide_time_left or 0) - real_dt
        local all_snapped = true
        if self.consumable_nodes then
            for _, c in ipairs(self.consumable_nodes) do
                if c and c.VT and c.T then
                    local dx = math.abs((c.VT.x or 0) - (c.T.x or 0))
                    local dy = math.abs((c.VT.y or 0) - (c.T.y or 0))
                    local ds = math.abs((c.VT.scale or 0) - (c.T.scale or 0))
                    if dx > 0.6 or dy > 0.6 or ds > 0.02 then
                        all_snapped = false
                        break
                    end
                end
            end
        end
        if all_snapped == true or (self.consumables_slide_time_left or 0) <= 0 then
            self.consumables_sliding = false
            self.consumables_slide_time_left = 0
        end
    end

    local removed_nodes = 0
    -- Per-card beat, not raw scaled time: see `card_beat_dt`.
    self.discard_timer = self.discard_timer + self:card_beat_dt(dt)
    for i = #self.pending_discard, 1, -1 do
        local entry = self.pending_discard[i]
        -- Send the card on its way when its beat comes round; `Hand` staggers these so a
        -- discarded hand peels off rather than vanishing all at once.
        if not entry.flew and self.discard_timer >= (entry.fly_after or 0) then
            entry.flew = true
            entry.flight_time = 0
            if entry.target then
                -- An un-deal flight: back to the deck's off-screen origin, no scatter — the
                -- cards funnel into one pile the way they came out of it.
                entry.node.T.x = entry.target.x
                entry.node.T.y = entry.target.y
                entry.node.T.r = entry.target.r or 0
            else
                -- Scatter the flight targets and give each card a toss rotation so a discarded
                -- hand reads as thrown at a pile, not vacuumed to one point. The scatter is
                -- the reference's own: its discard area places each card at `card.discard_pos`,
                -- a per-card offset and rotation within the area (`cardarea.lua:425-434`).
                --
                -- The direction is the reference's too. Its discard pile sits off the right of
                -- the room a little above centre -- `G.discard.T.x` works out to about 25 tiles
                -- against a 20-tile room, at `T.y = 4.2` of 11.5 (`common_events.lua:26-27`).
                -- The port was throwing them off the top left, which is the opposite corner.
                local jitter = (love.math and love.math.random and love.math.random()) or 0.5
                entry.node.T.x = DISCARD_TARGET_X + jitter * DISCARD_SCATTER_X
                entry.node.T.y = DISCARD_TARGET_Y + (1 - jitter) * DISCARD_SCATTER_Y
                entry.node.T.r = (jitter - 0.5) * 0.8
            end
            -- The cue every card entering an area gets in the reference, pitched by its place
            -- in the sweep (`common_events.lua:416`).
            if Sfx and Sfx.play then
                Sfx.play("card1", 0.85 + 0.2 * (entry.percent or 0.5), 0.6)
            end
        end
        if entry.flew then
            entry.flight_time = (entry.flight_time or 0) + real_dt
        end
        if entry.flew and (discard_node_has_arrived(entry.node)
            or (entry.flight_time or 0) >= DISCARD_MAX_FLIGHT_TIME) then
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
            -- A full collect here walked the ~2.3 MB live heap in one frame, which
            -- landed as a visible hitch right as a discard animation finished. Spread
            -- the same reclamation across the next frames instead: 12 frames of
            -- step(160) covers well over a full cycle of this heap, without the spike.
            self._gc_boost_frames = 12
        end
    end

    -- Small periodic incremental GC step to smooth frame spikes on 3DS, raised to a
    -- burst while a discard wave's garbage is being worked off.
    if (self._gc_boost_frames or 0) > 0 then
        self._gc_boost_frames = self._gc_boost_frames - 1
        collectgarbage("step", 160)
    else
        self._gc_timer = self._gc_timer + real_dt
        if self._gc_timer >= 0.2 then
            self._gc_timer = 0
            collectgarbage("step", 96)
        end
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

--- Topmost owned consumable under (x, y), or nil. Same reason as `get_owned_joker_at`: the
--- pack choice cards and the hand sit in `self.nodes` above the owned row, so `get_node_at`
--- would hand back whatever is underneath the pulled-down panel.
function Game:get_owned_consumable_at(x, y)
    if not self.consumable_nodes then return nil end
    for i = #self.consumable_nodes, 1, -1 do
        local c = self.consumable_nodes[i]
        if c and c.states and c.states.click.can and self:point_in_rect(x, y, c) then
            return c
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

--- Top-screen inventory regions: jokers 2/3 width, consumables 1/3, small gap between.
--- Screen geometry is fixed, so these are built once and handed out by reference. Both are
--- read on several per-frame layout paths, and rebuilding a table of five constants on each
--- call was pure garbage. No caller writes to them.
local TOP_INVENTORY_DIMS = (function()
    local w, gap = 400, 2
    local joker_panel_w = math.floor(w * (2 / 3))
    return {
        top_screen_w = w,
        panel_gap = gap,
        joker_panel_w = joker_panel_w,
        consumable_panel_w = w - joker_panel_w - gap,
        consumable_panel_x = joker_panel_w + gap,
    }
end)()

local BOTTOM_INVENTORY_DIMS = (function()
    local w, gap = 320, 2
    local joker_panel_w = math.floor(w * (2 / 3))
    return {
        bottom_screen_w = w,
        panel_gap = gap,
        joker_panel_w = joker_panel_w,
        consumable_panel_w = w - joker_panel_w - gap,
        consumable_panel_x = joker_panel_w + gap,
    }
end)()

function Game:get_top_inventory_dims()
    return TOP_INVENTORY_DIMS
end

--- Bottom-screen inventory regions: jokers 2/3 width, consumables 1/3, small gap between.
function Game:get_bottom_inventory_dims()
    return BOTTOM_INVENTORY_DIMS
end

--- Padding between a pulled-down row's cards and the edge of the tray behind them.
--- Matches `TopUI:draw` so the tray a row sits on is the same shape on either screen.
local BOTTOM_TRAY_PAD = 3

--- Screen rect of the tray behind a pulled-down inventory row, or nil when that row is not
--- on the bottom screen.
---
--- Unlike the top screen, where the tray is the whole panel whether or not anything is in it,
--- this one is only as wide as the row it holds. The bottom screen is the playfield: a
--- full-width band would cover the shop's continue and reroll buttons, and a row pulled down
--- is meant to sit over the screen, not replace the top half of it.
---
--- The y is the row's resting y, except while the row is sliding in, when it follows the
--- highest card so the tray arrives from off-screen underneath them rather than popping in at
--- the destination. A card being dragged is excluded: it leaves the row, and the tray must not
--- chase it down the screen.
---
--- Nil when the row's cards are hidden even though the row is nominally down - `Game:draw`
--- hides the consumables outright on the cash-out screen, and an empty tray there would be a
--- slab over the payout with nothing in it.
---@param kind string "jokers" | "consumables"
function Game:get_bottom_panel_rect(kind)
    local dims = self:get_bottom_inventory_dims()
    local nodes, x, w, h, y, sliding
    if kind == "jokers" then
        if self.jokers_on_bottom ~= true then return nil end
        nodes = self.jokers
        local s = self.joker_slot_scale_bottom or 1
        local card_w = (self.joker_slot_w or 70) * s
        local row_w = (self.consumables_on_bottom == true) and dims.joker_panel_w or dims.bottom_screen_w
        local span, start_x = select(2, self:_compute_fanned_joker_row(
            #(self.jokers or {}), row_w, card_w, (self.joker_slot_gap or 8) * s, 8))
        x = self._joker_row_start_x_bottom or self.joker_slot_start_x_bottom or start_x
        w = tonumber(self.joker_row_span_bottom) or span
        h = (self.joker_slot_h or 94) * s
        y = self.joker_slot_y_bottom or BOTTOM_INVENTORY_Y
        sliding = self.jokers_sliding == true
    elseif kind == "consumables" then
        if self.consumables_on_bottom ~= true then return nil end
        nodes = self.consumable_nodes
        local s = self.consumable_slot_scale_bottom or 1
        local card_w = (self.consumable_slot_w or 72) * s
        local row_w = (self.jokers_on_bottom == true) and dims.consumable_panel_w or dims.bottom_screen_w
        local span, rel_start = select(2, self:_compute_fanned_joker_row(
            #(self.consumables or {}), row_w, card_w, (self.joker_slot_gap or 8) * s, 8))
        local fallback_x = (self.jokers_on_bottom == true)
            and (dims.consumable_panel_x + rel_start) or rel_start
        x = self.consumable_slot_start_x_bottom or fallback_x
        w = tonumber(self.consumable_row_span_bottom) or span
        h = (self.consumable_slot_h or 95) * s
        y = self.consumable_slot_y_bottom or self.joker_slot_y_bottom or BOTTOM_INVENTORY_Y
        sliding = self.consumables_sliding == true
    else
        return nil
    end
    if not nodes or #nodes == 0 then return nil end

    local any_visible = false
    for _, node in ipairs(nodes) do
        if node and node.states and node.states.visible ~= false then
            any_visible = true
            if sliding and node ~= self.dragging then
                local ny = node.VT and node.VT.y
                if ny and ny < y then y = ny end
            end
        end
    end
    if not any_visible then return nil end

    return {
        x = x - BOTTOM_TRAY_PAD,
        y = y - BOTTOM_TRAY_PAD,
        w = w + BOTTOM_TRAY_PAD * 2,
        h = h + BOTTOM_TRAY_PAD * 2,
    }
end

--- Draw the trays behind whichever inventory rows are pulled down.
---
--- Same tray `TopUI` draws behind the rows on the readout, so a row that is pulled down keeps
--- the outline it had up there and stays visually separate from the playfield it now covers.
--- No stereo depth: the bottom screen is 2D.
function Game:draw_bottom_inventory_trays()
    if not (TopUI and TopUI.draw_inventory_tray) then return end
    local r = self:get_bottom_panel_rect("jokers")
    if r then
        TopUI:draw_inventory_tray(r.x, r.y, r.w, r.h, true, 0)
    end
    r = self:get_bottom_panel_rect("consumables")
    if r then
        TopUI:draw_inventory_tray(r.x, r.y, r.w, r.h, true, 0)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function Game:_snap_consumables_vt()
    if self.consumables_sliding == true then return end
    if not self.consumable_nodes then return end
    for _, c in ipairs(self.consumable_nodes) do
        if c and c.VT and c.T then
            c.VT.x = c.T.x
            c.VT.y = c.T.y
            c.VT.r = c.T.r or 0
            c.VT.scale = c.T.scale
        end
    end
end

--- Rough top/bottom start positions before `_apply_joker_layout` (uses owned count).
function Game:recompute_joker_slot_layout()
    self.joker_slot_w = self.joker_slot_w or 70
    self.joker_slot_h = self.joker_slot_h or 94
    self.joker_slot_gap = self.joker_slot_gap or 8
    self.joker_slot_y_top = self.joker_slot_y_top or 124
    self.joker_slot_y_bottom = self.joker_slot_y_bottom or BOTTOM_INVENTORY_Y

    local bot_dims = self:get_bottom_inventory_dims()
    local dims = self:get_top_inventory_dims()
    local n = #(self.jokers or {})
    local eff_n = math.max(n, 1)
    local card_w = self.joker_slot_w or 70
    local gap = self.joker_slot_gap or 8

    local _, _, top_x = self:_compute_fanned_joker_row(eff_n, dims.joker_panel_w, card_w, gap, 4)
    self.joker_slot_start_x = top_x

    self.joker_slot_scale_bottom = 1
    local s = self.joker_slot_scale_bottom
    local eff_w = card_w * s
    local eff_gap = gap * s
    local bot_w = (self.consumables_on_bottom == true) and bot_dims.joker_panel_w or bot_dims.bottom_screen_w
    local _, _, bot_x = self:_compute_fanned_joker_row(eff_n, bot_w, eff_w, eff_gap, 8)
    self.joker_slot_start_x_bottom = bot_x
end

--- Rough top/bottom start positions before `_apply_consumable_layout`.
function Game:recompute_consumable_slot_layout()
    self._consumable_layout_dirty = true
    self.consumable_slot_w = self.consumable_slot_w or 72
    self.consumable_slot_h = self.consumable_slot_h or 95
    self.consumable_slot_y_bottom = self.consumable_slot_y_bottom or BOTTOM_INVENTORY_Y

    local bot_dims = self:get_bottom_inventory_dims()
    local dims = self:get_top_inventory_dims()
    local n = #(self.consumables or {})
    if n <= 0 then return end
    local card_w = self.consumable_slot_w or 72
    local gap = self.joker_slot_gap or 8

    local _, span_top, rel_top = self:_compute_fanned_joker_row(n, dims.consumable_panel_w, card_w, gap, 4)
    self.consumable_slot_start_x = dims.consumable_panel_x + rel_top
    self.consumable_row_span_top = span_top

    local bot_w = (self.jokers_on_bottom == true) and bot_dims.consumable_panel_w or bot_dims.bottom_screen_w
    local s = self.consumable_slot_scale_bottom or 1
    local eff_w = card_w * s
    local eff_gap = gap * s
    local _, span_bot, rel_bot = self:_compute_fanned_joker_row(n, bot_w, eff_w, eff_gap, 8)
    self.consumable_slot_start_x_bottom = (self.jokers_on_bottom == true)
        and (bot_dims.consumable_panel_x + rel_bot) or rel_bot
    self.consumable_row_span_bottom = span_bot
end

function Game:joker_base_capacity() 
    if self.challenge_joker_slots_disabled == true then return 0 end
    local base = (self.challenge_rules and tonumber(self.challenge_rules.joker_slots)) or 5
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
    self.consumables_on_bottom = false
    self.jokers_sliding = false
    self.jokers_slide_time_left = 0

    self.consumables_sliding = false
    self.consumables_slide_time_left = 0
    self.consumable_slot_w = 72
    self.consumable_slot_h = 95
    self.consumable_slot_y_bottom = BOTTOM_INVENTORY_Y
    self.consumable_slot_scale_bottom = 1

    self.joker_slot_w, self.joker_slot_h = 70, 94
    self.joker_slot_gap = 8
    self.joker_slot_y_top = 124 - 10
    self.joker_slot_y_bottom = BOTTOM_INVENTORY_Y

    self:recompute_joker_slot_layout()
    self:recompute_consumable_slot_layout()
    self:sync_jokers_interactivity()
    self:sync_consumables_interactivity()

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
        return { random_suit = suits[self:random("anc", 1, #suits)] }
    end

    if def_id == "j_castle" then
        local deck = self.deck
        if deck and deck.random_card then
            local card = deck:random_card()
            if card and card.suit then
                return { random_suit = card.suit }
            end
        end
        return { random_suit = suits[self:random("cas", 1, #suits)] }
    end

    if def_id == "j_mail" then
        -- Match Castle and Idol: choose from the run's actual deck rather than an
        -- evenly distributed rank (reference/Balatro/functions/common_events.lua:2288-2300).
        local deck = self.deck
        if deck and deck.random_card then
            local card = deck:random_card()
            if card and card.rank then
                return { random_rank = card.rank }
            end
        end
        return { random_rank = self:random("mail", 2, 14) }
    end

    if def_id == "j_idol" then
        local deck = self.deck
        if deck and deck.random_card then
            local card = deck:random_card()
            if card then
                return { random_rank = card.rank, random_suit = card.suit }
            end
        end
        return { random_rank = self:random("idol", 2, 14), random_suit = suits[self:random("idol", 1, #suits)] }
    end

    if def_id == "j_todo_list" then
        local handlist = self.handlist or {}
        if #handlist == 0 then return nil end
        local found = false
        local hand_name = nil
        while not found do
            local pos = self:random("to_do", 1, #handlist)
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
--- `arrive_from` is a node this one is taking the place of - the shop shelf card behind a
--- purchase. The reference does not materialise a bought card: `buy_from_shop` moves the
--- existing card out of the shop CardArea into `G.jokers` and lets the spring carry it to its
--- slot (`button_callbacks.lua:2414-2437`), so what the player sees is one card travelling,
--- not one vanishing and another burning in. Passing the old node here reproduces that - the
--- new one starts where the old one sat and springs across - and suppresses the materialise.
--- A card that genuinely comes into being passes nothing and burns in as before.
function Game:add_joker_by_def(def_id, create_params, arrive_from)
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
    if self.challenge_modifiers and self.challenge_modifiers.all_eternal == true
        and def.eternal_compat ~= false then
        merged.eternal = true
        merged.perishable = nil
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
    self:discover_edition(merged.edition)
    self:check_unlock("modify_jokers")

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

    if arrive_from and arrive_from.VT and j.VT then
        j.VT.x, j.VT.y = arrive_from.VT.x, arrive_from.VT.y
        j.VT.scale = arrive_from.VT.scale or j.VT.scale
        j.VT.r = arrive_from.VT.r or j.VT.r
    else
        -- After the snap above, for the same reason as `add_consumable`: the burst has to
        -- converge on the slot the joker took, not on the (0, 0) it was constructed at.
        self:begin_materializing_node(j)
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

    local top_dims = self:get_top_inventory_dims()
    local bot_dims = self:get_bottom_inventory_dims()
    local slot_w = self.joker_slot_w or 70
    local slot_h = self.joker_slot_h or 94
    local gap = self.joker_slot_gap or 8

    if self.jokers_on_bottom == true then
        local n = #self.jokers
        if n <= 0 then return end

        local s = self.joker_slot_scale_bottom or 1
        local y = self.joker_slot_y_bottom or BOTTOM_INVENTORY_Y
        local eff_w = slot_w * s
        local eff_gap = gap * s
        local panel_w = (self.consumables_on_bottom == true) and bot_dims.joker_panel_w or bot_dims.bottom_screen_w
        local step, total_span, start_x =
            self:_compute_fanned_joker_row(n, panel_w, eff_w, eff_gap, 8)

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
        local step, total_span, start_x = self:_compute_fanned_joker_row(n, top_dims.joker_panel_w, slot_w, gap, 4)

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

function Game:_apply_consumable_layout()
    -- Cleared up front rather than at the end so the empty-list early-out also
    -- counts as "applied" — there is nothing to lay out until a mutation re-dirties.
    self._consumable_layout_dirty = false
    local list = self.consumables or {}
    local nodes = self.consumable_nodes or {}
    if #list == 0 then return end

    local top_dims = self:get_top_inventory_dims()
    local bot_dims = self:get_bottom_inventory_dims()
    local card_w = self.consumable_slot_w or 72
    local card_h = self.consumable_slot_h or 95
    local gap = self.joker_slot_gap or 8
    local n = #list

    if self.consumables_on_bottom == true then
        local s = self.consumable_slot_scale_bottom or 1
        local y = self.consumable_slot_y_bottom or self.joker_slot_y_bottom or BOTTOM_INVENTORY_Y
        local eff_w = card_w * s
        local eff_h = card_h * s
        local eff_gap = gap * s
        local panel_w = (self.jokers_on_bottom == true) and bot_dims.consumable_panel_w or bot_dims.bottom_screen_w
        local step, total_span, rel_start =
            self:_compute_fanned_joker_row(n, panel_w, eff_w, eff_gap, 8)
        local start_x = (self.jokers_on_bottom == true)
            and (bot_dims.consumable_panel_x + rel_start) or rel_start

        self._consumable_row_step = step
        self._consumable_row_span = total_span
        self._consumable_row_start_x = start_x
        self._consumable_row_card_w = eff_w
        self.consumable_row_span_bottom = total_span
        self.consumable_slot_start_x_bottom = start_x

        local delta_x = (card_w * s * (1 - s)) / 2
        local delta_y = (card_h * s * (1 - s)) / 2

        for i = 1, n do
            local node = nodes[i]
            local desired_left = start_x + (i - 1) * step
            local x = desired_left - delta_x
            local y_pos = y - delta_y
            if node then
                node.T.x = x
                node.T.y = y_pos
                node.T.r = 0
                node.T.scale = s
            end
            set_rect(self._consumable_rects, i, x, y_pos, eff_w, eff_h)
        end
    else
        local s = 1
        local y = self.joker_slot_y_top or 124
        local step, total_span, rel_start =
            self:_compute_fanned_joker_row(n, top_dims.consumable_panel_w, card_w, gap, 4)
        local start_x = top_dims.consumable_panel_x + rel_start

        self._consumable_row_step = step
        self._consumable_row_span = total_span
        self._consumable_row_start_x = start_x
        self._consumable_row_card_w = card_w
        self.consumable_row_span_top = total_span
        self.consumable_slot_start_x = start_x

        for i = 1, n do
            local node = nodes[i]
            local x = start_x + (i - 1) * step
            if node then
                node.T.x = x
                node.T.y = y
                node.T.scale = s
            end
            set_rect(self._consumable_rects, i, x, y, card_w, card_h)
        end
    end
end

function Game:sync_consumables_interactivity()
    local on_bottom = self.consumables_on_bottom == true
    if not self.consumable_nodes then return end
    for _, c in ipairs(self.consumable_nodes) do
        if c and c.states then
            c.states.click.can = on_bottom
            c.states.drag.can = on_bottom
            c.states.visible = on_bottom
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

--- Extra scoring passes from Red Seal (once) and each joker's `query_retrigger` (Balatro-style additive
--- retriggers), one entry per extra pass so callers can shake whatever caused it: the joker, or `false`
--- for the card's own Red Seal.
--- `retrigger_ctx` should include `card_node` (or `retrigger_card`), `played_cards` when scoring the play area, and `held` is set from the `held` argument.
--- Appends to `out` in place rather than allocating, since scoring walks every card in the hand.
---@param held boolean
---@param retrigger_ctx table|nil
---@param out table
---@return table out
function Game:collect_retrigger_sources(held, retrigger_ctx, out)
    if type(retrigger_ctx) ~= "table" then return out end
    retrigger_ctx.held = not not held
    local card = retrigger_ctx.card_node or retrigger_ctx.retrigger_card
    if card and card.seal == "red" then
        out[#out + 1] = false
    end

    -- Slot order already drops the joker Crimson Heart disabled this round.
    for _, j in ipairs(self:_collect_jokers_in_slot_order()) do
        if j.query_retrigger then
            local n = math.floor(tonumber(j:query_retrigger(retrigger_ctx)) or 0)
            for _ = 1, n do
                out[#out + 1] = j
            end
        end
    end
    return out
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
    local scratch = {}
    for _, node in ipairs(self.hand.card_nodes) do
        if node and node.emit_hand_event then
            local applied = node:emit_hand_event(event_name, ctx) and true or false
            -- End-of-round held effects retrigger exactly like held scoring does: the
            -- reference builds a `reps` list per card from the Red Seal and from every
            -- joker (`state_events.lua:171-207`), so a Gold card with a Red Seal pays twice
            -- and Mime doubles the whole hand's end-of-round income. Only a card that
            -- actually did something is repeated (`state_events.lua:193`).
            if event_name == "on_round_end" and applied then
                for i = #scratch, 1, -1 do scratch[i] = nil end
                local retrigger_ctx = {
                    card_node = node,
                    retrigger_card = node,
                    end_of_round = true,
                    held_first_pass_effect_applied = true,
                }
                for _, source in ipairs(self:collect_retrigger_sources(true, retrigger_ctx, scratch)) do
                    node:emit_hand_event(event_name, ctx)
                    -- `false` marks the card's own Red Seal; a joker shakes for its own pass.
                    if source and source.juice_up then source:juice_up() end
                end
            end
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
            if j and j.apply_edition_on_hand_scored then
                j:apply_edition_on_hand_scored(ctx, true)
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
    -- Adding cards can complete a suit or enhancement tally (`cardarea.lua:63`).
    self:check_unlock("modify_deck")
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
    -- Starts at zero, not -1: the reference only takes a hand that has actually been played
    -- (`card.lua:1739`), so with a fresh run Telescope forces nothing and the pack draws
    -- normally. Counting from -1 forced the first hand in the list, whose planet may still be
    -- softlocked.
    local best_i, best_c = nil, 0
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
            -- Each matching held Planet is independently scored (reference card.lua:1630-1638).
            ctx.mult = (tonumber(ctx.mult) or 1) * 1.5
            self:_sync_joker_ctx(ctx)
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
        local edition_triggered = false
        if q.event_name == "on_hand_scored" and j.apply_edition_on_hand_scored then
            local edition = j.normalize_edition and j.normalize_edition(j.edition) or j.edition
            edition_triggered = edition ~= nil and edition ~= "base" and edition ~= "negative"
            j:apply_edition_on_hand_scored(q.ctx)
        end
        self:_sync_joker_ctx(q.ctx)
        if j.apply_effect then
            if q.pre_matched == true or (j.matches_trigger and q.event_name and j:matches_trigger(q.event_name, q.ctx)) then
                j:apply_effect(q.ctx)
                did_trigger = edition_triggered
                    or q.ctx._joker_effect_applied_now == true
                    or q.ctx._joker_effect_created_item_now == true
            end
        end
        self:_sync_joker_ctx(q.ctx)
        if q.event_name == "on_hand_scored" and j.apply_edition_on_hand_scored then
            local edition = j.normalize_edition and j.normalize_edition(j.edition) or j.edition
            if edition == "polychrome" then edition_triggered = true end
            j:apply_edition_on_hand_scored(q.ctx, true)
            self:_sync_joker_ctx(q.ctx)
        end
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

    -- A triggering joker owns this beat. Only scan ahead in the same frame when the joker we
    -- just inspected was a no-op; the old unconditional scan applied the first *two* scoring
    -- jokers together, then staggered only the third onward. Reference status events are
    -- blocking, so one actual trigger is announced per beat (`common_events.lua:859-879`).
    while not had_trigger and self._joker_emit_queue
        and self._joker_emit_next <= #self._joker_emit_queue.list do
        local next_did_trigger = self:_apply_one_joker_emit()
        if next_did_trigger then
            had_trigger = true
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
    local interval = tonumber(self.JOKER_EMIT_INTERVAL) or 0.9375
    if self._joker_emit_timer < interval then
        return
    end

    self._joker_emit_timer = self._joker_emit_timer - interval
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

--- After beating a blind: return all cards to the deck and reshuffle; hand stays empty until
--- the next blind starts. Visually the hand un-deals — each node flies back to the deck's
--- off-screen origin on the discard beat clock during the defeat hold, the way the reference
--- peels the hand off through its `draw_card` queue at round end (`state_events.lua:237-250`).
--- In-flight discard nodes are carried across the recycle instead of being popped, so a hand
--- played into the win finishes its throw.
function Game:recycle_full_deck_after_blind_win()
    local flights = {}
    for _, entry in ipairs(self.pending_discard or {}) do
        flights[#flights + 1] = entry
    end
    self.pending_discard = {}
    if self.hand and self.hand.take_undeal_flights then
        for _, entry in ipairs(self.hand:take_undeal_flights()) do
            flights[#flights + 1] = entry
        end
    end
    self:recycle_full_deck()
    self.pending_discard = flights
end

function Game:prepare_hand_for_new_blind()
    if not self.deck and Deck then
        self.deck = Deck(self)
    end

    data = {
        blind_name = self.current_blind_name,
        is_boss_blind = (tonumber(self.current_blind_index) == 3),
    }
    
    self:emit_joker_event("on_blind_selected", data)

    -- No sting here: the reference opens a blind with nothing but the card-deal ladder.
    -- The whoosh1+introPad1 pair that used to play was mis-mapped from `Game:splash_screen`
    -- (reference `game.lua:1435-1436`); see `reference/review/03-cue-map.md`.
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
    -- Reference `card.lua:2463-2489`: readiness hints begin on the first hand draw, not
    -- merely whenever a joker happens to observe full hand/discard counters.
    for _, joker in ipairs(self.jokers or {}) do
        if joker and joker.start_ready_pulse then joker:start_ready_pulse() end
    end
    self:boss_on_hand_refilled(true)
    self:reset_gamepad_nav()
    self:ensure_dpad_cursor()

    self:emit_joker_event("on_round_begin", {})

    -- `set_state` above check-pointed the run before the deal was queued, so the snapshot on
    -- disk described a blind with no hand and no draw queue -- and nothing refills a hand on
    -- resume, so continuing that save landed the player in SELECTING_HAND with an empty
    -- playfield. Overwrite it now that the deal exists. (`load_run_snapshot` also repairs the
    -- saves already written this way.)
    self:autosave_run()
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
    self.shop_free_rerolls_used = 0
    self.shop_offer_slots = 2
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
    self.current_boss_blind_id = nil
    self.hand_play_counts = {}
    self.blind_hand_play_counts = {}
    -- The Ox starts a run pointed at High Card (`game.lua:1964`).
    self.frozen_most_played_hand_index = nil
    self.tarots_used = 0
    self.consumable_usage = {}
    self.handsPlayed = 0
    self.discardsUnused = 0
    self.skipsTaken = 0
    self._endless_mode = false
    self._victory_progress_recorded = false
    self.hand_size_delta_spectral = 0
    self.hand_size_delta_juggle = 0
    self.ectoplasm_used = 0
    self:reset_run_stats()
    self:reset_joker_pool_replacements()
    
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
    G:apply_pending_challenge()
    self:init_shop_offer_queue()
    self:roll_skips()
    self:set_state(self.STATES.BLIND_SELECT)
    self:begin_blind_select_intro()
end

--- Challenges use the ordinary run state; only their declarative inputs differ.
--- This mirrors the reference's start-run application order (game.lua:2063-2140).
function Game:is_challenge_banned(id)
    return type(id) == "string" and self.challenge_banned_keys and self.challenge_banned_keys[id] == true
end

local function challenge_rank(rank)
    if rank == "T" then return 10 end
    if rank == "J" then return 11 end
    if rank == "Q" then return 12 end
    if rank == "K" then return 13 end
    if rank == "A" then return 14 end
    return tonumber(rank)
end

function Game:_apply_challenge_deck_preset(preset)
    if not self.deck or type(self.deck.cards) ~= "table" then return end
    if preset == "standard" or preset == nil then return end
    local cards, suits = {}, { "Diamonds", "Clubs", "Hearts", "Spades" }
    local function add(suit, rank, enhancement, seal)
        cards[#cards + 1] = { suit = suit, rank = challenge_rank(rank), enhancement = enhancement, seal = seal }
    end
    for _, suit in ipairs(suits) do
        if preset == "city" then
            for _, rank in ipairs({ "4", "5", "6", "7", "8", "9", "T", "J", "Q", "K", "J", "Q", "K" }) do add(suit, rank) end
        elseif preset == "numbered" then
            for rank = 2, 9 do add(suit, rank) end
        else
            for rank = 2, 14 do
                local enhancement = (preset == "face_stone" and rank >= 11 and rank <= 13) and "stone" or nil
                local seal = (preset == "gold_seal") and "red" or nil
                if preset == "glass" then enhancement = "glass" end
                add(suit, rank, enhancement, seal)
            end
        end
    end
    self.deck.cards = cards
    self.deck.discard_pile = {}
end

function Game:apply_pending_challenge()
    local id = self._pending_challenge_id
    if type(id) ~= "string" or not CHALLENGE_DEFS_BY_ID then return false end
    local def = CHALLENGE_DEFS_BY_ID[id]
    if type(def) ~= "table" then return false end
    self.challenge_id = id
    self.challenge_rules = copy_table(def.rules or {})
    self.challenge_modifiers = copy_table(def.custom_rules or {})
    if self.challenge_modifiers.no_reward == true then
        self.challenge_modifiers.no_blind_reward = { ["Small Blind"] = true, ["Big Blind"] = true, ["Boss Blind"] = true }
    elseif type(self.challenge_modifiers.no_reward_specific) == "table" then
        self.challenge_modifiers.no_blind_reward = {}
        for blind_type, banned in pairs(self.challenge_modifiers.no_reward_specific) do
            if banned then self.challenge_modifiers.no_blind_reward[blind_type .. " Blind"] = true end
        end
    end
    self.challenge_banned_keys = {}
    for _, group in pairs(def.banned or {}) do
        for key, banned in pairs(group) do if banned == true then self.challenge_banned_keys[key] = true end end
    end
    self.inflation = 0
    self:_apply_challenge_deck_preset(def.deck and def.deck.preset)
    if self.challenge_rules.dollars ~= nil then self.money = tonumber(self.challenge_rules.dollars) or self.money end
    self:refresh_joker_capacity_from_negatives()
    for _, voucher_id in ipairs(def.start_vouchers or {}) do
        if not self:has_voucher(voucher_id) then
            self.vouchers[#self.vouchers + 1] = voucher_id
            self:apply_voucher_effect(voucher_id)
        end
    end
    for _, item in ipairs(def.start_jokers or {}) do
        self:add_joker_by_def(item.id, { edition = item.edition, eternal = item.eternal, pinned = item.pinned })
    end
    for _, consumable_id in ipairs(def.start_consumables or {}) do self:add_consumable(consumable_id) end
    self.hands = self:get_effective_hands_per_round()
    self.discards = self:get_effective_discards_per_round()
    return true
end

function Game:enter_blind_select()
    self:set_state(self.STATES.BLIND_SELECT)
    -- BlindChips.png is 864x1008 on disk and 1024x1024 resident -- 4 MiB uploaded inside
    -- whichever frame first drew a blind chip. Pay it on the transition instead.
    self:warm_atlases(nil, { "blind_chips" })
    self:begin_blind_select_intro()
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
    self:apply_new_blind_choice_tags()
end

--- Confirming a blind slides the cards back out the bottom; the real state
--- change happens in _commit_selected_blind once the slide finishes.
function Game:start_selected_blind()
    if self._blind_slide then return false end
    local idx = tonumber(self.selected_blind_index) or tonumber(self.current_blind_index) or 1
    if not self:is_blind_selectable(idx) then
        return false
    end
    if not self:get_blind_def(idx) then return false end
    self.active_tooltip_blind_index = nil
    self.active_tooltip_skip_blind_index = nil
    self._blind_slide = { mode = "out", t = 0 }
    return true
end

function Game:_commit_selected_blind()
    local idx = tonumber(self.selected_blind_index) or tonumber(self.current_blind_index) or 1
    if not self:is_blind_selectable(idx) then
        return false
    end
    local def = self:get_blind_def(idx)
    if not def then return false end

    self.current_blind_index = idx
    self.current_blind_target = self:get_blind_target(idx, self.ante)
    self.current_blind_reward = tonumber(def.reward) or 0
    if idx == 1 and self._stake_no_small_reward then
        -- Red and higher stakes remove the Small Blind reward (reference game.lua:2049-2057).
        self.current_blind_reward = 0
    end
    if self.challenge_modifiers and type(self.challenge_modifiers.no_blind_reward) == "table"
        and self.challenge_modifiers.no_blind_reward[def.name] == true then
        self.current_blind_reward = 0
    end
    self.current_blind_name = def.name or "Blind"
    if Sfx and Sfx.play then
        -- Reference `blind.lua:140-143`: announce the blind's displayed requirement.
        Sfx.play("chips1", 0.55 + sfx_jitter() * 0.1, 0.42)
        Sfx.play("gold_seal", 1.85 + sfx_jitter() * 0.1, 0.26)
    end
    if def.id == "boss" then
        local proto = self:get_boss_blind_prototype()
        if proto then
            self.current_blind_name = proto.name or self.current_blind_name
            self.current_blind_reward = tonumber(proto.dollars) or self.current_blind_reward
        end
        if self.challenge_modifiers and type(self.challenge_modifiers.no_blind_reward) == "table"
            and self.challenge_modifiers.no_blind_reward["Boss Blind"] == true then
            self.current_blind_reward = 0
        end
        if self.current_boss_blind_id then
            self:discover_item(self.current_boss_blind_id)
        end
        self:begin_boss_announce()
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

--- Leaving the shop slides the panel (contents and all) back out the bottom;
--- _commit_continue_from_shop advances the round once the slide finishes.
function Game:continue_from_shop()
    if self._shop_slide then return end
    -- Pin every slot before the panel leaves: a node still lerping home from a
    -- drop would otherwise trail behind the departing shop.
    self:_clear_shop_settle_flags(self.shop_offer_nodes)
    self:_clear_shop_settle_flags(self.shop_booster_nodes)
    self:_clear_shop_settle_flags(self.shop_voucher_nodes)
    self._shop_slide = { mode = "out", t = 0 }
end

function Game:_commit_continue_from_shop()
    self._shop_reroll_base_cost_override = nil
    self.hand_size_delta_juggle = 0
    self:clear_shop_selection()
    self:reset_gamepad_nav()
    self:advance_after_shop()
end

-- ---------------------------------------------------------------------------
-- Shop offers use their own named stream, so unrelated gameplay rolls cannot move them.
-- Pool weights: Joker 20, Tarot 4, Planet 4. Shop jokers: Common/Uncommon/Rare only.
-- ---------------------------------------------------------------------------

function Game:init_shop_offer_queue()
    self.shop_offer_queue = {}
    self:_refill_shop_offer_queue(128)
end

function Game:_shop_rand_int(lo, hi)
    return self:random("shop", lo, hi)
end

function Game:_pack_rand_int(lo, hi)
    return self:random("pack", lo, hi)
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

--- Inflation raises every remaining shop price after each purchase. Prices are
--- recalculated from definitions, avoiding a second mutable price system.
--- `reference/Balatro/card.lua:1800-1804`
function Game:increment_challenge_inflation()
    if not (self.challenge_modifiers and self.challenge_modifiers.inflation == true) then return end
    self.inflation = math.max(0, math.floor(tonumber(self.inflation) or 0)) + 1
    self:refresh_shop_prices()
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
    local data = self:_roll_playing_card_data(self:has_voucher("v_illusion"))
    local rank = data.rank
    local suit = data.suit
    local name = string.format("%s %s", tostring(rank), suit)
    local base_price = 4 + (tonumber(self.inflation) or 0)
    return {
        kind = "playing_card",
        id = "playing_card",
        name = name,
        price = self:apply_shop_discount_to_price(base_price),
        card_data = data,
    }
end

--- Generate a random playing card for an Illusion shop offer or Standard Pack.
--- Standard cards use the same enhancement/seal/edition polling as Illusion cards
--- (reference card.lua:1647-1665).
function Game:_roll_playing_card_data(with_modifiers, stream)
    local function roll(lo, hi) return stream == "pack" and self:_pack_rand_int(lo, hi) or self:_shop_rand_int(lo, hi) end
    local suits = { "Hearts", "Clubs", "Diamonds", "Spades" }
    local rank = roll(2, 14)
    local suit = suits[roll(1, #suits)]
    local data = { rank = rank, suit = suit, enhancement = nil, seal = nil }
    if with_modifiers then
        if roll(1, 100) <= 40 then
            local enhs = { "bonus", "mult", "wild", "glass", "steel", "gold", "lucky" }
            data.enhancement = enhs[roll(1, #enhs)]
        end
        if roll(1, 100) <= 20 then
            local seals = { "red", "blue", "gold", "purple" }
            data.seal = seals[roll(1, #seals)]
        end
        -- Standard/Illusion edition poll is 2x normal and cannot be Negative.
        local r = roll(1, 10000)
        local edition
        if r > 9880 then edition = "polychrome"
        elseif r > 9600 then edition = "holo"
        elseif r > 9200 then edition = "foil"
        end
        if edition then data.modifier = { edition = edition } end
    end
    return data
end

--- Eligible unowned voucher ids, excluding any already listed in `exclude_ids`.
function Game:_shop_voucher_candidate_ids(exclude_ids)
    exclude_ids = exclude_ids or {}
    local candidates = {}
    if type(VOUCHER_DEFS) ~= "table" then return candidates end
    for vid, def in pairs(VOUCHER_DEFS) do
        if type(def) == "table" and type(vid) == "string" and not exclude_ids[vid] and not self:is_challenge_banned(vid) then
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
    local price = (tonumber(d and d.price) or 10) + (tonumber(self.inflation) or 0)
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

--- Purchase cue shared by every shop purchase (joker/card offer, instant-use consumable,
--- booster pack). Vouchers use the same pair when redeemed.
function Game:_play_shop_buy_sfx()
    if not (Sfx and Sfx.play) then return end
    -- Reference `functions/button_callbacks.lua:2464-2467`.
    Sfx.play("card1")
    Sfx.play("coin1")
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
    self:increment_challenge_inflation()
    if not self.vouchers then self.vouchers = {} end
    self.vouchers[#self.vouchers + 1] = voucher_id
    self:apply_voucher_effect(voucher_id)
    table.remove(self.shop_voucher_offers, slot_index)
    if self.shop_voucher_nodes and self.shop_voucher_nodes[slot_index] then
        local removed = self.shop_voucher_nodes[slot_index]
        table.remove(self.shop_voucher_nodes, slot_index)
        -- The reference juices the voucher and holds it on screen while it announces itself
        -- (`card.lua:1813-1848`); the port blinked it out, so the run's most consequential
        -- purchase read exactly like buying a $3 joker. The name callout is still missing.
        if removed and removed.juice_up then removed:juice_up(0.3, 0.5) end
        self:retain_dissolving_node(removed, self.C and self.C.GOLD)
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
    if Sfx and Sfx.play then
        -- Reference `card.lua:1830-1831`.
        Sfx.play("card1")
        Sfx.play("coin1")
    end
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
        pick = candidates[self:random("voucher", 1, #candidates)]
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
    if self._blind_slide then return false end
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
        -- Negative is a flat 0.3% poll and is not affected by Hone/Glow Up
        -- (reference common_events.lua:2055-2080).
        negative = 0.3,
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

--- Older name for `Game:consumable_center_in_play`, kept for the shop call sites.
function Game:_shop_consumable_owned(id)
    return self:consumable_center_in_play(id)
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
    local guard = 0
    while guard < 64 do
        guard = guard + 1
        if #(self.shop_offer_queue or {}) == 0 then break end
        local entry = table.remove(self.shop_offer_queue, 1)
        if not entry then break end
        self:remap_shop_joker_offer(entry)
        local is_joker = entry.kind == "joker" or entry.kind == nil
        if is_joker and type(entry.id) == "string" and not self:joker_meets_deck_requirement(entry.id) then
            -- Skip deck-gated jokers that were queued before the requirement was met.
        else
            return entry
        end
    end
    return self:_generate_next_shop_queue_offer()
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
    -- Magic Trick adds four playing-card weights (reference game.lua:604).
    local cw = self:has_voucher("v_magic_trick") and 4 or 0
    local joker_weight = (self.challenge_modifiers and self.challenge_modifiers.no_shop_jokers == true) and 0 or 20
    local total = joker_weight + tw + pw + sw + cw
    local max_attempts = 32

    for _ = 1, max_attempts do
        local roll = self:_shop_rand_int(1, total)
        local kind = "planet"
        if roll <= joker_weight then
            kind = "joker"
        elseif roll <= joker_weight + tw then
            kind = "tarot"
        elseif roll <= joker_weight + tw + pw then
            kind = "planet"
        elseif roll <= joker_weight + tw + pw + sw then
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

    if joker_weight > 0 then
        local j2 = self:_roll_shop_queue_joker_offer()
        if j2 then return j2 end
    end
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
            if rv == target_rar and rv >= 1 and rv <= 3 and not self:is_challenge_banned(id) and self:joker_allowed_in_random_pool(id) then
                candidates[#candidates + 1] = id
            end
        end
    end
    table.sort(candidates)
    if #candidates == 0 then
        for id, def in pairs(JOKER_DEFS) do
            if type(def) == "table" and type(id) == "string" then
                local rv = tonumber(def.rarity) or 1
                if rv >= 1 and rv <= 3 and not self:is_challenge_banned(id) and self:joker_allowed_in_random_pool(id) then
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
        if type(def) == "table" and def.kind == wanted_kind and type(id) == "string" and not self:is_challenge_banned(id) then
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
    local raw = math.max(1, base + (tonumber(ec) or 0) + (tonumber(self.inflation) or 0))
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
    if self.challenge_modifiers and self.challenge_modifiers.all_eternal == true
        and not (type(def) == "table" and def.eternal_compat == false) then
        params.eternal = true
        params.perishable = nil
    end
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
    local raw = (by_kind[kind] or 3) + (tonumber(self.inflation) or 0)
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
    local base = (tonumber(d and d.price) or 10) + (tonumber(self.inflation) or 0)
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
    -- Free rerolls (Chaos the Clown) don't count toward the escalation, so the
    -- roll after a free one still costs the base price.
    local free_used = math.max(0, math.floor(tonumber(self.shop_free_rerolls_used) or 0))
    local n = math.max(0, math.floor(tonumber(self.shop_reroll_count) or 0) - free_used)
    if free_used < 1 and self:hasJoker("j_chaos") then return 0 end
    local sub = 0
    if self:has_voucher("v_reroll_glut") then sub = sub + 2 end
    if self:has_voucher("v_reroll") then sub = sub + 2 end
    if self._shop_reroll_base_cost_override ~= nil then
        return math.max(0, base + n - sub)
    end
    return math.max(1, base + n - sub)
end

function Game:generate_joker_from_rarity(rarity)
    local id = self:random_joker_def_id_by_rarity(rarity, "shop")
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
            if tag.type == "uncommon" or tag.type == "rare" then
                entry = self:generate_joker_from_rarity(tag.type == "rare" and 3 or 2)
                if entry.id == nil then
                    -- The rarity's pool is empty - every Joker in it is already owned. The
                    -- reference plays the tag's `nope()` and hands out nothing
                    -- (`reference/Balatro/tag.lua:363-370`); here the tag is still spent, but
                    -- the slot falls back to a normal shop roll. Keeping the id-less entry
                    -- put a blank, nameless, free card on the shelf.
                    entry = nil
                    self:removeTag(i)
                else
                    entry.price = 0
                    tagUsed = tag.type
                end
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
            -- The reference's cull is on `G.GAME.used_jokers`, which `Card:set_ability` sets
            -- for *any* card that exists (`card.lua:349-354`) -- including one sitting in the
            -- shop. So the shop cannot roll the same tarot into two slots: the first one's
            -- existence takes it out of the pool for the second. This port derived "in play"
            -- from the player's inventory alone, which covers a consumable you are holding but
            -- not one already on the shelf beside it, so a shop could offer two Towers.
            --
            -- `seen_ids` is the shop-local half of that, and is what the joker branch above
            -- has always used. A rejected entry just consumes its queue slot and the loop pops
            -- another, exactly as an owned one does.
            local dup = false
            if not allow_duplicates then
                dup = self:_shop_consumable_owned(entry.id)
                    or (entry.id ~= nil and seen_ids[entry.id] == true)
            end
            if not dup then
                if self:hasTag("coupon") ~= -1 and self.shop_reroll_count == 0 then entry.price = 0 end
                self.shop_offers[#self.shop_offers + 1] = entry
                if entry.id ~= nil then seen_ids[entry.id] = true end
            end
        end
    end
    self:refresh_shop_prices()
    self:sync_shop_offer_nodes()
end

function Game:reroll_shop_offers()
    if self.STATE ~= self.STATES.SHOP then return false end
    if self._shop_slide then return false end
    local cost = self:shop_current_reroll_cost()
    if not self:can_afford_price(cost) then
        return false
    end
    local chaos_free = (math.floor(tonumber(self.shop_free_rerolls_used) or 0) < 1) and self:hasJoker("j_chaos")
    self.money = (tonumber(self.money) or 0) - cost
    self.shop_reroll_count = (tonumber(self.shop_reroll_count) or 0) + 1
    if chaos_free then
        self.shop_free_rerolls_used = (tonumber(self.shop_free_rerolls_used) or 0) + 1
    end
    self:record_shop_reroll()
    if Sfx and Sfx.play then
        -- Reference `functions/button_callbacks.lua:2880-2881`.
        Sfx.play("coin2")
        Sfx.play("other1")
    end
    self:emit_joker_event("on_shop_reroll", {
        reroll_cost = cost,
        reroll_count = self.shop_reroll_count,
    })
    self.active_tooltip_joker = nil
    self.active_tooltip_shop_voucher_slot = nil
    self:roll_shop_offers()
    self:clear_shop_selection()
    self:begin_shop_pop_in(self.shop_offer_nodes)
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
        if type_name == "top_up" then return 10 end
        if type_name == "juggle" then return 11 end
        if type_name == "boss" then return 12 end
        if type_name == "standard" then return 13 end
        if type_name == "charm" then return 14 end
        if type_name == "meteor" then return 15 end
        if type_name == "buffoon" then return 16 end
        if type_name == "orbital" then return 17 end
        if type_name == "skip" then return 18 end
        if type_name == "handy" then return 19 end
        if type_name == "garbage" then return 20 end
        if type_name == "ethereal" then return 21 end
        if type_name == "economy" then return 22 end
        if type_name == "d_six" then return 23 end
        return -1
    end

    if type(self.P_TAGS) == "table" then
        for tag_key, def in pairs(self.P_TAGS) do
            if type(def) == "table" and type(tag_key) == "string" then
                local min_ante = tonumber(def.min_ante)
                if (not min_ante) or ante >= min_ante then
                    local id = tag_key_to_id(tag_key)
                    if id ~= -1 and not self:is_challenge_banned(tag_key) then
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
        local tag_key = eligible_tags[self:random("tag", 1, #eligible_tags)]
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
        if (spectral_ok or e.pack ~= "spectral")
            and not self:is_challenge_banned("p_" .. e.pack .. "_" .. e.size .. "_1") then
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
    local raw = (by_size[size] or 4) + (tonumber(self.inflation) or 0)
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
        local n_cards = BoosterPackUI.card_count_for_size(size, pack)
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

    local opening_origin = self._shop_booster_rects and self._shop_booster_rects[slot_index]
    if opening_origin then
        opening_origin = {
            x = opening_origin.x, y = opening_origin.y,
            w = opening_origin.w, h = opening_origin.h,
        }
    end
    self.money = (tonumber(self.money) or 0) - price
    self:increment_challenge_inflation()
    self:_play_shop_buy_sfx()
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
    self:begin_booster_session(offer, opening_origin)
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

function Game:_consumable_pool_ids(wanted_kind, ignore_cull)
    local pool = {}
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
            -- A pack does not offer what you are already holding, the same cull the reference
            -- applies to every pool (`common_events.lua:1987`). The joker path below already
            -- did this through `_shop_joker_owned`; consumables were missing it.
            if incl and not ignore_cull and self:consumable_center_in_play(id) then
                incl = false
            end
            if incl then
                pool[#pool + 1] = id
            end
        end
    end
    table.sort(pool)
    return pool
end

--- One draw pool, shared by every slot of a single booster pack, so a pack cannot offer the
--- same centre twice. The reference gets that for free: `Card:set_ability` marks a centre used
--- the moment a pack card is created (`card.lua:352`) and the next slot's pool culls it
--- (`common_events.lua:1987`). Here the pool is explicit, so it has to outlive the slot.
function Game:_new_pack_pool(wanted_kind, stream)
    local allow_duplicates = self:hasJoker("j_ring_master")
    local ids = self:_consumable_pool_ids(wanted_kind, allow_duplicates)
    -- Holding enough of a kind can cull the pool to nothing (a Celestial pack while sitting on
    -- most of the planets). An empty pack is worse than a duplicate, so drop the cull rather
    -- than open with no choices at all - the reference reaches for a fixed fallback centre at
    -- the same point (`common_events.lua:2038-2043`).
    if #ids == 0 and not allow_duplicates then
        ids = self:_consumable_pool_ids(wanted_kind, true)
    end
    return { kind = wanted_kind, ids = ids, allow_duplicates = allow_duplicates, stream = stream }
end

--- Takes one id out of a pack pool. `forced` skips the draw entirely (Telescope's guaranteed
--- planet) and still consumes the id, which is what stops a later slot from repeating it.
function Game:_pack_pool_take(pool, forced)
    if not pool then return nil end
    local ids = pool.ids
    if forced then
        if not pool.allow_duplicates then
            for i = #ids, 1, -1 do
                if ids[i] == forced then table.remove(ids, i) end
            end
        end
        return forced
    end
    if #ids == 0 then return nil end
    local idx = pool.stream == "pack" and self:_pack_rand_int(1, #ids) or self:_shop_rand_int(1, #ids)
    if pool.allow_duplicates then return ids[idx] end
    return table.remove(ids, idx)
end

function Game:_shop_pick_unique_consumable_ids(wanted_kind, count, stream)
    local pool = self:_new_pack_pool(wanted_kind, stream)
    local out = {}
    for _ = 1, count do
        local id = self:_pack_pool_take(pool)
        if not id then break end
        out[#out + 1] = id
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
    local rare_spectral_placed = {}
    local function maybe_replace_with_rare_spectral(base_kind, def_copy)
        if type(def_copy) ~= "table" then return base_kind, def_copy end
        local soul_def = CONSUMABLE_DEFS and CONSUMABLE_DEFS.spectral_soul
        local black_hole_def = CONSUMABLE_DEFS and CONSUMABLE_DEFS.spectral_black_hole

        local can_soul = (pack == "arcana" or pack == "spectral")
        local can_black_hole = (pack == "celestial" or pack == "spectral")
        -- The reference gates each of these on `used_jokers`, which a created Soul / Black Hole
        -- sets (`common_events.lua:2090-2097`), so one pack cannot roll the same rare twice and
        -- one you already hold is off the table. Showman lifts both, as it lifts every cull.
        local allow_duplicates = self:hasJoker("j_ring_master")
        local function blocked(id)
            if allow_duplicates then return false end
            return rare_spectral_placed[id] or self:consumable_center_in_play(id)
        end

        -- 0.3% chance each per card slot (replacement behavior).
        if can_black_hole and black_hole_def and not blocked("spectral_black_hole")
            and self:_pack_rand_int(1, 1000) <= 3 then
            local c = copy_table and copy_table(black_hole_def) or nil
            if c then
                c.id = "spectral_black_hole"
                rare_spectral_placed["spectral_black_hole"] = true
                return "spectral", c
            end
        end
        if can_soul and soul_def and not blocked("spectral_soul")
            and self:_pack_rand_int(1, 1000) <= 3 then
            local c = copy_table and copy_table(soul_def) or nil
            if c then
                c.id = "spectral_soul"
                rare_spectral_placed["spectral_soul"] = true
                return "spectral", c
            end
        end
        return base_kind, def_copy
    end

    local function consumable_choice(kind, id)
        local def = CONSUMABLE_DEFS and CONSUMABLE_DEFS[id]
        if type(def) ~= "table" or not copy_table then return end
        local c = copy_table(def)
        c.id = id
        local out_kind, out_def = maybe_replace_with_rare_spectral(kind, c)
        choices[#choices + 1] = { kind = out_kind, consumable_def = out_def, taken = false }
    end

    if pack == "arcana" then
        local tarots = self:_new_pack_pool("tarot", "pack")
        local spectrals = nil
        for _ = 1, n do
            local kind, id = "tarot", nil
            -- Omen Globe replaces a Tarot 20% of the time (reference card.lua:1640-1645). The
            -- reference rolls this before drawing, so a replaced slot never spends a Tarot.
            if self:has_voucher("v_omen_globe") and self:_pack_rand_int(1, 100) > 80 then
                spectrals = spectrals or self:_new_pack_pool("spectral", "pack")
                id = self:_pack_pool_take(spectrals)
                if id then kind = "spectral" end
            end
            if not id then
                kind, id = "tarot", self:_pack_pool_take(tarots)
            end
            if not id then break end
            consumable_choice(kind, id)
        end
    elseif pack == "celestial" then
        local pool = self:_new_pack_pool("planet", "pack")
        local pref = nil
        if self:has_voucher("v_telescope") then
            pref = self:_planet_consumable_id_for_most_played_hand()
            if pref and not (CONSUMABLE_DEFS and CONSUMABLE_DEFS[pref]) then pref = nil end
        end
        for i = 1, n do
            -- Telescope forces the first slot only, and forcing it consumes the planet so the
            -- remaining slots cannot repeat it (reference card.lua:1737-1751 forces a key, which
            -- both skips the pool draw and marks the centre used).
            local forced = (i == 1) and pref or nil
            local id = self:_pack_pool_take(pool, forced)
            if not id then break end
            if forced then
                -- A forced key means the reference never reaches its Soul / Black Hole roll
                -- (`common_events.lua:2087`), so the guaranteed planet stays a planet.
                local def = CONSUMABLE_DEFS[id]
                if type(def) == "table" and copy_table then
                    local c = copy_table(def)
                    c.id = id
                    choices[#choices + 1] = { kind = "planet", consumable_def = c, taken = false }
                end
            else
                consumable_choice("planet", id)
            end
        end
    elseif pack == "spectral" then
        local pool = self:_new_pack_pool("spectral", "pack")
        for _ = 1, n do
            local id = self:_pack_pool_take(pool)
            if not id then break end
            consumable_choice("spectral", id)
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
        for _ = 1, n do
            choices[#choices + 1] = {
                kind = "playing",
                playing_data = self:_roll_playing_card_data(true, "pack"),
                taken = false,
            }
        end
    end

    return choices
end

--- Pack contents arrive white and slow: `card.lua:1779` materialises every card a booster
--- lays out with `{G.C.WHITE, G.C.WHITE}` at 1.5x the usual tween. White because a pack has
--- not told you what is in it yet, and slow because it is the one moment the player is
--- looking at nothing else.
local BOOSTER_MATERIALIZE_COLOUR = { 1, 1, 1, 1 }
local BOOSTER_MATERIALIZE_TIMEFAC = 1.5

--- Warm one pack choice's art, at most one per call.
---
--- `_release_booster_pack` constructs every choice node in a single frame, and each
--- construction blocks on `newImage` - a SD read plus a texture build, ~24 ms on console.
--- Five of those stacked is the ~80 ms freeze on the frame the pack bursts open, which is the
--- one frame of the whole animation the player is actually looking at.
---
--- The fix is scheduling, not caching: the choices are rolled in `begin_booster_session`, and
--- the wrapper then spends PACK_MOVE_DURATION + PACK_BURST_DURATION (1.7 s, ~100 frames)
--- flying in and shaking before it releases. One sprite a frame across that window costs the
--- same total time but never puts two loads in the same frame, so the freeze becomes a handful
--- of merely-slow frames under an animation that is already shaking the screen.
---
--- One per call rather than a whole batch on purpose: a 24 ms load already overruns a 16.7 ms
--- frame, so the budget is one, and there are twenty times more frames than choices.
---@param sess table the booster session
local function warm_next_booster_choice(sess)
    local choices = sess and sess.choices
    if type(choices) ~= "table" then return end
    local i = (tonumber(sess.warm_index) or 0) + 1
    while i <= #choices do
        local ch = choices[i]
        if type(ch) == "table" and not ch.taken then
            if (ch.kind == "tarot" or ch.kind == "planet" or ch.kind == "spectral")
                and Consumable and Consumable.warm_sprite then
                local def = ch.consumable_def
                -- Asked for rather than recomputed: the negative-edition offset belongs to
                -- the constructor, and a warm that guessed it wrong would load the wrong
                -- sprite and leave the real one to stall the frame it was sparing.
                local index = type(def) == "table" and Consumable.sprite_index_for(def)
                if index and not Consumable.sprite_is_resident(index) then
                    sess.warm_index = i
                    Consumable.warm_sprite(index)
                    return
                end
            elseif ch.kind == "joker" and Joker and Joker.warm_sprite then
                local jd = JOKER_DEFS and JOKER_DEFS[ch.joker_id]
                if type(jd) == "table" then
                    local params = type(ch.create_params) == "table" and ch.create_params
                        or { edition = ch.edition or "base" }
                    sess.warm_index = i
                    if Joker.warm_sprite(jd, params) then return end
                end
            end
            -- A playing card draws from the shared card atlas, which a run always has resident.
        end
        i = i + 1
    end
    sess.warm_index = #choices
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
                node.states.click.can = false
                node.states.drag.can = false
                nodes[i] = node
                self:add(node)
                self:_booster_materialize_choice_node(node)
            end
        elseif ch.kind == "joker" and Joker then
            local jd = JOKER_DEFS and JOKER_DEFS[ch.joker_id]
            if type(jd) == "table" then
                local create_params = type(ch.create_params) == "table" and copy_table(ch.create_params) or { edition = ch.edition or "base" }
                create_params.face_up = true
                local node = Joker(0, 0, self.joker_slot_w, self.joker_slot_h, jd, create_params)
                node._booster_choice_index = i
                node.states.click.can = false
                node.states.drag.can = false
                nodes[i] = node
                self:add(node)
                self:_booster_materialize_choice_node(node)
            end
        elseif ch.kind == "playing" and Card then
            local node = Card(0, 0, nil, nil, ch.playing_data, nil, { face_up = true })
            node._booster_choice_index = i
            node.states.click.can = false
            node.states.drag.can = false
            nodes[i] = node
            self:add(node)
            self:_booster_materialize_choice_node(node)
        end
    end
    return nodes
end

--- Burn one pack card in. No burst: these are spawned before `layout_choice_nodes` has put
--- them anywhere, so a converging ring would collapse onto the origin instead of the card.
---@param node Moveable
function Game:_booster_materialize_choice_node(node)
    self:begin_materializing_node(node, BOOSTER_MATERIALIZE_COLOUR,
        BOOSTER_MATERIALIZE_TIMEFAC, true)
end

--- Wrapper art for a pack that did not come from the shop. Shop offers roll a random frame
--- from the pack's row; a tag's pack has no roll behind it, and the reference hands out one
--- fixed key (`p_buffoon_mega_1`, `reference/Balatro/tag.lua:271`), so take the first frame.
--- Without this the index fell back to 0 at draw time and every tag pack - Buffoon, Standard,
--- Spectral - wore the normal Arcana wrapper (`booster_pack_ui.lua:282`).
---@return number
function Game:_default_booster_sprite_index(pack, size)
    local frames = ShopUI and ShopUI.booster_frames_for_pack_size and
        ShopUI.booster_frames_for_pack_size(pack, size)
    if type(frames) == "table" and frames[1] then return frames[1] end
    return 0
end

function Game:begin_booster_session(offer, opening_origin)
    if type(offer) ~= "table" then return end
    self:_booster_destroy_choice_nodes()
    self.booster_session = nil
    self._booster_closing = nil
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
        booster_sprite_index = tonumber(offer.booster_sprite_index)
            or self:_default_booster_sprite_index(offer.pack, offer.size),
        opening_origin_rect = opening_origin,
        opening_pack_rect = opening_origin,
        opening_phase = "move",
        opening_t = 0,
    }
    self._booster_skip_rect = nil

    -- Reference `Card:open` keeps the wrapper alive for its buildup and only creates
    -- pack cards after the release (`reference/Balatro/card.lua:1721-1789`).
    self:set_state(self.STATES.OPEN_BOOSTER)

    if Sfx and Sfx.play then Sfx.play("explosion_buildup1") end
end

function Game:_release_booster_pack()
    local sess = self.booster_session
    if not sess or sess.opening_phase ~= "buildup" then return end
    sess.opening_phase = "reveal"
    sess.opening_t = 0
    -- A pack releases every card on one frame, and the dissolve mask's crowd count is a frame
    -- behind by design - so without this the single frame the player is watching is the one
    -- frame drawn at the expensive resolution. The pack knows the number, so it says so.
    if Fx and Fx.expect_dissolves then
        local pending = 0
        for _, ch in ipairs(sess.choices) do
            if type(ch) == "table" and not ch.taken then pending = pending + 1 end
        end
        Fx.expect_dissolves(pending)
    end
    sess.choice_nodes = self:_booster_spawn_choice_nodes(sess.choices)
    if self.shake then self:shake(3) end
    if Sfx and Sfx.play then Sfx.play("explosion_release1") end

    if sess.hand_for_tarot then
        if self.hand and self.hand.return_all_cards_to_deck_draw_pile then
            self.hand:return_all_cards_to_deck_draw_pile()
        elseif self.hand and self.hand.clear then
            self.hand:clear()
        end
        if self.hand and self.hand.fill_from_deck then
            -- Dealt through the normal staggered queue, as the reference deals a pack's
            -- preview hand (`state_events.lua:371-376`). Consumable use flushes the queue
            -- first, so a mashed pick still sees the whole hand.
            self.hand:fill_from_deck()
        end
    end
    self:init_booster_gamepad_nav()
end

function Game:_update_booster_opening(dt)
    local sess = self.booster_session
    if self.STATE ~= self.STATES.OPEN_BOOSTER or not sess or not sess.opening_phase then return end
    sess.opening_t = (tonumber(sess.opening_t) or 0) + math.max(0, tonumber(dt) or 0)
    if sess.opening_phase == "move" and sess.opening_t >= BoosterPackUI.PACK_MOVE_DURATION then
        sess.opening_phase = "buildup"
        sess.opening_t = sess.opening_t - BoosterPackUI.PACK_MOVE_DURATION
    end
    -- Everything before the release is dead time the art can be loaded in. Once the pack has
    -- released, the nodes exist and warming has nothing left to do.
    if sess.opening_phase == "move" or sess.opening_phase == "buildup" then
        warm_next_booster_choice(sess)
    end
    if sess.opening_phase == "buildup" then
        local speed = tonumber(self.SETTINGS and self.SETTINGS.GAMESPEED) or 1
        local duration = BoosterPackUI.PACK_BURST_DURATION * math.sqrt(speed)
        if sess.opening_t >= duration then self:_release_booster_pack() end
    elseif sess.opening_phase == "reveal" and sess.opening_t >= BoosterPackUI.CARD_REVEAL_DURATION then
        sess.opening_phase = "ready"
        sess.opening_t = BoosterPackUI.CARD_REVEAL_DURATION
    end
end

--- Data-only view of an open pack, for the run snapshot. The live session also holds card
--- nodes and an opening animation; neither survives a save, and neither needs to — a restored
--- pack opens straight onto its choices.
---
--- Without this, buying a pack and quitting inside it charged the player and gave nothing
--- back: the offer had already left the shop and the state fell back to `SHOP` on load. The
--- reference serialises its pack CardArea with everything else (`misc_functions.lua:1454`).
---@return table|nil
function Game:_serialize_booster_session()
    local sess = self.booster_session
    if type(sess) ~= "table" or type(sess.choices) ~= "table" then return nil end
    local choices = {}
    for i, choice in ipairs(sess.choices) do
        choices[i] = copy_table(choice)
    end
    return {
        pack = sess.pack,
        size = sess.size,
        title = sess.title,
        choices = choices,
        picks_remaining = math.max(0, math.floor(tonumber(sess.picks_remaining) or 0)),
        hand_for_tarot = sess.hand_for_tarot == true or nil,
        booster_sprite_index = sess.booster_sprite_index,
        return_state = self._booster_return_state,
    }
end

--- Rebuild an open pack from a snapshot, skipping the buildup animation.
---@param data table|nil
---@return boolean restored
function Game:_restore_booster_session(data)
    if type(data) ~= "table" or type(data.choices) ~= "table" or #data.choices == 0 then
        return false
    end
    self:_booster_destroy_choice_nodes()
    self._booster_return_state = data.return_state or self.STATES.SHOP
    self.booster_session = {
        pack = data.pack,
        size = data.size,
        title = data.title or self:_booster_offer_display_name(data.pack, data.size),
        choices = data.choices,
        choice_nodes = {},
        picks_remaining = math.max(0, math.floor(tonumber(data.picks_remaining) or 0)),
        hand_for_tarot = data.hand_for_tarot == true,
        active_choice_index = nil,
        booster_sprite_index = tonumber(data.booster_sprite_index)
            or self:_default_booster_sprite_index(data.pack, data.size),
        -- The wrapper burst already happened before the save; come back to the open pack.
        opening_phase = "ready",
        opening_t = BoosterPackUI.CARD_REVEAL_DURATION,
    }
    self._booster_skip_rect = nil
    self.booster_session.choice_nodes = self:_booster_spawn_choice_nodes(self.booster_session.choices)
    return true
end

--- Is anything the last pick set in motion still playing out?
---
--- Everything a tarot or spectral can start -- the used card flying out, a conversion ripple,
--- cards coming apart under Immolate, the hand level-up flourish -- runs on its own clock and
--- used to be cut off the instant the pack closed, because the close happened on the same frame
--- as the pick.
---@return boolean
function Game:booster_effects_busy()
    if self._consumable_flight then return true end
    if self._card_ripple then return true end
    if self._hand_levelup then return true end
    if self._dissolving_nodes and #self._dissolving_nodes > 0 then return true end
    local hand = self.hand
    if hand and hand.has_pending_card_lifecycles and hand:has_pending_card_lifecycles() then
        return true
    end
    return false
end

--- Beat held after the last pick before the pack closes, even when nothing is animating, so a
--- pick never reads as the pack blinking shut. The reference gets the same beat out of the two
--- `delay(0.2)`s either side of `use_consumeable` (`button_callbacks.lua:2216-2258`).
local BOOSTER_CLOSE_MIN_HOLD = 0.4
--- Ceiling on that hold, so a stuck animation can never strand the player in a spent pack. It
--- has to clear the longest legitimate effect a pick can start, which is the hand level-up a
--- Celestial pack runs; anything under that would cut the last card's readout off mid-climb.
--- (`HAND_LEVELUP_DURATION`, 2.9 s, plus a beat; a literal because that constant is declared
--- further down this file and this line runs at load.)
local BOOSTER_CLOSE_MAX_HOLD = 3.4

--- Begin closing the pack: hold while the last pick's effects finish, then end the session.
function Game:begin_booster_close()
    if not self.booster_session then return end
    if self._booster_closing then return end
    self._booster_closing = { t = 0 }
end

---@param dt number real seconds
function Game:_update_booster_close(dt)
    if not self.booster_session then
        self._booster_closing = nil
        return
    end
    -- A session restored from a save with nothing left to pick has no other way out but the
    -- skip button; start the close for it.
    if not self._booster_closing and (tonumber(self.booster_session.picks_remaining) or 1) <= 0 then
        self:begin_booster_close()
    end
    local c = self._booster_closing
    if not c then return end
    if self.STATE == self.STATES.PAUSED then return end
    c.t = c.t + dt
    if c.t < BOOSTER_CLOSE_MIN_HOLD then return end
    if c.t < BOOSTER_CLOSE_MAX_HOLD and self:booster_effects_busy() then return end
    self._booster_closing = nil
    self:end_booster_session()
end

function Game:end_booster_session()
    local sess = self.booster_session
    self._booster_closing = nil
    if sess and sess.hand_for_tarot then
        if self.hand and self.hand.clear_selection then
            self.hand:clear_selection()
        end
        -- Un-deal rather than vanish: the preview hand goes back to the deck's off-screen origin
        -- on the discard beat, the same peel-off a beaten blind's hand gets
        -- (`Game:recycle_full_deck_after_blind_win`). `take_undeal_flights` detaches the nodes
        -- and leaves `Hand.cards` alone, so the recycle below still sees every card.
        if self.hand and self.hand.take_undeal_flights then
            self.pending_discard = self.pending_discard or {}
            for _, entry in ipairs(self.hand:take_undeal_flights()) do
                self.pending_discard[#self.pending_discard + 1] = entry
            end
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
        -- Ectoplasm and Hex both draw from the editionless pool (`card.lua:1546-1548`).
        if (sid == "spectral_ectoplasm" or sid == "spectral_hex") and #self:editionless_jokers() < 1 then
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
        -- Taking a card out of a pack is an acquisition, not a creation: the reference's pack
        -- cards materialised when the pack opened (`card.lua:1779`) and `use_card` then moves
        -- the existing card into the joker row. Fly it off the pack shelf rather than burning
        -- a second copy in on top of the one the player just clicked.
        self:add_joker_by_def(ch.joker_id, create_params,
            sess.choice_nodes and sess.choice_nodes[idx])
    elseif ch.kind == "playing" then
        if self.deck and self.deck.insert_random then
            self.deck:insert_random(ch.playing_data)
            self:notify_cards_added_to_deck(1)
        end
    elseif ch.kind == "tarot" or ch.kind == "spectral" then
        local c = ch.consumable_def
        -- A pick mid-deal must act on the full preview hand, not the part that has landed.
        if sess.hand_for_tarot and self.hand and self.hand.flush_draw_queue then
            self.hand:flush_draw_queue()
        end
        if not self:pack_consumable_can_apply(c) then return false end
        self:track_consumable_use(c)
        self:apply_consumable_effect(c)
    else
        return false
    end

    ch.taken = true
    -- The card leaving the pack: a low card thump under the generic confirm.
    if Sfx and Sfx.play then
        Sfx.play("card1", 0.8, 0.6)
        Sfx.play("generic1")
    end
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
    if sess.picks_remaining <= 0 then self:begin_booster_close() end
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
    -- A pick mid-deal must act on the full preview hand, not the part that has landed.
    if sess.hand_for_tarot and self.hand and self.hand.flush_draw_queue then
        self.hand:flush_draw_queue()
    end
    if not self:pack_consumable_can_apply(c) then return false end

    self:track_consumable_use(c)
    self:apply_consumable_effect(c)

    ch.taken = true
    -- Same take cue as pick_booster_choice; the consumable's own cue plays from
    -- apply_consumable_effect above.
    if Sfx and Sfx.play then
        Sfx.play("card1", 0.8, 0.6)
        Sfx.play("generic1")
    end
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
        self:begin_booster_close()
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
    -- `Blind:defeat` flips the Jokers back before the round even ends (`blind.lua:338`), so
    -- Amber Acorn's flip does not follow the player into the cash out and the shop.
    self:restore_joker_facing()
    -- Garbage Tag counts unused discards across completed blinds (reference tag.lua:158-165).
    self.discardsUnused = math.max(0, tonumber(self.discardsUnused) or 0)
        + math.max(0, tonumber(self.discards) or 0)
    if tonumber(self.current_blind_index) == 3 then
        self.boss_runtime = self.boss_runtime or {}
        self.boss_runtime.clear_card_debuffs_after_win = true
        -- The ante rises the moment the Boss falls, not when the shop is left
        -- (`state_events.lua:248`: the eternal/joker-slot modifiers, then `ease_ante(1)`,
        -- all inside `end_round` before ROUND_EVAL). `ease_ante` is what rings the
        -- highlight2/generic1 pair, so the cue belongs to the win, not to the shop exit.
        -- The challenge modifiers compare against the ante that just ended, so they run
        -- before the increment.
        local mods = self.challenge_modifiers or {}
        if tonumber(mods.set_eternal_ante) == (tonumber(self.ante) or 1) then
            for _, joker in ipairs(self.jokers or {}) do
                if joker then joker.eternal = true end
            end
        end
        if tonumber(mods.set_joker_slots_ante) == (tonumber(self.ante) or 1) then
            self.challenge_joker_slots_disabled = true
        end
        self.ante = (tonumber(self.ante) or 1) + 1
        self:check_unlock("ante_up", { ante = self.ante })
        -- The Ox's target is re-fixed only here, as a Boss blind falls
        -- (`state_events.lua:132-138`).
        self:freeze_most_played_hand()
    end

    -- Round-win unlock conditions (`common_events.lua:1500-1520`). Matador wants a Boss
    -- taken in one hand with no discards spent; Hanging Chad wants a Boss taken on High
    -- Card; Troubadour wants a streak of one-hand rounds, which is tracked here because
    -- this is the only place that knows a round just ended.
    local hands_this_round = 0
    for _, count in pairs(self.blind_hand_play_counts or {}) do
        hands_this_round = hands_this_round + (tonumber(count) or 0)
    end
    if hands_this_round == 1 then
        self:add_career_stat("c_single_hand_round_streak", 1)
    elseif type(self.career_stats) == "table" then
        self.career_stats.c_single_hand_round_streak = 0
    end
    local discards_used = math.max(0, (tonumber(self:get_effective_discards_per_round()) or 0)
        - (tonumber(self.discards) or 0))
    self:check_unlock("round_win", {
        is_boss_blind = tonumber(self.current_blind_index) == 3,
        hands_played = hands_this_round,
        discards_used = discards_used,
        last_hand = self.handlist and self.handlist[tonumber(self.last_played_hand_index) or -1] or nil,
    })
    self:check_unlock("money")
    self:record_run_high_scores()
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
        -- Reference `functions/state_events.lua:1149-1207` collects every reward
        -- before applying the cash-out total. In particular, Joker and tag money
        -- must not increase this round's interest.
        table.insert(self._round_win_joker_payout_lines, { label, amt, "pending" })
        if JokerEffects and JokerEffects.mark_effect_applied then
            JokerEffects.mark_effect_applied(ctx)
        end
    end
    -- The round-end jokers that pop rather than pay -- Popcorn shrinking, Turtle Bean
    -- wilting, Gros Michel and Cavendish rolling for extinction, Invisible Joker -- announce
    -- themselves with blocking status events in the reference (`state_events.lua:1149-1207`).
    -- Stagger the batch and run the rest of the round-win evaluation once it drains. The
    -- state is still PLAY here, so the pops land on the playfield before the blind falls and
    -- the Cash Out panel slides in -- the reference's order. The money rows already have
    -- their own per-row, per-dollar reveal in `update_round_win_eval`.
    if self:begin_joker_emit("on_round_end", ctx) then
        self._pending_round_win_eval = { ctx = ctx, hands_left = hands_left }
        return
    end
    self:_finish_round_win_eval(ctx, hands_left)
end

--- The half of `enter_round_win_after_blind` that runs once the staggered `on_round_end`
--- joker batch has finished: card end-of-round effects, tag payouts, interest, the Cash Out
--- panel and the blind-defeat ladder that reveals it.
---@param ctx table
---@param hands_left number
function Game:_finish_round_win_eval(ctx, hands_left)
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

    -- Interest is based on the balance before blind, hand, Joker and tag rewards.
    -- Gold cards and Gold Seals have already paid during `on_round_end`, matching
    -- the reference's end-of-round card-effect phase.
    local cap_dollars = self:get_interest_round_cap_dollars()
    local interest_count_cap = cap_dollars * 5
    local interest = math.floor(math.min(math.max(0, self.money), interest_count_cap) / 5)
    interest = math.min(interest, cap_dollars)
    if self._deck_no_interest or (self.challenge_modifiers and self.challenge_modifiers.no_interest == true) then interest = 0 end

    self:recycle_full_deck_after_blind_win()

    local hand_bonus = tonumber(self.extra_hand_bonus) or 0
    if self.challenge_modifiers and self.challenge_modifiers.no_extra_hand_money == true then hand_bonus = 0 end
    local discard_bonus = tonumber(self.extra_discard_bonus) or 0

    local blind_pay = math.max(0, math.floor(tonumber(self.current_blind_reward) or 0))

    -- Reveal order for the Cash Out panel. The blind row is its header; zero-value rows are
    -- dropped so the list only ever shows money that was actually paid.
    self._round_win_display_lines = {
        { "Blind reward", blind_pay, "pending", slot = "blind" },
    }
    local function add_display_line(row)
        if (math.floor(tonumber(row[2]) or 0)) <= 0 then return end
        self._round_win_display_lines[#self._round_win_display_lines + 1] = row
    end
    local money_per_hand = math.max(1, hand_bonus)
    add_display_line({ string.format("Remaining Hands ($%d each)", money_per_hand), hands_left * money_per_hand, "pending",
        badge = tostring(hands_left), badge_color = self.C.BLUE })
    add_display_line({ string.format("Remaining Discards ($%d each)", discard_bonus), discard_bonus * self.discards, "pending",
        badge = tostring(self.discards), badge_color = self.C.RED })
    for _, row in ipairs(self._round_win_joker_payout_lines) do
        add_display_line(row)
    end
    add_display_line({ string.format("1 interest per $5 (%d max)", cap_dollars), interest, "pending",
        badge = tostring(interest), badge_color = self.C.ORANGE })
    self._round_win_joker_payout_lines = nil

    self._round_win_line_timer = 0
    self._round_win_lines_revealed = 0
    -- The cashout screen hides consumables outright (see show_consumables in
    -- Game:draw); a panel pulled down during play must not carry invisible,
    -- focusable cards into it.
    if self.consumables_on_bottom == true then
        self:set_consumables_location(false, { silent = true })
    end
    self:begin_blind_defeat(blind_pay)
end

--- Apply an enhancement to the first `count` picked cards, rippling across them.
---
--- Unlike a suit conversion, the enhancement is applied outright rather than at the pinch:
--- `Card:set_enhancement` carries gameplay logic (the Stone Card rank/suit swap), and holding
--- that back for up to half a second would leave the hand readout describing cards that no
--- longer exist. The ripple is the flip, the pop and the `card1` ladder over the top of it.
---@param ord Card[] picked cards in fan order
---@param enhancement string
---@param count number how many of the picks this tarot affects
function Game:convert_enhancement_ripple(ord, enhancement, count)
    local targets = {}
    for i = 1, math.min(count, #ord) do
        ord[i]:set_enhancement(enhancement)
        targets[#targets + 1] = ord[i]
    end
    self:begin_card_ripple(targets, function() end)
end

--- Convert up to three picked cards to one suit, rippling across them.
---
--- The gameplay data changes immediately - scoring, saves and the hand readout all read it -
--- while the drawn face lags behind each card's pinch, which is the same split the reference
--- keeps between `facing` and `sprite_facing`.
---@param ord Card[] picked cards in fan order
---@param suit string
function Game:convert_suit_ripple(ord, suit)
    local targets = {}
    for i = 1, math.min(3, #ord) do
        local cd = ord[i].card_data
        if cd then cd.suit = suit end
        targets[#targets + 1] = ord[i]
    end
    self:begin_card_ripple(targets, function(node)
        node:sync_visual_from_card_data()
    end)
end

--- A used consumable flies to the middle of the playfield, holds there, then comes apart.
---
--- The reference moves the used card to hand centre, waits, resolves it and dissolves it a
--- beat later (`functions/button_callbacks.lua:2155-2260`). The port removed it and relaid the
--- row out in a single frame, so a tarot vanished on the frame it fired and the only thing the
--- player saw of the most deliberate action in the game was the result.
---
--- The effect itself still resolves immediately - deferring it would let the player act during
--- the flight against state that is about to change. What is staged is the card leaving.
local CONSUMABLE_FLY_DURATION = 0.25
local CONSUMABLE_HOLD_DURATION = 0.12
local BOTTOM_SCREEN_CENTRE_X = 160
local BOTTOM_SCREEN_CENTRE_Y = 120
-- The top screen is 400x240 (`platform/ctr/include/common/screen_ext.hpp`); a consumable that
-- was living on the readout has to fly somewhere on the readout.
local TOP_SCREEN_CENTRE_X = 200
local TOP_SCREEN_CENTRE_Y = 120
local TOP_SCREEN_HEIGHT = 240
--- Bottom edge of the readout panel `TopUI:draw` fills (y 4, 104 tall). A card that only passes
--- through screen centre may overlap it; one that is parked there for seconds may not.
local TOP_SCREEN_PANEL_BOTTOM = 108

--- Beat that conversion ripples wait out, so the cards start turning over once the consumable
--- that ordered it has actually arrived rather than while it is still in the air.
---@return number
function Game:consumable_flight_lead()
    return self._consumable_flight and CONSUMABLE_FLY_DURATION or 0
end

---@param node Consumable|nil already unlinked from run state
function Game:begin_consumable_use_flight(node)
    -- One flight at a time. Two consumables used inside the same quarter second (two Planets
    -- off the same hand, a pack that resolves two picks) used to overwrite this slot, and the
    -- node the slot was holding was never handed to `retain_dissolving_node` -- it stayed in
    -- `self.nodes`, parked at screen centre, for the rest of the run. The one already in the
    -- air finishes early rather than being stranded.
    local prev = self._consumable_flight
    if prev then
        self._consumable_flight = nil
        if prev.node and prev.node ~= node then
            self:retain_dissolving_node(prev.node)
        end
    end
    if not node or not node.T then
        if node then self:retain_dissolving_node(node) end
        return
    end
    if node.states then
        node.states.hover.can = false
        node.states.click.can = false
        node.states.drag.can = false
    end
    -- Fly out on whichever screen the card was actually being seen on. Owned consumables render
    -- on the top screen unless they have been pulled down (`TopUI.draw`), and unlinking the node
    -- from `consumable_nodes` drops it out of that loop -- so a card used from the readout used
    -- to reappear on the bottom screen, at a coordinate that meant nothing there, and slide to
    -- the middle of the hand. That teleport between screens is the whole of the "weird".
    node._draw_screen = (self.consumables_on_bottom == true) and "bottom" or "top"
    -- Retarget rather than teleport: the spring carries it in with the overshoot every other
    -- moving thing on the board has.
    local w = (node.VT and node.VT.w or 0) * (node.VT and node.VT.scale or 1)
    local h = (node.VT and node.VT.h or 0) * (node.VT and node.VT.scale or 1)
    if node._draw_screen == "top" then
        node.T.x = TOP_SCREEN_CENTRE_X - w * 0.5
        node.T.y = TOP_SCREEN_CENTRE_Y - h * 0.5
    else
        node.T.x = BOTTOM_SCREEN_CENTRE_X - w * 0.5
        node.T.y = BOTTOM_SCREEN_CENTRE_Y - h * 0.5
    end
    self._consumable_flight = { node = node, phase = "fly", t = 0 }
end

--- Advance the flight, then hand the node to the dissolve list.
---@param dt number real seconds, for the flight itself
---@param scaled_dt number|nil game-speed-scaled seconds, for the hold that follows it
function Game:_update_consumable_flight(dt, scaled_dt)
    local f = self._consumable_flight
    if not f then return end
    if self.STATE == self.STATES.PAUSED then return end
    if f.phase == "fly" then
        f.t = f.t + dt
        if f.t >= CONSUMABLE_FLY_DURATION then
            f.phase = "hold"
            f.t = 0
        end
        return
    end
    f.t = f.t + (tonumber(scaled_dt) or dt)
    if f.t >= (f.hold or CONSUMABLE_HOLD_DURATION) then
        self._consumable_flight = nil
        self:retain_dissolving_node(f.node)
    end
end

--- Retain a node past its removal from run state so it can come apart on screen.
---
--- The hand owns its own dissolve bookkeeping (`Hand:update_card_lifecycles`); this is the
--- equivalent for everything that is not a hand card. Jokers eaten by Gros Michel and used
--- consumables used to be unlinked on the frame they fired, so the only feedback was a crumple
--- cue over a card that had already gone.

--- The reference's default `dissolve_colours` are black/orange/red/gold/joker-grey
--- (`card.lua:2133`) and it always emits; only the tint is ever a caller's choice
--- (`card.lua:1610` sells a joker in gold). The port used to treat a missing colour as
--- "no burst", which meant a joker eaten by Gros Michel came apart in silence while a sold
--- one threw shards - the same event with and without feedback depending on the call site.
--- All five, not just the first: the reference picks each shard's colour out of the whole
--- list (`engine/particles.lua:92`), which is what stops a burst reading as one flat puff.
local DISSOLVE_SHARD_COLOURS = {
    { 0.216, 0.259, 0.267, 1 }, -- G.C.BLACK,      HEX("374244")
    { 0.992, 0.635, 0.000, 1 }, -- G.C.ORANGE,     HEX("fda200")
    { 0.996, 0.373, 0.333, 1 }, -- G.C.RED,        HEX("FE5F55")
    { 0.918, 0.753, 0.345, 1 }, -- G.C.GOLD,       HEX("eac058")
    { 0.749, 0.780, 0.835, 1 }, -- G.C.JOKER_GREY, HEX("bfc7d5")
}

---@param node Moveable|nil already unlinked from run state, still in `self.nodes`
---@param colour table|nil shard tint; defaults to the reference's orange
function Game:retain_dissolving_node(node, colour)
    if not node or not node.begin_lifecycle then
        if node then self:remove(node) end
        return
    end
    -- The reference's `dissolve_colours` drive the shader and the particles from one list
    -- (`sprite.lua:103-104`, `card.lua:2140`), so a joker sold for gold burns gold as well as
    -- throwing gold. Passing the tint only to the shards left every destruction burning the
    -- default black-on-orange whatever it was.
    local burn = (colour and type(colour[1]) == "number") and colour or nil
    node.begin_lifecycle(node, "dissolve", burn)
    -- A ghost keeps the screen its owner row was on. Unlinking the node from `self.jokers` /
    -- `self.consumable_nodes` is what takes it out of `TopUI`'s draw, so without this a joker
    -- eaten off the readout would come apart on the bottom screen instead.
    if node._draw_screen == nil then
        if Joker and node.is and node:is(Joker) then
            node._draw_screen = (self.jokers_on_bottom == true) and "bottom" or "top"
        elseif Consumable and node.is and node:is(Consumable) then
            node._draw_screen = (self.consumables_on_bottom == true) and "bottom" or "top"
        end
    end
    if node.states then
        node.states.hover.can = false
        node.states.click.can = false
        node.states.drag.can = false
    end

    -- Shed for the whole tween rather than in one salvo; `_update_dissolving_nodes` drives it.
    node._dissolve_tint = colour or DISSOLVE_SHARD_COLOURS

    self._dissolving_nodes = self._dissolving_nodes or {}
    self._dissolving_nodes[#self._dissolving_nodes + 1] = node
end

--- Tick retained ghosts and unlink them once they have finished collapsing.
---@param dt number real seconds
function Game:_update_dissolving_nodes(dt)
    local list = self._dissolving_nodes
    if not list then return end
    for i = #list, 1, -1 do
        local node = list[i]
        if node and node._card_lifecycle and node.VT and Particles and Particles.shed_dissolve then
            local vt = node.VT
            local scale = vt.scale or 1
            local w, h = (vt.w or 0) * scale, (vt.h or 0) * scale
            Particles.shed_dissolve(node._card_lifecycle, dt,
                (vt.x or 0) + w * 0.5, (vt.y or 0) + h * 0.5, w, h,
                node._dissolve_tint or DISSOLVE_SHARD_COLOURS)
        end
        if not node or not node._card_lifecycle or node:advance_lifecycle(dt) then
            if node then self:remove(node) end
            table.remove(list, i)
        end
    end
    if #list == 0 then self._dissolving_nodes = nil end
end

--- The mirror of `retain_dissolving_node`: something arriving in the run rather than leaving it.
---
--- Destruction had a tween, a cue and a tinted burst; creation had none of the three. A joker
--- bought in the shop, a consumable pulled out of a pack and a card conjured by a Spectral all
--- simply existed on the next frame, at full size, in silence. The reference runs the dissolve
--- shader backwards for exactly this (`card.lua:2183` `start_materialize`), so the port owes it
--- the same beat in the other direction.
---
--- Shards converge instead of scattering. Same primitive, same count, opposite sign: they start
--- on a ring outside the node and fly inward, arriving as the node reaches full size. That is
--- what distinguishes "coming together" from "coming apart" at 240p, where the tween alone is
--- only a few pixels of scale.
local MATERIALIZE_SHARD_COUNT = 10
--- Ring radius as a multiple of the node's half-diagonal, so the shards start clear of the art
--- whatever size the node is.
local MATERIALIZE_SHARD_SPREAD = 1.35
local MATERIALIZE_SHARD_SPEC = {
    x = 0, y = 0, vx = 0, vy = 0, gravity = 0,
    lifetime = 0, w = 3, h = 3, colour = nil, colours = nil, fade = false, grow = true,
}

--- Tints by set, the way the reference colours a creation by what was created (`G.C.SET`).
--- A Tarot arriving is purple, a Planet blue, a Spectral its pale blue, a Joker red - so the
--- burst says what turned up before the art is legible.
local MATERIALIZE_SET_COLOURS = {
    tarot = { 0.60, 0.36, 0.86, 1 },
    planet = { 0.30, 0.55, 0.92, 1 },
    spectral = { 0.35, 0.70, 0.94, 1 },
    joker = { 0.94, 0.31, 0.31, 1 },
}
--- Anything without a set of its own (a playing card conjured into the deck).
local MATERIALIZE_DEFAULT_COLOUR = { 0.92, 0.92, 0.96, 1 }

--- Tint for a node that is materialising, keyed off whatever the node knows about itself.
---@param node Moveable
---@return table
function Game:materialize_colour_for(node)
    local kind = node and (node.kind or (node.def and node.def.kind))
    return MATERIALIZE_SET_COLOURS[kind]
        or (Joker and node and node.is and node:is(Joker) and MATERIALIZE_SET_COLOURS.joker)
        or MATERIALIZE_DEFAULT_COLOUR
end

--- Whether a node appearing right now is something the player is watching arrive.
---
--- Run setup deals a deck's starting consumables and a save restore rebuilds every owned node;
--- neither is a creation the player sees happen, and bursting on them would flash the board on
--- entry. The states below are the three where a node can appear under the player's eyes.
---@return boolean
function Game:node_creation_animates()
    if self._restoring_run_snapshot == true then return false end
    if self.STAGE ~= self.STAGES.RUN then return false end
    local s = self.STATE
    return s == self.STATES.SELECTING_HAND or s == self.STATES.SHOP
        or s == self.STATES.OPEN_BOOSTER
end

--- Converge a burst onto a node that is materialising.
---
--- Split from `begin_materializing_node` because the hand runs its own lifecycle bookkeeping
--- (`Hand:update_card_lifecycles`) and only wants the burst.
---@param node Moveable|nil
---@param colour table|nil override tint; defaults to the node's set colour
function Game:begin_materialize_burst(node, colour)
    if not node or not self:node_creation_animates() then return end
    if not (Particles and Particles.emit and node.VT) then return end
    local vt = node.VT
    local scale = vt.scale or 1
    local w = (vt.w or 0) * scale
    local h = (vt.h or 0) * scale
    local cx = (vt.x or 0) + w * 0.5
    local cy = (vt.y or 0) + h * 0.5
    local radius = math.sqrt(w * w + h * h) * 0.5 * MATERIALIZE_SHARD_SPREAD
    -- Shards land as the tween finishes, so the burst and the fade-in end together rather than
    -- the shards outliving the thing they were assembling.
    local lifetime = Moveable.MATERIALIZE_DURATION
    -- The hand hands its dissolve palette straight through here, so a list has to be taken
    -- as a list; `emit` then picks one per shard the way the reference does.
    local tint = colour or self:materialize_colour_for(node)
    if type(tint[1]) == "table" then
        MATERIALIZE_SHARD_SPEC.colours, MATERIALIZE_SHARD_SPEC.colour = tint, nil
    else
        MATERIALIZE_SHARD_SPEC.colours, MATERIALIZE_SHARD_SPEC.colour = nil, tint
    end
    MATERIALIZE_SHARD_SPEC.lifetime = lifetime
    for i = 1, MATERIALIZE_SHARD_COUNT do
        -- Evenly spaced around the ring with a jittered radius: an even angle reads as a
        -- deliberate implosion, while a random one clumps and looks like a second scatter.
        local angle = (i / MATERIALIZE_SHARD_COUNT) * math.pi * 2
        local r = radius * (0.8 + love.math.random() * 0.4)
        local sx, sy = math.cos(angle) * r, math.sin(angle) * r
        MATERIALIZE_SHARD_SPEC.x = cx + sx
        MATERIALIZE_SHARD_SPEC.y = cy + sy
        -- Straight-line convergence on the centre over the shard's whole life.
        MATERIALIZE_SHARD_SPEC.vx = -sx / lifetime
        MATERIALIZE_SHARD_SPEC.vy = -sy / lifetime
        Particles.emit(MATERIALIZE_SHARD_SPEC)
    end
end

--- Fade a newly created node in and converge a burst onto it.
---@param node Moveable|nil already linked into run state
---@param colour table|nil override tint; defaults to the node's set colour
---@param timefac number|nil stretch the tween
---@param no_burst boolean|nil mask only; for nodes whose position is not settled yet
function Game:begin_materializing_node(node, colour, timefac, no_burst)
    if not node or not node.begin_lifecycle then return end
    if not self:node_creation_animates() then return end
    local burn1, burn2
    if colour and type(colour[1]) == "number" then burn1, burn2 = colour, nil end
    node:begin_lifecycle("materialize", burn1, burn2, timefac)

    self._materializing_nodes = self._materializing_nodes or {}
    self._materializing_nodes[#self._materializing_nodes + 1] = node

    if not no_burst then self:begin_materialize_burst(node, colour) end
end

--- Tick fade-ins. Unlike `_update_dissolving_nodes` this never unlinks the node: the entry is
--- dropped when the tween runs out and the node carries on as a normal member of the run.
---@param dt number real seconds
function Game:_update_materializing_nodes(dt)
    local list = self._materializing_nodes
    if not list then return end
    for i = #list, 1, -1 do
        local node = list[i]
        if not node or not node._card_lifecycle or node:advance_lifecycle(dt) then
            table.remove(list, i)
        end
    end
    if #list == 0 then self._materializing_nodes = nil end
end

--- The hand level-up flourish: what the player sees when a Planet (or Black Hole) lands.
---
--- The reference hands the top hand-text area over to the hand being levelled and walks it up
--- one slot per beat. `card.lua:1265` points the readout at that hand with its pre-upgrade
--- numbers under a `button` at pitch 0.8; `level_up_hand` then rings `tarot1` three times at
--- 0.9 s spacing, juicing the used card on each, and after each ring pushes one value:
--- mult, then chips, then level (`common_events.lua:464-490`). Each of the first two covers its
--- readout with a green plate carrying the delta - `attention_text` with `cover`
--- (`UI_definitions.lua:883-935`) - and the level slot pops and recolours to its new rung.
--- `card.lua:1267` then blanks the whole area under a `button` at pitch 1.1.
---
--- The port had the three cues and nothing else: no readout, no deltas, no level, and the card
--- dissolved on the first beat, so a Planet read as a card vanishing with a sound.
local HAND_LEVELUP_BEATS = 3
local HAND_LEVELUP_INTERVAL = 0.9
--- `card.lua:1265` waits 0.3 s before the readout populates, then `common_events.lua:469` waits
--- another 0.2 s before the first ring.
local HAND_LEVELUP_LEAD = 0.5
--- `attention_text{hold = 1}` (`common_events.lua:516`), so the mult plate is still up when the
--- chips plate arrives - which is what makes the two read as one climb rather than two events.
local HAND_LEVELUP_COVER_HOLD = 1.0
--- Beat held after the last ring before the readout blanks. The reference's `delay(1.3)` is
--- longer, but it is padding an event queue that has nothing else to do; two thirds of a second
--- is enough to read a level on a 240p screen and keeps the whole flourish inside the ceiling
--- `_update_booster_close` puts on a pack staying open.
local HAND_LEVELUP_TAIL = 0.6
Game.HAND_LEVELUP_DURATION = HAND_LEVELUP_LEAD
    + (HAND_LEVELUP_BEATS - 1) * HAND_LEVELUP_INTERVAL
    + HAND_LEVELUP_TAIL

--- Signed delta between two readout values, as the reference formats it: `+N` for a gain, the
--- bare number for a loss, and the value itself when it is already a string (Black Hole levels
--- every hand, so it has no number to subtract and passes `+` straight through)
--- (`common_events.lua:501-509`).
---@return string
local function levelup_delta(from, to)
    if type(to) ~= "number" or type(from) ~= "number" then return tostring(to) end
    local d = to - from
    if d > 0 then
        -- Whole numbers everywhere except the fractional mult a boss modifier can leave behind.
        if d % 1 == 0 then return "+" .. tostring(math.floor(d)) end
        return string.format("+%.1f", d)
    end
    if d % 1 == 0 then return tostring(math.floor(d)) end
    return string.format("%.1f", d)
end

--- Start the flourish. With no numbers (Black Hole) the readout shows the reference's
--- placeholders instead of a ladder.
---@param hand_name string display name for the hand slot
---@param from_level integer|nil
---@param from_chips number|nil
---@param from_mult number|nil
---@param to_level integer|nil
---@param to_chips number|nil
---@param to_mult number|nil
function Game:begin_hand_levelup_flourish(hand_name, from_level, from_chips, from_mult,
                                          to_level, to_chips, to_mult)
    local numeric = type(from_level) == "number"
    if not numeric then
        from_level, from_chips, from_mult = nil, "...", "..."
        to_level, to_chips, to_mult = "+1", "+", "+"
    end
    self._hand_levelup = {
        t = 0,
        fired = 0,
        hand = hand_name or "",
        -- Currently displayed; each beat swaps one of these for its `to_` counterpart.
        level = from_level,
        chips = from_chips,
        mult = from_mult,
        to_level = to_level,
        to_chips = to_chips,
        to_mult = to_mult,
        chips_delta = levelup_delta(from_chips, to_chips),
        mult_delta = levelup_delta(from_mult, to_mult),
        -- Seconds of plate left over each readout.
        chips_cover = 0,
        mult_cover = 0,
    }
    -- The readout being handed over is its own cue, and it belongs to every caller rather than
    -- to Planets specifically (`card.lua:1265`, `card.lua:1154`, `tag.lua:192`).
    Sfx.play("button", 0.8, 0.7)
    -- Hold the used card for the whole ladder instead of letting it dissolve on the first beat,
    -- so all three juices land on something the player can see. `hold` is measured from the end
    -- of the flight in, so the card comes apart on the frame the readout blanks rather than a
    -- quarter second after it.
    local flight = self._consumable_flight
    if flight then
        flight.hold = Game.HAND_LEVELUP_DURATION - CONSUMABLE_FLY_DURATION
        -- A card parked at the top screen's centre covers the readout panel, and the readout is
        -- the entire point of this flourish. Drop it into the clear strip below the panel; the
        -- quarter-second flights every other consumable makes are short enough that they can go
        -- on crossing it.
        local node = flight.node
        if node and node.T and node._draw_screen == "top" then
            local h = (node.VT and node.VT.h or 0) * (node.VT and node.VT.scale or 1)
            node.T.y = TOP_SCREEN_PANEL_BOTTOM
                + (TOP_SCREEN_HEIGHT - TOP_SCREEN_PANEL_BOTTOM - h) * 0.5
        end
    end
end

--- Advance the level-up flourish.
---@param dt number game-speed-scaled seconds (the reference's `TOTAL` clock, which is what its
--- event queue runs on)
function Game:_update_hand_levelup(dt)
    local f = self._hand_levelup
    if not f then return end
    if self.STATE == self.STATES.PAUSED then return end
    f.t = f.t + dt
    if f.chips_cover > 0 then f.chips_cover = f.chips_cover - dt end
    if f.mult_cover > 0 then f.mult_cover = f.mult_cover - dt end
    while f.fired < HAND_LEVELUP_BEATS
        and f.t >= HAND_LEVELUP_LEAD + f.fired * HAND_LEVELUP_INTERVAL do
        f.fired = f.fired + 1
        Sfx.play("tarot1")
        if f.fired == 1 then
            f.mult = f.to_mult
            f.mult_cover = HAND_LEVELUP_COVER_HOLD
        elseif f.fired == 2 then
            f.chips = f.to_chips
            f.chips_cover = HAND_LEVELUP_COVER_HOLD
        else
            f.level = f.to_level
            -- `update_hand_text{sound = 'button', volume = 0.7, pitch = 0.9}`
            -- (`common_events.lua:486`) rides on top of the third ring.
            Sfx.play("button", 0.9, 0.7)
        end
        local node = self._consumable_flight and self._consumable_flight.node
        if node and node.juice_up then node:juice_up(0.8, 0.5) end
    end
    if f.t >= Game.HAND_LEVELUP_DURATION then
        self._hand_levelup = nil
        -- Blanking the readout is its own cue in the reference (`card.lua:1267`).
        Sfx.play("button", 1.1, 0.7)
    end
end

--- Chips and mult the top readout should show this frame. During a level-up flourish that is
--- the flourish's ladder rather than the selected hand, and either may be a string.
---@return number|string chips, number|string mult
function Game:readout_chips_mult()
    local f = self._hand_levelup
    if f then return f.chips, f.mult end
    -- Picking hand cards inside a booster pack targets a consumable, not a play, so there is no
    -- hand to preview (see `TopUI:draw`).
    if self.STATES and self.STATE == self.STATES.OPEN_BOOSTER then return 0, 0 end
    return tonumber(self.selectedHandChips) or 0, tonumber(self.selectedHandMult) or 0
end

--- Level the top readout should show, or nil for a blank level slot.
---@return integer|string|nil
function Game:readout_hand_level()
    local f = self._hand_levelup
    if f then return f.level end
    if self.STATES and self.STATE == self.STATES.OPEN_BOOSTER then return nil end
    if not self.selectedHand or self.selectedHand == -1 then return nil end
    return self.selectedHandLevel or 1
end

--- Beat between cards in a conversion ripple. The reference queues one `after` event per card
--- at this delay, so they land in sequence rather than together (`card.lua:1108`).
local CARD_RIPPLE_INTERVAL = 0.15

--- Flip a run of cards one after another, applying a change to each at the point it is
--- edge-on.
---
--- Suit and enhancement tarots are the signature "ripple" of the original: The Sun sweeps
--- across the picked cards, each one turning over with a descending `card1` and a pop
--- (`reference/card.lua:1105-1110`). The port applied the change and refreshed the sprite in
--- one frame, so the pips simply blinked to their new suit under a single `tarot1`.
---
---@param nodes Card[] cards to turn over, in the order they should ripple
---@param apply fun(node: Card, index: number) the mutation, run when that card is edge-on
function Game:begin_card_ripple(nodes, apply)
    if type(nodes) ~= "table" or #nodes == 0 or type(apply) ~= "function" then return end
    local n = #nodes
    -- Wait for the consumable that ordered this to reach the middle of the board before the
    -- cards start turning over, the way the reference sits on `delay(0.4)` first
    -- (`card.lua:1101`). Zero when nothing is in flight.
    local lead = self:consumable_flight_lead()
    local queue = {}
    for i = 1, n do
        queue[i] = {
            node = nodes[i],
            at = lead + CARD_RIPPLE_INTERVAL * i,
            -- Reference `card.lua:1107`: a descending ladder across the run.
            pitch = 1.15 - (i - 0.999) / math.max(0.002, n - 0.998) * 0.3,
            index = i,
        }
    end
    self._card_ripple = { t = 0, next = 1, queue = queue, apply = apply }
end

--- Advance a conversion ripple.
---@param dt number real seconds
function Game:_update_card_ripple(dt)
    local rip = self._card_ripple
    if not rip then return end
    if self.STATE == self.STATES.PAUSED then return end

    rip.t = rip.t + dt
    while rip.next <= #rip.queue and rip.t >= rip.queue[rip.next].at do
        local entry = rip.queue[rip.next]
        local node = entry.node
        rip.next = rip.next + 1
        if node then
            local apply = rip.apply
            local index = entry.index
            -- The change lands at the pinch, so the old face is never seen turning into the
            -- new one - the same split the reference keeps between `facing` and `sprite_facing`.
            if node.start_flip then
                node:start_flip(function() apply(node, index) end)
            else
                apply(node, index)
            end
            if node.juice_up then node:juice_up(0.3, 0.3) end
            Sfx.play("card1", entry.pitch)
        end
    end

    if rip.next > #rip.queue then self._card_ripple = nil end
end

--- Announce an edition the moment its card becomes visible.
---
--- `Card:set_edition` never sets an edition silently: it queues an event that juices the
--- card and plays the edition's own sting 0.2 s later, holding the controller for the
--- duration (`reference/Balatro/card.lua:430-452`). A shop shelf full of editioned cards
--- therefore announces itself card by card rather than all at once, which is what makes a
--- polychrome offer register before the player has read a single price.
---
--- The port has no event manager, so this is the same shape as `begin_card_ripple`: a
--- queue drained against real time from `update`.
local EDITION_REVEAL_DELAY = 0.2
local EDITION_REVEAL_STAGGER = 0.28

---@param nodes table[] display nodes carrying a non-base edition, in shelf order
function Game:begin_edition_reveals(nodes)
    if self._suppress_edition_reveals then return end
    if type(nodes) ~= "table" or #nodes == 0 then return end
    local queue = self._edition_reveals and self._edition_reveals.queue or {}
    -- A reveal already in flight keeps its clock; new cards queue behind it so two
    -- stings never land on the same frame.
    local base = 0
    for _, entry in ipairs(queue) do
        if entry.at > base then base = entry.at end
    end
    if #queue == 0 then base = EDITION_REVEAL_DELAY - EDITION_REVEAL_STAGGER end
    for _, node in ipairs(nodes) do
        base = base + EDITION_REVEAL_STAGGER
        queue[#queue + 1] = { at = base, node = node, edition = node.edition_reveal_pending }
    end
    self._edition_reveals = self._edition_reveals or { t = 0, next = 1 }
    self._edition_reveals.queue = queue
end

--- Drain the reveal queue: the reference's `juice_up(1, 0.5)` plus the edition's sting.
---@param dt number real seconds
function Game:_update_edition_reveals(dt)
    local rev = self._edition_reveals
    if not rev then return end
    if self.STATE == self.STATES.PAUSED then return end

    -- A shop shelf is built while the panel is still sliding in and its nodes are
    -- hidden (`shop_contents_hidden`). Announcing a card the player cannot see yet puts
    -- the sting ahead of the reveal, so the clock holds until the card is on screen.
    local head = rev.queue[rev.next]
    local head_node = head and head.node
    if head_node and head_node.states and head_node.states.visible == false then return end

    rev.t = rev.t + dt
    while rev.next <= #rev.queue and rev.t >= rev.queue[rev.next].at do
        local entry = rev.queue[rev.next]
        rev.next = rev.next + 1
        local node = entry.node
        if node then
            -- Reference `card.lua:441`.
            if node.juice_up then node:juice_up(1, 0.5) end
            node.edition_reveal_pending = nil
        end
        if Joker and Joker.play_edition_reveal_sfx then
            Joker.play_edition_reveal_sfx(entry.edition)
        end
    end

    if rev.next > #rev.queue then self._edition_reveals = nil end
end

--- Queue a reveal for a single node that has just been given an edition (Aura, Wheel of
--- Fortune, a Negative Tag), matching the shop path.
---@param node table|nil
---@param edition string|nil
function Game:announce_edition(node, edition)
    local ed = Joker and Joker.normalize_edition and Joker.normalize_edition(edition)
        or edition
    if not ed or ed == "base" then return end
    if not node then
        if not self._suppress_edition_reveals and Joker and Joker.play_edition_reveal_sfx then
            Joker.play_edition_reveal_sfx(ed)
        end
        return
    end
    node.edition_reveal_pending = ed
    self:begin_edition_reveals({ node })
end

--- The beat between clearing a blind and the Cash Out panel arriving.
---
--- The reference does not cut straight to the round eval: it holds for
--- `1.3*min(dollars+2,7)/2*0.15 + 0.5` and defeats the blind inside that window
--- (`functions/state_events.lua:1148-1154`), so a fatter payout lingers longer. The defeat
--- itself rings out a descending ladder of `cancel` pings, one per `dollars+2` up to seven,
--- capped off by a `whoosh2` (`blind.lua:303-309`). The port used to skip all of this and
--- slide the panel in on a flat quarter second, which is why clearing a boss felt abrupt.
---@param blind_pay number the blind's own reward, which sets both the hold and the ping count
function Game:begin_blind_defeat(blind_pay)
    local dollars = math.max(0, math.floor(tonumber(blind_pay) or 0))
    -- Reference `blind.lua:83`.
    local pings = math.min(dollars + 2, 7)
    local hold = 1.3 * pings / 2 * 0.15 + 0.5

    local schedule = {}
    for i = 1, pings do
        -- Reference `blind.lua:305`, at the reference's default `dissolve_time` of 1.
        schedule[i] = {
            at = (0.15 - 0.01 * pings) * i,
            pitch = 0.8 - 0.05 * i,
            -- The reference caps the closing whoosh at the sixth ping, so a short ladder
            -- never gets one (`blind.lua:308`).
            whoosh = (i == math.min(pings + 1, 6)),
        }
    end

    self._blind_defeat = { t = 0, hold = hold, next_ping = 1, pings = schedule }
end

--- Advance the defeat hold, ring its pings, then hand off to the Cash Out slide.
---@param dt number real seconds
function Game:_update_blind_defeat(dt)
    local d = self._blind_defeat
    if not d then return end
    -- Same rule as the scene slides: this commits run state, so leaving the round abandons it.
    if self.STATE ~= self.STATES.SELECTING_HAND then
        self._blind_defeat = nil
        return
    end
    if self.STATE == self.STATES.PAUSED then return end

    d.t = d.t + dt
    while d.next_ping <= #d.pings and d.t >= d.pings[d.next_ping].at do
        local p = d.pings[d.next_ping]
        Sfx.play("cancel", p.pitch, 1)
        if p.whoosh then Sfx.play("whoosh2", 0.7, 0.42) end
        d.next_ping = d.next_ping + 1
    end

    if d.t < d.hold then return end
    self._blind_defeat = nil
    self:set_state(self.STATES.ROUND_EVAL)
    -- The panel slides up and lands with a jiggle and cardFan2 (see _update_scene_transitions).
    self._round_eval_slide = { mode = "in", t = 0 }
end

--- Per-dollar reveal cadence for a cash-out row (`common_events.lua:1043-1046`): the tick
--- tightens as the payout grows so a big row still finishes in a couple of seconds.
local function round_win_dollar_interval(amount)
    if amount > 20 then return 0.05 end
    if amount > 9 then return 0.08 end
    return 0.18
end

--- Reveal the next cash-out line. Rewards are credited together when Cash Out is confirmed.
--- A normal row starts a per-dollar count (`common_events.lua:1043-1062`, one coin3 per $);
--- a payout past the reference's 60 collapses to its full amount with the two-part total cue.
function Game:_reveal_one_round_win_line()
    local lines = self._round_win_display_lines
    if not lines or #lines == 0 then return end
    local i = (self._round_win_lines_revealed or 0) + 1
    if i > #lines then return end
    self._round_win_lines_revealed = i
    -- Each row's label reveals letter by letter as it lands, the way every row of the
    -- reference's cash-out is a DynaText (`common_events.lua:927+`). Cash Out is a screen the
    -- player reads at leisure, so text sitting dead still there is unusually noticeable.
    self._round_win_row_dyna = self._round_win_row_dyna or {}
    local dyna = self._round_win_row_dyna[i]
    if not dyna then
        dyna = DynaText.new({ pop_on_change = true })
        self._round_win_row_dyna[i] = dyna
    end
    DynaText.pop_in(dyna)
    local amount = math.floor(tonumber(lines[i] and lines[i][2]) or 0)
    -- Row pitch ladder: 0.95 + 0.06 per row (`state_events.lua:1099-1180`).
    local pitch = 0.95 + 0.06 * (i - 1)
    if Sfx and Sfx.play then
        -- Each row lands on `cancel` at the ladder pitch plus a highlight ping
        -- (`common_events.lua:1015-1016`). This rang `coin1` at a flat pitch, which both
        -- pre-empted the cash-out coins and lost the rising ladder.
        Sfx.play("cancel", pitch)
        Sfx.play("highlight1", 1.5 * pitch, 0.2)
    end
    if amount > 60 then
        if Sfx and Sfx.play then
            -- `common_events.lua:1033-1034`: the collapsed total's two-part cue.
            Sfx.play("coin3", 0.9 + 0.2 * sfx_jitter(), 0.7)
            Sfx.play("coin6", 1.3, 0.8)
        end
    elseif amount > 0 then
        self._round_win_row_tick = {
            index = i,
            shown = 0,
            total = amount,
            timer = 0,
            interval = round_win_dollar_interval(amount),
        }
    end
end

--- Dollars currently visible for a payout row: partial while its count is ticking, full after.
function Game:round_win_row_display_amount(reveal_index, row)
    local tick = self._round_win_row_tick
    if tick and tick.index == reveal_index then return tick.shown end
    return math.floor(tonumber(row and row[2]) or 0)
end

--- Credit every listed reward when Cash Out is confirmed, including unrevealed rows.
function Game:flush_round_win_pending_payouts()
    local lines = self._round_win_display_lines
    if not lines then return end
    for i = 1, #lines do
        local row = lines[i]
        if row[3] == "pending" then
            local amt = math.floor(tonumber(row[2]) or 0)
            if amt ~= 0 then
                self.money = (tonumber(self.money) or 0) + amt
            end
        end
    end
    self._round_win_lines_revealed = #lines
    self._round_win_row_tick = nil
end

function Game:update_round_win_eval(dt)
    local lines = self._round_win_display_lines
    if not lines or #lines == 0 then return end
    -- Rows wait for the panel to land, as the reference starts `evaluate_round` only once
    -- its round-eval UIBox settles (`game.lua:3296-3330`).
    if self._round_eval_slide then return end
    -- A row's dollar count holds the queue: the next row waits for the last tick, matching
    -- the reference's chained per-dollar events (`common_events.lua:1043-1062`).
    local tick = self._round_win_row_tick
    if tick then
        tick.timer = tick.timer + dt
        while tick.timer >= tick.interval and tick.shown < tick.total do
            tick.timer = tick.timer - tick.interval
            tick.shown = tick.shown + 1
            if Sfx and Sfx.play then
                Sfx.play("coin3", 0.9 + 0.2 * sfx_jitter(), 0.55)
            end
        end
        if tick.shown >= tick.total then
            self._round_win_row_tick = nil
            self._round_win_line_timer = 0
        end
        return
    end
    local revealed = self._round_win_lines_revealed or 0
    if revealed >= #lines then return end
    self._round_win_line_timer = (self._round_win_line_timer or 0) + dt
    if self._round_win_line_timer >= ROUND_WIN_LINE_DELAY then
        self._round_win_line_timer = self._round_win_line_timer - ROUND_WIN_LINE_DELAY
        self:_reveal_one_round_win_line()
    end
end

function Game:enter_shop_after_blind()
    self:set_state(self.STATES.SHOP)
    self:init_shop_gamepad_nav()
    self.shop_reroll_count = 0
    self.shop_free_rerolls_used = 0
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
    -- Pack and voucher atlases otherwise load lazily on the first shop draw,
    -- and that stall lands inside the slide-in and eats most of it.
    self:ensure_asset_atlas_loaded("Booster")
    self:ensure_asset_atlas_loaded("Voucher")
    self._shop_slide = { mode = "in", t = 0 }
end

function Game:continue_from_round_win()
    if Sfx and Sfx.play then
        -- Reference `functions/button_callbacks.lua:2945`.
        Sfx.play("coin7")
    end
    self:flush_round_win_pending_payouts()
    self._round_win_display_lines = nil
    self._round_win_lines_revealed = nil
    self._round_win_line_timer = nil
    self._round_win_row_tick = nil
    -- Ante 8 boss beaten: show You Win before the shop (Endless continues into shop).
    -- Ante already stepped when the Boss fell, so the winning run sits on 9 here.
    if self._last_completed_blind_was_boss and (tonumber(self.ante) or 1) > 8 and not self._endless_mode then
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
    self:ensure_victory_progress_recorded()
    -- Reference `functions/state_events.lua:1-43` reserves this cue for
    -- `win_game`, which is reached only after defeating the Ante 8 Boss.
    if Sfx and Sfx.play then Sfx.play("win") end
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
    self:ensure_victory_progress_recorded()
    self:save_you_win_run()
    self._pause_prev_state = nil
    self._pause_save_error = nil
    self:enter_main_menu()
    MainMenuUI.open_deck_select(self)
end

function Game:continue_from_you_win_main_menu()
    -- Persist the won run so Continue Run can return to the You Win screen.
    self:ensure_victory_progress_recorded()
    self:save_you_win_run()
    self:enter_main_menu()
end

function Game:continue_from_you_win_endless()
    self:ensure_victory_progress_recorded()
    self._endless_mode = true
    self:enter_shop_after_blind()
end

function Game:do_random(min,max,goal,key)
    local g = goal or 1
    local oops = self:count_jokers_with_id("j_oops")
    if oops > 0 then
        -- Every copy doubles all probabilities, rather than adding one winning face
        -- (reference card.lua:608-611). Keep the base goal as the first winning face
        -- and wrap at the range boundary so every legal goal doubles uniformly.
        local outcomes = max - min + 1
        local winning_faces = math.min(outcomes, 2 ^ oops)
        local roll = key and self:random(key, min, max) or math.random(min,max)
        return ((roll - g) % outcomes) < winning_faces
    else
        return (key and self:random(key, min, max) or math.random(min,max)) == g
    end

end

--- A guaranteed edition roll, weighted the way the reference weights one.
---
--- `poll_edition(key, nil, _no_neg, _guaranteed)` (`functions/common_events.lua:2055-2067`)
--- is not uniform: at the guaranteed tier the bands are Polychrome 15%, Holographic 35%,
--- Foil 50%. Wheel of Fortune and Aura both draw from it, and rolling 1-in-3 instead made
--- Polychrome — the strongest of the three — more than twice as likely as it should be.
---@param stream string named RNG stream, so seeded runs stay reproducible
---@return string "foil" | "holo" | "polychrome"
function Game:poll_guaranteed_edition(stream)
    local roll = self:random(stream)
    if roll > 1 - 0.006 * 25 then return "polychrome" end
    if roll > 1 - 0.02 * 25 then return "holo" end
    return "foil"
end

--- Owned Jokers that carry no edition yet — the pool Wheel of Fortune, Hex and Ectoplasm
--- draw their target from (`card.lua:4209-4223`, filter `v.ability.set == 'Joker' and
--- (not v.edition)`). Picking from every Joker instead let the Wheel overwrite a Negative
--- and silently cost the player a Joker slot.
---@return table[] nodes, number[] indices parallel lists, both empty when none qualify
function Game:editionless_jokers()
    local nodes, indices = {}, {}
    for i, j in ipairs(self.jokers or {}) do
        local ed = Joker and Joker.normalize_edition(j and j.edition) or nil
        if j and (ed == nil or ed == "base") then
            nodes[#nodes + 1] = j
            indices[#indices + 1] = i
        end
    end
    return nodes, indices
end

--- Remove an owned Joker.
---
--- `dissolve` is opt-in rather than the default because most callers are not a destruction the
--- player is meant to watch: selling hands the card to the shop, and loading or resetting a run
--- tears the whole row down at once. Only something actually eating a Joker asks for the ghost.
---@param index number
---@param force boolean|nil ignore the eternal sticker
---@param dissolve boolean|nil retain the node on screen while it collapses
---@param dissolve_colour table|nil shard tint for that collapse
function Game:remove_owned_joker_at(index, force, dissolve, dissolve_colour)
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
    if dissolve then
        -- Already out of run state, so nothing reads it any more; the node just plays out.
        self:retain_dissolving_node(joker, dissolve_colour)
    else
        self:remove(joker)
    end
    self:refresh_joker_capacity_from_negatives()
    if #(self.jokers or {}) == 0 and self.jokers_on_bottom then
        self:set_jokers_location(false)
    end
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
    -- The shelf node the purchase is taking the place of, read before the removal below so the
    -- new node can start where it sat.
    local shelf = self.shop_offer_nodes and self.shop_offer_nodes[slot_index]
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
        ok = self:add_joker_by_def(offer.id, create_params, shelf) and true or false
    elseif k == "tarot" or k == "planet" or k == "spectral" then
        local params = offer.edition and { edition = offer.edition } or nil
        if not self:can_add_consumable(params) then return false end
        ok = self:add_consumable(offer.id, params, shelf)
    elseif k == "playing_card" then
        ok = self:_deck_inject_playing_card(offer.card_data)
    else
        return false
    end

    if not ok then return false end

    self.money = (tonumber(self.money) or 0) - price
    self:increment_challenge_inflation()
    self:_play_shop_buy_sfx()
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
    self:increment_challenge_inflation()
    self:_play_shop_buy_sfx()
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
    -- The reference sells a joker with a pop and a gold dissolve, not an instant removal
    -- (`card.lua:1590-1612`). The sale is the point of the shop loop; it should have weight.
    if joker and joker.juice_up then joker:juice_up(0.3, 0.4) end
    joker = self:remove_owned_joker_at(index, false, true, self.C and self.C.GOLD)
    if not joker then return false end
    local value = tonumber(joker.sell_cost) or 0
    self.money = (tonumber(self.money) or 0) + value
    local duplicated_from_invisible = false
    if invisible_ready and type(self.jokers) == "table" and #self.jokers > 0 then
        local src = self.jokers[self:random("invisible", 1, #self.jokers)]
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
    -- The round is over either way - Mr. Bones' rescue or the game over - and `Blind:defeat`
    -- runs on both paths in the reference (`blind.lua:338`).
    self:restore_joker_facing()
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
        self:remove_owned_joker_at(mr_bones_index, true, true)
        if Sfx and Sfx.play then
            -- `card.lua:3047-3053`: tarot1, then the dissolve's own crumple. `slice1` is
            -- Ceremonial Dagger's cue and nothing else's.
            Sfx.play("tarot1")
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
    -- Descending sting, not the generic back/close ping. The reference also jiggles the
    -- room by 3 when the run dies (`game.lua:3601`).
    self:shake(3)
    if Sfx and Sfx.play then
        Sfx.play("negative", 0.5, 0.7)
        Sfx.play("whoosh2", 0.9, 0.7)
    end
    self:clear_run_snapshot()
    self:add_career_stat("c_losses", 1)
    self:record_run_high_scores()
    if type(self.career_stats) == "table" then
        self.career_stats.c_current_streak = 0
    end
    self:check_unlock("career_stat")
    self:set_state(self.STATES.GAME_OVER)
    self._game_over_slide = { mode = "in", t = 0 }
    GameOverUI.begin_title_pop()
end

function Game:refocus_after_bottom_panel_closed(closed_layer)
    if self:get_gamepad_focus_layer() ~= closed_layer then return end

    if closed_layer == "jokers" and self.consumables_on_bottom and #(self.consumables or {}) > 0 then
        self:set_gamepad_focus_layer("consumables")
        return
    end
    if closed_layer == "consumables" and self.jokers_on_bottom and #(self.jokers or {}) > 0 then
        self:set_gamepad_focus_layer("jokers")
        return
    end

    if self.STATE == self.STATES.SHOP then
        self:set_gamepad_shop_focus()
    elseif self.STATE == self.STATES.OPEN_BOOSTER then
        if self:is_booster_hand_mode() then
            self:set_gamepad_focus_layer("hand")
        else
            self:set_gamepad_focus_layer("booster")
        end
    elseif self.STATE == self.STATES.SELECTING_HAND then
        self:set_gamepad_focus_layer("hand")
    else
        self._gamepad_focus_layer = "hand"
        self._joker_focus_index = nil
        self.active_tooltip_joker = nil
        self._consumable_focus_index = nil
        self.active_tooltip_consumable_index = nil
    end
end

function Game:set_jokers_location(on_bottom)
    if on_bottom == true and #(self.jokers or {}) == 0 then return end
    if self.jokers_on_bottom == (on_bottom == true) then return end
    local to_bottom = on_bottom == true

    if to_bottom then
        self:clear_bottom_tooltips()
    end

    -- Toggling again mid-slide must spring from wherever the cards currently are,
    -- not teleport them back to the staging position.
    local was_sliding = self.jokers_sliding == true

    self._joker_swap_pick_index = nil
    self.jokers_on_bottom = to_bottom
    if not to_bottom then
        self.active_tooltip_joker = nil
        self:refocus_after_bottom_panel_closed("jokers")
    end
    self:recompute_joker_slot_layout()
    self:recompute_consumable_slot_layout()
    self:sync_jokers_interactivity()
    self:_apply_joker_layout()
    if self.consumables_on_bottom then
        self:_apply_consumable_layout()
    end

    self.jokers_sliding = true
    self.jokers_slide_time_left = 0.6

    -- Panel slide cue: rising when pulled down, falling when sent back up.
    if Sfx and Sfx.play then
        Sfx.play("whoosh1", to_bottom and 1.25 or 0.85, 0.45)
    end

    if self.jokers and not was_sliding then
        local start_y
        if to_bottom then
            local s = self.joker_slot_scale_bottom or 1
            local slot_h = self.joker_slot_h or 94
            local h = slot_h * s
            local delta_y = (slot_h * s * (1 - s)) / 2
            start_y = -(h + 60) - delta_y
        else
            local s = self.joker_slot_scale_bottom or 1
            local slot_h = self.joker_slot_h or 94
            local h = slot_h * s
            local delta_y = (slot_h * s * (1 - s)) / 2
            start_y = (self.joker_slot_y_bottom or BOTTOM_INVENTORY_Y) + h + 60 - delta_y
        end

        for _, j in ipairs(self.jokers) do
            if j and j.VT then
                if j.T then
                    j.VT.x = j.T.x
                    j.VT.scale = j.T.scale
                end
                j.VT.y = start_y
            end
        end
    end
end

function Game:set_consumables_location(on_bottom, opts)
    if on_bottom == true and #(self.consumables or {}) == 0 then return end
    if self.consumables_on_bottom == (on_bottom == true) then return end
    local to_bottom = on_bottom == true

    if to_bottom then
        self:clear_bottom_tooltips()
    end

    -- Same mid-slide rule as set_jokers_location: don't teleport a moving row.
    local was_sliding = self.consumables_sliding == true

    self.consumables_on_bottom = to_bottom
    if not to_bottom then
        self.active_tooltip_consumable_index = nil
        self:refocus_after_bottom_panel_closed("consumables")
    end
    self:recompute_joker_slot_layout()
    self:recompute_consumable_slot_layout()
    self:sync_consumables_interactivity()
    self:_apply_consumable_layout()
    if self.jokers_on_bottom then
        self:_apply_joker_layout()
    end

    self.consumables_sliding = true
    self.consumables_slide_time_left = 0.6

    if Sfx and Sfx.play and not (opts and opts.silent) then
        Sfx.play("whoosh1", to_bottom and 1.25 or 0.85, 0.45)
    end

    if self.consumable_nodes and not was_sliding then
        local s = self.consumable_slot_scale_bottom or 1
        local slot_h = self.consumable_slot_h or 95
        local h = slot_h * s
        local delta_y = (slot_h * s * (1 - s)) / 2
        local start_y
        if to_bottom then
            start_y = -(h + 60) - delta_y
        else
            start_y = (self.consumable_slot_y_bottom or BOTTOM_INVENTORY_Y) + h + 60 - delta_y
        end
        for _, c in ipairs(self.consumable_nodes) do
            if c and c.VT then
                if c.T then
                    c.VT.x = c.T.x
                    c.VT.scale = c.T.scale
                end
                c.VT.y = start_y
            end
        end
    end
end

--- Gate for pulling an inventory panel DOWN. main.lua wires the shoulder buttons to the
--- toggles before any per-state routing, so every screen where the panels are hidden or
--- would fight the UI has to be refused here. Closing is never gated by this (a panel
--- that is already down must always be dismissable).
---@param kind string "jokers" | "consumables"
function Game:can_pull_panel(kind)
    if self:scene_transition_active() then return false end
    local s = self.STATE
    if s == self.STATES.MENU or s == self.STATES.PAUSED
        or s == self.STATES.GAME_OVER or s == self.STATES.YOU_WIN then
        return false
    end
    -- draw() hides consumable nodes outright on the cashout screen (see
    -- show_consumables in Game:draw), so pulling them down there would hand
    -- gamepad focus to invisible cards.
    if kind == "consumables" and s == self.STATES.ROUND_EVAL then
        return false
    end
    -- Mid-scoring the jokers are animating on the top readout; yanking them down
    -- mid-ladder detaches them from the score events they're juicing for.
    if self.hand and self.hand.is_scoring_active and self.hand:is_scoring_active() then
        return false
    end
    return true
end

--- Shoulder presses on screens that don't show the panels at all (pause overlay,
--- menus, end-of-run) must be inert in BOTH directions, not just for opening.
function Game:_panel_toggle_blocked()
    if self._deck_view_open then return true end
    local s = self.STATE
    return s == self.STATES.MENU or s == self.STATES.PAUSED
        or s == self.STATES.GAME_OVER or s == self.STATES.YOU_WIN
end

function Game:toggle_jokers_pulled()
    if self:_panel_toggle_blocked() then return false end
    local to_bottom = not (self.jokers_on_bottom == true)
    if to_bottom then
        if not self:can_pull_panel("jokers") then return false end
        if #(self.jokers or {}) == 0 then
            -- Quiet refusal beats a dead button.
            if Sfx and Sfx.play then Sfx.play("cancel", 1, 0.25) end
            return false
        end
    end
    self:set_jokers_location(to_bottom)
    if to_bottom then
        self._gamepad_bottom_layer = "jokers"
        self:set_gamepad_focus_layer("jokers")
    end
    return true
end

function Game:toggle_consumables_pulled()
    if self:_panel_toggle_blocked() then return false end
    local to_bottom = not (self.consumables_on_bottom == true)
    if to_bottom then
        if not self:can_pull_panel("consumables") then return false end
        if #(self.consumables or {}) == 0 then
            if Sfx and Sfx.play then Sfx.play("cancel", 1, 0.25) end
            return false
        end
    end
    self:set_consumables_location(to_bottom)
    if to_bottom then
        self:set_gamepad_focus_layer("consumables")
    end
    return true
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

--- Move a joker to a new index and let the row spring into the new arrangement.
---
--- Nothing here snaps `VT` to `T`. The reference reorders by handing the card area a new order
--- and letting every card's own spring carry it (`cardarea.lua:130`), which is what makes a
--- swap read as the neighbours stepping aside. The port used to teleport the whole row on the
--- frame the order changed, so a reorder was a jump cut.
---@param from_idx integer
---@param to_idx integer
---@return boolean moved
function Game:move_joker_to_index(from_idx, to_idx)
    if not self.jokers then return false end
    from_idx = math.floor(tonumber(from_idx) or 0)
    to_idx = math.floor(tonumber(to_idx) or 0)
    local n = #self.jokers
    if from_idx < 1 or to_idx < 1 or from_idx > n or to_idx > n then return false end
    if from_idx == to_idx then return false end
    table.insert(self.jokers, to_idx, table.remove(self.jokers, from_idx))
    self:_apply_joker_layout()
    return true
end

--- Exchange two jokers. This is the pick-then-place gamepad gesture
--- (`Game:gamepad_joker_press_a`), which genuinely swaps rather than reinserting. It springs for
--- the same reason `move_joker_to_index` does.
---@param from_idx integer
---@param to_idx integer
---@return boolean swapped
function Game:swap_jokers_at_indices(from_idx, to_idx)
    if not self.jokers then return false end
    from_idx = math.floor(tonumber(from_idx) or 0)
    to_idx = math.floor(tonumber(to_idx) or 0)
    local n = #self.jokers
    if from_idx < 1 or to_idx < 1 or from_idx > n or to_idx > n then return false end
    if from_idx == to_idx then return false end
    self.jokers[from_idx], self.jokers[to_idx] = self.jokers[to_idx], self.jokers[from_idx]
    self:_apply_joker_layout()
    return true
end

--- Index of a joker in the owned row, or nil.
---@param joker_node Joker|nil
---@return integer|nil
function Game:owned_joker_index(joker_node)
    if not joker_node or not self.jokers then return nil end
    for i, j in ipairs(self.jokers) do
        if j == joker_node then return i end
    end
    return nil
end

--- Reorder live while a joker is being dragged.
---
--- Called every touch move: the dragged card's own centre picks the slot, and if that is not
--- where it currently sits the row is reshuffled around it there and then. The other jokers
--- spring aside under the finger the way they do in the base game, so by the time the player
--- lets go the arrangement they are looking at is the one they get. The dragged node is left
--- alone -- `Moveable:touchmoved` owns its `VT` until release.
---@param joker_node Joker|nil
---@return boolean moved this frame
function Game:update_joker_drag_reorder(joker_node)
    if not joker_node or not self.jokers_on_bottom then return false end
    local from_idx = self:owned_joker_index(joker_node)
    if not from_idx then return false end
    local vt = joker_node.VT
    if not vt then return false end
    local centre_x = (vt.x or 0) + (vt.w or 0) * (vt.scale or 1) * 0.5
    local to_idx = self:_joker_nearest_slot_idx(centre_x)
    if to_idx == from_idx then return false end
    if not self:move_joker_to_index(from_idx, to_idx) then return false end
    -- The click the reference plays whenever a card lands in a new place in an area
    -- (`cardarea.lua:140`).
    if Sfx and Sfx.play then Sfx.play("cardSlide1", 1.05, 0.5) end
    self.active_tooltip_joker = nil
    return true
end

--- Settle a dragged joker. The order is already correct -- `update_joker_drag_reorder` has been
--- keeping it that way -- so this only has to make sure the final resting slot matches where the
--- card was let go, for the case where the drag ended between moves.
---@param joker_node Joker|nil
---@param release_x number
---@return boolean reordered
function Game:try_reorder_joker_after_drag(joker_node, release_x)
    if not joker_node or not self.jokers or not self.jokers_on_bottom then return false end
    local from_idx = self:owned_joker_index(joker_node)
    if not from_idx then return false end
    local to_idx = self:_joker_nearest_slot_idx(release_x)
    return self:move_joker_to_index(from_idx, to_idx)
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
    self._joker_drag_reordered = false
    if node.touchpressed then
        node:touchpressed(id, x, y)
    end
    self.dragging = node
    self:move_to_front(node)
end

--- Touch routing for the pulled-down inventory rows, ahead of every per-state handler.
---
--- The trays are drawn over everything else on the bottom screen, so they own every touch that
--- lands inside them. Without this the tap falls through to whatever is underneath - a hand
--- card, or a pack choice card while a Spectral pack is open - and selling a joker from a row
--- pulled down over the pack is impossible.
---
--- A touch inside a tray but not on a card is swallowed rather than passed on, for the same
--- reason: the tray is opaque, and tapping something you cannot see is never intended.
---@return boolean True if the touch was consumed.
function Game:handle_bottom_panel_touch(id, x, y)
    local joker_rect = self:get_bottom_panel_rect("jokers")
    local consumable_rect = self:get_bottom_panel_rect("consumables")
    local in_jokers = joker_rect ~= nil and self:_point_in_rect_simple(x, y, joker_rect)
    local in_consumables = consumable_rect ~= nil and self:_point_in_rect_simple(x, y, consumable_rect)
    if not in_jokers and not in_consumables then return false end

    -- Mid-scoring the row is juicing along with the score events; picking a card up out of it
    -- there is what `can_pull_panel` already refuses to let you set up. The tray still eats the
    -- touch, since it is still covering the hand.
    if self:is_hand_scoring_active() then
        self.touch_start_x = x
        self.touch_start_y = y
        return true
    end

    if in_jokers then
        local joker = self:get_owned_joker_at(x, y)
        if joker then
            begin_node_drag(self, id, x, y, joker)
            return true
        end
    end
    if in_consumables then
        local node = self:get_owned_consumable_at(x, y)
        if node then
            begin_node_drag(self, id, x, y, node)
            return true
        end
    end

    self.touch_start_x = x
    self.touch_start_y = y
    return true
end

--- Touch handling for the settings panel. Extracted from `touchpressed` because the
--- panel is now reachable from two places: paused mid-run, and from the main menu
--- via `open_settings_from_menu`. The pause page itself stays inline below.
---@param x number
---@param y number
function Game:handle_pause_settings_touch(x, y)
        if self._pause_settings_tab == "performance" then
            for _, r in ipairs(self._perf_toggle_rects or {}) do
                if self:_point_in_rect_simple(x, y, r) then
                    PerformanceLab.toggle(r.experiment_id)
                    RenderProfiler.reset()
                    return
                end
            end
            if self._perf_reset_rect and self:_point_in_rect_simple(x, y, self._perf_reset_rect) then
                RenderProfiler.reset()
                return
            end
            if self._perf_disable_rect and self:_point_in_rect_simple(x, y, self._perf_disable_rect) then
                PerformanceLab.disable_all()
                RenderProfiler.reset()
                return
            end
            if self._pause_back_rect and self:_point_in_rect_simple(x, y, self._pause_back_rect) then
                self._pause_settings_tab = "general"
                self._pause_focus_index = 1
                return
            end
            return
        end
        if self._pause_settings_tab == "controls" then
            for _, r in ipairs(self._controls_role_rects or {}) do
                if self:_point_in_rect_simple(x, y, r) then
                    self._controls_focus_zone = "list"
                    self._controls_focus_col = r.col or 1
                    self._controls_focus_row = r.row or 1
                    self._controls_listen_role = r.role
                    self._controls_listen_slot = r.slot or 1
                    return
                end
            end
            if self._pause_controls_reset_rect and self:_point_in_rect_simple(x, y, self._pause_controls_reset_rect) then
                self:reset_control_bindings()
                self._controls_listen_role = nil
                self._controls_listen_slot = nil
                self._controls_focus_zone = "footer"
                self._controls_focus_footer = "reset"
                return
            end
            if self._pause_back_rect and self:_point_in_rect_simple(x, y, self._pause_back_rect) then
                self._pause_settings_tab = "general"
                self._controls_listen_role = nil
                self._controls_listen_slot = nil
                self:reset_controls_grid_focus()
                return
            end
            return
        end
        -- Settings general tab touch
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
            self._pause_sfx_slider_drag = false
            local vol = self:_music_volume_from_slider_x(x)
            if vol ~= nil then self:set_music_volume(vol, { skip_save = true }) end
            return
        end
        slider = self._pause_sfx_slider_rect
        if slider and self:_point_in_rect_simple(x, y, slider) then
            self._pause_sfx_slider_drag = true
            self._pause_music_slider_drag = false
            self._pause_screenshake_slider_drag = false
            local vol = self:_sfx_volume_from_slider_x(x)
            if vol ~= nil then self:set_sfx_volume(vol, { skip_save = true }) end
            return
        end
        slider = self._pause_screenshake_slider_rect
        if slider and self:_point_in_rect_simple(x, y, slider) then
            self._pause_screenshake_slider_drag = true
            self._pause_music_slider_drag = false
            self._pause_sfx_slider_drag = false
            local pct = self:_screenshake_from_slider_x(x)
            if pct ~= nil then self:set_screenshake_percent(pct, { skip_save = true }) end
            return
        end
        if self._pause_reduced_motion_rect
            and self:_point_in_rect_simple(x, y, self._pause_reduced_motion_rect) then
            self:end_pause_slider_drag()
            self:set_reduced_motion(not self:reduced_motion_enabled())
            return
        end
        if self._pause_tilt_rect and self:_point_in_rect_simple(x, y, self._pause_tilt_rect) then
            self:end_pause_slider_drag()
            self:set_tilt_enabled(not self:tilt_enabled())
            return
        end
        if self._pause_joker_display_rect
            and self:_point_in_rect_simple(x, y, self._pause_joker_display_rect) then
            self:end_pause_slider_drag()
            self:set_joker_display_enabled(not self:joker_display_enabled())
            return
        end
        if self._pause_controls_open_rect and self:_point_in_rect_simple(x, y, self._pause_controls_open_rect) then
            self:end_pause_slider_drag()
            self._pause_settings_tab = "controls"
            self._controls_listen_role = nil
            self:reset_controls_grid_focus()
            self._pause_focus_index = 1
            return
        end
        if self._pause_performance_open_rect and self:_point_in_rect_simple(x, y, self._pause_performance_open_rect) then
            self:end_pause_slider_drag()
            self._pause_settings_tab = "performance"
            self._pause_focus_index = 1
            return
        end
        if self._pause_back_rect and self:_point_in_rect_simple(x, y, self._pause_back_rect) then
            self:leave_settings_panel()
            return
        end
        return
end

function Game:touchpressed(id, x, y)
    self:note_input_mode("touch")
    -- Settings opened from the main menu borrows the pause panel and its touch handling.
    if self._settings_over_menu and self.STATE == self.STATES.MENU then
        self:handle_pause_settings_touch(x, y)
        return
    end
    -- Collection opened from the pause menu: it owns the bottom screen until it closes.
    if self._collection_over_run and self.STATE == self.STATES.PAUSED then
        if self._menu_sub_state == "collection_grid" then
            CollectionUI.handle_touchpressed(self, id, x, y)
        else
            CollectionUI.handle_touch_menu(self, x, y)
        end
        return
    end
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
            self:handle_pause_settings_touch(x, y)
            return
        end
        -- Main pause page touch
        if self._pause_continue_rect and self:_point_in_rect_simple(x, y, self._pause_continue_rect) then
            self:exit_pause_menu()
            return
        end
        if self._pause_settings_rect and self:_point_in_rect_simple(x, y, self._pause_settings_rect) then
            self._pause_show_settings = true
            self._pause_settings_tab = "general"
            self._controls_listen_role = nil
            return
        end
        if self._pause_collection_rect and self:_point_in_rect_simple(x, y, self._pause_collection_rect) then
            self:open_collection_over_run()
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
    -- Before any per-state routing: a row that has been pulled down is drawn over the whole
    -- bottom screen and takes the touch ahead of whatever it covers.
    if self:handle_bottom_panel_touch(id, x, y) then return end
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
        if self.consumables_on_bottom == true then
            local node = self:get_node_at(x, y)
            local is_cons = select(1, node_is_owned_consumable(self, node))
            if is_cons then
                begin_node_drag(self, id, x, y, node)
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
    local joker_touch_state = self.jokers_on_bottom == true
    local consumable_touch_state = self.consumables_on_bottom == true
    if not selecting_hand and not joker_touch_state and not consumable_touch_state then return end
    if selecting_hand and self.hand and self.hand.is_scoring_active and self.hand:is_scoring_active() then return end
    -- Owned jokers on the bottom row take priority over hand cards / other nodes.
    -- `handle_bottom_panel_touch` has already claimed everything inside the tray; what is left
    -- for these two is a card that juiced or lifted past the tray's edge.
    if self.jokers_on_bottom == true and not pack_hand_move then
        local joker = self:get_owned_joker_at(x, y)
        if joker and node_is_owned_joker(self, joker) then
            begin_node_drag(self, id, x, y, joker)
            return
        end
    end
    if self.consumables_on_bottom == true and not pack_hand_move then
        local node_at = self:get_owned_consumable_at(x, y)
        if node_at then
            begin_node_drag(self, id, x, y, node_at)
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
        node:touchpressed(id, x, y)
        self.dragging = node
        self:move_to_front(node)
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
        if self._pause_show_settings and self._pause_settings_tab ~= "controls" then
            if self._pause_music_slider_drag then
                local vol = self:_music_volume_from_slider_x(x)
                if vol ~= nil then self:set_music_volume(vol, { skip_save = true }) end
            elseif self._pause_sfx_slider_drag then
                local vol = self:_sfx_volume_from_slider_x(x)
                if vol ~= nil then self:set_sfx_volume(vol, { skip_save = true }) end
            elseif self._pause_screenshake_slider_drag then
                local pct = self:_screenshake_from_slider_x(x)
                if pct ~= nil then self:set_screenshake_percent(pct, { skip_save = true }) end
            end
        end
        return
    end
    if self.STATE == self.STATES.GAME_OVER or self.STATE == self.STATES.YOU_WIN then
        return
    end
    local pack_hand_move = (self.STATE == self.STATES.OPEN_BOOSTER and self.booster_session and self.booster_session.hand_for_tarot)
    local selecting_hand = (self.STATE == self.STATES.SELECTING_HAND) or pack_hand_move
    local joker_touch_state = self.jokers_on_bottom == true
    local consumable_touch_state = self.consumables_on_bottom == true
    local zone_drag_state = (self.STATE == self.STATES.SHOP or self.STATE == self.STATES.OPEN_BOOSTER)
        and self.dragging and node_is_zone_draggable(self, self.dragging)
    local owned_joker_drag = self.jokers_on_bottom == true and self.dragging and node_is_owned_joker(self, self.dragging)
    local owned_cons_drag = self.consumables_on_bottom == true and self.dragging and select(1, node_is_owned_consumable(self, self.dragging))
    if not selecting_hand and not joker_touch_state and not consumable_touch_state and not zone_drag_state and not owned_joker_drag and not owned_cons_drag then return end
    if selecting_hand and self.hand and self.hand.is_scoring_active and self.hand:is_scoring_active() then return end
    if zone_drag_state then
        if self.dragging.touchmoved then
            self.dragging:touchmoved(id, x, y, dx, dy)
        end
        return
    end
    if self.dragging and select(1, node_is_owned_consumable(self, self.dragging)) and self.consumables_on_bottom == true then
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
    if self.dragging and self.dragging.touchmoved then
        self.dragging:touchmoved(id, x, y, dx, dy)
    end
    -- Reorder under the finger rather than on release, so the row the player is looking at while
    -- they drag is the row they end up with.
    if owned_joker_drag and self:update_joker_drag_reorder(self.dragging) then
        self._joker_drag_reordered = true
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
        if self._pause_music_slider_drag or self._pause_sfx_slider_drag
            or self._pause_screenshake_slider_drag then
            self:save_settings()
        end
        self._pause_music_slider_drag = false
        self._pause_sfx_slider_drag = false
        self._pause_screenshake_slider_drag = false
        self.dragging = nil
        return
    end
    if self.STATE == self.STATES.GAME_OVER then
        -- Same mid-slide gate as round eval: no dismissing a panel still entering.
        if not self:scene_transition_active() then
            GameOverUI.handle_touch(self, x, y)
        end
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
    local joker_touch_state = self.jokers_on_bottom == true
    local tapped_consumable = false
    if self.consumables_on_bottom == true then
        tapped_consumable = self:get_owned_consumable_at(x, y) ~= nil
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
    -- Let a dropped shop item glide back to its slot instead of snapping, so the
    -- motion tilt plays out on the way home.
    if released and node_is_zone_draggable(self, released) then
        released._shop_settling = true
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
    -- The row has been reordering live under the finger, so there is no distance threshold to
    -- clear here any more: this is a final settle for a drag that ended between moves, and
    -- `_joker_drag_reordered` carries whether anything actually shifted so the drop is not also
    -- read as a tap.
    if not zone_action_done and released and self.jokers and self.jokers_on_bottom and node_is_owned_joker(self, released) then
        reordered = self:try_reorder_joker_after_drag(released, x) or false
        reordered = reordered or (self._joker_drag_reordered == true)
        if reordered then
            self.active_tooltip_joker = nil
        end
    end
    self._joker_drag_reordered = false
    if not zone_action_done and released and self.consumable_nodes and self.consumables_on_bottom == true then
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
    if dist < TAP_THRESHOLD and self.consumables_on_bottom == true then
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

    -- The Play/Sort/Discard bar. `released == nil` means no node was under the initial press,
    -- so a hand card dragged down onto the bar and let go there cannot fire it; the tap
    -- threshold rules out a drag that merely started on the bar. Scoring is already excluded
    -- further up, where an active play sequence returns early.
    if not released and dist < TAP_THRESHOLD and self.STATE == self.STATES.SELECTING_HAND then
        if HandActionsUI.handle_touch(self, x, y) then
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

function Game:sync_gamepad_focus_after_inventory_change()
    if self.STATE == self.STATES.SELECTING_HAND
        or self.STATE == self.STATES.SHOP
        or self.STATE == self.STATES.OPEN_BOOSTER then
        local layer = self:get_gamepad_focus_layer()
        if layer == "consumables" then
            local n = self.consumable_nodes and #self.consumable_nodes or 0
            if n <= 0 then
                if self.consumables_on_bottom then
                    self:set_consumables_location(false)
                end
                if self.STATE == self.STATES.SHOP then
                    self:set_gamepad_shop_focus()
                elseif self.STATE == self.STATES.OPEN_BOOSTER then
                    if self:is_booster_hand_mode() then
                        self:set_gamepad_focus_layer("hand")
                    else
                        self:set_gamepad_focus_layer("booster")
                    end
                else
                    self:set_gamepad_focus_layer("hand")
                end
            else
                local idx = tonumber(self._consumable_focus_index) or 1
                self:consumable_gamepad_focus_at(math.max(1, math.min(n, idx)))
            end
        elseif layer == "jokers" or (self.STATE == self.STATES.SHOP and self._gamepad_bottom_layer == "jokers") then
            if #(self.jokers or {}) == 0 then
                if self.jokers_on_bottom then
                    self:set_jokers_location(false)
                end
                if self.STATE == self.STATES.SHOP then
                    self:set_gamepad_shop_focus()
                elseif self.STATE == self.STATES.OPEN_BOOSTER then
                    if self:is_booster_hand_mode() then
                        self:set_gamepad_focus_layer("hand")
                    else
                        self:set_gamepad_focus_layer("booster")
                    end
                else
                    self:set_gamepad_focus_layer("hand")
                end
            end
        end
    end
end

function Game:set_gamepad_shop_focus()
    self._gamepad_focus_layer = "hand"
    self.active_tooltip_consumable_index = nil
    self._gamepad_bottom_layer = "shop"
    self._joker_swap_pick_index = nil
    self.active_tooltip_joker = nil
    if tonumber(self._shop_focus_index) then
        self:sync_shop_gamepad_focus()
    end
end

function Game:_bottom_inventory_focus_locked()
    local layer = self:get_gamepad_focus_layer()
    if layer == "jokers" and self.jokers_on_bottom then return true end
    if layer == "consumables" and self.consumables_on_bottom then return true end
    return false
end

function Game:_handle_bottom_inventory_vertical(button)
    if not self:_bottom_inventory_focus_locked() then return false end
    if button ~= "up" and button ~= "dpup" and button ~= "down" and button ~= "dpdown" then
        return false
    end
    local up = (button == "up" or button == "dpup")
    if self.jokers_on_bottom and self.consumables_on_bottom then
        if up then
            self:set_gamepad_focus_layer("jokers")
        else
            self:set_gamepad_focus_layer("consumables")
        end
    end
    return true
end

function Game:handle_gamepad_shop_vertical(button)
    if button ~= "up" and button ~= "dpup" and button ~= "down" and button ~= "dpdown" then
        return false
    end
    self:ensure_shop_gamepad_nav()
    if self:_handle_bottom_inventory_vertical(button) then
        return true
    end
    return false
end

--- Volume for the focus-move tick, matching what the menu screens play.
local FOCUS_CUE_VOL = 0.2
--- Volume for D-pad auto-repeat steps. update_dpad_horizontal_repeat re-steps every
--- 200 ms while a direction is held, and a full-volume tick five times a second is a
--- machine gun, so held navigation is silent. Raise this if it feels dead on hardware.
local FOCUS_CUE_REPEAT_VOL = 0

--- Focus moved to a different thing. Call only once the index or layer has actually
--- changed: a bumped-into-the-end press must stay silent.
function Game:play_focus_cue()
    local vol = self._dpad_repeating and FOCUS_CUE_REPEAT_VOL or FOCUS_CUE_VOL
    if vol <= 0 then return end
    if Sfx and Sfx.play then Sfx.play("highlight1", nil, vol) end
end

--- How hard a newly focused node pops. The same values the hand cursor already uses
--- (`dpad_cursor_move`), which are the reference's hover-enter pop - small on purpose, because
--- this fires on every d-pad press and a walk along the shop shelf must not become a row of
--- bouncing cards.
local FOCUS_JUICE_SCALE = 0.05
local FOCUS_JUICE_ROT = 0.03

--- Focus moved onto `node`: ring the cue and pop the thing that now has it.
---
--- The cue alone told the player something had moved but not what to, which on a 240p screen
--- with no cursor is most of the information. The hand cursor has popped its card since it was
--- written (`dpad_cursor_move`, off the reference's hover-enter at `card.lua:4306`); the shop
--- shelf, the joker row, the consumable row and the booster choices never did, so focus was
--- visible in the hand and inaudible everywhere else.
---@param node Moveable|nil the node that just took focus, if the caller has one
function Game:announce_focus_move(node)
    self:play_focus_cue()
    -- Silent auto-repeat gets no pop either, for the same reason the cue is damped: holding a
    -- direction would otherwise shake every node it passed over.
    if self._dpad_repeating then return end
    if node and node.juice_up then node:juice_up(FOCUS_JUICE_SCALE, FOCUS_JUICE_ROT) end
end

--- Ticks when the focus lands on a different layer. Every vertical focus path in the
--- game funnels through here, including handle_gamepad_focus_vertical and the bottom
--- inventory swap, so this is the only place the layer cue belongs.
---@param layer string "hand" | "jokers" | "consumables" | "booster"
function Game:set_gamepad_focus_layer(layer)
    local prev = self._gamepad_focus_layer
    self:_set_gamepad_focus_layer(layer)
    if self._gamepad_focus_layer ~= prev then
        self:play_focus_cue()
    end
end

function Game:_set_gamepad_focus_layer(layer)
    self._joker_swap_pick_index = nil
    if layer == "jokers" then
        if #(self.jokers or {}) == 0 then
            layer = "hand"
        else
            self._gamepad_focus_layer = "jokers"
            self:joker_gamepad_focus_at(tonumber(self._joker_focus_index) or 1)
        end
    end
    if layer == "consumables" then
        local n = self.consumable_nodes and #self.consumable_nodes or 0
        if n <= 0 then
            if self.consumables_on_bottom then
                self:set_consumables_location(false)
            end
            self:_set_gamepad_focus_layer("hand")
            return
        end
        self._gamepad_focus_layer = "consumables"
        self:consumable_gamepad_focus_at(tonumber(self._consumable_focus_index) or 1)
        return
    end
    if layer == "jokers" then
        return
    end
    if layer == "booster" then
        self._gamepad_focus_layer = "booster"
        self:booster_gamepad_focus_first()
    else
        self._gamepad_focus_layer = "hand"
        self.active_tooltip_joker = nil
        self.active_tooltip_consumable_index = nil
        self:ensure_dpad_cursor()
    end
end

function Game:handle_gamepad_focus_vertical(button)
    if button ~= "up" and button ~= "dpup" and button ~= "down" and button ~= "dpdown" then
        return false
    end
    if self:scene_transition_active() then return true end
    local up = (button == "up" or button == "dpup")

    if self.STATE == self.STATES.SHOP then
        return self:handle_gamepad_shop_vertical(button)
    end

    if self:_bottom_inventory_focus_locked() then
        return self:_handle_bottom_inventory_vertical(button)
    end

    if self:is_booster_hand_mode() then
        if up then
            self:set_gamepad_focus_layer("hand")
        else
            self:set_gamepad_focus_layer("booster")
        end
        return true
    end

    if self.STATE == self.STATES.BLIND_SELECT then
        return false
    end

    if self.STATE == self.STATES.OPEN_BOOSTER then
        return false
    end

    return false
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
    self._gamepad_focus_layer = "hand"
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
    local moved = (idx ~= tonumber(self._shop_focus_index))
    self._shop_focus_index = idx
    local target = targets[idx]
    self:sync_shop_gamepad_tooltips(target)
    -- Only an "offer" target owns a node; a voucher or booster slot is a panel rect.
    if moved then self:announce_focus_move(target and target.node) end
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
    local moved = (idx ~= tonumber(self._joker_focus_index))
    local node = self:joker_gamepad_focus_at(idx)
    if moved then self:announce_focus_move(node) end
    return node
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
    local moved = (idx ~= tonumber(self._consumable_focus_index))
    local node = self:consumable_gamepad_focus_at(idx)
    if moved then self:announce_focus_move(node) end
    return node
end

function Game:toggle_hand_sort()
    if not self.hand then return false end
    if self._hand_sort_by_rank == true then
        self.hand:sort_by_suit()
        self._hand_sort_by_rank = false
    else
        self.hand:sort_by_rank()
        self._hand_sort_by_rank = true
    end
    return true
end

--- Confirm/cancel routed to a pulled-down panel (select/use vs sell). Shared by the
--- screens whose own UI must yield those buttons while a panel holds gamepad focus
--- (blind select, cashout).
function Game:handle_bottom_inventory_button(button)
    local layer = self:get_gamepad_focus_layer()

    if self:is_role(button, "confirm") then
        if layer == "jokers" and self.jokers_on_bottom then
            return self:gamepad_joker_press_select()
        end
        if layer == "consumables" and self.consumables_on_bottom then
            return self:gamepad_consumable_use()
        end
        return false
    end

    if self:is_role(button, "cancel") then
        if layer == "jokers" and self.jokers_on_bottom then
            return self:gamepad_joker_sell()
        end
        if layer == "consumables" and self.consumables_on_bottom then
            return self:gamepad_consumable_sell()
        end
        return false
    end

    return false
end

function Game:handle_gamepad_blind_select(button)
    if self.STATE ~= self.STATES.BLIND_SELECT then return false end
    if self._blind_slide then return true end
    return self:handle_bottom_inventory_button(button)
end

function Game:try_gamepad_boss_reroll()
    if self.STATE ~= self.STATES.BLIND_SELECT then return false end
    if self._blind_slide then return false end
    if not (self:has_voucher("v_directors_cut") or self:has_voucher("v_retcon")) then return false end
    if tonumber(self.selected_blind_index) ~= 3 then return false end
    if not self:can_afford_price(10) then return false end
    if self:has_voucher("v_directors_cut") and not self:has_voucher("v_retcon") then
        if (tonumber(self.boss_rerolls_used_this_ante) or 0) >= 1 then return false end
    end
    self.money = (tonumber(self.money) or 0) - 10
    self.boss_rerolls_used_this_ante = (tonumber(self.boss_rerolls_used_this_ante) or 0) + 1
    self:roll_boss_blind({ exclude_current = true })
    return true
end

function Game:consumable_reorder_gamepad_step(delta)
    if self.consumables_on_bottom ~= true then return false end
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
    self._consumable_layout_dirty = true
    self._consumable_focus_index = to_idx
    self.active_tooltip_consumable_index = to_idx
    self:draw_consumables_row()
    self:_snap_consumables_vt()
    return true
end

function Game:joker_reorder_gamepad_step(delta)
    if not self.jokers_on_bottom or not self.jokers then return false end
    local idx = tonumber(self._joker_focus_index)
    if not idx then return false end
    delta = math.floor(tonumber(delta) or 0)
    if delta == 0 then return false end
    local to_idx = idx + delta
    -- Springs, not a teleport: same reasoning as `Game:move_joker_to_index`, which does the work.
    if not self:move_joker_to_index(idx, to_idx) then return false end
    self._joker_focus_index = to_idx
    self:joker_gamepad_focus_at(to_idx)
    return true
end

function Game:gamepad_joker_press_select()
    if self.jokers_on_bottom ~= true then return false end
    if self:get_gamepad_focus_layer() ~= "jokers" then return false end
    return self:gamepad_joker_press_a()
end

function Game:gamepad_joker_sell()
    if self.jokers_on_bottom ~= true then return false end
    if self:get_gamepad_focus_layer() ~= "jokers" then return false end
    local idx = tonumber(self._joker_focus_index) or 1
    local node = self.jokers and self.jokers[idx]
    if not node then return false end
    return self:perform_sell_for_target({ kind = "joker", index = idx, node = node }) == true
end

function Game:gamepad_consumable_use()
    if self:get_gamepad_focus_layer() ~= "consumables" then return false end
    if self.consumables_on_bottom ~= true then return false end
    local idx = tonumber(self._consumable_focus_index) or tonumber(self.active_tooltip_consumable_index)
    if not idx then return false end
    return self:use_consumable(idx) == true
end

function Game:gamepad_consumable_sell()
    if self:get_gamepad_focus_layer() ~= "consumables" then return false end
    if self.consumables_on_bottom ~= true then return false end
    local idx = tonumber(self._consumable_focus_index) or tonumber(self.active_tooltip_consumable_index)
    if not idx then return false end
    local node = self.consumable_nodes and self.consumable_nodes[idx]
    if not node then return false end
    return self:perform_sell_for_target({ kind = "consumable", index = idx, node = node }) == true
end

--- Is the cancel button the hand's right now -- deselect on a tap, sweep on a hold -- rather
--- than some other screen's back/sell button?
---
--- Checked when the button goes down as well as when it comes up (`main.lua`), because the two
--- can differ: selling the last joker with B empties the row and hands focus straight back to
--- the hand, and without this the release would land on the hand and clear the selection the
--- player never touched.
---@return boolean
function Game:hand_cancel_gesture_available()
    if self._deck_view_open then return false end
    if self:get_gamepad_focus_layer() ~= "hand" then return false end
    if self.STATE ~= self.STATES.SELECTING_HAND and not self:is_booster_hand_mode() then
        return false
    end
    -- The press handler refuses everything mid-scoring (`handle_gamepad_selecting_hand`); the
    -- release path has to refuse it too or B re-sorts a hand that is being played.
    if self:is_hand_scoring_active() then return false end
    return true
end

--- A tap of the cancel button on the hand: drop the selection, or sort if there is none.
---
--- Two jobs on one button because the Switch layout this port follows leaves sorting without a
--- face button of its own (see `input_bindings.lua`). They cannot collide -- deselecting with
--- nothing selected does nothing, which is exactly when sorting is offered -- and the
--- bottom-screen action bar still carries a Sort segment for the touch path.
function Game:try_gamepad_hand_cancel_tap()
    if not self:hand_cancel_gesture_available() then return false end
    if self.hand and self.hand:has_selection() then
        -- Silent, as the reference's `remove_from_highlighted` is (`cardarea.lua:187-200`);
        -- see the same note in `Hand:toggle_selection`.
        self.hand:clear_selection()
        return true
    end
    return self:toggle_hand_sort()
end

function Game:handle_gamepad_selecting_hand(button)
    if self.STATE ~= self.STATES.SELECTING_HAND then return false end
    if self.hand and self.hand.is_scoring_active and self.hand:is_scoring_active() then
        return false
    end

    local layer = self:get_gamepad_focus_layer()

    if self:is_role(button, "confirm") then
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

    if self:is_role(button, "discard") then
        if layer == "hand" and self.hand and self.hand:has_selection() then
            -- Every reference button click rings (`engine/ui.lua:989`); the touch bar
            -- already does this in `hand_actions_ui`, the pad path did not.
            Sfx.play_button()
            self.hand:discard_selected()
            return true
        end
        return false
    end

    if self:is_role(button, "cancel") then
        -- On the hand, cancel resolves on release (`Game:try_gamepad_hand_cancel_tap`): it is
        -- also the sweep-select hold, and a press that deselected on the way down would empty
        -- the selection the sweep is about to build.
        if layer == "jokers" then
            return self:gamepad_joker_sell()
        elseif layer == "consumables" then
            return self:gamepad_consumable_sell()
        end
        return false
    end

    if self:is_role(button, "play") then
        if layer == "hand" and self.hand and self.hand:has_selection() then
            Sfx.play_button()
            self.hand:play_selected()
            return true
        end
    end

    return false
end

function Game:handle_gamepad_booster_hand_button(button)
    if not self:is_booster_hand_mode() then return false end
    local layer = self:get_gamepad_focus_layer()

    if self:is_role(button, "confirm") and layer == "hand" then
        local node = self:dpad_cursor_node()
        if node and self.hand then
            self.hand:toggle_selection(node)
        end
        return true
    end

    if self:is_role(button, "discard") and layer == "hand" and self.hand and self.hand:has_selection() then
        self.hand:discard_selected()
        return true
    end

    -- Swallow cancel while cards are picked so the press cannot skip the pack out from under a
    -- selection. What it does instead -- drop the selection -- happens on release, because this
    -- is also the sweep-select hold (`Game:try_gamepad_hand_cancel_tap`).
    if self:is_role(button, "cancel") and layer == "hand" and self.hand and self.hand:has_selection() then
        return true
    end

    if self:is_role(button, "play") then
        if layer == "hand" and self.hand and self.hand:has_selection() then
            return self:gamepad_booster_apply_hand_targeted()
        end
    end

    if layer == "consumables" then
        if self:is_role(button, "confirm") then return self:gamepad_consumable_use() end
        if self:is_role(button, "cancel") then return self:gamepad_consumable_sell() end
    end

    if layer == "jokers" then
        if self:is_role(button, "confirm") then return self:gamepad_joker_press_select() end
        if self:is_role(button, "cancel") then return self:gamepad_joker_sell() end
    end

    return false
end

function Game:is_gamepad_joker_focused(joker)
    if self.jokers_on_bottom ~= true then return false end
    if self:get_gamepad_focus_layer() ~= "jokers" then return false end
    return self.active_tooltip_joker == joker
end

function Game:is_joker_swap_pick(joker)
    local pick = tonumber(self._joker_swap_pick_index)
    if not pick or not self.jokers then return false end
    return self.jokers[pick] == joker
end

--- Track whether the player is currently steering with the touch screen or the
--- buttons. Focus outlines only make sense for button navigation; on touch the
--- finger is the cursor and an outline just reads as a stray black box.
---@param mode "touch"|"gamepad"
function Game:note_input_mode(mode)
    self.input_mode = mode
end

function Game:gamepad_focus_visible()
    return self.input_mode ~= "touch"
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
        if layer == "consumables" and self.consumables_on_bottom then
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
        if self:get_gamepad_focus_layer() == "consumables" then
            local idx = tonumber(self._consumable_focus_index) or tonumber(self.active_tooltip_consumable_index)
            if idx and self.consumable_nodes and self.consumable_nodes[idx] == node then
                return true
            end
        end
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
        if self:get_gamepad_focus_layer() == "consumables" and self.consumables_on_bottom then
            local idx = tonumber(self._consumable_focus_index) or tonumber(self.active_tooltip_consumable_index)
            if idx and self.consumable_nodes and self.consumable_nodes[idx] == node then
                return true
            end
        end
        local layer = self:get_gamepad_focus_layer()
        if layer ~= "jokers" and layer ~= "consumables" and not self:is_hand_cursor_active() then
            local sess = self.booster_session
            if sess and node._booster_choice_index then
                return tonumber(sess.active_choice_index) == node._booster_choice_index
            end
        end
    end
    if self.STATE == self.STATES.BLIND_SELECT then
        local layer = self:get_gamepad_focus_layer()
        if layer == "jokers" and self:is_gamepad_joker_focused(node) then
            return true
        end
        if layer == "consumables" and self.consumables_on_bottom then
            local idx = tonumber(self._consumable_focus_index) or tonumber(self.active_tooltip_consumable_index)
            if idx and self.consumable_nodes and self.consumable_nodes[idx] == node then
                return true
            end
        end
        if self:is_joker_swap_pick(node) then
            return true
        end
    end
    return false
end

function Game:draw_node_gamepad_focus_outline(node)
    if not node or not self:gamepad_focus_visible() then return end
    if not self:should_draw_gamepad_focus_outline(node) then return end
    local r = node.get_collision_rect and node:get_collision_rect()
    if not r then return end
    local lift_y = self:shop_joker_selection_lift_y(node)
    r = { x = r.x, y = r.y + lift_y, w = r.w, h = r.h }
    -- The collision rect is the full card slot, which is what keeps the shop and joker rows
    -- gapless to touch. The outline is meant to trace the card the player can see, and a few
    -- joker fronts are drawn shorter than their slot (`joker.lua` SHORT_ART_HEIGHT), so pull
    -- it in to the art. Centred art keeps this a symmetric inset.
    if node.get_art_metrics then
        local art_h, art_off = node:get_art_metrics()
        local scale = node.get_render_scale and node:get_render_scale() or 1
        if art_h * scale < r.h then
            r.y = r.y + art_off * scale
            r.h = art_h * scale
        end
    end
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
    if self.jokers_on_bottom ~= true then return false end
    if self:get_gamepad_focus_layer() ~= "jokers" then return false end
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
    local moved = (idx ~= current)
    sess.active_choice_index = idx
    self.active_tooltip_card = nil
    self.active_tooltip_joker = nil
    local node = sess.choice_nodes and sess.choice_nodes[idx]
    if node then self:move_to_front(node) end
    if moved then self:announce_focus_move(node) end
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
    if self._shop_slide then return true end
    self:ensure_shop_gamepad_nav()

    if button == "up" or button == "dpup" or button == "down" or button == "dpdown" then
        if self:handle_gamepad_shop_vertical(button) then
            return true
        end
    end

    local layer = self:get_gamepad_focus_layer()

    if layer == "consumables" then
        if self:is_role(button, "confirm") then return self:gamepad_consumable_use() end
        if self:is_role(button, "cancel") then return self:gamepad_consumable_sell() end
        return false
    end

    if layer == "jokers" then
        if self:is_role(button, "confirm") then return self:gamepad_joker_press_select() end
        if self:is_role(button, "cancel") then return self:gamepad_joker_sell() end
        return false
    end

    if self:is_role(button, "confirm") then
        return self:gamepad_shop_buy()
    end
    if self:is_role(button, "play") then
        return self:gamepad_shop_buy_use()
    end
    -- Reroll sits on the discard button in both places it exists (here and the boss reroll in
    -- blind select): throwing the shelf away for a fresh one is the same gesture as throwing
    -- a hand away for a fresh one, and the play button is spoken for by Buy & Use.
    if self:is_role(button, "discard") then
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
    -- Consume every button until the wrapper and its contents have finished their
    -- reference opening beats; `main.lua` otherwise treats B as an immediate skip.
    if sess and sess.opening_phase ~= "ready" then return true end
    local hand_pack = sess and sess.hand_for_tarot

    if hand_pack then
        if self:handle_gamepad_focus_vertical(button) then return true end
        if self:handle_gamepad_booster_hand_button(button) then return true end
    end

    local layer = self:get_gamepad_focus_layer()

    if layer == "jokers" then
        if self:is_role(button, "confirm") then return self:gamepad_joker_press_select() end
        if self:is_role(button, "cancel") then return self:gamepad_joker_sell() end
        return false
    end

    if layer == "consumables" then
        if self:is_role(button, "confirm") then return self:gamepad_consumable_use() end
        if self:is_role(button, "cancel") then return self:gamepad_consumable_sell() end
        return false
    end

    if self:is_role(button, "confirm") then
        local ok = self:gamepad_booster_confirm()
        if ok == true and self:is_booster_mega_pack() then
            self:booster_gamepad_focus_next_after_pick()
        end
        return ok == true
    end

    return false
end

function Game:_bottom_inventory_nav_active()
    local layer = self:get_gamepad_focus_layer()
    if layer == "jokers" and self.jokers_on_bottom and #(self.jokers or {}) > 0 then
        return true
    end
    if layer == "consumables" and self.consumables_on_bottom and self.consumable_nodes and #self.consumable_nodes > 0 then
        return true
    end
    return false
end

function Game:_bottom_inventory_horizontal_step(dir)
    local layer = self:get_gamepad_focus_layer()
    if layer == "jokers" and self.jokers_on_bottom and #(self.jokers or {}) > 0 then
        if self:is_joker_reorder_mode() then
            self:joker_reorder_gamepad_step(dir)
        else
            self:joker_gamepad_move(dir)
        end
        return true
    end
    if layer == "consumables" and self.consumables_on_bottom and self.consumable_nodes and #self.consumable_nodes > 0 then
        if self:is_consumable_reorder_mode() then
            self:consumable_reorder_gamepad_step(dir)
        else
            self:consumable_gamepad_move(dir)
        end
        return true
    end
    return false
end

function Game:_gamepad_horizontal_nav_active()
    -- Blind select and cashout have no horizontal nav of their own, but a pulled-down
    -- panel is still browsable there.
    if self.STATE == self.STATES.BLIND_SELECT or self.STATE == self.STATES.ROUND_EVAL then
        return self:_bottom_inventory_nav_active()
    end
    if self.STATE == self.STATES.SELECTING_HAND then
        local layer = self:get_gamepad_focus_layer()
        if layer == "hand" and self.hand and #(self.hand.card_nodes or {}) > 0 then
            return true
        end
        if layer == "jokers" and self.jokers_on_bottom and #(self.jokers or {}) > 0 then
            return true
        end
        if layer == "consumables" and self.consumables_on_bottom and self.consumable_nodes and #self.consumable_nodes > 0 then
            return true
        end
        return false
    end
    if self.STATE == self.STATES.SHOP then
        self:ensure_shop_gamepad_nav()
        local layer = self:get_gamepad_focus_layer()
        if layer == "consumables" and self.consumables_on_bottom and self.consumable_nodes and #self.consumable_nodes > 0 then
            return true
        end
        if layer == "jokers" and self.jokers_on_bottom and #(self.jokers or {}) > 0 then
            return true
        end
        if layer == "hand" and #self:build_shop_focus_targets() > 0 then
            return true
        end
    end
    if self.STATE == self.STATES.OPEN_BOOSTER and self.booster_session then
        local layer = self:get_gamepad_focus_layer()
        if self:is_hand_cursor_active() then
            return self.hand and #(self.hand.card_nodes or {}) > 0
        end
        if layer == "jokers" and self.jokers_on_bottom and #(self.jokers or {}) > 0 then
            return true
        end
        if layer == "consumables" and self.consumables_on_bottom and self.consumable_nodes and #self.consumable_nodes > 0 then
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
    local node = self:dpad_cursor_node()
    -- The gamepad cursor is this port's hover: the reference ticks every hover-enter with a
    -- tiny pop and a paper1 chirp (`reference/Balatro/card.lua:4306-4308`), the single
    -- most-fired piece of feedback in the game.
    if node and node.juice_up then
        node:juice_up(0.05, 0.03)
    end
    -- Silent while a direction is held, for the same reason `play_focus_cue` is: the repeat
    -- steps every 200 ms, and the reference's chirp is hover-*enter*, not a held tick.
    if Sfx and Sfx.play and not self._dpad_repeating then
        local jitter = (love.math and love.math.random and love.math.random()) or 0.5
        Sfx.play("paper1", 0.9 + jitter * 0.2, 0.35)
    end
    return node
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
    if not self:is_sweep_select_mode() or self._sweep_seeded then return end
    local node = self:dpad_cursor_node()
    if node then
        self:_sweep_toggle_card(node)
        self._sweep_seeded = true
    end
end

function Game:update_sweep_seed()
    if not self:is_sweep_select_mode() or self._sweep_seeded then return end
    local press_time = self:get_role_press_time("cancel")
    if not press_time then return end
    if love.timer.getTime() - press_time >= InputBindings.GESTURES.sweep_seed_hold_ms / 1000 then
        self:ensure_sweep_seed()
    end
end

function Game:_dpad_sweep_toggle(node)
    if not self.hand or not node then return end
    self:_sweep_toggle_card(node)
end

function Game:_dpad_horizontal_step(dir, sweep)
    if self:scene_transition_active() then return end
    if self:_bottom_inventory_horizontal_step(dir) then
        return
    end

    if self.STATE == self.STATES.SHOP then
        self:ensure_shop_gamepad_nav()
        if self:get_gamepad_focus_layer() == "consumables" then
            if self:is_consumable_reorder_mode() then
                self:consumable_reorder_gamepad_step(dir)
            else
                self:consumable_gamepad_move(dir)
            end
            return
        end
        if self:get_gamepad_focus_layer() == "jokers" then
            if self:is_joker_reorder_mode() then
                self:joker_reorder_gamepad_step(dir)
            else
                self:joker_gamepad_move(dir)
            end
            return
        end
        self:shop_gamepad_move(dir)
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
        local layer = self:get_gamepad_focus_layer()
        if layer == "jokers" and self.jokers_on_bottom then
            if self:is_joker_reorder_mode() then
                self:joker_reorder_gamepad_step(dir)
            else
                self:joker_gamepad_move(dir)
            end
            return
        end
        if layer == "consumables" and self.consumables_on_bottom then
            if self:is_consumable_reorder_mode() then
                self:consumable_reorder_gamepad_step(dir)
            else
                self:consumable_gamepad_move(dir)
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

--- Repeat D-pad left/right while held: navigate, sweep-select (Hold B), or reorder (Hold A + selection).
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
        -- Auto-repeat, not a press. play_focus_cue damps itself while this is set;
        -- ticking every 200 ms at press volume is a machine gun.
        self._dpad_repeating = true
        self:_dpad_horizontal_step(dir, sweep)
        self._dpad_repeating = false
    end
end

function Game:is_hand_reorder_mode()
    if not self:is_role_held("confirm") then return false end
    if not self:is_hand_cursor_active() then return false end
    return self.hand and self.hand:has_selection()
end

function Game:is_joker_reorder_mode()
    if not self:is_role_held("confirm") or self.jokers_on_bottom ~= true then return false end
    return self:get_gamepad_focus_layer() == "jokers"
end

function Game:is_consumable_reorder_mode()
    if not self:is_role_held("confirm") or self.consumables_on_bottom ~= true then return false end
    return self:get_gamepad_focus_layer() == "consumables"
end

--- Cancel doubles as the sell button, so a hold that began on a pulled-down row must not turn
--- into a hand sweep when selling the last item hands focus back to the hand mid-hold. The
--- gesture is armed on the press (`main.lua`) and only then.
function Game:is_sweep_select_mode()
    if not self:is_role_held("cancel") then return false end
    if not self._cancel_gesture_armed then return false end
    return self:is_hand_cursor_active()
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

--- Keep hold roles aligned with hardware (release events can be dropped mid-play).
function Game:sync_shoulder_input()
    local bindings = self:control_bindings()
    local down = {}
    local joysticks = love.joystick.getJoysticks()
    local joy = joysticks and joysticks[1]
    if joy and joy.isGamepad and joy:isGamepad() then
        down = InputBindings.build_gamepad_down_map(joy, InputBindings.REBINDABLE_BUTTONS)
    elseif love.keyboard.isDown then
        local KEY_TO_GAMEPAD = {
            z = "a", x = "b", c = "x", v = "y", y = "y",
            q = "leftshoulder", e = "rightshoulder",
        }
        for key, btn in pairs(KEY_TO_GAMEPAD) do
            if love.keyboard.isDown(key) then
                down[btn] = true
            end
        end
        if love.keyboard.isDown("return") then
            down.a = true
        end
    end

    for role in pairs(InputBindings.HOLD_ROLES) do
        local buttons = InputBindings.get_role_buttons(role, bindings)
        if #buttons > 0 then
            local any_down = false
            for _, btn in ipairs(buttons) do
                if down[btn] then
                    any_down = true
                    break
                end
            end
            if not any_down then
                self:set_role_held(role, false)
                if role == "cancel" then
                    self._sweep_seeded = false
                    self._cancel_gesture_armed = false
                end
            end
        end
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
    entry.load_error = (not ok) and tostring(err) or nil
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
    atlas.load_error = (not ok) and tostring(err) or nil
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
    atlas.load_error = (not ok) and tostring(err) or nil
    return atlas
end

--- Source rectangle for one cell of a grid atlas, cached on the atlas itself.
---
--- Two separate problems, one helper.
---
--- The grid is read from declared geometry (`cols`/`rows` on the atlas entry) before it is
--- derived from the image, because on hardware `Image:getDimensions()` can report the
--- power-of-two padded runtime size rather than the source PNG's -- BlindChips.png is
--- 864x1008 on disk and 1024x1024 in memory. Dividing the padded width by the cell width
--- gives 28 columns where the sheet has 24, so every cell past the first row lands on the
--- wrong pixels: right on desktop, wrong on console. This is the trap the asset atlases
--- already carry `cols` to avoid (`consumable.lua:43-46`).
---
--- And the quad is cached rather than rebuilt. These are called from the draw path, once
--- per frame per animated sprite, and `newQuad` allocates every time.
---@return userdata|nil quad, number cell_w, number cell_h
function Game:atlas_cell_quad(atlas, index)
    if not atlas or not atlas.image then return nil, 0, 0 end
    local cell_w = tonumber(atlas.px)
    local cell_h = tonumber(atlas.py)
    if not cell_w or not cell_h or cell_w <= 0 or cell_h <= 0 then return nil, 0, 0 end

    local iw, ih = atlas.image:getDimensions()
    local cols = tonumber(atlas.cols) or math.floor(iw / cell_w)
    local rows = tonumber(atlas.rows) or math.floor(ih / cell_h)
    if cols <= 0 or rows <= 0 then return nil, 0, 0 end

    index = tonumber(index) or 0
    if index < 0 or index >= (cols * rows) then index = 0 end

    -- Keyed on the dimensions the quads were built against: an atlas can be unloaded and
    -- reloaded, and a quad holds its source size, so a cache that outlived a size change
    -- would hand back stale rectangles.
    local cache = atlas._quads
    if not cache or cache.iw ~= iw or cache.ih ~= ih then
        cache = { iw = iw, ih = ih }
        atlas._quads = cache
    end

    local quad = cache[index]
    if not quad then
        quad = love.graphics.newQuad(
            (index % cols) * cell_w, math.floor(index / cols) * cell_h,
            cell_w, cell_h, iw, ih)
        cache[index] = quad
    end
    return quad, cell_w, cell_h
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
    atlas._quads = nil
    return true
end

--- Load atlases before the frame that draws them.
---
--- Lazy loading is right for a 64 MB budget, but it puts the load on whichever draw call
--- reaches for the sheet first, which means an SD read plus a t3x decode plus a texture
--- upload happening inside a frame. The two that hurt are the first blind of a run
--- (BlindChips.png, 4 MiB) and the first deal (`centers` + `cards_2`, 4 MiB between them).
--- Warming at a state transition moves that cost to a moment that already reads as one.
---
--- `ensure_*` returns immediately once the image is resident, so warming an already-warm
--- atlas is a table lookup, and calling this on every entry to a state is fine.
function Game:warm_atlases(asset_names, animation_names)
    if asset_names then
        for i = 1, #asset_names do
            self:ensure_asset_atlas_loaded(asset_names[i])
        end
    end
    if animation_names then
        for i = 1, #animation_names do
            self:ensure_animation_atlas_loaded(animation_names[i])
        end
    end
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
    atlas._quads = nil
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
        -- `cols`/`rows` are declared, not derived, for the same reason the asset atlases
        -- below declare theirs: hardware reports the padded runtime size from
        -- `getDimensions`, so dividing it by the cell size finds the wrong grid.
        -- BlindChips.png is 864x1008 (24x28 cells of 36) padded to 1024x1024; menu.png is
        -- 1024x1024 already, 8x8 cells of 128.
        self.animation_atli = {
            {name = "blind_chips", path = "resources/textures/1x/BlindChips.png",px=36,py=36, cols=24, rows=28, frames = 21},
            {name = "shop_sign", path = "resources/textures/1x/ShopSignAnimation.png",px=113,py=60, cols=4, rows=1, frames = 4},
            -- The menu backdrop is generated on the GPU now (`backdrop.lua`), so this sheet
            -- is no longer loaded: it was 1024x1024, 2.5 MB on the card and 4 MiB resident,
            -- and it was read back in on every entry to the home screen. `path` is nil so
            -- `ensure_animation_atlas_loaded` returns the entry without touching the card;
            -- the entry itself stays so anything walking this table sees the same shape.
            {name = "menu", path = nil, px=128, py=128, cols=8, rows=8, frames = 63},
        }
        self.asset_atli = {
            -- Edition pattern sheets: structure only, colour comes from the vertex field.
            -- fx.lua declares its own cell geometry for these (the sheet holds two card
            -- silhouettes at different sizes, so one px/py cannot describe it); the
            -- entries are here purely to get lazy load and unload for free.
            {name = "edition_foil", path = "resources/textures/1x/editions/foil.png",px=72,py=95},
            {name = "edition_holo", path = "resources/textures/1x/editions/holo.png",px=72,py=95},
            -- `cols` is declared, not derived: on hardware an atlas is padded to a power of two
            -- (Enhancers.png is 720x380 on disk, 1024x512 in memory) and `getDimensions` can
            -- report the padded size, which would put the deck backs and seals on the wrong cells.
            {name = "cards_1", path = "resources/textures/1x/8BitDeck.png",px=72,py=95,cols=13},
            {name = "cards_2", path = "resources/textures/1x/8BitDeck_opt2.png",px=72,py=95,cols=13},
            {name = "centers", path = "resources/textures/1x/Enhancers.png",px=72,py=95,cols=10},
            {name = "Voucher", path = "resources/textures/1x/Vouchers.png",px=72,py=95,cols=10},
            {name = "Booster", path = "resources/textures/1x/boosters.png",px=72,py=95,cols=10},
            {name = "balatro", path = "resources/textures/1x/balatro.png",px=336,py=216},
            -- The ace over the logo is a live card in the reference, not part of the logo art:
            -- it is a real Card emplaced in the `title_top` CardArea (`game.lua:1599`) so the
            -- single-card idle motion in `cardarea.lua:466` can breathe it. Drawing it from
            -- `centers` + `cards_2` the way Card:draw does would pull 4 MiB of atlas onto the
            -- title screen for one 72x95 sprite, so it is pre-composited into its own sheet.
            {name = "title_ace", path = "resources/textures/1x/title_ace.png",px=72,py=95},
            {name = 'gamepad_ui', path = "resources/textures/1x/gamepad_ui.png",px=32,py=32},
            {name = 'tags', path = "resources/textures/1x/tags.png",px=34,py=34,cols=10},
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
        -- Single-image (non-atlas) assets. Empty for now: this port has no publisher
        -- splash, so the Playstack and LocalThunk logo sheets are not shipped.
        self.asset_images = {}

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
            self.ANIMATION_ATLAS[name].cols = entry.cols
            self.ANIMATION_ATLAS[name].rows = entry.rows
            self.ANIMATION_ATLAS[name].frames = entry.frames
            -- Lazy, like the asset atlases. These used to load during Game() for every
            -- sheet but `menu`, which meant BlindChips.png was resident before the title
            -- screen drew: 864x1008 pads to 1024x1024 on hardware, so 4 MiB of a 64 MB
            -- budget, held for the whole process, to serve 36x36 cells at blind select.
            -- Every consumer goes through `ensure_animation_atlas_loaded` instead.
            self.ANIMATION_ATLAS[name].image = nil
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
            self.ASSET_ATLAS[self.asset_atli[i].name].cols = self.asset_atli[i].cols
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

        for _, v in pairs(G.I.SPRITE) do
            v:reset()
        end
end
