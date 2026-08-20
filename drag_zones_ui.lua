--- Drop zones for drag-to-buy/sell/use/pick (320x240 bottom screen).
---@class DragZonesUI
local DragZonesUI = {}

local SCREEN_W = 320
local SCREEN_H = 240
local TOP_STRIP_H = 64
local BOTTOM_STRIP_H = 64
local BOTTOM_STRIP_Y = SCREEN_H - BOTTOM_STRIP_H
local TOP_RIGHT_SIZE = 138

local function zone_rects()
    return {
        top = { x = 0, y = 0, w = SCREEN_W - TOP_RIGHT_SIZE, h = TOP_STRIP_H },
        top_right = { x = SCREEN_W - TOP_RIGHT_SIZE, y = 0, w = TOP_RIGHT_SIZE, h = TOP_STRIP_H },
        bottom = { x = 0, y = BOTTOM_STRIP_Y, w = SCREEN_W, h = BOTTOM_STRIP_H },
        full = { x = 0, y = 0, w = SCREEN_W, h = TOP_STRIP_H },
    }
end

local function point_in_rect(rect, x, y)
    if not rect then return false end
    return x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h
end

local function zone_fill_color(zone)
    if not zone or not zone.visible then return nil end
    local c = zone.color or { 0.5, 0.5, 0.5 }
    return { c[1] or 0.5, c[2] or 0.5, c[3] or 0.5, zone.enabled and 0.55 or 0.35 }
end

---@param zones table|nil
---@return string|nil zone_id
---@return table|nil zone
function DragZonesUI.hit_test(zones, x, y)
    if not zones then return nil, nil end
    -- Full-width strip takes priority over split top / top-right.
    if zones.full and zones.full.visible and point_in_rect(zones.full.rect, x, y) then
        return "full", zones.full
    end
    if zones.top_right and zones.top_right.visible and point_in_rect(zones.top_right.rect, x, y) then
        return "top_right", zones.top_right
    end
    if zones.top and zones.top.visible and point_in_rect(zones.top.rect, x, y) then
        return "top", zones.top
    end
    if zones.bottom and zones.bottom.visible and point_in_rect(zones.bottom.rect, x, y) then
        return "bottom", zones.bottom
    end
    return nil, nil
end

---@param zones table|nil
function DragZonesUI.draw(game, zones)
    if not zones then return end
    local order = { "full", "top", "top_right", "bottom" }
    local fallback = zone_rects()
    for _, key in ipairs(order) do
        local zone = zones[key]
        if zone and zone.visible then
            local rect = zone.rect or fallback[key]
            local fill = zone_fill_color(zone)
            if fill and love and love.graphics then
                love.graphics.setColor(fill)
                love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h)
                love.graphics.setColor(fill)
                love.graphics.setLineWidth(2)
                love.graphics.rectangle("line", rect.x + 0.5, rect.y + 0.5, rect.w - 1, rect.h - 1)
                local label = zone.label or ""
                local font = game and game.FONTS and game.FONTS.PIXEL and game.FONTS.PIXEL.SMALL
                if label ~= "" and font then
                    love.graphics.setFont(font)
                    love.graphics.setColor(1, 1, 1, zone.enabled and 1 or 0.65)
                    local tw = font:getWidth(label)
                    local th = font:getHeight()
                    local lx = math.floor(rect.x + (rect.w - tw) * 0.5)
                    local ly = math.floor(rect.y + (rect.h - th) * 0.5)
                    love.graphics.print(label, lx, ly)
                end
            end
        end
    end
    if love and love.graphics then
        love.graphics.setColor(1, 1, 1, 1)
    end
end

function DragZonesUI.make_zone(label, enabled, color, action, visible)
    return {
        label = label,
        enabled = enabled == true,
        color = color or { 0.5, 0.5, 0.5 },
        action = action,
        visible = visible ~= false,
    }
end

function DragZonesUI.attach_rects(zones)
    if not zones then return zones end
    local rects = zone_rects()
    for key, rect in pairs(rects) do
        if zones[key] then
            zones[key].rect = rect
        end
    end
    return zones
end

return DragZonesUI
