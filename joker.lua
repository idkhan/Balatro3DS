---@class Joker : Moveable
Joker = Moveable:extend()
require "joker_effects"
local TooltipDraw = require("tooltip_draw")

-- Basic 2-layer joker: back sprite (centers atlas) and front sprite (individual PNG).

local SHAKE_MAGNITUDE = 10
local SHAKE_MAX_DURATION = (JokerEffects and JokerEffects.SHAKE_MAX_DURATION) or 0.22
local JOKER_STICKER_ATLAS_NAME = "stickers"
local JOKER_STICKER_INDICES = {
    eternal = 0,
    rental = 11,
    perishable = 10,
}

Joker.SPRITE_W = 70
Joker.SPRITE_H = 94
Joker.WEE_JOKER_ID = "j_wee"
Joker.WEE_DISPLAY_SCALE = 0.75
local JOKER_SPRITE_W = Joker.SPRITE_W
local JOKER_SPRITE_H = Joker.SPRITE_H

local JOKER_PAGE_OFFSETS = {
    Joker1 = 0,
    Joker1_p1 = 0,
    Joker1_p2 = 24,
    Joker1_p3 = 48,
    Joker1_p4 = 72,
    Joker2 = 0,
    Joker2_p1 = 0,
    Joker2_p2 = 24,
    Joker2_p3 = 48,
}

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

local function as_truthy_flag(value)
    return value == true or value == 1 or value == "true" or value == "1"
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
        free_joker_slots = tonumber(joker and joker.free_joker_slots) or 0,
        money = tonumber((G or {}).money) or 0,
        joker_count = (type((G or {}).jokers) == "table") and #G.jokers or 0,
        consumable_count = (type((G or {}).consumables) == "table") and #G.consumables or 0,
        hand_count = (type(hand_cards) == "table") and #hand_cards or 0,
        deck_count = (type(deck_cards) == "table") and #deck_cards or 0
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

local function count_cards_in_deck(pred)
    if G and G.count_cards_in_deck then
        return G:count_cards_in_deck(pred)
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

--- Individual sprite key under `resources/textures/1x/Jokers/` (e.g. `"Jokers1_17"` or `"Jokers1_negative_17"`).
---@param atlas_name string|nil
---@param index number|nil 0-based cell index from the legacy atlas layout
---@param edition string|nil raw edition; negative loads the `_negative_` sprite variant
---@return string|nil
function Joker.sprite_key_from_pos(atlas_name, index, edition)
    if not atlas_name then return nil end
    local atlas = tostring(atlas_name)
    local set = string.find(atlas, "Joker2", 1, true) and "2" or "1"
    local off = JOKER_PAGE_OFFSETS[atlas] or 0
    local num = off + (tonumber(index) or 0) + 1
    if Joker.normalize_edition(edition) == "negative" then
        return "Jokers" .. set .. "_negative_" .. num
    end
    return "Jokers" .. set .. "_" .. num
end

local function joker_front_sprite_signature(joker)
    return tostring(joker.front_sprite_key or joker.front_atlas_name) .. "\0" .. Joker.normalize_edition(joker.edition)
end

-- Edition visuals: foil/holo/polychrome use multiply tint; negative uses a dedicated sprite.

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
    if joker and joker.is_sticker_debuffed and joker:is_sticker_debuffed() then
        return true
    end
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

local function resolve_joker_sprite(key)
    if not key or not G or not G.ensure_joker_sprite_loaded then return nil end
    return G:ensure_joker_sprite_loaded(key)
end

function Joker.is_wee_def(def)
    return type(def) == "table" and def.id == Joker.WEE_JOKER_ID
end

function Joker:get_display_scale_mult()
    return Joker.is_wee_def(self.def) and Joker.WEE_DISPLAY_SCALE or 1
end

function Joker:get_render_scale()
    return (self.VT and self.VT.scale or 1) * self:get_display_scale_mult()
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

    local sticker_def = self.params and self.params.stickers or self.def and self.def.stickers
    if type(sticker_def) ~= "table" then sticker_def = nil end
    self.perishable = as_truthy_flag(self.params.perishable)
        or as_truthy_flag(self.def.perishable)
        or as_truthy_flag(sticker_def and sticker_def.perishable)
    self.rental = as_truthy_flag(self.params.rental)
        or as_truthy_flag(self.def.rental)
        or as_truthy_flag(sticker_def and sticker_def.rental)
    self.eternal = as_truthy_flag(self.params.eternal)
        or as_truthy_flag(self.def.eternal)
        or as_truthy_flag(sticker_def and sticker_def.eternal)

    -- Runtime accumulator for effects that grow over time (e.g. Ceremonial Dagger).
    self.stored_mult = tonumber(self.effect_config.mult) or 0
    self.stored_chips = tonumber(self.effect_config.chips) or 0
    self.stored_xmult = tonumber(self.effect_config.Xmult) or 1
    self.runtime_counter = 0
    self.free_joker_slots = nil
    self.perishable_counter = 5

    self.effect_impl = JokerEffects.get(self)

    if type(self.def) == "table" then
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
        elseif self.def.id == "j_rocket" then
            local ex = type(self.def.config) == "table" and self.def.config.extra
            self.running_count = math.max(1, math.floor(tonumber(ex and ex.dollars) or 1))
        elseif self.def.id == "j_loyalty_card" then
            local extra = type(self.effect_config.extra) == "table" and self.effect_config.extra or {}
            local every = math.max(1, tonumber(extra.every) or 6)
            self.runtime_counter = every
        end
    end

    local cw = W or JOKER_SPRITE_W
    local ch = H or JOKER_SPRITE_H
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
    local old_front_sprite_key = self._front_atlas_ref_name

    self.front_sprite_key = Joker.sprite_key_from_pos(self.front_atlas_name, self.front_index, self.edition)
    self.front_sprite = resolve_joker_sprite(self.front_sprite_key)
    if Joker.normalize_edition(self.edition) == "negative" then
        if not self.front_sprite or not self.front_sprite.image then
            self.front_sprite_key = Joker.sprite_key_from_pos(self.front_atlas_name, self.front_index)
            self.front_sprite = resolve_joker_sprite(self.front_sprite_key)
        end
    end
    self.front_w = JOKER_SPRITE_W
    self.front_h = JOKER_SPRITE_H

    self.back_atlas = resolve_atlas(self.back_atlas_name)
    self.back_quad, self.back_w, self.back_h = compute_quad(self.back_atlas, self.back_index)
    self._front_atlas_ref_name = self.front_sprite_key

    local sub = self.params.sub_pos or self.def.sub_pos
    if type(sub) == "table" and sub.atlas and sub.index ~= nil then
        self.sub_atlas_name = sub.atlas
        self.sub_index = tonumber(sub.index) or 0
        if string.find(tostring(sub.atlas), "Joker", 1, true) then
            self.sub_sprite_key = Joker.sprite_key_from_pos(sub.atlas, self.sub_index)
            self.sub_sprite = resolve_joker_sprite(self.sub_sprite_key)
            self.sub_atlas = nil
            self.sub_quad = nil
        else
            self.sub_sprite_key = nil
            self.sub_sprite = nil
            self.sub_atlas = resolve_atlas(self.sub_atlas_name)
            self.sub_quad = compute_quad(self.sub_atlas, self.sub_index)
        end
    else
        self.sub_atlas_name = nil
        self.sub_index = nil
        self.sub_sprite_key = nil
        self.sub_sprite = nil
        self.sub_atlas = nil
        self.sub_quad = nil
    end

    self.sticker_atlas = resolve_atlas(JOKER_STICKER_ATLAS_NAME)
    self.sticker_quads = {}
    self.sticker_w = 0
    self.sticker_h = 0
    if self.sticker_atlas and self.sticker_atlas.image then
        for name, index in pairs(JOKER_STICKER_INDICES) do
            local quad, w, h = compute_quad(self.sticker_atlas, index)
            self.sticker_quads[name] = quad
            if quad and (w or 0) > 0 and (h or 0) > 0 then
                self.sticker_w = math.max(self.sticker_w, w or 0)
                self.sticker_h = math.max(self.sticker_h, h or 0)
            end
        end
    end

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

    self._quads_refresh_signature = joker_front_sprite_signature(self)
    if G and G.on_joker_front_atlas_resolved then
        G:on_joker_front_atlas_resolved(self, old_front_sprite_key, self._front_atlas_ref_name)
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
    local s = self:get_render_scale()
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

local function split_tooltip_override(s)
    if type(s) ~= "string" or s == "" then return nil end
    local lines = {}
    for line in string.gmatch(s, "[^\r\n]+") do
        table.insert(lines, { kind = "text", text = line })
    end
    if #lines == 0 then return { { kind = "text", text = s } } end
    return lines
end

local function fmt_runtime_number(n, decimals)
    local d = tonumber(decimals) or 2
    local s = string.format("%." .. d .. "f", tonumber(n) or 0)
    s = s:gsub("%.?0+$", "")
    return s
end

local function joker_effect_kind(joker)
    local def = type(joker) == "table" and joker.def or {}
    local et = def.effect
    if type(et) == "string" then return et end
    if type(et) == "table" then
        if et.type == "add_mult" then return "Mult" end
        if et.type == "add_chips" then return "Chips" end
    end
    local cfg = joker.effect_config or {}
    if cfg.mult ~= nil then return "Mult" end
    if type(cfg.extra) == "table" and cfg.extra.s_mult ~= nil then return "Suit Mult" end
    if cfg.t_mult ~= nil then return "Type Mult" end
    if type(cfg.extra) == "table" and cfg.extra.s_chips ~= nil then return "Suit Chips" end
    if cfg.t_chips ~= nil then return "Type Chips" end
    return nil
end

local function rank_to_label(r)
    if r == 14 then
        return "Ace"
    elseif r == 13 then
        return "King"
    elseif r == 12 then
        return "Queen"
    elseif r ~= nil then
        return tostring(r)
    end
    return "-"
end

local function describe_joker_effect_lines(joker)
    local et = joker_effect_kind(joker)
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
        local remaining = tonumber(joker.runtime_counter) or every
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
        j_steel_joker = function(_)
            local steel = count_full_deck(function(c) return c.enhancement == "steel" end)
            local x = 1 + (0.2 * steel)
            return "(Currently X" .. fmt_runtime_number(x, 2) .. " Mult)"
        end,
        j_constellation = function(j) return "(Currently X" .. fmt_runtime_number(j.stored_xmult or 1, 2) .. " Mult)" end,
        j_madness = function(j) return "(Currently X" .. fmt_runtime_number(j.stored_xmult or 1, 2) .. " Mult)" end,
        j_vampire = function(j) return "(Currently X" .. fmt_runtime_number(j.stored_xmult or 1, 2) .. " Mult)" end,
        j_hologram = function(j) return "(Currently X" .. fmt_runtime_number(j.stored_xmult or 1, 2) .. " Mult)" end,
        j_obelisk = function(j) return "(Currently X" .. fmt_runtime_number(j.stored_xmult or 1, 2) .. " Mult)" end,
        j_throwback = function(_)
            local skipped = (G and tonumber(G.skipsTaken)) or 0
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
        j_fortune_teller = function() return string.format("(Currently +%d)", math.floor(tonumber(G and G.tarots_used) or 0)) end,
        j_popcorn = function(j) return string.format("+%d Mult", math.floor(tonumber(j.stored_mult) or 0)) end,
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
        j_blue_joker = function() return string.format("(Currently +%d Chips)", 2 * count_cards_in_deck()) end,
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
        local label = rank_to_label(r)
        return string.format("Earn *$5* for each discarded *%s*,", label)
    end
    if id == "j_idol" then
        local r = tonumber(self.random_rank)
        local label = rank_to_label(r)
        local s = self.random_suit
        if type(s) ~= "string" or s == "" then
            s = "-"
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
        local remaining = tonumber(self.runtime_counter) or 6
        return string.format("%d remaining", math.floor(remaining))
    end
    if id == "j_ancient_joker" then
        local s = self.random_suit
        if type(s) ~= "string" or s == "" then
            s = "-"
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
            s = "-"
        end
        return string.format("This Joker gains +3 Chips per discarded %s", s)
    end
    if id == "j_todo_list" then
        local rh = self.random_hand
        if type(rh) ~= "string" or rh == "" then
            rh = "-"
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
    local function append_extra(lines)
        if self.perishable == true then
            local remaining = math.max(0, math.floor(tonumber(self.perishable_counter) or 5))
            local unit = remaining == 1 and "round" or "rounds"
            table.insert(lines, { kind = "text", text = string.format("Perishable: %d %s remaining", remaining, unit) })
        end
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
            return append_extra(out)
        end
    end
    if type(def.tooltip) == "string" then
        local lines = split_tooltip_override(def.tooltip)
        if lines then return append_extra(lines) end
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
    return append_extra(base_lines)
end

function Joker:resolve_tooltip_line_segments(line_def)
    if type(line_def) == "string" then
        return TooltipDraw.build_segments_from_text(line_def)
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
                TooltipDraw.append_segment(out, text, color_key)
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
    return TooltipDraw.build_segments_from_text(text)
end

function Joker:draw_tooltip(draw_x, draw_y)
    local def = self.def or {}
    local title = self.name or def.name or "Joker"
    if G and G.is_discovered and def.id and not G:is_discovered(def.id) then
        title = "Not Discovered"
    end
    local lines = self:get_tooltip_body_lines()
    local font = G.FONTS.PIXEL.SMALL or love.graphics.getFont()
    local resolved_lines = {}
    for _, line in ipairs(lines) do
        table.insert(resolved_lines, self:resolve_tooltip_line_segments(line))
    end
    local card_w = self.VT.w * self:get_render_scale()
    local card_h = self.VT.h * self:get_render_scale()
    TooltipDraw.draw_tooltip_layout(font, title, resolved_lines, draw_x, draw_y, card_w, card_h)
end


function Joker:get_layout_draw_xy()
    local draw_x = self.VT.x + self.collision_offset.x
    local draw_y = self.VT.y + self.collision_offset.y
    if G and self.shop_offer_slot == nil and G.jokers_on_bottom then
        local lifted = (G.active_tooltip_joker == self)
            or (G.is_joker_swap_pick and G:is_joker_swap_pick(self))
        if lifted then
            draw_y = draw_y - 8
        end
    end

    if self.scoring_shake_timer and self.scoring_shake_timer > 0 then
        local mag = SHAKE_MAGNITUDE * (self.scoring_shake_timer / SHAKE_MAX_DURATION)
        local t = self.scoring_shake_phase or 0
        draw_x = draw_x + math.sin(t * 85) * mag
        draw_y = draw_y + math.cos(t * 73) * mag * 0.65
    end
    return draw_x, draw_y
end

function Joker:should_draw_tooltip()
    if not self.face_up or not G then return false end
    if G.is_hand_scoring_active and G:is_hand_scoring_active() then return false end
    if G._collection_open and G._collection_tooltip_node == self then return true end
    if G.is_card_select_mode and G:is_card_select_mode() then return false end
    if G.STATE == G.STATES.BLIND_SELECT and G.active_tooltip_skip_blind_index then return false end
    if self._booster_choice_index and G.STATE == G.STATES.OPEN_BOOSTER and G.booster_session then
        return tonumber(G.booster_session.active_choice_index) == self._booster_choice_index
    end
    if G.should_draw_gamepad_focus_outline and G:should_draw_gamepad_focus_outline(self) then
        return true
    end
    if G.is_shop_item_selected and G:is_shop_item_selected(self) then
        return true
    end
    return G.active_tooltip_joker == self
        and (G.jokers_on_bottom == true or self.shop_offer_slot ~= nil)
end

function Joker:draw_tooltip_overlay()
    if not self.states.visible or not self:should_draw_tooltip() then return end
    local draw_x, draw_y = self:get_layout_draw_xy()
    self:draw_tooltip(draw_x, draw_y)
end

function Joker:draw_sub_pos_overlay(draw_x, draw_y)
    if not self.face_up then return end
    love.graphics.setColor(1, 1, 1, 1)
    if self.sub_sprite and self.sub_sprite.image then
        love.graphics.draw(self.sub_sprite.image, draw_x, draw_y, 0, 1, 1)
        return
    end
    if not self.sub_atlas or not self.sub_atlas.image or not self.sub_quad then return end
    love.graphics.draw(self.sub_atlas.image, self.sub_quad, draw_x, draw_y, 0, 1, 1)
end

function Joker:draw_sticker_overlays(draw_x, draw_y)
    if not self.sticker_atlas or not self.sticker_atlas.image then return end

    local active_stickers = {}
    if self.perishable then table.insert(active_stickers, "perishable") end
    if self.rental then table.insert(active_stickers, "rental") end
    if self.eternal then table.insert(active_stickers, "eternal") end
    if #active_stickers == 0 then return end

    for _, name in ipairs(active_stickers) do
        local quad = self.sticker_quads and self.sticker_quads[name]
        if quad then
            love.graphics.draw(self.sticker_atlas.image, quad, draw_x, draw_y, 0, 1, 1)
        end
    end
end

function Joker:draw()
    if not self.states.visible then return end

    local prev_draw_r, prev_draw_g, prev_draw_b, prev_draw_a = love.graphics.getColor()
    love.graphics.setColor(1, 1, 1, 1)

    local draw_x, draw_y = self:get_layout_draw_xy()

    love.graphics.push()

    local base_scale = self.VT.scale or 1
    local render_scale = self:get_render_scale()
    local cx = draw_x + (self.VT.w * base_scale) / 2
    local cy = draw_y + (self.VT.h * base_scale) / 2
    love.graphics.translate(cx, cy)
    love.graphics.rotate(self.VT.r)
    love.graphics.scale(render_scale, render_scale)
    love.graphics.translate(-cx, -cy)

    if self.face_up then
        if self.front_sprite and self.front_sprite.image then
            local ed = Joker.normalize_edition(self.edition)
            local function draw_sprite_front()
                love.graphics.draw(self.front_sprite.image, draw_x, draw_y, 0, 1, 1)
            end

            if ed == "foil" then
                love.graphics.setColor(0.62, 0.78, 1.12, 1)
                draw_sprite_front()
            elseif ed == "holo" then
                love.graphics.setColor(1.15, 0.55, 0.55, 1)
                draw_sprite_front()
            elseif ed == "polychrome" then
                polychrome_edition_set_color()
                draw_sprite_front()
            else
                love.graphics.setColor(1, 1, 1, 1)
                draw_sprite_front()
            end
            love.graphics.setColor(1, 1, 1, 1)
        end
        self:draw_sub_pos_overlay(draw_x, draw_y)
    else
        if self.back_atlas and self.back_atlas.image and self.back_quad then
            love.graphics.draw(self.back_atlas.image, self.back_quad, draw_x, draw_y, 0, 1, 1)
        end
    end

    self:draw_sticker_overlays(draw_x, draw_y)

    if joker_is_debuffed_for_display(self) then
        draw_debuff_x_overlay(draw_x, draw_y, self.VT.w, self.VT.h)
    end

    love.graphics.pop()

    if G and G.draw_node_gamepad_focus_outline then
        G:draw_node_gamepad_focus_outline(self)
    end

    love.graphics.setColor(prev_draw_r, prev_draw_g, prev_draw_b, prev_draw_a)

    -- Debug bounding box.
    self:draw_boundingrect()

    love.graphics.setColor(prev_draw_r, prev_draw_g, prev_draw_b, prev_draw_a)
end

function Joker:update(dt)
    Moveable.update(self, dt)
    if joker_front_sprite_signature(self) ~= self._quads_refresh_signature then
        self:refresh_quads()
    end
    if self.scoring_shake_timer and self.scoring_shake_timer > 0 then
        self.scoring_shake_timer = self.scoring_shake_timer - dt
        self.scoring_shake_phase = (self.scoring_shake_phase or 0) + dt
        if self.scoring_shake_timer < 0 then self.scoring_shake_timer = 0 end
        if self.scoring_shake_timer <= 0 then self.scoring_shake_phase = nil end
    end
end

-- Event-based trigger hook for data-driven joker effects.
-- `event_name` is something like: "on_hand_scored"
-- `ctx` is the runtime scoring context.
function Joker:is_sticker_debuffed()
    return self.perishable == true and (self.perishable_debuffed == true or tonumber(self.perishable_counter or 0) <= 0)
end

function Joker:matches_trigger(event_name, ctx)
    if self:is_sticker_debuffed() then
        return false
    end
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
    self.scoring_shake_phase = 0
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
    ctx.VT = self.VT
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

