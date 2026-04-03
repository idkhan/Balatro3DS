---@class Joker : Moveable
Joker = Moveable:extend()

-- Basic 2-layer joker: back sprite and front sprite.
-- Rendering logic is similar to `Card:draw()` but uses atlas cell indices instead of rank/suit.

local SHAKE_MAGNITUDE = 8
local SHAKE_MAX_DURATION = 0.22

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
    local base = base_atlas and tostring(base_atlas) or "Joker1"
    local ed = Joker.normalize_edition(edition)
    if ed == "negative" then
        if base == "Joker1" then return "Joker1_negative" end
        if base == "Joker2" then return "Joker2_negative" end
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
    self.front_atlas_name = (self.params.pos and self.params.pos.atlas) or (self.def.pos and self.def.pos.atlas) or "Joker1"
    self.back_atlas_name = "centers"

    self.front_index = (self.params.pos and self.params.pos.index) or (self.def.pos and self.def.pos.index) or 0
    self.back_index = 0

    self.scoring_shake_timer = 0

    self:refresh_quads()
end

function Joker:refresh_quads()
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
local TOOLTIP_SPACING = 1
local TOOLTIP_SECTION_GAP = 2
local TOOLTIP_OUTER_PAD_X = 3
local TOOLTIP_OUTER_PAD_Y = 3

local function split_tooltip_override(s)
    if type(s) ~= "string" or s == "" then return nil end
    local lines = {}
    for line in string.gmatch(s, "[^\r\n]+") do
        table.insert(lines, line)
    end
    if #lines == 0 then return { s } end
    return lines
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
    return { tostring(et) }
end

function Joker:get_edition_tooltip_lines()
    local ed = Joker.normalize_edition(self.edition)
    if ed == "base" then return {} end
    if ed == "foil" then return { "Foil: +50 Chips when hand is scored" } end
    if ed == "holo" then return { "Holographic: +10 Mult when hand is scored" } end
    if ed == "polychrome" then return { "Polychrome: ×1.5 Mult when hand is scored" } end
    if ed == "negative" then return { "Negative: +1 Joker slot" } end
    return {}
end

function Joker:get_tooltip_body_lines()
    local def = self.def or {}
    local edition_lines = self:get_edition_tooltip_lines()
    local function append_edition(lines)
        for _, el in ipairs(edition_lines) do
            table.insert(lines, el)
        end
        return lines
    end
    if type(def.tooltip) == "table" then
        local out = {}
        for _, l in ipairs(def.tooltip) do
            if type(l) == "string" then table.insert(out, l) end
        end
        if #out > 0 then return append_edition(out) end
    end
    if type(def.tooltip) == "string" then
        local lines = split_tooltip_override(def.tooltip)
        if lines then return append_edition(lines) end
    end
    return append_edition(describe_joker_effect_lines(self))
end

function Joker:draw_tooltip(draw_x, draw_y)
    local def = self.def or {}
    local title = self.name or def.name or "Joker"
    local lines = self:get_tooltip_body_lines()
    local font = G.FONTS.PIXEL.SMALL or love.graphics.getFont()
    local prev_font = love.graphics.getFont()
    local prev_r, prev_g, prev_b, prev_a = love.graphics.getColor()
    love.graphics.setFont(font)

    local header_w = font:getWidth(title)
    local body_max_w = 0
    for _, line in ipairs(lines) do
        local w = font:getWidth(line)
        if w > body_max_w then body_max_w = w end
    end
    local line_h = font:getHeight()
    local header_w_total = header_w + (TOOLTIP_PAD_X * 2)
    local header_h_total = line_h + (TOOLTIP_HEADER_PAD_Y * 2)
    local body_w_total = body_max_w + (TOOLTIP_PAD_X * 2)
    local body_h_total = (#lines * line_h) + ((#lines - 1) * TOOLTIP_SPACING) + (TOOLTIP_BODY_PAD_Y * 2)
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

    local text_y = body_y + TOOLTIP_BODY_PAD_Y
    local gray = { 0.22, 0.24, 0.26, 1 }
    local green = (G.C and G.C.GREEN) or { 0.2, 0.75, 0.55, 1 }

    local function strip_prob_prefix(s)
        local p = s:match("^(%d+/%d+:%s*)")
        if p then
            return p, s:sub(#p + 1)
        end
        return nil, s
    end

    local function draw_segments_centered(segments, line_y)
        local total_w = 0
        for _, seg in ipairs(segments) do
            total_w = total_w + font:getWidth(seg[1])
        end
        local x = body_x + math.floor((inner_w - total_w) * 0.5 + 0.5)
        for _, seg in ipairs(segments) do
            local t, col = seg[1], seg[2]
            love.graphics.setColor(col[1], col[2], col[3], col[4])
            love.graphics.print(t, x, line_y)
            x = x + font:getWidth(t)
        end
    end

    for _, line in ipairs(lines) do
        local line_y = math.floor(text_y + 0.5)
        local prob, rest = strip_prob_prefix(line)

        local num_chips, suf_chips = rest:match("^(.-)( chips)$")
        local num_mult, suf_mult = rest:match("^(.-)( mult)$")

        if num_chips and suf_chips then
            local segs = {}
            if prob then
                table.insert(segs, { prob, green })
            end
            table.insert(segs, { num_chips, G.C.CHIPS })
            table.insert(segs, { suf_chips, G.C.CHIPS })
            draw_segments_centered(segs, line_y)
        elseif num_mult and suf_mult then
            local segs = {}
            if prob then
                table.insert(segs, { prob, green })
            end
            table.insert(segs, { num_mult, G.C.MULT })
            table.insert(segs, { suf_mult, G.C.MULT })
            draw_segments_centered(segs, line_y)
        else
            local left, mid, right = rest:match("^(.-)%s(mult)(.*)$")
            if left and mid and right ~= nil then
                local segs = {}
                if prob then
                    table.insert(segs, { prob, green })
                end
                table.insert(segs, { left .. " ", G.C.MULT })
                table.insert(segs, { mid, G.C.MULT })
                table.insert(segs, { right, gray })
                draw_segments_centered(segs, line_y)
            else
                local left_c, mid_c, right_c = rest:match("^(.-)%s(chips)(.*)$")
                if left_c and mid_c and right_c ~= nil then
                    local segs = {}
                    if prob then
                        table.insert(segs, { prob, green })
                    end
                    table.insert(segs, { left_c .. " ", G.C.CHIPS })
                    table.insert(segs, { mid_c, G.C.CHIPS })
                    table.insert(segs, { right_c, gray })
                    draw_segments_centered(segs, line_y)
                elseif prob then
                    draw_segments_centered({ { prob, green }, { rest, gray } }, line_y)
                else
                    local line_w = font:getWidth(line)
                    local line_x = body_x + math.floor((inner_w - line_w) * 0.5 + 0.5)
                    love.graphics.setColor(gray[1], gray[2], gray[3], gray[4])
                    love.graphics.print(line, line_x, line_y)
                end
            end
        end
        text_y = text_y + line_h + TOOLTIP_SPACING
    end

    love.graphics.setFont(prev_font)
    love.graphics.setColor(prev_r, prev_g, prev_b, prev_a)
end


function Joker:draw()
    if not self.states.visible then return end

    local prev_draw_r, prev_draw_g, prev_draw_b, prev_draw_a = love.graphics.getColor()
    love.graphics.setColor(1, 1, 1, 1)

    local draw_x = self.VT.x + self.collision_offset.x
    local draw_y = self.VT.y + self.collision_offset.y

    if self.scoring_shake_timer and self.scoring_shake_timer > 0 then
        local mag = SHAKE_MAGNITUDE * (self.scoring_shake_timer / SHAKE_MAX_DURATION)
        local t = love.timer.getTime()
        if self.scoring_shake_t0 then
            t = t - self.scoring_shake_t0
        end
        draw_x = draw_x + math.sin(t * 85) * mag
        draw_y = draw_y + math.cos(t * 73) * mag * 0.65
    end

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

    love.graphics.pop()

    love.graphics.setColor(prev_draw_r, prev_draw_g, prev_draw_b, prev_draw_a)

    if self.face_up and G and G.jokers_on_bottom == true and G.active_tooltip_joker == self then
        self:draw_tooltip(draw_x, draw_y)
    end

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
    -- Passive, do nothing
    if self.effect_type == "Hand card double" then
        return false
    end

    -- Unknown effect types are non-triggering.
    if self.effect_type == nil then
        return false
    end

    -- Determine event mapping for the data-driven effect.
    local default_event = nil
    if self.effect_type == "Mult" or self.effect_type == "Chips" then
        default_event = "on_hand_scored"
    elseif self.effect_type == "Suit Mult" or self.effect_type == "Suit Chips" then
        default_event = "card_played"
    elseif self.effect_type == "Type Mult" or self.effect_type == "Type Chips" then
        default_event = "on_hand_scored"
    elseif self.effect_type == "Hand Size Mult" then
        default_event = "on_hand_scored"
    elseif self.effect_type == "Stencil Mult" then
        default_event = "on_hand_scored"
    elseif self.effect_type == "Discard Chips" then
        default_event = "on_hand_scored"
    elseif self.effect_type == "No Discard Mult" then
        default_event = "on_hand_scored"
    elseif self.effect_type == "Stone card hands" then
        default_event = "on_blind_selected"
    elseif self.effect_type == "1 in 6 mult" or self.effect_type == "1 in 10 mult" then
        default_event = "on_hand_scored"
    end

    local expected_event = default_event
    if expected_event and expected_event ~= event_name then
        return false
    end

    -- Apply effect-specific conditions.
    local cfg = self.effect_config or {}
    if self.effect_type == "Suit Mult" or self.effect_type == "Suit Chips" then
        local extra = type(cfg.extra) == "table" and cfg.extra or {}
        if extra.suit ~= nil then
            if ctx == nil or ctx.suit ~= extra.suit then return false end
        end
    elseif self.effect_type == "Type Mult" or self.effect_type == "Type Chips" then
        if ctx == nil then return false end

        if ctx.hand_type ~= cfg.type then
            local contains = ctx.contains_hand_types
            if type(contains) ~= "table" or contains[cfg.type] ~= true then
                return false
            end
        end
    elseif self.effect_type == "Hand Size Mult" then
        if ctx == nil then return false end
        local extra = type(cfg.extra) == "table" and cfg.extra or {}
        local max_size = tonumber(extra.size) or 3
        local cards = ctx.cards
        if type(cards) ~= "table" or #cards > max_size then
            return false
        end
    elseif self.effect_type == "Stencil Mult" then
        if ctx == nil then return false end
        if tonumber(ctx.free_joker_slots) == nil then
            return false
        end
        self.free_joker_slots = tonumber(ctx.free_joker_slots)
    elseif self.effect_type == "No Discard Mult" then
        -- Mystic Summit: only active when no discards remain.
        local d_remaining = tonumber((type(cfg.extra) == "table" and cfg.extra.d_remaining)) or 0
        local discards_left = tonumber((ctx and ctx.discards_left) or (G and G.discards)) or 0
        if discards_left ~= d_remaining then
            return false
        end
    elseif self.effect_type == "Destroy Joker" then
        -- Ceremonial Dagger behavior:
        -- - on_blind_selected: only trigger if there is a joker immediately to the right
        -- - on_hand_scored: trigger when we have stored mult to apply
        if event_name == "on_blind_selected" then
            local joker_list = G and type(G.jokers) == "table" and G.jokers
            if not joker_list then
                return false
            end
            local self_index = nil
            for i, joker in ipairs(joker_list) do
                if joker == self then
                    self_index = i
                    break
                end
            end
            local target_index = self_index and (self_index + 1) or nil
            if not (target_index and joker_list[target_index]) then
                return false
            end
        elseif event_name == "on_hand_scored" then
            if (tonumber(self.stored_mult) or 0) <= 0 then
                return false
            end
        else
            return false
        end
    elseif self.effect_type == "1 in 6 mult" or self.effect_type == "1 in 10 mult" then
        local extra = type(cfg.extra) == "table" and cfg.extra or {}
        local every = math.max(1, tonumber(extra.every) or 6)
        local remaining = tonumber(self.loyalty_remaining)
        if remaining == nil then
            remaining = tonumber(extra.remaining) or every
        end
        if remaining < 1 or remaining > every then
            remaining = every
        end
        remaining = remaining - 1
        if remaining <= 0 then
            self.loyalty_remaining = every
            return true
        end
        self.loyalty_remaining = remaining
        return false
    end

    return true
end

--- Foil / Holo / Polychrome modify chips or mult when the scored hand is finalized (not Negative).
function Joker:apply_edition_on_hand_scored(ctx)
    if type(ctx) ~= "table" then return end
    local ed = Joker.normalize_edition(self.edition)
    if ed == "base" or ed == "negative" then return end
    if ed == "foil" then
        ctx.chips = (tonumber(ctx.chips) or 0) + 50
    elseif ed == "holo" then
        ctx.mult = (tonumber(ctx.mult) or 0) + 10
    elseif ed == "polychrome" then
        ctx.mult = (tonumber(ctx.mult) or 0) * 1.5
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
    local cfg = self.effect_config or {}

    -- Visual feedback: shake when this joker actually triggers.
    self.scoring_shake_timer = SHAKE_MAX_DURATION
    self.scoring_shake_t0 = love.timer.getTime()

    if self.effect_type == "Mult" then
        local amount = tonumber(cfg.mult) or 0
        ctx.mult = (tonumber(ctx.mult) or 0) + amount
        Sfx.play_mult()
    elseif self.effect_type == "Chips" then
        local amount = tonumber(cfg.chips) or 0
        ctx.chips = (tonumber(ctx.chips) or 0) + amount
    elseif self.effect_type == "Suit Mult" then
        local extra = type(cfg.extra) == "table" and cfg.extra or {}
        local amount = tonumber(extra.s_mult) or 0
        ctx.mult = (tonumber(ctx.mult) or 0) + amount
        Sfx.play_mult()
    elseif self.effect_type == "Suit Chips" then
        local extra = type(cfg.extra) == "table" and cfg.extra or {}
        local amount = tonumber(extra.s_chips) or 0
        ctx.chips = (tonumber(ctx.chips) or 0) + amount
    elseif self.effect_type == "Type Mult" then
        local amount = tonumber(cfg.t_mult) or 0
        ctx.mult = (tonumber(ctx.mult) or 0) + amount
        Sfx.play_mult()
    elseif self.effect_type == "Type Chips" then
        local amount = tonumber(cfg.t_chips) or 0
        ctx.chips = (tonumber(ctx.chips) or 0) + amount
    elseif self.effect_type == "Hand Size Mult" then
        local extra = type(cfg.extra) == "table" and cfg.extra or {}
        local amount = tonumber(extra.mult) or tonumber(cfg.mult) or 0
        ctx.mult = (tonumber(ctx.mult) or 0) + amount
        Sfx.play_mult()
    elseif self.effect_type == "Stencil Mult" then
        local free_slots = tonumber(ctx.free_joker_slots) or 0
        local factor = free_slots + 1
        ctx.mult = (tonumber(ctx.mult) or 0) * factor
        Sfx.play_mult2()
    elseif self.effect_type == "Discard Chips" then
        -- Banner: +X chips for each remaining discard.
        local extra = tonumber(cfg.extra) or 0
        local discards_left = tonumber((ctx and ctx.discards_left) or (G and G.discards)) or 0
        ctx.chips = (tonumber(ctx.chips) or 0) + (extra * math.max(0, discards_left))
    elseif self.effect_type == "No Discard Mult" then
        -- Mystic Summit: +mult only when no discards remain (condition also gated in matches_trigger).
        local extra = type(cfg.extra) == "table" and cfg.extra or {}
        local amount = tonumber(extra.mult) or tonumber(cfg.mult) or 0
        ctx.mult = (tonumber(ctx.mult) or 0) + amount
        Sfx.play_mult()
    elseif self.effect_type == "Stone card hands" then
        -- Add a card with a random rank and suit to the deck
        local deck = (ctx and ctx.deck) or (G and G.deck)
        if not (deck and deck.cards) then
            return
        end
        local suits = { "Hearts", "Clubs", "Diamonds", "Spades" }
        local MIN_RANK = 2
        local MAX_RANK = 14
        local suit = suits[math.random(1, #suits)]
        local rank = math.random(MIN_RANK, MAX_RANK)
        table.insert(deck.cards, { rank = rank, suit = suit, enhancement = "stone" })
    elseif self.effect_type == "1 in 6 mult" or self.effect_type == "1 in 10 mult" then
        local extra = type(cfg.extra) == "table" and cfg.extra or {}
        local factor = tonumber(extra.Xmult) or tonumber(cfg.Xmult) or 1
        ctx.mult = (tonumber(ctx.mult) or 0) * factor
        Sfx.play_mult2()

    elseif self.effect_type == "Destroy Joker" then
        if ctx.event_name == "on_hand_scored" then
            local amount = tonumber(self.stored_mult) or 0
            if amount > 0 then
                ctx.mult = (tonumber(ctx.mult) or 0) + amount
                Sfx.play_mult()
            end
            return
        end

        local joker_list = G and type(G.jokers) == "table" and G.jokers
        if not joker_list then
            return
        end

        local self_index = nil
        for i, joker in ipairs(joker_list) do
            if joker == self then
                self_index = i
                break
            end
        end

        local target_index = self_index and (self_index + 1) or nil
        if target_index and joker_list[target_index] then
            local victim = joker_list[target_index]
            local gained = tonumber(victim and victim.sell_cost) or 0
            self.stored_mult = (tonumber(self.stored_mult) or 0) + (gained * 2)
            if G and G.remove_owned_joker_at then
                G:remove_owned_joker_at(target_index)
            else
                victim = table.remove(joker_list, target_index)
                if victim and G and G.remove then
                    G:remove(victim)
                end
            end
            Sfx.play("resources/sounds/slice1.ogg")

        end
    end
end

