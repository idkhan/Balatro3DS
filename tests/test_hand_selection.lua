--- Selecting and deselecting hand cards. The lift is a target, not a draw-time offset, so
--- anything that changes the selection has to retarget the fan or the board and the run state
--- drift apart.
local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

suite.test("clearing a selection drops the cards back out of the lift", function()
    local g = bootstrap.new_game(5003)
    local hand = Hand(g)
    g.hand = hand
    hand:add_card({ rank = 10, suit = "Spades" })
    hand:add_card({ rank = 4, suit = "Hearts" })
    local node = hand.card_nodes[1]
    local resting_y = node.T.y

    hand:toggle_selection(node)
    T.assert_true(node.T.y < resting_y, "a selected card is lifted")

    hand:clear_selection()
    T.assert_false(node.selected, "the run state deselected it")
    T.assert_eq(node.T.y, resting_y, "and the card is targeting the fan again")
end)

return suite
