--- Run Info (ZL): the whole run state spread across both screens, with no tabs.
---
--- The reference packs this into one four-tab dialog -- Poker Hands, Blinds, Vouchers and
--- Stake (`UI_definitions.lua:3129-3151`) -- because it has a single screen to put it on.
--- Three of those four panels are small: three blind tokens, a row of voucher cards and one
--- stake chip fit the 400 px readout at once. So the top screen carries all three
--- permanently and the bottom screen carries the only list long enough to need the room,
--- which is the poker hands. Nothing to navigate, nothing hidden behind a shoulder button.
---
--- The port previously had no Run Info at all: ZL reopened the deck view with a hand-level
--- panel slid over it, Blinds were nowhere, and the Vouchers list lived on the deck screen.
--- This module is where all four of the reference's tabs now live.
local RunInfoUI = {}
local NumberFormat = require("number_format")
local TextCache = require("text_cache")
local Fonts = require("fonts")

local TOP_W, TOP_H = 400, 240
local SCREEN_W, SCREEN_H = 320, 240

-- Blind plates: three across the 400 px readout with an 6 px gutter.
local BLIND_X0, BLIND_STEP, BLIND_W, BLIND_H = 10, 130, 124, 86
local BLIND_Y = 20

-- The reference colours a blind's state plate by that state (`UI_definitions.lua:1554`).
local STATE_COLOUR = {
    Defeated = "GREY",
    Skipped = "BLUE",
    Upcoming = "ORANGE",
    Current = "RED",
}

--- Redeemed vouchers, in the order they were taken, with their catalog text.
---
--- Lives here rather than on the deck screen because a voucher is run state, not deck state:
--- the reference lists them on Run Info (`UI_definitions.lua:3140-3143`, `:3426`).
---@param game table
---@return table[] `{ id, name, description }`
function RunInfoUI.owned_vouchers(game)
    local out = {}
    local seen = {}
    local function add(id)
        if type(id) ~= "string" or id == "" or seen[id] then return end
        local def = VOUCHER_DEFS and VOUCHER_DEFS[id]
        if type(def) ~= "table" then return end
        seen[id] = true
        out[#out + 1] = {
            id = id,
            name = I18N.content_name("voucher", id, def.name or id),
            description = I18N.content_text("voucher", id, def.description or ""),
            pos = def.pos, def = def,
        }
    end
    local vs = (game and game.vouchers) or {}
    -- Both shapes are in use: an ordered list, and a set keyed by id.
    for _, id in ipairs(vs) do add(id) end
    local keys = {}
    for id, flag in pairs(vs) do
        if flag == true and type(id) == "string" then keys[#keys + 1] = id end
    end
    table.sort(keys)
    for _, id in ipairs(keys) do add(id) end
    return out
end

function RunInfoUI.held_tag_summary(game)
    local names, first_description = {}, nil
    for _, tag in ipairs((game and game.tags) or {}) do
        if tag and tag.type then
            local key = game.tag_key_for_id and game:tag_key_for_id(tag.id)
            local def = key and game.P_TAGS and game.P_TAGS[key]
            names[#names + 1] = I18N.content_name("tag", key,
                (def and def.name) or (tag.type:gsub("^%l", string.upper) .. " Tag"))
            if not first_description and Tag and Tag.get_description then
                first_description = I18N.content_text("tag", key, Tag.get_description(tag.type))
            end
        end
    end
    if #names == 0 then return nil end
    local summary = I18N.text("run_info.held", nil, "Held: ") .. table.concat(names, I18N.text("common.list_separator", nil, ", "))
    if #names == 1 and first_description and first_description ~= "" then
        summary = summary .. " — " .. first_description
    end
    return summary
end

--- Descriptions of every stake below `stake_id`, strongest first.
---
--- Stakes stack: a Blue Stake run is also running Red, Green and Black. The reference lists
--- the inherited ones under "Also applied:" (`UI_definitions.lua:3181-3204`). White is
--- skipped because "No modifiers." is not a modifier.
---@param stake_id string
---@return string[]
function RunInfoUI.inherited_stake_descriptions(stake_id)
    local out = {}
    local current = STAKE_DEFS_BY_ID and STAKE_DEFS_BY_ID[stake_id]
    local current_order = tonumber(current and current.order)
    if not current_order then return out end
    for _, def in ipairs(STAKE_DEFS or {}) do
        local order = tonumber(def.order)
        if order and order < current_order and def.id ~= "stake_white"
            and type(def.description) == "string" and def.description ~= "" then
            out[#out + 1] = I18N.content_text("stake", def.id, def.description)
        end
    end
    -- Nearest stake first: those are the ones the player just stepped up from.
    for i = 1, math.floor(#out / 2) do
        out[i], out[#out - i + 1] = out[#out - i + 1], out[i]
    end
    return out
end

--- Where a blind sits in the ante, as one of the reference's four states.
---
--- Derived rather than stored, except for Skipped: `Game.skips` holds the tag a skip *would*
--- award, not a record that one was taken, so `Game:skip_blind` marks `blinds_skipped`. A
--- skipped Big Blind reading "Defeated" is the one wrong answer this screen could give.
---@param game table
---@param index integer 1 Small, 2 Big, 3 Boss
---@return string
function RunInfoUI.blind_state(game, index)
    local current = tonumber(game and game.current_blind_index) or 1
    index = tonumber(index) or 1
    if index > current then return "Upcoming" end
    if index == current then return "Current" end
    local skipped = game and game.blinds_skipped
    if type(skipped) == "table" and skipped[index] then return "Skipped" end
    return "Defeated"
end

--- The three blinds of the current ante, in order, with everything the plate needs.
---@param game table
---@return table[] `{ index, name, target, reward, state, sprite_row }`
function RunInfoUI.blinds(game)
    local out = {}
    if not game then return out end
    for i = 1, 3 do
        local target = (game.get_blind_target and game:get_blind_target(i, game.ante)) or 0
        out[i] = {
            index = i,
            name = (game.get_blind_display_name and game:get_blind_display_name(i)) or I18N.text("hud.blind", nil, "Blind"),
            target = math.floor(tonumber(target) or 0),
            reward = (game.get_blind_reward and game:get_blind_reward(i)) or 0,
            state = RunInfoUI.blind_state(game, i),
            sprite_row = (game.get_blind_sprite_index and game:get_blind_sprite_index(i)) or 0,
        }
    end
    return out
end

--- Poker hands the player is allowed to see, with their live level, chips, mult and count.
---
--- `is_hand_stats_visible` hides the three secret hands until they have been played, which is
--- why the list length is not fixed and the row height below has to adapt to it.
---@param game table
---@return table[] `{ index, name, level, chips, mult, played }`
function RunInfoUI.visible_hands(game)
    local out = {}
    if not game then return out end
    for i, name in ipairs(game.handlist or {}) do
        if game.is_hand_stats_visible and game:is_hand_stats_visible(i) then
            local level, chips, mult = 1, 0, 0
            if game.get_hand_level_stats then
                level, chips, mult = game:get_hand_level_stats(i)
            end
            out[#out + 1] = {
                index = i,
                name = name,
                level = level,
                chips = chips,
                mult = mult,
                played = tonumber(game.hand_play_counts and game.hand_play_counts[i]) or 0,
            }
        end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Chrome
-- ---------------------------------------------------------------------------

--- The reference's overlay dialog: a 70%-alpha GREY scrim over the paused screen, a
--- JOKER_GREY frame with an emboss, and an L_BLACK inner panel
--- (`create_UIBox_generic_options`, `UI_definitions.lua:6333-6338`).
local function draw_dialog(game, x, y, w, h)
    local grey = game.C.GREY
    love.graphics.setColor(grey[1], grey[2], grey[3], 0.72)
    love.graphics.rectangle("fill", 0, 0, SCREEN_W, SCREEN_H)
    draw_rect_with_shadow(x, y, w, h, 7, 0, game.C.JOKER_GREY, game.C.BLOCK.SHADOW, 3)
    love.graphics.setColor(game.C.L_BLACK)
    draw_rounded_rect(x + 4, y + 4, w - 8, h - 8, 5, 0, "fill")
end

--- Orange Back button with its B pip, matching the reference's generic-options footer.
local function draw_back_button(game, x, y, w)
    draw_button_with_shadow(x, y, w, 17, 3, 0, game.C.ORANGE, game.C.BLOCK.SHADOW, 2)
    love.graphics.setColor(game.C.WHITE)
    local font = game.FONTS.PIXEL.LABEL
    love.graphics.setFont(font)
    TextCache.printf(I18N.text("common.back", nil, "Back"), x, Fonts.centre_y(game, font, y, 17), w, "center")
    if game.draw_button_pip and game.gamepad_focus_visible and game:gamepad_focus_visible() then
        game:draw_button_pip(game:get_button_for_role("cancel"), x + 4, y + 3, 11)
    end
    game._run_info_back_rect = { x = x, y = y, w = w, h = 17 }
end

-- ---------------------------------------------------------------------------
-- Top screen: blinds, vouchers, stake
-- ---------------------------------------------------------------------------

local VOUCHER_CELL_W, VOUCHER_CELL_H = 72, 95
local VOUCHER_SCALE = 0.78
local VOUCHER_AREA_X, VOUCHER_AREA_W = 10, 248
local VOUCHER_Y, VOUCHER_H = 132, 74

--- Overlapping fan, same rule as `DeckViewUI`'s rows and the joker tray: cards keep their
--- natural gap until the row would overflow, then they tuck under each other.
---@return number step, number start_x
local function fanned_step(n, area_w, card_w, gap)
    gap = gap or 4
    if n <= 0 then return 0, 0 end
    if n == 1 then return 0, math.floor((area_w - card_w) * 0.5 + 0.5) end
    local natural_step = card_w + gap
    local natural_span = card_w + (n - 1) * natural_step
    if natural_span <= area_w then
        return natural_step, math.floor((area_w - natural_span) * 0.5 + 0.5)
    end
    local step = (area_w - card_w) / (n - 1)
    return step, math.floor((area_w - ((n - 1) * step + card_w)) * 0.5 + 0.5)
end
RunInfoUI._fanned_step = fanned_step

local function draw_atlas_cell(game, atlas_name, index, x, y, scale)
    if game.ensure_asset_atlas_loaded then
        game:ensure_asset_atlas_loaded(atlas_name)
    end
    local atlas = game.ASSET_ATLAS and game.ASSET_ATLAS[atlas_name]
    if not atlas or not atlas.image then return false end
    local quad, cell_w, cell_h = game:atlas_cell_quad(atlas, index)
    if not quad then return false end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(atlas.image, quad, x, y, 0, scale, scale)
    return true, cell_w * scale, cell_h * scale
end

--- One blind: token, name, target, and the state plate underneath.
local function draw_blind_plate(game, b, x, y)
    draw_rect_with_shadow(x, y, BLIND_W, BLIND_H, 4, 0, game.C.BLOCK.BACK, game.C.BLOCK.SHADOW, 2)

    game:draw_blind_chip_sprite(b.sprite_row, x + 8 + 18, y + 8 + 18, 1.05)

    local name_font = Fonts.fit_block(game, game.FONTS.PIXEL.SMALL, b.name, 66, 30)
    love.graphics.setFont(name_font)
    love.graphics.setColor(game.C.WHITE)
    love.graphics.printf(b.name, x + 52, y + 6, 66, "left")

    local target = NumberFormat.format(b.target)
    love.graphics.setFont(Fonts.fit(game, game.FONTS.PIXEL.PRICE, target, 66))
    love.graphics.setColor(game.C.BLUE)
    love.graphics.printf(target, x + 52, y + 40, 66, "left")

    local col = game.C[STATE_COLOUR[b.state] or "GREY"] or game.C.GREY
    local plate_y, plate_w, plate_h = y + BLIND_H - 22, BLIND_W - 8, 18
    love.graphics.setColor(col)
    draw_rounded_rect(x + 4, plate_y, plate_w, plate_h, 3, 0, "fill")
    local state = I18N.text("run_info.state." .. b.state:lower(), nil, b.state)
    local font = Fonts.fit_line(game, game.FONTS.PIXEL.LABEL, state, plate_w - 8, plate_h - 4)
    love.graphics.setFont(font)
    love.graphics.setColor(game.C.WHITE)
    TextCache.printf(state, x + 4, Fonts.centre_y(game, font, plate_y, plate_h), plate_w, "center")
end

function RunInfoUI.draw_top(screen, game)
    love.graphics.setColor(game.C.BLACK)
    love.graphics.rectangle("fill", 0, 0, TOP_W, TOP_H)

    -- Headers: the ante centred in the strip above the blinds, and the two section names in
    -- the 15 px strip above the vouchers, clear of the held-tag line under the blinds.
    local label = game.FONTS.PIXEL.LABEL
    love.graphics.setFont(label)
    love.graphics.setColor(game.C.JOKER_GREY)
    love.graphics.print(I18N.text("run_info.ante_prefix", nil, "Ante ") .. tostring(tonumber(game.ante) or 1), 10, Fonts.centre_y(game, label, 0, BLIND_Y))
    local head_y = Fonts.centre_y(game, label, VOUCHER_Y - 15, 15)

    for i, b in ipairs(RunInfoUI.blinds(game)) do
        draw_blind_plate(game, b, BLIND_X0 + (i - 1) * BLIND_STEP, BLIND_Y)
    end

    local tag_summary = RunInfoUI.held_tag_summary(game)
    if tag_summary then
        love.graphics.setFont(game.FONTS.PIXEL.MICRO or game.FONTS.PIXEL.SMALL)
        love.graphics.setColor(game.C.DARK_WHITE or game.C.WHITE)
        love.graphics.printf(tag_summary, 10, 108, 382, "left")
    end

    -- Vouchers, as the cards they are. They used to be bare icons with no way to read them.
    local vouchers = RunInfoUI.owned_vouchers(game)
    love.graphics.setFont(label)
    love.graphics.setColor(game.C.JOKER_GREY)
    love.graphics.print(#vouchers > 0 and (I18N.text("run_info.vouchers_prefix", nil, "Vouchers ") .. #vouchers) or I18N.text("deck_view.vouchers", nil, "Vouchers"), 10, head_y)
    if #vouchers == 0 then
        love.graphics.setColor(game.C.BLOCK.BACK)
        draw_rounded_rect(VOUCHER_AREA_X, VOUCHER_Y, VOUCHER_AREA_W, VOUCHER_H, 4, 0, "fill")
        love.graphics.setColor(game.C.GREY)
        TextCache.printf(I18N.text("run_info.no_vouchers", nil, "None redeemed yet"), VOUCHER_AREA_X, Fonts.centre_y(game, label, VOUCHER_Y, VOUCHER_H), VOUCHER_AREA_W, "center")
    else
        local card_w = VOUCHER_CELL_W * VOUCHER_SCALE
        local step, start_x = fanned_step(#vouchers, VOUCHER_AREA_W, card_w, 4)
        for i, v in ipairs(vouchers) do
            local vx = VOUCHER_AREA_X + start_x + (i - 1) * step
            local drawn = false
            if v.def and v.def.mod_sprite and game.voucher_sprite then
                local image, quad = game:voucher_sprite(v.def)
                if image and quad then
                    love.graphics.setColor(1, 1, 1, 1)
                    love.graphics.draw(image, quad, vx, VOUCHER_Y, 0, VOUCHER_SCALE, VOUCHER_SCALE)
                    drawn = true
                end
            else
                drawn = draw_atlas_cell(game, "Voucher", tonumber(v.pos) or 0, vx, VOUCHER_Y, VOUCHER_SCALE)
            end
            if not drawn then
                love.graphics.setColor(game.C.VOUCHER)
                draw_rounded_rect(vx, VOUCHER_Y, card_w, VOUCHER_CELL_H * VOUCHER_SCALE, 4, 0, "fill")
                love.graphics.setColor(game.C.WHITE)
                love.graphics.printf(v.name, vx, VOUCHER_Y + 26, card_w, "center")
            end
        end
    end

    -- Stake: the chip, its own rule, then the rules it inherits from every stake below it.
    local stake_id = game.selected_stake_id or game._pending_stake_id or "stake_white"
    local stake_def = STAKE_DEFS_BY_ID and STAKE_DEFS_BY_ID[stake_id]
    love.graphics.setFont(label)
    love.graphics.setColor(game.C.JOKER_GREY)
    love.graphics.print(I18N.text("deck_view.stake", nil, "Stake"), 270, head_y)
    -- The chip cell is 30 px, drawn 1:1: at 1.3x the nearest filter made some of its pixels
    -- one screen pixel wide and some two.
    local chip_y, chip_h = VOUCHER_Y + 4, 30
    local stake_pos = tonumber(stake_def and stake_def.pos)
    if stake_pos then
        -- The cell has one clear column on the left, so x = 268 lines the chip's edge up with
        -- the "Stake" label above it.
        draw_atlas_cell(game, "chips", stake_pos, 268, chip_y, 1)
    end
    -- 8 px right of the 1:1 chip, out to the rules' right edge (270 + 122), centred on the chip.
    local stake_name = stake_def and I18N.content_name("stake", stake_def.id, stake_def.name) or I18N.text("deck_view.stake", nil, "Stake")
    local name_font = Fonts.fit_line(game, label, stake_name, 86, chip_h)
    love.graphics.setFont(name_font)
    love.graphics.setColor(game.C.WHITE)
    love.graphics.print(stake_name, 306, Fonts.centre_y(game, name_font, chip_y, chip_h))

    -- The stake's own rule as large as two LABEL lines allow. The inherited list under it stays
    -- MICRO: it is the long tail, and is cut with "+N more" when it runs out of room.
    local text_y = 180
    local rule = stake_def and I18N.content_text("stake", stake_def.id, stake_def.description or "") or ""
    local rule_font = Fonts.fit_block(game, label, rule, 122, 34)
    love.graphics.setFont(rule_font)
    love.graphics.setColor(game.C.JOKER_GREY)
    love.graphics.printf(rule, 270, text_y, 122, "left")
    local _, wrapped = rule_font:getWrap(rule, 122)
    text_y = text_y + math.max(1, #wrapped) * rule_font:getHeight() + 2

    love.graphics.setFont(game.FONTS.PIXEL.MICRO or game.FONTS.PIXEL.SMALL)
    local line_h = love.graphics.getFont():getHeight()
    local inherited = RunInfoUI.inherited_stake_descriptions(stake_id)
    if #inherited > 0 and text_y + line_h * 2 <= TOP_H - 2 then
        love.graphics.setColor(game.C.GREY)
        TextCache.print(I18N.text("run_info.also_applied", nil, "Also applied"), 270, text_y)
        text_y = text_y + line_h
        love.graphics.setColor(game.C.DARK_WHITE)
        local shown = 0
        for _, line in ipairs(inherited) do
            local _, lines = love.graphics.getFont():getWrap(line, 122)
            -- Leave a line spare for the "+N more" that says the list was cut.
            if text_y + (#lines + 1) * line_h > TOP_H - 2 then break end
            love.graphics.printf(line, 270, text_y, 122, "left")
            text_y = text_y + #lines * line_h
            shown = shown + 1
        end
        if shown < #inherited then
            love.graphics.setColor(game.C.GREY)
            love.graphics.printf(string.format(I18N.text("run_info.more", nil, "+%d more"), #inherited - shown), 270, text_y, 122, "left")
        end
    end

    -- Centred in the strip under the vouchers, in the readable grey the other labels use.
    love.graphics.setFont(label)
    love.graphics.setColor(game.C.JOKER_GREY)
    TextCache.print(I18N.text("run_info.hands_hint", nil, "Poker hands are on the touch screen"), 10,
        Fonts.centre_y(game, label, VOUCHER_Y + VOUCHER_H, TOP_H - VOUCHER_Y - VOUCHER_H))
    love.graphics.setColor(1, 1, 1, 1)
end

-- ---------------------------------------------------------------------------
-- Bottom screen: the poker hand list
-- ---------------------------------------------------------------------------

local DIALOG_X, DIALOG_Y, DIALOG_W, DIALOG_H = 8, 6, 304, 228
local LIST_X, LIST_W = 16, 288
local LIST_TOP, LIST_BOTTOM = 34, 202
local ROW_STEP_MAX, ROW_STEP_MIN = 24, 14
-- The played count's right edge sits this far inside the row; its header lines up on it.
local PLAYED_INSET = 3

--- Row height that fits every visible hand without scrolling.
---
--- Twelve hands is the ceiling (`globals.lua:370`) and the list has 168 px, so the tightest
--- case is a 14 px step -- still one clear line of SMALL. Scrolling a list you can see all of
--- is worse than shrinking it by three pixels.
---@param n integer
---@return number step, number row_h
function RunInfoUI.row_metrics(n)
    n = math.max(1, tonumber(n) or 1)
    local avail = LIST_BOTTOM - LIST_TOP
    local step = math.floor(avail / n)
    if step > ROW_STEP_MAX then step = ROW_STEP_MAX end
    if step < ROW_STEP_MIN then step = ROW_STEP_MIN end
    return step, step - 3
end

--- One field of a hand row, its capitals centred in the plate band `y, h` by its own face: a
--- field that `Fonts.fit` stepped down a size would otherwise sit off the others' line.
local function print_field(game, font, colour, text, x, y, h, limit, align)
    love.graphics.setFont(font)
    love.graphics.setColor(colour)
    local ty = Fonts.centre_y(game, font, y, h)
    if limit then
        TextCache.printf(text, x, ty, limit, align)
    else
        TextCache.print(text, x, ty)
    end
end

--- One hand: level pill, name, chips X mult, times played.
---
--- Mirrors `create_UIBox_current_hands`: the level pill takes its colour from
--- `G.C.HAND_LEVELS` so a levelled hand reads as levelled at a glance, and the chip and mult
--- plates keep the reference's blue and red.
function RunInfoUI.draw_hand_row(game, x, y, w, h, hand)
    draw_rect_with_shadow(x, y, w, h, 3, 0, game.C.GREY, game.C.BLOCK.SHADOW, 2)

    -- Plates keep a 3 px inset while the row has room and shrink towards the text's own
    -- height (1 px clear above and below) as twelve hands squeeze the rows; SMALL drops to
    -- TINY only once even that does not fit.
    local base = game.FONTS.PIXEL.SMALL
    local _, ink_h = Fonts.ink(game, base)
    if ink_h + 2 > h then
        base = game.FONTS.PIXEL.TINY or base
        _, ink_h = Fonts.ink(game, base)
    end
    local inner_h = math.max(h - 6, ink_h + 2)
    local inner_y = y + math.floor((h - inner_h) * 0.5)
    local pad = 3
    local level = math.max(0, tonumber(hand.level) or 1)
    local levels = game.C.HAND_LEVELS or {}
    love.graphics.setColor(levels[level] or levels[#levels] or game.C.WHITE)
    draw_rounded_rect(x + pad, inner_y, 40, inner_h, 3, 0, "fill")

    local chips_x = x + w - 98
    local mult_x = x + w - 46
    love.graphics.setColor(game.C.BLOCK.BACK)
    draw_rounded_rect(chips_x, inner_y, 40, inner_h, 3, 0, "fill")
    draw_rounded_rect(mult_x, inner_y, 22, inner_h, 3, 0, "fill")

    -- Every field is fitted to its own plate: `printf` neither clips nor scrolls on this
    -- backend, so anything that outgrows its box draws over the neighbour instead. Levelling
    -- past 9 widens the pill text, a levelled Flush Five runs past four digits, and a replayed
    -- Pair passes 99.
    local level_text = "lvl." .. tostring(level)
    local chips_text = NumberFormat.format(tonumber(hand.chips) or 0)
    local mult_text = NumberFormat.format(tonumber(hand.mult) or 0)
    local played = tonumber(hand.played) or 0
    local played_text = tostring(played)

    -- All of it goes through `TextCache`: the dialog is static while it is open, which is the
    -- module's stated case, and 12 rows x 5 fields is 60 reshapes a frame otherwise. The
    -- strings are single-colour by construction -- "0" only ever appears greyed, since a
    -- non-zero count is never "0" -- so nothing alternates colour on one cache key.
    print_field(game, Fonts.fit(game, base, level_text, 38), game.C.BLOCK.BACK, level_text, x + pad, inner_y, inner_h, 40, "center")
    print_field(game, base, game.C.WHITE, I18N.hand_name(hand.name or ""), x + 50, inner_y, inner_h)
    print_field(game, Fonts.fit(game, base, chips_text, 38), game.C.BLUE, chips_text, chips_x, inner_y, inner_h, 40, "center")
    print_field(game, base, game.C.WHITE, "X", x + w - 56, inner_y, inner_h)
    print_field(game, Fonts.fit(game, base, mult_text, 20), game.C.RED, mult_text, mult_x, inner_y, inner_h, 22, "center")
    print_field(game, Fonts.fit(game, base, played_text, 18), played > 0 and game.C.JOKER_GREY or game.C.GREY,
        played_text, x + w - PLAYED_INSET - 18, inner_y, inner_h, 18, "right")
end

function RunInfoUI.draw_bottom(game)
    draw_dialog(game, DIALOG_X, DIALOG_Y, DIALOG_W, DIALOG_H)

    love.graphics.setFont(game.FONTS.PIXEL.PRICE)
    love.graphics.setColor(game.C.WHITE)
    TextCache.print(I18N.text("deck_view.poker_hands", nil, "Poker Hands"), LIST_X, 14)
    -- On the title's line, right-aligned on the played column below it.
    love.graphics.setFont(game.FONTS.PIXEL.LABEL)
    love.graphics.setColor(game.C.JOKER_GREY)
    TextCache.printf(I18N.text("run_info.played", nil, "played"), LIST_X, 14, LIST_W - PLAYED_INSET, "right")

    local hands = RunInfoUI.visible_hands(game)
    local step, row_h = RunInfoUI.row_metrics(#hands)
    for i, hand in ipairs(hands) do
        local y = LIST_TOP + (i - 1) * step
        if y + row_h > LIST_BOTTOM then break end
        RunInfoUI.draw_hand_row(game, LIST_X, y, LIST_W, row_h, hand)
    end

    draw_back_button(game, LIST_X, 206, LIST_W)
    love.graphics.setColor(1, 1, 1, 1)
end

-- ---------------------------------------------------------------------------
-- Input
-- ---------------------------------------------------------------------------

local function in_rect(r, x, y)
    return type(r) == "table" and x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
end

---@return boolean handled
function RunInfoUI.handle_touchpressed(game, id, x, y)
    if in_rect(game._run_info_back_rect, x, y) then
        game:exit_run_info()
        return true
    end
    return true -- the dialog is modal: nothing behind it takes a touch
end

---@return boolean handled
function RunInfoUI.handle_gamepad(game, button)
    if not game or not game._run_info_open then return false end
    if button == "back" or button == "select"
        or (game.is_menu_back and game:is_menu_back(button))
        or (game.is_menu_activate and game:is_menu_activate(button)) then
        Sfx.play("cancel")
        game:exit_run_info()
        return true
    end
    return true -- modal: swallow everything else rather than driving the playfield behind
end

return RunInfoUI
