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
--- Positions and angles snap even while they animate. Nearest-filtered art cannot be shown
--- between pixels anyway, so a snapped slide steps exactly as the unsnapped one would appear,
--- and every layer of an object steps together. An animation that eases a *scale* (a juice pop,
--- a card being dealt) still moves through fractional values. Snapping that would make it step
--- visibly, which is worse.
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

--- Whether a scale about an anchor is too close to 1 to show. If no point within `extent`
--- pixels of the anchor moves half a pixel, the scaled draw covers the same pixels as a plain
--- one, except that text is resampled off the grid and blurs. The settling tail of a pop (0.99,
--- 1.015, ...) is drawn plain instead; the pop itself, which visibly moves edges, is not.
---@param scale number
---@param extent number farthest drawn pixel from the scale's anchor
---@return boolean
function PixelGrid.at_rest(scale, extent)
    return math.abs(scale - 1) * extent < 0.5
end

--- The angle to draw a `w` x `h` sprite at when it rotates about its centre.
---
--- Nearest-filtered art rotated by a small angle is sheared, not turned: each row is shifted by a
--- whole pixel where the rotation crosses half a pixel, so a seam runs across the art. While the
--- angle eases (a sway, a lean, a wobble), those seams slide through the art every frame and the
--- sprite shimmers, even though its outline moves less than a pixel. Rounding the angle to steps
--- that move the corners one whole pixel keeps the seams still between steps, so the art changes
--- only when its outline visibly moves. Under half a step it rounds to 0 and draws square.
---
--- Snap the sprite's position too: a rotation about a pivot that drifts between pixels moves the
--- seams just the same.
---@param r number radians
---@param w number drawn width
---@param h number drawn height
---@return number
function PixelGrid.turn(r, w, h)
    if r == 0 then return 0 end
    -- One step turns the corners, half the diagonal from the centre, by one pixel.
    local step = 2 / math.sqrt(w * w + h * h)
    return math.floor(r / step + 0.5) * step
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
