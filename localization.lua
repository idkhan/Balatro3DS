--- Display-text localization: `Localization.t(key, params)` with English fallback.
---
--- From Fussyzhy's Chinese translation of this port (https://github.com/Fussyzhy/Balatro3DS-zh),
--- used with permission; LOCALIZATION.md is the contract it follows. Gameplay never sees
--- translated text: catalog ids, hand names, suits and ranks stay English and are translated only
--- where they are drawn.
---
--- Strings live in `locales/<language>.lua` (interface) and `locales/content/<language>/*.lua`
--- (catalog names and descriptions). A missing entry falls back to English, then to the caller's
--- fallback, then to the key itself, so an untranslated string is visible rather than blank.
local Localization = {}

Localization.DEFAULT_LANGUAGE = "en"

Localization.SUPPORTED_LANGUAGES = { "en", "es", "da", "zh_CN", "it" }

local locale_cache = {}
--- Strings added at runtime, by language: mod text (`smods.lua`), layered over the files.
local added = {}
local current_language = Localization.DEFAULT_LANGUAGE

local CONTENT_MODULES = {
    "terms",
    "decks",
    "stakes",
    "blinds",
    "vouchers",
    "tags",
    "consumables",
    "jokers",
}

local function merge_locale(target, source)
    if type(target) ~= "table" or type(source) ~= "table" then return target end
    for key, value in pairs(source) do
        target[key] = value
    end
    return target
end

local function is_supported(language)
    if type(language) ~= "string" then return false end
    for _, code in ipairs(Localization.SUPPORTED_LANGUAGES) do
        if code == language then return true end
    end
    return false
end

local function load_locale(language)
    if locale_cache[language] then return locale_cache[language] end
    local ok, locale = pcall(require, "locales." .. language)
    if not ok or type(locale) ~= "table" then
        locale = {}
    end
    for _, module_name in ipairs(CONTENT_MODULES) do
        local content_ok, content = pcall(
            require,
            string.format("locales.content.%s.%s", language, module_name)
        )
        if content_ok then
            merge_locale(locale, content)
        end
    end
    merge_locale(locale, added[language])
    locale_cache[language] = locale
    return locale
end

local function lookup(locale, key)
    if type(locale) ~= "table" or type(key) ~= "string" then return nil end
    if locale[key] ~= nil then return locale[key] end

    local value = locale
    for part in key:gmatch("[^.]+") do
        if type(value) ~= "table" then return nil end
        value = value[part]
        if value == nil then return nil end
    end
    return value
end

--- `{name}` from `params`. A table replacement rather than a closure: tooltips call this every
--- frame they are up (`Joker:get_live_current_tooltip_text`), and a closure per call is garbage
--- per frame on a console without a trace compiler. A name missing from `params` stays as
--- written, which is what gsub does with a nil lookup.
local function interpolate_string(value, params)
    if type(value) ~= "string" or type(params) ~= "table" then return value end
    if not value:find("{", 1, true) then return value end
    return (value:gsub("{([%w_]+)}", params))
end

local function interpolate_value(value, params)
    if type(value) == "string" then
        return interpolate_string(value, params)
    end
    if type(value) ~= "table" then return value end

    local out = {}
    for key, item in pairs(value) do
        out[key] = interpolate_value(item, params)
    end
    return out
end

--- Add strings for a language at runtime (a mod's own translations). They sit over the locale
--- files and survive a language switch.
function Localization.add_strings(language, strings)
    if type(language) ~= "string" or type(strings) ~= "table" then return end
    added[language] = added[language] or {}
    for key, value in pairs(strings) do
        added[language][key] = value
        if locale_cache[language] then locale_cache[language][key] = value end
    end
end

--- Take runtime strings back out (a mod that failed to load, or the tests).
function Localization.remove_strings(language, keys)
    for _, key in ipairs(keys or {}) do
        if added[language] then added[language][key] = nil end
        if locale_cache[language] then locale_cache[language][key] = nil end
    end
end

function Localization.is_supported(language)
    return is_supported(language)
end

function Localization.get_language()
    return current_language
end

function Localization.set_language(language)
    if not is_supported(language) then
        current_language = Localization.DEFAULT_LANGUAGE
        return false
    end
    current_language = language
    load_locale(language)
    local catalog = rawget(_G, "CollectionCatalog")
    if not catalog and package.loaded["collection_catalog"] then
        catalog = package.loaded["collection_catalog"]
    end
    if catalog and catalog.invalidate_cache then
        catalog.invalidate_cache()
    end
    return true
end

--- The language's own display name, in the current language (`language.<code>`).
function Localization.language_name(code)
    return Localization.t("language." .. tostring(code), nil, tostring(code))
end

function Localization.available_languages()
    local out = {}
    for i, code in ipairs(Localization.SUPPORTED_LANGUAGES) do
        out[i] = code
    end
    return out
end

function Localization.has(key, language)
    local code = is_supported(language) and language or current_language
    return lookup(load_locale(code), key) ~= nil
end

function Localization.t(key, params, explicit_fallback)
    if type(params) ~= "table" then
        if explicit_fallback == nil and params ~= nil then
            explicit_fallback = params
        end
        params = nil
    end

    local value = lookup(load_locale(current_language), key)
    if value == nil and current_language ~= Localization.DEFAULT_LANGUAGE then
        value = lookup(load_locale(Localization.DEFAULT_LANGUAGE), key)
    end
    if value == nil then value = explicit_fallback end
    if value == nil then value = tostring(key or "") end
    return interpolate_value(value, params)
end

function Localization.item_name(kind, id, fallback)
    return Localization.t(string.format("%s.%s.name", tostring(kind), tostring(id)), nil, fallback)
end

function Localization.item_description(kind, id, fallback)
    return Localization.t(string.format("%s.%s.description", tostring(kind), tostring(id)), nil, fallback)
end

local function identifier_key(value)
    local key = tostring(value or ""):lower()
    key = key:gsub("[^%w]+", "_")
    return key:gsub("^_+", ""):gsub("_+$", "")
end

--- Catalog text in the live language. In English the catalog's own text is the source of truth
--- (LOCALIZATION.md), so a caller's English fallback is returned as it is: English stays exactly
--- what it was even where `locales/content/en` words a term differently.
local function catalog_text(key, fallback)
    if current_language == Localization.DEFAULT_LANGUAGE and fallback ~= nil then return fallback end
    return Localization.t(key, nil, fallback)
end

function Localization.content_name(kind, id, fallback)
    return catalog_text(string.format("%s.%s.name", tostring(kind), tostring(id)), fallback)
end

function Localization.content_description(kind, id, fallback)
    return catalog_text(string.format("%s.%s.description", tostring(kind), tostring(id)), fallback)
end

--- Text the code already has in English: that English, unchanged, in English; the translation
--- in any other language (falling back to the same English). For strings where the port's
--- wording and `locales/en.lua` differ, so switching the code over cannot change English.
function Localization.text(key, params, english)
    if current_language == Localization.DEFAULT_LANGUAGE and english ~= nil then return english end
    return Localization.t(key, params, english)
end

--- A description as one string, whether the translation wrote it as one or as lines.
function Localization.content_text(kind, id, fallback)
    local value = Localization.content_description(kind, id, fallback)
    if type(value) == "table" then
        local lines = {}
        for _, l in ipairs(value) do lines[#lines + 1] = type(l) == "table" and (l.text or "") or tostring(l) end
        return table.concat(lines, "\n")
    end
    return value
end

function Localization.content_lines(kind, id, fallback)
    local value = Localization.content_description(kind, id, fallback)
    if type(value) == "table" then return value end
    local lines = {}
    for line in tostring(value or ""):gmatch("[^\r\n]+") do
        lines[#lines + 1] = line
    end
    return lines
end

function Localization.hand_name(internal_name)
    return Localization.t("hand." .. identifier_key(internal_name), nil, internal_name)
end

function Localization.suit_name(internal_name)
    return Localization.t("suit." .. identifier_key(internal_name), nil, internal_name)
end

function Localization.rank_name(internal_rank)
    local rank = tonumber(internal_rank)
    local key = rank and tostring(math.floor(rank)) or identifier_key(internal_rank)
    return Localization.t("rank." .. key, nil, internal_rank)
end

load_locale(Localization.DEFAULT_LANGUAGE)

return Localization
