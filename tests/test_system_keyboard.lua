--- Seed entry and profile renaming through the 3DS system keyboard.
---
--- These paths only run on console, so the desktop stub never exercised them and a wrong
--- option key went unnoticed. `swkbd_stub` below reimplements the runtime's argument
--- checking exactly: `Wrap_Keyboard::SetTextInput` pushes the whole option table through
--- `luax::CheckTableFields` before it reads a single field, so any key outside
--- {type, password, hint, length} raises "Invalid keyboard setting name" and the keyboard
--- never opens (`source/modules/keyboard/wrap_keyboard.cpp:34`,
--- `include/modules/keyboard/keyboard.tcc:77`). The port wraps the call in pcall, so the
--- error surfaced as a dead button rather than a crash.
local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

bootstrap.load()
local MainMenuUI = require("main_menu_ui")
local ProfileUI = require("profile_ui")

local VALID_OPTIONS = { type = true, password = true, hint = true, length = true }
local VALID_TYPES = { normal = true, qwerty = true, numpad = true }

--- Stand-in for the CTR system keyboard. Records the options it was handed, validates them
--- the way the runtime does, and hands back `reply` (nil means the player cancelled, which
--- on hardware means no textinput event is ever emitted).
local function swkbd_stub(reply)
    local kb = { calls = {}, opened = 0 }

    kb.install = function()
        local love = _G.love
        kb.saved = love.keyboard
        love.keyboard = {
            isDown = function() return false end,
            hasTextInput = function() return false end,
            hasScreenKeyboard = function() return true end,
            setTextInput = function(enable, options)
                if not enable then return end
                if options ~= nil then
                    for key in pairs(options) do
                        if not VALID_OPTIONS[key] then
                            error("Invalid keyboard setting name: " .. tostring(key), 0)
                        end
                    end
                    if options.type ~= nil and not VALID_TYPES[options.type] then
                        error("Invalid keyboard type: " .. tostring(options.type), 0)
                    end
                    if options.hint ~= nil and type(options.hint) ~= "string" then
                        error("bad argument (string expected)", 0)
                    end
                    if options.length ~= nil and type(options.length) ~= "number" then
                        error("bad argument (number expected)", 0)
                    end
                end
                kb.opened = kb.opened + 1
                kb.calls[#kb.calls + 1] = options
                kb.reply = reply
            end,
        }
    end

    kb.restore = function() _G.love.keyboard = kb.saved end

    return kb
end

--- One frame of the console's event ordering: the keyboard blocks inside the button
--- handler, so its text is only pumped on the following frame. `draw` in between is what
--- ages the pending flag.
local function pump(kb, deliver)
    if kb.reply ~= nil then
        deliver(kb.reply)
        kb.reply = nil
    end
end

suite.test("seed entry opens the system keyboard with options the runtime accepts", function()
    local kb = swkbd_stub("A1B2C3D4")
    kb.install()
    local ok, err = pcall(function()
        local g = bootstrap.new_game(9301)

        T.assert_true(MainMenuUI.begin_seed_entry(g), "the seed button opens the keyboard")
        T.assert_eq(kb.opened, 1, "the keyboard was actually shown")
        T.assert_not_nil(kb.calls[1], "options were passed")
        T.assert_eq(kb.calls[1].length, 8, "the length is capped at a seed's width")
        T.assert_nil(kb.calls[1].maxLength, "maxLength is not a key the runtime knows")
        T.assert_true(MainMenuUI.is_editing_seed(g), "and the menu is waiting on it")

        pump(kb, function(text) MainMenuUI.handle_seed_textinput(g, text) end)

        T.assert_eq(g._pending_run_seed, "A1B2C3D4", "the typed seed is applied")
        T.assert_false(MainMenuUI.is_editing_seed(g), "and the menu leaves seed entry")
    end)
    kb.restore()
    if not ok then error(err, 0) end
end)

suite.test("a seed typed loosely is filtered and truncated like inline entry", function()
    local kb = swkbd_stub("  a1b2-c3d4xyz  ")
    kb.install()
    local ok, err = pcall(function()
        local g = bootstrap.new_game(9302)
        MainMenuUI.begin_seed_entry(g)
        pump(kb, function(text) MainMenuUI.handle_seed_textinput(g, text) end)
        T.assert_eq(g._pending_run_seed, "A1B2C3D4", "uppercased, stripped and cut to eight")
    end)
    kb.restore()
    if not ok then error(err, 0) end
end)

suite.test("cancelling the seed keyboard leaves the button usable", function()
    local kb = swkbd_stub(nil)
    kb.install()
    local ok, err = pcall(function()
        local g = bootstrap.new_game(9303)
        g._menu_sub_state = "deck_select"

        MainMenuUI.begin_seed_entry(g)
        T.assert_true(MainMenuUI.is_editing_seed(g))

        -- No textinput ever arrives. Two frames of drawing must release the pending flag.
        MainMenuUI.draw_bottom(g)
        MainMenuUI.draw_bottom(g)
        T.assert_false(MainMenuUI.is_editing_seed(g), "the pending flag expires")

        T.assert_true(MainMenuUI.begin_seed_entry(g), "so the seed button still works")
        T.assert_eq(kb.opened, 2, "and the keyboard opens a second time")
    end)
    kb.restore()
    if not ok then error(err, 0) end
end)

suite.test("a rejected keyboard call does not wedge seed entry", function()
    local kb = swkbd_stub(nil)
    kb.install()
    local ok, err = pcall(function()
        local g = bootstrap.new_game(9304)
        _G.love.keyboard.setTextInput = function() error("Invalid keyboard setting name: nope", 0) end

        T.assert_false(MainMenuUI.begin_seed_entry(g), "the failure is reported")
        T.assert_false(MainMenuUI.is_editing_seed(g), "and nothing is left pending")
    end)
    kb.restore()
    if not ok then error(err, 0) end
end)

suite.test("renaming a profile opens the system keyboard with options the runtime accepts", function()
    local kb = swkbd_stub("Reese")
    kb.install()
    local ok, err = pcall(function()
        local g = bootstrap.new_game(9305)
        g._menu_sub_state = "profile"
        g._profile_selected = 2

        T.assert_true(ProfileUI.begin_rename(g), "rename opens the keyboard")
        T.assert_eq(kb.opened, 1, "the keyboard was actually shown")
        T.assert_eq(kb.calls[1].length, 14, "capped at the profile name limit")
        T.assert_nil(kb.calls[1].maxLength, "maxLength is not a key the runtime knows")
        T.assert_true(ProfileUI.is_renaming(g))

        pump(kb, function(text) ProfileUI.handle_textinput(g, text) end)

        T.assert_eq(g:get_profile_name(2), "Reese", "the typed name is applied")
        T.assert_false(ProfileUI.is_renaming(g))
    end)
    kb.restore()
    if not ok then error(err, 0) end
end)

suite.test("a rejected keyboard call does not wedge profile renaming", function()
    local kb = swkbd_stub(nil)
    kb.install()
    local ok, err = pcall(function()
        local g = bootstrap.new_game(9306)
        g._menu_sub_state = "profile"
        _G.love.keyboard.setTextInput = function() error("Invalid keyboard setting name: nope", 0) end

        T.assert_false(ProfileUI.begin_rename(g), "the failure is reported")
        T.assert_false(ProfileUI.is_renaming(g), "and nothing is left pending")
    end)
    kb.restore()
    if not ok then error(err, 0) end
end)

return suite
