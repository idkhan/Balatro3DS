---@class Game
Game = Object:extend()

---@param seed number|nil Optional seed for the RNG. If nil, a seed is generated (os.time()).
function Game:init(seed)
    G = self
    -- core containers/state
    self.nodes = {}
    self.dragging = nil
    self.touch_start_x = 0
    self.touch_start_y = 0
    self.pending_discard = {}
    self.discard_timer = 0
    self.selectedHand = -1
    self.selectedHandLevel = 1
    self.selectedHandChips = 0
    self.selectedHandMult = 0
    self.active_tooltip_card = nil
    self.round_score = 0
    self.last_hand_score = 0
    --- Run currency
    self.money = 0
    -- Run Discards
    self.discards = 5
    -- Run Hands
    self.hands = 5
    -- Round Count
    self.round = 1
    -- Ante Count
    self.ante = 1
    self._last_completed_blind_was_boss = false
    self.current_blind_index = 1
    self.current_blind_target = 0
    self.current_blind_reward = 0
    self.current_blind_name = "Small Blind"
    self.selected_blind_index = 1
    self._blind_resolution_pending = false
    self.shop_offers = {}
    self.shop_offer_cursor = 1
    self.shop_sell_cursor = 1
    self.current_boss_blind_id = nil
    self._collidables_buf = {}
    self._gc_timer = 0
    self._gc_discarded_nodes = 0
    --- Staggered joker resolution (left-to-right); see `begin_joker_emit` / `_update_joker_emit_queue`.
    self._joker_emit_queue = nil
    self._joker_emit_next = 1
    self._joker_emit_timer = 0
    self.JOKER_EMIT_INTERVAL = 0.5

    -- Pull all shared globals from globals.lua
    if self.set_globals then
        self:set_globals()
    end
    if self.init_item_prototypes then
        self:init_item_prototypes()
    end

    if seed ~= nil then
        self.SEED = seed
    end
    math.randomseed(self.SEED)
    collectgarbage("setpause", 110)
    collectgarbage("setstepmul", 200)

    -- set filters and load atlases
    self:set_render_settings()

    -- Create joker slots + initial joker instances.
    -- (Top-screen rendering is handled by `TopUI.draw()`)
    self:init_jokers()
end

function Game:add(node)
    table.insert(self.nodes, node)
    return node
end

function Game:set_state(state_id)
    self.STATE = state_id
end

function Game:get_base_requirement_for_ante(ante)
    local base_table = self.BASE_REQUIREMENT_BY_ANTE or {}
    local a = math.max(1, tonumber(ante) or 1)
    if base_table[a] then
        return tonumber(base_table[a]) or 0
    end
    local max_ante = 1
    for k, _ in pairs(base_table) do
        if k > max_ante then max_ante = k end
    end
    local last_base = tonumber(base_table[max_ante]) or 300
    local overflow = math.max(0, a - max_ante)
    return math.floor(last_base * (1 + overflow * 0.6))
end

function Game:get_blind_def(index)
    local defs = self.BLIND_DEFS or {}
    return defs[index]
end

function Game:get_boss_blind_pool()
    local out = {}
    for key, blind in pairs(self.P_BLINDS or {}) do
        if key ~= "bl_small" and key ~= "bl_big" and type(blind) == "table" and type(blind.boss) == "table" then
            out[#out + 1] = key
        end
    end
    table.sort(out)
    return out
end

function Game:roll_boss_blind()
    local pool = self:get_boss_blind_pool()
    if #pool == 0 then
        self.current_boss_blind_id = nil
        return nil
    end
    self.current_boss_blind_id = pool[math.random(#pool)]
    return self.current_boss_blind_id
end

function Game:get_boss_blind_prototype()
    local key = self.current_boss_blind_id
    if not key or not self.P_BLINDS or not self.P_BLINDS[key] then
        key = self:roll_boss_blind()
    end
    return key and self.P_BLINDS and self.P_BLINDS[key] or nil
end

function Game:get_blind_display_name(index)
    local def = self:get_blind_def(index)
    if not def then return "Blind" end
    if def.id == "boss" then
        local proto = self:get_boss_blind_prototype()
        if proto and proto.name then return proto.name end
    end
    return def.name or "Blind"
end

function Game:get_blind_color(index)
    local def = self:get_blind_def(index)
    if not def then return self.C.BLIND_COLORS.Big end
    if def.id == "boss" then
        local proto = self:get_boss_blind_prototype()
        if proto and proto.boss_colour then
            return proto.boss_colour
        end
    end
    return self.C.BLIND_COLORS[def.key] or self.C.BLIND_COLORS.Big
end

function Game:get_blind_reward(index)
    local def = self:get_blind_def(index)
    if not def then return 0 end
    return tonumber(def.reward) or 0
end

function Game:get_blind_sprite_index(index)
    local def = self:get_blind_def(index)
    if not def then return 0 end
    if def.id == "small" then
        return tonumber(self.P_BLINDS and self.P_BLINDS.bl_small and self.P_BLINDS.bl_small.pos) or 0
    end
    if def.id == "big" then
        return tonumber(self.P_BLINDS and self.P_BLINDS.bl_big and self.P_BLINDS.bl_big.pos) or 1
    end
    local proto = self:get_boss_blind_prototype()
    return tonumber(proto and proto.pos) or 2
end

function Game:get_blind_target(index, ante)
    local def = self:get_blind_def(index)
    if not def then return 0 end
    local base = self:get_base_requirement_for_ante(ante or self.ante or 1)
    local mult = tonumber(def.multiplier) or 1
    if def.id == "boss" then
        local proto = self:get_boss_blind_prototype()
        mult = tonumber(proto and proto.mult) or mult
    end
    return math.floor(base * mult)
end

function Game:get_preview_blind()
    return self:get_blind_def(self.selected_blind_index or self.current_blind_index or 1)
end

function Game:is_blind_selectable(index)
    return tonumber(index) == tonumber(self.current_blind_index)
end

function Game:remove(node)
    for i, n in ipairs(self.nodes) do
        if n == node then
            table.remove(self.nodes, i)
            return true
        end
    end
    return false
end

function Game:init_item_prototypes()
    self.P_TAGS = {
        tag_uncommon =      {name = 'Uncommon Tag',     set = 'Tag', discovered = false, min_ante = nil, order = 1, config = {type = 'store_joker_create'}, pos = {x = 0,y = 0}},
        tag_rare =          {name = 'Rare Tag',         set = 'Tag', discovered = false, min_ante = nil, order = 2, config = {type = 'store_joker_create', odds = 3}, requires = 'j_blueprint', pos = {x = 1,y = 0}},
        tag_negative =      {name = 'Negative Tag',     set = 'Tag', discovered = false, min_ante = 2,   order = 3, config = {type = 'store_joker_modify', edition = 'negative', odds = 5}, requires = 'e_negative', pos = {x = 2, y = 0}},
        tag_foil =          {name = 'Foil Tag',         set = 'Tag', discovered = false, min_ante = nil, order = 4, config = {type = 'store_joker_modify', edition = 'foil', odds = 2}, requires = 'e_foil', pos = {x = 3,y = 0}},
        tag_holo =          {name = 'Holographic Tag',  set = 'Tag', discovered = false, min_ante = nil, order = 5, config = {type = 'store_joker_modify', edition = 'holo', odds = 3}, requires = 'e_holo', pos = {x = 0,y = 1}},
        tag_polychrome =    {name = 'Polychrome Tag',   set = 'Tag', discovered = false, min_ante = nil, order = 6, config = {type = 'store_joker_modify', edition = 'polychrome', odds = 4}, requires = 'e_polychrome', pos = {x = 1,y = 1}},
        tag_investment =    {name = 'Investment Tag',   set = 'Tag', discovered = false, min_ante = nil, order = 7, config = {type = 'eval', dollars = 25}, pos = {x = 2,y = 1}},
        tag_voucher =       {name = 'Voucher Tag',      set = 'Tag', discovered = false, min_ante = nil, order = 8, config = {type = 'voucher_add'}, pos = {x = 3,y = 1}},
        tag_boss =          {name = 'Boss Tag',         set = 'Tag', discovered = false, min_ante = nil, order = 9, config = {type = 'new_blind_choice', }, pos = {x = 0,y = 2}},
        tag_standard =      {name = 'Standard Tag',     set = 'Tag', discovered = false, min_ante = 2,   order = 10, config = {type = 'new_blind_choice', }, pos = {x = 1,y = 2}},
        tag_charm =         {name = 'Charm Tag',        set = 'Tag', discovered = false, min_ante = nil, order = 11, config = {type = 'new_blind_choice', }, pos = {x = 2,y = 2}},
        tag_meteor =        {name = 'Meteor Tag',       set = 'Tag', discovered = false, min_ante = 2,   order = 12, config = {type = 'new_blind_choice', }, pos = {x = 3,y = 2}},
        tag_buffoon =       {name = 'Buffoon Tag',      set = 'Tag', discovered = false, min_ante = 2,   order = 13, config = {type = 'new_blind_choice', }, pos = {x = 4,y = 2}},
        tag_handy =         {name = 'Handy Tag',        set = 'Tag', discovered = false, min_ante = 2,   order = 14, config = {type = 'immediate', dollars_per_hand = 1}, pos = {x = 1,y = 3}},
        tag_garbage =       {name = 'Garbage Tag',      set = 'Tag', discovered = false, min_ante = 2,   order = 15, config = {type = 'immediate', dollars_per_discard = 1}, pos = {x = 2,y = 3}},
        tag_ethereal =      {name = 'Ethereal Tag',     set = 'Tag', discovered = false, min_ante = 2,   order = 16, config = {type = 'new_blind_choice'}, pos = {x = 3,y = 3}},
        tag_coupon =        {name = 'Coupon Tag',       set = 'Tag', discovered = false, min_ante = nil, order = 17, config = {type = 'shop_final_pass', }, pos = {x = 4,y = 0}},
        tag_double =        {name = 'Double Tag',       set = 'Tag', discovered = false, min_ante = nil, order = 18, config = {type = 'tag_add', }, pos = {x = 5,y = 0}},
        tag_juggle =        {name = 'Juggle Tag',       set = 'Tag', discovered = false, min_ante = nil, order = 19, config = {type = 'round_start_bonus', h_size = 3}, pos = {x = 5,y = 1}},
        tag_d_six =         {name = 'D6 Tag',           set = 'Tag', discovered = false, min_ante = nil, order = 20, config = {type = 'shop_start', }, pos = {x = 5,y = 3}},
        tag_top_up =        {name = 'Top-up Tag',       set = 'Tag', discovered = false, min_ante = 2,   order = 21, config = {type = 'immediate', spawn_jokers = 2}, pos = {x = 4,y = 1}},
        tag_skip =          {name = 'Skip Tag',         set = 'Tag', discovered = false, min_ante = nil, order = 22, config = {type = 'immediate', skip_bonus = 5}, pos = {x = 0,y = 3}},
        tag_orbital =       {name = 'Orbital Tag',      set = 'Tag', discovered = false, min_ante = 2,   order = 23, config = {type = 'immediate', levels = 3}, pos = {x = 5,y = 2}},
        tag_economy =       {name = 'Economy Tag',      set = 'Tag', discovered = false, min_ante = nil, order = 24, config = {type = 'immediate', max = 40}, pos = {x = 4,y = 3}},
    }
    self.tag_undiscovered = {name = 'Not Discovered', order = 1, config = {type = ''}, pos = {x=3,y=4}}

    self.P_STAKES = {
        stake_white =   {name = 'White Chip',   unlocked = true,  order = 1, pos = {x = 0,y = 0}, stake_level = 1, set = 'Stake'},
        stake_red =     {name = 'Red Chip',     unlocked = false, order = 2, pos = {x = 1,y = 0}, stake_level = 2, set = 'Stake'},
        stake_green =   {name = 'Green Chip',   unlocked = false, order = 3, pos = {x = 2,y = 0}, stake_level = 3, set = 'Stake'},  
        stake_black =   {name = 'Black Chip',   unlocked = false, order = 4, pos = {x = 4,y = 0}, stake_level = 4, set = 'Stake'},
        stake_blue =    {name = 'Blue Chip',    unlocked = false, order = 5, pos = {x = 3,y = 0}, stake_level = 5, set = 'Stake'},
        stake_purple =  {name = 'Purple Chip',  unlocked = false, order = 6, pos = {x = 0,y = 1}, stake_level = 6, set = 'Stake'},
        stake_orange =  {name = 'Orange Chip',  unlocked = false, order = 7, pos = {x = 1,y = 1}, stake_level = 7, set = 'Stake'},
        stake_gold =    {name = 'Gold Chip',    unlocked = false, order = 8, pos = {x = 2,y = 1}, stake_level = 8, set = 'Stake'},
    }

    self.P_BLINDS = {
        bl_small =           {name = 'Small Blind',  defeated = false, order = 1, dollars = 3, mult = 1,  vars = {}, debuff_text = '', debuff = {}, pos = 0},
        bl_big =             {name = 'Big Blind',    defeated = false, order = 2, dollars = 4, mult = 1.5,vars = {}, debuff_text = '', debuff = {}, pos = 1},
        bl_ox =              {name = 'The Ox',       defeated = false, order = 4, dollars = 5, mult = 2,  vars = {'ph_most_played'}, debuff = {}, pos = 2, boss = {min = 6, max = 10}, boss_colour = HEX('b95b08')},
        bl_hook =            {name = 'The Hook',     defeated = false, order = 3, dollars = 5, mult = 2,  vars = {}, debuff = {}, pos = 7, boss = {min = 1, max = 10}, boss_colour = HEX('a84024')},
        bl_mouth =           {name = 'The Mouth',    defeated = false, order = 17, dollars = 5, mult = 2, vars = {}, debuff = {}, pos = 18, boss = {min = 2, max = 10}, boss_colour = HEX('ae718e')},
        bl_fish =            {name = 'The Fish',     defeated = false, order = 10, dollars = 5, mult = 2, vars = {}, debuff = {}, pos = 5, boss = {min = 2, max = 10}, boss_colour = HEX('3e85bd')},
        bl_club =            {name = 'The Club',     defeated = false, order = 9, dollars = 5, mult = 2,  vars = {}, debuff = {suit = 'Clubs'}, pos = 4, boss = {min = 1, max = 10}, boss_colour = HEX('b9cb92')},
        bl_manacle =         {name = 'The Manacle',  defeated = false, order = 15, dollars = 5, mult = 2, vars = {}, debuff = {}, pos = 8, boss = {min = 1, max = 10}, boss_colour = HEX('575757')},
        bl_tooth =           {name = 'The Tooth',    defeated = false, order = 23, dollars = 5, mult = 2, vars = {}, debuff = {}, pos = 22, boss = {min = 3, max = 10}, boss_colour = HEX('b52d2d')},
        bl_wall =            {name = 'The Wall',     defeated = false, order = 6, dollars = 5, mult = 4,  vars = {}, debuff = {}, pos = 9, boss = {min = 2, max = 10}, boss_colour = HEX('8a59a5')},
        bl_house =           {name = 'The House',    defeated = false, order = 5, dollars = 5, mult = 2,  vars = {}, debuff = {}, pos = 3, boss ={min = 2, max = 10}, boss_colour = HEX('5186a8')},
        bl_mark =            {name = 'The Mark',     defeated = false, order = 25, dollars = 5, mult = 2, vars = {}, debuff = {}, pos = 23, boss = {min = 2, max = 10}, boss_colour = HEX('6a3847')},
        bl_final_bell =      {name = 'Cerulean Bell',defeated = false, order = 30, dollars = 8, mult = 2, vars = {}, debuff = {}, pos = 26, boss = {showdown = true, min = 10, max = 10}, boss_colour = HEX('009cfd')},
        bl_wheel =           {name = 'The Wheel',    defeated = false, order = 7, dollars = 5, mult = 2,  vars = {}, debuff = {}, pos = 10, boss = {min = 2, max = 10}, boss_colour = HEX('50bf7c')},
        bl_arm =             {name = 'The Arm',      defeated = false, order = 8, dollars = 5, mult = 2,  vars = {}, debuff = {}, pos = 11, boss = {min = 2, max = 10}, boss_colour = HEX('6865f3')},
        bl_psychic =         {name = 'The Psychic',  defeated = false, order = 11, dollars = 5, mult = 2, vars = {}, debuff = {h_size_ge = 5}, pos = 12, boss = {min = 1, max = 10}, boss_colour = HEX('efc03c')},
        bl_goad =            {name = 'The Goad',     defeated = false, order = 12, dollars = 5, mult = 2, vars = {}, debuff = {suit = 'Spades'}, pos = 13, boss = {min = 1, max = 10}, boss_colour = HEX('b95c96')},
        bl_water =           {name = 'The Water',    defeated = false, order = 13, dollars = 5, mult = 2, vars = {}, debuff = {}, pos = 14, boss = {min = 2, max = 10}, boss_colour = HEX('c6e0eb')},
        bl_eye =             {name = 'The Eye',      defeated = false, order = 16, dollars = 5, mult = 2, vars = {}, debuff = {}, pos = 17, boss = {min = 3, max = 10}, boss_colour = HEX('4b71e4')},
        bl_plant =           {name = 'The Plant',    defeated = false, order = 18, dollars = 5, mult = 2, vars = {}, debuff = {is_face = 'face'}, pos = 19, boss = {min = 4, max = 10}, boss_colour = HEX('709284')},
        bl_needle =          {name = 'The Needle',   defeated = false, order = 21, dollars = 5, mult = 1, vars = {}, debuff = {}, pos = 20, boss = {min = 2, max = 10}, boss_colour = HEX('5c6e31')},
        bl_head =            {name = 'The Head',     defeated = false, order = 22, dollars = 5, mult = 2, vars = {}, debuff = {suit = 'Hearts'}, pos = 21, boss = {min = 1, max = 10}, boss_colour = HEX('ac9db4')},
        bl_final_leaf =      {name = 'Verdant Leaf', defeated = false, order = 27, dollars = 8, mult = 2, vars = {}, debuff = {}, pos = 28, boss = {showdown = true, min = 10, max = 10}, boss_colour = HEX('56a786')},
        bl_final_vessel =    {name = 'Violet Vessel',defeated = false, order = 28, dollars = 8, mult = 6, vars = {}, debuff = {}, pos = 29, boss = {showdown = true, min = 10, max = 10}, boss_colour = HEX('8a71e1')},
        bl_window =          {name = 'The Window',   defeated = false, order = 14, dollars = 5, mult = 2, vars = {}, debuff = {suit = 'Diamonds'}, pos = 6, boss = {min = 1, max = 10}, boss_colour = HEX('a9a295')},
        bl_serpent =         {name = 'The Serpent',  defeated = false, order = 19, dollars = 5, mult = 2, vars = {}, debuff = {}, pos = 15, boss = {min = 5, max = 10}, boss_colour = HEX('439a4f')},
        bl_pillar =          {name = 'The Pillar',   defeated = false, order = 20, dollars = 5, mult = 2, vars = {}, debuff = {}, pos = 16, boss = {min = 1, max = 10}, boss_colour = HEX('7e6752')},
        bl_flint =           {name = 'The Flint',    defeated = false, order = 24, dollars = 5, mult = 2, vars = {}, debuff = {}, pos = 24, boss = {min = 2, max = 10}, boss_colour = HEX('e56a2f')},
        bl_final_acorn =     {name = 'Amber Acorn',  defeated = false, order = 26, dollars = 8, mult = 2, vars = {}, debuff = {}, pos = 27, boss = {showdown = true, min = 10, max = 10}, boss_colour = HEX('fda200')},
        bl_final_heart =     {name = 'Crimson Heart',defeated = false, order = 29, dollars = 8, mult = 2, vars = {}, debuff = {}, pos = 25, boss = {showdown = true, min = 10, max = 10}, boss_colour = HEX('ac3232')},
        
    }
end

function Game:draw()
    -- Dark panel behind the entire joker row (bottom screen).
    if self.jokers_on_bottom == true and self.jokers then
        local slot_count = self.joker_capacity or self.joker_slot_count or #self.jokers
        local slot_w = self.joker_slot_w or 71
        local slot_h = self.joker_slot_h or 95
        local slot_gap = self.joker_slot_gap or 8
        local s = self.joker_slot_scale_bottom or 1

        local total_w_base = slot_count * slot_w + (slot_count - 1) * slot_gap
        local panel_x = self.joker_slot_start_x_bottom or 0
        local panel_y = self.joker_slot_y_bottom or 20
        local panel_w = total_w_base * s
        local panel_h = slot_h * s

        -- Extra padding so jokers don't touch the panel edges.
        local panel_pad = 4
        local panel_pad_scaled = panel_pad * s
        panel_x = panel_x - panel_pad_scaled
        panel_y = panel_y - panel_pad_scaled
        panel_w = panel_w + (panel_pad_scaled * 2)
        panel_h = panel_h + (panel_pad_scaled * 2)

        local prev_r, prev_g, prev_b, prev_a = love.graphics.getColor()
        if _G.draw_rect_with_shadow then
            draw_rect_with_shadow(
                panel_x, panel_y, panel_w, panel_h,
                4, 2,
                G and G.C and G.C.BLOCK and G.C.BLOCK.BACK or { 0, 0, 0, 1 },
                G and G.C and G.C.BLOCK and G.C.BLOCK.SHADOW or { 0, 0, 0, 1 },
                2
            )
        else
            love.graphics.setColor(G and G.C and G.C.PANEL or { 0.2, 0.2, 0.2, 1 })
            love.graphics.rectangle("fill", panel_x, panel_y, panel_w, panel_h, 4, 4)
        end
        love.graphics.setColor(prev_r, prev_g, prev_b, prev_a)
    end

    for _, node in ipairs(self.nodes) do
        node:draw()
    end

    if self.STATE == self.STATES.BLIND_SELECT then
        self:draw_bottom_blind_select()
    elseif self.STATE == self.STATES.SHOP then
        self:draw_bottom_shop()
    end
end

function Game:_point_in_rect_simple(px, py, r)
    return r and px >= r.x and px <= (r.x + r.w) and py >= r.y and py <= (r.y + r.h)
end

function Game:draw_blind_chip_anim(blind_index, center_x, center_y, scale)
    local atlas = self.ANIMATION_ATLAS and self.ANIMATION_ATLAS.blind_chips
    if not atlas or not atlas.image then return end
    local cell_w = tonumber(atlas.px) or 36
    local cell_h = tonumber(atlas.py) or 36
    local frames_per_blind = tonumber(atlas.frames) or 1
    local blind_row = tonumber(self:get_blind_sprite_index(blind_index)) or 0
    local anim_fps = 10
    local t = love.timer.getTime()
    local frame = math.floor(t * anim_fps) % math.max(1, frames_per_blind)
    local sprite_index = (blind_row * frames_per_blind) + frame
    local iw, ih = atlas.image:getDimensions()
    local cols = math.max(1, math.floor(iw / cell_w))
    local total_cells = math.floor((iw / cell_w) * (ih / cell_h))
    if sprite_index >= total_cells then
        sprite_index = 0
    end
    local col = sprite_index % cols
    local row = math.floor(sprite_index / cols)
    local qx = col * cell_w
    local qy = row * cell_h
    local quad = love.graphics.newQuad(qx, qy, cell_w, cell_h, iw, ih)
    local s = scale or 1
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(atlas.image, quad, center_x - (cell_w * s * 0.5), center_y - (cell_h * s * 0.5), 0, s, s)
end

function Game:draw_bottom_blind_select()
    local card_w, card_h = 98, 300
    local gap = 8
    local start_x = 6
    local y = 8
    self._blind_select_tap_rects = {}
    for i = 1, 3 do
        local def = self:get_blind_def(i)
        local x = start_x + (i - 1) * (card_w + gap)
        local selectable = self:is_blind_selectable(i)
        local target = self:get_blind_target(i, self.ante)
        local card_color = self.C.PANEL
        if not selectable then
            y = 60
        else 
            y = 8
        end
        
        love.graphics.setColor(card_color)
        love.graphics.rectangle("fill", x, y, card_w, card_h, 4, 4)
        local blind_color = self:get_blind_color(i) or self.C.BLOCK.BACK
        love.graphics.setColor(blind_color)
        love.graphics.setLineWidth(3)
        love.graphics.rectangle("line", x, y, card_w, card_h, 4, 4)


        local padding = 16
        love.graphics.setLineWidth(2)
        love.graphics.setColor(self.C.GREY)
        love.graphics.rectangle("line", x + padding/2, y + padding/2, card_w - padding, 142, 4, 4)
        love.graphics.setLineWidth(1)


        local selectText = "Upcoming"
        if selectable then
            selectText = "Select"
        end
        local selectWidth = 60
        local selectHeight = 16
        local offset = 6
        local btn_x = x + math.floor(card_w / 2) - math.floor(selectWidth / 2)
        local btn_y = y + padding/2 + offset
        if selectable then
            draw_rect_with_shadow(btn_x, btn_y, selectWidth, selectHeight, 4, 4, self.C.ORANGE, self.C.BLOCK.SHADOW, 2)
        else
            draw_rect_with_shadow(btn_x, btn_y, selectWidth, selectHeight, 4, 4, self.C.GREY, self.C.BLOCK.SHADOW, 2)
        end
        self._blind_select_tap_rects[i] = { x = btn_x, y = btn_y, w = selectWidth, h = selectHeight }

        love.graphics.setColor(self.C.WHITE)
        love.graphics.setFont(self.FONTS.PIXEL.SMALL)
        local tx = x + math.floor(card_w / 2) - math.floor(love.graphics.getFont():getWidth(selectText) / 2)
        love.graphics.print(selectText, tx, btn_y + 2)

        local blindWidth = 70
        local label = self:get_blind_display_name(i)
        love.graphics.setColor(blind_color)
        tx = x + math.floor(card_w / 2) - math.floor(blindWidth / 2)
        love.graphics.rectangle("fill", tx, btn_y + selectHeight + 8, blindWidth, selectHeight, 4, 4)

        tx = x + math.floor(card_w / 2) - math.floor(love.graphics.getFont():getWidth(label) / 2)
        love.graphics.setColor(self.C.WHITE)
        love.graphics.print(label, tx, btn_y + selectHeight + 8 + 2)
        self:draw_blind_chip_anim(i, x + math.floor(card_w / 2), y + 80, 1.1)

        local scoreWidth = 78
        local scoreHeight = 28
        local reward = self:get_blind_reward(i)

        if reward > 0 then 
            scoreHeight = 44
        end
        love.graphics.setFont(self.FONTS.PIXEL.SMALL)
        love.graphics.setColor(self.C.BLOCK.BACK)
        tx = x + math.floor(card_w / 2) - math.floor(scoreWidth / 2)
        love.graphics.rectangle("fill", tx, y + 105, scoreWidth, scoreHeight, 4, 4)

        love.graphics.setColor(self.C.WHITE)
        ty = y + 108
        love.graphics.print("Score at Least", tx + 6, ty)
        love.graphics.setColor(self.C.RED)
        local req = tostring(target)
        local rx = x + math.floor(card_w / 2) - math.floor(love.graphics.getFont():getWidth(req) / 2)
        love.graphics.print(req, rx, ty + 12)
        
        love.graphics.setColor(self.C.WHITE)
        req = "Reward: "..string.rep("$", reward).."+"
        rx = x + math.floor(card_w / 2) - math.floor(love.graphics.getFont():getWidth(req) / 2)

        love.graphics.print("Reward: ", rx, ty + 24)
        love.graphics.setColor(self.C.MONEY)
        love.graphics.print("$"..string.rep("$", reward).."+", rx + love.graphics.getFont():getWidth("Reward: "), ty + 24)
        

        --[[ if not selectable then
            local grey = self.C.GREY
            local premultiplied_grey = {
                grey[1] * grey[4],
                grey[2] * grey[4],
                grey[3] * grey[4],
                grey[4] or 1
            }
            love.graphics.setBlendMode("multiply", "premultiplied")
            love.graphics.setColor(premultiplied_grey)
            love.graphics.setLineWidth(3)
            love.graphics.rectangle("fill", x, y, card_w, card_h, 4, 4)
            love.graphics.setBlendMode("alpha")
            love.graphics.setLineWidth(1)

        end ]]
    end
end

function Game:draw_bottom_shop()
    local panel_x, panel_y, panel_w, panel_h = 8, 8, 304, 124
    if _G.draw_rect_with_shadow then
        draw_rect_with_shadow(panel_x, panel_y, panel_w, panel_h, 4, 2, self.C.BLOCK.BACK, self.C.BLOCK.SHADOW, 2)
    else
        love.graphics.setColor(self.C.PANEL)
        love.graphics.rectangle("fill", panel_x, panel_y, panel_w, panel_h, 4, 4)
    end

    love.graphics.setColor(self.C.WHITE)
    love.graphics.setFont(self.FONTS.PIXEL.MEDIUM)
    love.graphics.print("Shop", panel_x + 8, panel_y + 4)
    love.graphics.setFont(self.FONTS.PIXEL.SMALL)
    love.graphics.print("Tap offer to buy | Tap owned joker to sell", panel_x + 8, panel_y + 22)

    self._shop_offer_rects = {}
    local offer_w, offer_h = 145, 34
    for i, offer in ipairs(self.shop_offers or {}) do
        local ox = panel_x + 8 + ((i - 1) * (offer_w + 6))
        local oy = panel_y + 42
        if _G.draw_rect_with_shadow then
            draw_rect_with_shadow(ox, oy, offer_w, offer_h, 3, 2, self.C.BLOCK.BACK, self.C.BLOCK.SHADOW, 2)
        else
            love.graphics.setColor(self.C.BLOCK.BACK)
            love.graphics.rectangle("fill", ox, oy, offer_w, offer_h, 3, 3)
        end
        love.graphics.setColor(self.C.WHITE)
        love.graphics.print(offer.name or "Joker", ox + 6, oy + 5)
        love.graphics.setColor(self.C.MONEY)
        love.graphics.print("$"..tostring(offer.price or 0), ox + 6, oy + 18)
        self._shop_offer_rects[i] = { x = ox, y = oy, w = offer_w, h = offer_h }
    end

    self._shop_owned_rects = {}
    local owned_y = panel_y + 84
    local owned_w, owned_h = 56, 26
    for i, j in ipairs(self.jokers or {}) do
        local ox = panel_x + 8 + ((i - 1) * (owned_w + 4))
        if ox + owned_w <= panel_x + panel_w - 8 then
            if _G.draw_rect_with_shadow then
                draw_rect_with_shadow(ox, owned_y, owned_w, owned_h, 3, 2, self.C.BLOCK.BACK, self.C.BLOCK.SHADOW, 2)
            else
                love.graphics.setColor(self.C.BLOCK.BACK)
                love.graphics.rectangle("fill", ox, owned_y, owned_w, owned_h, 3, 3)
            end
            love.graphics.setColor(self.C.WHITE)
            local short = (j.def and j.def.name) and string.sub(j.def.name, 1, 7) or "Joker"
            love.graphics.print(short, ox + 4, owned_y + 3)
            love.graphics.setColor(self.C.MONEY)
            love.graphics.print("$"..tostring(j.sell_value or 0), ox + 4, owned_y + 14)
            self._shop_owned_rects[i] = { x = ox, y = owned_y, w = owned_w, h = owned_h }
        end
    end

    self._shop_continue_rect = { x = panel_x + panel_w - 84, y = panel_y + panel_h - 24, w = 74, h = 18 }
    love.graphics.setColor(self.C.GREEN)
    love.graphics.rectangle("line", self._shop_continue_rect.x, self._shop_continue_rect.y, self._shop_continue_rect.w, self._shop_continue_rect.h, 3, 3)
    love.graphics.setColor(self.C.WHITE)
    love.graphics.print("Continue", self._shop_continue_rect.x + 10, self._shop_continue_rect.y + 4)
end

function Game:handle_blind_select_touch(x, y)
    for i, r in ipairs(self._blind_select_tap_rects or {}) do
        if self:_point_in_rect_simple(x, y, r) then
            if not self:is_blind_selectable(i) then
                return true
            end
            if self.selected_blind_index == i then
                self:start_selected_blind()
            else
                self.selected_blind_index = i
            end
            return true
        end
    end
    return false
end

function Game:handle_shop_touch(x, y)
    for i, r in ipairs(self._shop_offer_rects or {}) do
        if self:_point_in_rect_simple(x, y, r) then
            self:buy_shop_joker(i)
            return true
        end
    end
    for i, r in ipairs(self._shop_owned_rects or {}) do
        if self:_point_in_rect_simple(x, y, r) then
            self:sell_owned_joker(i)
            return true
        end
    end
    if self:_point_in_rect_simple(x, y, self._shop_continue_rect) then
        self:continue_from_shop()
        return true
    end
    return false
end

function Game:update(dt)
    self:_update_joker_emit_queue(dt)
    for _, node in ipairs(self.nodes) do
        if node.update then
            node:update(dt)
        end
    end
    if self.hand and self.hand.update then
        self.hand:update(dt)
    end
    self:check_collisions(dt)

    -- Determine whether the joker slide animation is still running.
    -- While sliding, guides should move with jokers; afterward, guides lock to slot geometry.
    if self.jokers_sliding == true then
        self.jokers_slide_time_left = (self.jokers_slide_time_left or 0) - dt
        local all_snapped = true
        if self.jokers then
            for _, j in ipairs(self.jokers) do
                if j and j.VT and j.T then
                    local dx = math.abs((j.VT.x or 0) - (j.T.x or 0))
                    local dy = math.abs((j.VT.y or 0) - (j.T.y or 0))
                    local ds = math.abs((j.VT.scale or 0) - (j.T.scale or 0))
                    if dx > 0.6 or dy > 0.6 or ds > 0.02 then
                        all_snapped = false
                        break
                    end
                end
            end
        end

        if all_snapped == true or (self.jokers_slide_time_left or 0) <= 0 then
            self.jokers_sliding = false
            self.jokers_slide_time_left = 0
        end
    end

    local removed_nodes = 0
    self.discard_timer = self.discard_timer + dt
    for i = #self.pending_discard, 1, -1 do
        local entry = self.pending_discard[i]
        if self.discard_timer >= entry.remove_after then
            self:remove(entry.node)
            table.remove(self.pending_discard, i)
            removed_nodes = removed_nodes + 1
        end
    end

    if removed_nodes > 0 then
        self._gc_discarded_nodes = self._gc_discarded_nodes + removed_nodes
        if self._gc_discarded_nodes >= 24 then
            self._gc_discarded_nodes = 0
            collectgarbage("collect")
        end
    end

    -- Small periodic incremental GC step to smooth frame spikes on 3DS.
    self._gc_timer = self._gc_timer + dt
    if self._gc_timer >= 0.2 then
        self._gc_timer = 0
        collectgarbage("step", 96)
    end
end

function Game:rects_overlap(a, b)
    return a.x < b.x + b.w and
           a.x + a.w > b.x and
           a.y < b.y + b.h and
           a.y + a.h > b.y
end

function Game:get_overlap(a, b)
    local ox = math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x)
    local oy = math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y)
    return ox, oy
end

function Game:check_collisions(dt)
    if not self.dragging then
        for _, node in ipairs(self.nodes) do
            if node.states then
                node.states.collide.is = false
            end
        end
        return
    end
    
    local collidables = self._collidables_buf
    for i = #collidables, 1, -1 do
        collidables[i] = nil
    end
    for _, node in ipairs(self.nodes) do
        if node.states and node.states.collide.can then
            table.insert(collidables, node)
        end
    end
    
    local nudge_strength = 200 * dt
    local deadzone = 3
    local max_overlap = 40

    local held = self.dragging
    local rect_held = held:get_collision_rect()

    for _, other in ipairs(collidables) do
        if other ~= held then
            local rect_other = other:get_collision_rect()

            if self:rects_overlap(rect_held, rect_other) then
                local ox, oy = self:get_overlap(rect_held, rect_other)
                local min_overlap = math.min(ox, oy)

                if min_overlap > max_overlap then
                    other.states.collide.is = false
                elseif min_overlap < deadzone then
                    other.states.collide.is = true
                else
                    other.states.collide.is = true

                    local center_hx = rect_held.x + rect_held.w / 2
                    local center_hy = rect_held.y + rect_held.h / 2
                    local center_ox = rect_other.x + rect_other.w / 2
                    local center_oy = rect_other.y + rect_other.h / 2

                    local dx = center_ox - center_hx
                    local dy = center_oy - center_hy

                    if ox < oy then
                        local nudge = (dx > 0 and 1 or -1) * nudge_strength
                        other.collision_offset.x = other.collision_offset.x + nudge
                    else
                        local nudge = (dy > 0 and 1 or -1) * nudge_strength
                        other.collision_offset.y = other.collision_offset.y + nudge
                    end
                end
            else
                other.states.collide.is = false
            end
        end
    end

    -- Decay offset so cards return to original position when collision ends
    for _, node in ipairs(collidables) do
        local decay = 5 * dt
        node.collision_offset.x = node.collision_offset.x * (1 - decay)
        node.collision_offset.y = node.collision_offset.y * (1 - decay)
    end
end

function Game:point_in_rect(px, py, node)
    local r = node.get_collision_rect and node:get_collision_rect() or nil
    if not r then
        local t = node.VT or node.T
        r = { x = t.x, y = t.y, w = t.w * t.scale, h = t.h * t.scale }
    end
    return px >= r.x and px <= r.x + r.w and py >= r.y and py <= r.y + r.h
end

function Game:get_node_at(x, y)
    for i = #self.nodes, 1, -1 do
        local node = self.nodes[i]
        if node.states and node.states.click.can and self:point_in_rect(x, y, node) then
            return node
        end
    end
    return nil
end

function Game:init_jokers()
    -- Owned Jokers live in `self.jokers` (packed left-to-right).
    -- `self.joker_capacity` defines the fixed UI slot count (panel size),
    -- and does NOT change the number of owned nodes.
    self.jokers = {}

    if not Joker then return end

    -- Capacity-first: start at 5 (you can modify later via gameplay).
    self.joker_capacity = self.joker_capacity or 5

    self.jokers_on_bottom = false
    self.jokers_sliding = false
    self.jokers_slide_time_left = 0

    -- Slot geometry is shared by both top- and bottom-screen placements.
    self.joker_slot_w, self.joker_slot_h = 71, 95
    self.joker_slot_gap = 8
    self.joker_slot_y_top = 124 -- under top HUD panel
    self.joker_slot_y_bottom = 20 -- above the hand fan on bottom screen

    -- Bottom screen is narrower than top in this project (hand uses 320 wide).
    local BOTTOM_SCREEN_W = 320
    local TOP_SCREEN_W = 400

    local slot_count = self.joker_capacity
    local base_total_w = slot_count * self.joker_slot_w + (slot_count - 1) * self.joker_slot_gap

    -- Top layout uses full scale (1.0) and centers within the top-screen width.
    local top_start_x = math.floor((TOP_SCREEN_W - base_total_w) * 0.5 + 0.5)
    if top_start_x < 0 then top_start_x = 0 end
    self.joker_slot_start_x = top_start_x

    -- Bottom layout centers and scales down to fit within the bottom-screen width.
    local bottom_scale = math.min(1, (BOTTOM_SCREEN_W or 320) / math.max(1, base_total_w))
    self.joker_slot_scale_bottom = bottom_scale

    local bottom_total_w = base_total_w * bottom_scale
    local bottom_start_x = math.floor((BOTTOM_SCREEN_W - bottom_total_w) * 0.5 + 0.5)
    if bottom_start_x < 0 then bottom_start_x = 0 end
    self.joker_slot_start_x_bottom = bottom_start_x

    -- Demo-owned jokers (randomized for testing).
    -- Replace this with your shop/buy system later.
    local pool = {}
    if JOKER_DEFS and type(JOKER_DEFS) == "table" then
        for def_id, _ in pairs(JOKER_DEFS) do
            pool[#pool + 1] = def_id
        end
    end

    -- -- Fisher–Yates shuffle
    -- for i = #pool, 2, -1 do
    --     local j = math.random(i)
    --     pool[i], pool[j] = pool[j], pool[i]
    -- end

    -- local want = math.min(self.joker_capacity or 0, #pool)
    -- for i = 1, want do
    --     self:add_joker_by_def(pool[i])
    -- end
    self:add_joker_by_def("j_mime")
    self:add_joker_by_def("j_banner")
    self:add_joker_by_def("j_mystic_summit")
    self:add_joker_by_def("j_clever")
    self:add_joker_by_def("j_gluttenous_joker")
end

---Add an owned Joker by definition id.
---Owned Jokers are packed left-to-right and never exceed `self.joker_capacity`.
---@param def_id string
---@return boolean
function Game:add_joker_by_def(def_id)
    if type(def_id) ~= "string" or def_id == "" then return false end
    if not JOKER_DEFS or type(JOKER_DEFS) ~= "table" then return false end
    local def = JOKER_DEFS[def_id]
    if type(def) ~= "table" then return false end

    if not self.joker_capacity then self.joker_capacity = 5 end
    if not self.jokers then self.jokers = {} end
    if #self.jokers >= self.joker_capacity then return false end

    -- Create at an arbitrary location; `_apply_joker_layout()` will position it.
    local j = Joker(0, 0, self.joker_slot_w, self.joker_slot_h, def, { face_up = true })
    table.insert(self.jokers, j)
    self:add(j)

    self:_apply_joker_layout()
    self:sync_jokers_interactivity()

    -- Snap immediately if we're not in a DPAD slide transition.
    if self.jokers_sliding ~= true then
        for _, jj in ipairs(self.jokers) do
            if jj and jj.VT and jj.T then
                jj.VT.x = jj.T.x
                jj.VT.y = jj.T.y
                jj.VT.scale = jj.T.scale
            end
        end
    end

    return true
end

function Game:_apply_joker_layout()
    if not self.jokers then return end

    if self.jokers_on_bottom == true then
        local s = self.joker_slot_scale_bottom or 1
        local start_x = self.joker_slot_start_x_bottom or 0
        local y = self.joker_slot_y_bottom

        -- Compensation because Joker scales around its center, which shifts
        -- the visible top-left when s != 1.
        local slot_w = self.joker_slot_w or 71
        local slot_h = self.joker_slot_h or 95
        local delta_x = (slot_w * s * (1 - s)) / 2
        local delta_y = (slot_h * s * (1 - s)) / 2

        -- We want the effective visible left/top edges to match:
        --   desired_left = start_x + (i-1)*step
        -- So set T.x/T.y to the draw coordinates that counteract that shift.

        for i, j in ipairs(self.jokers) do
            if j and j.T then
                local step = (slot_w + (self.joker_slot_gap or 0)) * s
                local desired_left = start_x + (i - 1) * step
                j.T.x = desired_left - delta_x
                j.T.y = y - delta_y
                j.T.scale = s
            end
        end
    else
        local s = 1
        local start_x = self.joker_slot_start_x or 0
        local y = self.joker_slot_y_top

        for i, j in ipairs(self.jokers) do
            if j and j.T then
                local step = (self.joker_slot_w + self.joker_slot_gap) * s
                j.T.x = start_x + (i - 1) * step
                j.T.y = y
                j.T.scale = s
            end
        end
    end
end

function Game:sync_jokers_interactivity()
    local on_bottom = self.jokers_on_bottom == true
    if not self.jokers then return end
    for _, j in ipairs(self.jokers) do
        if j and j.states then
            j.states.click.can = on_bottom
            j.states.drag.can = on_bottom
            -- Bottom screen draw path uses `j:draw()`, which checks `states.visible`.
            -- Top screen draw is handled by `TopUI.draw()` which temporarily overrides visibility.
            j.states.visible = on_bottom
        end
    end
end

--- Jokers in slot order (left-to-right) that match `event_name` and have `apply_effect`.
---@param event_name string
---@param ctx table
---@return table[]
function Game:collect_matching_jokers(event_name, ctx)
    local out = {}
    if not self.jokers or type(self.jokers) ~= "table" then return out end
    if type(event_name) ~= "string" or event_name == "" then return out end
    if type(ctx) ~= "table" then ctx = {} end

    for _, j in ipairs(self.jokers) do
        if j and j.matches_trigger and j:matches_trigger(event_name, ctx) and j.apply_effect then
            table.insert(out, j)
        end
    end
    -- Resolve left-to-right on screen (array order can diverge after drag-reorder).
    table.sort(out, function(a, b)
        local ax = (a.T and a.T.x) or (a.VT and a.VT.x) or 0
        local bx = (b.T and b.T.x) or (b.VT and b.VT.x) or 0
        return ax < bx
    end)
    return out
end

---Emit a joker event to all jokers and apply their effects to the context.
---`ctx` is a mutable table that joker effects can update (e.g. ctx.chips/ctx.mult).
---@param event_name string
---@param ctx table|nil
function Game:emit_joker_event(event_name, ctx)
    if not self.jokers or type(self.jokers) ~= "table" then return end
    if type(event_name) ~= "string" or event_name == "" then return end
    if type(ctx) ~= "table" then ctx = {} end

    for _, j in ipairs(self.jokers) do
        if j and j.matches_trigger and j:matches_trigger(event_name, ctx) then
            if j.apply_effect then
                j:apply_effect(ctx)
            end
        end
    end
end

function Game:_sync_joker_ctx(ctx)
    if type(ctx) ~= "table" then return end
    self.selectedHandChips = tonumber(ctx.chips) or self.selectedHandChips
    self.selectedHandMult = tonumber(ctx.mult) or self.selectedHandMult
end

--- True while a staggered joker batch (from `begin_joker_emit`) is still resolving.
function Game:joker_emit_busy()
    return self._joker_emit_queue ~= nil
end

--- Apply one joker from the stagger queue and sync chips/mult to `G`.
function Game:_apply_one_joker_emit()
    local q = self._joker_emit_queue
    if not q or type(q.list) ~= "table" then
        self._joker_emit_queue = nil
        self._joker_emit_timer = 0
        return
    end
    local j = q.list[self._joker_emit_next]
    if j and j.apply_effect then
        j:apply_effect(q.ctx)
    end
    self:_sync_joker_ctx(q.ctx)
    self._joker_emit_next = self._joker_emit_next + 1
    if self._joker_emit_next > #q.list then
        self._joker_emit_queue = nil
        self._joker_emit_timer = 0
    end
end

--- Resolve matching jokers left-to-right with a delay between each trigger (first applies immediately).
--- Returns true if any joker was queued (caller should wait until `joker_emit_busy()` is false).
---@param event_name string
---@param ctx table|nil
---@return boolean
function Game:begin_joker_emit(event_name, ctx)
    local list = self:collect_matching_jokers(event_name, ctx)
    if #list == 0 then return false end
    if type(ctx) ~= "table" then ctx = {} end
    self._joker_emit_queue = { list = list, ctx = ctx }
    self._joker_emit_next = 1
    self._joker_emit_timer = 0
    self:_apply_one_joker_emit()
    return true
end

function Game:_update_joker_emit_queue(dt)
    if not self._joker_emit_queue then return end
    self._joker_emit_timer = self._joker_emit_timer + dt
    local interval = tonumber(self.JOKER_EMIT_INTERVAL) or 0.18
    if self._joker_emit_timer >= interval then
        self._joker_emit_timer = 0
        self:_apply_one_joker_emit()
    end
end

--- End Round — call once when the current round finishes (e.g. blind beaten).
--- Discards the hand, merges draw + discard piles, shuffles into the draw pile, then refills the hand.
function Game:end_round()
    if self.hand and self.hand.send_entire_hand_to_discard_pile then
        self.hand:send_entire_hand_to_discard_pile()
    end
    local deck = self.deck
    if deck and deck.end_round then
        deck:end_round()
    end
    if self.hand and self.hand.fill_from_deck then
        self.hand:fill_from_deck()
    end
end

--- After beating a blind: return all cards to the deck and reshuffle; hand stays empty until the next blind starts.
function Game:recycle_full_deck_after_blind_win()
    if self.hand and self.hand.send_entire_hand_to_discard_pile then
        self.hand:send_entire_hand_to_discard_pile()
    end
    local deck = self.deck
    if deck and deck.end_round then
        deck:end_round()
    end
end

function Game:prepare_hand_for_new_blind()
    if not self.deck and Deck then
        self.deck = Deck()
    end
    if self.deck and self.deck.shuffle then
        self.deck:shuffle()
    end
    if not self.hand and Hand then
        self.hand = Hand(self)
    end
    if self.hand and self.hand.clear then
        self.hand:clear()
    end
    if self.hand and self.hand.fill_from_deck then
        self.hand:fill_from_deck()
    end
end

function Game:initialize_run_loop()
    self.STAGE = self.STAGES.RUN
    self.ante = 1
    self.round = 1
    self.money = 0
    self.hands = 5
    self.discards = 5
    self.round_score = 0
    self.last_hand_score = 0
    self.current_blind_index = 1
    self.selected_blind_index = 1
    self._blind_resolution_pending = false
    self.current_blind_target = 0
    self.current_blind_reward = 0
    self.current_blind_name = "Small Blind"
    self.shop_offers = {}
    self.shop_offer_cursor = 1
    self.shop_sell_cursor = 1
    if self.hand and self.hand.clear then
        self.hand:clear()
    end
    self:set_state(self.STATES.BLIND_SELECT)
end

function Game:enter_blind_select()
    self:set_state(self.STATES.BLIND_SELECT)
    self.selected_blind_index = self.current_blind_index or 1
    if self.selected_blind_index == 3 then
        self:roll_boss_blind()
    end
    self.round_score = 0
    self.last_hand_score = 0
    self.current_blind_target = 0
    self.current_blind_reward = 0
    self._blind_resolution_pending = false
    if self.hand and self.hand.clear then
        self.hand:clear()
    end
end

function Game:start_selected_blind()
    local idx = tonumber(self.selected_blind_index) or tonumber(self.current_blind_index) or 1
    if not self:is_blind_selectable(idx) then
        return false
    end
    local def = self:get_blind_def(idx)
    if not def then return false end

    self.current_blind_index = idx
    self.current_blind_target = self:get_blind_target(idx, self.ante)
    self.current_blind_reward = tonumber(def.reward) or 0
    self.current_blind_name = def.name or "Blind"
    if def.id == "boss" then
        local proto = self:get_boss_blind_prototype()
        if proto then
            self.current_blind_name = proto.name or self.current_blind_name
            self.current_blind_reward = tonumber(proto.dollars) or self.current_blind_reward
        end
    end
    self.hands = 5
    self.discards = 5
    self.round_score = 0
    self.last_hand_score = 0
    self._blind_resolution_pending = false
    self:prepare_hand_for_new_blind()
    self:set_state(self.STATES.SELECTING_HAND)
    return true
end

function Game:advance_after_shop()
    if self._last_completed_blind_was_boss then
        self.ante = (tonumber(self.ante) or 1) + 1
        self.current_blind_index = 1
    else
        self.current_blind_index = math.min(3, (tonumber(self.current_blind_index) or 1) + 1)
    end
    self.selected_blind_index = self.current_blind_index
    self.round = (tonumber(self.round) or 0) + 1
    self._last_completed_blind_was_boss = false
    self:enter_blind_select()
end

function Game:continue_from_shop()
    self:advance_after_shop()
end

function Game:_build_shop_pool()
    local pool = {}
    if type(JOKER_DEFS) ~= "table" then return pool end
    local owned = {}
    for _, j in ipairs(self.jokers or {}) do
        if j and j.def and j.def.id then
            owned[j.def.id] = true
        end
    end
    for id, def in pairs(JOKER_DEFS) do
        if type(def) == "table" and owned[id] ~= true then
            pool[#pool + 1] = id
        end
    end
    for i = #pool, 2, -1 do
        local j = math.random(i)
        pool[i], pool[j] = pool[j], pool[i]
    end
    return pool
end

function Game:roll_shop_offers()
    local pool = self:_build_shop_pool()
    self.shop_offers = {}
    local max_offers = math.min(2, #pool)
    for i = 1, max_offers do
        local id = pool[i]
        local def = JOKER_DEFS[id]
        local sell_value = tonumber(def and def.sell_value) or 1
        self.shop_offers[#self.shop_offers + 1] = {
            id = id,
            name = def and def.name or id,
            price = math.max(3, math.floor(sell_value * 2)),
            sell_value = sell_value
        }
    end
    self.shop_offer_cursor = 1
    self.shop_sell_cursor = math.min(1, #self.jokers or 0)
end

function Game:enter_shop_after_blind()
    self:recycle_full_deck_after_blind_win()
    self.money = (tonumber(self.money) or 0) + (tonumber(self.current_blind_reward) or 0)
    self:set_state(self.STATES.SHOP)
    self:roll_shop_offers()
end

function Game:remove_owned_joker_at(index)
    if type(index) ~= "number" or index < 1 then return nil end
    if type(self.jokers) ~= "table" then return nil end
    local joker = self.jokers[index]
    if not joker then return nil end
    table.remove(self.jokers, index)
    self:remove(joker)
    self:_apply_joker_layout()
    self:sync_jokers_interactivity()
    return joker
end

function Game:buy_shop_joker(slot_index)
    local offer = self.shop_offers and self.shop_offers[slot_index]
    if not offer then return false end
    if (tonumber(self.money) or 0) < (tonumber(offer.price) or 0) then return false end
    if #self.jokers >= (self.joker_capacity or 5) then return false end
    if not self:add_joker_by_def(offer.id) then return false end
    self.money = self.money - offer.price
    table.remove(self.shop_offers, slot_index)
    if self.shop_offer_cursor > #self.shop_offers then
        self.shop_offer_cursor = math.max(1, #self.shop_offers)
    end
    self.shop_sell_cursor = math.max(1, math.min(self.shop_sell_cursor, #self.jokers))
    return true
end

function Game:sell_owned_joker(index)
    local joker = self:remove_owned_joker_at(index)
    if not joker then return false end
    local value = tonumber(joker.sell_value) or tonumber(joker.def and joker.def.sell_value) or 0
    self.money = (tonumber(self.money) or 0) + value
    self.shop_sell_cursor = math.max(1, math.min(self.shop_sell_cursor, #self.jokers))
    return true
end

function Game:evaluate_blind_progress()
    if self.STATE ~= self.STATES.SELECTING_HAND then
        return
    end
    if self._blind_resolution_pending then
        return
    end
    local target = tonumber(self.current_blind_target) or 0
    local score = tonumber(self.round_score) or 0
    if score >= target and target > 0 then
        self._blind_resolution_pending = true
        self._last_completed_blind_was_boss = (self.current_blind_index == 3)
        self:enter_shop_after_blind()
        return
    end
    if (tonumber(self.hands) or 0) <= 0 and score < target then
        self._blind_resolution_pending = true
        self:handle_failed_blind_reset()
    end
end

function Game:handle_failed_blind_reset()
    self:set_state(self.STATES.GAME_OVER)
    self:initialize_run_loop()
end

function Game:set_jokers_location(on_bottom)
    if self.jokers_on_bottom == (on_bottom == true) then return end
    local from_bottom = self.jokers_on_bottom == true
    local to_bottom = on_bottom == true

    self.jokers_on_bottom = to_bottom
    self:sync_jokers_interactivity()

    -- Update target transforms first.
    self:_apply_joker_layout()

    -- Guide rectangles should move with jokers during this transition.
    -- They'll lock back to stationary slot geometry once the jokers snap.
    self.jokers_sliding = true
    self.jokers_slide_time_left = 0.6

    -- Then force VT to the previous layout so the slide always starts
    -- from a consistent top/bottom position (independent of prior VT drift).
    if self.jokers then
        local start_y
        if to_bottom then
            -- Start above the bottom screen so it feels like sliding down from the top.
            local s = self.joker_slot_scale_bottom or 1
            local slot_h = self.joker_slot_h or 95
            local h = slot_h * s
            local delta_y = (slot_h * s * (1 - s)) / 2
            start_y = -(h + 60) - delta_y -- guaranteed < 0 (effective visible)
        else
            -- Start below the bottom slots so it feels like sliding up.
            local s = self.joker_slot_scale_bottom or 1
            local slot_h = self.joker_slot_h or 95
            local h = slot_h * s
            local delta_y = (slot_h * s * (1 - s)) / 2
            start_y = (self.joker_slot_y_bottom or 20) + h + 60 - delta_y
        end

        for i, j in ipairs(self.jokers) do
            if j and j.VT then
                -- Keep VT centered and sized like the final slot;
                -- this prevents extra horizontal/scale drift during the slide.
                if j.T then
                    j.VT.x = j.T.x
                    j.VT.scale = j.T.scale
                end
                j.VT.y = start_y
            end
        end
    end
end

function Game:_joker_nearest_slot_idx(release_x)
    local owned_count = self.jokers and #self.jokers or 0
    if owned_count <= 0 then return 1 end

    if self.jokers_on_bottom == true then
        local s = self.joker_slot_scale_bottom or 1
        local start_x = self.joker_slot_start_x_bottom or 0
        local step = (self.joker_slot_w + self.joker_slot_gap) * s
        local slot_w_scaled = self.joker_slot_w * s
        local best_i, best_d = 1, 1e9
        for i = 1, owned_count do
            local cx = start_x + (i - 1) * step + slot_w_scaled / 2
            local d = math.abs(release_x - cx)
            if d < best_d then
                best_d = d
                best_i = i
            end
        end
        return best_i
    end

    local best_i, best_d = 1, 1e9
    for i = 1, owned_count do
        local cx = self.joker_slot_start_x + (i - 1) * (self.joker_slot_w + self.joker_slot_gap) + self.joker_slot_w / 2
        local d = math.abs(release_x - cx)
        if d < best_d then
            best_d = d
            best_i = i
        end
    end
    return best_i
end

function Game:try_reorder_joker_after_drag(joker_node, release_x)
    if not joker_node or not self.jokers or not self.jokers_on_bottom then return false end

    local from_idx
    for i, j in ipairs(self.jokers) do
        if j == joker_node then
            from_idx = i
            break
        end
    end
    if not from_idx then return false end

    local to_idx = self:_joker_nearest_slot_idx(release_x)
    if to_idx == from_idx then return false end

    local reordered = false
    local node = table.remove(self.jokers, from_idx)
    table.insert(self.jokers, to_idx, node)
    reordered = true

    -- Update target positions to reflect new slot order.
    self:_apply_joker_layout()

    -- Snap immediately to avoid visible overshoot beyond the bottom screen.
    -- We only do this when the slide transition is not active.
    if self.jokers_sliding ~= true then
        for _, j in ipairs(self.jokers) do
            if j and j.VT and j.T then
                j.VT.x = j.T.x
                j.VT.y = j.T.y
                j.VT.scale = j.T.scale
            end
        end
    end
    return reordered
end

function Game:move_to_front(node)
    for i, n in ipairs(self.nodes) do
        if n == node then
            table.remove(self.nodes, i)
            table.insert(self.nodes, node)
            return
        end
    end
end

local TAP_THRESHOLD = 15

function Game:touchpressed(id, x, y)
    if self.STATE == self.STATES.BLIND_SELECT then
        self:handle_blind_select_touch(x, y)
        return
    end
    if self.STATE == self.STATES.SHOP then
        self:handle_shop_touch(x, y)
        return
    end
    if self.STATE ~= self.STATES.SELECTING_HAND then return end
    if self.hand and self.hand.is_scoring_active and self.hand:is_scoring_active() then return end
    self.touch_start_x = x
    self.touch_start_y = y
    local node = self:get_node_at(x, y)
    if node and node.touchpressed then
        node:touchpressed(id, x, y)
        self.dragging = node
        self:move_to_front(node)
    end
end

function Game:touchmoved(id, x, y, dx, dy)
    if self.STATE == self.STATES.BLIND_SELECT or self.STATE == self.STATES.SHOP then return end
    if self.STATE ~= self.STATES.SELECTING_HAND then return end
    if self.hand and self.hand.is_scoring_active and self.hand:is_scoring_active() then return end
    if self.dragging and self.dragging.touchmoved then
        self.dragging:touchmoved(id, x, y, dx, dy)
    end
end

function Game:touchreleased(id, x, y)
    if self.STATE == self.STATES.BLIND_SELECT or self.STATE == self.STATES.SHOP then
        self.dragging = nil
        return
    end
    if self.STATE ~= self.STATES.SELECTING_HAND then
        self.dragging = nil
        return
    end
    if self.hand and self.hand.is_scoring_active and self.hand:is_scoring_active() then
        self.dragging = nil
        return
    end
    local released = self.dragging
    if released and released.touchreleased then
        released:touchreleased(id, x, y)
    end
    local dx = x - self.touch_start_x
    local dy = y - self.touch_start_y
    local dist = math.sqrt(dx * dx + dy * dy)
    local reordered = false

    -- Joker reordering (bottom screen only).
    if released and self.jokers and self.jokers_on_bottom then
        local rmin = self.joker_reorder_drag_threshold and self.joker_reorder_drag_threshold() or 22
        if dist >= rmin then
            reordered = self:try_reorder_joker_after_drag(released, x) or false
        end
    end

    if released and self.hand and self.hand.try_reorder_card_after_drag then
        local rmin = self.hand.reorder_drag_threshold and self.hand:reorder_drag_threshold() or 22
        if dist >= rmin then
            for _, node in ipairs(self.hand.card_nodes) do
                if node == released then
                    reordered = self.hand:try_reorder_card_after_drag(node, x)
                    break
                end
            end
        end
    end
    if released and self.hand and not reordered and dist < TAP_THRESHOLD then
        for _, node in ipairs(self.hand.card_nodes) do
            if node == released then
                self.hand:toggle_selection(node)
                break
            end
        end
    end
    if not released and dist < TAP_THRESHOLD then
        self.active_tooltip_card = nil
    end
    self.dragging = nil
    if released and self.hand then
        for _, node in ipairs(self.hand.card_nodes) do
            if node == released then
                self:restore_hand_draw_order()
                break
            end
        end
    end
end

function Game:restore_hand_draw_order()
    if not self.hand or #self.hand.card_nodes == 0 then return end
    local hand_set = {}
    for _, node in ipairs(self.hand.card_nodes) do
        hand_set[node] = true
    end
    local ordered = {}
    for _, node in ipairs(self.nodes) do
        if not hand_set[node] then
            table.insert(ordered, node)
        end
    end
    for _, node in ipairs(self.hand.card_nodes) do
        table.insert(ordered, node)
    end
    self.nodes = ordered
end

--- Puts selected hand cards at the end of the draw list so they render on top.
function Game:move_selected_hand_cards_to_front()
    if not self.hand or #self.hand.selected == 0 then return end
    local sel = {}
    for _, n in ipairs(self.hand.selected) do sel[n] = true end
    local ordered = {}
    for _, node in ipairs(self.nodes) do
        if not sel[node] then
            table.insert(ordered, node)
        end
    end
    for _, node in ipairs(self.hand.selected) do
        table.insert(ordered, node)
    end
    self.nodes = ordered
end

function Game:ensure_asset_atlas_loaded(name)
    if not name or not self.ASSET_ATLAS then return nil end
    local atlas = self.ASSET_ATLAS[name]
    if not atlas then return nil end
    if atlas.image then return atlas end
    if not atlas.path then return atlas end

    local ok, img = pcall(love.graphics.newImage, atlas.path, { dpiscale = atlas.dpiscale or self.SETTINGS.GRAPHICS.texture_scaling })
    if not ok then
        ok, img = pcall(love.graphics.newImage, atlas.path, {})
    end
    atlas.image = ok and img or nil
    return atlas
end

function Game:set_render_settings()
    self.SETTINGS.GRAPHICS.texture_scaling = self.SETTINGS.GRAPHICS.texture_scaling or 1

    love.graphics.setDefaultFilter(
        self.SETTINGS.GRAPHICS.texture_scaling == 1 and 'nearest' or 'linear',
        self.SETTINGS.GRAPHICS.texture_scaling == 1 and 'nearest' or 'linear', 1
    )
    love.graphics.setLineStyle("rough")

        --spritesheets
        self.animation_atli = {
            {name = "blind_chips", path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/BlindChips.png",px=36,py=36, frames = 21},
            {name = "shop_sign", path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/ShopSignAnimation.png",px=113,py=60, frames = 4}
        }
        self.asset_atli = {
            {name = "cards_1", path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/8BitDeck.png",px=72,py=95},
            {name = "cards_2", path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/8BitDeck_opt2.png",px=72,py=95},
            {name = "centers", path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/Enhancers.png",px=72,py=95},
            {name = "Joker1", path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/Jokers1.png",px=71,py=95},
            {name = "Joker2", path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/Jokers2.png",px=71,py=95},
            {name = "Tarot", path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/Tarots.png",px=72,py=95},
            {name = "Voucher", path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/Vouchers.png",px=72,py=95},
            {name = "Booster", path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/boosters.png",px=72,py=95},
            {name = "ui_1", path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/ui_assets.png",px=18,py=18},
            {name = "ui_2", path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/ui_assets_opt2.png",px=18,py=18},
            {name = "balatro", path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/balatro.png",px=336,py=216},        
            {name = 'gamepad_ui', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/gamepad_ui.png",px=32,py=32},
            {name = 'icons', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/icons.png",px=66,py=66},
            {name = 'tags', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/tags.png",px=34,py=34},
            {name = 'stickers', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/stickers.png",px=72,py=95},
            {name = 'chips', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/chips.png",px=30,py=30},
    
            --[[ {name = 'collab_AU_1', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_AU_1.png",px=71,py=95},
            {name = 'collab_AU_2', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_AU_2.png",px=71,py=95},
            {name = 'collab_TW_1', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_TW_1.png",px=71,py=95},
            {name = 'collab_TW_2', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_TW_2.png",px=71,py=95},
            {name = 'collab_VS_1', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_VS_1.png",px=71,py=95},
            {name = 'collab_VS_2', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_VS_2.png",px=71,py=95},
            {name = 'collab_DTD_1', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_DTD_1.png",px=71,py=95},
            {name = 'collab_DTD_2', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_DTD_2.png",px=71,py=95},
    
            {name = 'collab_CYP_1', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_CYP_1.png",px=71,py=95},
            {name = 'collab_CYP_2', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_CYP_2.png",px=71,py=95},
            {name = 'collab_STS_1', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_STS_1.png",px=71,py=95},
            {name = 'collab_STS_2', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_STS_2.png",px=71,py=95},
            {name = 'collab_TBoI_1', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_TBoI_1.png",px=71,py=95},
            {name = 'collab_TBoI_2', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_TBoI_2.png",px=71,py=95},
            {name = 'collab_SV_1', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_SV_1.png",px=71,py=95},
            {name = 'collab_SV_2', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_SV_2.png",px=71,py=95},
            
            {name = 'collab_SK_1', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_SK_1.png",px=71,py=95},
            {name = 'collab_SK_2', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_SK_2.png",px=71,py=95},
            {name = 'collab_DS_1', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_DS_1.png",px=71,py=95},
            {name = 'collab_DS_2', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_DS_2.png",px=71,py=95},
            {name = 'collab_CL_1', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_CL_1.png",px=71,py=95},
            {name = 'collab_CL_2', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_CL_2.png",px=71,py=95},
            {name = 'collab_D2_1', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_D2_1.png",px=71,py=95},
            {name = 'collab_D2_2', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_D2_2.png",px=71,py=95},
            {name = 'collab_PC_1', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_PC_1.png",px=71,py=95},
            {name = 'collab_PC_2', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_PC_2.png",px=71,py=95},
            {name = 'collab_WF_1', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_WF_1.png",px=71,py=95},
            {name = 'collab_WF_2', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_WF_2.png",px=71,py=95},
            {name = 'collab_EG_1', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_EG_1.png",px=71,py=95},
            {name = 'collab_EG_2', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_EG_2.png",px=71,py=95},
            {name = 'collab_XR_1', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_XR_1.png",px=71,py=95},
            {name = 'collab_XR_2', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_XR_2.png",px=71,py=95},
    
            {name = 'collab_CR_1', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_CR_1.png",px=71,py=95},
            {name = 'collab_CR_2', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_CR_2.png",px=71,py=95},
            {name = 'collab_BUG_1', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_BUG_1.png",px=71,py=95},
            {name = 'collab_BUG_2', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_BUG_2.png",px=71,py=95},
            {name = 'collab_FO_1', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_FO_1.png",px=71,py=95},
            {name = 'collab_FO_2', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_FO_2.png",px=71,py=95},
            {name = 'collab_DBD_1', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_DBD_1.png",px=71,py=95},
            {name = 'collab_DBD_2', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_DBD_2.png",px=71,py=95},
            {name = 'collab_C7_1', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_C7_1.png",px=71,py=95},
            {name = 'collab_C7_2', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_C7_2.png",px=71,py=95},
            {name = 'collab_R_1', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_R_1.png",px=71,py=95},
            {name = 'collab_R_2', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_R_2.png",px=71,py=95},
            {name = 'collab_AC_1', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_AC_1.png",px=71,py=95},
            {name = 'collab_AC_2', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_AC_2.png",px=71,py=95},
            {name = 'collab_STP_1', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_STP_1.png",px=71,py=95},
            {name = 'collab_STP_2', path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/collabs/collab_STP_2.png",px=71,py=95}, ]]
        }
        self.asset_images = {
            {name = "playstack_logo", path = "resources/textures/1x/playstack-logo.png", px=1416,py=1416},
            {name = "localthunk_logo", path = "resources/textures/1x/localthunk-logo.png", px=1390,py=560}
        }
    
        -- Helper: load image with no mipmaps for pixel-art memory savings.
        local function load_image(path, options)
            local ok, img = pcall(love.graphics.newImage, path, options or {})
            if not ok and options and options.dpiscale then
                ok, img = pcall(love.graphics.newImage, path, {})
            end
            return ok and img or nil
        end

        -- Animation atlases are small; load eagerly (no mipmaps).
        for i=1, #self.animation_atli do
            self.ANIMATION_ATLAS[self.animation_atli[i].name] = {}
            self.ANIMATION_ATLAS[self.animation_atli[i].name].name = self.animation_atli[i].name
            self.ANIMATION_ATLAS[self.animation_atli[i].name].path = self.animation_atli[i].path
            self.ANIMATION_ATLAS[self.animation_atli[i].name].image = load_image(self.animation_atli[i].path, {dpiscale = self.SETTINGS.GRAPHICS.texture_scaling})
            self.ANIMATION_ATLAS[self.animation_atli[i].name].px = self.animation_atli[i].px
            self.ANIMATION_ATLAS[self.animation_atli[i].name].py = self.animation_atli[i].py
            self.ANIMATION_ATLAS[self.animation_atli[i].name].frames = self.animation_atli[i].frames
        end

        -- Register all asset atlases, lazy-load textures on first use.
        for i=1, #self.asset_atli do
            self.ASSET_ATLAS[self.asset_atli[i].name] = {}
            self.ASSET_ATLAS[self.asset_atli[i].name].name = self.asset_atli[i].name
            self.ASSET_ATLAS[self.asset_atli[i].name].path = self.asset_atli[i].path
            self.ASSET_ATLAS[self.asset_atli[i].name].dpiscale = self.SETTINGS.GRAPHICS.texture_scaling
            self.ASSET_ATLAS[self.asset_atli[i].name].image = nil
            self.ASSET_ATLAS[self.asset_atli[i].name].type = self.asset_atli[i].type
            self.ASSET_ATLAS[self.asset_atli[i].name].px = self.asset_atli[i].px
            self.ASSET_ATLAS[self.asset_atli[i].name].py = self.asset_atli[i].py
        end
        for i=1, #self.asset_images do
            self.ASSET_ATLAS[self.asset_images[i].name] = {}
            self.ASSET_ATLAS[self.asset_images[i].name].name = self.asset_images[i].name
            self.ASSET_ATLAS[self.asset_images[i].name].path = self.asset_images[i].path
            self.ASSET_ATLAS[self.asset_images[i].name].dpiscale = 1
            self.ASSET_ATLAS[self.asset_images[i].name].image = nil
            self.ASSET_ATLAS[self.asset_images[i].name].type = self.asset_images[i].type
            self.ASSET_ATLAS[self.asset_images[i].name].px = self.asset_images[i].px
            self.ASSET_ATLAS[self.asset_images[i].name].py = self.asset_images[i].py
        end

        -- Preload only the atlases needed for the current core gameplay path.
        local preload_atlases = {
            "cards_1", "cards_2", "centers", "ui_1", "ui_2", "chips", "balatro"
        }
        for i = 1, #preload_atlases do
            self:ensure_asset_atlas_loaded(preload_atlases[i])
        end

        -- Aliases (point at same table; lazy loading still applies).
        self.ASSET_ATLAS.Planet = self.ASSET_ATLAS.Tarot
        self.ASSET_ATLAS.Spectral = self.ASSET_ATLAS.Tarot

        for _, v in pairs(G.I.SPRITE) do
            v:reset()
        end
end
