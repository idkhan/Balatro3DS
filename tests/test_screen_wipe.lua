--- The screen wipe that covers a run being built.
---
--- What matters here is not the picture, it is the schedule. The wipe exists because the
--- run build used to happen inside one frame and blew past the music stream's buffer runway
--- (see the header in `screen_wipe.lua`), so the contract worth pinning down is: no step runs
--- until the screen is actually covered, exactly one step runs per frame, the last step and
--- the uncover never share a frame, and the whole thing ends up in the state the synchronous
--- path produces.

local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

bootstrap.load()

local ScreenWipe = require("screen_wipe")

local FRAME = 1 / 60

--- Advance the wipe a frame at a time until it clears, collecting what each frame reported.
---@param game table
---@param limit integer|nil
---@return integer frames, integer suppressed frames the scene update was skipped on
local function run_to_completion(game, limit)
    local frames, suppressed = 0, 0
    while game.screenwipe and frames < (limit or 600) do
        if ScreenWipe.update(game, FRAME) then suppressed = suppressed + 1 end
        frames = frames + 1
    end
    return frames, suppressed
end

--- Steps that record the frame they ran on, so ordering and one-per-frame are both testable.
---@return function[] steps, table log
local function counting_steps(n)
    local log = {}
    local steps = {}
    for i = 1, n do
        steps[i] = function() log[#log + 1] = i end
    end
    return steps, log
end

suite.test("no step runs until the screen is covered", function()
    local game = bootstrap.new_game(4101)
    local steps, log = counting_steps(3)
    ScreenWipe.begin(game, steps)

    T.assert_eq(#log, 0, "nothing runs on the frame the wipe starts")
    while game.screenwipe and game.screenwipe.alpha < 1 do
        ScreenWipe.update(game, FRAME)
        T.assert_eq(#log, 0, "the fade-in must not run work the player can still see behind")
    end
    T.assert_true(ScreenWipe.hides_scene(game), "the cover is opaque before any step")
end)

suite.test("steps run one per frame, in order", function()
    local game = bootstrap.new_game(4102)
    local steps, log = counting_steps(5)
    ScreenWipe.begin(game, steps)

    local before = 0
    while game.screenwipe and #log < 5 do
        ScreenWipe.update(game, FRAME)
        -- The `present` between two steps is the whole point: it is the only thing that
        -- reliably lets LovePotion's audio pool thread refill the NDSP buffers.
        T.assert_true(#log - before <= 1, "at most one step per frame")
        before = #log
    end
    T.assert_deep_eq(log, { 1, 2, 3, 4, 5 }, "and in the order given")
end)

suite.test("the last step and the reveal never share a frame", function()
    local game = bootstrap.new_game(4103)
    local ran_last, revealed_on = false, nil
    local frame = 0
    local steps = {
        function() end,
        function() ran_last = true end,
    }
    ScreenWipe.begin(game, steps, function() revealed_on = frame end)

    local last_step_frame = nil
    while game.screenwipe do
        frame = frame + 1
        ScreenWipe.update(game, FRAME)
        if ran_last and not last_step_frame then last_step_frame = frame end
    end
    T.assert_not_nil(last_step_frame)
    T.assert_not_nil(revealed_on, "the reveal callback fires")
    T.assert_true(revealed_on > last_step_frame, "the cover holds for at least a frame after")
end)

suite.test("the reveal fires once and the wipe clears itself", function()
    local game = bootstrap.new_game(4104)
    local reveals = 0
    ScreenWipe.begin(game, counting_steps(2), function(g)
        reveals = reveals + 1
        T.assert_eq(g, game, "the reveal is handed the game")
    end)

    local frames, suppressed = run_to_completion(game)
    T.assert_eq(reveals, 1)
    T.assert_eq(game.screenwipe, nil, "the wipe removes itself when the cover is gone")
    T.assert_true(frames > suppressed, "the uncover lets the scene animate back in")
    T.assert_true(ScreenWipe.active(game) == false)
end)

suite.test("a step returning false abandons the ones after it", function()
    local game = bootstrap.new_game(4105)
    local ran = {}
    ScreenWipe.begin(game, {
        function() ran[#ran + 1] = "read" end,
        function() ran[#ran + 1] = "restore"; return false end,
        function() ran[#ran + 1] = "save" end,
    })
    run_to_completion(game)

    T.assert_deep_eq(ran, { "read", "restore" }, "a failed restore does not write a save back")
    T.assert_eq(game.screenwipe, nil, "and the cover still lifts rather than sticking")
end)

--- An atlas upload inside a step hands the next frame a dt larger than the whole animation.
suite.test("a load hitch cannot skip the transition", function()
    local game = bootstrap.new_game(4106)
    ScreenWipe.begin(game, counting_steps(1))
    ScreenWipe.update(game, 2.5)
    T.assert_true(game.screenwipe ~= nil, "one enormous frame must not end the wipe")
    T.assert_true(game.screenwipe.alpha < 1, "nor cover the screen instantly")
end)

suite.test("a second wipe cannot start over a live one", function()
    local game = bootstrap.new_game(4107)
    local first, second = counting_steps(1)
    T.assert_true(ScreenWipe.begin(game, first))
    local other = { function() error("the second wipe's steps must not run") end }
    T.assert_true(ScreenWipe.begin(game, other) == false)
    run_to_completion(game)
end)

--- The deck being started, not the one the last run used. `apply_deck_config` is several steps
--- away when the card is picked, so `selected_deck_id` is still the previous run's.
suite.test("the card is the deck the player just picked", function()
    local game = bootstrap.new_game(4108)
    game.selected_deck_id = "b_red"
    game._pending_deck_id = "b_blue"
    ScreenWipe.begin(game, {})

    T.assert_eq(game.screenwipe.back_index, game:get_deck_back_index("b_blue"))
    T.assert_true(game.screenwipe.back_index ~= game:get_deck_back_index("b_red"),
        "the two decks must actually differ, or this asserts nothing")
end)

--- The reason `Game:speed_factor` already knew about `screenwipe` before anything set it:
--- a wipe runs at 1x whatever the game-speed setting is (reference `game.lua:2495`).
suite.test("game speed does not apply under the cover", function()
    local game = bootstrap.new_game(4109)
    game.STAGE = game.STAGES.RUN
    game.SETTINGS.GAMESPEED = 4
    ScreenWipe.begin(game, {})
    T.assert_eq(game:speed_factor(0.1), 1)
end)

--- The whole point: the deferred path has to build the same run the immediate one does.
suite.test("a run started behind the wipe matches the synchronous build", function()
    local sync = bootstrap.new_game(4110)
    sync._pending_deck_id = "b_red"
    sync._pending_stake_id = "stake_white"
    sync._pending_run_seed = "WIPETEST"
    sync:start_run_from_main_menu()

    local wiped = bootstrap.new_game(4110)
    wiped._pending_deck_id = "b_red"
    wiped._pending_stake_id = "stake_white"
    wiped._pending_run_seed = "WIPETEST"
    T.assert_true(wiped:start_new_run_from_main_menu())
    T.assert_true(wiped.STATE ~= wiped.STATES.BLIND_SELECT, "and not before the cover is up")
    run_to_completion(wiped)

    T.assert_eq(wiped.STATE, sync.STATE)
    T.assert_eq(wiped.STAGE, sync.STAGE)
    T.assert_eq(wiped.SEED, sync.SEED)
    T.assert_eq(wiped.ante, sync.ante)
    T.assert_eq(wiped.money, sync.money)
    T.assert_eq(#wiped.deck.cards, #sync.deck.cards)
    T.assert_true(wiped.ASSET_ATLAS.centers.image ~= nil, "centers resident for the first deal")
    T.assert_true(wiped.ASSET_ATLAS.cards_2.image ~= nil, "cards_2 resident for the first deal")
    T.assert_eq(wiped.ASSET_ATLAS.balatro.image, nil, "and the menu sheets are gone")
end)

--- The menu keeps drawing through the fade-in, so anything that changes what it draws has to
--- wait for the cover. Retiring the sub-state at the button press popped deck select back to
--- the root main menu in front of the player.
suite.test("deck select stays on screen until the cover is up", function()
    local game = bootstrap.new_game(4114)
    game._menu_sub_state = "deck_select"
    game._pending_deck_id = "b_red"
    game._pending_stake_id = "stake_white"
    game:start_new_run_from_main_menu()

    while game.screenwipe and not ScreenWipe.hides_scene(game) do
        T.assert_eq(game._menu_sub_state, "deck_select", "the menu must not change under a sheer cover")
        ScreenWipe.update(game, FRAME)
    end
    run_to_completion(game)
    T.assert_eq(game._menu_sub_state, nil, "and is retired once it is out of sight")
end)

--- The blind-select entrance is 0.25 s of slide. Started inside the last step it would run
--- its whole course under an opaque cover and the player would see the cards already parked.
suite.test("blind select enters as the cover lifts, not under it", function()
    local game = bootstrap.new_game(4111)
    game._pending_deck_id = "b_red"
    game._pending_stake_id = "stake_white"
    game:start_new_run_from_main_menu()

    local guard = 0
    while game.screenwipe and game.screenwipe.phase ~= "out" and guard < 600 do
        ScreenWipe.update(game, FRAME)
        guard = guard + 1
    end
    T.assert_not_nil(game._blind_slide, "the slide is live on the first uncovered frame")
    T.assert_eq(game._blind_slide.t, 0, "and starting from the top")
end)

--- Resuming stalls the same way starting does: a file read, a full state restore, a write
--- back. Same treatment.
suite.test("continue runs its read, restore and save-back as separate steps", function()
    local game = bootstrap.new_game(4112)
    game._pending_deck_id = "b_red"
    game._pending_stake_id = "stake_white"
    game:start_run_from_main_menu()
    game:autosave_run()

    local fresh = bootstrap.new_game(4113)
    T.assert_true(fresh:begin_continue_saved_run())
    local _, suppressed = run_to_completion(fresh)
    T.assert_true(suppressed >= 3, "each chunk gets its own covered frame")
    T.assert_eq(fresh.STAGE, fresh.STAGES.RUN, "and the run comes back")
end)

return suite
