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
    -- Last touch delta while dragging, used for tilt-in-motion
    self.drag_velocity = { x = 0, y = 0 }
    self.drag_raise_scale = 1.08
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
    self.VT.scale = (self.T.scale or 1) * (self.drag_raise_scale or 1.08)
end

function Moveable:touchmoved(id, x, y, dx, dy)
    if not self.states.drag.is then return end
    
    self.VT.x = x - self.click_offset.x
    self.VT.y = y - self.click_offset.y
    self.drag_velocity.x = dx
    self.drag_velocity.y = dy
end

function Moveable:touchreleased(id, x, y)
    self.states.drag.is = false
    self.drag_velocity.x = 0
    self.drag_velocity.y = 0
end

function Moveable:update(dt)
    local lerp_speed = 10 * dt
    local dx, dy

    if self.states.drag.is then
        dx = self.drag_velocity.x
        dy = self.drag_velocity.y
        -- Decay so tilt eases back when finger stops moving
        self.drag_velocity.x = self.drag_velocity.x * 0.7
        self.drag_velocity.y = self.drag_velocity.y * 0.7
    else
        dx = self.T.x - self.VT.x
        dy = self.T.y - self.VT.y
        self.VT.x = self.VT.x + dx * lerp_speed
        self.VT.y = self.VT.y + dy * lerp_speed
        self.VT.scale = self.VT.scale + (self.T.scale - self.VT.scale) * lerp_speed
    end

    -- Slight tilt toward direction of motion (while dragging or returning); straighten when velocity ~0
    local vel_mag = math.sqrt(dx * dx + dy * dy)
    local max_tilt = 0.10
    local tilt
    if vel_mag > 2 then
        tilt = math.atan2(dy, dx) + math.pi
        if tilt > math.pi then tilt = tilt - 2 * math.pi end
        if tilt > max_tilt then tilt = max_tilt elseif tilt < -max_tilt then tilt = -max_tilt end
    else
        tilt = 0
    end
    local target_r = self.T.r + tilt
    self.VT.r = self.VT.r + (target_r - self.VT.r) * lerp_speed
end

function Moveable:draw_boundingrect()
    if not G or not G.DEBUG then return end
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