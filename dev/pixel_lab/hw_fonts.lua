--- Text as the 3DS draws it.
---
--- `bake_hw_fonts.py` reproduces the glyph sheets `dev/build.sh` bakes with mkbcfnt, from the
--- same `PIXEL_FONT_SHEETS` table. This swaps them in for the desktop `.ttf` fallback in
--- `Fonts.font_for`, and matches the two runtime behaviours that change what a glyph looks like:
---
---  * sampling is linear, always (`font.cpp` CreateTexture hardcodes GPU_LINEAR on ctr and
---    `Font::SetSamplerState` is a stub), so any `setFilter` call on a font is ignored;
---  * a line advances by the sheet's cell height (`genericshaper.cpp`/`font.cpp`: the CTR
---    rasterizer reports `cellHeight * scale` as its height and a line height of 1), not by the
---    sheet's lineFeed.
---
--- The sheets are rebaked whenever the ladder in `dev/config.sh` changes.
local HwFonts = {}

local CACHE = "dev/pixel_lab/.cache/fonts"

--- `cell:pt` pairs from dev/config.sh PIXEL_FONT_SHEETS, so the lab follows the build.
local function read_ladder()
    local text = love.filesystem.read("dev/config.sh")
    assert(text, "dev/config.sh not readable")
    local block = text:match("PIXEL_FONT_SHEETS=%((.-)%)")
    assert(block, "PIXEL_FONT_SHEETS not found in dev/config.sh")
    local ladder = {}
    for cell, pt in block:gmatch('"(%d+):([%d%.]+)"') do
        ladder[#ladder + 1] = { cell = tonumber(cell), pt = pt }
    end
    assert(#ladder > 0, "PIXEL_FONT_SHEETS is empty")
    return ladder
end

local function baked_matches(ladder)
    local listing = love.filesystem.read(CACHE .. "/hw_fonts.txt")
    if not listing then return false end
    local want = {}
    for _, s in ipairs(ladder) do want[#want + 1] = s.cell .. " " .. s.pt end
    local have = {}
    for line in listing:gmatch("[^\n]+") do
        have[#have + 1] = line:match("^(%S+ %S+)")
    end
    return table.concat(want, ";") == table.concat(have, ";")
end

local function bake(ladder)
    local base = love.filesystem.getSource()
    local args = {}
    for _, s in ipairs(ladder) do args[#args + 1] = s.cell .. ":" .. s.pt end
    local cmd = string.format('python "%s/dev/pixel_lab/bake_hw_fonts.py" "%s/resources/fonts/m6x11plus.ttf" "%s/%s" %s',
        base, base, base, CACHE, table.concat(args, " "))
    io.write("[pixel-lab] baking hardware font sheets: ", cmd, "\n")
    local ok = os.execute(cmd)
    assert(ok == 0 or ok == true, "bake_hw_fonts.py failed; is freetype-py installed? (pip install freetype-py pillow)")
end

local function force_linear(font)
    font:setFilter("linear", "linear")
    -- Hardware ignores filter changes on fonts; so does the lab.
    local mt = getmetatable(font)
    if not mt.__pixel_lab_patched then
        mt.__pixel_lab_patched = true
        local set = mt.__index.setFilter
        mt.__index.setFilter = function(self, ...)
            if rawget(HwFonts.owned, self) or HwFonts.owned[self] then return end
            return set(self, ...)
        end
    end
end

HwFonts.owned = setmetatable({}, { __mode = "k" })

function HwFonts.install()
    local ladder = read_ladder()
    if not baked_matches(ladder) then bake(ladder) end
    local by_cell = {}
    for _, s in ipairs(ladder) do by_cell[s.cell] = s end

    local Fonts = require "fonts"
    local original = Fonts.font_for
    Fonts.font_for = function(profile, size, language)
        if language or profile ~= "native" or not by_cell[size] then
            return original(profile, size, language)
        end
        local font = love.graphics.newFont(string.format("%s/hw_h%d.fnt", CACHE, size))
        HwFonts.owned[font] = true
        force_linear(font)
        return font, true
    end
end

return HwFonts
