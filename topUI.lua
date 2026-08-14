local GameOverUI = require("game_over_ui")
local DynaText = require("dyna_text")
local Fonts = require("fonts")
local NumberFormat = require("number_format")
-- Static labels are shaped once and redrawn; see text_cache.lua for why that is the
-- largest saving on this screen.
local TextCache = require("text_cache")

---@class TopUI
TopUI = Object:extend()

sysDepth = 0
buttonHeight = 1
textHeight = 2
signHeight = 3
jokerHeight = 2
PopupHeight = 4

--- Top-screen UI: draw content for the 3DS top screen (or equivalent when screen ~= "bottom").

--- Counter pop: the original juices the mult readout on every change with the same
--- `juice_up` curve a card gets (`common_events.lua:545`). `TopUI` extends `Object`, not
--- `Moveable`, so each counter keeps a bare state table and borrows `Moveable`'s curve
--- through it - one implementation, not two that drift apart.
---
--- Strength 1 is the original's UI default (0.4 amplitude), which overshoots further than a
--- card does; `center_text_juiced` caps growth at the counter's box, so a number that already
--- fills its box only dips.
local COUNTER_JUICE = 1

--- Start a counter pop and return the state table to keep it in.
local function begin_juice(state)
    state = state or {}
    Moveable.juice_up(state, COUNTER_JUICE)
    return state
end

--- Advance a counter pop. Returns the scale multiplier, or nil once it has settled.
local function step_juice(state, dt)
    if not state or not state.juice then return nil end
    Moveable.update_juice(state, dt)
    return state.juice_scale
end

--- Score count-up. A single hand can multiply the round score by four orders of magnitude, so
--- the ease runs in log space: equal time per decade rather than per point. A linear ramp would
--- sit near 300 for most of the animation and then blur through the last three million in two
--- frames.
---
--- The *duration* is fixed at the reference's 0.5 s (`state_events.lua:1043-1060`) regardless
--- of the size of the jump, because the chip total drains to zero over exactly that window and
--- the two readouts have to land together - the whole point of the beat is that the product
--- visibly pours into the score. Scaling the duration with the jump (which this used to do,
--- up to 0.9 s) left the score still climbing for up to 0.4 s after the total had emptied.
---
--- exp is monotone and the endpoint is assigned exactly rather than evaluated, so the readout
--- only ever climbs and always lands on the true score. The displayed value is floored, never
--- rounded, so it cannot momentarily read one point high.
local SCORE_EASE_DURATION = 0.5

--- Draw a rounded rectangle and return the inner area (with padding) for placing content.
--- @param x number Left edge
--- @param y number Top edge
--- @param w number Width
--- @param h number Height
--- @param radius number Corner radius (rx and ry)
--- @param padding number|nil Inset from all sides for content (default 0)
--- @param mode "fill"|"line"|nil Draw mode (default "fill")
--- @return number inner_x, number inner_y, number inner_w, number inner_h Content bounds inside the rect
function draw_rounded_rect(x, y, w, h, radius, padding, mode)
    padding = padding or 0
    mode = mode or "fill"
    radius = math.min(radius or 0, w / 2, h / 2)
    if radius < 0 then radius = 0 end

    -- Only touch the line width when this rect is actually going to read it. The reset used
    -- to run unconditionally, so a fill -- which is nearly every rect on screen, around 28 a
    -- frame on the top screen alone -- paid a state change nothing consumes. It is 2.04 us a
    -- call on hardware. Every site in this codebase that draws a line sets its own width
    -- immediately beforehand, so nothing was relying on this to leave the width at 1.
    local styled = (mode == "line" and padding ~= 0)
    if styled then love.graphics.setLineWidth(padding) end
    love.graphics.rectangle(mode, x, y, w, h, radius, radius)
    if styled then love.graphics.setLineWidth(1) end

    local pad = padding
    return x + pad, y + pad, w - (2 * pad), h - (2 * pad)
end

function draw_rect_with_shadow(x, y, w, h, radius, padding, color, shadowColor, shadowSize, offset)
    local ox = tonumber(offset) or 0
    local rx = x - ox
    love.graphics.setColor(shadowColor)
    draw_rounded_rect(rx, y + shadowSize, w, h, radius, padding, "fill")
    love.graphics.setColor(color)
    return draw_rounded_rect(rx, y, w, h, radius, padding, "fill")
end

--- `draw_rect_with_shadow` for buttons: while the active touch sits on the rect (and for
--- a beat after release, so a tap still reads), the face sinks onto its shadow — the
--- reference physically depresses buttons by dropping their `shadow_height` on press
--- (`reference/Balatro/engine/ui.lua:404-409`). Callers keep drawing labels at the
--- resting coordinates; a 2 px sink under a static label reads fine at 240p.
function draw_button_with_shadow(x, y, w, h, radius, padding, color, shadowColor, shadowSize, offset)
    local p = G and G._ui_press
    if p then
        local ox = tonumber(offset) or 0
        local rx = x - ox
        local inside = p.x >= rx and p.x <= rx + w and p.y >= y and p.y <= y + h + shadowSize
        local recent = p.held
            or (p.released_at and love.timer and (love.timer.getTime() - p.released_at) < 0.09)
        if inside and recent then
            love.graphics.setColor(color)
            return draw_rounded_rect(rx, y + shadowSize, w, h, radius, padding, "fill")
        end
    end
    return draw_rect_with_shadow(x, y, w, h, radius, padding, color, shadowColor, shadowSize, offset)
end

--- One-value string memo, so the common frame formats nothing.
---
--- `chips_readout`/`mult_readout` already do this for the two counters; these are the same
--- treatment for the handful of other labels that were being concatenated fresh on every
--- frame, several of them for values that change once a blind or never.
--- @return string
function TopUI:cached_label(key, value, prefix, suffix)
    local cache = self._label_cache
    if not cache then
        cache = {}
        self._label_cache = cache
    end
    local entry = cache[key]
    if entry and entry.value == value then return entry.text end
    local text = (prefix or "") .. tostring(value) .. (suffix or "")
    if entry then
        entry.value, entry.text = value, text
    else
        cache[key] = { value = value, text = text }
    end
    return text
end

--- Face and shadow for the plate that covers a readout while a gain is being pushed into it.
---
--- The reference builds it as `mix_colours(<panel>, G.C.GREEN, 0.1)` (`common_events.lua:515`),
--- i.e. a tenth of the panel's own colour in nine tenths green, so a chips gain and a mult gain
--- read as the same event while still belonging to their side. Cached per key: the mix is
--- constant and this runs inside the draw loop.
--- @param key string
--- @param base table panel colour being covered
--- @return table face, table shadow
function TopUI:gain_cover_colours(key, base)
    local cache = self._cover_colours
    if not cache then
        cache = {}
        self._cover_colours = cache
    end
    local entry = cache[key]
    if entry then return entry[1], entry[2] end
    local green = G.C.GREEN
    local face = {
        base[1] * 0.1 + green[1] * 0.9,
        base[2] * 0.1 + green[2] * 0.9,
        base[3] * 0.1 + green[3] * 0.9,
        1,
    }
    entry = { face, { face[1] * 0.6, face[2] * 0.6, face[3] * 0.6, 1 } }
    cache[key] = entry
    return entry[1], entry[2]
end

--- Memo for an "n/limit" readout, keyed on both halves. The slot counters redraw every frame
--- on the top screen and neither half changes often, so building the string each time would
--- be two throwaway allocations a frame for nothing.
--- @return string
function TopUI:cached_ratio_label(key, used, limit)
    local cache = self._ratio_label_cache
    if not cache then
        cache = {}
        self._ratio_label_cache = cache
    end
    local entry = cache[key]
    if entry and entry.used == used and entry.limit == limit then return entry.text end
    local text = tostring(used) .. "/" .. tostring(limit)
    if entry then
        entry.used, entry.limit, entry.text = used, limit, text
    else
        cache[key] = { used = used, limit = limit, text = text }
    end
    return text
end

--- "3/8", as the reference prints it (`UI_definitions.lua:1319-1326`) - but only while the win
--- ante is still ahead of the player.
---
--- Once the run is past it there is nothing left to count towards, and the denominator is worse
--- than useless: "10/8" is four glyphs plus a slash in a 46 px field, so it wrapped and put the
--- "/8" on its own line under the ante. The reference's HUD is 1280 px wide and keeps the
--- denominator forever because it can afford to.
---
--- Memoized on both halves rather than through `cached_label`, which keys on one value: the
--- suffix appearing and disappearing is exactly the case a one-value memo would miss.
--- @return string
function TopUI:ante_readout()
    local ante = G and G.ante
    local win = (G and G.get_win_ante) and G:get_win_ante() or nil
    local cache = self._ante_label
    if cache and cache.ante == ante and cache.win == win then return cache.text end

    local n, w = tonumber(ante), tonumber(win)
    local text
    if w and n and n > w then
        text = tostring(ante)
    else
        text = tostring(ante) .. "/" .. tostring(win)
    end
    self._ante_label = { ante = ante, win = win, text = text }
    return text
end

--- The reward readout is one "$" per dollar, not the number, so it needs its own memo.
--- @return string
function TopUI:cached_reward_pips(dollars)
    local cache = self._reward_pip_cache
    if cache and cache.value == dollars then return cache.text end
    local text = "$" .. string.rep("$", dollars) .. "+"
    self._reward_pip_cache = { value = dollars, text = text }
    return text
end

--- The tray behind the joker or consumable row.
---
--- Filled when the area holds something, and an outline when it does not: the reference's
--- version is one faint `{0,0,0,0.1}` panel either way (`cardarea.lua:292`), which on a
--- 1280x720 window over a moving background is enough to read as "cards go here". At 400x240
--- against this port's opaque tray colour, the same panel sitting empty reads as a solid slab
--- rather than a space, so an empty area is outlined instead of filled.
---@param occupied boolean whether the area currently holds anything
function TopUI:draw_inventory_tray(x, y, w, h, occupied, depth)
    local C = G and G.C
    local back = C and C.BLOCK and C.BLOCK.BACK or { 0, 0, 0, 1 }
    if occupied then
        if _G.draw_rect_with_shadow then
            draw_rect_with_shadow(x, y, w, h, 4, 2, back,
                C and C.BLOCK and C.BLOCK.SHADOW or { 0, 0, 0, 1 }, 2, depth)
        else
            love.graphics.setColor(C and C.PANEL or { 0.2, 0.2, 0.2, 1 })
            love.graphics.rectangle("fill", x, y, w, h, 4, 4)
        end
        return
    end

    love.graphics.setColor(back[1], back[2], back[3], (back[4] or 1) * 0.45)
    love.graphics.rectangle("fill", x - (depth or 0), y, w, h, 4, 4)
    love.graphics.setColor(C and C.GREY or { 0.5, 0.5, 0.5, 1 })
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x - (depth or 0) + 0.5, y + 0.5, w - 1, h - 1, 4, 4)
end

function TopUI:draw(screen)
    sysDepth = -love.graphics.getDepth()
    if screen == "right" then
        sysDepth = -sysDepth
    end
    if G and G.STATES and G.STATE == G.STATES.GAME_OVER then
        GameOverUI.draw_top(G)
        return
    end
    local depthOffset = sysDepth * buttonHeight
    local jokerDepthOffset = sysDepth * jokerHeight
    local popupDepthOffset = sysDepth * PopupHeight
    local panelHeight = 104
    local panelY = 4
    local is_blind_select = (G.STATE == G.STATES.BLIND_SELECT)
    local blind_def = nil
    if G and G.get_blind_def then
        if G.STATE == G.STATES.SELECTING_HAND then
            blind_def = G:get_blind_def(G.current_blind_index or 1)
        else
            blind_def = G:get_preview_blind()
        end
    end
    local blind_index = G.selected_blind_index or G.current_blind_index or 1
    if G.STATE == G.STATES.SELECTING_HAND or G.STATE == G.STATES.ROUND_EVAL or G.STATE == G.STATES.GAME_OVER then
        blind_index = G.current_blind_index or blind_index
    end
    local blind_name = (G.get_blind_display_name and G:get_blind_display_name(blind_index)) or ((blind_def and blind_def.name) or (G.current_blind_name or "Blind"))
    
    local blind_target = tonumber(G.current_blind_target) or 0
    if G.STATE == G.STATES.BLIND_SELECT and G.get_blind_target then
        blind_target = G:get_blind_target(G.selected_blind_index or G.current_blind_index or 1, G.ante)
    end
    local blind_reward = tonumber(G.current_blind_reward) or 0
    if G.STATE == G.STATES.BLIND_SELECT and blind_def then
        blind_reward = tonumber(blind_def.reward) or blind_reward
        if blind_def.id == "boss" and G.get_boss_blind_prototype then
            local proto = G:get_boss_blind_prototype()
            blind_reward = tonumber(proto and proto.dollars) or blind_reward
        end
    end
    local blind_key = (blind_def and blind_def.key) or "Big"
    local blind_color = G.C.BLIND_COLORS.Big
    if not is_blind_select then
        blind_color = (G.get_blind_color and G:get_blind_color(blind_index)) or G.C.BLIND_COLORS.Big
    end
    local factor = 0.5
    local blind_dark = {blind_color[1] * factor, blind_color[2] * factor, blind_color[3] * factor, blind_color[4]}
    local blind_sign = blind_dark

    -- Panel
    love.graphics.setColor(G.C.PANEL)
    love.graphics.rectangle("fill", 0, panelY, 400, panelHeight)

    love.graphics.setColor(G.C.BLIND_COLORS.Big)
    love.graphics.rectangle("line", 0, panelY, 401, panelHeight)

    -- Title
    local titlePosX = 2
    local titlePosY = 5 + panelY
    local titleHeight = 90
    local titleWidth = 120
    love.graphics.setColor(G.C.BLOCK.SHADOW)
    local ix, iy, iw, ih = draw_rect_with_shadow(titlePosX, titlePosY, titleWidth, titleHeight , 4, 2, G.C.BLOCK.BACK, G.C.BLOCK.SHADOW, 2, depthOffset)

    -- Blind
    local blindPosX, blindPosY = ix, iy
    local blindWidth, blindHeight = iw, math.floor((ih/4) - 1)
    
    love.graphics.setColor(G.C.WHITE)
    love.graphics.setFont(G.FONTS.PIXEL.MEDIUM)
    
    
    if is_blind_select then
        TopUI.center_text_static("Choose blind", ix - sysDepth * textHeight, iy -2, iw, ih)

    elseif G.STATE == G.STATES.ROUND_EVAL then
        love.graphics.setColor(G.C.WHITE)
        love.graphics.setFont(G.FONTS.PIXEL.MEDIUM)
        TopUI.center_text_static("Round won!", ix - sysDepth * textHeight, iy - 6, iw, math.floor(ih * 0.55))
        local bi = G.current_blind_index or 1
        G:draw_blind_chip_anim(bi, ix + math.floor(iw / 2) - sysDepth * signHeight, iy + math.floor(ih * 0.72), 1.05)

    elseif G.STATE == G.STATES.SHOP then
        local cell_w = 113
        local cell_h = 60
        if G.ANIMATION_ATLAS and G.ANIMATION_ATLAS.shop_sign then
            local a = G.ANIMATION_ATLAS.shop_sign
            cell_w = tonumber(a.px) or cell_w
            cell_h = tonumber(a.py) or cell_h
        end
        local s = math.min(iw / cell_w, ih / cell_h) * 0.92
        if s > 1.25 then s = 1.25 end
        G:draw_shop_sign_anim(ix + math.floor(iw / 2) - sysDepth * signHeight, iy + math.floor(ih / 2), s)

    elseif G.STATE == G.STATES.OPEN_BOOSTER then
        love.graphics.setColor(G.C.WHITE)
        love.graphics.setFont(G.FONTS.PIXEL.MEDIUM)
        local sess = G.booster_session
        local t1 = (sess and sess.title) or "Booster Pack"
        TopUI.center_text(t1, ix, iy - 4, iw, math.floor(ih * 0.45))
        love.graphics.setFont(G.FONTS.PIXEL.MEDIUM)
        local pr = sess and tonumber(sess.picks_remaining) or 0
        TopUI.center_text(self:cached_label("picks", pr, "Picks left: "), ix - sysDepth * textHeight, iy + math.floor(ih * 0.6), iw, math.floor(ih * 0.35))

    else
        -- Score Requirements Box
        ix, iy, iw, ih = draw_rect_with_shadow(blindPosX, blindPosY, blindWidth, blindHeight, 4, 4, blind_color, blind_dark, 2, depthOffset)
        local is_boss_blind = blind_def and blind_def.id == "boss"
        local blind_name_x, blind_name_w = ix - sysDepth * textHeight, iw
        if is_boss_blind then
            love.graphics.setFont(G.FONTS.PIXEL.MICRO or G.FONTS.PIXEL.SMALL)
            love.graphics.setColor(G.C.RED)
            DynaText.draw(self.boss_indicator_text, "BOSS", blind_name_x + 2, iy + 3, 24, "left")
            blind_name_x = blind_name_x + 22
            blind_name_w = blind_name_w - 22
            love.graphics.setFont(G.FONTS.PIXEL.MEDIUM)
        end
        love.graphics.setColor(G.C.WHITE)
        -- Boss names run to "Crimson Heart" and "Verdant Leaf", which are wider than this block at
        -- MEDIUM; DynaText lays out per glyph off the current font, so the fit has to happen here.
        love.graphics.setFont(Fonts.fit(G, G.FONTS.PIXEL.MEDIUM, blind_name, blind_name_w))
        DynaText.draw(self.blind_name_text, blind_name, blind_name_x, iy - 2, blind_name_w, "center")
        
        love.graphics.setColor(blind_sign)
        ix, iy, iw, ih = draw_rounded_rect(blindPosX, blindPosY + blindHeight + 4, blindWidth, blindHeight * 3, 4, 4, "fill")
        local score_box_ix, score_box_iy, score_box_iw, score_box_ih = ix, iy, iw, ih

        
        ix, iy, iw, ih = draw_rect_with_shadow(score_box_ix + math.floor(score_box_iw/3), score_box_iy - 1, 72, score_box_ih, 4, 4, G.C.BLOCK.BACK, G.C.BLOCK.SHADOW, 2, depthOffset)

        G:draw_blind_chip_anim(
            blind_index,
            score_box_ix + math.floor(score_box_iw / 6) - 2,
            score_box_iy + math.floor(score_box_ih / 2),
            1.1
        )
        
        local show_boss_effect = G.STATE == G.STATES.SELECTING_HAND and blind_def and blind_def.id == "boss"
        if show_boss_effect then
            -- The reference keeps each boss debuff visible in its blind UI
            -- (`reference/Balatro/functions/UI_definitions.lua:2933-2979`). Reuse the
            -- readout's blind block so the 320x240 touch screen remains uncluttered.
            local effect = G.get_boss_effect_text and G:get_boss_effect_text() or ""
            love.graphics.setFont(G.FONTS.PIXEL.MICRO or G.FONTS.PIXEL.SMALL)
            love.graphics.setColor(G.C.WHITE)
            love.graphics.printf(effect, score_box_ix + 34 - sysDepth * textHeight, score_box_iy + 2, score_box_iw - 36, "left")
            love.graphics.setFont(G.FONTS.PIXEL.SMALL)
            love.graphics.setColor(G.C.WHITE)
            TextCache.print("Score", score_box_ix + 34 - sysDepth * textHeight, score_box_iy + score_box_ih - 21)
            local bossReq = NumberFormat.format(math.floor(blind_target))
            love.graphics.setFont(Fonts.fit(G, G.FONTS.PIXEL.MEDIUM, bossReq, score_box_iw - 36))
            love.graphics.setColor(G.C.RED)
            love.graphics.printf(bossReq, score_box_ix + 34 - sysDepth * textHeight,
                score_box_iy + score_box_ih - 14, score_box_iw - 36, "center")
        else
            love.graphics.setColor(G.C.WHITE)
            love.graphics.setFont(G.FONTS.PIXEL.SMALL)
            TextCache.print("Score at least", ix - sysDepth * textHeight, iy - 2)

            love.graphics.setColor(G.C.RED)
            local scoreReq = NumberFormat.format(math.floor(blind_target))
            love.graphics.setFont(Fonts.fit(G, G.FONTS.PIXEL.MEDIUM, scoreReq, iw))
            local scoreReqY = iy + math.floor(G.FONTS.PIXEL.SMALL_HEIGHT/2) + 5
            love.graphics.printf(scoreReq, ix - sysDepth * textHeight, scoreReqY, iw, "center")

            love.graphics.setColor(G.C.WHITE)
            love.graphics.setFont(G.FONTS.PIXEL.SMALL)
            local rewardText = "Reward: "
            local rewardY = iy + math.floor(G.FONTS.PIXEL.SMALL_HEIGHT/2) + 6 + G.FONTS.PIXEL.MEDIUM_HEIGHT
            TextCache.print(rewardText, ix - sysDepth * textHeight, rewardY)
            love.graphics.setColor(G.C.MONEY)
            local moneyText = self:cached_reward_pips(blind_reward)
            local rewardLabelW = love.graphics.getFont():getWidth(rewardText)
            love.graphics.print(moneyText, ix + rewardLabelW - sysDepth * textHeight, rewardY)
        end
    end

    -- Round Score, Chips and Mult
    love.graphics.setColor(G.C.BLOCK.SHADOW)
    local width = 64
    ix, iy, iw, ih = draw_rounded_rect(titlePosX + (width * 2) - 4, titlePosY, titleWidth, math.floor(titleHeight/3.5), 4, 4, "fill")
    
    love.graphics.setFont(G.FONTS.PIXEL.SMALL)
    love.graphics.setColor(G.C.WHITE)
    TextCache.print("Round", ix, iy - 3)
    TextCache.print("Score", ix, iy + 7)

    love.graphics.setColor(G.C.PANEL)
    local paneOffset = 30
    ix, iy, iw, ih = draw_rounded_rect(ix + paneOffset, iy, iw - paneOffset, ih, 2, 2, "fill")

    -- The eased count-up value, not `G.round_score`: the fit has to follow what is actually on
    -- screen or a climb past a rung would shrink the text before it gets there. Measuring the
    -- string rather than testing the value is what makes the separators safe - "9,999,999" is
    -- two glyphs wider than the number it groups, and a digit threshold cannot know that.
    local score = self:score_readout()
    love.graphics.setFont(Fonts.fit(G, G.FONTS.PIXEL.MEDIUM, score, iw))
    love.graphics.setColor(G.C.WHITE)
    TopUI.center_text(score, ix - sysDepth * textHeight, iy -1, iw, ih)


    love.graphics.setColor(G.C.BLOCK.SHADOW)
    ix, iy, iw, ih = draw_rounded_rect(titlePosX + (width * 2) - 4, titlePosY + math.floor(titleHeight/3.5) + 4, titleWidth, titleHeight - math.floor(titleHeight/3.5) - 3, 4, 4, "fill")

    love.graphics.setColor(G.C.WHITE)
    love.graphics.setFont(G.FONTS.PIXEL.MEDIUM)
    -- A hand level-up owns this readout for as long as it runs: the reference points the hand
    -- text area at the hand being levelled and walks mult, chips and level up in turn
    -- (`card.lua:1265-1267`). It outranks the booster blanking below, because a Celestial pack
    -- levels hands from inside a pack and that is the only place the result is shown.
    local levelup = G._hand_levelup
    local handSelected = ""
    local handHidden = (G.selectedHandHidden == true)
    -- Picking hand cards inside a booster pack targets a consumable, not a play:
    -- the hand type and chips/mult preview would be meaningless there.
    local hide_hand_preview = (G.STATE == G.STATES.OPEN_BOOSTER) and not levelup
    if levelup then
        handHidden = false
        handSelected = levelup.hand
    elseif hide_hand_preview then
        handHidden = false
    elseif G.selectedHand and G.selectedHand ~= -1 then
        handSelected = G.handlist[G.selectedHand]
    end
    if handHidden then
        handSelected = "???"
    end
    if(love.graphics.getFont():getWidth(handSelected) > (iw - 20)) then
        love.graphics.setFont(G.FONTS.PIXEL.SMALL)
    end
    -- Popped whenever the detected hand changes, the way the mult and level readouts beside it
    -- already are. The reference juices the whole hand-text area on every `update_hand_text`
    -- (`common_events.lua:553`), and this was the one readout on the panel that never moved -
    -- so building up to a Full House looked exactly like building up to a High Card.
    local _, posY = TopUI.center_text_juiced(handSelected, ix - sysDepth * textHeight, iy -2,
        iw -20, math.floor(ih/3), self.hand_juice)
    posY = posY + math.floor(G.FONTS.PIXEL.MEDIUM_HEIGHT/6)
    love.graphics.setFont(G.FONTS.PIXEL.SMALL)
    local handLevel = G:readout_hand_level()
    if(handSelected ~= "" and handLevel ~= nil and not handHidden) then
        -- Tinted by the rung it reached and popped on every change, as the reference does
        -- (`common_events.lua:553-563`). The level is the whole point of a Planet, so it cannot
        -- be the one number on this readout that never moves.
        love.graphics.setColor(TopUI.hand_level_colour(handLevel))
        TopUI.printf_juiced(self:cached_label("hand_level", handLevel, "lvl."),
            ix - sysDepth * textHeight, posY, iw, "right", self.level_juice)
        love.graphics.setColor(G.C.WHITE)
    elseif handSelected ~= "" then
        TextCache.printf("lvl.?", ix - sysDepth * textHeight, posY, iw, "right")
    end

    -- Chip
    local ChipX = ix
    local ChipY = iy + ih/3 + 6
    local ChipWidth = iw/2 - 8
    local ChipHeight = ih/2 + 2
    local totalW = iw

    -- The landed chips x mult product, once the hand resolves (see update_chip_total).
    --
    -- It used to be drawn where the X sits, between the two panels. That gap is `totalW - 2 *
    -- ChipWidth`, i.e. 16 px, and the product is a four-to-eight digit number - it ran straight
    -- through both panels. While it is up the reference has already zeroed chips and mult, so the
    -- operands carry nothing: collapse the pair into one panel and give the number the full width,
    -- which is also what the arithmetic means. `fit` is the backstop for a run with a huge product.
    local total_value = self.chip_total_value
    local showing_total = total_value and total_value > 0

    if not showing_total then
        love.graphics.setFont(G.FONTS.PIXEL.MEDIUM)
        love.graphics.setColor(G.C.RED)
        TopUI.center_text_static("X", ix - sysDepth * textHeight, iy + math.floor(ih/5), iw, ih)
    end

    -- Score flames rise from behind the chips/mult panels once the blind is beaten
    -- (drawn first so the panels occlude the flame roots). Accents follow the
    -- reference's lick formula against the panel colours.
    self._chip_accent = self._chip_accent or Fx.flame_accent(G.C.CHIPS, G.C.YELLOW)
    self._mult_accent = self._mult_accent or Fx.flame_accent(G.C.MULT, G.C.YELLOW)
    Fx.draw_flame(self.chip_flame, ChipX, ChipY + 3, ChipWidth, G.C.CHIPS, self._chip_accent)
    Fx.draw_flame(self.mult_flame, ChipX + totalW - ChipWidth, ChipY + 3, ChipWidth, G.C.MULT, self._mult_accent)

    if showing_total then
        -- Neutral rather than chips-blue or mult-red: the product belongs to neither operand, and
        -- a coloured panel spanning the row reads as one of them having grown.
        draw_rect_with_shadow(ChipX, ChipY, totalW, ChipHeight, 4, 2,
            G.C.BLOCK.BACK, G.C.BLOCK.SHADOW, 2, depthOffset)
        local total_text = NumberFormat.format(math.floor(total_value))
        love.graphics.setFont(Fonts.fit(G, G.FONTS.PIXEL.MEDIUM, total_text, totalW - 8))
        love.graphics.setColor(G.C.WHITE)
        TopUI.center_text_juiced(total_text, ChipX - sysDepth * textHeight, ChipY - 1,
            totalW, ChipHeight, self.total_juice)
    else
        -- While a level-up is pushing a value in, the reference covers that readout with a
        -- mostly-green plate carrying the delta rather than letting the number silently change
        -- (`common_events.lua:512-522`). That plate is the "+30" the player actually reads.
        local chips_covered = levelup and levelup.chips_cover > 0
        local mult_covered = levelup and levelup.mult_cover > 0
        local chip_face, chip_shadow = G.C.CHIPS, G.C.CHIPS_DARK
        local mult_face, mult_shadow = G.C.MULT, G.C.MULT_DARK
        if chips_covered then
            chip_face, chip_shadow = self:gain_cover_colours("chips", G.C.CHIPS)
        end
        if mult_covered then
            mult_face, mult_shadow = self:gain_cover_colours("mult", G.C.MULT)
        end
        draw_rect_with_shadow(ChipX, ChipY, ChipWidth, ChipHeight, 4, 2, chip_face, chip_shadow, 2, depthOffset)

        --Mult
        draw_rect_with_shadow(ChipX + totalW - ChipWidth, ChipY, ChipWidth, ChipHeight, 4, 2, mult_face, mult_shadow, 2, depthOffset)

        local rawChips, rawMult = G:readout_chips_mult()
        local handChips = chips_covered and levelup.chips_delta
            or (type(rawChips) == "number" and self:chips_readout(rawChips) or tostring(rawChips))
        local handMult = mult_covered and levelup.mult_delta
            or (type(rawMult) == "number" and self:mult_readout(rawMult) or tostring(rawMult))
        love.graphics.setColor(G.C.WHITE)
        -- Each panel fits its own text. Both counters carry thousands separators now, so a
        -- five-figure chip count is nine glyphs in a panel sized for five, and the operands
        -- would run into the X between them.
        -- No juice argument on chips: the reference does not pop that readout (see `update_counters`).
        love.graphics.setFont(Fonts.fit(G, G.FONTS.PIXEL.MEDIUM, handChips, ChipWidth - 4))
        TopUI.center_text_juiced(handChips, ChipX - sysDepth * textHeight, ChipY - 1, ChipWidth, ChipHeight, nil)
        love.graphics.setFont(Fonts.fit(G, G.FONTS.PIXEL.MEDIUM, handMult, ChipWidth - 4))
        TopUI.center_text_juiced(handMult, ChipX + totalW - ChipWidth - sysDepth * textHeight, ChipY - 1, ChipWidth, ChipHeight, self.mult_juice)
    end
    
    -- Hands, Discards, Money, Ante and Round
    local fieldsPositionX = titlePosX + (titleWidth + 4) * 2
    local fieldsPositionY = titlePosY
    local fieldWidth = 46
    local fieldHeight = 43
    local padding = 4
    local field_juice = self.field_juice or {}
    TopUI.LabeledField("Hands", G.hands, fieldsPositionX, fieldsPositionY, fieldWidth, fieldHeight, G.C.BLUE, field_juice.hands)
    TopUI.LabeledField("Discards", G.discards, fieldsPositionX + fieldWidth + padding, fieldsPositionY, fieldWidth, fieldHeight, G.C.RED, field_juice.discards)
    local ante_label = self:ante_readout()
    TopUI.LabeledField("Ante", ante_label, fieldsPositionX + (fieldWidth + padding) * 2, fieldsPositionY, fieldWidth, fieldHeight, G.C.ORANGE, field_juice.ante)
    TopUI.LabeledField("Round", G.round, fieldsPositionX + (fieldWidth + padding) * 2, fieldsPositionY + fieldHeight + padding, fieldWidth, fieldHeight, G.C.RED, field_juice.round)
    TopUI.LabeledField("", self:cached_label("money", G.money, "$"), fieldsPositionX, fieldsPositionY + fieldHeight + padding, fieldWidth * 2 + padding, fieldHeight, G.C.MONEY, field_juice.money)
    -- The base game surfaces the seed during play only on seeded runs
    -- (`UI_definitions.lua:2254`: `G.GAME.seeded and current_seed or nil`).
    if G.seeded == true then
        love.graphics.setFont(G.FONTS.PIXEL.MICRO or G.FONTS.PIXEL.SMALL)
        love.graphics.setColor(G.C.DARK_WHITE or G.C.GREY)
        love.graphics.printf(self:cached_label("seed", G.SEED or "", "Seed "), 250 - sysDepth * textHeight, 96, 146, "center")
    end

    -- Joker panel (left 2/3 of top screen).
    local dims = G.get_top_inventory_dims and G:get_top_inventory_dims() or { joker_panel_w = 266, consumable_panel_w = 132, consumable_panel_x = 268, panel_gap = 2 }
    local n = G and G.jokers and #G.jokers or 0
    local slot_w, slot_h = G.joker_slot_w or 71, G.joker_slot_h or 95
    local slot_gap = G.joker_slot_gap or 8
    local slot_y = G.joker_slot_y_top or (panelY + panelHeight + 6)
    local total_w = tonumber(G.joker_row_span_top)
        or select(2, G:_compute_fanned_joker_row(n, dims.joker_panel_w, slot_w, slot_gap, 4))
    local start_x = G.joker_slot_start_x or 4

    -- Extra padding so jokers don't touch the panel edges.
    local panel_pad = 3
    local joker_panel_w = dims.joker_panel_w
    local joker_panel_x = 0
    total_w = math.min(total_w + (panel_pad * 2), joker_panel_w)
    start_x = math.max(joker_panel_x + panel_pad, start_x - panel_pad)
    slot_y = slot_y - panel_pad
    slot_h = slot_h + (panel_pad * 2)

    -- Dark panel background, drawn whether or not the area holds anything. The reference's
    -- CardArea builds its `area_uibox` unconditionally for joker-type areas -- both the joker
    -- row and the consumable row are `type = 'joker'` (`game.lua:2235-2245`) and neither is in
    -- `invisible_area_types` -- so the tray is on screen from the first blind, showing where a
    -- joker would land before you own one (`cardarea.lua:280-290`). This port only drew it once
    -- there was something in it, so an empty run started with nothing marking the slots at all.
    self:draw_inventory_tray(joker_panel_x, slot_y, joker_panel_w, slot_h,
        (G.jokers and #G.jokers or 0) > 0, depthOffset)

    -- Used/limit under each card area, as the reference renders beneath every CardArea
    -- (`cardarea.lua:283-289`, jokers left-aligned and consumables right-aligned). Without
    -- it there is nothing on screen telling the player how many slots they have — which is
    -- exactly the number you need before buying.
    local counter_y = slot_y + slot_h + 1
    love.graphics.setFont(G.FONTS.PIXEL.MICRO or G.FONTS.PIXEL.SMALL)
    love.graphics.setColor(G.C.DARK_WHITE or G.C.GREY)
    local joker_cap = math.max(0, math.floor(tonumber(G.joker_capacity) or 5))
    love.graphics.printf(self:cached_ratio_label("joker_slots", n, joker_cap),
        joker_panel_x + 4 - sysDepth * textHeight, counter_y, joker_panel_w - 8, "left")

    -- Consumable panel (right 1/3 of top screen).
    local cn = G and G.consumables and #G.consumables or 0
    local consumable_cap = math.max(0, math.floor(
        (G.get_effective_consumable_capacity and G:get_effective_consumable_capacity()) or 2))
    if G.consumables_on_bottom ~= true then
        love.graphics.printf(self:cached_ratio_label("consumable_slots", cn, consumable_cap),
            dims.consumable_panel_x + 4 - sysDepth * textHeight, counter_y,
            dims.consumable_panel_w - 8, "right")
    end
    if G.consumables_on_bottom ~= true then
        if cn > 0 and G.draw_consumables_row then G:draw_consumables_row() end
        local cslot_h = G.consumable_slot_h or 95
        local cslot_y = G.joker_slot_y_top or slot_y + panel_pad
        local c_panel_pad = 3
        cslot_y = cslot_y - c_panel_pad
        cslot_h = cslot_h + (c_panel_pad * 2)
        self:draw_inventory_tray(dims.consumable_panel_x, cslot_y,
            dims.consumable_panel_w, cslot_h, cn > 0, depthOffset)
    end

    -- Held tags are sprite-only, deliberately. The base game lets you hover a held tag for
    -- its description (`UI_definitions.lua:1252-1275`), but tags live on the top screen and
    -- the 3DS only digitises the bottom one, so there is no hover and no tap to give them.
    -- Moving them down would cost playfield height for something you read once; this is an
    -- accepted platform sacrifice, not an oversight. The description is still shown where
    -- the choice is actually made, at blind select (`Game:_draw_skip_tag_tooltip`).
    for _, t in ipairs(G.tags) do
        if t and t.draw then
            local scale = 0.75
            love.graphics.push()
            love.graphics.translate(t.X, t.Y)
            love.graphics.scale(scale, scale)
            -- Draw the stored tag rather than building a throwaway one. `G.tags` already holds
            -- Tag objects (`Game:addTag`), and constructing another every frame ran the
            -- 24-branch init, re-resolved the atlas and allocated a fresh GPU quad per tag per
            -- frame. Coordinates are zeroed around the draw because the translate above already
            -- places it, and t.X/t.Y are the layout's, not this transform's.
            local tx, ty = t.X, t.Y
            t.X, t.Y = 0, 0
            t:draw()
            t.X, t.Y = tx, ty
            love.graphics.pop()
        end
    end

    -- Owned inventory on top screen (same layer as jokers; above tags / bottom-screen content).
    local draw_jokers_top = G and G.jokers_on_bottom ~= true and n > 0
    local draw_cons_top = G and G.consumables_on_bottom ~= true and cn > 0 and G.consumable_nodes
    if draw_jokers_top or draw_cons_top then
        love.graphics.setFont(G.FONTS.PIXEL.MEDIUM)
        love.graphics.setColor(G.C.WHITE)

        if draw_jokers_top then
            love.graphics.push()
            love.graphics.translate(-jokerDepthOffset, 0)
            for _, joker in ipairs(G.jokers) do
                if joker and joker.draw then
                    local prev_visible = joker.states and joker.states.visible
                    if joker.states then joker.states.visible = true end
                    joker:draw()
                    if joker.states then joker.states.visible = prev_visible end
                end
            end
            love.graphics.pop()
        end

        if draw_cons_top then
            love.graphics.push()
            love.graphics.translate(-jokerDepthOffset, 0)
            for _, cons in ipairs(G.consumable_nodes) do
                if cons and cons.draw then
                    local prev_visible = cons.states and cons.states.visible
                    if cons.states then cons.states.visible = true end
                    cons:draw()
                    if cons.states then cons.states.visible = prev_visible end
                end
            end
            love.graphics.pop()
        end
    end

    -- Nodes that have left their owner row but are still on screen: a consumable flying out
    -- after being used, a joker coming apart. They are no longer in `G.jokers` /
    -- `G.consumable_nodes`, and `Game:draw` skips them on the bottom screen, so this is the only
    -- place they get drawn. Without it a tarot used from the readout simply blinked out.
    TopUI.draw_offscreen_row_ghosts(jokerDepthOffset)

    if self.popups then
        for _, popup in ipairs(self.popups) do
            if popup and popup.draw then
                popup:draw(popupDepthOffset)
            end
        end
    end

end

--- Draw the nodes tagged `_draw_screen == "top"`: cards that have been unlinked from the joker
--- or consumable row but are still animating out on the readout.
---@param depth_offset number stereoscopic shift, matching the row they came from
function TopUI.draw_offscreen_row_ghosts(depth_offset)
    if not G then return end
    local flight = G._consumable_flight and G._consumable_flight.node
    local dissolving = G._dissolving_nodes
    local any = (flight and flight._draw_screen == "top") and true or false
    if not any and dissolving then
        for _, node in ipairs(dissolving) do
            if node._draw_screen == "top" then any = true break end
        end
    end
    if not any then return end

    love.graphics.push()
    love.graphics.translate(-depth_offset, 0)
    love.graphics.setColor(G.C.WHITE)
    local function draw_ghost(node)
        if not node or node._draw_screen ~= "top" or not node.draw then return end
        local prev_visible = node.states and node.states.visible
        if node.states then node.states.visible = true end
        node:draw()
        if node.states then node.states.visible = prev_visible end
    end
    draw_ghost(flight)
    for _, node in ipairs(dissolving or {}) do
        -- The flight node joins this list once it has dissolved; don't draw it twice.
        if node ~= flight then draw_ghost(node) end
    end
    love.graphics.pop()
end

--- @param juice number|nil pop scale for the value, from `TopUI:update_fields`
function TopUI.LabeledField(string, value, x, y, iw, ih, fieldColor, juice)
    love.graphics.setColor(G.C.BLOCK.SHADOW)
    local ix, iy, iw, ih = draw_rounded_rect(x, y, iw, ih, 4, 4,"fill")
    
    if(string ~= "") then
        love.graphics.setColor(G.C.WHITE)
        love.graphics.setFont(G.FONTS.PIXEL.SMALL)
        TopUI.center_text_static(string, ix, iy, iw, math.floor(ih/4))
    end

    love.graphics.setColor(G.C.PANEL)
    if(string ~= "") then
        ix, iy, iw, ih = draw_rounded_rect(ix, iy + ih/4 + 4, iw, math.floor(ih/4 * 3) - 4, 4, 4,"fill")
    else
        ix, iy, iw, ih = draw_rounded_rect(ix, iy, iw, ih, 4, 4,"fill")
    end

    love.graphics.setFont(G.FONTS.PIXEL.MEDIUM)
    love.graphics.setColor(fieldColor)
    TopUI.center_text_juiced(value, ix - sysDepth * textHeight, iy - 1, iw, ih, juice)

end

--- `center_text` for a label whose string never changes. Same geometry, but the text is
--- shaped once and cached instead of re-shaped every frame -- 16.11 us against 53.49 us on
--- hardware for a short string. Only for literals and values that hold still; a counter
--- belongs in `center_text`.
function TopUI.center_text_static(string, x, y, iw, ih)
    local s = tostring(string or "")
    local font = love.graphics.getFont()
    local yval = y + math.floor(ih / 2) - math.floor(font:getHeight() / 2)
    TextCache.printf(s, x, yval, iw, "center")
    return x, yval
end

function TopUI.center_text(string, x, y, iw, ih)
    local s = tostring(string or "")
    local font = love.graphics.getFont()
    local yval = y + math.floor(ih/2) - math.floor(font:getHeight()/2)
    love.graphics.printf(s, x, yval, iw, "center")
    local xval = x
    return xval, yval
end

--- Colour for a hand level, capped at the top rung of the ladder. A non-numeric level is one of
--- the reference's placeholders (`+1` under Black Hole), which it draws at rung one
--- (`common_events.lua:557-561`).
--- @param level integer|string
--- @return table
function TopUI.hand_level_colour(level)
    local levels = G.C.HAND_LEVELS
    if type(level) ~= "number" then return levels[1] end
    local n = math.floor(level)
    if n < 1 then return levels[1] end
    if n > #levels then return levels[#levels] end
    return levels[n]
end

--- `love.graphics.printf` with a scale pop anchored to the edge the text is aligned to, so a
--- right-aligned label grows leftwards instead of sliding. `scale` nil means idle.
--- @param scale number|nil Pop scale from the baked curve
function TopUI.printf_juiced(text, x, y, w, align, scale)
    if not scale then
        love.graphics.printf(text, x, y, w, align)
        return
    end
    local anchor_x = (align == "right" and x + w) or (align == "center" and x + w * 0.5) or x
    local anchor_y = y + love.graphics.getFont():getHeight() * 0.5
    love.graphics.push()
    love.graphics.translate(anchor_x, anchor_y)
    love.graphics.scale(scale, scale)
    love.graphics.translate(-anchor_x, -anchor_y)
    love.graphics.printf(text, x, y, w, align)
    love.graphics.pop()
end

--- `center_text` with a scale pop about the centre of its box. `scale` nil means idle, which is
--- every frame except the quarter second after a counter changes, and costs one nil test.
--- @param scale number|nil Pop scale from the baked curve
function TopUI.center_text_juiced(string, x, y, iw, ih, scale)
    if not scale then
        return TopUI.center_text(string, x, y, iw, ih)
    end

    -- The counters sit in 48 px boxes with the X between them, so a wide number must not be
    -- allowed to grow past its box. A number that already fills the box only dips.
    local w = love.graphics.getFont():getWidth(tostring(string or ""))
    if w > 0 then
        local cap = iw / w
        if cap < 1 then cap = 1 end
        if scale > cap then scale = cap end
    end

    local cx = x + iw * 0.5
    local cy = y + ih * 0.5
    love.graphics.push()
    love.graphics.translate(cx, cy)
    love.graphics.scale(scale, scale)
    love.graphics.translate(-cx, -cy)
    local xval, yval = TopUI.center_text(string, x, y, iw, ih)
    love.graphics.pop()
    return xval, yval
end

function TopUI:init()
    self.popups = {}
    self.blind_name_text = DynaText.new({
        float_amount = 1,
        rotation_amount = 0.025,
        bump_amount = 0.10,
        -- A new blind's name spells itself out with the paper1 chirp (`text.lua:156-208`).
        pop_on_change = true,
    })
    self.boss_indicator_text = DynaText.new({
        float_amount = 1,
        rotation_amount = 0.035,
    })
    -- Score flames over the chips/mult panels; seeds offset the flicker so the
    -- two never move in lockstep (the reference varies them by object ID).
    self.chip_flame = Fx.new_flame(0)
    self.mult_flame = Fx.new_flame(4.7)
end

--- Advance both score flames. The target tracks the chips x mult readout the panels
--- actually display — not the round score — so the fire lights while a scoring hand
--- beats the blind and dies when the readout resets to 0 x 0, exactly like the
--- reference, whose earned_score comes from the live hand text
--- (`reference/Balatro/functions/button_callbacks.lua:2022-2026`). Zero inside a
--- booster pack, where the panels show a consumable pick instead of a score.
--- @param dt number
function TopUI:update_flames(dt)
    local target = 0
    if G and G.STATE ~= (G.STATES and G.STATES.OPEN_BOOSTER) then
        local chips = tonumber(G.selectedHandChips) or 0
        local mult = tonumber(G.selectedHandMult) or 0
        target = Fx.flame_target(chips * mult, G.current_blind_target)
    end
    Fx.update_flame(self.chip_flame, target, dt)
    Fx.update_flame(self.mult_flame, target, dt)

    -- Ambient bed levels ride the same flame state (`misc_functions.lua:745-747`):
    -- fire from the chip flame's intensity, organ from how far the hand overshoots
    -- the blind (log base 5, capped at 0.4). Sfx ignores this on consoles that can't
    -- afford the extra decodes.
    if Sfx and Sfx.ambient_set_levels then
        local fire = math.min(1, ((self.chip_flame.real or 0) + (self.chip_flame.change or 0)) / 10)
        local organ = 0
        local required = tonumber(G and G.current_blind_target) or 0
        if required > 0 then
            local chips = tonumber(G and G.selectedHandChips) or 0
            local mult = tonumber(G and G.selectedHandMult) or 0
            local earned = chips * mult
            if earned > 0 then
                organ = math.max(0, math.min(0.4, 0.1 * math.log(earned / (required + 1)) / math.log(5)))
            end
        end
        Sfx.ambient_set_levels(fire, organ)
    end
end

--- Ease the round score toward `G.round_score`. See the SCORE_EASE_ constants above.
--- @param dt number
function TopUI:update_score(dt)
    local target = math.floor(tonumber(G and G.round_score) or 0)
    if target < 0 then target = 0 end

    if target ~= self.score_target then
        self.score_target = target
        local from = self.score_value
        if from == nil or target <= from then
            -- First frame, or the score was reset for a new round: nothing to count up to.
            self.score_value = target
            self.score_time = nil
        else
            local log_from = math.log(from + 1)
            self.score_log_from = log_from
            self.score_log_span = math.log(target + 1) - log_from
            self.score_duration = SCORE_EASE_DURATION
            self.score_time = 0
        end
    end

    local t = self.score_time
    if t then
        t = t + dt
        if t >= self.score_duration then
            self.score_time = nil
            self.score_value = target
        else
            self.score_time = t
            local u = t / self.score_duration
            u = u * (2 - u) -- ease out: leaves at full speed, settles into the target
            local v = math.floor(math.exp(self.score_log_from + self.score_log_span * u) - 1)
            -- Belt and braces against float drift at either end of the curve.
            if v > target then v = target end
            if v > self.score_value then self.score_value = v end
        end
    end

    if self.score_value ~= self.score_shown or not self.score_text then
        self.score_shown = self.score_value
        self.score_text = NumberFormat.format(self.score_value)
    end
end

--- The chips x mult total shown between the two panels while the hand's product lands.
--- The reference zeroes chips and mult, pulses `chip_total` with the button thunk, then
--- eases it down to 0 over 0.5 s while the round score eases up — the product visibly
--- drains into the score (`reference/Balatro/functions/state_events.lua:1029-1062`).
--- @param dt number
function TopUI:update_chip_total(dt)
    local total = G and tonumber(G.chip_total_display)
    if not total then
        self.chip_total_value = nil
        self.chip_total_seen = nil
        return
    end
    if self.chip_total_seen ~= total then
        self.chip_total_seen = total
        self.chip_total_value = total
        self.total_juice_state = begin_juice(self.total_juice_state)
    end
    if G.chip_total_drain and self.chip_total_value then
        -- Linear drain over the reference's 0.5 s, synchronized with the score count-up
        -- that starts on the same frame (`update_score` sees the new round_score).
        self.chip_total_value = self.chip_total_value - total * (dt / 0.5)
        if self.chip_total_value <= 0 then
            self.chip_total_value = nil
            self.chip_total_seen = nil
            G.chip_total_display = nil
            G.chip_total_drain = nil
        end
    end
    self.total_juice = step_juice(self.total_juice_state, dt)
end

--- Kick a pop whenever the chips or mult readout changes value. The change is detected here by
--- comparing against the value this UI last saw, so nothing outside has to announce it.
--- @param dt number
function TopUI:update_counters(dt)
    local chips, mult = 0, 0
    if G and G.readout_chips_mult then
        -- The same source `draw` reads, so a level-up ladder pops the counters the way a
        -- selection change does.
        chips, mult = G:readout_chips_mult()
    end

    -- Only mult pops. The reference's `update_hand_text` juices the mult readout
    -- (`common_events.lua:545`) but pushes chips through a plain `update(0)`
    -- (`common_events.lua:517`), so during a scoring ladder the mult is the counter that
    -- moves and the chips simply climb. Popping both made the chips look like they were
    -- breathing on every card.
    -- Restart before stepping, so the frame the value changes already shows the curve's first step.
    if self.mult_seen ~= nil and mult ~= self.mult_seen then
        self.mult_juice_state = begin_juice(self.mult_juice_state)
    end
    self.chips_seen, self.mult_seen = chips, mult

    -- The hand name pops whenever the detected hand changes, so selecting a card that turns a
    -- Pair into Two Pair reads on the panel rather than only in the numbers under it. Keyed on
    -- the name rather than on `G.selectedHand`, so the level-up flourish taking the readout
    -- over counts as a change and re-selecting the same hand type does not.
    -- `false` for "nothing shown", so the first hand to appear still registers as a change.
    local hand_name = false
    if G then
        local levelup = G._hand_levelup
        if levelup then
            hand_name = levelup.hand or false
        elseif G.selectedHand and G.selectedHand ~= -1 and G.handlist then
            hand_name = G.handlist[G.selectedHand] or false
        end
    end
    if self.hand_seen ~= nil and hand_name ~= self.hand_seen and hand_name ~= false then
        self.hand_juice_state = begin_juice(self.hand_juice_state)
    end
    self.hand_seen = hand_name

    -- The level readout pops on every change too (`common_events.lua:562`), which is the beat a
    -- Planet is bought for.
    -- `false` rather than nil for a blank slot, so the first level to appear still counts as a
    -- change against the "nothing seen yet" state.
    local level = false
    if G and G.readout_hand_level then level = G:readout_hand_level() or false end
    if self.level_seen ~= nil and level ~= self.level_seen then
        self.level_juice_state = begin_juice(self.level_juice_state)
    end
    self.level_seen = level

    -- Real time, not the game-speed-scaled `dt`: the pop is an animation, and the original
    -- runs `move_juice` off `TIMERS.REAL`.
    local juice_dt = (G and G.real_dt) or dt
    self.mult_juice = step_juice(self.mult_juice_state, juice_dt)
    self.level_juice = step_juice(self.level_juice_state, juice_dt)
    self.hand_juice = step_juice(self.hand_juice_state, juice_dt)
end

--- HUD fields the reference gives their own bump: dollars (`UI_definitions.lua:1310`), hands
--- and discards (`1290`, `1300`). The port drew all five through plain text, which read oddly
--- next to a score that pops — gaining money, the shop loop's whole reward signal, was a
--- silent number swap.
---
--- Ante and Round are here too. The reference eases them through `ease_ante` / `ease_round`
--- (`common_events.lua:200-250`), which pop the counter and play a cue; anteing up is the
--- run's main progress beat and it was the quietest thing on the screen.
local JUICED_FIELDS = { "money", "hands", "discards", "ante", "round" }

--- @param dt number
function TopUI:update_fields(dt)
    self.field_seen = self.field_seen or {}
    self.field_juice_states = self.field_juice_states or {}
    self.field_juice = self.field_juice or {}

    local juice_dt = (G and G.real_dt) or dt
    for _, key in ipairs(JUICED_FIELDS) do
        local value = G and G[key]
        if self.field_seen[key] ~= nil and value ~= self.field_seen[key] then
            self.field_juice_states[key] = begin_juice(self.field_juice_states[key])
            -- Reference `ease_ante` pairs the pop with this cue (`common_events.lua:217-218`).
            -- Round advances pop silently: the reference's `ease_round` cue rings at blind
            -- select, but this port's round counter moves on shop exit, where the base game
            -- plays nothing — so the pop stays and the cue does not. Money, hands and
            -- discards stay silent too and keep the cues their own actions already play.
            if key == "ante" and tonumber(value) and tonumber(self.field_seen[key])
                and tonumber(value) > tonumber(self.field_seen[key]) then
                Sfx.play("highlight2", 0.685, 0.2)
                Sfx.play("generic1")
            end
        end
        self.field_seen[key] = value
        self.field_juice[key] = step_juice(self.field_juice_states[key], juice_dt)
    end
end

function TopUI:update(dt)
    self:update_score(dt)
    self:update_chip_total(dt)
    self:update_counters(dt)
    self:update_fields(dt)
    -- `update_canvas_juice(dt)` runs before SPEEDFACTOR is applied in reference `game.lua:2459`.
    self:update_flames((G and G.real_dt) or dt)

    local popups = self.popups
    if popups then
        for i = 1, #popups do
            local popup = popups[i]
            if popup.update then popup:update(dt) end
        end
        -- Remove in reverse order so indices stay valid.
        for i = #popups, 1, -1 do
            local popup = popups[i]
            if popup.update and (popup.remove or popup.time <= 0) then
                table.remove(popups, i)
            end
        end
    end
end

--- Text on the score readout. `update` keeps this in sync with the eased value; the fallback
--- only runs if something draws before the first update.
--- @return string
function TopUI:score_readout()
    local text = self.score_text
    if text then return text end
    return NumberFormat.format(math.floor(tonumber(G and G.round_score) or 0))
end

--- Cached counter strings, rebuilt only when the value changes, so the common frame formats
--- nothing. Kept separate from the `_seen` values `update_counters` compares, so a rebuild here
--- can never swallow a pop.
--- @return string
function TopUI:chips_readout(v)
    if v ~= self.chips_value or not self.chips_str then
        self.chips_value = v
        self.chips_str = NumberFormat.format(v)
    end
    return self.chips_str
end

--- @return string
function TopUI:mult_readout(v)
    if v ~= self.mult_value or not self.mult_str then
        self.mult_value = v
        -- Both counters go through the same formatter, as the reference's `update_hand_text`
        -- does (`button_callbacks.lua:1918-1928`). This used to break to `%.1e` at 100000 to
        -- keep the panel from overflowing; the panels now fit their text instead, so mult can
        -- hold the grouped form as long as chips does and both switch to an exponent together.
        self.mult_str = NumberFormat.format(v)
    end
    return self.mult_str
end

function TopUI:addPopup(node)
    if Popup and node and node.is and node:is(Popup) then
        table.insert(self.popups, node)
    end
end
