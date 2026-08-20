--- A booster pack draws every slot from one pool, so no pack can show the same centre twice
--- unless Showman says otherwise. The reference gets this from `Card:set_ability` marking a
--- centre used the moment a pack card is created (`card.lua:352`), culled at
--- `common_events.lua:1987`.
local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

local function ids_of(choices)
    local out = {}
    for _, ch in ipairs(choices) do
        out[#out + 1] = ch.consumable_def and ch.consumable_def.id or ch.joker_id
    end
    return out
end

local function assert_unique(choices, what)
    local seen = {}
    for _, id in ipairs(ids_of(choices)) do
        T.assert_true(not seen[id], (what or "pack") .. " offered " .. tostring(id) .. " twice")
        seen[id] = true
    end
end

--- Run seeds have to be eight alphanumerics or `Game:normalize_run_seed` throws them away and
--- the run gets a generated one, which would make a sweep re-test one RNG stream.
local function seed(i) return string.format("PACK%04d", i) end

--- A mega pack of every consumable kind, opened over many seeds.
local function each_pack(fn)
    for _, pack in ipairs({ "arcana", "celestial", "spectral" }) do
        for i = 1, 40 do
            fn(pack, seed(i))
        end
    end
end

suite.test("no consumable pack repeats a card", function()
    each_pack(function(pack, seed)
        local g = bootstrap.new_game(seed)
        assert_unique(g:_booster_build_choices({ pack = pack, card_count = 5 }), pack)
    end)
end)

--- Telescope's planet follows the most-played hand, so pin the hand rather than the id.
local function with_telescope(run_seed, hand_index)
    local g = bootstrap.new_game(run_seed)
    g.vouchers = { "v_telescope" }
    g.hand_play_counts[hand_index] = 7
    local pref = g:_planet_consumable_id_for_most_played_hand()
    T.assert_true(pref ~= nil, "the fixture needs a most-played hand")
    return g, pref
end

suite.test("Telescope's guaranteed planet is not also drawn into a later slot", function()
    for i = 1, 40 do
        for hand_index = 1, 9 do
            local g, pref = with_telescope(seed(i), hand_index)
            local choices = g:_booster_build_choices({ pack = "celestial", card_count = 5 })
            T.assert_eq(#choices, 5)
            T.assert_eq(choices[1].consumable_def.id, pref, "Telescope must fill the first slot")
            assert_unique(choices, "a Telescope Celestial pack")
        end
    end
end)

suite.test("two Jupiters: Telescope cannot repeat its planet when the pool is tight", function()
    -- The reported case, made deterministic: cull the planet pool down to three, one of which
    -- Telescope then forces. Overwriting slot one instead of consuming the planet duplicates it.
    local keep = { planet_venus = true, planet_mars = true, planet_jupiter = true }
    local g, pref = with_telescope("PACKTGHT", 1)
    g.consumables = {}
    for id, def in pairs(CONSUMABLE_DEFS) do
        if type(def) == "table" and def.kind == "planet" and not keep[id] then
            g.consumables[#g.consumables + 1] = { id = id, kind = "planet" }
        end
    end
    -- Force Jupiter specifically, whatever hand it belongs to.
    g._planet_consumable_id_for_most_played_hand = function() return "planet_jupiter" end
    pref = "planet_jupiter"

    local choices = g:_booster_build_choices({ pack = "celestial", card_count = 3 })
    T.assert_eq(choices[1].consumable_def.id, pref)
    assert_unique(choices, "a tight Telescope Celestial pack")
end)

suite.test("Telescope with nothing played forces nothing", function()
    local g = bootstrap.new_game()
    g.vouchers = { "v_telescope" }
    -- The reference only takes a hand with `played > 0` (card.lua:1739).
    T.assert_eq(g:_planet_consumable_id_for_most_played_hand(), nil)
end)

suite.test("Omen Globe cannot put the same Spectral in two slots", function()
    for i = 1, 60 do
        local g = bootstrap.new_game(seed(i))
        g.vouchers = { "v_omen_globe" }
        assert_unique(g:_booster_build_choices({ pack = "arcana", card_count = 5 }), "an Omen Globe pack")
    end
end)

suite.test("Omen Globe's replacements share one Spectral pool", function()
    -- Cull the Spectral pool to two cards, so two Omen Globe hits in one pack land on the same
    -- card unless the hits share a pool. (One card would not do: a shared pool runs dry and the
    -- slot falls back to a Tarot, so the second hit never shows.)
    local found_two_hits = false
    for i = 1, 60 do
        local g = bootstrap.new_game(seed(i))
        g.vouchers = { "v_omen_globe" }
        g.consumables = {}
        for id, def in pairs(CONSUMABLE_DEFS) do
            if type(def) == "table" and def.kind == "spectral" and id ~= "spectral_aura"
                and id ~= "spectral_grim" and id ~= "spectral_soul" and id ~= "spectral_black_hole" then
                g.consumables[#g.consumables + 1] = { id = id, kind = "spectral" }
            end
        end
        local choices = g:_booster_build_choices({ pack = "arcana", card_count = 5 })
        local hits = 0
        for _, ch in ipairs(choices) do
            if ch.kind == "spectral" then hits = hits + 1 end
        end
        if hits >= 2 then found_two_hits = true end
        assert_unique(choices, "a two-Spectral Omen Globe pack")
    end
    T.assert_true(found_two_hits, "the fixture never produced two Omen Globe replacements")
end)

suite.test("a pack still fills every slot", function()
    each_pack(function(pack, seed)
        local g = bootstrap.new_game(seed)
        local choices = g:_booster_build_choices({ pack = pack, card_count = 5 })
        T.assert_eq(#choices, 5, pack .. " came up short")
    end)
end)

suite.test("Showman puts duplicates back into a pack", function()
    local seen_duplicate = false
    for i = 1, 60 do
        local g = bootstrap.new_game(seed(i))
        T.assert_true(g:add_joker_by_def("j_ring_master"))
        local choices = g:_booster_build_choices({ pack = "celestial", card_count = 5 })
        T.assert_eq(#choices, 5)
        local seen = {}
        for _, id in ipairs(ids_of(choices)) do
            if seen[id] then seen_duplicate = true end
            seen[id] = true
        end
    end
    T.assert_true(seen_duplicate, "Showman should eventually allow a repeat")
end)

suite.test("a pack does not offer a consumable already in hand", function()
    for i = 1, 30 do
        local g = bootstrap.new_game(seed(i))
        T.assert_true(g:add_consumable("planet_venus"))
        for _, id in ipairs(ids_of(g:_booster_build_choices({ pack = "celestial", card_count = 5 }))) do
            T.assert_true(id ~= "planet_venus", "a pack offered a held planet")
        end
    end
end)

suite.test("Black Hole you already hold is not rolled again", function()
    local g = bootstrap.new_game()
    T.assert_true(g:add_consumable("spectral_black_hole"))
    -- 0.3% per slot, so this is about the gate rather than the odds: 4000 slots without the
    -- cull would hit it many times over.
    for _ = 1, 800 do
        for _, id in ipairs(ids_of(g:_booster_build_choices({ pack = "celestial", card_count = 5 }))) do
            T.assert_true(id ~= "spectral_black_hole", "a held Black Hole came back")
        end
    end
end)

return suite
