--- Headless `love` stub.
---
--- There is no LOVE/LovePotion binary in CI or on a dev machine, but the game modules
--- reach for `love.*` at require time (atlas loads, font construction). This provides
--- just enough surface to let them load and run logic, with no window and no audio.
---
--- The rule for this file: every entry point here exists because something in the repo
--- calls it. Grep before adding. Drawing calls are deliberately inert -- if a test needs
--- to observe drawing it should assert on game state, not on pixels.
---
--- Two parts are *recording* rather than inert, because tests assert on them:
---   - Sources record setPitch/setVolume/play/stop so sfx behaviour is observable.
---   - love.filesystem is a real in-memory filesystem so save/load round-trips work.

local stub = {}

--------------------------------------------------------------------------------
-- Inert drawable objects
--------------------------------------------------------------------------------

--- Fonts report plausible non-zero metrics. Layout code divides by getWidth in places,
--- so returning 0 would produce NaN rather than a clean failure.
local function new_font(size)
    local h = tonumber(size) or 12
    return {
        _stub = "Font",
        getHeight = function() return h end,
        getWidth = function(_, text) return #tostring(text or "") * math.floor(h * 0.5) end,
        --- Greedy word wrap over the same fake advance `getWidth` reports, so layout code
        --- that measures a wrapped block gets a plausible line count instead of nil.
        getWrap = function(self, text, limit)
            local cw = math.max(1, math.floor(h * 0.5))
            local per_line = math.max(1, math.floor((tonumber(limit) or 0) / cw))
            local lines, line = {}, nil
            for word in tostring(text or ""):gmatch("%S+") do
                if not line then
                    line = word
                elseif #line + 1 + #word <= per_line then
                    line = line .. " " .. word
                else
                    lines[#lines + 1] = line
                    line = word
                end
            end
            if line then lines[#lines + 1] = line end
            local widest = 0
            for _, l in ipairs(lines) do widest = math.max(widest, #l * cw) end
            return widest, lines
        end,
        getBaseline = function() return h end,
        getAscent = function() return math.floor(h * 0.8) end,
        getDescent = function() return -math.floor(h * 0.2) end,
        setFilter = function() end,
        getFilter = function() return "nearest", "nearest", 1 end,
        setLineHeight = function() end,
        getLineHeight = function() return 1 end,
        release = function() return true end,
        type = function() return "Font" end,
        typeOf = function(_, t) return t == "Font" or t == "Object" end,
    }
end

local function new_quad(x, y, w, h, sw, sh)
    return {
        _stub = "Quad",
        _x = x, _y = y, _w = w, _h = h, _sw = sw, _sh = sh,
        getViewport = function() return x, y, w, h end,
        setViewport = function(_, nx, ny, nw, nh) x, y, w, h = nx, ny, nw, nh end,
        getTextureDimensions = function() return sw, sh end,
        release = function() return true end,
        type = function() return "Quad" end,
        typeOf = function(_, t) return t == "Quad" or t == "Object" end,
    }
end

--- Images claim a fixed size. Nothing in the repo depends on the real atlas dimensions
--- for logic -- only for draw positioning, which is inert here.
--- Every image the game has asked the runtime to build, in order.
---
--- `newImage` is a blocking SD read plus a texture build on console (~24 ms for a small
--- sprite), so *when* one happens is a behavioural fact worth asserting on, not just an
--- implementation detail: code that spreads loads across frames is only doing its job if the
--- frame it was protecting performs none.
local images = {}

local function new_image(path)
    local w, h = 512, 512
    images[#images + 1] = path
    return {
        _stub = "Image",
        _path = path,
        getWidth = function() return w end,
        getHeight = function() return h end,
        getDimensions = function() return w, h end,
        setFilter = function() end,
        getFilter = function() return "nearest", "nearest", 1 end,
        setWrap = function() end,
        release = function() return true end,
        type = function() return "Image" end,
        typeOf = function(_, t) return t == "Image" or t == "Texture" or t == "Object" end,
    }
end

--------------------------------------------------------------------------------
-- Audio: recording fake Sources
--------------------------------------------------------------------------------

--- Every Source the stub hands out, in creation order. Tests inspect this to assert
--- what actually played.
local sources = {}

--- Monotonic counter stamped onto a Source each time it plays, so a test can identify
--- the most recent playback rather than guessing from play counts.
local play_seq = 0

--- Whether a game asset exists on disk. Real love.audio.newSource raises on a missing
--- file, and sfx.lua's "unknown cue" handling depends on that failure, so the stub has
--- to reproduce it rather than accept every path.
---@param path string
---@return boolean
local function asset_exists(path)
    local root = os.getenv("BALATRO_ROOT") or "."
    local fh = io.open(root .. "/" .. tostring(path), "r")
    if fh then
        fh:close()
        return true
    end
    -- Also try the path as given, in case it is already absolute.
    fh = io.open(tostring(path), "r")
    if fh then
        fh:close()
        return true
    end
    return false
end

--- Fake Source. `playing` is a plain flag rather than a timer: nothing here advances
--- real time, so a Source stays "playing" until explicitly stopped. Tests that care
--- about voice stealing set it themselves.
local function new_source(arg, kind)
    local src = {
        _stub = "Source",
        _arg = arg,
        _kind = kind,
        _pitch = 1,
        _volume = 1,
        _playing = false,
        _play_count = 0,
        _stop_count = 0,
        _play_seq = 0,
        _pitch_history = {},
        _volume_history = {},
        _position = 0,
        _seek_history = {},
    }
    function src:setPitch(p)
        self._pitch = p
        self._pitch_history[#self._pitch_history + 1] = p
    end
    function src:getPitch() return self._pitch end
    function src:setVolume(v)
        self._volume = v
        self._volume_history[#self._volume_history + 1] = v
    end
    function src:getVolume() return self._volume end
    function src:play()
        self._playing = true
        self._play_count = self._play_count + 1
        play_seq = play_seq + 1
        self._play_seq = play_seq
        return true
    end
    function src:stop()
        self._playing = false
        self._stop_count = self._stop_count + 1
    end
    function src:pause() self._playing = false end
    function src:isPlaying() return self._playing end
    function src:setLooping() end
    function src:isLooping() return false end
    function src:seek(position, unit)
        self._position = position
        self._seek_history[#self._seek_history + 1] = { position = position, unit = unit }
    end
    function src:tell() return self._position end
    function src:getDuration() return 173.62 end
    function src:release() return true end
    function src:clone()
        local c = new_source(self._arg, self._kind)
        c._cloned_from = self
        return c
    end
    function src:type() return "Source" end
    function src:typeOf(t) return t == "Source" or t == "Object" end

    sources[#sources + 1] = src
    return src
end

--------------------------------------------------------------------------------
-- Filesystem: real in-memory store
--------------------------------------------------------------------------------

--- path -> string contents. Directories are tracked separately since getInfo
--- distinguishes "file" from "directory".
local files = {}
local dirs = { [""] = true }

local function normalize(path)
    return (tostring(path):gsub("^%./", ""):gsub("//+", "/"))
end

--------------------------------------------------------------------------------
-- Assembly
--------------------------------------------------------------------------------

--- Install the stub as the global `love`. Idempotent-ish: calling again resets
--- recorded state.
---@return table love the installed stub table
function stub.install()
    local time = 0

    --- Screen passes recorded by the graphics stub. loading.lua draws outside
    --- love.draw and presents by hand, so "which screens, how many frames" is
    --- behaviour rather than pixels; test_loading.lua asserts on it.
    local frames = { presents = 0, screens = {} }

    local graphics
    graphics = {
        -- every mesh ever constructed, in order (see newMesh)
        _meshes = {},
        -- state setters: inert
        setColor = function() end,
        getColor = function() return 1, 1, 1, 1 end,
        setBackgroundColor = function() end,
        clear = function() end,
        present = function() frames.presents = frames.presents + 1 end,
        origin = function() end,
        push = function() end,
        pop = function() end,
        translate = function() end,
        rotate = function() end,
        scale = function() end,
        shear = function() end,
        setScissor = function() end,
        getScissor = function() return nil end,
        setBlendMode = function() end,
        setDefaultFilter = function() end,
        getDefaultFilter = function() return "nearest", "nearest", 1 end,
        setLineStyle = function() end,
        setLineWidth = function() end,
        getLineWidth = function() return 1 end,
        -- Desktop LÖVE has both; LövePotion has neither. `console.lua` keys "am I on real
        -- hardware?" off newShader's absence, so the stub has to model the desktop side.
        newShader = function() return {} end,
        setShader = function() end,
        getStats = function()
            return {
                drawcalls = 0,
                drawcallsbatched = 0,
                cputime = 0,
                gputime = 0,
                texturememory = 0,
            }
        end,
        -- draw calls: inert, except that drawing a mesh records a snapshot in
        -- `_meshes`. fx.lua now rewrites one cached mesh per vertex count instead of
        -- constructing one per pass, so recording at newMesh time would see one mesh
        -- where the tests need one entry per pass; snapshotting at draw time keeps
        -- the old one-entry-per-pass semantics, with the texture and vertex values
        -- the pass actually drew.
        draw = function(drawable)
            if type(drawable) == "table" and drawable._vertices and drawable.typeOf
                and drawable:typeOf("Mesh") then
                local snap = {
                    _mode = drawable._mode,
                    _usage = drawable._usage,
                    _texture = drawable._texture,
                    _vertices = {},
                }
                for i, vert in ipairs(drawable._vertices) do
                    local c = {}
                    for j = 1, #vert do c[j] = vert[j] end
                    snap._vertices[i] = c
                end
                graphics._meshes[#graphics._meshes + 1] = snap
            end
        end,
        print = function() end,
        printf = function() end,
        rectangle = function() end,
        circle = function() end,
        ellipse = function() end,
        line = function() end,
        polygon = function() end,
        points = function() end,
        -- constructors
        newImage = function(path) return new_image(path) end,
        newCanvas = function() return new_image("canvas") end,
        setCanvas = function() end,
        newQuad = function(x, y, w, h, sw, sh) return new_quad(x, y, w, h, sw, sh) end,
        newFont = function(a, b)
            -- newFont(size) or newFont(path, size)
            if type(a) == "number" then return new_font(a) end
            return new_font(b)
        end,
        newSpriteBatch = function(texture, size)
            local batch = { _texture = texture, _size = size, _items = {} }
            function batch:add(...)
                self._items[#self._items + 1] = { ... }
                return #self._items
            end
            function batch:clear() self._items = {} end
            function batch:getCount() return #self._items end
            function batch:release() return true end
            function batch:type() return "SpriteBatch" end
            function batch:typeOf(t) return t == "SpriteBatch" or t == "Drawable" or t == "Object" end
            return batch
        end,
        -- Meshes record their construction so fx tests can assert on vertex data.
        -- Vertices are deep-copied: the game pools and rewrites its vertex tables.
        newMesh = function(vertices, mode, usage)
            local copied = {}
            for i, vert in ipairs(vertices) do
                local c = {}
                for j = 1, #vert do c[j] = vert[j] end
                copied[i] = c
            end
            local mesh = {
                _vertices = copied,
                _mode = mode,
                _usage = usage,
                _texture = nil,
            }
            function mesh:setTexture(tex) self._texture = tex end
            -- Mirrors the Balatro3DS runtime binding (dev/patch_lovepotion.py):
            -- rewrites the buffer in place, capped by the construction-time count.
            function mesh:setVertices(verts, start)
                start = (start or 1) - 1
                assert(start >= 0 and start + #verts <= #self._vertices,
                    "setVertices: too many vertices")
                for i, vert in ipairs(verts) do
                    local c = self._vertices[start + i]
                    for j = 1, 8 do c[j] = vert[j] end
                end
            end
            function mesh:getTexture() return self._texture end
            function mesh:release() return true end
            function mesh:type() return "Mesh" end
            function mesh:typeOf(t) return t == "Mesh" or t == "Object" end
            return mesh
        end,
        -- 3DS top screen is 400x240; the game targets the 320x240 bottom screen. As on
        -- LovePotion, the dimension getters take an optional screen name and default to
        -- the top screen (`source/modules/graphics/wrap_graphics.cpp:300`).
        getWidth = function(screen) return screen == "bottom" and 320 or 400 end,
        getHeight = function() return 240 end,
        getDimensions = function(screen) return screen == "bottom" and 320 or 400, 240 end,
        -- Two-screen console API. loading.lua branches on getScreens being present.
        getScreens = function() return { "top", "bottom" } end,
        setActiveScreen = function(screen) frames.screens[#frames.screens + 1] = screen end,
        isActive = function() return true end,
        -- Stereoscopic depth on the 3DS. 0 = flat, which is what a headless run is.
        getDepth = function() return 0 end,
        setDepth = function() end,
    }

    local default_font = new_font(12)
    graphics.getFont = function() return default_font end
    graphics.setFont = function(f) default_font = f or default_font end

    local love = {
        _stub = true,
        -- LovePotion sets this on console targets; main.lua branches on it.
        _console = "3DS",
        _version = "11.4",

        graphics = graphics,

        audio = {
            --- Raises on a missing file, as the real API does. sfx.lua pcalls this and
            --- marks the cue missing, so a stub that always succeeded would make every
            --- typo'd cue look playable.
            newSource = function(arg, kind)
                if type(arg) == "string" and not asset_exists(arg) then
                    error("could not open file " .. arg, 2)
                end
                return new_source(arg, kind)
            end,
            stop = function() end,
            setVolume = function() end,
            getVolume = function() return 1 end,
        },

        sound = {
            --- Returns an inert SoundData. sfx.lua only ever passes it back to
            --- newSource or calls :release() on it.
            newSoundData = function(path)
                if type(path) == "string" and not asset_exists(path) then
                    error("could not open file " .. tostring(path), 2)
                end
                return {
                    _stub = "SoundData",
                    _path = path,
                    release = function() return true end,
                    getDuration = function() return 1 end,
                    type = function() return "SoundData" end,
                    typeOf = function(_, t) return t == "SoundData" or t == "Data" end,
                }
            end,
        },

        timer = {
            getTime = function() return time end,
            getDelta = function() return 1 / 60 end,
            getFPS = function() return 60 end,
            step = function() end,
            sleep = function() end,
        },

        math = {
            --- Deliberately delegates to `math.random` so a test that stubs
            --- `math.random` also controls `love.math.random`. sfx.lua picks its
            --- random cue through here.
            random = function(a, b)
                if a == nil then return math.random() end
                if b == nil then return math.random(a) end
                return math.random(a, b)
            end,
            setRandomSeed = function(s) math.randomseed(s) end,
            newRandomGenerator = function() return { random = math.random } end,
            random_state = nil,
        },

        filesystem = {
            write = function(path, data)
                path = normalize(path)
                files[path] = tostring(data)
                return true
            end,
            read = function(path)
                path = normalize(path)
                local c = files[path]
                if not c then return nil, "file not found" end
                return c, #c
            end,
            --- Mirrors love.filesystem.load: compiles the file and returns the chunk,
            --- or nil plus a message. The game calls the chunk to get its save table.
            load = function(path)
                path = normalize(path)
                local c = files[path]
                if not c then return nil, "file not found: " .. path end
                local loader = loadstring or load
                return loader(c, "@" .. path)
            end,
            getInfo = function(path, filter)
                path = normalize(path)
                local info
                if files[path] then
                    info = { type = "file", size = #files[path], modtime = 0 }
                elseif dirs[path] then
                    info = { type = "directory", size = 0, modtime = 0 }
                else
                    local prefix = path .. "/"
                    for p in pairs(files) do
                        if p:sub(1, #prefix) == prefix then
                            info = { type = "directory", size = 0, modtime = 0 }
                            break
                        end
                    end
                end
                if not info then return nil end
                if filter and info.type ~= filter then return nil end
                return info
            end,
            createDirectory = function(path)
                dirs[normalize(path)] = true
                return true
            end,
            --- A File handle with PhysFS semantics: "w" truncates, "a" keeps the contents and
            --- starts at the end, and a seek is honoured either way, so writing after
            --- `seek(0)` on an append handle overwrites in place. Contents land on `close`.
            openFile = function(path, mode)
                path = normalize(path)
                local buf = (mode == "a" and files[path]) or ""
                if mode == "r" and not files[path] then return nil, "file not found" end
                local pos = (mode == "a") and #buf or 0
                local open = true
                local handle = {}
                function handle:seek(p)
                    p = tonumber(p) or 0
                    if not open or p < 0 or p > #buf then return false end
                    pos = p
                    return true
                end
                function handle:write(data)
                    if not open or mode == "r" then return false, "not writable" end
                    data = tostring(data)
                    buf = buf:sub(1, pos) .. data .. buf:sub(pos + #data + 1)
                    pos = pos + #data
                    return true
                end
                function handle:read()
                    return buf:sub(pos + 1)
                end
                function handle:close()
                    if open and mode ~= "r" then files[path] = buf end
                    open = false
                    return true
                end
                if mode ~= "r" then files[path] = buf end
                return handle
            end,
            remove = function(path)
                path = normalize(path)
                if files[path] then
                    files[path] = nil
                    return true
                end
                if dirs[path] then
                    dirs[path] = nil
                    return true
                end
                return false
            end,
            getDirectoryItems = function(path)
                path = normalize(path)
                local prefix = path == "" and "" or (path .. "/")
                -- Files and subdirectories alike, as the real call lists them. A directory is
                -- known either from `createDirectory` or from a file written somewhere under it.
                local seen, out = {}, {}
                local function add(p)
                    if p:sub(1, #prefix) ~= prefix then return end
                    local name = p:sub(#prefix + 1):match("^[^/]+")
                    if name and not seen[name] then
                        seen[name] = true
                        out[#out + 1] = name
                    end
                end
                for p in pairs(files) do add(p) end
                for p in pairs(dirs) do add(p) end
                table.sort(out)
                return out
            end,
            getSaveDirectory = function() return "sdmc" end,
            setIdentity = function() end,
        },

        system = {
            getOS = function() return "Horizon" end,
            -- Old 3DS is single core from the game's point of view.
            getProcessorCount = function() return 1 end,
            getPowerInfo = function() return "battery", 100, nil end,
        },

        keyboard = {
            isDown = function() return false end,
            setTextInput = function() end,
            hasTextInput = function() return false end,
            hasScreenKeyboard = function() return false end,
        },

        mouse = {
            isDown = function() return false end,
            getPosition = function() return 0, 0 end,
            setVisible = function() end,
        },

        joystick = {
            getJoysticks = function() return {} end,
            getJoystickCount = function() return 0 end,
        },

        window = {
            setMode = function() return true end,
            setTitle = function() end,
            getDimensions = function() return 400, 240 end,
        },

        event = {
            quit = function() end,
            push = function() end,
        },

        touch = {
            getTouches = function() return {} end,
        },
    }

    --- Test-only handles, namespaced so they cannot collide with the real API.
    love._test = {
        sources = sources,
        files = files,
        dirs = dirs,
        frames = frames,
        meshes = graphics._meshes,
        images = images,
        --- Advance the fake clock; love.timer.getTime reflects it.
        advance = function(dt) time = time + (dt or 0) end,
        set_time = function(t) time = t end,
        --- Empty the in-memory filesystem. Separate from `reset` because sfx pools
        --- outlive any one test file: a voice built by an earlier file is still live
        --- and still playable, but dropping it from `sources` makes it invisible to
        --- `last_played`, so a filesystem test must not take the source log with it.
        reset_files = function()
            for k in pairs(files) do files[k] = nil end
            for k in pairs(dirs) do dirs[k] = nil end
            dirs[""] = true
        end,
        --- Drop every recorded Source and every in-memory file.
        reset = function()
            for i = #sources, 1, -1 do sources[i] = nil end
            for k in pairs(files) do files[k] = nil end
            for k in pairs(dirs) do dirs[k] = nil end
            dirs[""] = true
            frames.presents = 0
            for i = #frames.screens, 1, -1 do frames.screens[i] = nil end
            time = 0
        end,
        --- The Source most recently :play()ed, or nil if nothing has played.
        last_played = function()
            local best = nil
            for _, s in ipairs(sources) do
                if s._play_seq > 0 and (best == nil or s._play_seq > best._play_seq) then
                    best = s
                end
            end
            return best
        end,
        new_font = new_font,
    }

    _G.love = love
    return love
end

return stub
