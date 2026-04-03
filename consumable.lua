---@class Consumable : Moveable
Consumable = Moveable:extend()

local function consumable_resolve_atlas(name)
    if not name or not G or not G.ASSET_ATLAS then return nil end
    if G.ensure_asset_atlas_loaded then
        G:ensure_asset_atlas_loaded(name)
    end
    return G.ASSET_ATLAS[name]
end

local function consumable_compute_quad(atlas, index)
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

---@param X number
---@param Y number
---@param def table  -- entry from CONSUMABLE_DEFS
function Consumable:init(X, Y, def)
    self.def = def or {}
    self.id = self.def.id
    self.kind = self.def.kind
    self.name = self.def.name or "Consumable"
    self.sell_cost = tonumber(self.def.sell_cost) or 0
    self.atlas_name = self.def.atlas or "Tarot"
    self.index = tonumber(self.def.index) or 0

    local cw, ch = 72, 95
    Moveable.init(self, X or 0, Y or 0, cw, ch)

    self.states.collide.can = false
    self.states.click.can = true
    self.states.drag.can = true
    self.states.visible = true

    self.atlas = consumable_resolve_atlas(self.atlas_name)
    self.quad, self.w, self.h = consumable_compute_quad(self.atlas, self.index)

    if self.w and self.h and self.w > 0 and self.h > 0 then
        self.T.w = self.w
        self.T.h = self.h
        if self.VT then
            self.VT.w = self.w
            self.VT.h = self.h
        end
    end
end

function Consumable:get_collision_rect()
    local t = self.VT or self.T
    local s = t.scale or 1
    local w = t.w or 0
    local h = t.h or 0

    local offx = (self.collision_offset and self.collision_offset.x) or 0
    local offy = (self.collision_offset and self.collision_offset.y) or 0

    local scaled_w = w * s
    local scaled_h = h * s

    local delta_x = (w * s * (1 - s)) / 2
    local delta_y = (h * s * (1 - s)) / 2

    local draw_x = t.x + offx
    local draw_y = t.y + offy

    return {
        x = draw_x + delta_x,
        y = draw_y + delta_y,
        w = scaled_w,
        h = scaled_h,
    }
end

function Consumable:draw()
    if not self.states.visible then return end
    if not (self.atlas and self.atlas.image and self.quad) then return end

    local draw_x = self.VT.x + self.collision_offset.x
    local draw_y = self.VT.y + self.collision_offset.y

    love.graphics.push()

    local cx = draw_x + (self.VT.w * self.VT.scale) / 2
    local cy = draw_y + (self.VT.h * self.VT.scale) / 2
    love.graphics.translate(cx, cy)
    love.graphics.rotate(self.VT.r)
    love.graphics.scale(self.VT.scale, self.VT.scale)
    love.graphics.translate(-cx, -cy)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.atlas.image, self.quad, draw_x, draw_y, 0, 1, 1)

    love.graphics.pop()
end

