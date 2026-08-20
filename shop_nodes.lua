--- Draggable shop booster / voucher nodes (Moveable, not full Joker/Consumable).
local ShopUI = require("shop_ui")

---@class ShopBoosterNode : Moveable
ShopBoosterNode = Moveable:extend()

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
    if not ShopUI.draw_booster_atlas_frame(game, rect, idx) then
        love.graphics.setColor((game.C and game.C.BOOSTER) or { 0.4, 0.43, 0.72 })
        love.graphics.rectangle("fill", x, y, w, h, 3, 3)
        love.graphics.setColor(1, 1, 1, 1)
    end
    if game.draw_node_gamepad_focus_outline then
        game:draw_node_gamepad_focus_outline(self)
    end
end

---@class ShopVoucherNode : Moveable
ShopVoucherNode = Moveable:extend()

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
    if pos and game.ensure_asset_atlas_loaded and game.ASSET_ATLAS and game.ASSET_ATLAS.Voucher then
        game:ensure_asset_atlas_loaded("Voucher")
        local atlas = game.ASSET_ATLAS.Voucher
        if atlas and atlas.image then
            local px = tonumber(atlas.px) or 72
            local py = tonumber(atlas.py) or 95
            local iw, ih = atlas.image:getDimensions()
            local cols = math.max(1, math.floor(iw / px))
            local col = pos % cols
            local row = math.floor(pos / cols)
            local qx, qy = col * px, row * py
            local quad = love.graphics.newQuad(qx, qy, px, py, iw, ih)
            local s = math.min(w / px, h / py)
            local dw, dh = px * s, py * s
            local dx = x + math.floor((w - dw) * 0.5 + 0.5)
            local dy = y + math.floor((h - dh) * 0.5 + 0.5)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(atlas.image, quad, dx, dy, 0, s, s)
            drew = true
        end
    end
    if not drew then
        love.graphics.setColor((game.C and game.C.VOUCHER) or { 0.5, 0.35, 0.55 })
        love.graphics.rectangle("fill", x, y, w, h, 3, 3)
        love.graphics.setColor(1, 1, 1, 1)
    end
    if game.draw_node_gamepad_focus_outline then
        game:draw_node_gamepad_focus_outline(self)
    end
end
