--- Cached text rendering, for strings that do not change between frames.
---
--- `love.graphics.print` and `printf` re-shape their string in C++ on every call --
--- `Font::GenerateVertices` walks the codepoints, looks up each glyph, applies kerning and
--- builds six vertices per character (`font.cpp:451`, `:368`), throws the result away, and
--- does it again next frame. On hardware that is 53.49 us for a five-glyph `print` and
--- 250.99 us for a wrapped `printf`, against 16.11 us to draw a `TextBatch` that was shaped
--- once. Both issue exactly one draw command, so the whole difference is the reshaping.
---
--- The top screen is mostly labels that never change -- "Score", "Round", blind names, stat
--- captions -- and it issues around 33 text calls a frame, so this is the largest saving
--- available in the frame that does not need a runtime change.
---
--- Two facts about the backend shape the design, and both are the opposite of what the API
--- suggests:
---
---  * **A TextBatch bakes its colour when the text is set, and ignores `setColor` when it is
---    drawn.** `TextBatch::Draw` fills its draw command from its own vertex buffer
---    (`textbatch.cpp:233`) where every other primitive fills from the current colour, and a
---    plain string is baked white (`wrap_font.cpp:8`). Desktop LOVE *does* multiply by the
---    current colour at draw time. So the colour is baked into the coloured-string form on
---    both paths and the draw is issued at white -- the only arrangement where hardware and
---    desktop render the same thing. Colour is therefore part of what a cached entry has to
---    match, not something applied afterwards.
---  * **The name differs by runtime.** LovePotion has `newTextBatch`; desktop LOVE 11 calls
---    the same object `newText`. Either is used if present, and if neither is the module
---    degrades to plain `print`/`printf` -- which is also what happens under the headless
---    test stub, so nothing here can break the suite by being absent.
---
--- Only pass text that is stable across frames. A string that changes every frame re-shapes
--- on every frame anyway, so it gains nothing and costs a table lookup; score counters and
--- chip totals should keep calling `printf` directly.

local TextCache = {}

--- Entries per font before the whole font's cache is dropped. Static text does not come
--- close to this; blowing past it means dynamic text is being cached, and starting over is
--- both cheap and self-correcting.
TextCache.MAX_ENTRIES = 96

-- Keyed by the Font object itself, so a face swapped out by `Fonts.apply` simply misses and
-- its entries fall off with it. Weak keys let the dead font's batches be collected; a
-- TextBatch owns native memory, so they must not be pinned by a cache nobody reads.
local cache = setmetatable({}, { __mode = "k" })
local counts = setmetatable({}, { __mode = "k" })

--- nil until first use: the constructor under whichever name this runtime has, or false.
local factory = nil

local function text_factory()
    if factory == nil then
        local g = love.graphics
        factory = (g and (g.newTextBatch or g.newText)) or false
    end
    return factory
end

--- Whether this runtime can cache at all. False means every call falls through to `printf`.
--- @return boolean
function TextCache.is_supported()
    return text_factory() ~= false
end

--- Drop everything. Only the tests need this; a font swap is handled by the weak keys.
function TextCache.reset()
    cache = setmetatable({}, { __mode = "k" })
    counts = setmetatable({}, { __mode = "k" })
    factory = nil
end

--- Entries currently held for `font`, for the tests to assert the cache is actually reused
--- rather than rebuilt every frame -- which would be slower than not caching at all.
--- @return integer
function TextCache.count(font)
    return counts[font] or 0
end

--- Fetch or build the batch for this exact (font, text, limit, align, colour). Returns nil
--- when the runtime cannot make one, which is the caller's signal to fall back.
local function acquire(font, text, limit, align, r, g, b, a)
    local make = text_factory()
    if not make or not font then return nil end

    local entries = cache[font]
    if not entries then
        entries = {}
        cache[font], counts[font] = entries, 0
    end

    local entry = entries[text]
    if entry and entry.limit == limit and entry.align == align
        and entry.r == r and entry.g == g and entry.b == b and entry.a == a then
        return entry.batch
    end

    -- The coloured-string form, which is what bakes the colour in. Rebuilt rather than
    -- mutated: the colour table is handed to the C++ side and must not be shared.
    local coloured = { { r, g, b, a }, text }

    if entry then
        -- Same string, different colour or wrap. Re-setting reshapes -- exactly what a
        -- plain printf would have cost -- so an animating label degrades to the old cost
        -- rather than growing an entry per frame.
        local ok = pcall(function()
            if limit then entry.batch:setf(coloured, limit, align)
            else entry.batch:set(coloured) end
        end)
        if not ok then return nil end
        entry.limit, entry.align = limit, align
        entry.r, entry.g, entry.b, entry.a = r, g, b, a
        return entry.batch
    end

    if (counts[font] or 0) >= TextCache.MAX_ENTRIES then
        cache[font], counts[font] = {}, 0
        entries = cache[font]
    end

    local ok, batch = pcall(make, font, coloured)
    if not ok or not batch then return nil end
    if limit then
        -- Constructing with a plain string leaves it unwrapped; setf applies the wrap and
        -- alignment, and re-bakes the same colour.
        if not pcall(function() batch:setf(coloured, limit, align) end) then return nil end
    end

    entries[text] = {
        batch = batch, limit = limit, align = align, r = r, g = g, b = b, a = a,
    }
    counts[font] = (counts[font] or 0) + 1
    return batch
end

--- Draw `batch` at the current colour's expense: white, then put the colour back so this is
--- a drop-in for a `printf` that left the colour alone.
local function draw_at(batch, x, y, r, g, b, a)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(batch, x, y)
    love.graphics.setColor(r, g, b, a)
end

--- `love.graphics.printf`, shaped once and cached. Same arguments, same result.
--- @param text string Stable across frames; dynamic text belongs in a plain printf
function TextCache.printf(text, x, y, limit, align)
    local s = tostring(text or "")
    local font = love.graphics.getFont and love.graphics.getFont()
    local r, g, b, a = love.graphics.getColor()
    local batch = acquire(font, s, limit, align or "left", r, g, b, a or 1)
    if not batch then
        love.graphics.printf(s, x, y, limit, align)
        return
    end
    draw_at(batch, x, y, r, g, b, a)
end

--- `love.graphics.print`, shaped once and cached.
--- @param text string Stable across frames
function TextCache.print(text, x, y)
    local s = tostring(text or "")
    local font = love.graphics.getFont and love.graphics.getFont()
    local r, g, b, a = love.graphics.getColor()
    local batch = acquire(font, s, nil, nil, r, g, b, a or 1)
    if not batch then
        love.graphics.print(s, x, y)
        return
    end
    draw_at(batch, x, y, r, g, b, a)
end

return TextCache
