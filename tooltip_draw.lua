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
    "flush",
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

local function paint_phrase_ranges(text, paints, priorities, phrase, color_key, prio)
    local hay = string.lower(text)
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

--- Split *Balatro-style* description text into colored segments (asterisks stripped).
function M.build_segments_from_text(raw_text)
    local text = tostring(raw_text or "")
    text = text:gsub("%*", "")
    local len = #text
    if len <= 0 then
        return { { text = "", color_key = nil } }
    end

    local paints = {}
    local priorities = {}

    paint_phrase_ranges(text, paints, priorities, "tarot", "PURPLE", 50)
    paint_phrase_ranges(text, paints, priorities, "planet", "CHIPS", 50)
    paint_phrase_ranges(text, paints, priorities, "playing", "IMPORTANT", 50)
    paint_phrase_ranges(text, paints, priorities, "spectral", "PURPLE", 49)
    paint_phrase_ranges(text, paints, priorities, "joker", "MULT", 50)
    paint_phrase_ranges(text, paints, priorities, "jokers", "MULT", 50)
    paint_pattern_ranges(text, paints, priorities, "%d+", "IMPORTANT", 46)
    paint_phrase_ranges(text, paints, priorities, "hand size", "IMPORTANT", 55)
    paint_phrase_ranges(text, paints, priorities, "discard", "RED", 56)
    paint_phrase_ranges(text, paints, priorities, "discarded", "RED", 56)
    paint_pattern_ranges(text, paints, priorities, "%$%d+", "MONEY", 57)
    for _, hand_name in ipairs(HAND_NAME_PHRASES) do
        paint_phrase_ranges(text, paints, priorities, hand_name, "IMPORTANT", 58)
    end

    paint_pattern_ranges(text, paints, priorities, "%d+/%d+:%s*", "CHANCE", 70)
    paint_pattern_ranges(text, paints, priorities, "%d+%s+[Ii][Nn]%s+%d+", "CHANCE", 70)
    paint_phrase_ranges(text, paints, priorities, "chance", "CHANCE", 70)
    paint_phrase_ranges(text, paints, priorities, "probabilities", "CHANCE", 70)

    paint_pattern_ranges(text, paints, priorities, "[Xx]%d+[%d%.]*%s*[Mm]ult", "MULT", 80)
    paint_pattern_ranges(text, paints, priorities, "[%+%-]?%d+[%d%.]*%s*[Mm]ult", "MULT", 80)
    paint_phrase_ranges(text, paints, priorities, "[Mm]ult", "MULT", 78)
    paint_pattern_ranges(text, paints, priorities, "[%+%-]?%d+[%d%.]*%s*[Cc]hips", "CHIPS", 80)
    paint_phrase_ranges(text, paints, priorities, "[Cc]hips", "CHIPS", 78)

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
        return { { text = text, color_key = nil } }
    end
    return segments
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
    local sw = 320
    if love.graphics.getWidth then
        sw = love.graphics.getWidth("bottom")
        if not sw or sw <= 0 then sw = love.graphics.getWidth() end
        if not sw or sw <= 0 then sw = 320 end
    end
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

    love.graphics.setFont(prev_font)
    love.graphics.setColor(prev_r, prev_g, prev_b, prev_a)
end

return M
