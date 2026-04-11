---@class Card : Moveable
Card = Moveable:extend()

local SHAKE_MAGNITUDE = 6

--- Back / face sprite cell indices in the `centers` atlas (same atlas for both). Tune to match your sheet layout.
local ENHANCEMENT_CENTER_INDICES = {
    bonus = { back = 0, face = 8 },
    mult = { back = 0, face = 9 },
    wild = { back = 0, face = 10 },
    glass = { back = 6, face = 12 },
    steel = { back = 13, face = 13 },
    stone = { back = 5, face = 5 },
    gold = { back = 6, face = 6 },
    lucky = { back = 0, face = 11 },
}

--- Seal overlay: each seal has its **own** `centers` atlas cell index (not derived from rank/suit).
--- Same **render path** as rank (`compute_quad` + `draw_layer`); indices are unrelated to `rank_index`.
--- Override with `G.CARD_SEAL_INDICES` or `G.CARD_SEAL_CENTER_INDICES`.
local SEAL_ATLAS_INDICES = {
    gold = 2,
    red = 33,
    blue = 34,
    purple = 32,
}

---@param self Card
local function apply_enhancement_center_indices(self)
    local map = ENHANCEMENT_CENTER_INDICES
    if G and type(G.CARD_ENHANCEMENT_CENTER_INDICES) == "table" then
        map = G.CARD_ENHANCEMENT_CENTER_INDICES
    end
    local enh = self.enhancement
    if enh and map[enh] then
        local m = map[enh]
        self.back_index = m.back
        self.face_index = m.face
    else
        self.back_index = self.params.back_index or 0
        self.face_index = self.params.face_index or (self.back_index + 1)
    end
end

---@param X number
---@param Y number
---@param W number|nil
---@param H number|nil
---@param card table|nil   -- logical card data (rank/suit/etc), optional for now
---@param center any|nil   -- placeholder for future use
---@param params table|nil -- visual params (atlas names/indices/state)

function Card:init(X, Y, W, H, card, center, params)
    self.params = (type(params) == 'table') and params or {}
    self.card_data = card or {}
    self.center = center

    -- default to global card size if not provided
    local cw = W or (G and G.CARD_W) or 71
    local ch = H or (G and G.CARD_H) or 95

    Moveable.init(self, X or 0, Y or 0, cw, ch)

    self.states.collide.can = false

    self.enhancement = self.params.enhancement or (self.card_data and self.card_data.enhancement) or nil
    self.seal = self.params.seal or (self.card_data and self.card_data.seal) or nil

    -- register in global instance table if available
    if G and G.I and G.I.CARD then
        table.insert(G.I.CARD, self)
    end

    -- which atlases to use for each visual layer
    -- back & front: both from 'centers' atlas
    --   back_index  = N
    --   face_index  = N + 1  (your rule: face is back + 1)
    self.back_atlas_name = self.params.back_atlas_name or "centers"
    self.face_atlas_name = self.params.face_atlas_name or self.back_atlas_name

    self.rank_atlas_name = self.params.rank_atlas_name or "cards_2"
    -- Seals: separate atlas + per-seal indices (`SEAL_ATLAS_INDICES`), not rank/suit math.
    self.seal_atlas_name = self.params.seal_atlas_name or "centers"

    -- indices into those atlases (0-based cell index)
    -- derive rank/suit index for the overlay image when provided
    local rank = self.card_data.rank or self.params.rank
    local suit = self.card_data.suit or self.params.suit

    -- suit offset: Hearts=0, Clubs=13, Diamonds=26, Spades=39
    local function suit_offset(s)
        if not s then return 0 end
        if type(s) == "string" then
            s = s:lower()
            if s == "hearts" then return 0 end
            if s == "clubs"  then return 13 end
            if s == "diamonds" then return 26 end
            if s == "spades" then return 39 end
        elseif type(s) == "number" then
            -- optional numeric mapping 1..4 = Hearts, Clubs, Diamonds, Spades
            if s == 1 then return 0 end
            if s == 2 then return 13 end
            if s == 3 then return 26 end
            if s == 4 then return 39 end
        end
        return 0
    end

    -- by your rule for card faces in cards_1:
    --   rank 2 -> first texture (index 0), so base index = (rank - 2)
    --   then add suit offset (Hearts=0, Clubs=13, Diamonds=26, Spades=39)
    local computed_rank_index
    if rank then
        computed_rank_index = math.max(0, (rank - 2) + suit_offset(suit))
    end

    -- back/face indices: set in refresh_quads from enhancement or params
    self.back_index = 0
    self.face_index = 1

    -- rank atlas index comes from rank+suit mapping
    self.rank_index = self.params.rank_index or computed_rank_index or 0
    self.seal_index = self.params.seal_index -- seal is optional

    -- card orientation: false = back, true = front
    self.face_up = self.params.face_up or false

    -- resolve atlases and quads
    self:refresh_quads()
end

function Card:resolve_atlas(name)
    if not name or not G or not G.ASSET_ATLAS then return nil end
    if G.ensure_asset_atlas_loaded then
        G:ensure_asset_atlas_loaded(name)
    end
    return G.ASSET_ATLAS[name]
end

function Card:compute_quad(atlas, index)
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

--- Sets `seal_index` from `self.seal` only (unique index per seal type in seal atlas).
local function apply_seal_indices(self)
    local map = SEAL_ATLAS_INDICES
    if G and type(G.CARD_SEAL_INDICES) == "table" then
        map = G.CARD_SEAL_INDICES
    elseif G and type(G.CARD_SEAL_CENTER_INDICES) == "table" then
        map = G.CARD_SEAL_CENTER_INDICES
    end
    local s = self.seal
    if s == "none" or s == "" then
        self.seal_index = nil
    elseif s and type(map) == "table" and map[s] ~= nil then
        self.seal_index = map[s]
    elseif self.params and self.params.seal_index ~= nil then
        self.seal_index = self.params.seal_index
    else
        self.seal_index = nil
    end
end

--- Recompute `rank_index` and enhancement visuals from `card_data` / instance fields (after rank/suit/editing).
function Card:sync_visual_from_card_data()
    local data = self.card_data or {}
    local rank = data.rank or (self.params and self.params.rank)
    local suit = data.suit or (self.params and self.params.suit)

    local function suit_offset(s)
        if not s then return 0 end
        if type(s) == "string" then
            s = s:lower()
            if s == "hearts" then return 0 end
            if s == "clubs" then return 13 end
            if s == "diamonds" then return 26 end
            if s == "spades" then return 39 end
        elseif type(s) == "number" then
            if s == 1 then return 0 end
            if s == 2 then return 13 end
            if s == 3 then return 26 end
            if s == 4 then return 39 end
        end
        return 0
    end

    if rank then
        self.rank_index = math.max(0, (rank - 2) + suit_offset(suit))
    end

    local enh = data.enhancement
    if enh == "none" or enh == "" then enh = nil end
    self.enhancement = enh

    local seal = data.seal
    if seal == "none" or seal == "" then seal = nil end
    self.seal = seal

    self:refresh_quads()
end

function Card:refresh_quads()
    apply_enhancement_center_indices(self)
    apply_seal_indices(self)

    -- resolve atlases
    self.back_atlas = self:resolve_atlas(self.back_atlas_name)
    self.face_atlas = self:resolve_atlas(self.face_atlas_name)
    self.rank_atlas = self:resolve_atlas(self.rank_atlas_name)
    self.seal_atlas = self:resolve_atlas(self.seal_atlas_name)

    self.back_quad, self.back_w, self.back_h = self:compute_quad(self.back_atlas, self.back_index)
    self.face_quad, self.face_w, self.face_h = self:compute_quad(self.face_atlas, self.face_index)
    self.rank_quad, self.rank_w, self.rank_h = self:compute_quad(self.rank_atlas, self.rank_index)
    
    -- Stone cards don't display rank or suit.
    if self.enhancement == "stone" then
        self.rank_quad = nil
        self.rank_w, self.rank_h = 0, 0
    end

    if self.seal_index ~= nil then
        self.seal_quad, self.seal_w, self.seal_h = self:compute_quad(self.seal_atlas, self.seal_index)
    else
        self.seal_quad, self.seal_w, self.seal_h = nil, 0, 0
    end

    -- ensure the card's transform matches the visual sprite size so it isn't tiny
    local base_w = self.back_w or self.face_w
    local base_h = self.back_h or self.face_h
    if base_w and base_w > 0 and base_h and base_h > 0 then
        self.T.w = base_w
        self.T.h = base_h
        if self.VT then
            self.VT.w = base_w
            self.VT.h = base_h
        end
    end
end

function Card:set_face_up(face_up)
    self.face_up = not not face_up
end

--- Set or clear enhancement (updates `card_data.enhancement` and back/face sprites in the centers atlas).
---@param name string|nil
function Card:set_enhancement(name)
    self.enhancement = name
    if self.card_data then
        self.card_data.enhancement = name
    end
    self:refresh_quads()
end

---@param name string|nil
function Card:set_seal(name)
    self.seal = name
    if self.card_data then
        self.card_data.seal = name
    end
    self:refresh_quads()
end

-- helper to draw one layer (atlas+quad) at given position (ox, oy) or default VT position
function Card:draw_layer(atlas, quad, cell_w, cell_h, ox, oy)
    if not atlas or not atlas.image or not quad then return end

    local draw_x = ox or (self.VT.x + self.collision_offset.x)
    local draw_y = oy or (self.VT.y + self.collision_offset.y)

    -- draw at 1:1 pixel size based on atlas cell, since we already synced VT.w/h to that in refresh_quads
    local scale_x = 1
    local scale_y = 1

    love.graphics.draw(
        atlas.image,
        quad,
        draw_x,
        draw_y,
        0,
        scale_x,
        scale_y
    )
end

local SELECTED_LIFT = 20
local TOOLTIP_PAD_X = 8
local TOOLTIP_HEADER_PAD_Y = 3
local TOOLTIP_BODY_PAD_Y = 10
local TOOLTIP_SPACING = 1
local TOOLTIP_SECTION_GAP = 2
local TOOLTIP_OUTER_PAD_X = 3
local TOOLTIP_OUTER_PAD_Y = 3

local function rank_to_label(rank)
    if rank == 14 then return "Ace" end
    if rank == 13 then return "King" end
    if rank == 12 then return "Queen" end
    if rank == 11 then return "Jack" end
    if type(rank) == "number" then return tostring(rank) end
    return "?"
end

local function card_base_score(rank)
    if rank == 14 then return 11 end
    if rank == 11 or rank == 12 or rank == 13 then return 10 end
    if type(rank) == "number" then return rank end
    return 0
end

local function get_card_modifier_bonus(card_data)
    if type(card_data) ~= "table" then return 0, 0 end

    if G and G.hand and G.hand.get_modifier_bonus then
        return G.hand:get_modifier_bonus(card_data)
    end

    local chip_bonus = 0
    local mult_bonus = 0
    chip_bonus = chip_bonus + (tonumber(card_data.chip_bonus) or 0)
    chip_bonus = chip_bonus + (tonumber(card_data.chips_bonus) or 0)
    mult_bonus = mult_bonus + (tonumber(card_data.mult_bonus) or 0)
    mult_bonus = mult_bonus + (tonumber(card_data.multiplier_bonus) or 0)
    return chip_bonus, mult_bonus
end

---@param enh string|nil
---@return string[]
local function enhancement_tooltip_lines(enh)
    if not enh or enh == "none" then return {} end
    if enh == "bonus" then return { "+30 chips" }
    elseif enh == "mult" then return { "+4 mult" }
    elseif enh == "glass" then return { "×2 mult", "1/4: breaks after score" }
    elseif enh == "steel" then return { "×1.5 mult while held" }
    elseif enh == "stone" then return { "+50 chips" }
    elseif enh == "gold" then return { "+$3 while held" }
    elseif enh == "lucky" then return { "1/5: +20 mult", "1/15: +$20" }
    elseif enh == "wild" then return { "Wild card" }
    end
    return {}
end

---@param seal string|nil
---@return string[]
local function seal_tooltip_lines(seal)
    if not seal then return {} end
    if seal == "gold" then return { "+$3 when scored" }
    elseif seal == "red" then return { "Retrigger" }
    elseif seal == "blue" then return { "Planet if held" }
    elseif seal == "purple" then return { "Purple seal" }
    end
    return {}
end

function Card:get_collision_rect()
    local r = Node.get_collision_rect(self)
    if self.selected and not self.scoring_center then
        r.y = r.y - SELECTED_LIFT
    end
    return r
end

function Card:draw_boundingrect()
    if not G or not G.DEBUG then return end
    local r = self:get_collision_rect()
    local prev_r, prev_g, prev_b, prev_a = love.graphics.getColor()
    if self.states.collide.is then
        love.graphics.setColor(1, 0, 0, 1)
    else
        love.graphics.setColor(0, 1, 0, 1)
    end
    love.graphics.push()
    local cx = r.x + r.w / 2
    local cy = r.y + r.h / 2
    love.graphics.translate(cx, cy)
    love.graphics.rotate(self.VT.r)
    love.graphics.translate(-cx, -cy)
    love.graphics.rectangle("line", r.x, r.y, r.w, r.h)
    love.graphics.pop()
    love.graphics.setColor(prev_r, prev_g, prev_b, prev_a)
end

function Card:draw_tooltip(draw_x, draw_y)
    local data = self.card_data or {}
    local rank = data.rank
    local suit = data.suit
    local base_score = card_base_score(rank)
    local chip_bonus, mult_bonus = get_card_modifier_bonus(data)

    local header_only -- when set, single centered title (no rank/suit)
    local header_prefix, suit_name
    if self.enhancement == "stone" then
        header_only = "Stone Card"
    else
        local rank_name = rank_to_label(rank)
        suit_name = tostring(suit or "?")
        header_prefix = string.format("%s of ", rank_name)
    end

    local lines = {}
    if self.enhancement == "stone" then
        lines = { "+50 chips" }
        for _, l in ipairs(seal_tooltip_lines(self.seal)) do
            table.insert(lines, l)
        end
    else
        table.insert(lines, string.format("+%d chips", base_score))
        if chip_bonus ~= 0 then
            table.insert(lines, string.format("%+d chips", chip_bonus))
        end
        if mult_bonus ~= 0 then
            table.insert(lines, string.format("%+d mult", mult_bonus))
        end
        local enh = self.enhancement
        if enh == "none" then enh = nil end
        for _, l in ipairs(enhancement_tooltip_lines(enh)) do
            table.insert(lines, l)
        end
        for _, l in ipairs(seal_tooltip_lines(self.seal)) do
            table.insert(lines, l)
        end
    end

    local font = G.FONTS.PIXEL.SMALL or love.graphics.getFont()
    local prev_font = love.graphics.getFont()
    local prev_r, prev_g, prev_b, prev_a = love.graphics.getColor()
    love.graphics.setFont(font)

    local header_w
    if header_only then
        header_w = font:getWidth(header_only)
    else
        header_w = font:getWidth(header_prefix) + font:getWidth(suit_name)
    end
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
    local tx = draw_x + (card_w - box_w) * 0.5
    local ty = draw_y - box_h - 3
    local margin = 2
    local sw = 320
    if love.graphics.getWidth then
        sw = love.graphics.getWidth("bottom")
        if not sw or sw <= 0 then sw = love.graphics.getWidth() end
        if not sw or sw <= 0 then sw = 320 end
    end
    tx = math.max(margin, math.min(tx, sw - box_w - margin))
    if ty < 2 then ty = draw_y + 2 end
    tx = math.floor(tx + 0.5)
    ty = math.floor(ty + 0.5)

    -- Outer container (single rounded rectangle around both sections)
    draw_rect_with_shadow(tx, ty, box_w, box_h, 4, 0, G.C.TOOLTIP, G.C.BLOCK.SHADOW, 1)
        
    love.graphics.setColor(1, 1, 1, 1)
    draw_rounded_rect(tx, ty, box_w, box_h, 4, 2, "line")
    
    local header_x = tx + TOOLTIP_OUTER_PAD_X
    local header_y = ty + TOOLTIP_OUTER_PAD_Y
    local body_x = header_x
    local body_y = header_y + header_h_total + TOOLTIP_SECTION_GAP

    -- Outer rounded panels
    love.graphics.setColor(G.C.TOOLTIP)
    draw_rounded_rect(header_x, header_y, inner_w, header_h_total, 4, 0, "fill")
    draw_rounded_rect(body_x, body_y, inner_w, body_h_total, 4, 0, "fill")    

    -- Inner light fill
    local inner_pad = 2
    local inner_header_h = math.max(1, header_h_total - (inner_pad * 2))
    local inner_body_h = math.max(1, body_h_total - (inner_pad * 2))
    love.graphics.setColor(G.C.WHITE)
    draw_rect_with_shadow(header_x + inner_pad, header_y + inner_pad, inner_w - (inner_pad * 2), inner_header_h, 4, 0, G.C.WHITE, G.C.DARK_WHITE, 1)
    draw_rect_with_shadow(body_x + inner_pad, body_y + inner_pad -1, inner_w - (inner_pad * 2), inner_body_h, 4, 0, G.C.WHITE, G.C.DARK_WHITE, 1)
 
    -- Header: rank + suit, or anonymous Stone title
    local header_text_y = header_y + math.floor((header_h_total - line_h) * 0.5 + 0.5)
    if header_only then
        local header_total_w = font:getWidth(header_only)
        local header_text_x = header_x + math.floor((inner_w - header_total_w) * 0.5 + 0.5)
        love.graphics.setColor(G.C.PANEL)
        love.graphics.print(header_only, header_text_x, header_text_y)
    else
        local header_total_w = font:getWidth(header_prefix) + font:getWidth(suit_name)
        local header_text_x = header_x + math.floor((inner_w - header_total_w) * 0.5 + 0.5)
        love.graphics.setColor(G.C.PANEL)
        love.graphics.print(header_prefix, header_text_x, header_text_y)
        local suit_col = (G and G.C and G.C.SUITS and G.C.SUITS[suit_name]) or (G and G.C and G.C.PANEL) or {1, 1, 1, 1}
        love.graphics.setColor(suit_col)
        love.graphics.print(suit_name, header_text_x + font:getWidth(header_prefix), header_text_y)
    end

    local text_y = body_y + TOOLTIP_BODY_PAD_Y
    local gray = { 0.22, 0.24, 0.26, 1 }
    local green = (G.C and G.C.GREEN) or { 0.2, 0.75, 0.55, 1 }

    --- Split optional `1/5: ` style odds prefix (colored green).
    local function strip_prob_prefix(s)
        local p = s:match("^(%d+/%d+:%s*)")
        if p then
            return p, s:sub(#p + 1)
        end
        return nil, s
    end

    local function draw_segments_centered(segments, line_y)
        local total_w = 0
        for _, seg in ipairs(segments) do
            total_w = total_w + font:getWidth(seg[1])
        end
        local x = body_x + math.floor((inner_w - total_w) * 0.5 + 0.5)
        for _, seg in ipairs(segments) do
            local t, col = seg[1], seg[2]
            love.graphics.setColor(col[1], col[2], col[3], col[4])
            love.graphics.print(t, x, line_y)
            x = x + font:getWidth(t)
        end
    end

    for _, line in ipairs(lines) do
        local line_y = math.floor(text_y + 0.5)
        local prob, rest = strip_prob_prefix(line)

        local num_chips, suf_chips = rest:match("^(.-)( chips)$")
        local num_mult, suf_mult = rest:match("^(.-)( mult)$")

        if num_chips and suf_chips then
            local segs = {}
            if prob then
                table.insert(segs, { prob, green })
            end
            table.insert(segs, { num_chips, G.C.CHIPS })
            table.insert(segs, { suf_chips, G.C.CHIPS })
            draw_segments_centered(segs, line_y)
        elseif num_mult and suf_mult then
            local segs = {}
            if prob then
                table.insert(segs, { prob, green })
            end
            table.insert(segs, { num_mult, G.C.MULT })
            table.insert(segs, { suf_mult, G.C.MULT })
            draw_segments_centered(segs, line_y)
        else
            local left, mid, right = rest:match("^(.-)%s(mult)(.*)$")
            if left and mid and right ~= nil then
                local segs = {}
                if prob then
                    table.insert(segs, { prob, green })
                end
                table.insert(segs, { left .. " ", G.C.MULT })
                table.insert(segs, { mid, G.C.MULT })
                table.insert(segs, { right, gray })
                draw_segments_centered(segs, line_y)
            elseif prob then
                draw_segments_centered({ { prob, green }, { rest, gray } }, line_y)
            else
                local line_w = font:getWidth(line)
                local line_x = body_x + math.floor((inner_w - line_w) * 0.5 + 0.5)
                love.graphics.setColor(gray[1], gray[2], gray[3], gray[4])
                love.graphics.print(line, line_x, line_y)
            end
        end
        text_y = text_y + line_h + TOOLTIP_SPACING
    end

    love.graphics.setFont(prev_font)
    love.graphics.setColor(prev_r, prev_g, prev_b, prev_a)
end

local SHAKE_MAX_DURATION = 0.22

function Card:update(dt)
    Moveable.update(self, dt)
    if self.scoring_shake_timer and self.scoring_shake_timer > 0 then
        self.scoring_shake_timer = self.scoring_shake_timer - dt
        if self.scoring_shake_timer < 0 then self.scoring_shake_timer = 0 end
        if self.scoring_shake_timer <= 0 then self.scoring_shake_t0 = nil end
    end
end

--- World draw position for sprite and tooltip (selected lift + scoring shake).
function Card:get_layout_draw_xy()
    local draw_x = self.VT.x + self.collision_offset.x
    local draw_y = self.VT.y + self.collision_offset.y
    if self.selected and not self.scoring_center then draw_y = draw_y - SELECTED_LIFT end

    if self.scoring_shake_timer and self.scoring_shake_timer > 0 then
        local mag = SHAKE_MAGNITUDE * (self.scoring_shake_timer / SHAKE_MAX_DURATION)
        local t = love.timer.getTime()
        if self.scoring_shake_t0 then
            t = t - self.scoring_shake_t0
        end
        draw_x = draw_x + math.sin(t * 85) * mag
        draw_y = draw_y + math.cos(t * 73) * mag * 0.65
    end
    return draw_x, draw_y
end

function Card:should_draw_tooltip()
    if not self.face_up then return false end
    return self.states.drag.is or (G and G.active_tooltip_card == self)
end

function Card:draw_tooltip_overlay()
    if not self.states.visible or not self:should_draw_tooltip() then return end
    local draw_x, draw_y = self:get_layout_draw_xy()
    self:draw_tooltip(draw_x, draw_y)
end

function Card:draw()
    if not self.states.visible then return end

    local prev_r, prev_g, prev_b, prev_a = love.graphics.getColor()
    love.graphics.setColor(1, 1, 1, 1)

    local draw_x, draw_y = self:get_layout_draw_xy()

    love.graphics.push()

    local cx = draw_x + (self.VT.w * self.VT.scale) / 2
    local cy = draw_y + (self.VT.h * self.VT.scale) / 2

    love.graphics.translate(cx, cy)
    love.graphics.rotate(self.VT.r)
    love.graphics.scale(self.VT.scale, self.VT.scale)
    love.graphics.translate(-cx, -cy)

    -- base layer: back or face, depending on orientation
    if self.face_up then
        if self.face_quad then
            self:draw_layer(self.face_atlas, self.face_quad, self.face_w, self.face_h, draw_x, draw_y)
        elseif self.back_quad then
            self:draw_layer(self.back_atlas, self.back_quad, self.back_w, self.back_h, draw_x, draw_y)
        end
    else
        if self.back_quad then
            self:draw_layer(self.back_atlas, self.back_quad, self.back_w, self.back_h, draw_x, draw_y)
        end
    end

    -- middle layer: rank + suit icon (only when face-up)
    if self.face_up and self.rank_quad then
        self:draw_layer(self.rank_atlas, self.rank_quad, self.rank_w, self.rank_h, draw_x, draw_y)
    end

    -- top: seal overlay (`draw_layer` like rank; separate atlas + per-seal index)
    if self.face_up and self.seal_quad then
        self:draw_layer(self.seal_atlas, self.seal_quad, self.seal_w, self.seal_h, draw_x, draw_y)
    end

    love.graphics.pop()

    love.graphics.setColor(prev_r, prev_g, prev_b, prev_a)

    -- debug bounding box
    self:draw_boundingrect()

    -- draw children, if any
    for _, v in pairs(self.children or {}) do
        v:draw()
    end
end

--- How many times this card runs the played-card trigger (base 1 + `card_data.retrigger_play` + `G:sum_retrigger_extras`).
--- Red Seal, Hanging Chad, Hack, Sock and Buskin, etc. are summed in `Game:sum_retrigger_extras`.
---@param seq table|nil play sequence (`cards`, Photograph fields for Sock/Buskin)
function Card:play_trigger_total(seq)
    local cd = self.card_data or {}
    local extra = math.max(0, tonumber(cd.retrigger_play) or 0)
    local ctx = {
        held = false,
        card_node = self,
        retrigger_card = self,
        played_cards = type(seq) == "table" and seq.cards or nil,
        photograph_first_face_node = type(seq) == "table" and seq.photograph_first_face_node or nil,
        photograph_pareidolia = type(seq) == "table" and seq.photograph_pareidolia or false,
    }
    local R = 0
    if G and G.sum_retrigger_extras then
        R = tonumber(G:sum_retrigger_extras(false, ctx)) or 0
    end
    return math.max(1, 1 + extra + R)
end

--- How many times this card runs the in-hand trigger (Mime, Red Seal, `card_data.retrigger_held` via `G:sum_retrigger_extras`).
---@param seq table|nil play sequence for context (`cards`, Photograph / Pareidolia flags)
function Card:held_trigger_total(seq)
    local cd = self.card_data or {}
    local extra = math.max(0, tonumber(cd.retrigger_held) or 0)
    local ctx = {
        held = true,
        card_node = self,
        retrigger_card = self,
        played_cards = type(seq) == "table" and seq.cards or nil,
        photograph_first_face_node = type(seq) == "table" and seq.photograph_first_face_node or nil,
        photograph_pareidolia = type(seq) == "table" and seq.photograph_pareidolia or false,
    }
    local R = 0
    if G and G.sum_retrigger_extras then
        R = tonumber(G:sum_retrigger_extras(true, ctx)) or 0
    end
    return math.max(1, 1 + extra + R)
end

function Card:matches_trigger(event_name)
    if event_name == "held_in_hand" then    
        if self.enhancement == "gold" or self.enhancement == "steel" or self.seal == "blue" then
            return true    
        else
            return false
        end
    elseif event_name == "card_played" then
        if self.enhancement == "bonus" or self.enhancement == "mult" or  self.enhancement == "glass" or self.enhancement == "lucky" or self.enhancement == "stone" or self.seal == "gold" or self.seal == "red" then
            return true
        else
            return false
        end
    end
    
    return false
end

--- Dispatch a hand/scoring event to this card (e.g. `"card_played"` → `do_enhancement` / `do_seal` when it matches).
--- Shakes the card when an enhancement or seal actually triggers (same timing as joker scoring shake).
---@param event_name string
---@param ctx table|nil
function Card:emit_hand_event(event_name, ctx)
    if type(ctx) ~= "table" then ctx = {} end
    if not (self.matches_trigger and self:matches_trigger(event_name)) then
        return
    end
    if self.do_enhancement then
        self:do_enhancement(ctx)
    end
    if self.seal and self.do_seal then
        self:do_seal(ctx)
    end
    self.scoring_shake_timer = SHAKE_MAX_DURATION
    self.scoring_shake_t0 = love.timer.getTime()
end

function Card:do_enhancement(ctx)
    if type(ctx) ~= "table" then return end
    local chips = tonumber(ctx.chips) or 0
    local mult = tonumber(ctx.mult) or 1
    ctx.chips = chips
    ctx.mult = mult

    if self.enhancement == "bonus" then
        --+30 chips
        ctx.chips = chips + 30
        Sfx.play_chips()
    elseif self.enhancement == "mult" then
        --+4 mult
        ctx.mult = mult + 4
    elseif self.enhancement == "glass" then
        -- x2 mult, 1 in 4 chance to break
        ctx.mult = mult * 2
        Sfx.play_mult()
        if math.random(1, 4) == 1 then
            ctx.glass_broken_node = self
        end
    elseif self.enhancement == "steel" then
        -- x1.5 mult when held in hand
        ctx.mult = math.floor((tonumber(ctx.mult) or 1) * 1.5)
        Sfx.play_mult()
    elseif self.enhancement == "stone" then
        -- +50 chip
        ctx.chips = (tonumber(ctx.chips) or 0) + 50
        Sfx.play_chips()
    elseif self.enhancement == "gold" then
        -- +$3 when held in hand
        G.money = G.money + 3
        Sfx.play_money()
    elseif self.enhancement == "lucky" then
        local triggered = false
        -- 1 in 5 chance to give +20 mult
        if math.random(1, 5) == 1 then
            ctx.mult = (tonumber(ctx.mult) or 1) + 20
            triggered = true
            Sfx.play_mult()
        end
        -- 1 in 15 to give +$20
        if math.random(1, 15) == 1 then
            G.money = G.money + 20
            triggered = true
            Sfx.play_money()
        end
        if triggered then
            G:emit_joker_event("lucky_trigger")
        end
    end
end

---@param ctx table|nil
function Card:do_seal(ctx)
    ctx = type(ctx) == "table" and ctx or {}
    if self.seal == "gold" then
        if G and G.money ~= nil then
            G.money = G.money + 3
        end
        if Sfx and Sfx.play_money then Sfx.play_money() end
    elseif self.seal == "red" then
        -- Retrigger count is handled in `Hand` via `play_trigger_total` / `held_trigger_total`.
    elseif self.seal == "blue" then
        -- Planet card, when held in hand
    elseif self.seal == "purple" then

    end
end