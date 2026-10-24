--- Deck Info: the run's cards on the touch screen, the reference's 13x4 deck table on the
--- readout above it.
---
--- The base game makes you pick one or the other -- `deck_preview` is the table
--- (`UI_definitions.lua:469-620`) and `view_deck` is the card fan (`:3233`), and they are
--- separate modals over one screen. Two screens dissolve that: the table is static while the
--- overlay is open, so it lives on the top screen through `TextCache` at almost no cost, and
--- the bottom screen keeps the cards, which are the part worth touching.
---
--- Vouchers used to live here as a second page. They are run state, not deck state, so they
--- moved to `run_info_ui.lua` where the reference keeps them.
local DeckViewUI = {}
local TextCache = require("text_cache")
local Fonts = require("fonts")
local SCREEN_W, SCREEN_H = 320, 240
local CARD_W, CARD_H = 71, 95
local TAP_THRESHOLD = 15

local TOP_W, TOP_H = 400, 240

local SUITS = { "Spades", "Hearts", "Clubs", "Diamonds" }

local SUIT_SYMBOLS = {
    Hearts = "H",
    Clubs = "C",
    Diamonds = "D",
    Spades = "S",
}

-- Tab strip across the top of the touch screen.
local TAB_X, TAB_Y, TAB_W = 6, 4, 308

sysDepth = 0
buttonHeight = 1
textHeight = 2
signHeight = 3
jokerHeight = 2
PopupHeight = 4

--- Every playing card in the run, tagged with whether it is still in the draw pile.
---
--- The deck view used to build from the draw pile alone, so a card you had just enhanced
--- vanished from it. The reference always lists the whole deck and greys what is no longer
--- drawable (`UI_definitions.lua:3260-3266`), which is both tabs' shared behaviour: the
--- Remaining tab greys, the Full Deck tab does not.
---@param game table
---@return table[] entries `{ data = card_data, in_draw = boolean }`
function DeckViewUI.collect_run_cards(game)
    local entries = {}
    local deck = game and game.deck
    for _, c in ipairs((deck and deck.cards) or {}) do
        entries[#entries + 1] = { data = c, in_draw = true }
    end
    for _, c in ipairs((deck and deck.discard_pile) or {}) do
        entries[#entries + 1] = { data = c, in_draw = false }
    end
    -- Cards sitting in the player's hand are out of the draw pile but still in the deck.
    for _, c in ipairs((game and game.hand and game.hand.cards) or {}) do
        entries[#entries + 1] = { data = c, in_draw = false }
    end
    return entries
end

--- Group tagged entries by suit, ranked low to high.
---@param entries table[]
---@return table<string, table[]>
function DeckViewUI.group_entries_by_suit(entries)
    local by_suit = {}
    for _, suit in ipairs(SUITS) do
        by_suit[suit] = {}
    end
    for _, entry in ipairs(entries or {}) do
        local suit = entry and entry.data and entry.data.suit
        if suit and by_suit[suit] then
            by_suit[suit][#by_suit[suit] + 1] = entry
        end
    end
    for _, suit in ipairs(SUITS) do
        table.sort(by_suit[suit], function(a, b)
            local ra, rb = tonumber(a.data.rank) or 0, tonumber(b.data.rank) or 0
            if ra ~= rb then return ra < rb end
            -- Stable within a rank: drawable copies first, so the gaps read left to right.
            return (a.in_draw and 1 or 0) > (b.in_draw and 1 or 0)
        end)
    end
    return by_suit
end

---@param game table
---@return string "remaining" | "full"
function DeckViewUI.mode(game)
    return game and game._deck_view_mode == "full" and "full" or "remaining"
end

local ROW_GAP = 2
local ROW_PAD_Y = 1

--- Overlapping row step (same idea as `Game:_compute_fanned_joker_row`).
---@return number step
---@return number total_span
---@return number start_x offset within `area_w`
local function compute_fanned_step(n, area_w, card_w, gap)
    gap = gap or ROW_GAP
    n = tonumber(n) or 0
    card_w = tonumber(card_w) or CARD_W
    area_w = tonumber(area_w) or SCREEN_W
    if n <= 0 then return 0, 0, 0 end
    if n == 1 then
        return 0, card_w, math.floor((area_w - card_w) * 0.5 + 0.5)
    end
    local natural_step = card_w + gap
    local natural_span = card_w + (n - 1) * natural_step
    local step, total_span
    if natural_span <= area_w then
        step = natural_step
        total_span = natural_span
    else
        step = (area_w - card_w) / (n - 1)
        total_span = (n - 1) * step + card_w
    end
    local start_x = math.floor((area_w - total_span) * 0.5 + 0.5)
    return step, total_span, start_x
end

--- Fixed geometry: four suit rows always, whether or not a suit still has cards.
---
--- The rows used to size themselves to however many suits were non-empty, so playing out your
--- last Club made every remaining card jump and grow. A deck screen that reflows while you
--- read it is worse than one with a gap in it, and the reference draws a band per suit
--- regardless (`UI_definitions.lua:3244-3252`).
function DeckViewUI._chrome_metrics()
    local margin_x = 4
    local rows_y = TAB_Y + 23 + 4
    local row_step = 43
    local row_h = 40
    local scale = math.min(1, (row_h - ROW_PAD_Y * 2) / CARD_H)
    local card_w = CARD_W * scale
    local card_h = CARD_H * scale
    local row_start_x = 22
    return {
        margin_x = margin_x,
        rows_y = rows_y,
        row_step = row_step,
        row_h = row_h,
        label_dy = math.floor((row_h - 15) * 0.5 + 0.5),
        area_w = SCREEN_W - row_start_x - 10,
        row_start_x = row_start_x,
        scale = scale,
        card_w = card_w,
        card_h = card_h,
    }
end

function DeckViewUI._layout_row(nodes, m, row_y)
    local n = #(nodes or {})
    if n == 0 then return end
    local step, _, rel_start = compute_fanned_step(n, m.area_w, m.card_w, ROW_GAP)
    local card_y = row_y + math.floor((m.row_h - m.card_h) * 0.5 + 0.5)
    local x = m.row_start_x + rel_start
    for i, node in ipairs(nodes) do
        if node and node.T then
            local px = x + (i - 1) * step
            node.T.x = px
            node.T.y = card_y
            node.T.r = 0
            node.T.scale = m.scale
            if node.collision_offset then
                node.collision_offset.x = 0
                node.collision_offset.y = 0
            end
            if not (node.states and node.states.drag and node.states.drag.is) then
                node.VT.x = px
                node.VT.y = card_y
                node.VT.r = 0
                node.VT.scale = m.scale
            end
        end
    end
end

function DeckViewUI.layout(game)
    local rows = game._deck_view_rows
    if type(rows) ~= "table" then return end
    local m = DeckViewUI._chrome_metrics()
    for row_i, suit in ipairs(SUITS) do
        DeckViewUI._layout_row(rows[suit], m, m.rows_y + (row_i - 1) * m.row_step)
    end
end

function DeckViewUI.build(game)
    DeckViewUI.destroy(game)
    if not game or not game.deck then return end

    game._deck_view_rows = {}
    game._deck_view_nodes = {}
    for _, suit in ipairs(SUITS) do
        game._deck_view_rows[suit] = {}
    end

    local by_suit = DeckViewUI.group_entries_by_suit(DeckViewUI.collect_run_cards(game))
    for _, suit in ipairs(SUITS) do
        for _, entry in ipairs(by_suit[suit]) do
            local copy = Deck.copy_card_data(entry.data)
            if copy and game.ensure_card_uid then
                game:ensure_card_uid(copy)
            end
            local node = Card(0, 0, CARD_W, CARD_H, copy, nil, { face_up = true })
            node._deck_view_card = true
            node._deck_view_in_draw = entry.in_draw and true or false
            node.states.click.can = true
            node.states.drag.can = true
            game:add(node)
            game._deck_view_rows[suit][#game._deck_view_rows[suit] + 1] = node
            game._deck_view_nodes[#game._deck_view_nodes + 1] = node
        end
    end

    DeckViewUI.layout(game)
    DeckViewUI.refresh_readout(game)

    if game.hand and game.hand.card_nodes then
        for _, node in ipairs(game.hand.card_nodes) do
            node.states.visible = false
            node._deck_view_hidden = true
        end
    end
end

function DeckViewUI.destroy(game)
    if not game then return end
    for _, node in ipairs(game._deck_view_nodes or {}) do
        if node then
            node.selected = false
            game:remove(node)
        end
    end
    game._deck_view_rows = nil
    game._deck_view_nodes = nil
    game._deck_view_readout = nil

    if game.hand and game.hand.card_nodes then
        for _, node in ipairs(game.hand.card_nodes) do
            if node and node._deck_view_hidden then
                node.states.visible = true
                node._deck_view_hidden = nil
            end
        end
    end
end

function DeckViewUI.toggle_tooltip(game, node)
    if not game or not node or not node._deck_view_card then return end
    if game.active_tooltip_card == node then
        game.active_tooltip_card = nil
    else
        game.active_tooltip_card = node
        game.active_tooltip_joker = nil
        game.active_tooltip_consumable_index = nil
        if game.move_to_front then
            game:move_to_front(node)
        end
    end
end

function DeckViewUI.get_node_at(game, x, y)
    for i = #(game._deck_view_nodes or {}), 1, -1 do
        local node = game._deck_view_nodes[i]
        if node and node.states and node.states.click.can and game:point_in_rect(x, y, node) then
            return node
        end
    end
    return nil
end

--- Point-in-rect without depending on `Game`, so the header controls can be hit-tested from
--- a test as well as from a touch.
local function in_rect(r, x, y)
    return type(r) == "table" and x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
end

--- Pick a tab outright rather than cycling, so a touch lands where it was aimed.
---@param game table
---@param index integer 1 Remaining, 2 Full Deck
function DeckViewUI.set_mode(game, index)
    local want = (tonumber(index) == 2) and "full" or "remaining"
    if DeckViewUI.mode(game) == want then return end
    game._deck_view_mode = want
    DeckViewUI.refresh_readout(game)
    Sfx.play("cardSlide1")
end

--- Tabs and the Close button, checked before the cards so a tap on the chrome never grabs a
--- card behind it. Returns true when the press was consumed.
---@return boolean
function DeckViewUI.handle_header_touch(game, x, y)
    if in_rect(game._deck_view_close_rect, x, y) then
        Sfx.play("cancel")
        game:exit_deck_view()
        return true
    end
    for i, r in ipairs(game._deck_view_tab_rects or {}) do
        if in_rect(r, x, y) then
            DeckViewUI.set_mode(game, i)
            return true
        end
    end
    return false
end

function DeckViewUI.handle_touchpressed(game, id, x, y)
    if DeckViewUI.handle_header_touch(game, x, y) then
        game.dragging = nil
        return
    end
    game.touch_start_x = x
    game.touch_start_y = y
    local node = DeckViewUI.get_node_at(game, x, y)
    if node and node.touchpressed then
        node:touchpressed(id, x, y)
        game.dragging = node
        game:move_to_front(node)
    else
        game.dragging = nil
    end
end

function DeckViewUI.handle_touchmoved(game, id, x, y, dx, dy)
    if game.dragging and game.dragging.touchmoved then
        game.dragging:touchmoved(id, x, y, dx, dy)
    end
end

function DeckViewUI.handle_touchreleased(game, id, x, y)
    local released = game.dragging
    if released and released.touchreleased then
        released:touchreleased(id, x, y)
    end
    local start_x = game.touch_start_x or x
    local start_y = game.touch_start_y or y
    local dx = x - start_x
    local dy = y - start_y
    local dist = math.sqrt(dx * dx + dy * dy)
    if released and released._deck_view_card and dist < TAP_THRESHOLD then
        DeckViewUI.toggle_tooltip(game, released)
    elseif released and released._deck_view_card and dist >= TAP_THRESHOLD then
        DeckViewUI.layout(game)
    elseif dist < TAP_THRESHOLD then
        game.active_tooltip_card = nil
    end
    game.dragging = nil
end

--- The shoulders switch tabs, which is what the pips beside them advertise and what the
--- reference binds them to (`create_tabs`, `UI_definitions.lua:2091`).
---@return boolean handled
function DeckViewUI.handle_gamepad(game, button)
    if not game or not game._deck_view_open then return false end
    if button == "leftshoulder" or button == "dpleft" or button == "left" then
        DeckViewUI.set_mode(game, 1)
        return true
    end
    if button == "rightshoulder" or button == "dpright" or button == "right" then
        DeckViewUI.set_mode(game, 2)
        return true
    end
    -- SELECT steps on to Run Info rather than closing, so both overlays stay reachable on an
    -- Old 3DS, where ZL/ZR do not physically exist (`input_bindings.lua:331`). B/X/A/Y close.
    if button == "back" or button == "select" then
        Sfx.play("cardSlide1")
        game:toggle_run_info()
        return true
    end
    if (game.is_menu_back and game:is_menu_back(button))
        or (game.is_menu_activate and game:is_menu_activate(button)) then
        Sfx.play("cancel")
        game:exit_deck_view()
        return true
    end
    return false
end
-- ---------------------------------------------------------------------------
-- Rank and suit counting
-- ---------------------------------------------------------------------------

local RANKS = {}
local RANK_LABELS = {}
for r = 2, 14 do
    RANKS[#RANKS + 1] = r
    if r <= 10 then
        RANK_LABELS[r] = tostring(r)
    elseif r == 11 then
        RANK_LABELS[r] = "J"
    elseif r == 12 then
        RANK_LABELS[r] = "Q"
    elseif r == 13 then
        RANK_LABELS[r] = "K"
    else
        RANK_LABELS[r] = "A"
    end
end

--- Ace first, matching the reference's rank header (`UI_definitions.lua:507`).
local RANKS_DESC = {}
for i = #RANKS, 1, -1 do
    RANKS_DESC[#RANKS_DESC + 1] = RANKS[i]
end
DeckViewUI.RANKS_DESC = RANKS_DESC

--- Suit, face, numbered and ace counts over a set of cards. The reference shows all of these
--- beside the rank column (`UI_definitions.lua:3390-3420`). Stone cards are excluded from
--- every tally because they have no rank or suit (`UI_definitions.lua:3363`).
---@param cards table[]
---@return table
function DeckViewUI.count_tallies(cards)
    local out = {
        suits = { Hearts = 0, Clubs = 0, Diamonds = 0, Spades = 0 },
        face = 0, numbered = 0, ace = 0, total = 0,
    }
    for _, card_data in ipairs(cards or {}) do
        local enh = card_data and card_data.enhancement
        if card_data and enh ~= "stone" then
            local suit = card_data.suit
            if suit and out.suits[suit] ~= nil then
                out.suits[suit] = out.suits[suit] + 1
            end
            local rank = tonumber(card_data.rank)
            if rank then
                if rank >= 11 and rank <= 13 then
                    out.face = out.face + 1
                elseif rank == 14 then
                    out.ace = out.ace + 1
                elseif rank >= 2 then
                    out.numbered = out.numbered + 1
                end
            end
            out.total = out.total + 1
        end
    end
    return out
end

--- Everything the top screen reads, derived once.
---
--- The deck cannot change while a modal is over it, so this is built on entry and rebuilt only
--- when the tab flips. It used to run in the draw path: `draw_matrix` walked
--- the mode's card list, then `draw_top` walked it again for the tallies and a third time for the
--- drawable counter -- three passes over the whole run's cards, each allocating a table per
--- card, sixty times a second, for numbers that had not moved. Per-frame allocation is the
--- thing this port is least able to afford (`CLAUDE.md`, "the interpreter is the budget").
---@param game table
function DeckViewUI.refresh_readout(game)
    if not game then return end
    local entries = DeckViewUI.collect_run_cards(game)
    local full = DeckViewUI.mode(game) == "full"
    local cards, drawable = {}, 0
    for _, entry in ipairs(entries) do
        if entry.in_draw then drawable = drawable + 1 end
        if full or entry.in_draw then cards[#cards + 1] = entry.data end
    end
    local grid, stones = DeckViewUI.count_suit_ranks(cards)
    game._deck_view_readout = {
        grid = grid,
        stones = stones,
        tallies = DeckViewUI.count_tallies(cards),
        drawable = drawable,
        owned = #entries,
    }
end

--- The cached readout, built on demand if a caller reaches the draw path first.
---@param game table
---@return table
function DeckViewUI.readout(game)
    if not game._deck_view_readout then DeckViewUI.refresh_readout(game) end
    return game._deck_view_readout
end

--- The 13x4 grid the whole readout is built on: how many cards sit at each suit and rank.
---
--- This is the shape of `deck_preview` (`UI_definitions.lua:520-528`), and the reason it is
--- worth the table rather than two separate strips of totals: a suit total tells you a flush
--- is live, a rank total tells you a pair is live, and only the intersection tells you which
--- flush or which pair. Stone cards have neither, so they are counted apart.
---@param cards table[]
---@return table<string, table<number, integer>> grid, integer stones
function DeckViewUI.count_suit_ranks(cards)
    local grid = {}
    for _, suit in ipairs(SUITS) do
        grid[suit] = {}
        for _, r in ipairs(RANKS) do
            grid[suit][r] = 0
        end
    end
    local stones = 0
    for _, card_data in ipairs(cards or {}) do
        if card_data then
            if card_data.enhancement == "stone" then
                stones = stones + 1
            else
                local suit, rank = card_data.suit, tonumber(card_data.rank)
                if suit and rank and grid[suit] and grid[suit][rank] ~= nil then
                    grid[suit][rank] = grid[suit][rank] + 1
                end
            end
        end
    end
    return grid, stones
end

-- ---------------------------------------------------------------------------
-- Drawing helpers
-- ---------------------------------------------------------------------------

--- `mix_colours` from the reference (`misc_functions.lua`), which the deck preview uses to
--- tint each suit row down towards the panel colour so four saturated bands do not fight the
--- numbers sitting on them.
local function mix(a, b, t)
    return {
        a[1] * (1 - t) + b[1] * t,
        a[2] * (1 - t) + b[2] * t,
        a[3] * (1 - t) + b[3] * t,
        1,
    }
end

local function suit_colour(game, suit)
    local c = game.C.SUITS and game.C.SUITS[suit]
    return c or game.C.WHITE
end

--- Reference tab pills: RED, the chosen one full-bright and the rest darkened, with the
--- shoulder-button pips sitting outside them (`create_tabs`, `UI_definitions.lua:2088-2092`).
--- Records a rect per tab so a touch can pick one.
---@return number next_y
local function draw_tabs(game, x, y, w, labels, current, rects)
    local pip_w = 13
    local inner = w - pip_w * 2 - 8
    local gap = 3
    local tw = (inner - gap * (#labels - 1)) / #labels

    -- L and R exist on both console revisions; only ZL/ZR are New 3DS-only. The pips follow
    -- the remappable roles and, like every other prompt in the port, only show while the pad
    -- owns focus (`shop_ui.lua:425`).
    if game.draw_button_pip and game.gamepad_focus_visible and game:gamepad_focus_visible() then
        love.graphics.setColor(game.C.WHITE)
        game:draw_button_pip(game:get_button_for_role("shoulder_l"), x, y + 4, 11)
        game:draw_button_pip(game:get_button_for_role("shoulder_r"), x + w - 11, y + 4, 11)
    end

    love.graphics.setFont(game.FONTS.PIXEL.SMALL)
    for i, label in ipairs(labels) do
        local tx = math.floor(x + pip_w + 4 + (i - 1) * (tw + gap))
        local on = (i == current)
        local face = on and game.C.RED or mix(game.C.RED, game.C.BLOCK.BACK, 0.45)
        draw_button_with_shadow(tx, y, tw, 19, 3, 0, face, game.C.BLOCK.SHADOW, 2)
        love.graphics.setColor(on and game.C.WHITE or game.C.DARK_WHITE)
        TextCache.printf(label, tx, y + 4, tw, "center")
        if rects then rects[i] = { x = tx, y = y, w = tw, h = 19 } end
    end
    return y + 23
end

--- Orange Back/Close button with its B pip, as the reference's generic-options footer.
local function draw_close_button(game, x, y, w, label)
    draw_button_with_shadow(x, y, w, 17, 3, 0, game.C.ORANGE, game.C.BLOCK.SHADOW, 2)
    love.graphics.setColor(game.C.WHITE)
    love.graphics.setFont(game.FONTS.PIXEL.SMALL)
    TextCache.printf(label, x, y + 3, w, "center")
    if game.draw_button_pip and game.gamepad_focus_visible and game:gamepad_focus_visible() then
        game:draw_button_pip(game:get_button_for_role("cancel"), x + 4, y + 3, 11)
    end
    game._deck_view_close_rect = { x = x, y = y, w = w, h = 17 }
end

local DECK_SPRITE_SCALE = 0.62

local function draw_deck_sprite(game, def, x, y, scale)
    if not def or not game.get_deck_back_quad then return false end
    -- A mod deck's back is its own image, not a cell of `centers`.
    local atlas, quad = game:get_deck_back_quad(def.id)
    if not quad then return false end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(atlas.image, quad, x, y, 0, scale, scale)
    return true
end

local function draw_stake_chip(game, stake_def, x, y, scale)
    local pos = tonumber(stake_def and stake_def.pos)
    if not pos then return false end
    if game.ensure_asset_atlas_loaded then
        game:ensure_asset_atlas_loaded("chips")
    end
    local atlas = game.ASSET_ATLAS and game.ASSET_ATLAS.chips
    if not atlas or not atlas.image then return false end
    local quad = game:atlas_cell_quad(atlas, pos)
    if not quad then return false end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(atlas.image, quad, x, y, 0, scale, scale)
    return true
end

-- ---------------------------------------------------------------------------
-- The matrix
-- ---------------------------------------------------------------------------

--- The reference's deck readout: a rank header with the count of that rank across the whole
--- deck, then one tinted row per suit holding the count at every intersection, with the suit
--- totals down the left (`deck_preview`, `UI_definitions.lua:534-583`).
---
--- Every string here is stable while the overlay is open -- the deck cannot change behind a
--- modal -- so all 86 of them go through `TextCache`. Straight `print` would be 4.6 ms of
--- reshaping a frame on hardware, a quarter of the budget, for text that never moves.
---@param game table
---@param x number
---@param y number
---@param w number
---@param opts table|nil `{ label_w, cell_h, head_h }`
---@return number bottom_y
function DeckViewUI.draw_matrix(game, x, y, w, opts)
    opts = opts or {}
    local label_w = opts.label_w or 44
    local cell_h = opts.cell_h or 26
    local head_h = opts.head_h or 30
    local grid = DeckViewUI.readout(game).grid
    local cw = (w - label_w) / #RANKS_DESC

    local ink = game.C.BLOCK.BACK
    local plate_face = mix(game.C.JOKER_GREY, game.C.L_BLACK, 0.35)
    local plate_num = mix(game.C.JOKER_GREY, game.C.L_BLACK, 0.55)

    -- Header: the rank, then how many of it are left anywhere in the tracked set.
    for i, rank in ipairs(RANKS_DESC) do
        local cx = x + label_w + (i - 1) * cw
        local total = 0
        for _, suit in ipairs(SUITS) do total = total + grid[suit][rank] end

        love.graphics.setColor(rank >= 11 and rank <= 13 and plate_face or plate_num)
        draw_rounded_rect(cx + 1, y, cw - 2, head_h - 3, 3, 0, "fill")
        love.graphics.setFont(game.FONTS.PIXEL.SMALL)
        love.graphics.setColor(ink)
        TextCache.printf(RANK_LABELS[rank], cx, y + 2, cw, "center")

        love.graphics.setColor(game.C.L_BLACK)
        draw_rounded_rect(cx + 2, y + 12, cw - 4, head_h - 14, 2, 0, "fill")
        love.graphics.setFont(game.FONTS.PIXEL.MICRO or game.FONTS.PIXEL.SMALL)
        love.graphics.setColor(game.C.WHITE)
        TextCache.printf(tostring(total), cx, y + 13, cw, "center")
    end

    -- One tinted band per suit, its total inset on the left, then the thirteen cells.
    local dim = { 1, 1, 1, 0.2 }
    for j, suit in ipairs(SUITS) do
        local ry = y + head_h + (j - 1) * cell_h
        local sc = suit_colour(game, suit)
        love.graphics.setColor(mix(sc, game.C.L_BLACK, 0.62))
        draw_rounded_rect(x, ry, w, cell_h - 2, 3, 0, "fill")

        love.graphics.setColor(game.C.BLOCK.BACK)
        draw_rounded_rect(x + 2, ry + 2, label_w - 6, cell_h - 6, 3, 0, "fill")

        local suit_total = 0
        for _, rank in ipairs(RANKS_DESC) do suit_total = suit_total + grid[suit][rank] end

        love.graphics.setFont(game.FONTS.PIXEL.SMALL)
        love.graphics.setColor(sc)
        TextCache.print(SUIT_SYMBOLS[suit], x + 3, ry + 4)
        love.graphics.setColor(game.C.WHITE)
        TextCache.printf(tostring(suit_total), x + 11, ry + 4, label_w - 16, "right")

        local cell_ty = ry + math.floor((cell_h - 4 - 11) * 0.5 + 0.5)
        for i, rank in ipairs(RANKS_DESC) do
            local cx = x + label_w + (i - 1) * cw
            local n = grid[suit][rank]
            -- An empty cell prints a dash rather than a greyed "0": same information, and it
            -- keeps each string to a single baked colour so the text cache never thrashes.
            if n > 0 then
                love.graphics.setColor(game.C.WHITE)
                TextCache.printf(tostring(n), cx, cell_ty, cw, "center")
            else
                love.graphics.setColor(dim)
                TextCache.printf("-", cx, cell_ty, cw, "center")
            end
        end
    end

    return y + head_h + #SUITS * cell_h
end

-- ---------------------------------------------------------------------------
-- Top screen: the deck, the stake, and the matrix
-- ---------------------------------------------------------------------------

function DeckViewUI.draw_top(screen, game)
    love.graphics.setColor(game.C.BLACK)
    love.graphics.rectangle("fill", 0, 0, TOP_W, TOP_H)

    love.graphics.setFont(game.FONTS.PIXEL.SMALL)
    love.graphics.setColor(game.C.JOKER_GREY)
    TextCache.print(I18N.text("deck_view.deck", nil, "Deck"), 8, 6)

    local deck_id = game.selected_deck_id or game._pending_deck_id or "b_red"
    local deck_def = (DECK_DEFS_BY_ID and DECK_DEFS_BY_ID[deck_id]) or (DECK_DEFS and DECK_DEFS[1])
    draw_deck_sprite(game, deck_def, 8, 20, DECK_SPRITE_SCALE)
    love.graphics.setFont(game.FONTS.PIXEL.PRICE)
    love.graphics.setColor(game.C.WHITE)
    TextCache.print(deck_def and I18N.content_name("deck", deck_def.id, deck_def.name) or I18N.text("deck_view.deck", nil, "Deck"), 58, 22)
    local deck_rule = deck_def and I18N.content_text("deck", deck_def.id, deck_def.description or "") or ""
    love.graphics.setFont(Fonts.fit_block(game, game.FONTS.PIXEL.SMALL, deck_rule, 120, 44))
    love.graphics.setColor(game.C.JOKER_GREY)
    TextCache.printf(deck_rule, 58, 40, 120, "left")

    local stake_id = game.selected_stake_id or game._pending_stake_id or "stake_white"
    local stake_def = STAKE_DEFS_BY_ID and STAKE_DEFS_BY_ID[stake_id]
    draw_stake_chip(game, stake_def, 190, 20, 1)
    love.graphics.setFont(game.FONTS.PIXEL.PRICE)
    love.graphics.setColor(game.C.WHITE)
    TextCache.print(stake_def and I18N.content_name("stake", stake_def.id, stake_def.name) or I18N.text("deck_view.stake", nil, "Stake"), 224, 22)
    local stake_rule = stake_def and I18N.content_text("stake", stake_def.id, stake_def.description or "") or ""
    love.graphics.setFont(Fonts.fit_block(game, game.FONTS.PIXEL.MICRO, stake_rule, 168, 44))
    love.graphics.setColor(game.C.JOKER_GREY)
    TextCache.printf(stake_rule, 224, 40, 168, "left")

    DeckViewUI.draw_matrix(game, 0, 86, TOP_W, { label_w = 44, cell_h = 26, head_h = 30 })

    local readout = DeckViewUI.readout(game)
    local t = readout.tallies
    local tally_text = string.format(I18N.text("deck_view.tallies", nil, "Aces %s   Faces %s   Numbered %s"), t.ace, t.face, t.numbered)
    love.graphics.setFont(Fonts.fit(game, game.FONTS.PIXEL.SMALL, tally_text, 188))
    love.graphics.setColor(game.C.JOKER_GREY)
    love.graphics.print(tally_text, 8, 224)

    love.graphics.setColor(game.C.WHITE)
    love.graphics.printf(string.format(I18N.text("deck_view.drawable", nil, "%s / %s drawable"), readout.drawable, readout.owned),
        200, 224, 192, "right")
    love.graphics.setColor(1, 1, 1, 1)
end

-- ---------------------------------------------------------------------------
-- Bottom screen: the cards
-- ---------------------------------------------------------------------------

function DeckViewUI.draw_bottom(game)
    love.graphics.setColor(game.C.BLACK)
    love.graphics.rectangle("fill", 0, 0, SCREEN_W, SCREEN_H)

    -- Greying is what distinguishes the two modes; both list every card in the run.
    local grey_spent = DeckViewUI.mode(game) == "remaining"
    for _, node in ipairs(game._deck_view_nodes or {}) do
        if node then
            node.greyed = grey_spent and node._deck_view_in_draw == false or nil
            if node.states then node.states.visible = true end
        end
    end

    game._deck_view_tab_rects = game._deck_view_tab_rects or {}
    draw_tabs(game, TAB_X, TAB_Y, TAB_W, { I18N.text("deck_view.remaining", nil, "Remaining"), I18N.text("deck_view.full_deck", nil, "Full Deck") },
        DeckViewUI.mode(game) == "full" and 2 or 1, game._deck_view_tab_rects)

    local m = DeckViewUI._chrome_metrics()
    for j, suit in ipairs(SUITS) do
        local ry = m.rows_y + (j - 1) * m.row_step
        love.graphics.setColor(mix(suit_colour(game, suit), game.C.L_BLACK, 0.68))
        draw_rounded_rect(m.margin_x, ry, SCREEN_W - m.margin_x * 2, m.row_h, 4, 0, "fill")
        love.graphics.setFont(game.FONTS.PIXEL.PRICE)
        love.graphics.setColor(suit_colour(game, suit))
        TextCache.print(SUIT_SYMBOLS[suit], m.margin_x + 4, ry + m.label_dy)
    end

    love.graphics.setColor(1, 1, 1, 1)
    for _, node in ipairs(game._deck_view_nodes or {}) do
        if node and node.draw then
            node:draw()
        end
    end

    love.graphics.setFont(game.FONTS.PIXEL.SMALL)
    love.graphics.setColor(game.C.JOKER_GREY)
    TextCache.print(I18N.text("deck_view.tap_hint", nil, "Tap a card to read it"), 8, 205)
    draw_close_button(game, 206, 216, 108, I18N.text("common.close", nil, "Close"))
    love.graphics.setColor(1, 1, 1, 1)
end

function DeckViewUI.draw_tooltips(game)
    for _, node in ipairs(game._deck_view_nodes or {}) do
        if node and node.draw_tooltip_overlay then
            node:draw_tooltip_overlay()
        end
    end
end

return DeckViewUI
