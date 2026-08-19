--- The live per-Joker readouts (`joker_display.lua`), a native reimplementation of the
--- JokerDisplay mod. What matters here is that a readout says what the scoring run would
--- actually do: a number under a Joker that disagrees with the score is worse than no number.
local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")
local JokerDisplay = require("joker_display")

local suite = T.suite()

--- A game with the readouts on and a hand ready to select from.
local function game_with_display(seed)
    local g = bootstrap.new_game(seed or 4242)
    g.SETTINGS.JOKER_DISPLAY = true
    local hand = Hand(g)
    g.hand = hand
    return g, hand
end

local function select_all(hand)
    for _, node in ipairs(hand.card_nodes) do
        hand:toggle_selection(node)
    end
end

--- The readout for the joker at `slot`, after a forced rebuild.
local function readout(g, slot)
    JokerDisplay.refresh(g, true)
    local j = g.jokers[slot or 1]
    return j and j._jd_main, j and j._jd_note
end

suite.test("nothing is computed while the setting is off", function()
    local g = game_with_display()
    g.SETTINGS.JOKER_DISPLAY = false
    g:add_joker_by_def("j_joker")
    T.assert_false(JokerDisplay.refresh(g, true), "refresh declines to run")
    T.assert_nil(g.jokers[1]._jd_main, "and leaves no readout behind")
end)

suite.test("a flat Mult joker reads its own number", function()
    local g = game_with_display()
    g:add_joker_by_def("j_joker")
    T.assert_eq(readout(g), "+4")
end)

suite.test("a hand-type joker only shows when the selection contains that hand", function()
    local g, hand = game_with_display()
    g:add_joker_by_def("j_jolly")
    hand:add_card({ rank = 10, suit = "Spades" })
    hand:add_card({ rank = 4, suit = "Hearts" })
    select_all(hand)
    T.assert_nil(readout(g), "High Card is not a Pair")

    hand:clear_selection()
    hand:add_card({ rank = 10, suit = "Hearts" })
    for _, node in ipairs(hand.card_nodes) do
        if (node.card_data or {}).rank == 10 then hand:toggle_selection(node) end
    end
    T.assert_eq(readout(g), "+8", "a Pair pays Jolly Joker")
end)

suite.test("a suit joker totals every scoring card of its suit", function()
    local g, hand = game_with_display()
    g:add_joker_by_def("j_greedy_joker")
    hand:add_card({ rank = 5, suit = "Diamonds" })
    hand:add_card({ rank = 5, suit = "Diamonds" })
    hand:add_card({ rank = 9, suit = "Spades" })
    select_all(hand)
    -- The Pair scores; the Nine does not, so only the two Diamonds pay.
    T.assert_eq(readout(g), "+6")
end)

suite.test("Sock and Buskin's retrigger is counted into a suit joker's total", function()
    local g, hand = game_with_display()
    g:add_joker_by_def("j_wrathful_joker")
    g:add_joker_by_def("j_sock_and_buskin")
    hand:add_card({ rank = 13, suit = "Spades" })
    hand:add_card({ rank = 13, suit = "Spades" })
    select_all(hand)
    -- Two Kings, each scoring twice: 4 x 3 Mult.
    T.assert_eq(readout(g, 1), "+12")
end)

suite.test("an accumulator reads its running total, starting value included", function()
    local g = game_with_display()
    g:add_joker_by_def("j_hologram")
    T.assert_eq(readout(g), "X1", "a fresh Hologram still shows where it is")
    g.jokers[1].stored_xmult = 1.75
    T.assert_eq(readout(g), "X1.75")

    local g2 = game_with_display(99)
    g2:add_joker_by_def("j_green_joker")
    T.assert_eq(readout(g2), "+0", "and so does a Green Joker that has not scored yet")
end)

suite.test("a money joker reads in dollars", function()
    local g = game_with_display()
    g:add_joker_by_def("j_to_the_moon")
    g.money = 23
    T.assert_eq(readout(g), "$4", "one dollar of interest per whole $5")
end)

suite.test("Blueprint names what it is copying", function()
    local g = game_with_display()
    g:add_joker_by_def("j_blueprint")
    g:add_joker_by_def("j_joker")
    T.assert_eq(readout(g, 1), "Joker")
end)

suite.test("Blueprint says so when the slot to its right cannot be copied", function()
    local g = game_with_display()
    g:add_joker_by_def("j_blueprint")
    T.assert_eq(readout(g, 1), "none", "with nothing to the right there is no target")
end)

suite.test("a Joker the Blind has switched off shows nothing", function()
    local g = game_with_display()
    g:add_joker_by_def("j_joker")
    local j = g.jokers[1]
    j.perishable = true
    j.perishable_counter = 0
    T.assert_true(j:is_sticker_debuffed(), "the sticker has run out")
    T.assert_nil(readout(g), "so the number under it would be a lie")
end)

suite.test("the readout is rebuilt when the selection changes, not every frame", function()
    local g, hand = game_with_display()
    g:add_joker_by_def("j_jolly")
    hand:add_card({ rank = 7, suit = "Spades" })
    hand:add_card({ rank = 7, suit = "Hearts" })

    JokerDisplay.refresh(g, true)
    T.assert_false(JokerDisplay.refresh(g), "an unchanged run is not recomputed")

    select_all(hand)
    T.assert_true(JokerDisplay.refresh(g), "selecting a hand invalidates it")
    T.assert_eq(g.jokers[1]._jd_main, "+8")
end)

suite.test("a live run value moves the readout without a selection change", function()
    local g = game_with_display()
    g:add_joker_by_def("j_bull")
    g.money = 10
    T.assert_eq(readout(g), "+20")
    g.money = 11
    JokerDisplay.refresh(g)
    T.assert_eq(g.jokers[1]._jd_main, "+22", "Bull follows the wallet")
end)

suite.test("Dusk reads the hand being built as the last one", function()
    local g, hand = game_with_display()
    g:add_joker_by_def("j_dusk")
    hand:add_card({ rank = 9, suit = "Spades" })
    select_all(hand)

    g.hands = 2
    T.assert_nil(readout(g), "with two hands left Dusk is not up yet")
    g.hands = 1
    T.assert_eq(readout(g), "1", "the hand on the table is the final one")
end)

suite.test("a panel is laid out even while the card reads as invisible", function()
    -- `TopUI` flips `states.visible` on for the duration of each card's own draw and back off
    -- again, so the row is invisible by the time the readouts are drawn. Checking visibility
    -- here is what made the whole feature render on the bottom screen and nowhere else.
    local g = game_with_display()
    g:add_joker_by_def("j_joker")
    local j = g.jokers[1]
    j.states.visible = false
    JokerDisplay.refresh(g, true)
    JokerDisplay.draw_row(g, g.jokers, 70)
    T.assert_eq(j._jd_main_fit, "+4", "the panel was laid out anyway")
end)

suite.test("a note is dropped rather than truncated when the column is narrow", function()
    local g = game_with_display()
    g:add_joker_by_def("j_ancient_joker")
    local j = g.jokers[1]
    j.random_suit = "Hearts"
    -- Force a value so the note has something to sit beside.
    JokerDisplay.refresh(g, true)
    j._jd_main, j._jd_main_kind = "X1.5", "xmult"
    j._jd_note, j._jd_note_kind = "Heart", "plain"
    j._jd_fit_w = nil

    JokerDisplay.draw_row(g, g.jokers, 200)
    T.assert_eq(j._jd_note_fit, "Heart", "a wide column keeps the note")

    j._jd_fit_w = nil
    JokerDisplay.draw_row(g, g.jokers, 30)
    T.assert_nil(j._jd_note_fit, "a narrow one drops it whole rather than cutting it")
end)

suite.test("the band and the slot counter under it both fit on the top screen", function()
    -- The readouts hang between the Joker row and the used/limit counter, on a 240 px screen
    -- with about 30 px to spare. Anything that grows the face or the padding has to be checked
    -- against this or the counter silently walks off the bottom.
    local g = game_with_display()
    g:add_joker_by_def("j_green_joker")
    JokerDisplay.refresh(g, true)

    local pixel = g.FONTS.PIXEL
    local band = JokerDisplay.band_height(g)
    T.assert_true(band > 0, "a Joker with a readout needs room")

    local card_bottom = g.joker_slot_y_top + g.joker_slot_h
    T.assert_true(card_bottom + band <= 226, "the panels clear the counter's row")

    -- `topUI.lua` derives the counter from the tray, which is the row plus its 3 px padding.
    local counter_y = (g.joker_slot_y_top - 3) + (g.joker_slot_h + 6) + 1 + band
    T.assert_true(counter_y + pixel.MICRO_HEIGHT <= 240, "and the counter still fits under them")
end)

suite.test("the readouts use the face the rest of the game reads in", function()
    -- MICRO is the 9 px rung: crisp on hardware under the native ladder and a sub-pixel-grid
    -- fallback everywhere else, which read soft next to the surrounding UI.
    local g = game_with_display()
    T.assert_eq(g.FONTS.PIXEL.SMALL_HEIGHT, 13, "SMALL is the native ladder's 13 px sheet")
end)

suite.test("the settings toggle round-trips through the save", function()
    local g = bootstrap.new_game(77)
    g.SETTINGS.JOKER_DISPLAY = false
    T.assert_false(g:joker_display_enabled())
    g:set_joker_display_enabled(true)
    T.assert_true(g:joker_display_enabled())
    local snapshot = g:snapshot_settings()
    T.assert_true(snapshot.JOKER_DISPLAY, "and it is written out")
    T.assert_true(g:normalize_settings(snapshot).JOKER_DISPLAY, "and read back")
end)

return suite
