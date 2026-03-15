---@class Moveable : Node
Moveable = Node:extend()


---@param args {T: table, container: Node}
function Moveable:init(X,Y,W,H)
    local args = (type(X) == 'table') and X or {T ={X or 0,Y or 0,W or 0,H or 0}}
    Node.init(self, args)

    --The Visible transform is initally set to the same values as the transform T.
    --Note that the VT has an extra 'scale' factor, this is used to manipulate the center-adjusted
    --scale of any objects that need to be drawn larger or smaller
    self.VT = {
        x = self.T.x,
        y = self.T.y,
        w = self.T.w,
        h = self.T.h,
        r = self.T.r,
        scale = self.T.scale
    }

    --To determine location of VT, we need to keep track of the velocity of VT as it approaches T for the next frame
    self.velocity = {x = 0, y = 0, r = 0, scale = 0, mag = 0}
end

function Moveable:draw()
    Node.draw(self)
    self:draw_boundingrect()
end

function Moveable:touchpressed(id, x, y)
    if not self.states.drag.can then return end
    
    self.states.drag.is = true
    self.click_offset.x = x - self.VT.x
    self.click_offset.y = y - self.VT.y
end

function Moveable:touchmoved(id, x, y, dx, dy)
    if not self.states.drag.is then return end
    
    self.VT.x = x - self.click_offset.x
    self.VT.y = y - self.click_offset.y
end

function Moveable:touchreleased(id, x, y)
    self.states.drag.is = false
end

function Moveable:update(dt)
    if self.states.drag.is then return end
    
    local lerp_speed = 10 * dt
    self.VT.x = self.VT.x + (self.T.x - self.VT.x) * lerp_speed
    self.VT.y = self.VT.y + (self.T.y - self.VT.y) * lerp_speed
    self.VT.r = self.VT.r + (self.T.r - self.VT.r) * lerp_speed
    self.VT.scale = self.VT.scale + (self.T.scale - self.VT.scale) * lerp_speed
end

function Moveable:draw_boundingrect()
    local prev_r, prev_g, prev_b, prev_a = love.graphics.getColor()
    
    local draw_x = self.VT.x + self.collision_offset.x
    local draw_y = self.VT.y + self.collision_offset.y
    
    if self.states.collide.is then
        love.graphics.setColor(1, 0, 0, 1)
    else
        love.graphics.setColor(0, 1, 0, 1)
    end
    
    love.graphics.push()
    
    local cx = draw_x + (self.VT.w * self.VT.scale) / 2
    local cy = draw_y + (self.VT.h * self.VT.scale) / 2
    
    love.graphics.translate(cx, cy)
    love.graphics.rotate(self.VT.r)
    love.graphics.translate(-cx, -cy)
    
    love.graphics.rectangle(
        "line",
        draw_x,
        draw_y,
        self.VT.w * self.VT.scale,
        self.VT.h * self.VT.scale
    )
    
    love.graphics.pop()
    love.graphics.setColor(prev_r, prev_g, prev_b, prev_a)
end