--- Collection category definitions and entry enumeration.
local CollectionCatalog = {}

CollectionCatalog.ENHANCEMENT_KEYS = {
    "bonus", "mult", "wild", "glass", "steel", "stone", "gold", "lucky",
}

CollectionCatalog.SEAL_KEYS = {
    "gold", "red", "purple", "blue",
}

CollectionCatalog.EDITION_KEYS = {
    "foil", "holo", "polychrome", "negative",
}

CollectionCatalog.ENHANCEMENT_NAMES = {
    bonus = "Bonus Card",
    mult = "Mult Card",
    wild = "Wild Card",
    glass = "Glass Card",
    steel = "Steel Card",
    stone = "Stone Card",
    gold = "Gold Card",
    lucky = "Lucky Card",
}

CollectionCatalog.SEAL_NAMES = {
    gold = "Gold Seal",
    red = "Red Seal",
    blue = "Blue Seal",
    purple = "Purple Seal",
}

CollectionCatalog.EDITION_NAMES = {
    foil = "Foil",
    holo = "Holographic",
    polychrome = "Polychrome",
    negative = "Negative",
}

CollectionCatalog.ENHANCEMENT_TOOLTIPS = {
    bonus = { "+30 chips" },
    mult = { "+4 mult" },
    glass = { "×2 mult", "1/4: breaks after score" },
    steel = { "×1.5 mult while held in hand" },
    stone = { "+50 chips" },
    gold = { "+$3 while held in hand at the end of the Round" },
    lucky = { "1/5: +20 mult", "1/15: +$20" },
    wild = { "Wild card" },
}

CollectionCatalog.SEAL_TOOLTIPS = {
    gold = { "+$3 when scored" },
    red = { "Retriggers Card Once" },
    blue = { "Creates a Planet card for the winning Hand if held in hand" },
    purple = { "Creates a Tarot Card when Discarded" },
}

CollectionCatalog.BOOSTER_PACK_ORDER = { "arcana", "celestial", "spectral", "standard", "buffoon" }
CollectionCatalog.BOOSTER_SIZE_ORDER = { "normal", "jumbo", "mega" }

local function shop_ui_module()
    if ShopUI then return ShopUI end
    local ok, mod = pcall(require, "shop_ui")
    return ok and mod or nil
end

local function booster_pack_ui_module()
    local ok, mod = pcall(require, "booster_pack_ui")
    return ok and mod or nil
end

--- P_TAGS key -> Tag() type string
CollectionCatalog.TAG_TYPE_FROM_KEY = {
    tag_uncommon = "uncommon",
    tag_rare = "rare",
    tag_negative = "negative",
    tag_foil = "foil",
    tag_holo = "holo",
    tag_polychrome = "polychrome",
    tag_investment = "investment",
    tag_voucher = "voucher",
    tag_boss = "boss",
    tag_standard = "standard",
    tag_charm = "charm",
    tag_meteor = "meteor",
    tag_buffoon = "buffoon",
    tag_handy = "handy",
    tag_garbage = "garbage",
    tag_ethereal = "ethereal",
    tag_coupon = "coupon",
    tag_double = "double",
    tag_juggle = "juggle",
    tag_d_six = "d6",
    tag_top_up = "topup",
    tag_skip = "speed",
    tag_orbital = "orbital",
    tag_economy = "economy",
}

CollectionCatalog.TAG_KEY_FROM_TYPE = {}
for key, tag_type in pairs(CollectionCatalog.TAG_TYPE_FROM_KEY) do
    CollectionCatalog.TAG_KEY_FROM_TYPE[tag_type] = key
end

CollectionCatalog.CATEGORIES = {
    { id = "jokers",    label = "Jokers",          color_key = "RED",    tall = true },
    { id = "decks",     label = "Decks",           color_key = "RED" },
    { id = "vouchers",  label = "Vouchers",        color_key = "RED" },
    { id = "tarots",    label = "Tarot Cards",     color_key = "PURPLE", group = "consumables" },
    { id = "planets",   label = "Planet Cards",    color_key = "PLANET", group = "consumables" },
    { id = "spectrals", label = "Spectral Cards",  color_key = "SPECTRAL", group = "consumables" },
    { id = "enhanced",  label = "Enhanced Cards",  color_key = "RED" },
    { id = "seals",     label = "Seals",           color_key = "RED" },
    { id = "editions",  label = "Editions",        color_key = "RED" },
    { id = "boosters",  label = "Booster Packs",   color_key = "RED" },
    { id = "tags",      label = "Tags",            color_key = "RED" },
    { id = "blinds",    label = "Blinds",          color_key = "RED", tall = true },
}

function CollectionCatalog.discovery_id_for_entry(entry)
    if not entry then return nil end
    if entry.discovery_id then return entry.discovery_id end
    return entry.id
end

function CollectionCatalog.is_entry_discovered(game, entry)
    if not game or not entry then return false end
    if entry.category == "seals" or entry.category == "editions" then
        return true
    end
    if entry.category == "decks" then
        return game.is_deck_unlocked and game:is_deck_unlocked(entry.id) == true
    end
    local did = CollectionCatalog.discovery_id_for_entry(entry)
    return game.is_discovered and game:is_discovered(did) == true
end

local function sort_entries(a, b)
    local oa = tonumber(a.order) or 9999
    local ob = tonumber(b.order) or 9999
    if oa ~= ob then return oa < ob end
    return tostring(a.name or a.id) < tostring(b.name or b.id)
end

function CollectionCatalog.build_joker_entries()
    local out = {}
    for id, def in pairs(JOKER_DEFS or {}) do
        if type(def) == "table" then
            out[#out + 1] = {
                id = id,
                category = "jokers",
                node_kind = "joker",
                name = def.name or id,
                order = tonumber(def.order) or 9999,
                def = def,
                discovery_id = id,
            }
        end
    end
    table.sort(out, sort_entries)
    return out
end

function CollectionCatalog.build_consumable_entries(kind)
    local out = {}
    for id, def in pairs(CONSUMABLE_DEFS or {}) do
        if type(def) == "table" and def.kind == kind then
            out[#out + 1] = {
                id = id,
                category = kind == "tarot" and "tarots" or (kind == "planet" and "planets" or "spectrals"),
                node_kind = "consumable",
                name = def.name or id,
                order = tonumber(def.index) or 9999,
                def = def,
                discovery_id = id,
            }
        end
    end
    table.sort(out, sort_entries)
    return out
end

function CollectionCatalog.build_deck_entries()
    local out = {}
    for _, def in ipairs(DECK_DEFS or {}) do
        out[#out + 1] = {
            id = def.id,
            category = "decks",
            node_kind = "deck",
            name = def.name or def.id,
            order = tonumber(def.order) or 9999,
            def = def,
            pos = def.pos,
        }
    end
    table.sort(out, sort_entries)
    return out
end

function CollectionCatalog.build_voucher_entries()
    local out = {}
    for id, def in pairs(VOUCHER_DEFS or {}) do
        if type(def) == "table" then
            out[#out + 1] = {
                id = id,
                category = "vouchers",
                node_kind = "voucher",
                name = def.name or id,
                order = tonumber(def.pos) or 9999,
                def = def,
                discovery_id = id,
                description = def.description,
            }
        end
    end
    table.sort(out, sort_entries)
    return out
end

function CollectionCatalog.build_enhanced_entries()
    local out = {}
    for i, key in ipairs(CollectionCatalog.ENHANCEMENT_KEYS) do
        out[#out + 1] = {
            id = "enhancement_" .. key,
            category = "enhanced",
            node_kind = "enhanced",
            name = CollectionCatalog.ENHANCEMENT_NAMES[key] or key,
            order = i,
            enhancement = key,
            discovery_id = "enhancement_" .. key,
        }
    end
    return out
end

function CollectionCatalog.build_seal_entries()
    local out = {}
    for i, key in ipairs(CollectionCatalog.SEAL_KEYS) do
        out[#out + 1] = {
            id = "seal_" .. key,
            category = "seals",
            node_kind = "seal",
            name = CollectionCatalog.SEAL_NAMES[key] or key,
            order = i,
            seal = key,
            discovery_id = "seal_" .. key,
        }
    end
    return out
end

function CollectionCatalog.build_edition_entries()
    local out = {}
    for i, key in ipairs(CollectionCatalog.EDITION_KEYS) do
        out[#out + 1] = {
            id = "edition_" .. key,
            category = "editions",
            node_kind = "edition",
            name = CollectionCatalog.EDITION_NAMES[key] or key,
            order = i,
            edition = key,
            discovery_id = "edition_" .. key,
        }
    end
    return out
end

function CollectionCatalog.build_booster_entries()
    local out = {}
    local ShopUIMod = shop_ui_module()
    local BoosterPackUI = booster_pack_ui_module()
    local frames = ShopUIMod and ShopUIMod.BOOSTER_ATLAS_FRAMES or {}
    local order = 0
    for _, pack in ipairs(CollectionCatalog.BOOSTER_PACK_ORDER) do
        local sizes = frames[pack]
        if type(sizes) == "table" then
            for _, size in ipairs(CollectionCatalog.BOOSTER_SIZE_ORDER) do
                local idx_list = sizes[size]
                if type(idx_list) == "table" and #idx_list > 0 then
                    order = order + 1
                    local frame_idx = idx_list[1]
                    local id = string.format("booster_%s_%s", pack, size)
                    local label = BoosterPackUI and BoosterPackUI.display_label(pack, size) or pack
                    local card_count = BoosterPackUI and BoosterPackUI.card_count_for_size(size) or 3
                    local picks = BoosterPackUI and BoosterPackUI.picks_for_size(size) or 1
                    out[#out + 1] = {
                        id = id,
                        category = "boosters",
                        node_kind = "booster",
                        name = label .. " Pack",
                        order = order,
                        pack = pack,
                        size = size,
                        frame_index = frame_idx,
                        discovery_id = id,
                        shop_offer = {
                            pack = pack,
                            size = size,
                            card_count = card_count,
                            picks_granted = picks,
                        },
                    }
                end
            end
        end
    end
    return out
end

function CollectionCatalog.deck_tooltip_body(game, def)
    if type(def) ~= "table" then return "" end
    if game and game.is_deck_unlocked and game:is_deck_unlocked(def.id) then
        return def.description or ""
    end
    local uc = def.unlock_condition
    if type(uc) == "table" and type(uc.text) == "string" then
        return uc.text
    end
    return "Complete the unlock condition to play this deck."
end

---@return string title
---@return string[] body_lines
function CollectionCatalog.entry_tooltip_content(game, entry)
    if not entry then return "Not Discovered", {} end
    if not CollectionCatalog.is_entry_discovered(game, entry) then
        return "Not Discovered", {}
    end

    local kind = entry.node_kind
    if kind == "deck" then
        return entry.name or "Deck", { CollectionCatalog.deck_tooltip_body(game, entry.def) }
    elseif kind == "voucher" then
        local desc = entry.description or (entry.def and entry.def.description) or ""
        return entry.name or "Voucher", { desc }
    elseif kind == "booster" then
        local BoosterPackUI = booster_pack_ui_module()
        local title = entry.name or "Booster Pack"
        local desc = ""
        if BoosterPackUI and entry.shop_offer then
            desc = BoosterPackUI.shop_tooltip_description(entry.shop_offer) or ""
        end
        return title, { desc }
    elseif kind == "enhanced" then
        return entry.name or "Enhanced Card",
            CollectionCatalog.ENHANCEMENT_TOOLTIPS[entry.enhancement] or {}
    elseif kind == "seal" then
        return entry.name or "Seal",
            CollectionCatalog.SEAL_TOOLTIPS[entry.seal] or {}
    elseif kind == "tag" then
        local body = entry.description or ""
        if body == "" and entry.tag_def then
            body = entry.tag_def.name or ""
        end
        return entry.name or "Tag", { body }
    elseif kind == "blind" then
        local key = entry.blind_key or entry.id
        local desc = ""
        if game and game.get_blind_prototype_description then
            desc = game:get_blind_prototype_description(key) or ""
        end
        if desc == "" then desc = "No special effect." end
        return entry.name or "Blind", { desc }
    end

    return entry.name or "???", {}
end

function CollectionCatalog.invalidate_cache()
    _entries_cache = nil
end

function CollectionCatalog.build_tag_entries()
    local out = {}
    local tags = G and G.P_TAGS or {}
    for key, def in pairs(tags) do
        if type(def) == "table" and key ~= "tag_undiscovered" then
            local tag_type = CollectionCatalog.TAG_TYPE_FROM_KEY[key]
            if tag_type then
                out[#out + 1] = {
                    id = key,
                    category = "tags",
                    node_kind = "tag",
                    name = def.name or key,
                    order = tonumber(def.order) or 9999,
                    tag_type = tag_type,
                    tag_def = def,
                    discovery_id = key,
                    description = Tag and Tag.DESCRIPTIONS and Tag.DESCRIPTIONS[tag_type],
                }
            end
        end
    end
    table.sort(out, sort_entries)
    return out
end

function CollectionCatalog.build_blind_entries()
    local out = {}
    local blinds = G and G.P_BLINDS or {}
    for key, def in pairs(blinds) do
        if type(def) == "table" then
            out[#out + 1] = {
                id = key,
                category = "blinds",
                node_kind = "blind",
                name = def.name or key,
                order = tonumber(def.order) or 9999,
                blind_def = def,
                blind_key = key,
                discovery_id = key,
            }
        end
    end
    table.sort(out, sort_entries)
    return out
end

local _entries_cache = nil

function CollectionCatalog.all_entries_by_category()
    if _entries_cache then return _entries_cache end
    _entries_cache = {
        jokers = CollectionCatalog.build_joker_entries(),
        decks = CollectionCatalog.build_deck_entries(),
        vouchers = CollectionCatalog.build_voucher_entries(),
        tarots = CollectionCatalog.build_consumable_entries("tarot"),
        planets = CollectionCatalog.build_consumable_entries("planet"),
        spectrals = CollectionCatalog.build_consumable_entries("spectral"),
        enhanced = CollectionCatalog.build_enhanced_entries(),
        seals = CollectionCatalog.build_seal_entries(),
        editions = CollectionCatalog.build_edition_entries(),
        boosters = CollectionCatalog.build_booster_entries(),
        tags = CollectionCatalog.build_tag_entries(),
        blinds = CollectionCatalog.build_blind_entries(),
    }
    return _entries_cache
end

function CollectionCatalog.get_entries(category_id)
    local all = CollectionCatalog.all_entries_by_category()
    return all[category_id] or {}
end

function CollectionCatalog.get_progress(game, category_id)
    local entries = CollectionCatalog.get_entries(category_id)
    local total = #entries
    local discovered = 0
    for _, entry in ipairs(entries) do
        if CollectionCatalog.is_entry_discovered(game, entry) then
            discovered = discovered + 1
        end
    end
    return { discovered = discovered, total = total }
end

function CollectionCatalog.get_category_def(category_id)
    for _, cat in ipairs(CollectionCatalog.CATEGORIES) do
        if cat.id == category_id then return cat end
    end
    return nil
end

return CollectionCatalog
