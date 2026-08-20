--- Menu entrance slide: every menu screen eases up from below the way the reference's
--- overlay UIBoxes do (`reference/Balatro/functions/button_callbacks.lua:1328-1356`).
local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")
local suite = T.suite("menu slide")

local MainMenuUI

local function menu_game()
    local g = bootstrap.new_game()
    MainMenuUI = MainMenuUI or require("main_menu_ui")
    g.STATE = g.STATES.MENU
    g._menu_sub_state = "main"
    g._menu_page = "main"
    -- The first menu frame of a session is covered by the boot wipe and does not slide;
    -- settle that frame so the tests below exercise a page change.
    MainMenuUI.update(g, 0.016)
    return g
end

suite.test("the first menu frame settles without a slide", function()
    local g = menu_game()
    T.assert_false(MainMenuUI.slide_active(g))
    T.assert_eq(MainMenuUI.slide_dy(g), 0)
end)

suite.test("a page turn starts a slide that lands within its duration", function()
    local g = menu_game()
    MainMenuUI.open_page(g, "play")
    MainMenuUI.update(g, 0.016)
    T.assert_true(MainMenuUI.slide_active(g))
    T.assert_true(MainMenuUI.slide_dy(g) > 0, "the panel starts below its resting place")

    for _ = 1, 30 do MainMenuUI.update(g, 0.016) end
    T.assert_false(MainMenuUI.slide_active(g))
    T.assert_eq(MainMenuUI.slide_dy(g), 0)
end)

suite.test("opening a full screen slides too", function()
    local g = menu_game()
    MainMenuUI.open_deck_select(g)
    MainMenuUI.update(g, 0.016)
    T.assert_true(MainMenuUI.slide_active(g))
end)

suite.test("a dt longer than the slide still animates rather than snapping", function()
    local g = menu_game()
    MainMenuUI.open_page(g, "options")
    MainMenuUI.update(g, 1.0)
    T.assert_true(MainMenuUI.slide_active(g), "a hitched frame must not finish the slide")
end)

suite.test("touches are swallowed while the panel is moving", function()
    local g = menu_game()
    MainMenuUI.open_page(g, "play")
    MainMenuUI.update(g, 0.016)
    T.assert_true(MainMenuUI.handle_touch(g, 160, 120))
    T.assert_eq(MainMenuUI.current_page(g), "play", "no button may fire mid-slide")
end)

suite.test("the offset is ignored outside the menu state", function()
    local g = menu_game()
    MainMenuUI.open_page(g, "play")
    MainMenuUI.update(g, 0.016)
    g.STATE = g.STATES.PAUSED
    T.assert_eq(MainMenuUI.slide_dy(g), 0)
end)

return suite
