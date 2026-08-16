--- The bottom-screen Play / Sort / Discard bar (`hand_actions_ui.lua`).
---
--- Two things are worth pinning here. The enable rules, because they are the port's only
--- statement of when a hand may be committed by touch and they mirror the reference's
--- `can_play` / `can_discard` (`button_callbacks.lua:2048`, `:2092`). And the geometry, because
--- the bar's Y and `hand.lua`'s `HAND_BOTTOM_MARGIN` are two halves of one measurement living
--- in two files: nothing but a test stops someone tuning the fan and quietly parking the
--- lowest card on top of the Play button.

local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

local CARD_H = 95
--- Fan geometry copied from `hand.lua` so the assertions below are checking the layout the game
--- actually produces rather than re-deriving it from the same constants.
local FAN_ANGLE = 0.2
local ARC_DROP = CARD_H / (2.4 * 47 / 41)

local function fan_rotation(i, n) return FAN_ANGLE * (-n / 2 - 0.5 + i) / n end
local function arc_drop(i, n) return ARC_DROP * math.abs(0.5 * (-n / 2 + i - 0.5) / n) end

--- Deal `n` cards and pump the draw queue until the fan is populated. Dealing is on a beat, so
--- a single update is not enough.
local function hand_of(g, n)
    local cards = {}
    local suits = { "Hearts", "Clubs", "Diamonds", "Spades" }
    for i = 1, n do
        cards[i] = { rank = ((i - 1) % 13) + 2, suit = suits[((i - 1) % 4) + 1] }
    end
    -- `fill_from_deck` stops at the effective limit, which is 8 by default. Hand size grows
    -- past that in a real run (Juggler, Troubadour, the hand-size vouchers), and the fan is
    -- tightest when it is full, so the fixture opens the limit rather than capping the test.
    g.hand_size_delta_voucher = math.max(0, n - 8)
    local hand = Hand(g)
    g.hand = hand
    g.deck = Deck()
    g.deck.cards = cards
    hand:fill_from_deck()
    for _ = 1, 200 do
        hand:update(0.1)
        if #hand.card_nodes >= n then break end
    end
    hand:layout(true)
    return hand
end

--- A game sitting in SELECTING_HAND with a full hand and resources to spend.
local function playing_game(selected)
    local g = bootstrap.new_game(4242)
    g.STATE = g.STATES.SELECTING_HAND
    local hand = hand_of(g, 8)
    G.hands, G.discards = 4, 3
    for i = 1, (selected or 0) do
        hand:toggle_selection(hand.card_nodes[i])
    end
    return g, hand
end

--- Centre of a bar segment, which is what a real tap lands near.
local function centre(rect)
    return rect.x + rect.w * 0.5, rect.y + rect.h * 0.5
end

--------------------------------------------------------------------------------
-- Geometry
--------------------------------------------------------------------------------

--- Lowest card ink that falls within the bar's x span, for a laid-out fan.
---
--- Cards are rotated, so the lowest point is a corner rather than the axis-aligned bottom edge.
--- The outermost cards hang lowest of all - `arc_drop` plus the widest fan angle - but they sit
--- past the ends of the bar, which is the whole reason the plate is inset rather than
--- full-width. Only corners actually over the plate count.
local function lowest_ink_over(bar, m)
    local n, worst = m.n, -math.huge
    for i = 1, n do
        local cx = m.start_x + (i - 1) * m.step + m.card_w * 0.5
        local cy = m.y + arc_drop(i, n) + m.card_h * 0.5
        local th = fan_rotation(i, n)
        local cos, sin = math.cos(th), math.sin(th)
        local py = m.card_h * 0.5
        for _, px in ipairs({ -m.card_w * 0.5, m.card_w * 0.5 }) do
            local x = cx + px * cos - py * sin
            local y = cy + px * sin + py * cos
            if x >= bar.x and x <= bar.x + bar.w and y > worst then worst = y end
        end
    end
    return worst
end

suite.test("the bar clears the fan at every reachable hand size", function()
    local HandActionsUI = require("hand_actions_ui")
    local bar = HandActionsUI.BAR
    T.assert_true(bar.y + bar.h + 2 <= 240, "the bar and its shadow fit on the screen")

    -- The base limit is 8, but Juggler and the hand-size vouchers push it well past that, and
    -- the fan gets *tighter* as it fills: the step shrinks, so cards with more `arc_drop` slide
    -- in over the plate. Testing only the common 8 would miss the case that actually collides.
    for n = 1, 14 do
        local g = bootstrap.new_game(1000 + n)
        g.STATE = g.STATES.SELECTING_HAND
        local hand = hand_of(g, n)
        local m = hand:_layout_metrics()
        T.assert_not_nil(m, "the fan laid out at n=" .. n)
        T.assert_eq(m.n, n, "every card was dealt at n=" .. n)

        local worst = lowest_ink_over(bar, m)
        if worst > -math.huge then
            T.assert_true(bar.y - worst >= 3, string.format(
                "n=%d: the lowest card corner over the bar (y=%.1f) must clear its face " ..
                "(y=%d) by a visible margin, got %.1f px", n, worst, bar.y, bar.y - worst))
        end
    end
end)

suite.test("the three segments tile the bar without gaps or overlap", function()
    local HandActionsUI = require("hand_actions_ui")
    local R, bar = HandActionsUI.RECTS, HandActionsUI.BAR
    T.assert_eq(R.play.x, bar.x, "play starts at the left edge")
    T.assert_eq(R.sort.x, R.play.x + R.play.w, "sort abuts play")
    T.assert_eq(R.discard.x, R.sort.x + R.sort.w, "discard abuts sort")
    T.assert_eq(R.discard.x + R.discard.w, bar.x + bar.w, "discard ends at the right edge")
    T.assert_eq(R.play.w, R.discard.w, "the two committing actions are the same size")
end)

--------------------------------------------------------------------------------
-- Enablement
--------------------------------------------------------------------------------

suite.test("nothing commits without a selection", function()
    local HandActionsUI = require("hand_actions_ui")
    local g = playing_game(0)
    T.assert_false(HandActionsUI.can_play(g), "no cards picked, nothing to play")
    T.assert_false(HandActionsUI.can_discard(g), "or to discard")
    T.assert_true(HandActionsUI.can_sort(g), "sorting needs no selection")
end)

suite.test("a selection enables both actions", function()
    local HandActionsUI = require("hand_actions_ui")
    local g = playing_game(3)
    T.assert_true(HandActionsUI.can_play(g))
    T.assert_true(HandActionsUI.can_discard(g))
end)

suite.test("discard greys when the round's discards are spent", function()
    local HandActionsUI = require("hand_actions_ui")
    local g = playing_game(3)
    G.discards = 0
    T.assert_false(HandActionsUI.can_discard(g), "reference can_discard greys at zero left")
    T.assert_true(HandActionsUI.can_play(g), "playing is unaffected")
end)

suite.test("play greys when the hands are spent", function()
    local HandActionsUI = require("hand_actions_ui")
    local g = playing_game(3)
    G.hands = 0
    T.assert_false(HandActionsUI.can_play(g), "play_selected would refuse, so say so first")
    T.assert_true(HandActionsUI.can_discard(g), "discarding is unaffected")
end)

suite.test("the whole bar freezes while a hand is scoring", function()
    local HandActionsUI = require("hand_actions_ui")
    local g, hand = playing_game(3)
    hand._play_sequence = { stage = "scoring" }
    T.assert_true(hand:is_scoring_active(), "the fixture put the hand mid-play")
    T.assert_false(HandActionsUI.can_play(g))
    T.assert_false(HandActionsUI.can_discard(g))
    T.assert_false(HandActionsUI.can_sort(g), "re-sorting mid-score would reorder the play")
end)

--------------------------------------------------------------------------------
-- Touch
--------------------------------------------------------------------------------

suite.test("tapping Play plays the selection", function()
    local HandActionsUI = require("hand_actions_ui")
    local g, hand = playing_game(2)
    local called = 0
    hand.play_selected = function() called = called + 1 end

    local handled = HandActionsUI.handle_touch(g, centre(HandActionsUI.RECTS.play))
    T.assert_true(handled, "the tap was consumed")
    T.assert_eq(called, 1, "and reached Hand:play_selected")
end)

suite.test("tapping Discard discards the selection", function()
    local HandActionsUI = require("hand_actions_ui")
    local g, hand = playing_game(2)
    local called = 0
    hand.discard_selected = function() called = called + 1 end

    T.assert_true(HandActionsUI.handle_touch(g, centre(HandActionsUI.RECTS.discard)))
    T.assert_eq(called, 1)
end)

suite.test("tapping the sort toggle swaps the sort mode", function()
    local HandActionsUI = require("hand_actions_ui")
    local g, hand = playing_game(0)

    HandActionsUI.handle_touch(g, centre(HandActionsUI.RECTS.sort))
    local first = hand.sort_mode
    HandActionsUI.handle_touch(g, centre(HandActionsUI.RECTS.sort))
    T.assert_ne(hand.sort_mode, first, "a second tap swaps back the other way")
end)

suite.test("a greyed segment swallows the tap without acting", function()
    local HandActionsUI = require("hand_actions_ui")
    local g, hand = playing_game(2)
    G.discards = 0
    local called = 0
    hand.discard_selected = function() called = called + 1 end

    local handled = HandActionsUI.handle_touch(g, centre(HandActionsUI.RECTS.discard))
    T.assert_eq(called, 0, "a spent discard does nothing")
    -- The plate is opaque. Falling through would let the tap reach the "tapped empty felt"
    -- branch in Game:touchreleased and clear the player's tooltips from under them.
    T.assert_true(handled, "but the tap is still consumed")
end)

suite.test("the shadow band presses and acts, rather than one or the other", function()
    local HandActionsUI = require("hand_actions_ui")
    local g, hand = playing_game(2)
    local bar = HandActionsUI.BAR
    local played = 0
    hand.play_selected = function() played = played + 1 end

    -- The plate's ink runs to y 240 and nothing sits below it. A tap on the bottom two pixels
    -- used to sink the plate and then fall through to the "tapped empty felt" branch, which
    -- clears tooltips - a press animation for an action that never happened.
    local px = HandActionsUI.RECTS.play.x + 10
    local py = bar.y + bar.h + 1
    T.assert_true(HandActionsUI.handle_touch(g, px, py), "the shadow band belongs to the plate")
    T.assert_eq(played, 1, "and commits like the rest of the face")

    T.assert_false(HandActionsUI.handle_touch(g, px, bar.y + bar.h + 3),
        "but the band stops where the ink does")
end)

suite.test("a card dragged over the bar does not depress it", function()
    local HandActionsUI = require("hand_actions_ui")
    local g, hand = playing_game(2)
    local bar = HandActionsUI.BAR

    local function plate_top()
        local ys = {}
        local real_rect = love.graphics.rectangle
        love.graphics.rectangle = function(mode, x, y, ...)
            ys[#ys + 1] = y
            return real_rect(mode, x, y, ...)
        end
        pcall(HandActionsUI.draw, g)
        love.graphics.rectangle = real_rect
        local top = math.huge
        for _, y in ipairs(ys) do if y < top then top = y end end
        return top
    end

    g._ui_press = { x = bar.x + 10, y = bar.y + 10, held = true }
    T.assert_eq(plate_top(), bar.y + 2, "a bare finger on the plate sinks it")

    -- The release will be a card drop, not a button press, so the plate must not promise one.
    g.dragging = hand.card_nodes[1]
    T.assert_eq(plate_top(), bar.y, "the same finger dragging a card leaves it at rest")
end)

suite.test("a tap off the bar is not the bar's business", function()
    local HandActionsUI = require("hand_actions_ui")
    local g = playing_game(2)
    local bar = HandActionsUI.BAR
    T.assert_false(HandActionsUI.handle_touch(g, 160, bar.y - 30), "above the bar")
    T.assert_false(HandActionsUI.handle_touch(g, bar.x - 10, bar.y + 10), "left of the bar")
    T.assert_false(HandActionsUI.handle_touch(g, bar.x + bar.w + 10, bar.y + 10), "right of it")
end)

suite.test("a card dragged onto the bar does not play the hand", function()
    local HandActionsUI = require("hand_actions_ui")
    local g, hand = playing_game(2)
    local called = 0
    hand.play_selected = function() called = called + 1 end

    -- Game:touchreleased only consults the bar when nothing was being dragged, so drive the
    -- real entry point with a node under the finger rather than calling handle_touch directly.
    local node = hand.card_nodes[1]
    local px, py = centre(HandActionsUI.RECTS.play)
    g.dragging = node
    g.touch_start_x, g.touch_start_y = px, py
    g:touchreleased(1, px, py)

    T.assert_eq(called, 0, "the drop is a card release, not a button press")

    -- And the same tap with nothing under it does play, which is what makes the assertion
    -- above mean something rather than just proving touchreleased bailed out early.
    g.dragging = nil
    g.touch_start_x, g.touch_start_y = px, py
    g:touchreleased(1, px, py)
    T.assert_eq(called, 1, "a bare tap on the same pixel reaches the button")
end)

--------------------------------------------------------------------------------
-- Draw
--------------------------------------------------------------------------------

suite.test("the bar draws its labels and survives a frame", function()
    local HandActionsUI = require("hand_actions_ui")
    local g = playing_game(3)

    local printed = {}
    local real_printf = love.graphics.printf
    love.graphics.printf = function(text, ...)
        printed[#printed + 1] = tostring(text)
        return real_printf(text, ...)
    end
    local ok, err = pcall(HandActionsUI.draw, g)
    love.graphics.printf = real_printf
    if not ok then error(err, 0) end

    local joined = table.concat(printed, "\n")
    T.assert_true(joined:find("Play", 1, true) ~= nil, "the play label draws")
    T.assert_true(joined:find("Discard", 1, true) ~= nil, "and the discard label")
end)

suite.test("the sort icon is drawn, not typed", function()
    local HandActionsUI = require("hand_actions_ui")
    local g = playing_game(0)

    -- m6x11plus has no arrow glyphs at all, so any character-based icon would ship blank on
    -- hardware while looking fine under desktop LOVE. The segment must use polygons.
    local polygons = 0
    local real_polygon = love.graphics.polygon
    love.graphics.polygon = function(...)
        polygons = polygons + 1
        return real_polygon(...)
    end
    pcall(HandActionsUI.draw, g)
    love.graphics.polygon = real_polygon

    T.assert_eq(polygons, 2, "two stacked triangles")
end)

suite.test("the plate sinks onto its shadow under the finger", function()
    local HandActionsUI = require("hand_actions_ui")
    local g = playing_game(3)
    local bar = HandActionsUI.BAR

    local function tops()
        local ys = {}
        local real_rect = love.graphics.rectangle
        love.graphics.rectangle = function(mode, x, y, ...)
            ys[#ys + 1] = y
            return real_rect(mode, x, y, ...)
        end
        pcall(HandActionsUI.draw, g)
        love.graphics.rectangle = real_rect
        local top = math.huge
        for _, y in ipairs(ys) do if y < top then top = y end end
        return top
    end

    g._ui_press = nil
    T.assert_eq(tops(), bar.y, "at rest the shadow sits under a face at the bar's own y")

    g._ui_press = { x = bar.x + 10, y = bar.y + 10, held = true }
    T.assert_eq(tops(), bar.y + 2, "pressed, every fill drops onto the shadow")
end)

return suite
