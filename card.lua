---@class Card : Moveable
Card = Moveable:extend()

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

function Card:get_collision_rect()
    local r = Node.get_collision_rect(self)
    if self.selected then
        r.y = r.y - SELECTED_LIFT
    end
    return r
end

function Card:draw()
    if not self.states.visible then return end

    local prev_r, prev_g, prev_b, prev_a = love.graphics.getColor()
    love.graphics.setColor(1, 1, 1, 1)

    local draw_x = self.VT.x + self.collision_offset.x
    local draw_y = self.VT.y + self.collision_offset.y
    if self.selected then draw_y = draw_y - SELECTED_LIFT end

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

    love.graphics.setColor(prev_r, prev_g, prev_b, prev_a)

    -- debug bounding box
    self:draw_boundingrect()

    -- draw children, if any
    for _, v in pairs(self.children or {}) do
        v:draw()
    end
end