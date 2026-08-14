--- The main menu's Play / Options / Collection / Quit tree, and the title logo's live ace.
---
--- The base game's main menu is four entries (`UI_definitions.lua:6216-6222`) with the run
--- choices behind Play (`:5306-5330`) and the rest behind Options (`:2248-2260`). This port
--- had all of them flattened onto one screen.
local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

bootstrap.load()
local MainMenuUI = require("main_menu_ui")
local ProfileUI = require("profile_ui")

local function kinds(game)
    local out = {}
    for _, t in ipairs(MainMenuUI.build_main_menu_focus_targets(game)) do out[#out + 1] = t.kind end
    return out
end

local function has(list, value)
    for _, v in ipairs(list) do if v == value then return true end end
    return false
end

local function menu(seed, page)
    local g = bootstrap.new_game(seed)
    g.STATE = g.STATES.MENU
    g._menu_sub_state = "main"
    g._menu_page = page
    MainMenuUI.draw_bottom(g)
    return g
end

--- Activate an entry by kind, wherever the current page put it, then redraw. The focus
--- targets are whatever the last draw laid out, so a press has to be followed by a frame
--- before the new page's rects exist -- which is the order the real loop runs in.
local function press(game, kind)
    for i, t in ipairs(MainMenuUI.build_main_menu_focus_targets(game)) do
        if t.kind == kind then
            game._menu_focus_index = i
            local ok = MainMenuUI.activate_main_menu_focus(game)
            if game._menu_sub_state == "main" then MainMenuUI.draw_bottom(game) end
            return ok
        end
    end
    return false
end

suite.test("the root menu is the base game's four entries", function()
    local g = menu(9001, "main")
    local k = kinds(g)
    T.assert_true(has(k, "play"), "Play")
    T.assert_true(has(k, "options"), "Options")
    T.assert_true(has(k, "collection"), "Collection")
    T.assert_true(has(k, "quit"), "Quit")

    -- The run choices are no longer at the top level.
    T.assert_false(has(k, "start"), "New Run moved behind Play")
    T.assert_false(has(k, "challenges"), "so did Challenges")
    T.assert_false(has(k, "settings"), "and Settings moved behind Options")
end)

suite.test("Play holds the run choices and Continue only appears with a save", function()
    local g = menu(9002, "main")
    -- Stubbed both ways: the stub filesystem is shared across the suite, so whether a save
    -- exists depends on what ran first.
    g.has_saved_run = function() return false end
    T.assert_true(press(g, "play"))
    T.assert_eq(MainMenuUI.current_page(g), "play")

    local k = kinds(g)
    T.assert_true(has(k, "start"), "New Run")
    T.assert_true(has(k, "challenges"), "Challenges")
    T.assert_false(has(k, "continue"), "no saved run, so no Continue")

    -- With a run to resume, Continue leads the page the way the base game pre-selects its
    -- Continue tab (`UI_definitions.lua:5316`).
    g.has_saved_run = function() return true end
    MainMenuUI.draw_bottom(g)
    local with_save = kinds(g)
    T.assert_eq(with_save[1], "continue", "Continue leads once there is a save")
end)

suite.test("Options holds settings, stats and the port's own controls page", function()
    local g = menu(9003, "main")
    T.assert_true(press(g, "options"))
    T.assert_eq(MainMenuUI.current_page(g), "options")

    local k = kinds(g)
    T.assert_true(has(k, "settings"))
    T.assert_true(has(k, "stats"))
    T.assert_true(has(k, "profile"))
    T.assert_true(has(k, "how_to_play"))
end)

--- Settings opened from Options borrows the pause panel. Backing out of it used to clear only
--- `_pause_show_settings`, which left the pause list (Continue / Settings / Collection / New Run /
--- Save and Quit) drawn over the main menu with no way out -- Continue calls `exit_pause_menu`,
--- which refuses to run while `STATE` is MENU.
suite.test("backing out of menu settings returns to Options, not the pause list", function()
    for _, exit_with in ipairs({ "touch", "button" }) do
        local g = menu(9013, "main")
        press(g, "options")
        T.assert_true(press(g, "settings"), exit_with .. ": Settings opens")
        T.assert_true(g._settings_over_menu, exit_with .. ": over the menu")
        T.assert_true(g._pause_show_settings)

        MainMenuUI.draw_bottom(g)
        local back = g._pause_back_rect
        T.assert_not_nil(back, exit_with .. ": the panel has a Back button")

        if exit_with == "touch" then
            g:touchpressed(1, back.x + back.w * 0.5, back.y + back.h * 0.5)
        else
            MainMenuUI.handle_button(g, "b")
        end

        T.assert_false(g._settings_over_menu, exit_with .. ": the panel closes all the way out")
        T.assert_false(g._pause_show_settings)
        T.assert_eq(g.STATE, g.STATES.MENU)

        -- And the menu is live again rather than the pause list.
        MainMenuUI.draw_bottom(g)
        T.assert_eq(MainMenuUI.current_page(g), "options")
        T.assert_true(has(kinds(g), "settings"), exit_with .. ": Options is back")
    end
end)

--- In an actual run the same Back has to keep landing on the pause list.
suite.test("backing out of pause settings still lands on the pause list", function()
    local g = bootstrap.new_game(9014)
    g.STATE = g.STATES.PAUSED
    g._pause_show_settings = true
    g._pause_settings_tab = "general"
    g:leave_settings_panel()
    T.assert_false(g._pause_show_settings)
    T.assert_eq(g.STATE, g.STATES.PAUSED, "the run stays paused")
end)

suite.test("cancel walks back up the tree and stops at the root", function()
    local g = menu(9004, "main")
    press(g, "options")
    T.assert_eq(MainMenuUI.current_page(g), "options")

    MainMenuUI._button_main(g, "b")
    T.assert_eq(MainMenuUI.current_page(g), "main", "cancel leaves a sub-page")

    MainMenuUI._button_main(g, "b")
    T.assert_eq(MainMenuUI.current_page(g), "main", "and the root has nowhere further to go")
end)

suite.test("a sub-page carries Back where the root carries the profile", function()
    local root = menu(9005, "main")
    T.assert_true(has(kinds(root), "profile"), "root footer is the loaded profile")
    T.assert_false(has(kinds(root), "back"))

    local sub = menu(9006, "play")
    T.assert_true(has(kinds(sub), "back"), "sub-page footer is Back")
end)

suite.test("entering the menu resets to the root page", function()
    local g = bootstrap.new_game(9007)
    g._menu_page = "options"
    g:enter_main_menu()
    T.assert_eq(MainMenuUI.current_page(g), "main")
end)

suite.test("an unknown page falls back to the root rather than drawing nothing", function()
    local g = menu(9008, "nonsense")
    T.assert_eq(MainMenuUI.current_page(g), "main")
    T.assert_true(has(kinds(g), "play"))
end)

suite.test("Stats opens its own page and backs out to the menu", function()
    local g = menu(9009, "options")
    T.assert_true(press(g, "stats"))
    T.assert_eq(g._menu_sub_state, "stats")

    ProfileUI.draw_stats(g)
    T.assert_not_nil(g._stats_back_rect, "the page laid out a Back button")

    local r = g._stats_back_rect
    T.assert_true(ProfileUI.handle_stats_touch(g, r.x + r.w * 0.5, r.y + r.h * 0.5))
    T.assert_eq(g._menu_sub_state, "main")
    T.assert_eq(MainMenuUI.current_page(g), "options", "and lands back on the page it came from")
end)

suite.test("touch activates whatever the page drew at that point", function()
    local g = menu(9010, "main")
    local play = nil
    for _, t in ipairs(MainMenuUI.build_main_menu_focus_targets(g)) do
        if t.kind == "play" then play = t.rect end
    end
    T.assert_not_nil(play)
    T.assert_true(MainMenuUI.handle_touch(g, play.x + play.w * 0.5, play.y + play.h * 0.5))
    T.assert_eq(MainMenuUI.current_page(g), "play")
end)

suite.test("every focus target sits inside the bottom screen", function()
    for _, page in ipairs({ "main", "play", "options" }) do
        local g = menu(9011, page)
        for _, t in ipairs(MainMenuUI.build_main_menu_focus_targets(g)) do
            local r = t.rect
            T.assert_true(r.x >= 0 and r.x + r.w <= 320,
                page .. ":" .. t.kind .. " fits horizontally")
            T.assert_true(r.y >= 0 and r.y + r.h <= 240,
                page .. ":" .. t.kind .. " fits vertically")
        end
    end
end)

suite.test("the title ace is its own sheet, not part of the logo", function()
    local g = bootstrap.new_game(9012)
    T.assert_not_nil(g.ASSET_ATLAS.title_ace, "the ace is registered as its own atlas")
    T.assert_eq(g.ASSET_ATLAS.title_ace.px, 72)
    T.assert_eq(g.ASSET_ATLAS.title_ace.py, 95)

    -- It has to leave with the logo, or the menu's textures outlive the menu.
    g:ensure_asset_atlas_loaded("title_ace")
    g:start_run_from_main_menu()
    T.assert_eq(g.ASSET_ATLAS.title_ace.image, nil, "and is freed when the menu is left")
end)

return suite
