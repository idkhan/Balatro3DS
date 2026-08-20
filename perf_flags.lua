--- Runtime switches for the hardware optimisation work, read off the SD card at boot.
---
--- The two largest changes in that pass -- the coalescing renderer flush and the New 3DS
--- backdrop field worker -- can only be validated on a console, and when one of them
--- misbehaves the symptom is a frozen picture rather than a stack trace. Rebuilding and
--- reinstalling to move one boolean is several minutes per bisection step, which is the wrong
--- loop to be in. It earned its keep immediately: two SD-card edits are what identified
--- indexed drawing as the thing hanging the GPU, without a single rebuild.
---
--- Both are ON by default now, having had a clean run on a New 3DS. This file exists to turn
--- them OFF again -- it lives next to `benchmark.txt` in the save directory
--- (`sdmc:/3ds/save/<identity>/perf_flags.txt`), one `key=value` per line:
---
---     batching=0     0 one submission per command, 1 merge adjacent compatible commands
---     worker=0       0 field on the main thread in bands, 1 field on the New 3DS spare core
---
--- A key that is absent leaves the runtime's own default alone, so a file naming only
--- `batching` says nothing about the worker. An absent or unreadable file changes nothing at
--- all. Nothing here can fail in a way that stops the game booting -- a boot-time crash caused
--- by the crash-diagnosis mechanism would be its own joke.
---
--- Read once, at load, off the main thread's own boot path. `love.filesystem.read` is ~21 ms
--- on hardware, which is a fifth of the loading bar's own step and never happens again.

local PerfFlags = {}

PerfFlags.FILE = "perf_flags.txt"

--- What this module changed, for `benchmark.txt` to print. `nil` means "left as the runtime
--- had it" -- either the file said nothing about it, or the binding does not exist, which is
--- every non-3DS build. The authoritative reading of what is actually in force is
--- `love.graphics.getBatchStats().batching`, which the report also prints.
local applied = { batching = nil, worker = nil, source = "defaults" }

local function read_flags()
    if not (love.filesystem and love.filesystem.getInfo and love.filesystem.read) then
        return nil
    end
    -- One stat at boot to avoid the read's 21 ms when the file is not there, which is the
    -- normal case for anyone who is not bisecting.
    local ok, info = pcall(love.filesystem.getInfo, PerfFlags.FILE, "file")
    if not ok or not info then return nil end

    local read_ok, text = pcall(love.filesystem.read, PerfFlags.FILE)
    if not read_ok or type(text) ~= "string" then return nil end
    return text
end

--- Parse `key=value` lines into numbers. A word is accepted for the on/off cases so the file
--- reads the way anyone would expect: `true`, `yes` and `on` all mean 1, everything else that
--- is not a number means 0.
--- @return table<string, integer>
function PerfFlags.parse(text)
    local out = {}
    if type(text) ~= "string" then return out end
    for line in (text .. "\n"):gmatch("([^\r\n]*)[\r\n]") do
        local key, value = line:match("^%s*([%w_]+)%s*=%s*(%S*)")
        if key then
            value = value:lower()
            local number = tonumber(value)
            if number == nil then
                number = (value == "true" or value == "yes" or value == "on") and 1 or 0
            end
            out[key:lower()] = math.floor(number)
        end
    end
    return out
end

--- Read the file and apply whatever it asks for. Safe to call when neither binding exists.
function PerfFlags.apply()
    local text = read_flags()
    local flags = PerfFlags.parse(text)
    applied.source = text and PerfFlags.FILE or "defaults"

    -- Only what the file actually names. Calling the setter with a default would mean a file
    -- that mentions one subsystem silently reconfigured the other, which is the opposite of
    -- what a bisection tool should do.
    local g = love.graphics
    if g and g.setBatching and flags.batching ~= nil then
        if pcall(g.setBatching, flags.batching) then applied.batching = flags.batching end
    end

    if g and g.setBackdropWorker and flags.worker ~= nil then
        local on = flags.worker ~= 0
        if pcall(g.setBackdropWorker, on) then applied.worker = on end
    end

    -- A breadcrumb, so what actually took effect can be read back off the card without
    -- getting as far as the benchmark -- which matters when the thing being bisected is a
    -- freeze. Only written when someone is actually bisecting: a 36 ms write on every boot
    -- for the benefit of nobody is not a trade worth making.
    if text and love.filesystem and love.filesystem.write then
        pcall(love.filesystem.write, "perf_flags_applied.txt", string.format(
            "batching=%s\nworker=%s\nsource=%s\n",
            tostring(applied.batching), tostring(applied.worker), tostring(applied.source)))
    end

    return applied
end

--- What ended up in force, for the benchmark report.
function PerfFlags.state() return applied end

return PerfFlags
