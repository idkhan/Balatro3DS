---@class Tag
Tag = Object:extend()

local function resolve_atlas(name)
    if not name or not G or not G.ASSET_ATLAS then return nil end
    if G.ensure_asset_atlas_loaded then
        G:ensure_asset_atlas_loaded(name)
    end
    return G.ASSET_ATLAS[name]
end

local function compute_quad(atlas, index)
    if not atlas or not atlas.image or index == nil then return nil, 0, 0 end
    local iw, ih = atlas.image:getDimensions()
    local cell_w, cell_h = atlas.px, atlas.py
    if not cell_w or not cell_h or cell_w <= 0 or cell_h <= 0 then
        return nil, 0, 0
    end
    local cols = math.floor(iw / cell_w)
    if cols <= 0 then return nil, 0, 0 end
    local col = index % cols
    local row = math.floor(index / cols)
    local sx = col * cell_w
    local sy = row * cell_h
    local quad = love.graphics.newQuad(sx, sy, cell_w, cell_h, iw, ih)
    return quad, cell_w, cell_h
end

function Tag:init(type, x, y)
    self.type = type
    self.X = x or 0
    self.Y = y or 0
    if self.type == "uncommon" then
        self.id = 0
    elseif self.type == "rare" then
        self.id = 1
    elseif self.type == "negative" then
        self.id = 2
    elseif self.type == "foil" then
        self.id = 3
    elseif self.type == "holo" then
        self.id = 6
    elseif self.type == "polychrome" then
        self.id = 7
    elseif self.type == "investment" then
        self.id = 8
    elseif self.type == "voucher" then
        self.id = 9
    elseif self.type == "boss" then
        self.id = 12
    elseif self.type == "standard" then
        self.id = 13
    elseif self.type == "charm" then
        self.id = 14
    elseif self.type == "meteor" then
        self.id = 15
    elseif self.type == "buffoon" then
        self.id = 16
    elseif self.type == "handy" then
        self.id = 19
    elseif self.type == "garbage" then
        self.id = 20
    elseif self.type == "ethereal" then
        self.id = 21
    elseif self.type == "coupon" then
        self.id = 4
    elseif self.type == "double" then
        self.id = 5
    elseif self.type == "juggle" then
        self.id = 11
    elseif self.type == "d6" then
        self.id = 23
    elseif self.type == "topup" then
        self.id = 10
    elseif self.type == "speed" then
        self.id = 18
    elseif self.type == "orbital" then
        self.id = 17
    elseif self.type == "economy" then
        self.id = 22
    else 
        self.id = -1
    end

    self.atlas_name = "tags"
    self.atlas = resolve_atlas(self.atlas_name)
    self.quad, self.w, self.h = compute_quad(self.atlas, self.id)
end

function Tag:draw()
    local atlas = self.atlas or resolve_atlas(self.atlas_name)
    local quad = self.quad
    local w, h = self.w, self.h
    if not quad then
        quad, w, h = compute_quad(atlas, self.id)
    end

    local x = tonumber(self.X) or 0
    local y = tonumber(self.Y) or 0

    love.graphics.push()
    if atlas and atlas.image and quad then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(atlas.image, quad, x, y, 0, 1, 1)
    else
        love.graphics.setColor(0.9, 0.2, 0.2, 0.8)
        love.graphics.rectangle("line", x, y, (w > 0 and w) or 34, (h > 0 and h) or 34)
    end
    love.graphics.pop()
end

function Tag:setPosition(x, y)
    self.X = x
    self.Y = y
end

function Tag:Use()
    --Tags that are used should fire and return true
    if self.type == "economy" then
        if G and type(G) == "table" and type(G.money) == "number" then
            G.money = G.money + math.min(G.money * 2, 40)
        end
        return true
    

    elseif self.type == "standard" then
        if G and G.begin_booster_session then
            G:begin_booster_session({
                kind = "booster",
                pack = "standard",
                size = "mega",
                price = 0,
                name = "Mega Standard Pack",
                card_count = 5,
                picks_granted = 2,
            })
        end
        return true
    

    elseif self.type == "charm" then
        if G and G.begin_booster_session then
            G:begin_booster_session({
                kind = "booster",
                pack = "arcana",
                size = "mega",
                price = 0,
                name = "Mega Arcana Pack",
                card_count = 5,
                picks_granted = 2,
            })
        end
        return true
    elseif self.type == "buffoon" then
        if G and G.begin_booster_session then
            G:begin_booster_session({
                kind = "booster",
                pack = "buffoon",
                size = "mega",
                price = 0,
                name = "Mega Buffoon Pack",
                card_count = 5,
                picks_granted = 2,
            })
        end
        return true
    elseif self.type == "ethereal" then
        if G and G.begin_booster_session then
            G:begin_booster_session({
                kind = "booster",
                pack = "spectral",
                size = "mega",
                price = 0,
                name = "Mega Spectral Pack",
                card_count = 5,
                picks_granted = 2,
            })
        end
        return true
    elseif self.type == "meteor" then
        if G and G.begin_booster_session then
            G:begin_booster_session({
                kind = "booster",
                pack = "celestial",
                size = "mega",
                price = 0,
                name = "Mega Celestial Pack",
                card_count = 5,
                picks_granted = 2,
            })
        end
        return true
    elseif self.type == "topup" then
        if G and G.joker_has_room_for_new and G.add_joker_by_def and G.random_joker_def_id_by_rarity then
            for _ = 1, 2 do
                if not G:joker_has_room_for_new() then break end
                local id = G:random_joker_def_id_by_rarity(1)
                if not id then break end
                G:add_joker_by_def(id)
            end
        end
        return true
    elseif self.type == "orbital" then
        if G and G.upgrade_hand_level_at_index then
            local idx = tonumber(self.orbital_hand_index)
            if not idx and G.roll_orbital_hand_index then
                idx = G:roll_orbital_hand_index()
            end
            if idx then
                for _ = 1, 3 do
                    G:upgrade_hand_level_at_index(idx)
                end
            end
        end
        return true
    elseif self.type == "handy" then
        if G and G.handsPlayed and G.money then
            G.money = G.money + G.handsPlayed
            Sfx.play_money()
        end
        return true
    elseif self.type == "speed" then
        if G and G.skipsTaken and G.money then
            G.money = G.money + G.skipsTaken * 5
            Sfx.play_money()
        end
        return true
    elseif self.type == "boss" then
        G:roll_boss_blind({ exclude_current = true })
    end

    return false
end

Tag.DESCRIPTIONS = {
    uncommon = "Gives a free Uncommon Joker in the next Shop",
    rare = "Gives a free Rare Joker in the next Shop",
    negative = "Next base-edition Joker in the Shop is Negative",
    foil = "Next base-edition Joker in the Shop is Foil",
    holo = "Next base-edition Joker in the Shop is Holographic",
    polychrome = "Next base-edition Joker in the Shop is Polychrome",
    investment = "Earn $25 at end of the Boss Blind",
    voucher = "Adds a Voucher to the next Shop",
    boss = "Reroll the Boss Blind",
    standard = "Open a Mega Standard Pack",
    charm = "Open a Mega Arcana Pack",
    meteor = "Open a Mega Celestial Pack",
    buffoon = "Open a Mega Buffoon Pack",
    handy = "Earn $1 for each hand played this run",
    garbage = "Earn $1 for each unused discard this run",
    ethereal = "Open a Mega Spectral Pack",
    coupon = "All initial items are free in the next Shop",
    double = "Gives a copy of the next selected Tag",
    juggle = "+3 hand size next round",
    d6 = "Shop rerolls start at $0 next Shop",
    topup = "Create up to 2 Common Jokers (Must have room)",
    speed = "Earn $5 for each skipped Blind this run",
    orbital = "Upgrade a poker hand by 3 levels",
    economy = "Double money (Max of $40)",
}

function Tag.get_description(type_name, hand_name)
    if type(type_name) ~= "string" then return "" end
    if type_name == "orbital" and type(hand_name) == "string" and hand_name ~= "" then
        return "Upgrade " .. hand_name .. " by 3 levels"
    end
    return Tag.DESCRIPTIONS[type_name] or ""
end
