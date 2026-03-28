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
require "game"
require "globals"
require "topUI"
Sfx = require "sfx"

function love.load()
    -- Decode static SFX once; avoids stutter on first play (sources stay in `Sfx` cache).
    if Sfx and Sfx.preload_game_sounds then
        Sfx.preload_game_sounds()
    end

    G = Game()

    G.deck = Deck()
    G.deck:shuffle()

    G.hand = Hand(G)
    G.hand:fill_from_deck()

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
    if key == "e" and G and G.hand then
        G.hand:sort_by_rank()
    end
    if key == "r" and G and G.hand then
        G.hand:sort_by_suit()
    end
    if (key == "l") and G and G.hand then
        if G.hand:has_selection() then G.hand:discard_selected() end
    end
    if (key == ";") and G and G.hand then
        if G.hand:has_selection() then G.hand:play_selected() end
    end
    if key == "x" and G and G.deck and G.hand and not G.deck:empty() and not G.hand:is_full() then
        local card = G.deck:draw()
        if card then G.hand:add_card(card) end
    end

    if G and G.set_jokers_location then
        if key == "up" then
            G:set_jokers_location(true)
            return
        end
        if key == "down" then
            G:set_jokers_location(false)
            return
        end
    end
end

function love.gamepadpressed(_, button)
    if button == "start" and G then
        G.DEBUG = not G.DEBUG
    end

    -- Bring jokers down to bottom screen for touch interaction.
    if G and G.set_jokers_location then
        if button == "dpup" or button == "up" then
            G:set_jokers_location(true)
            return
        end
        if button == "dpdown" or button == "down" then
            G:set_jokers_location(false)
            return
        end
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
