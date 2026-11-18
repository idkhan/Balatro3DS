--- Save-file writes that rewrite the file in place instead of truncating it.
---
--- `love.filesystem.write` opens through `PHYSFS_openWrite`, which truncates: the file's
--- clusters go back to the FAT and a fresh one is allocated on every save. On some cards that
--- allocation scan is the whole cost of a save -- issue #94 measured a 6-13 KB run save at
--- 1.1-1.3 s on an Old 3DS, against 32-42 ms for the same bytes written over the existing file.
--- Which case a card is in depends on where its free space happens to sit, so the same build
--- can be fast one session and stall every state change the next.
---
--- So these files are opened for append (no truncation), rewound, and overwritten. A file
--- written this way can never shrink, so the content is padded with spaces up to the size the
--- file already has (and to a multiple of PAD_UNIT, so ordinary growth rarely crosses a
--- cluster). Every save here is a `return {...}` chunk read back with `love.filesystem.load`,
--- and trailing whitespace is legal Lua, so padded files load exactly as before -- in older
--- builds too.
---
--- The trick relies on the runtime honouring a seek on an append handle. PhysFS does (its
--- POSIX backend opens without O_APPEND and seeks to the end itself), but rather than trust
--- that blindly the first few writes of a session are read back and compared. Any mismatch,
--- or any error along the way, switches this module to plain `love.filesystem.write` for the
--- rest of the session.
---
--- Everything that writes or removes a file through here must keep doing so: the module
--- remembers each file's size so it does not have to stat the card (`getInfo` measured 12 ms
--- on the same console), and a file grown behind its back would keep a stale tail.

local SaveIO = {}

--- Padding granularity. Small enough that the 1 KB active-profile file does not turn into
--- something slow to read at boot, large enough that a run save growing by a card or two
--- usually stays the same size.
SaveIO.PAD_UNIT = 4096

--- How many in-place writes per session are read back and checked.
SaveIO.VERIFY_WRITES = 3

local known_size = {}
local verified = 0
local disabled = false

local function filesystem()
    return love and love.filesystem or nil
end

--- Size of `path` on the card, or 0 if it does not exist. Stats once per path per session.
local function current_size(fs, path)
    local size = known_size[path]
    if size ~= nil then return size end
    size = 0
    if fs.getInfo then
        local info = fs.getInfo(path, "file")
        size = (info and tonumber(info.size)) or 0
    end
    known_size[path] = size
    return size
end

local function plain_write(fs, path, data)
    local ok, err = fs.write(path, data)
    if ok then
        known_size[path] = #data
        return true
    end
    known_size[path] = nil
    return false, err
end

--- Overwrite `path` without truncating it. Returns true on success, or false plus a reason.
---@param path string
---@param data string
---@return boolean ok
---@return string|nil err
function SaveIO.write(path, data)
    local fs = filesystem()
    if not (fs and fs.write) then return false, "filesystem_unavailable" end
    data = tostring(data)
    if disabled or not fs.openFile then return plain_write(fs, path, data) end

    local unit = SaveIO.PAD_UNIT
    local target = math.max(unit, math.ceil(#data / unit) * unit)
    local existing = current_size(fs, path)
    if existing > target then target = existing end
    local padded = data .. string.rep(" ", target - #data)

    local ok, wrote = pcall(function()
        local file = fs.openFile(path, "a")
        if not file then return false end
        local good = file:seek(0) and file:write(padded)
        file:close()
        return good and true or false
    end)
    if not (ok and wrote) then
        disabled = true
        known_size[path] = nil
        return plain_write(fs, path, data)
    end
    known_size[path] = target

    if verified < SaveIO.VERIFY_WRITES and fs.read then
        verified = verified + 1
        local back = fs.read(path)
        if back ~= padded then
            disabled = true
            known_size[path] = nil
            return plain_write(fs, path, data)
        end
    end
    return true
end

--- Remove `path` and forget its size.
---@param path string
---@return boolean removed
function SaveIO.remove(path)
    known_size[path] = nil
    local fs = filesystem()
    if not (fs and fs.remove) then return false end
    return fs.remove(path) and true or false
end

--- Forget everything learned this session. For tests that rebuild the filesystem.
function SaveIO.reset()
    known_size = {}
    verified = 0
    disabled = false
end

--- Whether in-place writes have been abandoned for this session.
function SaveIO.is_disabled()
    return disabled
end

return SaveIO
