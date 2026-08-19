--- Live per-Joker readouts, drawn under the Joker row.
---
--- This is a native reimplementation of nh6574's JokerDisplay mod
--- (https://github.com/nh6574/JokerDisplay). That mod is a Lovely/Steamodded package: it patches
--- the desktop game at load time and hangs a `JokerDisplay` UIBox off every Joker card, built out
--- of the reference's node tree (`engine/ui.lua`) with per-Joker definitions that push text rows,
--- reminder rows and edition rows. None of that machinery exists here — this port has no UIBox
--- system, no mod loader, and a 240p screen with roughly 45 px of width per Joker once the row
--- fans. So the *idea* is ported, not the implementation:
---
---  * One line of text per Joker instead of a stack of rows, with an optional short second line.
---    The mod's collapse/expand affordance is unnecessary when there is only ever one row.
---  * The value is a plain formatted number (`+12`, `X2.5`, `$4`) rather than the mod's
---    coloured multi-node row, because at MICRO (9 px) anything longer stops being readable.
---  * Per-Joker right-click-to-disable is dropped: there is no right click, and the whole
---    feature is one settings toggle instead (`Settings > Joker Info`).
---  * Values are recomputed only when something they depend on changes (see `signature`), and the
---    resulting strings go through `TextCache`. On this hardware a `printf` costs 250 us and a
---    cached TextBatch 16 us, so a row of five Jokers recomputed every frame would be a real
---    fraction of the frame budget for text that changes a few times a round.
---
--- Retrigger counts come from `Game:collect_retrigger_sources`, i.e. the same query the scoring
--- run uses, rather than from a second copy of the retrigger rules. Everything else is read off
--- the live run state; nothing here mutates anything.

local TextCache = require("text_cache")

local JokerDisplay = {}

--- Bumped by anything that invalidates every readout at once (a selection change). Live numbers
--- like money are folded into the signature directly.
local generation = 0
local last_signature = nil

--- Panel geometry. One line, always: the row fans down to about 45 px a column on the top
--- screen, and the band has to clear the slot counter under the tray.
local PANEL_PAD_X = 2
local PANEL_PAD_Y = 1
--- Gap between the value and its note when both fit.
local NOTE_GAP = 3
--- Distance from the bottom of the card to the top of its panel.
local PANEL_OFFSET_Y = 2

--- The readouts render in SMALL, the face the great majority of the game's text uses. MICRO is
--- the tempting choice at this size, but it is the 9 px rung: crisp on hardware under the native
--- ladder, and a fallback to the shared `.ttf` rasterised well below its pixel grid everywhere
--- else, which is what made the panels read soft next to the rest of the UI.
---@return love.Font|nil font
---@return number line_h
local function readout_font(g)
    local pixel = g and g.FONTS and g.FONTS.PIXEL
    if not pixel then return nil, 9 end
    local font = pixel.SMALL or pixel.MICRO
    -- The declared role height, not `font:getHeight()`. The band has to fit between the Joker
    -- row and the slot counter on a 240 px screen, and the runtimes disagree about a face's
    -- height: a `.bcfnt` reports its cell height while desktop LOVE reports ascent plus descent.
    -- Laying out to the desktop number would push the counter off the console's screen.
    local h = tonumber(pixel.SMALL_HEIGHT) or tonumber(pixel.MICRO_HEIGHT) or 9
    return font, h
end

local function panel_height(g)
    return select(2, readout_font(g)) + PANEL_PAD_Y * 2
end

---@return boolean
function JokerDisplay.enabled(game)
    local g = game or G
    return g ~= nil and g.SETTINGS ~= nil and g.SETTINGS.JOKER_DISPLAY == true
end

--- Force a rebuild on the next `refresh`. Called from `Hand:calculate_play`, which is the one
--- place the selection can change from.
function JokerDisplay.invalidate()
    generation = generation + 1
end

-- ---------------------------------------------------------------------------------------------
-- Formatting
-- ---------------------------------------------------------------------------------------------

--- Trim a float to at most two decimals with no trailing zeros: 2.5 not 2.50, 3 not 3.00.
local function num(n)
    n = tonumber(n) or 0
    if n == math.floor(n) then return string.format("%d", n) end
    local s = string.format("%.2f", n)
    s = s:gsub("0+$", ""):gsub("%.$", "")
    return s
end

--- `kind` picks both the prefix and the colour; see `COLOUR_FOR_KIND`.
local function format_value(value, kind)
    if kind == "xmult" then return "X" .. num(value) end
    if kind == "money" then
        local v = tonumber(value) or 0
        if v < 0 then return "-$" .. num(-v) end
        return "$" .. num(v)
    end
    if kind == "plain" then return tostring(value) end
    local v = tonumber(value) or 0
    if v < 0 then return num(v) end
    return "+" .. num(v)
end

local function colour_for_kind(g, kind)
    local C = g.C
    if kind == "chips" then return C.CHIPS end
    if kind == "money" then return C.MONEY end
    if kind == "plain" then return C.WHITE end
    return C.MULT
end

-- ---------------------------------------------------------------------------------------------
-- Card predicates, matching the scoring path's rules
-- ---------------------------------------------------------------------------------------------

local function joker_owned(g, id)
    return g ~= nil and g.hasJoker ~= nil and g:hasJoker(id)
end

--- Suit match, with Smeared Joker collapsing Hearts/Diamonds and Spades/Clubs
--- (`joker_effects.lua`'s `is_suit`, kept in step with it).
local function is_suit(g, suit, check)
    if suit == nil or check == nil then return false end
    if joker_owned(g, "j_smeared") then
        if check == "Hearts" or check == "Diamonds" then
            return suit == "Hearts" or suit == "Diamonds"
        elseif check == "Spades" or check == "Clubs" then
            return suit == "Spades" or suit == "Clubs"
        end
    end
    return suit == check
end

local function rank_is_face(g, rank)
    rank = tonumber(rank)
    if joker_owned(g, "j_pareidolia") then return rank ~= nil end
    return rank == 11 or rank == 12 or rank == 13
end

local function rank_is_even(rank)
    rank = tonumber(rank)
    if rank and rank < 14 and rank > 10 then return false end
    return rank ~= nil and rank ~= 14 and rank % 2 == 0
end

local function rank_is_odd(rank)
    rank = tonumber(rank)
    if rank and rank < 14 and rank > 10 then return false end
    return rank ~= nil and (rank == 14 or rank % 2 == 1)
end

local function count_full_deck(g, pred)
    if g and g.count_cards_in_full_deck then return g:count_cards_in_full_deck(pred) end
    return 0
end

local function config_of(joker)
    local cfg = joker and joker.effect_config
    if type(cfg) == "table" then return cfg end
    local def = joker and joker.def
    if type(def) == "table" and type(def.config) == "table" then return def.config end
    return {}
end

local function extra_of(joker)
    local e = config_of(joker).extra
    if type(e) == "table" then return e end
    return {}
end

-- ---------------------------------------------------------------------------------------------
-- Evaluation context
-- ---------------------------------------------------------------------------------------------

--- Cards the current selection would actually score, in play order, plus the cards left in hand.
--- `Hand:calculate_play` has already marked `counts_for_play_score` on every selection change, so
--- this is a read, not a second hand evaluation.
local function build_context(g)
    local ctx = {
        game = g,
        scoring = {},
        played = {},
        held = {},
        hand_index = tonumber(g.selectedHand),
        hand_name = nil,
        contains = {},
        trigger_scratch = {},
        trigger_ctx = {},
    }
    if ctx.hand_index and ctx.hand_index > 0 and type(g.handlist) == "table" then
        ctx.hand_name = g.handlist[ctx.hand_index]
    end

    local hand = g.hand
    if not hand or type(hand.card_nodes) ~= "table" then return ctx end

    local selected = {}
    for _, node in ipairs(hand.selected or {}) do selected[node] = true end

    for _, node in ipairs(hand.card_nodes) do
        if node and node.card_data then
            if selected[node] then
                ctx.played[#ctx.played + 1] = node
                if node.counts_for_play_score == true then
                    ctx.scoring[#ctx.scoring + 1] = node
                end
            else
                ctx.held[#ctx.held + 1] = node
            end
        end
    end

    if hand.build_contained_hand_types then
        ctx.contains = hand:build_contained_hand_types(ctx.played) or {}
    end
    return ctx
end

--- How many times `node` scores this hand: its own pass plus every retrigger the run would grant
--- it. Delegates to the scoring path's own query so Hanging Chad, Hack, Sock and Buskin, Dusk,
--- Seltzer, a Red Seal and any Blueprint copying one of them are all counted exactly once.
local function card_triggers(ctx, node)
    local g = ctx.game
    if not (g and g.collect_retrigger_sources) then return 1 end
    local out = ctx.trigger_scratch
    for i = #out, 1, -1 do out[i] = nil end
    local rctx = ctx.trigger_ctx
    rctx.card_node = node
    rctx.retrigger_card = node
    rctx.played_cards = ctx.played
    -- Dusk asks whether this is the final hand; at readout time the hand has not been spent yet,
    -- so it needs to test one lower. `joker_effects.lua`'s `j_dusk` honours this flag.
    rctx.jd_preview = true
    g:collect_retrigger_sources(false, rctx, out)
    return 1 + #out
end

--- Sum `per_card(node)` over the scoring cards, weighted by how often each one triggers.
local function sum_scoring(ctx, per_card)
    local total = 0
    for _, node in ipairs(ctx.scoring) do
        local v = per_card(node, node.card_data or {})
        if v and v ~= 0 then
            total = total + v * card_triggers(ctx, node)
        end
    end
    return total
end

local function has_hand(ctx, name)
    return ctx.hand_name == name or ctx.contains[name] == true
end

-- ---------------------------------------------------------------------------------------------
-- Per-Joker definitions
--
-- `main(joker, ctx)` returns `value, kind`; nil means "nothing to show". `note(joker, ctx)`
-- returns a short second line, or nil. Values are what the Joker would contribute to the
-- currently selected hand, which is what makes the readout worth the screen space.
-- ---------------------------------------------------------------------------------------------

local DEFS = {}

--- Flat "+N Mult if the hand contains X" and its chips twin, which between them cover sixteen
--- Jokers whose only difference is the number and the hand name.
local function hand_type_def(hand_name, amount, kind)
    return {
        main = function(_, ctx)
            if not has_hand(ctx, hand_name) then return nil end
            return amount, kind
        end,
    }
end

--- "+N per scored card of suit S", the four gem/elemental pairs.
local function suit_def(suit, amount, kind)
    return {
        main = function(joker, ctx)
            local n = tonumber(extra_of(joker).s_mult) or tonumber(extra_of(joker).s_chips) or amount
            local total = sum_scoring(ctx, function(_, data)
                return is_suit(ctx.game, data.suit, suit) and n or 0
            end)
            if total == 0 then return nil end
            return total, kind
        end,
    }
end

--- "+N per scored card matching `pred`".
local function rank_def(pred, amount, kind)
    return {
        main = function(_, ctx)
            local total = sum_scoring(ctx, function(_, data)
                return pred(ctx.game, data.rank) and amount or 0
            end)
            if total == 0 then return nil end
            return total, kind
        end,
    }
end

--- A stored value the Joker has accumulated.
---
--- Shown at its starting value too — a Green Joker at +0 and a fresh Hologram at X1 both still
--- get a number. The running total is the whole reason to look at one of these, and a readout
--- that only appears once the Joker has earned something reads as the feature being broken.
--- Conditional Jokers are the opposite case and stay hidden until they would fire; at ~45 px a
--- column, "+0" under every Joker that is not going to do anything is noise.
local function stored_def(field, kind, default)
    return {
        main = function(joker)
            return tonumber(joker[field]) or default or 0, kind
        end,
    }
end

-- Flat additions, always on.
DEFS.j_joker      = { main = function(j) return tonumber(config_of(j).mult) or 4, "mult" end }
DEFS.j_misprint   = { main = function() return "+0-23", "plain" end }
DEFS.j_stuntman   = { main = function(j) return tonumber(extra_of(j).chip_mod) or 250, "chips" end }
DEFS.j_gros_michel = { main = function() return 15, "mult" end }
DEFS.j_cavendish  = { main = function(j) return tonumber(extra_of(j).Xmult) or 3, "xmult" end }

-- Hand-type Jokers.
DEFS.j_jolly   = hand_type_def("Pair", 8, "mult")
DEFS.j_zany    = hand_type_def("Three of a Kind", 12, "mult")
DEFS.j_mad     = hand_type_def("Two Pair", 10, "mult")
DEFS.j_crazy   = hand_type_def("Straight", 12, "mult")
DEFS.j_droll   = hand_type_def("Flush", 10, "mult")
DEFS.j_sly     = hand_type_def("Pair", 50, "chips")
DEFS.j_wily    = hand_type_def("Three of a Kind", 100, "chips")
DEFS.j_clever  = hand_type_def("Two Pair", 80, "chips")
DEFS.j_devious = hand_type_def("Straight", 100, "chips")
DEFS.j_crafty  = hand_type_def("Flush", 80, "chips")
DEFS.j_duo     = hand_type_def("Pair", 2, "xmult")
DEFS.j_trio    = hand_type_def("Three of a Kind", 3, "xmult")
DEFS.j_family  = hand_type_def("Four of a Kind", 4, "xmult")
DEFS.j_order   = hand_type_def("Straight", 3, "xmult")
DEFS.j_tribe   = hand_type_def("Flush", 2, "xmult")

-- Suit Jokers.
DEFS.j_greedy_joker    = suit_def("Diamonds", 3, "mult")
DEFS.j_lusty_joker     = suit_def("Hearts", 3, "mult")
DEFS.j_wrathful_joker  = suit_def("Spades", 3, "mult")
DEFS.j_gluttenous_joker = suit_def("Clubs", 3, "mult")
DEFS.j_arrowhead       = suit_def("Spades", 50, "chips")
DEFS.j_onyx_agate      = suit_def("Clubs", 7, "mult")

-- Rank Jokers.
DEFS.j_scary_face  = rank_def(rank_is_face, 30, "chips")
DEFS.j_smiley_face = rank_def(rank_is_face, 5, "mult")
DEFS.j_even_steven = rank_def(function(_, r) return rank_is_even(r) end, 4, "mult")
DEFS.j_odd_todd    = rank_def(function(_, r) return rank_is_odd(r) end, 31, "chips")

DEFS.j_fibonacci = rank_def(function(_, r)
    r = tonumber(r)
    return r == 14 or r == 2 or r == 3 or r == 5 or r == 8
end, 8, "mult")

DEFS.j_scholar = {
    main = function(_, ctx)
        local total = sum_scoring(ctx, function(_, data)
            return tonumber(data.rank) == 14 and 4 or 0
        end)
        if total == 0 then return nil end
        return total, "mult"
    end,
    note = function(_, ctx)
        local chips = sum_scoring(ctx, function(_, data)
            return tonumber(data.rank) == 14 and 20 or 0
        end)
        if chips == 0 then return nil end
        return chips, "chips"
    end,
}

DEFS.j_walkie_talkie = {
    main = function(_, ctx)
        local total = sum_scoring(ctx, function(_, data)
            local r = tonumber(data.rank)
            return (r == 10 or r == 4) and 4 or 0
        end)
        if total == 0 then return nil end
        return total, "mult"
    end,
    note = function(_, ctx)
        local chips = sum_scoring(ctx, function(_, data)
            local r = tonumber(data.rank)
            return (r == 10 or r == 4) and 10 or 0
        end)
        if chips == 0 then return nil end
        return chips, "chips"
    end,
}

-- Multiplicative per-card Jokers: the product, not the per-card factor.
local function xmult_per_card_def(factor, pred)
    return {
        main = function(_, ctx)
            local x = 1
            for _, node in ipairs(ctx.scoring) do
                local data = node.card_data or {}
                if pred(ctx.game, data, node, ctx) then
                    for _ = 1, card_triggers(ctx, node) do x = x * factor end
                end
            end
            if x == 1 then return nil end
            return x, "xmult"
        end,
    }
end

DEFS.j_triboulet = xmult_per_card_def(2, function(_, data)
    local r = tonumber(data.rank)
    return r == 12 or r == 13
end)

DEFS.j_photograph = xmult_per_card_def(2, function(g, data, node, ctx)
    -- Only the first scoring face card counts (`joker_effects.lua`'s `j_photograph`).
    for _, other in ipairs(ctx.scoring) do
        if rank_is_face(g, (other.card_data or {}).rank) then
            return other == node
        end
    end
    return false
end)

DEFS.j_ancient_joker = {
    main = function(joker, ctx)
        local suit = joker.random_suit
        if type(suit) ~= "string" then return nil end
        local x = 1
        for _, node in ipairs(ctx.scoring) do
            if is_suit(ctx.game, (node.card_data or {}).suit, suit) then
                for _ = 1, card_triggers(ctx, node) do x = x * 1.5 end
            end
        end
        if x == 1 then return nil end
        return x, "xmult"
    end,
    note = function(joker)
        local suit = joker.random_suit
        return type(suit) == "string" and suit:sub(1, 5) or nil
    end,
}

DEFS.j_idol = {
    main = function(joker, ctx)
        local r, s = tonumber(joker.random_rank), joker.random_suit
        if not r or type(s) ~= "string" then return nil end
        local x = 1
        for _, node in ipairs(ctx.scoring) do
            local data = node.card_data or {}
            if tonumber(data.rank) == r and is_suit(ctx.game, data.suit, s) then
                for _ = 1, card_triggers(ctx, node) do x = x * 2 end
            end
        end
        if x == 1 then return nil end
        return x, "xmult"
    end,
    note = function(joker)
        local r, s = tonumber(joker.random_rank), joker.random_suit
        if not r or type(s) ~= "string" then return nil end
        local label = (r == 14 and "A") or (r == 13 and "K") or (r == 12 and "Q") or (r == 11 and "J") or tostring(r)
        return label .. " " .. s:sub(1, 1)
    end,
}

-- Chance-based Jokers show the payout they would make on a hit; the odds go on the note line,
-- because a number with no odds beside it reads as a certainty.
DEFS.j_bloodstone = {
    main = function(_, ctx)
        local hits = 0
        for _, node in ipairs(ctx.scoring) do
            if is_suit(ctx.game, (node.card_data or {}).suit, "Hearts") then
                hits = hits + card_triggers(ctx, node)
            end
        end
        if hits == 0 then return nil end
        local x = 1
        for _ = 1, hits do x = x * 1.5 end
        return x, "xmult"
    end,
    note = function() return "1 in 2", "plain" end,
}

DEFS.j_rough_gem = suit_def("Diamonds", 1, "money")

DEFS.j_business = {
    main = function(_, ctx)
        local n = 0
        for _, node in ipairs(ctx.scoring) do
            if rank_is_face(ctx.game, (node.card_data or {}).rank) then
                n = n + card_triggers(ctx, node)
            end
        end
        if n == 0 then return nil end
        return n * 2, "money"
    end,
    note = function() return "1 in 2", "plain" end,
}

DEFS.j_ticket = {
    main = function(_, ctx)
        local total = sum_scoring(ctx, function(_, data)
            return data.enhancement == "gold" and 4 or 0
        end)
        if total == 0 then return nil end
        return total, "money"
    end,
}

DEFS.j_8_ball = {
    main = function(joker, ctx)
        local n = 0
        for _, node in ipairs(ctx.scoring) do
            if tonumber((node.card_data or {}).rank) == 8 then
                n = n + card_triggers(ctx, node)
            end
        end
        if n == 0 then return nil end
        return n, "plain"
    end,
    note = function(joker)
        local odds = math.max(2, math.floor(tonumber(config_of(joker).extra) or 4))
        return "1 in " .. odds, "plain"
    end,
}

-- Held-in-hand Jokers.
DEFS.j_baron = {
    main = function(_, ctx)
        local x = 1
        for _, node in ipairs(ctx.held) do
            if tonumber((node.card_data or {}).rank) == 13 then
                x = x * 1.5
            end
        end
        if x == 1 then return nil end
        return x, "xmult"
    end,
}

DEFS.j_shoot_the_moon = {
    main = function(_, ctx)
        local n = 0
        for _, node in ipairs(ctx.held) do
            if tonumber((node.card_data or {}).rank) == 12 then n = n + 1 end
        end
        if n == 0 then return nil end
        return n * 13, "mult"
    end,
}

DEFS.j_raised_fist = {
    main = function(_, ctx)
        local lowest = nil
        for _, node in ipairs(ctx.held) do
            local data = node.card_data or {}
            local rank = tonumber(data.rank)
            local enhancement = node.enhancement or data.enhancement
            if enhancement ~= "stone" and rank and (lowest == nil or rank <= lowest) then
                lowest = rank
            end
        end
        if not lowest then return nil end
        if lowest == 14 then lowest = 11 elseif lowest > 10 then lowest = 10 end
        return lowest * 2, "mult"
    end,
}

DEFS.j_reserved_parking = {
    main = function(_, ctx)
        local n = 0
        for _, node in ipairs(ctx.held) do
            if rank_is_face(ctx.game, (node.card_data or {}).rank) then n = n + 1 end
        end
        if n == 0 then return nil end
        return n, "money"
    end,
    note = function() return "1 in 2", "plain" end,
}

DEFS.j_blackboard = {
    main = function(_, ctx)
        for _, node in ipairs(ctx.held) do
            local s = (node.card_data or {}).suit
            if not is_suit(ctx.game, s, "Spades") and not is_suit(ctx.game, s, "Clubs") then
                return nil
            end
        end
        return 3, "xmult"
    end,
}

-- Whole-hand conditions.
DEFS.j_half = {
    main = function(_, ctx)
        if #ctx.played == 0 or #ctx.played > 3 then return nil end
        return 20, "mult"
    end,
}

DEFS.j_flower_pot = {
    main = function(_, ctx)
        local has = { Hearts = false, Clubs = false, Diamonds = false, Spades = false }
        for _, node in ipairs(ctx.scoring) do
            local s = (node.card_data or {}).suit
            if s then
                for suit in pairs(has) do
                    if is_suit(ctx.game, s, suit) then has[suit] = true end
                end
            end
        end
        if has.Hearts and has.Clubs and has.Diamonds and has.Spades then return 3, "xmult" end
        return nil
    end,
}

DEFS.j_seeing_double = {
    main = function(_, ctx)
        local clubs, other = false, false
        for _, node in ipairs(ctx.scoring) do
            if is_suit(ctx.game, (node.card_data or {}).suit, "Clubs") then clubs = true else other = true end
        end
        if clubs and other then return 2, "xmult" end
        return nil
    end,
}

DEFS.j_superposition = {
    main = function(_, ctx)
        if not has_hand(ctx, "Straight") then return nil end
        for _, node in ipairs(ctx.scoring) do
            if tonumber((node.card_data or {}).rank) == 14 then return "Tarot", "plain" end
        end
        return nil
    end,
}

DEFS.j_seance = {
    main = function(_, ctx)
        if ctx.hand_name == "Straight Flush" then return "Spectral", "plain" end
        return nil
    end,
}

-- Run-state Jokers.
DEFS.j_stencil = {
    main = function(joker, ctx)
        local g = ctx.game
        local cap = tonumber(g.joker_capacity) or tonumber(g.joker_slot_count) or 0
        local used = (type(g.jokers) == "table") and #g.jokers or 0
        return math.max(0, cap - used) + 1, "xmult"
    end,
}

DEFS.j_abstract = {
    main = function(_, ctx)
        local n = (type(ctx.game.jokers) == "table") and #ctx.game.jokers or 0
        return 3 * n, "mult"
    end,
}

DEFS.j_banner = {
    main = function(_, ctx) return 30 * (tonumber(ctx.game.discards) or 0), "chips" end,
}

DEFS.j_mystic_summit = {
    main = function(_, ctx)
        if (tonumber(ctx.game.discards) or 0) ~= 0 then return nil end
        return 15, "mult"
    end,
}

DEFS.j_blue_joker = {
    main = function(_, ctx)
        local g = ctx.game
        local n = g.count_cards_in_deck and g:count_cards_in_deck() or 0
        return 2 * n, "chips"
    end,
    note = function(_, ctx)
        local g = ctx.game
        return tostring(g.count_cards_in_deck and g:count_cards_in_deck() or 0) .. " left", "plain"
    end,
}

DEFS.j_stone_joker = {
    main = function(_, ctx)
        local n = count_full_deck(ctx.game, function(c) return c.enhancement == "stone" end)
        if n == 0 then return nil end
        return 25 * n, "chips"
    end,
}

DEFS.j_steel_joker = {
    main = function(_, ctx)
        local n = count_full_deck(ctx.game, function(c) return c.enhancement == "steel" end)
        return 1 + 0.2 * n, "xmult"
    end,
}

DEFS.j_bull = {
    main = function(_, ctx) return 2 * math.max(0, tonumber(ctx.game.money) or 0), "chips" end,
}

DEFS.j_bootstraps = {
    main = function(_, ctx)
        local dollars = math.floor((tonumber(ctx.game.money) or 0) / 5)
        if dollars < 1 then return nil end
        return dollars * 2, "mult"
    end,
}

DEFS.j_to_the_moon = {
    main = function(_, ctx) return math.floor((tonumber(ctx.game.money) or 0) / 5), "money" end,
}

DEFS.j_cloud_9 = {
    main = function(_, ctx)
        return count_full_deck(ctx.game, function(c) return tonumber(c.rank) == 9 end), "money"
    end,
}

DEFS.j_erosion = {
    main = function(_, ctx)
        local start = tonumber(ctx.game.STARTING_DECK_SIZE) or 52
        local n = math.max(0, (start - count_full_deck(ctx.game)) * 4)
        if n == 0 then return nil end
        return n, "mult"
    end,
}

DEFS.j_drivers_license = {
    main = function(_, ctx)
        local n = count_full_deck(ctx.game, function(c)
            return c.enhancement ~= nil and c.enhancement ~= ""
        end)
        if n >= 16 then return 3, "xmult" end
        return nil
    end,
    note = function(_, ctx)
        local n = count_full_deck(ctx.game, function(c)
            return c.enhancement ~= nil and c.enhancement ~= ""
        end)
        return n .. "/16", "plain"
    end,
}

DEFS.j_throwback = {
    main = function(_, ctx) return 1 + 0.25 * (tonumber(ctx.game.skipsTaken) or 0), "xmult" end,
}

DEFS.j_fortune_teller = {
    main = function(_, ctx)
        local n = tonumber(ctx.game.tarots_used) or 0
        if n == 0 then return nil end
        return n, "mult"
    end,
}

DEFS.j_swashbuckler = {
    main = function(joker, ctx)
        local total = 0
        for _, other in ipairs(ctx.game.jokers or {}) do
            if other and other ~= joker then total = total + (tonumber(other.sell_cost) or 0) end
        end
        if total == 0 then return nil end
        return total, "mult"
    end,
}

DEFS.j_baseball_card = {
    main = function(joker, ctx)
        local x = 1
        for _, other in ipairs(ctx.game.jokers or {}) do
            local r = other and (tonumber(other.rarity) or (other.def and tonumber(other.def.rarity)))
            if other ~= joker and r == 2 then x = x * 1.5 end
        end
        if x == 1 then return nil end
        return x, "xmult"
    end,
}

DEFS.j_supernova = {
    main = function(_, ctx)
        local i = ctx.hand_index
        local c = (i and ctx.game.hand_play_counts and ctx.game.hand_play_counts[i]) or 0
        if c == 0 then return nil end
        return c, "mult"
    end,
}

DEFS.j_card_sharp = {
    main = function(joker, ctx)
        local i = ctx.hand_index
        local played = (i and ctx.game.blind_hand_play_counts and ctx.game.blind_hand_play_counts[i]) or 0
        if played <= 1 then return nil end
        return tonumber(extra_of(joker).Xmult) or 3, "xmult"
    end,
}

DEFS.j_acrobat = {
    main = function(_, ctx)
        -- The hand being read has not been spent yet, so "final hand" is one remaining.
        if (tonumber(ctx.game.hands) or 0) > 1 then return nil end
        return 3, "xmult"
    end,
}

DEFS.j_matador = {
    main = function(_, ctx)
        if ctx.game.blind_triggered_this_hand ~= true then return nil end
        return 8, "money"
    end,
}

DEFS.j_vagabond = {
    main = function(_, ctx)
        if (tonumber(ctx.game.money) or 0) > 4 then return nil end
        return "Tarot", "plain"
    end,
}

DEFS.j_delayed_grat = {
    main = function(_, ctx)
        local g = ctx.game
        local discards = tonumber(g.discards) or 0
        local per_round = g.get_effective_discards_per_round and g:get_effective_discards_per_round()
        if per_round ~= discards then return nil end
        return 2 * discards, "money"
    end,
}

DEFS.j_rocket = {
    main = function(joker) return math.max(1, math.floor(tonumber(joker.running_count) or 1)), "money" end,
}

DEFS.j_satellite = {
    main = function(_, ctx)
        local unique = 0
        for _, usage in pairs(ctx.game.consumable_usage or {}) do
            if type(usage) == "table" and usage.kind == "planet" then unique = unique + 1 end
        end
        return unique, "money"
    end,
}

DEFS.j_golden_joker = { main = function() return 4, "money" end }

DEFS.j_egg = { main = function(joker) return tonumber(joker.sell_cost) or 0, "money" end }

DEFS.j_mail = {
    main = function(joker)
        local r = tonumber(joker.random_rank)
        if not r then return nil end
        local label = (r == 14 and "A") or (r == 13 and "K") or (r == 12 and "Q") or (r == 11 and "J") or tostring(r)
        return label, "plain"
    end,
    note = function(joker)
        return tonumber(type(joker.def) == "table" and joker.def.config and joker.def.config.extra) or 5, "money"
    end,
}

DEFS.j_todo_list = {
    main = function(joker)
        local h = joker.random_hand
        if type(h) ~= "string" then return nil end
        return h, "plain"
    end,
}

DEFS.j_castle = {
    main = stored_def("runtime_counter", "chips").main,
    note = function(joker)
        local s = joker.random_suit
        return type(s) == "string" and s or nil
    end,
}

-- Accumulating Jokers: the stored value is the readout, whether or not a hand is up.
DEFS.j_ceremonial     = stored_def("stored_mult", "mult")
DEFS.j_ride_the_bus   = stored_def("runtime_counter", "mult")
DEFS.j_green_joker    = stored_def("stored_mult", "mult")
DEFS.j_red_card       = stored_def("stored_mult", "mult")
DEFS.j_flash_card     = stored_def("stored_mult", "mult")
DEFS.j_spare_trousers = stored_def("stored_mult", "mult")
DEFS.j_popcorn        = stored_def("stored_mult", "mult")
DEFS.j_runner         = stored_def("stored_chips", "chips")
DEFS.j_square         = stored_def("stored_chips", "chips")
DEFS.j_wee            = stored_def("stored_chips", "chips")
DEFS.j_ice_cream      = stored_def("runtime_counter", "chips")
DEFS.j_constellation  = stored_def("stored_xmult", "xmult", 1)
DEFS.j_madness        = stored_def("stored_xmult", "xmult", 1)
DEFS.j_vampire        = stored_def("stored_xmult", "xmult", 1)
DEFS.j_hologram       = stored_def("stored_xmult", "xmult", 1)
DEFS.j_obelisk        = stored_def("stored_xmult", "xmult", 1)
DEFS.j_glass          = stored_def("stored_xmult", "xmult", 1)
DEFS.j_hit_the_road   = stored_def("stored_xmult", "xmult", 1)
DEFS.j_canio          = stored_def("stored_xmult", "xmult", 1)
DEFS.j_lucky_cat      = stored_def("stored_xmult", "xmult", 1)
DEFS.j_campfire       = stored_def("stored_xmult", "xmult", 1)

DEFS.j_yorick = {
    main = stored_def("stored_xmult", "xmult", 1).main,
    note = function(joker)
        return (math.floor(tonumber(joker.runtime_counter) or 0)) .. "/23", "plain"
    end,
}

DEFS.j_ramen = {
    main = function(joker)
        local x = tonumber(joker.runtime_counter) or 2
        if x <= 1 then return nil end
        return x, "xmult"
    end,
}

-- Countdown Jokers.
DEFS.j_loyalty_card = {
    main = function(joker)
        local extra = extra_of(joker)
        local every = math.max(1, math.floor(tonumber(extra.every) or 6))
        local remaining = math.floor(tonumber(joker.runtime_counter) or every)
        if remaining < 1 or remaining > every then remaining = every end
        if remaining == 1 then
            return tonumber(extra.Xmult) or tonumber(config_of(joker).Xmult) or 4, "xmult"
        end
        return nil
    end,
    note = function(joker)
        local extra = extra_of(joker)
        local every = math.max(1, math.floor(tonumber(extra.every) or 6))
        local remaining = math.floor(tonumber(joker.runtime_counter) or every)
        if remaining < 1 or remaining > every then remaining = every end
        return (remaining - 1) .. " left", "plain"
    end,
}

DEFS.j_seltzer = {
    main = function(joker)
        local n = math.max(0, math.floor(tonumber(joker.runtime_counter) or 0))
        return n, "plain"
    end,
    note = function() return "hands", "plain" end,
}

DEFS.j_turtle_bean = {
    main = function(joker) return math.max(0, math.floor(tonumber(joker.runtime_counter) or 0)), "plain" end,
    note = function() return "rounds", "plain" end,
}

DEFS.j_invisible = {
    main = function(joker)
        return math.floor(tonumber(joker.runtime_counter) or 0) .. "/2", "plain"
    end,
}

-- Retrigger Jokers show how many extra passes they are granting the current selection, which is
-- the one number a player cannot count off the card art.
local function retrigger_def(pred)
    return {
        main = function(_, ctx)
            local n = 0
            for _, node in ipairs(ctx.scoring) do
                if pred(ctx.game, node.card_data or {}, node, ctx) then n = n + 1 end
            end
            if n == 0 then return nil end
            return n, "plain"
        end,
        note = function() return "retrig", "plain" end,
    }
end

DEFS.j_hack = retrigger_def(function(_, data)
    local r = tonumber(data.rank)
    return r ~= nil and r >= 2 and r <= 5
end)
DEFS.j_sock_and_buskin = retrigger_def(function(g, data) return rank_is_face(g, data.rank) end)
DEFS.j_hanging_chad = {
    main = function(joker, ctx)
        if #ctx.scoring == 0 then return nil end
        local n = tonumber(config_of(joker).extra) or 2
        return math.max(0, math.floor(n)), "plain"
    end,
    note = function() return "retrig", "plain" end,
}
DEFS.j_dusk = {
    main = function(_, ctx)
        if (tonumber(ctx.game.hands) or 0) > 1 then return nil end
        if #ctx.scoring == 0 then return nil end
        return #ctx.scoring, "plain"
    end,
    note = function() return "retrig", "plain" end,
}
DEFS.j_mime = {
    main = function(_, ctx)
        if #ctx.held == 0 then return nil end
        return #ctx.held, "plain"
    end,
    note = function() return "held", "plain" end,
}

-- Copycats: name what they are pointing at, which is the whole question with these two.
local function copy_target_note(joker, ctx)
    local list = ctx.game.jokers
    if type(list) ~= "table" then return nil end
    local target
    if (joker.def or {}).id == "j_brainstorm" then
        target = list[1]
    else
        for i, other in ipairs(list) do
            if other == joker then target = list[i + 1] break end
        end
    end
    if target == joker then return nil end
    if type(target) ~= "table" then return "none", "plain" end
    local def = target.def or {}
    if def.blueprint_compat ~= true and def.id ~= "j_blueprint" and def.id ~= "j_brainstorm" then
        return "N/A", "plain"
    end
    local name = tostring(target.name or def.name or "?")
    return name, "plain"
end

DEFS.j_blueprint = { main = copy_target_note }
DEFS.j_brainstorm = { main = copy_target_note }

-- ---------------------------------------------------------------------------------------------
-- Refresh
-- ---------------------------------------------------------------------------------------------

--- A cheap number that changes whenever any readout could have. Everything a definition reads is
--- either folded in here or covered by `generation`; recomputing the whole row every frame would
--- cost more than the draw it feeds.
local function signature(g)
    local s = generation * 1000003
    s = s + (tonumber(g.money) or 0) * 31
    s = s + (tonumber(g.hands) or 0) * 17
    s = s + (tonumber(g.discards) or 0) * 13
    s = s + (tonumber(g.tarots_used) or 0) * 7
    s = s + (tonumber(g.skipsTaken) or 0) * 11
    s = s + (g.blind_triggered_this_hand == true and 1 or 0)
    local list = g.jokers
    if type(list) == "table" then
        s = s + #list * 101
        for i, j in ipairs(list) do
            s = s + i * (
                (tonumber(j.stored_mult) or 0)
                + (tonumber(j.stored_chips) or 0) * 3
                + (tonumber(j.stored_xmult) or 1) * 997
                + (tonumber(j.runtime_counter) or 0) * 29
                + (tonumber(j.sell_cost) or 0) * 5
            )
        end
    end
    return s
end

local function apply_line(joker, key_text, key_kind, value, kind)
    if value == nil then
        joker[key_text] = nil
        joker[key_kind] = nil
        return
    end
    joker[key_text] = format_value(value, kind or "mult")
    joker[key_kind] = kind or "mult"
end

--- Rebuild `_jd_main` / `_jd_note` on every owned Joker, if anything they depend on moved.
---@param force boolean|nil rebuild even when the signature is unchanged (the tests use this)
function JokerDisplay.refresh(game, force)
    local g = game or G
    if not g or type(g.jokers) ~= "table" then return false end
    if not JokerDisplay.enabled(g) then return false end

    local sig = signature(g)
    if not force and sig == last_signature then return false end
    last_signature = sig

    local ctx = build_context(g)
    for _, joker in ipairs(g.jokers) do
        joker._jd_main, joker._jd_main_kind = nil, nil
        joker._jd_note, joker._jd_note_kind = nil, nil
        joker._jd_fit_w = nil
        local id = (joker.def or {}).id
        local def = type(id) == "string" and DEFS[id] or nil
        -- A Joker the Blind has switched off contributes nothing, so a number under it would be
        -- a lie; `Joker:is_sticker_debuffed` covers a spent Perishable the same way.
        local disabled = (joker.is_sticker_debuffed and joker:is_sticker_debuffed())
            or (g.boss_is_joker_debuffed and g:boss_is_joker_debuffed(joker))
        if def and not disabled then
            local ok, value, kind = pcall(def.main, joker, ctx)
            if ok then apply_line(joker, "_jd_main", "_jd_main_kind", value, kind) end
            if joker._jd_main and def.note then
                local ok2, note, note_kind = pcall(def.note, joker, ctx)
                if ok2 then apply_line(joker, "_jd_note", "_jd_note_kind", note, note_kind or "plain") end
            end
        end
    end
    return true
end

-- ---------------------------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------------------------

--- Trim a readout to the width it has, once per string per width rather than per frame.
---
--- Almost every readout is three or four characters and never comes near this; the ones that do
--- are the names Blueprint and To Do List carry.
local function fit_one(font, text, w)
    if text == nil then return nil end
    if font:getWidth(text) <= w then return text end
    local out = text
    while #out > 1 and font:getWidth(out) > w do
        out = out:sub(1, #out - 1)
    end
    return out
end

--- Lay the panel out for one Joker: the value, the note beside it if there is room, and the
--- panel width the two of them need.
---
--- `refresh` clears `_jd_fit_w` whenever it rebuilds a readout, so a matching width is proof the
--- cached layout is still the current one.
local function fit_panel(joker, font, w)
    if joker._jd_fit_w == w then return end
    joker._jd_fit_w = w

    local inner = math.max(8, w - PANEL_PAD_X * 2)
    local main = fit_one(font, joker._jd_main, inner)
    local main_w = font:getWidth(main)
    local note, note_w = nil, 0
    if joker._jd_note then
        -- The note is the first thing to go: it is context for the number, and a truncated
        -- "(Diamo" is worse than nothing.
        local candidate_w = font:getWidth(joker._jd_note)
        if main_w + NOTE_GAP + candidate_w <= inner then
            note, note_w = joker._jd_note, candidate_w
        end
    end

    joker._jd_main_fit = main
    joker._jd_main_w = main_w
    joker._jd_note_fit = note
    joker._jd_note_w = note_w
    joker._jd_panel_w = main_w + (note and (NOTE_GAP + note_w) or 0) + PANEL_PAD_X * 2
end

--- Draw the readouts under a row of Jokers.
---
--- Each one is its own small panel hanging off the bottom of its card, the way the mod's row
--- sits under a Joker rather than being part of the card area behind it. The panel is only as
--- wide as its text, which is what keeps neighbours clear of each other once the row fans and a
--- column is down to about 45 px.
---
--- Called once per row, after every Joker in it has been drawn, so a panel is never covered by
--- the neighbour overlapping it from the right. Visibility is the caller's business: `TopUI`
--- flips `states.visible` on for the duration of each card's own draw and back off again, so a
--- test here would find the whole row invisible.
---@param jokers table[] the row, in slot order
---@param column_w number|nil horizontal budget per readout; defaults to the card width
function JokerDisplay.draw_row(game, jokers, column_w)
    local g = game or G
    if not JokerDisplay.enabled(g) then return end
    if type(jokers) ~= "table" or #jokers == 0 then return end
    JokerDisplay.refresh(g)

    local font, line_h = readout_font(g)
    if not font then return end
    local box_h = line_h + PANEL_PAD_Y * 2
    local prev_font = love.graphics.getFont()
    love.graphics.setFont(font)

    local C = g.C or {}
    local fill = C.TOOLTIP or C.PANEL or { 0.12, 0.14, 0.2, 1 }
    local shadow = (C.BLOCK and C.BLOCK.SHADOW) or { 0, 0, 0, 0.35 }
    local dim = C.DARK_WHITE or C.GREY or { 0.8, 0.8, 0.8, 1 }

    for _, joker in ipairs(jokers) do
        if joker and joker._jd_main and joker.face_up and joker.VT then
            local vt = joker.VT
            local scale = (joker.get_render_scale and joker:get_render_scale()) or vt.scale or 1
            local off = joker.collision_offset or { x = 0, y = 0 }
            local card_w = (vt.w or 70) * scale
            local card_h = (vt.h or 94) * scale
            local budget = tonumber(column_w) or 0
            if budget <= 0 then budget = card_w end

            fit_panel(joker, font, budget)

            local panel_w = joker._jd_panel_w
            local px = math.floor(vt.x + off.x + (card_w - panel_w) * 0.5 + 0.5)
            local py = math.floor(vt.y + off.y + card_h + PANEL_OFFSET_Y + 0.5)

            if _G.draw_rect_with_shadow then
                draw_rect_with_shadow(px, py, panel_w, box_h, 2, 0, fill, shadow, 1)
            else
                love.graphics.setColor(fill[1], fill[2], fill[3], fill[4] or 1)
                love.graphics.rectangle("fill", px, py, panel_w, box_h, 2, 2)
            end

            local tx = px + PANEL_PAD_X
            local ty = py + PANEL_PAD_Y
            local c = colour_for_kind(g, joker._jd_main_kind)
            love.graphics.setColor(c[1], c[2], c[3], 1)
            TextCache.print(joker._jd_main_fit, tx, ty)

            if joker._jd_note_fit then
                local nc = (joker._jd_note_kind == "plain") and dim or colour_for_kind(g, joker._jd_note_kind)
                love.graphics.setColor(nc[1], nc[2], nc[3], 1)
                TextCache.print(joker._jd_note_fit, tx + joker._jd_main_w + NOTE_GAP, ty)
            end
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
    if prev_font then love.graphics.setFont(prev_font) end
end

--- Vertical room the panels need under the cards, so whatever the row sits above can move clear.
--- Zero when the setting is off or nothing in the row has anything to say.
---@return number
function JokerDisplay.band_height(game)
    local g = game or G
    if not JokerDisplay.enabled(g) then return 0 end
    if type(g.jokers) ~= "table" or #g.jokers == 0 then return 0 end
    JokerDisplay.refresh(g)
    for _, joker in ipairs(g.jokers) do
        if joker._jd_main then return PANEL_OFFSET_Y + panel_height(g) end
    end
    return 0
end

--- Exposed for the tests; nothing in the game reads it.
JokerDisplay.DEFS = DEFS

return JokerDisplay
