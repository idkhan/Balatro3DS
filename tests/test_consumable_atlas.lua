--- Consumable definitions must stay aligned with the packed Tarots atlas.

local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

suite.test("maps planets and spectral cards to their packed atlas cells", function()
    bootstrap.load()

    local expected = {
        planet_eris = 23, planet_ceres = 28, planet_x = 29, planet_mercury = 30,
        planet_venus = 31, planet_earth = 32, planet_mars = 33, planet_jupiter = 34,
        planet_saturn = 35, planet_uranus = 36, planet_neptune = 37, planet_pluto = 38,
        spectral_black_hole = 39, spectral_familiar = 40, spectral_grim = 41,
        spectral_incantation = 42, spectral_talisman = 43, spectral_aura = 44,
        spectral_wraith = 45, spectral_sigil = 46, spectral_ouija = 47,
        spectral_ectoplasm = 48, spectral_immolate = 49, spectral_ankh = 50,
        spectral_deja_vu = 51, spectral_hex = 52, spectral_trance = 53,
        spectral_medium = 54, spectral_cryptid = 55, spectral_soul = 22,
    }

    for id, index in pairs(expected) do
        T.assert_eq(CONSUMABLE_DEFS[id].index, index, id)
    end
end)

suite.test("loads each consumable from a power-of-two sprite", function()
    local game = bootstrap.new_game(99)
    -- The cache is module-scoped and other suites leave cards standing, so start clean.
    Consumable.release_all_sprites()
    for id, index in pairs({
        tarot_fool = 0,
        planet_venus = 31,
        planet_earth = 32,
        planet_uranus = 36,
        planet_pluto = 38,
        spectral_soul = 22,
    }) do
        local card = Consumable(0, 0, CONSUMABLE_DEFS[id])
        game:add(card)
        T.assert_eq(card.atlas.path,
            string.format("resources/textures/1x/Consumables/%03d.png", index), id)
        local x, y, w, h = card.quad:getViewport()
        T.assert_eq(x, 0, id .. " x")
        T.assert_eq(y, 0, id .. " y")
        T.assert_eq(w, 64, id .. " width")
        T.assert_eq(h, 96, id .. " height")
        game:remove(card)
        -- Sprites are shared and refcounted now, so removal drops this card's reference
        -- rather than releasing an image it might not own alone.
        T.assert_eq(card.atlas, nil, id .. " released its sprite reference")
        local _, owners = Consumable.sprite_cache_stats(index)
        T.assert_eq(owners, 0, id .. " has no remaining owners")
    end
end)

--- The point of the cache: a five-card Arcana pack used to be five SD reads and five t3x
--- decodes in one frame, and duplicates each held their own copy of the same texture.
suite.test("cards of the same consumable share one sprite", function()
    local game = bootstrap.new_game(99)
    Consumable.release_all_sprites()
    local def = CONSUMABLE_DEFS.tarot_fool
    local index = def.index

    local a = Consumable(0, 0, def); game:add(a)
    local b = Consumable(0, 0, def); game:add(b)
    local c = Consumable(0, 0, def); game:add(c)

    T.assert_eq(a.atlas, b.atlas, "duplicates share one atlas entry")
    T.assert_eq(b.atlas, c.atlas, "and a third does too")
    local _, owners = Consumable.sprite_cache_stats(index)
    T.assert_eq(owners, 3, "three owners are counted")

    local shared_image = a.atlas.image
    game:remove(a)
    game:remove(b)
    T.assert_eq(c.atlas.image, shared_image, "the survivor still has its image")
    local _, still = Consumable.sprite_cache_stats(index)
    T.assert_eq(still, 1, "one owner left")

    game:remove(c)
    local _, none = Consumable.sprite_cache_stats(index)
    T.assert_eq(none, 0, "the last removal frees the sprite")
end)

--- `Game:remove` is the only release path but it can be reached twice for one node; the
--- refcount must not go negative and strand a live texture.
suite.test("releasing a card twice drops only one reference", function()
    local game = bootstrap.new_game(99)
    Consumable.release_all_sprites()
    local def = CONSUMABLE_DEFS.tarot_fool
    local a = Consumable(0, 0, def); game:add(a)
    local b = Consumable(0, 0, def); game:add(b)

    a:release_texture()
    a:release_texture()

    local _, owners = Consumable.sprite_cache_stats(def.index)
    T.assert_eq(owners, 1, "the double release cost only one reference")
    T.assert_true(b.atlas ~= nil and b.atlas.image ~= nil, "the other card keeps its sprite")
end)

--- The run teardown sweeps the cache, but a card can outlive it -- a dissolving node is
--- retained past the state change. Its later release must not decrement a count that now
--- belongs to a card acquired after the sweep, or that card's sprite is freed under it.
suite.test("a card that outlives the cache sweep cannot free a newer card's sprite", function()
    local game = bootstrap.new_game(99)
    Consumable.release_all_sprites()
    local def = CONSUMABLE_DEFS.tarot_fool

    local stale = Consumable(0, 0, def); game:add(stale)
    Consumable.release_all_sprites()

    local fresh = Consumable(0, 0, def); game:add(fresh)
    local fresh_image = fresh.atlas.image
    T.assert_true(fresh_image ~= nil, "the new card loaded a sprite")

    -- The stale card is torn down after the sweep.
    game:remove(stale)

    local _, owners = Consumable.sprite_cache_stats(def.index)
    T.assert_eq(owners, 1, "the stale release left the new card's count alone")
    T.assert_eq(fresh.atlas.image, fresh_image, "and did not free its sprite")

    game:remove(fresh)
    local _, none = Consumable.sprite_cache_stats(def.index)
    T.assert_eq(none, 0, "the real owner still releases normally")
end)

suite.test("ships base and negative sprites for every consumable", function()
    bootstrap.load()
    local root = os.getenv("BALATRO_ROOT") or "."
    for id, def in pairs(CONSUMABLE_DEFS) do
        for _, index in ipairs({ def.index, def.index + 56 }) do
            local path = string.format("%s/resources/textures/1x/Consumables/%03d.png", root, index)
            local file = io.open(path, "rb")
            T.assert_true(file ~= nil, id .. " missing " .. path)
            if file then
                local header = file:read(24)
                file:close()
                local function u32(offset)
                    local a, b, c, d = header:byte(offset, offset + 3)
                    return ((a * 256 + b) * 256 + c) * 256 + d
                end
                T.assert_eq(u32(17), 64, id .. " sprite width")
                T.assert_eq(u32(21), 128, id .. " sprite height")
            end
        end
    end
end)

suite.test("uses the packed negative consumable sprite offset", function()
    local game = bootstrap.new_game(99)
    local card = Consumable(0, 0, {
        id = "tarot_fool",
        kind = "tarot",
        atlas = "Tarot",
        index = 0,
        edition = "negative",
    })

    T.assert_eq(card.index, 56)
    T.assert_eq(card.atlas.path, "resources/textures/1x/Consumables/056.png")

    local lower_card = Consumable(0, 0, {
        id = "tarot_death",
        kind = "tarot",
        atlas = "Tarot",
        index = 13,
        edition = "negative",
    })

    T.assert_eq(lower_card.index, 69)
    T.assert_eq(lower_card.atlas.path, "resources/textures/1x/Consumables/069.png")
    game:remove(card)
    game:remove(lower_card)
end)

--- The reference's Planet text is four lines carrying the hand's level and the exact mult and
--- chips the card grants (`localization/en-us.lua:2335-2342`). The port showed one generic
--- line, so a Celestial pack gave the player nothing to choose on.
suite.test("a Planet tooltip names the level and the mult and chips it grants", function()
    local game = bootstrap.new_game(3301)
    -- Pair is handlist index 11; base 10/2, +15 chips and +1 mult per level.
    game.hand_stats[11].level = 3
    local card = Consumable(0, 0, CONSUMABLE_DEFS.planet_mercury)
    local lines = card:get_tooltip_body_lines()

    T.assert_eq(lines[1], "(lvl.3) Level up")
    T.assert_eq(lines[2], "Pair")
    T.assert_eq(lines[3], string.format("+%d mult and", game.hand_stats[11].mult_per_level))
    T.assert_eq(lines[4], string.format("+%d chips", game.hand_stats[11].chips_per_level))
    game:remove(card)
end)

--- The reference quotes Temperance's payout on the card itself -- "(Currently $12)" -- as its
--- second localisation variable (`functions/common_events.lua:2687-2696`). Without it the card
--- is worth an unknown amount until it is used.
suite.test("Temperance names what it would pay right now", function()
    local game = bootstrap.new_game(3303)
    local card = Consumable(0, 0, CONSUMABLE_DEFS.tarot_temperance)

    local lines = card:get_tooltip_body_lines()
    T.assert_eq(lines[#lines], "(Currently $0)", "no Jokers, nothing to sell")

    T.assert_true(game:add_joker_by_def("j_joker"))
    game.jokers[1].sell_cost = 3
    T.assert_true(game:add_joker_by_def("j_greedy_joker"))
    game.jokers[2].sell_cost = 4
    lines = card:get_tooltip_body_lines()
    T.assert_eq(lines[#lines], "(Currently $7)", "the sum of every Joker's sell value")
    T.assert_eq(game:temperance_payout(), 7, "and the payout agrees with the readout")

    game.jokers[1].sell_cost = 400
    T.assert_eq(card:get_tooltip_body_lines()[3], "(Currently $50)", "capped at the card's max")
    T.assert_eq(game:temperance_payout(), 50)
    game:remove(card)
end)

--- Every sticker the card draws needs a line; the reference queues one info box per badge
--- (`card.lua:938-943`). Only Perishable had one, so Eternal and Rental were unreadable.
suite.test("Eternal and Rental Jokers explain their stickers", function()
    local game = bootstrap.new_game(3302)
    local def
    for _, candidate in pairs(JOKER_DEFS) do
        if candidate and candidate.id then def = candidate break end
    end

    local eternal = Joker(0, 0, 70, 94, def, { eternal = true })
    local found = false
    for _, line in ipairs(eternal:get_tooltip_body_lines()) do
        if type(line) == "table" and tostring(line.text):find("Eternal", 1, true) then found = true end
    end
    T.assert_true(found, "an Eternal Joker says it cannot be sold")

    local rental = Joker(0, 0, 70, 94, def, { rental = true })
    found = false
    for _, line in ipairs(rental:get_tooltip_body_lines()) do
        if type(line) == "table" and tostring(line.text):find("Rental", 1, true) then found = true end
    end
    T.assert_true(found, "a Rental Joker says what it costs each round")
    T.assert_eq(rental.sell_cost, 1, "and a rental sells for its $1 cost")

    game:remove(eternal)
    game:remove(rental)
end)

return suite
