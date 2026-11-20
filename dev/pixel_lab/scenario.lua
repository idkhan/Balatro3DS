--- Scenario runner: a scenario is a function run as a coroutine, one resume per frame.
---
--- Inside it, `lab` is the only way to touch the game:
---
---   lab.wait(seconds)            let the game run (fixed 1/60 s steps)
---   lab.frames(n)                same, in frames
---   lab.press(button, hold_s)    a gamepad press through `love.gamepadpressed`, as the player does
---   lab.touch(x, y, hold_s)      a bottom-screen tap through `love.touchpressed`
---   lab.capture(name)            write both screens of the next drawn frame
---   lab.burst(name, n, every)    n captures `every` frames apart (animations)
---   lab.G                        the live game, for setup that has no input path (seeding,
---                                granting jokers) -- the same calls the F1 debug keys make
---
--- Captures land in `<out>/<name>.png` (both screens, laid out as on the console: 400x240 top,
--- 320x240 bottom centred under it) plus `<name>_top.png` and `<name>_bottom.png`.
local Scenario = {}
Scenario.__index = Scenario

local TOP_W, TOP_H, BOT_W, BOT_H = 400, 240, 320, 240

function Scenario.new(script, env)
    local self = setmetatable({}, Scenario)
    self.env = env
    self.pending_capture = nil
    self.captures = {}
    self.done = false

    local lab = {}
    self.lab = lab
    local function yield_frames(n)
        for _ = 1, math.max(1, n) do coroutine.yield() end
    end
    function lab.frames(n) yield_frames(n) end
    function lab.wait(seconds) yield_frames(math.floor(seconds / env.dt + 0.5)) end
    function lab.press(button, hold)
        love.gamepadpressed(nil, button)
        yield_frames(math.max(1, math.floor((hold or 0.05) / env.dt + 0.5)))
        love.gamepadreleased(nil, button)
        yield_frames(1)
    end
    function lab.touch(x, y, hold)
        love.touchpressed("lab", x, y, 0, 0, 1)
        yield_frames(math.max(1, math.floor((hold or 0.05) / env.dt + 0.5)))
        love.touchreleased("lab", x, y, 0, 0, 1)
        yield_frames(1)
    end
    function lab.capture(name)
        self.pending_capture = name
        coroutine.yield()
    end
    function lab.burst(name, n, every)
        for i = 1, n do
            lab.capture(string.format("%s_f%02d", name, i))
            if i < n then yield_frames((every or 1) - 1) end
        end
    end
    function lab.log(fmt, ...)
        io.write("[pixel-lab] ", string.format(fmt, ...), "\n")
        io.flush()
    end
    --- Tutorial strip and discovery toasts off, so a capture shows the screen and not the
    --- first-run overlays on top of it. Scenarios about those overlays leave this out.
    function lab.quiet()
        if G and G.skip_tutorial then G:skip_tutorial() end
        local Milestones = require "milestone_queue"
        Milestones.push = function() end
        if G then G._milestone_active = nil end
    end
    setmetatable(lab, { __index = function(_, k) if k == "G" then return G end end })

    self.co = coroutine.create(function() script(lab) end)
    return self
end

--- Advance the script one frame. Returns true once it has finished.
function Scenario:before_update()
    if self.done then return true end
    -- A capture requested last frame has been taken by now.
    self.pending_capture = nil
    local ok, err = coroutine.resume(self.co, self.lab)
    if not ok then
        error("scenario failed: " .. tostring(err) .. "\n" .. debug.traceback(self.co), 0)
    end
    if coroutine.status(self.co) == "dead" and not self.pending_capture then
        self.done = true
        return true
    end
    return false
end

function Scenario:capture_request()
    return self.pending_capture
end

local function write(path, filedata)
    local f = assert(io.open(path, "wb"))
    f:write(filedata:getString())
    f:close()
end

function Scenario:store_capture(name, top, bottom)
    local out = self.env.out
    write(out .. "/" .. name .. "_top.png", top:encode("png"))
    write(out .. "/" .. name .. "_bottom.png", bottom:encode("png"))
    local both = love.image.newImageData(TOP_W, TOP_H + BOT_H)
    both:mapPixel(function() return 0, 0, 0, 1 end)
    both:paste(top, 0, 0, 0, 0, TOP_W, TOP_H)
    both:paste(bottom, (TOP_W - BOT_W) / 2, TOP_H, 0, 0, BOT_W, BOT_H)
    write(out .. "/" .. name .. ".png", both:encode("png"))
    self.captures[#self.captures + 1] = name
    if self.env.audit then self.env.audit.note_capture(name) end
end

function Scenario:finish()
    local out = self.env.out
    if self.env.audit then
        self.env.audit.write_report(out .. "/audit.txt", out .. "/audit.json")
    end
    local f = assert(io.open(out .. "/captures.txt", "w"))
    for _, n in ipairs(self.captures) do f:write(n, "\n") end
    f:close()
    io.write(string.format("[pixel-lab] %d captures written to %s\n", #self.captures, out))
end

return Scenario
