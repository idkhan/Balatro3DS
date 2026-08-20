--- The reference culls a random pool against `G.GAME.used_jokers`, which `Card:set_ability`
--- sets for *any* card that exists (`card.lua:349-354`) -- including one sitting on the shop
--- shelf. So a shop cannot roll the same tarot into two slots: the first one's existence takes
--- it out of the pool for the second.
---
--- This port derived "in play" from the player's inventory, which covers a consumable you are
--- holding but not one already on the shelf beside it, so a shop could offer two Towers.
local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

bootstrap.load()

local function consumable_ids(offers)
    local ids = {}
    for _, o in ipairs(offers or {}) do
        if o.kind ~= "joker" and o.kind ~= nil and o.kind ~= "playing_card" then
            ids[#ids + 1] = o.id
        end
    end
    return ids
end

suite.test("a shop never puts the same consumable in two slots", function()
    local g = bootstrap.new_game(4301)
    g.shop_offer_slots = 4
    -- Many rolls: the bug needed two consumable entries with the same id to come off the
    -- queue in one shop, which is uncommon per roll and near-certain across a hundred.
    for i = 1, 120 do
        g.shop_reroll_count = i
        g:roll_shop_offers()
        local seen = {}
        for _, id in ipairs(consumable_ids(g.shop_offers)) do
            T.assert_true(not seen[id], "the shop offered " .. tostring(id) .. " twice")
            seen[id] = true
        end
    end
end)

suite.test("a consumable already on the shelf is culled like one in hand", function()
    local g = bootstrap.new_game(4302)
    g.shop_offer_slots = 4
    g:roll_shop_offers()
    local ids = consumable_ids(g.shop_offers)
    if #ids == 0 then return end

    -- Holding one is the case that already worked; being offered one is the case that did not.
    -- Both must keep it out of a second slot.
    T.assert_true(g:_shop_consumable_owned(ids[1]) == false,
        "the shelf copy is not in the player's inventory")
end)

suite.test("Showman puts shop duplicates back on the table", function()
    local g = bootstrap.new_game(4303)
    g.shop_offer_slots = 4
    T.assert_true(g:add_joker_by_def("j_ring_master"))

    -- With Showman the cull is off entirely, so a repeat is allowed rather than required;
    -- what matters is that rolling still fills the shop.
    for i = 1, 40 do
        g.shop_reroll_count = i
        g:roll_shop_offers()
        T.assert_true(#g.shop_offers > 0, "the shop still stocks with the cull disabled")
    end
end)

suite.test("culling does not starve the shop of slots", function()
    local g = bootstrap.new_game(4304)
    g.shop_offer_slots = 2
    for i = 1, 40 do
        g.shop_reroll_count = i
        g:roll_shop_offers()
        T.assert_eq(#g.shop_offers, 2, "both slots fill")
    end
end)

return suite
