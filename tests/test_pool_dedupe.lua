--- Random pools cull whatever is already in play, and Showman turns that off.
--- Reference: `functions/common_events.lua:1987` (the cull), `card.lua:352` (what marks a
--- centre as in play), `common_events.lua:2038-2043` (the empty-pool fallback).
local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

local function planet_ids(g)
    local ids = {}
    for id, def in pairs(CONSUMABLE_DEFS) do
        if type(def) == "table" and def.kind == "planet" and g:planet_consumable_unlocked(id, def) then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids)
    return ids
end

suite.test("a consumable you are holding is not drawn again", function()
    local g = bootstrap.new_game()
    T.assert_true(g:add_consumable("planet_venus"))

    -- Drawn many times over: the held planet must never come back.
    for i = 1, 60 do
        local id = g:random_consumable_id_of_kind("planet", {}, "probe" .. i)
        T.assert_true(id ~= "planet_venus", "a held planet was offered again")
    end
end)

suite.test("The High Priestess cannot hand you the same planet twice", function()
    local g = bootstrap.new_game()
    g.STATE = g.STATES.SELECTING_HAND
    -- Enough room for both, which is the case the bug needed.
    T.assert_true(g:get_effective_consumable_capacity() >= 2)

    local first = g:random_consumable_id_of_kind("planet", {}, "high_priestess")
    T.assert_true(first ~= nil)
    T.assert_true(g:add_consumable(first))
    -- The second draw happens after the first is in hand, so the cull sees it.
    local second = g:random_consumable_id_of_kind("planet", {}, "high_priestess")
    T.assert_true(second ~= first, "the second planet duplicated the first")
end)

suite.test("Showman puts duplicates back in the pool", function()
    local g = bootstrap.new_game()
    T.assert_true(g:add_consumable("planet_venus"))
    T.assert_true(g:add_joker_by_def("j_ring_master"))

    local seen_venus = false
    for i = 1, 200 do
        if g:random_consumable_id_of_kind("planet", {}, "showman" .. i) == "planet_venus" then
            seen_venus = true
            break
        end
    end
    T.assert_true(seen_venus, "Showman should allow a held planet to be drawn again")
end)

suite.test("holding every planet falls back rather than drawing nothing", function()
    local g = bootstrap.new_game()
    -- Capacity is not the point here; force the whole pool into play.
    g.consumables = {}
    for _, id in ipairs(planet_ids(g)) do
        g.consumables[#g.consumables + 1] = { id = id, kind = "planet" }
    end

    local id = g:random_consumable_id_of_kind("planet", {}, "empty")
    T.assert_eq(id, "planet_pluto", "the reference's Planet fallback")
end)

suite.test("an explicit exclusion still beats the fallback", function()
    local g = bootstrap.new_game()
    g.consumables = {}
    for _, id in ipairs(planet_ids(g)) do
        g.consumables[#g.consumables + 1] = { id = id, kind = "planet" }
    end
    -- Asking for anything but the fallback, with nothing else available, yields nothing.
    T.assert_eq(g:random_consumable_id_of_kind("planet", { planet_pluto = true }, "x"), nil)
end)

suite.test("a booster pack does not offer what you already hold", function()
    local g = bootstrap.new_game()
    T.assert_true(g:add_consumable("planet_venus"))

    for _ = 1, 20 do
        local ids = g:_shop_pick_unique_consumable_ids("planet", 3, "pack")
        for _, id in ipairs(ids) do
            T.assert_true(id ~= "planet_venus", "a pack offered a planet already in hand")
        end
    end
end)

suite.test("a pack still fills when the cull would empty the pool", function()
    local g = bootstrap.new_game()
    g.consumables = {}
    for _, id in ipairs(planet_ids(g)) do
        g.consumables[#g.consumables + 1] = { id = id, kind = "planet" }
    end

    local ids = g:_shop_pick_unique_consumable_ids("planet", 3, "pack")
    T.assert_true(#ids > 0, "an empty pack is worse than a duplicate")
end)

suite.test("pool order does not depend on table iteration order", function()
    local g = bootstrap.new_game()
    -- Same seed and same stream name must give the same draw every time; `pairs` alone
    -- would not guarantee that.
    local a = bootstrap.new_game(4242):random_consumable_id_of_kind("tarot", {}, "det")
    local b = bootstrap.new_game(4242):random_consumable_id_of_kind("tarot", {}, "det")
    T.assert_eq(a, b)
    T.assert_true(a ~= nil)
end)

return suite
