local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite("fonts")

local ROLES = {
    "MICRO", "TINY", "SMALL", "PRICE", "BUTTON", "MEDIUM", "BUTTON_PRICE", "LARGE",
}

local function fresh()
    package.loaded.fonts = nil
    package.loaded.performance_lab = nil
    return require("fonts"), require("performance_lab")
end

suite.test("both profiles cover every role with a font and a height", function()
    bootstrap.load()
    local Fonts = fresh()
    for profile in pairs(Fonts.PROFILES) do
        local pixel = Fonts.build(profile)
        T.assert_eq(pixel.PROFILE, profile)
        for _, role in ipairs(ROLES) do
            T.assert_not_nil(pixel[role], profile .. "." .. role)
            T.assert_eq(pixel[role .. "_HEIGHT"], Fonts.PROFILES[profile][role],
                profile .. "." .. role .. "_HEIGHT")
        end
    end
end)

suite.test("the shared profile is the historical ladder", function()
    local Fonts = fresh()
    -- Toggling the experiment off has to land on exactly what shipped, or the A/B compares the
    -- new ladder against something that was never released.
    T.assert_deep_eq(Fonts.PROFILES.shared, {
        MICRO = 8, TINY = 9, SMALL = 11, PRICE = 15,
        BUTTON = 18, MEDIUM = 22, BUTTON_PRICE = 26, LARGE = 33,
    })
end)

suite.test("every native size is a cell height mkbcfnt can produce", function()
    local Fonts = fresh()
    local available = {}
    for _, h in ipairs(Fonts.CELL_HEIGHTS) do available[h] = true end
    for role, size in pairs(Fonts.PROFILES.native) do
        -- A size off this list cannot render 1:1 on hardware no matter what the build does, so
        -- it would quietly be a resample again - the exact thing the profile exists to avoid.
        T.assert_true(available[size],
            string.format("native.%s = %d is not a bakeable cell height", role, size))
    end
end)

suite.test("distinct faces are shared across roles of equal size", function()
    bootstrap.load()
    local Fonts = fresh()
    local pixel = Fonts.build("native")
    -- Each newFont linearAllocs its own copy of the glyph sheet on 3DS; two roles at the same
    -- size must not pay for it twice.
    T.assert_eq(pixel.TINY, pixel.MICRO, "MICRO and TINY are both 9")
    T.assert_eq(pixel.PRICE, pixel.BUTTON, "PRICE and BUTTON are both 18")

    local distinct = {}
    local count = 0
    for _, role in ipairs(ROLES) do
        if not distinct[pixel[role]] then
            distinct[pixel[role]] = true
            count = count + 1
        end
    end
    T.assert_eq(pixel.FACES, count, "FACES matches the distinct faces built")
    T.assert_true(count < #ROLES, "native profile builds fewer faces than roles")
end)

suite.test("the native ladder is never smaller than the shared one", function()
    local Fonts = fresh()
    -- The complaint being addressed is that text reads small on a 240p screen. A role that got
    -- smaller in the name of sharpness is a regression, not a trade.
    for _, role in ipairs(ROLES) do
        T.assert_true(Fonts.PROFILES.native[role] >= Fonts.PROFILES.shared[role],
            string.format("native.%s (%d) < shared.%s (%d)", role,
                Fonts.PROFILES.native[role], role, Fonts.PROFILES.shared[role]))
    end
end)

suite.test("the build's sheet list matches the game's cell heights", function()
    local Fonts = fresh()
    local root = os.getenv("BALATRO_ROOT") or "."
    local handle = io.open(root .. "/dev/config.sh", "r")
    T.assert_not_nil(handle, "dev/config.sh is readable")
    local config = handle:read("*a")
    handle:close()

    local block = config:match("PIXEL_FONT_SHEETS=%((.-)%)")
    T.assert_not_nil(block, "PIXEL_FONT_SHEETS is declared in dev/config.sh")

    local baked = {}
    for cell_h in block:gmatch('"(%d+):%d+"') do
        baked[tonumber(cell_h)] = true
    end

    -- The build bakes one sheet per cell height and the game asks for it by that number. If the
    -- two lists drift the game silently falls back to the shared sheet and every size resamples
    -- again, with nothing on-console to say so.
    for _, h in ipairs(Fonts.CELL_HEIGHTS) do
        T.assert_true(baked[h], string.format("dev/config.sh bakes no %dpx sheet", h))
    end
    for h in pairs(baked) do
        local wanted = false
        for _, want in ipairs(Fonts.CELL_HEIGHTS) do
            if want == h then wanted = true end
        end
        T.assert_true(wanted, string.format("dev/config.sh bakes an unused %dpx sheet", h))
    end
end)

suite.test("apply swaps the ladder in place", function()
    local Fonts = fresh()
    bootstrap.load()
    local game = { FONTS = { PIXEL = Fonts.build("shared") } }
    local pixel = game.FONTS.PIXEL

    T.assert_true(Fonts.apply(game, "native"))
    -- In place: UI modules capture `local P = game.FONTS.PIXEL`, so replacing the table would
    -- strand them on the retired faces.
    T.assert_eq(game.FONTS.PIXEL, pixel, "the table identity is preserved")
    T.assert_eq(pixel.PROFILE, "native")
    T.assert_eq(pixel.SMALL_HEIGHT, Fonts.PROFILES.native.SMALL)

    T.assert_false(Fonts.apply(game, "native"), "re-applying the live profile is a no-op")

    T.assert_true(Fonts.apply(game, "shared"))
    T.assert_eq(pixel.SMALL_HEIGHT, Fonts.PROFILES.shared.SMALL)
end)

suite.test("apply drops the shop's cached font references", function()
    local Fonts = fresh()
    bootstrap.load()
    -- shop_ui caches Font objects in button part tables rather than looking them up per draw,
    -- so the cache outlives the fonts it was built from.
    local game = { FONTS = { PIXEL = Fonts.build("shared") }, _shop_ui_cache = { stale = true } }
    Fonts.apply(game, "native")
    T.assert_nil(game._shop_ui_cache)
    T.assert_true(game._shop_layout_dirty)
end)

suite.test("an unknown profile falls back to the default rather than erroring", function()
    local Fonts = fresh()
    local pixel = Fonts.build("nonsense")
    T.assert_eq(pixel.PROFILE, Fonts.DEFAULT_PROFILE)
end)

suite.test("the crisp fonts experiment registers and drives apply", function()
    local Fonts, lab = fresh()
    T.assert_true(lab.is_available("crisp_fonts"))
    T.assert_false(lab.is_enabled("crisp_fonts"), "starts off, i.e. on the shipped ladder")

    bootstrap.load()
    local previous = G
    G = { FONTS = { PIXEL = Fonts.build("shared") } }

    lab.toggle("crisp_fonts")
    T.assert_eq(G.FONTS.PIXEL.PROFILE, "native")

    -- "All Off" has to put the fonts back, not just clear the flag.
    lab.disable_all()
    T.assert_false(lab.is_enabled("crisp_fonts"))
    T.assert_eq(G.FONTS.PIXEL.PROFILE, "shared")

    G = previous
end)

suite.test("the status line reports the live profile and native face count", function()
    local Fonts = fresh()
    local game = { FONTS = { PIXEL = Fonts.build("shared") } }
    local line = Fonts.status_line(game)
    T.assert_true(line:find("shared", 1, true) ~= nil, line)
    -- Off-console the per-size files do not exist, so nothing is native and the readout says so
    -- instead of implying the toggle worked.
    T.assert_true(line:find("native 0/", 1, true) ~= nil, line)
end)

suite.test("a missing per-size sheet falls back on the face, never on the size", function()
    bootstrap.load()
    local Fonts = fresh()
    -- Every non-3DS build is this case: the per-size sheets only exist inside a packaged 3DS
    -- build, so desktop and nest always take the fallback. The stub loads any path, so the
    -- failure has to be induced.
    local real_new_font = love.graphics.newFont
    local requested = {}
    love.graphics.newFont = function(path, size)
        if type(path) == "string" and path:find("_h%d") then
            error("no such file: " .. path, 0)
        end
        requested[#requested + 1] = { path = path, size = size }
        return real_new_font(path, size)
    end
    local ok, pixel = pcall(Fonts.build, "native")
    love.graphics.newFont = real_new_font

    T.assert_true(ok, tostring(pixel))
    T.assert_eq(pixel.PROFILE, "native", "the profile is still native, only the face changed")
    T.assert_eq(pixel.NATIVE_FACES, 0, "nothing loaded 1:1, and the readout must say so")
    T.assert_true(pixel.FACES > 0)
    for _, role in ipairs(ROLES) do
        T.assert_not_nil(pixel[role], role .. " still has a usable face")
        -- Falling back on size too would make nest and hardware lay out differently, which is the
        -- one thing the fallback must not do.
        T.assert_eq(pixel[role .. "_HEIGHT"], Fonts.PROFILES.native[role], role .. "_HEIGHT")
    end
    for _, call in ipairs(requested) do
        T.assert_true(call.path:find("_h%d") == nil, "fallback should not retry a per-size path")
    end
end)

suite.test("next_smaller always steps down, even where roles share a face", function()
    bootstrap.load()
    local Fonts = fresh()
    for profile in pairs(Fonts.PROFILES) do
        local game = { FONTS = { PIXEL = Fonts.build(profile) } }
        local pixel = game.FONTS.PIXEL
        for _, role in ipairs(ROLES) do
            local font = pixel[role]
            local smaller = Fonts.next_smaller(game, font)
            if smaller ~= nil then
                -- Returning the same object would spin shop_ui's label-shrink loop forever, and
                -- roles do collapse onto one face (PRICE and BUTTON are both 18 under native).
                T.assert_ne(smaller, font,
                    string.format("%s.%s stepped down to itself", profile, role))
            end
        end
    end
end)

suite.test("walking next_smaller terminates from every role", function()
    bootstrap.load()
    local Fonts = fresh()
    for profile in pairs(Fonts.PROFILES) do
        local game = { FONTS = { PIXEL = Fonts.build(profile) } }
        for _, role in ipairs(ROLES) do
            local font = game.FONTS.PIXEL[role]
            local steps = 0
            while font do
                font = Fonts.next_smaller(game, font)
                steps = steps + 1
                T.assert_true(steps <= #ROLES + 1,
                    string.format("%s.%s did not reach the bottom of the ladder", profile, role))
            end
        end
    end
end)

suite.test("fit leaves a label that already fits alone", function()
    bootstrap.load()
    local Fonts = fresh()
    local game = { FONTS = { PIXEL = Fonts.build("native") } }
    local pixel = game.FONTS.PIXEL
    T.assert_eq(Fonts.fit(game, pixel.MEDIUM, "Hi", 10000), pixel.MEDIUM)
end)

suite.test("fit returns the largest face that fits, not the first that does", function()
    bootstrap.load()
    local Fonts = fresh()
    for profile in pairs(Fonts.PROFILES) do
        local game = { FONTS = { PIXEL = Fonts.build(profile) } }
        local pixel = game.FONTS.PIXEL
        local text = string.rep("W", 12)
        -- Sweep every width from "nothing fits" to "everything fits" and check the result is both
        -- within budget and maximal. Stepping too far is a silent legibility loss, and the ladder
        -- has no rung between 9 and 13, so an over-eager step is a big one.
        local widest = pixel.LARGE:getWidth(text)
        for limit = 1, math.ceil(widest) + 4 do
            local got = Fonts.fit(game, pixel.LARGE, text, limit)
            local got_w = got:getWidth(text)
            local floor_w = pixel.MICRO:getWidth(text)
            if got_w > limit then
                T.assert_true(limit < floor_w,
                    string.format("%s: overshot at limit %d without being at the floor", profile, limit))
            end
            for _, role in ipairs(ROLES) do
                local w = pixel[role]:getWidth(text)
                if w <= limit then
                    T.assert_true(got_w >= w,
                        string.format("%s: at limit %d picked %g but %s at %g also fit",
                            profile, limit, got_w, role, w))
                end
            end
        end
    end
end)

suite.test("fit bottoms out instead of spinning when nothing fits", function()
    bootstrap.load()
    local Fonts = fresh()
    local game = { FONTS = { PIXEL = Fonts.build("native") } }
    local pixel = game.FONTS.PIXEL
    local got = Fonts.fit(game, pixel.LARGE, string.rep("W", 200), 1)
    T.assert_eq(got, pixel.MICRO, "should land on the smallest face")
end)

suite.test("fit tolerates missing arguments", function()
    bootstrap.load()
    local Fonts = fresh()
    local game = { FONTS = { PIXEL = Fonts.build("native") } }
    local pixel = game.FONTS.PIXEL
    T.assert_eq(Fonts.fit(game, pixel.SMALL, nil, 100), pixel.SMALL)
    T.assert_eq(Fonts.fit(game, pixel.SMALL, "x", nil), pixel.SMALL)
    T.assert_nil(Fonts.fit(game, nil, "x", 100))
end)

suite.test("next_smaller is nil for the smallest face and for strangers", function()
    bootstrap.load()
    local Fonts = fresh()
    local game = { FONTS = { PIXEL = Fonts.build("native") } }
    T.assert_nil(Fonts.next_smaller(game, game.FONTS.PIXEL.MICRO), "MICRO is the floor")
    T.assert_nil(Fonts.next_smaller(game, love.graphics.newFont(17)), "a font not in the ladder")
    T.assert_nil(Fonts.next_smaller(game, nil))
end)

return suite
