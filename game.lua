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

    -- Pull all shared globals from globals.lua
    if self.set_globals then
        self:set_globals()
    end

    if seed ~= nil then
        self.SEED = seed
    end
    math.randomseed(self.SEED)

    -- set filters and load atlases
    self:set_render_settings()
end

function Game:add(node)
    table.insert(self.nodes, node)
    return node
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

function Game:draw()
    for _, node in ipairs(self.nodes) do
        node:draw()
    end
end

function Game:update(dt)
    for _, node in ipairs(self.nodes) do
        if node.update then
            node:update(dt)
        end
    end
    if self.hand and self.hand.update then
        self.hand:update(dt)
    end
    self:check_collisions(dt)

    self.discard_timer = self.discard_timer + dt
    for i = #self.pending_discard, 1, -1 do
        local entry = self.pending_discard[i]
        if self.discard_timer >= entry.remove_after then
            self:remove(entry.node)
            table.remove(self.pending_discard, i)
        end
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
    
    local collidables = {}
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
    if self.dragging and self.dragging.touchmoved then
        self.dragging:touchmoved(id, x, y, dx, dy)
    end
end

function Game:touchreleased(id, x, y)
    local released = self.dragging
    if released and released.touchreleased then
        released:touchreleased(id, x, y)
    end
    local dx = x - self.touch_start_x
    local dy = y - self.touch_start_y
    local dist = math.sqrt(dx * dx + dy * dy)
    if released and self.hand and dist < TAP_THRESHOLD then
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
            {name = "Joker", path = "resources/textures/"..self.SETTINGS.GRAPHICS.texture_scaling.."x/Jokers.png",px=64,py=85},
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
    
        -- Helper: load image; on 3DS mipmaps/dpiscale can cause "Failed to create Texture", so retry with no options
        local function load_image(path, options)
            local ok, img = pcall(love.graphics.newImage, path, options or {})
            if not ok and options and (options.mipmaps or options.dpiscale) then
                ok, img = pcall(love.graphics.newImage, path, {})
            end
            return ok and img or nil
        end

        --Load in all atli defined above
        for i=1, #self.animation_atli do
            self.ANIMATION_ATLAS[self.animation_atli[i].name] = {}
            self.ANIMATION_ATLAS[self.animation_atli[i].name].name = self.animation_atli[i].name
            self.ANIMATION_ATLAS[self.animation_atli[i].name].image = load_image(self.animation_atli[i].path, {mipmaps = true, dpiscale = self.SETTINGS.GRAPHICS.texture_scaling})
            self.ANIMATION_ATLAS[self.animation_atli[i].name].px = self.animation_atli[i].px
            self.ANIMATION_ATLAS[self.animation_atli[i].name].py = self.animation_atli[i].py
            self.ANIMATION_ATLAS[self.animation_atli[i].name].frames = self.animation_atli[i].frames
        end
    
        for i=1, #self.asset_atli do
            self.ASSET_ATLAS[self.asset_atli[i].name] = {}
            self.ASSET_ATLAS[self.asset_atli[i].name].name = self.asset_atli[i].name
            self.ASSET_ATLAS[self.asset_atli[i].name].image = load_image(self.asset_atli[i].path, {mipmaps = true, dpiscale = self.SETTINGS.GRAPHICS.texture_scaling})
            self.ASSET_ATLAS[self.asset_atli[i].name].type = self.asset_atli[i].type
            self.ASSET_ATLAS[self.asset_atli[i].name].px = self.asset_atli[i].px
            self.ASSET_ATLAS[self.asset_atli[i].name].py = self.asset_atli[i].py
        end
        for i=1, #self.asset_images do
            self.ASSET_ATLAS[self.asset_images[i].name] = {}
            self.ASSET_ATLAS[self.asset_images[i].name].name = self.asset_images[i].name
            self.ASSET_ATLAS[self.asset_images[i].name].image = load_image(self.asset_images[i].path, {mipmaps = true, dpiscale = 1})
            self.ASSET_ATLAS[self.asset_images[i].name].type = self.asset_images[i].type
            self.ASSET_ATLAS[self.asset_images[i].name].px = self.asset_images[i].px
            self.ASSET_ATLAS[self.asset_images[i].name].py = self.asset_images[i].py
        end
    
        for _, v in pairs(G.I.SPRITE) do
            v:reset()
        end
    
        self.ASSET_ATLAS.Planet = self.ASSET_ATLAS.Tarot
        self.ASSET_ATLAS.Spectral = self.ASSET_ATLAS.Tarot
    
end
