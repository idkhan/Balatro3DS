--- Amber Acorn flips the Joker row face down for the duration of the boss blind, and the
--- flip has to come off the moment the blind resolves - the reference undoes it in
--- `Blind:defeat` (`reference/Balatro/blind.lua:338`) and `Blind:disable` (`:357`), not on
--- the next blind. Doing it only on the next blind left the row face down through the cash
--- out, the shop and blind select.
local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

local function acorn_game()
    local g = bootstrap.new_game(4242)
    g.STATE = g.STATES.SELECTING_HAND
    -- Acorn is a showdown boss, so it is only legal on a showdown ante.
    g.ante = 8
    g.current_blind_index = 3
    g.current_boss_blind_id = "bl_final_acorn"
    T.assert_true(g:add_joker_by_def("j_joker"))
    T.assert_true(g:add_joker_by_def("j_greedy_joker"))
    g:boss_reset_for_new_blind()
    return g
end

local function all_face_up(g)
    for _, j in ipairs(g.jokers or {}) do
        if j.face_up ~= true then return false end
    end
    return true
end

local function none_face_up(g)
    for _, j in ipairs(g.jokers or {}) do
        if j.face_up ~= false then return false end
    end
    return true
end

suite.test("the blind flips the Joker row face down", function()
    local g = acorn_game()
    T.assert_true(none_face_up(g), "every Joker is face down while Amber Acorn is live")
end)

suite.test("winning the blind flips them back", function()
    local g = acorn_game()
    g:enter_round_win_after_blind()
    T.assert_true(all_face_up(g), "the Jokers are face up again once the blind is beaten")
end)

suite.test("losing the blind flips them back", function()
    local g = acorn_game()
    g.hands = 0
    g:handle_failed_blind_reset()
    T.assert_true(all_face_up(g), "the Jokers are face up again once the blind is lost")
end)

suite.test("selling Luchador flips them back", function()
    local g = acorn_game()
    T.assert_true(g:add_joker_by_def("j_luchador"))
    local luchador = g.jokers[#g.jokers]
    luchador:set_face_up(false)
    g:boss_on_joker_sold(luchador)
    T.assert_true(g.boss_runtime.disable_current_boss_ability, "the boss ability is disabled")
    T.assert_true(all_face_up(g), "disabling the boss undoes its flip")
end)

suite.test("a Joker bought after the flip is not flipped by the next blind", function()
    local g = acorn_game()
    g:enter_round_win_after_blind()
    T.assert_true(g:add_joker_by_def("j_banner"))
    g.current_blind_index = 1
    g.current_boss_blind_id = nil
    g:boss_reset_for_new_blind()
    T.assert_true(all_face_up(g), "a non-boss blind leaves the row face up")
end)

return suite
