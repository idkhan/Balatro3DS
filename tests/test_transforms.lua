--- The flattened sprite transforms.
---
--- `Card:draw` used to build its transform by hand, twice per card:
---
---     translate(x, y) scale(s, s) translate(w/2, h/2) rotate(r) scale(f, 1) translate(-w/2, -h/2)
---
--- eight graphics calls with the push and pop, and 17.1 us of them on a New 3DS. The helpers
--- in `engine/moveable.lua` collapse that algebraically -- a uniform scale commutes with a
--- rotation, and without a rotation the two centring translates cancel outright.
---
--- "Algebraically" is the claim this file has to hold to. A transform that is subtly wrong
--- does not throw; it puts a rotated card a pixel off its shadow, or pivots a flip about the
--- wrong edge, and nobody notices until a screenshot is compared months later. So the original
--- chain is written out here in full, both forms are run through a matrix tracker, and the two
--- are compared by where they actually send points.

local T = require("tests.testlib")
require("tests.bootstrap").load()

local suite = T.suite()

--------------------------------------------------------------------------------
-- a 2x3 affine tracker standing in for love.graphics' transform stack
--------------------------------------------------------------------------------

local IDENTITY = { 1, 0, 0, 1, 0, 0 } -- [a c e; b d f]

local function mul(m, n)
    return {
        m[1] * n[1] + m[3] * n[2],
        m[2] * n[1] + m[4] * n[2],
        m[1] * n[3] + m[3] * n[4],
        m[2] * n[3] + m[4] * n[4],
        m[1] * n[5] + m[3] * n[6] + m[5],
        m[2] * n[5] + m[4] * n[6] + m[6],
    }
end

local function apply(m, x, y)
    return m[1] * x + m[3] * y + m[5], m[2] * x + m[4] * y + m[6]
end

--- Run `body` with love.graphics' transform calls recorded rather than performed. Returns the
--- matrix left on top of the stack, and how many graphics calls it took to get there.
local function track(body)
    local stack, current, calls = {}, IDENTITY, 0
    local g = love.graphics
    local saved = {}
    for _, name in ipairs({ "push", "pop", "translate", "rotate", "scale", "draw" }) do
        saved[name] = g[name]
    end

    g.push = function()
        calls = calls + 1
        stack[#stack + 1] = current
    end
    g.pop = function()
        calls = calls + 1
        current = table.remove(stack) or IDENTITY
    end
    g.translate = function(x, y)
        calls = calls + 1
        current = mul(current, { 1, 0, 0, 1, x, y })
    end
    g.rotate = function(r)
        calls = calls + 1
        current = mul(current, { math.cos(r), math.sin(r), -math.sin(r), math.cos(r), 0, 0 })
    end
    g.scale = function(sx, sy)
        calls = calls + 1
        current = mul(current, { sx, 0, 0, sy or sx, 0, 0 })
    end

    local ok, err = pcall(body)

    for name, fn in pairs(saved) do g[name] = fn end
    if not ok then error(err, 0) end

    return current, calls
end

--- The chain `Card:draw` built before the helper existed, written out rather than referenced,
--- so a change to the helper cannot quietly change what it is being compared against.
local function original_sprite_chain(x, y, w, h, s, r, flip_sx)
    love.graphics.push()
    love.graphics.translate(x, y)
    love.graphics.scale(s, s)
    love.graphics.translate(w * 0.5, h * 0.5)
    love.graphics.rotate(r)
    love.graphics.scale(flip_sx, 1)
    love.graphics.translate(-w * 0.5, -h * 0.5)
end

--- And the chain jokers and consumables built: rotate and scale about a point.
local function original_pivot_chain(px, py, r, sx, sy)
    love.graphics.push()
    love.graphics.translate(px, py)
    love.graphics.rotate(r)
    love.graphics.scale(sx, sy)
    love.graphics.translate(-px, -py)
end

--- Where two transforms send the corners and centre of a card-sized rectangle. Comparing
--- points rather than matrix entries keeps the assertion in units anyone can picture, and a
--- transform that agrees on five spread-out points agrees everywhere -- an affine map is
--- determined by three.
local PROBES = { { 0, 0 }, { 71, 0 }, { 0, 95 }, { 71, 95 }, { 35.5, 47.5 } }

local function assert_same_transform(a, b, why)
    for _, probe in ipairs(PROBES) do
        local ax, ay = apply(a, probe[1], probe[2])
        local bx, by = apply(b, probe[1], probe[2])
        T.assert_near(bx, ax, 1e-4, why .. ": x at (" .. probe[1] .. "," .. probe[2] .. ")")
        T.assert_near(by, ay, 1e-4, why .. ": y at (" .. probe[1] .. "," .. probe[2] .. ")")
    end
end

--------------------------------------------------------------------------------
-- the cases a card is actually drawn in
--------------------------------------------------------------------------------

local CARD_W, CARD_H = 71, 95

local SPRITE_CASES = {
    ["idle in hand"]        = { x = 40, y = 150, s = 1, r = 0, f = 1 },
    ["lifted and scaled"]   = { x = 40, y = 130, s = 1.08, r = 0, f = 1 },
    ["shrunk in the deck"]  = { x = 8, y = 20, s = 0.55, r = 0, f = 1 },
    ["leaning into motion"] = { x = 40, y = 150, s = 1, r = 0.21, f = 1 },
    ["leaning the other way"] = { x = 40, y = 150, s = 1, r = -0.21, f = 1 },
    ["rotated and scaled"]  = { x = 12, y = 33, s = 1.24, r = 0.4, f = 1 },
    ["mid flip"]            = { x = 40, y = 150, s = 1, r = 0, f = 0.4 },
    ["edge on"]             = { x = 40, y = 150, s = 1, r = 0, f = 0.05 },
    ["flipping while it leans"] = { x = 40, y = 150, s = 1.1, r = 0.18, f = 0.35 },
    ["juiced past its size"] = { x = 40, y = 150, s = 1.4, r = 0.05, f = 1 },
    ["negative scale"]      = { x = 40, y = 150, s = 1, r = 0.1, f = -1 },
    ["at the origin"]       = { x = 0, y = 0, s = 1, r = 0, f = 1 },
}

for why, c in pairs(SPRITE_CASES) do
    suite.test("the sprite transform matches the original chain: " .. why, function()
        local before = track(function()
            original_sprite_chain(c.x, c.y, CARD_W, CARD_H, c.s, c.r, c.f)
        end)
        local after = track(function()
            Moveable.push_sprite_transform(c.x, c.y, CARD_W, CARD_H, c.s, c.r, c.f)
        end)
        assert_same_transform(before, after, why)
    end)
end

local PIVOT_CASES = {
    ["settled joker"]     = { px = 60, py = 40, r = 0, sx = 1, sy = 1 },
    ["scaled joker"]      = { px = 60, py = 40, r = 0, sx = 0.8, sy = 0.8 },
    ["pinched mid flip"]  = { px = 60, py = 40, r = 0, sx = -0.3, sy = 0.9 },
    ["rotating joker"]    = { px = 60, py = 40, r = 0.15, sx = 1, sy = 1 },
    ["rotating and scaled"] = { px = 12, py = 90, r = -0.3, sx = 1.2, sy = 1.2 },
}

for why, c in pairs(PIVOT_CASES) do
    suite.test("the pivot transform matches the original chain: " .. why, function()
        local before = track(function()
            original_pivot_chain(c.px, c.py, c.r, c.sx, c.sy)
        end)
        local after = track(function()
            Moveable.push_pivot_transform(c.px, c.py, c.r, c.sx, c.sy)
        end)
        assert_same_transform(before, after, why)
    end)
end

--------------------------------------------------------------------------------
-- the draws that dropped the transform stack entirely
--------------------------------------------------------------------------------

--- LOVE's own argument form is `translate(x,y) rotate(r) scale(sx,sy) translate(-ox,-oy)`.
local function draw_args_chain(x, y, r, sx, sy, ox, oy)
    love.graphics.push()
    love.graphics.translate(x, y)
    love.graphics.rotate(r)
    love.graphics.scale(sx, sy)
    love.graphics.translate(-ox, -oy)
end

suite.test("the card shadow's draw arguments express the same transform", function()
    for why, c in pairs(SPRITE_CASES) do
        local w, h = CARD_W, CARD_H
        local before = track(function()
            original_sprite_chain(c.x, c.y, w, h, c.s, c.r, c.f)
        end)
        -- What Card:draw now passes straight to love.graphics.draw for the shadow.
        local after = track(function()
            draw_args_chain(c.x + c.s * w * 0.5, c.y + c.s * h * 0.5,
                c.r, c.s * c.f, c.s, w * 0.5, h * 0.5)
        end)
        assert_same_transform(before, after, "shadow draw args: " .. why)
    end
end)

suite.test("the consumable's draw arguments express the same transform", function()
    -- The old form pushed a pivot transform and then drew the quad at (draw_x, draw_y); the
    -- new one folds both into the draw call.
    for why, c in pairs(PIVOT_CASES) do
        local draw_x, draw_y = c.px - 30, c.py - 40
        local before = track(function()
            original_pivot_chain(c.px, c.py, c.r, c.sx, c.sy)
            love.graphics.translate(draw_x, draw_y)
        end)
        local after = track(function()
            draw_args_chain(c.px, c.py, c.r, c.sx, c.sy, c.px - draw_x, c.py - draw_y)
        end)
        assert_same_transform(before, after, "consumable draw args: " .. why)
    end
end)

--------------------------------------------------------------------------------
-- and that it is actually cheaper, which is the point
--------------------------------------------------------------------------------

--- Moving a push into a helper is the classic way to leave the transform stack one deep, and
--- on hardware that shows up as everything drawn after the offending node sliding by whatever
--- the leaked transform was. Draw one of each and check the stack comes back empty.
suite.test("every node type leaves the transform stack balanced", function()
    local bootstrap = require("tests.bootstrap")
    local game = bootstrap.new_game(1)

    local nodes = {
        card = Card(10, 20, 71, 95, { rank = 7, suit = "Spades" }, nil, { face_up = true }),
        consumable = Consumable and Consumable(10, 20, CONSUMABLE_DEFS and CONSUMABLE_DEFS.c_fool
            or { id = "c_fool", kind = "tarot", name = "The Fool" }) or nil,
        joker = Joker and Joker(10, 20, 71, 95,
            (JOKER_DEFS and JOKER_DEFS.j_joker) or { id = "j_joker", name = "Joker" },
            { face_up = true }) or nil,
    }

    for name, node in pairs(nodes) do
        for _, state in ipairs({ "plain", "rotated", "juiced", "flipping", "dissolving" }) do
            if state == "rotated" then node.VT.r = 0.25 end
            if state == "juiced" then node:juice_up() end
            if state == "flipping" then node:start_flip() end
            if state == "dissolving" then node:begin_lifecycle("dissolve") end

            local depth = 0
            local g = love.graphics
            local push, pop = g.push, g.pop
            g.push = function() depth = depth + 1 return push() end
            g.pop = function() depth = depth - 1 return pop() end

            local ok, err = pcall(function() node:draw() end)

            g.push, g.pop = push, pop
            T.assert_true(ok, name .. " (" .. state .. ") should draw: " .. tostring(err))
            T.assert_eq(depth, 0, name .. " (" .. state .. ") left the transform stack unbalanced")
        end
    end

    T.assert_true(game ~= nil, "the game fixture is what supplies the atlases")
end)

suite.test("the flattened chains cost fewer graphics calls", function()
    local _, original = track(function()
        original_sprite_chain(40, 150, CARD_W, CARD_H, 1, 0, 1)
    end)
    local _, flattened = track(function()
        Moveable.push_sprite_transform(40, 150, CARD_W, CARD_H, 1, 0, 1)
    end)
    T.assert_eq(original, 7, "the original chain was a push and six transforms")
    T.assert_eq(flattened, 2, "an unrotated unscaled card needs a push and one translate")

    local _, rotated = track(function()
        Moveable.push_sprite_transform(40, 150, CARD_W, CARD_H, 1.1, 0.2, 0.5)
    end)
    T.assert_eq(rotated, 5, "and a rotated one a push and four")

    local _, pivot = track(function()
        Moveable.push_pivot_transform(60, 40, 0, 1, 1)
    end)
    T.assert_eq(pivot, 1, "a settled joker's pivot transform is just the push")
end)

return suite
