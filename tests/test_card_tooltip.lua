--- Card tap tooltip: modifiers surface with their reference badge names, editions included
--- (`common_events.lua:2722-2736` queues one titled info box per badge in the base game).
local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

--- Render a card's tooltip and capture every string printed into it.
local function tooltip_text(card_data, params)
    bootstrap.new_game(7001)
    local card = Card(0, 100, 72, 95, card_data, nil, params or { face_up = true })
    local printed = {}
    local real_print = love.graphics.print
    love.graphics.print = function(text, ...)
        printed[#printed + 1] = tostring(text)
        return real_print(text, ...)
    end
    local ok, err = pcall(function() card:draw_tooltip(100, 150) end)
    love.graphics.print = real_print
    if G and G.remove then G:remove(card) end
    if not ok then error(err, 0) end
    return table.concat(printed, "\n")
end

local function assert_shows(text, needle, why)
    T.assert_true(text:find(needle, 1, true) ~= nil,
        why .. " (looked for \"" .. needle .. "\")")
end

suite.test("an edition appears in the tooltip with its effect", function()
    local text = tooltip_text({ rank = 7, suit = "Hearts", modifier = { edition = "foil" } })
    assert_shows(text, "Foil", "the edition badge name shows")
    assert_shows(text, "+50", "and its chip bonus")

    text = tooltip_text({ rank = 7, suit = "Hearts", modifier = { edition = "polychrome" } })
    assert_shows(text, "Polychrome", "polychrome names itself")
    assert_shows(text, "1.5", "with its mult effect")
end)

suite.test("an enhancement is named, not just described", function()
    local text = tooltip_text({ rank = 10, suit = "Clubs", enhancement = "lucky" })
    assert_shows(text, "Lucky Card", "the enhancement badge name shows")
    -- Segments print separately ("1/5: ", "+20", " mult"), so match the pieces.
    assert_shows(text, "1/5", "with the lucky odds prefix")
    assert_shows(text, "+20", "and the lucky mult amount")
end)

suite.test("a seal is named alongside its effect", function()
    local text = tooltip_text({ rank = 3, suit = "Spades", seal = "gold" })
    assert_shows(text, "Gold Seal", "the seal badge name shows")
end)

suite.test("a fully modified card lists enhancement then edition then seal", function()
    local text = tooltip_text({
        rank = 14, suit = "Diamonds",
        enhancement = "glass", seal = "red",
        modifier = { edition = "holo" },
    })
    local enh_at = text:find("Glass Card", 1, true)
    local ed_at = text:find("Holographic", 1, true)
    local seal_at = text:find("Red Seal", 1, true)
    T.assert_true(enh_at ~= nil, "enhancement present")
    T.assert_true(ed_at ~= nil, "edition present")
    T.assert_true(seal_at ~= nil, "seal present")
    T.assert_true(enh_at < ed_at and ed_at < seal_at,
        "badge order matches the reference's info queue")
end)

suite.test("a plain card names no badges", function()
    local text = tooltip_text({ rank = 5, suit = "Hearts" })
    T.assert_true(text:find("Card", 1, true) == nil, "no badge name on an unmodified card")
    assert_shows(text, "+5", "base chips still show")
end)

return suite
