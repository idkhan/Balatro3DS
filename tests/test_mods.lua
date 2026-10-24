local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

bootstrap.load()
local Json = require("json")
local ModLoader = require("mod_loader")

--------------------------------------------------------------------------------
-- Fixtures
--------------------------------------------------------------------------------

local function wipe_mods()
    local fs = love.filesystem
    local function rm(path)
        for _, item in ipairs(fs.getDirectoryItems(path)) do
            local child = path .. "/" .. item
            if fs.getInfo(child, "file") then fs.remove(child) else rm(child); fs.remove(child) end
        end
    end
    if fs.getInfo(ModLoader.DIR) then rm(ModLoader.DIR) end
    ModLoader.reset()
end

--- Write a mod folder: a Steamodded manifest plus its main file.
local function write_mod(folder, manifest, main)
    local base = ModLoader.DIR .. "/" .. folder
    love.filesystem.createDirectory(base)
    local parts = {}
    for k, v in pairs(manifest) do
        local value
        if type(v) == "table" then
            local items = {}
            for _, x in ipairs(v) do items[#items + 1] = ("%q"):format(x) end
            value = "[" .. table.concat(items, ", ") .. "]"
        else
            value = ("%q"):format(tostring(v))
        end
        parts[#parts + 1] = ("%q: %s"):format(k, value)
    end
    love.filesystem.write(base .. "/" .. folder .. ".json", "{" .. table.concat(parts, ",\n") .. "}")
    love.filesystem.write(base .. "/" .. (manifest.main_file or "main.lua"), main)
    -- Each card is its own image; registration checks the file is there, so write one for
    -- every `sprite = "..."` the main file names. The stub's newImage accepts any bytes.
    for file in main:gmatch('sprite%s*=%s*"([^"]+)"') do
        love.filesystem.write(base .. "/assets/1x/" .. file, "png")
    end
end

local EXAMPLE = [[
SMODS.Joker {
    key = "plus_four",
    loc_txt = { name = "Plus Four", text = { "{C:mult}+#1#{} Mult" } },
    config = { extra = { mult = 4 } },
    rarity = 1, cost = 2, sprite = "plus_four.png", negative_sprite = "plus_four_negative.png",
    blueprint_compat = true,
    loc_vars = function(self, info_queue, card) return { vars = { card.ability.extra.mult } } end,
    calculate = function(self, card, context)
        if context.joker_main then return { mult = card.ability.extra.mult } end
    end,
}

SMODS.Joker {
    key = "sevens",
    loc_txt = { name = "Sevens", text = { "Played {C:attention}7s{} give {C:chips}+#1#{} Chips" } },
    config = { extra = { chips = 30 } },
    rarity = 2, cost = 5, sprite = "sevens.png",
    calculate = function(self, card, context)
        if context.individual and context.cardarea == G.play and context.other_card:get_id() == 7 then
            return { chips = card.ability.extra.chips }
        end
    end,
}

SMODS.Joker {
    key = "runner",
    loc_txt = { name = "Runner", text = { "{C:inactive}(Currently {C:chips}+#1#{C:inactive} Chips)" } },
    config = { extra = { chips = 0, gain = 15 } },
    rarity = 1, cost = 5, sprite = "runner.png",
    loc_vars = function(self, info_queue, card) return { vars = { card.ability.extra.chips } } end,
    calculate = function(self, card, context)
        if context.before and next(context.poker_hands["Straight"]) and not context.blueprint then
            card.ability.extra.chips = card.ability.extra.chips + card.ability.extra.gain
            return { message = "Upgrade!" }
        end
        if context.joker_main and card.ability.extra.chips > 0 then
            return { chips = card.ability.extra.chips }
        end
    end,
}

SMODS.Joker {
    key = "golden",
    loc_txt = { name = "Golden", text = { "Earn {C:money}$#1#{}" } },
    config = { extra = { money = 4 } },
    rarity = 1, cost = 6, sprite = "golden.png",
    calc_dollar_bonus = function(self, card) return card.ability.extra.money end,
}

SMODS.Joker {
    key = "buskin",
    loc_txt = { name = "Buskin", text = { "Retrigger face cards" } },
    rarity = 2, cost = 6, sprite = "buskin.png",
    calculate = function(self, card, context)
        if context.repetition and context.cardarea == G.play and context.other_card:is_face() then
            return { repetitions = 1 }
        end
    end,
}

SMODS.Joker {
    key = "broken",
    loc_txt = { name = "Broken", text = { "Throws" } },
    rarity = 1, cost = 1, sprite = "broken.png",
    calculate = function(self, card, context)
        if context.joker_main then error("boom") end
    end,
}
]]

local function install_example()
    wipe_mods()
    write_mod("Example", {
        id = "ExampleMod", name = "Example", prefix = "ex", main_file = "main.lua",
        version = "1.2.0", author = { "Someone" },
    }, EXAMPLE)
    ModLoader.load_all()
    local game = bootstrap.new_game(4401)
    G = game
    G.play = G.play or SMODS.PLAY
    -- Popups land on the top screen's UI, which `love.load` builds and the tests do not.
    _G.Top = _G.Top or { addPopup = function() end }
    return game
end

local function add(game, id)
    game.jokers = {}
    T.assert_true(game:add_joker_by_def(id), id .. " should be addable")
    return game.jokers[#game.jokers]
end

local function scored(joker, extra)
    local ctx = { event = "on_hand_scored", event_name = "on_hand_scored", chips = 10, mult = 2 }
    for k, v in pairs(extra or {}) do ctx[k] = v end
    if joker:matches_trigger(ctx.event_name, ctx) then joker:apply_effect(ctx) end
    return ctx
end

--------------------------------------------------------------------------------
-- Loading
--------------------------------------------------------------------------------

suite.test("json decodes a Steamodded manifest", function()
    local m = Json.decode('\239\187\191{ "id": "VSMODS", "author": ["a", "b\\u00e9"], "n": -1.5e1, "x": null, "ok": true }')
    T.assert_eq(m.id, "VSMODS")
    T.assert_eq(m.author[2], "b\195\169")
    T.assert_eq(m.n, -15)
    T.assert_eq(m.x, nil)
    T.assert_true(m.ok)
    T.assert_false(pcall(Json.decode, '{ "id": }'), "bad JSON raises")
end)

suite.test("a mod's Jokers register as ordinary Jokers", function()
    local game = install_example()
    local mod = ModLoader.by_id.ExampleMod
    T.assert_eq(mod.status, "loaded")
    T.assert_eq(#mod.registered.jokers, 6)
    local def = JOKER_DEFS.j_ex_plus_four
    T.assert_true(def ~= nil, "id is j_<prefix>_<key>")
    T.assert_eq(def.name, "Plus Four")
    T.assert_eq(def.rarity, 1)
    T.assert_true(def.order > 150, "mod Jokers sort after the vanilla ones")
    T.assert_true(game:joker_allowed_in_random_pool("j_ex_plus_four"), "rollable in the shop")
    local found = false
    for _, entry in ipairs(require("collection_catalog").get_entries("jokers")) do
        if entry.id == "j_ex_plus_four" then found = true end
    end
    T.assert_true(found, "listed in the collection")
    wipe_mods()
end)

suite.test("a mod that fails is rolled back and the others still load", function()
    wipe_mods()
    write_mod("Good", { id = "Good", prefix = "good", main_file = "main.lua", version = "1" }, [[
        SMODS.Joker { key = "fine", rarity = 1, sprite = "a.png" }
    ]])
    write_mod("Bad", { id = "Bad", prefix = "bad", main_file = "main.lua", version = "1" }, [[
        SMODS.Joker { key = "first", rarity = 1, sprite = "a.png" }
        SMODS.Joker { key = "second", rarity = 9, sprite = "a.png" }
    ]])
    write_mod("NoManifest", {}, "")
    love.filesystem.remove(ModLoader.DIR .. "/NoManifest/NoManifest.json")
    write_mod("Needy", { id = "Needy", prefix = "needy", main_file = "main.lua", version = "1",
        dependencies = { "Steamodded (>=1.0.0)", "Missing (>=2)" } }, "")
    ModLoader.load_all()

    T.assert_eq(ModLoader.by_id.Good.status, "loaded")
    T.assert_true(JOKER_DEFS.j_good_fine ~= nil)
    local bad = ModLoader.by_id.Bad
    T.assert_eq(bad.status, "error")
    T.assert_true(tostring(bad.error):find("rarity", 1, true) ~= nil, tostring(bad.error))
    T.assert_eq(JOKER_DEFS.j_bad_first, nil, "the half-loaded Joker is gone with its mod")
    T.assert_eq(SMODS.Sprites["mod:bad:a.png"], nil, "and its images")
    local needy = ModLoader.by_id.Needy
    T.assert_eq(needy.status, "error")
    T.assert_true(needy.error:find("Missing", 1, true) ~= nil, needy.error)
    local no_manifest
    for _, m in ipairs(ModLoader.mods) do if m.folder == "NoManifest" then no_manifest = m end end
    T.assert_eq(no_manifest.status, "error")
    T.assert_true(love.filesystem.read(ModLoader.LOG_PATH):find("[ERROR] Bad", 1, true) ~= nil,
        "the log names the failure for a modder on hardware")
    wipe_mods()
end)

--------------------------------------------------------------------------------
-- Scoring
--------------------------------------------------------------------------------

suite.test("joker_main returns are scored like a vanilla Joker", function()
    local game = install_example()
    local j = add(game, "j_ex_plus_four")
    local ctx = scored(j)
    T.assert_eq(ctx.mult, 6)
    T.assert_true(ctx._joker_effect_applied, "counts as a trigger for the scoring pace")
    wipe_mods()
end)

suite.test("individual contexts see the scored card", function()
    local game = install_example()
    local j = add(game, "j_ex_sevens")
    local seven = Card(0, 0, 1, 1, { rank = 7, suit = "Hearts" })
    local eight = Card(0, 0, 1, 1, { rank = 8, suit = "Hearts" })
    local function play(node)
        local ctx = { event = "card_played", event_name = "card_played", chips = 0, mult = 1,
            rank = node.card_data.rank, suit = node.card_data.suit, card_node = node }
        if j:matches_trigger("card_played", ctx) then j:apply_effect(ctx) end
        return ctx.chips
    end
    T.assert_eq(play(seven), 30)
    T.assert_eq(play(eight), 0)
    wipe_mods()
end)

suite.test("each copy scales its own ability", function()
    local game = install_example()
    game.jokers = {}
    game:add_joker_by_def("j_ex_runner")
    game:add_joker_by_def("j_ex_runner")
    local a, b = game.jokers[1], game.jokers[2]
    local before = { event = "on_hand_played", event_name = "on_hand_played",
        hand_type = "Straight", contains_hand_types = { Straight = true } }
    a:apply_effect(before)
    T.assert_eq(a.ability.extra.chips, 15)
    T.assert_eq(b.ability.extra.chips, 0, "the second copy did not scale")
    T.assert_eq(JOKER_DEFS.j_ex_runner.config.extra.chips, 0, "the definition is untouched")
    T.assert_eq(scored(a).chips, 25)
    wipe_mods()
end)

suite.test("retriggers, round-end money and runtime errors", function()
    local game = install_example()
    local busk = add(game, "j_ex_buskin")
    local king = Card(0, 0, 1, 1, { rank = 13, suit = "Spades" })
    T.assert_eq(busk:query_retrigger({ card_node = king, held = false }), 1)
    T.assert_eq(busk:query_retrigger({ card_node = Card(0, 0, 1, 1, { rank = 5, suit = "Spades" }), held = false }), 0)

    local golden = add(game, "j_ex_golden")
    local paid = {}
    local ctx = { event = "on_round_end", event_name = "on_round_end",
        add_round_win_payout = function(label, n) paid[#paid + 1] = { label, n } end }
    golden:apply_effect(ctx)
    T.assert_eq(paid[1][1], "Golden")
    T.assert_eq(paid[1][2], 4)

    local broken = add(game, "j_ex_broken")
    local out = scored(broken)
    T.assert_eq(out.mult, 2, "a throwing Joker is skipped, not fatal")
    local errs = ModLoader.by_id.ExampleMod.runtime_errors
    T.assert_true(#errs >= 1 and errs[1]:find("boom", 1, true) ~= nil)
    wipe_mods()
end)

--------------------------------------------------------------------------------
-- Presentation
--------------------------------------------------------------------------------

suite.test("tooltips fill loc_vars and colour Steamodded markup", function()
    local game = install_example()
    local j = add(game, "j_ex_plus_four")
    local lines = j:get_tooltip_body_lines()
    T.assert_eq(lines[1].kind, "rarity_badge")
    local segs = lines[2].segments
    T.assert_eq(segs[1].text, "+4")
    T.assert_eq(segs[1].color_key, "MULT")
    T.assert_eq(segs[2].text, " Mult")
    T.assert_eq(segs[2].color_key, nil, "{} resets the colour")
    wipe_mods()
end)

suite.test("a negative mod Joker draws its negative art, if it has some", function()
    local game = install_example()
    game.jokers = {}
    T.assert_true(game:add_joker_by_def("j_ex_plus_four", { edition = "negative" }))
    T.assert_eq(game.jokers[1].front_sprite_key, "mod:ex:plus_four_negative.png")
    T.assert_eq(Joker.front_sprite_key_for(JOKER_DEFS.j_ex_plus_four, { edition = "negative" }),
        "mod:ex:plus_four_negative.png", "warming names the same sprite")
    T.assert_true(game:add_joker_by_def("j_ex_sevens", { edition = "negative" }))
    T.assert_eq(game.jokers[2].front_sprite_key, "mod:ex:sevens.png", "no negative art: the plain image")
    wipe_mods()
end)

suite.test("a mod Joker's image loads and frees like a vanilla sprite", function()
    local game = install_example()
    local j = add(game, "j_ex_sevens")
    T.assert_eq(j.front_sprite_key, "mod:ex:sevens.png")
    local entry = game.JOKER_SPRITES["mod:ex:sevens.png"]
    T.assert_eq(entry.path, ModLoader.DIR .. "/Example/assets/1x/sevens.png")
    T.assert_true(entry.image ~= nil)
    j:draw()
    game:remove_owned_joker_at(1, true)
    T.assert_eq(entry.image, nil, "the last owner going frees it, as for vanilla art")
    wipe_mods()
end)

suite.test("atlases, missing images and stray atlas/pos are load errors that say why", function()
    wipe_mods()
    write_mod("A", { id = "A", prefix = "a", main_file = "main.lua", version = "1" },
        'SMODS.Atlas { key = "x", path = "x.png", px = 71, py = 95 }')
    write_mod("B", { id = "B", prefix = "b", main_file = "main.lua", version = "1" },
        'SMODS.Joker { key = "j", rarity = 1, atlas = "x", pos = { x = 0, y = 0 } }')
    write_mod("C", { id = "C", prefix = "c", main_file = "main.lua", version = "1" },
        'SMODS.Joker { key = "j", rarity = 1, sprite = "here.png" }')
    love.filesystem.remove(ModLoader.DIR .. "/C/assets/1x/here.png")
    write_mod("D", { id = "D", prefix = "d", main_file = "main.lua", version = "1" },
        'SMODS.Joker { key = "j", rarity = 1, sprite = "only_t3x.png" }')
    love.filesystem.remove(ModLoader.DIR .. "/D/assets/1x/only_t3x.png")
    love.filesystem.write(ModLoader.DIR .. "/D/assets/1x/only_t3x.t3x", "t3x")
    ModLoader.load_all()
    T.assert_true(ModLoader.by_id.A.error:find("sprite = ", 1, true) ~= nil, ModLoader.by_id.A.error)
    T.assert_true(ModLoader.by_id.B.error:find("atlas/pos", 1, true) ~= nil, ModLoader.by_id.B.error)
    T.assert_true(ModLoader.by_id.C.error:find("here.t3x", 1, true) ~= nil, ModLoader.by_id.C.error)
    T.assert_eq(ModLoader.by_id.D.status, "loaded", "a .t3x alone is enough: that is what the 3DS loads")
    wipe_mods()
end)

--------------------------------------------------------------------------------
-- Saves
--------------------------------------------------------------------------------

suite.test("a run records its mods and refuses to continue on a different set", function()
    local game = install_example()
    game.jokers = {}
    game:add_joker_by_def("j_ex_runner")
    game.jokers[1].ability.extra.chips = 45
    local snap = game:build_run_snapshot()
    T.assert_eq(snap.mods[1].id, "ExampleMod")
    T.assert_eq(snap.mods[1].version, "1.2.0")
    T.assert_eq(snap.jokers[1].ability.extra.chips, 45)
    T.assert_true(game:check_saved_run_mods(snap), "same mods: continue")

    T.assert_true(game:load_run_snapshot(snap))
    T.assert_eq(game.jokers[1].ability.extra.chips, 45, "a mod Joker's state survives the save")

    -- Mod removed: the run is held, not loaded or discarded.
    wipe_mods()
    T.assert_false(game:check_saved_run_mods(snap))
    T.assert_eq(game._menu_sub_state, "mods")
    T.assert_eq(game._mods_continue_block.missing[1].id, "ExampleMod")

    -- Version changed.
    write_mod("Example", { id = "ExampleMod", prefix = "ex", main_file = "main.lua", version = "2.0.0" }, EXAMPLE)
    ModLoader.load_all()
    T.assert_false(game:check_saved_run_mods(snap))
    T.assert_eq(game._mods_continue_block.changed[1].installed, "2.0.0")

    -- A vanilla save with a mod now installed.
    T.assert_false(game:check_saved_run_mods({ seed = "X" }))
    T.assert_eq(game._mods_continue_block.extra[1].id, "ExampleMod")
    local lines = ModLoader.describe_mismatch(game._mods_continue_block)
    T.assert_true(lines[1]:find("Turn off ExampleMod", 1, true) ~= nil, lines[1])
    wipe_mods()
end)

suite.test("a mod Joker's tooltip leads with its rarity, like a vanilla one", function()
    local game = install_example()
    local sevens = add(game, "j_ex_sevens")
    local lines = sevens:get_tooltip_body_lines()
    T.assert_eq(lines[1].kind, "rarity_badge")
    T.assert_eq(lines[1].rarity, 2)
    T.assert_eq(lines[1].text, "Uncommon")
    T.assert_eq(#sevens:get_tooltip_body_lines(), #lines, "the badge is added once, not per call")

    I18N.set_language("zh_CN")
    T.assert_eq(sevens:get_tooltip_body_lines()[1].text, I18N.t("rarity.uncommon"))
    I18N.set_language("en")
    wipe_mods()
end)

--------------------------------------------------------------------------------
-- Turning mods off and on
--------------------------------------------------------------------------------

local SIMPLE_JOKER = [[
SMODS.Joker { key = "j", loc_txt = { name = "J", text = { "x" } }, rarity = 1, cost = 1, sprite = "j.png" }
]]

suite.test("a mod turned off does not load, stays off across boots, and comes back on", function()
    wipe_mods()
    write_mod("Base", { id = "Base", prefix = "base", main_file = "main.lua", version = "1" }, SIMPLE_JOKER)
    write_mod("Addon", { id = "Addon", prefix = "add", main_file = "main.lua", version = "1",
        dependencies = { "Base (>=1)" } }, SIMPLE_JOKER)
    ModLoader.load_all()
    T.assert_eq(ModLoader.by_id.Base.status, "loaded")
    T.assert_true(JOKER_DEFS.j_base_j ~= nil)

    ModLoader.set_enabled("Base", false)
    T.assert_eq(ModLoader.by_id.Base.status, "disabled")
    T.assert_eq(JOKER_DEFS.j_base_j, nil, "a mod turned off takes its Jokers with it")
    T.assert_eq(ModLoader.by_id.Addon.status, "error")
    T.assert_true(ModLoader.by_id.Addon.error:find("turned off", 1, true) ~= nil, ModLoader.by_id.Addon.error)
    T.assert_eq(#ModLoader.fingerprint(), 0, "neither is part of a run now")
    T.assert_true(love.filesystem.read(ModLoader.DISABLED_PATH):find("Base", 1, true) ~= nil)

    -- A reboot reads the choice back.
    ModLoader.disabled = {}
    ModLoader.load_all()
    T.assert_eq(ModLoader.by_id.Base.status, "disabled")
    -- The prefix is free while it is off: only what registers under it reserves it.
    write_mod("Other", { id = "Other", prefix = "base", main_file = "main.lua", version = "1" }, "")
    ModLoader.load_all()
    T.assert_eq(ModLoader.by_id.Other.status, "loaded", tostring(ModLoader.by_id.Other.error))
    love.filesystem.remove(ModLoader.DIR .. "/Other/Other.json")

    ModLoader.set_enabled("Base", true)
    T.assert_eq(ModLoader.by_id.Base.status, "loaded")
    T.assert_eq(ModLoader.by_id.Addon.status, "loaded", tostring(ModLoader.by_id.Addon.error))
    T.assert_true(JOKER_DEFS.j_base_j ~= nil)
    T.assert_eq(love.filesystem.getInfo(ModLoader.DISABLED_PATH, "file"), nil, "nothing off, no file")
    wipe_mods()
end)

suite.test("a mod with a load error can be turned off, and its error goes with it", function()
    wipe_mods()
    write_mod("Bad", { id = "Bad", prefix = "bad", main_file = "main.lua", version = "1" }, "error('nope')")
    ModLoader.load_all()
    T.assert_eq(ModLoader.by_id.Bad.status, "error")
    ModLoader.set_enabled("Bad", false)
    T.assert_eq(ModLoader.by_id.Bad.status, "disabled")
    T.assert_eq(ModLoader.by_id.Bad.error, nil)
    wipe_mods()
end)

suite.test("the Mods page switches mods, and re-checks a held saved run as it does", function()
    local game = install_example()
    local snap = game:build_run_snapshot()
    local ModsUI = require("mods_ui")

    -- Turned off on the Mods page, the saved run asks for it back by name.
    ModsUI.open(game)
    ModsUI.draw(game)
    T.assert_eq(ModsUI.switchable()[1].id, "ExampleMod")
    ModsUI.handle_button(game, "a")
    T.assert_eq(ModLoader.by_id.ExampleMod.status, "disabled", "A flips the focused mod")
    T.assert_eq(game._menu_sub_state, "mods", "and does not leave the page")

    T.assert_false(game:check_saved_run_mods(snap))
    local lines = ModLoader.describe_mismatch(game._mods_continue_block)
    T.assert_true(lines[1]:find("Turn on ExampleMod", 1, true) ~= nil, lines[1])

    -- Tapping the mod's row turns it back on, and the page says the run can go on.
    ModsUI.draw(game)
    local rect = game._mods_switch_rects[1]
    T.assert_true(rect ~= nil, "the mod's row is a switch")
    ModsUI.handle_touch(game, rect.x + 4, rect.y + 2)
    T.assert_eq(ModLoader.by_id.ExampleMod.status, "loaded")
    T.assert_eq(game._mods_continue_block, nil)
    local text = {}
    for _, l in ipairs(ModsUI.lines(game)) do text[#text + 1] = l[1] end
    T.assert_true(table.concat(text, "\n"):find("match the saved run", 1, true) ~= nil)
    T.assert_true(game:check_saved_run_mods(snap))

    ModsUI.handle_button(game, "b")
    T.assert_eq(game._menu_sub_state, "main")
    wipe_mods()
end)

suite.test("the example mod in dev/example_mods loads and scores", function()
    wipe_mods()
    local root = (os.getenv("BALATRO_ROOT") or ".") .. "/dev/example_mods/ExampleJokers/"
    for _, name in ipairs({ "ExampleJokers.json", "ExampleJokers.lua" }) do
        local f = assert(io.open(root .. name, "rb"))
        love.filesystem.createDirectory(ModLoader.DIR .. "/ExampleJokers")
        local text = f:read("*a")
        f:close()
        love.filesystem.write(ModLoader.DIR .. "/ExampleJokers/" .. name, text)
        -- Every image the mod names has to be in the repo, as the .png and the .t3x it ships.
        for file in text:gmatch('sprite%s*=%s*"([^"]+)"') do
            for _, real in ipairs({ file, (file:gsub("%.png$", ".t3x")) }) do
                local img = io.open(root .. "assets/1x/" .. real, "rb")
                T.assert_true(img ~= nil, "example mod ships assets/1x/" .. real)
                if img then img:close() end
            end
            love.filesystem.write(ModLoader.DIR .. "/ExampleJokers/assets/1x/" .. file, "png")
        end
    end
    ModLoader.load_all()
    local mod = ModLoader.by_id.ExampleJokers
    T.assert_eq(mod.status, "loaded", tostring(mod.error))
    T.assert_eq(#mod.registered.jokers, 3)
    T.assert_eq(#mod.registered.consumables, 2)
    T.assert_eq(#mod.registered.vouchers, 2)
    T.assert_eq(#mod.registered.deck_skins, 1)
    T.assert_eq(require("card_art").find("Spades", "exj_royal_court").name, "Royal Court")
    T.assert_eq(VOUCHER_DEFS.v_exj_biggest_hand.depends_on, "v_exj_bigger_hand")
    T.assert_eq(JOKER_DEFS.j_exj_grower.negative_pos.index, "mod:exj:grower_negative.png")
    local game = bootstrap.new_game(4403)
    G = game
    G.play = G.play or SMODS.PLAY
    _G.Top = _G.Top or { addPopup = function() end }
    local grower = add(game, "j_exj_grower")
    grower:apply_effect({ event = "on_hand_played", event_name = "on_hand_played",
        hand_type = "Flush", contains_hand_types = { Flush = true } })
    T.assert_eq(grower.ability.extra.money, 1)
    T.assert_eq(#mod.runtime_errors, 0)
    wipe_mods()
end)

--------------------------------------------------------------------------------
-- Consumables and Vouchers
--------------------------------------------------------------------------------

local CV_MOD = [[
SMODS.Consumable {
    set = "Tarot", key = "gilded",
    loc_txt = { name = "Gilded", text = { "Enhances {C:attention}#1#{} cards to Gold" } },
    config = { max_highlighted = 2, mod_conv = "m_gold" },
    sprite = "gilded.png", negative_sprite = "gilded_negative.png",
    loc_vars = function(self, info_queue, card) return { vars = { card.ability.max_highlighted } } end,
}
SMODS.Consumable {
    set = "Planet", key = "pluto2",
    loc_txt = { name = "Pluto 2", text = { "Levels High Card, +$1" } },
    config = { hand_type = "High Card" },
    sprite = "pluto2.png",
    use = function(self, card) ease_dollars(1) end,
}
SMODS.Consumable {
    set = "Spectral", key = "windfall", cost = 5,
    loc_txt = { name = "Windfall", text = { "Gain {C:money}$#1#{}" } },
    config = { extra = { dollars = 7 } },
    sprite = "windfall.png",
    loc_vars = function(self, info_queue, card) return { vars = { card.ability.extra.dollars } } end,
    can_use = function(self, card) return G.money < 100 end,
    use = function(self, card) ease_dollars(card.ability.extra.dollars) end,
}
SMODS.Voucher {
    key = "bigger_hand",
    loc_txt = { name = "Bigger Hand", text = { "{C:attention}+#1#{} hand size" } },
    config = { h_size = 1 },
    sprite = "bigger_hand.png",
    loc_vars = function(self, info_queue, card) return { vars = { card.ability.h_size } } end,
}
SMODS.Voucher {
    key = "even_bigger",
    loc_txt = { name = "Even Bigger", text = { "+1 hand size, +1 discard" } },
    config = { h_size = 1, d_size = 1 },
    sprite = "even_bigger.png", requires = { "bigger_hand" }, cost = 12,
    redeem = function(self, card) ease_dollars(3) end,
}
SMODS.Joker {
    key = "slotter", loc_txt = { name = "Slotter", text = { "+1 Joker slot" } },
    config = { joker_slots = 1, consumable_slots = 1 },
    rarity = 2, sprite = "slotter.png",
}
]]

local function install_cv()
    wipe_mods()
    write_mod("CV", { id = "CV", prefix = "cv", main_file = "main.lua", version = "1" }, CV_MOD)
    ModLoader.load_all()
    T.assert_eq(ModLoader.by_id.CV.status, "loaded", tostring(ModLoader.by_id.CV.error))
    local game = bootstrap.new_game(4410)
    G = game
    G.play = G.play or SMODS.PLAY
    _G.Top = _G.Top or { addPopup = function() end }
    game.money = 10
    return game
end

suite.test("mod consumables register into the pools as their set", function()
    local game = install_cv()
    local gilded = CONSUMABLE_DEFS.c_cv_gilded
    T.assert_eq(gilded.kind, "tarot")
    T.assert_eq(gilded.select.max, 2)
    T.assert_eq(CONSUMABLE_DEFS.c_cv_pluto2.hand, "High Card")
    T.assert_eq(CONSUMABLE_DEFS.c_cv_windfall.kind, "spectral")
    local function in_pool(kind, id)
        for _, x in ipairs(game:_consumable_pool_ids(kind, true)) do if x == id then return true end end
        return false
    end
    T.assert_true(in_pool("tarot", "c_cv_gilded"))
    T.assert_true(in_pool("spectral", "c_cv_windfall"))
    T.assert_eq(game:shop_price_for_consumable_offer(CONSUMABLE_DEFS.c_cv_windfall), 5, "its own cost")
    for _, v in pairs(gilded) do T.assert_true(type(v) ~= "function", "defs stay saveable data") end
    wipe_mods()
end)

suite.test("mod consumables are rolled by the real shop and pack code", function()
    -- The pools above are not what the shop and packs draw from: they index a fixed
    -- reference order (`REFERENCE_CONSUMABLE_POOL_ORDERS`), which mod cards have to join.
    local game = install_cv()
    game.consumables, game.jokers = {}, {}
    local seen = {}
    for ante = 1, 300 do
        game.ante = ante
        game.shop_offers = {}
        for _, kind in ipairs({ "tarot", "planet", "spectral" }) do
            local offer = game:_roll_shop_queue_consumable_offer(kind)
            if offer and offer.id then seen["shop:" .. offer.id] = true end
        end
        for _, pack in ipairs({ "arcana", "celestial", "spectral" }) do
            for _, ch in ipairs(game:_booster_build_choices({ pack = pack, card_count = 5 })) do
                local id = (ch.consumable_def and ch.consumable_def.id) or ch.id
                if id then seen["pack:" .. id] = true end
            end
        end
        local made = game:random_consumable_id_of_kind("tarot", nil, "test")
        if made then seen["make:" .. made] = true end
    end
    T.assert_true(seen["shop:c_cv_gilded"], "Tarot in the shop")
    T.assert_true(seen["shop:c_cv_pluto2"], "Planet in the shop")
    T.assert_true(seen["shop:c_cv_windfall"], "Spectral in the shop")
    T.assert_true(seen["pack:c_cv_gilded"], "Tarot in an Arcana pack")
    T.assert_true(seen["pack:c_cv_pluto2"], "Planet in a Celestial pack")
    T.assert_true(seen["pack:c_cv_windfall"], "Spectral in a Spectral pack")
    T.assert_true(seen["make:c_cv_gilded"], "created by The Emperor and friends")
    wipe_mods()
end)

suite.test("with no mods the consumable rolls are the reference ones", function()
    wipe_mods()
    local game = bootstrap.new_game(4412)
    G = game
    game.consumables, game.shop_offers = {}, {}
    game.ante = 3
    local offer = game:_roll_shop_queue_consumable_offer("tarot")
    T.assert_true(offer.id:match("^tarot_") ~= nil, offer.id)
end)

suite.test("a data-only Tarot enhances the selected cards", function()
    local game = install_cv()
    game.STATE = game.STATES.SELECTING_HAND
    local a = Card(0, 0, 1, 1, { rank = 5, suit = "Hearts" })
    local b = Card(0, 0, 1, 1, { rank = 9, suit = "Clubs" })
    local selected = { a, b }
    game.hand = {
        ordered_selected_nodes = function() return selected end,
        clear_selection = function() end, layout = function() end,
        is_scoring_active = function() return false end,
    }
    game.consumables, game.consumable_nodes = {}, {}
    T.assert_true(game:add_consumable("c_cv_gilded"))
    T.assert_true(game:consumable_use_enabled(1), "two selected: usable")
    selected = { a, b, Card(0, 0, 1, 1, { rank = 2, suit = "Clubs" }) }
    T.assert_false(game:consumable_use_enabled(1), "three selected: over max_highlighted")
    selected = { a, b }
    T.assert_true(game:use_consumable(1))
    T.assert_eq(a.card_data.enhancement, "gold")
    T.assert_eq(b.card_data.enhancement, "gold")
    T.assert_eq(game.last_consumable_use_id, "c_cv_gilded", "The Fool can copy it")
    wipe_mods()
end)

suite.test("a mod Planet levels its hand, then runs its use", function()
    local game = install_cv()
    local idx
    for i, name in ipairs(game.handlist) do if name == "High Card" then idx = i end end
    local before = game.hand_stats[idx].level
    game:apply_consumable_effect(copy_table(CONSUMABLE_DEFS.c_cv_pluto2))
    T.assert_eq(game.hand_stats[idx].level, before + 1)
    T.assert_eq(game.money, 11)
    wipe_mods()
end)

suite.test("can_use and use drive a coded Spectral, with per-copy ability saved", function()
    local game = install_cv()
    game.STATE = game.STATES.SHOP
    game.consumables, game.consumable_nodes = {}, {}
    T.assert_true(game:add_consumable("c_cv_windfall"))
    game.consumables[1].ability.extra.dollars = 9
    local snap = game:build_run_snapshot()
    T.assert_eq(snap.consumables[1].ability.extra.dollars, 9)
    game.money = 150
    T.assert_false(game:consumable_use_enabled(1), "can_use says no")
    game.money = 10
    T.assert_true(game:use_consumable(1))
    T.assert_eq(game.money, 19)
    wipe_mods()
end)

suite.test("mod consumable art and tooltips", function()
    local game = install_cv()
    local plain = Consumable(0, 0, copy_table(CONSUMABLE_DEFS.c_cv_gilded))
    T.assert_eq(plain.index, "mod:cv:gilded.png")
    T.assert_eq(plain.atlas.path, ModLoader.DIR .. "/CV/assets/1x/gilded.png")
    T.assert_true(plain.quad ~= nil, "drawn like a vanilla consumable sprite")
    local neg = copy_table(CONSUMABLE_DEFS.c_cv_gilded)
    neg.edition = "negative"
    T.assert_eq(Consumable(0, 0, neg).index, "mod:cv:gilded_negative.png", "negative art")
    plain:draw()
    local lines = plain:get_tooltip_body_lines()
    T.assert_eq(lines[1].segments[2].text, "2")
    T.assert_eq(lines[1].segments[2].color_key, "IMPORTANT")
    plain:draw_tooltip(0, 0)
    game:remove(plain)
    wipe_mods()
end)

suite.test("mod vouchers: tiers, the shop roll, redeem and declared modifiers", function()
    local game = install_cv()
    game.vouchers = {}
    local function candidate(id)
        for _, x in ipairs(game:_shop_voucher_candidate_ids({})) do if x == id then return true end end
        return false
    end
    T.assert_true(candidate("v_cv_bigger_hand"))
    T.assert_false(candidate("v_cv_even_bigger"), "needs Bigger Hand first")
    T.assert_eq(VOUCHER_DEFS.v_cv_bigger_hand.description, "+1 hand size")

    local hand_before = game:get_effective_hand_size_limit()
    local discards_before = game:get_effective_discards_per_round()
    game.vouchers[#game.vouchers + 1] = "v_cv_bigger_hand"
    game:apply_voucher_effect("v_cv_bigger_hand")
    T.assert_eq(game:get_effective_hand_size_limit(), hand_before + 1)
    T.assert_true(candidate("v_cv_even_bigger"))
    game.money = 0
    game.vouchers[#game.vouchers + 1] = "v_cv_even_bigger"
    game:apply_voucher_effect("v_cv_even_bigger")
    T.assert_eq(game.money, 3, "redeem ran")
    T.assert_eq(game:get_effective_hand_size_limit(), hand_before + 2)
    T.assert_eq(game:get_effective_discards_per_round(), discards_before + 1)

    -- The roll can land on a mod voucher; with no mods the pool is the reference one.
    local seen = false
    game.vouchers = {}
    for ante = 1, 200 do
        game.ante = ante
        local offer = game:_roll_one_shop_voucher_offer()
        if offer and offer.id == "v_cv_bigger_hand" then seen = true break end
    end
    T.assert_true(seen, "mod vouchers appear in the shop")

    local image, quad = game:voucher_sprite(VOUCHER_DEFS.v_cv_bigger_hand)
    T.assert_true(image ~= nil and quad ~= nil)
    wipe_mods()
end)

suite.test("a mod Joker's declared slots apply while it is held", function()
    local game = install_cv()
    game.jokers = {}
    local jokers_before = game:joker_base_capacity()
    local cons_before = game:get_effective_consumable_capacity()
    T.assert_true(game:add_joker_by_def("j_cv_slotter"))
    T.assert_eq(game:joker_base_capacity(), jokers_before + 1)
    T.assert_eq(game:get_effective_consumable_capacity(), cons_before + 1)
    game:remove_owned_joker_at(1, true)
    T.assert_eq(game:joker_base_capacity(), jokers_before)
    wipe_mods()
end)

suite.test("a failed mod takes its consumables and vouchers with it", function()
    wipe_mods()
    write_mod("CV", { id = "CV", prefix = "cv", main_file = "main.lua", version = "1" },
        CV_MOD .. "\nerror('late failure')")
    ModLoader.load_all()
    T.assert_eq(ModLoader.by_id.CV.status, "error")
    T.assert_eq(CONSUMABLE_DEFS.c_cv_gilded, nil)
    T.assert_eq(VOUCHER_DEFS.v_cv_bigger_hand, nil)
    wipe_mods()
end)

--------------------------------------------------------------------------------
-- Deck skins
--------------------------------------------------------------------------------

local SKIN_MOD = [[
SMODS.DeckSkin {
    key = "royal", suit = "Spades",
    loc_txt = { name = "Royal Court" },
    sprite = "royal_spades.png", hc_sprite = "royal_spades_hc.png",
}
SMODS.DeckSkin {
    key = "plain", suit = "hearts", loc_txt = "Plain Hearts",
    sprite = "plain_hearts.png",
}
]]

local function install_skins()
    wipe_mods()
    write_mod("Skins", { id = "Skins", prefix = "sk", main_file = "main.lua", version = "1" }, SKIN_MOD)
    ModLoader.load_all()
    T.assert_eq(ModLoader.by_id.Skins.status, "loaded", tostring(ModLoader.by_id.Skins.error))
    local game = bootstrap.new_game(4420)
    G = game
    return game
end

suite.test("a mod deck skin joins its suit's Card Art carousel and draws on live cards", function()
    local CardArt = require("card_art")
    local game = install_skins()
    local carousel = CardArt.carousel("Spades")
    T.assert_eq(carousel[#carousel].id, "sk_royal", "after the built-in sets")
    T.assert_eq(carousel[#carousel].name, "Royal Court")
    T.assert_eq(CardArt.carousel("Hearts")[#CardArt.carousel("Hearts")].name, "Plain Hearts", "loc_txt as a string")

    local atlas = game.ASSET_ATLAS[CardArt.atlas_name("Spades", "sk_royal", false)]
    T.assert_eq(atlas.path, ModLoader.DIR .. "/Skins/assets/1x/royal_spades.png")
    T.assert_eq(game.ASSET_ATLAS[CardArt.atlas_name("Spades", "sk_royal", true)].path,
        ModLoader.DIR .. "/Skins/assets/1x/royal_spades_hc.png", "its own high-contrast strip")
    T.assert_eq(game.ASSET_ATLAS[CardArt.atlas_name("Hearts", "sk_plain", true)].path,
        ModLoader.DIR .. "/Skins/assets/1x/plain_hearts.png", "no hc_sprite: the normal strip")

    game.SETTINGS.CARD_ART = CardArt.default_settings()
    local king = Card(0, 0, 1, 1, { rank = 13, suit = "Spades" })
    T.assert_true(game:set_card_art("Spades", "sk_royal", false))
    T.assert_eq(king.rank_atlas_name, "collab_spades_sk_royal_1")
    T.assert_eq(king.rank_index, 13 - 2 + 39)
    local snap = game:snapshot_settings()
    T.assert_eq(snap.CARD_ART.Spades.collab, "sk_royal", "the choice saves")

    -- The panel previews it like any other set.
    game:open_card_art_panel()
    game:art_select_suit(4)
    game._art_pick = #CardArt.carousel("Spades")
    T.assert_eq(game:art_preview_sprite(2), "collab_spades_sk_royal_1")

    -- Mod removed: the saved choice falls back to the deck's own art instead of breaking.
    wipe_mods()
    T.assert_eq(CardArt.find("Spades", "sk_royal"), nil, "rolled back with its mod")
    T.assert_eq(game:normalize_settings(snap).CARD_ART.Spades.collab, nil)
end)

suite.test("deck skins reject what this port cannot draw, saying why", function()
    wipe_mods()
    write_mod("A", { id = "A", prefix = "a", main_file = "main.lua", version = "1" },
        'SMODS.DeckSkin { key = "x", suit = "Spades", lc_atlas = "x" }')
    write_mod("B", { id = "B", prefix = "b", main_file = "main.lua", version = "1" },
        'SMODS.DeckSkin { key = "x", suit = "Spades", ranks = { "Jack", "Queen", "King", "Ace" }, sprite = "x.png" }')
    write_mod("C", { id = "C", prefix = "c", main_file = "main.lua", version = "1" },
        'SMODS.DeckSkin { key = "x", suit = "Stars", sprite = "x.png" }')
    write_mod("D", { id = "D", prefix = "d", main_file = "main.lua", version = "1" },
        'SMODS.DeckSkin { key = "x", suit = "Spades", sprite = "x.png" }\nerror("late")')
    ModLoader.load_all()
    T.assert_true(ModLoader.by_id.A.error:find("216x95", 1, true) ~= nil, ModLoader.by_id.A.error)
    T.assert_true(ModLoader.by_id.B.error:find("Ace", 1, true) ~= nil, ModLoader.by_id.B.error)
    T.assert_true(ModLoader.by_id.C.error:find("suit must be", 1, true) ~= nil, ModLoader.by_id.C.error)
    T.assert_eq(require("card_art").find("Spades", "d_x"), nil, "a failed mod's skin goes with it")
    wipe_mods()
end)

suite.test("the Mods page draws loaded and failed mods", function()
    wipe_mods()
    write_mod("Bad", { id = "Bad", prefix = "bad", main_file = "main.lua", version = "1" }, "error('nope')")
    ModLoader.load_all()
    local game = bootstrap.new_game(4402)
    G = game
    local ModsUI = require("mods_ui")
    ModsUI.open(game)
    local text = {}
    for _, l in ipairs(ModsUI.lines(game)) do text[#text + 1] = l[1] end
    T.assert_true(table.concat(text, "\n"):find("Not loaded", 1, true) ~= nil)
    ModsUI.draw(game)
    ModsUI.handle_button(game, "dpdown")
    wipe_mods()
end)

suite.test("mod loc_txt can carry one table per language", function()
    wipe_mods()
    write_mod("Loc", { id = "Loc", prefix = "loc", main_file = "main.lua", version = "1" }, [==[
SMODS.Joker {
    key = "plus",
    loc_txt = {
        ["en-us"] = { name = "Plus", text = { "{C:mult}+#1#{} Mult" } },
        zh_CN = { name = "加号", text = { "{C:mult}+#1#{}倍率" } },
    },
    config = { extra = { mult = 4 } }, rarity = 1, cost = 2, sprite = "plus.png",
    loc_vars = function(self, info_queue, card) return { vars = { card.ability.extra.mult } } end,
}
SMODS.Voucher {
    key = "big",
    loc_txt = { ["en-us"] = { name = "Big", text = { "+#1# hand size" } }, zh_CN = { name = "大", text = { "手牌上限+#1#" } } },
    config = { extra = 1 }, cost = 10, sprite = "big.png",
    loc_vars = function(self, info_queue, card) return { vars = { card.ability.extra } } end,
}
]==])
    ModLoader.load_all()
    T.assert_eq(ModLoader.by_id.Loc.status, "loaded", tostring(ModLoader.by_id.Loc.error))
    T.assert_eq(JOKER_DEFS.j_loc_plus.name, "Plus", "the English name is the definition's")
    T.assert_eq(VOUCHER_DEFS.v_loc_big.description, "+1 hand size")

    local function flat(v, out)
        out = out or {}
        if type(v) == "string" then out[#out + 1] = v
        elseif type(v) == "table" then for _, x in pairs(v) do flat(x, out) end end
        return out
    end
    local card = { ability = { extra = { mult = 4 } } }
    T.assert_true(table.concat(flat(SMODS.tooltip_lines("j_loc_plus", card))):find("Mult", 1, true) ~= nil)

    I18N.set_language("zh_CN")
    T.assert_eq(I18N.content_name("joker", "j_loc_plus", "Plus"), "加号")
    T.assert_eq(I18N.content_name("voucher", "v_loc_big", "Big"), "大")
    T.assert_eq(I18N.t("voucher.v_loc_big.description"), "手牌上限+1")
    T.assert_true(table.concat(flat(SMODS.tooltip_lines("j_loc_plus", card))):find("倍率", 1, true) ~= nil,
        "the tooltip follows the live language")

    wipe_mods()
    T.assert_false(I18N.has("joker.j_loc_plus.name"), "unloading a mod takes its strings with it")
    I18N.set_language("en")
end)

suite.test("context.probability_success repeats a chance roll that hit", function()
    wipe_mods()
    write_mod("Dice", { id = "Dice", name = "Dice", prefix = "dice", main_file = "main.lua" }, [[
SMODS.Joker {
    key = "nat20", rarity = 3, cost = 6, sprite = "nat20.png", blueprint_compat = true,
    calculate = function(self, card, context)
        if context.probability_success then return { repetitions = 1 } end
    end,
}
]])
    ModLoader.load_all()
    local game = bootstrap.new_game(4402)
    G = game
    _G.Top = _G.Top or { addPopup = function() end }
    local real_do_random = game.do_random
    game.do_random = function() return true end

    game.jokers = {}
    T.assert_eq(game:chance_triggers(1, 5, 1, "t"), 1, "a hit with no help fires once")
    T.assert_true(game:add_joker_by_def("j_seltzer"))
    T.assert_eq(game:chance_triggers(1, 5, 1, "t"), 1, "card retriggers do not repeat rolls")
    T.assert_true(game:add_joker_by_def("j_dice_nat20"))
    T.assert_eq(game:chance_triggers(1, 5, 1, "t"), 2, "the mod Joker fires it again")
    -- Blueprint copies the Joker to its right: Blueprint, then Natural 20.
    game.jokers = {}
    T.assert_true(game:add_joker_by_def("j_blueprint"))
    T.assert_true(game:add_joker_by_def("j_dice_nat20"))
    T.assert_eq(game:chance_triggers(1, 5, 1, "t"), 3, "Blueprint copies it")

    local lucky = Card(0, 0, 1, 1, { rank = 5, suit = "Spades", enhancement = "lucky" })
    local money = game.money
    local ctx = { chips = 0, mult = 1 }
    lucky:do_enhancement(ctx)
    T.assert_eq(ctx.mult, 61, "+20 Mult three times")
    T.assert_eq(game.money - money, 60, "+$20 three times")

    game.do_random = function() return false end
    T.assert_eq(game:chance_triggers(1, 5, 1, "t"), 0, "a miss never fires")
    game.do_random = real_do_random
    wipe_mods()
end)

--- A mod whose Jokers each exercise one of the hooks below. `seen` records every context flag
--- the recorder is asked with, so a test can check an engine path raised it.
local HOOKS = [[
SEEN = {}
_MOD.seen = SEEN
SMODS.Joker {
    key = "plus", rarity = 1, sprite = "j.png", blueprint_compat = true,
    calculate = function(self, card, context)
        if context.joker_main then
            if context.retrigger_joker then SEEN.retrigger_pass = (SEEN.retrigger_pass or 0) + 1 end
            return { mult = 4 }
        end
    end,
}
SMODS.Joker {
    key = "again", rarity = 1, sprite = "j.png", blueprint_compat = true,
    calculate = function(self, card, context)
        if context.retrigger_joker_check and context.other_card ~= card then
            return { repetitions = 1 }
        end
    end,
}
SMODS.Joker {
    key = "echo", rarity = 1, sprite = "j.png",
    calculate = function(self, card, context)
        if context.post_trigger and context.other_card ~= card then return { chips = 1 } end
    end,
}
SMODS.Joker {
    key = "loaded", rarity = 1, sprite = "j.png",
    calculate = function(self, card, context)
        if context.mod_probability then return { numerator = context.numerator * 2 } end
        if context.pseudorandom_result then
            SEEN.results = (SEEN.results or 0) + 1
            SEEN.last_result = context.result
        end
    end,
}
SMODS.Joker {
    key = "sure", rarity = 1, sprite = "j.png",
    calculate = function(self, card, context)
        if context.fix_probability then return { numerator = context.denominator } end
        if context.probability_success then return { repetitions = 2 } end
    end,
}
SMODS.Joker {
    key = "recorder", rarity = 1, sprite = "j.png",
    in_pool = function(self, args) return false end,
    set_ability = function(self, card, initial) card.ability.stamp = initial end,
    calculate = function(self, card, context)
        for _, flag in ipairs({ "card_added", "tag_added", "ante_change", "ending_shop",
            "starting_shop", "skip_blind", "blind_defeated", "hand_drawn", "final_scoring_step" }) do
            if context[flag] then SEEN[flag] = context[flag] end
        end
        if context.card_added then SEEN.added_card = context.card end
        if context.pre_discard then SEEN.pre_discard_hand = #context.full_hand end
        if context.discard then SEEN.discard_hand = #context.full_hand end
        if context.final_scoring_step then return { xmult = 2 } end
    end,
}
]]

local function install_hooks()
    wipe_mods()
    write_mod("Hooks", { id = "Hooks", name = "Hooks", prefix = "hk", main_file = "main.lua" }, HOOKS)
    ModLoader.load_all()
    local game = bootstrap.new_game(4403)
    G = game
    G.play = G.play or SMODS.PLAY
    _G.Top = _G.Top or { addPopup = function() end }
    return game
end

--- The mod's `SEEN` table. Mod globals live in the mod's own environment, so the mod hands
--- it over through `_MOD`.
local function seen()
    return ModLoader.by_id.Hooks.seen
end

local function hold(game, ids)
    game.jokers = {}
    for _, id in ipairs(ids) do T.assert_true(game:add_joker_by_def(id), id .. " should be addable") end
end

local function hand_scored()
    return { event = "on_hand_scored", event_name = "on_hand_scored", chips = 10, mult = 2 }
end

suite.test("retrigger_joker_check repeats another Joker's effect", function()
    local game = install_hooks()
    hold(game, { "j_hk_plus", "j_hk_again" })
    local ctx = hand_scored()
    game:emit_joker_event("on_hand_scored", ctx)
    T.assert_eq(ctx.mult, 10, "+4 Mult, then +4 again")
    T.assert_eq(seen().retrigger_pass, 1, "the repeat sees context.retrigger_joker")

    -- The staggered queue the scoring sequence uses gives the repeat its own beat.
    ctx = hand_scored()
    game:begin_joker_emit("on_hand_scored", ctx)
    local guard = 0
    while game:joker_emit_busy() and guard < 50 do
        game:_update_joker_emit_queue(1)
        guard = guard + 1
    end
    T.assert_eq(ctx.mult, 10, "the queued path repeats it too")

    -- A vanilla Joker can be retriggered as well.
    hold(game, { "j_joker", "j_hk_again" })
    ctx = hand_scored()
    game:emit_joker_event("on_hand_scored", ctx)
    T.assert_eq(ctx.mult, 10, "Joker's +4 Mult twice")
    wipe_mods()
end)

suite.test("post_trigger lets a Joker react to another's trigger", function()
    local game = install_hooks()
    hold(game, { "j_hk_plus", "j_hk_echo" })
    local ctx = hand_scored()
    game:emit_joker_event("on_hand_scored", ctx)
    T.assert_eq(ctx.mult, 6, "+4 Mult from plus")
    T.assert_eq(ctx.chips, 11, "+1 chip from echo reacting to it")
    wipe_mods()
end)

suite.test("mod_probability and fix_probability reshape every roll", function()
    local game = install_hooks()
    hold(game, { "j_hk_loaded" })
    local num, den = SMODS.get_probability_vars(nil, 1, 4)
    T.assert_eq(num, 2, "loaded doubles the numerator")
    T.assert_eq(den, 4)

    hold(game, { "j_hk_sure" })
    local hits = 0
    for i = 1, 20 do
        if game:do_random(1, 4, 1, "fixed" .. i) then hits = hits + 1 end
    end
    T.assert_eq(hits, 20, "fix_probability made the game's own roll certain")
    local hit, times = SMODS.pseudorandom_probability(nil, "modroll", 1, 1000)
    T.assert_true(hit, "and a mod's roll")
    T.assert_eq(times, 3, "probability_success adds two more passes to a mod roll")

    hold(game, { "j_hk_loaded" })
    seen().results = 0
    game:do_random(1, 4, 1, "heard")
    SMODS.pseudorandom_probability(nil, "heard2", 1, 4)
    T.assert_eq(seen().results, 2, "pseudorandom_result hears both kinds of roll")
    wipe_mods()
end)

suite.test("in_pool and set_ability", function()
    local game = install_hooks()
    T.assert_false(game:joker_allowed_in_random_pool("j_hk_recorder"), "in_pool false keeps it out")
    T.assert_true(game:joker_allowed_in_random_pool("j_hk_plus"), "others still roll")
    hold(game, { "j_hk_recorder" })
    T.assert_eq(game.jokers[1].ability.stamp, true, "set_ability ran on creation")
    wipe_mods()
end)

suite.test("lifecycle contexts fire from the game's own paths", function()
    local game = install_hooks()
    hold(game, { "j_hk_recorder" })
    T.assert_true(game:add_joker_by_def("j_joker"))
    T.assert_eq(seen().added_card, game.jokers[2], "card_added hands over the new Joker")
    game:emit_joker_event("on_ante_change", { ante_change = -1 })
    T.assert_eq(seen().ante_change, -1, "ante_change carries the change")
    game:emit_joker_event("on_shop_exit", {})
    T.assert_true(seen().ending_shop, "ending_shop")
    game:emit_joker_event("on_hand_drawn", { drawn_cards = { Card(0, 0, 1, 1, { rank = 5, suit = "Spades" }) } })
    T.assert_eq(#seen().hand_drawn, 1, "hand_drawn lists the cards drawn")
    game:addTag("investment")
    T.assert_true(seen().tag_added ~= nil, "tag_added from addTag")
    game:roll_skips()
    game:skip_blind(1)
    T.assert_true(seen().skip_blind, "skip_blind from skip_blind")
    wipe_mods()
end)

suite.test("discard contexts see the discarded batch as full_hand", function()
    local game = install_hooks()
    hold(game, { "j_hk_recorder" })
    local nodes = {
        Card(0, 0, 1, 1, { rank = 5, suit = "Spades" }),
        Card(0, 0, 1, 1, { rank = 9, suit = "Hearts" }),
    }
    game:emit_joker_event("on_pre_discard", { discarded_nodes = nodes, discard_reason = "discard" })
    T.assert_eq(seen().pre_discard_hand, 2, "pre_discard")
    game:emit_joker_event("on_discard", {
        discarded_nodes = nodes, card_node = nodes[1], discard_reason = "discard",
    })
    T.assert_eq(seen().discard_hand, 2, "discard")
    wipe_mods()
end)

suite.test("final_scoring_step changes the score before it lands", function()
    local game = install_hooks()
    hold(game, { "j_hk_recorder" })
    game.selectedHandChips, game.selectedHandMult = 10, 2
    local hand = setmetatable({
        _play_sequence = { phase = "finalize", finalize_step = 2, timer = 0, cards = {} },
    }, { __index = Hand })
    local seq = hand._play_sequence
    for _ = 1, 20 do
        if seq.final_score then break end
        hand:_update_play_sequence(0.5)
        game:_update_joker_emit_queue(1)
    end
    T.assert_eq(seq.final_score, 40, "10 chips x (2 Mult x2)")
    wipe_mods()
end)

return suite
