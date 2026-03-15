---@class Node
Node = Object:extend()

---@param args {T: table, container: Node}

function Node:init(args)
    args = args or {}
    args.T = args.T or {}

    --Store all argument and return tables here for reuse, because Lua likes to generate garbage
    self.ARGS = self.ARGS or {}
    self.RETS = {}

    --Config table used for any metadata about this node
    self.config = self.config or {}

    --For transform init, accept params in the form x|1, y|2, w|3, h|4, r|5
    self.T = {
        x = args.T.x or args.T[1] or 0,
        y = args.T.y or args.T[2] or 0,
        w = args.T.w or args.T[3] or 1,
        h = args.T.h or args.T[4] or 1,
        r = args.T.r or args.T[5] or 0,
        scale = args.T.scale or args.T[6] or 1,
    }

    --Transform to use for collision detection
    self.CT = self.T

    --Create the offset tables, used to determine things like drag offset and 3d shader effects
    self.click_offset = { x = 0, y = 0 }
    self.hover_offset = { x = 0, y = 0 }

    --Frame tracker to aid in not doing too many extra calculations
    self.FRAME = {
        DRAW = -1,
        MOVE = -1
    }

    --The states for this Node and all derived nodes. This is how we control the visibility and interactibility of any object
    --All nodes do not collide by default. This reduces the size of n for the O(n^2) collision detection
    self.states = {
        visible = true,
        collide = { can = false, is = false },
        focus = { can = false, is = false },
        hover = { can = true, is = false },
        click = { can = true, is = false },
        drag = { can = true, is = false },
        release_on = { can = true, is = false }
    }

    --The list of children give Node a treelike structure. This can be used for things like drawing, deterministice movement and parallax
    --calculations when child nodes rely on updated information from parents, and inherited attributes like button click functions
    if not self.children then
        self.children = {}
    end
    
    --Collision offset applied when nudged by other collidable objects
    self.collision_offset = { x = 0, y = 0 }
end

function Node:get_collision_rect()
    local t = self.VT or self.T
    return {
        x = t.x + self.collision_offset.x,
        y = t.y + self.collision_offset.y,
        w = t.w * t.scale,
        h = t.h * t.scale
    }
end

--Draw a bounding rectangle representing the transform of this node. Used in debugging.
function Node:draw_boundingrect()
    local prev_r, prev_g, prev_b, prev_a = love.graphics.getColor()
    
    love.graphics.setColor(0, 1, 0, 1)
    
    love.graphics.push()
    
    local cx = self.T.x + (self.T.w * self.T.scale) / 2
    local cy = self.T.y + (self.T.h * self.T.scale) / 2
    
    love.graphics.translate(cx, cy)
    love.graphics.rotate(self.T.r)
    love.graphics.translate(-cx, -cy)
    
    love.graphics.rectangle(
        "line",
        self.T.x,
        self.T.y,
        self.T.w * self.T.scale,
        self.T.h * self.T.scale
    )
    
    love.graphics.pop()
    
    love.graphics.setColor(prev_r, prev_g, prev_b, prev_a)
end

--Draws self, then adds self the the draw hash, then draws all children
function Node:draw()
    self:draw_boundingrect()
    if self.states.visible then
        ---add_to_drawhash(self)
        for _, v in pairs(self.children) do
            v:draw()
        end
    end
end
