local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()
local love = bootstrap.load()

local root = os.getenv("BALATRO_ROOT") or "."
dofile(root .. "/main.lua")

--- The wash reaches the screen as the runtime's background colour, not as a `clear` inside
--- `love.draw`: the run loop clears every screen with it before calling us
--- (`callbacks.lua:276`), so clearing again in the draw was a discarded full-screen fill.
--- That moves the assertion seam to `setBackgroundColor` off `love.update`.
local function background_color_for(index, boss_id)
    local captured
    local original_set = love.graphics.setBackgroundColor
    local original_g, original_top, original_sfx = G, Top, Sfx
    love.graphics.setBackgroundColor = function(r, g, b, a)
        captured = { r, g, b, a }
    end
    Top = { update = function() end }
    Sfx = { update = function() end }
    G = {
        STATE = "RUN",
        STATES = { MENU = "MENU" },
        TIMERS = { REAL = 0, TOTAL = 0 },
        C = {
            BLIND = { Big = { 0.1, 0.2, 0.3, 1 } },
            BLIND_COLORS = {
                Small = { 0.2, 0.3, 0.4, 1 },
                Big = { 0.4, 0.5, 0.6, 1 },
                Boss = { 0.6, 0.7, 0.8, 1 },
            },
        },
        current_blind_index = index,
        current_boss_blind_id = boss_id,
        P_BLINDS = {
            bl_test = { boss_colour = { 0.9, 0.1, 0.2, 1 } },
        },
        get_blind_def = function(_, blind_index)
            return ({
                [1] = { id = "small", key = "Small" },
                [2] = { id = "big", key = "Big" },
                [3] = { id = "boss", key = "Boss" },
            })[blind_index]
        end,
        speed_factor = function() return 1 end,
        update = function() end,
        draw = function() end,
    }
    love.update(1 / 60)
    love.graphics.setBackgroundColor = original_set
    G, Top, Sfx = original_g, original_top, original_sfx
    return captured
end

--- The menu paints its own background over the whole screen, so `love.update` leaves the
--- wash alone there rather than easing it under something opaque.
local function menu_sets_background()
    local touched = false
    local original_set = love.graphics.setBackgroundColor
    local original_g, original_top, original_sfx = G, Top, Sfx
    love.graphics.setBackgroundColor = function() touched = true end
    Top = { update = function() end }
    Sfx = { update = function() end }
    G = {
        STATE = "MENU",
        STATES = { MENU = "MENU" },
        TIMERS = { REAL = 0, TOTAL = 0 },
        speed_factor = function() return 1 end,
        update = function() end,
    }
    love.update(1 / 60)
    love.graphics.setBackgroundColor = original_set
    G, Top, Sfx = original_g, original_top, original_sfx
    return touched
end

suite.test("bottom background follows small and big blind palettes", function()
    T.assert_deep_eq(background_color_for(1), { 0.2, 0.3, 0.4, 1 }, "small blind")
    T.assert_deep_eq(background_color_for(2), { 0.4, 0.5, 0.6, 1 }, "big blind")
end)

suite.test("bottom background uses the active boss palette", function()
    T.assert_deep_eq(background_color_for(3, "bl_test"), { 0.9, 0.1, 0.2, 1 }, "boss blind")
    T.assert_deep_eq(background_color_for(3), { 0.6, 0.7, 0.8, 1 }, "boss fallback")
end)

suite.test("the menu leaves the background wash alone", function()
    T.assert_eq(menu_sets_background(), false, "menu should not set a background colour")
end)

return suite
