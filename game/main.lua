local nest_ok, nest = pcall(function()
    return require("nest").init({ console = "3ds" })
end)

require "engine/object"
require "engine/node"
require "engine/moveable"
require "engine/sprite"
require "card"
require "game"
require "globals"

function love.load()
    G = Game()

    -- demo card: 2 of Hearts
    -- rank 2 => first texture in cards_1; Hearts => +0 offset
    local demo_card = G:add(Card(
        120, 50, nil, nil,
        { rank = 2, suit = "Hearts" },
        nil,
        { face_up = true }
    ))
    local demo_card = G:add(Card(
        150, 50, nil, nil,
        { rank = 13, suit = "Clubs" },
        nil,
        { face_up = true }
    ))
    local demo_card = G:add(Card(
        180, 50, nil, nil,
        { rank = 2, suit = "Hearts" },
        nil,
        { face_up = false }
    ))
end

function love.update(dt)
    G:update(dt)
end

function love.draw(screen)
    love.graphics.clear(0.2, 0.2, 0.3)
    
    if screen == "bottom" then
        love.graphics.setColor(1, 1, 1)
        G:draw()
    else
        love.graphics.setColor(1, 1, 1)
        love.graphics.print("Balatro3DS", 10, 10)
    end
end

function love.gamepadpressed(_, button)
    if button == "a" and nest_ok then
        nest.plug_in()
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
