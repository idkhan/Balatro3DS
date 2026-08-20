--@class Popup
Popup = Object:extend()

remove = false 
popupTime = 0.75
function Popup:init()
    self.time = popupTime
    self.text = "+30"
    self.pos = { x = 0, y = 0 }
    self.speed = math.random(-90, 90)
end

function Popup:spawn(amount, type, x, y, scale)
    self.text = amount
    self.time = popupTime
    self.pos.x = x + math.random(-10, 10)
    self.pos.y = y + math.random(-20, 20)
    if scale then
        self.scale = scale
    else
        self.scale = 1
    end
    self:checkType(type)
end

function Popup:checkType(type)
    if type == "chips" then
        self.text = "+" .. self.text
        self.Color = G.C.CHIPS
    elseif type == "money" then
        self.text = "+" .. self.text
        self.Color = G.C.MONEY
    elseif type == "mult" then
        self.text = "+" .. self.text
        self.Color = G.C.MULT
    elseif type == "xmult" then
        self.text = "x" .. self.text
        self.Color = G.C.XMULT
    elseif type == "Nope" then
        self.text = self.text
        self.Color = G.C.BOOSTER
        self.scale = 5
    else 
        self.text = self.text
        self.Color = G.C.WHITE
        self.noRect = true
    end
end

function Popup:get_anim_scale()
    local timeFactor = 1 - self.time / popupTime
    timeFactor = math.max(math.min(timeFactor, 1), 0)
    local pop = 1 + 2 * timeFactor - 5 * math.pow(timeFactor, 2) + 3 * math.pow(timeFactor, 3)
    return (self.scale or 1) * pop, timeFactor
end

function Popup:pick_font(effectiveScale)
    local fonts = G and G.FONTS and G.FONTS.PIXEL
    if not fonts then return love.graphics.getFont() end
    if effectiveScale >= 2.5 then return fonts.LARGE end
    if effectiveScale >= 1.5 then return fonts.MEDIUM end
    return fonts.SMALL
end

function Popup:draw(depthOffset)
    depthOffset = tonumber(depthOffset) or 0
    local effectiveScale, timeFactor = self:get_anim_scale()
    local font = self:pick_font(effectiveScale)
    love.graphics.setFont(font)

    local w = font:getWidth(self.text)
    local h = font:getHeight(self.text)
    local drawX = math.floor(self.pos.x - w / 2 + 0.5 - depthOffset)
    local drawY = math.floor(self.pos.y - h / 2 + 0.5)
    local alpha = math.min(1, self.time * 2)

    --Rectangle Behind Text
    if not self.noRect then
        love.graphics.push()
        love.graphics.setColor(self.Color)
        local r, g, b = love.graphics.getColor()
        love.graphics.setColor(r, g, b, alpha)
        love.graphics.translate(math.floor(self.pos.x + 0.5 - depthOffset), math.floor(self.pos.y + 0.5))
        love.graphics.rotate(math.rad(self.speed * timeFactor))
        love.graphics.rectangle("fill", -w / 2 - 5, -h / 2 - 5, w + 10, h + 10)
        love.graphics.pop()
    end

    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.print(self.text, drawX, drawY)
    love.graphics.setColor(1, 1, 1, 1)
end

function Popup:update(dt)
    self.time = self.time - dt
    if self.time <= 0 then
        self.time = 0
        self.text = ""
        self.remove = true
    end
end