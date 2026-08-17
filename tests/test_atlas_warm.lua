--- Atlases are lazy, so without a warm step the first draw that reaches for one pays an SD
--- read, a t3x decode and a texture upload inside a frame. The two that hurt are the first
--- blind of a run (BlindChips.png, 4 MiB resident) and the first deal (`centers` + `cards_2`).

local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

local function unload_all(game, assets, anims)
    for _, n in ipairs(assets) do game:unload_asset_atlas(n) end
    for _, n in ipairs(anims) do game:unload_animation_atlas(n) end
end

suite.test("warming loads the named atlases", function()
    local game = bootstrap.new_game(11)
    unload_all(game, { "centers", "cards_2" }, { "blind_chips" })

    T.assert_eq(game.ASSET_ATLAS.centers.image, nil, "centers starts unloaded")
    T.assert_eq(game.ANIMATION_ATLAS.blind_chips.image, nil, "blind_chips starts unloaded")

    game:warm_atlases({ "centers", "cards_2" }, { "blind_chips" })

    T.assert_true(game.ASSET_ATLAS.centers.image ~= nil, "centers warmed")
    T.assert_true(game.ASSET_ATLAS.cards_2.image ~= nil, "cards_2 warmed")
    T.assert_true(game.ANIMATION_ATLAS.blind_chips.image ~= nil, "blind_chips warmed")
end)

suite.test("warming an already-resident atlas keeps the same image", function()
    local game = bootstrap.new_game(11)
    game:warm_atlases({ "centers" })
    local first = game.ASSET_ATLAS.centers.image
    game:warm_atlases({ "centers" })
    T.assert_eq(game.ASSET_ATLAS.centers.image, first, "no reload for a warm atlas")
end)

suite.test("either list may be omitted", function()
    local game = bootstrap.new_game(11)
    unload_all(game, { "centers" }, { "blind_chips" })
    game:warm_atlases(nil, { "blind_chips" })
    T.assert_true(game.ANIMATION_ATLAS.blind_chips.image ~= nil, "animation-only warm")
    T.assert_eq(game.ASSET_ATLAS.centers.image, nil, "assets untouched")
    game:warm_atlases({ "centers" })
    T.assert_true(game.ASSET_ATLAS.centers.image ~= nil, "asset-only warm")
end)

--- The blind chips are what `Game:draw_blind_chip_sprite` reaches for, so entering blind
--- select has to leave them resident or the transition bought nothing.
suite.test("entering blind select warms the blind chips", function()
    local game = bootstrap.new_game(11)
    game:unload_animation_atlas("blind_chips")
    T.assert_eq(game.ANIMATION_ATLAS.blind_chips.image, nil, "unloaded first")
    game:enter_blind_select()
    T.assert_true(game.ANIMATION_ATLAS.blind_chips.image ~= nil,
        "blind select should not leave the 4 MiB upload to the first draw")
end)

suite.test("starting a run warms the sheets the first deal needs", function()
    local game = bootstrap.new_game(11)
    unload_all(game, { "centers", "cards_2" }, {})
    game:start_run_from_main_menu()
    T.assert_true(game.ASSET_ATLAS.centers.image ~= nil, "centers resident for the deal")
    T.assert_true(game.ASSET_ATLAS.cards_2.image ~= nil, "cards_2 resident for the deal")
end)

return suite
