local path = (...):gsub("%.modules.+", "")

local config = require(path .. ".config")
local video = require(path .. ".modules.video")

local nest = require(path)

-- Credit: https://shorturl.at/tyENT
local function foreach(t, f)
    for i = 1, #t do
        local result = f(t[i], i)
        if result ~= nil then
            return result
        end
    end
    return nil
end

-- video should be inited by now
local framebuffers = video.getFramebuffers()

local active_screen = nil
function love.graphics.setActiveScreen(screen)
    active_screen = screen
end

function love.graphics.getActiveScreen()
    return active_screen
end

local originalSetCanvas = love.graphics.setCanvas
function love.graphics.setCanvas(...)
    local length = select("#", ...)

    if length == 1 then
        foreach(framebuffers, function(element, _)
            element:toggleRenderTo()
        end)

        originalSetCanvas(...)
    else
        originalSetCanvas(...)

        foreach(framebuffers, function(element, _)
            element:toggleRenderTo()
        end)
    end
end

function love.graphics.getWidth(screen)
    return foreach(framebuffers, function(element, _)
        if element:getName() == screen then
            return element:getWidth()
        end
    end) or framebuffers[1]:getWidth()
end

function love.graphics.getHeight(screen)
    return foreach(framebuffers, function(element, _)
        if element:getName() == screen then
            return element:getHeight()
        end
    end) or framebuffers[1]:getHeight()
end

function love.graphics.getDimensions(screen)
    local element = foreach(framebuffers, function(element, _)
        if element:getName() == screen then
            return element
        end
    end)

    if element then
        return element:getDimensions()
    end
    return framebuffers[1]:getDimensions()
end

if config.get("console") == "3ds" then
    local depth_enabled = true
    function love.graphics.get3D()
        return depth_enabled
    end

    function love.graphics.set3D(enabled)
        depth_enabled = enabled
    end

    local depth_value = 0.0
    function love.graphics.getDepth()
        if not love.graphics.get3D() then
            return 0.0
        end
        return depth_value
    end

    function love.graphics._setDepth(depth)
        depth_value = math.max(0, math.min(depth_value + depth, 1))
    end
end

local state, percent = "battery", 100
function love.system.getPowerInfo()
    local channel_percent = love.thread.getChannel("battery"):pop()
    if channel_percent then
        percent = channel_percent
    end
    return state, percent
end

function nest.setPowerState(new_state, new_percent)
    state, percent = new_state, new_percent or percent
    love.thread.getChannel("power_state"):push({state, percent})
end

function nest.plug_in(plugged)
    if plugged then
        return nest.setPowerState("charging")
    end
    nest.setPowerState("battery")
end

local thread_code = [[
local state, percent = ...
local max_timer = 15
local timer = max_timer
require("love.timer")

while true do
    timer = math.max(timer - 1, 0)

    local stats = love.thread.getChannel("power_state"):pop()
    if stats then
        state, percent = unpack(stats)
    end

    if timer <= 0 then
        if state == "battery" then
            percent = math.max(percent - 1, 0)
        elseif state == "charging" then
            percent = math.min(percent + 1, 100)
        end
        love.thread.getChannel("battery"):push(percent)
        timer = max_timer
    end
    love.timer.sleep(1)
end
]]

local thread = love.thread.newThread(thread_code)
thread:start(state, percent)
