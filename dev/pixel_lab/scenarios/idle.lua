--- Things at rest that are still animating: the title ace, and a dealt hand with jokers and
--- consumables while nobody touches anything. Every frame is captured for a few seconds, so
--- frame-to-frame differences show what idle motion does to the art: whole-pixel steps, or seams
--- crawling through it.
return function(lab)
    local MainMenuUI = require "main_menu_ui"
    lab.quiet()

    lab.wait(3.0)
    lab.burst("01_menu_idle", 90, 1)

    MainMenuUI.open_page(lab.G, "play")
    lab.wait(0.6)
    MainMenuUI.activate_menu_entry(lab.G, "start")
    lab.wait(1.0)
    lab.G._pending_run_seed = "PIXELLAB"
    MainMenuUI._start_run(lab.G)
    lab.wait(2.5)

    local G = lab.G
    G:add_joker_by_def("j_joker")
    G:add_joker_by_def("j_hologram")
    G:add_joker_by_def("j_perkeo")
    G:add_consumable("c_fool")
    G:add_consumable("c_pluto")

    G:start_selected_blind()
    lab.wait(3.0)
    lab.burst("02_hand_idle", 180, 1)
end
