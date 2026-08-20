--- Shared item tooltips

local M = {}

local TOOLTIP_PAD_X = 8
local TOOLTIP_HEADER_PAD_Y = 3
local TOOLTIP_BODY_PAD_Y = 10
local TOOLTIP_BODY_PAD_TOP_RARITY = 4
local TOOLTIP_SPACING = 1
local TOOLTIP_SECTION_GAP = 2
local TOOLTIP_OUTER_PAD_X = 3
local TOOLTIP_OUTER_PAD_Y = 3
local RARITY_BADGE_PAD_X = 10
local RARITY_BADGE_PAD_Y = 3

--------------------------------------------------------------------------------
-- Appear animation
--------------------------------------------------------------------------------

--- Tooltips used to snap to full size the frame the player touched a card, which on a 240p
--- screen reads as a flicker rather than as something opening. The reference pops its info
--- boxes in through the UI spring (`UIBox:align_to_major` off `juice_up`), so this gives the
--- box the same short overshoot.
---
--- Scale only, no alpha: the box is drawn through a dozen `setColor` calls plus two global
--- rounded-rect helpers, so threading an alpha would touch every one of them, and at this
--- size a scale pop reads the same. A card uses `Fx.draw_dissolve_cell` for its own
--- appearance instead; a tooltip has no single sprite to run a mask over.
local TOOLTIP_APPEAR_DURATION = 0.13
--- Start size and the overshoot it passes through on the way to 1.
local TOOLTIP_APPEAR_FROM = 0.72
local TOOLTIP_APPEAR_OVERSHOOT = 1.05

--- Which tooltip is on screen and how long it has been there. Only one tooltip is ever visible
--- on a 320x240 playfield, so this is a single slot rather than a table keyed by node.
local appear = { key = nil, t = TOOLTIP_APPEAR_DURATION }
--- Set by `draw_tooltip_layout`, consumed by `M.update`. Drawing cannot advance the clock
--- itself: `love.draw` runs once per screen, so a tooltip would animate at double speed the
--- moment anything drew it twice in a frame.
local seen_key = nil

--- Advance the appear clock. Call once per frame, before or after drawing.
--- @param dt number real seconds
function M.update(dt)
    if seen_key == nil then
        -- Nothing drew a tooltip last frame, so the next one to appear starts from scratch.
        appear.key = nil
        return
    end
    if seen_key ~= appear.key then
        appear.key = seen_key
        appear.t = 0
    else
        appear.t = math.min(TOOLTIP_APPEAR_DURATION, appear.t + (tonumber(dt) or 0))
    end
    seen_key = nil
end

--- Scale for the tooltip identified by `key`, and a note of it for `update`.
--- @param key string
--- @return number
local function appear_scale(key)
    seen_key = key
    if key ~= appear.key then
        -- First frame of a new tooltip: it has not been through `update` yet.
        return TOOLTIP_APPEAR_FROM
    end
    local p = appear.t / TOOLTIP_APPEAR_DURATION
    if p >= 1 then return 1 end
    -- Rise to the overshoot over the first two thirds, settle back over the last third.
    if p < 0.66 then
        local q = p / 0.66
        return TOOLTIP_APPEAR_FROM + (TOOLTIP_APPEAR_OVERSHOOT - TOOLTIP_APPEAR_FROM) * q
    end
    local q = (p - 0.66) / 0.34
    return TOOLTIP_APPEAR_OVERSHOOT + (1 - TOOLTIP_APPEAR_OVERSHOOT) * q
end

local HAND_NAME_PHRASES = {
    "flush five",
    "flush house",
    "five of a kind",
    "straight flush",
    "four of a kind",
    "two of a kind",
    "full house",
    "three of a kind",
    "two pair",
    "high card",
    "straight",
    "straights",
    "flush",
    "flushes",
    "pair",
}

function M.append_segment(segments, text, color_key)
    if type(text) ~= "string" or text == "" then return end
    local last = segments[#segments]
    if last and last.color_key == color_key then
        last.text = last.text .. text
        return
    end
    table.insert(segments, { text = text, color_key = color_key })
end

local function apply_range(paints, priorities, s, e, color_key, prio)
    if type(s) ~= "number" or type(e) ~= "number" then return end
    s = math.max(1, math.floor(s))
    e = math.max(s, math.floor(e))
    prio = tonumber(prio) or 1
    for i = s, e do
        local old = priorities[i] or -1
        if prio >= old then
            priorities[i] = prio
            paints[i] = color_key
        end
    end
end

--- `hay` is the already-lowercased line. It used to be lowered inside here, which meant one
--- fresh copy of the whole line per phrase - and there are more than twenty phrase passes.
local function paint_phrase_ranges(hay, paints, priorities, phrase, color_key, prio)
    local needle = string.lower(phrase)
    local start_i = 1
    while true do
        local s, e = hay:find(needle, start_i, true)
        if not s then break end
        apply_range(paints, priorities, s, e, color_key, prio)
        start_i = e + 1
    end
end

local function paint_pattern_ranges(text, paints, priorities, pattern, color_key, prio)
    local start_i = 1
    while true do
        local s, e = text:find(pattern, start_i)
        if not s then break end
        apply_range(paints, priorities, s, e, color_key, prio)
        if e < start_i then
            start_i = start_i + 1
        else
            start_i = e + 1
        end
    end
end

--- Resolved segment lists, keyed by the raw text they came from.
---
--- Building one runs twenty-odd colouring passes over the line and allocates two arrays the
--- length of the string plus a table per colour run, and it was being done every frame for
--- every visible tooltip line. Description text barely ever changes, so the work is done once
--- per distinct string instead. Callers only ever read the result.
local segment_cache = {}
local segment_cache_count = 0
--- Cleared wholesale rather than evicted one at a time: this is a small bounded cache on a
--- 64 MB console, and a dropped entry costs one rebuild.
local SEGMENT_CACHE_LIMIT = 96

--- Store a built result under its source text, if it came from one.
local function remember_segments(cache_key, segments)
    if cache_key then
        if segment_cache_count >= SEGMENT_CACHE_LIMIT then
            segment_cache = {}
            segment_cache_count = 0
        end
        segment_cache[cache_key] = segments
        segment_cache_count = segment_cache_count + 1
    end
    return segments
end

--- Split *Balatro-style* description text into colored segments (asterisks stripped).
function M.build_segments_from_text(raw_text)
    local cache_key = type(raw_text) == "string" and raw_text or nil
    if cache_key then
        local hit = segment_cache[cache_key]
        if hit then return hit end
    end
    local text = tostring(raw_text or "")
    text = text:gsub("%*", "")
    local len = #text
    if len <= 0 then
        return remember_segments(cache_key, { { text = "", color_key = nil } })
    end

    local paints = {}
    local priorities = {}
    local hay = string.lower(text)

    paint_phrase_ranges(hay, paints, priorities, "tarot", "PURPLE", 50)
    paint_phrase_ranges(hay, paints, priorities, "planet", "CHIPS", 50)
    paint_phrase_ranges(hay, paints, priorities, "playing", "IMPORTANT", 50)
    paint_phrase_ranges(hay, paints, priorities, "spectral", "PURPLE", 49)
    paint_phrase_ranges(hay, paints, priorities, "joker", "MULT", 50)
    paint_phrase_ranges(hay, paints, priorities, "jokers", "MULT", 50)
    paint_pattern_ranges(text, paints, priorities, "%d+", "IMPORTANT", 46)
    paint_phrase_ranges(hay, paints, priorities, "hand size", "IMPORTANT", 55)
    paint_phrase_ranges(hay, paints, priorities, "discard", "RED", 56)
    paint_phrase_ranges(hay, paints, priorities, "discards", "RED", 56)
    paint_phrase_ranges(hay, paints, priorities, "discarded", "RED", 56)
    paint_pattern_ranges(text, paints, priorities, "%$%d+", "MONEY", 57)
    for _, hand_name in ipairs(HAND_NAME_PHRASES) do
        paint_phrase_ranges(hay, paints, priorities, hand_name, "IMPORTANT", 58)
    end

    paint_pattern_ranges(text, paints, priorities, "%d+/%d+:%s*", "CHANCE", 70)
    paint_pattern_ranges(text, paints, priorities, "%d+%s+[Ii][Nn]%s+%d+", "CHANCE", 70)
    paint_phrase_ranges(hay, paints, priorities, "chance", "CHANCE", 70)
    paint_phrase_ranges(hay, paints, priorities, "probabilities", "CHANCE", 70)

    paint_pattern_ranges(text, paints, priorities, "[Xx]%d+[%d%.]*%s*[Mm]ult", "MULT", 80)
    paint_pattern_ranges(text, paints, priorities, "[%+%-]?%d+[%d%.]*%s*[Mm]ult", "MULT", 80)
    paint_phrase_ranges(hay, paints, priorities, "mult", "MULT", 78)
    paint_pattern_ranges(text, paints, priorities, "[%+%-]?%d+[%d%.]*%s*[Cc]hips", "CHIPS", 80)
    paint_phrase_ranges(hay, paints, priorities, "chips", "CHIPS", 78)

    local segments = {}
    local current_color = paints[1]
    local run_start = 1
    for i = 2, len + 1 do
        local next_color = paints[i]
        if i == (len + 1) or next_color ~= current_color then
            M.append_segment(segments, text:sub(run_start, i - 1), current_color)
            run_start = i
            current_color = next_color
        end
    end
    if #segments <= 0 then
        return remember_segments(cache_key, { { text = text, color_key = nil } })
    end
    return remember_segments(cache_key, segments)
end

function M.tooltip_color_by_key(color_key)
    if not color_key then
        return { 0.22, 0.24, 0.26, 1 }
    end
    local C = (G and G.C) or {}
    if color_key == "MULT" then return C.MULT or { 0.9, 0.3, 0.4, 1 } end
    if color_key == "CHIPS" then return C.CHIPS or { 0.3, 0.7, 1, 1 } end
    if color_key == "CHANCE" then return C.CHANCE or C.GREEN or { 0.2, 0.75, 0.55, 1 } end
    if color_key == "PURPLE" then return C.PURPLE or { 0.66, 0.51, 0.82, 1 } end
    if color_key == "IMPORTANT" then return C.IMPORTANT or { 1, 0.6, 0.0, 1 } end
    if color_key == "MONEY" then return C.MONEY or { 0.9, 0.8, 0.2, 1 } end
    if color_key == "RED" then return C.RED or { 0.996, 0.373, 0.333, 1 } end
    return { 0.22, 0.24, 0.26, 1 }
end

--- One semantic line per non-empty row in `s` (split on newlines).
function M.resolved_lines_from_multiline(s)
    local resolved = {}
    for line in string.gmatch(tostring(s or "") .. "\n", "(.-)\n") do
        if line ~= "" then
            resolved[#resolved + 1] = M.build_segments_from_text(line)
        end
    end
    if #resolved == 0 then
        resolved[1] = M.build_segments_from_text(" ")
    end
    return resolved
end

--- Bottom-screen width. Kept here rather than as a constant because the tooltip is clamped to it
--- and `love.graphics.getWidth` needs the screen name under LövePotion's two-screen model.
local function screen_width()
    if not love.graphics.getWidth then return 320 end
    local w = love.graphics.getWidth("bottom")
    if not w or w <= 0 then w = love.graphics.getWidth() end
    if not w or w <= 0 then w = 320 end
    return w
end

--- Break one line's colour runs across as many lines as it takes to fit `limit`.
---
--- Catalog descriptions arrive pre-broken for a measure that assumed the smallest font, so nothing
--- wrapped at the shipped ladder - the box just grew until it hit the screen clamp and the text
--- past that edge was lost. Any larger font makes that reachable, so the break has to happen here
--- rather than in the catalog copy, which has no idea what size it will be drawn at.
---
--- Splitting on words, not characters, and carrying each word's colour with it: the segments are
--- colour runs (`build_segments_from_text`), so a naive split would repaint the wrapped remainder.
---@param font love.Font
---@param segments table[] { text, color_key? }
---@param limit number
---@return table[][] one segment array per output line
--- Hang a wrap result off the segment list it came from. Keyed by font and width, so a
--- font change or a different box still rewraps.
local function remember_wrap(segments, font, limit, lines)
    segments._wrap = { font = font, limit = limit, lines = lines }
    return lines
end

local function wrap_segments(font, segments, limit)
    -- A badge is a fixed-size pill, not prose; breaking it would just make a broken pill.
    if #segments == 1 and segments[1].rarity_badge then return { segments } end

    -- Wrapping allocates a table per word and measures each one, and the answer only changes
    -- when the text, the font or the available width does. Segment lists come from
    -- `build_segments_from_text`'s cache, so their identity is stable and the result can hang
    -- off the list itself rather than needing a second lookup table.
    local cached = segments._wrap
    if cached and cached.font == font and cached.limit == limit then return cached.lines end

    local words = {}
    for _, seg in ipairs(segments) do
        local color_key = seg.color_key
        -- Keep the separators: a colour run can begin or end mid-word, so joining on a single
        -- space would move the spacing between runs and shift the whole line.
        for chunk, gap in tostring(seg.text or ""):gmatch("(%S*)(%s*)") do
            if chunk ~= "" then words[#words + 1] = { text = chunk, color_key = color_key } end
            if gap ~= "" then words[#words + 1] = { text = gap, color_key = color_key, space = true } end
        end
    end

    local lines, current, width = {}, {}, 0
    local function flush()
        if #current > 0 then
            -- Trailing space would centre the line off by half a space.
            while #current > 0 and current[#current].space do table.remove(current) end
            if #current > 0 then lines[#lines + 1] = current end
        end
        current, width = {}, 0
    end
    for _, word in ipairs(words) do
        local w = font:getWidth(word.text)
        if word.space and #current == 0 then
            -- Leading space on a wrapped line; drop it.
        elseif #current > 0 and width + w > limit and not word.space then
            flush()
            current[1] = word
            width = w
        else
            current[#current + 1] = word
            width = width + w
        end
    end
    flush()
    if #lines == 0 then return remember_wrap(segments, font, limit, { segments }) end

    -- Re-merge adjacent runs of one colour so the draw loop makes one print call per run rather
    -- than one per word.
    local merged = {}
    for _, line in ipairs(lines) do
        local out = {}
        for _, word in ipairs(line) do M.append_segment(out, word.text, word.color_key) end
        merged[#merged + 1] = out
    end
    return remember_wrap(segments, font, limit, merged)
end

---@param font love.Font
---@param title string
---@param resolved_lines table[] each entry is an array of { text, color_key?, rarity_badge?, rarity_index? }
---@param draw_x number anchor top-left (e.g. card / pack sprite)
---@param draw_y number
---@param anchor_w number
---@param anchor_h number
function M.draw_tooltip_layout(font, title, resolved_lines, draw_x, draw_y, anchor_w, anchor_h)
    if not font or not title then return end
    resolved_lines = resolved_lines or {}
    if #resolved_lines == 0 then
        resolved_lines = { M.build_segments_from_text(" ") }
    end

    local prev_font = love.graphics.getFont()
    local prev_r, prev_g, prev_b, prev_a = love.graphics.getColor()
    love.graphics.setFont(font)

    -- Widest body line the box can hold and still be placed on screen: the box is clamped into
    -- [margin, sw - box_w - margin] below, so anything past this is drawn off the edge.
    local sw = screen_width()
    local body_limit = sw - (2 * 2) - (TOOLTIP_OUTER_PAD_X * 2) - (TOOLTIP_PAD_X * 2)
    local wrapped = {}
    for _, segments in ipairs(resolved_lines) do
        for _, line in ipairs(wrap_segments(font, segments, body_limit)) do
            wrapped[#wrapped + 1] = line
        end
    end
    resolved_lines = wrapped

    local header_w = font:getWidth(title)
    local line_h = font:getHeight()
    local body_line_heights = {}
    local body_max_w = 0
    for _, segments in ipairs(resolved_lines) do
        local w = 0
        if #segments == 1 and segments[1].rarity_badge then
            local seg = segments[1]
            w = font:getWidth(seg.text or "") + RARITY_BADGE_PAD_X * 2
            body_line_heights[#body_line_heights + 1] = line_h + RARITY_BADGE_PAD_Y * 2
        else
            for _, seg in ipairs(segments) do
                w = w + font:getWidth(seg.text or "")
            end
            body_line_heights[#body_line_heights + 1] = line_h
        end
        if w > body_max_w then body_max_w = w end
    end
    local body_lines_total_h = 0
    for i, h in ipairs(body_line_heights) do
        body_lines_total_h = body_lines_total_h + h
        if i < #body_line_heights then
            body_lines_total_h = body_lines_total_h + TOOLTIP_SPACING
        end
    end
    local first_is_rarity = #resolved_lines > 0
        and resolved_lines[1][1]
        and resolved_lines[1][1].rarity_badge == true
    local body_pad_top = first_is_rarity and TOOLTIP_BODY_PAD_TOP_RARITY or TOOLTIP_BODY_PAD_Y
    local header_w_total = header_w + (TOOLTIP_PAD_X * 2)
    local header_h_total = line_h + (TOOLTIP_HEADER_PAD_Y * 2)
    local body_w_total = body_max_w + (TOOLTIP_PAD_X * 2)
    local body_h_total = body_lines_total_h + body_pad_top + TOOLTIP_BODY_PAD_Y
    local inner_w = math.max(header_w_total, body_w_total)
    local inner_h = header_h_total + TOOLTIP_SECTION_GAP + body_h_total
    local box_w = inner_w + (TOOLTIP_OUTER_PAD_X * 2)
    local box_h = inner_h + (TOOLTIP_OUTER_PAD_Y * 2)

    local card_w = tonumber(anchor_w) or 0
    local card_h = tonumber(anchor_h) or 0
    local tx = draw_x + (card_w - box_w) * 0.5
    local ty = draw_y + card_h + 3
    local margin = 2
    tx = math.max(margin, math.min(tx, sw - box_w - margin))
    local sh = nil
    if love.graphics.getHeight then
        sh = love.graphics.getHeight("bottom")
        if not sh or sh <= 0 then
            sh = love.graphics.getHeight()
        end
    end
    if not sh or sh <= 0 then sh = 240 end
    if ty + box_h > sh - 2 then
        ty = draw_y - box_h - 3
    end
    if ty < 2 then ty = 2 end
    tx = math.floor(tx + 0.5)
    ty = math.floor(ty + 0.5)

    -- Grow out of the card rather than out of thin air: anchor the pop on whichever edge of the
    -- box is against the anchor sprite. `ty` was flipped above if the box did not fit below.
    local scale = appear_scale(title)
    local popped = scale ~= 1
    if popped then
        local anchor_x = tx + box_w * 0.5
        local anchor_y = (ty >= draw_y) and ty or (ty + box_h)
        love.graphics.push()
        love.graphics.translate(anchor_x, anchor_y)
        love.graphics.scale(scale, scale)
        love.graphics.translate(-anchor_x, -anchor_y)
    end

    local C = (G and G.C) or {}
    local tooltip_c = C.TOOLTIP or { 0.12, 0.14, 0.2, 1 }
    local shadow_c = (C.BLOCK and C.BLOCK.SHADOW) or { 0, 0, 0, 0.35 }
    local white_c = C.WHITE or { 1, 1, 1, 1 }
    local dark_white = C.DARK_WHITE or { 0.9, 0.9, 0.92, 1 }
    local panel_c = C.PANEL or { 0.2, 0.22, 0.28, 1 }

    if _G.draw_rect_with_shadow then
        draw_rect_with_shadow(tx, ty, box_w, box_h, 4, 0, tooltip_c, shadow_c, 1)
    else
        love.graphics.setColor(tooltip_c[1], tooltip_c[2], tooltip_c[3], tooltip_c[4] or 1)
        love.graphics.rectangle("fill", tx, ty, box_w, box_h, 4, 4)
    end
    love.graphics.setColor(1, 1, 1, 1)
    if _G.draw_rounded_rect then
        draw_rounded_rect(tx, ty, box_w, box_h, 4, 2, "line")
    end

    local header_x = tx + TOOLTIP_OUTER_PAD_X
    local header_y = ty + TOOLTIP_OUTER_PAD_Y
    local body_x = header_x
    local body_y = header_y + header_h_total + TOOLTIP_SECTION_GAP

    love.graphics.setColor(tooltip_c[1], tooltip_c[2], tooltip_c[3], tooltip_c[4] or 1)
    if _G.draw_rounded_rect then
        draw_rounded_rect(header_x, header_y, inner_w, header_h_total, 4, 0, "fill")
        draw_rounded_rect(body_x, body_y, inner_w, body_h_total, 4, 0, "fill")
    end

    local inner_pad = 2
    local inner_header_h = math.max(1, header_h_total - (inner_pad * 2))
    local inner_body_h = math.max(1, body_h_total - (inner_pad * 2))
    love.graphics.setColor(white_c[1], white_c[2], white_c[3], white_c[4] or 1)
    if _G.draw_rect_with_shadow then
        draw_rect_with_shadow(header_x + inner_pad, header_y + inner_pad, inner_w - (inner_pad * 2), inner_header_h, 4, 0, white_c, dark_white, 1)
        draw_rect_with_shadow(body_x + inner_pad, body_y + inner_pad - 1, inner_w - (inner_pad * 2), inner_body_h, 4, 0, white_c, dark_white, 1)
    end

    local header_text_y = header_y + math.floor((header_h_total - line_h) * 0.5 + 0.5)
    local header_text_x = header_x + math.floor((inner_w - header_w) * 0.5 + 0.5)
    love.graphics.setColor(panel_c[1], panel_c[2], panel_c[3], panel_c[4] or 1)
    love.graphics.print(title, header_text_x, header_text_y)

    local text_y = body_y + body_pad_top
    local function draw_segments_centered(segments, line_y0)
        local total_w = 0
        for _, seg in ipairs(segments) do
            total_w = total_w + font:getWidth(seg.text or "")
        end
        local x = body_x + math.floor((inner_w - total_w) * 0.5 + 0.5)
        for _, seg in ipairs(segments) do
            local t = seg.text or ""
            local col = M.tooltip_color_by_key(seg.color_key)
            love.graphics.setColor(col[1], col[2], col[3], col[4])
            love.graphics.print(t, x, line_y0)
            x = x + font:getWidth(t)
        end
    end

    for i, segments in ipairs(resolved_lines) do
        local row_h = body_line_heights[i] or line_h
        if #segments == 1 and segments[1].rarity_badge then
            local seg = segments[1]
            local label = seg.text or ""
            local ri = tonumber(seg.rarity_index) or 1
            local rc = (G and G.C and G.C.RARITY and G.C.RARITY[ri]) or { 0.035, 0.62, 1, 1 }
            local bw = font:getWidth(label) + RARITY_BADGE_PAD_X * 2
            local x0 = body_x + math.floor((inner_w - bw) * 0.5 + 0.5)
            love.graphics.setColor(rc[1], rc[2], rc[3], rc[4] or 1)
            if _G.draw_rounded_rect then
                draw_rounded_rect(x0, text_y, bw, row_h, 4, 0, "fill")
            end
            local text_x = x0 + RARITY_BADGE_PAD_X
            local text_y_row = text_y + math.floor((row_h - line_h) * 0.5 + 0.5)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.print(label, text_x, text_y_row)
        else
            local line_y0 = math.floor(text_y + (row_h - line_h) * 0.5 + 0.5)
            draw_segments_centered(segments, line_y0)
        end
        text_y = text_y + row_h + TOOLTIP_SPACING
    end

    if popped then love.graphics.pop() end

    love.graphics.setFont(prev_font)
    love.graphics.setColor(prev_r, prev_g, prev_b, prev_a)
end

return M
