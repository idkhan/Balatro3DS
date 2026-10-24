--- fx.lua: the shader-replacement effects.
---
--- Everything here is the math and mesh-construction layer: vertex colours, UV
--- normalization (including the hardware case where getDimensions reports the t3x's
--- power-of-two padded size), the flame intensity state machine, and that the draw
--- entry points build the meshes and restore GPU state. Actual pixels need hardware.

local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

local love = bootstrap.load()
local Fx = _G.Fx
local Console = require("console")

--- Meshes created since the marker returned by `mark()`.
local function mark()
    return #love._test.meshes
end

local function since(from)
    local out = {}
    for i = from + 1, #love._test.meshes do out[#out + 1] = love._test.meshes[i] end
    return out
end

--- A fake image whose reported dimensions we control; Fx only ever asks for
--- getDimensions and hands the image to Mesh:setTexture.
local function fake_image(w, h)
    return { getDimensions = function() return w, h end }
end

--------------------------------------------------------------------------------
-- Colour math
--------------------------------------------------------------------------------

suite.test("hue_rgb hits the primaries and wraps", function()
    local r, g, b = Fx.hue_rgb(0)
    T.assert_deep_eq({ r, g, b }, { 1, 0, 0 }, "hue 0 is red")
    r, g, b = Fx.hue_rgb(1 / 3)
    T.assert_deep_eq({ r, g, b }, { 0, 1, 0 }, "hue 1/3 is green")
    r, g, b = Fx.hue_rgb(2 / 3)
    T.assert_deep_eq({ r, g, b }, { 0, 0, 1 }, "hue 2/3 is blue")

    local r1, g1, b1 = Fx.hue_rgb(0.25)
    local r2, g2, b2 = Fx.hue_rgb(1.25)
    T.assert_deep_eq({ r1, g1, b1 }, { r2, g2, b2 }, "hue wraps at 1")

    for h = 0, 1, 0.05 do
        local cr, cg, cb = Fx.hue_rgb(h)
        for _, c in ipairs({ cr, cg, cb }) do
            T.assert_true(c >= 0 and c <= 1, "channels stay in [0,1]")
        end
        T.assert_near(math.max(cr, cg, cb), 1, 1e-9, "full-value hue always has a peak channel")
    end
end)

suite.test("band peaks at the centre and dies at the edges", function()
    T.assert_near(Fx.band(0.5, 0.5, 0.2), 1, 1e-9, "centre")
    T.assert_eq(Fx.band(0.71, 0.5, 0.2), 0, "outside right")
    T.assert_eq(Fx.band(0.29, 0.5, 0.2), 0, "outside left")
    local inner = Fx.band(0.55, 0.5, 0.2)
    local outer = Fx.band(0.65, 0.5, 0.2)
    T.assert_true(inner > outer and outer > 0, "profile decays monotonically")
    T.assert_near(Fx.band(0.45, 0.5, 0.2), Fx.band(0.55, 0.5, 0.2), 1e-9, "symmetric")
end)

--------------------------------------------------------------------------------
-- Edition colours
--------------------------------------------------------------------------------

--- Polychrome and holo now read their hue from the shared interference field, so their
--- colour functions take (field, index) rather than (u, v). The field is built once a
--- frame for the whole board; see fx.lua on why.
local function field_of(kind, t)
    return Fx.field_table(kind, t)
end

suite.test("polychrome base multiply never crushes the art", function()
    for _, t in ipairs({ 0, 1.3, 7.77, 100 }) do
        local field = field_of("polychrome", t)
        for n = 1, 49 do
            local r, g, b, a = Fx.polychrome_base_rgba(field, n, 0, 0, t, 0)
            T.assert_true(r >= 0.32 - 1e-9 and g >= 0.32 - 1e-9 and b >= 0.32 - 1e-9,
                "multiply floor keeps the art's own shading readable at 240p")
            T.assert_eq(a, 1, "base pass is opaque")
        end
    end
end)

suite.test("polychrome pools colour across the card rather than sliding a ramp", function()
    local field = field_of("polychrome", 2)
    -- The field is a blob field: opposite corners of the grid should not agree, and the
    -- variation should not be a straight line across the card either.
    local seen = {}
    for _, n in ipairs({ 1, 7, 43, 49, 25 }) do
        local r, g, b = Fx.polychrome_base_rgba(field, n, 0, 0, 2, 0)
        seen[#seen + 1] = { r, g, b }
    end
    local spread = 0
    for i = 2, #seen do
        spread = spread + math.abs(seen[i][1] - seen[1][1])
            + math.abs(seen[i][2] - seen[1][2]) + math.abs(seen[i][3] - seen[1][3])
    end
    T.assert_true(spread > 0.05, "several colours are on the card at once")
end)

suite.test("a per-card seed keeps a row of cards out of lockstep", function()
    local field = field_of("polychrome", 4)
    local r1 = Fx.polychrome_base_rgba(field, 20, 0, 0, 4, 0)
    local r2 = Fx.polychrome_base_rgba(field, 20, 0, 0, 4, 0.4)
    T.assert_true(math.abs(r1 - r2) > 1e-6, "the same vertex differs between two cards")
end)

suite.test("the shared field is rebuilt on a schedule, not every frame", function()
    local a = Fx.field_table("holo", 100)
    local first = a[1]
    -- Well inside the refresh window: same table, same contents.
    local b = Fx.field_table("holo", 100 + 1 / 60)
    T.assert_eq(b[1], first, "a frame later the field has not been rebuilt")
    -- Past it: rebuilt.
    local c = Fx.field_table("holo", 100 + 1)
    T.assert_true(math.abs(c[1] - first) > 1e-12, "a second later it has")
end)

suite.test("foil base stays a sheen over readable art", function()
    -- `foil.fs:129` caps the foil overlay at 0.3 alpha off the ridges, so compositing the
    -- shader's own (tex-delta, tex-delta, tex) colour over a mid-tone card lands near a
    -- (0.72, 0.70, 1.0) multiply. Anything much darker is applying a 30% overlay at 100%.
    for v = 0, 1, 0.5 do
        local r, g, b, a = Fx.foil_base_rgba(0.5, v, 0)
        T.assert_true(b > r and b > g, "blue is held while red and green are pulled down")
        T.assert_true(r > 0.62 and r < 0.82, "the multiply is a sheen, not a repaint")
        T.assert_true(g <= r, "green sits at or under red, as delta subtraction leaves it")
        T.assert_eq(a, 1, "base pass is opaque")
    end
end)

suite.test("foil sweep lights the ring sheet only as it passes", function()
    -- `maxfac` is zero across almost all of the card and spikes on the ridges
    -- (`foil.fs:107-116`), so a resting card must not carry a lit lattice.
    local seen_peak, seen_rest = false, false
    for i = 0, 40 do
        local t = i * 0.1
        local _, _, _, a = Fx.foil_add_rgba(0.5, 0.5, t)
        T.assert_true(a >= 0 and a <= 1.0 + 1e-9, "alpha stays in range")
        if a > 0.5 then seen_peak = true end
        if a < 0.1 then seen_rest = true end
    end
    T.assert_true(seen_peak, "the sweep does cross the card")
    T.assert_true(seen_rest, "and the rings go quiet between sweeps")
end)

suite.test("holo add pass reads red, not rainbow", function()
    -- Holo is the +Mult edition. `holo.fs:131` blends the hue-rotated copy in at `delta`
    -- (0.2..0.6), tinted pink-violet -- it never sweeps the whole wheel at full strength,
    -- which is polychrome's signature.
    for _, t in ipairs({ 0, 3.9, 12.5 }) do
        local field = field_of("holo", t)
        for n = 1, 49, 8 do
            local r, g, b, a = Fx.holo_add_rgba(field, n, 0.5, 1, t, 0)
            T.assert_true(a >= 0.10 and a <= 0.32, "additive alpha stays near the reference blend")
            T.assert_near(math.max(r, g, b), 1, 1e-9, "spectral colours at full value")
            T.assert_true(r >= g and r >= b, "red leads; the arc never leaves red/magenta")
            T.assert_true(g < 0.35, "green never comes up, so the hue cannot reach cyan or yellow")
        end
    end
end)

suite.test("holo hue moves without escaping the red arc", function()
    -- It must still shimmer -- a frozen tint is not holo either.
    local field = field_of("holo", 7)
    local lo, hi = 2, -1
    for n = 1, 49 do
        local _, _, b = Fx.holo_add_rgba(field, n, 0.5, 1, 7, 0)
        if b < lo then lo = b end
        if b > hi then hi = b end
    end
    T.assert_true(hi - lo > 0.05, "the field still moves the hue across the card")
end)

suite.test("pattern cells walk the sheet and wrap", function()
    local Fx_pattern = { phases = 6, cols = 3,
        variants = { card = { x = 0, y = 0, w = 72, h = 95 },
                     joker = { x = 0, y = 190, w = 70, h = 94 } } }

    local sx, sy, cw, ch = Fx.pattern_cell(Fx_pattern, "card", 0)
    T.assert_deep_eq({ sx, sy, cw, ch }, { 0, 0, 72, 95 }, "phase 0 is the first cell")

    sx, sy = Fx.pattern_cell(Fx_pattern, "card", 1 / 6 + 1e-9)
    T.assert_deep_eq({ sx, sy }, { 72, 0 }, "one phase along is one column along")

    sx, sy = Fx.pattern_cell(Fx_pattern, "card", 3 / 6 + 1e-9)
    T.assert_deep_eq({ sx, sy }, { 0, 95 }, "past the last column it wraps to the next row")

    sx, sy = Fx.pattern_cell(Fx_pattern, "joker", 0)
    T.assert_deep_eq({ sx, sy }, { 0, 190 }, "the Joker silhouette is its own block")

    local a = { Fx.pattern_cell(Fx_pattern, "card", 0) }
    local b = { Fx.pattern_cell(Fx_pattern, "card", 1) }
    T.assert_deep_eq(a, b, "phase wraps at 1")
end)

suite.test("the foil phase follows card motion, not just the clock", function()
    local still = Fx.foil_phase(0, 0, 0)
    T.assert_true(Fx.foil_phase(0.2, 0, 0) ~= still, "rotation moves the phase")
    T.assert_true(Fx.foil_phase(0, 0.02, 0) ~= still, "so does juice")
    T.assert_true(Fx.foil_phase(0, 0, 3) ~= still, "and it crawls on its own")
    for _, args in ipairs({ { 0, 0, 0 }, { 9, 9, 9 }, { -3, -3, 40 } }) do
        local p = Fx.foil_phase(args[1], args[2], args[3])
        T.assert_true(p >= 0 and p < 1, "always a 0..1 phase, whatever the inputs")
    end
end)

suite.test("has_edition_fx covers exactly the mesh editions", function()
    T.assert_true(Fx.has_edition_fx("foil"), "foil")
    T.assert_true(Fx.has_edition_fx("holo"), "holo")
    T.assert_true(Fx.has_edition_fx("polychrome"), "polychrome")
    T.assert_false(Fx.has_edition_fx("negative"), "negative is a baked sprite, not a mesh pass")
    T.assert_false(Fx.has_edition_fx("base"), "base")
    T.assert_false(Fx.has_edition_fx(nil), "nil")
end)

--------------------------------------------------------------------------------
-- Strip construction
--------------------------------------------------------------------------------

suite.test("build_strip lays out a full-cover strip with cell UVs", function()
    local verts = Fx.build_strip(64, 190, 71, 95, 512, 512, 71, 95, 0,
        function(u, v) return u, v, 0.5, 1 end)
    T.assert_eq(#verts, 18, "9 columns x 2 rows")

    -- Corner positions cover the draw rect exactly.
    T.assert_deep_eq({ verts[1][1], verts[1][2] }, { 0, 0 }, "first vertex at the top-left")
    T.assert_deep_eq({ verts[2][1], verts[2][2] }, { 0, 95 }, "second vertex below it (strip pairs)")
    T.assert_deep_eq({ verts[17][1], verts[17][2] }, { 71, 0 }, "last column right edge")
    T.assert_deep_eq({ verts[18][1], verts[18][2] }, { 71, 95 }, "bottom-right corner")

    -- UVs span the cell, normalized against the image dimensions.
    T.assert_near(verts[1][3], 64 / 512, 1e-9, "left U")
    T.assert_near(verts[1][4], 190 / 512, 1e-9, "top V")
    T.assert_near(verts[18][3], (64 + 71) / 512, 1e-9, "right U")
    T.assert_near(verts[18][4], (190 + 95) / 512, 1e-9, "bottom V")

    -- Colour function's u/v arrive as promised.
    T.assert_deep_eq({ verts[1][5], verts[1][6] }, { 0, 0 }, "top-left colour args")
    T.assert_deep_eq({ verts[18][5], verts[18][6] }, { 1, 1 }, "bottom-right colour args")
end)

suite.test("build_strip normalizes against padded hardware dimensions", function()
    -- On hardware a 512x512 sheet reports 512, but an odd-sized source like 1000x600
    -- reports 1024x1024 (the t3x padded size). The same cell must land on the same
    -- texels: UV = pixel / reported, whatever reported is.
    local desktop = Fx.build_strip(100, 200, 50, 60, 1000, 600, 50, 60, 0,
        function() return 1, 1, 1, 1 end)
    local u_desktop = desktop[1][3] * 1000
    local v_desktop = desktop[1][4] * 600

    local hardware = Fx.build_strip(100, 200, 50, 60, 1024, 1024, 50, 60, 0,
        function() return 1, 1, 1, 1 end)
    local u_hardware = hardware[1][3] * 1024
    local v_hardware = hardware[1][4] * 1024

    T.assert_near(u_desktop, u_hardware, 1e-6, "same texel column either way")
    T.assert_near(v_desktop, v_hardware, 1e-6, "same texel row either way")
end)

--------------------------------------------------------------------------------
-- Draw entry points
--------------------------------------------------------------------------------

suite.test("polychrome draws both passes off the dense shared grid", function()
    local img = fake_image(512, 512)
    local from = mark()
    Fx.draw_edition_cell(img, 0, 0, 71, 95, 0, 0, 71, 95, "polychrome", 1.5)
    local meshes = since(from)
    T.assert_eq(#meshes, 2, "one base pass, one additive pass")
    for _, mesh in ipairs(meshes) do
        T.assert_eq(mesh._mode, "strip", "strip meshes")
        T.assert_eq(mesh._texture, img, "polychrome has no pattern sheet: both passes are the art")
        -- 6x7x2 grid vertices plus five stitching pairs, one draw.
        T.assert_eq(#mesh._vertices, 94, "grid strip")
    end
    T.assert_eq(meshes[1]._vertices[1][8], 1, "base pass opaque")
    T.assert_true(meshes[2]._vertices[1][8] < 1, "add pass translucent")
end)

--- Every mesh vertex costs a run of Lua/C boundary crossings in `newMesh`, and meshes
--- are immutable on ctr so each pass rebuilds every frame. An Old 3DS drops to a coarser
--- grid; the strip must still be stitched into one continuous run at either resolution.
suite.test("an Old 3DS builds the field grid at reduced resolution", function()
    local real = _G.love
    local graphics = {}
    for k, v in pairs(real.graphics) do graphics[k] = v end
    graphics.newShader = nil -- LövePotion has none; this is what marks real hardware
    _G.love = setmetatable({ _console = "3DS", graphics = graphics,
        system = { getProcessorCount = function() return 2 end } }, { __index = real })
    Console.reset_cache()

    local ok, err = pcall(function()
        local img = fake_image(512, 512)
        local from = mark()
        Fx.draw_edition_cell(img, 0, 0, 71, 95, 0, 0, 71, 95, "polychrome", 1.5)
        for _, mesh in ipairs(since(from)) do
            -- 4x5x2 grid vertices plus three stitching pairs.
            T.assert_eq(#mesh._vertices, 46, "reduced grid strip")
        end
    end)

    _G.love = real
    Console.reset_cache()
    if not ok then error(err, 0) end
end)

--- The stitch is what keeps the grid a single draw call: each row must start where the
--- previous one ended, so the degenerate pair collapses instead of drawing a stray band.
suite.test("the grid strip stitches rows into one continuous run", function()
    local field = Fx.field_table("polychrome", 1.5)
    local verts = Fx.build_grid(0, 0, 71, 95, 512, 512, 71, 95, 1.5,
        function() return 1, 1, 1, 1 end, field, 0)
    T.assert_eq(#verts, 94, "desktop builds the full grid")

    -- Each row is 2*(grid+1) vertices, followed by the two-vertex stitch on all but the
    -- last row, so a row block is 16 vertices at grid 6.
    local grid, block = 6, 16
    for j = 0, grid - 2 do
        local close = verts[j * block + 2 * (grid + 1) + 1]
        local restart = verts[j * block + 2 * (grid + 1) + 2]
        T.assert_near(close[1], 71, 1e-9, "the stitch closes at the right edge")
        T.assert_near(restart[1], 0, 1e-9, "and restarts at the next row's left edge")
        T.assert_near(close[2], restart[2], 1e-9,
            "both sit on the seam, so the pair collapses to zero area")
        T.assert_near(restart[2], verts[j * block + block + 1][2], 1e-9,
            "the seam is where the next row actually begins")
    end
end)

--- Foil's structure lives in a baked sheet, so its additive pass must sample that sheet
--- and not the art -- that is the whole point of the pattern path.
suite.test("foil sends its additive pass to the pattern sheet", function()
    local art = fake_image(512, 512)
    local sheet = fake_image(256, 512)
    local real_G = _G.G
    _G.G = { ensure_asset_atlas_loaded = function(_, name)
        return name == "edition_foil" and { image = sheet } or nil
    end }

    local from = mark()
    Fx.draw_edition_cell(art, 0, 0, 72, 95, 0, 0, 72, 95, "foil", 0.25, "card", 0)
    local meshes = since(from)
    _G.G = real_G

    T.assert_eq(#meshes, 2, "still two passes")
    T.assert_eq(meshes[1]._texture, art, "the base pass multiplies the art")
    T.assert_eq(meshes[2]._texture, sheet, "the additive pass carries the rings")
    T.assert_eq(#meshes[1]._vertices, 18, "foil's base is the cheap strip")
    T.assert_eq(#meshes[2]._vertices, 18, "and so is its sweep")
end)

--- A sheet that has not been loaded yet must not blank the card.
suite.test("a missing pattern sheet falls back to the art", function()
    local art = fake_image(512, 512)
    local real_G = _G.G
    _G.G = { ensure_asset_atlas_loaded = function() return nil end }

    local from = mark()
    Fx.draw_edition_cell(art, 0, 0, 72, 95, 0, 0, 72, 95, "foil", 0.25, "card", 0)
    local meshes = since(from)
    _G.G = real_G

    T.assert_eq(#meshes, 2, "both passes still run")
    T.assert_eq(meshes[2]._texture, art, "the additive pass degrades to the art")
end)

suite.test("a registered mod edition draws its tint and glow through the same two passes", function()
    for _, anim in ipairs({ "sweep", "shimmer", "pulse", "steady", "rainbow" }) do
        Fx.register_edition("e_test_look", {
            tint = { 0.5, 0.75, 1 }, glow = { 1, 0.5, 0, 0.4 }, animation = anim,
        })
        T.assert_true(Fx.has_edition_fx("e_test_look"), anim)
        local img = fake_image(512, 512)
        local from = mark()
        Fx.draw_edition_cell(img, 0, 0, 72, 95, 0, 0, 72, 95, "e_test_look", 1.25, "card", 0, 0.3)
        local meshes = since(from)
        T.assert_eq(#meshes, 2, anim .. ": one base pass, one additive pass")
        local base, add = meshes[1]._vertices[1], meshes[2]._vertices[1]
        if anim ~= "rainbow" then
            T.assert_eq(base[5], 0.5, anim .. ": the tint multiplies the art")
            T.assert_eq(base[7], 1, anim)
            T.assert_eq(add[5], 1, anim .. ": the glow's colour")
        end
        for _, v in ipairs(meshes[2]._vertices) do
            T.assert_true(v[8] >= 0 and v[8] <= 0.4 + 1e-9, anim .. ": glow never beyond its strength")
        end
        Fx.unregister_edition("e_test_look")
        T.assert_false(Fx.has_edition_fx("e_test_look"))
    end
    -- Unregistering a vanilla name does nothing.
    Fx.unregister_edition("foil")
    T.assert_true(Fx.has_edition_fx("foil"))
end)

suite.test("draw_edition_cell ignores unknown editions", function()
    local from = mark()
    Fx.draw_edition_cell(fake_image(512, 512), 0, 0, 71, 95, 0, 0, 71, 95, "negative", 0)
    T.assert_eq(#since(from), 0, "negative has no mesh passes")
end)

suite.test("shine sweeps briefly then rests", function()
    T.assert_not_nil(Fx.shine_pos(0.0), "sweep starts a period")
    T.assert_not_nil(Fx.shine_pos(0.7), "still sweeping")
    T.assert_nil(Fx.shine_pos(1.5), "resting")
    T.assert_nil(Fx.shine_pos(3.9), "resting until the next period")
    T.assert_not_nil(Fx.shine_pos(4.1), "next period sweeps again")

    local from = mark()
    Fx.draw_shine_cell(fake_image(512, 512), 0, 0, 30, 30, 0, 0, 30, 30, 2.0)
    T.assert_eq(#since(from), 0, "no mesh at all during the rest phase")

    from = mark()
    Fx.draw_shine_cell(fake_image(512, 512), 0, 0, 30, 30, 0, 0, 30, 30, 0.4)
    T.assert_eq(#since(from), 1, "one additive pass mid-sweep")
end)

--------------------------------------------------------------------------------
-- Flames
--------------------------------------------------------------------------------

suite.test("flame_target lights only after the blind is beaten", function()
    T.assert_eq(Fx.flame_target(0, 300), 0, "no score, no fire")
    T.assert_eq(Fx.flame_target(299, 300), 0, "just short of the blind")
    T.assert_eq(Fx.flame_target(500, 0), 0, "no requirement (menus, blind select), no fire")
    T.assert_eq(Fx.flame_target(nil, nil), 0, "missing state is quiet")

    local at_blind = Fx.flame_target(300, 300)
    T.assert_near(at_blind, math.log(300) / math.log(5) - 2, 1e-9,
        "log5 of the earned score, minus the reference's base offset")
    T.assert_true(Fx.flame_target(10000, 300) > at_blind, "overkill burns hotter")
end)

suite.test("update_flame converges on its target and cools back down", function()
    local f = Fx.new_flame(0)
    for _ = 1, 600 do Fx.update_flame(f, 3, 1 / 60) end
    T.assert_near(f.real, 3, 0.2, "spun up to the target after ten seconds")

    local timer_hot = f.timer
    for _ = 1, 600 do Fx.update_flame(f, 0, 1 / 60) end
    T.assert_true(f.real < 0.05, "cooled back to embers")
    T.assert_true(f.timer > timer_hot, "the clock only runs forward")
end)

suite.test("flame clock runs faster at high intensity", function()
    local cold, hot = Fx.new_flame(0), Fx.new_flame(0)
    for _ = 1, 60 do
        Fx.update_flame(cold, 0, 1 / 60)
        Fx.update_flame(hot, 5, 1 / 60)
    end
    T.assert_true(hot.timer > cold.timer,
        "reference flame_handler advances the shader clock 1 + 0.2*intensity")
end)

suite.test("flame_accent matches the reference lick formula", function()
    local chips = { 0, 157 / 255, 1, 1 }
    local yellow = { 1, 1, 0, 1 }
    local accent = Fx.flame_accent(chips, yellow)
    for i = 1, 3 do
        local expected = math.min(math.max(((chips[i] * 0.5 + yellow[i] * 0.5) + 0.1) ^ 2, 0.1), 1)
        T.assert_near(accent[i], expected, 1e-9, "channel " .. i)
    end
    T.assert_eq(accent[4], 1, "accent is opaque")
end)

suite.test("flames track the chips x mult readout and die when it resets to 0 x 0", function()
    local game = bootstrap.new_game(777)
    local top = TopUI()

    -- A scoring hand beating the blind: readout shows 500 x 10 against a 300 blind.
    G.selectedHandChips = 500
    G.selectedHandMult = 10
    G.current_blind_target = 300
    for _ = 1, 300 do top:update_flames(1 / 60) end
    T.assert_true(top.chip_flame.real > 1, "fire while the readout beats the blind")

    -- Scoring ends, panels reset to 0 x 0. Round score stays high — that must NOT
    -- keep the fire lit (regression: flames once tracked G.round_score).
    G.round_score = 1000000
    G.selectedHandChips = 0
    G.selectedHandMult = 0
    for _ = 1, 300 do top:update_flames(1 / 60) end
    T.assert_true(top.chip_flame.real < 0.05, "fire dies with the readout, not the round score")
    T.assert_true(top.mult_flame.real < 0.05, "both flames")
end)

suite.test("draw_flame draws solid pixel columns only when hot", function()
    local rects = {}
    local old_rect = love.graphics.rectangle
    love.graphics.rectangle = function(mode, rx, ry, rw, rh)
        rects[#rects + 1] = { mode = mode, x = rx, y = ry, w = rw, h = rh }
    end

    local ok, err = pcall(function()
        local f = Fx.new_flame(0)
        Fx.draw_flame(f, 10, 100, 60, { 0, 0.6, 1, 1 }, { 0.4, 0.8, 0.4, 1 })
        T.assert_eq(#rects, 0, "a cold flame draws nothing")

        for _ = 1, 240 do Fx.update_flame(f, 4, 1 / 60) end
        Fx.draw_flame(f, 10, 100, 60, { 0, 0.6, 1, 1 }, { 0.4, 0.8, 0.4, 1 })
        T.assert_true(#rects > 0, "a hot flame draws columns")
        for _, r in ipairs(rects) do
            T.assert_eq(r.mode, "fill", "solid fills, not outlines")
            T.assert_eq(r.h % 2, 0, "heights snap to the pixel grid")
            T.assert_true(r.y >= 100 - 46 and r.y + r.h <= 100 + 0.5,
                "columns rise from the base line and stay inside the height budget")
            T.assert_true(r.x >= 10 and r.x + r.w <= 70.5, "columns stay inside the panel width")
        end
    end)

    love.graphics.rectangle = old_rect
    T.assert_no_error(function()
        if not ok then error(err) end
    end)
end)

--------------------------------------------------------------------------------
-- Dissolve / materialize mask
--
-- The shader-free stand-in for `reference/Balatro/resources/shaders/dissolve.fs`. What
-- can be checked without pixels is the vertex data: that the mask erodes as the tween
-- runs, that it eats the card's margins before its middle, and that the burn ring is
-- actually a different colour from the art behind it.
--------------------------------------------------------------------------------

local CELL_W, CELL_H = 71, 95

--- Zero the crowd counter and whatever the current frame has already counted.
---
--- The mask resolution is global state that other test files reach through `Game`: opening a
--- booster declares its burst to `Fx`, and nothing calls `Fx.begin_frame` outside the running
--- game, so a pack test leaves the grid coarse for whoever runs next. Every test here that
--- cares about resolution starts by clearing it rather than trusting file order.
local function clear_crowd()
    Fx.begin_frame()
    Fx.begin_frame()
end

--- Draw one mask at `d` without touching the crowd count, for the tests that are building one.
local function draw_dissolve(d, burn1, burn2)
    local img = fake_image(512, 512)
    local from = mark()
    local drawn = Fx.draw_dissolve_cell(img, 0, 0, CELL_W, CELL_H, 0, 0, CELL_W, CELL_H,
        d, burn1, burn2, 1)
    return drawn, since(from)
end

--- Draw one mask at `d`, at the full grid, and hand back the base pass and the additive pass.
local function dissolve_passes(d, burn1, burn2)
    clear_crowd()
    return draw_dissolve(d, burn1, burn2)
end

--- Total vertex alpha in a pass: how much of the card is still there.
local function alpha_sum(mesh)
    local total = 0
    for _, v in ipairs(mesh._vertices) do total = total + v[8] end
    return total
end

suite.test("a dissolve draws a base pass and a burn pass", function()
    local drawn, meshes = dissolve_passes(0.5)
    T.assert_true(drawn, "the mask reports that it drew")
    T.assert_eq(#meshes, 2, "one masked art pass, one additive burn pass")
    for _, mesh in ipairs(meshes) do
        T.assert_eq(mesh._mode, "strip")
        -- 16x17x2 grid vertices plus fifteen stitching pairs. Far finer than the edition grid:
        -- the mask draws a contour, and a contour needs samples to curve through.
        T.assert_eq(#mesh._vertices, 574, "the dissolve grid")
    end
end)

--- The artifact that made an earlier cut look wrong: a sample that renders opaque while every
--- neighbour renders at nothing interpolates into a diamond, because alpha ramps to zero along
--- every triangle edge leaving it. A card sprinkled with those reads as rhombus confetti.
---
--- The bound is on *when*, not on the count. Measured across the tween these sit at 0.0-0.4%
--- of live samples through the first two thirds and only climb past d = 0.7, by which point the
--- card really has broken into scattered fragments - which is what the base game does too, and
--- what its own late-tween frames look like. Early diamonds are the artifact; late ones are
--- debris. The configuration this replaced had them prominent from the start.
suite.test("diamonds do not appear while the card is still mostly whole", function()
    local half = 0.5 / 80
    local function alpha(v, adj)
        local a = 0.5 + (v - adj) / (2 * half)
        return a > 1 and 1 or (a < 0 and 0 or a)
    end
    for _, d in ipairs({ 0.2, 0.3, 0.45, 0.6 }) do
        local adj = (d * d * (3 - 2 * d)) * 1.02 - 0.01
        for _, grid in ipairs({ 16, 10 }) do
            local isolated, live = 0, 0
            for variant = 1, 4 do
                local f = Fx.dissolve_field_table(variant, grid)
                local stride = grid + 1
                for j = 0, grid do
                    for i = 0, grid do
                        local n = j * stride + i + 1
                        if alpha(f[n], adj) > 0 then
                            live = live + 1
                            local neighbours, dark = 0, 0
                            local function check(m)
                                if m then
                                    neighbours = neighbours + 1
                                    if alpha(f[m], adj) <= 0 then dark = dark + 1 end
                                end
                            end
                            check(i > 0 and n - 1 or nil)
                            check(i < grid and n + 1 or nil)
                            check(j > 0 and n - stride or nil)
                            check(j < grid and n + stride or nil)
                            if neighbours > 0 and alpha(f[n], adj) >= 0.5 and dark == neighbours then
                                isolated = isolated + 1
                            end
                        end
                    end
                end
            end
            T.assert_true(isolated / live < 0.05, string.format(
                "grid %d at d = %.2f: %.1f%% of live samples render as isolated diamonds",
                grid, d, 100 * isolated / live))
        end
    end
end)

--- The softness being traded for that curved contour, pinned so a regression to fog is caught.
--- One Gouraud cell is the floor; measured over the card's interior the 90%-to-10% front is
--- 5.4 px at grid 16. The version that shipped fog had it across most of the card.
suite.test("the front is about one cell wide, not most of the card", function()
    local CELL = 71 / 16
    local _, meshes = dissolve_passes(0.45)
    local verts = meshes[1]._vertices
    local partial, total = 0, 0
    for _, v in ipairs(verts) do
        if v[8] > 0.02 then
            total = total + 1
            if v[8] < 0.98 then partial = partial + 1 end
        end
    end
    T.assert_true(total > 0, "something is still standing at half-tween")
    -- A one-cell ramp puts a minority of live samples mid-fade; fog put nearly all of them.
    T.assert_true(partial / total < 0.45, string.format(
        "%.0f%% of live samples are mid-fade (cell is %.1f px)", 100 * partial / total, CELL))
end)

--- The shadow has to be eaten by the same field as the card, or a solid silhouette sits under
--- a card full of holes (`reference/Balatro/card.lua:4362`, `dissolve.fs:52`).
suite.test("the shadow pass is the same mask in black", function()
    local img = fake_image(512, 512)
    local from = mark()
    T.assert_true(Fx.draw_dissolve_shadow(img, 0, 0, CELL_W, CELL_H, 0, 0, CELL_W, CELL_H,
        0.5, 0.5, 1))
    local meshes = since(from)
    T.assert_eq(#meshes, 1, "one pass; a shadow has no burn to add")

    local from2 = mark()
    Fx.draw_dissolve_cell(img, 0, 0, CELL_W, CELL_H, 0, 0, CELL_W, CELL_H, 0.5, nil, nil, 1)
    local base = since(from2)[1]

    for i, v in ipairs(meshes[1]._vertices) do
        T.assert_eq(v[5], 0, "black")
        T.assert_eq(v[6], 0)
        T.assert_eq(v[7], 0)
        -- Same field, same threshold: the holes line up, at half the opacity.
        T.assert_near(v[8], base._vertices[i][8] * 0.5, 0.0001, "vertex " .. i .. " alpha")
    end
end)

--- `dstate.shadow` is scratch state on a shared table; leaving it set would paint the next
--- card to dissolve solid black.
suite.test("a shadow pass does not leak into the next card", function()
    local img = fake_image(512, 512)
    Fx.draw_dissolve_shadow(img, 0, 0, CELL_W, CELL_H, 0, 0, CELL_W, CELL_H, 0.5, 0.5, 1)
    local from = mark()
    Fx.draw_dissolve_cell(img, 0, 0, CELL_W, CELL_H, 0, 0, CELL_W, CELL_H, 0.5, nil, nil, 1)
    local lit = false
    for _, v in ipairs(since(from)[1]._vertices) do
        if v[5] > 0 then lit = true end
    end
    T.assert_true(lit, "the card after a shadow still draws its art")
end)

--- A card that has finished dissolving is not drawn faintly, it is not drawn.
suite.test("a finished dissolve draws nothing at all", function()
    local drawn, meshes = dissolve_passes(1)
    T.assert_true(drawn, "the caller must not fall back to a plain draw")
    T.assert_eq(#meshes, 0)
end)

--- `dissolve.fs:51` cuts a pixel once the noise threshold passes it, so the visible area
--- only ever shrinks. This is the whole animation; if it is not monotonic the card
--- flickers back into existence partway through.
suite.test("the mask only ever takes more away", function()
    local last
    for _, d in ipairs({ 0.1, 0.3, 0.5, 0.7, 0.9 }) do
        local _, meshes = dissolve_passes(d)
        local present = alpha_sum(meshes[1])
        if last then
            T.assert_true(present < last, "more of the card is gone at d = " .. d)
        end
        last = present
    end
end)

--- `dissolve.fs:38-41` pulls the outer margins under the threshold in proportion to `d`,
--- which is what makes a card burn inward from its edges rather than dissolving evenly.
suite.test("the margins go before the middle, but not instead of it", function()
    local _, meshes = dissolve_passes(0.25)
    local edge_total, edge_n, mid_total, mid_n = 0, 0, 0, 0
    for _, v in ipairs(meshes[1]._vertices) do
        local u, w = v[1] / CELL_W, v[2] / CELL_H
        if u < 0.2 or u > 0.8 or w < 0.2 or w > 0.8 then
            edge_total, edge_n = edge_total + v[8], edge_n + 1
        else
            mid_total, mid_n = mid_total + v[8], mid_n + 1
        end
    end
    T.assert_true(edge_n > 0 and mid_n > 0, "samples on both sides of the margin")
    T.assert_true(edge_total / edge_n < mid_total / mid_n,
        "the margin is further gone than the middle")
    -- ...but not so much further that the card reads as eaten from the sides: the shader's
    -- border term is weak early, so interior holes open while most of the border stands.
    T.assert_true(edge_total / edge_n > 0.5,
        "most of the border is still standing this early in the tween")
end)

--- `dissolve.fs:44-50` paints the pixels either side of the cut in the burn colours,
--- which is the part of the effect that reads at 240p. Interior vertices carry a
--- greyscale multiply instead, so a coloured vertex is a ring vertex.
suite.test("the burn ring is coloured and the art behind it is not", function()
    local red, blue = { 1, 0, 0 }, { 0, 0, 1 }
    local _, meshes = dissolve_passes(0.5, red, blue)
    local ring, grey = 0, 0
    for _, v in ipairs(meshes[1]._vertices) do
        if v[8] > 0 then
            if v[5] == v[6] and v[6] == v[7] then grey = grey + 1 else ring = ring + 1 end
        end
    end
    T.assert_true(ring > 0, "some of the front is burning")
    T.assert_true(grey > 0, "and the rest of the card is still the art")
end)

--- The other half of `dissolve.fs:59-65`: what a multiply cannot do, the additive pass
--- does. It has to grow with `d` or the card just fades instead of catching.
suite.test("the burn wash builds as the card goes", function()
    local function wash(d)
        local _, meshes = dissolve_passes(d)
        -- The centre vertex is the last thing the ring reaches, so it carries the wash
        -- rather than the ring colour for most of the tween.
        local best = 0
        for _, v in ipairs(meshes[2]._vertices) do
            local u, w = v[1] / CELL_W, v[2] / CELL_H
            if u > 0.4 and u < 0.6 and w > 0.4 and w < 0.6 then best = math.max(best, v[8]) end
        end
        return best
    end
    T.assert_true(wash(0.5) > wash(0.15), "there is more burn on it later")
end)

--- The jank this replaced. The shader tests band membership per pixel, so its burn ring is a
--- hard edge that still moves smoothly because there are thousands of pixels. Classifying per
--- *vertex* the same way put the ring's position on the grid: a corner flipped from art to
--- burn in one step and the cells around it jumped with it, once per vertex per tween.
---
--- The invariant that catches a return to that is continuity, not slowness. The mask is
--- allowed to move fast - the shader's own cut is infinitely fast - but it has to be a
--- continuous function of `d`, so halving the step has to halve the largest jump. A hard
--- classification floors out instead: refine the sweep as far as you like and a vertex still
--- crosses the whole distance between the art tint and a burn colour in one step.
suite.test("the burn front is continuous in the tween, not classified per vertex", function()
    local function worst_jump(steps)
        local prev, worst = nil, 0
        for i = 0, steps do
            local _, meshes = dissolve_passes(i / steps, { 1, 0, 0 }, { 0, 0, 1 })
            local verts = meshes[1] and meshes[1]._vertices
            if prev and verts then
                for k, v in ipairs(verts) do
                    -- Premultiplied, because that is what reaches the framebuffer: a vertex
                    -- whose alpha is already zero may hold any colour without it being seen,
                    -- and the dead-sample early-out takes advantage of that.
                    local p = prev[k]
                    for c = 5, 7 do
                        local jump = math.abs(v[c] * v[8] - p[c] * p[8])
                        if jump > worst then worst = jump end
                    end
                    local jump = math.abs(v[8] - p[8])
                    if jump > worst then worst = jump end
                end
            end
            prev = verts
        end
        return worst
    end

    local coarse = worst_jump(200)
    local fine = worst_jump(2000)
    T.assert_true(fine * 5 < coarse,
        string.format("ten times the resolution has to shrink the jump: %.4f then %.4f",
            coarse, fine))
end)

--- The look being matched is swiss cheese, not one growing blob: the shader's field puts
--- seven to eleven waves across a card, so mid-tween it has several disjoint holes at once.
--- Tiles are independent - no interpolation forces neighbours to agree - so the field can
--- carry enough waves for that. This counts 4-connected dead regions at mid-tween.
suite.test("mid-tween the card has several separate holes", function()
    for variant = 1, 4 do
        local f, grid = Fx.dissolve_field_table(variant)
        local stride = grid + 1
        local adj = (0.45 * 0.45 * (3 - 2 * 0.45)) * 1.02 - 0.01
        local seen, holes = {}, 0
        for j = 0, grid do
            for i = 0, grid do
                local n = j * stride + i + 1
                if f[n] <= adj and not seen[n] then
                    holes = holes + 1
                    local stack = { n }
                    while #stack > 0 do
                        local c = table.remove(stack)
                        if not seen[c] and f[c] <= adj then
                            seen[c] = true
                            local ci, cj = (c - 1) % stride, math.floor((c - 1) / stride)
                            if ci > 0 then stack[#stack + 1] = c - 1 end
                            if ci < grid then stack[#stack + 1] = c + 1 end
                            if cj > 0 then stack[#stack + 1] = c - stride end
                            if cj < grid then stack[#stack + 1] = c + stride end
                        end
                    end
                end
            end
        end
        T.assert_true(holes >= 3, string.format(
            "variant %d has %d holes at half-tween; a single blob is the failure this guards",
            variant, holes))
    end
end)

--- The schedule has to be the base game's, and this is the test that says so.
---
--- What has to match is *when* a card is half gone, not which half: the port has 81 samples
--- where the shader has 6745, so it has to choose its own pattern. But it was empty by d = 0.6
--- where the shader still has a third of the card, and then sat invisible for the rest of the
--- tween - and a materialise is that curve backwards, so a booster pack showed nothing for the
--- first 40% of the fade and then cards arriving at half strength.
---
--- The expected numbers are `dissolve.fs` itself, sampled per pixel over a 70x94 sprite across
--- all four noise variants, with its own `floored_uv` normalisation and its own border term.
--- `REFERENCE_ERODE_SCHEDULE` is the inverse of that curve, baked into the field.
suite.test("the card erodes on the base game's schedule", function()
    local EXPECTED = {
        [0.15] = 88, [0.3] = 73, [0.45] = 50, [0.6] = 31, [0.75] = 18, [0.9] = 5,
    }
    for _, grid in ipairs({ 16, 10 }) do
        for _, d in ipairs({ 0.15, 0.3, 0.45, 0.6, 0.75, 0.9 }) do
            -- The threshold the shipped code compares against, used raw: the ramp's headroom
            -- lives in the field rather than in the threshold.
            local adj = (d * d * (3 - 2 * d)) * 1.02 - 0.01
            local alive, n = 0, 0
            for variant = 1, 4 do
                local f = Fx.dissolve_field_table(variant, grid)
                for i = 1, #f do
                    if f[i] > adj then alive = alive + 1 end
                    n = n + 1
                end
            end
            local pct = 100 * alive / n
            -- Five points of slack: a few hundred samples cannot land on a per-pixel curve
            -- exactly, and the failure this guards against was thirty points wide.
            T.assert_true(math.abs(pct - EXPECTED[d]) <= 5, string.format(
                "grid %d at d = %.2f: %.0f%% standing, base game has %d%%",
                grid, d, pct, EXPECTED[d]))
        end
    end
end)

--- A materialise is the same curve read backwards, so a schedule that is wrong at the end of a
--- dissolve is wrong at the *start* of a fade-in - which is the half the player is watching.
--- The criterion here is the renderer's, not the schedule's: a sample is on screen while its
--- alpha is above zero, which is EDGE_HALF_WIDTH short of where it leaves the schedule.
suite.test("a materialise is on screen from its first frame", function()
    local half = 0.5 / 90
    -- d = 0.9 is where the base game first has anything to show: sampled per pixel it holds 5%
    -- of the card there and is completely empty by 0.95, so the opening tenth of a materialise
    -- is blank in the shipping game too. This is about matching that, not beating it.
    for _, d in ipairs({ 0.9 }) do
        local adj = (d * d * (3 - 2 * d)) * 1.02 - 0.01
        for variant = 1, 4 do
            local f = Fx.dissolve_field_table(variant)
            local lit = 0
            for i = 1, #f do if f[i] - adj > -half then lit = lit + 1 end end
            T.assert_true(lit > 0, string.format(
                "variant %d has nothing on screen at d = %.2f", variant, d))
        end
    end
end)

--- And the other end: a card that has not started dissolving is a card, not a faint one.
suite.test("a card at rest is fully opaque everywhere", function()
    local half = 0.5 / 90
    local adj = -0.01
    for _, grid in ipairs({ 16, 10 }) do
        for variant = 1, 4 do
            for _, v in ipairs(Fx.dissolve_field_table(variant, grid)) do
                T.assert_true(v - adj >= half, string.format(
                    "grid %d variant %d: a sample is already fading at d = 0", grid, variant))
            end
        end
    end
end)

--- `dissolve.fs:22` smoothsteps the threshold and stretches it past both ends so the mask
--- does not stall at 0 and 1. At d = 0 nothing has gone yet.
suite.test("a card at the very start of a dissolve is whole", function()
    local _, meshes = dissolve_passes(0)
    T.assert_eq(#meshes, 1, "nothing to add before the burn has any colour in it")
    for _, v in ipairs(meshes[1]._vertices) do
        T.assert_eq(v[8], 1, "every sample is still present")
        T.assert_eq(v[5], 1, "and untinted")
    end
end)

--- Two nodes coming apart at once must not come apart identically. The reference seeds
--- the field off the card's ID (`sprite.lua:100`); the variant index stands in for it.
suite.test("noise variants cycle and wrap", function()
    local seen = {}
    for seed = 0, 8 do seen[Fx.dissolve_variant(seed)] = true end
    local count = 0
    for _ in pairs(seen) do count = count + 1 end
    T.assert_true(count > 1, "consecutive lifecycles do not share a field")
    T.assert_eq(Fx.dissolve_variant(0), Fx.dissolve_variant(4), "and the set is bounded")
end)

--- Different fields, same erosion behaviour: a variant that eroded in a different order
--- would be fine, one that did not erode at all would not.
suite.test("every variant erodes", function()
    local img = fake_image(512, 512)
    for seed = 1, 4 do
        local from = mark()
        Fx.draw_dissolve_cell(img, 0, 0, CELL_W, CELL_H, 0, 0, CELL_W, CELL_H, 0.2, nil, nil, seed)
        local early = alpha_sum(since(from)[1])
        from = mark()
        Fx.draw_dissolve_cell(img, 0, 0, CELL_W, CELL_H, 0, 0, CELL_W, CELL_H, 0.8, nil, nil, seed)
        T.assert_true(alpha_sum(since(from)[1]) < early, "variant " .. seed .. " erodes")
    end
end)

--- The whole-image form has to draw the same rectangle `love.graphics.draw(image, x, y)`
--- would, because cell UVs against a padded t3x do not (`Fx.draw_edition_image`).
suite.test("the whole-image form spans the reported dimensions", function()
    local img = fake_image(70, 94)
    local from = mark()
    T.assert_true(Fx.draw_dissolve_image(img, 12, 34, 0.5))
    local mesh = since(from)[1]
    local max_x, max_y = 0, 0
    for _, v in ipairs(mesh._vertices) do
        max_x, max_y = math.max(max_x, v[1]), math.max(max_y, v[2])
    end
    T.assert_eq(max_x, 70)
    T.assert_eq(max_y, 94)
end)

--------------------------------------------------------------------------------
-- Dissolve cost at scale
--
-- One dissolve was what the mask was tuned against; a Mega booster lands five at once, and
-- the vertex build and the colour math are both per card. These pin the two things that make
-- five affordable - the per-sample colour bake and the crowd resolution drop - including that
-- neither of them changes what a lone, watched dissolve looks like.
--------------------------------------------------------------------------------

--- Baking colours per field sample is only worth doing if it is the same picture. `build_grid`
--- keeps the per-vertex `color_fn` path for the edition passes, so the two can be compared
--- directly on the same field.
suite.test("the baked colour path matches evaluating per vertex", function()
    local field = Fx.dissolve_field_table(1, 6)
    local fn = function(f, n)
        local v = f[n] or 0
        return v, 1 - v, v * 0.5, 1 - v * 0.25
    end
    local colors = {}
    for n = 1, #field do
        local r, g, b, a = fn(field, n)
        local k = (n - 1) * 4
        colors[k + 1], colors[k + 2], colors[k + 3], colors[k + 4] = r, g, b, a
    end

    local per_vertex = {}
    for i, v in ipairs(Fx.build_grid(0, 0, CELL_W, CELL_H, 512, 512, CELL_W, CELL_H, 0,
        fn, field, 0, 6)) do
        per_vertex[i] = { v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8] }
    end
    local baked = Fx.build_grid(0, 0, CELL_W, CELL_H, 512, 512, CELL_W, CELL_H, 0,
        nil, field, 0, 6, colors)

    T.assert_eq(#baked, #per_vertex, "same strip either way")
    for i = 1, #baked do
        T.assert_deep_eq({ baked[i][1], baked[i][2], baked[i][3], baked[i][4],
            baked[i][5], baked[i][6], baked[i][7], baked[i][8] }, per_vertex[i],
            "vertex " .. i .. " is identical")
    end
end)

--- The additive burn pass reuses the base pass's strip, so it has to leave every position
--- and UV exactly where the build put them and change nothing but colour. Getting that wrong
--- would shift the burn ring off the art it is supposed to be sitting on.
suite.test("recolouring a grid touches colours and nothing else", function()
    local field = Fx.dissolve_field_table(1, 6)
    local built = Fx.build_grid(0, 0, CELL_W, CELL_H, 512, 512, CELL_W, CELL_H, 0,
        function() return 1, 1, 1, 1 end, field, 0, 6)
    local geometry = {}
    for i, v in ipairs(built) do geometry[i] = { v[1], v[2], v[3], v[4] } end

    local colors = {}
    for n = 1, #field do
        local k = (n - 1) * 4
        colors[k + 1], colors[k + 2], colors[k + 3], colors[k + 4] = n * 0.001, 0.25, 0.5, 0.75
    end
    -- Snapshotted, because `recolor_grid` and `build_grid` hand back the same pooled table:
    -- comparing the two live would compare a table with itself and pass on anything.
    local recoloured = {}
    for i, v in ipairs(Fx.recolor_grid(built, colors, 6)) do
        recoloured[i] = { v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8] }
    end

    -- Against a full rebuild with the same colours: the two must be indistinguishable.
    local rebuilt = Fx.build_grid(0, 0, CELL_W, CELL_H, 512, 512, CELL_W, CELL_H, 0,
        nil, field, 0, 6, colors)
    T.assert_eq(#recoloured, #rebuilt)
    for i = 1, #rebuilt do
        T.assert_deep_eq({ recoloured[i][1], recoloured[i][2], recoloured[i][3],
            recoloured[i][4] }, geometry[i], "vertex " .. i .. " kept its geometry")
        for c = 5, 8 do
            T.assert_near(recoloured[i][c], rebuilt[i][c], 1e-12,
                "vertex " .. i .. " component " .. c)
        end
    end
end)

--- The whole point of reading the count a frame late: a card's base, additive and shadow
--- passes have to agree on a resolution, and they only agree because the count cannot move
--- between them.
suite.test("a lone dissolve keeps the full grid", function()
    clear_crowd()
    local _, meshes = draw_dissolve(0.5)
    for _, mesh in ipairs(meshes) do
        T.assert_eq(#mesh._vertices, 574, "grid 16")
    end
    Fx.begin_frame()
    T.assert_eq(Fx.dissolve_crowd(), 1, "one card counted, well under the threshold")
    clear_crowd()
end)

--- Two overlapping dissolves is ordinary play - a card destroyed while another arrives - so
--- the threshold has to sit above it.
suite.test("two dissolves still get the full grid", function()
    clear_crowd()
    for _ = 1, 2 do draw_dissolve(0.5) end
    Fx.begin_frame()
    T.assert_eq(Fx.dissolve_crowd(), 2)
    local _, meshes = draw_dissolve(0.5)
    T.assert_eq(#meshes[1]._vertices, 574, "still grid 16")
    clear_crowd()
end)

--- A Mega pack. Grid 16 to 10 takes a pass from 574 vertices to 238, and there are two or
--- three passes a card, so five cards go from ~8600 vertex builds a frame to ~3600.
suite.test("a crowd of dissolves drops the mask a resolution step", function()
    clear_crowd()
    for _ = 1, 5 do draw_dissolve(0.5) end
    Fx.begin_frame()
    T.assert_eq(Fx.dissolve_crowd(), 5, "the burst is counted")

    local _, meshes = draw_dissolve(0.5)
    for _, mesh in ipairs(meshes) do
        -- 10x11x2 grid vertices plus nine stitching pairs.
        T.assert_eq(#mesh._vertices, 238, "grid 10 while crowded")
    end
    clear_crowd()
end)

--- And it has to come back, or every dissolve after the first pack is coarse forever.
suite.test("the fine grid returns once the crowd thins", function()
    clear_crowd()
    for _ = 1, 5 do draw_dissolve(0.5) end
    Fx.begin_frame()
    T.assert_eq(#select(2, draw_dissolve(0.5))[1]._vertices, 238, "crowded")
    Fx.begin_frame()
    local _, meshes = draw_dissolve(0.5)
    T.assert_eq(#meshes[1]._vertices, 574, "back to grid 16")
    clear_crowd()
end)

--- The shadow is the same card's silhouette and must come apart on exactly the same holes.
--- At a different resolution it would sample a different field and show through the card.
suite.test("the shadow pass uses the same grid as the card it sits under", function()
    clear_crowd()
    for _ = 1, 5 do draw_dissolve(0.5) end
    Fx.begin_frame()

    local img = fake_image(512, 512)
    local from = mark()
    T.assert_true(Fx.draw_dissolve_shadow(img, 0, 0, CELL_W, CELL_H, 0, 0, CELL_W, CELL_H,
        0.5, 0.5, 1))
    T.assert_eq(#since(from)[1]._vertices, 238, "the shadow is crowded too")
    clear_crowd()
end)

--- Counting is a frame behind, which is right for a burst that builds and wrong for one that
--- arrives whole. A booster releases every card on one frame - the frame the player is
--- watching - so it declares the burst rather than being counted into it a frame too late.
suite.test("a declared burst is coarse from its very first frame", function()
    clear_crowd()
    local _, before = draw_dissolve(0.5)
    T.assert_eq(#before[1]._vertices, 574, "nothing declared, so the full grid")

    clear_crowd()
    Fx.expect_dissolves(5)
    local _, meshes = draw_dissolve(0.5)
    for _, mesh in ipairs(meshes) do
        T.assert_eq(#mesh._vertices, 238, "already at crowd resolution")
    end
    clear_crowd()
end)

--- Declaring fewer cards than are actually on screen must not talk the grid back up.
suite.test("a declaration never lowers a crowd already counted", function()
    clear_crowd()
    for _ = 1, 5 do draw_dissolve(0.5) end
    Fx.begin_frame()
    Fx.expect_dissolves(1)
    T.assert_eq(Fx.dissolve_crowd(), 5, "the five that are really there still win")
    clear_crowd()
end)

--- Baking a field costs a `build_field` plus a sort, and a burst is several cards asking for
--- an uncached one on the same frame. Prewarming moves that off the frame the burst starts on.
---
--- Both resolutions, not just the coarse one: a burst's first frame is drawn at the fine grid
--- unless it was declared, so leaving those unbaked would just move the hitch by a frame.
suite.test("prewarming builds the fields at both resolutions", function()
    -- From empty, or the assertion is met by whatever earlier tests happened to bake.
    Fx.reset_dissolve_fields()
    T.assert_false(Fx.dissolve_field_cached(1, 16), "the cache really is empty to start")

    Fx.prewarm_dissolve()
    for variant = 1, 4 do
        -- Asked of the cache, not of the builder: `dissolve_field_table` would bake the field
        -- on the spot and report success whether or not prewarming had done anything.
        T.assert_true(Fx.dissolve_field_cached(variant, 16),
            "variant " .. variant .. " is baked at the full grid")
        T.assert_true(Fx.dissolve_field_cached(variant, 10),
            "variant " .. variant .. " is baked at the crowd grid")
    end
    T.assert_eq(#Fx.dissolve_field_table(1, 16), 289, "grid 16 has 17x17 samples")
    T.assert_eq(#Fx.dissolve_field_table(1, 10), 121, "grid 10 has 11x11 samples")
    clear_crowd()
end)

suite.test("hardware UV space pads to powers of two", function()
    -- On ctr the GPU texture is NextPo2-padded while getDimensions reports the source
    -- size; mesh UVs must divide by the padded size or the art shrinks on-device.
    local Fx = require("fx")
    local w, h = Fx.padded_uv_dimensions(70, 94)
    T.assert_eq(w, 128, "joker sprite width pads to 128")
    T.assert_eq(h, 128, "joker sprite height pads to 128")
    w, h = Fx.padded_uv_dimensions(1024, 512)
    T.assert_eq(w, 1024, "power-of-two atlas width is unchanged")
    T.assert_eq(h, 512, "power-of-two atlas height is unchanged")
    w, h = Fx.padded_uv_dimensions(1, 8)
    T.assert_eq(w, 8, "t3x minimum edge is 8")
    T.assert_eq(h, 8, "t3x minimum edge is 8")
end)

return suite
