--- Low-draw-call ticket treatment for progression and summary UI.
--- Rectangular fills are deliberate: on 3DS their pixel area is effectively free, while
--- rounded geometry spends 3-5x the vertices (`AGENTS.md`, renderer measurements).

local Fonts = require("fonts")
local TicketStrip = {}

function TicketStrip.layout(x, y, w, h, stub_w)
    stub_w = math.max(22, math.min(w - 32, tonumber(stub_w) or 54))
    return {
        x = x, y = y, w = w, h = h, stub_w = stub_w,
        body_x = x + stub_w,
        body_w = w - stub_w,
        notch = math.max(2, math.min(5, math.floor(h / 5))),
    }
end

local function colour(c, fallback)
    return c or fallback or { 1, 1, 1, 1 }
end

--- One paper ticket: coloured stub, square paper body, two edge notches and a perforation.
--- The perforation uses four tiny fills rather than a dashed line so line-state changes do
--- not flush the 3DS renderer between the ticket and its text.
function TicketStrip.draw(game, spec)
    local C = game.C
    local r = TicketStrip.layout(spec.x, spec.y, spec.w, spec.h, spec.stub_w)
    love.graphics.setColor(colour(spec.paper, C.LIGHT_GREY or C.WHITE))
    love.graphics.rectangle("fill", r.x, r.y, r.w, r.h)
    love.graphics.setColor(colour(spec.stub_color, C.RED))
    love.graphics.rectangle("fill", r.x, r.y, r.stub_w, r.h)

    love.graphics.setColor(C.BLOCK.BACK)
    love.graphics.rectangle("fill", r.body_x - r.notch, r.y, r.notch * 2, r.notch)
    love.graphics.rectangle("fill", r.body_x - r.notch, r.y + r.h - r.notch, r.notch * 2, r.notch)
    local dash_h = math.max(2, math.floor((r.h - r.notch * 4) / 7))
    for i = 0, 3 do
        love.graphics.rectangle("fill", r.body_x - 1, r.y + r.notch * 2 + i * dash_h * 2, 2, dash_h)
    end

    love.graphics.setFont(spec.font or game.FONTS.PIXEL.SMALL)
    love.graphics.setColor(C.WHITE)
    love.graphics.printf(spec.stub or "", r.x + 2, r.y + math.floor((r.h - love.graphics.getFont():getHeight()) / 2),
        r.stub_w - 4, "center")
    -- Title and detail are one line each, so each is fitted to the body width rather than left to
    -- wrap onto the other.
    local text_font = spec.font or game.FONTS.PIXEL.SMALL
    love.graphics.setColor(C.BLACK or C.BLOCK.BACK)
    love.graphics.setFont(Fonts.fit(game, text_font, spec.title or "", r.body_w - 14))
    Fonts.printf_fit(spec.title or "", r.body_x + 7, r.y + 4, r.body_w - 14, "left")
    if spec.detail and spec.detail ~= "" then
        love.graphics.setColor(C.GREY)
        love.graphics.setFont(Fonts.fit(game, text_font, spec.detail, r.body_w - 14))
        Fonts.printf_fit(spec.detail, r.body_x + 7, r.y + r.h - love.graphics.getFont():getHeight() - 3,
            r.body_w - 14, "left")
    end
    return r
end

local function count_keys(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

function TicketStrip.challenge_facts(def)
    if type(def) ~= "table" then return {} end
    local out = {}
    local rules = def.rules or {}
    local ordered = {
        { "hands", "Hands" }, { "discards", "Discards" }, { "hand_size", "Hand Size" },
        { "joker_slots", "Joker Slots" }, { "dollars", "Starting $" },
    }
    local function fact(key, label, value)
        return I18N.text("challenge.fact." .. key, nil, label) .. I18N.text("challenge.fact.separator", nil, ": ")
            .. tostring(value)
    end
    for _, pair in ipairs(ordered) do
        if rules[pair[1]] ~= nil then out[#out + 1] = fact(pair[1], pair[2], rules[pair[1]]) end
    end
    if #(def.start_jokers or {}) > 0 then out[#out + 1] = fact("start_jokers", "Starting Jokers", #def.start_jokers) end
    if #(def.start_consumables or {}) > 0 then
        out[#out + 1] = fact("start_consumables", "Starting Consumables", #def.start_consumables)
    end
    if #(def.start_vouchers or {}) > 0 then out[#out + 1] = fact("start_vouchers", "Starting Vouchers", #def.start_vouchers) end
    local banned = count_keys(def.banned and def.banned.cards)
        + count_keys(def.banned and def.banned.packs)
        + count_keys(def.banned and def.banned.tags)
        + count_keys(def.banned and def.banned.blinds)
    if banned > 0 then out[#out + 1] = fact("banned", "Banned Items", banned) end
    if #out == 0 then out[1] = I18N.text("challenge.fact.special", nil, "Special rules apply") end
    return out
end

return TicketStrip
