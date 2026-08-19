---@class Hand
Hand = Object:extend()

local Particles = require("particles")

local SCREEN_W = 320
local SCREEN_H = 240
local CARD_W = 72
local CARD_H = 95
-- Gradual scaling: scale = min(1, CARDS_AT_FULL_SCALE / n), clamped to MIN_HAND_SCALE
local CARDS_AT_FULL_SCALE = 6
local MIN_HAND_SCALE = 1

--- Card height in px over the reference's `G.CARD_H` of 2.75 tiles. The hand's shape and sway
--- are card-relative, not screen-relative, so they convert on the card rather than on the
--- screen the way `engine/moveable.lua` does.
local PX_PER_UNIT = CARD_H / (2.4 * 47 / 41)

--- Fan and arc, both straight off `CardArea:align_cards` (`cardarea.lua:454`). The hand is not
--- a row: cards rotate a little further out from centre in each direction and the ends droop.
--- With eight cards that is +-5 degrees across the fan and about 6 px of droop.
local FAN_ANGLE = 0.2
local ARC_DROP = PX_PER_UNIT

--- How far a picked card rises out of the fan. The reference's `G.HIGHLIGHT_H`
--- (`cardarea.lua:458`), in this port's pixels.
local SELECTED_LIFT = 20

--- Gap between the bottom of the fan and the bottom of the screen.
---
--- The reference anchors its Play/Sort/Discard UIBox *under* `G.hand` and lets the layout push
--- the hand up to fit it. This port draws into a fixed 320x240 playfield with no layout engine,
--- so the room for that bar has to be reserved here instead: 38 px puts the plate's face at
--- y 214 (`hand_actions_ui.lua`) with 7.5 px of clearance over the lowest card corner that
--- sits above it. The outermost cards hang lower still - `arc_drop` plus their +-5 degree fan
--- rotation - but they fall outside the bar's x span. `tests/test_hand_actions.lua` pins the
--- relationship so the two constants cannot drift apart.
local HAND_BOTTOM_MARGIN = 38

--- Idle sway. The reference recomputes card targets every frame with a pair of slow sines
--- folded in, phase-shifted by the card's own x so the hand ripples rather than pulsing in
--- unison, and lets the spring lag behind them. It is barely a pixel of travel and it is most
--- of the difference between a hand that is resting and a hand that is a screenshot.
local SWAY_R_AMP = 0.02
local SWAY_R_RATE = 2
local SWAY_Y_AMP = 0.03 * PX_PER_UNIT
local SWAY_Y_RATE = 0.666
--- The reference phases off x in tiles; the port's playfield is 320 px over the same 20 tiles.
local SWAY_PHASE_PER_PX = 20 / SCREEN_W

--- Where a card is before it is dealt, and where the hand un-deals back to: the deck.
---
--- The reference puts the deck at the bottom right, level with the hand -- `G.deck.T.y` and
--- `G.hand.T.y` are both `G.TILE_H - 0.95*G.CARD_H` and `G.deck.T.x` is half a tile in from
--- the right edge (`common_events.lua:22-24`). So cards slide in horizontally out of the deck
--- and fan across into the hand. This port had them dropping in from above the top right
--- instead, which is not where any deck is.
---
--- There is no deck sprite on the playfield here (the count lives on the top screen), so the
--- origin is just off the right edge at the hand's own y.
local OFFSCREEN_START_X = SCREEN_W + 0
local OFFSCREEN_START_Y = SCREEN_H - CARD_H - HAND_BOTTOM_MARGIN

local MAX_SELECTED = 5
local MAX_HAND_SIZE = 8
--- Beat between cards arriving in the hand. The reference deals at 0.1 s a card
--- (`common_events.lua:388`, and `draw_card`'s default is what `state_events.lua:372` uses for
--- the round-opening deal) and refills mid-round at 0.07 (`cardarea.lua:103`). One constant
--- covers both here; the opening deal is the one you actually watch.
local DRAW_DELAY = 0.1
--- Pause before the first card of a deal leaves the deck; the reference sits on `delay(0.3)`
--- ahead of every `draw_card` loop (`state_events.lua:369`).
local DEAL_LEAD_IN = 0.3
--- Shards outlive most of the dissolve they came from; the tween itself is timed by
--- `Moveable.DISSOLVE_DURATION`, which destroyed Jokers and used consumables share.
local DISSOLVE_DURATION = Moveable.DISSOLVE_DURATION
local DISSOLVE_PARTICLE_COUNT = 8
--- The reference tints the dissolve burst per card - black/orange/red/gold/joker-grey by
--- default, and callers override it (a Gold seal being destroyed passes gold, `card.lua:1609`).
--- Falling back to one hard-coded orange made every destruction look the same regardless of
--- what was destroyed.
local DISSOLVE_PARTICLE_COLOUR = { 1, 0.34, 0.16, 1 }
local DISSOLVE_PARTICLE_SPEC = {
    x = 0, y = 0, vx = 0, vy = 0, gravity = 48,
    lifetime = DISSOLVE_DURATION * 0.7, w = 2, h = 2,
    colour = DISSOLVE_PARTICLE_COLOUR, fade = true,
}

--- Dissolve tints keyed by what the card is, so the burst reads as a Gold card breaking
--- rather than a generic puff. Values are the port's palette entries where they exist.
--- Held by reference on every emitted shard, so these are shared constants rather than
--- per-dissolve allocations.
local DISSOLVE_COLOURS = {
    gold = { 0.94, 0.73, 0.20, 1 },
    red = { 0.86, 0.24, 0.24, 1 },
    blue = { 0.30, 0.55, 0.92, 1 },
    purple = { 0.60, 0.36, 0.86, 1 },
    glass = { 0.85, 0.92, 0.97, 1 },
    steel = { 0.60, 0.62, 0.66, 1 },
    stone = { 0.45, 0.45, 0.47, 1 },
}

local function dissolve_colour_for(node)
    local card = node and node.card_data
    if not card then return DISSOLVE_PARTICLE_COLOUR end
    -- A seal is the louder read, so it wins over the enhancement underneath it.
    return DISSOLVE_COLOURS[card.seal]
        or DISSOLVE_COLOURS[card.enhancement]
        or DISSOLVE_PARTICLE_COLOUR
end

-- Play / scoring sequence (bottom screen)
local PLAY_MOVE_MIN_TIME = 0.35
local PLAY_MOVE_MAX_TIME = 0.85
local PLAY_MOVE_ARRIVE_EPS = 2.5
--- Beat between played cards peeling out of the hand; the reference queue's default
--- (`common_events.lua:388`).
local PLAY_RELEASE_INTERVAL = 0.1
--- Beat between hand cards peeling off to the deck after a blind is beaten; the reference's
--- hand-to-discard sweep (`state_events.lua:1126`).
local UNDEAL_RELEASE_INTERVAL = 0.07
--- Beat between scoring triggers.
---
--- The reference does not hold a constant here; every scoring pop is a blocking event whose
--- delay is the pop's own hold time, `0.65` for most things and `0.6` for chips, all scaled by
--- `1.25` on the way out (`common_events.lua:805,878`). Chips are what a played card raises,
--- so `0.6*1.25` is the beat the bulk of a hand runs at. It is much slower than it looks
--- written down - a five card hand is about four seconds - and that unhurried tick is most of
--- what the scoring sequence feels like. `Game:speed_factor` is what keeps a long joker chain
--- from becoming a problem, exactly as the original does it.
local PLAY_TRIGGER_INTERVAL = 0.75
--- Beat for each of a card's effects past its chips.
---
--- The reference charges a blocking beat per *effect*, not per card: chips at `0.6*1.25` and
--- everything else at `0.65*1.25` (`common_events.lua:806,816`). A card that only adds chips
--- costs one beat; a Steel, Glass or Lucky card costs two; one that is also editioned, or that
--- a joker hangs something on, costs three or four. The port charged one beat for all of them,
--- so exactly the cards a deck is built around resolved fastest.
---
--- The sequencer counts these by sampling chips and mult at each stage of the pass rather than
--- by splitting the pass into separately announced effects. That keeps the scoring math
--- completely untouched - this is a pacing change and must not be able to become a scoring one.
---
--- The popups now follow those beats: `announce_card_effects` raises one per effect and staggers
--- them by this interval, so a Bonus card's rank and its enhancement are two announcements
--- rather than one added-up number. What is still shared is the *cue* - one trigger sound per
--- card, where the reference rings one per effect. Splitting that means restructuring the pass
--- itself, which is the scoring change this deliberately avoids.
local PLAY_EFFECT_INTERVAL = 0.8125
--- Beat for the joker that caused a retrigger (Mime, Hack, ...) to shake on its own before the
--- replay. The reference announces one through the same path as a joker trigger: `0.75*1.25`.
local RETRIGGER_NOTICE_INTERVAL = 0.9375
--- After the last trigger, before the total lands and the cards clear. The reference sits on
--- `delay(0.3)` here (`state_events.lua:782`).
local PLAY_AFTER_SCORE_PAUSE = 0.3
local PLAY_CENTER_SCALE = 1
--- The reference pauses once the played cards land (`state_events.lua:601`, `delay(0.2)`)
--- before lifting the scoring subset one card at a time (`common_events.lua:434-442`,
--- 0.1 s apart with a rising cardSlide1), then holds again before the first trigger
--- (`state_events.lua:610-620`, roughly 0.4 + the hand-name beat). That build-up is the
--- signature rhythm of a played hand.
local PLAY_HIGHLIGHT_LEAD = 0.2
local PLAY_HIGHLIGHT_INTERVAL = 0.1
local PLAY_ANTICIPATION = 0.55

--- Randomness for pitch jitter, 0..1. Deliberately not `math.random`: the run reseeds that
--- stream for reproducibility, and a sound must never advance it.
local function sfx_jitter()
    if love and love.math and love.math.random then return love.math.random() end
    return 0.5
end

-- Scoring pitch ladder. The reference opens every hand at 0.3 and steps 0.08 per scoring
-- trigger (`state_events.lua:607`), feeding each scoring cue `pitch = 0.8 + percent*0.2`,
-- so a long joker chain audibly climbs. Nothing resets it mid-hand.
local SCORE_PERCENT_START = 0.3
local SCORE_PERCENT_DELTA = 0.08

--- Position of card `i` of `n` in a fan-out sweep, as 0..1.
--- The odd constants are the reference's (`common_events.lua:439` and friends): they keep
--- a one-card fan off a divide-by-zero without special-casing it.
---@param i integer
---@param n integer
---@return number
local function fan_percent(i, n)
    return (i - 0.999) / ((tonumber(n) or 1) - 0.998)
end

--- Fan angle for card `i` of `n`, in radians. `cardarea.lua:454`, verbatim.
---@param i integer
---@param n integer
---@return number
local function fan_rotation(i, n)
    return FAN_ANGLE * (-n / 2 - 0.5 + i) / n
end

--- Downward droop for card `i` of `n`. The reference's term is a folded straight line, not a
--- curve: the ends of the hand hang, and the two middle cards sit level with each other.
---@param i integer
---@param n integer
---@param amount number px of droop per unit
---@return number
local function arc_drop(i, n, amount)
    return amount * math.abs(0.5 * (-n / 2 + i - 0.5) / n)
end

--- Point a card at its laid-out transform, and remember it so `apply_idle_sway` has something
--- to sway around. Cards that leave the hand's layout (played, dragged) drop the record.
---
--- A card out in the play area is off limits: it is still in `card_nodes` until the hand is
--- discarded, and anything that relays out the hand mid-scoring (a card destroyed by Glass or
--- Sixth Sense does exactly that) would otherwise drag the played cards back down into the fan.
---@return boolean placed false when the card is out in the play area and was left alone
local function set_card_target(node, x, y, r, scale)
    if node.scoring_center then
        node._layout_base = nil
        return false
    end
    -- The selection lift belongs in the target, not in the draw call. The reference subtracts
    -- `G.HIGHLIGHT_H` from the card's `T.y` (`cardarea.lua:458`) so the rise runs through
    -- `move_xy` and inherits the spring's overshoot and the velocity-derived lean. Applied at
    -- draw time it snapped up in a single frame with no bounce and no tilt, on the interaction
    -- the player performs more than any other.
    if node.selected then y = y - SELECTED_LIFT end
    node.T.x = x
    node.T.y = y
    node.T.r = r
    node.T.scale = scale
    local base = node._layout_base
    if base then
        base.x, base.y, base.r = x, y, r
    else
        node._layout_base = { x = x, y = y, r = r }
    end
    return true
end

local function hand_size_limit()
    if G and G.get_effective_hand_size_limit then
        return math.max(1, tonumber(G:get_effective_hand_size_limit()) or MAX_HAND_SIZE)
    end
    return MAX_HAND_SIZE
end

function Hand:init(game)
    self.game = game or G
    self.cards = {}
    self.card_nodes = {}
    self.selected = {}
    self._draw_queue = {}
    self._draw_timer = 0
    self._destroying_nodes = {}
    -- A pending discard resume must not survive a hand reset; its nodes are gone.
    self._pending_discard_finish = nil
    self._materializing_nodes = {}
    self.sort_mode = "rank"
    self._play_sequence = nil
    -- A run abandoned mid-drain must not leave the landed total on the next run's readout.
    if G then
        G.chip_total_display = nil
        G.chip_total_drain = nil
    end
end

--- One played card scoring: the chip cue alone, riding the ladder. The reference's `chips`
--- eval type plays only `chips1` (`common_events.lua:816`); `generic1` belongs to the
--- joker/extra type, so doubling it here thickened every card hit.
function Hand:play_sfx_trigger()
    Sfx.play_chips(Hand.scoring_pitch())
end

function Hand:is_scoring_active()
    return self._play_sequence ~= nil
end

--- Pitch for a cue fired from the current scoring trigger. Outside a scoring run there is
--- no ladder, so the code paths shared with the shop and round end (a steel card from a
--- tarot, a joker paying out at round end) stay unmodified.
---@return number
function Hand.scoring_pitch()
    local seq = G and G.hand and G.hand._play_sequence
    if not seq then return 1 end
    return 0.8 + (seq.percent or SCORE_PERCENT_START) * 0.2
end

--- Step the ladder one trigger. One step per scored pass, never per cue: a card that adds
--- both chips and mult is one trigger and moves the pitch once.
---@param seq table
local function advance_scoring_pitch(seq)
    seq.percent = (seq.percent or SCORE_PERCENT_START) + SCORE_PERCENT_DELTA
end

--- Joker variant. The reference's joker loop steps once per joker that did something
--- (`state_events.lua:882-943`), but a joker firing inside a played card's pass shares
--- that pass's pitch instead. `Joker:apply_effect` cannot tell the two apart, so the
--- sequencer raises `percent_per_joker` once it reaches the joker loop and this is a
--- no-op until then.
function Hand.advance_scoring_pitch_per_joker()
    local seq = G and G.hand and G.hand._play_sequence
    if seq and seq.percent_per_joker then
        advance_scoring_pitch(seq)
    end
end

--- Keep `self.cards` aligned with each node's `card_data` (tarots may replace node tables).
function Hand:sync_cards_from_nodes()
    for i, node in ipairs(self.card_nodes or {}) do
        if node and node.card_data then
            self.cards[i] = node.card_data
        end
    end
end

--- Pitch for the next card sliding into the hand, rising across a deal
--- (`common_events.lua:416`). A card added outside a deal -- created by a tarot, duplicated
--- by a joker -- has no position in a sweep and lands at the top of the range.
---@return number
function Hand:next_deal_pitch()
    local n = self._deal_n
    if not n then return 1.05 end
    local i = (self._deal_i or 0) + 1
    self._deal_i = i
    if i >= n then
        self._deal_n = nil
        self._deal_i = nil
    end
    return 0.85 + fan_percent(i, n) * 0.2
end

---@param bypass_limit boolean|nil if true, allow one card over normal hand cap (e.g. Certificate)
function Hand:add_card(card_data, bypass_limit)
    if not card_data or not self.game then return nil end
    if Card and Card.normalize_gameplay_data then
        Card.normalize_gameplay_data(card_data)
    end
    if self.game and self.game.ensure_card_uid then
        self.game:ensure_card_uid(card_data)
    end
    local limit = hand_size_limit()
    if self.game and self.game.get_active_boss_blind_id and self.game:get_active_boss_blind_id() == "bl_serpent" then
        limit = math.max(limit, 999)
    end
    if not bypass_limit and #self.cards >= limit then return nil end
    table.insert(self.cards, card_data)
    if self.game and self.game.discover_card_properties then
        self.game:discover_card_properties(card_data)
    end
    local face_up = true
    local flipped_cards = self.game.challenge_modifiers and tonumber(self.game.challenge_modifiers.flipped_cards)
    if flipped_cards and flipped_cards > 0 then
        -- X-ray Vision flips each draw independently (reference/Balatro/cardarea.lua:601-605).
        face_up = self.game:random("flipped_card", 1, flipped_cards) ~= 1
    end
    local node = Card(0, 0, nil, nil, card_data, nil, { face_up = face_up })
    self.game:add(node)
    table.insert(self.card_nodes, node)
    self:layout(false)
    -- New card animates in from off-screen; existing cards interpolate to new T
    local new_node = self.card_nodes[#self.card_nodes]
    new_node.VT.x = OFFSCREEN_START_X
    new_node.VT.y = OFFSCREEN_START_Y
    new_node.VT.r = 0
    new_node.VT.scale = new_node.T.scale
    Sfx.play("card1", self:next_deal_pitch(), 0.6)

    if self.sort_mode == "rank" then
        self:sort_by_rank(new_node)
    elseif self.sort_mode == "suit" then
        self:sort_by_suit(new_node)
    end

    if self.game and self.game.boss_on_card_drawn then
        self.game:boss_on_card_drawn(new_node)
    end

    return node
end

--- Fan geometry for hit-testing and reorder (same math as layout).
function Hand:_layout_metrics()
    local nodes = self.card_nodes
    local n = #nodes
    if n == 0 then return nil end
    local scale = math.max(MIN_HAND_SCALE, math.min(1, CARDS_AT_FULL_SCALE / n))
    local card_w = CARD_W * scale
    local card_h = CARD_H * scale
    local step = (SCREEN_W - card_w) / math.max(1, n - 1)
    local total_w = n == 1 and card_w or (card_w + (n - 1) * step)
    local start_x = (SCREEN_W - total_w) * 0.5
    local y = SCREEN_H - card_h - HAND_BOTTOM_MARGIN
    return {
        n = n,
        scale = scale,
        card_w = card_w,
        card_h = card_h,
        step = step,
        start_x = start_x,
        y = y,
    }
end

--- Nearest hand slot index (1..n) for a screen x (center of card column).
function Hand:slot_index_from_screen_x(screen_x)
    local m = self:_layout_metrics()
    if not m then return 1 end
    if m.n <= 1 then return 1 end
    local best_i, best_d = 1, 1e9
    for i = 1, m.n do
        local cx = m.start_x + (i - 1) * m.step + m.card_w / 2
        local d = math.abs(screen_x - cx)
        if d < best_d then
            best_d = d
            best_i = i
        end
    end
    return best_i
end

--- Move card node to the slot under release_x (hand order). Returns true if order changed.
function Hand:try_reorder_card_after_drag(node, release_x)
    if self._play_sequence or not node then return false end
    local from_idx
    for i, n in ipairs(self.card_nodes) do
        if n == node then
            from_idx = i
            break
        end
    end
    if not from_idx then return false end

    local to_idx = self:slot_index_from_screen_x(release_x)
    if to_idx == from_idx then return false end

    local card = table.remove(self.cards, from_idx)
    local inode = table.remove(self.card_nodes, from_idx)
    table.insert(self.cards, to_idx, card)
    table.insert(self.card_nodes, to_idx, inode)

    self:layout(false)
    if self.game and self.game.restore_hand_draw_order then
        self.game:restore_hand_draw_order()
    end
    if self.game and self.game.move_selected_hand_cards_to_front then
        self.game:move_selected_hand_cards_to_front()
    end
    Sfx.play_random("cardSlide1", "cardSlide2")
    return true
end

--- Gamepad: shift one hand card left (-1) or right (+1) in fan order.
function Hand:reorder_node_step(node, delta)
    if self._play_sequence or not node then return false end
    delta = math.floor(tonumber(delta) or 0)
    if delta == 0 then return false end

    local from_idx
    for i, n in ipairs(self.card_nodes) do
        if n == node then
            from_idx = i
            break
        end
    end
    if not from_idx then return false end

    local to_idx = from_idx + delta
    if to_idx < 1 or to_idx > #self.card_nodes then return false end

    local card = table.remove(self.cards, from_idx)
    local inode = table.remove(self.card_nodes, from_idx)
    table.insert(self.cards, to_idx, card)
    table.insert(self.card_nodes, to_idx, inode)

    self:layout(false)
    if self.game and self.game.restore_hand_draw_order then
        self.game:restore_hand_draw_order()
    end
    if self.game and self.game.move_selected_hand_cards_to_front then
        self.game:move_selected_hand_cards_to_front()
    end
    if self.game and self.game.set_dpad_cursor_for_node then
        self.game:set_dpad_cursor_for_node(inode)
    end
    Sfx.play_random("cardSlide1", "cardSlide2")
    return true
end

--- Prefer cursor card when selected; otherwise first selected card in hand order.
function Hand:reorder_gamepad_step(delta, cursor_node)
    local node
    if cursor_node and self:is_selected(cursor_node) then
        node = cursor_node
    elseif #self.selected > 0 then
        local ordered = self:ordered_selected_nodes()
        node = ordered[1]
    elseif cursor_node then
        node = cursor_node
    end
    if not node then return false end
    return self:reorder_node_step(node, delta)
end

---@param update_visual boolean|nil If true or omitted, VT is set to match T (instant). If false, only T is updated so cards interpolate to new positions.
---@param skip_vt_node Card|nil If set, that node's VT is left unchanged (e.g. animating in from off-screen).
function Hand:layout(update_visual, skip_vt_node)
    local nodes = self.card_nodes
    if #nodes == 0 then return end
    if update_visual == nil then update_visual = true end

    if self.game and self.game.STATE == self.game.STATES.OPEN_BOOSTER and self.game.booster_session and self.game.booster_session.hand_for_tarot then
        self:layout_booster_pack_row(update_visual, skip_vt_node)
        return
    end

    local n = #nodes
    local scale = math.max(MIN_HAND_SCALE, math.min(1, CARDS_AT_FULL_SCALE / n))
    local card_w = CARD_W * scale
    local card_h = CARD_H * scale

    local step = (SCREEN_W - card_w) / math.max(1, n - 1)
    local total_w = n == 1 and card_w or (card_w + (n - 1) * step)
    local start_x = (SCREEN_W - total_w) * 0.5
    local y = SCREEN_H - card_h - HAND_BOTTOM_MARGIN

    for i, node in ipairs(nodes) do
        local x = start_x + (i - 1) * step
        local r = fan_rotation(i, n)
        local card_y = y + arc_drop(i, n, ARC_DROP)
        local placed = set_card_target(node, x, card_y, r, scale)
        local set_vt = placed and update_visual and (skip_vt_node == nil or node ~= skip_vt_node)
        if set_vt then
            node.VT.x = x
            node.VT.y = card_y
            node.VT.r = r
            node.VT.scale = scale
        end
    end
end

--- Compact fan at the top of the bottom screen while resolving Arcana/Spectral boosters (pack choices stay below).
function Hand:layout_booster_pack_row(update_visual, skip_vt_node)
    local nodes = self.card_nodes
    if #nodes == 0 then return end
    if update_visual == nil then update_visual = true end

    local n = #nodes
    local scale = math.max(MIN_HAND_SCALE, math.min(1, CARDS_AT_FULL_SCALE / math.max(n, 1)))
    local card_w = CARD_W * scale
    local card_h = CARD_H * scale

    local step = (SCREEN_W - card_w) / math.max(1, n - 1)
    local total_w = n == 1 and card_w or (card_w + (n - 1) * step)
    local start_x = (SCREEN_W - total_w) * 0.5
    local y = 6

    for i, node in ipairs(nodes) do
        local x = start_x + (i - 1) * step
        local r = fan_rotation(i, n)
        -- Shallower than the hand's: this row sits under the pack's choices, not on its own.
        local card_y = y + arc_drop(i, n, ARC_DROP * 0.35)
        local placed = set_card_target(node, x, card_y, r, scale)
        local set_vt = placed and update_visual and (skip_vt_node == nil or node ~= skip_vt_node)
        if set_vt then
            node.VT.x = x
            node.VT.y = card_y
            node.VT.r = r
            node.VT.scale = scale
        end
    end
end

function Hand:clear()
    for _, node in ipairs(self.card_nodes) do
        self.game:remove(node)
    end
    for _, node in ipairs(self._destroying_nodes) do
        self.game:remove(node)
    end
    self.cards = {}
    self.card_nodes = {}
    self.selected = {}
    self._draw_queue = {}
    self._draw_timer = 0
    self._destroying_nodes = {}
    -- A pending discard resume must not survive a hand reset; its nodes are gone.
    self._pending_discard_finish = nil
    self._materializing_nodes = {}
    self._play_sequence = nil
    self._deal_n = nil
    self._deal_i = nil
end

--- Return every card in the hand and draw queue back to the deck draw pile (not discard).
function Hand:return_all_cards_to_deck_draw_pile()
    self:sync_cards_from_nodes()
    local deck = self.game and self.game.deck
    if not deck or not deck.insert_random then
        self:clear()
        return
    end
    for _, c in ipairs(self._draw_queue or {}) do
        deck:insert_random(c)
    end
    for _, c in ipairs(self.cards) do
        deck:insert_random(c)
    end
    self:clear()
end

--- Detach every card node from the hand and return them as flight entries for
--- `Game.pending_discard`, targeting the deck's off-screen origin so a beaten blind's hand
--- visibly un-deals instead of popping out. The reference peels the hand off through the same
--- per-card `draw_card` queue it dealt with, hand-to-discard at a 0.07 s beat with the pitch
--- ladder running downward (`state_events.lua:237-250`, `:1126`; `common_events.lua:389`).
--- `self.cards` is left intact for the deck recycle; the caller owns the returned entries.
function Hand:take_undeal_flights()
    self:sync_cards_from_nodes()
    local nodes = self.card_nodes
    self.card_nodes = {}
    self.selected = {}
    if self.game then self.game.active_tooltip_card = nil end
    local flights = {}
    local n = #nodes
    local t = (self.game and self.game.discard_timer) or 0
    for i, node in ipairs(nodes) do
        node.selected = false
        flights[#flights + 1] = {
            node = node,
            fly_after = t + (i - 1) * UNDEAL_RELEASE_INTERVAL,
            percent = 1 - fan_percent(i, n),
            target = { x = OFFSCREEN_START_X, y = OFFSCREEN_START_Y, r = 0 },
        }
    end
    return flights
end

--- Push every card still in the hand (and queued draws) to the deck discard pile, then clear hand nodes. Used when a blind is beaten.
function Hand:send_entire_hand_to_discard_pile()
    self:sync_cards_from_nodes()
    local deck = self.game and self.game.deck
    if not deck or not deck.push_discard then
        self:clear()
        return
    end
    for _, c in ipairs(self._draw_queue or {}) do
        deck:push_discard(c)
    end
    for i = 1, #self.cards do
        deck:push_discard(self.cards[i])
    end
    self:clear()
end

--- Selected cards in left-to-right hand order (card_nodes index), not toggle order.
function Hand:ordered_selected_nodes()
    local sel = {}
    for _, n in ipairs(self.selected) do
        sel[n] = true
    end
    local out = {}
    for _, node in ipairs(self.card_nodes) do
        if sel[node] then
            table.insert(out, node)
        end
    end
    return out
end

function Hand:is_selected(node)
    for _, n in ipairs(self.selected) do
        if n == node then return true end
    end
    return false
end

function Hand:selection_at_capacity()
    return #self.selected >= MAX_SELECTED
end

function Hand:toggle_selection(node)
    if self._play_sequence then return end
    if not node or not self.game then return end
    for i, n in ipairs(self.selected) do
        if n == node then
            if self.game and self.game.get_active_boss_blind_id and self.game:get_active_boss_blind_id() == "bl_final_bell" then
                local forced_uid = self.game.boss_runtime and self.game.boss_runtime.forced_card_uid
                local uid = node.card_data and node.card_data.uid
                if forced_uid ~= nil and uid == forced_uid then
                    return
                end
            end
            node.selected = false
            -- Retarget so the card drops back into the fan on the spring rather than at draw
            -- time. `false` leaves VT alone, which is what lets it animate.
            self:layout(false)
            -- The pick/unpick pop the reference gives every (de)selection (`card.lua:4314`).
            if node.juice_up then node:juice_up(0.05, 0.03) end
            -- Deselecting is silent. `CardArea:remove_from_highlighted`
            -- (`cardarea.lua:187-200`) plays nothing, and `card3` had no `play_sound` site
            -- anywhere in the reference (the asset is no longer shipped) — the pitched
            -- ramp this used to run was
            -- `highlight_card`, which belongs to the scoring lift, not to clicking a card.
            table.remove(self.selected, i)
            if self.game then
                if not (self.game.is_card_select_mode and self.game:is_card_select_mode()) then
                    self.game.active_tooltip_card = nil
                end
            end
            if self.game.move_selected_hand_cards_to_front then self.game:move_selected_hand_cards_to_front() end
            self:calculate_play()
            return
        end
    end
    if #self.selected >= MAX_SELECTED then return end
    node.selected = true
    self:layout(false)
    if node.juice_up then node:juice_up(0.05, 0.03) end
    -- One flat click per pick: `add_to_highlighted` plays `cardSlide1` with no pitch argument
    -- (`cardarea.lua:140`).
    Sfx.play("cardSlide1")
    table.insert(self.selected, node)
    if self.game then
        if not (self.game.is_card_select_mode and self.game:is_card_select_mode()) then
            self.game.active_tooltip_card = node
            self.game.active_tooltip_joker = nil
        end
    end
    if self.game.move_selected_hand_cards_to_front then self.game:move_selected_hand_cards_to_front() end
    self:calculate_play()
end

function Hand:has_selection()
    return #self.selected > 0
end

function Hand:clear_selection()
    for _, n in ipairs(self.selected) do
        if n then n.selected = false end
    end
    self.selected = {}
    -- Retarget so the cards drop back out of the selection lift on the spring. Without this the
    -- run state is deselected but `Hand:layout` never re-runs, so every card a tarot was used on
    -- stays visually raised until something else disturbs the fan.
    self:layout(false)
    if self.game then
        self.game.active_tooltip_card = nil
    end
    if self.game and self.game.move_selected_hand_cards_to_front then
        self.game:move_selected_hand_cards_to_front()
    end
    self:calculate_play()
end

function Hand:discard_selected()
    if self._play_sequence or self._pending_discard_finish then return end
    if #self.selected == 0 or not self.game or G.discards <= 0 then return end
    local discard_cost = self.game.challenge_modifiers and tonumber(self.game.challenge_modifiers.discard_cost)
    if discard_cost and discard_cost > 0 then
        -- The cost is allowed to take the player below zero; Credit Card follows
        -- the same affordability rule for shop purchases (reference state_events.lua:433-434).
        G.money = (tonumber(G.money) or 0) - discard_cost
    end
    G.discards = G.discards - 1
    -- `ease_discard` rings a chip as the counter moves (`common_events.lua:137`).
    Sfx.play("chips2")
    if self.game and self.game.check_unlock then
        local discarded = {}
        for _, node in ipairs(self.selected or {}) do
            if node and node.card_data then discarded[#discarded + 1] = node.card_data end
        end
        -- `state_events.lua:431` fires this with the cards that were let go.
        self.game:check_unlock("discard_custom", { cards = discarded })
    end
    self:_discard_selected_impl("discard")
end

--- Internal discard used after play sequence (or directly when not scoring).
---@param reason string|nil
---@param opts table|nil `{ skip_events = true }` skips joker/card discard events (e.g. Psychic void).
function Hand:_discard_selected_impl(reason, opts)
    if not self.game then return end
    opts = type(opts) == "table" and opts or {}
    local skip_events = opts.skip_events == true
    self:sync_cards_from_nodes()
    -- Played cards may have been destroyed during scoring (e.g. Sixth Sense); still finish the play.
    if #self.selected == 0 then
        if reason == "play" then
            self.game.active_tooltip_card = nil
            self:layout(false)
            if self.game.restore_hand_draw_order then
                self.game:restore_hand_draw_order()
            end
            if self.game.boss_after_discard_or_play then
                self.game:boss_after_discard_or_play(reason)
            end
            if self.game.boss_after_play_before_draw then
                self.game:boss_after_play_before_draw()
            end
            self:fill_from_deck()
            if self.game.boss_on_hand_refilled then
                self.game:boss_on_hand_refilled(false, reason)
            end
            self:calculate_play()
        end
        return
    end
    -- Glass rolls only for scoring, non-debuffed cards (`reference/Balatro/functions/state_events.lua:961`).
    if reason == "play" and not skip_events then
        local to_try = {}
        for _, node in ipairs(self.selected) do
            if node and node.counts_for_play_score == true
                and node.debuffed_for_scoring ~= true and node.debuffed ~= true then
                to_try[#to_try + 1] = node
            end
        end
        for _, node in ipairs(to_try) do
            if node and node.enhancement == "glass" and self.game.do_random and self.game:do_random(1, 4, 1, "glass") then
                -- The shatter is two layers: the pane and a body hit under it
                -- (`reference/Balatro/card.lua:2104`).
                Sfx.play_glass_break(0.9 + sfx_jitter() * 0.2, 0.5)
                Sfx.play("generic1", 0.9 + sfx_jitter() * 0.2, 0.5)
                if self.game.emit_joker_event then
                    self.game:emit_joker_event("glass_broken")
                end
                self:destroy_card_node(node, true)
            end
        end
    end
    local deck = self.game.deck
    local discarded_nodes = {}
    local discarded_cards = {}
    if deck and deck.push_discard then
        for _, node in ipairs(self.selected) do
            local pushed = false
            for i, n in ipairs(self.card_nodes) do
                if n == node then
                    table.insert(discarded_nodes, node)
                    table.insert(discarded_cards, self.cards[i])
                    deck:push_discard(self.cards[i])
                    pushed = true
                    break
                end
            end
            if not pushed and node and node.card_data then
                table.insert(discarded_nodes, node)
                table.insert(discarded_cards, node.card_data)
                deck:push_discard(node.card_data)
            end
        end
    end
    local selected_set = {}
    for _, n in ipairs(self.selected) do selected_set[n] = true end
    if not skip_events and self.game and self.game.emit_joker_event then
        local dctx = {
            event = "on_discard",
            event_name = "on_discard",
            discarded_nodes = discarded_nodes,
            discarded_cards = discarded_cards,
            discard_reason = reason,
        }
        -- A player-initiated discard is the reference's `context.discard` pass, and its
        -- status events are blocking: Burnt Joker's level-up, Ramen shrinking, Hit the Road
        -- and Yorick each own a beat (`state_events.lua:395-430`). Hold the rest of the
        -- discard until the batch drains rather than resolving it all in one frame. Only
        -- this path staggers -- every on_discard joker gates on `discard_reason ==
        -- "discard"`, so the play-cleanup and boss-forced paths have nothing to announce.
        if reason == "discard" and self.game.begin_joker_emit
            and self.game:begin_joker_emit("on_discard", dctx) then
            self._pending_discard_finish = {
                reason = reason,
                skip_events = skip_events,
                discarded_nodes = discarded_nodes,
                discarded_cards = discarded_cards,
                selected_set = selected_set,
            }
            return
        end
        if not (reason == "discard" and self.game.begin_joker_emit) then
            self.game:emit_joker_event("on_discard", dctx)
        end
    end
    self:_finish_discard(reason, skip_events, discarded_nodes, discarded_cards, selected_set)
end

--- The half of a discard that runs once the `on_discard` joker batch has finished: the
--- per-card discard events, removal from the hand, the flight queue and the refill.
---@param reason string|nil
---@param skip_events boolean
---@param discarded_nodes table[]
---@param discarded_cards table[]
---@param selected_set table<table, boolean>
function Hand:_finish_discard(reason, skip_events, discarded_nodes, discarded_cards, selected_set)
    if reason == "discard" and not skip_events then
        if self.game.record_cards_discarded then
            self.game:record_cards_discarded(#discarded_nodes)
        end
        for _, node in ipairs(discarded_nodes) do
            if node and node.emit_hand_event then
                node:emit_hand_event("on_discard", {
                    event = "on_discard",
                    event_name = "on_discard",
                    discard_reason = reason,
                    discarded_nodes = discarded_nodes,
                    discarded_cards = discarded_cards,
                    card_node = node,
                })
            end
        end
    end
    local new_cards, new_nodes = {}, {}
    for i, node in ipairs(self.card_nodes) do
        if not selected_set[node] then
            table.insert(new_cards, self.cards[i])
            table.insert(new_nodes, node)
        end
    end
    self.cards = new_cards
    self.card_nodes = new_nodes
    -- Cards leave one at a time, on the same beat they left on to be played: the reference
    -- discards through the same per-card `draw_card` queue (`state_events.lua:420`). `Game`
    -- launches each one when its beat comes round; until then it sits where it was.
    local t = self.game.discard_timer or 0
    for i, node in ipairs(self.selected) do
        node.selected = false
        local fly_after = t + (i - 1) * PLAY_RELEASE_INTERVAL
        table.insert(self.game.pending_discard, {
            node = node,
            fly_after = fly_after,
            percent = fan_percent(i, #self.selected),
        })
    end
    self.selected = {}
    if self.game then self.game.active_tooltip_card = nil end
    self:layout(false)
    if self.game.restore_hand_draw_order then
        self.game:restore_hand_draw_order()
    end
    if self.game and self.game.boss_after_discard_or_play then
        self.game:boss_after_discard_or_play(reason)
    end
    if reason == "play" and self.game and self.game.boss_after_play_before_draw then
        self.game:boss_after_play_before_draw()
    end
    self:fill_from_deck()
    if self.game and self.game.boss_on_hand_refilled then
        self.game:boss_on_hand_refilled(false, reason)
    end
    self:calculate_play()
end

--- Insert a duplicate of the card at index (shallow copy of card data). Returns the new Card node or nil.
---@param index integer
---@return Card|nil
function Hand:duplicate_card_at_index(index)
    if not self.game then return nil end
    local cd = self.cards[index]
    if not cd then return nil end
    local copy = Deck.copy_card_data(cd)
    if not copy then return nil end
    copy.uid = nil
    local node = self:add_card(copy)
    if node then
        self:start_card_materialize(node)
        Card.play_materialize_sfx()
    end
    return node
end

--- Create a new hand card from logical `card_data` (rank/suit/extras). Returns the new `Card` node or nil if full.
---@param card_data table
---@return Card|nil
function Hand:create_card(card_data)
    local node = self:add_card(card_data)
    if node then
        self:start_card_materialize(node)
        Card.play_materialize_sfx()
    end
    return node
end

--- Destroy a hand card: removed from the game entirely (no discard pile). Use `discard_card_at_index` to send to the discard pile instead.
---@param index integer
---@param silent boolean|nil skip the dissolve cue because the caller plays its own (a glass shatter)
---@return boolean
function Hand:destroy_card_at_index(index, silent)
    local node = self.card_nodes and self.card_nodes[index]
    local cd = node and node.card_data or (self.cards and self.cards[index])
    local runtime = self.game and self.game.boss_runtime
    if runtime and runtime.forced_card_uid ~= nil and cd and cd.uid == runtime.forced_card_uid then
        -- Cerulean Bell: destroying the forced card frees selection for this hand (no re-pick until refill).
        runtime.forced_card_uid = nil
    end
    -- Only the destroy path gets the cue: `remove_card_at_index` is shared with discarding,
    -- which already has its own sound.
    local removed = self:remove_card_at_index(index, true)
    if removed and not silent then Card.play_dissolve_sfx() end
    return removed
end

--- Same as `destroy_card_at_index`, but by `Card` node reference.
---@param node Card|nil
---@param silent boolean|nil skip the dissolve cue because the caller plays its own
---@return boolean
function Hand:destroy_card_node(node, silent)
    if not node then return false end
    for i, n in ipairs(self.card_nodes) do
        if n == node then
            return self:destroy_card_at_index(i, silent)
        end
    end
    return false
end

--- Send one hand card to the discard pile, then remove it from the hand (same logical outcome as discarding). Destroy/break effects must use `destroy_card_*` instead.
---@param index integer
---@param opts table|nil `{ hook = true }` identifies The Hook's forced discard.
---@return boolean
function Hand:discard_card_at_index(index, opts)
    if not self.game then return false end
    local deck = self.game.deck
    local node = self.card_nodes[index]
    local cd = self.cards[index]
    if not node or not cd then return false end
    if opts and opts.hook == true and self.game.emit_joker_event then
        -- The Hook follows the discard event path, but Burnt Joker explicitly ignores it
        -- (`reference/Balatro/card.lua:2749-2755`).
        local discard_ctx = {
            event = "on_discard",
            event_name = "on_discard",
            discarded_nodes = { node },
            discarded_cards = { cd },
            discard_reason = "discard",
            hook = true,
        }
        self.game:emit_joker_event("on_discard", discard_ctx)
        -- The card's own seal fires too: the reference routes the forced discard through
        -- `discard_cards_from_highlighted` (`blind.lua:466-484`), which reaches
        -- `calculate_seal{discard = true}` (`state_events.lua:400`), so a Purple Seal makes
        -- its Tarot whether the player chose the discard or The Hook did.
        if node.emit_hand_event then
            discard_ctx.card_node = node
            node:emit_hand_event("on_discard", discard_ctx)
        end
    end
    if deck and deck.push_discard then
        deck:push_discard(cd)
    end
    return self:remove_card_at_index(index)
end

--- Remove a card from the hand by index without sending it to the discard pile (destroyed / gone from the run).
---@param index integer
---@return boolean
function Hand:remove_card_at_index(index, retain_destroy_visual)
    if not self.game then return false end
    local node = self.card_nodes[index]
    local cd = self.cards[index]
    if not node or not cd then return false end

    for i, sel in ipairs(self.selected) do
        if sel == node then
            table.remove(self.selected, i)
            break
        end
    end
    node.selected = false
    if retain_destroy_visual then
        self:start_card_dissolve(node)
    else
        self.game:remove(node)
    end
    table.remove(self.cards, index)
    table.remove(self.card_nodes, index)
    if self.game.emit_on_destroy_cards and Deck and Deck.copy_card_data then
        local snap = Deck.copy_card_data(cd)
        if snap then
            self.game:emit_on_destroy_cards({ snap })
        end
    end
    if self.game.active_tooltip_card == node then
        self.game.active_tooltip_card = nil
    end
    self:layout(false)
    if self.game.restore_hand_draw_order then
        self.game:restore_hand_draw_order()
    end
    self:calculate_play()
    return true
end

--- Work out where each played card is headed and stash it on the node. Nothing moves yet:
--- `release_play_card` is what hands a card its target, one at a time.
---
--- The reference does not launch a played hand as a block. Each card is its own blocking
--- `draw_card` event at the queue's 0.1 s beat (`state_events.lua:483`), so the cards peel out
--- of the hand left to right and arrive in the same order - the ripple is the animation.
function Hand:layout_play_cards_at_center(nodes)
    local n = #nodes
    if n == 0 then return end
    local scale = PLAY_CENTER_SCALE
    local card_w = CARD_W * scale
    local card_h = CARD_H * scale
    local max_step = (SCREEN_W - card_w) / math.max(1, n - 1)
    local step = n == 1 and 0 or math.min(74 * scale, max_step)
    local total_w = n == 1 and card_w or (card_w + (n - 1) * step)
    local start_x = (SCREEN_W - total_w) * 0.5
    local y = math.floor(SCREEN_H * 0.25) - card_h * 0.5
    for i, node in ipairs(nodes) do
        -- Every card lands at the low row; the scoring subset is lifted afterwards, card by
        -- card, in the sequencer's highlight phase (`state_events.lua:602-605`). Landing the
        -- scoring cards pre-lifted skipped the beat where the player reads the hand.
        node._play_target = {
            x = start_x + (i - 1) * step,
            y = y + math.floor(card_h * 0.3),
            scale = scale,
        }
        if node.counts_for_play_score == true then
            node._score_lift_y = y
        else
            node._score_lift_y = nil
        end
    end
end

--- Send one card on its way to the play area.
function Hand:release_play_card(node)
    local target = node and node._play_target
    if not target then return end
    node._play_target = nil
    node.T.x = target.x
    node.T.y = target.y
    node.T.r = 0
    node.T.scale = target.scale
    -- The hand's layout no longer owns this card; drop the sway anchor so `apply_idle_sway`
    -- does not drag it back down into the fan on the next frame.
    node._layout_base = nil
    -- The cue every card entering an area gets in the reference, pitched by its place in the
    -- sweep (`common_events.lua:416`).
    Sfx.play("card1", 0.85 + 0.2 * (node._play_release_percent or 0.5), 0.6)
end

---@param immediate boolean|nil If true, move all queued draws into the hand in this call (no per-frame delay).
function Hand:fill_from_deck(immediate)
    local deck = self.game and self.game.deck
    if not deck then return end
    local limit = hand_size_limit()
    local current_count = #self.cards + #self._draw_queue
    -- The Serpent draws a flat count instead of topping the hand back up.
    local forced_draws = self.game and self.game.boss_consume_serpent_draws
        and self.game:boss_consume_serpent_draws() or nil
    if forced_draws then
        limit = current_count + forced_draws
    end
    -- The fan-out ramp is carried as a counter set up front rather than recomputed from a
    -- queue that is already draining.
    -- Topping up mid-drain lengthens the sweep instead of restarting it.
    local batch = math.min(math.max(0, limit - current_count), deck:size())
    if batch > 0 then
        self._deal_n = (self._deal_n or 0) + batch
        self._deal_i = self._deal_i or 0
        -- Every reference deal -- round-opening and mid-round refill alike -- sits on a
        -- `delay(0.3)` before the first `draw_card` fires (`state_events.lua:369`). Priming
        -- the timer negative reproduces that breath; a top-up while a deal is already
        -- draining keeps the running beat instead.
        if not immediate and #self._draw_queue == 0 then
            self._draw_timer = -DEAL_LEAD_IN
        end
    end
    while #self.cards + #self._draw_queue < limit and not deck:empty() do
        local card = deck:draw()
        if card then
            -- `draw_card` is an Event with its normal 0.1 TOTAL-clock delay even for the
            -- opening hand (`reference/functions/common_events.lua:386-423`). Starting the
            -- first card synchronously made an opening deal lead its reference cadence by a
            -- whole beat, particularly noticeable at 4x.
            table.insert(self._draw_queue, card)
        end
    end
    if immediate then
        self:flush_draw_queue()
    end
end

--- Land every queued draw right now. The dealing animation is skippable, not load-bearing:
--- anything that acts on "the hand" (a pack tarot used mid-deal) must see all of it.
function Hand:flush_draw_queue()
    local had_queue = #self._draw_queue > 0
    while #self._draw_queue > 0 do
        local card = table.remove(self._draw_queue, 1)
        if card then self:add_card(card) end
    end
    self._deal_n = nil
    self._deal_i = nil
    if had_queue then self:_notify_deal_complete() end
end

--- The deal that was in flight has finished landing. The reference's per-card draw event is
--- what `Blind:drawn_to_hand` hangs off (`blind.lua:571`), and the bosses that read the hand as
--- a whole -- Cerulean Bell picking the card it forces -- need the finished hand, not the one
--- that was there when the refill was ordered.
function Hand:_notify_deal_complete()
    if self.game and self.game.boss_on_hand_deal_complete then
        self.game:boss_on_hand_deal_complete()
    end
end

function Hand:_cards_reached_play_targets(nodes)
    for _, node in ipairs(nodes) do
        local dx = math.abs((node.VT.x or 0) - (node.T.x or 0))
        local dy = math.abs((node.VT.y or 0) - (node.T.y or 0))
        if dx > PLAY_MOVE_ARRIVE_EPS or dy > PLAY_MOVE_ARRIVE_EPS then
            return false
        end
    end
    return true
end

--- Build a map of lower hand types contained by these cards.
--- Example: a Flush with rank pattern 2,2,1 will contain Pair and Two Pair.
function Hand:build_contained_hand_types(nodes)
    local contained = {}
    if type(nodes) ~= "table" then return contained end

    local cached = self._last_play_hand_flags
    local use_cached = false
    if type(cached) == "table" and type(cached.nodes) == "table" and #cached.nodes == #nodes then
        use_cached = true
        for i = 1, #nodes do
            if cached.nodes[i] ~= nodes[i] then
                use_cached = false
                break
            end
        end
    end

    local pairs_count = 0
    local max_of_a_kind = 0
    local flush = false
    local straight = false
    if use_cached then
        pairs_count = tonumber(cached.pairs_count) or 0
        max_of_a_kind = tonumber(cached.max_of_a_kind) or 0
        flush = cached.flush == true
        straight = cached.straight == true
    end

    local rank_counts = {}
    local suit_counts = {}
    local wild_count = 0
    local n = 0

    for _, node in ipairs(nodes) do
        local data = (node and node.card_data) or {}
        local rank = data.rank
        local suit = data.suit
        local enhancement = data.enhancement
        -- Stone Cards are rankless/suitless (reference/Balatro/card.lua:957-981).
        if rank ~= nil then
            rank_counts[rank] = (rank_counts[rank] or 0) + 1
        end
        if enhancement == "wild" then
            wild_count = wild_count + 1
        elseif suit ~= nil then
            suit_counts[suit] = (suit_counts[suit] or 0) + 1
        end
        n = n + 1
    end

    if not use_cached then
        for _, c in pairs(rank_counts) do
            if c > max_of_a_kind then max_of_a_kind = c end
            if c == 2 then pairs_count = pairs_count + 1 end
        end
        if n > 0 then
            if wild_count == n then
                flush = true
            else
                local suit_kinds = 0
                local max_suit_count = 0
                for _, c in pairs(suit_counts) do
                    suit_kinds = suit_kinds + 1
                    if c > max_suit_count then max_suit_count = c end
                end
                local required = self.game and self.game:hasJoker("j_four_fingers") and 4 or 5
                flush = max_suit_count + wild_count >= required
            end
        end
    end

    if max_of_a_kind >= 2 then contained["Pair"] = true end
    if pairs_count >= 2 or (max_of_a_kind >= 3 and pairs_count >= 1) then
        contained["Two Pair"] = true
    end
    if max_of_a_kind >= 3 then contained["Three of a Kind"] = true end
    if max_of_a_kind >= 4 then contained["Four of a Kind"] = true end
    if flush then contained["Flush"] = true end
    if straight then contained["Straight"] = true end

    return contained
end

local function printTable(t, level, seen)
    level = level or 0
    seen = seen or {}
    if type(t) == "table" then
        if seen[t] then io.write(" {*circular*}") return end
        seen[t] = true
        print(string.rep("\t", level) .. "{")
        for k, v in pairs(t) do
            io.write(string.rep("\t", level + 1), tostring(k), " = ")
            printTable(v, level + 1, seen)
        end
        print(string.rep("\t", level) .. "}")
    else
        print(tostring(t))
    end
end


--- After one played-card trigger (including jokers), advance repeat counter or move to next card.
--- A normal card-to-card transition keeps a small delay; the extra pause is only added when a delayed joker batch ran.
local function hand_advance_play_trigger(seq, add_delay)
    add_delay = add_delay ~= false
    seq.play_rep = (tonumber(seq.play_rep) or 0) + 1
    if seq.play_rep > (tonumber(seq.play_rep_total) or 1) then
        seq.play_rep = nil
        seq.play_rep_total = nil
    end
    if add_delay then
        seq.trigger_wait = (seq.trigger_wait or 0) + PLAY_TRIGGER_INTERVAL
    end
end

function Hand:_update_play_sequence(dt)
    local seq = self._play_sequence
    if not seq then return end
    if seq.phase == "move_center" then
        -- Cards peel out of the hand on the card-cadence clock so the release stagger
        -- survives 4x (`Game:card_beat_dt`); the scoring beats that follow stay on the
        -- scaled clock -- speeding those up is what the game-speed setting is for.
        seq.timer = seq.timer
            + ((self.game and self.game.card_beat_dt) and self.game:card_beat_dt(dt) or dt)
    else
        seq.timer = seq.timer + dt
    end

    if seq.phase == "move_center" then
        local n = #seq.cards
        local released = seq.release_i or 0
        while released < n and seq.timer >= released * PLAY_RELEASE_INTERVAL do
            released = released + 1
            self:release_play_card(seq.cards[released])
        end
        seq.release_i = released
        if released < n then return end

        -- Settling time is measured from the last card leaving, not from the first.
        local settle = seq.timer - (n - 1) * PLAY_RELEASE_INTERVAL
        if (settle >= PLAY_MOVE_MIN_TIME and self:_cards_reached_play_targets(seq.cards))
            or settle >= PLAY_MOVE_MAX_TIME then
            if seq.voided then
                -- Nothing lifts, triggers or rings: the cards sit at centre and the total
                -- lands as zero, which is the whole of a voided hand.
                seq.phase = "finalize"
                seq.finalize_step = 2
                seq.timer = 0
                return
            end
            seq.phase = "highlight"
            seq.timer = 0
            seq.highlight_i = 0
            local hl = {}
            for _, node in ipairs(seq.cards) do
                if node and node._score_lift_y then hl[#hl + 1] = node end
            end
            seq.highlight_cards = hl
        end
    elseif seq.phase == "highlight" then
        -- Lift the scoring cards left to right on a 0.1 s beat with a rising cardSlide1
        -- (`common_events.lua:434-442`), then hold before the first trigger.
        local hl = seq.highlight_cards or {}
        local i = seq.highlight_i or 0
        if i < #hl and seq.timer >= PLAY_HIGHLIGHT_LEAD + i * PLAY_HIGHLIGHT_INTERVAL then
            i = i + 1
            seq.highlight_i = i
            local node = hl[i]
            if node and node._score_lift_y then
                node.T.y = node._score_lift_y
                node._score_lift_y = nil
            end
            Sfx.play("cardSlide1", 0.85 + fan_percent(i, 5) * 0.2)
        end
        if i >= #hl and seq.timer >= PLAY_HIGHLIGHT_LEAD + #hl * PLAY_HIGHLIGHT_INTERVAL then
            -- The reference runs its `before` joker pass here: after the scoring cards are
            -- lifted and the hand text is set, before any card is scored
            -- (`reference/Balatro/functions/state_events.lua:600-637`).
            seq.phase = "before_jokers"
            seq.timer = 0
            seq.highlight_cards = nil
        end
    elseif seq.phase == "before_jokers" then
        -- `before_ctx` is consumed on the first visit; a visit with no context means the
        -- staggered batch has finished (or there was nothing to run) and scoring may start.
        local bctx = seq.before_ctx
        seq.before_ctx = nil
        if bctx then
            if G and G.begin_joker_emit then
                if G:begin_joker_emit("on_hand_played", bctx) then
                    seq.phase = "wait_jokers"
                    seq.joker_wait_resume = { phase = "before_jokers" }
                    return
                end
            elseif G and G.emit_joker_event then
                G:emit_joker_event("on_hand_played", bctx)
            end
        end
        seq.phase = "trigger"
        seq.timer = 0
        seq.idx = 0
        seq.trigger_wait = PLAY_ANTICIPATION
        seq.play_rep = nil
        seq.play_rep_total = nil
    elseif seq.phase == "trigger" then
        seq.trigger_wait = (seq.trigger_wait or 0) - dt
        if seq.trigger_wait <= 0 then
            -- The scored card owns the first blocking status beat. Evaluate its jokers only
            -- after that beat, so the first joker neither overlaps the card nor forces a
            -- redundant delay after the batch (`state_events.lua:680-760`).
            if seq.pending_joker_ctx then
                local jctx = seq.pending_joker_ctx
                seq.pending_joker_ctx = nil
                if G and G.begin_joker_emit then
                    if G:begin_joker_emit("card_played", jctx) then
                        seq.phase = "wait_jokers"
                        seq.joker_wait_resume = {
                            phase = "trigger",
                            advance_play_repeat = true,
                            delay_next_trigger = false,
                        }
                    else
                        -- `begin_joker_emit` already evaluated every candidate while looking
                        -- for a real trigger. Do not dispatch the event a second time: chance
                        -- jokers would otherwise get two rolls on a no-op pass.
                        hand_advance_play_trigger(seq, false)
                    end
                else
                    if G and G.emit_joker_event then
                        G:emit_joker_event("card_played", jctx)
                        G.selectedHandChips = tonumber(jctx.chips) or G.selectedHandChips
                        G.selectedHandMult = tonumber(jctx.mult) or G.selectedHandMult
                    end
                    hand_advance_play_trigger(seq, false)
                end
                return
            end
            if seq.play_rep == nil then
                -- Pick next scored card and start its repeat cycle.
                while true do
                    seq.idx = (tonumber(seq.idx) or 0) + 1
                    if seq.idx > #seq.cards then
                        seq.phase = "inhand_trigger"
                        seq.timer = 0
                        seq.play_rep = nil
                        seq.play_rep_total = nil
                        break
                    end
                    local node = seq.cards[seq.idx]
                    -- A debuffed card is skipped for score but not for attention: the
                    -- reference gives it its own beat and a rejection sting
                    -- (`state_events.lua:792`). It does not move the ladder. Kickers, which
                    -- also fail `counts_for_play_score`, stay silent.
                    if node and node.debuffed_for_scoring == true then
                        node:juice_up(0.6, 0.1)
                        if G and G.shake then G:shake(0.7) end
                        Sfx.play("cancel", Hand.scoring_pitch())
                        seq.trigger_wait = (seq.trigger_wait or 0) + PLAY_TRIGGER_INTERVAL
                        return
                    end
                    if node and node.counts_for_play_score == true then
                        local sources = seq.play_sources or {}
                        for i = #sources, 1, -1 do sources[i] = nil end
                        if node.trigger_sources then
                            node:trigger_sources(false, seq, sources)
                        end
                        seq.play_sources = sources
                        seq.play_rep_total = #sources + 1
                        seq.play_rep = 1
                        seq.play_notice_rep = nil
                        break
                    end
                end
            end

            if seq.phase == "trigger" and seq.play_rep and seq.play_rep_total then
                local node = seq.cards[seq.idx]
                local score_this = node and node.counts_for_play_score == true 

                if node and score_this then
                    -- Every pass past the first was granted by something: give the joker that granted
                    -- it a beat of its own before the card replays. Red Seal (`false`) has no joker to
                    -- point at, so the card simply pops twice.
                    local source = seq.play_rep > 1 and seq.play_sources and seq.play_sources[seq.play_rep - 1]
                    if source and seq.play_notice_rep ~= seq.play_rep then
                        seq.play_notice_rep = seq.play_rep
                        source:juice_up(0.6, 0.1)
                        if G and G.shake then G:shake(0.7) end
                        -- The reference announces a retrigger source with no ladder pitch at
                        -- all, just a small random wobble, so the climb stays legible as the
                        -- card's own line (`common_events.lua:779`).
                        Sfx.play("generic1", 0.98 + sfx_jitter() * 0.04)
                        seq.trigger_wait = (seq.trigger_wait or 0) + RETRIGGER_NOTICE_INTERVAL
                        return
                    end

                    -- One step per pass, before the pass makes any sound: every cue this
                    -- card and its jokers raise shares the new rung.
                    advance_scoring_pitch(seq)
                    node:juice_up(0.6, 0.1)
                    -- Every scoring trigger rattles the room (`common_events.lua:895`).
                    if G and G.shake then G:shake(0.7) end
                    self:play_sfx_trigger()
                    -- Effect boundaries for the beat count below; see PLAY_EFFECT_INTERVAL.
                    -- Sampled rather than restructured: the scoring math is untouched, the
                    -- sequencer just notices how many separate things this card did.
                    local chips_before = tonumber(G.selectedHandChips) or 0
                    local mult_before = tonumber(G.selectedHandMult) or 1
                    local chips, mult = self:accumulate_card_score(
                        tonumber(G.selectedHandChips) or 0,
                        tonumber(G.selectedHandMult) or 1,
                        node,
                        false
                    )
                    G.selectedHandChips = chips
                    G.selectedHandMult = mult
                    -- The card's own modifier mult (Steel, Glass, Lucky) is a second effect.
                    local chips_after_own, mult_after_own = chips, mult

                    local data = (node and node.card_data) or {}
                    chips = tonumber(G.selectedHandChips) or 0
                    mult = tonumber(G.selectedHandMult) or 1
                    local card_ctx = {
                        event = "card_played",
                        rank = data.rank,
                        suit = data.suit,
                        chips = chips,
                        mult = mult,
                        hand_index = G.selectedHand,
                        hand_level = G.selectedHandLevel,
                        card_node = node,
                        photograph_first_face_node = seq.photograph_first_face_node,
                        photograph_pareidolia = seq.photograph_pareidolia,
                    }
                    if node.emit_hand_event then
                        node:emit_hand_event("card_played", card_ctx)
                    end
                    chips = tonumber(card_ctx.chips) or chips
                    mult = tonumber(card_ctx.mult) or mult
                    -- Anything a listener hung on this card is a third.
                    local chips_after_listeners, mult_after_listeners = chips, mult
                    -- `accumulate_card_score` above was told to skip this, so the edition lands
                    -- here, after the card's own listeners. This used to be guarded by an
                    -- undeclared global that was always nil, so the guard never fired and an
                    -- editioned playing card had its bonus applied twice in the animated path.
                    chips, mult = self:apply_playing_card_edition(chips, mult, data)
                    self:announce_playing_card_edition(node, data)
                    G.selectedHandChips = chips
                    G.selectedHandMult = mult

                    local jctx = {
                        event = "card_played",
                        event_name = "card_played",
                        rank = data.rank,
                        suit = data.suit,
                        chips = tonumber(G.selectedHandChips) or 0,
                        mult = tonumber(G.selectedHandMult) or 1,
                        hand_index = G.selectedHand,
                        hand_level = G.selectedHandLevel,
                        card_node = node,
                        shake_card_node = node,
                        photograph_first_face_node = seq.photograph_first_face_node,
                        photograph_pareidolia = seq.photograph_pareidolia,
                    }
                    seq.pending_joker_ctx = jctx
                    -- One beat per effect. The card's chips are the first; its own mult
                    -- modifier, anything its listeners added, and its edition each buy another.
                    seq.trigger_wait = (seq.trigger_wait or 0) + PLAY_TRIGGER_INTERVAL
                    local extra = 0
                    if mult_after_own ~= mult_before then extra = extra + 1 end
                    if chips_after_listeners ~= chips_after_own
                        or mult_after_listeners ~= mult_after_own then
                        extra = extra + 1
                    end
                    if chips ~= chips_after_listeners or mult ~= mult_after_listeners then
                        extra = extra + 1
                    end
                    seq.trigger_wait = seq.trigger_wait + extra * PLAY_EFFECT_INTERVAL
                end
            end
        end
    elseif seq.phase == "wait_jokers" then
        if G and G.joker_emit_busy and G:joker_emit_busy() then
            -- Stagger runs in `Game:update` (`_update_joker_emit_queue`).
        else
            local r = seq.joker_wait_resume
            seq.joker_wait_resume = nil
            if r and r.phase == "trigger" then
                seq.phase = "trigger"
                if r.advance_play_repeat then
                    hand_advance_play_trigger(seq, r.delay_next_trigger == true)
                end
            elseif r and r.phase == "before_jokers" then
                seq.phase = "before_jokers"
                seq.timer = 0
            elseif r and r.phase == "finalize" then
                seq.phase = "finalize"
                seq.finalize_step = r.finalize_step
                seq.timer = 0
            elseif r and r.phase == "inhand_trigger" then
                seq.phase = "inhand_trigger"
                -- Matching the event isn't scoring it: a Queens-only joker still walks every held card.
                -- Hold the beat only when one of them actually did something.
                local c = r.ctx
                local scored = (c and (c._joker_effect_applied or c._joker_effect_created_item)) or r.hand_triggered
                if r.append_held_retriggers then
                    r.append_held_retriggers(scored)
                end
                seq.inhand_wait = scored and PLAY_TRIGGER_INTERVAL or 0
                if scored and r.node and seq.inhand_scored then
                    seq.inhand_scored[r.node] = true
                    seq.inhand_mod_percent = true
                end
            end
        end
    elseif seq.phase == "inhand_trigger" then
        -- After played cards finish triggering, notify cards still held (staggered like play triggers).
        -- Queue is flattened into steps: `node` runs one in-hand trigger pass, `notice` shakes the joker
        -- that granted the retrigger the following pass replays (Mime, or Blueprint copying it).
        if not seq.inhand_queue then
            local played = {}
            for _, n in ipairs(seq.cards) do
                played[n] = true
            end
            local by_node = {}
            for _, node in ipairs(self.card_nodes or {}) do
                if not played[node] and node.card_data then
                    table.insert(by_node, node)
                end
            end
            table.sort(by_node, function(a, b)
                local ax = (a.VT and a.VT.x) or (a.T and a.T.x) or 0
                local bx = (b.VT and b.VT.x) or (b.T and b.T.x) or 0
                return ax < bx
            end)
            local q = {}
            for _, node in ipairs(by_node) do
                q[#q + 1] = { node = node, first_pass = true }
            end
            seq.inhand_queue = q
            seq.inhand_i = 0
            seq.inhand_wait = 0
            seq.inhand_scored = {}
            -- Held cards defer their ladder step by one card. See `inhand_mod_percent` below.
            seq.inhand_last_node = nil
            seq.inhand_mod_percent = false
        end

        seq.inhand_wait = (seq.inhand_wait or 0) - dt
        if seq.inhand_wait > 0 then return end

        local q = seq.inhand_queue
        if seq.inhand_i >= #q then
            seq.inhand_queue = nil
            seq.inhand_i = nil
            seq.inhand_wait = nil
            seq.inhand_scored = nil
            seq.inhand_last_node = nil
            seq.inhand_mod_percent = nil
            -- The last held card's deferred step never lands, exactly as in the reference:
            -- the loop ends and one unconditional step opens the joker section
            -- (`state_events.lua:879`).
            advance_scoring_pitch(seq)
            seq.percent_per_joker = true
            seq.phase = "finalize"
            seq.timer = 0
            seq.finalize_step = nil
            return
        end

        seq.inhand_i = seq.inhand_i + 1
        local step = q[seq.inhand_i]
        if step.notice then
            -- The pass still runs either way (Reserved Parking rerolls on every one of them), but there
            -- is nothing to announce until this card has actually scored something.
            if not (seq.inhand_scored and seq.inhand_scored[step.node]) then return end
            step.notice:juice_up(0.6, 0.1)
            if G and G.shake then G:shake(0.7) end
            Sfx.play("generic1", 0.98 + sfx_jitter() * 0.04)
            seq.inhand_wait = RETRIGGER_NOTICE_INTERVAL
            return
        end

        local node = step.node
        -- A debuffed card in hand is worth nothing to the jokers that read it: the reference
        -- has Baron and Shoot the Moon return a "Debuffed" message instead of their mult when
        -- `context.other_card.debuff` is set (`reference/Balatro/card.lua:3272-3300`), and every
        -- getter the card itself would contribute through bails the same way. It gets no beat,
        -- because the reference's held loop only steps the ladder when something fired.
        if node and node.is_debuffed and node:is_debuffed() then
            seq.inhand_last_node = node
            return
        end
        -- Held cards step the ladder late. The reference (`state_events.lua:783`) raises
        -- `mod_percent` when a held card actually did something, but applies the step at the
        -- top of the *next* card's turn -- so a card's own cues sound at the rung the card
        -- before it left behind. A retrigger pass of the same card is not a new card and
        -- steps immediately, matching the reference's `reps[j] ~= 1` branch.
        if node ~= seq.inhand_last_node then
            if seq.inhand_mod_percent then advance_scoring_pitch(seq) end
            seq.inhand_mod_percent = false
            seq.inhand_last_node = node
        else
            advance_scoring_pitch(seq)
        end
        local ctx = {
            event = "inhand_trigger",
            hand_index = G and G.selectedHand,
            hand_level = G and G.selectedHandLevel,
            chips = tonumber(G and G.selectedHandChips) or 0,
            mult = tonumber(G and G.selectedHandMult) or 1,
            played_cards = seq.cards,
        }
        local triggered = false
        if node and node.emit_hand_event then
            triggered = node:emit_hand_event("held_in_hand", ctx) == true
        end
        G.selectedHandChips = tonumber(ctx.chips) or G.selectedHandChips
        G.selectedHandMult = tonumber(ctx.mult) or G.selectedHandMult

        local data = (node and node.card_data) or {}
        local jctx = {
            event = "card_held",
            event_name = "card_held",
            card_node = node,
            shake_card_node = node,
            rank = data.rank,
            suit = data.suit,
            chips = tonumber(G.selectedHandChips) or 0,
            mult = tonumber(G.selectedHandMult) or 1,
            played_cards = seq.cards,
        }
        local function append_held_retriggers(first_pass_effect_applied)
            if not step.first_pass or not node or not node.trigger_sources then return end
            local sources = {}
            node:trigger_sources(true, seq, sources, first_pass_effect_applied)
            local insert_at = seq.inhand_i + 1
            for _, source in ipairs(sources) do
                if source then
                    table.insert(q, insert_at, { notice = source, node = node })
                    insert_at = insert_at + 1
                end
                table.insert(q, insert_at, { node = node })
                insert_at = insert_at + 1
            end
        end
        -- A card where nothing fired gets no beat at all, so a hand of blanks doesn't stall scoring.
        if G and G.begin_joker_emit and G:begin_joker_emit("card_held", jctx) then
            seq.phase = "wait_jokers"
            seq.joker_wait_resume = {
                phase = "inhand_trigger",
                ctx = jctx,
                node = node,
                hand_triggered = triggered,
                append_held_retriggers = append_held_retriggers,
            }
        elseif triggered then
            seq.inhand_scored[node] = true
            seq.inhand_mod_percent = true
            seq.inhand_wait = PLAY_TRIGGER_INTERVAL
        end
        if not (G and G.joker_emit_busy and G:joker_emit_busy()) then
            append_held_retriggers(triggered)
        end
    elseif seq.phase == "finalize" then
        local chips = tonumber(G.selectedHandChips) or 0
        local mult = tonumber(G.selectedHandMult) or 1

        if seq.finalize_step == nil then
            seq.finalize_step = 1
        end

        -- Step 1: single scored-hand joker event.
        if seq.finalize_step == 1 then
            local hand_type = nil
            if G and G.handlist and G.selectedHand and G.handlist[G.selectedHand] then
                hand_type = G.handlist[G.selectedHand]
            end
            hand_type = hand_type or tostring(G.selectedHand or "unknown")
            local free_joker_slots = 0
            if G then
                local cap = tonumber(G.joker_capacity) or tonumber(G.joker_slot_count) or 0
                local used = (type(G.jokers) == "table") and #G.jokers or 0
                free_joker_slots = math.max(0, cap - used)
            end
            local scored_cards = {}
            for _, node in ipairs(seq.cards or {}) do
                if node and node.counts_for_play_score == true then
                    scored_cards[#scored_cards + 1] = node
                end
            end
            local ctx = {
                event = "on_hand_scored",
                event_name = "on_hand_scored",
                chips = chips,
                mult = mult,
                hand_index = G.selectedHand,
                hand_type = hand_type,
                contains_hand_types = self:build_contained_hand_types(scored_cards),
                hand_level = G.selectedHandLevel,
                cards = scored_cards,
                full_hand = seq.cards,
                played_cards = seq.cards,
                free_joker_slots = free_joker_slots,
                discards_left = tonumber(G and G.discards) or 0,
            }
            if G and G.begin_joker_emit then
                local pause = G:begin_joker_emit("on_hand_scored", ctx)
                if pause then
                    seq.phase = "wait_jokers"
                    seq.joker_wait_resume = { phase = "finalize", finalize_step = 2 }
                    seq.timer = 0
                    return
                end
            elseif G and G.emit_joker_event then
                G:emit_joker_event("on_hand_scored", ctx)
            end
            seq.finalize_step = 2
        end

        -- Step 2: the total lands. The reference holds 0.4 s after the last trigger before
        -- the button thunk (`state_events.lua:1029`), then a further 0.8 s before the chip
        -- commit sting (`state_events.lua:1038`) — "thunk … ka-ching", never one frame.
        if seq.finalize_step == 2 and seq.timer >= 0.4 then
            chips = math.max(tonumber(G.selectedHandChips) or 0, 0)
            mult = math.max(tonumber(G.selectedHandMult) or 1, 0)

            if G.challenge_modifiers and G.challenge_modifiers.chips_dollar_cap == true then
                chips = math.min(chips, math.max(0, tonumber(G.money) or 0))
            end

            if (G._deck_special or nil) == "plasma" and not seq.voided then
                local avg = math.floor((chips + mult)/2)
                chips = avg
                mult = avg
                -- Three layers, not one full-volume gong (`back.lua:134-136`).
                Sfx.play("gong", 0.94, 0.3)
                Sfx.play("gong", 0.94 * 1.5, 0.2)
                Sfx.play("tarot1", 1.5)
            end

            G.selectedHandChips = chips
            G.selectedHandMult = mult

            Sfx.play_button(0.9, 0.6)
            seq.final_score = math.floor(chips * mult)
            -- The panels zero out and the product moves to the total readout with the thunk
            -- (`state_events.lua:1029-1032`); TopUI pulses and later drains it.
            G.selectedHandChips = 0
            G.selectedHandMult = 0
            G.chip_total_display = seq.final_score > 0 and seq.final_score or nil
            seq.finalize_step = 3
            seq.timer = 0
        end

        -- Step 3: chip commit, after the reference's 0.8 s hold.
        if seq.finalize_step == 3 and seq.timer >= 0.8 then
            local final_score = seq.final_score or 0
            if final_score > 0 then
                Sfx.play("chips2")
                -- Start the total's 0.5 s drain in step with the score count-up.
                G.chip_total_drain = true
            end
            G.last_hand_score = final_score
            G.round_score = (G.round_score or 0) + final_score
            if G.record_hand_score then
                G:record_hand_score(final_score)
            end
            if G.record_career_best then
                G:record_career_best("c_best_hand_chips", final_score)
                G:check_unlock("chip_score", { chips = final_score })
            end
            seq.finalize_step = 4
            seq.timer = 0
        end

        -- Step 4: the reference's `after` pass, which runs once the score has landed
        -- (`state_events.lua:1063-1070`). Ice Cream melts and Seltzer drains here, not
        -- during scoring.
        if seq.finalize_step == 4 then
            if not seq.voided and G and G.begin_joker_emit then
                local actx = {
                    event = "on_hand_after",
                    event_name = "on_hand_after",
                    cards = seq.cards,
                    full_hand = seq.cards,
                    hand_index = G.selectedHand,
                }
                if G:begin_joker_emit("on_hand_after", actx) then
                    seq.phase = "wait_jokers"
                    seq.joker_wait_resume = { phase = "finalize", finalize_step = 5 }
                    seq.timer = 0
                    return
                end
            end
            seq.finalize_step = 5
        end

        if seq.finalize_step == 5 then
            seq.phase = "discard_wait"
            seq.timer = 0
        end
    elseif seq.phase == "discard_wait" then
        if seq.timer >= PLAY_AFTER_SCORE_PAUSE then
            for _, node in ipairs(seq.cards) do
                node.scoring_center = false
            end
            self._play_sequence = nil
            self:_discard_selected_impl("play")
            if G and G.evaluate_blind_progress then
                G:evaluate_blind_progress()
            end
        end
    end
end

--- Breathe the hand.
---
--- The reference rewrites every card's target transform every frame with two slow sines folded
--- in (`cardarea.lua:454`), phase-shifted by the card's own x. Because these move `T` and not
--- `VT`, the spring is always chasing and never arrives, which is the whole point: a Balatro
--- hand at rest is still moving. Cards that the layout does not own - dragged, or flown out to
--- the play area - are left alone, exactly as the reference skips `states.drag.is`.
function Hand:apply_idle_sway()
    local t = (G and G.TIMERS and G.TIMERS.REAL) or 0
    for _, node in ipairs(self.card_nodes) do
        local base = node._layout_base
        if base and not (node.states and node.states.drag and node.states.drag.is) then
            local phase = base.x * SWAY_PHASE_PER_PX
            node.T.r = base.r + SWAY_R_AMP * math.sin(SWAY_R_RATE * t + phase)
            node.T.y = base.y + SWAY_Y_AMP * math.sin(SWAY_Y_RATE * t + phase)
        end
    end
end

local function visual_random()
    if love and love.math and love.math.random then return love.math.random() end
    return 0.5
end

--- Keep destruction feedback shader-free: the 3DS backend cannot run the reference's
--- dissolve fragment shader, so retained card ghosts and bounded primitive shards preserve
--- the timing without allocating in frame paths (reference/Balatro/card.lua:2130-2180).
function Hand:start_card_dissolve(node)
    if not node then return end
    -- Timing, the override rule and the pop all live on Moveable, shared with destroyed
    -- Jokers and used consumables.
    if node._card_lifecycle and node._card_lifecycle.kind == "dissolve" then return end
    node:begin_lifecycle("dissolve")
    node.states.hover.can = false
    node.states.click.can = false
    node.states.drag.can = false
    self._destroying_nodes[#self._destroying_nodes + 1] = node

    local vt = node.VT
    local cx = vt.x + vt.w * vt.scale * 0.5
    local cy = vt.y + vt.h * vt.scale * 0.5
    DISSOLVE_PARTICLE_SPEC.colour = dissolve_colour_for(node)
    for _ = 1, DISSOLVE_PARTICLE_COUNT do
        DISSOLVE_PARTICLE_SPEC.x = cx + (visual_random() - 0.5) * vt.w * vt.scale
        DISSOLVE_PARTICLE_SPEC.y = cy + (visual_random() - 0.5) * vt.h * vt.scale
        DISSOLVE_PARTICLE_SPEC.vx = (visual_random() - 0.5) * 88
        DISSOLVE_PARTICLE_SPEC.vy = -16 - visual_random() * 58
        Particles.emit(DISSOLVE_PARTICLE_SPEC)
    end
end

--- The inverse of `start_card_dissolve`: a newly created hand card scales and fades in over
--- the same short beat as its existing materialize cue (reference/Balatro/card.lua:2183-2239).
---
--- The burst converges rather than scatters, and is tinted by the card the same way the
--- dissolve is, so a Gold card being conjured reads as gold arriving. `Game` owns the emitter
--- because jokers and consumables materialise through it too.
function Hand:start_card_materialize(node)
    if not node then return end
    node:begin_lifecycle("materialize")
    self._materializing_nodes[#self._materializing_nodes + 1] = node
    local game = self.game
    if game and game.begin_materialize_burst then
        game:begin_materialize_burst(node, dissolve_colour_for(node))
    end
end

--- Advance retained card lifecycles. Entries and particle specs are created only at an effect
--- boundary; this loop does not allocate during a frame.
function Hand:update_card_lifecycles(dt)
    dt = tonumber(dt) or 0
    if dt <= 0 then return end
    for i = #self._destroying_nodes, 1, -1 do
        local node = self._destroying_nodes[i]
        if not node or not node._card_lifecycle or node:advance_lifecycle(dt) then
            if node then self.game:remove(node) end
            table.remove(self._destroying_nodes, i)
        end
    end
    for i = #self._materializing_nodes, 1, -1 do
        local node = self._materializing_nodes[i]
        local life = node and node._card_lifecycle
        -- A materialise that got overridden by a dissolve is the dissolve list's problem now.
        if not life or life.kind ~= "materialize" or node:advance_lifecycle(dt) then
            table.remove(self._materializing_nodes, i)
        end
    end
end

--- Is a card still coming apart or fading in? Callers that want to wait for the board to settle
--- (a booster pack holding open so Immolate's destruction is visible) ask this.
---@return boolean
function Hand:has_pending_card_lifecycles()
    return #self._destroying_nodes > 0 or #self._materializing_nodes > 0
end

function Hand:update(dt)
    self:update_card_lifecycles((G and G.real_dt) or dt)
    self:apply_idle_sway()
    -- A staggered `on_discard` batch holds the second half of the discard; the stagger
    -- itself runs in `Game:update` (`_update_joker_emit_queue`).
    local pending = self._pending_discard_finish
    if pending and not (self.game and self.game.joker_emit_busy and self.game:joker_emit_busy()) then
        self._pending_discard_finish = nil
        self:_finish_discard(pending.reason, pending.skip_events, pending.discarded_nodes,
            pending.discarded_cards, pending.selected_set)
    end
    if self._play_sequence then
        self:_update_play_sequence(dt)
    end
    if #self._draw_queue == 0 then return end
    -- Deal beat runs on the card-cadence clock, which caps out below full game speed so the
    -- stagger stays visible at 4x (`Game:card_beat_dt`).
    local beat_dt = (self.game and self.game.card_beat_dt) and self.game:card_beat_dt(dt) or dt
    self._draw_timer = self._draw_timer + beat_dt
    if self._draw_timer >= DRAW_DELAY then
        self._draw_timer = 0
        local card = table.remove(self._draw_queue, 1)
        if card then self:add_card(card) end
        if #self._draw_queue == 0 then
            -- The sweep cannot outlive the queue that drives it. A deal that ends short --
            -- the hand cap dropped mid-drain, a card was refused -- would otherwise strand
            -- the counter and pitch every later `add_card` off a stale ramp.
            self._deal_n = nil
            self._deal_i = nil
            self:_notify_deal_complete()
        end
    end
end

function Hand:size()
    return #self.cards
end

function Hand:is_full()
    return #self.cards >= hand_size_limit()
end

local SUIT_ORDER = { Hearts = 2, Clubs = 3, Diamonds = 4, Spades = 1 }
-- Order: A, K, Q, J, 10, 9, 8, 7, 6, 5, 4, 3, 2 (Ace first, then descending)
local function rank_sort_key(rank)
    return 14 - (rank or 2)
end

local function base_card_chips(rank)
    if rank == 14 then return 11 end -- Ace
    if rank == 11 or rank == 12 or rank == 13 then return 10 end -- J/Q/K
    if type(rank) == "number" then return rank end
    return 0
end

--- Permanent extra chips on `card_data` (field `Bonus`, lowercase `bonus` accepted).
local function card_data_bonus_chips(data)
    if type(data) ~= "table" then return 0 end
    return math.floor(tonumber(data.Bonus) or tonumber(data.bonus) or 0)
end

function Hand:get_modifier_bonus(card_data)
    if type(card_data) ~= "table" then return 0, 0 end

    local chip_bonus = 0
    local mult_bonus = 0

    -- Common direct fields on card data
    chip_bonus = chip_bonus + (tonumber(card_data.chip_bonus) or 0)
    chip_bonus = chip_bonus + (tonumber(card_data.chips_bonus) or 0)
    mult_bonus = mult_bonus + (tonumber(card_data.mult_bonus) or 0)
    mult_bonus = mult_bonus + (tonumber(card_data.multiplier_bonus) or 0)

    -- Generic single modifier table shape
    if type(card_data.modifier) == "table" then
        chip_bonus = chip_bonus + (tonumber(card_data.modifier.chip_bonus) or tonumber(card_data.modifier.chips) or 0)
        mult_bonus = mult_bonus + (tonumber(card_data.modifier.mult_bonus) or tonumber(card_data.modifier.mult) or 0)
    end

    -- Generic list of modifier tables
    if type(card_data.modifiers) == "table" then
        for _, mod in ipairs(card_data.modifiers) do
            if type(mod) == "table" then
                chip_bonus = chip_bonus + (tonumber(mod.chip_bonus) or tonumber(mod.chips) or 0)
                mult_bonus = mult_bonus + (tonumber(mod.mult_bonus) or tonumber(mod.mult) or 0)
            end
        end
    end

    return chip_bonus, mult_bonus
end

--- Playing-card editions are encoded as one modifier field by every acquisition path.
---@return number chip_bonus
---@return number mult_bonus
---@return number x_mult_bonus
function Hand:get_playing_card_edition_bonus(card_data)
    local modifier = type(card_data) == "table" and card_data.modifier or nil
    local edition = type(modifier) == "table" and modifier.edition or nil
    if edition == "foil" then return 50, 0, 1 end
    if edition == "holo" then return 0, 10, 1 end
    if edition == "polychrome" then return 0, 0, 1.5 end
    return 0, 0, 1
end

function Hand:apply_playing_card_edition(chips, mult, card_data)
    local chip_bonus, mult_bonus, x_mult_bonus = self:get_playing_card_edition_bonus(card_data)
    -- Playing-card xMult is applied after that card's own effects (reference state_events.lua:759-776).
    return chips + chip_bonus, (mult + mult_bonus) * x_mult_bonus
end

--- Apply one card's chips and mult bonuses (hand base chips/mult should already be in G).
function Hand:accumulate_card_score(chips, mult, node, include_edition)
    local data = node.card_data or {}
    local rank = data.rank
    local suit = data.suit
    local bonus = card_data_bonus_chips(data)
    -- New card, new run of effect beats: this card's popups stagger from zero rather than
    -- continuing the previous card's queue. The sequencer's later edition step deliberately
    -- carries on from wherever this leaves the slot.
    self._effect_slot = 0

    local card_chips = base_card_chips(rank) + bonus
    chips = chips + card_chips

    local mod_chip_bonus, mod_mult_bonus = self:get_modifier_bonus(data)
    chips = chips + mod_chip_bonus
    mult = mult + mod_mult_bonus
    -- The animated sequencer passes `false` and applies the edition itself, after the card's
    -- `card_played` listeners have run, which is the reference's order
    -- (`state_events.lua:759-776`). Callers that score in one shot let it happen here.
    if include_edition ~= false then
        chips, mult = self:apply_playing_card_edition(chips, mult, data)
    end
    local announce_edition_here = (include_edition ~= false)

    local card_center_x = node.VT.x + node.collision_offset.x + (node.VT.w / 2) * node.VT.scale
    local card_center_y = node.VT.y + node.collision_offset.y + (node.VT.h / 2) * node.VT.scale
    -- One popup per effect, staggered onto the beats the sequencer already charges for them
    -- (see `PLAY_EFFECT_INTERVAL`). The card's rank, its enhancement and anything hung on it by
    -- a modifier are three separate things in the reference, each with its own status text
    -- (`common_events.lua:779-935`); this used to add them together and show one number, so a
    -- Bonus card and a plain one of the same rank announced identically.
    self:announce_card_effects(node, card_center_x, card_center_y, {
        { amount = base_card_chips(rank), kind = "chips" },
        { amount = bonus, kind = "chips" },
        { amount = mod_chip_bonus, kind = "chips" },
        -- `> 0`, not `> 1`: this was guarded against 1 and silently swallowed a +1 mult.
        { amount = mod_mult_bonus, kind = "mult" },
    })
    -- The sequencer applies the edition later and announces it there, in the reference's order.
    -- A one-shot caller applied it above, so it announces here to stay in step.
    if announce_edition_here then
        self:announce_playing_card_edition(node, data)
    end

    return chips, mult
end

--- Spawn one popup per non-zero effect, each a beat after the last.
---
--- Split out so the scoring path stays a list of effects rather than a run of near-identical
--- Popup blocks, and so the edition step in the sequencer can announce itself the same way.
---@param node Card the card the effects belong to
---@param x number card centre
---@param y number
---@param effects table[] `{ amount, kind }` in the order they apply; zero amounts are skipped
function Hand:announce_card_effects(node, x, y, effects)
    -- The slot counts effects already announced for the card being scored right now, so the
    -- edition - which the sequencer applies later, after the card's listeners - queues behind
    -- them instead of landing on top of the first one.
    local slot = self._effect_slot or 0
    for _, effect in ipairs(effects) do
        local amount = tonumber(effect.amount) or 0
        if amount ~= 0 then
            local p = Popup()
            p:spawn(amount, effect.kind, x, y, effect.scale, slot * PLAY_EFFECT_INTERVAL)
            G:addPopup(p)
            slot = slot + 1
        end
    end
    self._effect_slot = slot
    return slot
end

--- Announce a played card's edition where the sequencer applies it.
---
--- The edition was the one effect with no status text at all: a Polychrome playing card
--- multiplied the mult with nothing on screen to say so. It lands after the card's own
--- listeners, which is the reference's order (`state_events.lua:759-776`), so it announces from
--- there rather than from `accumulate_card_score`.
---@param node Card
---@param card_data table
function Hand:announce_playing_card_edition(node, card_data)
    if not node or not node.VT then return end
    local chip_bonus, mult_bonus, x_mult_bonus = self:get_playing_card_edition_bonus(card_data)
    local x = node.VT.x + node.collision_offset.x + (node.VT.w / 2) * node.VT.scale
    local y = node.VT.y + node.collision_offset.y + (node.VT.h / 2) * node.VT.scale
    self:announce_card_effects(node, x, y, {
        { amount = chip_bonus, kind = "chips" },
        { amount = mult_bonus, kind = "mult" },
        -- A neutral xMult is 1 and must not be announced; `announce_card_effects` skips 0, so
        -- the identity is subtracted out here and added back by the "x" prefix.
        { amount = (x_mult_bonus ~= 1) and x_mult_bonus or 0, kind = "xmult" },
    })
end

function Hand:score_selected_hand()
    if #self.selected == 0 then return nil end

    local chips = tonumber(G.selectedHandChips) or 0
    local mult = tonumber(G.selectedHandMult) or 1
    local ordered = self:ordered_selected_nodes()

    print(string.format("Scoring hand start: chips=%d mult=%d", chips, mult))

    for i, node in ipairs(ordered) do
        local score_this = node.counts_for_play_score == true
        local data = node.card_data or {}
        local rank = data.rank
        local suit = data.suit
        local card_chips = base_card_chips(rank) + card_data_bonus_chips(data)
        local mod_chip_bonus, mod_mult_bonus = self:get_modifier_bonus(data)

        if score_this then
            chips, mult = self:accumulate_card_score(chips, mult, node)
        end

        print(string.format(
            "Card %d [%s of %s]: +%d chips, modifier +%d chips / +%d mult -> chips=%d mult=%d%s",
            i, tostring(rank), tostring(suit), card_chips, mod_chip_bonus, mod_mult_bonus, chips, mult,
            score_this and "" or " (kicker - not scored)"
        ))
    end

    if G and G.challenge_modifiers and G.challenge_modifiers.chips_dollar_cap == true then
        chips = math.min(chips, math.max(0, tonumber(G.money) or 0))
    end
    local final_score = math.floor(chips * mult)
    G.selectedHandChips = chips
    G.selectedHandMult = mult
    G.last_hand_score = final_score
    G.round_score = (G.round_score or 0) + final_score

    print(string.format("Hand result: %d x %d = %d", chips, mult, final_score))
    print(string.format("Round score: %d", G.round_score))

    return { chips = chips, mult = mult, score = final_score }
end

function Hand:play_selected()
    if #self.selected == 0 or G.hands <= 0 then return end
    if self._play_sequence or self._pending_discard_finish then return end

    if self.game then
        self.game:clear_bottom_tooltips()
    end

    self:calculate_play()
    local cards = self:ordered_selected_nodes()
    if self.game and self.game.boss_before_play_selected and not self.game:boss_before_play_selected(cards) then
        return
    end
    -- Mouth / Eye / Psychic void the hand rather than refusing it: it is played and consumed,
    -- but the whole scoring block is skipped (`state_events.lua:614`).
    local voided = self.game and self.game.boss_should_void_current_play
        and self.game:boss_should_void_current_play() or false

    -- Face-down cards (Blind boss) turn over before scoring. The reference sweeps a flip
    -- downward in pitch (`reference/Balatro/card.lua:1107`), the opposite of a deal.
    local flipped_any = false
    local flip_n = #cards
    for i, n in ipairs(cards) do
        if n and n.face_up == false and n.set_face_up then
            n:set_face_up(true)
            flipped_any = true
            Sfx.play("card1", 1.15 - fan_percent(i, flip_n) * 0.3)
        end
    end
    if flipped_any then
        self:calculate_play()
        cards = self:ordered_selected_nodes()
    end

    -- Cleared the moment the hand is played, so Matador only sees abilities that fired
    -- during this hand (`reference/Balatro/functions/state_events.lua:454`).
    if self.game then self.game.blind_triggered_this_hand = false end

    -- Debuff boss ability: one notify per played hand (not per selection / per card).
    if self._pending_boss_debuff_notify and self.game and self.game.notify_boss_effect_triggered then
        self.game:notify_boss_effect_triggered({ reason = "card_debuffed_for_scoring" })
    end
    self._pending_boss_debuff_notify = false

    if self.game then
        local hi = tonumber(G and G.selectedHand)
        if hi and hi > 0 then
            self.game.last_played_hand_index = hi
        end
    end

    G.hands = G.hands - 1
    -- `ease_hands_played` does the same for the hands counter (`common_events.lua:176`).
    Sfx.play("chips2")
    G.handsPlayed = G.handsPlayed + 1
    -- Unlock bookkeeping. `c_face_cards_played` counts every face card in the played hand,
    -- and `hand_contents` / `play_all_hearts` read the hand itself
    -- (`common_events.lua:1522-1546`, `state_events.lua:521`).
    if self.game and self.game.add_career_stat then
        local played_data = {}
        local faces = 0
        for _, node in ipairs(cards) do
            local d = node and node.card_data
            if d then
                played_data[#played_data + 1] = d
                local r = tonumber(d.rank)
                if r == 11 or r == 12 or r == 13 then faces = faces + 1 end
            end
        end
        self.game:add_career_stat("c_hands_played", 1)
        if faces > 0 then self.game:add_career_stat("c_face_cards_played", faces) end
        self.game:check_unlock("career_stat")
        self.game:check_unlock("hand_contents", { cards = played_data })
        self.game:check_unlock("play_all_hearts")
    end
    if G.record_cards_played then
        G:record_cards_played(#cards)
    end
    if self.game and self.game.boss_apply_on_hand_submitted then
        self.game:boss_apply_on_hand_submitted(cards)
    end
    -- Everything below is the scoring block the reference skips wholesale on a voided hand:
    -- no joker sees the play, no hand-type counter moves, and the product is zero.
    if voided then
        G.selectedHandChips = 0
        G.selectedHandMult = 0
    end
    -- The `before` pass is not run here: it is handed to the play sequence and dispatched
    -- after the scoring cards lift, so each triggering joker gets its own blocking beat the
    -- way the reference's status events do (`state_events.lua:600-637`).
    local before_ctx = nil
    if not voided then
        before_ctx = {
            event = "on_hand_played",
            event_name = "on_hand_played",
            cards = cards,
            full_hand = cards,
            hand_index = G and G.selectedHand,
            hand_level = G and G.selectedHandLevel,
            hand_type = (G and G.handlist and G.selectedHand and G.handlist[G.selectedHand]) or nil,
        }
    end
    if not voided and self.game and self.game.increment_hand_play_count then
        self.game:increment_hand_play_count(G and G.selectedHand)
    end

    if self.game and self.game.challenge_modifiers
        and self.game.challenge_modifiers.debuff_played_cards == true then
        -- Only the scoring subset is marked, matching the reference's post-score
        -- event (reference/Balatro/functions/state_events.lua:1080-1084).
        for _, n in ipairs(cards) do
            if n and n.counts_for_play_score == true and n.card_data then
                n.card_data.perma_debuff = true
            end
        end
    end

    for _, n in ipairs(cards) do
        n.scoring_center = true
    end

    local chad_count = self.game and self.game.count_jokers_with_id and self.game:count_jokers_with_id("j_hanging_chad") or 0
    local hanging_chad_first = nil
    if chad_count > 0 then
        for _, n in ipairs(cards) do
            if n and n.counts_for_play_score == true then
                hanging_chad_first = n
                break
            end
        end
    end

    -- Photograph: first scoring face card in play order; x2 applies on every scoring pass (retriggers included).
    local photograph_pareidolia = self.game and self.game:hasJoker("j_pareidolia")
    local photograph_first_face = nil
    for _, n in ipairs(cards) do
        if n and n.counts_for_play_score == true then
            local d = n.card_data or {}
            local r = tonumber(d.rank)
            if photograph_pareidolia or r == 11 or r == 12 or r == 13 then
                photograph_first_face = n
                break
            end
        end
    end

    self._play_sequence = {
        phase = "move_center",
        timer = 0,
        release_i = 0,
        percent = SCORE_PERCENT_START,
        cards = cards,
        voided = voided,
        photograph_first_face_node = photograph_first_face,
        photograph_pareidolia = photograph_pareidolia and true or false,
        before_ctx = before_ctx,
    }
    for i, node in ipairs(cards) do
        node._play_release_percent = fan_percent(i, #cards)
    end

    self:layout_play_cards_at_center(cards)
    if self.game and self.game.move_selected_hand_cards_to_front then
        self.game:move_selected_hand_cards_to_front()
    end
end

function Hand:sort_by_rank(layout_skip_vt_node)
    self.sort_mode = "rank"
    if #self.cards == 0 then return end
    -- Reference `functions/button_callbacks.lua:45-47`.
    Sfx.play("paper1")
    local pairs = {}
    for i = 1, #self.cards do
        table.insert(pairs, { card = self.cards[i], node = self.card_nodes[i] })
    end
    table.sort(pairs, function(a, b)
        local ra, rb = rank_sort_key(a.card.rank), rank_sort_key(b.card.rank)
        if ra ~= rb then return ra < rb end
        return (SUIT_ORDER[a.card.suit] or 0) < (SUIT_ORDER[b.card.suit] or 0)
    end)
    self.cards = {}
    self.card_nodes = {}
    for _, p in ipairs(pairs) do
        table.insert(self.cards, p.card)
        table.insert(self.card_nodes, p.node)
    end
    self:layout(false, layout_skip_vt_node)
    if self.game and self.game.restore_hand_draw_order then
        self.game:restore_hand_draw_order()
    end
end

function Hand:sort_by_suit(layout_skip_vt_node)
    self.sort_mode = "suit"
    if #self.cards == 0 then return end
    -- Reference `functions/button_callbacks.lua:36-39`.
    Sfx.play("paper1")
    local pairs = {}
    for i = 1, #self.cards do
        table.insert(pairs, { card = self.cards[i], node = self.card_nodes[i] })
    end
    table.sort(pairs, function(a, b)
        local sa, sb = SUIT_ORDER[a.card.suit] or 0, SUIT_ORDER[b.card.suit] or 0
        if sa ~= sb then return sa < sb end
        return rank_sort_key(a.card.rank) < rank_sort_key(b.card.rank)
    end)
    self.cards = {}
    self.card_nodes = {}
    for _, p in ipairs(pairs) do
        table.insert(self.cards, p.card)
        table.insert(self.card_nodes, p.node)
    end
    self:layout(false, layout_skip_vt_node)
    if self.game and self.game.restore_hand_draw_order then
        self.game:restore_hand_draw_order()
    end
end

function Hand:calculate_play()
    local n_sel = #self.selected
    if n_sel == 0 then
        self._last_play_hand_flags = nil
        self._pending_boss_debuff_notify = false
        for _, node in ipairs(self.card_nodes) do
            node.counts_for_play_score = false
            node.debuffed_for_scoring = false
        end
        print("No cards selected")
        G.selectedHandHidden = false
        G.selectedHand = -1
        G.selectedHandLevel = 1
        G.selectedHandChips = 0
        G.selectedHandMult = 0
        return
    end

    print("Selected cards:")

    local sel_set = {}
    for _, node in ipairs(self.selected) do
        sel_set[node] = true
    end

    -- One pass: clear scoring flags + build left-to-right order of selected cards
    local ordered = {}
    for _, node in ipairs(self.card_nodes) do
        node.counts_for_play_score = false
        node.debuffed_for_scoring = false
        if sel_set[node] then
            table.insert(ordered, node)
        end
    end

    local n = #ordered
    local has_four_fingers = false
    local has_shortcut = false
    local has_smeared = false
    if self.game and self.game:hasJoker("j_four_fingers") then
        has_four_fingers = true
    end
    if self.game and self.game:hasJoker("j_shortcut") then
        has_shortcut = true
    end
    if self.game and self.game:hasJoker("j_smeared") then
        has_smeared = true
    end

    local function normalized_suit_for_scoring(suit)
        if not has_smeared then return suit end
        if suit == "Hearts" or suit == "Diamonds" then return "Red" end
        if suit == "Spades" or suit == "Clubs" then return "Black" end
        return suit
    end

    -- Collect ranks / suits (hand order); track high rank for marking high card later
    local ranks = {}
    local suits = {}
    local rank_counts = {}
    local suit_counts = {}
    local wild_count = 0
    local max_rank_for_high = nil
    local has_face_down_selected = false

    for _, node in ipairs(ordered) do
        local data = node.card_data or {}
        local rank = data.rank
        local suit = data.suit
        local enhancement = data.enhancement
        if node and node.face_up == false then
            has_face_down_selected = true
        end

        -- Stone Cards are rankless/suitless (reference/Balatro/card.lua:957-981).
        if rank ~= nil then
            table.insert(ranks, rank)
            rank_counts[rank] = (rank_counts[rank] or 0) + 1
        end
        if suit ~= nil then
            table.insert(suits, suit)
        end
        if enhancement == "wild" then
            wild_count = wild_count + 1
        elseif suit ~= nil then
            local normalized_suit = normalized_suit_for_scoring(suit)
            suit_counts[normalized_suit] = (suit_counts[normalized_suit] or 0) + 1
        end

        if type(rank) == "number" then
            if max_rank_for_high == nil or rank > max_rank_for_high then
                max_rank_for_high = rank
            end
        end
    end

    local min_straight_flush_cards = has_four_fingers and 4 or 5

    local function is_flush()
        if n < min_straight_flush_cards then return false end
        if wild_count == n then return true end
        if next(suit_counts) == nil then return false end
        local max_suit = 0
        for _, c in pairs(suit_counts) do
            if c > max_suit then max_suit = c end
        end
        return max_suit + wild_count >= min_straight_flush_cards
    end

    -- Rank pattern: one pass over rank_counts (also used for scoring marks later)
    local max_of_a_kind = 0
    local pairs_count = 0
    local has_three = false
    local has_two = false
    for _, c in pairs(rank_counts) do
        if c > max_of_a_kind then max_of_a_kind = c end
        if c == 2 then
            pairs_count = pairs_count + 1
            has_two = true
        end
        if c == 3 then has_three = true end
    end

    -- A straight usually needs 5 cards, but Four Fingers allows 4-card straights.
    local function is_straight()
        if n < min_straight_flush_cards then return false end
        local function has_valid_run(sorted_unique_ranks)
            if #sorted_unique_ranks < min_straight_flush_cards then return false end
            local run_len = 1
            for i = 2, #sorted_unique_ranks do
                local diff = sorted_unique_ranks[i] - sorted_unique_ranks[i - 1]
                local is_run_step = (diff == 1) or (has_shortcut and diff == 2)
                if is_run_step then
                    run_len = run_len + 1
                    if run_len >= min_straight_flush_cards then
                        return true
                    end
                else
                    run_len = 1
                end
            end
            return false
        end

        local uniq = {}
        for _, r in ipairs(ranks) do
            if r == nil then return false end
            uniq[r] = true
        end

        local uniq_ranks = {}
        for r in pairs(uniq) do
            table.insert(uniq_ranks, r)
        end
        table.sort(uniq_ranks)

        if has_valid_run(uniq_ranks) then return true end

        -- Ace-low variants (A as 1), including Shortcut gap runs (e.g. A-3-5-7-9).
        if uniq[14] then
            local ace_low = {}
            for _, rr in ipairs(uniq_ranks) do
                ace_low[#ace_low + 1] = (rr == 14) and 1 or rr
            end
            table.sort(ace_low)
            local dedup = {}
            local prev = nil
            for _, rr in ipairs(ace_low) do
                if rr ~= prev then
                    dedup[#dedup + 1] = rr
                    prev = rr
                end
            end
            if has_valid_run(dedup) then return true end
        end

        local hasA = uniq[14] or uniq["A"]
        local wheel5 = hasA and uniq[2] and uniq[3] and uniq[4] and uniq[5]
        local wheel4 = hasA and uniq[2] and uniq[3] and uniq[4]
        return wheel5 or (min_straight_flush_cards <= 4 and wheel4)
    end

    local flush = is_flush()
    local straight = is_straight()
    self._last_play_hand_flags = {
        nodes = ordered,
        pairs_count = pairs_count,
        max_of_a_kind = max_of_a_kind,
        flush = flush and true or false,
        straight = straight and true or false,
    }

    -- Determine hand according to Balatro order in globals.handlist:
    -- 1  Flush Five      (five of same rank & same suit)
    -- 2  Flush House     (full house, all same suit)
    -- 3  Five of a Kind  (five of same rank, not all same suit)
    -- 4  Straight Flush
    -- 5  Four of a Kind
    -- 6  Full House
    -- 7  Flush
    -- 8  Straight
    -- 9  Three of a Kind
    -- 10 Two Pair
    -- 11 Pair
    -- 12 High Card

    local hand_index

    if n == 5 then
        -- Secret hands first
        if max_of_a_kind == 5 and flush then
            hand_index = 1 -- Flush Five
        elseif flush then
            -- Check for Flush House: 3-of-a-kind + 2-of-a-kind, all same suit
            if has_three and has_two then
                hand_index = 2 -- Flush House
            end
        end

        if not hand_index then
            if max_of_a_kind == 5 then
                hand_index = 3 -- Five of a Kind
            elseif flush and straight then
                hand_index = 4 -- Straight Flush
            elseif max_of_a_kind == 4 then
                hand_index = 5 -- Four of a Kind
            else
                if has_three and has_two then
                    hand_index = 6 -- Full House
                elseif flush then
                    hand_index = 7 -- Flush
                elseif straight then
                    hand_index = 8 -- Straight
                elseif max_of_a_kind == 3 then
                    hand_index = 9 -- Three of a Kind
                elseif pairs_count == 2 then
                    hand_index = 10 -- Two Pair
                elseif pairs_count == 1 then
                    hand_index = 11 -- Pair
                else
                    hand_index = 12 -- High Card
                end
            end
        end
    else
        -- Fewer than 5 cards: fall back to best matching category we can infer
        if flush and straight then
            hand_index = 4 -- Straight Flush (Four Fingers 4-card enable)
        elseif max_of_a_kind >= 4 then
            hand_index = 5 -- Four of a Kind (partial)
        elseif flush then
            hand_index = 7 -- Flush (Four Fingers 4-card enable)
        elseif straight then
            hand_index = 8 -- Straight (Four Fingers 4-card enable)
        elseif max_of_a_kind == 3 then
            hand_index = 9 -- Three of a Kind
        elseif pairs_count >= 2 then
            hand_index = 10 -- Two Pair
        elseif pairs_count == 1 then
            hand_index = 11 -- Pair
        else
            hand_index = 12 -- High Card
        end
    end

    G.selectedHand = hand_index or 12

    local hand_stats = G.hand_stats and G.hand_stats[G.selectedHand] or nil
    if hand_stats then
        local level = math.max(1, tonumber(hand_stats.level) or 1)
        local chips = (hand_stats.base_chips or 0) + ((level - 1) * (hand_stats.chips_per_level or 0))
        local mult = (hand_stats.base_mult or 0) + ((level - 1) * (hand_stats.mult_per_level or 0))
        if G and G.boss_apply_hand_base_modifiers then
            chips, mult = G:boss_apply_hand_base_modifiers(chips, mult)
        end
        G.selectedHandLevel = level
        G.selectedHandChips = chips
        G.selectedHandMult = mult
    else
        G.selectedHandLevel = 1
        G.selectedHandChips = 0
        G.selectedHandMult = 0
    end

    if G.selectedHand and G.handlist and G.handlist[G.selectedHand] then
        print("Detected hand: " .. tostring(G.handlist[G.selectedHand]))
    else
        print("Detected hand index: " .. tostring(G.selectedHand))
    end
    G.selectedHandHidden = has_face_down_selected == true

    print("Hand level: " .. tostring(G.selectedHandLevel))
    print("Hand chips: " .. tostring(G.selectedHandChips))
    print("Hand mult: " .. tostring(G.selectedHandMult))

    -- Mark which selected cards actually score (ordered built above).
    local hi = G.selectedHand

    local function mark_all_ordered()
        for _, node in ipairs(ordered) do
            node.counts_for_play_score = true
        end
    end

    local function mark_rank_scoring(r)
        for _, node in ipairs(ordered) do
            if (node.card_data or {}).rank == r then
                node.counts_for_play_score = true
            end
        end
    end

    if G:hasJoker("j_splash") then
        mark_all_ordered()
    elseif hi == 1 or hi == 2 or hi == 3 or hi == 4 or hi == 6 or hi == 7 or hi == 8 then
        mark_all_ordered()
    elseif hi == 5 then
        for r, c in pairs(rank_counts) do
            if c == 4 then
                mark_rank_scoring(r)
                break
            end
        end
    elseif hi == 9 then
        for r, c in pairs(rank_counts) do
            if c == 3 then
                mark_rank_scoring(r)
                break
            end
        end
    elseif hi == 10 then
        for r, c in pairs(rank_counts) do
            if c == 2 then
                mark_rank_scoring(r)
            end
        end
    elseif hi == 11 then
        for r, c in pairs(rank_counts) do
            if c == 2 then
                mark_rank_scoring(r)
                break
            end
        end
    elseif hi == 12 then
        if max_rank_for_high ~= nil then
            mark_rank_scoring(max_rank_for_high)
        end
    else
        mark_all_ordered()
    end

    -- Stone cards always score when played
    for _, node in ipairs(ordered) do
        local enh = node.enhancement or (node.card_data and node.card_data.enhancement)
        if enh == "stone" then
            node.counts_for_play_score = true
        end
    end

    -- Mark debuffs for scoring preview only; notify once on play (see play_selected).
    self._pending_boss_debuff_notify = false
    if G and G.boss_is_card_debuffed_for_scoring then
        for _, node in ipairs(ordered) do
            if node.counts_for_play_score == true and G:boss_is_card_debuffed_for_scoring(node) then
                node.counts_for_play_score = false
                -- Distinct from a kicker, which also carries `counts_for_play_score = false`.
                -- Only a card that *would* have scored gets the rejection sting; re-querying
                -- the boss during scoring cannot tell the two apart, because The Pillar marks
                -- every played card the moment the hand is submitted.
                node.debuffed_for_scoring = true
                self._pending_boss_debuff_notify = true
            end
        end
    end
    if G and G.get_active_boss_blind_id and G:get_active_boss_blind_id() == "bl_psychic" and #ordered < 5 then
        for _, node in ipairs(ordered) do
            node.counts_for_play_score = false
        end
        G.selectedHandChips = 0
        G.selectedHandMult = 0
    end
end
