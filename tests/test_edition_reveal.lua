--- Editions announce themselves when a card shows one.
---
--- `Card:set_edition` queues a `juice_up(1, 0.5)` and the edition's own sting 0.2 s after
--- the edition lands, and never does it silently unless asked
--- (`reference/Balatro/card.lua:430-452`). The port had the sting function but nothing on
--- the shop path called it, so a polychrome offer arrived in total silence.

local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

local function with_recorded_cues(fn)
    local original = Sfx.play
    local cues = {}
    Sfx.play = function(cue, pitch, vol)
        cues[#cues + 1] = { cue = cue, pitch = pitch, vol = vol }
        return true
    end
    local ok, err = pcall(fn, cues)
    Sfx.play = original
    if not ok then error(err, 0) end
end

local function fake_node(edition)
    return { edition = edition, juiced = 0,
        juice_up = function(self, s, r) self.juiced = self.juiced + 1; self.scale = s; self.rot = r end }
end

--- Run the queue past `t` seconds in frame-sized steps.
local function advance(g, t)
    local step = 1 / 60
    for _ = 1, math.ceil(t / step) do g:_update_edition_reveals(step) end
end

suite.test("an edition reveal juices the card and plays its sting", function()
    local g = bootstrap.new_game()
    with_recorded_cues(function(cues)
        local node = fake_node("polychrome")
        g:announce_edition(node, "polychrome")
        T.assert_eq(#cues, 0, "nothing fires on the frame the edition lands")
        T.assert_eq(node.juiced, 0)

        advance(g, 0.3)
        T.assert_eq(#cues, 1, "the sting lands after the reference's 0.2 s beat")
        T.assert_eq(cues[1].cue, "polychrome1")
        T.assert_eq(node.juiced, 1, "and the card juices with it")
        T.assert_eq(node.scale, 1, "reference card.lua:441 juice_up(1, 0.5)")
        T.assert_eq(node.rot, 0.5)
    end)
end)

suite.test("a base edition announces nothing", function()
    local g = bootstrap.new_game()
    with_recorded_cues(function(cues)
        g:announce_edition(fake_node("base"), "base")
        g:announce_edition(fake_node(nil), nil)
        advance(g, 1)
        T.assert_eq(#cues, 0)
    end)
end)

suite.test("a shelf of editions announces one card at a time", function()
    local g = bootstrap.new_game()
    with_recorded_cues(function(cues)
        local nodes = { fake_node("foil"), fake_node("holo"), fake_node("negative") }
        for _, n in ipairs(nodes) do n.edition_reveal_pending = n.edition end
        g:begin_edition_reveals(nodes)

        -- Each sting gets its own beat: three cues never land on one frame.
        local seen = {}
        for _ = 1, 120 do
            local before = #cues
            g:_update_edition_reveals(1 / 60)
            T.assert_true(#cues - before <= 1, "at most one sting per frame")
            for i = before + 1, #cues do seen[#seen + 1] = cues[i].cue end
        end
        T.assert_eq(#seen, 3)
        T.assert_eq(seen[1], "foil1")
        T.assert_eq(seen[2], "holo1")
        T.assert_eq(seen[3], "negative")
        T.assert_eq(g._edition_reveals, nil, "the queue clears when it drains")
    end)
end)

suite.test("reveals are suppressed while a save is being restored", function()
    local g = bootstrap.new_game()
    with_recorded_cues(function(cues)
        g._suppress_edition_reveals = true
        g:announce_edition(fake_node("foil"), "foil")
        g._suppress_edition_reveals = nil
        advance(g, 1)
        T.assert_eq(#cues, 0, "restored cards are being put back, not appearing")
    end)
end)

suite.test("a reveal waits for the card to be on screen", function()
    local g = bootstrap.new_game()
    with_recorded_cues(function(cues)
        local node = fake_node("holo")
        node.states = { visible = false }
        g:announce_edition(node, "holo")
        advance(g, 2)
        T.assert_eq(#cues, 0, "the shop panel is still sliding in")

        node.states.visible = true
        advance(g, 0.3)
        T.assert_eq(#cues, 1, "and the sting lands once the shelf is up")
    end)
end)

suite.test("the shop reads an edition off a joker offer or a playing card", function()
    local g = bootstrap.new_game()
    T.assert_eq(g:shop_offer_edition({ kind = "joker", edition = "holo" }), "holo")
    T.assert_eq(g:shop_offer_edition({ kind = "joker", edition = "base" }), nil)
    T.assert_eq(g:shop_offer_edition({ kind = "joker" }), nil)
    T.assert_eq(g:shop_offer_edition({ kind = "playing_card",
        card_data = { rank = "A", suit = "S", modifier = { edition = "foil" } } }), "foil")
    T.assert_eq(g:shop_offer_edition({ kind = "playing_card",
        card_data = { rank = "A", suit = "S" } }), nil)
end)

suite.test("a shop shelf announces every editioned card it materialises", function()
    local g = bootstrap.new_game()
    with_recorded_cues(function(cues)
        g.STATE = g.STATES.SHOP
        g.shop_offers = {
            { kind = "joker", id = "j_joker", edition = "foil" },
            { kind = "joker", id = "j_greedy_joker", edition = "base" },
        }
        g:sync_shop_offer_nodes()
        advance(g, 2)
        T.assert_eq(#cues, 1, "only the editioned offer announces")
        T.assert_eq(cues[1].cue, "foil1")

        -- Re-syncing the same shelf must not announce again: those nodes already exist.
        local before = #cues
        g:sync_shop_offer_nodes()
        advance(g, 2)
        T.assert_eq(#cues, before, "a resync is not a reappearance")
    end)
end)

return suite
