local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

bootstrap.load()
local I18N = require("localization")
local Fonts = require("fonts")
local Utf8 = require("utf8_text")

local suite = T.suite()

local ROOT = (os.getenv("BALATRO_ROOT") or ".") .. "/"

local function placeholders(value)
    local out = {}
    if type(value) == "string" then
        for name in value:gmatch("{([%w_]+)}") do out[name] = true end
    elseif type(value) == "table" then
        for _, v in pairs(value) do
            for name in pairs(placeholders(v)) do out[name] = true end
        end
    end
    return out
end

local function keys_of(t)
    local out = {}
    for k in pairs(t) do out[#out + 1] = k end
    table.sort(out)
    return table.concat(out, ",")
end

--- Always leave the process on English: the language is module state, and every other test file
--- expects English strings and the Latin face.
local function back_to_english(game)
    I18N.set_language("en")
    if game then
        game.SETTINGS.LANGUAGE = "en"
        game:apply_language("en")
    end
end

--------------------------------------------------------------------------------
-- Strings
--------------------------------------------------------------------------------

suite.test("lookups fall back from the language to English to the caller to the key", function()
    I18N.set_language("zh_CN")
    T.assert_true(I18N.t("menu.new_run") ~= "New Run", "translated")
    T.assert_eq(I18N.t("no.such.key", nil, "Fallback"), "Fallback")
    T.assert_eq(I18N.t("no.such.key"), "no.such.key", "a missing key stays visible")
    T.assert_eq(I18N.t("menu.seed", { seed = "ABC" }):find("ABC", 1, true) ~= nil, true, "placeholders fill")
    T.assert_false(I18N.set_language("xx"), "unknown language")
    T.assert_eq(I18N.get_language(), "en", "and it lands on English")
    T.assert_eq(I18N.t("menu.new_run"), "New Run")
    back_to_english()
end)

suite.test("every interface translation matches an English key and its placeholders", function()
    local en = dofile(ROOT .. "locales/en.lua")
    for _, code in ipairs(I18N.available_languages()) do
        if code ~= "en" then
            local strings = dofile(ROOT .. "locales/" .. code .. ".lua")
            for key, value in pairs(strings) do
                T.assert_true(en[key] ~= nil, code .. ": " .. key .. " has no English string")
                T.assert_eq(keys_of(placeholders(value)), keys_of(placeholders(en[key])),
                    code .. ": " .. key .. " placeholders differ from English")
            end
        end
    end
end)

suite.test("content translations name content that exists", function()
    -- A translation for a Joker or consumable that was renamed or removed is dead weight that
    -- also bloats the baked font; catch it here rather than in a build.
    local catalogs = { joker = JOKER_DEFS, consumable = CONSUMABLE_DEFS, voucher = VOUCHER_DEFS }
    for _, code in ipairs(I18N.available_languages()) do
        I18N.set_language(code)
        for kind, defs in pairs(catalogs) do
            for id in pairs(defs) do
                -- Every catalog entry resolves to something printable in every language.
                local name = I18N.content_name(kind, id, defs[id].name)
                T.assert_true(type(name) == "string" and name ~= "", kind .. " " .. id .. " has no name")
            end
        end
    end
    back_to_english()
end)

--------------------------------------------------------------------------------
-- Text handling
--------------------------------------------------------------------------------

suite.test("UTF-8 text splits into characters, not bytes", function()
    local chars = Utf8.chars("A\195\169\231\174\128\228\189\147")   -- "Aé简体"
    T.assert_eq(#chars, 4)
    T.assert_eq(chars[3], "\231\174\128")
    T.assert_eq(Utf8.codepoint("\231\174\128"), 0x7B80)
    T.assert_eq(Utf8.len("plain"), 5)
end)

suite.test("Chinese breaks between characters and keeps punctuation on the right side", function()
    local text = "\230\137\147\229\135\186\239\188\140\229\128\141\231\142\135"  -- "打出，倍率"
    local pieces = Utf8.break_pieces(text)
    T.assert_eq(#pieces, 4, "four characters, the comma held to the one before it")
    T.assert_eq(pieces[2], "\229\135\186\239\188\140", "出，")
    T.assert_eq(table.concat(pieces), text, "nothing lost")
    T.assert_eq(#Utf8.break_pieces("Mult"), 1, "Latin text stays whole")
    T.assert_eq(Utf8.break_pieces("+4\229\128\141")[1], "+4")
end)

suite.test("tooltips wrap Chinese inside the screen", function()
    local TooltipDraw = require("tooltip_draw")
    local line = ("\229\128\141\231\142\135"):rep(40)              -- 80 characters, no spaces
    local font = love.graphics.newFont(13)
    local resolved = { TooltipDraw.build_segments_from_text(line) }
    -- Drawing wraps through `wrap_segments`; a single unbreakable line would overrun.
    TooltipDraw.draw_tooltip_layout(font, "T", resolved, 0, 0, 72, 95)
    local cached = resolved[1]._wrap
    T.assert_true(cached and #cached.lines > 1, "an unspaced sentence wraps onto several lines")
end)

suite.test("animated headlines animate whole characters", function()
    local DynaText = require("dyna_text")
    local state = DynaText.new({ float_amount = 1 })
    love.graphics.setFont(love.graphics.newFont(13))
    DynaText.draw(state, "\229\176\143\229\155\162", 0, 0, 100, "left")   -- two characters
    T.assert_eq(state.layout.count, 2)
end)

--------------------------------------------------------------------------------
-- Fonts
--------------------------------------------------------------------------------

suite.test("the language font draws every role from a baked height, never below 13 px", function()
    local pixel = Fonts.build("native", "zh_CN")
    T.assert_eq(pixel.LANGUAGE, "zh_CN")
    T.assert_eq(pixel.MICRO_HEIGHT, 13, "9 px Chinese is unreadable")
    T.assert_eq(pixel.SMALL_HEIGHT, 13)
    T.assert_eq(pixel.PRICE_HEIGHT, 17, "18 is not reachable; 17 is")
    T.assert_eq(pixel.MEDIUM_HEIGHT, 21)
    T.assert_eq(pixel.LARGE_HEIGHT, Fonts.LANGUAGE_CELL_HEIGHTS[#Fonts.LANGUAGE_CELL_HEIGHTS])
    local latin = Fonts.build("native", "en")
    T.assert_eq(latin.LANGUAGE, nil)
    T.assert_eq(latin.MEDIUM_HEIGHT, 22, "English is untouched")
end)

suite.test("dev/config.sh bakes the heights fonts.lua loads", function()
    local f = assert(io.open(ROOT .. "dev/config.sh", "rb"))
    local text = f:read("*a")
    f:close()
    local list = text:match("CJK_CELL_HEIGHTS=%(([^)]*)%)")
    T.assert_true(list ~= nil, "CJK_CELL_HEIGHTS in config.sh")
    local heights = {}
    for n in list:gmatch("%d+") do heights[#heights + 1] = tonumber(n) end
    T.assert_deep_eq(heights, Fonts.LANGUAGE_CELL_HEIGHTS)
    T.assert_true(text:find('"zh_CN:', 1, true) ~= nil, "zh_CN has a source font")
end)

--------------------------------------------------------------------------------
-- The setting
--------------------------------------------------------------------------------

suite.test("the language is a saved setting that swaps strings and fonts together", function()
    local game = bootstrap.new_game(5501)
    G = game
    T.assert_eq(game.SETTINGS.LANGUAGE, "en")
    T.assert_true(game:set_language("zh_CN"))
    T.assert_eq(I18N.get_language(), "zh_CN")
    T.assert_eq(game.FONTS.PIXEL.LANGUAGE, "zh_CN")
    T.assert_eq(game.FONTS.PIXEL.MEDIUM_HEIGHT, 21)
    T.assert_eq(game:snapshot_settings().LANGUAGE, "zh_CN")
    T.assert_eq(game:normalize_settings({ LANGUAGE = "zh_CN" }).LANGUAGE, "zh_CN")
    T.assert_eq(game:normalize_settings({ LANGUAGE = "klingon" }).LANGUAGE, "en", "unknown: English")
    T.assert_false(game:set_language("klingon"))

    -- Loading settings puts the saved language live, as a boot does.
    game:set_language("en")
    T.assert_eq(game.FONTS.PIXEL.LANGUAGE, nil)
    game.SETTINGS.LANGUAGE = "zh_CN"
    game:save_settings()
    game:load_settings()
    T.assert_eq(I18N.get_language(), "zh_CN", "the saved language is live after a load")
    back_to_english(game)
    game:save_settings()
end)

--------------------------------------------------------------------------------
-- Content
--------------------------------------------------------------------------------

suite.test("every vanilla card, voucher, blind, tag, deck and stake has a Chinese name and text", function()
    local game = bootstrap.new_game(5510)
    G = game
    I18N.set_language("zh_CN")
    local missing = {}
    local function check(kind, id, needs_text)
        if not I18N.has(kind .. "." .. id .. ".name") then missing[#missing + 1] = kind .. "." .. id .. ".name" end
        if needs_text and not I18N.has(kind .. "." .. id .. ".description") then
            missing[#missing + 1] = kind .. "." .. id .. ".description"
        end
    end
    for id, def in pairs(JOKER_DEFS) do if not def.mod_id then check("joker", id, true) end end
    for id, def in pairs(CONSUMABLE_DEFS) do
        if not def.mod_id then check("consumable", id, def.kind ~= "planet") end   -- planets are built from hand stats
    end
    for id, def in pairs(VOUCHER_DEFS) do if not def.mod_id then check("voucher", id, true) end end
    for id in pairs(game.P_BLINDS) do check("blind", id, true) end
    for id in pairs(game.P_TAGS) do if id ~= "tag_undiscovered" then check("tag", id, true) end end
    for _, d in ipairs(DECK_DEFS) do if not d.omit then check("deck", d.id, true) end end
    for _, d in ipairs(STAKE_DEFS) do check("stake", d.id, true) end
    table.sort(missing)
    T.assert_eq(#missing, 0, "untranslated: " .. table.concat(missing, ", "))
    back_to_english()
end)

suite.test("English content text is exactly the catalog's", function()
    local game = bootstrap.new_game(5511)
    G = game
    T.assert_eq(I18N.content_name("joker", "j_joker", "Joker"), "Joker")
    T.assert_eq(game:get_blind_display_name(1), "Small Blind")
    local j = Joker(0, 0, 1, 1, JOKER_DEFS.j_ceremonial)
    local lines = j:get_tooltip_body_lines()
    T.assert_eq(lines[1].kind, "rarity_badge")
    T.assert_eq(lines[1].text, "Uncommon")
    T.assert_eq(j:get_live_current_tooltip_text(""), "(Currently +0 Mult)")
    local entries = require("collection_catalog").get_entries("jokers")
    T.assert_eq(entries[1].name, "Joker")
end)

suite.test("in Chinese, Jokers, consumables, blinds and the collection read translated", function()
    local game = bootstrap.new_game(5512)
    G = game
    I18N.set_language("zh_CN")
    local CollectionCatalog = require("collection_catalog")

    local j = Joker(0, 0, 1, 1, JOKER_DEFS.j_ceremonial)
    local lines = j:get_tooltip_body_lines()
    T.assert_eq(lines[1].kind, "rarity_badge")
    T.assert_eq(lines[1].text, I18N.t("rarity.uncommon"))
    T.assert_true(lines[1].text ~= "Uncommon", "the badge is translated")
    T.assert_true(#lines >= 2, "translated description lines follow the badge")
    local live = j:get_live_current_tooltip_text("")
    T.assert_true(not live:find("Currently", 1, true), "live values are translated: " .. live)
    T.assert_true(I18N.content_name("joker", "j_joker", "Joker") ~= "Joker")

    -- Castle's two live lines: the suit line, and the running total marked runtime = "value".
    local castle = Joker(0, 0, 1, 1, JOKER_DEFS.j_castle)
    castle.random_suit = "Hearts"
    T.assert_true(castle:get_live_current_tooltip_text("", "value")
        ~= castle:get_live_current_tooltip_text("", nil), "the two Castle lines differ")

    local planet = Consumable(0, 0, copy_table(CONSUMABLE_DEFS.planet_pluto))
    local plines = planet:get_tooltip_body_lines()
    T.assert_eq(plines[2], I18N.hand_name("High Card"), "the hand is named in Chinese")
    T.assert_true(plines[2] ~= "High Card")
    local fool = Consumable(0, 0, copy_table(CONSUMABLE_DEFS.tarot_fool))
    T.assert_true(#fool:get_tooltip_body_lines() >= 1)
    planet:draw_tooltip(0, 0)
    game:remove(planet)
    game:remove(fool)

    T.assert_true(game:get_blind_display_name(1) ~= "Small Blind", "blind names")
    T.assert_true(CollectionCatalog.get_entries("jokers")[1].name ~= "Joker", "the collection rebuilt in Chinese")

    -- Hands are compared by their internal names; only the drawn label is translated.
    T.assert_eq(I18N.hand_name("Flush") ~= "Flush", true)
    back_to_english()
    T.assert_eq(CollectionCatalog.get_entries("jokers")[1].name, "Joker", "and back to English")
end)

suite.test("the playing-card tooltip header keeps the suit coloured in either word order", function()
    local game = bootstrap.new_game(5513)
    G = game
    local card = Card(0, 0, 1, 1, { rank = 12, suit = "Hearts", enhancement = "gold", seal = "red" })
    card.face_up = true
    card:draw_tooltip(10, 10)
    I18N.set_language("zh_CN")
    game:apply_language("zh_CN")
    card:draw_tooltip(10, 10)
    back_to_english(game)
end)

suite.test("the main menu's globe opens a language picker", function()
    local MainMenuUI = require("main_menu_ui")
    local game = bootstrap.new_game(5502)
    G = game
    game:enter_main_menu()
    MainMenuUI.open_page(game, "main")
    MainMenuUI.draw_bottom(game)
    local globe
    for _, t in ipairs(MainMenuUI.build_main_menu_focus_targets(game)) do
        if t.kind == "language" then globe = t.rect end
    end
    T.assert_true(globe ~= nil, "a globe on the root page, in the focus ring")

    -- Touch: the globe opens the picker, a language picks it and closes it.
    MainMenuUI.handle_touch(game, globe.x + 2, globe.y + 2)
    T.assert_true(game._language_picker_open)
    MainMenuUI.draw_bottom(game)
    local zh
    for _, r in ipairs(game._language_picker_rects) do if r.language == "zh_CN" then zh = r end end
    MainMenuUI.handle_touch(game, zh.x + 2, zh.y + 2)
    T.assert_eq(I18N.get_language(), "zh_CN")
    T.assert_eq(game.SETTINGS.LANGUAGE, "zh_CN", "and remembered")
    T.assert_eq(game._language_picker_open, nil)

    -- Buttons: open, move, confirm; and B closes without changing anything.
    MainMenuUI.open_language_picker(game)
    MainMenuUI.draw_bottom(game)
    -- Walk up to English by name: how many languages sit between it and Chinese depends on
    -- what ships, and picking whichever is one row up leaves every later test in that language.
    local languages = I18N.available_languages()
    for _ = 1, #languages do
        if languages[game._language_picker_focus] == "en" then break end
        MainMenuUI.handle_button(game, "dpup")
    end
    MainMenuUI.handle_button(game, "a")
    T.assert_eq(I18N.get_language(), "en")
    MainMenuUI.open_language_picker(game)
    MainMenuUI.handle_button(game, "dpdown")
    MainMenuUI.handle_button(game, "b")
    T.assert_eq(game._language_picker_open, nil)
    T.assert_eq(I18N.get_language(), "en", "cancel changes nothing")

    -- Not on the sub-pages, and no longer in Settings.
    MainMenuUI.open_page(game, "options")
    MainMenuUI.draw_bottom(game)
    for _, t in ipairs(MainMenuUI.build_main_menu_focus_targets(game)) do
        T.assert_true(t.kind ~= "language", "only on the root page")
    end
    game:open_settings_from_menu()
    game:draw_bottom_pause()
    for _, t in ipairs(game:build_pause_focus_targets()) do
        T.assert_true(t.kind ~= "language", "not in Settings")
    end
    back_to_english(game)
    game:save_settings()
end)

--------------------------------------------------------------------------------
-- Screens
--------------------------------------------------------------------------------

suite.test("interface strings keep the format directives the code fills", function()
    -- `string.format` fills these positionally, so a translation has to keep each one, in order.
    local en, zh = dofile(ROOT .. "locales/en.lua"), dofile(ROOT .. "locales/zh_CN.lua")
    local function directives(s)
        local out = {}
        for d in s:gsub("%%%%", ""):gmatch("%%[%d%.%-]*[dsf]") do out[#out + 1] = d:sub(-1) end
        return table.concat(out)
    end
    for key, value in pairs(en) do
        if type(value) == "string" and type(zh[key]) == "string" then
            T.assert_eq(directives(zh[key]), directives(value), key)
        end
    end
end)

suite.test("How to Play has the same pages in every language", function()
    local MainMenuUI = require("main_menu_ui")
    local english = MainMenuUI.HOW_TO_PLAY_PAGES
    I18N.set_language("zh_CN")
    local pages = MainMenuUI.how_to_play_pages()
    T.assert_true(pages ~= english, "a translated set")
    T.assert_eq(#pages, #english)
    for i, page in ipairs(pages) do
        T.assert_true(type(page.title) == "string" and #page.lines == #english[i].lines, "page " .. i)
    end
    back_to_english()
    T.assert_true(MainMenuUI.how_to_play_pages() == english, "English is the table itself")
end)

--- Draw `fn` with every string the screens print recorded.
local function capture(fn)
    local seen, errors = {}, {}
    local g = love.graphics
    local print0, printf0 = g.print, g.printf
    local function record(text)
        if type(text) == "string" then seen[#seen + 1] = text end
    end
    g.print = function(text, ...) record(text); return print0(text, ...) end
    g.printf = function(text, ...) record(text); return printf0(text, ...) end
    local ok, err = xpcall(fn, function(e)
        if type(e) == "table" then return tostring(e.message or e.msg or e[1]) end
        return debug.traceback(e)
    end)
    g.print, g.printf = print0, printf0
    if not ok then errors[#errors + 1] = err end
    return seen, errors
end

--- Words a screen may still show in Latin letters in Chinese: button glyph names, the
--- hardware's own labels, and the numbers' units.
local LATIN_ALLOWED = {
    Boss = true, Start = true, Select = true, START = true, SELECT = true, Enter = true, Esc = true,
    -- The mods folder's path, which is a path on the SD card in any language.
    sdmc = true, mods = true,
}

--- Every run of four or more Latin letters a translated screen printed.
local function english_left(seen)
    local out = {}
    for _, s in ipairs(seen) do
        for word in s:gmatch("%a%a%a%a+") do
            if not LATIN_ALLOWED[word] then out[#out + 1] = word .. " (in \"" .. s .. "\")" end
        end
    end
    return out
end

suite.test("in Chinese, the menus, the run screens and the end screens print no English", function()
    local MainMenuUI = require("main_menu_ui")
    local ProfileUI = require("profile_ui")
    local ModsUI = require("mods_ui")
    local CollectionUI = require("collection_ui")
    local GameOverUI = require("game_over_ui")
    local YouWinUI = require("you_win")
    local RunInfoUI = require("run_info_ui")
    local DeckViewUI = require("deck_view_ui")
    require("topUI")
    local game = bootstrap.new_game(5503)
    G = game
    local top = _G.TopUI()
    game.SETTINGS.LANGUAGE = "zh_CN"
    game:apply_language("zh_CN")

    local all_seen, all_errors = {}, {}
    local function screen(name, fn)
        local seen, errors = capture(fn)
        for _, s in ipairs(seen) do all_seen[#all_seen + 1] = s end
        for _, e in ipairs(errors) do all_errors[#all_errors + 1] = name .. ": " .. e end
    end

    game:enter_main_menu()
    for _, page in ipairs({ "main", "play", "options" }) do
        screen("menu " .. page, function()
            MainMenuUI.open_page(game, page)
            MainMenuUI.draw_bottom(game)
            MainMenuUI.draw_top("top", game)
        end)
    end
    screen("how to play", function()
        MainMenuUI.open_how_to_play(game)
        for i = 1, #MainMenuUI.how_to_play_pages() do
            game._how_to_play_page = i
            MainMenuUI.draw_bottom(game)
        end
    end)
    screen("challenges", function()
        MainMenuUI.open_challenges(game)
        MainMenuUI.draw_bottom(game)
        MainMenuUI.draw_top("top", game)
    end)
    screen("deck select", function()
        MainMenuUI.open_deck_select(game)
        MainMenuUI.draw_bottom(game)
        MainMenuUI.draw_top("top", game)
    end)
    screen("collection", function()
        CollectionUI.open(game)
        MainMenuUI.draw_bottom(game)
        MainMenuUI.draw_top("top", game)
        CollectionUI.open_category(game, "jokers")
        MainMenuUI.draw_bottom(game)
        MainMenuUI.draw_top("top", game)
    end)
    screen("profile", function()
        ProfileUI.open(game)
        MainMenuUI.draw_bottom(game)
        game._profile_show_stats = true
        MainMenuUI.draw_bottom(game)
        ProfileUI.open_stats(game)
        MainMenuUI.draw_bottom(game)
    end)
    screen("mods", function()
        ModsUI.open(game)
        MainMenuUI.draw_bottom(game)
    end)
    screen("settings", function()
        game:open_settings_from_menu()
        for _, tab in ipairs({ "game", "audio", "controls", "art" }) do
            game._pause_settings_tab = tab
            game:draw_bottom_pause()
        end
    end)

    -- A run.
    game:start_new_run_from_main_menu()
    if game.STATE ~= game.STATES.BLIND_SELECT then game:enter_blind_select() end
    screen("blind select", function()
        T.assert_eq(game.STATE, game.STATES.BLIND_SELECT, "reached blind select")
        game:draw()
        top:draw("top")
    end)
    screen("pause", function()
        game:enter_pause_menu()
        game._pause_show_settings = nil
        game:draw_bottom_pause()
        game:exit_pause_menu()
    end)
    screen("run info", function()
        RunInfoUI.draw_top("top", game)
        RunInfoUI.draw_bottom(game)
    end)
    screen("deck view", function()
        DeckViewUI.draw_top("top", game)
    end)
    screen("round win", function()
        -- Builds the payout rows; the state change itself rides the end-of-round animation.
        game:enter_round_win_after_blind()
        game:set_state(game.STATES.ROUND_EVAL)
        T.assert_true(#(game._round_win_display_lines or {}) > 0, "the payout rows are built")
        game:draw()
        top:draw("top")
    end)
    screen("shop", function()
        game:enter_shop_after_blind()
        T.assert_eq(game.STATE, game.STATES.SHOP, "reached the shop")
        game:draw()
        top:draw("top")
        for i = 1, #(game.shop_booster_offers or {}) do
            game:_draw_shop_booster_tooltip(game.shop_booster_offers[i], { x = 10, y = 10, w = 60, h = 80 })
        end
    end)
    screen("booster pack", function()
        game.money = 100
        game:buy_shop_booster(1)
        T.assert_eq(game.STATE, game.STATES.OPEN_BOOSTER, "opened a pack")
        game:draw()
        top:draw("top")
    end)
    screen("game over", function()
        GameOverUI.draw_top(game)
        GameOverUI.draw_bottom(game)
    end)
    screen("you win", function()
        YouWinUI.drawTop(game)
    end)

    T.assert_eq(#all_errors, 0, table.concat(all_errors, "\n"))
    T.assert_true(#all_seen > 100, "the screens drew their text (" .. #all_seen .. " strings)")
    local left = english_left(all_seen)
    T.assert_eq(#left, 0, "English left on Chinese screens:\n" .. table.concat(left, "\n"))
    back_to_english(game)
end)

return suite
