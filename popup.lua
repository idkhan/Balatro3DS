--@class Popup
-- Scoring status text. The reference anchors these to the card that raised them and holds
-- them for a per-type beat (`reference/Balatro/functions/common_events.lua:779-935`): chips
-- 0.6*1.25, most things 0.65*1.25, joker messages 0.75*1.25. Nothing scatters and nothing
-- rotates — the pop reads as a crisp label, not an arcade damage number.
Popup = Object:extend()

remove = false
local DEFAULT_TIME = 0.8125 -- 0.65 * 1.25
local TIME_BY_TYPE = {
    chips = 0.75, -- 0.6 * 1.25
    Nope = 0.9375, -- joker-message hold, 0.75 * 1.25
}
-- Anchored a fixed height above the spawn point, with a small upward drift over the hold.
local ANCHOR_Y_OFF = -32
local DRIFT_PX = 8

function Popup:init()
    self.time = DEFAULT_TIME
    self.duration = DEFAULT_TIME
    self.text = "+30"
    self.pos = { x = 0, y = 0 }
    self.delay = 0
end

--- @param delay number|nil seconds to wait before appearing, for effects that share a card
function Popup:spawn(amount, type, x, y, scale, delay)
    self.text = amount
    self.pos.x = x
    self.pos.y = y + ANCHOR_Y_OFF
    self.scale = scale or 1
    self:checkType(type)
    self.duration = TIME_BY_TYPE[type] or DEFAULT_TIME
    self.time = self.duration
    -- A card with more than one effect raises more than one of these from the same point. The
    -- reference separates them in time because each is its own blocking event; here they would
    -- otherwise stack on the same pixels and be unreadable, so later effects wait their turn.
    self.delay = math.max(0, tonumber(delay) or 0)
end

--- Whether this popup is still waiting to appear.
--- @return boolean
function Popup:is_pending()
    return (self.delay or 0) > 0
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
        self.Color = G.C.BOOSTER
        if self.scale == 1 then self.scale = 2 end
    else
        self.Color = G.C.WHITE
        self.noRect = true
    end
end

function Popup:get_anim_scale()
    local timeFactor = 1 - self.time / (self.duration or DEFAULT_TIME)
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
    if self:is_pending() then return end
    depthOffset = tonumber(depthOffset) or 0
    local effectiveScale, timeFactor = self:get_anim_scale()
    local font = self:pick_font(effectiveScale)
    love.graphics.setFont(font)

    local w = font:getWidth(self.text)
    local h = font:getHeight(self.text)
    local drift = DRIFT_PX * timeFactor
    local drawX = math.floor(self.pos.x - w / 2 + 0.5 - depthOffset)
    local drawY = math.floor(self.pos.y - h / 2 - drift + 0.5)
    local alpha = math.min(1, self.time * 2)

    --Rectangle Behind Text
    if not self.noRect then
        local r, g, b = self.Color[1], self.Color[2], self.Color[3]
        love.graphics.setColor(r, g, b, alpha)
        love.graphics.rectangle("fill", drawX - 5, drawY - 5, w + 10, h + 10)
    end

    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.print(self.text, drawX, drawY)
    love.graphics.setColor(1, 1, 1, 1)
end

function Popup:update(dt)
    -- Burn the wait first, and only start the hold once it is spent, so a delayed popup gets
    -- its full duration rather than a duration shortened by however long it waited.
    if self:is_pending() then
        self.delay = self.delay - dt
        if self.delay > 0 then return end
        -- Any overshoot past the delay is time the hold should already have used.
        dt = -self.delay
        self.delay = 0
    end
    self.time = self.time - dt
    if self.time <= 0 then
        self.time = 0
        self.text = ""
        self.remove = true
    end
end
