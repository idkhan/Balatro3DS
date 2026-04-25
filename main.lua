local raw_print = print
function print(...)
    if G and G.DEBUG then
        raw_print(...)
    end
end

local nest_ok, nest = pcall(function()
    return require("nest").init({ console = "3ds" })
end)

require "engine.object"
require "engine.node"
require "engine.moveable"
require "engine.sprite"
require "card"
require "deck"
require "hand"
require "joker"
require "joker_catalog"
require "consumable"
require "game"
require "globals"
require "consumable_catalog"
require "voucher_catalog"
require "topUI"
local MainMenuUI = require "main_menu_ui"
Sfx = require "sfx"

function love.load()
    -- Decode static SFX once; avoids stutter on first play (sources stay in `Sfx` cache).
    if Sfx and Sfx.preload_game_sounds then
        Sfx.preload_game_sounds()
    end

    G = Game()
    G:enter_main_menu()

    G.music = love.audio.newSource("resources/sounds/music1_low.ogg", "stream")
    if G.music then
        G.music:setLooping(true)
        G.music:play()
    end
end

function love.update(dt)
    G:update(dt)
end

function love.draw(screen)
    if G and G.STATE == G.STATES.MENU then
        MainMenuUI.draw_background(G, screen)
    else
        love.graphics.clear(unpack(G.C.BLIND.Big))
    end
    if screen == "bottom" then
        love.graphics.setColor(1, 1, 1)
        G:draw()
    else
        if G and G.STATE == G.STATES.MENU then
            MainMenuUI.draw_top(G)
        else
            TopUI.draw()
        end
    end
end

function love.keypressed(key)
    if key == "f1" then
        if G then G.DEBUG = not G.DEBUG end
    end
    if not G then return end
    if key == "escape" then
        if G.toggle_pause then
            G:toggle_pause()
            return
        end
    end
    if G.STATE == G.STATES.MENU then
        if key == "return" or key == "space" or key == "z" then
            if G.has_saved_run and G:has_saved_run() and G.continue_saved_run_from_main_menu then
                G:continue_saved_run_from_main_menu()
            elseif G.start_new_run_from_main_menu then
                G:start_new_run_from_main_menu()
            else
                G:start_run_from_main_menu()
            end
            return
        end
        return
    end
    if G.STATE == G.STATES.PAUSED then
        if key == "return" or key == "space" or key == "z" then
            G:exit_pause_menu()
        end
        return
    end
    if G.set_jokers_location then
        -- Allow joker row screen toggle in every gameplay state.
        if key == "up" then
            G:set_jokers_location(true)
            return
        end
        if key == "down" then
            G:set_jokers_location(false)
            return
        end
    end

    if G.STATE ~= G.STATES.SELECTING_HAND then
        return
    end

    if key == "e" and G.hand then
        G.hand:sort_by_rank()
    end
    if key == "r" and G.hand then
        G.hand:sort_by_suit()
    end
    if (key == "l") and G.hand then
        if G.hand:has_selection() then G.hand:discard_selected() end
    end
    if (key == ";") and G.hand then
        if G.hand:has_selection() then G.hand:play_selected() end
    end
    if key == "x" and G.deck and G.hand and not G.deck:empty() and not G.hand:is_full() then
        local card = G.deck:draw()
        if card then G.hand:add_card(card) end
    end

end

function love.gamepadpressed(_, button)
    if button == "start" and G then
        if G.toggle_pause then
            G:toggle_pause()
            return
        end
    end

    if not G then return end
    if G.STATE == G.STATES.MENU then
        if button == "a" or button == "y" then
            if G.has_saved_run and G:has_saved_run() and G.continue_saved_run_from_main_menu then
                G:continue_saved_run_from_main_menu()
            elseif G.start_new_run_from_main_menu then
                G:start_new_run_from_main_menu()
            else
                G:start_run_from_main_menu()
            end
        end
        return
    end
    if G.STATE == G.STATES.PAUSED then
        if button == "a" or button == "y" then
            G:exit_pause_menu()
        end
        return
    end
    if G.set_jokers_location then
        if button == "up" or button == "dpup" then
            G:set_jokers_location(true)
            return
        end
        if button == "down" or button == "dpdown" then
            G:set_jokers_location(false)
            return
        end
    end
    if G.STATE == G.STATES.BLIND_SELECT then
        if button == "y" or button == "a" then
            G:start_selected_blind()
        end
        return
    end
    if G.STATE == G.STATES.ROUND_EVAL then
        if button == "y" or button == "a" then
            G:continue_from_round_win()
        end
        return
    end
    if G.STATE == G.STATES.SHOP then
        if button == "y" or button == "a" then
            G:continue_from_shop()
        end
        return
    end
    if G.STATE == G.STATES.OPEN_BOOSTER then
        if button == "b" and G.end_booster_session then
            G:end_booster_session()
        end
        return
    end
    if G.STATE ~= G.STATES.SELECTING_HAND then
        return
    end

    if (button == "l" or button == "dpleft") and G.hand then
        G.hand:sort_by_rank()
    end
    if (button == "r" or button == "dpright") and G.hand then
        G.hand:sort_by_suit()
    end
    if (button == "leftshoulder" or button == "x") and G.hand and G.hand:has_selection() then
        G.hand:discard_selected()
    end
    if (button == "rightshoulder" or button == "y") and G.hand and G.hand:has_selection() then
        G.hand:play_selected()
    end
    if (button == "b") and G and G.deck and G.hand and not G.deck:empty() and not G.hand:is_full() then
        local card = G.deck:draw()
        if card then G.hand:add_card(card) end
    end
end

function love.gamepadaxis(_, axis, value)
    print(axis, value)
end

function love.touchpressed(id, x, y, dx, dy, pressure)
    G:touchpressed(id, x, y)
end

function love.touchmoved(id, x, y, dx, dy, pressure)
    G:touchmoved(id, x, y, dx, dy)
end

function love.touchreleased(id, x, y, dx, dy, pressure)
    G:touchreleased(id, x, y)
end
