--- Joker fronts that ship shorter than the cell they are packed in.
---
--- Half Joker, Square Joker and Photograph are drawn as short cards, and their art sits at
--- the top of a full-height atlas cell with transparent padding underneath. The reference
--- gets away with knowing nothing about that -- it leaves them hanging from the top of the
--- slot and masks every effect to the sprite's alpha in a fragment shader. There is no
--- fragment stage and no stencil on the PICA200, so here the art is centred in the slot and
--- the rectangular overlays (edition silhouette, debuff X, focus outline, tooltip anchor)
--- are told its real height.
---
--- Pixels need hardware. What is pinned here is the geometry every one of those overlays
--- derives from, and the one place it changes a mesh.

local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

local love = bootstrap.load()
local Fx = _G.Fx

--- The measured alpha heights of the three short fronts, out of a 94 px cell. Taken from
--- `resources/textures/1x/Jokers/` and cross-checked against the reference atlas cells
--- (`reference/.../1x/Jokers.png` at 7,0 / 9,11 / 8,13). If an art update moves one of
--- these, this is the test that should fail rather than a foil sheen quietly detaching.
local SHORT = {
    j_half = 60,
    j_square = 69,
    j_photograph = 78,
}

local function joker(id)
    local def = JOKER_DEFS[id]
    assert(def, "no such joker: " .. tostring(id))
    return Joker(0, 0, Joker.SPRITE_W, Joker.SPRITE_H, def)
end

suite.test("a full-size front reports the whole cell and no offset", function()
    for _, id in ipairs({ "j_joker", "j_blueprint", "j_canio" }) do
        local art_h, off = joker(id):get_art_metrics()
        T.assert_eq(art_h, Joker.SPRITE_H, id .. " fills the cell")
        T.assert_eq(off, 0, id .. " needs no offset")
    end
end)

suite.test("the three short fronts report their measured art height", function()
    for id, h in pairs(SHORT) do
        local art_h = joker(id):get_art_metrics()
        T.assert_eq(art_h, h, id .. " art height")
    end
end)

--- Centred, not top- or bottom-anchored: near-equal padding above and below is what lets the
--- popup and tooltip anchors keep using the cell's centre, since the two coincide. "Near"
--- because the offset is floored to a whole pixel, so an odd amount of padding leaves one
--- extra row at the bottom rather than putting the sprite on a half texel.
suite.test("short art is centred in the slot, on a whole pixel", function()
    for id in pairs(SHORT) do
        local art_h, off = joker(id):get_art_metrics()
        T.assert_eq(off, math.floor(off), id .. " offset is a whole pixel")
        local slack = Joker.SPRITE_H - (off * 2 + art_h)
        T.assert_true(slack == 0 or slack == 1,
            id .. " pads equally top and bottom, give or take the rounded pixel")
        T.assert_true(math.abs((off + art_h / 2) - Joker.SPRITE_H / 2) <= 0.5,
            id .. " art centre is the cell centre")
    end
end)

suite.test("no other joker in the catalog is short", function()
    for id in pairs(JOKER_DEFS) do
        if not SHORT[id] then
            local art_h = joker(id):get_art_metrics()
            T.assert_eq(art_h, Joker.SPRITE_H, id .. " is full height")
        end
    end
end)

--------------------------------------------------------------------------------
-- The edition passes
--------------------------------------------------------------------------------

local function fake_image(w, h)
    return { getDimensions = function() return w, h end }
end

local function mark() return #love._test.meshes end
local function since(from)
    local out = {}
    for i = from + 1, #love._test.meshes do out[#out + 1] = love._test.meshes[i] end
    return out
end

--- Largest y any vertex in the mesh reaches, i.e. how far down the card the pass paints.
local function bottom(mesh)
    local y = -math.huge
    for _, v in ipairs(mesh._vertices) do if v[2] > y then y = v[2] end end
    return y
end

--- The pattern sheet is a baked asset the headless suite has no atlas registry for, and
--- `draw_edition` falls back to sampling the art when it is missing -- which is exactly the
--- path that does not need cropping. Stub it so the silhouette branch is the one under test.
local function with_pattern_sheet(sheet, fn)
    local real = Fx.pattern_image
    Fx.pattern_image = function() return sheet end
    local ok, err = pcall(fn)
    Fx.pattern_image = real
    if not ok then error(err, 0) end
end

--- Foil's additive pass samples a baked full-card silhouette, so it is the one pass that
--- cannot discover the art ends early. Uncropped it hangs 34 px below Half Joker.
suite.test("a short front crops the additive silhouette and leaves the base pass alone", function()
    local img, sheet = fake_image(70, 94), fake_image(256, 512)
    with_pattern_sheet(sheet, function()
        local from = mark()
        Fx.draw_edition_image(img, 0, 0, "foil", 1.5, 0, 0, 60)
        local meshes = since(from)
        T.assert_eq(#meshes, 2, "one base pass, one additive pass")
        T.assert_eq(meshes[1]._texture, img, "the base pass is the art")
        T.assert_eq(meshes[2]._texture, sheet, "the additive pass is the baked silhouette")
        T.assert_near(bottom(meshes[1]), 94, 1e-9, "the base pass spans the sprite it samples")
        T.assert_near(bottom(meshes[2]), 60, 1e-9, "the silhouette stops at the art")
    end)
end)

suite.test("omitting the art height leaves both passes spanning the sprite", function()
    local img, sheet = fake_image(70, 94), fake_image(256, 512)
    with_pattern_sheet(sheet, function()
        local from = mark()
        Fx.draw_edition_image(img, 0, 0, "foil", 1.5, 0, 0)
        for _, mesh in ipairs(since(from)) do
            T.assert_near(bottom(mesh), 94, 1e-9, "full-height pass")
        end
    end)
end)

--- Without the sheet the additive pass samples the art, and the art's own alpha already
--- stops where the card does; cropping there would squash the texture.
suite.test("the missing-sheet fallback is not cropped", function()
    local img = fake_image(70, 94)
    with_pattern_sheet(nil, function()
        local from = mark()
        Fx.draw_edition_image(img, 0, 0, "foil", 1.5, 0, 0, 60)
        for _, mesh in ipairs(since(from)) do
            T.assert_eq(mesh._texture, img, "fell back to the art")
            T.assert_near(bottom(mesh), 94, 1e-9, "full-height pass")
        end
    end)
end)

--- Polychrome has no pattern sheet: its additive pass samples the art, whose own alpha
--- already stops where the card does. Cropping it there would squash the texture instead.
suite.test("polychrome ignores the art height", function()
    local img = fake_image(70, 94)
    local from = mark()
    Fx.draw_edition_image(img, 0, 0, "polychrome", 1.5, 0, 0, 60)
    local meshes = since(from)
    T.assert_eq(#meshes, 2, "both passes still run")
    for _, mesh in ipairs(meshes) do
        T.assert_eq(mesh._texture, img, "both passes sample the art")
        T.assert_near(bottom(mesh), 94, 1e-9, "and both span it")
    end
end)

return suite
