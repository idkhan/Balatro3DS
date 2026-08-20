--- `Game:atlas_cell_quad` carries the two things that make grid atlases work on hardware:
--- declared grid geometry (because `getDimensions` reports the padded runtime size on
--- console) and a per-index quad cache (because the callers are in the draw path).

local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

--- Stands in for a loaded atlas. `reported` is what `getDimensions` answers, which on
--- hardware is the power-of-two padded size, not the source PNG's.
local function fake_atlas(px, py, cols, rows, reported_w, reported_h)
    return {
        px = px, py = py, cols = cols, rows = rows,
        image = {
            getDimensions = function() return reported_w, reported_h end,
        },
    }
end

suite.test("declared columns win over the padded runtime size", function()
    local game = bootstrap.new_game(1)

    -- BlindChips.png: 864x1008 on disk, 24 columns of 36 px, padded to 1024x1024 in memory.
    -- Deriving the grid from the padded width finds 28 columns and lands cell 24 at
    -- (864, 0) instead of (0, 36) -- inside the padding, off the artwork entirely.
    local atlas = fake_atlas(36, 36, 24, 28, 1024, 1024)

    local first_of_second_row = game:atlas_cell_quad(atlas, 24)
    local x, y = first_of_second_row:getViewport()
    T.assert_eq(x, 0, "cell 24 starts a new row")
    T.assert_eq(y, 36, "and sits one cell down")

    local last_of_first_row = game:atlas_cell_quad(atlas, 23)
    local lx, ly = last_of_first_row:getViewport()
    T.assert_eq(lx, 23 * 36, "cell 23 is the last of the first row")
    T.assert_eq(ly, 0, "still on row zero")
end)

suite.test("the quad's source size is the padded size the sampler sees", function()
    local game = bootstrap.new_game(1)
    local atlas = fake_atlas(36, 36, 24, 28, 1024, 1024)
    local sw, sh = game:atlas_cell_quad(atlas, 0):getTextureDimensions()
    T.assert_eq(sw, 1024, "quads normalise against the real texture width")
    T.assert_eq(sh, 1024, "and height")
end)

suite.test("a repeated index returns the same quad rather than a new one", function()
    local game = bootstrap.new_game(1)
    local atlas = fake_atlas(36, 36, 24, 28, 1024, 1024)
    local a = game:atlas_cell_quad(atlas, 7)
    local b = game:atlas_cell_quad(atlas, 7)
    T.assert_eq(a, b, "the draw path must not allocate a quad per frame")
    T.assert_eq(game:atlas_cell_quad(atlas, 8) ~= a, true, "different cells stay distinct")
end)

suite.test("the cache is dropped when the reported dimensions change", function()
    local game = bootstrap.new_game(1)
    local w, h = 1024, 1024
    local atlas = {
        px = 36, py = 36, cols = 24, rows = 28,
        image = { getDimensions = function() return w, h end },
    }
    local before = game:atlas_cell_quad(atlas, 3)
    w, h = 512, 512
    local after = game:atlas_cell_quad(atlas, 3)
    T.assert_eq(before ~= after, true, "a reload at a new size must not reuse stale quads")
    local _, sh = after:getTextureDimensions()
    T.assert_eq(sh, 512, "the rebuilt quad normalises against the new size")
end)

suite.test("an out-of-range index falls back to the first cell", function()
    local game = bootstrap.new_game(1)
    local atlas = fake_atlas(36, 36, 24, 28, 1024, 1024)
    local x, y = game:atlas_cell_quad(atlas, 24 * 28):getViewport()
    T.assert_eq(x, 0, "past the last cell, clamp to cell zero")
    T.assert_eq(y, 0, "on both axes")
end)

suite.test("an unloaded or malformed atlas yields no quad", function()
    local game = bootstrap.new_game(1)
    T.assert_eq(game:atlas_cell_quad(nil, 0), nil, "no atlas")
    T.assert_eq(game:atlas_cell_quad({ px = 36, py = 36 }, 0), nil, "no image")
    T.assert_eq(game:atlas_cell_quad(fake_atlas(0, 36, 4, 4, 128, 128), 0), nil, "zero cell width")
end)

--- Without a declared `cols` the helper still has to work -- the fallback is what the
--- single-sprite consumable atlases rely on, where source and padded size agree.
suite.test("undeclared geometry falls back to dividing the image", function()
    local game = bootstrap.new_game(1)
    local atlas = { px = 64, py = 128, image = { getDimensions = function() return 128, 256 end } }
    local x, y = game:atlas_cell_quad(atlas, 3):getViewport()
    T.assert_eq(x, 64, "cell 3 of a 2x2 grid is column 1")
    T.assert_eq(y, 128, "row 1")
end)

--- Unloading an atlas releases its image; the quads it cached name that image's dimensions
--- and must not survive it (`game.lua`, `Game:unload_animation_atlas`).
suite.test("unloading an atlas drops its quad cache", function()
    local game = bootstrap.new_game(1)
    local atlas = game:ensure_animation_atlas_loaded("blind_chips")
    if not atlas or not atlas.image then return end
    game:atlas_cell_quad(atlas, 0)
    T.assert_eq(atlas._quads ~= nil, true, "the cache exists after a draw")
    game:unload_animation_atlas("blind_chips")
    T.assert_eq(atlas._quads, nil, "and is gone after the unload")
end)

return suite
