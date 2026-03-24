---@class Sprite : Moveable
Sprite = Moveable:extend()

function Sprite:init(args)
    args = args or {}

    -- position on screen
    local x = args.x or args[1] or 0
    local y = args.y or args[2] or 0

    -- atlas data: either pass the atlas table directly, or by name + global atlas map
    self.atlas = args.atlas
    if not self.atlas and args.atlas_name and G and G.ASSET_ATLAS then
        if G.ensure_asset_atlas_loaded then
            G:ensure_asset_atlas_loaded(args.atlas_name)
        end
        self.atlas = G.ASSET_ATLAS[args.atlas_name]
    end

    -- base sprite size comes from atlas cell size when available
    local cell_w = (self.atlas and self.atlas.px) or args.w or args[3] or 32
    local cell_h = (self.atlas and self.atlas.py) or args.h or args[4] or 32

    Moveable.init(self, x, y, cell_w, cell_h)

    self.sprite = {
        image = args.image, -- may be overridden by atlas
        sx = 0,
        sy = 0,
        sw = cell_w,
        sh = cell_h
    }

    self.index = args.index or 0

    if self.atlas then
        self:set_from_index(self.index)
    else
        -- fallback: manual quad definition
        local sx = args.sx or 0
        local sy = args.sy or 0
        local sw = args.sw or cell_w
        local sh = args.sh or cell_h
        self.sprite.image = self.sprite.image
        self:set_quad(sx, sy, sw, sh)
    end
end

function Sprite:set_image(image)
    self.sprite.image = image
    if self.sprite.quad then
        self:set_quad(self.sprite.sx, self.sprite.sy, self.sprite.sw, self.sprite.sh)
    end
end

function Sprite:set_quad(sx, sy, sw, sh)
    self.sprite.sx = sx
    self.sprite.sy = sy
    self.sprite.sw = sw
    self.sprite.sh = sh

    if self.sprite.image then
        local iw, ih = self.sprite.image:getDimensions()
        self.sprite.quad = love.graphics.newQuad(sx, sy, sw, sh, iw, ih)
    end
end

-- select a cell from the atlas by index (0-based)
function Sprite:set_from_index(index)
    self.index = index
    if not self.atlas or not self.atlas.image then return end

    local iw, ih = self.atlas.image:getDimensions()
    local cell_w, cell_h = self.atlas.px, self.atlas.py

    local cols = math.floor(iw / cell_w)
    if cols <= 0 then return end

    local col = index % cols
    local row = math.floor(index / cols)

    local sx = col * cell_w
    local sy = row * cell_h

    self.sprite.image = self.atlas.image
    self:set_quad(sx, sy, cell_w, cell_h)
end

function Sprite:draw_sprite()
    if not self.sprite.image or not self.sprite.quad then return end
    
    local prev_r, prev_g, prev_b, prev_a = love.graphics.getColor()
    love.graphics.setColor(1, 1, 1, 1)
    
    local draw_x = self.VT.x + self.collision_offset.x
    local draw_y = self.VT.y + self.collision_offset.y
    
    love.graphics.push()
    
    local cx = draw_x + (self.VT.w * self.VT.scale) / 2
    local cy = draw_y + (self.VT.h * self.VT.scale) / 2
    
    love.graphics.translate(cx, cy)
    love.graphics.rotate(self.VT.r)
    love.graphics.scale(self.VT.scale, self.VT.scale)
    love.graphics.translate(-cx, -cy)
    
    local scale_x = self.VT.w / self.sprite.sw
    local scale_y = self.VT.h / self.sprite.sh
    
    love.graphics.draw(
        self.sprite.image,
        self.sprite.quad,
        draw_x,
        draw_y,
        0,
        scale_x,
        scale_y
    )
    
    love.graphics.pop()
    love.graphics.setColor(prev_r, prev_g, prev_b, prev_a)
end

function Sprite:draw()
    if self.states.visible then
        self:draw_sprite()
        self:draw_boundingrect()
        
        for _, v in pairs(self.children) do
            v:draw()
        end
    end
end
