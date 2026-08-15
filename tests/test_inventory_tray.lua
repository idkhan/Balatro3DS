--- The joker and consumable areas are on screen before you own anything.
---
--- The reference builds a CardArea's `area_uibox` unconditionally for joker-type areas -- both
--- rows are `type = 'joker'` (`game.lua:2235-2245`) and neither is in `invisible_area_types` --
--- so the tray marks the slots from the first blind (`cardarea.lua:280-290`). This port drew it
--- only once the area held something, so a fresh run had nothing showing where a joker goes.
local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

--- Every rectangle `TopUI:draw` puts on the top screen.
local function capture_rects(top)
    local rects = {}
    local real = love.graphics.rectangle
    love.graphics.rectangle = function(mode, x, y, w, h, ...)
        rects[#rects + 1] = { mode = mode, x = x, y = y, w = w, h = h }
        return real(mode, x, y, w, h, ...)
    end
    local ok, err = pcall(top.draw, top, "top")
    love.graphics.rectangle = real
    T.assert_true(ok, tostring(err))
    return rects
end

--- A rectangle covering most of `x..x+w` at `y`, in either fill or line mode.
local function covers(rects, x, w, y_lo, y_hi)
    for _, r in ipairs(rects) do
        if r.w and r.h and r.w >= w * 0.8 and r.h >= 40
            and r.x <= x + 8 and r.x + r.w >= x + w - 8
            and r.y >= y_lo and r.y <= y_hi then
            return r
        end
    end
    return nil
end

local function fresh_game()
    bootstrap.load()
    local g = Game()
    _G.G = g
    g:init(4401)
    g.STATE = g.STATES.SELECTING_HAND
    return g, TopUI()
end

suite.test("the joker tray is drawn with nothing in it", function()
    local g, top = fresh_game()
    T.assert_eq(#g.jokers, 0, "a fresh run owns no jokers")

    local dims = g:get_top_inventory_dims()
    local rects = capture_rects(top)
    T.assert_not_nil(covers(rects, 0, dims.joker_panel_w, 20, 200),
        "the empty joker area still marks its slots")
end)

suite.test("the consumable tray is drawn with nothing in it", function()
    local g, top = fresh_game()
    T.assert_eq(#g.consumables, 0, "a fresh run holds no consumables")

    local dims = g:get_top_inventory_dims()
    local rects = capture_rects(top)
    T.assert_not_nil(covers(rects, dims.consumable_panel_x, dims.consumable_panel_w, 20, 200),
        "the empty consumable area still marks its slots")
end)

suite.test("an empty tray is outlined and a full one is filled", function()
    local g, top = fresh_game()
    local dims = g:get_top_inventory_dims()

    local empty = capture_rects(top)
    local empty_tray = covers(empty, 0, dims.joker_panel_w, 20, 200)
    T.assert_not_nil(empty_tray)

    T.assert_true(g:add_joker_by_def("j_joker"), "own a joker")
    local full = capture_rects(top)
    local full_tray = covers(full, 0, dims.joker_panel_w, 20, 200)
    T.assert_not_nil(full_tray, "the tray is still there once it holds something")

    -- The empty tray draws an outline pass the occupied one does not. Matched on the tray's
    -- own box, since plenty of other things on this screen are also stroked rectangles.
    local function outlines_tray(rects, tray)
        for _, r in ipairs(rects) do
            if r.mode == "line"
                and math.abs(r.w - tray.w) < 2 and math.abs(r.h - tray.h) < 2
                and math.abs(r.y - tray.y) < 2 then
                return true
            end
        end
        return false
    end
    T.assert_true(outlines_tray(empty, empty_tray), "empty is outlined")
    T.assert_false(outlines_tray(full, full_tray), "occupied is not")
end)

suite.test("the tray stays put when the row is pulled to the bottom screen", function()
    local g, top = fresh_game()
    local dims = g:get_top_inventory_dims()

    g.jokers_on_bottom = true
    local rects = capture_rects(top)
    T.assert_not_nil(covers(rects, 0, dims.joker_panel_w, 20, 200),
        "the joker slots are still marked while the row is down on the playfield")

    -- The consumable row is the one that hides its tray when pulled down, because the whole
    -- area moves rather than just its cards.
    g.consumables_on_bottom = true
    local down = capture_rects(top)
    T.assert_eq(covers(down, dims.consumable_panel_x, dims.consumable_panel_w, 20, 200), nil,
        "the consumable tray goes with it")
end)

return suite
