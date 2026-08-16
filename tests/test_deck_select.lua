--- The New Run screen: stake chip tinting, the stake ladder, and the deck-change pop.
---
--- Stakes unlock per deck, so `STAKE_DEFS[i].unlocked` is only ever the catalog's starting
--- default -- unlike `DECK_DEFS[i].unlocked`, nothing syncs it back from `game.unlocks`
--- (`game.lua:1716-1721`). Reading it in the drawing code dimmed every chip above White for
--- the whole game.
local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

bootstrap.load()
local MainMenuUI = require("main_menu_ui")

local function deck_select(seed)
    local g = bootstrap.new_game(seed)
    g.STATE = g.STATES.MENU
    MainMenuUI.open_deck_select(g)
    g._deck_select_idx = 1
    g._stake_select_idx = 1
    MainMenuUI.draw_bottom(g)
    return g
end

suite.test("the catalog's stake flag is not the runtime one", function()
    local g = bootstrap.new_game(9101)
    -- Red Stake ships locked in the catalog and stays that way there forever...
    T.assert_false(STAKE_DEFS_BY_ID.stake_red.unlocked == true,
        "the catalog default is locked")

    -- ...but the runtime table is what actually governs, and it is per deck.
    g.unlocks.b_red.stakes.stake_red.unlocked = true
    T.assert_true(g:is_stake_unlocked("b_red", "stake_red"))
    T.assert_false(g:is_stake_unlocked("b_blue", "stake_red"),
        "and unlocking it on one deck does not unlock it on another")

    T.assert_false(STAKE_DEFS_BY_ID.stake_red.unlocked == true,
        "unlocking a stake never writes back to the catalog")
end)

suite.test("the stake chip tints on the runtime answer, not the catalog's", function()
    local unlocked = { MainMenuUI.stake_sprite_tint(true) }
    local locked = { MainMenuUI.stake_sprite_tint(false) }

    T.assert_eq(unlocked[1], 1, "an unlocked stake draws at full brightness")
    T.assert_true(locked[1] < 1, "a locked one is knocked back")
    T.assert_true(locked[1] > 0.4, "but not so far that the chip stops reading")

    -- The screen passes `is_stake_unlocked`, so unlocking a stake brightens its chip even
    -- though nothing ever touches the catalog flag.
    local g = deck_select(9102)
    g._stake_select_idx = 2
    T.assert_eq(MainMenuUI.stake_sprite_tint(g:is_stake_unlocked("b_red", "stake_red")), 0.55,
        "locked while it is locked")
    g.unlocks.b_red.stakes.stake_red.unlocked = true
    T.assert_eq(MainMenuUI.stake_sprite_tint(g:is_stake_unlocked("b_red", "stake_red")), 1,
        "and full brightness once it is not")
end)

suite.test("the stake ladder only offers unlocked rungs", function()
    local g = deck_select(9103)
    -- A fresh profile has White only.
    T.assert_eq(#g._stake_marker_rects, 1, "one selectable rung to start")
    T.assert_eq(g._stake_marker_rects[1].index, 1)

    g.unlocks.b_red.stakes.stake_red.unlocked = true
    MainMenuUI.draw_bottom(g)
    T.assert_eq(#g._stake_marker_rects, 2, "unlocking Red adds its rung")

    -- Tapping an unlocked rung selects it.
    local rung = g._stake_marker_rects[2]
    T.assert_true(MainMenuUI.handle_touch(g, rung.x + rung.w * 0.5, rung.y + rung.h * 0.5))
    T.assert_eq(g._stake_select_idx, rung.index)
end)

suite.test("the stake ladder cannot be walked off either end", function()
    local g = deck_select(9104)
    local count = #(STAKE_DEFS or {})

    g._stake_select_idx = count
    MainMenuUI._button_deck_select(g, "dpup")
    T.assert_eq(g._stake_select_idx, count, "up stops at the top stake")

    g._stake_select_idx = 1
    MainMenuUI._button_deck_select(g, "dpdown")
    T.assert_eq(g._stake_select_idx, 1, "down stops at the bottom")

    -- Up climbs and down descends, rather than the two being crossed.
    g._stake_select_idx = 2
    MainMenuUI._button_deck_select(g, "dpup")
    T.assert_eq(g._stake_select_idx, 3)
    MainMenuUI._button_deck_select(g, "dpdown")
    T.assert_eq(g._stake_select_idx, 2)
end)

--- The regression the crossed bounds caused: the screen redrew clamped, but `_start_run`
--- read the stored index and found nothing there.
suite.test("running off the ladder does not leave Play unable to start", function()
    local g = deck_select(9105)
    g._stake_select_idx = #(STAKE_DEFS or {})
    MainMenuUI._button_deck_select(g, "dpup")
    MainMenuUI.draw_bottom(g)
    T.assert_not_nil((STAKE_DEFS or {})[g._stake_select_idx],
        "the stored index still names a stake")
end)

suite.test("the deck carousel clamps and pops only when it actually moves", function()
    local g = deck_select(9106)
    local count = #(DECK_SELECT_DEFS or DECK_DEFS or {})

    g._deck_swap_juice = nil
    MainMenuUI.set_deck_index(g, 2)
    T.assert_eq(g._deck_select_idx, 2)
    T.assert_not_nil(g._deck_swap_juice and g._deck_swap_juice.juice, "moving pops the sprite")

    g._deck_swap_juice = nil
    MainMenuUI.set_deck_index(g, 2)
    T.assert_eq(g._deck_swap_juice, nil, "re-selecting the same deck does not")

    g._deck_swap_juice = nil
    g._deck_select_idx = 1
    MainMenuUI.set_deck_index(g, 0)
    T.assert_eq(g._deck_select_idx, 1, "clamped at the near end")
    T.assert_eq(g._deck_swap_juice, nil, "and running into it is silent")

    g._deck_select_idx = count
    MainMenuUI.set_deck_index(g, count + 1)
    T.assert_eq(g._deck_select_idx, count, "clamped at the far end")
end)

suite.test("the deck pop settles rather than running forever", function()
    local g = deck_select(9107)
    MainMenuUI.set_deck_index(g, 2)
    T.assert_not_nil(g._deck_swap_juice.juice)

    -- The engine's trigger curve is 0.4 s plus whatever the spring needs to come home.
    for _ = 1, 240 do MainMenuUI.update(g, 1 / 60) end
    T.assert_eq(g._deck_swap_juice.juice, nil, "the pop finishes")
    T.assert_eq(g._deck_swap_juice.juice_scale, nil, "and stops reporting a scale")
end)

suite.test("the pop does not move the layout the info card is placed from", function()
    local g = deck_select(9108)
    local def = (DECK_SELECT_DEFS or DECK_DEFS)[1]
    local x0, y0, w0, h0 = MainMenuUI.draw_deck_carousel_sprite(g, def, 4, 0, 64, 80, 0, true)

    MainMenuUI.set_deck_index(g, 2)
    MainMenuUI.update(g, 1 / 60)
    local x1, y1, w1, h1 = MainMenuUI.draw_deck_carousel_sprite(g, def, 4, 0, 64, 80, 0, true)

    T.assert_eq(x1, x0, "x is unchanged mid-pop")
    T.assert_eq(y1, y0, "y is unchanged mid-pop")
    T.assert_eq(w1, w0, "and so is the reported size")
    T.assert_eq(h1, h0)
end)

return suite
