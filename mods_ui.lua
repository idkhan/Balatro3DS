--- Options > Mods: every installed mod, whether it loaded, and why not, with a switch to turn
--- each one off and on.
---
--- Also where Continue lands when a saved run was played with a different set of mods
--- (`Game:check_saved_run_mods`): the page then leads with what to install or remove before
--- that run can be resumed, and re-checks as mods are switched. The run itself is left on the
--- card untouched.
---
--- The page is one scrolling column of wrapped lines, because a load error is free text of any
--- length and a 320 px screen will not fit a table of them. Each mod's name line carries its
--- switch. A switch takes effect at once (`ModLoader.set_enabled` reloads every mod): the page
--- is only reachable from the main menu, so no run is in memory to be pulled out from under.

local ModLoader = require("mod_loader")

local ModsUI = {}

local SCREEN_W, SCREEN_H = 320, 240
local LIST_X, LIST_Y, LIST_W = 14, 34, SCREEN_W - 28
local LIST_BOTTOM = SCREEN_H - 38
local LINE_GAP = 1
local SWITCH_W = 34

function ModsUI.open(game)
    game._menu_sub_state = "mods"
    game._mods_scroll = 0
    game._mods_focus = 1
    Sfx.play("paper1")
end

function ModsUI.close(game)
    game._menu_sub_state = "main"
    game._mods_continue_block = nil
    game._mods_continue_saved = nil
    Sfx.play("cancel")
end

--- The mods that have a switch, in page order.
function ModsUI.switchable()
    local out = {}
    for _, mod in ipairs(ModLoader.mods or {}) do
        if ModLoader.can_toggle(mod) then out[#out + 1] = mod end
    end
    return out
end

local function focused_mod(game)
    local mods = ModsUI.switchable()
    if #mods == 0 then return nil end
    local i = math.max(1, math.min(#mods, math.floor(tonumber(game._mods_focus) or 1)))
    game._mods_focus = i
    return mods[i]
end

--- Every line the page shows, before wrapping: `{ text, colour_key, font = "small"|"medium",
--- mod = <the mod, on its name line> }`.
function ModsUI.lines(game)
    local out = {}
    local block = game._mods_continue_block
    if block then
        out[#out + 1] = { I18N.text("mods.mismatch_1", nil, "This run was saved with different mods."), "RED" }
        out[#out + 1] = { I18N.text("mods.mismatch_2", nil, "Change them to continue it:"), "RED" }
        for _, line in ipairs(ModLoader.describe_mismatch(block)) do
            out[#out + 1] = { "  " .. line, "WHITE" }
        end
        out[#out + 1] = { " ", "WHITE" }
    elseif game._mods_continue_saved then
        out[#out + 1] = { I18N.text("mods.mismatch_fixed", nil, "Mods now match the saved run. Go back to continue it."), "GREEN" }
        out[#out + 1] = { " ", "WHITE" }
    end
    local mods = ModLoader.mods or {}
    if #mods == 0 then
        out[#out + 1] = { I18N.text("mods.none", nil, "No mods installed."), "GREY" }
        out[#out + 1] = { I18N.text("mods.where", { dir = ModLoader.DIR }, "Put mods in " .. ModLoader.DIR .. "/ in the save folder."), "GREY" }
        return out
    end
    for _, mod in ipairs(mods) do
        local ok = mod.status == "loaded"
        local off = mod.status == "disabled"
        out[#out + 1] = { ("%s  v%s"):format(mod.name or mod.id, mod.version or "?"),
            ok and "GREEN" or (off and "GREY" or "RED"), font = "medium",
            mod = ModLoader.can_toggle(mod) and mod or nil }
        if off then
            out[#out + 1] = { I18N.text("mods.turned_off", nil, "Turned off"), "GREY" }
        elseif ok then
            local reg = mod.registered or {}
            local parts = {}
            for _, kind in ipairs({ { "jokers", "Joker" }, { "consumables", "Consumable" }, { "vouchers", "Voucher" }, { "decks", "Deck" }, { "editions", "Edition" }, { "deck_skins", "Card Art Set" } }) do
                local n = #(reg[kind[1]] or {})
                if n > 0 then
                    parts[#parts + 1] = I18N.text("mods.count." .. kind[1], { count = n },
                        ("%d %s%s"):format(n, kind[2], n == 1 and "" or "s"))
                end
            end
            if #parts == 0 then parts[1] = I18N.text("mods.nothing_added", nil, "Nothing added") end
            out[#out + 1] = { table.concat(parts, I18N.text("common.list_separator", nil, ", ")) .. ((mod.author ~= nil and mod.author ~= "")
                and I18N.text("mods.by", { author = mod.author }, "  -  by " .. mod.author) or ""), "GREY" }
        else
            out[#out + 1] = { I18N.text("mods.not_loaded", nil, "Not loaded: ") .. tostring(mod.error), "RED" }
        end
        for _, err in ipairs(mod.runtime_errors or {}) do
            out[#out + 1] = { I18N.text("mods.error", nil, "Error: ") .. tostring(err), "ORANGE" }
        end
    end
    out[#out + 1] = { " ", "WHITE" }
    out[#out + 1] = { I18N.text("mods.details", nil, "Details: ") .. ModLoader.LOG_PATH, "GREY" }
    return out
end

local function font_for(game, which)
    return which == "medium" and game.FONTS.PIXEL.MEDIUM or game.FONTS.PIXEL.SMALL
end

--- The lines wrapped to the list width: `{ text, colour, font, h, mod = <on a name line's first
--- row> }`. A name line leaves room on the right for its switch.
local function wrapped(game)
    local out = {}
    for _, line in ipairs(ModsUI.lines(game)) do
        local font = font_for(game, line.font)
        local width = line.mod and (LIST_W - SWITCH_W - 6) or LIST_W
        local pieces = { line[1] }
        if font.getWrap then
            local _, w = font:getWrap(line[1], width)
            if type(w) == "table" and #w > 0 then pieces = w end
        end
        for i, piece in ipairs(pieces) do
            out[#out + 1] = { piece, line[2], font, font:getHeight() + LINE_GAP, mod = i == 1 and line.mod or nil }
        end
    end
    return out
end

--- How far the list can scroll, in lines.
local function max_scroll(rows)
    local h, n = 0, 0
    for i = #rows, 1, -1 do
        h = h + rows[i][4]
        if h > LIST_BOTTOM - LIST_Y then break end
        n = n + 1
    end
    return math.max(0, #rows - n)
end

--- Scroll so the focused mod's name line, and the line under it, are on screen.
local function scroll_to_focus(game)
    local mod = focused_mod(game)
    if not mod then return end
    local rows = wrapped(game)
    local at
    for i, row in ipairs(rows) do
        if row.mod and row.mod.id == mod.id then at = i break end
    end
    if not at then return end
    local last = (rows[at + 1] and not rows[at + 1].mod) and at + 1 or at
    local top = math.floor(tonumber(game._mods_scroll) or 0)
    -- The first mod scrolls right up, so the saved-run notice above it shows again.
    if game._mods_focus == 1 then top = 0 end
    if at - 1 < top then top = at - 1 end
    local function fits()
        local h = 0
        for i = top + 1, last do h = h + rows[i][4] end
        return LIST_Y + h <= LIST_BOTTOM
    end
    while top < at - 1 and not fits() do top = top + 1 end
    game._mods_scroll = math.min(top, max_scroll(rows))
end

--- Flip one mod's switch. Every mod reloads, so `ModLoader.mods` holds new tables afterwards;
--- focus is an index into a list sorted by id, which the reload leaves in the same order.
function ModsUI.toggle(game, mod)
    if not ModLoader.can_toggle(mod) then return false end
    ModLoader.set_enabled(mod.id, not ModLoader.is_enabled(mod))
    -- A deck a mod adds needs its stake ladder in the profile's unlocks; one it took away keeps
    -- its progress there for when it comes back (`Game:normalize_unlocks`).
    if game.apply_unlocks then game:apply_unlocks(game.unlocks) end
    local saved = game._mods_continue_saved
    if saved then game._mods_continue_block = ModLoader.compare(saved.mods) end
    Sfx.play_button()
    return true
end

local function draw_switch(game, x, y, h, on)
    local C = game.C
    love.graphics.setColor(on and C.GREEN or C.GREY)
    love.graphics.rectangle("fill", x, y, SWITCH_W, h, 3, 3)
    love.graphics.setColor(C.WHITE)
    love.graphics.setFont(game.FONTS.PIXEL.SMALL)
    local font = love.graphics.getFont()
    love.graphics.printf(on and I18N.text("mods.on", nil, "ON") or I18N.text("mods.off", nil, "OFF"),
        x, y + math.floor((h - font:getHeight()) / 2), SWITCH_W, "center")
end

function ModsUI.draw(game)
    local C = game.C
    love.graphics.setColor(C.PANEL)
    love.graphics.rectangle("fill", 0, 0, SCREEN_W, SCREEN_H)
    love.graphics.setFont(game.FONTS.PIXEL.MEDIUM)
    love.graphics.setColor(C.WHITE)
    love.graphics.printf(I18N.text("menu.entry.mods", nil, "Mods"), 0, 10, SCREEN_W, "center")

    local rows = wrapped(game)
    local top = math.max(0, math.min(max_scroll(rows), math.floor(tonumber(game._mods_scroll) or 0)))
    game._mods_scroll = top
    local focus = focused_mod(game)
    game._mods_switch_rects = {}
    local y = LIST_Y
    for i = top + 1, #rows do
        local row = rows[i]
        if y + row[4] > LIST_BOTTOM then break end
        love.graphics.setFont(row[3])
        love.graphics.setColor(C[row[2]] or C.WHITE)
        love.graphics.print(row[1], LIST_X, y)
        if row.mod then
            local rect = { x = LIST_X - 4, y = y - 1, w = LIST_W + 8, h = row[4] + 1, mod = row.mod }
            game._mods_switch_rects[#game._mods_switch_rects + 1] = rect
            draw_switch(game, LIST_X + LIST_W - SWITCH_W, y, row[4] - LINE_GAP, ModLoader.is_enabled(row.mod))
            if focus and row.mod.id == focus.id then
                love.graphics.setColor(C.WHITE)
                love.graphics.setLineWidth(2)
                love.graphics.rectangle("line", rect.x + 0.5, rect.y + 0.5, rect.w - 1, rect.h - 1)
            end
        end
        y = y + row[4]
    end
    local hint
    if focus then
        hint = I18N.text("mods.switch_hint", nil, "Up/Down: choose   A: turn on/off")
    elseif max_scroll(rows) > 0 then
        hint = I18N.text("mods.scroll_hint", nil, "Up/Down to scroll")
    end
    if hint then
        love.graphics.setFont(game.FONTS.PIXEL.SMALL)
        love.graphics.setColor(C.GREY)
        love.graphics.printf(hint, 0, LIST_BOTTOM + 1, SCREEN_W, "center")
    end

    game._mods_back_rect = { x = 20, y = SCREEN_H - 30, w = SCREEN_W - 40, h = 24 }
    local r = game._mods_back_rect
    love.graphics.setColor(C.MULT)
    love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 4, 4)
    love.graphics.setColor(C.WHITE)
    love.graphics.setFont(game.FONTS.PIXEL.SMALL)
    local font = love.graphics.getFont()
    love.graphics.printf(I18N.text("common.back", nil, "Back"), r.x, r.y + math.floor((r.h - font:getHeight()) / 2), r.w, "center")
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", r.x + 0.5, r.y + 0.5, r.w - 1, r.h - 1)
end

function ModsUI.scroll(game, delta)
    game._mods_scroll = math.max(0, math.floor(tonumber(game._mods_scroll) or 0) + delta)
end

--- Move the focus one mod up or down; past either end, scroll instead, so the saved-run notice
--- above the first mod and the long errors under the last stay reachable.
function ModsUI.move_focus(game, delta)
    local n = #ModsUI.switchable()
    local i = math.floor(tonumber(game._mods_focus) or 1)
    if n > 0 and i + delta >= 1 and i + delta <= n then
        game._mods_focus = i + delta
        Sfx.play("highlight1", nil, 0.2)
        scroll_to_focus(game)
    else
        ModsUI.scroll(game, delta)
    end
end

function ModsUI.handle_touch(game, x, y)
    local back = game._mods_back_rect
    if back and game:_point_in_rect_simple(x, y, back) then
        ModsUI.close(game)
        return true
    end
    for _, rect in ipairs(game._mods_switch_rects or {}) do
        if game:_point_in_rect_simple(x, y, rect) then
            for i, mod in ipairs(ModsUI.switchable()) do
                if mod.id == rect.mod.id then game._mods_focus = i end
            end
            ModsUI.toggle(game, rect.mod)
            return true
        end
    end
    -- Top and bottom halves of the list scroll, the way a thumb reaches for them.
    if y >= LIST_Y and y < LIST_BOTTOM then
        ModsUI.scroll(game, y < (LIST_Y + LIST_BOTTOM) / 2 and -3 or 3)
        return true
    end
    return false
end

function ModsUI.handle_button(game, btn)
    if btn == "dpup" or btn == "up" then
        ModsUI.move_focus(game, -1)
    elseif btn == "dpdown" or btn == "down" then
        ModsUI.move_focus(game, 1)
    elseif game.is_menu_back and game:is_menu_back(btn) then
        ModsUI.close(game)
    elseif game.is_menu_activate and game:is_menu_activate(btn) then
        local mod = focused_mod(game)
        if mod then ModsUI.toggle(game, mod) else ModsUI.close(game) end
    end
end

return ModsUI
