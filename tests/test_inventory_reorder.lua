--- Moving jokers around the bottom row. A reorder used to change run state and then teleport
--- every node onto its new slot, which reads as a jump cut rather than as the neighbours
--- stepping aside.
local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

--- Three jokers laid out on the bottom screen, each sitting exactly on its slot.
local function bottom_row(g)
    g:add_joker_by_def("j_joker")
    g:add_joker_by_def("j_greedy_joker")
    g:add_joker_by_def("j_baron")
    g.jokers_on_bottom = true
    g:_apply_joker_layout()
    for _, j in ipairs(g.jokers) do
        j.VT.x, j.VT.y, j.VT.scale = j.T.x, j.T.y, j.T.scale
    end
    return g.jokers
end

local function ids(g)
    local out = {}
    for i, j in ipairs(g.jokers) do out[i] = j.def and j.def.id end
    return table.concat(out, ",")
end

suite.test("a reordered joker row springs rather than teleporting", function()
    local g = bootstrap.new_game(5001)
    bottom_row(g)
    local moved = g.jokers[3]
    local before_vt = moved.VT.x

    T.assert_true(g:move_joker_to_index(3, 1), "the move lands")
    T.assert_eq(ids(g), "j_baron,j_joker,j_greedy_joker", "the order changed")
    T.assert_eq(moved.VT.x, before_vt, "the node has not jumped to its new slot")
    T.assert_true(moved.T.x < before_vt, "but it is now targeting one")
end)

suite.test("dragging a joker past a neighbour reorders it under the finger", function()
    local g = bootstrap.new_game(5002)
    local jokers = bottom_row(g)
    local dragged = jokers[1]
    local original = ids(g)

    -- Still over its own slot: nothing to do.
    T.assert_false(g:update_joker_drag_reorder(dragged), "no move while it is home")
    T.assert_eq(ids(g), original)

    -- Carry it over the far slot.
    dragged.VT.x = g.jokers[3].T.x
    T.assert_true(g:update_joker_drag_reorder(dragged), "crossing a slot reorders")
    T.assert_eq(ids(g), "j_greedy_joker,j_baron,j_joker", "it landed at the end")
    T.assert_eq(g.jokers[3], dragged)
    -- The reorder is idempotent while the finger stays put.
    T.assert_false(g:update_joker_drag_reorder(dragged), "and does not thrash")
end)

return suite
