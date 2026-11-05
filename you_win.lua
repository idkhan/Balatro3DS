local YouWinUI = {}
local PixelGrid = require("pixel_grid")
local NumberFormat = require("number_format")
local TicketStrip = require("ticket_strip")

local WIN_QUIPS = {
    "You Aced it!", "You dealt with that pretty well!", "Looks like you weren't bluffing!",
    "Too bad these chips are all virtual...", "Looks like I've taught you well!",
    "You made some heads up plays!", "Good thing I didn't bet against you!",
}

function YouWinUI.quip(game)
    local index = ((math.floor(tonumber(game.round) or 0) + math.floor(tonumber(game.ante) or 0))
        % #WIN_QUIPS) + 1
    return I18N.text("win.quip." .. index, nil, WIN_QUIPS[index])
end

local function fmt_num(n)
    return NumberFormat.format(math.floor(tonumber(n) or 0))
end

YouWinUI.information = {
    {
        title = "Best Hand", key = "best_hand",
        color = function(G)
            return G.C.MULT
        end,
        content = function(G)
            return fmt_num(G.run_best_hand_score)
        end,
    },
    {
        title = "Most Played Hand", key = "most_played_hand",
        content = function(G)
            if G.get_most_played_hand_name then
                return I18N.hand_name(G:get_most_played_hand_name())
            end
            return I18N.text("common.none", nil, "None")
        end,
    },
    {
        title = "Cards Played", key = "cards_played",
        color = function(G)
            return G.C.CHIPS
        end,
        content = function(G)
            return fmt_num(G.run_cards_played)
        end,
    },
    {
        title = "Cards Discarded", key = "cards_discarded",
        color = function(G)
            return G.C.MULT
        end,
        content = function(G)
            return fmt_num(G.run_cards_discarded)
        end,
    },
    {
        title = "Cards Purchased", key = "cards_purchased",
        color = function(G)
            return G.C.MONEY
        end,
        content = function(G)
            return fmt_num(G.run_cards_purchased)
        end,
    },
    {
        title = "Times Rerolled", key = "times_rerolled",
        color = function(G)
            return G.C.GREEN
        end,
        content = function(G)
            return fmt_num(G.run_times_rerolled)
        end,
    },
    {
        title = "New Discoveries", key = "new_discoveries",
        color = function(G) return G.C.ORANGE end,
        content = function(G) return fmt_num(G.get_run_discoveries and G:get_run_discoveries() or 0) end,
    },
    {
        title = "Seed", key = "seed",
        content = function(G)
            if G.SEED == nil then return I18N.text("common.unknown", nil, "Unknown") end
            return tostring(G.SEED)
        end,
    },
}

YouWinUI.buttons = {
    {
        text = "New Run", key = "new_run",
        callback = function(game)
            if game.continue_from_you_win_new_run then
                game:continue_from_you_win_new_run()
            end
        end,
        color = function(G)
            return G.C.MULT
        end,
    },
    {
        text = "Main Menu", key = "main_menu",
        callback = function(game)
            if game.continue_from_you_win_main_menu then
                game:continue_from_you_win_main_menu()
            end
        end,
        color = function(G)
            return G.C.MULT
        end,
    },
    {
        text = "Endless Mode", key = "endless_mode",
        callback = function(game)
            if game.continue_from_you_win_endless then
                game:continue_from_you_win_endless()
            end
        end,
        color = function(G)
            return G.C.CHIPS
        end,
    },
}

function YouWinUI.drawTop(game)
    local screen_w, screen_h = 400, 240
    if love.graphics.getDimensions then
        screen_w, screen_h = love.graphics.getDimensions()
    end
    local panel_w, panel_h = math.min(384, screen_w - 16), 226
    local panel_x = math.floor((screen_w - panel_w) * 0.5)
    local panel_y = 7
    local C = (game and game.C) or G.C

    local padding = 8
    local font_s = G.FONTS.PIXEL.SMALL

    love.graphics.setColor(C.BLOCK.BACK)
    love.graphics.rectangle("fill", panel_x, panel_y, panel_w, panel_h, 4, 4)
    love.graphics.setColor(C.BOOSTER)
    PixelGrid.outline(panel_x, panel_y, panel_w, panel_h, 4)

    local new_count = #(game._newly_unlocked_jokers or {}) + #(game._newly_unlocked_vouchers or {})
    TicketStrip.draw(game, {
        x = panel_x + padding, y = panel_y + padding, w = panel_w - padding * 2, h = 38, stub_w = 70,
        stub = I18N.text("win.stub", nil, "CLEARED"), title = I18N.text("win.title", nil, "You Win!"),
        detail = YouWinUI.quip(game) .. require("game_over_ui").new_unlocks_text(new_count),
        stub_color = C.BOOSTER,
        font = font_s,
    })

    local data_y = panel_y + 52
    for i, info in ipairs(YouWinUI.information) do
        local title = info.key and I18N.text("win." .. info.key, nil, info.title) or info.title or "Unknown"
        local content = info.content and info.content(game) or I18N.text("common.not_available", nil, "N/A")
        if info.key == "best_hand" and game._run_record_flags and game._run_record_flags.c_best_hand_chips then
            content = tostring(content) .. I18N.text("run.new_record", nil, "  NEW")
        end
        local color = info.color and info.color(game) or C.WHITE
        TicketStrip.draw(game, {
            x = panel_x + padding + (i % 2 == 0 and 8 or 0), y = data_y,
            w = panel_w - padding * 2 - 8, h = 21, stub_w = 88,
            stub = title, title = tostring(content), stub_color = color, font = font_s,
        })
        data_y = data_y + 23
    end
end

function YouWinUI.drawBottom(game)
    local screen_w, screen_h = 320, 240
    local panel_w, panel_h = 160, 112
    local panel_x = math.floor((screen_w - panel_w) * 0.5)
    local panel_y = math.floor((screen_h - panel_h) * 0.5)
    local C = (game and game.C) or G.C

    love.graphics.setColor(C.BLOCK.BACK)
    love.graphics.rectangle("fill", panel_x, panel_y, panel_w, panel_h, 4, 4)
    love.graphics.setColor(C.BOOSTER)
    PixelGrid.outline(panel_x, panel_y, panel_w, panel_h, 4)

    local padding = 4
    local font_m = G.FONTS.PIXEL.MEDIUM
    local button_h = 32
    local button_y = panel_y + padding
    game._you_win_button_rects = {}

    for i, button in ipairs(YouWinUI.buttons) do
        local text = button.key and I18N.text("win." .. button.key, nil, button.text) or button.text
        local color = button.color and button.color(game) or C.MULT
        local bx = panel_x + padding
        local by = button_y
        local bw = panel_w - padding * 2
        local bh = button_h

        TicketStrip.draw(game, {
            x = bx, y = by, w = bw, h = bh, stub_w = 40,
            stub = string.format("%02d", i), title = text, stub_color = color, font = font_m,
        })

        game._you_win_button_rects[i] = { x = bx, y = by, w = bw, h = bh, index = i }
        button_y = button_y + button_h + padding
    end
end

function YouWinUI.handle_touch(game, x, y)
    for _, rect in ipairs(game._you_win_button_rects or {}) do
        if game:_point_in_rect_simple(x, y, rect) then
            local button = YouWinUI.buttons[rect.index]
            if button and button.callback then
                Sfx.play_button()
                button.callback(game)
            end
            return true
        end
    end
    return false
end

function YouWinUI.handle_button(game, btn)
    if game.is_menu_activate and game:is_menu_activate(btn) then
        Sfx.play_button()
        if game.continue_from_you_win_endless then
            game:continue_from_you_win_endless()
        end
        return true
    end
    if game.is_menu_back and game:is_menu_back(btn) then
        Sfx.play("cancel")
        if game.continue_from_you_win_main_menu then
            game:continue_from_you_win_main_menu()
        end
        return true
    end
    return false
end

return YouWinUI
