---@class Card : Moveable
Card = Moveable:extend()

--- Stone cards retain their former face only as dormant restoration data. Their rank and
--- suit must be absent from gameplay data, matching reference/Balatro/card.lua:957-981.
---@param data table|nil
---@return table|nil
function Card.normalize_gameplay_data(data)
    if type(data) ~= "table" or data.enhancement ~= "stone" then return data end
    if data.rank ~= nil then data._stone_rank = data.rank end
    if data.suit ~= nil then data._stone_suit = data.suit end
    data.rank = nil
    data.suit = nil
    return data
end

---@param data table|nil
---@return table|nil
function Card.restore_gameplay_data(data)
    if type(data) ~= "table" then return data end
    if data.rank == nil then data.rank = data._stone_rank end
    if data.suit == nil then data.suit = data._stone_suit end
    data._stone_rank = nil
    data._stone_suit = nil
    return data
end

--- Face sprite cell index in the `centers` atlas, per enhancement. The **back** is never listed
--- here: an enhancement replaces what a card shows face up, never what it shows face down. The
--- reference builds the back sprite from the selected deck's cell for every playing card
--- regardless of centre (`reference/Balatro/card.lua:213`).
local ENHANCEMENT_CENTER_INDICES = {
    bonus = { face = 8 },
    mult = { face = 9 },
    wild = { face = 10 },
    glass = { face = 12 },
    steel = { face = 13 },
    stone = { face = 5 },
    gold = { face = 6 },
    lucky = { face = 11 },
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

--- Randomness for pitch jitter, 0..1. Deliberately not `math.random`: the run reseeds that
--- stream for reproducibility, and a sound must never advance it.
local function sfx_jitter()
    if love and love.math and love.math.random then return love.math.random() end
    return 0.5
end

--- Ladder pitch for a cue raised during hand scoring; 1 outside a scoring run. Resolved
--- through the global so a headless load of this module alone still works.
local function scoring_pitch()
    if Hand and Hand.scoring_pitch then return Hand.scoring_pitch() end
    return 1
end

--- Module scope so a destroy or a create never allocates a list to pick from.
local CRUMPLE = { "crumple1", "crumple2", "crumple3", "crumple4", "crumple5" }

--- Destroying or creating several things in one frame is routine -- Immolate takes five
--- hand cards at once. These cues have two voices each, so a burst steals from itself and
--- collapses into a flam instead of layering. The reference gates materialise on a 0.01 s
--- window for exactly this (`reference/Balatro/card.lua:2211`); apply it both ways.
local last_cue_at = {}

---@param kind string
---@return boolean
local function cue_burst_ok(kind)
    local now = love and love.timer and love.timer.getTime and love.timer.getTime()
    if type(now) ~= "number" then return true end
    local prev = last_cue_at[kind]
    if prev and now >= prev and now - prev < 0.01 then return false end
    last_cue_at[kind] = now
    return true
end

--- A card, joker or consumable leaving the game: paper being torn away.
--- Reference `Card:start_dissolve` (`reference/Balatro/card.lua:2156`). Static, because by
--- the time a caller knows something was destroyed it has usually already dropped the node.
function Card.play_dissolve_sfx()
    if not cue_burst_ok("dissolve") then return end
    Sfx.play("whoosh2", 0.9 + sfx_jitter() * 0.2, 0.5)
    Sfx.play_random(CRUMPLE, 0.9 + sfx_jitter() * 0.2, 0.5)
end

--- The inverse: something materialising into the run. Reference `Card:start_materialize`
--- (`reference/Balatro/card.lua:2213`) -- a low whoosh under a high crumple.
function Card.play_materialize_sfx()
    if not cue_burst_ok("materialize") then return end
    Sfx.play("whoosh1", 0.6 + sfx_jitter() * 0.1, 0.3)
    Sfx.play_random(CRUMPLE, 1.2 + sfx_jitter() * 0.2, 0.8)
end

---@param self Card
local function selected_deck_back_index()
    if G and G.get_selected_deck_back_index then
        return G:get_selected_deck_back_index()
    end
    return 0
end

--- Standard playing-card face cell in `centers` (rank/suit come from `cards_2`). Deck backs use `DECK_DEFS.pos` independently.
local DEFAULT_PLAYING_CARD_FACE_INDEX = 1

---@param self Card
local function apply_enhancement_center_indices(self)
    local map = ENHANCEMENT_CENTER_INDICES
    if G and type(G.CARD_ENHANCEMENT_CENTER_INDICES) == "table" then
        map = G.CARD_ENHANCEMENT_CENTER_INDICES
    end
    -- The back is the selected deck's cell for every playing card, enhanced or not: a face-down
    -- card is hidden, not modified, so a Stone or Steel card turned over by The Wheel shows the
    -- same backing as the rest of the hand.
    self.back_index = self.params.back_index or selected_deck_back_index()
    local enh = self.enhancement
    if enh and map[enh] then
        self.face_index = map[enh].face or DEFAULT_PLAYING_CARD_FACE_INDEX
    else
        self.face_index = self.params.face_index or DEFAULT_PLAYING_CARD_FACE_INDEX
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
    Card.normalize_gameplay_data(self.card_data)
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
    -- back: `centers` cell from selected deck (`DECK_DEFS.pos`) or enhancement
    -- face: standard playing-card front in `centers` (rank/suit overlay from `cards_2`)
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
    self.sprite_face_up = self.face_up

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

    -- Prefer the atlas's declared column count. On hardware `getDimensions` can report the
    -- power-of-two padded size rather than the source PNG's (Enhancers.png is 720x380 on disk
    -- and 1024x512 in memory), so dividing width by cell width picks 14 columns instead of 10
    -- and every cell from index 10 up -- the non-red deck backs, the coloured seals, the wild /
    -- lucky / glass / steel faces -- lands on the wrong art. `consumable_compute_quad` prefers
    -- the declared count for the same reason (`consumable.lua:46`).
    local cols = tonumber(atlas.cols) or math.floor(iw / cell_w)
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

--- Logical facing changes immediately (gameplay reads it), the drawn face lags behind the
--- flip pinch and swaps edge-on, exactly as the reference splits `facing` from
--- `sprite_facing` (`reference/Balatro/card.lua:4113-4142`).
---@param face_up boolean
---@param instant boolean|nil skip the animation (deals, saves, off-screen setup)
function Card:set_face_up(face_up, instant)
    face_up = not not face_up
    self.face_up = face_up
    if self.sprite_face_up == nil then self.sprite_face_up = face_up end
    if self.sprite_face_up == face_up then return end
    if instant or not self.start_flip then
        self.sprite_face_up = face_up
        return
    end
    self:start_flip(function() self.sprite_face_up = self.face_up end)
end

--- Set or clear enhancement (updates `card_data.enhancement` and back/face sprites in the centers atlas).
---@param name string|nil
function Card:set_enhancement(name)
    if self.card_data then
        if self.card_data.enhancement == "stone" and name ~= "stone" then
            Card.restore_gameplay_data(self.card_data)
        end
        self.card_data.enhancement = name
        Card.normalize_gameplay_data(self.card_data)
    end
    self.enhancement = name
    self:refresh_quads()
    -- Deck composition drives seven unlocks, and a Gold Card that also carries a Gold Seal
    -- drives an eighth (`card.lua:144`, `:305`). The reference re-checks on every card
    -- mutation, which is exactly what this is.
    if G and G.check_unlock then
        G:check_unlock("modify_deck")
        if self.enhancement == "gold" and self.seal == "gold" then
            G:check_unlock("double_gold")
        end
    end
end

---@param name string|nil
function Card:set_seal(name)
    local changed = name ~= self.seal
    self.seal = name
    if self.card_data then
        self.card_data.seal = name
    end
    -- Applying a seal has its own cue, one for all four colours, exactly as the reference's
    -- `Card:set_seal` (`reference/Balatro/card.lua:472`). Removing one is silent. Nothing
    -- calls this on load or on a sprite refresh, so it cannot fire outside a real reveal.
    if changed and name and name ~= "none" and name ~= "" then
        Sfx.play("gold_seal", 1.2, 0.4)
    end
    self:refresh_quads()
    if G and G.check_unlock and self.enhancement == "gold" and self.seal == "gold" then
        G:check_unlock("double_gold")
    end
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

local TOOLTIP_PAD_X = 8
local TOOLTIP_HEADER_PAD_Y = 3
local TOOLTIP_BODY_PAD_Y = 10
local TOOLTIP_SPACING = 1
local TOOLTIP_SECTION_GAP = 2
local TOOLTIP_OUTER_PAD_X = 3
local TOOLTIP_OUTER_PAD_Y = 3
local CARD_SHADOW_ALPHA = 0.5
local CARD_SHADOW_DRAG_ALPHA = 0.45
local CARD_SHADOW_Y = 1.5
local CARD_SHADOW_DRAG_Y = 4

--- Offset and opacity for the single cheap card-shadow pass. The sideways component follows
--- the original's view-relative parallax (`reference/Balatro/engine/moveable.lua:71-73`).
--- Returning scalars keeps this per-card, per-frame path allocation-free.
function Card.shadow_draw_params(draw_x, width, lifted)
    local parallax_x = ((draw_x + width * 0.5) - 160) / 160 * 0.75
    -- The reference deepens the shadow whenever the card is physically raised — dragged,
    -- selected in hand, or up in the play area (`reference/Balatro/card.lua:4360-4362`,
    -- shadow_height 0.35 vs 0.1 at rest). Without this a 20 px lift reads as a slide.
    if lifted then
        return parallax_x, CARD_SHADOW_DRAG_Y, CARD_SHADOW_DRAG_ALPHA
    end
    return parallax_x, CARD_SHADOW_Y, CARD_SHADOW_ALPHA
end

--- Is this card debuffed right now, for score as well as for display?
---
--- The reference answers this per-getter: `get_chip_bonus`, `get_chip_h_x_mult`, `get_p_dollars`
--- and `get_seal` all return nothing when `card.debuff` is set (`reference/Balatro/card.lua:977`,
--- `:1007`, `:502`). The port has no per-card `debuff` field, so the boss predicate is the
--- source of truth and the two per-play flags cover the cases the play loop has already
--- resolved (`Hand:mark_scoring` sets `debuffed_for_scoring`).
---@return boolean
function Card:is_debuffed()
    if self.debuffed == true or self.debuffed_for_scoring == true then return true end
    return G and G.boss_is_card_debuffed_for_scoring
        and G:boss_is_card_debuffed_for_scoring(self) == true
end

local function card_is_debuffed_for_display(card)
    return G and G.boss_is_card_debuffed_for_scoring and G:boss_is_card_debuffed_for_scoring(card) == true
end

local function card_edition_for_display(card)
    local data = card and card.card_data
    local mod = data and data.modifier
    local ed = mod and mod.edition
    if type(ed) ~= "string" then return nil end
    if ed == "foil" or ed == "holo" or ed == "polychrome" then
        return ed
    end
    return nil
end

local function set_shop_edition_tint(edition)
    if edition == "foil" then
        love.graphics.setColor(0.80, 0.90, 1.0, 1)
    elseif edition == "holo" then
        love.graphics.setColor(0.94, 0.82, 1.0, 1)
    elseif edition == "polychrome" then
        love.graphics.setColor(0.88, 0.72, 1.0, 1)
    else
        love.graphics.setColor(1, 1, 1, 1)
    end
end

--- A stable per-card hue offset. The interference field behind holo and polychrome is
--- built once a frame and shared by every card on screen, so without this a hand of
--- editioned cards would shimmer in perfect lockstep; the reference avoids that with a
--- per-card shader seed (`holo.y`, `polychrome.y`).
---@return number
function Card:edition_seed()
    local uid = self.card_data and tonumber(self.card_data.uid)
    return ((uid or 0) * 0.137) % 1
end

--- Draw one layer through the Fx mesh passes instead of a plain draw. Only when the
--- layer has a quad (editions never apply to a card that hasn't resolved its art).
local function draw_layer_with_edition(atlas, quad, cell_w, cell_h, edition, t, card)
    if not atlas or not atlas.image or not quad then return end
    local sx, sy, cw, ch = quad:getViewport()
    local rot = card and card.VT and card.VT.r or 0
    local juice = card and card.juice_r or 0
    -- "card" picks the 72x95 silhouette baked from the `centers` cell these layers come
    -- from; a Joker sprite is a different shape and gets its own.
    Fx.draw_edition_cell(atlas.image, sx, sy, cw, ch, 0, 0, cell_w, cell_h, edition, t,
        "card", Fx.foil_phase(rot, juice, t), card and card:edition_seed() or 0)
end

local DEBUFF_X_WIDTH = 5
local DEBUFF_WASH_R, DEBUFF_WASH_G, DEBUFF_WASH_B, DEBUFF_WASH_A = 0.40, 0.40, 0.44, 0.62
--- Lighter than the debuff wash, and bluer: a spent card should read as receded, not as
--- disabled. Both are drawn the same way, by redrawing the base layer tinted, so the card
--- keeps its rounded silhouette instead of picking up a hard rectangle.
local GREYED_WASH_R, GREYED_WASH_G, GREYED_WASH_B, GREYED_WASH_A = 0.22, 0.28, 0.32, 0.72

--- Corner-to-corner X, inset only by half the stroke so the arms stay on the card.
local function draw_debuff_x_overlay(draw_x, draw_y, w, h)
    local inset = DEBUFF_X_WIDTH * 0.5
    local x1 = draw_x + inset
    local y1 = draw_y + inset
    local x2 = draw_x + w - inset
    local y2 = draw_y + h - inset
    local prev_w = love.graphics.getLineWidth()
    love.graphics.setLineWidth(DEBUFF_X_WIDTH)
    love.graphics.setColor(0.95, 0.2, 0.2, 0.95)
    love.graphics.line(x1, y1, x2, y2)
    love.graphics.line(x1, y2, x2, y1)
    love.graphics.setLineWidth(prev_w)
end

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

local function card_data_bonus_chips(data)
    if type(data) ~= "table" then return 0 end
    return math.floor(tonumber(data.Bonus) or tonumber(data.bonus) or 0)
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

--- Modifier name lines, coloured the way the reference badges them: enhancements in the
--- Enhanced set colour, editions in the dark-edition badge colour, seals in their own colour
--- (`common_events.lua:2722-2736` queues one titled info box per badge; this compact tooltip
--- folds each into a named section instead).
local ENHANCEMENT_NAMES = {
    bonus = "Bonus Card", mult = "Mult Card", wild = "Wild Card", glass = "Glass Card",
    steel = "Steel Card", stone = "Stone Card", gold = "Gold Card", lucky = "Lucky Card",
}
local EDITION_NAMES = { foil = "Foil", holo = "Holographic", polychrome = "Polychrome" }
local SEAL_NAMES = { gold = "Gold Seal", red = "Red Seal", blue = "Blue Seal", purple = "Purple Seal" }

--- Effect line per edition, from the port's actual scoring values (`hand.lua`
--- `get_edition_bonus`; reference `localization/en-us.lua:343-372`).
local function edition_tooltip_lines(ed)
    if ed == "foil" then return { "+50 chips" }
    elseif ed == "holo" then return { "+10 mult" }
    elseif ed == "polychrome" then return { "×1.5 mult" }
    end
    return {}
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
    elseif enh == "wild" then return { "Can be any Suit" }
    end
    return {}
end

---@param seal string|nil
---@return string[]
local function seal_tooltip_lines(seal)
    if not seal then return {} end
    if seal == "gold" then return { "+$3 when scored" }
    elseif seal == "red" then return { "Retriggers Card Once" }
    elseif seal == "blue" then return { "Creates a Planet card for the winning Hand if held in hand" }
    elseif seal == "purple" then return { "Creates a Tarot Card when Discarded" }
    end
    return {}
end

-- No selection-lift adjustment here: the lift lives in the card's `T.y` (`hand.lua`,
-- `set_card_target`), so `VT` already carries it and the inherited rect is correct.

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

--- Body text colour, and the fallback for the odds prefix. Module constants because these
--- were two fresh tables per frame for every frame a tooltip was up.
local TOOLTIP_BODY_GREY = { 0.22, 0.24, 0.26, 1 }
local TOOLTIP_PROB_GREEN = { 0.2, 0.75, 0.55, 1 }
local TOOLTIP_FALLBACK_WHITE = { 1, 1, 1, 1 }

--- Split an optional `1/5: ` style odds prefix, which the body colours separately.
local function strip_prob_prefix(s)
    local p = s:match("^(%d+/%d+:%s*)")
    if p then
        return p, s:sub(#p + 1)
    end
    return nil, s
end

--- A run is one centred line of coloured text: `{ width, measure, [i] = {text, colour, width} }`.
--- `width` is the sum of the segment widths, which is what centring uses; `measure` is the
--- width of the undivided line, which is what the box is sized from. The two differ only if
--- the face kerns across a segment boundary, and keeping both preserves the geometry the
--- uncached version produced.
local function new_run()
    return { width = 0, measure = 0 }
end

--- Bumped whenever the small pixel face changes, which retires every cached plan in one
--- integer compare. Holding the Font in the plan instead would keep a retired face (and
--- its glyph sheet) alive on every card that had shown a tooltip; `tooltip_font` holds
--- only the live one, so the old face is released as soon as the swap is noticed.
local tooltip_font_generation = 0
local tooltip_font = nil

---@return integer generation for `font`, bumped if the face has just changed
local function tooltip_font_epoch(font)
    if font ~= tooltip_font then
        tooltip_font = font
        tooltip_font_generation = tooltip_font_generation + 1
    end
    return tooltip_font_generation
end

local function run_add(run, font, text, colour)
    if not text or text == "" then return run end
    local w = font:getWidth(text)
    run[#run + 1] = { text = text, colour = colour, width = w }
    run.width = run.width + w
    return run
end

--- Decompose one body line into coloured segments, the way the reference badges numbers:
--- the odds prefix in green, chip and mult figures in their own colours, the rest in body grey.
local function build_line_run(font, line)
    local run = new_run()

    if type(line) == "table" then
        run.measure = font:getWidth(line.text)
        return run_add(run, font, line.text, line.color or TOOLTIP_BODY_GREY)
    end

    run.measure = font:getWidth(line)
    local green = (G.C and G.C.GREEN) or TOOLTIP_PROB_GREEN
    local prob, rest = strip_prob_prefix(line)

    local num_chips, suf_chips = rest:match("^(.-)( chips)$")
    if num_chips and suf_chips then
        run_add(run, font, prob, green)
        run_add(run, font, num_chips, G.C.CHIPS)
        return run_add(run, font, suf_chips, G.C.CHIPS)
    end

    local num_mult, suf_mult = rest:match("^(.-)( mult)$")
    if num_mult and suf_mult then
        run_add(run, font, prob, green)
        run_add(run, font, num_mult, G.C.MULT)
        return run_add(run, font, suf_mult, G.C.MULT)
    end

    local left, mid, right = rest:match("^(.-)%s(mult)(.*)$")
    if left and mid and right ~= nil then
        run_add(run, font, prob, green)
        run_add(run, font, left .. " ", G.C.MULT)
        run_add(run, font, mid, G.C.MULT)
        return run_add(run, font, right, TOOLTIP_BODY_GREY)
    end

    if prob then
        run_add(run, font, prob, green)
        return run_add(run, font, rest, TOOLTIP_BODY_GREY)
    end

    return run_add(run, font, line, TOOLTIP_BODY_GREY)
end

--- Everything about a card tooltip that does not depend on where it lands: the body lines,
--- their colour decomposition, every font measurement, and the resulting box geometry.
---
--- Split out because none of it changes between frames while the whole of it was being
--- rebuilt on every one: a dozen `string.format` calls, three closures, two throwaway
--- colour tables and a `getWidth` of every line and segment. A tooltip is up for the card
--- under the finger, so that ran while a card was being dragged, which is when frame
--- pacing is most visible. Measured on the interpreter the console actually runs (PUC Lua
--- 5.1, no trace compiler to sink any of it): a plain hand card was about 40% of the whole
--- frame's garbage, and a fully modified card cost 3.3 KB and 7.8 us per frame on its own.
--- `tooltip_draw.lua:91-105` already treats joker tooltips this way.
---@return table plan
local function build_tooltip_plan(font, rank, suit, enh, edition, seal,
                                  bonus_chips, chip_bonus, mult_bonus)
    local header = new_run()
    if enh == "stone" then
        -- Anonymous title: a stone card has no rank or suit to show.
        run_add(header, font, "Stone Card", G.C.PANEL)
    else
        local suit_name = tostring(suit or "?")
        local suit_colour = (G.C and G.C.SUITS and G.C.SUITS[suit_name])
            or (G.C and G.C.PANEL) or TOOLTIP_FALLBACK_WHITE
        run_add(header, font, string.format("%s of ", rank_to_label(rank)), G.C.PANEL)
        run_add(header, font, suit_name, suit_colour)
    end

    local lines = {}
    --- A modifier gets its reference badge name as a coloured line above its effect lines,
    --- standing in for the base game's per-badge info boxes.
    local function add_named_section(name, colour, effect_lines)
        if not name or #effect_lines == 0 then return end
        table.insert(lines, { text = name, color = colour })
        for _, l in ipairs(effect_lines) do
            table.insert(lines, l)
        end
    end
    local enh_name_colour = (G.C.SECONDARY_SET and G.C.SECONDARY_SET.Enhanced) or G.C.PURPLE
    local seal_colours = { gold = G.C.GOLD, red = G.C.RED, blue = G.C.BLUE, purple = G.C.PURPLE }

    if enh == "stone" then
        table.insert(lines, "+50 chips")
        if bonus_chips ~= 0 then
            table.insert(lines, string.format("Bonus %+d chips", bonus_chips))
        end
    else
        table.insert(lines, string.format("+%d chips", card_base_score(rank)))
        if bonus_chips ~= 0 then
            table.insert(lines, string.format("Bonus %+d chips", bonus_chips))
        end
        if chip_bonus ~= 0 then
            table.insert(lines, string.format("%+d chips", chip_bonus))
        end
        if mult_bonus ~= 0 then
            table.insert(lines, string.format("%+d mult", mult_bonus))
        end
        add_named_section(ENHANCEMENT_NAMES[enh], enh_name_colour, enhancement_tooltip_lines(enh))
    end
    -- Badge order matches the reference's info queue: enhancement, then edition, then seal
    -- (`common_events.lua:2722-2736`).
    add_named_section(EDITION_NAMES[edition], G.C.DARK_EDITION, edition_tooltip_lines(edition))
    add_named_section(SEAL_NAMES[seal], seal_colours[seal], seal_tooltip_lines(seal))

    local runs, body_max_w = {}, 0
    for i = 1, #lines do
        local run = build_line_run(font, lines[i])
        runs[i] = run
        if run.measure > body_max_w then body_max_w = run.measure end
    end

    local line_h = font:getHeight()
    local count = #runs
    local header_h_total = line_h + (TOOLTIP_HEADER_PAD_Y * 2)
    local body_h_total = (count * line_h) + ((count - 1) * TOOLTIP_SPACING) + (TOOLTIP_BODY_PAD_Y * 2)
    local inner_w = math.max(header.width + (TOOLTIP_PAD_X * 2), body_max_w + (TOOLTIP_PAD_X * 2))
    local inner_h = header_h_total + TOOLTIP_SECTION_GAP + body_h_total

    return {
        -- Key: every input the plan was derived from. The face is represented by
        -- `tooltip_font_generation` rather than by the Font itself: `Fonts.apply` swaps
        -- the faces inside `FONTS.PIXEL` in place, and a plan holding the retired face
        -- would pin its glyph sheet on every card that had ever shown a tooltip --
        -- the retention that function's own cleanup block exists to avoid.
        generation = tooltip_font_generation,
        rank = rank,
        suit = suit,
        enh = enh,
        edition = edition,
        seal = seal,
        bonus_chips = bonus_chips,
        chip_bonus = chip_bonus,
        mult_bonus = mult_bonus,

        header = header,
        runs = runs,
        line_h = line_h,
        header_h_total = header_h_total,
        body_h_total = body_h_total,
        inner_w = inner_w,
        box_w = inner_w + (TOOLTIP_OUTER_PAD_X * 2),
        box_h = inner_h + (TOOLTIP_OUTER_PAD_Y * 2),
    }
end

--- Draw one centred run at `line_y`, left-aligned from the centre of an `inner_w` box at `x`.
local function draw_run(run, font, x, inner_w, line_y)
    local pen = x + math.floor((inner_w - run.width) * 0.5 + 0.5)
    for i = 1, #run do
        local seg = run[i]
        local c = seg.colour
        love.graphics.setColor(c[1], c[2], c[3], c[4] or 1)
        love.graphics.print(seg.text, pen, line_y)
        pen = pen + seg.width
    end
end

function Card:draw_tooltip(draw_x, draw_y)
    local data = self.card_data or {}
    local rank = data.rank
    local suit = data.suit
    local bonus_chips = card_data_bonus_chips(data)
    local chip_bonus, mult_bonus = get_card_modifier_bonus(data)
    local enh = self.enhancement
    if enh == "none" then enh = nil end
    local edition = card_edition_for_display(self)
    local seal = self.seal

    local font = G.FONTS.PIXEL.SMALL or love.graphics.getFont()
    local generation = tooltip_font_epoch(font)

    -- Nine scalar comparisons against a cached plan, all of them values that were being
    -- derived anyway. Anything that changes the printed face misses and rebuilds.
    local plan = self._tooltip_plan
    if not (plan and plan.generation == generation and plan.rank == rank and plan.suit == suit
            and plan.enh == enh and plan.edition == edition and plan.seal == seal
            and plan.bonus_chips == bonus_chips and plan.chip_bonus == chip_bonus
            and plan.mult_bonus == mult_bonus) then
        plan = build_tooltip_plan(font, rank, suit, enh, edition, seal,
            bonus_chips, chip_bonus, mult_bonus)
        self._tooltip_plan = plan
    end

    local prev_font = love.graphics.getFont()
    local prev_r, prev_g, prev_b, prev_a = love.graphics.getColor()
    love.graphics.setFont(font)

    local line_h = plan.line_h
    local header_h_total = plan.header_h_total
    local body_h_total = plan.body_h_total
    local inner_w = plan.inner_w
    local box_w, box_h = plan.box_w, plan.box_h

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
    draw_run(plan.header, font, header_x, inner_w, header_text_y)

    local text_y = body_y + TOOLTIP_BODY_PAD_Y
    local runs = plan.runs
    for i = 1, #runs do
        draw_run(runs[i], font, body_x, inner_w, math.floor(text_y + 0.5))
        text_y = text_y + line_h + TOOLTIP_SPACING
    end

    love.graphics.setFont(prev_font)
    love.graphics.setColor(prev_r, prev_g, prev_b, prev_a)
end

--- World draw position for sprite and tooltip (selected lift). The trigger pop is scale and
--- rotation only, as in the original - what shakes on a hit is the room, not the card
--- (`Game:shake`).
function Card:get_layout_draw_xy()
    local draw_x = self.VT.x + self.collision_offset.x
    local draw_y = self.VT.y + self.collision_offset.y
    return draw_x, draw_y
end

function Card:should_draw_tooltip()
    if not self.face_up then return false end
    if G and G.is_hand_scoring_active and G:is_hand_scoring_active() then return false end
    if G and G._collection_open and G._collection_tooltip_node == self then return true end
    if G and G.is_hand_cursor_active and G:is_hand_cursor_active() then
        return G:dpad_cursor_node() == self
    end
    if self.shop_offer_slot and G and G.STATE == G.STATES.SHOP and G.active_tooltip_joker == self then
        return true
    end
    if G and G.should_draw_gamepad_focus_outline and G:should_draw_gamepad_focus_outline(self) then
        return true
    end
    if G and G.is_shop_item_selected and G:is_shop_item_selected(self) then
        return true
    end
    if self._booster_choice_index and G and G.STATE == G.STATES.OPEN_BOOSTER and G.booster_session then
        return tonumber(G.booster_session.active_choice_index) == self._booster_choice_index
    end
    if self._deck_view_card and G and G._deck_view_open then
        return self.states.drag.is or G.active_tooltip_card == self
    end
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
    local ed = card_edition_for_display(self)
    love.graphics.setColor(1, 1, 1, 1)

    local draw_x, draw_y = self:get_layout_draw_xy()
    -- The drawn face lags the logical one through the flip pinch (see `set_face_up`).
    local shown_up = self.sprite_face_up
    if shown_up == nil then shown_up = self.face_up end
    local flip_sx = self.flip_sx and self:flip_sx() or 1
    local w, h = self.VT.w, self.VT.h
    local s = self.VT.scale or 1
    local r = self.VT.r or 0
    local lifecycle_alpha = 1
    if self._card_lifecycle then
        local lifecycle_scale
        lifecycle_scale, lifecycle_alpha = self:lifecycle_visuals()
        -- A Card is drawn from its top-left, so shrinking it has to be re-centred by hand;
        -- Joker and Consumable already draw about their centre.
        draw_x = draw_x + (1 - lifecycle_scale) * w * s * 0.5
        draw_y = draw_y + (1 - lifecycle_scale) * h * s * 0.5
        s = s * lifecycle_scale
    end

    -- Trigger pop: grow about the card's centre rather than its top-left corner.
    local js = self.juice_scale
    if js then
        draw_x = draw_x - (js - 1) * w * s * 0.5
        draw_y = draw_y - (js - 1) * h * s * 0.5
        s = s * js
        r = r + self.juice_r
    end

    -- The reference draws a parallaxed silhouette before the card (`reference/Balatro/card.lua:4359-4363`).
    -- Limit it to one base-atlas pass: alpha fill rate is precious on the Old 3DS's 268 MHz GPU.
    local lifted = self.states.drag.is
        or (self.selected == true and not self.scoring_center)
        or (self.scoring_center == true and self.counts_for_play_score == true and not self._score_lift_y)
    local shadow_x, shadow_y, shadow_alpha = Card.shadow_draw_params(draw_x, w, lifted)
    love.graphics.push()
    love.graphics.translate(draw_x + shadow_x, draw_y + shadow_y)
    love.graphics.scale(s, s)
    love.graphics.translate(w * 0.5, h * 0.5)
    love.graphics.rotate(r)
    love.graphics.scale(flip_sx, 1)
    love.graphics.translate(-w * 0.5, -h * 0.5)
    love.graphics.setColor(0, 0, 0, shadow_alpha * lifecycle_alpha)
    if shown_up and self.face_quad then
        self:draw_layer(self.face_atlas, self.face_quad, self.face_w, self.face_h, 0, 0)
    elseif self.back_quad then
        self:draw_layer(self.back_atlas, self.back_quad, self.back_w, self.back_h, 0, 0)
    end
    love.graphics.pop()

    love.graphics.push()
    love.graphics.translate(draw_x, draw_y)
    love.graphics.scale(s, s)
    love.graphics.translate(w * 0.5, h * 0.5)
    love.graphics.rotate(r)
    love.graphics.scale(flip_sx, 1)
    love.graphics.translate(-w * 0.5, -h * 0.5)

    -- base layer: back or face, depending on orientation. An edition replaces the
    -- plain draw with the Fx mesh passes; editions only show on the face (the
    -- reference never applies edition shaders to card backs).
    if shown_up then
        if self.face_quad then
            if ed and (self.shop_offer_slot == nil or Fx.shop_editions_animated()) then
                -- Reference card drawing applies the edition shader without an area check
                -- (`reference/Balatro/card.lua:4416-4424`). Each animated edition creates two
                -- transient meshes per frame, so shop shelves keep the flat tint only on the
                -- Old 3DS's 268 MHz CPU (`Fx.shop_editions_animated`).
                draw_layer_with_edition(self.face_atlas, self.face_quad, self.face_w, self.face_h, ed, Fx.time(), self)
            else
                set_shop_edition_tint(ed)
                self:draw_layer(self.face_atlas, self.face_quad, self.face_w, self.face_h, 0, 0)
                love.graphics.setColor(1, 1, 1, lifecycle_alpha)
            end
        elseif self.back_quad then
            self:draw_layer(self.back_atlas, self.back_quad, self.back_w, self.back_h, 0, 0)
        end
    else
        if self.back_quad then
            self:draw_layer(self.back_atlas, self.back_quad, self.back_w, self.back_h, 0, 0)
        end
    end

    -- middle layer: rank + suit icon (only when face-up)
    if shown_up and self.rank_quad then
        self:draw_layer(self.rank_atlas, self.rank_quad, self.rank_w, self.rank_h, 0, 0)
    end

    -- Steel and Glass deliberately get no shine pass: the reference draws them as static
    -- atlas art, reserving the voucher.fs sweep for vouchers, gold seals and stickers
    -- (reference/Balatro/card.lua:4440-4500). Adding one here would be a divergence.

    -- top: seal overlay (`draw_layer` like rank; separate atlas + per-seal index)
    if shown_up and self.seal_quad then
        self:draw_layer(self.seal_atlas, self.seal_quad, self.seal_w, self.seal_h, 0, 0)
        -- Gold seals get the periodic light sweep the reference does in gold_seal.fs.
        if self.shop_offer_slot == nil and self.seal == "gold" and self.seal_atlas and self.seal_atlas.image then
            local sx, sy, cw, ch = self.seal_quad:getViewport()
            Fx.draw_shine_cell(self.seal_atlas.image, sx, sy, cw, ch, 0, 0, self.seal_w, self.seal_h, Fx.time())
        end
    end

    -- Deck view "Remaining": a card already drawn or discarded is greyed rather than hidden,
    -- so the row still shows the whole deck and the gaps are visible. The reference does the
    -- same, greying instead of filtering (`UI_definitions.lua:3260-3266`, `copy.greyed`).
    -- No X over it: it is not debuffed, just spent.
    if self.greyed then
        love.graphics.setColor(GREYED_WASH_R, GREYED_WASH_G, GREYED_WASH_B, GREYED_WASH_A)
        if shown_up and self.face_quad then
            self:draw_layer(self.face_atlas, self.face_quad, self.face_w, self.face_h, 0, 0)
        elseif self.back_quad then
            self:draw_layer(self.back_atlas, self.back_quad, self.back_w, self.back_h, 0, 0)
        end
    end

    if card_is_debuffed_for_display(self) then
        -- Grey wash: redraw the base layer tinted so the card keeps its silhouette (rounded corners
        -- included) instead of picking up a hard rectangle.
        love.graphics.setColor(DEBUFF_WASH_R, DEBUFF_WASH_G, DEBUFF_WASH_B, DEBUFF_WASH_A)
        if shown_up and self.face_quad then
            self:draw_layer(self.face_atlas, self.face_quad, self.face_w, self.face_h, 0, 0)
        elseif self.back_quad then
            self:draw_layer(self.back_atlas, self.back_quad, self.back_w, self.back_h, 0, 0)
        end
        draw_debuff_x_overlay(0, 0, w, h)
    end

    love.graphics.pop()

    if G and G.is_hand_cursor_active and G:is_hand_cursor_active() and G.hand and G._dpad_cursor_index then
        local cursor = G.hand.card_nodes[G._dpad_cursor_index]
        if cursor == self and (not G.gamepad_focus_visible or G:gamepad_focus_visible()) then
            local r = self:get_collision_rect()
            local lw = love.graphics.getLineWidth()
            love.graphics.setLineWidth(2)
            love.graphics.setColor(0, 0, 0, 1)
            love.graphics.push()
            local cx = r.x + r.w / 2
            local cy = r.y + r.h / 2
            love.graphics.translate(cx, cy)
            love.graphics.rotate(self.VT.r)
            love.graphics.translate(-cx, -cy)
            love.graphics.rectangle("line", r.x, r.y, r.w, r.h)
            love.graphics.pop()
            love.graphics.setLineWidth(lw)
        end
    elseif G and G.draw_node_gamepad_focus_outline then
        G:draw_node_gamepad_focus_outline(self)
    end

    love.graphics.setColor(prev_r, prev_g, prev_b, prev_a)

    -- debug bounding box
    self:draw_boundingrect()

    -- draw children, if any
    for _, v in pairs(self.children or {}) do
        v:draw()
    end
end

--- Scratch context for `Card:trigger_sources`. Retrigger queries read it and return a count, so one
--- shared table serves every card instead of allocating per card per scoring pass. Do not retain it.
local RETRIGGER_CTX = {}

--- One entry per EXTRA trigger pass beyond the first, in trigger order, holding the joker that granted
--- it (Mime, Hack, Sock and Buskin, Hanging Chad, Blueprint) or `false` when the card itself did
--- (Red Seal, `card_data.retrigger_play` / `retrigger_held`). Total passes for the card is `#out + 1`.
--- Fills `out` in place; `Hand` walks it to give each retrigger source its own shake before the replay.
---@param held boolean in-hand pass rather than played pass
---@param seq table|nil play sequence (`cards`, Photograph fields for Sock and Buskin)
---@param out table
---@param held_first_pass_effect_applied boolean|nil
---@return table out
function Card:trigger_sources(held, seq, out, held_first_pass_effect_applied)
    local cd = self.card_data or {}
    local extra
    if held then
        extra = tonumber(cd.retrigger_held)
    else
        extra = tonumber(cd.retrigger_play)
    end
    extra = math.max(0, math.floor(extra or 0))
    for _ = 1, extra do
        out[#out + 1] = false
    end
    if not (G and G.collect_retrigger_sources) then return out end

    local ctx = RETRIGGER_CTX
    ctx.card_node = self
    ctx.retrigger_card = self
    ctx.played_cards = type(seq) == "table" and seq.cards or nil
    ctx.photograph_first_face_node = type(seq) == "table" and seq.photograph_first_face_node or nil
    ctx.photograph_pareidolia = type(seq) == "table" and seq.photograph_pareidolia or false
    ctx.held_first_pass_effect_applied = held and held_first_pass_effect_applied == true or nil
    return G:collect_retrigger_sources(held, ctx, out)
end

--- Dispatch a hand/scoring event to this card (e.g. `"card_played"` → `do_enhancement` / `do_seal` when it matches).
--- Known events: `"card_played"`, `"held_in_hand"`, `"on_round_end"` (e.g. Gold card, Blue seal — see `do_enhancement` / `do_seal`).
--- Juices the card when an enhancement or seal actually triggers (same animation as a scored card).
---@param event_name string
---@param ctx table|nil
---@return boolean triggered True when something on the card fired, so callers can skip the beat otherwise.
function Card:emit_hand_event(event_name, ctx)
    if type(ctx) ~= "table" then ctx = {} end
    local ev = ctx.event_name or event_name
    ctx.event_name = ev
    -- A debuffed card contributes nothing from its enhancement or its seal. The reference gets
    -- this for free because every getter behind `eval_card` bails on `card.debuff`; here the
    -- dispatch is the one place all of them go through. The played-card path already filters
    -- debuffed cards out upstream (`Hand:mark_scoring`), so this only bites for held-in-hand
    -- Steel and for end-of-round Gold / Blue seal.
    if self:is_debuffed() then return false end
    local trigger = false
    if self.enhancement and self.enhancement ~= "none" and self.do_enhancement then
        if self.enhancement == "gold" and ev == "on_round_end" then
            self:do_enhancement(ctx)
            trigger = true

        elseif self.enhancement == "steel" and ev == "held_in_hand" then
            self:do_enhancement(ctx)
            trigger = true

        elseif (self.enhancement == "bonus" or self.enhancement == "mult" or  self.enhancement == "glass" or self.enhancement == "lucky" or self.enhancement == "stone") and ev == "card_played" then
            self:do_enhancement(ctx)
            trigger = true

        end
    end
    if self.seal and self.do_seal then
        if ev == "on_round_end" and self.seal == "blue" then
            self:do_seal(ctx)
            trigger = true

        elseif ev == "card_played" and self.seal == "gold" then
            self:do_seal(ctx)
            trigger = true

        elseif ev == "on_discard" and self.seal == "purple" and ctx.discard_reason == "discard" then
            self:do_seal(ctx)
            trigger = true
        end
    end
    if trigger then
        self:juice_up()
    end
    return trigger
end

function Card:do_enhancement(ctx)
    if type(ctx) ~= "table" then return end
    local chips = tonumber(ctx.chips) or 0
    local mult = tonumber(ctx.mult) or 1
    ctx.chips = chips
    ctx.mult = mult
    p = Popup()
    local card_center_x = self.VT.x + self.collision_offset.x + (self.VT.w / 2) * self.VT.scale
    local card_center_y = self.VT.y + self.collision_offset.y + (self.VT.h / 2) * self.VT.scale
    
    if self.enhancement == "bonus" then
        --+30 chips
        ctx.chips = chips + 30   
        p:spawn(30, "chips", card_center_x, card_center_y)
        G:addPopup(p)
        Sfx.play_chips(scoring_pitch())
    elseif self.enhancement == "mult" then
        --+4 mult
        p:spawn(4, "mult", card_center_x, card_center_y)
        G:addPopup(p)
        ctx.mult = mult + 4
        -- reference/Balatro/functions/common_events.lua:821 — flat mult plays multhit1.
        Sfx.play_mult(scoring_pitch())
    elseif self.enhancement == "glass" then
        -- x2 mult, 1 in 4 chance to break
        p:spawn(2, "xmult", card_center_x, card_center_y)
        G:addPopup(p)
        ctx.mult = mult * 2
        -- reference/Balatro/functions/common_events.lua:828 — x_mult plays multhit2 at 0.7.
        Sfx.play_mult2(scoring_pitch(), 0.7)
    elseif self.enhancement == "steel" then
        p:spawn(1.5, "xmult", card_center_x, card_center_y)
        G:addPopup(p)
        ctx.mult = (tonumber(ctx.mult) or 1) * 1.5
        -- reference/Balatro/functions/common_events.lua:828 — x_mult plays multhit2 at 0.7.
        Sfx.play_mult2(scoring_pitch(), 0.7)
    elseif self.enhancement == "stone" then
        -- +50 chip
        ctx.chips = (tonumber(ctx.chips) or 0) + 50
        p:spawn(50, "chips", card_center_x, card_center_y)
        G:addPopup(p)
        Sfx.play_chips(scoring_pitch())
    elseif self.enhancement == "gold" then
        -- +$3 when held in hand
        G.money = G.money + 3
        p:spawn(3, "money", card_center_x, card_center_y)
        G:addPopup(p)
        Sfx.play_money(scoring_pitch())
    elseif self.enhancement == "lucky" then
        local triggered = false
        -- 1 in 5 chance to give +20 mult
        if G:do_random(1, 5, 1, "lucky_mult") then
            p:spawn(20, "mult", card_center_x, card_center_y)
            G:addPopup(p)
            ctx.mult = (tonumber(ctx.mult) or 1) + 20
            triggered = true
            Sfx.play_mult(scoring_pitch())
        end
        -- 1 in 15 to give +$20
        if G:do_random(1, 15, 1, "lucky_money") then
            G.money = G.money + 20
            p:spawn(20, "money", card_center_x, card_center_y)
            G:addPopup(p)
            triggered = true
            Sfx.play_money(scoring_pitch())
        end
        if triggered then
            G:emit_joker_event("lucky_trigger", { shake_card_node = self })
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
        Sfx.play_money(scoring_pitch())
    elseif self.seal == "red" then
        -- Retrigger passes are handled in `Hand` via `Card:trigger_sources`.
    elseif self.seal == "blue" then
        if not (G and G.add_consumable and G.random_planet_id_for_hand_name and G.can_add_consumable) then
            return
        end
        if not G:can_add_consumable() then return end
        local hand_idx = tonumber(ctx.last_played_hand_index) or tonumber(G.last_played_hand_index)
        if not hand_idx or hand_idx < 1 then return end
        local hand_name = G.handlist and G.handlist[hand_idx] or nil
        if not hand_name then return end
        local pid = G:random_planet_id_for_hand_name(hand_name, "celestial")
        if not pid then return end
        -- Creating a card announces with `generic1`: the reference's seal path reaches
        -- `card_eval_status_text(..., 'extra', ...)` with no mult or edition to report, which
        -- resolves to `generic1` (`card.lua:1061`, `common_events.lua:854`). A mult thwack
        -- here read as a scoring hit rather than a card appearing.
        if G:add_consumable(pid) and Sfx and Sfx.play then
            Sfx.play("generic1")
        end
    elseif self.seal == "purple" then
        if not (G and G.add_consumable and G.random_non_fool_tarot_id and G.can_add_consumable) then
            return
        end
        if not G:can_add_consumable() then return end
        local tid = G:random_non_fool_tarot_id("fool")
        if not tid then return end
        -- As above (`card.lua:2266`).
        if G:add_consumable(tid) and Sfx and Sfx.play then
            Sfx.play("generic1")
        end
    end
end
