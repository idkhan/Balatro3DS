--- The mod API: a Steamodded-shaped surface over this port's own systems.
---
--- Mods are written the way Steamodded mods are -- `SMODS.Joker { key, loc_txt, config, rarity,
--- cost, loc_vars, calculate }` and friends -- so the examples at
--- https://github.com/Steamodded/examples port with little change. What sits underneath is not
--- Steamodded: there is no Lovely, no `G.GAME`, no event manager and no shaders. A mod Joker is
--- registered into `JOKER_DEFS` and `JokerEffects` exactly like a vanilla one, and `calculate`
--- is driven from the port's own joker events (`EVENT_CONTEXT` below), so pools, the shop, the
--- collection, Blueprint, retriggers and saving all treat it as a Joker like any other.
---
--- Textures: one image per card, the way the port stores its own Jokers and consumables, not
--- Steamodded's atlases. A card names its file (`sprite = "plus_four.png"`) under the mod's
--- `assets/1x/`, and the 3DS runtime loads the `.t3x` beside it whenever it is asked for a
--- `.png` (LovePotion's `translatePath`). Converting is the modder's job
--- (`tex3ds -f rgba plus_four.png -o plus_four.t3x`), never the game's. One file per card is what
--- lets a mod sprite be loaded when a card appears and freed when the last one goes, exactly as a
--- vanilla sprite is, instead of a whole sheet staying resident.
---
--- Editions stay the port's own: a mod Joker in foil, holo or polychrome is drawn with the same
--- additive texture passes as a vanilla one (`Fx.draw_edition_image`), since the PICA200 has no
--- fragment shaders to run a mod's. Negative needs its own image (`negative_sprite`).

SMODS = SMODS or {}

local CardArt = require("card_art")

--- Every mod image, by sprite key (`mod:<prefix>:<file>`): `{ path, mod }`.
SMODS.Sprites = SMODS.Sprites or {}
--- Every mod card's definition table (the one the mod passed in), by id.
SMODS.Centers = SMODS.Centers or {}
--- The mod whose main file is running. Only set while a mod loads, which is the only time
--- `SMODS.Joker` and the other registration calls may be made.
SMODS.current_mod = nil

--- Stands in for Steamodded's `G.play` card area, so `context.cardarea == G.play` reads true
--- for a scored card. `main.lua` points `G.play` at it.
SMODS.PLAY = SMODS.PLAY or { _smods_area = "play" }

--- Mod Jokers sort after every vanilla one in the collection.
local next_order = 1000

local RARITY = { common = 1, uncommon = 2, rare = 3, legendary = 4 }

local function deep_copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, vv in pairs(v) do out[k] = deep_copy(vv) end
    return out
end
SMODS.deep_copy = deep_copy

local function need_mod(what)
    local mod = SMODS.current_mod
    if not mod then
        error(what .. " can only be called from a mod's main file while it loads", 3)
    end
    return mod
end

local function check(cond, msg)
    if not cond then error(msg, 3) end
end

--------------------------------------------------------------------------------
-- Errors
--------------------------------------------------------------------------------

--- Record a runtime error against a mod. A mod that throws inside `calculate` must not take the
--- run down with it: the call is skipped, the error is kept for the Mods screen and the log, and
--- only the first few are kept so a Joker failing every frame cannot grow the list forever.
function SMODS.report_runtime_error(mod, err)
    if type(mod) ~= "table" then return end
    mod.runtime_errors = mod.runtime_errors or {}
    if #mod.runtime_errors < 5 then
        mod.runtime_errors[#mod.runtime_errors + 1] = tostring(err)
        if SMODS.on_runtime_error then SMODS.on_runtime_error(mod, err) end
    end
end

--- Call into mod code, catching anything it throws.
function SMODS.call(mod, fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
    SMODS.report_runtime_error(mod, a)
    return nil
end

--------------------------------------------------------------------------------
-- Sprites
--------------------------------------------------------------------------------

--- The atlas name a mod card's `pos` carries. Its `index` is then a sprite key rather than a
--- cell, so the port's existing sprite plumbing (`Joker.sprite_key_from_pos`, the collection,
--- sprite warming) resolves a mod card without knowing anything about mods.
SMODS.MOD_ATLAS = "@mod"

--- Register one of a mod's images and return its sprite key. The file has to exist -- as the
--- `.png` it is named by, or as the `.t3x` the 3DS loads in its place -- so a typo is a load error
--- naming the file, not an invisible card.
local function register_sprite(mod, file, what, key, field)
    if type(file) ~= "string" or not file:match("%S") then
        error(("%s '%s' needs %s = \"Name.png\" (an image in assets/1x)"):format(what, key, field), 0)
    end
    if file:find("..", 1, true) or file:sub(1, 1) == "/" then
        error(("%s '%s': %s must be a file inside assets/1x"):format(what, key, field), 0)
    end
    local path = mod.path .. "/assets/1x/" .. file
    local f = love and love.filesystem
    if f and f.getInfo then
        local t3x = path:gsub("%.[^./]+$", "") .. ".t3x"
        if not (f.getInfo(path, "file") or f.getInfo(t3x, "file")) then
            error(("%s '%s': %s '%s' not found in assets/1x (the 3DS loads %s)"):format(
                what, key, field, file, t3x:match("[^/]+$")), 0)
        end
    end
    local sprite_key = "mod:" .. mod.prefix .. ":" .. file
    if not SMODS.Sprites[sprite_key] then
        SMODS.Sprites[sprite_key] = { path = path, mod = mod }
        mod.registered.sprites[#mod.registered.sprites + 1] = sprite_key
    end
    return sprite_key
end

--- The file behind a sprite key, or nil when the key is not a mod's.
function SMODS.sprite_path(sprite_key)
    local sprite = SMODS.Sprites[sprite_key]
    return sprite and sprite.path or nil
end

--- The sprite key a `pos` names, or nil for a vanilla atlas position.
function SMODS.sprite_key(atlas_name, index)
    if atlas_name == SMODS.MOD_ATLAS and type(index) == "string" then return index end
    return nil
end

--- A mod image kept by this module, for the places that have no sprite cache of their own
--- (voucher art). Loaded on first use; a file that will not load is reported once.
function SMODS.image(sprite_key)
    local sprite = SMODS.Sprites[sprite_key]
    if not sprite then return nil end
    if sprite.image or sprite.load_error then return sprite.image end
    if not (love and love.graphics and love.graphics.newImage) then return nil end
    local ok, img = pcall(love.graphics.newImage, sprite.path)
    if ok and img then
        sprite.image = img
    else
        sprite.load_error = tostring(img)
        SMODS.report_runtime_error(sprite.mod, ("image %s failed to load: %s"):format(sprite.path, sprite.load_error))
    end
    return sprite.image
end

--- Steamodded's atlases are not how this port stores art: every card is its own image.
function SMODS.Atlas()
    error("SMODS.Atlas isn't supported on 3DS: give each card its own image with "
        .. "sprite = \"Name.png\" (see MODDING.md)", 2)
end

local function no_atlas(t, what)
    if t.atlas ~= nil or t.pos ~= nil then
        error(("%s '%s': atlas/pos aren't supported on 3DS; give it its own image with "
            .. "sprite = \"Name.png\""):format(what, tostring(t.key)), 0)
    end
end

--------------------------------------------------------------------------------
-- Card helpers mods call on playing cards
--------------------------------------------------------------------------------

--- Steamodded reads playing cards through methods and a `base` table. These answer from the
--- port's `card_data`, and `refresh_card_view` keeps `base` / `debuff` current for each context.
local function install_card_methods()
    if not Card or Card._smods_methods then return end
    Card._smods_methods = true
    function Card:get_id()
        local data = self.card_data or {}
        return tonumber(data.rank) or 0
    end
    function Card:is_face()
        local r = self:get_id()
        return (r >= 11 and r <= 13) or (G and G.hasJoker and G:hasJoker("j_pareidolia")) == true
    end
    function Card:is_suit(suit)
        local data = self.card_data or {}
        if data.enhancement == "stone" then return false end
        if data.enhancement == "wild" then return true end
        return JokerEffects.is_suit(data.suit, suit)
    end
end
SMODS.install_card_methods = install_card_methods

local function refresh_card_view(node)
    if type(node) ~= "table" then return node end
    local data = node.card_data or {}
    node.base = node.base or {}
    node.base.suit = data.suit
    node.base.id = tonumber(data.rank)
    node.base.nominal = tonumber(data.chips) or node.base.nominal
    node.debuff = node.debuffed == true or node.debuffed_for_scoring == true
    return node
end

local function card_views(list)
    local out = {}
    for i, node in ipairs(type(list) == "table" and list or {}) do out[i] = refresh_card_view(node) end
    return out
end

--------------------------------------------------------------------------------
-- Calculate: port events -> Steamodded contexts
--------------------------------------------------------------------------------

--- Which Steamodded context flag each of the port's joker events raises. `card_played` and
--- `card_held` are both `context.individual`, told apart by `cardarea` as in Steamodded.
local EVENT_CONTEXT = {
    on_hand_played = "before",
    card_played = "individual_play",
    card_held = "individual_hand",
    on_hand_scored = "joker_main",
    on_hand_after = "after",
    on_round_end = "end_of_round",
    on_discard = "discard",
    on_pre_discard = "pre_discard",
    on_blind_selected = "setting_blind",
    on_round_begin = "first_hand_drawn",
    on_joker_sold = "selling_card",
    on_shop_reroll = "reroll_shop",
    on_booster_open = "open_booster",
    on_booster_skip = "skipping_booster",
    on_consumable_used = "using_consumeable",
    on_shop_buy = "buying_card",
    on_destroy = "remove_playing_cards",
    on_cards_added_to_deck = "playing_card_added",
    on_shop_enter = "starting_shop",
    on_shop_exit = "ending_shop",
    on_blind_skipped = "skip_blind",
    on_blind_defeated = "blind_defeated",
    on_ante_change = "ante_change",
    on_hand_drawn = "hand_drawn",
    on_joker_added = "card_added",
    on_tag_added = "tag_added",
    on_hand_final = "final_scoring_step",
}
SMODS.EVENT_CONTEXT = EVENT_CONTEXT

--- `next(context.poker_hands["Straight"])` is how Steamodded asks whether a hand contains a
--- type. Contained types map to a non-empty list; anything else reads as an empty one.
local EMPTY = {}
local poker_hands_meta = { __index = function() return EMPTY end }
local function poker_hands_for(ctx)
    local out = setmetatable({}, poker_hands_meta)
    if type(ctx.contains_hand_types) == "table" then
        for name, yes in pairs(ctx.contains_hand_types) do
            if yes then out[name] = { true } end
        end
    end
    if type(ctx.hand_type) == "string" then out[ctx.hand_type] = { true } end
    return out
end

--- The Steamodded context for one port event. `context.port` is the raw event table, for mods
--- that want something the translation does not carry.
function SMODS.build_context(event_name, ctx, joker)
    ctx = type(ctx) == "table" and ctx or {}
    local kind = EVENT_CONTEXT[event_name]
    local c = {
        event = event_name,
        port = ctx,
        blueprint = ctx.blueprint,
        blueprint_card = ctx.blueprint_card,
        main_eval = true,
        game_over = false,
    }
    if kind == "individual_play" then
        c.individual = true
        c.cardarea = (G and G.play) or SMODS.PLAY
        c.other_card = refresh_card_view(ctx.card_node)
    elseif kind == "individual_hand" then
        c.individual = true
        c.cardarea = G and G.hand
        c.other_card = refresh_card_view(ctx.card_node)
    elseif kind then
        c[kind] = true
        c.cardarea = G and G.jokers
    end
    if kind == "discard" then c.other_card = refresh_card_view(ctx.card_node) end
    if kind == "selling_card" then
        c.card = ctx.joker or ctx.consumable
        c.selling_self = ctx.joker ~= nil and ctx.joker == joker
    end
    if kind == "end_of_round" and ctx.game_over ~= nil then c.game_over = ctx.game_over == true end
    -- Contexts whose flag carries a value rather than `true`.
    if kind == "hand_drawn" then c.hand_drawn = card_views(ctx.drawn_cards) end
    if kind == "card_added" then c.card = ctx.joker end
    if kind == "tag_added" then c.tag_added = ctx.tag end
    if kind == "ante_change" then
        c.ante_change = tonumber(ctx.ante_change) or 0
        c.ante_end = ctx.ante_end == true
    end
    -- Set while a `retrigger_joker_check` pass is repeating this Joker's effect.
    c.retrigger_joker = ctx.retrigger_joker
    c.scoring_name = ctx.hand_type
    c.poker_hands = poker_hands_for(ctx)
    c.scoring_hand = card_views(ctx.cards)
    -- Discard events carry the batch as `discarded_nodes`; Steamodded hands it over as `full_hand`.
    c.full_hand = card_views(ctx.full_hand or ctx.played_cards or ctx.discarded_nodes)
    return c
end

local function first_number(t, ...)
    for i = 1, select("#", ...) do
        local v = tonumber(t[select(i, ...)])
        if v then return v end
    end
    return nil
end

--- Apply what `calculate` returned, through the same helpers vanilla Jokers use: the popup, the
--- sound and the trigger bookkeeping that paces scoring all come for free.
function SMODS.apply_return(joker, ctx, ret, kind)
    if type(ret) ~= "table" then return end
    local chips = first_number(ret, "chips", "chip_mod", "h_chips")
    local mult = first_number(ret, "mult", "mult_mod", "h_mult")
    local xmult = first_number(ret, "xmult", "x_mult", "Xmult", "Xmult_mod", "x_mult_mod")
    local dollars = first_number(ret, "dollars", "p_dollars")
    if chips and chips ~= 0 then JokerEffects.add_chips(ctx, chips) end
    if mult and mult ~= 0 then JokerEffects.add_mult(ctx, mult) end
    if xmult and xmult ~= 1 then JokerEffects.mul_mult(ctx, xmult) end
    if dollars and dollars ~= 0 then
        if kind == "end_of_round" then
            JokerEffects.add_round_win_money(ctx, joker, dollars)
        else
            JokerEffects.add_money(ctx, dollars)
        end
    end
    -- A bare message ("Upgraded!", "Safe!") still counts as the Joker doing something.
    if ret.message and not (chips or mult or xmult or dollars) then
        if Popup and Top and ctx.VT then
            local p = Popup()
            p:spawn(tostring(ret.message), "Nope",
                ctx.VT.x + ctx.VT.w * 0.5 * (ctx.VT.scale or 1),
                ctx.VT.y + ctx.VT.h * 0.5 * (ctx.VT.scale or 1))
            Top:addPopup(p)
        end
        JokerEffects.mark_effect_applied(ctx)
    end
    if type(ret.extra) == "table" then SMODS.apply_return(joker, ctx, ret.extra, kind) end
end

--- The `JokerEffects` implementation for one mod Joker.
local function build_effect(center, def)
    local mod = center.mod
    local impl = {}

    function impl.matches_trigger(_, event_name)
        if not EVENT_CONTEXT[event_name] then return false end
        if type(center.calculate) == "function" then return true end
        return event_name == "on_round_end" and type(center.calc_dollar_bonus) == "function"
    end

    function impl.apply_effect(joker, ctx)
        local event_name = ctx.event_name or ctx.event
        local kind = EVENT_CONTEXT[event_name]
        if not kind then return end
        if type(center.calculate) == "function" then
            local ret = SMODS.call(mod, center.calculate, center, joker,
                SMODS.build_context(event_name, ctx, joker))
            SMODS.apply_return(joker, ctx, ret, kind)
        end
        -- Steamodded pays this at cash-out; the port's cash-out is the round-end payout table.
        if kind == "end_of_round" and not ctx.blueprint and type(center.calc_dollar_bonus) == "function" then
            local bonus = tonumber(SMODS.call(mod, center.calc_dollar_bonus, center, joker))
            if bonus and bonus > 0 then JokerEffects.add_round_win_money(ctx, joker, bonus) end
        end
    end

    --- Retriggers: Steamodded asks with `context.repetition` and reads `repetitions` back.
    function impl.query_retrigger(joker, rctx)
        if type(center.calculate) ~= "function" or type(rctx) ~= "table" then return 0 end
        local c = {
            repetition = true,
            cardarea = rctx.held and (G and G.hand) or ((G and G.play) or SMODS.PLAY),
            other_card = refresh_card_view(rctx.card_node or rctx.retrigger_card),
            blueprint = rctx.blueprint,
            blueprint_card = rctx.blueprint_card,
            port = rctx,
        }
        local ret = SMODS.call(mod, center.calculate, center, joker, c)
        return type(ret) == "table" and math.max(0, math.floor(tonumber(ret.repetitions) or 0)) or 0
    end

    --- A port extension: a chance roll just succeeded (`Game:chance_triggers`). Asked with
    --- `context.probability_success`, it reads `repetitions` back like `context.repetition`.
    function impl.query_probability_retrigger(joker, pctx)
        if type(center.calculate) ~= "function" or type(pctx) ~= "table" then return 0 end
        local c = {
            probability_success = true,
            identifier = pctx.key,
            numerator = pctx.numerator,
            denominator = pctx.denominator,
            cardarea = G and G.jokers,
            blueprint = pctx.blueprint,
            blueprint_card = pctx.blueprint_card,
            port = pctx,
        }
        local ret = SMODS.call(mod, center.calculate, center, joker, c)
        return type(ret) == "table" and math.max(0, math.floor(tonumber(ret.repetitions) or 0)) or 0
    end

    return impl
end

--------------------------------------------------------------------------------
-- Contexts asked outside an event: retriggers, post_trigger, probability
--------------------------------------------------------------------------------

--- Whether any held Joker is a mod's. Every helper below is a no-op without one, which keeps
--- them free in a vanilla run (they sit on paths that run per trigger and per roll).
local function holding_mod_joker()
    for _, j in ipairs(G and type(G.jokers) == "table" and G.jokers or EMPTY) do
        if j and j.def and j.def.smods then return true end
    end
    return false
end

--- Ask each held Joker that runs mod code one context, left to right. Blueprint and Brainstorm
--- answer for the Joker they copy, with `context.blueprint` set, as in Steamodded. `make()`
--- builds a fresh context per Joker, since a mod may write to it; `each(joker, ret)` gets every
--- table returned, `joker` being the one in the slot.
function SMODS.ask_jokers(make, each)
    if not (G and G._collect_jokers_in_slot_order) or not holding_mod_joker() then return end
    for _, j in ipairs(G:_collect_jokers_in_slot_order()) do
        local id = j.def and j.def.id
        local source = j
        if id == "j_blueprint" or id == "j_brainstorm" then source = JokerEffects.resolve_copy_target(j) end
        local center = type(source) == "table" and source.def and source.def.smods
        if center and type(center.calculate) == "function" then
            local c = make()
            c.cardarea = c.cardarea or (G and G.jokers)
            if source ~= j then
                c.blueprint = true
                c.blueprint_card = j
            end
            local ret = SMODS.call(center.mod, center.calculate, center, source, c)
            if type(ret) == "table" then each(j, ret) end
        end
    end
end

--- A floating message over a Joker, as a bare `message` return raises.
function SMODS.joker_message(joker, text)
    local vt = joker and joker.VT
    if not (vt and text and Popup and Top) then return end
    local p = Popup()
    p:spawn(tostring(text), "Nope", vt.x + vt.w * 0.5 * (vt.scale or 1), vt.y + vt.h * 0.5 * (vt.scale or 1))
    Top:addPopup(p)
end

--- `context.retrigger_joker_check`: `joker` just triggered on the event in `ctx`. Returns one
--- entry per extra pass, naming the Joker that asked for it. `context.other_card` is the Joker
--- that triggered and `context.other_context` the context it triggered in.
function SMODS.joker_retriggers(joker, ctx)
    local out = {}
    if not holding_mod_joker() then return out end
    local other = SMODS.build_context(ctx.event_name, ctx, joker)
    SMODS.ask_jokers(function()
        return { retrigger_joker_check = true, other_card = joker, other_context = other }
    end, function(j, ret)
        for _ = 1, math.max(0, math.floor(tonumber(ret.repetitions) or 0)) do out[#out + 1] = j end
    end)
    return out
end

--- `context.post_trigger`: `joker` just triggered. What each Joker returns is applied as if it
--- had triggered on the same event, its popup over itself.
function SMODS.post_trigger(joker, ctx)
    if not holding_mod_joker() then return end
    local other = SMODS.build_context(ctx.event_name, ctx, joker)
    local kind = EVENT_CONTEXT[ctx.event_name]
    SMODS.ask_jokers(function()
        return { post_trigger = true, other_card = joker, other_context = other }
    end, function(j, ret)
        local vt = ctx.VT
        ctx.VT = j.VT
        SMODS.apply_return(j, ctx, ret, kind)
        ctx.VT = vt
    end)
end

--- Steamodded's `mod_probability` pass, then its `fix_probability` pass, over one roll's odds.
--- Each Joker sees the odds as the ones before it left them and may return new
--- `numerator` / `denominator`. `identifier` names the roll (the vanilla RNG key for the
--- game's own rolls); `trigger_obj` is the mod's, nil for the game's.
function SMODS.modify_probability(trigger_obj, identifier, numerator, denominator)
    if not holding_mod_joker() then return numerator, denominator end
    for _, flag in ipairs({ "mod_probability", "fix_probability" }) do
        SMODS.ask_jokers(function()
            return { [flag] = true, trigger_obj = trigger_obj, identifier = identifier,
                numerator = numerator, denominator = denominator }
        end, function(_, ret)
            numerator = tonumber(ret.numerator) or numerator
            denominator = tonumber(ret.denominator) or denominator
        end)
    end
    return numerator, denominator
end

--- `context.pseudorandom_result`: a roll has landed (`result` is whether it hit). A returned
--- `message` floats over the Joker.
function SMODS.probability_result(trigger_obj, identifier, result, numerator, denominator)
    if not holding_mod_joker() then return end
    SMODS.ask_jokers(function()
        return { pseudorandom_result = true, result = result, trigger_obj = trigger_obj,
            identifier = identifier, numerator = numerator, denominator = denominator }
    end, function(j, ret)
        if ret.message then SMODS.joker_message(j, ret.message) end
    end)
end

--------------------------------------------------------------------------------
-- Tooltips: loc_txt + loc_vars, with Steamodded's {C:...} markup
--------------------------------------------------------------------------------

--- Steamodded colour names onto the tooltip palette (`TooltipDraw.tooltip_color_by_key`).
local COLOUR_KEYS = {
    mult = "MULT", red = "RED", chips = "CHIPS", blue = "CHIPS", green = "CHANCE",
    attention = "IMPORTANT", orange = "IMPORTANT", money = "MONEY", gold = "MONEY",
    yellow = "MONEY", purple = "PURPLE", tarot = "PURPLE", dark_edition = "PURPLE",
    legendary = "PURPLE", planet = "CHIPS", spectral = "CHIPS", edition = "PURPLE",
}

--- `{C:mult}`, `{X:mult,C:white}`, `{C:inactive}` ... `{}` -> colour for the text that follows.
local function colour_for_modifiers(spec)
    local c, x
    for part in tostring(spec):gmatch("[^,]+") do
        local k, v = part:match("^%s*(%a+)%s*:%s*([%w_]+)%s*$")
        if k == "C" then c = v elseif k == "X" then x = v end
    end
    if c and c ~= "white" and COLOUR_KEYS[c] then return COLOUR_KEYS[c] end
    if x and COLOUR_KEYS[x] then return COLOUR_KEYS[x] end
    return nil
end

--- Steamodded's language codes are the game's, except English.
local STEAMODDED_CODE = { en = "en-us" }

--- `loc_txt` for one language. A mod may write `loc_txt = { name, text }` (one language), or one
--- table per language as Steamodded allows: `loc_txt = { ["en-us"] = {...}, zh_CN = {...} }`.
local function loc_for(loc, language)
    if type(loc) ~= "table" then return nil end
    if loc.name ~= nil or loc.text ~= nil then return loc end
    return loc[STEAMODDED_CODE[language] or language] or loc[language] or loc["en-us"] or loc.default
end
SMODS.loc_for = loc_for

--- The languages a per-language `loc_txt` names, other than English.
local function other_languages(loc)
    local out = {}
    if type(loc) ~= "table" or loc.name ~= nil or loc.text ~= nil then return out end
    for code, entry in pairs(loc) do
        if type(entry) == "table" and code ~= "en-us" and code ~= "en" and code ~= "default" then
            out[#out + 1] = code
        end
    end
    return out
end

--- One tooltip line from one `loc_txt.text` entry: `#n#` filled from `vars`, then split into
--- coloured segments.
function SMODS.format_line(text, vars)
    text = tostring(text or ""):gsub("#(%d+)#", function(n)
        local v = vars and vars[tonumber(n)]
        if v == nil then return "#" .. n .. "#" end
        return tostring(v)
    end)
    local segments, colour, pos = {}, nil, 1
    while pos <= #text do
        local s, e, spec = text:find("{([^}]*)}", pos)
        local chunk = text:sub(pos, (s or #text + 1) - 1)
        if chunk ~= "" then segments[#segments + 1] = { text = chunk, color_key = colour } end
        if not s then break end
        colour = colour_for_modifiers(spec)
        pos = e + 1
    end
    if #segments == 0 then segments[1] = { text = " " } end
    return { segments = segments }
end

local function tooltip_lines_for(center)
    return function(joker)
        local loc = loc_for(center.loc_txt, I18N and I18N.get_language() or "en") or {}
        local text = loc.text
        if type(text) == "string" then text = { text } end
        if type(text) ~= "table" then return nil end
        local vars = {}
        if type(center.loc_vars) == "function" then
            local ret = SMODS.call(center.mod, center.loc_vars, center, {}, joker)
            if type(ret) == "table" and type(ret.vars) == "table" then vars = ret.vars end
        end
        local lines = {}
        for _, line in ipairs(text) do lines[#lines + 1] = SMODS.format_line(line, vars) end
        return lines
    end
end

--------------------------------------------------------------------------------
-- Jokers
--------------------------------------------------------------------------------

--- `SMODS.Joker { key, loc_txt, config, rarity, cost, sprite, soul_sprite, negative_sprite,
--- loc_vars, calculate, in_pool, set_ability,
--- calc_dollar_bonus, add_to_deck, remove_from_deck, blueprint_compat, eternal_compat,
--- perishable_compat, unlocked, discovered }`. The Joker's id is `j_<prefix>_<key>`.
function SMODS.Joker(t)
    local mod = need_mod("SMODS.Joker")
    check(type(t) == "table", "SMODS.Joker expects a table")
    check(type(t.key) == "string" and t.key:match("^[%w_]+$"),
        "SMODS.Joker needs a 'key' of letters, digits and underscores")
    local id = "j_" .. mod.prefix .. "_" .. t.key
    check(JOKER_DEFS[id] == nil, "Joker '" .. t.key .. "' is defined twice (id " .. id .. ")")

    local rarity = t.rarity
    if type(rarity) == "string" then rarity = RARITY[rarity:lower()] end
    rarity = tonumber(rarity or 1)
    check(rarity and rarity >= 1 and rarity <= 4 and rarity % 1 == 0,
        "Joker '" .. t.key .. "': rarity must be 1-4 or Common/Uncommon/Rare/Legendary")
    local cost = tonumber(t.cost or 3)
    check(cost and cost >= 0, "Joker '" .. t.key .. "': cost must be a number")

    no_atlas(t, "Joker")
    for name, fn in pairs({ calculate = t.calculate, loc_vars = t.loc_vars,
        calc_dollar_bonus = t.calc_dollar_bonus, add_to_deck = t.add_to_deck,
        remove_from_deck = t.remove_from_deck, in_pool = t.in_pool, set_ability = t.set_ability }) do
        check(fn == nil or type(fn) == "function", "Joker '" .. t.key .. "': " .. name .. " must be a function")
    end

    -- The art: the card, the floating layer Legendaries have, and the Negative version. The PC
    -- game recolours a Negative card in a shader; the PICA200 cannot, so vanilla ships a separate
    -- negative image per Joker and a mod does the same. Without one, the plain art is used.
    local sprite = register_sprite(mod, t.sprite, "Joker", t.key, "sprite")
    local soul = t.soul_sprite ~= nil and register_sprite(mod, t.soul_sprite, "Joker", t.key, "soul_sprite") or nil
    local negative = t.negative_sprite ~= nil
        and register_sprite(mod, t.negative_sprite, "Joker", t.key, "negative_sprite") or nil

    local loc = loc_for(t.loc_txt, "en") or {}
    next_order = next_order + 1
    local def = {
        id = id,
        name = tostring(loc.name or t.name or t.key),
        order = next_order,
        unlocked = t.unlocked ~= false,
        discovered = t.discovered == true,
        -- Steamodded's defaults: nothing copies a mod Joker unless it says it can be copied.
        blueprint_compat = t.blueprint_compat == true,
        perishable_compat = t.perishable_compat ~= false,
        eternal_compat = t.eternal_compat ~= false,
        rarity = rarity,
        cost = cost,
        sell_cost = math.max(1, math.floor(cost / 2)),
        config = deep_copy(type(t.config) == "table" and t.config or {}),
        pos = { atlas = SMODS.MOD_ATLAS, index = sprite },
        sub_pos = soul and { atlas = SMODS.MOD_ATLAS, index = soul } or nil,
        negative_pos = negative and { atlas = SMODS.MOD_ATLAS, index = negative } or nil,
        mod_id = mod.id,
        smods = t,
    }
    t.mod = mod
    t.original_key = t.key
    t.key = id
    def.mod_tooltip = tooltip_lines_for(t)

    JOKER_DEFS[id] = def
    SMODS.Centers[id] = t
    SMODS.register_translations(mod, "joker", id, t)
    JokerEffects.register(id, build_effect(t, def))
    mod.registered.jokers[#mod.registered.jokers + 1] = id
    return t
end

--------------------------------------------------------------------------------
-- Shared registration pieces (Jokers, Consumables, Vouchers)
--------------------------------------------------------------------------------

--- A card's image, and its negative image when it ships one.
local function card_sprites(mod, t, what)
    no_atlas(t, what)
    local sprite = register_sprite(mod, t.sprite, what, t.key, "sprite")
    local negative = t.negative_sprite ~= nil
        and register_sprite(mod, t.negative_sprite, what, t.key, "negative_sprite") or nil
    return sprite, negative
end

local function check_functions(t, what, names)
    for _, name in ipairs(names) do
        check(t[name] == nil or type(t[name]) == "function", what .. " '" .. t.key .. "': "
            .. name .. " must be a function")
    end
end

--- `loc_txt.text` as plain lines with `#n#` filled in and the markup dropped, for the places
--- that show a single plain string (the shop's voucher callout, the collection).
local function plain_text(center, card, language)
    local loc = loc_for(center.loc_txt, language or "en") or {}
    local text = loc.text
    if type(text) == "string" then text = { text } end
    if type(text) ~= "table" then return "" end
    local vars = {}
    if type(center.loc_vars) == "function" then
        local ret = SMODS.call(center.mod, center.loc_vars, center, {}, card)
        if type(ret) == "table" and type(ret.vars) == "table" then vars = ret.vars end
    end
    local lines = {}
    for _, line in ipairs(text) do
        local segs = SMODS.format_line(line, vars).segments
        local parts = {}
        for _, s in ipairs(segs) do parts[#parts + 1] = s.text end
        lines[#lines + 1] = table.concat(parts)
    end
    return table.concat(lines, "\n")
end
SMODS.plain_text = plain_text

--- A mod's own translations: each language in a per-language `loc_txt` gets the card's name
--- (and, for vouchers, whose description is shown as one plain string, the description) in the
--- game's string tables, so the collection, the shop and the toasts find it like any other.
--- Tooltip text is read from `loc_txt` in the live language when drawn (`tooltip_lines_for`).
function SMODS.register_translations(mod, kind, id, center, voucher_config)
    if not (I18N and I18N.add_strings) then return end
    for _, code in ipairs(other_languages(center.loc_txt)) do
        local entry = center.loc_txt[code]
        local strings, keys = {}, {}
        if entry.name ~= nil then
            strings[kind .. "." .. id .. ".name"] = tostring(entry.name)
        end
        if voucher_config then
            strings[kind .. "." .. id .. ".description"] = plain_text(center, { ability = deep_copy(voucher_config) }, code)
        end
        for key in pairs(strings) do keys[#keys + 1] = key end
        I18N.add_strings(code, strings)
        mod.registered.strings[#mod.registered.strings + 1] = { language = code, keys = keys }
    end
end

--- The tooltip lines for any mod centre, given the object standing in for `card`.
function SMODS.tooltip_lines(id, card)
    local center = SMODS.Centers[id]
    if not center then return nil end
    return tooltip_lines_for(center)(card)
end

--- Steamodded reads the player's selected cards as `G.hand.highlighted`. The port keeps the
--- selection on the Hand; this mirrors it there before a mod looks.
local function sync_highlighted(game)
    local hand = game and game.hand
    if not hand then return {} end
    local list = hand.ordered_selected_nodes and hand:ordered_selected_nodes() or {}
    hand.highlighted = card_views(list)
    return hand.highlighted
end
SMODS.sync_highlighted = sync_highlighted

--------------------------------------------------------------------------------
-- Consumables
--------------------------------------------------------------------------------

local CONSUMABLE_SET = { tarot = "tarot", planet = "planet", spectral = "spectral" }

--- Steamodded's enhancement keys onto the port's.
local ENHANCEMENT = {
    m_bonus = "bonus", m_mult = "mult", m_wild = "wild", m_glass = "glass",
    m_steel = "steel", m_stone = "stone", m_gold = "gold", m_lucky = "lucky",
}

local consumable_order = 1000

--- `SMODS.Consumable { set = "Tarot"|"Planet"|"Spectral", key, loc_txt, config, cost, sprite,
--- negative_sprite, loc_vars, can_use, use }`. The id is `c_<prefix>_<key>`.
---
--- Like Steamodded, a consumable that only declares data needs no code:
---   * `config.max_highlighted` (and `min_highlighted`) is how many cards it targets;
---   * `config.mod_conv = "m_gold"` enhances them, `config.suit_conv = "Hearts"` changes suit;
---   * a Planet with `config.hand_type = "Flush"` levels that hand.
--- `use` runs instead of (or, for a Planet, after) the built-in part.
function SMODS.Consumable(t)
    local mod = need_mod("SMODS.Consumable")
    check(type(t) == "table", "SMODS.Consumable expects a table")
    check(type(t.key) == "string" and t.key:match("^[%w_]+$"),
        "SMODS.Consumable needs a 'key' of letters, digits and underscores")
    local kind = CONSUMABLE_SET[tostring(t.set or ""):lower()]
    check(kind ~= nil, "Consumable '" .. t.key .. "': set must be \"Tarot\", \"Planet\" or \"Spectral\"")
    local id = "c_" .. mod.prefix .. "_" .. t.key
    check(CONSUMABLE_DEFS[id] == nil, "Consumable '" .. t.key .. "' is defined twice (id " .. id .. ")")
    check_functions(t, "Consumable", { "loc_vars", "can_use", "use" })
    local sprite, negative = card_sprites(mod, t, "Consumable")
    local config = type(t.config) == "table" and t.config or {}

    local select
    local max_h, min_h = tonumber(config.max_highlighted), tonumber(config.min_highlighted)
    if max_h then select = { min = math.max(1, min_h or 1), max = max_h } end
    if config.mod_conv ~= nil then
        check(ENHANCEMENT[config.mod_conv] ~= nil, "Consumable '" .. t.key .. "': unknown mod_conv '"
            .. tostring(config.mod_conv) .. "'")
    end
    if kind == "planet" and config.hand_type ~= nil then
        check(type(config.hand_type) == "string", "Consumable '" .. t.key .. "': hand_type must be a string")
    end

    local loc = loc_for(t.loc_txt, "en") or {}
    consumable_order = consumable_order + 1
    -- Data only: an owned consumable is a copy of this table and is saved with the run, so
    -- nothing here may be a function. The code is found again through `SMODS.Centers[id]`.
    CONSUMABLE_DEFS[id] = {
        id = id,
        kind = kind,
        name = tostring(loc.name or t.name or t.key),
        index = consumable_order,          -- collection order; the art is `mod_sprite`
        select = select,
        hand = kind == "planet" and config.hand_type or nil,
        cost = tonumber(t.cost),
        config = deep_copy(config),
        mod_id = mod.id,
        mod_sprite = sprite,
        mod_negative_sprite = negative,
    }
    t.mod = mod
    t.original_key = t.key
    t.key = id
    t.consumable_kind = kind
    SMODS.Centers[id] = t
    SMODS.register_translations(mod, "consumable", id, t)
    mod.registered.consumables[#mod.registered.consumables + 1] = id
    return t
end

--- Whether a mod consumable can be used now. The port has already checked that the game is in
--- a state where consumables can be used at all.
function SMODS.consumable_can_use(game, c)
    local center = SMODS.Centers[c and c.id]
    if not center then return nil end
    if type(c.select) == "table" then
        if not game:hand_ready_for_tarot_selection() then return false end
        if not game:tarot_selection_requirement_met(c) then return false end
    end
    if type(center.can_use) == "function" then
        sync_highlighted(game)
        return SMODS.call(center.mod, center.can_use, center, c) == true
    end
    return true
end

--- Use a mod consumable. Returns true when it is fully handled, false to let the port's own
--- Planet path level the hand first (the mod's `use`, if any, then runs from there).
function SMODS.use_consumable(game, c)
    local center = SMODS.Centers[c and c.id]
    if not center then return false end
    local config = c.ability or c.config or {}
    local hand = game.hand
    local highlighted = sync_highlighted(game)

    if center.consumable_kind == "planet" and c.hand and not c._smods_planet_done then
        return false
    end

    if config.mod_conv and ENHANCEMENT[config.mod_conv] then
        game:convert_enhancement_ripple(highlighted, ENHANCEMENT[config.mod_conv],
            tonumber(config.max_highlighted) or #highlighted)
    elseif type(config.suit_conv) == "string" then
        game:convert_suit_ripple(highlighted, config.suit_conv)
    end
    if type(center.use) == "function" then
        SMODS.call(center.mod, center.use, center, c, hand, nil)
    end

    game:record_consumable_use_id(c.id)
    if hand and hand.clear_selection then hand:clear_selection() end
    game.active_tooltip_card = nil
    if hand and hand.layout then hand:layout(false) end
    if Sfx and Sfx.play and center.consumable_kind ~= "planet" then Sfx.play("tarot1") end
    return true
end

--- After the port has levelled a mod Planet's hand, run the mod's own `use` if it has one.
function SMODS.after_planet(game, c)
    local center = SMODS.Centers[c and c.id]
    if center and type(center.use) == "function" then
        c._smods_planet_done = true
        SMODS.call(center.mod, center.use, center, c, game.hand, nil)
        c._smods_planet_done = nil
    end
end

--------------------------------------------------------------------------------
-- Vouchers
--------------------------------------------------------------------------------

--- Steamodded's ids for the vanilla vouchers, where they differ from the port's.
local VOUCHER_ALIAS = { v_overstock_norm = "v_overstock", v_reroll_surplus = "v_reroll" }

local voucher_order = 1000

--- `SMODS.Voucher { key, loc_txt, config, cost, sprite, requires, loc_vars, redeem }`.
--- The id is `v_<prefix>_<key>`. `requires` lists vouchers that must be owned first -- vanilla
--- ids, full mod ids, or this mod's own keys. `redeem(self, card)` runs once, when it is bought.
function SMODS.Voucher(t)
    local mod = need_mod("SMODS.Voucher")
    check(type(t) == "table", "SMODS.Voucher expects a table")
    check(type(t.key) == "string" and t.key:match("^[%w_]+$"),
        "SMODS.Voucher needs a 'key' of letters, digits and underscores")
    local id = "v_" .. mod.prefix .. "_" .. t.key
    check(VOUCHER_DEFS[id] == nil, "Voucher '" .. t.key .. "' is defined twice (id " .. id .. ")")
    check_functions(t, "Voucher", { "loc_vars", "redeem" })
    local sprite = card_sprites(mod, t, "Voucher")

    local requires = {}
    local req = t.requires
    if type(req) == "string" then req = { req } end
    for _, r in ipairs(type(req) == "table" and req or {}) do
        r = VOUCHER_ALIAS[r] or r
        local full = VOUCHER_DEFS[r] and r or ("v_" .. mod.prefix .. "_" .. tostring(r))
        check(VOUCHER_DEFS[full] ~= nil, "Voucher '" .. t.key .. "' requires unknown voucher '"
            .. tostring(r) .. "' (define it first)")
        requires[#requires + 1] = full
    end

    local loc = loc_for(t.loc_txt, "en") or {}
    voucher_order = voucher_order + 1
    t.mod = mod
    t.original_key = t.key
    t.key = id
    local config = deep_copy(type(t.config) == "table" and t.config or {})
    VOUCHER_DEFS[id] = {
        id = id,
        name = tostring(loc.name or t.name or t.key),
        description = plain_text(t, { ability = deep_copy(config) }),
        tier = #requires > 0 and 2 or 1,
        depends_on = requires[1],
        requires_all = #requires > 0 and requires or nil,
        price = tonumber(t.cost) or 10,
        order = voucher_order,
        config = config,
        mod_id = mod.id,
        mod_sprite = sprite,
    }
    SMODS.Centers[id] = t
    SMODS.register_translations(mod, "voucher", id, t, config)
    mod.registered.vouchers[#mod.registered.vouchers + 1] = id
    return t
end

--- Run a mod voucher's `redeem` once, when it is gained.
function SMODS.redeem_voucher(id)
    local center = SMODS.Centers[id]
    local def = VOUCHER_DEFS and VOUCHER_DEFS[id]
    if not center or not def then return false end
    if type(center.redeem) == "function" then
        SMODS.call(center.mod, center.redeem, center, { ability = deep_copy(def.config or {}) })
    end
    return true
end

--------------------------------------------------------------------------------
-- Deck skins: face-card sets for Options > Art
--------------------------------------------------------------------------------

local FACE_RANKS = { Jack = true, Queen = true, King = true }

--- `SMODS.DeckSkin { key, suit, loc_txt, sprite, hc_sprite }`: a set of Jack, Queen and King
--- art for one suit, offered in the Card Art carousel beside the built-in collab sets.
---
--- Same format as those sets (`card_art.lua`): `sprite` is one strip of three 72x95 cells, J, Q
--- and K left to right (216x95), drawn over the card front exactly like the deck's own faces.
--- `hc_sprite` is the high-contrast strip, used when the player ticks High Contrast for the
--- suit; without one, the normal strip is used at either contrast.
---
--- Steamodded's deck skins name atlases (`lc_atlas`, `hc_atlas`) and can cover any ranks; here
--- every skin is the three face cards, as the built-in sets are.
function SMODS.DeckSkin(t)
    local mod = need_mod("SMODS.DeckSkin")
    check(type(t) == "table", "SMODS.DeckSkin expects a table")
    check(type(t.key) == "string" and t.key:match("^[%w_]+$"),
        "SMODS.DeckSkin needs a 'key' of letters, digits and underscores")
    local suit = CardArt.suit_key(t.suit)
    check(suit ~= nil, "DeckSkin '" .. t.key .. "': suit must be \"Hearts\", \"Clubs\", \"Diamonds\" or \"Spades\"")
    if t.lc_atlas ~= nil or t.hc_atlas ~= nil or t.atlas ~= nil then
        error(("DeckSkin '%s': atlases aren't supported on 3DS; give it sprite = \"Name.png\", one "
            .. "216x95 strip of J, Q and K (and hc_sprite for high contrast)"):format(t.key), 0)
    end
    if t.ranks ~= nil then
        check(type(t.ranks) == "table", "DeckSkin '" .. t.key .. "': ranks must be a list")
        local n = 0
        for _, rank in ipairs(t.ranks) do
            check(FACE_RANKS[rank], "DeckSkin '" .. t.key .. "': only Jack, Queen and King can be "
                .. "replaced, not '" .. tostring(rank) .. "'")
            n = n + 1
        end
        check(n == 3, "DeckSkin '" .. t.key .. "': ranks must be Jack, Queen and King, all three")
    end
    local lc = register_sprite(mod, t.sprite, "DeckSkin", t.key, "sprite")
    local hc = t.hc_sprite ~= nil and register_sprite(mod, t.hc_sprite, "DeckSkin", t.key, "hc_sprite") or lc

    local loc = t.loc_txt
    local name = type(loc) == "string" and loc
        or type(loc) == "table" and (loc.name or loc["en-us"]) or t.name or t.key
    local id = mod.prefix .. "_" .. t.key
    check(CardArt.find(suit, id) == nil, "DeckSkin '" .. t.key .. "' is defined twice")
    CardArt.register(suit, {
        id = id,
        name = tostring(name),
        path_1 = SMODS.sprite_path(lc),
        path_2 = SMODS.sprite_path(hc),
        mod_id = mod.id,
    })
    mod.registered.deck_skins[#mod.registered.deck_skins + 1] = { suit = suit, id = id }
    return t
end

--------------------------------------------------------------------------------
-- Declarative modifiers
--------------------------------------------------------------------------------

--- The run-wide numbers a mod Joker or Voucher may change just by declaring them in `config`,
--- as vanilla Jokers like Juggler (`h_size`) and Drunkard (`d_size`) do. The port recomputes
--- each of these from what is owned whenever it is asked, so a modifier needs no bookkeeping:
--- it applies while the Joker is held or the Voucher redeemed, and saves with them.
SMODS.MODIFIERS = { h_size = true, d_size = true, hands = true, joker_slots = true, consumable_slots = true }

--- Sum one modifier over owned mod Jokers (their `card.ability`) and redeemed mod Vouchers.
function SMODS.modifier_total(game, key)
    if not next(SMODS.Centers) then return 0 end
    local total = 0
    for _, j in ipairs(game.jokers or {}) do
        if j and j.def and j.def.smods and type(j.ability) == "table" then
            total = total + (tonumber(j.ability[key]) or 0)
        end
    end
    for _, vid in ipairs(type(game.vouchers) == "table" and game.vouchers or {}) do
        local def = SMODS.Centers[vid] and VOUCHER_DEFS[vid]
        if def and type(def.config) == "table" then
            total = total + (tonumber(def.config[key]) or 0)
        end
    end
    return total
end

--- Per-copy state. Steamodded's `card.ability` is the Joker's own copy of its `config`, so two
--- copies of a scaling Joker scale apart; the port's `effect_config` is the shared def table,
--- so mod Jokers get a real copy here (`Joker:init`).
function SMODS.init_ability(joker)
    local def = joker and joker.def
    if type(def) ~= "table" or not def.smods then return end
    joker.ability = deep_copy(def.config or {})
    joker.ability.name = def.name
    local center = def.smods
    if type(center.set_ability) == "function" then
        SMODS.call(center.mod, center.set_ability, center, joker, true)
    end
end

--- `in_pool(self, args)`: false keeps the Joker out of the shop and every random roll.
function SMODS.in_pool(center)
    if type(center) ~= "table" or type(center.in_pool) ~= "function" then return true end
    local ok = SMODS.call(center.mod, center.in_pool, center, {})
    return ok ~= false
end

--- Called by the game when a mod Joker joins or leaves the player's Jokers. Not called while a
--- save is restored: the restored run already carries whatever these changed.
function SMODS.on_joker_added(joker)
    local center = joker and joker.def and joker.def.smods
    if center and center.add_to_deck then SMODS.call(center.mod, center.add_to_deck, center, joker, false) end
end

function SMODS.on_joker_removed(joker)
    local center = joker and joker.def and joker.def.smods
    if center and center.remove_from_deck then SMODS.call(center.mod, center.remove_from_deck, center, joker, false) end
end

--------------------------------------------------------------------------------
-- Randomness and text helpers mods expect
--------------------------------------------------------------------------------

--- How many times Oops! All 6s doubles probabilities.
local function oops_factor()
    local n = (G and G.count_jokers_with_id and G:count_jokers_with_id("j_oops")) or 0
    return 2 ^ n
end

--- `numerator in denominator` chance on the run's seeded stream: doubled by each Oops! All 6s,
--- then reshaped by mod Jokers' `mod_probability` / `fix_probability` unless `no_mod` is set.
--- Every Joker hears the outcome (`pseudorandom_result`). Returns whether it hit and, as a port
--- extension, how many times the effect should fire: 1, plus a pass for each
--- `context.probability_success` repetition (`local hit, times = SMODS.pseudorandom_probability(...)`).
function SMODS.pseudorandom_probability(trigger_obj, seed, numerator, denominator, identifier, no_mod)
    seed = tostring(seed or "smods")
    identifier = identifier or seed
    local num, den = tonumber(numerator) or 1, math.max(1, tonumber(denominator) or 1)
    if not no_mod then
        num, den = SMODS.modify_probability(trigger_obj, identifier, num * oops_factor(), den)
    end
    local hit
    if den == math.floor(den) then
        hit = (G and G.random and G:random(seed, 1, den) or math.random(1, den)) <= num
    else
        hit = (G and G.random and G:random(seed) or math.random()) * den < num
    end
    SMODS.probability_result(trigger_obj, identifier, hit, num, den)
    if not hit then return false, 0 end
    return true, 1 + (G and G.probability_retriggers and G:probability_retriggers(identifier, num, den) or 0)
end

--- The numbers a "#1# in #2#" tooltip should show: the same odds a roll would use.
function SMODS.get_probability_vars(trigger_obj, numerator, denominator, identifier, _, no_mod)
    local num, den = tonumber(numerator) or 1, tonumber(denominator) or 1
    if no_mod then return num, den end
    return SMODS.modify_probability(trigger_obj, identifier, num * oops_factor(), den)
end

--- `pseudorandom(seed)` in 0..1, or an integer in `min..max`, on the run's seeded stream.
function SMODS.pseudorandom(seed, min, max)
    seed = tostring(seed or "smods")
    if min and max then
        return G and G.random and G:random(seed, min, max) or math.random(min, max)
    end
    local n = G and G.random and G:random(seed, 1, 1000000) or math.random(1, 1000000)
    return (n - 1) / 999999
end

--- `pseudorandom_element(list, seed)`.
function SMODS.pseudorandom_element(list, seed)
    if type(list) ~= "table" or #list == 0 then return nil end
    return list[SMODS.pseudorandom(seed, 1, #list)]
end

--- The handful of vanilla localisation keys mods reach for in messages.
local LOCALIZE = {
    k_upgrade_ex = "Upgrade!", k_duplicated_ex = "Duplicated!", k_reset = "Reset",
    k_safe_ex = "Safe!", k_extinct_ex = "Extinct!", k_eaten_ex = "Eaten!",
    k_again_ex = "Again!", k_nope_ex = "Nope!", k_saved_ex = "Saved!",
    a_chips = "+#1#", a_mult = "+#1# Mult", a_xmult = "X#1# Mult", a_dollars = "$#1#",
}

--- A vanilla key in the live language: `smods.<key>` when the game has it, else the English.
local function localized(key)
    local english = LOCALIZE[key]
    if english == nil then return nil end
    return I18N and I18N.text("smods." .. key, nil, english) or english
end

function SMODS.localize(args, _)
    if type(args) == "table" then
        local text = localized(args.key) or tostring(args.key)
        return (text:gsub("#(%d+)#", function(n)
            local v = args.vars and args.vars[tonumber(n)]
            return v ~= nil and tostring(v) or ""
        end))
    end
    return localized(args) or tostring(args)
end

--- The globals a mod's main file sees beyond the game's own: Steamodded's free functions.
function SMODS.mod_environment(mod)
    local env = {
        SMODS = SMODS,
        localize = SMODS.localize,
        pseudorandom = SMODS.pseudorandom,
        pseudoseed = function(s) return tostring(s) end,
        pseudorandom_element = SMODS.pseudorandom_element,
        -- Vanilla's money change, which Steamodded mods call directly.
        ease_dollars = function(n)
            if G then G.money = (tonumber(G.money) or 0) + (tonumber(n) or 0) end
        end,
    }
    env._MOD = mod
    return setmetatable(env, { __index = _G })
end

--------------------------------------------------------------------------------
-- Rollback
--------------------------------------------------------------------------------

--- Undo everything a mod registered. A mod that throws halfway through its main file is not
--- left half-installed: everything it registered goes with it.
function SMODS.rollback(mod)
    if type(mod) ~= "table" or type(mod.registered) ~= "table" then return end
    for _, id in ipairs(mod.registered.jokers) do
        if JOKER_DEFS then JOKER_DEFS[id] = nil end
        SMODS.Centers[id] = nil
        JokerEffects.unregister(id)
    end
    for _, id in ipairs(mod.registered.consumables or {}) do
        if CONSUMABLE_DEFS then CONSUMABLE_DEFS[id] = nil end
        SMODS.Centers[id] = nil
    end
    for _, id in ipairs(mod.registered.vouchers or {}) do
        if VOUCHER_DEFS then VOUCHER_DEFS[id] = nil end
        SMODS.Centers[id] = nil
    end
    for _, set in ipairs(mod.registered.strings or {}) do
        if I18N and I18N.remove_strings then I18N.remove_strings(set.language, set.keys) end
    end
    mod.registered.strings = {}
    for _, skin in ipairs(mod.registered.deck_skins or {}) do CardArt.unregister(skin.suit, skin.id) end
    mod.registered.deck_skins = {}
    for _, key in ipairs(mod.registered.sprites or {}) do SMODS.Sprites[key] = nil end
    mod.registered.jokers, mod.registered.sprites = {}, {}
    mod.registered.consumables, mod.registered.vouchers = {}, {}
end

return SMODS
