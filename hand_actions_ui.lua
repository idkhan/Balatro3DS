--- The bottom-screen Play / Sort / Discard bar, drawn during `SELECTING_HAND`.
---
--- The reference builds this as a UIBox of three columns anchored under `G.hand`
--- (`reference/Balatro/functions/UI_definitions.lua:986-1027`): Play Hand in `G.C.BLUE`, a
--- bordered Sort Hand block holding Rank and Suit sub-buttons, and Discard in `G.C.RED`.
---
--- Two departures, both forced by the panel. The sort block collapses to one toggle, because
--- two labelled sub-buttons inside a bordered column cannot be built at a legible size across
--- 320 px. And the three faces are drawn as a single plate with hairline seams rather than as
--- three floating buttons: at 24 px tall, three separately shadowed rectangles read as debris,
--- where one plate reads as a control bar.
---
--- Before this existed there was no touch path to play or discard at all. Both actions lived
--- only on `Game:handle_gamepad_selecting_hand` (`game.lua:13117`), which left the bottom
--- screen a touch surface for every part of a hand except finishing it.

local HandActionsUI = {}

--- Bar geometry, in bottom-screen pixels.
---
--- Static: it does not vary with hand size, selection or state, so the rects live here as
--- constants and hit-testing reads them directly, rather than following the codebase's usual
--- "stash a rect on `game` during draw" convention (`round_win_ui.lua:229`). That convention
--- exists for layouts that actually move.
---
--- The 2 px drop shadow puts the plate's ink at y 216..240, flush with the bottom edge. The fan
--- clears the face by 7.5 px once `HAND_BOTTOM_MARGIN` (`hand.lua`) is applied. That margin and
--- this Y are two halves of one measurement, so `tests/test_hand_actions.lua` asserts the
--- clearance rather than leaving them free to drift apart.
local BAR_X, BAR_Y, BAR_W, BAR_H = 42, 214, 236, 24
local SHADOW_H = 2
local RADIUS = 5
local SEG_ACTION_W = 96
local SEG_SORT_W = 44

--- Matches `draw_button_with_shadow`'s release tail (`topUI.lua:101`) so a quick tap still
--- reads as a press instead of never rendering one.
local PRESS_TAIL = 0.09

--- The plate's touch footprint, shadow included.
---
--- The shadow is part of the object and the plate is flush with the bottom edge, so there is
--- nothing below it that a tap at y 239 could have been meant for. Press feedback and
--- hit-testing read this same band deliberately: `draw_button_with_shadow` sinks on the taller
--- band while its callers hit-test the shorter one (`topUI.lua:99` against
--- `round_win_ui.lua:310`), which leaves a 2 px strip that depresses the button and then does
--- nothing. Here that strip would also fall through to the "tapped empty felt" branch in
--- `Game:touchreleased` and clear the player's tooltips as a parting gift.
local TOUCH_H = BAR_H + SHADOW_H

HandActionsUI.BAR = { x = BAR_X, y = BAR_Y, w = BAR_W, h = BAR_H }

HandActionsUI.RECTS = {
    play    = { x = BAR_X,                              y = BAR_Y, w = SEG_ACTION_W, h = BAR_H },
    sort    = { x = BAR_X + SEG_ACTION_W,               y = BAR_Y, w = SEG_SORT_W,   h = BAR_H },
    discard = { x = BAR_X + SEG_ACTION_W + SEG_SORT_W,  y = BAR_Y, w = SEG_ACTION_W, h = BAR_H },
}

--------------------------------------------------------------------------------
-- Enablement
--------------------------------------------------------------------------------

---@return integer
local function selection_count(game)
    local hand = game and game.hand
    if not hand then return 0 end
    return #(hand.selected or {})
end

--- Nothing on the bar acts while a hand is being scored. The reference destroys the whole
--- UIBox for the duration (`game.lua:3180` and the dozen sibling call sites), but a bar that
--- vanishes and returns on every hand would flicker the bottom edge of a 240p screen, so this
--- greys in place instead.
---@return boolean
local function busy(game)
    local hand = game and game.hand
    if not hand then return true end
    return hand.is_scoring_active ~= nil and hand:is_scoring_active() == true
end

--- Reference `G.FUNCS.can_play` (`button_callbacks.lua:2048`): a selection, and no more than
--- the highlight cap. The cap needs no check here because `Hand:toggle_selection` refuses past
--- five on the way in (`hand.lua:682`), and this port has no `block_play` boss.
---
--- Hands remaining is the one addition. The reference leaves that to its state machine and
--- never greys on it, but `Hand:play_selected` refuses at zero (`hand.lua:2019`), and a button
--- that accepts a press and does nothing is worse than one that says it is spent.
---@return boolean
function HandActionsUI.can_play(game)
    if busy(game) then return false end
    if selection_count(game) <= 0 then return false end
    return (tonumber(G and G.hands) or 0) > 0
end

--- Reference `G.FUNCS.can_discard` (`button_callbacks.lua:2092`).
---@return boolean
function HandActionsUI.can_discard(game)
    if busy(game) then return false end
    if selection_count(game) <= 0 then return false end
    return (tonumber(G and G.discards) or 0) > 0
end

--- The reference's sort buttons carry no `func` and never grey; the only reason to refuse here
--- is a hand that is empty or mid-flight.
---@return boolean
function HandActionsUI.can_sort(game)
    if busy(game) then return false end
    local hand = game and game.hand
    return hand ~= nil and #(hand.cards or {}) > 0
end

--------------------------------------------------------------------------------
-- Draw
--------------------------------------------------------------------------------

--- Is the finger on the bar, in a way that will actually commit? Same rule as
--- `draw_button_with_shadow` (`topUI.lua:94`): inside the footprint, and for a beat after
--- release so a quick tap still renders a press.
---
--- The whole plate sinks, not the segment under the finger. It is drawn as one object, so it
--- moves as one; sinking a third of a continuous plate would read as the plate breaking.
---@return boolean
local function pressed(game)
    local p = game and game._ui_press
    if not p then return false end
    -- A card dragged across the bar must not depress it. `Game:touchreleased` only consults
    -- the bar when nothing was under the initial press, so that release is going to be a card
    -- drop; sinking the plate on the way past would promise a press that cannot happen.
    if game.dragging then return false end
    local inside = p.x >= BAR_X and p.x <= BAR_X + BAR_W
        and p.y >= BAR_Y and p.y <= BAR_Y + TOUCH_H
    if not inside then return false end
    if p.held then return true end
    if not p.released_at or not love.timer then return false end
    return (love.timer.getTime() - p.released_at) < PRESS_TAIL
end

--- Fill one segment of the plate. The plate has rounded outer corners and square seams, so an
--- end segment is drawn rounded and then has its inner corners squared off with a plain rect.
--- Cheaper than a stencil, and the 3DS backend is not worth trusting with one.
local function fill_segment(rect, y, colour, round_left, round_right)
    love.graphics.setColor(colour)
    if not round_left and not round_right then
        love.graphics.rectangle("fill", rect.x, y, rect.w, rect.h)
        return
    end
    love.graphics.rectangle("fill", rect.x, y, rect.w, rect.h, RADIUS, RADIUS)
    if not round_left then
        love.graphics.rectangle("fill", rect.x, y, RADIUS, rect.h)
    end
    if not round_right then
        love.graphics.rectangle("fill", rect.x + rect.w - RADIUS, y, RADIUS, rect.h)
    end
end

--- The sort toggle's icon, drawn rather than typed.
---
--- `m6x11plus` carries 225 codepoints and not one arrow among them, so every obvious glyph
--- (U+21C5, U+2195, U+25B2) would rasterise to nothing through `mkbcfnt` and the segment would
--- ship blank on hardware while looking correct under desktop LÖVE with a fallback face. Two
--- stacked triangles pointing apart cost two polygons and cannot go missing.
local function draw_sort_icon(cx, cy, colour)
    love.graphics.setColor(colour)
    love.graphics.polygon("fill", cx, cy - 7, cx - 4, cy - 2, cx + 4, cy - 2)
    love.graphics.polygon("fill", cx, cy + 7, cx - 4, cy + 2, cx + 4, cy + 2)
end

function HandActionsUI.draw(game)
    local C = game and game.C
    local P = game and game.FONTS and game.FONTS.PIXEL
    if not C or not P or not P.SMALL then return end

    local R = HandActionsUI.RECTS
    local sunk = pressed(game)
    local y = sunk and (BAR_Y + SHADOW_H) or BAR_Y

    if not sunk then
        love.graphics.setColor(C.BLOCK.SHADOW)
        love.graphics.rectangle("fill", BAR_X, BAR_Y + SHADOW_H, BAR_W, BAR_H, RADIUS, RADIUS)
    end

    local play_ok = HandActionsUI.can_play(game)
    local sort_ok = HandActionsUI.can_sort(game)
    local disc_ok = HandActionsUI.can_discard(game)

    -- Blue for hands and red for discards is not decoration: it is the pairing the top-screen
    -- readout already uses for the same two counters (`topUI.lua:442-443`), and the reference's
    -- own choice for these two buttons.
    fill_segment(R.play,    y, play_ok and C.BLUE   or C.GREY, true,  false)
    fill_segment(R.sort,    y, sort_ok and C.ORANGE or C.GREY, false, false)
    fill_segment(R.discard, y, disc_ok and C.RED    or C.GREY, false, true)

    -- Seams. Without them three fills of similar value smear into one bar at 240p.
    local sh = C.BLOCK.SHADOW
    love.graphics.setColor(sh[1], sh[2], sh[3], 0.45)
    love.graphics.rectangle("fill", R.sort.x, y, 1, BAR_H)
    love.graphics.rectangle("fill", R.discard.x, y, 1, BAR_H)

    local font = P.SMALL
    love.graphics.setFont(font)
    local text_y = y + math.floor((BAR_H - font:getHeight()) * 0.5 + 0.5)
    love.graphics.setColor(play_ok and C.WHITE or C.UI.TEXT_INACTIVE)
    love.graphics.printf("Play", R.play.x, text_y, R.play.w, "center")
    love.graphics.setColor(disc_ok and C.WHITE or C.UI.TEXT_INACTIVE)
    love.graphics.printf("Discard", R.discard.x, text_y, R.discard.w, "center")

    draw_sort_icon(R.sort.x + R.sort.w * 0.5, y + BAR_H * 0.5,
        sort_ok and C.BLACK or C.UI.TEXT_INACTIVE)

    love.graphics.setColor(1, 1, 1, 1)
end

--------------------------------------------------------------------------------
-- Touch
--------------------------------------------------------------------------------

--- A segment's x span over the plate's full touch footprint (see `TOUCH_H`).
---@return boolean
local function hit(rect, x, y)
    return x >= rect.x and x <= rect.x + rect.w
        and y >= BAR_Y and y <= BAR_Y + TOUCH_H
end

--- Act on a tap.
---
--- `Game:touchreleased` only calls this for a tap that had no node under its initial press, so
--- a card dragged down over the bar and released there cannot fire it. A press on a greyed
--- segment is still handled: the plate is opaque, and letting the tap fall through to the
--- "tapped empty felt" branch would clear the player's tooltips from under them.
---@return boolean handled
function HandActionsUI.handle_touch(game, x, y)
    local hand = game and game.hand
    if not hand then return false end
    local R = HandActionsUI.RECTS

    if hit(R.play, x, y) then
        if HandActionsUI.can_play(game) then
            Sfx.play_button()
            hand:play_selected()
        end
        return true
    end
    if hit(R.sort, x, y) then
        if HandActionsUI.can_sort(game) then
            -- No `button` cue here: `toggle_hand_sort` reaches `Hand:sort_by_rank` /
            -- `sort_by_suit`, which ring `paper1` (`hand.lua:2147`, the reference's own sort
            -- cue at `button_callbacks.lua:46`). Two cues on one press thickens it.
            game:toggle_hand_sort()
        end
        return true
    end
    if hit(R.discard, x, y) then
        if HandActionsUI.can_discard(game) then
            Sfx.play_button()
            hand:discard_selected()
        end
        return true
    end
    return false
end

return HandActionsUI
