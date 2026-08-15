local YouWinUI = {}
local DynaText = require("dyna_text")
local Fonts = require("fonts")
local NumberFormat = require("number_format")

local WIN_TITLE_TEXT = DynaText.new({
    float_amount = 1,
    rotation_amount = 0.025,
    rainbow = true,
})

local function fmt_num(n)
    return NumberFormat.format(math.floor(tonumber(n) or 0))
end

YouWinUI.information = {
    {
        title = "Best Hand",
        color = function(G)
            return G.C.MULT
        end,
        content = function(G)
            return fmt_num(G.run_best_hand_score)
        end,
    },
    {
        title = "Most Played Hand",
        content = function(G)
            if G.get_most_played_hand_name then
                return G:get_most_played_hand_name()
            end
            return "None"
        end,
    },
    {
        title = "Cards Played",
        color = function(G)
            return G.C.CHIPS
        end,
        content = function(G)
            return fmt_num(G.run_cards_played)
        end,
    },
    {
        title = "Cards Discarded",
        color = function(G)
            return G.C.MULT
        end,
        content = function(G)
            return fmt_num(G.run_cards_discarded)
        end,
    },
    {
        title = "Cards Purchased",
        color = function(G)
            return G.C.MONEY
        end,
        content = function(G)
            return fmt_num(G.run_cards_purchased)
        end,
    },
    {
        title = "Times Rerolled",
        color = function(G)
            return G.C.GREEN
        end,
        content = function(G)
            return fmt_num(G.run_times_rerolled)
        end,
    },
    {
        title = "Seed",
        content = function(G)
            if G.SEED == nil then return "Unknown" end
            return tostring(G.SEED)
        end,
    },
}

YouWinUI.buttons = {
    {
        text = "New Run",
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
        text = "Main Menu",
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
        text = "Endless Mode",
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
    local x_offset = 0
    local panel_w, panel_h = 160, 204
    local panel_x = math.floor((screen_w - panel_w) * 0.5) + x_offset
    local panel_y = math.floor((screen_h - panel_h) * 0.5)
    local C = (game and game.C) or G.C

    local padding = 4

    local winText = "You Win!"
    local font_l = G.FONTS.PIXEL.LARGE
    local font_s = G.FONTS.PIXEL.SMALL
    local text_h = font_l:getHeight()
    local text_y = panel_y + padding

    love.graphics.setColor(C.BLOCK.BACK)
    love.graphics.rectangle("fill", panel_x, panel_y, panel_w, panel_h, 4, 4)
    love.graphics.setColor(C.BOOSTER)
    love.graphics.rectangle("line", panel_x, panel_y, panel_w, panel_h, 4, 4)

    love.graphics.setFont(font_l)
    DynaText.draw(WIN_TITLE_TEXT, winText, panel_x, text_y, panel_w, "center")

    local data_y = text_y + text_h + padding
    local data_h = font_s:getHeight() + padding * 2
    local tabW = 64

    for _, info in ipairs(YouWinUI.information) do
        local title = info.title or "Unknown"
        local content = info.content and info.content(game) or "N/A"
        local color = info.color and info.color(game) or C.WHITE

        love.graphics.setColor(C.LIGHT_GREY)
        draw_rect_with_shadow(panel_x + padding, data_y, panel_w - padding * 2, data_h, 4, 4, C.LIGHT_GREY, C.GREY, 2)

        love.graphics.setFont(font_s)
        love.graphics.setColor(C.WHITE)
        love.graphics.printf(title, panel_x + padding, data_y + padding, panel_w - tabW - padding * 2, "center")

        love.graphics.setColor(C.BLOCK.BACK)
        love.graphics.rectangle("fill", panel_x + panel_w - tabW - padding * 2, data_y + padding, tabW, data_h - padding * 2, 4, 4)

        love.graphics.setColor(color)
        -- The tab is fixed at 64 px and the best-hand score is the widest thing that lands in
        -- it - grouped, an endless run's is well past that. Step the face down rather than
        -- printing over the panel edge, which is what 3DS `printf` does silently.
        love.graphics.setFont(Fonts.fit(game or G, font_s, content, tabW - 2))
        love.graphics.printf(content, panel_x + panel_w - tabW - padding * 2, data_y + padding, tabW, "center")
        love.graphics.setFont(font_s)

        data_y = data_y + data_h + padding
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
    love.graphics.rectangle("line", panel_x, panel_y, panel_w, panel_h, 4, 4)

    local padding = 4
    local font_m = G.FONTS.PIXEL.MEDIUM
    local button_h = 32
    local button_y = panel_y + padding
    game._you_win_button_rects = {}

    for i, button in ipairs(YouWinUI.buttons) do
        local text = button.text
        local color = button.color and button.color(game) or C.MULT
        local bx = panel_x + padding
        local by = button_y
        local bw = panel_w - padding * 2
        local bh = button_h

        love.graphics.setColor(color)
        draw_rect_with_shadow(bx, by, bw, bh, 4, 4, color, C.BLOCK.SHADOW, 2)

        love.graphics.setFont(font_m)
        love.graphics.setColor(C.WHITE)
        local text_y = by + math.floor((bh - font_m:getHeight()) * 0.5 + 0.5)
        love.graphics.printf(text, bx, text_y, bw, "center")

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
