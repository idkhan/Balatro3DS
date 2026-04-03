local raw_print = print
function print(...)
    if G and G.DEBUG then
        raw_print(...)
    end
end

local nest_ok, nest = pcall(function()
    return require("nest").init({ console = "3ds" })
end)

require "engine/object"
require "engine/node"
require "engine/moveable"
require "engine/sprite"
require "card"
require "deck"
require "hand"
require "joker"
require "joker_catalog"
require "consumable"
require "game"
require "globals"
require "consumable_catalog"
require "topUI"
Sfx = require "sfx"

function love.load()
    -- Decode static SFX once; avoids stutter on first play (sources stay in `Sfx` cache).
    if Sfx and Sfx.preload_game_sounds then
        Sfx.preload_game_sounds()
    end

    G = Game()
    G:initialize_run_loop()

    G.music = love.audio.newSource("resources/sounds/music1.ogg", "stream")
    if G.music then
        G.music:setLooping(true)
        G.music:play()
    end
end

function love.update(dt)
    G:update(dt)
end

function love.draw(screen)
    love.graphics.clear(unpack(G.C.BLIND.Big))

    -- Jokers decide their own visibility based on `G.jokers_on_bottom`.
    -- Top screen rendering is handled by `TopUI.draw()` which temporarily
    -- forces visibility for the joker row.
    
    if screen == "bottom" then
        love.graphics.setColor(1, 1, 1)
        G:draw()
    else
        TopUI.draw()
    end
end

function love.keypressed(key)
    if key == "f1" then
        if G then G.DEBUG = not G.DEBUG end
    end
    if not G then return end
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
        G.DEBUG = not G.DEBUG
    end

    if not G then return end
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
        if button == "dpleft" then G:move_blind_select_cursor(-1) end
        if button == "dpright" then G:move_blind_select_cursor(1) end
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
