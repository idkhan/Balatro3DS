--- Reaching the collection mid-run, and the settings from the main menu.
---
--- The base game offers both at the top level: the collection from the in-run options overlay
--- (`UI_definitions.lua:2223`) and Options from the main menu (`:2295`). This port had the
--- collection behind the main menu only, and settings behind an in-run pause only.
local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

bootstrap.load()
local CollectionUI = require("collection_ui")
local MainMenuUI = require("main_menu_ui")

local function target_kinds(game)
    local kinds = {}
    for _, t in ipairs(game:build_pause_focus_targets()) do kinds[#kinds + 1] = t.kind end
    return kinds
end

local function has(list, value)
    for _, v in ipairs(list) do if v == value then return true end end
    return false
end

suite.test("the pause menu offers the collection and opens it over the run", function()
    local g = bootstrap.new_game(7101)
    g.STATE = g.STATES.PAUSED
    g._pause_show_settings = false
    g:draw_bottom_pause()

    T.assert_true(has(target_kinds(g), "collection"), "collection is a pause target")
    T.assert_not_nil(g._pause_collection_rect, "and has a touch rect")

    T.assert_true(g:open_collection_over_run())
    T.assert_true(g._collection_over_run, "the collection is flagged as over a run")
    T.assert_true(g._collection_open)
    T.assert_eq(g.STATE, g.STATES.PAUSED, "the run stays paused underneath")

    -- Backing out returns to the pause menu rather than the main menu.
    CollectionUI.back_to_main(g)
    T.assert_eq(g._collection_over_run, nil)
    T.assert_false(g._collection_open)
    T.assert_eq(g.STATE, g.STATES.PAUSED, "still paused, not dumped to the menu")
    T.assert_eq(g._menu_sub_state, nil, "and not left in a menu sub-state")
end)

suite.test("opening the collection from the main menu still returns to the main menu", function()
    local g = bootstrap.new_game(7102)
    g.STATE = g.STATES.MENU
    CollectionUI.open(g)
    T.assert_true(g._collection_open)
    T.assert_eq(g._collection_over_run, nil, "not flagged as over a run")

    CollectionUI.back_to_main(g)
    T.assert_eq(g._menu_sub_state, "main", "menu path is unchanged")
end)

suite.test("the collection cannot be opened over a run that is not paused", function()
    local g = bootstrap.new_game(7103)
    g.STATE = g.STATES.SELECTING_HAND
    T.assert_false(g:open_collection_over_run())
    T.assert_eq(g._collection_over_run, nil)
end)

local function menu_kinds(game)
    local kinds = {}
    for _, t in ipairs(MainMenuUI.build_main_menu_focus_targets(game)) do kinds[#kinds + 1] = t.kind end
    return kinds
end

suite.test("the main menu offers settings and hands the screen back on close", function()
    local g = bootstrap.new_game(7104)
    g.STATE = g.STATES.MENU
    g._menu_sub_state = "main"
    g._menu_page = "options"
    MainMenuUI.draw_bottom(g)

    local kinds = menu_kinds(g)
    T.assert_true(has(kinds, "settings"), "settings is an Options entry")
    T.assert_true(has(kinds, "back"), "and the page can be backed out of")

    T.assert_true(g:open_settings_from_menu())
    T.assert_true(g._settings_over_menu)
    T.assert_true(g._pause_show_settings, "it borrows the pause settings panel")
    T.assert_eq(g._pause_settings_tab, "general")

    T.assert_true(g:close_settings_from_menu())
    T.assert_eq(g._settings_over_menu, nil)
    T.assert_false(g._pause_show_settings, "the panel closes with it")
    T.assert_eq(g.STATE, g.STATES.MENU)
end)

suite.test("menu settings do not open from inside a run", function()
    local g = bootstrap.new_game(7105)
    g.STATE = g.STATES.SELECTING_HAND
    T.assert_false(g:open_settings_from_menu())
    T.assert_eq(g._settings_over_menu, nil)
end)

--- The panel is one implementation reached from two places, so its touch handling had to come
--- out of `touchpressed`. Both callers must reach the same code.
suite.test("the settings panel takes touch from the menu as well as from a pause", function()
    local g = bootstrap.new_game(7106)
    T.assert_eq(type(g.handle_pause_settings_touch), "function",
        "settings touch is callable outside touchpressed")

    g.STATE = g.STATES.MENU
    g:open_settings_from_menu()
    MainMenuUI.draw_bottom(g)
    T.assert_not_nil(g._pause_back_rect, "the panel laid itself out over the menu")

    -- Pressing Back closes the panel through the shared handler.
    local r = g._pause_back_rect
    g:handle_pause_settings_touch(r.x + r.w * 0.5, r.y + r.h * 0.5)
    T.assert_false(g._pause_show_settings, "Back closes the panel")
end)

return suite
