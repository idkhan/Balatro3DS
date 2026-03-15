local path = (...):gsub('%.init$', '')

local nest =
{
    _VERSION     = "0.4.0",
    _DESCRIPTION = "LÖVE Potion Compatabiility Layer library",
    _LICENSE     = [[
       MIT LICENSE
       Copyright (c) 2020-2023 TurtleP
       Permission is hereby granted, free of charge, to any person obtaining a
       copy of this software and associated documentation files (the
       "Software"), to deal in the Software without restriction, including
       without limitation the rights to use, copy, modify, merge, publish,
       distribute, sublicense, and/or sell copies of the Software, and to
       permit persons to whom the Software is furnished to do so, subject to
       the following conditions:
       The above copyright notice and this permission notice shall be included
       in all copies or substantial portions of the Software.
       THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
       OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
       MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
       IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
       CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
       TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
       SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
   ]],

    init = function()
    end,

    setPowerState = function()
    end
}


if love._console then
    return nest
end

-- config flags
local config = require(path .. ".config")
local title = "Nintendo %s (nëst %s)"

nest._require = function(name, ...)
    name = string.format("%s.%s", path, name)
    local chunk = require(name)

    if type(chunk) ~= "function" then
        return chunk
    end

    local args = { ... }
    return chunk(unpack(args))
end

function nest.init(args)
    local success = config.set(args or {})

    if not success then
        return
    end

    config.parseBindingInfo()
    love._console = config.getName()

    if config.get("emulateJoystick") then
        nest._require("modules.input")
    end

    local video = nest._require("modules.video")

    local options = { scale = config.get("scale"), docked = config.get("docked"), mode = config.get("mode") }
    video.init(config.get("console"), options)

    nest._require("modules.overrides")
    nest._require("modules.filesystem")

    love.run = nest._require("runner", video.getFramebuffers())

    local window_title = title:format(love._console, nest._VERSION)
    love.window.setTitle(window_title)

    return nest
end

return nest
