--- The reference parents a shop card's price to the card itself (`UI_definitions.lua:813`), so
--- a card lifted off the shelf carries its price up with it and passes over the others. The
--- port drew all three tag rows in one pass after every shop node, so a dragged card ended up
--- underneath every tag on screen, including tags belonging to other slots.
local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

bootstrap.load()
local ShopUI = require("shop_ui")

--- Count the price tags a draw pass emits, by their DynaText keys.
local function capture_tags(fn)
    local DynaText = require("dyna_text")
    local real = DynaText.draw
    local drawn = {}
    DynaText.draw = function(state, text, x, y, w, align)
        drawn[#drawn + 1] = { text = text, x = x, y = y }
        return real(state, text, x, y, w, align)
    end
    local ok, err = pcall(fn)
    DynaText.draw = real
    T.assert_true(ok, tostring(err))
    return drawn
end

local function shop_with_offers(seed)
    local g = bootstrap.new_game(seed)
    g.STATE = g.STATES.SHOP
    g.shop_offer_slots = 3
    g:roll_shop_offers()
    g:sync_shop_offer_nodes()
    ShopUI.layout_shop_offer_nodes(g, { x = 4, y = 40, w = 300, h = 110 })
    return g
end

suite.test("a dragged shop node is identified only while the shop is open", function()
    local g = shop_with_offers(4305)
    local node = g.shop_offer_nodes[1]
    T.assert_not_nil(node)

    T.assert_eq(g:dragged_shop_node(), nil, "nothing is being dragged")

    g.dragging = node
    T.assert_eq(g:dragged_shop_node(), node, "the lifted shop card is picked out")

    g.STATE = g.STATES.SELECTING_HAND
    T.assert_eq(g:dragged_shop_node(), nil, "and only in the shop")
end)

suite.test("the tag pass skips the dragged slot and it is drawn back on top", function()
    local g = shop_with_offers(4306)
    local node = g.shop_offer_nodes[1]
    T.assert_not_nil(node)

    local all = capture_tags(function() ShopUI.draw_shop_price_tags(g, nil) end)
    T.assert_true(#all > 1, "the shelf has several tags to layer against")

    local skipped = capture_tags(function() ShopUI.draw_shop_price_tags(g, node) end)
    T.assert_eq(#skipped, #all - 1, "the dragged slot's tag is left out of the shelf pass")

    local own = capture_tags(function()
        T.assert_true(ShopUI.draw_price_tag_for_node(g, node), "its own tag is drawn on request")
    end)
    T.assert_eq(#own, 1, "exactly one tag, its own")
end)

suite.test("a dragged card's price tag follows the card", function()
    local g = shop_with_offers(4307)
    local node = g.shop_offer_nodes[1]
    g.dragging = node

    local before = capture_tags(function() ShopUI.draw_price_tag_for_node(g, node) end)
    node.T.x, node.T.y = node.T.x + 40, node.T.y - 30
    node.VT.x, node.VT.y = node.T.x, node.T.y
    local after = capture_tags(function() ShopUI.draw_price_tag_for_node(g, node) end)

    T.assert_eq(#before, 1)
    T.assert_eq(#after, 1)
    T.assert_true(after[1].x > before[1].x, "the tag tracks the card's x")
    T.assert_true(after[1].y < before[1].y, "and its y")
end)

suite.test("a node with no shop slot has no tag to draw", function()
    local g = shop_with_offers(4308)
    T.assert_false(ShopUI.draw_price_tag_for_node(g, { }) == true)
    T.assert_false(ShopUI.draw_price_tag_for_node(g, nil) == true)
end)

--- The buttons and the price tags carry the shop's drop shadow; the spine label was the one
--- piece of chrome still printed flat, which read as background rather than as a label.
suite.test("a panel header is drawn with its shadow behind it", function()
    local g = bootstrap.new_game(9100)

    local prints = {}
    local real_print = love.graphics.print
    local real_setColor = love.graphics.setColor
    local current = nil
    love.graphics.setColor = function(c, ...)
        current = (type(c) == "table") and { c[1], c[2], c[3], c[4] } or { c, ... }
        return real_setColor(c, ...)
    end
    love.graphics.print = function(text, px, py, r)
        prints[#prints + 1] = { text = text, x = px, y = py, r = r, colour = current }
        return real_print(text, px, py, r)
    end
    local ok, err = pcall(ShopUI.draw_panel_header, g, "VOUCHER", 4, 100, 90)
    love.graphics.print = real_print
    love.graphics.setColor = real_setColor
    if not ok then error(err, 0) end

    T.assert_eq(#prints, 2, "the label is drawn twice: shadow, then face")
    local shadow, face = prints[1], prints[2]
    T.assert_eq(shadow.text, "VOUCHER")
    T.assert_eq(face.text, "VOUCHER")
    -- The shadow sits one pixel down and right on screen, like every other shadow here.
    T.assert_eq(shadow.x, face.x + 1, "shadow is offset in x")
    T.assert_eq(shadow.y, face.y + 1, "shadow is offset in y")
    -- Both run up the panel, not across it.
    T.assert_near(face.r, math.rad(-90), 1e-9)
    T.assert_near(shadow.r, math.rad(-90), 1e-9)
    -- And the shadow is drawn first, so the face lands on top of it.
    T.assert_true(shadow.colour ~= nil and face.colour ~= nil, "both passes set a colour")
end)

return suite
