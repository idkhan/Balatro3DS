--- Texture residency: what is resident at boot, and what is handed back on the way out.
---
--- An Old 3DS application gets 64 MB total and the GPU pads every texture to a power of
--- two, so a sheet's cost on hardware is not its size on disk. BlindChips.png is the
--- extreme case: 864x1008 becomes 1024x1024, or 4 MiB, to serve 36x36 cells. Anything
--- loaded before it is needed, or never freed once it is not, is that budget spent for
--- nothing -- and it is invisible on desktop, which is why it needs a test.

local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

bootstrap.load()

--------------------------------------------------------------------------------

suite.test("no atlas is resident before something asks for it", function()
    local g = bootstrap.new_game(4242)

    for name, atlas in pairs(g.ANIMATION_ATLAS) do
        T.assert_eq(atlas.image, nil,
            "animation atlas '" .. name .. "' should be lazy, not loaded during Game()")
    end
    for name, atlas in pairs(g.ASSET_ATLAS) do
        T.assert_eq(atlas.image, nil,
            "asset atlas '" .. name .. "' should be lazy, not loaded during Game()")
    end
end)

--- The blind chips used to be eager purely because the draw path read the registry
--- directly and would silently draw nothing against a lazy entry.
suite.test("drawing a blind chip loads its sheet on demand", function()
    local g = bootstrap.new_game(4243)
    T.assert_eq(g.ANIMATION_ATLAS.blind_chips.image, nil, "not resident at boot")

    g:draw_blind_chip_sprite(0, 160, 120, 1)
    T.assert_not_nil(g.ANIMATION_ATLAS.blind_chips.image,
        "the first blind drawn should bring the sheet in")
end)

suite.test("returning to the main menu hands back the run's textures", function()
    local g = bootstrap.new_game(4244)

    local freed = {
        "cards_1", "cards_2", "Booster", "Voucher", "stickers",
        "centers", "tags", "edition_foil", "edition_holo",
    }
    for _, name in ipairs(freed) do
        g:ensure_asset_atlas_loaded(name)
        T.assert_not_nil(g.ASSET_ATLAS[name].image, name .. " should load on demand")
    end
    g:ensure_animation_atlas_loaded("blind_chips")
    g:ensure_animation_atlas_loaded("shop_sign")

    g:clear_run_assets_for_main_menu()

    for _, name in ipairs(freed) do
        T.assert_eq(g.ASSET_ATLAS[name].image, nil,
            name .. " should not outlive the run that loaded it")
    end
    T.assert_eq(g.ANIMATION_ATLAS.blind_chips.image, nil, "4 MiB of blind art is freed too")
    T.assert_eq(g.ANIMATION_ATLAS.shop_sign.image, nil, "and the shop sign with it")
end)

--- The main menu draws `chips` itself, so freeing it on the way back to the menu would
--- hand back a texture the very next frame reloads.
suite.test("the menu's own art is not freed out from under it", function()
    local g = bootstrap.new_game(4245)
    g:ensure_asset_atlas_loaded("chips")
    g:clear_run_assets_for_main_menu()
    T.assert_not_nil(g.ASSET_ATLAS.chips.image, "chips belongs to the menu, not the run")
end)

--- A joker front loaded with nobody counted as its owner -- warmed for a pack choice, say --
--- has no count to reach zero, and used to survive every trip back to the menu.
suite.test("returning to the main menu frees joker fronts nobody owns", function()
    local g = bootstrap.new_game(4246)
    local key = "Jokers_0"
    g:ensure_joker_sprite_loaded(key)
    T.assert_not_nil(g.JOKER_SPRITES[key].image, "loads on demand")
    T.assert_nil(g._atlas_owner_counts[key], "with no owner counted")

    g:clear_run_assets_for_main_menu()
    T.assert_nil(g.JOKER_SPRITES[key].image, "and is handed back with the rest of the run")
end)

--- Texture memory running out is what makes a sheet fail on hardware, and the draw path asks
--- for it every frame. It used to re-read the sheet from SD on each of those frames.
suite.test("a sheet that fails to load is not retried every frame", function()
    local g = bootstrap.new_game(4247)
    local real_new_image, real_get_time = love.graphics.newImage, love.timer.getTime
    local now, calls = 100, 0
    love.timer.getTime = function() return now end
    love.graphics.newImage = function()
        calls = calls + 1
        error("out of memory")
    end

    local ok_atlas = pcall(function()
        for _ = 1, 30 do g:ensure_asset_atlas_loaded("centers") end
    end)
    local calls_in_a_second = calls
    now = now + 2
    g:ensure_asset_atlas_loaded("centers")
    local calls_after = calls
    love.graphics.newImage = real_new_image
    g:ensure_asset_atlas_loaded("centers")
    love.timer.getTime = real_get_time

    T.assert_true(ok_atlas, "a failed load is not an error")
    T.assert_eq(calls_in_a_second, 2, "one attempt (and its fallback) for thirty frames")
    T.assert_eq(calls_after, 4, "tried again once the wait is over")
    now = now + 2
    love.timer.getTime = function() return now end
    g:ensure_asset_atlas_loaded("centers")
    love.timer.getTime = real_get_time
    T.assert_not_nil(g.ASSET_ATLAS.centers.image, "and it loads once memory is back")
end)

return suite
