---@class Joker : Moveable
Joker = Moveable:extend()

-- Basic 2-layer joker: back sprite and front sprite.
-- Rendering logic is similar to `Card:draw()` but uses atlas cell indices instead of rank/suit.

local SHAKE_MAGNITUDE = 6
local SHAKE_MAX_DURATION = 0.22

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
    self.sell_value = tonumber(self.def.sell_value) or 0
    self.effect_config = self.def.config or {}
    self.trigger_condition = self.def.trigger_condition or {}

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
    self.front_atlas = resolve_atlas(self.front_atlas_name)
    self.back_atlas = resolve_atlas(self.back_atlas_name)

    self.front_quad, self.front_w, self.front_h = compute_quad(self.front_atlas, self.front_index)
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

function Joker:draw()
    if not self.states.visible then return end

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
            love.graphics.draw(self.front_atlas.image, self.front_quad, draw_x, draw_y, 0, 1, 1)
        end
    else
        if self.back_atlas and self.back_atlas.image and self.back_quad then
            love.graphics.draw(self.back_atlas.image, self.back_quad, draw_x, draw_y, 0, 1, 1)
        end
    end

    love.graphics.pop()

    -- Debug bounding box.
    self:draw_boundingrect()
end

function Joker:update(dt)
    Moveable.update(self, dt)
    if self.scoring_shake_timer and self.scoring_shake_timer > 0 then
        self.scoring_shake_timer = self.scoring_shake_timer - dt
        if self.scoring_shake_timer < 0 then self.scoring_shake_timer = 0 end
        if self.scoring_shake_timer <= 0 then self.scoring_shake_t0 = nil end
    end
end

-- Event-based trigger hooks (skeleton; scoring integration comes next step).
-- `event_name` is something like: "on_hand_scored"
-- `ctx` is a runtime context table you will build during scoring.
function Joker:matches_trigger(event_name, ctx)
    local tc = self.trigger_condition
    if type(tc) ~= "table" then tc = {} end

    -- Passive, do nothing
    if self.effect_type == "Hand card double" then
        return false
    end

    -- If we can't interpret the joker as a data-driven effect, fall back to the old trigger_condition behavior.
    if self.effect_type == nil then
        if tc.event and tc.event ~= event_name then return false end
        if tc.always == true then return true end
        if next(tc) == nil then return true end
        return true
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
    end

    local expected_event = tc.event or default_event
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
    elseif self.effect_type == "No Discard Mult" then
        -- Mystic Summit: only active when no discards remain.
        local d_remaining = tonumber((type(cfg.extra) == "table" and cfg.extra.d_remaining)) or 0
        local discards_left = tonumber((ctx and ctx.discards_left) or (G and G.discards)) or 0
        if discards_left ~= d_remaining then
            return false
        end
    end

    return true
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
    end
end

