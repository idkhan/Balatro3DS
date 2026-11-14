--- A walk through the screens a run spends its time on, on a fixed seed, with the first-run
--- overlays off. Stills, plus bursts of the animations that run most often.
return function(lab)
    local MainMenuUI = require "main_menu_ui"
    lab.quiet()

    lab.wait(3.0)
    lab.capture("01_menu_main")

    MainMenuUI.open_page(lab.G, "play")
    lab.wait(0.6)
    lab.capture("02_menu_play")

    MainMenuUI.activate_menu_entry(lab.G, "start")
    lab.wait(1.0)
    lab.capture("03_deck_select")

    lab.G._pending_run_seed = "PIXELLAB"
    MainMenuUI._start_run(lab.G)
    lab.wait(0.35)
    lab.burst("04_blind_select_slide", 8, 2)
    lab.wait(2.0)
    lab.capture("04_blind_select")

    -- Something in every panel the run draws.
    local G = lab.G
    G:add_joker_by_def("j_joker")
    G:add_joker_by_def("j_greedy_joker")
    G:add_joker_by_def("j_blueprint")
    G:add_consumable("c_fool")
    G:add_consumable("c_pluto")

    G:start_selected_blind()
    lab.burst("05_deal", 12, 3)
    lab.wait(2.0)
    lab.capture("05_hand")

    lab.press("a")
    lab.burst("06_select_juice", 10, 1)
    lab.press("dpright")
    lab.press("a")
    lab.press("dpright")
    lab.press("a")
    lab.wait(0.6)
    lab.capture("06_hand_selected")

    lab.press("y")
    lab.burst("07_scoring", 30, 3)
    lab.wait(4.0)
    lab.capture("08_after_hand")

    -- Win the blind on the next hand.
    G.round_score = (G.round_score or 0) + 100000000
    lab.press("a")
    lab.press("y")
    lab.wait(6.0)
    lab.capture("09_round_eval")

    G:continue_from_round_win()
    lab.burst("10_shop_slide", 10, 2)
    lab.wait(2.0)
    lab.capture("10_shop")

    G.money = 100
    lab.frames(2)
    if G:buy_shop_booster(1) then
        lab.burst("11_booster_open", 15, 3)
        lab.wait(2.0)
        lab.capture("11_booster")
        if G.skip_booster_pack then G:skip_booster_pack() end
        lab.wait(2.0)
    end

    lab.press("leftshoulder")
    lab.wait(0.8)
    lab.capture("12_jokers_pulled")
    lab.press("leftshoulder")
    lab.wait(0.8)

    G:toggle_pause()
    lab.wait(0.8)
    lab.capture("13_pause")
    G:toggle_pause()
    lab.wait(0.5)

    G:toggle_deck_view()
    lab.wait(0.8)
    lab.capture("14_deck_view")
    G:toggle_deck_view()
    lab.wait(0.5)

    G:toggle_run_info()
    lab.wait(0.8)
    lab.capture("15_run_info")
    G:toggle_run_info()
    lab.wait(0.5)
end
