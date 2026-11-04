--- Draw-geometry audit: which draw calls put pixels somewhere the 3DS cannot draw them cleanly.
---
--- Every `love.graphics.draw`, `print` and `printf` is resolved to screen space (the current
--- transform stack included) and classified:
---
---  * text_subpixel     text whose origin is not on a whole pixel. LövePotion samples every font
---                      sheet with GPU_LINEAR (`font.cpp` CreateTexture), so this is blurred text
---                      on hardware, however crisp the glyph sheet is.
---  * text_scaled       text drawn with a scale other than 1: a resample of the glyph sheet.
---  * art_fractional_scale  nearest-filtered art at a non-integer scale. Some source pixels come
---                      out one screen pixel wide and some two -- the uneven, "misaligned" pixel
---                      look, and it shimmers when the scale animates.
---  * art_subpixel      nearest-filtered art at a whole-number scale but a fractional origin. The
---                      GPU snaps it, so a still frame looks fine; layers of one object snapped
---                      from different fractions land a pixel apart, and motion stutters.
---  * linear_subpixel   linear-filtered art off the pixel grid (blur).
---  * rotated           any rotation that is not a multiple of 90 degrees.
---
---  * shape_subpixel    a rectangle whose edges are not on whole pixels. Each edge snaps on its
---                      own, so its width wobbles by a pixel while it moves, and it parts company
---                      with the text or art drawn on it.
---
--- Findings are grouped by the call site that issued the draw, so the report reads as a list of
--- lines to fix rather than a list of frames.
local Audit = {}

local EPS = 0.02
local sites = {}
local screen = "?"
local capture_name = nil
local frame_index = 0
local captured_frames = 0
local orig = {}

local function frac_off(v)
    return math.abs(v - math.floor(v + 0.5)) > EPS
end

local function is_int_scale(s)
    s = math.abs(s)
    if s < EPS then return true end
    return math.abs(s - math.floor(s + 0.5)) <= EPS
end

local SELF = debug.getinfo(1, "S").source

local function call_site()
    local frames = {}
    local level = 3
    while #frames < 3 do
        local info = debug.getinfo(level, "Sl")
        if not info then break end
        if info.source ~= SELF and info.currentline and info.currentline > 0 then
            local src = info.short_src:gsub("^%.[/\\]", ""):gsub("\\", "/")
            frames[#frames + 1] = src .. ":" .. info.currentline
        end
        level = level + 1
    end
    return frames
end

local function record(kind, x, y, sx, sy, r)
    local stack = call_site()
    local key = kind .. "|" .. (stack[1] or "?")
    local s = sites[key]
    if not s then
        s = { kind = kind, site = stack[1] or "?", stack = stack, count = 0, frames = {},
            nframes = 0, screens = {}, captures = {}, samples = {} }
        sites[key] = s
    end
    s.count = s.count + 1
    if not s.frames[frame_index] then
        s.frames[frame_index] = true
        s.nframes = s.nframes + 1
    end
    s.screens[screen] = true
    if capture_name then s.captures[capture_name] = true end
    if #s.samples < 6 then
        s.samples[#s.samples + 1] = string.format("x=%.3f y=%.3f sx=%.3f sy=%.3f r=%.3f", x, y, sx, sy, r)
    end
end

--- Screen-space origin, per-axis scale and rotation of a draw, from the local transform
--- arguments and the current transform stack.
local function resolve(x, y, r, sx, sy, ox, oy)
    x, y, r = x or 0, y or 0, r or 0
    sx = sx or 1
    sy = sy or sx
    ox, oy = ox or 0, oy or 0
    local c, s = math.cos(r), math.sin(r)
    local function local_pt(u, v)
        local lx, ly = (u - ox) * sx, (v - oy) * sy
        return x + c * lx - s * ly, y + s * lx + c * ly
    end
    local tp = love.graphics.transformPoint
    local x0, y0 = tp(local_pt(0, 0))
    local x1, y1 = tp(local_pt(1, 0))
    local x2, y2 = tp(local_pt(0, 1))
    local ax, ay = x1 - x0, y1 - y0
    local bx, by = x2 - x0, y2 - y0
    local scale_x = math.sqrt(ax * ax + ay * ay)
    local scale_y = math.sqrt(bx * bx + by * by)
    local angle = math.atan2(ay, ax)
    return x0, y0, scale_x, scale_y, angle
end

local function from_transform(t)
    local tp = love.graphics.transformPoint
    local x0, y0 = tp(t:transformPoint(0, 0))
    local x1, y1 = tp(t:transformPoint(1, 0))
    local x2, y2 = tp(t:transformPoint(0, 1))
    local ax, ay = x1 - x0, y1 - y0
    local bx, by = x2 - x0, y2 - y0
    return x0, y0, math.sqrt(ax * ax + ay * ay), math.sqrt(bx * bx + by * by), math.atan2(ay, ax)
end

local function axis_aligned(angle)
    local q = angle / (math.pi / 2)
    return math.abs(q - math.floor(q + 0.5)) < 0.002
end

local function is_type(v, name)
    return type(v) == "userdata" and v.typeOf and v:typeOf(name)
end

local function texture_filter(drawable)
    if is_type(drawable, "Texture") then return (drawable:getFilter()) end
    if is_type(drawable, "SpriteBatch") or is_type(drawable, "Mesh") then
        local t = drawable:getTexture()
        return t and (t:getFilter()) or nil
    end
    return nil
end

local function classify_art(filter, x0, y0, scx, scy, angle)
    if not axis_aligned(angle) then
        record("rotated", x0, y0, scx, scy, angle)
        return
    end
    if filter == "nearest" then
        if not is_int_scale(scx) or not is_int_scale(scy) then
            record("art_fractional_scale", x0, y0, scx, scy, angle)
        elseif frac_off(x0) or frac_off(y0) then
            record("art_subpixel", x0, y0, scx, scy, angle)
        end
    elseif filter == "linear" then
        if frac_off(x0) or frac_off(y0) or not is_int_scale(scx) or not is_int_scale(scy) then
            record("linear_subpixel", x0, y0, scx, scy, angle)
        end
    end
end

local function classify_text(x0, y0, scx, scy, angle)
    if not axis_aligned(angle) then
        record("rotated", x0, y0, scx, scy, angle)
    elseif math.abs(scx - 1) > EPS or math.abs(scy - 1) > EPS then
        record("text_scaled", x0, y0, scx, scy, angle)
    elseif frac_off(x0) or frac_off(y0) then
        record("text_subpixel", x0, y0, scx, scy, angle)
    end
end

local function audit_draw(drawable, a, ...)
    local x0, y0, scx, scy, angle
    if is_type(a, "Quad") then
        local t = ...
        if is_type(t, "Transform") then
            x0, y0, scx, scy, angle = from_transform(t)
        else
            x0, y0, scx, scy, angle = resolve(...)
        end
    elseif is_type(a, "Transform") then
        x0, y0, scx, scy, angle = from_transform(a)
    else
        x0, y0, scx, scy, angle = resolve(a, ...)
    end
    if is_type(drawable, "Text") then
        classify_text(x0, y0, scx, scy, angle)
    else
        -- Meshes and batches carry their own vertex positions; only the transform is checked.
        classify_art(texture_filter(drawable), x0, y0, scx, scy, angle)
    end
end

local function audit_print(is_printf, text, a, ...)
    local rest
    if is_type(a, "Font") then
        rest = { ... }
    else
        rest = { a, ... }
    end
    local x, y = rest[1], rest[2]
    local r, sx, sy, ox, oy
    if is_printf then
        -- printf(text, x, y, limit, align, r, sx, sy, ox, oy)
        r, sx, sy, ox, oy = rest[5], rest[6], rest[7], rest[8], rest[9]
    else
        r, sx, sy, ox, oy = rest[3], rest[4], rest[5], rest[6], rest[7]
    end
    if is_type(x, "Transform") then
        classify_text(from_transform(x))
        return
    end
    classify_text(resolve(x, y, r, sx, sy, ox, oy))
end

local function audit_rect(mode, x, y, w, h)
    if type(x) ~= "number" then return end
    local tp = love.graphics.transformPoint
    local x0, y0 = tp(x, y)
    local x1, y1 = tp(x + (w or 0), y + (h or 0))
    local ax, ay = tp(x + 1, y)
    if math.abs(ay - y0) > 0.002 then
        record("rotated", x0, y0, x1 - x0, y1 - y0, math.atan2(ay - y0, ax - x0))
        return
    end
    if frac_off(x0) or frac_off(y0) or frac_off(x1) or frac_off(y1) then
        record("shape_subpixel", x0, y0, x1 - x0, y1 - y0, 0)
    end
end

function Audit.install()
    local g = love.graphics
    orig.draw, orig.print, orig.printf = g.draw, g.print, g.printf
    orig.rectangle = g.rectangle
    g.rectangle = function(mode, x, y, w, h, ...)
        audit_rect(mode, x, y, w, h)
        return orig.rectangle(mode, x, y, w, h, ...)
    end
    g.draw = function(drawable, ...)
        audit_draw(drawable, ...)
        return orig.draw(drawable, ...)
    end
    g.print = function(text, ...)
        audit_print(false, text, ...)
        return orig.print(text, ...)
    end
    g.printf = function(text, ...)
        audit_print(true, text, ...)
        return orig.printf(text, ...)
    end
end

function Audit.begin_frame(_, name)
    frame_index = frame_index + 1
    capture_name = name
    if name then captured_frames = captured_frames + 1 end
end

function Audit.set_screen(name) screen = name end
function Audit.end_frame() capture_name = nil end
function Audit.note_capture() end

local function keys(t)
    local out = {}
    for k in pairs(t) do out[#out + 1] = k end
    table.sort(out)
    return out
end

local KIND_ORDER = {
    "text_subpixel", "text_scaled", "art_fractional_scale", "art_subpixel",
    "linear_subpixel", "shape_subpixel", "rotated",
}

function Audit.write_report(txt_path, json_path)
    local list = {}
    for _, s in pairs(sites) do list[#list + 1] = s end
    table.sort(list, function(a, b)
        if a.kind ~= b.kind then return a.kind < b.kind end
        return a.nframes > b.nframes
    end)
    local f = assert(io.open(txt_path, "w"))
    f:write(string.format("pixel-lab draw audit: %d frames, %d call sites flagged\n\n",
        frame_index, #list))
    for _, kind in ipairs(KIND_ORDER) do
        local any = false
        for _, s in ipairs(list) do
            if s.kind == kind then
                if not any then
                    f:write("== ", kind, " ==\n")
                    any = true
                end
                f:write(string.format("%6d draws in %5d frames  %-34s screens=%s\n", s.count,
                    s.nframes, s.site, table.concat(keys(s.screens), ",")))
                f:write("        via ", table.concat(s.stack, " <- "), "\n")
                local caps = keys(s.captures)
                if #caps > 0 then
                    f:write("        in captures: ", table.concat(caps, ", "), "\n")
                end
                for _, smp in ipairs(s.samples) do f:write("        ", smp, "\n") end
            end
        end
        if any then f:write("\n") end
    end
    f:close()

    local jf = assert(io.open(json_path, "w"))
    jf:write("[\n")
    for i, s in ipairs(list) do
        jf:write(string.format('  {"kind":"%s","site":"%s","count":%d,"frames":%d,"captures":[%s]}%s\n',
            s.kind, s.site, s.count, s.nframes,
            (function()
                local c = {}
                for _, k in ipairs(keys(s.captures)) do c[#c + 1] = '"' .. k .. '"' end
                return table.concat(c, ",")
            end)(), i < #list and "," or ""))
    end
    jf:write("]\n")
    jf:close()
end

return Audit
