local path = (...):gsub("%.modules.+", "")
local assert = require(path .. ".libraries.assert")
local framebuffer = require(path .. ".classes.framebuffer")
local config = require(path .. ".config")

local data = require(path .. ".data.screens")

local video = {}
video._framebuffers = {}
video._toggleView = false

video._switchViews = { "undocked", "docked" }
video._switchViewIndex = 1

-- Credit: https://shorturl.at/pqCR7
local function find_max(items, f)
    local current_max = -math.huge

    for i = 1, #items do
        local e = items[i]
        local v = f(e, i)
        if v and v > current_max then
            current_max = v
        end
    end
    return current_max
end

---Initializes the video module
---@param console string name of the console
---@param extra table extra data for the framebuffer information
function video.init(console, extra)
    local info = assert:some(data[console], "No screen info was found for the given console")
    local scale = extra.scale

    if console == "3ds" then
        table.insert(video._framebuffers,
            framebuffer("left", { scale = scale, size = info.left }))
        table.insert(video._framebuffers,
            framebuffer("right", { scale = scale, size = info.right }))
        table.insert(video._framebuffers,
            framebuffer("bottom", { scale = scale, size = info.bottom, offset = { 40 * scale, 240 * scale } }))
    elseif console == "switch" then
        local mode = (extra.docked and "docked" or "undocked")
        video._toggleView = extra.docked

        table.insert(video._framebuffers,
            framebuffer("default", { scale = scale, size = info.default[mode], extra = { mode = mode } }))
    elseif console == "wiiu" then
        table.insert(video._framebuffers, framebuffer("tv", { scale = scale, size = info.tv[extra.mode] }))
        table.insert(video._framebuffers, framebuffer("gamepad", { scale = scale, size = info.gamepad }))
    end

    local window_width = find_max(video._framebuffers, framebuffer.getWidth)
    local window_height = find_max(video._framebuffers, framebuffer.getHeight)

    if console == "3ds" then
        window_height = window_height * 2
    end

    love.window.updateMode(window_width * scale, window_height * scale, {})
end

---Gets the framebuffers in the video module
---@return table
function video.getFramebuffers()
    return video._framebuffers
end

----
--- love callback hooks
----

local valid_console_input = {
    ["3ds"]    = false,
    ["switch"] = true,
    ["wiiu"]   = true
}

function video.keypressed(key)
    if not valid_console_input[config.get("console")] then
        return
    end

    local console = config.get("console")
    local binding = config.getKeybinding(key)

    if not binding then
        return
    end

    local is_button, pressed = binding[1], binding[2]

    if is_button and pressed.value == "special" then
        video._toggleView = not video._toggleView

        -- sync the view index with the toggled view boolean
        video._switchViewIndex = video._toggleView and 2 or 1

        -- default framebuffer
        local current_framebuffer = video._framebuffers[1]

        if console == "switch" then
            local mode = video._switchViews[video._switchViewIndex]
            video._framebuffers[1]:refresh(unpack(data[console].default[mode]))
        else
            for index = 1, #video._framebuffers do
                video._framebuffers[index]:toggle()
            end
            current_framebuffer = video._framebuffers[video._switchViewIndex]
        end

        -- set the new width and height of the window
        local width, height = current_framebuffer:getWidth(), current_framebuffer:getHeight()
        love.window.updateMode(width, height, {})
    end
end

function video.wheelmoved(x, y)
    if y > 0 then
        love.graphics._setDepth(0.1)
    elseif y < 0 then
        love.graphics._setDepth(-0.1)
    end
end

local love_events = { "keypressed", "wheelmoved" }
local registry = {}

-- hook into love events we want
for _, callback in ipairs(love_events) do
    registry[callback] = love[callback] or function() end
    love[callback] = function(...)
        registry[callback](...)
        video[callback](...)
    end
end

return video
