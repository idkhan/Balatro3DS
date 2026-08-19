---@class Consumable : Moveable
Consumable = Moveable:extend()

local TooltipDraw = require("tooltip_draw")
-- Tarots.png starts its negative variants at cell 56. Cells 24-27 are card backs,
-- so the offset is larger than the number of base consumables.
local NEGATIVE_CONSUMABLE_INDEX_OFFSET = 56
local CONSUMABLE_SPRITE_DIR = "resources/textures/1x/Consumables/"
local _consumable_missing_atlas_reported = {}

--- Shared, refcounted consumable sprites.
---
--- These used to be loaded per instance with no cache at all, so two of the same tarot in
--- the tray were two copies of one 64x128 texture, opening a five-card Arcana pack was five
--- SD reads and five t3x decodes inside a single frame, and paging the collection browser
--- re-read every sprite on the page.
---
--- The shape mirrors the joker front sprites (`game.lua`, `_inc_atlas_owner` /
--- `_dec_atlas_owner`): entries are shared and the image is freed when the last consumable
--- holding it goes. That is safe because removal has exactly one path -- `Game:remove` calls
--- `release_texture`, which is idempotent through `_texture_released`, so a card cannot
--- decrement its entry twice.
--- Bumped by `release_all_sprites`. A card stamps the generation it acquired under and can
--- only decrement a count from that same generation: the sweep drops every count to zero,
--- so a card that outlived it would otherwise decrement a count belonging to a card
--- acquired afterwards and free a sprite still being drawn.
local _sprite_cache = {}
local _sprite_owners = {}
local _sprite_generation = 0

local function consumable_acquire_sprite(index)
    local entry = _sprite_cache[index]
    if not entry then
        local path = string.format("%s%03d.png", CONSUMABLE_SPRITE_DIR, index)
        local ok, image = pcall(love.graphics.newImage, path, { dpiscale = 1, mipmaps = false })
        local err = ok and nil or image
        if not ok then
            ok, image = pcall(love.graphics.newImage, path, {})
            if not ok then err = image end
        end
        entry = {
            name = "Consumable_" .. tostring(index),
            path = path,
            image = ok and image or nil,
            load_error = (not ok) and tostring(err) or nil,
            px = 64,
            py = 96,
            cols = 1,
        }
        _sprite_cache[index] = entry
    end
    _sprite_owners[index] = (_sprite_owners[index] or 0) + 1
    return entry, _sprite_generation
end

local function consumable_release_sprite(index, generation)
    -- Stale reference: the cache was swept out from under this card, and its count now
    -- belongs to whoever acquired the sprite after the sweep.
    if generation ~= _sprite_generation then return end

    local remaining = (_sprite_owners[index] or 0) - 1
    if remaining > 0 then
        _sprite_owners[index] = remaining
        return
    end

    _sprite_owners[index] = nil
    local entry = _sprite_cache[index]
    _sprite_cache[index] = nil
    if entry and entry.image then
        if entry.image.release then
            pcall(function() entry.image:release() end)
        end
        entry.image = nil
    end
end

--- Free every cached sprite and forget the counts.
---
--- Refcounts only stay balanced while every constructed consumable reaches `Game:remove`.
--- That holds today -- the tray, the shop and the collection browser all tear down through
--- it -- but a missed release would otherwise pin a texture for the life of the process.
--- The run teardown calls this for the same reason it bulk-frees the run atlases: a leak
--- bounded by one run is recoverable, a permanent one is not.
function Consumable.release_all_sprites()
    for index, entry in pairs(_sprite_cache) do
        if entry.image then
            if entry.image.release then
                pcall(function() entry.image:release() end)
            end
            entry.image = nil
        end
        _sprite_cache[index] = nil
    end
    for index in pairs(_sprite_owners) do
        _sprite_owners[index] = nil
    end
    -- Anything still holding a reference is now stale and must not decrement these counts.
    _sprite_generation = _sprite_generation + 1
end

--- How many distinct sprites are resident, and how many cards hold the one for `index`.
--- Test seam only; nothing in the game reads these.
function Consumable.sprite_cache_stats(index)
    local resident = 0
    for _ in pairs(_sprite_cache) do resident = resident + 1 end
    return resident, (index ~= nil) and (_sprite_owners[index] or 0) or nil
end

local function consumable_compute_quad(atlas, index)
    if not atlas or not atlas.image or index == nil then return nil, 0, 0 end
    local iw, ih = atlas.image:getDimensions()
    local cell_w, cell_h = atlas.px, atlas.py
    if not cell_w or not cell_h or cell_w <= 0 or cell_h <= 0 then
        return nil, 0, 0
    end
    -- T3X can report its padded/runtime width rather than the PNG's source
    -- width on hardware. Consumables use a fixed 16-column source atlas, so
    -- prefer that declared geometry instead of deriving it from the image.
    local cols = tonumber(atlas.cols) or math.floor(iw / cell_w)
    if cols <= 0 then return nil, 0, 0 end
    local col = index % cols
    local row = math.floor(index / cols)
    local sx = col * cell_w
    local sy = row * cell_h
    local quad = love.graphics.newQuad(sx, sy, cell_w, cell_h, iw, ih)
    return quad, cell_w, cell_h
end

local function consumable_normalize_edition(raw)
    if raw == nil or raw == "" then return "base" end
    local e = string.lower(tostring(raw))
    if e == "e_negative" or e == "negative" then return "negative" end
    return "base"
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
    self.edition = consumable_normalize_edition(self.def.edition)
    self.atlas_name = self.def.atlas or "Tarot"
    self.index = tonumber(self.def.index) or 0
    if self.edition == "negative" then
        self.index = self.index + NEGATIVE_CONSUMABLE_INDEX_OFFSET
    end
    self.atlas_name = "Consumable_" .. tostring(self.index)

    local cw, ch = 72, 95
    Moveable.init(self, X or 0, Y or 0, cw, ch)

    self.states.collide.can = false
    self.states.click.can = true
    self.states.drag.can = true
    self.states.visible = true

    -- Individual power-of-two sprites avoid reserving a 2 MiB atlas for a
    -- handful of visible cards and bypass T3X subtexture geometry on 3DS.
    self.atlas, self._sprite_gen = consumable_acquire_sprite(self.index)
    self._sprite_index = self.index
    self.quad, self.w, self.h = consumable_compute_quad(self.atlas, 0)

    if (not self.atlas or not self.atlas.image or not self.quad) and G and self.atlas_name then
        local key = tostring(self.atlas_name) .. ":" .. tostring(self.index)
        if not _consumable_missing_atlas_reported[key] then
            _consumable_missing_atlas_reported[key] = true
            local err = (self.atlas and self.atlas.load_error) and tostring(self.atlas.load_error) or "unknown atlas/quad failure"
            print(string.format("[Consumable] draw fallback for '%s' atlas='%s' idx=%s err=%s",
                tostring(self.name), tostring(self.atlas_name), tostring(self.index), err))
        end
    end

    if self.w and self.h and self.w > 0 and self.h > 0 then
        self.T.w = self.w
        self.T.h = self.h
        if self.VT then
            self.VT.w = self.w
            self.VT.h = self.h
        end
    end
end

function Consumable:release_texture()
    if self._texture_released then return end
    self._texture_released = true
    -- The atlas entry is shared, so this drops a reference rather than releasing the image:
    -- another card of the same consumable may still be drawing it.
    if self._sprite_index ~= nil then
        consumable_release_sprite(self._sprite_index, self._sprite_gen)
        self._sprite_index = nil
        self._sprite_gen = nil
    end
    self.atlas = nil
    self.quad = nil
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

    local draw_x = self.VT.x + self.collision_offset.x
    local draw_y = self.VT.y + self.collision_offset.y
    local draw_w = (self.VT and self.VT.w) or (self.T and self.T.w) or 72
    local draw_h = (self.VT and self.VT.h) or (self.T and self.T.h) or 95

    love.graphics.push()

    local cx = draw_x + (self.VT.w * self.VT.scale) / 2
    local cy = draw_y + (self.VT.h * self.VT.scale) / 2
    -- A used consumable keeps its size and comes apart inside the sprite, the way the
    -- reference's dissolve shader does it (`reference/Balatro/card.lua:2130`).
    local dissolve = self._card_lifecycle and self:lifecycle_dissolve() or nil
    -- The pop the reference fires at both ends of a lifecycle (`card.lua:2135`, `:2196`).
    -- `Moveable:update_juice` has always been driving these fields on a consumable; nothing
    -- read them, so a used tarot was the one thing on screen that came apart without
    -- flinching first. This transform is already centre-anchored, so the pop needs no
    -- re-centring the way `Card:draw` does.
    local scale = self.VT.scale * (self.juice_scale or 1)
    local rot = self.VT.r + (self.juice_r or 0)
    love.graphics.translate(cx, cy)
    love.graphics.rotate(rot)
    love.graphics.scale(scale, scale)
    love.graphics.translate(-cx, -cy)

    if self.atlas and self.atlas.image and self.quad then
        love.graphics.setColor(1, 1, 1, dissolve and (1 - dissolve) or 1)
        local masked = false
        -- `Fx` is a global wired up by main.lua; a consumable can be drawn by a harness that
        -- never loaded it, and a dissolve is not worth erroring over.
        if dissolve and Fx and Fx.draw_dissolve_cell then
            local b1, b2 = self:lifecycle_burn()
            local qx, qy, qw, qh = self.quad:getViewport()
            masked = Fx.draw_dissolve_cell(self.atlas.image, qx, qy, qw, qh, draw_x, draw_y,
                qw, qh, dissolve, b1, b2, self:lifecycle_seed())
        end
        if not masked then
            love.graphics.draw(self.atlas.image, self.quad, draw_x, draw_y, 0, 1, 1)
        end
    else
        -- Visual fallback helps distinguish "not drawn" vs "texture failed."
        love.graphics.setColor(0.9, 0.25, 0.25, 0.9)
        love.graphics.rectangle("line", draw_x, draw_y, draw_w, draw_h)
        love.graphics.setColor(1, 1, 1, 1)
    end

    love.graphics.pop()

    if G and G.draw_node_gamepad_focus_outline then
        G:draw_node_gamepad_focus_outline(self)
    end
end

function Consumable:draw_tooltip_overlay()
    if not self.states.visible or not self:tooltip_is_active() then return end
    local draw_x = self.VT.x + self.collision_offset.x
    local draw_y = self.VT.y + self.collision_offset.y
    self:draw_tooltip(draw_x, draw_y)
end

--- `def.tooltip` as a line list, whether it was written as one string or several.
---@return string[]
local function static_tooltip_lines(def)
    local out = {}
    local tip = def and def.tooltip
    if type(tip) == "table" then
        for _, l in ipairs(tip) do
            if type(l) == "string" and l ~= "" then out[#out + 1] = l end
        end
    elseif type(tip) == "string" and tip ~= "" then
        for line in tip:gmatch("[^\r\n]+") do
            if line ~= "" then out[#out + 1] = line end
        end
    end
    return out
end

--- Planet: hand level text. Tarot: optional `def.tooltip` string or list of strings.
---@return string[]
function Consumable:get_tooltip_body_lines()
    local def = self.def or {}
    if def.id == "tarot_fool" and G then
        local out = static_tooltip_lines(def)
        local last_id = G.last_consumable_use_id
        if last_id and CONSUMABLE_DEFS and CONSUMABLE_DEFS[last_id] then
            local name = CONSUMABLE_DEFS[last_id].name or last_id
            out[#out + 1] = "Currently: " .. tostring(name)
        end
        if #out > 0 then return out end
    end
    -- Temperance quotes what it would pay right now. The reference fills that in as the card's
    -- second localisation variable (`localization/en-us.lua:2938-2946`,
    -- `functions/common_events.lua:2687-2696`); without it the card is the one consumable whose
    -- worth the player cannot read off the card.
    if def.id == "tarot_temperance" and G and G.temperance_payout then
        local out = static_tooltip_lines(def)
        out[#out + 1] = string.format("(Currently $%d)", G:temperance_payout())
        if #out > 0 then return out end
    end
    if def.kind == "planet" and type(def.hand) == "string" and def.hand ~= "" then
        -- The reference names the hand's current level and the exact mult/chips the card
        -- grants, not just the hand (`localization/en-us.lua:2335-2342`, four lines:
        -- "(lvl.N) Level up" / hand / "+M Mult and" / "+C chips"). Those numbers are what
        -- the player is choosing between when a Celestial pack offers three planets.
        local idx
        for i, name in ipairs((G and G.handlist) or {}) do
            if name == def.hand then idx = i break end
        end
        local stats = idx and G and G.hand_stats and G.hand_stats[idx] or nil
        if stats then
            return {
                string.format("(lvl.%d) Level up", math.max(1, math.floor(tonumber(stats.level) or 1))),
                def.hand,
                string.format("+%d mult and", math.floor(tonumber(stats.mult_per_level) or 0)),
                string.format("+%d chips", math.floor(tonumber(stats.chips_per_level) or 0)),
            }
        end
        return { string.format("Increases the value of %s", def.hand) }
    end
    if def.kind == "tarot" or def.kind == "spectral" then
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
    if G.is_hand_scoring_active and G:is_hand_scoring_active() then return false end
    if G._collection_open and G._collection_tooltip_node == self then return true end
    if G.is_card_select_mode and G:is_card_select_mode() then return false end
    if self.shop_offer_slot and G.STATE == G.STATES.SHOP and G.active_tooltip_joker == self then
        return true
    end
    if G.should_draw_gamepad_focus_outline and G:should_draw_gamepad_focus_outline(self) then
        return true
    end
    if G.is_shop_item_selected and G:is_shop_item_selected(self) then
        return true
    end
    if self._booster_choice_index and G.STATE == G.STATES.OPEN_BOOSTER and G.booster_session then
        return tonumber(G.booster_session.active_choice_index) == self._booster_choice_index
    end
    if G.consumables_on_bottom ~= true then
        if self.states.drag.is then return true end
        return false
    end
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
    if G and G.is_discovered and def.id and not G:is_discovered(def.id) then
        title = "Not Discovered"
    end
    local font = G.FONTS.PIXEL.SMALL or love.graphics.getFont()

    local resolved = {}
    for _, line in ipairs(lines) do
        resolved[#resolved + 1] = TooltipDraw.build_segments_from_text(line)
    end

    TooltipDraw.draw_tooltip_layout(
        font, title, resolved,
        draw_x, draw_y,
        self.VT.w * self.VT.scale, self.VT.h * self.VT.scale
    )
end
