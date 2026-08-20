--- L/R pull-down inventory panels: state gating, cashout behavior, slide feel.
local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

local function with_recorded_cues(fn)
    local original = Sfx.play
    local cues = {}
    Sfx.play = function(cue)
        cues[#cues + 1] = cue
        return true
    end
    local ok, err = pcall(fn, cues)
    Sfx.play = original
    if not ok then error(err, 0) end
end

local function has_cue(cues, wanted)
    for _, cue in ipairs(cues) do
        if cue == wanted then return true end
    end
    return false
end

local function game_with_joker(state)
    local g = bootstrap.new_game()
    T.assert_true(g:add_joker_by_def("j_joker"))
    if state then g.STATE = state end
    return g
end

suite.test("panels cannot be pulled down on pause, end-of-run, or menu screens", function()
    for _, state_name in ipairs({ "PAUSED", "GAME_OVER", "YOU_WIN", "MENU" }) do
        local g = game_with_joker()
        g.STATE = g.STATES[state_name]
        T.assert_false(g:toggle_jokers_pulled(), state_name .. " must block the joker panel")
        T.assert_false(g.jokers_on_bottom == true)
    end
end)

suite.test("shoulder presses are fully inert while the deck view is open", function()
    local g = game_with_joker()
    g.STATE = g.STATES.SELECTING_HAND
    T.assert_true(g:toggle_jokers_pulled())
    g._deck_view_open = true
    T.assert_false(g:toggle_jokers_pulled(), "must not close behind the deck view")
    T.assert_true(g.jokers_on_bottom == true)
end)

suite.test("jokers can be pulled down on the cashout screen, consumables cannot", function()
    local g = game_with_joker(nil)
    T.assert_true(g:add_consumable("tarot_fool"))
    g.STATE = g.STATES.ROUND_EVAL
    T.assert_true(g:toggle_jokers_pulled())
    T.assert_false(g:toggle_consumables_pulled(), "consumables are hidden on cashout")
    T.assert_false(g.consumables_on_bottom == true)
end)

suite.test("closing a panel is allowed even where opening is blocked", function()
    local g = bootstrap.new_game()
    T.assert_true(g:add_consumable("tarot_fool"))
    g.STATE = g.STATES.SELECTING_HAND
    T.assert_true(g:toggle_consumables_pulled())
    g.STATE = g.STATES.ROUND_EVAL
    T.assert_true(g:toggle_consumables_pulled(), "close must still work on cashout")
    T.assert_false(g.consumables_on_bottom == true)
end)

suite.test("entering the cashout screen closes a pulled-down consumable panel silently", function()
    local g = bootstrap.new_game()
    T.assert_true(g:add_consumable("tarot_fool"))
    g.STATE = g.STATES.SELECTING_HAND
    T.assert_true(g:toggle_consumables_pulled())
    g.emit_hand_cards_event = function() end
    with_recorded_cues(function(cues)
        g:enter_round_win_after_blind()
        T.assert_false(g.consumables_on_bottom == true)
        T.assert_false(has_cue(cues, "whoosh1"), "auto-close on cashout entry is silent")
    end)
    -- The blind now rings out for a payout-scaled beat before the cashout panel arrives
    -- (`Game:begin_blind_defeat`), so the state change lands on a later frame.
    T.assert_eq(g.STATE, g.STATES.SELECTING_HAND, "the defeat hold runs first")
    g:_update_blind_defeat(5)
    T.assert_eq(g.STATE, g.STATES.ROUND_EVAL)
end)

suite.test("pulled joker panel is d-pad navigable on the cashout screen", function()
    local g = game_with_joker()
    g.STATE = g.STATES.ROUND_EVAL
    T.assert_true(g:toggle_jokers_pulled())
    T.assert_eq(g:get_gamepad_focus_layer(), "jokers")
    T.assert_true(g:_gamepad_horizontal_nav_active())
end)

suite.test("panel focus blocks the cash-out confirm gate", function()
    local g = game_with_joker()
    g.STATE = g.STATES.ROUND_EVAL
    T.assert_true(g:toggle_jokers_pulled())
    T.assert_true(g:_bottom_inventory_focus_locked())
end)

suite.test("open and close play the slide cue; empty inventory plays a refusal", function()
    local g = game_with_joker(nil)
    g.STATE = g.STATES.SELECTING_HAND
    with_recorded_cues(function(cues)
        T.assert_true(g:toggle_jokers_pulled())
        T.assert_true(has_cue(cues, "whoosh1"))
    end)
    with_recorded_cues(function(cues)
        T.assert_true(g:toggle_jokers_pulled())
        T.assert_true(has_cue(cues, "whoosh1"))
    end)
    local empty = bootstrap.new_game()
    empty.STATE = empty.STATES.SELECTING_HAND
    with_recorded_cues(function(cues)
        T.assert_false(empty:toggle_jokers_pulled())
        T.assert_true(has_cue(cues, "cancel"))
    end)
end)

suite.test("toggling mid-slide springs from the current position instead of teleporting", function()
    local g = game_with_joker()
    g.STATE = g.STATES.SELECTING_HAND
    T.assert_true(g:toggle_jokers_pulled())
    local j = g.jokers[1]
    -- Pretend the card is halfway through the slide.
    j.VT.y = 5
    T.assert_true(g.jokers_sliding == true)
    T.assert_true(g:toggle_jokers_pulled())
    T.assert_eq(j.VT.y, 5, "mid-slide toggle must not reset the visual position")
end)

suite.test("panel cannot be pulled while a hand is scoring", function()
    local g = game_with_joker()
    g.STATE = g.STATES.SELECTING_HAND
    g.hand = g.hand or {}
    g.hand.is_scoring_active = function() return true end
    T.assert_false(g:toggle_jokers_pulled())
end)

--- End the slide so the cards are at their laid-out positions; hit-testing reads `VT`.
local function settle(g)
    for _, list in ipairs({ g.jokers or {}, g.consumable_nodes or {} }) do
        for _, node in ipairs(list) do
            if node and node.VT and node.T then
                node.VT.x, node.VT.y, node.VT.scale = node.T.x, node.T.y, node.T.scale
            end
        end
    end
    g.jokers_sliding = false
    g.consumables_sliding = false
end

--- A point on the first card of a pulled-down row.
local function card_center(node)
    local r = node:get_collision_rect()
    return r.x + r.w * 0.5, r.y + r.h * 0.5
end

suite.test("a pulled-down row's tray wraps its cards and vanishes when the row goes back up", function()
    local g = game_with_joker()
    g.STATE = g.STATES.SELECTING_HAND
    T.assert_eq(g:get_bottom_panel_rect("jokers"), nil, "no tray while the row is on the readout")

    T.assert_true(g:toggle_jokers_pulled())
    settle(g)
    local r = g:get_bottom_panel_rect("jokers")
    T.assert_not_nil(r)
    local card = g.jokers[1]:get_collision_rect()
    T.assert_true(r.x < card.x and r.x + r.w > card.x + card.w, "the tray wraps the row")
    T.assert_true(r.y < card.y and r.y + r.h > card.y + card.h)
    T.assert_true(r.w < g:get_bottom_inventory_dims().bottom_screen_w,
        "and leaves the rest of the playfield alone")

    T.assert_true(g:toggle_jokers_pulled())
    T.assert_eq(g:get_bottom_panel_rect("jokers"), nil)
end)

suite.test("both rows down get a tray each, side by side", function()
    local g = game_with_joker()
    T.assert_true(g:add_consumable("tarot_fool"))
    g.STATE = g.STATES.SELECTING_HAND
    T.assert_true(g:toggle_jokers_pulled())
    T.assert_true(g:toggle_consumables_pulled())
    settle(g)

    local dims = g:get_bottom_inventory_dims()
    local jr = g:get_bottom_panel_rect("jokers")
    local cr = g:get_bottom_panel_rect("consumables")
    T.assert_not_nil(jr)
    T.assert_not_nil(cr)
    T.assert_true(jr.x + jr.w <= dims.joker_panel_w, "the joker tray stays in the joker region")
    T.assert_true(cr.x >= dims.consumable_panel_x, "the consumable tray stays in its own")
    T.assert_true(jr.x + jr.w <= cr.x, "the two do not overlap")
end)

suite.test("the consumable tray is gone on the cash-out screen, where its cards are hidden", function()
    local g = bootstrap.new_game()
    T.assert_true(g:add_consumable("tarot_fool"))
    g.STATE = g.STATES.SELECTING_HAND
    T.assert_true(g:toggle_consumables_pulled())
    settle(g)
    T.assert_not_nil(g:get_bottom_panel_rect("consumables"))

    -- What `Game:draw` does to the row on cash-out.
    for _, node in ipairs(g.consumable_nodes) do node.states.visible = false end
    T.assert_eq(g:get_bottom_panel_rect("consumables"), nil, "no tray without cards to sit in it")
end)

--- A joker pulled down over an open pack that wants hand cards - the Spectral case that
--- started this: the tap landed on the playing card under the row instead of the joker.
local function pack_over_hand(seed)
    local g = bootstrap.new_game(seed)
    T.assert_true(g:add_joker_by_def("j_joker"))
    g.STATE = g.STATES.SHOP
    g:begin_booster_session({
        kind = "booster", pack = "spectral", size = "normal",
        card_count = 2, picks_granted = 1, booster_sprite_index = 1,
    })
    while g.booster_session.opening_phase ~= "ready" do
        g:_update_booster_opening(1)
    end
    g.booster_session.hand_for_tarot = true

    local hand = Hand(g)
    g.hand = hand
    hand:add_card({ rank = 10, suit = "Spades" })
    local card = hand.card_nodes[1]
    T.assert_not_nil(card)

    T.assert_true(g:toggle_jokers_pulled())
    settle(g)

    -- Put the card where the row now is; a selected card in the fan reaches into it.
    local joker = g.jokers[1]
    card.T.x, card.T.y = joker.T.x, joker.T.y
    card.VT.x, card.VT.y = joker.T.x, joker.T.y
    card.states.visible = true
    card.states.click.can = true
    -- The pack deals its hand after the run's jokers already exist, so the cards sit above them
    -- in the node list - which is exactly why the plain lookup used to hand back a playing card.
    g:move_to_front(card)
    return g, joker, card
end

suite.test("a tap on a pulled-down joker beats the hand card underneath it", function()
    local g, joker, card = pack_over_hand(6101)
    local jx, jy = card_center(joker)
    T.assert_eq(g:get_node_at(jx, jy), card, "the card is what the plain node lookup finds")

    g:touchpressed(1, jx, jy)
    T.assert_eq(g.dragging, joker, "the pulled-down row takes the touch")
end)

suite.test("a tap on the tray itself does not fall through to what it covers", function()
    local g = game_with_joker()
    g.STATE = g.STATES.SELECTING_HAND
    T.assert_true(g:toggle_jokers_pulled())
    settle(g)

    local r = g:get_bottom_panel_rect("jokers")
    -- The far left of the tray: inside the panel, outside every card in a one-joker row.
    local x, y = r.x + 2, r.y + r.h * 0.5
    T.assert_eq(g:get_owned_joker_at(x, y), nil, "the test point is not on a card")
    T.assert_true(g:handle_bottom_panel_touch(1, x, y), "the tray consumes it")
    T.assert_eq(g.dragging, nil, "and starts no drag")
end)

suite.test("a tap outside the tray is left to the screen underneath", function()
    local g = game_with_joker()
    g.STATE = g.STATES.SELECTING_HAND
    T.assert_true(g:toggle_jokers_pulled())
    settle(g)

    local r = g:get_bottom_panel_rect("jokers")
    T.assert_false(g:handle_bottom_panel_touch(1, r.x + 4, r.y + r.h + 20))
end)

suite.test("the tray eats the touch mid-scoring but does not lift a card out of the row", function()
    local g = game_with_joker()
    g.STATE = g.STATES.SELECTING_HAND
    T.assert_true(g:toggle_jokers_pulled())
    settle(g)
    g.hand = g.hand or {}
    g.hand.is_scoring_active = function() return true end

    local jx, jy = card_center(g.jokers[1])
    T.assert_true(g:handle_bottom_panel_touch(1, jx, jy))
    T.assert_eq(g.dragging, nil)
end)

--- A selected card is lifted straight into the band a pulled-down row occupies, so the tray
--- used to swallow most of the lift and opening a drawer read as the game deselecting the hand.
suite.test("a selected card is drawn over a pulled-down row, not under it", function()
    local g = game_with_joker()
    _G.G = g
    g.STATE = g.STATES.SELECTING_HAND
    g.deck = Deck(g)
    g.hand = Hand(g)
    g.hand:fill_from_deck(true)
    local selected = g.hand.card_nodes[2]
    g.hand:toggle_selection(selected)
    T.assert_true(g:toggle_jokers_pulled())
    settle(g)

    local order = {}
    local function trace(node, label)
        local real = node.draw
        node.draw = function(self, ...)
            order[#order + 1] = label
            return real(self, ...)
        end
    end
    trace(selected, "selected")
    trace(g.hand.card_nodes[1], "unselected")
    trace(g.jokers[1], "joker")

    g:draw()

    local seen = {}
    for i, label in ipairs(order) do seen[label] = seen[label] or i end
    T.assert_not_nil(seen.selected, "the selected card is drawn")
    T.assert_true(seen.unselected < seen.joker, "the row still covers the rest of the fan")
    T.assert_true(seen.selected > seen.joker, "but the selection comes out on top of it")
end)

return suite
