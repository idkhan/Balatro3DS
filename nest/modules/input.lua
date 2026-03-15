local path = (...):gsub("%.modules.+", "")
local config = require(path .. ".config")

local input = {}

----
--- Keyboard/Joystick input
----

function input.keypressed(key)
    local binding = config.getKeybinding(key)

    if not binding or binding[2].value == "special" then
        return
    end

    local is_button, pressed = binding[1], binding[2]

    if is_button then
        return love.event.push("gamepadpressed", {}, pressed.value)
    end
    love.event.push("gamepadaxis", {}, pressed.axis, tonumber(pressed.direction .. "1"))
end

function input.keyreleased(key)
    local binding = config.getKeybinding(key)

    if not binding or binding[2].value == "special" then
        return
    end

    local is_button, released = binding[1], binding[2]

    if is_button then
        return love.event.push("gamepadreleased", {}, released.value)
    end
    love.event.push("gamepadaxis", {}, released.axis, 0)
end

local function translate(x, y)
    if config.get("console") == "3ds" then
        if y < 240 then
            return
        end

        if (x < 40 or x > 360) then
            return
        end
        return math.max(0, x - 40), math.max(0, y - 240)
    end
    return x, y
end

local touch_held = false
function input.mousepressed(x, y)
    local _x, _y = translate(x, y)

    if not _x and not _y then
        return
    end

    touch_held = true
    love.event.push("touchpressed", 1, _x, _y, 0, 0, 1)
end

function input.mousemoved(x, y, dx, dy)
    if not touch_held then
        return
    end

    local _x, _y = translate(x, y)

    if not _x and not _y then
        return
    end
    love.event.push("touchmoved", 1, _x, _y, dx, dy, 1)
end

function input.mousereleased(x, y)
    local _x, _y = translate(x, y)

    if not _x and not _y then
        return
    end

    touch_held = false
    love.event.push("touchreleased", 1, _x, _y, 0, 0, 1)
end


----
--- Touch input
----

local love_events = { "keypressed", "keyreleased", "mousepressed", "mousemoved", "mousereleased" }
local registry = {}

-- hook into love events we want
for _, callback in ipairs(love_events) do
    registry[callback] = love[callback] or function () end
    love[callback] = function(...)
        registry[callback](...)
        input[callback](...)
    end
end
