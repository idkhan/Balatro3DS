--- Stakes are cumulative: a Blue Stake run also carries Red, Green and Black. The reference
--- lists the inherited ones under "Also applied:" (`UI_definitions.lua:3181-3204`); the port
--- showed only the selected stake's own line, hiding most of what the run was running.
local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

bootstrap.load()
local DeckViewUI = require("deck_view_ui")

suite.test("White Stake inherits nothing", function()
    T.assert_eq(#DeckViewUI.inherited_stake_descriptions("stake_white"), 0)
end)

suite.test("Red Stake inherits nothing but itself", function()
    -- Red is order 2, and White (order 1) carries no modifier worth listing.
    T.assert_eq(#DeckViewUI.inherited_stake_descriptions("stake_red"), 0)
end)

suite.test("a higher stake lists every lower stake's modifier, nearest first", function()
    local green = DeckViewUI.inherited_stake_descriptions("stake_green")
    T.assert_eq(#green, 1, "Green inherits Red")
    T.assert_eq(green[1], STAKE_DEFS_BY_ID.stake_red.description)

    local blue = DeckViewUI.inherited_stake_descriptions("stake_blue")
    T.assert_eq(#blue, 3, "Blue inherits Red, Green and Black")
    T.assert_eq(blue[1], STAKE_DEFS_BY_ID.stake_black.description, "nearest stake first")
    T.assert_eq(blue[3], STAKE_DEFS_BY_ID.stake_red.description, "furthest last")

    -- The top stake inherits all six below it.
    T.assert_eq(#DeckViewUI.inherited_stake_descriptions("stake_gold"), 6)
end)

suite.test("an unknown stake id is handled without raising", function()
    T.assert_eq(#DeckViewUI.inherited_stake_descriptions("stake_nonexistent"), 0)
    T.assert_eq(#DeckViewUI.inherited_stake_descriptions(nil), 0)
end)

return suite
