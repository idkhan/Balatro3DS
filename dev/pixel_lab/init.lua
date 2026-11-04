--- Pixel Lab: native-resolution screenshots of both 3DS screens, from desktop LÖVE.
---
--- nest already renders each screen into a canvas the exact size of the 3DS framebuffer
--- (400x240 top, 320x240 bottom) before scaling it into the window. This takes over the run
--- loop so those canvases can be written out 1:1, and makes the frames reproducible:
---
---  * time is a fixed 1/60 s step (`love.timer.getTime` included), so an animation captured on
---    frame N is the same picture every run;
---  * the save directory is a throwaway identity, wiped at start, so no profile leaks in;
---  * the console profile is an Old 3DS unless `--n3ds` is passed (the game turns effects
---    down on the 2-core machine, and that is what the player is looking at);
---  * text is drawn from glyph sheets rasterised the way `mkbcfnt` rasterises them for the
---    real build (see `hw_fonts.lua`), with the linear sampling LövePotion hardcodes for fonts.
---    Desktop LÖVE's own `.ttf` rendering is sharper than the hardware in places and blurrier in
---    others, which is useless for judging text.
---
--- It also audits every draw call for geometry the 3DS can only draw badly (see `audit.lua`).
---
--- Desktop only. `dev/` is not staged into console builds (`dev/build.sh`), and `main.lua`
--- only reaches this when `--pixel-lab` is on the command line.
---
---   love . --pixel-lab <scenario> [--out <dir>] [--n3ds] [--desktop-fonts] [--no-audit]
local Lab = {}

local DT = 1 / 60

local function parse_args(argv)
    local opts = { n3ds = false, hw_fonts = true, audit = true }
    local i = 1
    while i <= #argv do
        local a = argv[i]
        if a == "--pixel-lab" then
            opts.scenario = argv[i + 1]; i = i + 1
        elseif a == "--out" then
            opts.out = argv[i + 1]; i = i + 1
        elseif a == "--n3ds" then
            opts.n3ds = true
        elseif a == "--desktop-fonts" then
            opts.hw_fonts = false
        elseif a == "--no-audit" then
            opts.audit = false
        end
        i = i + 1
    end
    if not opts.scenario then error("--pixel-lab needs a scenario name", 0) end
    opts.out = opts.out or ("dev/pixel_lab/out/" .. opts.scenario)
    return opts
end

function Lab.requested(argv)
    for _, a in ipairs(argv or {}) do
        if a == "--pixel-lab" then return true end
    end
    return false
end

local function mkdir_p(path)
    -- Windows and POSIX both accept forward slashes here.
    local sep = package.config:sub(1, 1)
    local native = path:gsub("/", sep)
    if sep == "\\" then
        os.execute('if not exist "' .. native .. '" mkdir "' .. native .. '"')
    else
        os.execute("mkdir -p '" .. native .. "'")
    end
end

local function write_file(path, data)
    local f = assert(io.open(path, "wb"))
    f:write(data)
    f:close()
end

--- Remove every file in the save directory, depth first. Only the lab's own identity is ever
--- passed here.
local function wipe_save_dir(dir)
    for _, name in ipairs(love.filesystem.getDirectoryItems(dir)) do
        local p = (dir == "" and name) or (dir .. "/" .. name)
        local info = love.filesystem.getInfo(p)
        if info and info.type == "directory" then
            wipe_save_dir(p)
        end
        love.filesystem.remove(p)
    end
end

--- The deterministic clock every timing read in the game resolves to.
local clock = { t = 0, frame = 0 }

local function install_clock()
    love.timer.getTime = function() return clock.t end
    love.timer.step = function() return DT end
    love.timer.getDelta = function() return DT end
    love.timer.getFPS = function() return 60 end
    love.timer.getAverageDelta = function() return DT end
end

local function install_profile(opts)
    local Console = require "console"
    Console.is_new_3ds = function() return opts.n3ds end
end

function Lab.install(argv)
    local opts = parse_args(argv)
    Lab.opts = opts

    love.filesystem.setIdentity("Balatro3DS_pixel_lab")
    wipe_save_dir("")
    math.randomseed(1)
    if love.math and love.math.setRandomSeed then love.math.setRandomSeed(1) end

    install_clock()
    install_profile(opts)
    if opts.hw_fonts then
        require("dev.pixel_lab.hw_fonts").install()
    end

    local Audit = opts.audit and require("dev.pixel_lab.audit") or nil
    local Scenario = require("dev.pixel_lab.scenario")
    local script = require("dev.pixel_lab.scenarios." .. opts.scenario)

    mkdir_p(opts.out)
    local runner = Scenario.new(script, {
        out = opts.out,
        clock = clock,
        dt = DT,
        audit = Audit,
    })

    local framebuffers = require("nest.modules.video").getFramebuffers()
    local by_name = {}
    for _, fb in ipairs(framebuffers) do by_name[fb:getName()] = fb end

    love.run = function()
        if love.audio then love.audio.setVolume(0) end
        love.window.setVSync(0)
        -- The right eye is the same scene shifted; a still capture of it says nothing new.
        if love.graphics.set3D then love.graphics.set3D(false) end
        if love.load then love.load() end
        if Audit then Audit.install() end

        return function()
            love.event.pump()
            for name, a, b, c, d, e, f in love.event.poll() do
                if name == "quit" then return a or 0 end
                -- Real input is ignored: the scenario is the only player.
                if name ~= "keypressed" and name ~= "keyreleased" and name ~= "mousepressed"
                    and name ~= "mousereleased" and name ~= "touchpressed" and name ~= "touchreleased"
                    and name ~= "mousemoved" and name ~= "touchmoved" and name ~= "gamepadpressed"
                    and name ~= "gamepadreleased" and name ~= "gamepadaxis" and name ~= "joystickpressed"
                    and name ~= "joystickreleased" and name ~= "joystickaxis" then
                    love.handlers[name](a, b, c, d, e, f)
                end
            end

            clock.frame = clock.frame + 1
            clock.t = clock.t + DT

            local done = runner:before_update()
            if done then
                runner:finish()
                return 0
            end

            love.update(DT)

            local want = runner:capture_request()
            if Audit then Audit.begin_frame(want ~= nil, want) end
            for _, fb in ipairs(framebuffers) do
                local name = fb:getName()
                love.graphics.setActiveScreen(name)
                if Audit then Audit.set_screen(name) end
                fb:renderTo(function()
                    love.graphics.clear(love.graphics.getBackgroundColor())
                    if love.draw then love.draw(name) end
                end)
                love.graphics.origin()
                fb:draw()
            end
            if Audit then Audit.end_frame() end

            if want then
                local top = by_name.left:getCanvas():newImageData()
                local bottom = by_name.bottom:getCanvas():newImageData()
                runner:store_capture(want, top, bottom)
            end

            love.graphics.present()
        end
    end
end

return Lab
