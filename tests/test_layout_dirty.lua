--- Per-frame layout work that only re-runs when its inputs change.
---
--- `_apply_consumable_layout` ran from both Game:draw and TopUI:draw every frame, and
--- `sync_shop_offer_interactivity` rewrote three node lists' states from Game:draw in
--- every state. Both are pure functions of state that mutates rarely, so both now sit
--- behind an invalidation: a dirty flag for the layout, a generation-plus-booleans memo
--- for the shop states. These tests pin the invalidation points, because a missed one
--- is a stale row that only shows up on device.

local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

bootstrap.load()

local function count_layout_calls(g)
    local calls = 0
    local real = g._apply_consumable_layout
    g._apply_consumable_layout = function(self)
        calls = calls + 1
        return real(self)
    end
    return function() return calls end
end

suite.test("draw_consumables_row lays out once, then skips until dirtied", function()
    local g = bootstrap.new_game(9001)
    g:add_consumable("tarot_magician")
    T.assert_eq(g._consumable_layout_dirty, false,
        "add_consumable already applied the layout, so the row starts clean")
    local calls = count_layout_calls(g)

    g:recompute_consumable_slot_layout()
    g:draw_consumables_row()
    T.assert_eq(calls(), 1, "the first draw after a dirtying applies the layout")
    g:draw_consumables_row()
    g:draw_consumables_row()
    T.assert_eq(calls(), 1, "clean frames skip it")
end)

suite.test("every consumable mutation re-dirties the layout", function()
    local g = bootstrap.new_game(9002)
    g:add_consumable("tarot_magician")
    g:draw_consumables_row()

    T.assert_true(g:add_consumable("planet_pluto"), "second consumable added")
    T.assert_eq(g._consumable_layout_dirty, false,
        "add_consumable applies the layout on the spot")

    local calls = count_layout_calls(g)
    g:remove_consumable_at(2)
    T.assert_true(calls() >= 1, "removal re-lays out before the next frame")
end)

suite.test("reorder and location changes re-dirty the layout", function()
    local g = bootstrap.new_game(9003)
    g:add_consumable("tarot_magician")
    g:add_consumable("planet_pluto")
    g:draw_consumables_row()
    T.assert_eq(g._consumable_layout_dirty, false, "starts clean")

    g.consumables_on_bottom = true
    g._consumable_focus_index = 1
    T.assert_true(g:consumable_reorder_gamepad_step(1), "gamepad reorder succeeds")
    T.assert_eq(g._consumable_layout_dirty, false,
        "reorder dirties and immediately reapplies via draw_consumables_row")
    T.assert_eq(g.consumables[2].id, "tarot_magician", "order actually changed")

    g.consumables_on_bottom = false
    g:recompute_consumable_slot_layout()
    T.assert_true(g._consumable_layout_dirty,
        "recompute_consumable_slot_layout leaves the layout dirty for the draw path")
end)

suite.test("shop interactivity memo skips clean frames and wakes on a state flip", function()
    local g = bootstrap.new_game(9004)
    g.STATE = g.STATES.SHOP
    g.shop_offer_nodes = {
        { states = { visible = false, click = { can = false }, drag = { can = false } } },
    }
    g._shop_nodes_gen = (g._shop_nodes_gen or 0) + 1

    g:sync_shop_offer_interactivity()
    local node = g.shop_offer_nodes[1]
    T.assert_true(node.states.visible, "shop state makes the offer visible")

    -- A clean second call must not rewrite states: poison one and confirm it survives.
    node.states.visible = "poisoned"
    g:sync_shop_offer_interactivity()
    T.assert_eq(node.states.visible, "poisoned", "memo-hit frame writes nothing")

    g.STATE = g.STATES.PLAYING
    g:sync_shop_offer_interactivity()
    T.assert_eq(node.states.visible, false, "leaving the shop resyncs and hides the node")
end)

suite.test("rebuilding a shop node list busts the memo", function()
    local g = bootstrap.new_game(9005)
    g.STATE = g.STATES.SHOP
    g.shop_offer_nodes = {}
    g:sync_shop_offer_interactivity()

    local node = { states = { visible = false, click = { can = false }, drag = { can = false } } }
    g.shop_offer_nodes[1] = node
    g._shop_nodes_gen = (g._shop_nodes_gen or 0) + 1
    g:sync_shop_offer_interactivity()
    T.assert_true(node.states.visible, "a bumped generation resyncs the new node")
end)

return suite
