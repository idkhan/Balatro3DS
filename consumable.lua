---@class Consumable : Moveable
Consumable = Moveable:extend()

local TOOLTIP_PAD_X = 8
local TOOLTIP_HEADER_PAD_Y = 3
local TOOLTIP_BODY_PAD_Y = 10
local TOOLTIP_SPACING = 1
local TOOLTIP_SECTION_GAP = 2
local TOOLTIP_OUTER_PAD_X = 3
local TOOLTIP_OUTER_PAD_Y = 3

local function consumable_resolve_atlas(name)
    if not name or not G or not G.ASSET_ATLAS then return nil end
    if G.ensure_asset_atlas_loaded then
        G:ensure_asset_atlas_loaded(name)
    end
    return G.ASSET_ATLAS[name]
end

local function consumable_compute_quad(atlas, index)
    if not atlas or not atlas.image or index == nil then return nil, 0, 0 end
    local iw, ih = atlas.image:getDimensions()
    local cell_w, cell_h = atlas.px, atlas.py
    if not cell_w or not cell_h or cell_w <= 0 or cell_h <= 0 then
        return nil, 0, 0
    end
    local cols = math.floor(iw / cell_w)
    if cols <= 0 then return nil, 0, 0 end
    local col = index % cols
    local row = math.floor(index / cols)
    local sx = col * cell_w
    local sy = row * cell_h
    local quad = love.graphics.newQuad(sx, sy, cell_w, cell_h, iw, ih)
    return quad, cell_w, cell_h
end

---@param X number
---@param Y number
---@param def table  -- entry from CONSUMABLE_DEFS
function Consumable:init(X, Y, def)
    self.def = def or {}
    self.id = self.def.id
    self.kind = self.def.kind
    self.name = self.def.name or "Consumable"
    self.sell_cost = (self.kind == "spectral") and 2 or 1
    self.atlas_name = self.def.atlas or "Tarot"
    self.index = tonumber(self.def.index) or 0

    local cw, ch = 72, 95
    Moveable.init(self, X or 0, Y or 0, cw, ch)

    self.states.collide.can = false
    self.states.click.can = true
    self.states.drag.can = true
    self.states.visible = true

    self.atlas = consumable_resolve_atlas(self.atlas_name)
    self.quad, self.w, self.h = consumable_compute_quad(self.atlas, self.index)

    if self.w and self.h and self.w > 0 and self.h > 0 then
        self.T.w = self.w
        self.T.h = self.h
        if self.VT then
            self.VT.w = self.w
            self.VT.h = self.h
        end
    end
end

function Consumable:get_collision_rect()
    local t = self.VT or self.T
    local s = t.scale or 1
    local w = t.w or 0
    local h = t.h or 0

    local offx = (self.collision_offset and self.collision_offset.x) or 0
    local offy = (self.collision_offset and self.collision_offset.y) or 0

    local scaled_w = w * s
    local scaled_h = h * s

    local delta_x = (w * s * (1 - s)) / 2
    local delta_y = (h * s * (1 - s)) / 2

    local draw_x = t.x + offx
    local draw_y = t.y + offy

    return {
        x = draw_x + delta_x,
        y = draw_y + delta_y,
        w = scaled_w,
        h = scaled_h,
    }
end

function Consumable:draw()
    if not self.states.visible then return end
    if not (self.atlas and self.atlas.image and self.quad) then return end

    local draw_x = self.VT.x + self.collision_offset.x
    local draw_y = self.VT.y + self.collision_offset.y

    love.graphics.push()

    local cx = draw_x + (self.VT.w * self.VT.scale) / 2
    local cy = draw_y + (self.VT.h * self.VT.scale) / 2
    love.graphics.translate(cx, cy)
    love.graphics.rotate(self.VT.r)
    love.graphics.scale(self.VT.scale, self.VT.scale)
    love.graphics.translate(-cx, -cy)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.atlas.image, self.quad, draw_x, draw_y, 0, 1, 1)

    love.graphics.pop()
end

function Consumable:draw_tooltip_overlay()
    if not self.states.visible or not self:tooltip_is_active() then return end
    local draw_x = self.VT.x + self.collision_offset.x
    local draw_y = self.VT.y + self.collision_offset.y
    self:draw_tooltip(draw_x, draw_y)
end

--- Planet: hand level text. Tarot: optional `def.tooltip` string or list of strings.
---@return string[]
function Consumable:get_tooltip_body_lines()
    local def = self.def or {}
    if def.kind == "planet" and type(def.hand) == "string" and def.hand ~= "" then
        return { string.format("Increases the value of %s", def.hand) }
    end
    if def.kind == "tarot" then
        local tip = def.tooltip
        if type(tip) == "table" then
            local out = {}
            for _, l in ipairs(tip) do
                if type(l) == "string" and l ~= "" then out[#out + 1] = l end
            end
            if #out > 0 then return out end
        elseif type(tip) == "string" and tip ~= "" then
            local out = {}
            for line in tip:gmatch("[^\r\n]+") do
                if line ~= "" then out[#out + 1] = line end
            end
            if #out > 0 then return out end
        end
    end
    return {}
end

function Consumable:tooltip_is_active()
    if not G then return false end
    if self.shop_offer_slot and G.STATE == G.STATES.SHOP and G.active_tooltip_joker == self then
        return true
    end
    if self._booster_choice_index and G.STATE == G.STATES.OPEN_BOOSTER and G.booster_session then
        return tonumber(G.booster_session.active_choice_index) == self._booster_choice_index
    end
    if G.jokers_on_bottom == true then return false end
    if self.states.drag.is then return true end
    local idx = G.active_tooltip_consumable_index
    if idx and G.consumable_nodes and G.consumable_nodes[idx] == self then
        return true
    end
    return false
end

function Consumable:draw_tooltip(draw_x, draw_y)
    local lines = self:get_tooltip_body_lines()
    if #lines == 0 then return end

    local def = self.def or {}
    local title = self.name or def.name or "Consumable"
    local font = G.FONTS.PIXEL.SMALL or love.graphics.getFont()
    local prev_font = love.graphics.getFont()
    local prev_r, prev_g, prev_b, prev_a = love.graphics.getColor()
    love.graphics.setFont(font)

    local header_w = font:getWidth(title)
    local body_max_w = 0
    for _, line in ipairs(lines) do
        local w = font:getWidth(line)
        if w > body_max_w then body_max_w = w end
    end
    local line_h = font:getHeight()
    local header_w_total = header_w + (TOOLTIP_PAD_X * 2)
    local header_h_total = line_h + (TOOLTIP_HEADER_PAD_Y * 2)
    local body_w_total = body_max_w + (TOOLTIP_PAD_X * 2)
    local body_h_total = (#lines * line_h) + ((#lines - 1) * TOOLTIP_SPACING) + (TOOLTIP_BODY_PAD_Y * 2)
    local inner_w = math.max(header_w_total, body_w_total)
    local inner_h = header_h_total + TOOLTIP_SECTION_GAP + body_h_total
    local box_w = inner_w + (TOOLTIP_OUTER_PAD_X * 2)
    local box_h = inner_h + (TOOLTIP_OUTER_PAD_Y * 2)

    local card_w = self.VT.w * self.VT.scale
    local card_h = self.VT.h * self.VT.scale
    local tx = draw_x + (card_w - box_w) * 0.5
    -- Row sits near the top of the screen; prefer below the sprite, flip above if needed.
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

    if not _G.draw_rect_with_shadow or not _G.draw_rounded_rect then
        love.graphics.setFont(prev_font)
        love.graphics.setColor(prev_r, prev_g, prev_b, prev_a)
        return
    end

    draw_rect_with_shadow(tx, ty, box_w, box_h, 4, 0, G.C.TOOLTIP, G.C.BLOCK.SHADOW, 1)
    love.graphics.setColor(1, 1, 1, 1)
    draw_rounded_rect(tx, ty, box_w, box_h, 4, 2, "line")

    local header_x = tx + TOOLTIP_OUTER_PAD_X
    local header_y = ty + TOOLTIP_OUTER_PAD_Y
    local body_x = header_x
    local body_y = header_y + header_h_total + TOOLTIP_SECTION_GAP

    love.graphics.setColor(G.C.TOOLTIP)
    draw_rounded_rect(header_x, header_y, inner_w, header_h_total, 4, 0, "fill")
    draw_rounded_rect(body_x, body_y, inner_w, body_h_total, 4, 0, "fill")

    local inner_pad = 2
    local inner_header_h = math.max(1, header_h_total - (inner_pad * 2))
    local inner_body_h = math.max(1, body_h_total - (inner_pad * 2))
    love.graphics.setColor(G.C.WHITE)
    draw_rect_with_shadow(header_x + inner_pad, header_y + inner_pad, inner_w - (inner_pad * 2), inner_header_h, 4, 0, G.C.WHITE, G.C.DARK_WHITE, 1)
    draw_rect_with_shadow(body_x + inner_pad, body_y + inner_pad - 1, inner_w - (inner_pad * 2), inner_body_h, 4, 0, G.C.WHITE, G.C.DARK_WHITE, 1)

    local header_text_y = header_y + math.floor((header_h_total - line_h) * 0.5 + 0.5)
    local header_text_x = header_x + math.floor((inner_w - header_w) * 0.5 + 0.5)
    love.graphics.setColor(G.C.PANEL)
    love.graphics.print(title, header_text_x, header_text_y)

    local text_y = body_y + TOOLTIP_BODY_PAD_Y
    local gray = { 0.22, 0.24, 0.26, 1 }
    local emph = (G.C and G.C.MULT) or { 0.9, 0.45, 0.45, 1 }

    for _, line in ipairs(lines) do
        local line_y = math.floor(text_y + 0.5)
        if def.kind == "planet" and type(def.hand) == "string" and def.hand ~= "" then
            local prefix = "Increases the value of "
            local hand = def.hand
            local total_w = font:getWidth(prefix) + font:getWidth(hand)
            local x = body_x + math.floor((inner_w - total_w) * 0.5 + 0.5)
            love.graphics.setColor(gray[1], gray[2], gray[3], gray[4])
            love.graphics.print(prefix, x, line_y)
            love.graphics.setColor(emph[1], emph[2], emph[3], emph[4])
            love.graphics.print(hand, x + font:getWidth(prefix), line_y)
        else
            local line_w = font:getWidth(line)
            local line_x = body_x + math.floor((inner_w - line_w) * 0.5 + 0.5)
            love.graphics.setColor(gray[1], gray[2], gray[3], gray[4])
            love.graphics.print(line, line_x, line_y)
        end
        text_y = text_y + line_h + TOOLTIP_SPACING
    end

    love.graphics.setFont(prev_font)
    love.graphics.setColor(prev_r, prev_g, prev_b, prev_a)
end

