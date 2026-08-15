--- Draggable shop booster / voucher nodes (Moveable, not full Joker/Consumable).
local ShopUI = require("shop_ui")

--- Apply the motion tilt Moveable keeps in VT.r, the same way Card and Joker do.
--- Without this these nodes slide around perfectly upright while every other
--- draggable leans into the drag.
local function push_tilt(node, x, y, w, h)
    love.graphics.push()
    local cx = x + w * 0.5
    local cy = y + h * 0.5
    love.graphics.translate(cx, cy)
    love.graphics.rotate(node.VT.r or 0)
    love.graphics.translate(-cx, -cy)
end

---@class ShopBoosterNode : Moveable
ShopBoosterNode = Moveable:extend()

-- Sizes itself off VT.x/VT.y as a top-left origin rather than scaling about
-- its centre, so the shop pop-in has to compensate. See ShopUI apply_pop_in.
ShopBoosterNode.pop_anchor_topleft = true

function ShopBoosterNode:init(x, y, w, h, offer, slot_index)
    ShopBoosterNode.super.init(self, x, y, w, h)
    self.shop_booster_slot = slot_index
    self.shop_booster_offer = offer
    self.T.x = x
    self.T.y = y
    self.VT.x = x
    self.VT.y = y
    self.states.visible = true
    self.states.click.can = true
    self.states.drag.can = true
end

function ShopBoosterNode:draw()
    if not self.states.visible then return end
    local offer = self.shop_booster_offer
    if type(offer) ~= "table" then return end
    local scale = self.VT.scale or self.T.scale or 1
    local x, y = self.VT.x, self.VT.y
    local w = (self.T.w or 72) * scale
    local h = (self.T.h or 95) * scale
    local idx = tonumber(offer.booster_sprite_index) or 0
    local game = G
    if not game then return end
    local rect = { x = x, y = y, w = w, h = h }
    push_tilt(self, x, y, w, h)
    if not ShopUI.draw_booster_atlas_frame(game, rect, idx) then
        love.graphics.setColor((game.C and game.C.BOOSTER) or { 0.4, 0.43, 0.72 })
        love.graphics.rectangle("fill", x, y, w, h, 3, 3)
        love.graphics.setColor(1, 1, 1, 1)
    end
    love.graphics.pop()
    if game.draw_node_gamepad_focus_outline then
        game:draw_node_gamepad_focus_outline(self)
    end
end

---@class ShopVoucherNode : Moveable
ShopVoucherNode = Moveable:extend()

ShopVoucherNode.pop_anchor_topleft = true

function ShopVoucherNode:init(x, y, w, h, offer, slot_index)
    ShopVoucherNode.super.init(self, x, y, w, h)
    self.shop_voucher_slot = slot_index
    self.shop_voucher_offer = offer
    self.T.x = x
    self.T.y = y
    self.VT.x = x
    self.VT.y = y
    self.states.visible = true
    self.states.click.can = true
    self.states.drag.can = true
end

function ShopVoucherNode:draw()
    if not self.states.visible then return end
    local offer = self.shop_voucher_offer
    if type(offer) ~= "table" then return end
    local scale = self.VT.scale or self.T.scale or 1
    local x, y = self.VT.x, self.VT.y
    local w = (self.T.w or 72) * scale
    local h = (self.T.h or 95) * scale
    local game = G
    if not game then return end
    local def = VOUCHER_DEFS and offer.id and VOUCHER_DEFS[offer.id]
    local pos = def and tonumber(def.pos)
    local drew = false
    push_tilt(self, x, y, w, h)
    if pos and game.ensure_asset_atlas_loaded and game.ASSET_ATLAS and game.ASSET_ATLAS.Voucher then
        game:ensure_asset_atlas_loaded("Voucher")
        local atlas = game.ASSET_ATLAS.Voucher
        if atlas and atlas.image then
            local px = tonumber(atlas.px) or 72
            local py = tonumber(atlas.py) or 95
            local quad = ShopUI.cached_atlas_quad(atlas, pos, "_voucher_quads")
            if quad then
                local s = math.min(w / px, h / py)
                local dw, dh = px * s, py * s
                local dx = x + math.floor((w - dw) * 0.5 + 0.5)
                local dy = y + math.floor((h - dh) * 0.5 + 0.5)
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.draw(atlas.image, quad, dx, dy, 0, s, s)
                drew = true
            end
        end
    end
    if not drew then
        love.graphics.setColor((game.C and game.C.VOUCHER) or { 0.5, 0.35, 0.55 })
        love.graphics.rectangle("fill", x, y, w, h, 3, 3)
        love.graphics.setColor(1, 1, 1, 1)
    end
    love.graphics.pop()
    if game.draw_node_gamepad_focus_outline then
        game:draw_node_gamepad_focus_outline(self)
    end
end
