--- Main-menu Profile screen: slot tabs, renaming, progress readout, and slot actions.
local ProfileUI = {}
local PixelGrid = require("pixel_grid")
local NumberFormat = require("number_format")

local SCREEN_W, SCREEN_H = 320, 240
local NAME_MAX_LENGTH = 14

local TAB_Y, TAB_H, TAB_GAP = 4, 22, 7
local TAB_X0, TAB_W = 9, 96
local NAME_RECT = { x = 85, y = 30, w = 150, h = 18 }
local PANEL = { x = 6, y = 54, w = 184, h = 118 }
local PANEL_PAD = 5
local ROW_H, ROW_GAP = 18, 4
local LABEL_W = 84
local COL_X, COL_W = 196, 118

local function fill_rect(x, y, w, h, color, C)
    if _G.draw_rect_with_shadow then
        draw_rect_with_shadow(x, y, w, h, 4, 4, color, C.BLOCK.SHADOW, 2)
    else
        love.graphics.setColor(color)
        love.graphics.rectangle("fill", x, y, w, h, 4, 4)
    end
end

local function label_y(rect, font)
    return rect.y + math.floor((rect.h - font:getHeight()) * 0.5 + 0.5)
end

local function draw_button(rect, text, color, C, font)
    fill_rect(rect.x, rect.y, rect.w, rect.h, color, C)
    love.graphics.setFont(font)
    love.graphics.setColor(C.WHITE)
    love.graphics.printf(text, rect.x, label_y(rect, font), rect.w, "center")
end

--- Filled progress bar with the percentage and raw counts printed inside it.
local function draw_progress_bar(game, x, y, w, h, have, total, font, count_font)
    local C = game.C
    local ratio = total > 0 and math.max(0, math.min(1, have / total)) or 0
    love.graphics.setColor(C.BLOCK.BACK)
    love.graphics.rectangle("fill", x, y, w, h, 3, 3)
    if ratio > 0 then
        love.graphics.setColor(C.RED)
        love.graphics.rectangle("fill", x, y, math.max(3, math.floor(w * ratio + 0.5)), h, 3, 3)
    end

    local percent = string.format("%d%%", math.floor(ratio * 100 + 0.5))
    love.graphics.setFont(font)
    love.graphics.setColor(C.WHITE)
    love.graphics.print(percent, x + 4, label_y({ y = y, h = h }, font))

    if count_font then
        local counts = string.format("%d/%d", have, total)
        love.graphics.setFont(count_font)
        love.graphics.setColor(C.DARK_WHITE or C.LIGHT_GREY)
        love.graphics.print(counts, x + w - 4 - count_font:getWidth(counts), label_y({ y = y, h = h }, count_font))
    end
end

function ProfileUI.selected_id(game)
    local id = math.floor(tonumber(game._profile_selected) or 0)
    local count = game.get_profile_count and game:get_profile_count() or 3
    if id < 1 or id > count then id = game.get_profile_id and game:get_profile_id() or 1 end
    return id
end

function ProfileUI.open(game)
    game._menu_sub_state = "profile"
    game._profile_selected = game.get_profile_id and game:get_profile_id() or 1
    game._profile_delete_confirm = false
    game._profile_focus_index = 1
    ProfileUI.cancel_rename(game)
    Sfx.play("paper1")
end

function ProfileUI.close(game)
    ProfileUI.cancel_rename(game)
    game._profile_delete_confirm = false
    game._menu_sub_state = "main"
    Sfx.play("cancel")
end

--- The career page, reached from Options. The base game keeps these behind their own
--- `high_scores` entry rather than inside profile management (`UI_definitions.lua:2250`),
--- and the rows are the same six it shows there.
function ProfileUI.open_stats(game)
    game._menu_sub_state = "stats"
    game._stats_focus = 1
    Sfx.play("paper1")
end

function ProfileUI.close_stats(game)
    game._menu_sub_state = "main"
    Sfx.play("cancel")
end

--------------------------------------------------------------------------------
-- Renaming
--------------------------------------------------------------------------------

local function has_screen_keyboard()
    return love.keyboard and love.keyboard.hasScreenKeyboard and love.keyboard.hasScreenKeyboard() == true
end

--- The option table LövePotion accepts. The length key is `length`, not `maxLength`:
--- `love.keyboard.setTextInput` runs every field through `luax::CheckTableFields` before it
--- reads any of them and raises "Invalid keyboard setting name" on anything outside
--- {type, password, hint, length}, so one wrong key means the keyboard never opens
--- (`source/modules/keyboard/wrap_keyboard.cpp:34`, `include/modules/keyboard/keyboard.tcc:77`).
local RENAME_KEYBOARD_OPTIONS = {
    type = "normal",
    hint = "Profile Name",
    length = NAME_MAX_LENGTH,
}

--- Console builds hand off to the system keyboard; desktop edits the name inline.
function ProfileUI.begin_rename(game)
    if game._profile_rename_active or game._profile_rename_pending then return false end
    game._profile_delete_confirm = false
    local id = ProfileUI.selected_id(game)

    if has_screen_keyboard() then
        game._profile_rename_pending = id
        game._profile_rename_pending_frames = 0
        -- Drop the pending flag if the runtime rejects the call, so a failure does not read
        -- as a rename that is still in progress.
        if not pcall(love.keyboard.setTextInput, true, RENAME_KEYBOARD_OPTIONS) then
            game._profile_rename_pending = nil
            return false
        end
        return true
    end

    game._profile_rename_active = id
    game._profile_rename_buffer = game.get_profile_name and game:get_profile_name(id) or ""
    if love.keyboard and love.keyboard.setTextInput then
        pcall(love.keyboard.setTextInput, true)
    end
    return true
end

function ProfileUI.is_renaming(game)
    return game._profile_rename_active ~= nil or game._profile_rename_pending ~= nil
end

function ProfileUI.cancel_rename(game)
    local was_active = ProfileUI.is_renaming(game)
    game._profile_rename_active = nil
    game._profile_rename_pending = nil
    game._profile_rename_buffer = nil
    if was_active and not has_screen_keyboard() and love.keyboard and love.keyboard.setTextInput then
        pcall(love.keyboard.setTextInput, false)
    end
    return was_active
end

function ProfileUI.commit_rename(game)
    local id = game._profile_rename_active
    if not id then return false end
    local name = game._profile_rename_buffer
    ProfileUI.cancel_rename(game)
    if game.set_profile_name then
        game:set_profile_name(id, name)
    end
    Sfx.play_button()
    return true
end

--- Text from the system keyboard arrives whole; inline editing arrives per character.
function ProfileUI.handle_textinput(game, text)
    if type(text) ~= "string" or text == "" then return false end

    local pending = game._profile_rename_pending
    if pending then
        game._profile_rename_pending = nil
        if game.set_profile_name then
            game:set_profile_name(pending, text)
        end
        return true
    end

    if not game._profile_rename_active then return false end
    local buffer = tostring(game._profile_rename_buffer or "")
    for i = 1, #text do
        if #buffer >= NAME_MAX_LENGTH then break end
        local byte = text:byte(i)
        if byte >= 32 and byte <= 126 then
            buffer = buffer .. string.char(byte)
        end
    end
    game._profile_rename_buffer = buffer
    return true
end

--- Inline editing keys (desktop only); returns true when the key was consumed.
function ProfileUI.handle_key(game, key)
    if not game._profile_rename_active then return false end
    if key == "backspace" then
        local buffer = tostring(game._profile_rename_buffer or "")
        game._profile_rename_buffer = buffer:sub(1, math.max(0, #buffer - 1))
        return true
    end
    if key == "return" or key == "kpenter" then
        ProfileUI.commit_rename(game)
        return true
    end
    if key == "escape" then
        ProfileUI.cancel_rename(game)
        Sfx.play("cancel")
        return true
    end
    return true
end

--------------------------------------------------------------------------------
-- Actions
--------------------------------------------------------------------------------

function ProfileUI.select_slot(game, id)
    game._profile_selected = id
    game._profile_delete_confirm = false
    ProfileUI.cancel_rename(game)
end

function ProfileUI.load_selected(game)
    local id = ProfileUI.selected_id(game)
    if game.get_profile_id and game:get_profile_id() == id then return false end
    if game.switch_profile then
        game:switch_profile(id)
    end
    game._profile_delete_confirm = false
    return true
end

function ProfileUI.delete_selected(game)
    if not game._profile_delete_confirm then
        game._profile_delete_confirm = true
        return true
    end
    game._profile_delete_confirm = false
    if game.delete_profile then
        game:delete_profile(ProfileUI.selected_id(game))
    end
    return true
end

function ProfileUI.unlock_selected(game)
    game._profile_delete_confirm = false
    if game.unlock_everything_for_profile then
        game:unlock_everything_for_profile(ProfileUI.selected_id(game))
    end
    return true
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

--- The system keyboard blocks until dismissed, so its text lands before the next
--- frame. Nothing by then means the player cancelled it.
local function expire_pending_rename(game)
    if not game._profile_rename_pending then return end
    local frames = (tonumber(game._profile_rename_pending_frames) or 0) + 1
    game._profile_rename_pending_frames = frames
    if frames >= 2 then
        game._profile_rename_pending = nil
    end
end

--- Whether the career panel is showing. Stats belong to the loaded profile, so another slot
--- always falls back to its progress bars.
---@return boolean
function ProfileUI.showing_stats(game, selected, active)
    return game._profile_show_stats == true and selected == active
end

--- Thousands separators, so a nine-figure best hand stays readable, and an exponent past the
--- point where separators stop helping.
---@param n number
---@return string
local function fmt_num(n)
    return NumberFormat.format(math.floor(tonumber(n) or 0))
end

--- The reference's six high-score rows (`game.lua:864-874`).
---@param game table
---@return table[] `{ label, value, colour }`
function ProfileUI.career_rows(game)
    local C = game.C
    local hand_name, hand_count = game:career_most_played_hand()
    return {
        { I18N.text("career.best_hand", nil, "Best Hand"), fmt_num(game:get_career_stat("c_best_hand_chips")), C.RED },
        { I18N.text("career.highest_round", nil, "Highest Round"), fmt_num(game:get_career_stat("c_furthest_round")), C.WHITE },
        { I18N.text("career.highest_ante", nil, "Highest Ante"), fmt_num(game:get_career_stat("c_furthest_ante")), C.ORANGE },
        { I18N.text("career.most_played", nil, "Most Played"), hand_count > 0 and (I18N.hand_name(hand_name) .. " (" .. hand_count .. ")")
            or I18N.text("common.none", nil, "None"), C.WHITE },
        { I18N.text("career.most_money", nil, "Most Money"), "$" .. fmt_num(game:get_career_stat("c_most_money")), C.MONEY },
        { I18N.text("career.best_streak", nil, "Best Streak"), fmt_num(game:get_career_stat("c_win_streak")), C.GREEN },
    }
end

function ProfileUI.draw_bottom(game)
    expire_pending_rename(game)
    local C = game.C
    local font_t = game.FONTS.PIXEL.TINY
    local font_s = game.FONTS.PIXEL.SMALL
    local font_m = game.FONTS.PIXEL.MEDIUM

    local selected = ProfileUI.selected_id(game)
    local active = game.get_profile_id and game:get_profile_id() or 1
    local count = game.get_profile_count and game:get_profile_count() or 3
    local progress = game.get_profile_progress and game:get_profile_progress(selected) or nil

    love.graphics.setColor(C.PANEL)
    love.graphics.rectangle("fill", 0, 0, SCREEN_W, SCREEN_H)

    -- Slot tabs
    game._profile_tab_rects = {}
    for i = 1, count do
        local rect = { x = TAB_X0 + (TAB_W + TAB_GAP) * (i - 1), y = TAB_Y, w = TAB_W, h = TAB_H }
        game._profile_tab_rects[i] = rect
        draw_button(rect, tostring(i), i == selected and C.RED or C.GREY, C, font_m)
    end

    -- Name field
    local name_rect = { x = NAME_RECT.x, y = NAME_RECT.y, w = NAME_RECT.w, h = NAME_RECT.h }
    game._profile_name_rect = name_rect
    fill_rect(name_rect.x, name_rect.y, name_rect.w, name_rect.h, C.BLOCK.BACK, C)
    love.graphics.setFont(font_s)
    love.graphics.setColor(C.WHITE)
    if game._profile_rename_active then
        local buffer = tostring(game._profile_rename_buffer or "")
        local caret = (math.floor((love.timer and love.timer.getTime() or 0) * 2) % 2 == 0) and "_" or ""
        love.graphics.printf(buffer .. caret, name_rect.x, label_y(name_rect, font_s), name_rect.w, "center")
    else
        local name = game.get_profile_name and game:get_profile_name(selected) or ("P" .. selected)
        love.graphics.printf(name, name_rect.x, label_y(name_rect, font_s), name_rect.w, "center")
    end

    -- Left panel: progress bars, or the career stats the base game keeps beside them
    -- (`UI_definitions.lua:2591-2617` pairs `create_UIBox_high_scores` rows with the same
    -- progress box). Only the active profile's stats are loaded, so the panel falls back to
    -- progress for any other slot.
    fill_rect(PANEL.x, PANEL.y, PANEL.w, PANEL.h, C.BLOCK.BACK, C)
    local inner_x = PANEL.x + PANEL_PAD
    local inner_w = PANEL.w - PANEL_PAD * 2
    local bar_x = inner_x + LABEL_W + 2
    local bar_w = inner_w - LABEL_W - 2

    if ProfileUI.showing_stats(game, selected, active) then
        love.graphics.setFont(font_s)
        love.graphics.setColor(C.WHITE)
        love.graphics.print(I18N.text("profile.career", nil, "Career"), inner_x, label_y({ y = PANEL.y + PANEL_PAD, h = ROW_H }, font_s))
        local row_y = PANEL.y + PANEL_PAD + ROW_H + ROW_GAP
        for _, row in ipairs(ProfileUI.career_rows(game)) do
            love.graphics.setFont(font_s)
            love.graphics.setColor(C.DARK_WHITE or C.GREY)
            love.graphics.print(row[1], inner_x, label_y({ y = row_y, h = ROW_H }, font_s))
            love.graphics.setColor(row[3] or C.WHITE)
            love.graphics.printf(row[2], inner_x, label_y({ y = row_y, h = ROW_H }, font_s),
                inner_w, "right")
            row_y = row_y + ROW_H + ROW_GAP
        end
    else
        love.graphics.setFont(font_s)
        love.graphics.setColor(C.WHITE)
        love.graphics.print(I18N.text("profile.progress", nil, "Progress"), inner_x, label_y({ y = PANEL.y + PANEL_PAD, h = ROW_H }, font_s))
        draw_progress_bar(game, bar_x, PANEL.y + PANEL_PAD, bar_w, ROW_H,
            math.floor((progress and progress.overall or 0) * 100 + 0.5), 100, font_s, nil)

        local row_y = PANEL.y + PANEL_PAD + ROW_H + ROW_GAP
        for _, row in ipairs(progress and progress.rows or {}) do
            fill_rect(inner_x, row_y, LABEL_W, ROW_H, C.LIGHT_GREY, C)
            love.graphics.setFont(font_s)
            love.graphics.setColor(C.BLOCK.BACK)
            love.graphics.printf(I18N.text("profile.row." .. tostring(row.key), nil, row.label), inner_x + 2, label_y({ y = row_y, h = ROW_H }, font_s), LABEL_W - 4, "center")
            draw_progress_bar(game, bar_x, row_y, bar_w, ROW_H, row.have, row.total, font_s, font_t)
            row_y = row_y + ROW_H + ROW_GAP
        end
    end

    -- Wins
    local wins = progress and progress.wins or 0
    love.graphics.setFont(font_m)
    local wins_label, wins_value = I18N.text("profile.wins_prefix", nil, "Wins: "), tostring(wins)
    local wins_w = font_m:getWidth(wins_label) + font_m:getWidth(wins_value)
    local wins_x = COL_X + math.floor((COL_W - wins_w) * 0.5 + 0.5)
    love.graphics.setColor(C.WHITE)
    love.graphics.print(wins_label, wins_x, PANEL.y)
    love.graphics.setColor(C.RED)
    love.graphics.print(wins_value, wins_x + font_m:getWidth(wins_label), PANEL.y)

    -- Slot actions
    local is_active = selected == active
    game._profile_load_rect = { x = COL_X, y = PANEL.y + 30, w = COL_W, h = 26 }
    draw_button(game._profile_load_rect, is_active and I18N.text("profile.loaded", nil, "Loaded") or I18N.text("profile.load", nil, "Load Profile"),
        is_active and C.GREY or C.BLUE, C, font_s)

    game._profile_delete_rect = { x = COL_X, y = PANEL.y + 62, w = COL_W, h = 22 }
    draw_button(game._profile_delete_rect,
        game._profile_delete_confirm and I18N.text("menu.confirm_delete", nil, "Confirm?") or I18N.text("profile.delete", nil, "Delete Profile"),
        game._profile_delete_confirm and C.MULT_DARK or C.RED, C, font_s)

    -- Panel switch. Career stats are only kept for the profile that is loaded, so the button
    -- is offered only on that slot.
    if selected == active then
        game._profile_stats_rect = { x = COL_X, y = PANEL.y + 90, w = COL_W, h = 22 }
        draw_button(game._profile_stats_rect,
            game._profile_show_stats and I18N.text("profile.progress", nil, "Progress") or I18N.text("profile.career_stats", nil, "Career Stats"),
            game._profile_show_stats and C.BLUE or C.ORANGE, C, font_s)
    else
        game._profile_stats_rect = nil
    end

    local unlock_y = PANEL.y + (is_active and 118 or 90)
    if progress and progress.fully_unlocked then
        game._profile_unlock_rect = nil
        love.graphics.setFont(font_s)
        love.graphics.setColor(C.GREEN)
        love.graphics.printf(I18N.text("profile.unlocked", nil, "Unlocked!"), COL_X, unlock_y + 4, COL_W, "center")
    else
        game._profile_unlock_rect = { x = COL_X, y = unlock_y, w = COL_W, h = 22 }
        draw_button(game._profile_unlock_rect, I18N.text("profile.unlock_all", nil, "Unlock All"), C.GREEN, C, font_s)
    end

    game._profile_back_rect = { x = PANEL.x, y = SCREEN_H - 26, w = SCREEN_W - PANEL.x * 2, h = 20 }
    draw_button(game._profile_back_rect, I18N.text("common.back", nil, "Back"), C.ORANGE, C, font_s)

    if game._profile_rename_active then
        love.graphics.setFont(font_t)
        love.graphics.setColor(C.DARK_WHITE or C.LIGHT_GREY)
        love.graphics.printf(I18N.text("profile.rename_hint", nil, "Type a name - Enter to save, Esc to cancel"), 0, NAME_RECT.y + NAME_RECT.h + 2, SCREEN_W, "center")
    end

    local targets = ProfileUI.build_focus_targets(game)
    local focused = targets[ProfileUI.focus_index(game, targets)]
    if focused and focused.rect and not ProfileUI.is_renaming(game) then
        love.graphics.setColor(C.WHITE)
        love.graphics.setLineWidth(2)
        PixelGrid.outline(focused.rect.x, focused.rect.y, focused.rect.w, focused.rect.h)
    end
end

--- Standalone career page. Career stats are only kept for the profile that is loaded, so
--- this always reads the active one and names it rather than offering a slot picker.
function ProfileUI.draw_stats(game)
    local C = game.C
    local font_s = game.FONTS.PIXEL.SMALL
    local font_m = game.FONTS.PIXEL.MEDIUM

    love.graphics.setColor(C.PANEL)
    love.graphics.rectangle("fill", 0, 0, SCREEN_W, SCREEN_H)

    love.graphics.setFont(font_m)
    love.graphics.setColor(C.WHITE)
    love.graphics.printf(I18N.text("menu.entry.stats", nil, "Stats"), 0, 10, SCREEN_W, "center")

    local name = game.get_profile_name and game:get_profile_name() or I18N.text("menu.entry.profile", nil, "Profile")
    love.graphics.setFont(font_s)
    love.graphics.setColor(C.DARK_WHITE or C.GREY)
    love.graphics.printf(name, 0, 28, SCREEN_W, "center")

    local panel = { x = 20, y = 46, w = SCREEN_W - 40, h = 152 }
    fill_rect(panel.x, panel.y, panel.w, panel.h, C.BLOCK.BACK, C)

    local inner_x = panel.x + PANEL_PAD * 2
    local inner_w = panel.w - PANEL_PAD * 4
    local row_y = panel.y + PANEL_PAD + 2
    for _, row in ipairs(ProfileUI.career_rows(game)) do
        love.graphics.setFont(font_s)
        love.graphics.setColor(C.DARK_WHITE or C.GREY)
        love.graphics.print(row[1], inner_x, label_y({ y = row_y, h = ROW_H }, font_s))
        love.graphics.setColor(row[3] or C.WHITE)
        love.graphics.printf(row[2], inner_x, label_y({ y = row_y, h = ROW_H }, font_s), inner_w, "right")
        row_y = row_y + ROW_H + ROW_GAP
    end

    local progress = game.get_profile_progress and game:get_profile_progress() or nil
    love.graphics.setFont(font_s)
    love.graphics.setColor(C.DARK_WHITE or C.GREY)
    love.graphics.print(I18N.text("profile.wins", nil, "Wins"), inner_x, label_y({ y = row_y, h = ROW_H }, font_s))
    love.graphics.setColor(C.RED)
    love.graphics.printf(tostring(progress and progress.wins or 0), inner_x,
        label_y({ y = row_y, h = ROW_H }, font_s), inner_w, "right")

    game._stats_back_rect = { x = 20, y = SCREEN_H - 30, w = SCREEN_W - 40, h = 24 }
    draw_button(game._stats_back_rect, I18N.text("common.back", nil, "Back"), C.MULT, C, font_s)
    love.graphics.setColor(C.WHITE)
    love.graphics.setLineWidth(2)
    PixelGrid.outline(game._stats_back_rect.x, game._stats_back_rect.y,
        game._stats_back_rect.w, game._stats_back_rect.h)
end

function ProfileUI.handle_stats_touch(game, x, y)
    local back = game._stats_back_rect
    if back and game:_point_in_rect_simple(x, y, back) then
        ProfileUI.close_stats(game)
        return true
    end
    return false
end

function ProfileUI.handle_stats_button(game, btn)
    if (game.is_menu_back and game:is_menu_back(btn))
        or (game.is_menu_activate and game:is_menu_activate(btn)) then
        ProfileUI.close_stats(game)
    end
end

--------------------------------------------------------------------------------
-- Input
--------------------------------------------------------------------------------

function ProfileUI.build_focus_targets(game)
    local targets = {}
    for i, rect in ipairs(game._profile_tab_rects or {}) do
        targets[#targets + 1] = { kind = "tab", index = i, rect = rect }
    end
    if game._profile_name_rect then
        targets[#targets + 1] = { kind = "name", rect = game._profile_name_rect }
    end
    if game._profile_load_rect then
        targets[#targets + 1] = { kind = "load", rect = game._profile_load_rect }
    end
    if game._profile_delete_rect then
        targets[#targets + 1] = { kind = "delete", rect = game._profile_delete_rect }
    end
    if game._profile_stats_rect then
        targets[#targets + 1] = { kind = "stats", rect = game._profile_stats_rect }
    end
    if game._profile_unlock_rect then
        targets[#targets + 1] = { kind = "unlock", rect = game._profile_unlock_rect }
    end
    if game._profile_back_rect then
        targets[#targets + 1] = { kind = "back", rect = game._profile_back_rect }
    end
    return targets
end

function ProfileUI.focus_index(game, targets)
    local idx = math.floor(tonumber(game._profile_focus_index) or 1)
    if idx < 1 then idx = 1 end
    if idx > #targets then idx = #targets end
    game._profile_focus_index = idx
    return idx
end

function ProfileUI.activate_target(game, target)
    if not target then return false end
    if target.kind == "tab" then
        -- Silent when the tab is already selected, so re-pressing it does not chirp.
        if target.index ~= game._profile_selected then
            Sfx.play("highlight2", 0.685, 0.2)
            Sfx.play("generic1")
        end
        ProfileUI.select_slot(game, target.index)
    elseif target.kind == "name" then
        Sfx.play_button()
        ProfileUI.begin_rename(game)
    elseif target.kind == "load" then
        Sfx.play_button()
        ProfileUI.load_selected(game)
    elseif target.kind == "stats" then
        Sfx.play_button()
        game._profile_show_stats = not game._profile_show_stats
    elseif target.kind == "delete" then
        Sfx.play_button()
        ProfileUI.delete_selected(game)
    elseif target.kind == "unlock" then
        Sfx.play_button()
        ProfileUI.unlock_selected(game)
    elseif target.kind == "back" then
        -- ProfileUI.close plays the cancel cue.
        ProfileUI.close(game)
    else
        return false
    end
    if target.kind ~= "delete" then
        game._profile_delete_confirm = false
    end
    return true
end

function ProfileUI.handle_touch(game, x, y)
    if ProfileUI.is_renaming(game) then
        if game._profile_rename_active then
            ProfileUI.commit_rename(game)
            return true
        end
        return false
    end
    local targets = ProfileUI.build_focus_targets(game)
    for i, target in ipairs(targets) do
        if game:_point_in_rect_simple(x, y, target.rect) then
            game._profile_focus_index = i
            return ProfileUI.activate_target(game, target)
        end
    end
    game._profile_delete_confirm = false
    return false
end

function ProfileUI.handle_button(game, btn)
    if ProfileUI.is_renaming(game) then
        if game.is_menu_back and game:is_menu_back(btn) then
            ProfileUI.cancel_rename(game)
            Sfx.play("cancel")
        elseif game.is_menu_activate and game:is_menu_activate(btn) then
            ProfileUI.commit_rename(game)
        end
        return
    end

    local targets = ProfileUI.build_focus_targets(game)
    if #targets == 0 then return end
    local idx = ProfileUI.focus_index(game, targets)

    if btn == "dpleft" or btn == "left" or btn == "dpup" or btn == "up" then
        idx = idx - 1
        if idx < 1 then idx = #targets end
        if idx ~= game._profile_focus_index then Sfx.play("highlight1", nil, 0.2) end
        game._profile_focus_index = idx
    elseif btn == "dpright" or btn == "right" or btn == "dpdown" or btn == "down" then
        idx = idx + 1
        if idx > #targets then idx = 1 end
        if idx ~= game._profile_focus_index then Sfx.play("highlight1", nil, 0.2) end
        game._profile_focus_index = idx
    elseif game.is_menu_activate and game:is_menu_activate(btn) then
        ProfileUI.activate_target(game, targets[idx])
    elseif game.is_menu_back and game:is_menu_back(btn) then
        ProfileUI.close(game)
    end
end

return ProfileUI
