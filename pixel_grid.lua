--- Placing art and text on the 3DS's pixel grid.
---
--- Both screens are drawn 1:1 into 400x240 and 320x240 framebuffers, so a coordinate or scale
--- that is not a whole number cannot be shown as such. The two samplers fail differently:
---
---  * Nearest-filtered art (every sprite sheet, `game.lua` texture_scaling) at a non-integer
---    scale repeats some source rows and columns and drops others, so its pixels come out
---    uneven. At a fractional origin it snaps, but layers of one object can snap in different
---    directions and land a pixel apart.
---  * Glyph sheets are always sampled linearly (LovePotion `font.cpp`), so text off the grid
---    or at any scale but 1 is blurred.
---
--- These helpers are for *layout*, meaning positions and scales that hold still. An animation
--- that eases a scale (a juice pop, a card being dealt) still moves through fractional values.
--- Snapping that would make it step visibly, which is worse.
local PixelGrid = {}

--- Nearest whole pixel.
---@param v number
---@return integer
function PixelGrid.snap(v)
    return math.floor(v + 0.5)
end

--- The scale a layout should draw nearest-filtered art at: the nearest whole number at or
--- above 1. A downscale is returned as it is, because no whole number is left below 1. Art
--- shrunk below 1 needs a sheet baked at its size (see `dev/bake_button_pips.py`).
---@param s number
---@return number
function PixelGrid.art_scale(s)
    if s < 1 then return s end
    return math.floor(s + 0.5)
end

--- Stroke a rectangle's outline inside its edges, at the current line width.
---
--- LÖVE centres a stroke on the path. Traced on whole-pixel edges, a 1 or 3 px line straddles
--- them by half a pixel and the rasteriser picks a side per edge: the top panel's border sat one
--- row above its fill and its bottom border one row inside, and the PICA200 is free to choose
--- differently again. The old `x + 0.5, w - 1` workaround only fits a 1 px line; at 2 px it put
--- the stroke back across the edge. Insetting by half the width, whatever it is, keeps every
--- stroke on whole pixels inside `x, y, w, h`. The radius is the outer corner's, so the border
--- follows a fill drawn with the same rectangle.
---@param x number
---@param y number
---@param w number
---@param h number
---@param radius number|nil
function PixelGrid.outline(x, y, w, h, radius)
    local x1, y1 = math.floor(x + w + 0.5), math.floor(y + h + 0.5)
    x, y = math.floor(x + 0.5), math.floor(y + 0.5)
    local inset = love.graphics.getLineWidth() / 2
    local r = math.max(0, (radius or 0) - inset)
    love.graphics.rectangle("line", x + inset, y + inset, x1 - x - 2 * inset, y1 - y - 2 * inset, r, r)
end

return PixelGrid
