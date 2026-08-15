--- Bottom-screen shop panel, offer overlays, and shop-related touch targets.

local Fonts = require("fonts")
local DynaText = require("dyna_text")

local ShopUI = {}

local SETTLE_EPSILON = 0.6

--- Resolve and cache one atlas cell. On 3DS `getDimensions()` reports the
--- power-of-two T3X dimensions, so column counts must come from declared source
--- geometry. Keeping the Quad on the atlas also avoids allocating GPU objects in
--- the shop draw loop.
function ShopUI.cached_atlas_quad(atlas, index, cache_name)
    if not atlas or not atlas.image or index == nil then return nil end
    local px = tonumber(atlas.px)
    local py = tonumber(atlas.py)
    local cols = tonumber(atlas.cols)
    if not px or not py or not cols or px <= 0 or py <= 0 or cols <= 0 then return nil end

    index = math.max(0, math.floor(tonumber(index) or 0))
    local cache_key = cache_name or "_shop_quads"
    local cache = atlas[cache_key]
    if not cache then
        cache = {}
        atlas[cache_key] = cache
    end
    local quad = cache[index]
    if quad then return quad end

    local iw, ih = atlas.image:getDimensions()
    local qx = (index % cols) * px
    local qy = math.floor(index / cols) * py
    if qx + px > iw + 0.5 or qy + py > ih + 0.5 then return nil end
    quad = love.graphics.newQuad(qx, qy, px, py, iw, ih)
    cache[index] = quad
    return quad
end

local function list_has_layout_motion(list)
    for _, node in ipairs(list or {}) do
        if node and node._shop_settling then return true end
    end
    return false
end

--- Stable shop shelves do not need to rebuild target transforms and collision
--- rectangles every frame. Slides, pop-ins and dragged nodes still refresh live.
function ShopUI.shop_layout_needs_refresh(game)
    return game._shop_layout_dirty == true
        or game._shop_slide ~= nil
        or game:shop_pop_in_active()
        or game.dragging ~= nil
        or list_has_layout_motion(game.shop_offer_nodes)
        or list_has_layout_motion(game.shop_booster_nodes)
        or list_has_layout_motion(game.shop_voucher_nodes)
end

--- Shop slots normally pin the visible transform straight onto the target so a
--- restocked shop appears in place instead of flying in. A node that was just
--- dropped is the exception: let Moveable lerp it home so it leans into the
--- return the way hand cards and jokers do, and pin it again once it arrives.
local function should_pin_visual(game, node)
    if game.dragging == node then return false end
    if not node._shop_settling then return true end

    local dx = math.abs((node.VT.x or 0) - (node.T.x or 0))
    local dy = math.abs((node.VT.y or 0) - (node.T.y or 0))
    if dx < SETTLE_EPSILON and dy < SETTLE_EPSILON then
        node._shop_settling = nil
        return true
    end
    return false
end

--- Override the pinned visual scale/rotation while a node is mid pop-in.
--- Runs after the pin so the pop wins the frame; once the pop settles the
--- transform returns nil and the pin takes back over.
---
--- Jokers and cards scale about their centre, but ShopBoosterNode and
--- ShopVoucherNode size themselves off a top-left origin (`pop_anchor_topleft`),
--- so those need VT.x/y nudged in by half the shrink or the pop would grow out
--- of the slot corner instead of in place.
local function apply_pop_in(game, node, x, y, scale)
    local pop_scale, pop_rot = game:shop_pop_in_transform(node)
    if not pop_scale then return end
    node.VT.scale = scale * pop_scale
    node.VT.r = pop_rot
    if node.pop_anchor_topleft then
        local shrink = scale * (1 - pop_scale)
        node.VT.x = x + (node.T.w or 72) * shrink * 0.5
        node.VT.y = y + (node.T.h or 95) * shrink * 0.5
    end
end

function ShopUI.layout_shop_offer_nodes(game, param)
    local nodes = game.shop_offer_nodes or {}
    local offers = game.shop_offers or {}
    local n = math.min(#nodes, #offers)
    game._shop_offer_rects = {}
    if n <= 0 then return end

    local padding = 4
    local area_x = param.x + padding
    local area_y = param.y + padding
    local area_w = param.w - 2 * padding
    local area_h = param.h - 2 * padding

    local card_w = game.joker_slot_w or 71
    local card_h = game.joker_slot_h or 95
    local scale = math.min(1, math.max(0.55, (area_h - 4) / card_h))
    local eff_w = card_w * scale
    local eff_h = card_h * scale
    local gap_w = (game.joker_slot_gap or 8) * scale
    local step, _, start_x = game:_compute_fanned_joker_row(n, area_w, eff_w, gap_w, 2)
    local y = area_y + math.floor((area_h - eff_h) * 0.5 - 4)

    local visible = game:shop_nodes_visible()
    local interactive = game:shop_nodes_interactive()
    for i = 1, n do
        local node = nodes[i]
        if node and node.T and node.VT then
            local x = area_x + start_x + ((i - 1) * step)
            node.T.x = x
            node.T.y = y
            node.T.scale = scale
            if should_pin_visual(game, node) then
                node.VT.x = x
                node.VT.y = y
                node.VT.scale = scale
            end
            apply_pop_in(game, node, x, y, scale)
            node.states.visible = visible
            node.states.click.can = interactive
            node.states.drag.can = interactive
            node.shop_offer_slot = i
            game._shop_offer_rects[i] = node:get_collision_rect()
        end
    end
end

function ShopUI.layout_shop_booster_nodes(game, param)
    local nodes = game.shop_booster_nodes or {}
    local offers = game.shop_booster_offers or {}
    local n = math.min(#nodes, #offers)
    game._shop_booster_rects = {}
    if n <= 0 or type(param) ~= "table" then return end

    local padding = 4
    local area_x = param.x + padding
    local area_y = param.y + padding
    local area_w = param.w - 2 * padding
    local area_h = param.h - 2 * padding

    local pack_w, pack_h = 72, 95
    local scale = math.min(1, math.max(0.55, (area_h - 4) / pack_h))
    local eff_w = pack_w * scale
    local eff_h = pack_h * scale
    local step, _, start_x = game:_compute_fanned_joker_row(n, area_w, eff_w, 4 * scale, 2)
    local y = area_y + math.floor((area_h - eff_h) * 0.5 + 0.5)
    local visible = game:shop_nodes_visible()
    local interactive = game:shop_nodes_interactive()

    for i = 1, n do
        local node = nodes[i]
        if node and node.T and node.VT then
            local x = area_x + start_x + ((i - 1) * step)
            node.T.w = pack_w
            node.T.h = pack_h
            node.T.x = x
            node.T.y = y
            node.T.scale = scale
            if should_pin_visual(game, node) then
                node.VT.x = x
                node.VT.y = y
                node.VT.scale = scale
            end
            apply_pop_in(game, node, x, y, scale)
            node.states.visible = visible
            node.states.click.can = interactive
            node.states.drag.can = interactive
            node.shop_booster_slot = i
            game._shop_booster_rects[i] = node:get_collision_rect()
        end
    end
end

function ShopUI.layout_shop_voucher_nodes(game, param)
    local nodes = game.shop_voucher_nodes or {}
    local offers = game.shop_voucher_offers or {}
    local n = math.min(#nodes, #offers)
    game._shop_voucher_rects = {}
    if n <= 0 or type(param) ~= "table" then return end

    local padding = 4
    local area_x = param.x + padding
    local area_y = param.y + padding
    local area_w = param.w - 2 * padding
    local area_h = param.h - 2 * padding

    local pack_w, pack_h = 72, 95
    local scale = math.min(1, math.max(0.55, (area_h - 4) / pack_h))
    local eff_w = pack_w * scale
    local eff_h = pack_h * scale
    local step, _, start_x = game:_compute_fanned_joker_row(n, area_w, eff_w, 4 * scale, 2)
    local y = area_y + math.floor((area_h - eff_h) * 0.5 + 0.5)
    local visible = game:shop_nodes_visible()
    local interactive = game:shop_nodes_interactive()

    for i = 1, n do
        local node = nodes[i]
        if node and node.T and node.VT then
            local x = area_x + start_x + ((i - 1) * step)
            node.T.w = pack_w
            node.T.h = pack_h
            node.T.x = x
            node.T.y = y
            node.T.scale = scale
            if should_pin_visual(game, node) then
                node.VT.x = x
                node.VT.y = y
                node.VT.scale = scale
            end
            apply_pop_in(game, node, x, y, scale)
            node.states.visible = visible
            node.states.click.can = interactive
            node.states.drag.can = interactive
            node.shop_voucher_slot = i
            game._shop_voucher_rects[i] = {
                x = x, y = y, w = eff_w, h = eff_h,
            }
        end
    end
end

--- Price tags bump when their number changes.
---
--- The reference builds every price as `DynaText({..., bump = true})`
--- (`UI_definitions.lua:813`), so a voucher discount or a Chaos reroll visibly knocks the
--- price. The port drew all three price rows as plain text, on the one screen the player sits
--- and reads. State is keyed by slot and cached for the session: there are at most a handful
--- of tags, and a fresh state each frame would never survive long enough to animate.
local price_tag_dyna = {}

local function price_tag_state(key)
    local state = price_tag_dyna[key]
    if not state then
        state = DynaText.new({ bump_amount = 0.25 })
        price_tag_dyna[key] = state
    end
    return state
end

--- One price tag, centred above `rect`.
---
--- In the reference the price is a child UIBox of the card itself (`UI_definitions.lua:813`),
--- so it is drawn with the card and inherits its place in the draw order. The port draws the
--- three tag rows in one pass after every shop node, which is fine until a card is lifted:
--- a dragged card was drawn in the node pass and so ended up underneath every tag on screen,
--- including tags belonging to other slots. `ShopUI.draw_shop_price_tags` therefore skips the
--- dragged slot and `Game:draw` redraws it, and only it, after the dragged card.
local function draw_price_tag(game, key, rect, price)
    local label = "$" .. tostring(price or 0)
    local font = game.FONTS.PIXEL.PRICE
    local tag_w = math.floor(font:getWidth(label) + 12)
    local tag_h = math.floor(font:getHeight() + 4)
    local tx = math.floor(rect.x + math.floor((rect.w - tag_w) * 0.5 + 0.5))
    local ty = math.floor(rect.y - tag_h - 2)
    if _G.draw_rect_with_shadow then
        draw_rect_with_shadow(tx, ty, tag_w, tag_h, 3, 2, game.C.BLOCK.BACK, game.C.BLOCK.SHADOW, 1)
    else
        love.graphics.setColor(game.C.BLOCK.BACK)
        love.graphics.rectangle("fill", tx, ty, tag_w, tag_h, 3, 3)
    end
    love.graphics.setFont(font)
    love.graphics.setColor(game.C.MONEY)
    DynaText.draw(price_tag_state(key), label, tx, ty + 2, tag_w, "center")
end

--- Where a slot's tag hangs. Prefers the node's live collision rect so the tag tracks a card
--- that is being dragged, and falls back to the laid-out rect for a slot with no node.
local function slot_tag_rect(node, fallback)
    if node and node.get_collision_rect then
        local r = node:get_collision_rect()
        if r then return r end
    end
    return fallback
end

--- The three shop rows, keyed by the offer list, its nodes, and the laid-out rects.
local TAG_ROWS = {
    { key = "offer",   offers = "shop_offers",         nodes = "shop_offer_nodes",   rects = "_shop_offer_rects" },
    { key = "pack",    offers = "shop_booster_offers", nodes = "shop_booster_nodes", rects = "_shop_booster_rects" },
    { key = "voucher", offers = "shop_voucher_offers", nodes = "shop_voucher_nodes", rects = "_shop_voucher_rects" },
}

--- Draw every shop price tag except the one belonging to `skip_node`.
function ShopUI.draw_shop_price_tags(game, skip_node)
    if not game:shop_nodes_interactive() then return end
    for _, row in ipairs(TAG_ROWS) do
        local nodes = game[row.nodes]
        local rects = game[row.rects]
        for i, offer in ipairs(game[row.offers] or {}) do
            local node = nodes and nodes[i]
            if offer and node ~= skip_node then
                local rect = slot_tag_rect(node, rects and rects[i])
                if rect then
                    draw_price_tag(game, row.key .. ":" .. i, rect, offer.price)
                end
            end
        end
    end
end

--- Draw only the tag belonging to `node`, for redrawing it above the card it is attached to.
function ShopUI.draw_price_tag_for_node(game, node)
    if not node or not game:shop_nodes_interactive() then return false end
    for _, row in ipairs(TAG_ROWS) do
        local nodes = game[row.nodes]
        if nodes then
            for i, candidate in ipairs(nodes) do
                if candidate == node then
                    local offer = (game[row.offers] or {})[i]
                    local rect = slot_tag_rect(node, (game[row.rects] or {})[i])
                    if offer and rect then
                        draw_price_tag(game, row.key .. ":" .. i, rect, offer.price)
                        return true
                    end
                    return false
                end
            end
        end
    end
    return false
end

--- Top-screen shop sign (`animation_atli.shop_sign`).
function ShopUI.draw_shop_sign_anim(game, center_x, center_y, scale)
    -- Lazy sheet: the first shop frame pays the load, every later one is a lookup.
    local atlas = game.ensure_animation_atlas_loaded
        and game:ensure_animation_atlas_loaded("shop_sign")
    if not atlas or not atlas.image then return end
    local cell_w = tonumber(atlas.px) or 113
    local cell_h = tonumber(atlas.py) or 60
    local frame_count = tonumber(atlas.frames) or 4
    local anim_fps = 8
    local t = love.timer.getTime()
    local frame = math.floor(t * anim_fps) % math.max(1, frame_count)
    local quad = ShopUI.cached_atlas_quad(atlas, frame, "_shop_sign_quads")
    if not quad then return end
    local s = scale or 1
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(atlas.image, quad, center_x - (cell_w * s * 0.5), center_y - (cell_h * s * 0.5), 0, s, s)
end

ShopUI.BOOSTER_ATLAS_FRAMES = {
    arcana = { normal = { 0, 1, 2, 3 }, jumbo = { 8, 9 }, mega = { 10, 11 } },
    celestial = { normal = { 4, 5, 6, 7 }, jumbo = { 12, 13 }, mega = { 14, 15 } },
    spectral = { normal = { 16, 17 }, jumbo = { 18 }, mega = { 19 } },
    standard = { normal = { 22, 23, 24, 25 }, jumbo = { 26, 27 }, mega = { 28, 29 } },
    buffoon = { normal = { 30, 31 }, jumbo = { 32 }, mega = { 33 } },
}

function ShopUI.booster_frames_for_pack_size(pack, size)
    local row = ShopUI.BOOSTER_ATLAS_FRAMES[pack]
    if not row then return nil end
    return row[size] or row.normal
end

---@return boolean
function ShopUI.draw_booster_atlas_frame(game, rect, frame_index_zero_based)
    if not game or not rect or type(frame_index_zero_based) ~= "number" then return false end
    if game.ensure_asset_atlas_loaded then
        game:ensure_asset_atlas_loaded("Booster")
    end
    local atlas = game.ASSET_ATLAS and game.ASSET_ATLAS.Booster
    if not atlas or not atlas.image then return false end

    local px = tonumber(atlas.px) or 72
    local py = tonumber(atlas.py) or 95
    local idx = math.max(0, math.floor(frame_index_zero_based))
    local quad = ShopUI.cached_atlas_quad(atlas, idx, "_pack_quads")
    if not quad then return false end

    local s = math.min(1, rect.w / px, rect.h / py)
    local dw, dh = px * s, py * s
    local dx = rect.x + math.floor((rect.w - dw) * 0.5 + 0.5)
    local dy = rect.y + math.floor((rect.h - dh) * 0.5 + 0.5)
    local pr, pg, pb, pa = love.graphics.getColor()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(atlas.image, quad, dx, dy, 0, s, s)
    love.graphics.setColor(pr, pg, pb, pa)
    return true
end

-- m6x11plus ink metrics as a fraction of the font size: glyphs occupy the band
-- from 0.1875 to 0.875 of the line box, so stacked lines can be packed tighter
-- than getHeight() would allow.
local INK_TOP_RATIO = 0.1875
local INK_HEIGHT_RATIO = 0.6875
local LINE_GAP = 2

function ShopUI.draw_shop_button(game, param)
    if type(param) ~= "table" then
        print(type(param))
        return
    end

    local x = param.x
    local y = param.y
    local w = param.w
    local h = param.h
    local color = param.color
    local text = param.text
    local lines = param.lines

    if _G.draw_rect_with_shadow then
        local ix, iy, iw, ih = draw_button_with_shadow(x, y, w, h, 4, 2, color, game.C.BLOCK.SHADOW, 2)
        love.graphics.setColor(game.C.WHITE)

        local parts = param.parts
        if not parts then
            parts = {}
            for line in tostring(text or ""):gmatch("[^\n]+") do
                parts[#parts + 1] = { text = line, font = game.FONTS.PIXEL.SMALL }
            end
        end

        local total = 0
        for i, part in ipairs(parts) do
            local font = part.font or game.FONTS.PIXEL.SMALL
            -- Drop a size if the label would spill past the button's inner width. `next_smaller`
            -- is strictly smaller by construction, so this terminates at the bottom of the ladder.
            while font:getWidth(part.text) > iw do
                local smaller = Fonts.next_smaller(game, font)
                if not smaller then break end
                font = smaller
            end
            part.resolved_font = font
            total = total + font:getHeight() * INK_HEIGHT_RATIO
            if i > 1 then total = total + LINE_GAP end
        end

        local ink_y = iy + math.floor((ih - total) / 2)
        for _, part in ipairs(parts) do
            local font = part.resolved_font
            local size = font:getHeight()
            love.graphics.setFont(font)
            love.graphics.printf(part.text, ix, math.floor(ink_y - size * INK_TOP_RATIO), iw, "center")
            ink_y = ink_y + size * INK_HEIGHT_RATIO + LINE_GAP
        end
    else
        love.graphics.setColor(color)
        love.graphics.rectangle("fill", x, y, w, h, 4, 4)
    end
end

function ShopUI.draw_bottom_shop(game)
    -- Everything below hangs off panel_y, so the whole shop (buttons, sub
    -- panels, node layouts, tap rects) rides the scene-transition slide.
    local panel_x, panel_y, panel_w, panel_h = 4, 45 + game:get_shop_slide_dy(), 312, 200
    if _G.draw_rect_with_shadow then
        draw_rect_with_shadow(panel_x, panel_y, panel_w, panel_h, 4, 2, game.C.BLOCK.BACK, game.C.BLOCK.SHADOW, 2)
    else
        love.graphics.setColor(game.C.PANEL)
        love.graphics.rectangle("fill", panel_x, panel_y, panel_w, panel_h, 4, 4)
    end

    love.graphics.setColor(game.C.RED)
    love.graphics.rectangle("line", panel_x, panel_y, panel_w, panel_h, 4, 4)

    local padding = 4
    local cache = game._shop_ui_cache
    if not cache then
        cache = {
            continue = {
                x = 0, y = 0, w = 74, h = 45,
                parts = {
                    { text = "Next", font = game.FONTS.PIXEL.BUTTON },
                    { text = "Round", font = game.FONTS.PIXEL.BUTTON },
                },
            },
            reroll = {
                x = 0, y = 0, w = 74, h = 45,
                parts = {
                    { text = "Reroll", font = game.FONTS.PIXEL.BUTTON },
                    { text = "", font = game.FONTS.PIXEL.BUTTON_PRICE },
                },
            },
            joker_panel = {}, booster_panel = {}, voucher_panel = {},
            continue_hit = {}, reroll_hit = {},
        }
        game._shop_ui_cache = cache
    end

    local shop_continue_rect = cache.continue
    shop_continue_rect.x = panel_x + padding
    shop_continue_rect.y = panel_y + padding
    shop_continue_rect.color = game.C.RED
    local reroll_cost = game:shop_current_reroll_cost()
    local can_reroll = game:can_afford_price(reroll_cost)
    local reroll_color = can_reroll and game.C.GREEN or game.C.GREY
    local shop_reroll_rect = cache.reroll
    shop_reroll_rect.x = panel_x + padding
    shop_reroll_rect.y = shop_continue_rect.y + shop_continue_rect.h + padding
    shop_reroll_rect.color = reroll_color
    shop_reroll_rect.parts[2].text = "$" .. tostring(reroll_cost)

    local continue_hit = cache.continue_hit
    continue_hit.x, continue_hit.y = shop_continue_rect.x, shop_continue_rect.y
    continue_hit.w, continue_hit.h = shop_continue_rect.w, shop_continue_rect.h
    local reroll_hit = cache.reroll_hit
    reroll_hit.x, reroll_hit.y = shop_reroll_rect.x, shop_reroll_rect.y
    reroll_hit.w, reroll_hit.h = shop_reroll_rect.w, shop_reroll_rect.h
    game._shop_continue_rect = continue_hit
    game._shop_reroll_rect = reroll_hit
    ShopUI.draw_shop_button(game, shop_continue_rect)
    ShopUI.draw_shop_button(game, shop_reroll_rect)

    love.graphics.setColor(game.C.PANEL)
    local jokerPanel = cache.joker_panel
    jokerPanel.x = shop_continue_rect.x + shop_continue_rect.w + padding
    jokerPanel.y = shop_continue_rect.y
    jokerPanel.w = panel_w - 3 * padding - shop_continue_rect.w
    jokerPanel.h = (shop_reroll_rect.y + shop_reroll_rect.h) - shop_continue_rect.y
    love.graphics.rectangle("fill", jokerPanel.x, jokerPanel.y, jokerPanel.w, jokerPanel.h, 4, 4)

    local refresh_layout = ShopUI.shop_layout_needs_refresh(game)
    if refresh_layout then
        ShopUI.layout_shop_offer_nodes(game, jokerPanel)
    end

    game._shop_joker_panel = jokerPanel

    local bp_w, bp_h = 123, 90
    local boosterPanel = cache.booster_panel
    boosterPanel.x = jokerPanel.x + math.floor(jokerPanel.w * 0.5) - 10
    boosterPanel.y = jokerPanel.y + jokerPanel.h + padding
    boosterPanel.w, boosterPanel.h = bp_w, bp_h
    love.graphics.setColor(game.C.PANEL)
    love.graphics.rectangle("fill", boosterPanel.x, boosterPanel.y, boosterPanel.w, boosterPanel.h, 4, 4)
    game._shop_booster_panel = boosterPanel
    if refresh_layout then
        ShopUI.layout_shop_booster_nodes(game, boosterPanel)
    end

    local voucherPanel = cache.voucher_panel
    voucherPanel.x = panel_x + padding
    voucherPanel.y = boosterPanel.y
    voucherPanel.w, voucherPanel.h = 177, bp_h
    love.graphics.setColor(game.C.PANEL)
    love.graphics.rectangle("fill", voucherPanel.x, voucherPanel.y, voucherPanel.w, voucherPanel.h, 4, 4)
    game._shop_voucher_panel = voucherPanel
    if refresh_layout then
        ShopUI.layout_shop_voucher_nodes(game, voucherPanel)
        game._shop_layout_dirty = nil
    end

    ShopUI.draw_panel_header(game, "VOUCHER", panel_x - 1, voucherPanel.y, voucherPanel.h)
end

--- A shop panel's spine label, set sideways up the left edge of its panel.
---
--- Every other piece of shop chrome - the buttons, the price tags - carries the drop shadow
--- that gives this UI its depth, and this label was the one thing still printed flat, so it
--- read as part of the background rather than as a label on top of it. The offset is the same
--- one `draw_rect_with_shadow` uses, applied along the rotated axis so the shadow falls the
--- same way as everything else on the screen rather than sideways with the glyphs.
---@param text string
---@param x number left edge of the panel the label runs up
---@param panel_y number
---@param panel_h number
function ShopUI.draw_panel_header(game, text, x, panel_y, panel_h)
    local font = game.FONTS.PIXEL.MEDIUM
    love.graphics.setFont(font)
    -- Rotated -90 degrees, so the text runs bottom-to-top and is centred on the panel.
    local y = panel_y + font:getWidth(text) / 2 + panel_h / 2
    local shadow = (game.C.BLOCK and game.C.BLOCK.SHADOW) or { 0, 0, 0, 0.35 }
    love.graphics.setColor(shadow)
    -- +1 on screen x and y. Under the rotation the glyph axes are swapped, so the shadow is
    -- offset in the rotated frame's (y, -x) to land on the screen's (x, y).
    love.graphics.print(text, x + 1, y + 1, math.rad(-90))
    love.graphics.setColor(game.C.BLOCK.BACK)
    love.graphics.print(text, x, y, math.rad(-90))
end

function ShopUI.handle_touch(game, x, y)
    if game._shop_slide then return true end
    if game:_point_in_rect_simple(x, y, game._shop_continue_rect) then
        Sfx.play_button()
        game:continue_from_shop()
        return true
    end
    if game:_point_in_rect_simple(x, y, game._shop_reroll_rect) then
        -- The press only; reroll_shop_offers owns the coin cue.
        Sfx.play_button()
        game:reroll_shop_offers()
        return true
    end
    return false
end

return ShopUI
