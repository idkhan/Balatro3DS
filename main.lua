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
require "game"
require "globals"
require "topUI"
Sfx = require "sfx"

function love.load()
    G = Game()

    G.deck = Deck()
    G.deck:shuffle()

    G.hand = Hand(G)
    G.hand:fill_from_deck()

    G.music = love.audio.newSource("resources/sounds/music1.ogg", "static")
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
    
    if screen == "bottom" then
        love.graphics.setColor(1, 1, 1)
        G:draw()
    else
        TopUI.draw()
    end
end

function love.keypressed(key)
    if key == "f1" or key == "d" then
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
end

function love.gamepadpressed(_, button)
    if button == "a" and nest_ok then
        nest.plug_in()
    end
    if button == "start" and G then
        G.DEBUG = not G.DEBUG
    end
    if (button == "l" or button == "dpleft") and G.hand then
        G.hand:sort_by_rank()
    end
    if (button == "r" or button == "dpright") and G.hand then
        G.hand:sort_by_suit()
    end
    if (button == "leftshoulder") and G.hand and G.hand:has_selection() then
        G.hand:discard_selected()
    end
    if (button == "rightshoulder") and G.hand and G.hand:has_selection() then
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
