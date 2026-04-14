---@class Joker : Moveable
Joker = Moveable:extend()
require "joker_effects"

-- Basic 2-layer joker: back sprite and front sprite.
-- Rendering logic is similar to `Card:draw()` but uses atlas cell indices instead of rank/suit.

local SHAKE_MAGNITUDE = 10
local SHAKE_MAX_DURATION = (JokerEffects and JokerEffects.SHAKE_MAX_DURATION) or 0.22

local function lower(s)
    return string.lower(tostring(s or ""))
end

local function parse_first_number(s, fallback)
    local n = tonumber((tostring(s or "")):match("([%d%.]+)"))
    if n == nil then return fallback end
    return n
end

local function text_has(s, needle)
    return lower(s):find(lower(needle), 1, true) ~= nil
end

local function capture_joker_runtime_snapshot(joker)
    local hand_cards = (((G or {}).hand or {}).cards)
    local deck_cards = (((G or {}).deck or {}).cards)
    return {
        stored_mult = tonumber(joker and joker.stored_mult) or 0,
        stored_chips = tonumber(joker and joker.stored_chips) or 0,
        stored_xmult = tonumber(joker and joker.stored_xmult) or 1,
        runtime_counter = tonumber(joker and joker.runtime_counter) or 0,
        sell_cost = tonumber(joker and joker.sell_cost) or 0,
        loyalty_remaining = tonumber(joker and joker.loyalty_remaining) or 0,
        free_joker_slots = tonumber(joker and joker.free_joker_slots) or 0,
        money = tonumber((G or {}).money) or 0,
        joker_count = (type((G or {}).jokers) == "table") and #G.jokers or 0,
        consumable_count = (type((G or {}).consumables) == "table") and #G.consumables or 0,
        hand_count = (type(hand_cards) == "table") and #hand_cards or 0,
        deck_count = (type(deck_cards) == "table") and #deck_cards or 0,
    }
end

local function runtime_snapshot_delta(before, after)
    if not before or not after then return false, false end
    local created = (after.joker_count > before.joker_count)
        or (after.consumable_count > before.consumable_count)
        or (after.hand_count > before.hand_count)
        or (after.deck_count > before.deck_count)

    local state_changed = created
        or after.stored_mult ~= before.stored_mult
        or after.stored_chips ~= before.stored_chips
        or after.stored_xmult ~= before.stored_xmult
        or after.runtime_counter ~= before.runtime_counter
        or after.sell_cost ~= before.sell_cost
        or after.loyalty_remaining ~= before.loyalty_remaining
        or after.free_joker_slots ~= before.free_joker_slots
        or after.money ~= before.money
        or after.joker_count ~= before.joker_count
        or after.consumable_count ~= before.consumable_count
        or after.hand_count ~= before.hand_count
        or after.deck_count ~= before.deck_count
    return state_changed, created
end

local function count_full_deck(pred)
    if G and G.count_cards_in_full_deck then
        return G:count_cards_in_full_deck(pred)
    end
    return 0
end

---@param raw string|nil
---@return "base"|"foil"|"holo"|"polychrome"|"negative"
function Joker.normalize_edition(raw)
    if raw == nil or raw == "" then return "base" end
    local e = string.lower(tostring(raw))
    if e == "base" then return "base" end
    if e == "holographic" or e == "e_holo" then return "holo" end
    if e == "e_foil" or e == "foil" then return "foil" end
    if e == "e_polychrome" or e == "polychrome" then return "polychrome" end
    if e == "e_negative" or e == "negative" then return "negative" end
    if e == "holo" or e == "polychrome" or e == "negative" then return e end
    return "base"
end

--- Extra shop cost and sell value from the edition alone (added to def `cost` / `sell_cost`).
function Joker.edition_price_deltas(ed)
    ed = Joker.normalize_edition(ed)
    if ed == "foil" then return 2 end
    if ed == "holo" then return 3 end
    if ed == "polychrome" then return 5 end
    if ed == "negative" then return 5 end
    return 0
end

--- Atlas key for the front sheet: Negative edition uses pre-baked `Joker1_negative` / `Joker2_negative` sheets.
---@param base_atlas string|nil e.g. `"Joker1"` from `def.pos.atlas`
---@param edition string|nil raw edition
---@return string|nil
function Joker.resolve_front_atlas_key(base_atlas, edition)
    local base = base_atlas and tostring(base_atlas) or "Joker1_p1"
    local ed = Joker.normalize_edition(edition)
    if ed == "negative" then
        if base == "Joker1" then return "Joker1_negative" end
        if base == "Joker2" then return "Joker2_negative" end
        local p = string.match(base, "^Joker1_p(%d+)$")
        if p then return "Joker1_negative_p" .. p end
        p = string.match(base, "^Joker2_p(%d+)$")
        if p then return "Joker2_negative_p" .. p end
    end
    return base
end

local function joker_front_quads_signature(joker)
    return tostring(joker.front_atlas_name) .. "\0" .. Joker.normalize_edition(joker.edition)
end

-- Edition visuals: foil/holo/polychrome use multiply; Negative uses alternate atlas (see `resolve_front_atlas_key`).

--- Animated RGB multiply for Polychrome edition (no shader).
local function polychrome_edition_set_color()
    local t = love.timer.getTime() * 1.35
    local r = 0.52 + 0.48 * (0.5 + 0.5 * math.sin(t))
    local g = 0.52 + 0.48 * (0.5 + 0.5 * math.sin(t + 2.094395))
    local b = 0.52 + 0.48 * (0.5 + 0.5 * math.sin(t + 4.18879))
    love.graphics.setColor(r, g, b, 1)
end

local function compute_quad(atlas, index)
    if not atlas or not atlas.image or index == nil then return nil, 0, 0 end

    local iw, ih = atlas.image:getDimensions()
    local cell_w, cell_h = atlas.px, atlas.py
    if not cell_w or not cell_h or cell_w <= 0 or cell_h <= 0 then
        return nil, 0, 0
    end

    local cols = math.floor(iw / cell_w)
    if cols <= 0 then return nil, 0, 0 end

    local col = index % cols
    local row = math.floor(index / cols)

    local sx = col * cell_w
    local sy = row * cell_h

    local quad = love.graphics.newQuad(sx, sy, cell_w, cell_h, iw, ih)
    return quad, cell_w, cell_h
end

local function joker_is_debuffed_for_display(joker)
    return G and G.boss_is_joker_debuffed and G:boss_is_joker_debuffed(joker) == true
end

local function draw_debuff_x_overlay(draw_x, draw_y, w, h)
    local inset = math.max(4, math.floor(math.min(w, h) * 0.14))
    local x1 = draw_x + inset
    local y1 = draw_y + inset
    local x2 = draw_x + w - inset
    local y2 = draw_y + h - inset
    local prev_w = love.graphics.getLineWidth()
    love.graphics.setLineWidth(5)
    love.graphics.setColor(0.95, 0.2, 0.2, 0.95)
    love.graphics.line(x1, y1, x2, y2)
    love.graphics.line(x1, y2, x2, y1)
    love.graphics.setLineWidth(prev_w)
end

local function resolve_atlas(name)
    if not name or not G or not G.ASSET_ATLAS then return nil end
    if G.ensure_asset_atlas_loaded then
        G:ensure_asset_atlas_loaded(name)
    end
    return G.ASSET_ATLAS[name]
end

---@param X number
---@param Y number
---@param W number|nil
---@param H number|nil
---@param def table Joker definition (name/rarity/effect/trigger + sprites)
---@param params table|nil (face_up, front/back indices override, etc)
function Joker:init(X, Y, W, H, def, params)
    self.def = def or {}
    self.params = type(params) == "table" and params or {}

    -- Keep these on the instance for quick access in conditions/effects later.
    self.name = self.def.name or "Joker"
    self.rarity = self.def.rarity or "common"

    self.edition = Joker.normalize_edition(self.params.edition or self.def.edition)
    local base_cost = tonumber(self.def.cost) or 1
    local base_sell = tonumber(self.def.sell_cost)
    if base_sell == nil then
        base_sell = math.max(1, math.floor(base_cost / 2))
    end
    local ec = Joker.edition_price_deltas(self.edition)
    self.cost = base_cost + ec
    self.sell_cost = math.max(1, base_sell)

    self.effect_config = self.def.config or {}

    -- Runtime accumulator for effects that grow over time (e.g. Ceremonial Dagger).
    self.stored_mult = tonumber(self.effect_config.mult) or 0
    self.stored_chips = tonumber(self.effect_config.chips) or 0
    self.stored_xmult = tonumber(self.effect_config.Xmult) or 1
    self.runtime_counter = 0
    self.loyalty_remaining = nil
    self.free_joker_slots = nil

    -- Effect interpreter fields:
    -- Supported Balatro-like effect types:
    --   "Mult", "Suit Mult", "Type Mult", and optional chips variants.
    self.effect_type = nil

    if type(self.def.effect) == "string" then
        self.effect_type = self.def.effect
    elseif type(self.def.effect) == "table" then
        -- Legacy compatibility with the earlier prototype `{type="add_mult", amount=...}`.
        if self.def.effect.type == "add_mult" then
            self.effect_type = "Mult"
            self.effect_config = self.effect_config or {}
            self.effect_config.mult = tonumber(self.def.effect.amount) or 0
        elseif self.def.effect.type == "add_chips" then
            self.effect_type = "Chips"
            self.effect_config = self.effect_config or {}
            self.effect_config.chips = tonumber(self.def.effect.amount) or 0
        end
    end

    -- Infer effect type when missing (based on config).
    if self.effect_type == nil then
        if type(self.effect_config) == "table" then
            if self.effect_config.mult ~= nil then
                self.effect_type = "Mult"
            elseif type(self.effect_config.extra) == "table" and self.effect_config.extra.s_mult ~= nil then
                self.effect_type = "Suit Mult"
            elseif self.effect_config.t_mult ~= nil then
                self.effect_type = "Type Mult"
            elseif type(self.effect_config.extra) == "table" and self.effect_config.extra.s_chips ~= nil then
                self.effect_type = "Suit Chips"
            elseif self.effect_config.t_chips ~= nil then
                self.effect_type = "Type Chips"
            end
        end
    end

    if self.effect_type == "1 in 6 mult" or self.effect_type == "1 in 10 mult" then
        local extra = type(self.effect_config.extra) == "table" and self.effect_config.extra or {}
        local every = math.max(1, tonumber(extra.every) or 6)
        local remaining = tonumber(extra.remaining) or every
        if remaining < 1 or remaining > every then
            remaining = every
        end
        self.loyalty_remaining = remaining
    end

    self.effect_impl = JokerEffects.get(self)

    if type(self.def) == "table" then
        if (self.def.id == "j_ancient_joker" or self.def.id == "j_castle") then
            local suits = { "Hearts", "Clubs", "Diamonds", "Spades" }
            self.random_suit = suits[math.random(1, #suits)]
        end
        if self.def.id == "j_castle" then
            self.runtime_counter = tonumber(self.runtime_counter) or 0
        elseif self.def.id == "j_ramen" then
            self.runtime_counter = self.def.config.Xmult or 2 -- Starts at 2
        elseif self.def.id == "j_seltzer" then
            self.runtime_counter = self.def.config.duration or 10 -- Starts at 10
        elseif self.def.id == "j_ice_cream" then
            self.runtime_counter = self.def.config.chips or 100 -- Starts at 100
        elseif self.def.id == "j_turtle_bean" then
            self.runtime_counter = self.def.config.extra.h_size or 5
        elseif self.def.id == "j_todo_list" then
            local found = false
            while not found do
                local pos = math.random(1, #G.handlist)
                if (pos < 4) then -- Secret hands only show if played before
                    if (G.hand_play_counts[pos] and G.hand_play_counts[pos] > 0) then
                        found = true
                    end
                else
                    found = true
                end
                self.random_hand = G.handlist[pos]
            end
        elseif self.def.id == "j_rocket" then
            local ex = type(self.def.config) == "table" and self.def.config.extra
            self.running_count = math.max(1, math.floor(tonumber(ex and ex.dollars) or 1))
        elseif self.def.id == "j_mail" then
            self.random_rank = math.random(2, 14)
        elseif self.def.id == "j_idol" then
            local card = G.deck and G.deck.random_card and G.deck:random_card()
            if card then
                self.random_rank = card.rank
                self.random_suit = card.suit
            else
                local suits = { "Hearts", "Clubs", "Diamonds", "Spades" }
                self.random_rank = math.random(2, 14)
                self.random_suit = suits[math.random(1, #suits)]
            end
        end
    end

    local cw = W or 71
    local ch = H or 95
    Moveable.init(self, X or 0, Y or 0, cw, ch)

    -- Disable collisions between jokers/cards for now.
    self.states.collide.can = false

    -- Defaults to showing the front face.
    self.face_up = self.params.face_up
    if self.face_up == nil then self.face_up = true end

    -- Define which atlas cells represent the front/back joker art.
    -- Expected structure in def:
    --   def.pos = { atlas = "Joker1", index = 0 }
    self.front_atlas_name = (self.params.pos and self.params.pos.atlas) or (self.def.pos and self.def.pos.atlas) or "Joker1_p1"
    self.back_atlas_name = "centers"

    self.front_index = (self.params.pos and self.params.pos.index) or (self.def.pos and self.def.pos.index) or 0
    self.back_index = 0

    self.scoring_shake_timer = 0

    self:refresh_quads()
end

function Joker:refresh_quads()
    local old_front_atlas_name = self._front_atlas_ref_name
    local base_name = self.front_atlas_name
    local want_key = Joker.resolve_front_atlas_key(base_name, self.edition)
    local base_atlas = resolve_atlas(base_name)

    self.front_atlas = resolve_atlas(want_key)
    if Joker.normalize_edition(self.edition) == "negative" and want_key ~= base_name then
        if not self.front_atlas or not self.front_atlas.image then
            self.front_atlas = base_atlas
        end
    end

    self.back_atlas = resolve_atlas(self.back_atlas_name)

    self.front_quad, self.front_w, self.front_h = compute_quad(self.front_atlas, self.front_index)
    if Joker.normalize_edition(self.edition) == "negative" and want_key ~= base_name then
        if not self.front_quad and base_atlas and base_atlas.image then
            self.front_atlas = base_atlas
            self.front_quad, self.front_w, self.front_h = compute_quad(self.front_atlas, self.front_index)
        end
    end
    self.back_quad, self.back_w, self.back_h = compute_quad(self.back_atlas, self.back_index)
    self._front_atlas_ref_name = (self.front_atlas and self.front_atlas.name) or want_key or base_name

    -- Sync node transform size with sprite cell so it doesn't render tiny.
    local base_w = self.front_w or self.back_w
    local base_h = self.front_h or self.back_h
    if base_w and base_h and base_w > 0 and base_h > 0 then
        self.T.w = base_w
        self.T.h = base_h
        if self.VT then
            self.VT.w = base_w
            self.VT.h = base_h
        end
    end

    self._quads_refresh_signature = joker_front_quads_signature(self)
    if G and G.on_joker_front_atlas_resolved then
        G:on_joker_front_atlas_resolved(self, old_front_atlas_name, self._front_atlas_ref_name)
    end
end

function Joker:set_face_up(face_up)
    self.face_up = not not face_up
end

function Joker:touchreleased(id, x, y)
    Moveable.touchreleased(self, id, x, y)
end

-- Collision rect must match Joker's draw bounds.
-- `Joker:draw()` scales around the sprite center, which shifts the visible
-- top-left when `scale != 1`. Hit-testing should use the same effective bounds.
function Joker:get_collision_rect()
    local t = self.VT or self.T
    local s = t.scale or 1
    local w = t.w or 0
    local h = t.h or 0

    local offx = (self.collision_offset and self.collision_offset.x) or 0
    local offy = (self.collision_offset and self.collision_offset.y) or 0

    local scaled_w = w * s
    local scaled_h = h * s

    -- When scaling around the center and drawing with top-left coordinates,
    -- the effective visible top-left shifts by:
    --   delta = w*s*(1-s)/2
    local delta_x = (w * s * (1 - s)) / 2
    local delta_y = (h * s * (1 - s)) / 2

    local draw_x = t.x + offx
    local draw_y = t.y + offy

    return {
        x = draw_x + delta_x,
        y = draw_y + delta_y,
        w = scaled_w,
        h = scaled_h
    }
end

local TOOLTIP_PAD_X = 8
local TOOLTIP_HEADER_PAD_Y = 3
local TOOLTIP_BODY_PAD_Y = 10
--- Tighter top inset when the first body line is the rarity pill (less gap under the header).
local TOOLTIP_BODY_PAD_TOP_RARITY = 4
local TOOLTIP_SPACING = 1
local TOOLTIP_SECTION_GAP = 2
local TOOLTIP_OUTER_PAD_X = 3
local TOOLTIP_OUTER_PAD_Y = 3
local RARITY_BADGE_PAD_X = 10
local RARITY_BADGE_PAD_Y = 3

local function split_tooltip_override(s)
    if type(s) ~= "string" or s == "" then return nil end
    local lines = {}
    for line in string.gmatch(s, "[^\r\n]+") do
        table.insert(lines, { kind = "text", text = line })
    end
    if #lines == 0 then return { { kind = "text", text = s } } end
    return lines
end

local HAND_NAME_PHRASES = {
    "flush five",
    "flush house",
    "five of a kind",
    "straight flush",
    "four of a kind",
    "two of a kind",
    "full house",
    "three of a kind",
    "two pair",
    "high card",
    "straight",
    "flush",
    "pair",
}

local function fmt_runtime_number(n, decimals)
    local d = tonumber(decimals) or 2
    local s = string.format("%." .. d .. "f", tonumber(n) or 0)
    s = s:gsub("%.?0+$", "")
    return s
end

local function append_segment(segments, text, color_key)
    if type(text) ~= "string" or text == "" then return end
    local last = segments[#segments]
    if last and last.color_key == color_key then
        last.text = last.text .. text
        return
    end
    table.insert(segments, { text = text, color_key = color_key })
end

local function apply_range(paints, priorities, s, e, color_key, prio)
    if type(s) ~= "number" or type(e) ~= "number" then return end
    s = math.max(1, math.floor(s))
    e = math.max(s, math.floor(e))
    prio = tonumber(prio) or 1
    for i = s, e do
        local old = priorities[i] or -1
        if prio >= old then
            priorities[i] = prio
            paints[i] = color_key
        end
    end
end

local function paint_phrase_ranges(text, paints, priorities, phrase, color_key, prio)
    local hay = string.lower(text)
    local needle = string.lower(phrase)
    local start_i = 1
    while true do
        local s, e = hay:find(needle, start_i, true)
        if not s then break end
        apply_range(paints, priorities, s, e, color_key, prio)
        start_i = e + 1
    end
end

local function paint_pattern_ranges(text, paints, priorities, pattern, color_key, prio)
    local start_i = 1
    while true do
        local s, e = text:find(pattern, start_i)
        if not s then break end
        apply_range(paints, priorities, s, e, color_key, prio)
        if e < start_i then
            start_i = start_i + 1
        else
            start_i = e + 1
        end
    end
end

local function build_semantic_segments_from_text(raw_text)
    local text = tostring(raw_text or "")
    text = text:gsub("%*", "")
    local len = #text
    if len <= 0 then
        return { { text = "", color_key = nil } }
    end

    local paints = {}
    local priorities = {}

    -- Requested semantic categories.
    paint_phrase_ranges(text, paints, priorities, "tarot", "PURPLE", 50)
    paint_phrase_ranges(text, paints, priorities, "hand size", "IMPORTANT", 55)
    paint_phrase_ranges(text, paints, priorities, "discard", "RED", 56)
    paint_phrase_ranges(text, paints, priorities, "discarded", "RED", 56)
    paint_pattern_ranges(text, paints, priorities, "%$%d+", "MONEY", 57)
    for _, hand_name in ipairs(HAND_NAME_PHRASES) do
        paint_phrase_ranges(text, paints, priorities, hand_name, "IMPORTANT", 58)
    end

    -- Chance/probability.
    paint_pattern_ranges(text, paints, priorities, "%d+/%d+:%s*", "CHANCE", 70)
    paint_pattern_ranges(text, paints, priorities, "%d+%s+[Ii][Nn]%s+%d+", "CHANCE", 70)
    paint_phrase_ranges(text, paints, priorities, "chance", "CHANCE", 70)
    paint_phrase_ranges(text, paints, priorities, "probabilities", "CHANCE", 70)

    -- Mult/chips requested styling.
    paint_pattern_ranges(text, paints, priorities, "[Xx]%d+[%d%.]*%s*[Mm]ult", "MULT", 80)
    paint_pattern_ranges(text, paints, priorities, "[%+%-]?%d+[%d%.]*%s*[Mm]ult", "MULT", 80)
    paint_pattern_ranges(text, paints, priorities, "[Mm]ult", "MULT", 78)
    paint_pattern_ranges(text, paints, priorities, "[%+%-]?%d+[%d%.]*%s*[Cc]hips", "CHIPS", 80)
    paint_pattern_ranges(text, paints, priorities, "[Cc]hips", "CHIPS", 78)

    local segments = {}
    local current_color = paints[1]
    local run_start = 1
    for i = 2, len + 1 do
        local next_color = paints[i]
        if i == (len + 1) or next_color ~= current_color then
            append_segment(segments, text:sub(run_start, i - 1), current_color)
            run_start = i
            current_color = next_color
        end
    end
    if #segments <= 0 then
        return { { text = text, color_key = nil } }
    end
    return segments
end

local function describe_joker_effect_lines(joker)
    local et = joker.effect_type
    local cfg = joker.effect_config or {}
    if et == nil then
        return { "No effect description yet." }
    end
    if et == "Hand card double" then
        return { "Retrigger all held in hand abilities" }
    end
    if et == "Low Card double" then
        return { "Retrigger each played 2, 3, 4, and 5" }
    end
    if et == "Face card double" then
        return { "Retrigger played face cards" }
    end
    if et == "Mult" then
        local n = tonumber(cfg.mult) or 0
        return { string.format("+%d mult", n) }
    end
    if et == "Chips" then
        local n = tonumber(cfg.chips) or 0
        return { string.format("+%d chips", n) }
    end
    if et == "Suit Mult" then
        local extra = type(cfg.extra) == "table" and cfg.extra or {}
        local n = tonumber(extra.s_mult) or 0
        local suit = extra.suit or "?"
        return { string.format("Played cards with %s suit give +%d mult when scored", suit, n) }
    end
    if et == "Suit Chips" then
        local extra = type(cfg.extra) == "table" and cfg.extra or {}
        local n = tonumber(extra.s_chips) or 0
        local suit = extra.suit or "?"
        return { string.format("Played cards with %s suit give +%d chips when scored", suit, n) }
    end
    if et == "Type Mult" then
        local n = tonumber(cfg.t_mult) or 0
        local ht = cfg.type or "hand"
        return { string.format("+%d mult if played hand contains a %s", n, ht) }
    end
    if et == "Type Chips" then
        local n = tonumber(cfg.t_chips) or 0
        local ht = cfg.type or "hand"
        return { string.format("+%d chips if played hand contains a %s", n, ht) }
    end
    if et == "Hand Size Mult" then
        local extra = type(cfg.extra) == "table" and cfg.extra or {}
        local max_size = tonumber(extra.size) or 3
        local n = tonumber(extra.mult) or tonumber(cfg.mult) or 0
        return { string.format("+%d mult if played hand has at most %d cards", n, max_size) }
    end
    if et == "Stencil Mult" then
        local free = tonumber(joker.free_joker_slots)
        if free == nil and G then
            local cap = tonumber(G.joker_capacity) or tonumber(G.joker_slot_count) or 0
            local used = (type(G.jokers) == "table") and #G.jokers or 0
            free = math.max(0, cap - used)
        end
        free = tonumber(free) or 0
        return {
            "x1 mult for each empty Joker slot",
            string.format("Currently ×%d mult", free + 1),
        }
    end
    if et == "Discard Chips" then
        local n = tonumber(cfg.extra) or 0
        return { string.format("+%d chips for each remaining discard", n) }
    end
    if et == "No Discard Mult" then
        local extra = type(cfg.extra) == "table" and cfg.extra or {}
        local n = tonumber(extra.mult) or tonumber(cfg.mult) or 0
        return { string.format("+%d mult when 0 discards remaining", n) }
    end
    if et == "Stone card hands" then
        return { "Adds one Stone card to the deck when Blind is selected" }
    end
    if et == "1 in 6 mult" or et == "1 in 10 mult" then
        local extra = type(cfg.extra) == "table" and cfg.extra or {}
        local every = math.max(1, tonumber(extra.every) or 6)
        local xm = tonumber(extra.Xmult) or tonumber(cfg.Xmult) or 1
        local remaining = tonumber(joker.loyalty_remaining) or every
        return {
            string.format("X%d mult every %dth hand played", xm, every),
            string.format("%d remaining", remaining)
        }
    end
    if et == "Destroy Joker" then
        return {
            "When Blind is selected, destroy Joker to the right and",
            "permanently add double its sell value to this Mult",
            string.format("Currently +%d mult", joker.stored_mult)
        }
    end
    return { { kind = "text", text = tostring(et) } }
end

local function get_full_deck_starting_size()
    if G and G.STARTING_DECK_SIZE then
        return tonumber(G.STARTING_DECK_SIZE) or 52
    end
    return 52
end

function Joker:get_live_current_tooltip_text(base_text)
    local id = self.def and self.def.id or nil
    if type(id) ~= "string" then return base_text end

    local multipliers = {
        j_stencil = function(j)
            local free = tonumber(j.free_joker_slots)
            if free == nil and G then
                local cap = tonumber(G.joker_capacity) or tonumber(G.joker_slot_count) or 0
                local used = (type(G.jokers) == "table") and #G.jokers or 0
                free = math.max(0, cap - used)
            end
            free = tonumber(free) or 0
            return string.format("(Currently X%s)", fmt_runtime_number(free + 1, 2))
        end,
        j_steel_joker = function(j) return "(Currently X" .. fmt_runtime_number(j.stored_xmult or 1, 2) .. " Mult)" end,
        j_constellation = function(j) return "(Currently X" .. fmt_runtime_number(j.stored_xmult or 1, 2) .. " Mult)" end,
        j_madness = function(j) return "(Currently X" .. fmt_runtime_number(j.stored_xmult or 1, 2) .. " Mult)" end,
        j_vampire = function(j) return "(Currently X" .. fmt_runtime_number(j.stored_xmult or 1, 2) .. " Mult)" end,
        j_hologram = function(j) return "(Currently X" .. fmt_runtime_number(j.stored_xmult or 1, 2) .. " Mult)" end,
        j_obelisk = function(j) return "(Currently X" .. fmt_runtime_number(j.stored_xmult or 1, 2) .. " Mult)" end,
        j_throwback = function(j)
            local skipped = tonumber(j.runtime_counter) or 0
            local x = 1 + (0.25 * skipped)
            return "(Currently X" .. fmt_runtime_number(x, 2) .. " Mult)"
        end,
        j_glass = function(j) return "(Currently X" .. fmt_runtime_number(j.stored_xmult or 1, 2) .. " Mult)" end,
        j_hit_the_road = function(j) return "(Currently X" .. fmt_runtime_number(j.stored_xmult or 1, 2) .. " Mult)" end,
    j_canio = function(j) return "(Currently X" .. fmt_runtime_number(j.stored_xmult or 1, 2) .. " Mult)" end,
        j_yorick = function(j) return "(Currently X" .. fmt_runtime_number(j.stored_xmult or 1, 2) .. " Mult)" end,
        j_lucky_cat = function(j) return "(Currently X" .. fmt_runtime_number(j.stored_xmult or 1, 2) .. " Mult)" end,
        j_campfire = function(j) return "(Currently X" .. fmt_runtime_number(j.stored_xmult or 1, 2) .. " Mult)" end,
        j_ramen = function(j)
            local x = tonumber(j.runtime_counter) or 2
            return "(Currently X" .. fmt_runtime_number(x, 2) .. " Mult)"
        end,
    }
    if multipliers[id] then
        return multipliers[id](self)
    end

    local mults = {
        j_ceremonial = function(j) return string.format("(Currently +%d Mult)", math.floor(tonumber(j.stored_mult) or 0)) end,
        j_abstract = function() return string.format("(Currently +%d Mult)", 3 * ((G and G.jokers and #G.jokers) or 0)) end,
        j_ride_the_bus = function(j) return string.format("(Currently +%d Mult)", math.floor(tonumber(j.runtime_counter) or 0)) end,
        j_green_joker = function(j) return string.format("(Currently +%d Mult)", math.floor(tonumber(j.stored_mult) or 0)) end,
        j_red_card = function(j) return string.format("(Currently +%d Mult)", math.floor(tonumber(j.stored_mult) or 0)) end,
        j_erosion = function()
            local cnt = count_full_deck()
            local start_size = get_full_deck_starting_size()
            return string.format("(Currently +%d Mult)", math.max(0, (start_size - cnt) * 4))
        end,
        j_swashbuckler = function(j)
            local total = 0
            for _, owned in ipairs((G and G.jokers) or {}) do
                if owned and owned ~= j then
                    total = total + (tonumber(owned.sell_cost) or 0)
                end
            end
            return string.format("(Currently +%d Mult)", math.floor(total))
        end,
        j_bootstraps = function() return string.format("(Currently +%d Mult)", math.floor((tonumber(G and G.money) or 0) / 5) * 2) end,
        j_flash_card = function(j) return string.format("(Currently +%d Mult)", math.floor(tonumber(j.stored_mult) or 0)) end,
        j_spare_trousers = function(j) return string.format("(Currently +%d Mult)", math.floor(tonumber(j.stored_mult) or 0)) end,
        j_fortune_teller = function(j) return string.format("(Currently +%d)", math.floor(tonumber(j.stored_mult) or 0)) end,
    }
    if mults[id] then
        return mults[id](self)
    end

    local chips = {
        j_ice_cream = function(j)
            local n = math.max(0, math.floor(tonumber(j.runtime_counter) or 0))
            return string.format("(Currently +%d Chips)", n)
        end,
        j_runner = function(j) return string.format("(Currently +%d Chips)", math.floor(tonumber(j.stored_chips) or 0)) end,
        j_blue_joker = function() return string.format("(Currently +%d Chips)", 2 * count_full_deck()) end,
        j_square = function(j) return string.format("(Currently +%d Chips)", math.floor(tonumber(j.stored_chips) or 0)) end,
        j_wee = function(j) return string.format("(Currently +%d Chips)", math.floor(tonumber(j.stored_chips) or 0)) end,
        j_stone_joker = function() return string.format("(Currently +%d Chips)", 25 * count_full_deck(function(c) return c.enhancement == "stone" end)) end,
        j_bull = function() return string.format("(Currently +%d Chips)", 2 * (tonumber(G and G.money) or 0)) end,
    }
    if chips[id] then
        return chips[id](self)
    end

    if id == "j_cloud_9" then
        return string.format("(Currently $%d)", count_full_deck(function(c) return tonumber(c.rank) == 9 end))
    end
    if id == "j_rocket" then
        local n = math.max(1, math.floor(tonumber(self.running_count) or 1))
        return string.format("(Currently $%d)", n)
    end
    if id == "j_mail" then
        local r = tonumber(self.random_rank)
        local label = "—"
        if r == 14 then
            label = "Ace"
        elseif r == 13 then
            label = "King"
        elseif r == 12 then
            label = "Queen"
        elseif r == 11 then
            label = "Jack"
        elseif r ~= nil then
            label = tostring(r)
        end
        return string.format("Earn *$5* for each discarded *%s*,", label)
    end
    if id == "j_idol" then
        local r = tonumber(self.random_rank)
        local label = "—"
        if r == 14 then
            label = "Ace"
        elseif r == 13 then
            label = "King"
        elseif r == 12 then
            label = "Queen"
        elseif r == 11 then
            label = "Jack"
        elseif r ~= nil then
            label = tostring(r)
        end
        local s = self.random_suit
        if type(s) ~= "string" or s == "" then
            s = "—"
        end
        return string.format("Each played *%s* of *%s* gives *X3 Mult* when scored,", label, s)
    end
    if id == "j_invisible" then
        return string.format("(Currently %d/2)", math.floor(tonumber(self.runtime_counter) or 0))
    end
    if id == "j_drivers_license" then
        local enhanced = count_full_deck(function(c) return c.enhancement ~= nil and c.enhancement ~= "" end)
        return string.format("(Currently %d)", enhanced)
    end
    if id == "j_loyalty_card" then
        local remaining = tonumber(self.loyalty_remaining) or 6
        return string.format("%d remaining", math.floor(remaining))
    end
    if id == "j_ancient_joker" then
        local s = self.random_suit
        if type(s) ~= "string" or s == "" then
            s = "—"
        end
        return string.format("Each played card with %s gives X1.5 Mult when scored", s)
    end
    if id == "j_seltzer" then
        local n = math.max(0, math.floor(tonumber(self.runtime_counter) or 0))
        if n == 1 then
            return "(Currently 1 hand remaining)"
        end
        return string.format("(Currently %d hands remaining)", n)
    end
    if id == "j_turtle_bean" then
        local n = math.max(0, math.floor(tonumber(self.runtime_counter) or 0))
        return string.format("(Currently +%d hand size)", n)
    end
    if id == "j_castle" then
        local bt = tostring(base_text or "")
        if bt:find("(Currently", 1, true) then
            return string.format("(Currently +%d Chips)", math.floor(tonumber(self.runtime_counter) or 0))
        end
        local s = self.random_suit
        if type(s) ~= "string" or s == "" then
            s = "—"
        end
        return string.format("This Joker gains +3 Chips per discarded %s", s)
    end
    if id == "j_todo_list" then
        local rh = self.random_hand
        if type(rh) ~= "string" or rh == "" then
            rh = "—"
        end
        return string.format("Earn *$4* if poker hand is a *%s*,", rh)
    end
    return base_text
end

function Joker:get_edition_tooltip_lines()
    local ed = Joker.normalize_edition(self.edition)
    if ed == "base" then return {} end
    if ed == "foil" then return { { kind = "text", text = "Foil: +50 Chips when hand is scored" } } end
    if ed == "holo" then return { { kind = "text", text = "Holographic: +10 Mult when hand is scored" } } end
    if ed == "polychrome" then return { { kind = "text", text = "Polychrome: ×1.5 Mult when hand is scored" } } end
    if ed == "negative" then return { { kind = "text", text = "Negative: +1 Joker slot" } } end
    return {}
end

function Joker:get_tooltip_body_lines()
    local def = self.def or {}
    local edition_lines = self:get_edition_tooltip_lines()
    local impl = self.effect_impl
    local function append_edition(lines)
        for _, el in ipairs(edition_lines) do
            table.insert(lines, el)
        end
        return lines
    end
    if type(def.tooltip) == "table" then
        local out = {}
        for _, l in ipairs(def.tooltip) do
            if type(l) == "string" then
                table.insert(out, { kind = "text", text = l })
            elseif type(l) == "table" then
                table.insert(out, l)
            end
        end
        if #out > 0 then
            if impl and type(impl.tooltip_lines) == "function" then
                local extra = impl.tooltip_lines(self)
                if type(extra) == "table" then
                    for _, line in ipairs(extra) do
                        if type(line) == "string" then
                            table.insert(out, { kind = "text", text = line })
                        elseif type(line) == "table" then
                            table.insert(out, line)
                        end
                    end
                end
            end
            return append_edition(out)
        end
    end
    if type(def.tooltip) == "string" then
        local lines = split_tooltip_override(def.tooltip)
        if lines then return append_edition(lines) end
    end
    local base_lines = describe_joker_effect_lines(self)
    if impl and type(impl.tooltip_lines) == "function" then
        local extra = impl.tooltip_lines(self)
        if type(extra) == "table" then
            for _, line in ipairs(extra) do
                if type(line) == "string" then
                    table.insert(base_lines, { kind = "text", text = line })
                elseif type(line) == "table" then
                    table.insert(base_lines, line)
                end
            end
        end
    end
    return append_edition(base_lines)
end

local function tooltip_color_by_key(color_key)
    if not color_key then
        return { 0.22, 0.24, 0.26, 1 }
    end
    local C = (G and G.C) or {}
    if color_key == "MULT" then return C.MULT or { 0.9, 0.3, 0.4, 1 } end
    if color_key == "CHIPS" then return C.CHIPS or { 0.3, 0.7, 1, 1 } end
    if color_key == "CHANCE" then return C.CHANCE or C.GREEN or { 0.2, 0.75, 0.55, 1 } end
    if color_key == "PURPLE" then return C.PURPLE or { 0.66, 0.51, 0.82, 1 } end
    if color_key == "IMPORTANT" then return C.IMPORTANT or { 1, 0.6, 0.0, 1 } end
    if color_key == "MONEY" then return C.MONEY or { 0.9, 0.8, 0.2, 1 } end
    if color_key == "RED" then return C.RED or { 0.996, 0.373, 0.333, 1 } end
    if color_key == "MONEY" then return C.MONEY or { 0.996, 0.373, 0.333, 1 } end
    return { 0.22, 0.24, 0.26, 1 }
end

function Joker:resolve_tooltip_line_segments(line_def)
    if type(line_def) == "string" then
        return build_semantic_segments_from_text(line_def)
    end
    if type(line_def) ~= "table" then
        return { { text = tostring(line_def or ""), color_key = nil } }
    end
    if type(line_def.segments) == "table" then
        local out = {}
        for _, seg in ipairs(line_def.segments) do
            if type(seg) == "table" then
                local text = tostring(seg.text or seg[1] or "")
                local color_key = seg.color_key or seg[2]
                append_segment(out, text, color_key)
            end
        end
        if #out > 0 then return out end
    end

    if line_def.kind == "rarity_badge" then
        local r = tonumber(line_def.rarity) or 1
        if r < 1 then r = 1 end
        if r > 4 then r = 4 end
        local text = tostring(line_def.text or "")
        return { { text = text, rarity_badge = true, rarity_index = r } }
    end

    local text = tostring(line_def.text or "")
    if line_def.kind == "current" then
        text = self:get_live_current_tooltip_text(text)
    end
    return build_semantic_segments_from_text(text)
end

function Joker:draw_tooltip(draw_x, draw_y)
    local def = self.def or {}
    local title = self.name or def.name or "Joker"
    local lines = self:get_tooltip_body_lines()
    local font = G.FONTS.PIXEL.SMALL or love.graphics.getFont()
    local prev_font = love.graphics.getFont()
    local prev_r, prev_g, prev_b, prev_a = love.graphics.getColor()
    love.graphics.setFont(font)

    local resolved_lines = {}
    for _, line in ipairs(lines) do
        table.insert(resolved_lines, self:resolve_tooltip_line_segments(line))
    end

    local header_w = font:getWidth(title)
    local line_h = font:getHeight()
    local body_line_heights = {}
    local body_max_w = 0
    for _, segments in ipairs(resolved_lines) do
        local w = 0
        if #segments == 1 and segments[1].rarity_badge then
            local seg = segments[1]
            w = font:getWidth(seg.text or "") + RARITY_BADGE_PAD_X * 2
            body_line_heights[#body_line_heights + 1] = line_h + RARITY_BADGE_PAD_Y * 2
        else
            for _, seg in ipairs(segments) do
                w = w + font:getWidth(seg.text or "")
            end
            body_line_heights[#body_line_heights + 1] = line_h
        end
        if w > body_max_w then body_max_w = w end
    end
    local body_lines_total_h = 0
    for i, h in ipairs(body_line_heights) do
        body_lines_total_h = body_lines_total_h + h
        if i < #body_line_heights then
            body_lines_total_h = body_lines_total_h + TOOLTIP_SPACING
        end
    end
    local first_is_rarity = #resolved_lines > 0
        and resolved_lines[1][1]
        and resolved_lines[1][1].rarity_badge == true
    local body_pad_top = first_is_rarity and TOOLTIP_BODY_PAD_TOP_RARITY or TOOLTIP_BODY_PAD_Y
    local header_w_total = header_w + (TOOLTIP_PAD_X * 2)
    local header_h_total = line_h + (TOOLTIP_HEADER_PAD_Y * 2)
    local body_w_total = body_max_w + (TOOLTIP_PAD_X * 2)
    local body_h_total = body_lines_total_h + body_pad_top + TOOLTIP_BODY_PAD_Y
    local inner_w = math.max(header_w_total, body_w_total)
    local inner_h = header_h_total + TOOLTIP_SECTION_GAP + body_h_total
    local box_w = inner_w + (TOOLTIP_OUTER_PAD_X * 2)
    local box_h = inner_h + (TOOLTIP_OUTER_PAD_Y * 2)

    local card_w = self.VT.w * self.VT.scale
    local card_h = self.VT.h * self.VT.scale
    local tx = draw_x + (card_w - box_w) * 0.5
    -- Cards show tooltips above; jokers show them below the sprite.
    local ty = draw_y + card_h + 3
    local margin = 2
    local sw = 320
    if love.graphics.getWidth then
        sw = love.graphics.getWidth("bottom")
        if not sw or sw <= 0 then sw = love.graphics.getWidth() end
        if not sw or sw <= 0 then sw = 320 end
    end
    tx = math.max(margin, math.min(tx, sw - box_w - margin))
    local sh = nil
    if love.graphics.getHeight then
        sh = love.graphics.getHeight("bottom")
        if not sh or sh <= 0 then
            sh = love.graphics.getHeight()
        end
    end
    if not sh or sh <= 0 then sh = 240 end
    if ty + box_h > sh - 2 then
        ty = draw_y - box_h - 3
    end
    if ty < 2 then ty = 2 end
    tx = math.floor(tx + 0.5)
    ty = math.floor(ty + 0.5)

    draw_rect_with_shadow(tx, ty, box_w, box_h, 4, 0, G.C.TOOLTIP, G.C.BLOCK.SHADOW, 1)
    love.graphics.setColor(1, 1, 1, 1)
    draw_rounded_rect(tx, ty, box_w, box_h, 4, 2, "line")

    local header_x = tx + TOOLTIP_OUTER_PAD_X
    local header_y = ty + TOOLTIP_OUTER_PAD_Y
    local body_x = header_x
    local body_y = header_y + header_h_total + TOOLTIP_SECTION_GAP

    love.graphics.setColor(G.C.TOOLTIP)
    draw_rounded_rect(header_x, header_y, inner_w, header_h_total, 4, 0, "fill")
    draw_rounded_rect(body_x, body_y, inner_w, body_h_total, 4, 0, "fill")

    local inner_pad = 2
    local inner_header_h = math.max(1, header_h_total - (inner_pad * 2))
    local inner_body_h = math.max(1, body_h_total - (inner_pad * 2))
    love.graphics.setColor(G.C.WHITE)
    draw_rect_with_shadow(header_x + inner_pad, header_y + inner_pad, inner_w - (inner_pad * 2), inner_header_h, 4, 0, G.C.WHITE, G.C.DARK_WHITE, 1)
    draw_rect_with_shadow(body_x + inner_pad, body_y + inner_pad - 1, inner_w - (inner_pad * 2), inner_body_h, 4, 0, G.C.WHITE, G.C.DARK_WHITE, 1)

    local header_text_y = header_y + math.floor((header_h_total - line_h) * 0.5 + 0.5)
    local header_text_x = header_x + math.floor((inner_w - header_w) * 0.5 + 0.5)
    love.graphics.setColor(G.C.PANEL)
    love.graphics.print(title, header_text_x, header_text_y)

    local text_y = body_y + body_pad_top
    local function draw_segments_centered(segments, line_y)
        local total_w = 0
        for _, seg in ipairs(segments) do
            total_w = total_w + font:getWidth(seg.text or "")
        end
        local x = body_x + math.floor((inner_w - total_w) * 0.5 + 0.5)
        for _, seg in ipairs(segments) do
            local t = seg.text or ""
            local col = tooltip_color_by_key(seg.color_key)
            love.graphics.setColor(col[1], col[2], col[3], col[4])
            love.graphics.print(t, x, line_y)
            x = x + font:getWidth(t)
        end
    end

    for i, segments in ipairs(resolved_lines) do
        local row_h = body_line_heights[i] or line_h
        if #segments == 1 and segments[1].rarity_badge then
            local seg = segments[1]
            local label = seg.text or ""
            local ri = tonumber(seg.rarity_index) or 1
            local rc = (G and G.C and G.C.RARITY and G.C.RARITY[ri]) or { 0.035, 0.62, 1, 1 }
            local bw = font:getWidth(label) + RARITY_BADGE_PAD_X * 2
            local x0 = body_x + math.floor((inner_w - bw) * 0.5 + 0.5)
            love.graphics.setColor(rc[1], rc[2], rc[3], rc[4] or 1)
            draw_rounded_rect(x0, text_y, bw, row_h, 4, 0, "fill")
            local text_x = x0 + RARITY_BADGE_PAD_X
            local text_y_row = text_y + math.floor((row_h - line_h) * 0.5 + 0.5)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.print(label, text_x, text_y_row)
        else
            local line_y = math.floor(text_y + (row_h - line_h) * 0.5 + 0.5)
            draw_segments_centered(segments, line_y)
        end
        text_y = text_y + row_h + TOOLTIP_SPACING
    end

    love.graphics.setFont(prev_font)
    love.graphics.setColor(prev_r, prev_g, prev_b, prev_a)
end


function Joker:get_layout_draw_xy()
    local draw_x = self.VT.x + self.collision_offset.x
    local draw_y = self.VT.y + self.collision_offset.y
    if G and G.active_tooltip_joker == self and self.shop_offer_slot == nil then
        draw_y = draw_y - 8
    end

    if self.scoring_shake_timer and self.scoring_shake_timer > 0 then
        local mag = SHAKE_MAGNITUDE * (self.scoring_shake_timer / SHAKE_MAX_DURATION)
        local t = love.timer.getTime()
        if self.scoring_shake_t0 then
            t = t - self.scoring_shake_t0
        end
        draw_x = draw_x + math.sin(t * 85) * mag
        draw_y = draw_y + math.cos(t * 73) * mag * 0.65
    end
    return draw_x, draw_y
end

function Joker:should_draw_tooltip()
    if not self.face_up or not G then return false end
    if self._booster_choice_index and G.STATE == G.STATES.OPEN_BOOSTER and G.booster_session then
        return tonumber(G.booster_session.active_choice_index) == self._booster_choice_index
    end
    return G.active_tooltip_joker == self
        and (G.jokers_on_bottom == true or self.shop_offer_slot ~= nil)
end

function Joker:draw_tooltip_overlay()
    if not self.states.visible or not self:should_draw_tooltip() then return end
    local draw_x, draw_y = self:get_layout_draw_xy()
    self:draw_tooltip(draw_x, draw_y)
end

function Joker:draw()
    if not self.states.visible then return end

    local prev_draw_r, prev_draw_g, prev_draw_b, prev_draw_a = love.graphics.getColor()
    love.graphics.setColor(1, 1, 1, 1)

    local draw_x, draw_y = self:get_layout_draw_xy()

    love.graphics.push()

    local cx = draw_x + (self.VT.w * self.VT.scale) / 2
    local cy = draw_y + (self.VT.h * self.VT.scale) / 2
    love.graphics.translate(cx, cy)
    love.graphics.rotate(self.VT.r)
    love.graphics.scale(self.VT.scale, self.VT.scale)
    love.graphics.translate(-cx, -cy)

    if self.face_up then
        if self.front_atlas and self.front_atlas.image and self.front_quad then
            local ed = Joker.normalize_edition(self.edition)
            local function draw_atlas_front()
                love.graphics.draw(self.front_atlas.image, self.front_quad, draw_x, draw_y, 0, 1, 1)
            end

            if ed == "foil" then
                love.graphics.setColor(0.62, 0.78, 1.12, 1)
                draw_atlas_front()
            elseif ed == "holo" then
                love.graphics.setColor(1.15, 0.55, 0.55, 1)
                draw_atlas_front()
            elseif ed == "polychrome" then
                polychrome_edition_set_color()
                draw_atlas_front()
            else
                love.graphics.setColor(1, 1, 1, 1)
                draw_atlas_front()
            end
            love.graphics.setColor(1, 1, 1, 1)
        end
    else
        if self.back_atlas and self.back_atlas.image and self.back_quad then
            love.graphics.draw(self.back_atlas.image, self.back_quad, draw_x, draw_y, 0, 1, 1)
        end
    end

    if joker_is_debuffed_for_display(self) then
        draw_debuff_x_overlay(draw_x, draw_y, self.VT.w, self.VT.h)
    end

    love.graphics.pop()

    love.graphics.setColor(prev_draw_r, prev_draw_g, prev_draw_b, prev_draw_a)

    -- Debug bounding box.
    self:draw_boundingrect()

    love.graphics.setColor(prev_draw_r, prev_draw_g, prev_draw_b, prev_draw_a)
end

function Joker:update(dt)
    Moveable.update(self, dt)
    if joker_front_quads_signature(self) ~= self._quads_refresh_signature then
        self:refresh_quads()
    end
    if self.scoring_shake_timer and self.scoring_shake_timer > 0 then
        self.scoring_shake_timer = self.scoring_shake_timer - dt
        if self.scoring_shake_timer < 0 then self.scoring_shake_timer = 0 end
        if self.scoring_shake_timer <= 0 then self.scoring_shake_t0 = nil end
    end
end

-- Event-based trigger hook for data-driven joker effects.
-- `event_name` is something like: "on_hand_scored"
-- `ctx` is the runtime scoring context.
function Joker:matches_trigger(event_name, ctx)
    if self.effect_impl and type(self.effect_impl.matches_trigger) == "function" then
        return self.effect_impl.matches_trigger(self, event_name, ctx) == true
    end
    return false
end

--- Foil / Holo / Polychrome modify chips or mult when the scored hand is finalized (not Negative).
function Joker:apply_edition_on_hand_scored(ctx)
    if type(ctx) ~= "table" then return end
    local ed = Joker.normalize_edition(self.edition)
    if ed == "base" or ed == "negative" then return end
    if ed == "foil" then
        ctx.chips = (tonumber(ctx.chips) or 0) + 50
        Sfx.play("resources/sounds/foil2.ogg")
    elseif ed == "holo" then
        ctx.mult = (tonumber(ctx.mult) or 0) + 10
        Sfx.play_mult()
    elseif ed == "polychrome" then
        ctx.mult = (tonumber(ctx.mult) or 0) * 1.5
        Sfx.play("resources/sounds/polychrome.ogg")
    else
        return
    end

    self.scoring_shake_timer = SHAKE_MAX_DURATION
    self.scoring_shake_t0 = love.timer.getTime()
    if ed == "foil" and Sfx and Sfx.play_chips then
        Sfx.play_chips()
    elseif ed == "polychrome" and Sfx and Sfx.play_mult2 then
        Sfx.play_mult2()
    elseif Sfx and Sfx.play_mult then
        Sfx.play_mult()
    end
end

function Joker:apply_effect(ctx)
    ctx = ctx or {}
    local before = capture_joker_runtime_snapshot(self)
    local before_chips = tonumber(ctx.chips)
    local before_mult = tonumber(ctx.mult)
    if JokerEffects and JokerEffects.begin_apply_context then
        JokerEffects.begin_apply_context(ctx)
    end
    if self.effect_impl and type(self.effect_impl.apply_effect) == "function" then
        self.effect_impl.apply_effect(self, ctx)
    end
    local after = capture_joker_runtime_snapshot(self)
    local state_changed, created = runtime_snapshot_delta(before, after)
    local after_chips = tonumber(ctx.chips)
    local after_mult = tonumber(ctx.mult)
    if before_chips ~= after_chips or before_mult ~= after_mult or state_changed then
        if JokerEffects and JokerEffects.mark_effect_applied then
            JokerEffects.mark_effect_applied(ctx)
        end
    end
    if created and JokerEffects and JokerEffects.mark_created_item then
        JokerEffects.mark_created_item(ctx)
    end
    if JokerEffects and JokerEffects.apply_shake_if_needed then
        JokerEffects.apply_shake_if_needed(self, ctx)
    end
end

--- Extra scoring passes this joker contributes for the current card (used by `Game:sum_retrigger_extras`).
---@param ctx table|nil
---@return number
function Joker:query_retrigger(ctx)
    if self.effect_impl and type(self.effect_impl.query_retrigger) == "function" then
        return tonumber(self.effect_impl.query_retrigger(self, ctx)) or 0
    end
    return 0
end

