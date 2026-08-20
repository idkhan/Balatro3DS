--- Main-menu Collection: category picker + paginated 5x3 grids.
local CollectionCatalog = require("collection_catalog")
local ShopUI = require("shop_ui")

local CollectionUI = {}

local SCREEN_W, SCREEN_H = 320, 240
local TOP_W, TOP_H = 400, 240
local COLS, ROWS, PER_PAGE = 5, 3, 15
local CARD_W, CARD_H = 71, 95
local TAP_THRESHOLD = 12

CollectionUI.COLS = COLS
CollectionUI.ROWS = ROWS
CollectionUI.PER_PAGE = PER_PAGE

sysDepth = 0
buttonHeight = 1
textHeight = 2
signHeight = 3
jokerHeight = 2
PopupHeight = 4

---@class CollectionStaticNode : Moveable
local CollectionStaticNode = Moveable:extend()

function CollectionStaticNode:init(X, Y, W, H, entry)
    Moveable.init(self, X, Y, W, H)
    self._collection_entry = entry
    self._collection_static = true
    self._collection_node = true
    self.states.click.can = true
    self.states.drag.can = true
    self.face_up = true
end

local UNDISCOVERED_OVERLAY_INDEX = 26

local function joker_sprite_key_from_def(def, edition)
    if not def or not Joker or not Joker.sprite_key_from_pos then return nil end
    local pos = def.pos
    if type(pos) ~= "table" then return nil end
    return Joker.sprite_key_from_pos(pos.atlas, pos.index, edition)
end

local function atlas_quad_for_index(atlas, index)
    if not atlas or not atlas.image or index == nil then return nil, 0, 0 end
    local px = tonumber(atlas.px) or 72
    local py = tonumber(atlas.py) or 95
    local iw, ih = atlas.image:getDimensions()
    local cols = math.max(1, math.floor(iw / px))
    local col = index % cols
    local row = math.floor(index / cols)
    local quad = love.graphics.newQuad(col * px, row * py, px, py, iw, ih)
    return quad, px, py
end

local function draw_undiscovered_collection_card(x, y, w, h)
    if not G or not G.ensure_asset_atlas_loaded then return end
    local atlas = G:ensure_asset_atlas_loaded("centers")
    if not atlas or not atlas.image then return end

    local back_idx = 1

    local back_quad, px, py = atlas_quad_for_index(atlas, back_idx)
    local overlay_quad = atlas_quad_for_index(atlas, UNDISCOVERED_OVERLAY_INDEX)
    local s = math.min(w / px, h / py)

    love.graphics.setColor(1, 1, 1, 1)
    if back_quad then
        love.graphics.draw(atlas.image, back_quad, x, y, 0, s, s)
    end
    if overlay_quad then
        love.graphics.draw(atlas.image, overlay_quad, x, y, 0, s, s)
    end
end

local function draw_deck_collection_sprite(game, def, x, y, w, h)
    if not game or not def then return end
    local atlas = game.ensure_asset_atlas_loaded and game:ensure_asset_atlas_loaded("centers")
    if not atlas or not atlas.image then return end

    local index = tonumber(def.pos) or 0
    local iw, ih = atlas.image:getDimensions()
    local cell_w = tonumber(atlas.px) or 72
    local cell_h = tonumber(atlas.py) or 95
    local cols = math.max(1, math.floor(iw / cell_w))
    local col = index % cols
    local row = math.floor(index / cols)
    local quad = love.graphics.newQuad(col * cell_w, row * cell_h, cell_w, cell_h, iw, ih)

    local scale = math.min(w / cell_w, h / cell_h)
    if scale > 1 then scale = 1 end
    local draw_w = cell_w * scale
    local draw_h = cell_h * scale
    local dx = x + math.floor((w - draw_w) * 0.5 + 0.5)
    local dy = y + math.floor((h - draw_h) * 0.5 + 0.5)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(atlas.image, quad, dx, dy, 0, scale, scale)
end

function CollectionStaticNode:draw()
    local entry = self._collection_entry
    if not entry then return end
    local discovered = CollectionCatalog.is_entry_discovered(G, entry)
    local draw_x = self.VT.x + (self.collision_offset and self.collision_offset.x or 0)
    local draw_y = self.VT.y + (self.collision_offset and self.collision_offset.y or 0)
    local dw = self.VT.w * self.VT.scale
    local dh = self.VT.h * self.VT.scale

    if not discovered then
        draw_undiscovered_collection_card(draw_x, draw_y, dw, dh)
        return
    end

    local kind = entry.node_kind
    if kind == "deck" then
        draw_deck_collection_sprite(G, entry.def, draw_x, draw_y, dw, dh)
    elseif kind == "voucher" then
        local def = entry.def
        if G and G.ensure_asset_atlas_loaded then
            local atlas = G:ensure_asset_atlas_loaded("Voucher")
            if atlas and atlas.image and def then
                local px = tonumber(atlas.px) or 72
                local py = tonumber(atlas.py) or 95
                local idx = tonumber(def.pos) or 0
                local iw, ih = atlas.image:getDimensions()
                local cols = math.max(1, math.floor(iw / px))
                local col = idx % cols
                local row = math.floor(idx / cols)
                local quad = love.graphics.newQuad(col * px, row * py, px, py, iw, ih)
                local s = math.min(dw / px, dh / py)
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.draw(atlas.image, quad, draw_x, draw_y, 0, s, s)
            end
        end
    elseif kind == "booster" then
        ShopUI.draw_booster_atlas_frame(G, { x = draw_x, y = draw_y, w = dw, h = dh }, entry.frame_index or 0)
    elseif kind == "tag" then
        local tag = Tag(entry.tag_type, draw_x, draw_y)
        tag:draw()
    elseif kind == "blind" then
        if G and G.draw_blind_chip_sprite then
            local pos = entry.blind_def and entry.blind_def.pos
            local sprite_row = tonumber(pos) or 0
            G:draw_blind_chip_sprite(sprite_row, draw_x + dw * 0.5, draw_y + dh * 0.5, math.min(dw / 36, dh / 36))
        end
    end
end

function CollectionStaticNode:draw_tooltip(draw_x, draw_y)
    local entry = self._collection_entry
    if not entry or not G then return end
    CollectionUI.draw_entry_tooltip(G, self, draw_x, draw_y)
end

function CollectionStaticNode:draw_tooltip_overlay()
    if not G or G._collection_tooltip_node ~= self then return end
    local dx = self.VT.x + (self.collision_offset and self.collision_offset.x or 0)
    local dy = self.VT.y + (self.collision_offset and self.collision_offset.y or 0)
    self:draw_tooltip(dx, dy)
end

CollectionUI.CollectionStaticNode = CollectionStaticNode

local function category_color(game, color_key)
    local C = game.C or {}
    local sec = C.SECONDARY_SET or {}
    if color_key == "PURPLE" then return sec.Tarot or C.TAROT or { 0.65, 0.51, 0.82, 1 } end
    if color_key == "PLANET" then return sec.Planet or C.PLANET or { 0.07, 0.69, 0.81, 1 } end
    if color_key == "SPECTRAL" then return sec.Spectral or C.SPECTRAL or { 0.27, 0.52, 0.98, 1 } end
    return C.RED or C.MULT or { 0.99, 0.37, 0.33, 1 }
end

local function draw_collection_button(rect, label, prog, color, C, font_label, font_count)
    if _G.draw_rect_with_shadow then
        draw_rect_with_shadow(rect.x, rect.y, rect.w, rect.h, 4, 4, color, C.BLOCK.SHADOW, 2)
    else
        love.graphics.setColor(color)
        love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 4, 4)
    end

    local count_pad = 1
    local count_str = prog and string.format("%d / %d", prog.discovered, prog.total) or nil

    love.graphics.setFont(font_label)
    local title_h = love.graphics.getFont():getHeight()
    local count_h = 0
    if count_str then
        love.graphics.setFont(font_count)
        count_h = love.graphics.getFont():getHeight()
    end

    local block_h = title_h + (count_str and (count_pad + count_h) or 0)
    local text_y = rect.y + math.floor((rect.h - block_h) * 0.5 + 0.5)

    love.graphics.setFont(font_label)
    love.graphics.setColor(C.WHITE)
    love.graphics.printf(label, rect.x, text_y, rect.w, "center")

    if count_str then
        love.graphics.setFont(font_count)
        love.graphics.setColor(C.DARK_WHITE or C.GREY)
        love.graphics.printf(count_str, rect.x, text_y + title_h + count_pad, rect.w, "center")
    end
end

function CollectionUI.clear_tooltips(game)
    game._collection_tooltip_node = nil
    game._collection_draw_front_node = nil
    game.active_tooltip_joker = nil
    game.active_tooltip_consumable_index = nil
    game.active_tooltip_card = nil
end

local function draw_hidden_collection_tooltip(node)
    if not node or not G then return end
    local draw_x = node.VT.x + (node.collision_offset and node.collision_offset.x or 0)
    local draw_y = node.VT.y + (node.collision_offset and node.collision_offset.y or 0)
    local card_w = node.VT.w * node.VT.scale
    local card_h = node.VT.h * node.VT.scale
    local font = G.FONTS.PIXEL.SMALL or love.graphics.getFont()
    local TooltipDraw = require("tooltip_draw")
    TooltipDraw.draw_tooltip_layout(font, "Not Discovered", {}, draw_x, draw_y, card_w, card_h)
end

function CollectionUI.draw_entry_tooltip(game, node, draw_x, draw_y)
    if not game or not node then return end
    local entry = node._collection_entry
    if not entry then return end
    draw_x = draw_x or (node.VT.x + (node.collision_offset and node.collision_offset.x or 0))
    draw_y = draw_y or (node.VT.y + (node.collision_offset and node.collision_offset.y or 0))
    local card_w = node.VT.w * node.VT.scale
    local card_h = node.VT.h * node.VT.scale
    local title, raw_lines = CollectionCatalog.entry_tooltip_content(game, entry)
    local TooltipDraw = require("tooltip_draw")
    local resolved = {}
    for _, line in ipairs(raw_lines or {}) do
        local split = TooltipDraw.resolved_lines_from_multiline(tostring(line))
        for _, sl in ipairs(split) do
            resolved[#resolved + 1] = sl
        end
    end
    local font = game.FONTS.PIXEL.SMALL or love.graphics.getFont()
    TooltipDraw.draw_tooltip_layout(font, title, resolved, draw_x, draw_y, card_w, card_h)
end

function CollectionUI.draw_grid_tooltips(game)
    local node = game._collection_tooltip_node
    if not node then return end
    if node._collection_hidden then
        draw_hidden_collection_tooltip(node)
        return
    end
    local entry = node._collection_entry
    local custom_kinds = {
        deck = true, voucher = true, booster = true, tag = true,
        blind = true, seal = true, enhanced = true,
    }
    if entry and custom_kinds[entry.node_kind] then
        CollectionUI.draw_entry_tooltip(game, node)
        return
    end
    if node.draw_tooltip_overlay then
        node:draw_tooltip_overlay()
    end
end

function CollectionUI.open(game)
    game._menu_sub_state = "collection_menu"
    game._collection_category = nil
    game._collection_page = 1
    game._collection_open = true
    CollectionCatalog.invalidate_cache()
    if game.unload_animation_atlas then
        game:unload_animation_atlas("menu")
    end
    CollectionUI.destroy_grid(game)
    CollectionUI.clear_tooltips(game)
end

function CollectionUI.open_category(game, category_id)
    game._menu_sub_state = "collection_grid"
    game._collection_category = category_id
    game._collection_page = 1
    CollectionUI.clear_tooltips(game)
    CollectionUI.build_grid(game)
end

function CollectionUI.back_from_grid(game)
    CollectionUI.destroy_grid(game)
    CollectionUI.clear_tooltips(game)
    game._menu_sub_state = "collection_menu"
    game._collection_category = nil
end

function CollectionUI.back_to_main(game)
    CollectionUI.destroy_grid(game)
    CollectionUI.clear_tooltips(game)
    game._collection_open = false
    game._menu_sub_state = "main"
    game._collection_category = nil
end

function CollectionUI.page_count(game)
    local entries = CollectionCatalog.get_entries(game._collection_category or "")
    return math.max(1, math.ceil(#entries / PER_PAGE))
end

---@param count integer items on the current page (1..PER_PAGE)
---@return integer cols, integer rows
function CollectionUI.page_grid_dims(count)
    count = math.max(1, math.min(count, PER_PAGE))
    if count <= COLS then
        return count, 1
    end
    if count <= COLS * 2 then
        return math.min(COLS, math.ceil(count / 2)), 2
    end
    return COLS, math.min(ROWS, math.ceil(count / COLS))
end

---@param count_on_page integer|nil
function CollectionUI.grid_metrics(count_on_page)
    local count = math.max(1, math.min(tonumber(count_on_page) or PER_PAGE, PER_PAGE))
    local cols, rows = CollectionUI.page_grid_dims(count)

    local margin_x = 6
    local footer_h = 14
    local grid_h = SCREEN_H - footer_h - 4
    local area_w = SCREEN_W - margin_x * 2

    local step_x = cols > 1 and (area_w - CARD_W) / (cols - 1) or 0
    local step_y = rows > 1 and (grid_h - CARD_H) / (rows - 1) or 0
    local total_w = CARD_W + (cols - 1) * step_x
    local total_h = CARD_H + (rows - 1) * step_y
    local start_x = margin_x + math.floor((area_w - total_w) * 0.5 + 0.5)
    local start_y = math.floor((grid_h - total_h) * 0.5 + 0.5)

    return {
        cols = cols,
        rows = rows,
        count = count,
        card_w = CARD_W,
        card_h = CARD_H,
        step_x = step_x,
        step_y = step_y,
        start_x = start_x,
        start_y = start_y,
        total_w = total_w,
        scale = 1,
    }
end

---@param m table
---@param index_one_based integer
---@param count_on_page integer
function CollectionUI.slot_position(m, index_one_based, count_on_page)
    local i = index_one_based - 1
    local row = math.floor(i / m.cols)
    local row_start_index = row * m.cols
    local items_in_row = math.min(m.cols, count_on_page - row_start_index)
    local col_in_row = i - row_start_index

    local full_span_w = m.total_w or (CARD_W + (m.cols - 1) * m.step_x)
    local row_span_w = CARD_W + (items_in_row - 1) * m.step_x
    local row_offset_x = (full_span_w - row_span_w) * 0.5

    local x = m.start_x + row_offset_x + col_in_row * m.step_x
    local y = m.start_y + row * m.step_y
    return x, y
end

function CollectionUI.destroy_grid(game)
    for _, node in ipairs(game._collection_nodes or {}) do
        if node then
            if game.active_tooltip_joker == node then
                game.active_tooltip_joker = nil
            end
            game:remove(node)
        end
    end
    game._collection_nodes = {}
    game._collection_node_entries = nil
end

function CollectionUI.spawn_node_for_entry(game, entry, x, y, m)
    local w, h = CARD_W, CARD_H
    local node = nil
    local kind = entry.node_kind

    if kind == "joker" and Joker and entry.def then
        local sprite_key = joker_sprite_key_from_def(entry.def)
        if game.ensure_joker_sprite_loaded and sprite_key then
            game:ensure_joker_sprite_loaded(sprite_key)
        end
        node = Joker(x, y, w, h, entry.def, { face_up = true })
    elseif kind == "consumable" and Consumable and entry.def then
        node = Consumable(x, y, entry.def)
        node.VT.w = w
        node.VT.h = h
        node.T.w = w
        node.T.h = h
    elseif kind == "enhanced" and Card then
        local data = { rank = 14, suit = "Spades", enhancement = entry.enhancement, seal = nil }
        node = Card(x, y, w, h, data, nil, { face_up = true })
    elseif kind == "seal" and Card then
        local data = { rank = 14, suit = "Spades", enhancement = nil, seal = entry.seal }
        node = Card(x, y, w, h, data, nil, { face_up = true })
    elseif kind == "edition" and Joker and JOKER_DEFS and JOKER_DEFS.j_joker then
        local def = JOKER_DEFS.j_joker
        local sprite_key = joker_sprite_key_from_def(def, entry.edition)
        if game.ensure_joker_sprite_loaded and sprite_key then
            game:ensure_joker_sprite_loaded(sprite_key)
        end
        node = Joker(x, y, w, h, def, { face_up = true, edition = entry.edition })
    else
        node = CollectionStaticNode(x, y, w, h, entry)
    end

    if not node then return nil end

    node._collection_entry = entry
    node._collection_node = true
    node.states.click.can = true
    node.states.drag.can = true
    node.T.scale = 1
    node.VT.scale = 1
    node.T.x = x
    node.T.y = y
    node.VT.x = x
    node.VT.y = y

    if not CollectionCatalog.is_entry_discovered(game, entry) then
        node._collection_hidden = true
    end

    game:add(node)
    return node
end

local function wrap_draw_undiscovered(node)
    if node._collection_draw_wrapped then return end
    local base_draw = node.draw
    node.draw = function(self)
        if self._collection_hidden then
            local draw_x = self.VT.x + (self.collision_offset and self.collision_offset.x or 0)
            local draw_y = self.VT.y + (self.collision_offset and self.collision_offset.y or 0)
            local dw = self.VT.w * self.VT.scale
            local dh = self.VT.h * self.VT.scale
            draw_undiscovered_collection_card(draw_x, draw_y, dw, dh)
            return
        end
        base_draw(self)
    end
    node._collection_draw_wrapped = true
end

function CollectionUI.build_grid(game)
    CollectionUI.destroy_grid(game)
    local category = game._collection_category
    if not category then return end

    if game.ensure_asset_atlas_loaded then
        game:ensure_asset_atlas_loaded("centers")
        if category == "vouchers" then
            game:ensure_asset_atlas_loaded("Voucher")
        elseif category == "decks" then
            game:ensure_asset_atlas_loaded("centers")
        elseif category == "boosters" then
            game:ensure_asset_atlas_loaded("Booster")
        elseif category == "tags" or category == "blinds" then
            game:ensure_asset_atlas_loaded("tags")
        elseif category == "tarots" then
            game:ensure_asset_atlas_loaded("Tarot")
        elseif category == "planets" then
            game:ensure_asset_atlas_loaded("Planet")
        elseif category == "spectrals" then
            game:ensure_asset_atlas_loaded("Spectral")
        elseif category == "enhanced" or category == "seals" then
            game:ensure_asset_atlas_loaded("centers")
            game:ensure_asset_atlas_loaded("cards")
        elseif category == "jokers" or category == "editions" then
            game:ensure_asset_atlas_loaded("centers")
        end
    end

    local entries = CollectionCatalog.get_entries(category)
    local page = math.max(1, tonumber(game._collection_page) or 1)
    local page_max = math.max(1, math.ceil(#entries / PER_PAGE))
    page = math.min(page, page_max)
    game._collection_page = page

    local start_idx = (page - 1) * PER_PAGE + 1
    local end_idx = math.min(#entries, start_idx + PER_PAGE - 1)
    local count_on_page = math.max(0, end_idx - start_idx + 1)
    game._collection_page_count = count_on_page

    game._collection_nodes = {}
    game._collection_node_entries = {}

    local m = CollectionUI.grid_metrics(count_on_page)
    for i = start_idx, end_idx do
        local entry = entries[i]
        local slot = i - start_idx + 1
        local x, y = CollectionUI.slot_position(m, slot, count_on_page)
        local node = CollectionUI.spawn_node_for_entry(game, entry, x, y, m)
        if node then
            wrap_draw_undiscovered(node)
            game._collection_nodes[#game._collection_nodes + 1] = node
            game._collection_node_entries[node] = entry
        end
    end
end

function CollectionUI.layout_grid(game)
    local count = tonumber(game._collection_page_count) or #(game._collection_nodes or {})
    if count <= 0 then return end
    local m = CollectionUI.grid_metrics(count)
    for i, node in ipairs(game._collection_nodes or {}) do
        if node and node.T and not (node.states and node.states.drag and node.states.drag.is) then
            local x, y = CollectionUI.slot_position(m, i, count)
            node.T.x = x
            node.T.y = y
            node.VT.x = x
            node.VT.y = y
            node.T.r = 0
            node.VT.r = 0
            node.T.scale = 1
            node.VT.scale = 1
        end
    end
end

function CollectionUI.draw_category_menu(game)
    local W, H = SCREEN_W, SCREEN_H
    local C = game.C
    local font_s = game.FONTS.PIXEL.SMALL
    local font_m = game.FONTS.PIXEL.SMALL
    local btn_gap = 3

    love.graphics.setColor(C.PANEL)
    love.graphics.rectangle("fill", 0, 0, W, H)

    local col_gap = 6
    local col_w = math.floor((W - col_gap * 3) * 0.5)
    local left_x = col_gap
    local right_x = left_x + col_w + col_gap
    local y = 2
    local std_h = 28
    local tall_h = 36
    local small_h = 24
    local cons_pad = 3
    local cons_header_h = 12

    game._collection_menu_rects = {}

    local function add_btn(id, x, yy, w, h, label, color_key)
        local rect = { x = x, y = yy, w = w, h = h, category = id }
        game._collection_menu_rects[#game._collection_menu_rects + 1] = rect
        local prog = CollectionCatalog.get_progress(game, id)
        draw_collection_button(rect, label, prog, category_color(game, color_key), C, font_m, font_s)
        return yy + h + btn_gap
    end

    -- Left column
    y = add_btn("jokers", left_x, y, col_w, tall_h, "Jokers", "RED")
    y = add_btn("decks", left_x, y, col_w, std_h, "Decks", "RED")
    y = add_btn("vouchers", left_x, y, col_w, std_h, "Vouchers", "RED")

    local cons_x = left_x
    local cons_y = y
    local cons_w = col_w
    local cons_inner_w = cons_w - cons_pad * 2
    local cons_h = cons_header_h + cons_pad + small_h * 3 + btn_gap * 2 + cons_pad

    if _G.draw_rect_with_shadow then
        draw_rect_with_shadow(cons_x, cons_y, cons_w, cons_h, 4, 4, C.BLOCK.BACK, C.BLOCK.SHADOW, 2)
    else
        love.graphics.setColor(C.BLOCK.BACK)
        love.graphics.rectangle("fill", cons_x, cons_y, cons_w, cons_h, 4, 4)
    end

    love.graphics.setFont(font_s)
    love.graphics.setColor(C.GREY)
    love.graphics.printf("CONSUMABLES", cons_x, cons_y + cons_pad, cons_w, "center")

    local cy = cons_y + cons_header_h + cons_pad
    cy = add_btn("tarots", cons_x + cons_pad, cy, cons_inner_w, small_h, "Tarot Cards", "PURPLE")
    cy = add_btn("planets", cons_x + cons_pad, cy, cons_inner_w, small_h, "Planet Cards", "PLANET")
    add_btn("spectrals", cons_x + cons_pad, cy, cons_inner_w, small_h, "Spectral Cards", "SPECTRAL")

    -- Right column
    y = 2
    y = add_btn("enhanced", right_x, y, col_w, std_h, "Enhanced Cards", "RED")
    y = add_btn("seals", right_x, y, col_w, std_h, "Seals", "RED")
    y = add_btn("editions", right_x, y, col_w, std_h, "Editions", "RED")
    y = add_btn("boosters", right_x, y, col_w, std_h, "Booster Packs", "RED")
    y = add_btn("tags", right_x, y, col_w, std_h, "Tags", "RED")
    add_btn("blinds", right_x, y, col_w, tall_h, "Blinds", "RED")

    game._collection_back_rect = { x = 8, y = H - 22, w = 64, h = 18 }
    draw_collection_button(
        game._collection_back_rect, "Back", nil, C.MULT, C, font_s, font_s)

    love.graphics.setColor(C.GREY)
    love.graphics.printf("B/X: Back", 0, H - 12, W, "center")
end

function CollectionUI.draw_grid(game)
    local W = SCREEN_W

    love.graphics.setColor(G.C.PANEL)
    love.graphics.rectangle("fill", 0, 0, W, SCREEN_H)

    local page = tonumber(game._collection_page) or 1
    local pages = CollectionUI.page_count(game)

    local nav_y = SCREEN_H - 14
    game._collection_prev_rect = { x = 8, y = nav_y - 4, w = 24, h = 12 }
    game._collection_next_rect = { x = W - 32, y = nav_y - 4, w = 24, h = 12 }
    if page > 1 then
        love.graphics.setColor(G.C.WHITE)
        love.graphics.printf("<", game._collection_prev_rect.x, nav_y - 2, 24, "center")
    end
    if page < pages then
        love.graphics.setColor(G.C.WHITE)
        love.graphics.printf(">", game._collection_next_rect.x, nav_y - 2, 24, "center")
    end

    love.graphics.setFont(game.FONTS.PIXEL.SMALL)
    love.graphics.setColor(game.C.GREY)
    love.graphics.printf(
        "LEFT/RIGHT: Pages   B/X: Back",
        0, nav_y, W, "center")
end

function CollectionUI.draw_grid_nodes(game)
    local front = game.dragging or game._collection_draw_front_node
    for _, node in ipairs(game._collection_nodes or {}) do
        if node and node ~= front and node.draw then
            node:draw()
        end
    end
    if front and front.draw then
        front:draw()
    end
    CollectionUI.draw_grid_tooltips(game)
end

function CollectionUI.draw_top(screen, game)
    sysDepth = -love.graphics.getDepth()
    if screen == "right" then
        sysDepth = -sysDepth
    end
    local textDepth = sysDepth * textHeight
    local W = TOP_W
    love.graphics.setColor(game.C.WHITE)
    love.graphics.setFont(game.FONTS.PIXEL.MEDIUM)

    if game._menu_sub_state == "collection_grid" then
        local cat = CollectionCatalog.get_category_def(game._collection_category)
        local label = cat and cat.label or "Collection"
        local page = tonumber(game._collection_page) or 1
        local pages = CollectionUI.page_count(game)
        love.graphics.printf(label, 0 - textDepth, 12, W, "center")
        love.graphics.setFont(game.FONTS.PIXEL.SMALL)
        love.graphics.setColor(game.C.GREY)
        love.graphics.printf(string.format("%d / %d", page, pages), 0 - textDepth, 32, W, "center")
    else
        love.graphics.printf("Collection", 0 - textDepth, 20, W, "center")
    end
end

function CollectionUI.draw_bottom(game)
    if game._menu_sub_state == "collection_menu" then
        CollectionUI.draw_category_menu(game)
    elseif game._menu_sub_state == "collection_grid" then
        CollectionUI.draw_grid(game)
    end
end

function CollectionUI.get_node_at(game, x, y)
    for i = #(game._collection_nodes or {}), 1, -1 do
        local node = game._collection_nodes[i]
        if node and node.states and node.states.click.can and game:point_in_rect(x, y, node) then
            return node
        end
    end
    return nil
end

function CollectionUI.set_draw_front_node(game, node)
    if game then
        game._collection_draw_front_node = node
    end
end

function CollectionUI.toggle_tooltip(game, node)
    if not node then return end
    if game._collection_tooltip_node == node then
        CollectionUI.clear_tooltips(game)
        return
    end
    CollectionUI.clear_tooltips(game)
    game._collection_tooltip_node = node
    if Joker and node.is and node:is(Joker) then
        game.active_tooltip_joker = node
    elseif Card and node.is and node:is(Card) then
        game.active_tooltip_card = node
    end
    CollectionUI.set_draw_front_node(game, node)
end

function CollectionUI.handle_touch_menu(game, x, y)
    for _, rect in ipairs(game._collection_menu_rects or {}) do
        if rect.category and game:_point_in_rect_simple(x, y, rect) then
            CollectionUI.open_category(game, rect.category)
            return true
        end
    end
    local back = game._collection_back_rect
    if back and game:_point_in_rect_simple(x, y, back) then
        CollectionUI.back_to_main(game)
        return true
    end
    return false
end

function CollectionUI.handle_touch_grid(game, x, y)
    local page = tonumber(game._collection_page) or 1
    local pages = CollectionUI.page_count(game)

    if page > 1 and game._collection_prev_rect and game:_point_in_rect_simple(x, y, game._collection_prev_rect) then
        game._collection_page = page - 1
        CollectionUI.clear_tooltips(game)
        CollectionUI.build_grid(game)
        return true
    end
    if page < pages and game._collection_next_rect and game:_point_in_rect_simple(x, y, game._collection_next_rect) then
        game._collection_page = page + 1
        CollectionUI.clear_tooltips(game)
        CollectionUI.build_grid(game)
        return true
    end
    return false
end

function CollectionUI.handle_touchpressed(game, id, x, y)
    if game._menu_sub_state == "collection_menu" then
        return CollectionUI.handle_touch_menu(game, x, y)
    end
    if game._menu_sub_state ~= "collection_grid" then return false end

    if CollectionUI.handle_touch_grid(game, x, y) then return true end

    game.touch_start_x = x
    game.touch_start_y = y
    local node = CollectionUI.get_node_at(game, x, y)
    if node and node.touchpressed then
        node:touchpressed(id, x, y)
        game.dragging = node
        CollectionUI.set_draw_front_node(game, node)
        return true
    end
    game.dragging = nil
    CollectionUI.clear_tooltips(game)
    return true
end

function CollectionUI.handle_touchmoved(game, id, x, y, dx, dy)
    if game._menu_sub_state ~= "collection_grid" then return end
    if game.dragging and game.dragging.touchmoved then
        game.dragging:touchmoved(id, x, y, dx, dy)
    end
end

function CollectionUI.handle_touchreleased(game, id, x, y)
    if game._menu_sub_state ~= "collection_grid" then return false end

    local released = game.dragging
    if released and released.touchreleased then
        released:touchreleased(id, x, y)
    end
    local start_x = game.touch_start_x or x
    local start_y = game.touch_start_y or y
    local dist = math.sqrt((x - start_x)^2 + (y - start_y)^2)

    if released and dist < TAP_THRESHOLD then
        CollectionUI.toggle_tooltip(game, released)
    elseif released and dist >= TAP_THRESHOLD then
        CollectionUI.layout_grid(game)
        CollectionUI.clear_tooltips(game)
    end
    game.dragging = nil
    return true
end

function CollectionUI.handle_touch(game, x, y)
    if game._menu_sub_state == "collection_menu" then
        return CollectionUI.handle_touch_menu(game, x, y)
    end
    return false
end

function CollectionUI.handle_button(game, btn)
    if game._menu_sub_state == "collection_menu" then
        if game.is_menu_back and game:is_menu_back(btn) then
            CollectionUI.back_to_main(game)
        end
    elseif game._menu_sub_state == "collection_grid" then
        if game.is_menu_back and game:is_menu_back(btn) then
            CollectionUI.back_from_grid(game)
        elseif btn == "dpleft" or btn == "left" then
            local page = tonumber(game._collection_page) or 1
            if page > 1 then
                game._collection_page = page - 1
                CollectionUI.clear_tooltips(game)
                CollectionUI.build_grid(game)
            end
        elseif btn == "dpright" or btn == "right" then
            local page = tonumber(game._collection_page) or 1
            local pages = CollectionUI.page_count(game)
            if page < pages then
                game._collection_page = page + 1
                CollectionUI.clear_tooltips(game)
                CollectionUI.build_grid(game)
            end
        elseif game.is_menu_activate and game:is_menu_activate(btn) then
            local node = game._collection_tooltip_node
            if not node and game._collection_nodes and game._collection_nodes[1] then
                CollectionUI.toggle_tooltip(game, game._collection_nodes[1])
            end
        end
    end
end

return CollectionUI
