---@class Tag
Tag = Object:extend()

--- 0-1 roll for cue pitch jitter. Kept off `math.random`, which is reseeded per run
--- for reproducibility and must not be consumed by audio.
local function sfx_jitter()
    if love and love.math and love.math.random then return love.math.random() end
    return 0.5
end

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
    -- Prefer the atlas's declared column count. On hardware a t3x reports its padded runtime
    -- width rather than the source PNG's, so deriving columns from the image is right on
    -- desktop and wrong on a 3DS - tags.png is 340 px wide but pads to 512, which would read
    -- as 15 columns instead of 10 and pull every tag's sprite from the wrong cell. Same trap
    -- `consumable_compute_quad` documents.
    local cols = tonumber(atlas.cols) or math.floor(iw / cell_w)
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

--- Tags whose config type is `new_blind_choice` in the reference (`game.lua:233-240`): the
--- five that hand out a free booster pack, plus Boss Tag. They do not fire the moment they
--- are earned - the reference only runs them when a blind-select screen is built, one per
--- screen (`reference/Balatro/game.lua:3290-3294`). Firing one mid-skip opened its pack
--- before the skip had advanced the blind, so the pack's return state and the blind it came
--- back to disagreed.
Tag.NEW_BLIND_CHOICE_TYPES = {
    standard = true,
    charm = true,
    meteor = true,
    buffoon = true,
    ethereal = true,
    boss = true,
}

--- Fire the tag's effect and, if it actually did something, play the activation cue.
--- Tags that return false are stored for later instead, and stay silent here so a
--- run reloaded from a snapshot does not replay a cue for every tag it restores.
---@param context string|nil "new_blind_choice" when called from the blind-select screen
function Tag:Use(context)
    local fired = self:apply(context) and true or false
    if fired and Sfx and Sfx.play then
        -- Reference `tag.lua:78-79`.
        Sfx.play("generic1", 0.9 + sfx_jitter() * 0.1, 0.8)
        Sfx.play("holo1", 1.2 + sfx_jitter() * 0.1, 0.4)
    end
    return fired
end

---@param context string|nil
function Tag:apply(context)
    --Tags that are used should fire and return true
    -- Pack and Boss Tags wait for a blind-select screen; until then they sit in the tray.
    if Tag.NEW_BLIND_CHOICE_TYPES[self.type] and context ~= "new_blind_choice" then
        return false
    end
    if self.type == "economy" then
        if G and type(G) == "table" and type(G.money) == "number" then
            -- Doubles the balance, capped at a $40 gain: the reference adds
            -- `min(config.max, max(0, dollars))` (`tag.lua:184`, `max = 40`). Adding
            -- `min(money*2, 40)` tripled it, and went the wrong way while in debt.
            G.money = G.money + math.min(math.max(0, G.money), 40)
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
            -- Mega Buffoon exposes four choices, matching normal pack definitions (reference game.lua:693-696).
            G:begin_booster_session({
                kind = "booster",
                pack = "buffoon",
                size = "mega",
                price = 0,
                name = "Mega Buffoon Pack",
                card_count = 4,
                picks_granted = 2,
            })
        end
        return true
    elseif self.type == "ethereal" then
        if G and G.begin_booster_session then
            -- A plain Spectral Pack: the reference hardcodes `p_spectral_normal_1`
            -- (`tag.lua:239-241`), whose config is `{extra = 2, choose = 1}`
            -- (`game.lua:681`). This was granting a Mega — double the cards and picks.
            G:begin_booster_session({
                kind = "booster",
                pack = "spectral",
                size = "normal",
                price = 0,
                name = "Spectral Pack",
                card_count = 2,
                picks_granted = 1,
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
                local id = G:random_joker_def_id_by_rarity(1, "buffoon")
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
                -- Three levels at once, shown the same way a Planet's one level is: the
                -- reference runs Orbital through `update_hand_text` and `level_up_hand` with
                -- `levels = 3` (`reference/Balatro/tag.lua:191-198`). Skipping the readout here
                -- would make the strongest hand upgrade in the game the quietest.
                local from_level, from_chips, from_mult = G:get_hand_display_stats(idx)
                for _ = 1, 3 do
                    G:upgrade_hand_level_at_index(idx)
                end
                local to_level, to_chips, to_mult = G:get_hand_display_stats(idx)
                if G.begin_hand_levelup_flourish then
                    G:begin_hand_levelup_flourish(G.handlist and G.handlist[idx] or "",
                        from_level, from_chips, from_mult,
                        to_level, to_chips, to_mult)
                end
            end
        end
        return true
    elseif self.type == "handy" then
        if G and G.handsPlayed and G.money then
            G.money = G.money + G.handsPlayed
        end
        return true
    elseif self.type == "garbage" then
        if G and type(G.money) == "number" then
            -- Garbage pays for all prior unused discards immediately (reference tag.lua:158-165).
            G.money = G.money + math.max(0, tonumber(G.discardsUnused) or 0)
        end
        return true
    elseif self.type == "speed" then
        if G and G.skipsTaken and G.money then
            G.money = G.money + G.skipsTaken * 5
        end
        return true
    elseif self.type == "boss" then
        G:roll_boss_blind({ exclude_current = true })
        -- Consumed on use like every other immediate tag. Returning false stored it in the
        -- tag list forever, and because tags are re-applied when a run is loaded
        -- (`game.lua` restore), every save/load re-rolled the boss for free.
        return true
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
    ethereal = "Open a free Spectral Pack",
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
