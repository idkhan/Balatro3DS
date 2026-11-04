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

return PixelGrid
