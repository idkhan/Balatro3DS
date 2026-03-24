---@class Card : Moveable
Card = Moveable:extend()

local SHAKE_MAGNITUDE = 6

---@param X number
---@param Y number
---@param W number|nil
---@param H number|nil
---@param card table|nil   -- logical card data (rank/suit/etc), optional for now
---@param center any|nil   -- placeholder for future use
---@param params table|nil -- visual params (atlas names/indices/state)

function Card:init(X, Y, W, H, card, center, params)
    self.params = (type(params) == 'table') and params or {}
    self.card_data = card or {}
    self.center = center

    -- default to global card size if not provided
    local cw = W or (G and G.CARD_W) or 71
    local ch = H or (G and G.CARD_H) or 95

    Moveable.init(self, X or 0, Y or 0, cw, ch)

    self.states.collide.can = false
    
    -- register in global instance table if available
    if G and G.I and G.I.CARD then
        table.insert(G.I.CARD, self)
    end

    -- which atlases to use for each visual layer
    -- back & front: both from 'centers' atlas
    --   back_index  = N
    --   face_index  = N + 1  (your rule: face is back + 1)
    self.back_atlas_name = self.params.back_atlas_name or "centers"
    self.face_atlas_name = self.params.face_atlas_name or self.back_atlas_name

    -- rank+suit image comes from the main card atlas
    self.rank_atlas_name = self.params.rank_atlas_name or "cards_2"
    self.seal_atlas_name = self.params.seal_atlas_name or "centers"

    -- indices into those atlases (0-based cell index)
    -- derive rank/suit index for the overlay image when provided
    local rank = self.card_data.rank or self.params.rank
    local suit = self.card_data.suit or self.params.suit

    -- suit offset: Hearts=0, Clubs=13, Diamonds=26, Spades=39
    local function suit_offset(s)
        if not s then return 0 end
        if type(s) == "string" then
            s = s:lower()
            if s == "hearts" then return 0 end
            if s == "clubs"  then return 13 end
            if s == "diamonds" then return 26 end
            if s == "spades" then return 39 end
        elseif type(s) == "number" then
            -- optional numeric mapping 1..4 = Hearts, Clubs, Diamonds, Spades
            if s == 1 then return 0 end
            if s == 2 then return 13 end
            if s == 3 then return 26 end
            if s == 4 then return 39 end
        end
        return 0
    end

    -- by your rule for card faces in cards_1:
    --   rank 2 -> first texture (index 0), so base index = (rank - 2)
    --   then add suit offset (Hearts=0, Clubs=13, Diamonds=26, Spades=39)
    local computed_rank_index
    if rank then
        computed_rank_index = math.max(0, (rank - 2) + suit_offset(suit))
    end

    -- back is first texture in centers atlas by default; face is just back+1
    self.back_index = self.params.back_index or 0
    self.face_index = self.params.face_index or (self.back_index + 1)

    -- rank atlas index comes from rank+suit mapping
    self.rank_index = self.params.rank_index or computed_rank_index or 0
    self.seal_index = self.params.seal_index -- seal is optional

    -- card orientation: false = back, true = front
    self.face_up = self.params.face_up or false

    -- resolve atlases and quads
    self:refresh_quads()
end

function Card:resolve_atlas(name)
    if not name or not G or not G.ASSET_ATLAS then return nil end
    if G.ensure_asset_atlas_loaded then
        G:ensure_asset_atlas_loaded(name)
    end
    return G.ASSET_ATLAS[name]
end

function Card:compute_quad(atlas, index)
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

function Card:refresh_quads()
    -- resolve atlases
    self.back_atlas = self:resolve_atlas(self.back_atlas_name)
    self.face_atlas = self:resolve_atlas(self.face_atlas_name)
    self.rank_atlas = self:resolve_atlas(self.rank_atlas_name)
    self.seal_atlas = self:resolve_atlas(self.seal_atlas_name)

    -- compute quads
    self.back_quad, self.back_w, self.back_h = self:compute_quad(self.back_atlas, self.back_index)
    self.face_quad, self.face_w, self.face_h = self:compute_quad(self.face_atlas, self.face_index)
    self.rank_quad, self.rank_w, self.rank_h = self:compute_quad(self.rank_atlas, self.rank_index)

    if self.seal_index ~= nil then
        self.seal_quad, self.seal_w, self.seal_h = self:compute_quad(self.seal_atlas, self.seal_index)
    else
        self.seal_quad, self.seal_w, self.seal_h = nil, 0, 0
    end

    -- ensure the card's transform matches the visual sprite size so it isn't tiny
    local base_w = self.back_w or self.face_w
    local base_h = self.back_h or self.face_h
    if base_w and base_w > 0 and base_h and base_h > 0 then
        self.T.w = base_w
        self.T.h = base_h
        if self.VT then
            self.VT.w = base_w
            self.VT.h = base_h
        end
    end
end

function Card:set_face_up(face_up)
    self.face_up = not not face_up
end

-- helper to draw one layer (atlas+quad) at given position (ox, oy) or default VT position
function Card:draw_layer(atlas, quad, cell_w, cell_h, ox, oy)
    if not atlas or not atlas.image or not quad then return end

    local draw_x = ox or (self.VT.x + self.collision_offset.x)
    local draw_y = oy or (self.VT.y + self.collision_offset.y)

    -- draw at 1:1 pixel size based on atlas cell, since we already synced VT.w/h to that in refresh_quads
    local scale_x = 1
    local scale_y = 1

    love.graphics.draw(
        atlas.image,
        quad,
        draw_x,
        draw_y,
        0,
        scale_x,
        scale_y
    )
end

local SELECTED_LIFT = 20
local TOOLTIP_PAD_X = 8
local TOOLTIP_HEADER_PAD_Y = 3
local TOOLTIP_BODY_PAD_Y = 10
local TOOLTIP_SPACING = 1
local TOOLTIP_SECTION_GAP = 2
local TOOLTIP_OUTER_PAD_X = 3
local TOOLTIP_OUTER_PAD_Y = 3

local function rank_to_label(rank)
    if rank == 14 then return "Ace" end
    if rank == 13 then return "King" end
    if rank == 12 then return "Queen" end
    if rank == 11 then return "Jack" end
    if type(rank) == "number" then return tostring(rank) end
    return "?"
end

local function card_base_score(rank)
    if rank == 14 then return 11 end
    if rank == 11 or rank == 12 or rank == 13 then return 10 end
    if type(rank) == "number" then return rank end
    return 0
end

local function get_card_modifier_bonus(card_data)
    if type(card_data) ~= "table" then return 0, 0 end

    if G and G.hand and G.hand.get_modifier_bonus then
        return G.hand:get_modifier_bonus(card_data)
    end

    local chip_bonus = 0
    local mult_bonus = 0
    chip_bonus = chip_bonus + (tonumber(card_data.chip_bonus) or 0)
    chip_bonus = chip_bonus + (tonumber(card_data.chips_bonus) or 0)
    mult_bonus = mult_bonus + (tonumber(card_data.mult_bonus) or 0)
    mult_bonus = mult_bonus + (tonumber(card_data.multiplier_bonus) or 0)
    return chip_bonus, mult_bonus
end

function Card:get_collision_rect()
    local r = Node.get_collision_rect(self)
    if self.selected and not self.scoring_center then
        r.y = r.y - SELECTED_LIFT
    end
    return r
end

function Card:draw_boundingrect()
    if not G or not G.DEBUG then return end
    local r = self:get_collision_rect()
    local prev_r, prev_g, prev_b, prev_a = love.graphics.getColor()
    if self.states.collide.is then
        love.graphics.setColor(1, 0, 0, 1)
    else
        love.graphics.setColor(0, 1, 0, 1)
    end
    love.graphics.push()
    local cx = r.x + r.w / 2
    local cy = r.y + r.h / 2
    love.graphics.translate(cx, cy)
    love.graphics.rotate(self.VT.r)
    love.graphics.translate(-cx, -cy)
    love.graphics.rectangle("line", r.x, r.y, r.w, r.h)
    love.graphics.pop()
    love.graphics.setColor(prev_r, prev_g, prev_b, prev_a)
end

function Card:draw_tooltip(draw_x, draw_y)
    local data = self.card_data or {}
    local rank = data.rank
    local suit = data.suit
    local base_score = card_base_score(rank)
    local chip_bonus, mult_bonus = get_card_modifier_bonus(data)

    local rank_name = rank_to_label(rank)
    local suit_name = tostring(suit or "?")
    local header_prefix = string.format("%s of ", rank_name)
    local lines = {}
    table.insert(lines, string.format("+%d chips", base_score + chip_bonus))
    if mult_bonus ~= 0 then
        table.insert(lines, string.format("+%d mult", mult_bonus))
    end

    local font = G.FONTS.PIXEL.SMALL or love.graphics.getFont()
    local prev_font = love.graphics.getFont()
    local prev_r, prev_g, prev_b, prev_a = love.graphics.getColor()
    love.graphics.setFont(font)

    local header_w = font:getWidth(header_prefix) + font:getWidth(suit_name)
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
    local tx = draw_x + (card_w - box_w) * 0.5
    local ty = draw_y - box_h - 3
    if tx < 2 then tx = 2 end
    if ty < 2 then ty = draw_y + 2 end
    tx = math.floor(tx + 0.5)
    ty = math.floor(ty + 0.5)

    -- Outer container (single rounded rectangle around both sections)
    draw_rect_with_shadow(tx, ty, box_w, box_h, 4, 0, G.C.TOOLTIP, G.C.BLOCK.SHADOW, 1)
        
    love.graphics.setColor(1, 1, 1, 1)
    draw_rounded_rect(tx, ty, box_w, box_h, 4, 2, "line")
    
    local header_x = tx + TOOLTIP_OUTER_PAD_X
    local header_y = ty + TOOLTIP_OUTER_PAD_Y
    local body_x = header_x
    local body_y = header_y + header_h_total + TOOLTIP_SECTION_GAP

    -- Outer rounded panels
    love.graphics.setColor(G.C.TOOLTIP)
    draw_rounded_rect(header_x, header_y, inner_w, header_h_total, 4, 0, "fill")
    draw_rounded_rect(body_x, body_y, inner_w, body_h_total, 4, 0, "fill")    

    -- Inner light fill
    local inner_pad = 2
    local inner_header_h = math.max(1, header_h_total - (inner_pad * 2))
    local inner_body_h = math.max(1, body_h_total - (inner_pad * 2))
    love.graphics.setColor(G.C.WHITE)
    draw_rect_with_shadow(header_x + inner_pad, header_y + inner_pad, inner_w - (inner_pad * 2), inner_header_h, 4, 0, G.C.WHITE, G.C.DARK_WHITE, 1)
    draw_rect_with_shadow(body_x + inner_pad, body_y + inner_pad -1, inner_w - (inner_pad * 2), inner_body_h, 4, 0, G.C.WHITE, G.C.DARK_WHITE, 1)
 
    -- Header text with colored suit
    local header_total_w = font:getWidth(header_prefix) + font:getWidth(suit_name)
    local header_text_x = header_x + math.floor((inner_w - header_total_w) * 0.5 + 0.5)
    local header_text_y = header_y + math.floor((header_h_total - line_h) * 0.5 + 0.5)
    love.graphics.setColor(G.C.PANEL)
    love.graphics.print(header_prefix, header_text_x, header_text_y)
    local suit_col = (G and G.C and G.C.SUITS and G.C.SUITS[suit_name]) or (G and G.C and G.C.PANEL) or {1, 1, 1, 1}
    love.graphics.setColor(suit_col)
    love.graphics.print(suit_name, header_text_x + font:getWidth(header_prefix), header_text_y)

    local text_y = body_y + TOOLTIP_BODY_PAD_Y
    for _, line in ipairs(lines) do
        local line_w = font:getWidth(line)
        local line_x = body_x + math.floor((inner_w - line_w) * 0.5 + 0.5)
        local line_y = math.floor(text_y + 0.5)

        if string.match(line, " chips$") then
            local prefix = string.gsub(line, " chips$", " ")
            local prefix_w = font:getWidth(prefix)
            local chips_w = font:getWidth("chips")
            local total_w = prefix_w + chips_w
            local prefix_x = body_x + math.floor((inner_w - total_w) * 0.5 + 0.5)
            love.graphics.setColor(0.22, 0.24, 0.26, 1)
            love.graphics.print(prefix, prefix_x, line_y)
            love.graphics.setColor(G.C.CHIPS)
            love.graphics.print("chips", prefix_x + prefix_w, line_y)
        elseif string.match(line, " mult$") then
            local prefix = string.gsub(line, " mult$", " ")
            local prefix_w = font:getWidth(prefix)
            local mult_w = font:getWidth("mult")
            local total_w = prefix_w + mult_w
            local prefix_x = body_x + math.floor((inner_w - total_w) * 0.5 + 0.5)
            love.graphics.setColor(0.22, 0.24, 0.26, 1)
            love.graphics.print(prefix, prefix_x, line_y)
            love.graphics.setColor(G.C.MULT)
            love.graphics.print("mult", prefix_x + prefix_w, line_y)
        else
            love.graphics.setColor(0.22, 0.24, 0.26, 1)
            love.graphics.print(line, line_x, line_y)
        end
        text_y = text_y + line_h + TOOLTIP_SPACING
    end

    love.graphics.setFont(prev_font)
    love.graphics.setColor(prev_r, prev_g, prev_b, prev_a)
end

local SHAKE_MAX_DURATION = 0.22

function Card:update(dt)
    Moveable.update(self, dt)
    if self.scoring_shake_timer and self.scoring_shake_timer > 0 then
        self.scoring_shake_timer = self.scoring_shake_timer - dt
        if self.scoring_shake_timer < 0 then self.scoring_shake_timer = 0 end
    end
end

function Card:draw()
    if not self.states.visible then return end

    local prev_r, prev_g, prev_b, prev_a = love.graphics.getColor()
    love.graphics.setColor(1, 1, 1, 1)

    local draw_x = self.VT.x + self.collision_offset.x
    local draw_y = self.VT.y + self.collision_offset.y
    if self.selected and not self.scoring_center then draw_y = draw_y - SELECTED_LIFT end

    if self.scoring_shake_timer and self.scoring_shake_timer > 0 then
        local mag = SHAKE_MAGNITUDE * (self.scoring_shake_timer / SHAKE_MAX_DURATION)
        local t = love.timer.getTime()
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

    -- base layer: back or face, depending on orientation
    if self.face_up then
        if self.face_quad then
            self:draw_layer(self.face_atlas, self.face_quad, self.face_w, self.face_h, draw_x, draw_y)
        elseif self.back_quad then
            self:draw_layer(self.back_atlas, self.back_quad, self.back_w, self.back_h, draw_x, draw_y)
        end
    else
        if self.back_quad then
            self:draw_layer(self.back_atlas, self.back_quad, self.back_w, self.back_h, draw_x, draw_y)
        end
    end

    -- middle layer: rank + suit icon (only when face-up)
    if self.face_up and self.rank_quad then
        self:draw_layer(self.rank_atlas, self.rank_quad, self.rank_w, self.rank_h, draw_x, draw_y)
    end

    -- top layer: seal (only when face-up and defined)
    if self.face_up and self.seal_quad then
        self:draw_layer(self.seal_atlas, self.seal_quad, self.seal_w, self.seal_h, draw_x, draw_y)
    end

    love.graphics.pop()

    local show_tooltip = false
    if self.face_up then
        show_tooltip = self.states.drag.is or (G and G.active_tooltip_card == self)
    end
    if show_tooltip then
        self:draw_tooltip(draw_x, draw_y)
    end

    love.graphics.setColor(prev_r, prev_g, prev_b, prev_a)

    -- debug bounding box
    self:draw_boundingrect()

    -- draw children, if any
    for _, v in pairs(self.children or {}) do
        v:draw()
    end
end