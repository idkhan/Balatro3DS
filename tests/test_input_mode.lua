--- Touch and buttons are two HID modes, and only one of them owns the focus at a time.
---
--- The reference keeps a single "last device used" flag and drops `focused.target` the moment
--- the pointer takes over (`reference/Balatro/engine/controller.lua:136-175`), so a mouse player
--- never sees the controller's `snap_to` land on anything. This port's equivalent is
--- `Game:note_input_mode`: while the finger is driving, nothing is focused until it is touched,
--- and the press that takes focus back does not also act on it.
local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

local function game_with_hand(seed)
    local g = bootstrap.new_game(seed)
    g.STATE = g.STATES.SELECTING_HAND
    g._gamepad_focus_layer = "hand"
    local hand = Hand(g)
    g.hand = hand
    hand:add_card({ rank = 10, suit = "Spades" })
    hand:add_card({ rank = 4, suit = "Hearts" })
    hand:add_card({ rank = 7, suit = "Clubs" })
    g:ensure_dpad_cursor()
    return g
end

--- Which hand cards actually put a tooltip on screen for one frame. `draw_tooltip_overlay` is
--- offered to every node and filters itself, so the count that matters is the body below it.
local function drawn_hand_tooltips(g)
    local drawn = {}
    for _, node in ipairs(g.hand.card_nodes) do
        node.draw_tooltip = function(self) drawn[#drawn + 1] = self end
    end
    g:draw_tooltips_on_top()
    return drawn
end

suite.test("a freshly dealt hand shows no tooltip while the finger is driving", function()
    local g = game_with_hand(9101)
    g:note_input_mode("touch")

    T.assert_false(g:gamepad_focus_visible(), "touch hides the focus outline")
    T.assert_eq(#drawn_hand_tooltips(g), 0, "and no card volunteers a tooltip")
end)

suite.test("the same hand shows the cursor's tooltip on buttons", function()
    local g = game_with_hand(9102)
    g:note_input_mode("gamepad")

    local drawn = drawn_hand_tooltips(g)
    T.assert_eq(#drawn, 1, "exactly the cursor card draws")
    T.assert_eq(drawn[1], g:dpad_cursor_node(), "and it is the one under the cursor")
end)

suite.test("on touch the tapped card owns the tooltip", function()
    local g = game_with_hand(9103)
    g:note_input_mode("touch")
    local node = g.hand.card_nodes[2]

    g.hand:toggle_selection(node)
    T.assert_eq(g.active_tooltip_card, node, "picking a card shows that card")
    local drawn = drawn_hand_tooltips(g)
    T.assert_eq(#drawn, 1, "and only that card")
    T.assert_eq(drawn[1], node, "the tapped one")

    g.hand:toggle_selection(node)
    T.assert_eq(g.active_tooltip_card, nil, "unpicking takes it away again")
end)

suite.test("on buttons the selection does not fight the cursor for the tooltip", function()
    local g = game_with_hand(9104)
    g:note_input_mode("gamepad")

    g.hand:toggle_selection(g.hand.card_nodes[2])
    T.assert_eq(g.active_tooltip_card, nil, "the d-pad cursor keeps the tooltip")
end)

--------------------------------------------------------------------------------
-- Booster packs
--------------------------------------------------------------------------------

local function booster_offer()
    return {
        kind = "booster",
        pack = "standard",
        size = "normal",
        card_count = 3,
        picks_granted = 1,
        booster_sprite_index = 2,
    }
end

local function open_pack(g)
    g.STATE = g.STATES.SHOP
    g:begin_booster_session(booster_offer())
    for _ = 1, 200 do
        g:_update_booster_opening(1 / 30)
        if g.booster_session.opening_phase == "ready" then break end
    end
    g.STATE = g.STATES.OPEN_BOOSTER
    g:init_booster_gamepad_nav()
end

suite.test("a pack opened by touch highlights nothing", function()
    local g = bootstrap.new_game(9105)
    g:note_input_mode("touch")
    open_pack(g)

    T.assert_eq(g.booster_session.active_choice_index, nil, "no choice is preselected")
end)

suite.test("a pack opened by buttons highlights its first choice", function()
    local g = bootstrap.new_game(9106)
    g:note_input_mode("gamepad")
    open_pack(g)

    T.assert_eq(g.booster_session.active_choice_index, 1, "the leftmost untaken choice takes focus")
end)

suite.test("picking the buttons back up restores the pack's focus", function()
    local g = bootstrap.new_game(9107)
    g:note_input_mode("touch")
    open_pack(g)
    g._gamepad_focus_layer = "booster"

    g:note_input_mode("gamepad")
    T.assert_eq(g.booster_session.active_choice_index, 1, "focus comes back on the first button press")
end)

--------------------------------------------------------------------------------
-- The press that takes focus back
--------------------------------------------------------------------------------

suite.test("the first press after touch restores focus instead of acting on it", function()
    local g = game_with_hand(9108)
    g:note_input_mode("touch")

    T.assert_true(g:consumes_focus_restore_press("a"), "confirm would pick an unseen card")
    T.assert_true(g:consumes_focus_restore_press("dpleft"), "a direction would step off an unseen card")
    T.assert_false(g:consumes_focus_restore_press("y"), "play acts on the selection, which is visible")
    T.assert_false(g:consumes_focus_restore_press("x"), "so does discard")
    T.assert_false(g:consumes_focus_restore_press("start"), "pause is not a focus button")

    g:note_input_mode("gamepad")
    T.assert_false(g:consumes_focus_restore_press("a"), "and once focus is visible nothing is swallowed")
end)

suite.test("cancel is only swallowed where it acts on the focused item", function()
    local g = game_with_hand(9109)
    g:note_input_mode("touch")
    T.assert_false(g:consumes_focus_restore_press("b"), "in the hand cancel deselects and sorts")

    g._gamepad_focus_layer = "jokers"
    T.assert_true(g:consumes_focus_restore_press("b"), "on the joker row it sells the focused joker")
end)

suite.test("states without a hidden focus target swallow nothing", function()
    local g = game_with_hand(9110)
    g:note_input_mode("touch")
    g.STATE = g.STATES.MENU
    T.assert_false(g:consumes_focus_restore_press("a"), "the menu draws its own highlight")

    g.STATE = g.STATES.PAUSED
    T.assert_false(g:consumes_focus_restore_press("a"), "and so does the pause panel")
end)

return suite
