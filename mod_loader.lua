--- Finds and loads mods from the save directory.
---
--- Layout, Steamodded's:
---
---     <save dir>/sdmc/mods/<Folder>/<Anything>.json    the manifest: id, name, prefix, main_file, version
---     <save dir>/sdmc/mods/<Folder>/<main_file>.lua    run once at boot, before the game is built
---     <save dir>/sdmc/mods/<Folder>/assets/1x/*.t3x     one image per card (named as .png, see smods.lua)
---
--- Mods load in id order, so the same set of mods always registers in the same order. Each runs
--- in its own environment over the game's globals: it can read everything, but globals it
--- defines stay its own instead of landing on top of the game's. A mod that fails -- a bad
--- manifest, a missing dependency, an error in its main file -- is rolled back and listed on the
--- Mods screen with the reason; the others still load.
---
--- Every boot writes `mods/mods_log.txt` beside the mods, so a modder on hardware, with no
--- console, can read why something did not load.
---
--- The player turns mods off and on in Options > Mods. The ids of the ones turned off are kept in
--- `mods/disabled.txt`, one per line, so the list survives a reboot and can be edited off the card.

local Json = require("json")
require("smods")

local ModLoader = {}

ModLoader.DIR = "sdmc/mods"
ModLoader.LOG_PATH = "sdmc/mods/mods_log.txt"
ModLoader.DISABLED_PATH = "sdmc/mods/disabled.txt"

--- Every mod found, in load order. Each: `{ id, name, version, prefix, author, description,
--- path, main_file, dependencies, status = "loaded"|"error"|"disabled", error, runtime_errors,
--- registered = { jokers, consumables, vouchers, sprites } }`.
ModLoader.mods = {}
ModLoader.by_id = {}
--- The ids the player has turned off, as a set. Read from `DISABLED_PATH` by `load_all`.
ModLoader.disabled = {}

local function fs()
    return love and love.filesystem
end

local function is_dir(path)
    local f = fs()
    return f and f.getInfo and f.getInfo(path, "directory") ~= nil
end

local function new_mod(folder)
    return {
        id = folder, name = folder, version = "0.0.0", prefix = folder,
        folder = folder, path = ModLoader.DIR .. "/" .. folder,
        author = "", description = "", dependencies = {},
        status = "error", error = nil, runtime_errors = {},
        registered = { jokers = {}, sprites = {}, consumables = {}, vouchers = {}, decks = {}, editions = {}, deck_skins = {}, strings = {} },
    }
end

local function fail(mod, msg)
    mod.status = "error"
    mod.error = tostring(msg)
    return mod
end

--- Read a mod folder's manifest: the first `.json` in it that names a `main_file`.
local function read_manifest(folder)
    local mod = new_mod(folder)
    local f = fs()
    local items = f.getDirectoryItems(mod.path) or {}
    table.sort(items)
    local parse_error
    for _, item in ipairs(items) do
        if item:lower():match("%.json$") then
            local text = f.read(mod.path .. "/" .. item)
            local ok, data = pcall(Json.decode, text or "")
            if not ok then
                parse_error = item .. ": " .. tostring(data)
            elseif type(data) == "table" and type(data.main_file) == "string" then
                mod.manifest_file = item
                mod.id = type(data.id) == "string" and data.id or folder
                mod.name = type(data.name) == "string" and data.name or mod.id
                mod.version = data.version ~= nil and tostring(data.version) or "0.0.0"
                mod.prefix = type(data.prefix) == "string" and data.prefix or mod.id
                mod.main_file = data.main_file
                mod.description = type(data.description) == "string" and data.description or ""
                if type(data.author) == "table" then
                    mod.author = table.concat(data.author, ", ")
                elseif data.author ~= nil then
                    mod.author = tostring(data.author)
                end
                if type(data.dependencies) == "table" then mod.dependencies = data.dependencies end
                if not mod.prefix:match("^[%w_]+$") then
                    return fail(mod, "prefix '" .. mod.prefix .. "' may only use letters, digits and _")
                end
                mod.status = "pending"
                return mod
            end
        end
    end
    return fail(mod, parse_error or "no manifest: add a .json with id, prefix, main_file and version")
end

--- Steamodded dependency strings look like `"OtherMod (>=1.0.0)"`; the id is everything before
--- the version clause. Steamodded itself is what this loader stands in for, so it is satisfied.
local function dependency_id(dep)
    local id = tostring(dep):match("^%s*([^%s%(<>=]+)")
    return id
end

--- @return string|nil problem why the mod cannot load
--- @return boolean waiting true while a dependency has yet to load
local function check_dependencies(mod)
    local waiting = false
    for _, dep in ipairs(mod.dependencies or {}) do
        local id = dependency_id(dep)
        if id and id:lower() ~= "steamodded" then
            local other = ModLoader.by_id[id]
            if not other then return "needs mod '" .. id .. "', which is not installed", false end
            if other.status == "disabled" then return "needs mod '" .. id .. "', which is turned off", false end
            if other.status == "pending" then
                waiting = true
            elseif other.status ~= "loaded" then
                return "needs mod '" .. id .. "', which failed to load", false
            end
        end
    end
    return nil, waiting
end

local function run_mod(mod)
    local f = fs()
    local main_path = mod.path .. "/" .. mod.main_file
    if not f.getInfo(main_path, "file") then
        return fail(mod, "main_file '" .. mod.main_file .. "' not found")
    end
    local chunk, err = f.load(main_path)
    if not chunk then return fail(mod, err or "could not compile " .. mod.main_file) end
    setfenv(chunk, SMODS.mod_environment(mod))
    SMODS.current_mod = mod
    local ok, run_err = pcall(chunk)
    SMODS.current_mod = nil
    if not ok then
        SMODS.rollback(mod)
        return fail(mod, run_err)
    end
    mod.status = "loaded"
    mod.error = nil
    return mod
end

local function read_disabled()
    local set = {}
    local f = fs()
    if not (f and f.getInfo and f.getInfo(ModLoader.DISABLED_PATH, "file")) then return set end
    for line in tostring(f.read(ModLoader.DISABLED_PATH) or ""):gmatch("[^\r\n]+") do
        local id = line:match("^%s*(.-)%s*$")
        if id ~= "" and id:sub(1, 1) ~= "#" then set[id] = true end
    end
    return set
end

local function write_disabled()
    local f = fs()
    if not (f and f.write) then return false end
    local ids = {}
    for id in pairs(ModLoader.disabled) do ids[#ids + 1] = id end
    table.sort(ids)
    if #ids == 0 and f.remove then
        if f.getInfo(ModLoader.DISABLED_PATH, "file") then pcall(f.remove, ModLoader.DISABLED_PATH) end
        return true
    end
    local text = "# Mods turned off in Options > Mods, one id per line.\n" .. table.concat(ids, "\n") .. "\n"
    return (pcall(f.write, ModLoader.DISABLED_PATH, text))
end

--- Whether the player can turn this mod off and on: it needs a manifest, which is where its id
--- comes from. A folder with no readable manifest has nothing to switch.
function ModLoader.can_toggle(mod)
    return type(mod) == "table" and mod.manifest_file ~= nil
end

function ModLoader.is_enabled(mod)
    return type(mod) == "table" and not ModLoader.disabled[mod.id]
end

--- Turn a mod on or off, save the choice, and reload every mod so it takes effect now. Only
--- safe with no run in memory: the Mods screen is reached from the main menu alone.
--- @return boolean ok
function ModLoader.set_enabled(id, enabled)
    if type(id) ~= "string" then return false end
    ModLoader.disabled[id] = (not enabled) or nil
    local saved = write_disabled()
    ModLoader.load_all()
    return saved
end

--- Undo every loaded mod and forget them. Used by the tests; the game loads once per boot.
function ModLoader.reset()
    for _, mod in ipairs(ModLoader.mods) do SMODS.rollback(mod) end
    ModLoader.mods = {}
    ModLoader.by_id = {}
end

--- Discover and load every mod. Safe to call without a filesystem (does nothing).
function ModLoader.load_all()
    ModLoader.reset()
    local f = fs()
    if not (f and f.getDirectoryItems and f.load and f.read and f.getInfo) then return ModLoader.mods end
    if f.createDirectory then f.createDirectory(ModLoader.DIR) end
    SMODS.install_card_methods()
    ModLoader.disabled = read_disabled()

    local found = {}
    for _, folder in ipairs(f.getDirectoryItems(ModLoader.DIR) or {}) do
        if is_dir(ModLoader.DIR .. "/" .. folder) then
            found[#found + 1] = read_manifest(folder)
        end
    end
    table.sort(found, function(a, b)
        local la, lb = a.id:lower(), b.id:lower()
        if la ~= lb then return la < lb end
        return a.folder < b.folder
    end)

    local prefixes = {}
    for _, mod in ipairs(found) do
        ModLoader.mods[#ModLoader.mods + 1] = mod
        -- A mod that is turned off never runs, so whatever was wrong with it does not apply. It
        -- keeps its id, so dependants and the saved-run check can say it is off, not missing,
        -- but not its prefix: that is only reserved by what actually registers under it.
        if ModLoader.can_toggle(mod) and ModLoader.disabled[mod.id] then
            mod.status, mod.error = "disabled", nil
            ModLoader.by_id[mod.id] = ModLoader.by_id[mod.id] or mod
        end
        if mod.status == "pending" then
            if ModLoader.by_id[mod.id] then
                fail(mod, "another mod already uses the id '" .. mod.id .. "'")
            elseif prefixes[mod.prefix] then
                fail(mod, "prefix '" .. mod.prefix .. "' is already used by " .. prefixes[mod.prefix])
            end
        end
        if mod.status == "pending" then
            ModLoader.by_id[mod.id] = mod
            prefixes[mod.prefix] = mod.id
        end
    end

    -- Dependencies may load after their dependants in id order, so resolve in passes until
    -- nothing more can load.
    local progressed = true
    while progressed do
        progressed = false
        for _, mod in ipairs(ModLoader.mods) do
            if mod.status == "pending" then
                local problem, waiting = check_dependencies(mod)
                if problem then
                    fail(mod, problem)
                    progressed = true
                elseif not waiting then
                    run_mod(mod)
                    progressed = true
                end
            end
        end
    end
    for _, mod in ipairs(ModLoader.mods) do
        if mod.status == "pending" then fail(mod, "dependency cycle") end
    end

    -- The collection caches its entries; mod Jokers have to be in them.
    local ok, catalog = pcall(require, "collection_catalog")
    if ok and type(catalog) == "table" and catalog.invalidate_cache then catalog.invalidate_cache() end
    ModLoader.write_log()
    return ModLoader.mods
end

--- @return table[] the mods that loaded
function ModLoader.loaded_mods()
    local out = {}
    for _, mod in ipairs(ModLoader.mods) do
        if mod.status == "loaded" then out[#out + 1] = mod end
    end
    return out
end

--- What a run save records: every loaded mod and its version, sorted by id.
--- @return table[] `{ { id, version }, ... }`
function ModLoader.fingerprint()
    local out = {}
    for _, mod in ipairs(ModLoader.loaded_mods()) do
        out[#out + 1] = { id = mod.id, version = mod.version }
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

--- Compare a save's mod list against what is loaded now. A run is tied to the mods it was
--- played with: anything missing, at another version, or newly added changes what the run
--- contains or what its pools can roll, so it cannot be continued until the set matches.
--- A save from before mods existed carries no list, which means "no mods".
--- @param saved table|nil the save's `mods`
--- @return table|nil `{ missing = {...}, changed = {...}, extra = {...} }`, nil when they match
function ModLoader.compare(saved)
    local want = {}
    for _, m in ipairs(type(saved) == "table" and saved or {}) do
        if type(m) == "table" and type(m.id) == "string" then want[m.id] = tostring(m.version or "") end
    end
    local have = {}
    for _, m in ipairs(ModLoader.fingerprint()) do have[m.id] = m.version end

    local diff = { missing = {}, changed = {}, extra = {} }
    for id, version in pairs(want) do
        if have[id] == nil then
            diff.missing[#diff.missing + 1] = { id = id, version = version }
        elseif have[id] ~= version then
            diff.changed[#diff.changed + 1] = { id = id, saved = version, installed = have[id] }
        end
    end
    for id, version in pairs(have) do
        if want[id] == nil then diff.extra[#diff.extra + 1] = { id = id, version = version } end
    end
    for _, list in pairs(diff) do table.sort(list, function(a, b) return a.id < b.id end) end
    if #diff.missing == 0 and #diff.changed == 0 and #diff.extra == 0 then return nil end
    return diff
end

--- Plain lines describing a mismatch, for the Mods screen.
function ModLoader.describe_mismatch(diff)
    local lines = {}
    if not diff then return lines end
    for _, m in ipairs(diff.missing) do
        local installed = ModLoader.by_id[m.id]
        if installed and installed.status == "disabled" then
            lines[#lines + 1] = I18N.text("mods.turn_on", { id = m.id }, ("Turn on %s"):format(m.id))
        else
            lines[#lines + 1] = I18N.text("mods.install", { id = m.id, version = m.version }, ("Install %s %s"):format(m.id, m.version))
        end
    end
    for _, m in ipairs(diff.changed) do
        lines[#lines + 1] = I18N.text("mods.changed", { id = m.id, saved = m.saved, installed = m.installed },
            ("%s: saved with %s, installed %s"):format(m.id, m.saved, m.installed))
    end
    for _, m in ipairs(diff.extra) do
        lines[#lines + 1] = I18N.text("mods.remove", { id = m.id, version = m.version },
            ("Turn off %s %s (not in this run)"):format(m.id, m.version))
    end
    return lines
end

local function log_lines()
    local lines = { "Balatro3DS mods -- " .. ModLoader.DIR, "" }
    if #ModLoader.mods == 0 then lines[#lines + 1] = "No mods installed." end
    for _, mod in ipairs(ModLoader.mods) do
        local tag = ({ loaded = "OK", disabled = "OFF" })[mod.status] or "ERROR"
        lines[#lines + 1] = ("[%s] %s %s (%s)"):format(tag, mod.id, mod.version, mod.folder)
        if mod.status == "disabled" then
            lines[#lines + 1] = "    turned off in Options > Mods (" .. ModLoader.DISABLED_PATH .. ")"
        elseif mod.status == "loaded" then
            lines[#lines + 1] = ("    %d joker(s), %d consumable(s), %d voucher(s), %d deck(s), %d edition(s), %d deck skin(s), %d image(s)"):format(
                #mod.registered.jokers, #mod.registered.consumables, #mod.registered.vouchers,
                #mod.registered.decks, #mod.registered.editions, #mod.registered.deck_skins, #mod.registered.sprites)
        else
            lines[#lines + 1] = "    " .. tostring(mod.error)
        end
        for _, err in ipairs(mod.runtime_errors or {}) do
            lines[#lines + 1] = "    runtime: " .. tostring(err)
        end
    end
    return lines
end

function ModLoader.write_log()
    local f = fs()
    if not (f and f.write) then return end
    pcall(f.write, ModLoader.LOG_PATH, table.concat(log_lines(), "\n") .. "\n")
end

--- Runtime errors reach the log as they happen, so the file is current when a modder reads it.
SMODS.on_runtime_error = function() ModLoader.write_log() end

return ModLoader
