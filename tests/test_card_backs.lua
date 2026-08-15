--- A face-down playing card shows the selected deck's backing, and the cell it comes from is
--- found by the atlas's declared column count rather than by measuring the loaded image.

local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

local CELL_W, CELL_H = 72, 95

--- Width and height out of a PNG's IHDR (bytes 17-24 of the file). The love stub reports a
--- fixed size for every image, so the shipped art has to be measured off disk.
---@return integer w, integer h
local function png_dimensions(path)
    local file = assert(io.open(path, "rb"))
    local header = file:read(24)
    file:close()
    local function be32(offset)
        local a, b, c, d = header:byte(offset, offset + 3)
        return ((a * 256 + b) * 256 + c) * 256 + d
    end
    return be32(17), be32(21)
end

---@return table entry the `asset_atli` declaration for `name`
local function atlas_declaration(game, name)
    for _, entry in ipairs(game.asset_atli or {}) do
        if entry.name == name then return entry end
    end
    error("no atlas declaration named " .. tostring(name))
end

suite.test("declared column counts match the shipped sheets", function()
    local game = bootstrap.new_game(4)
    local root = os.getenv("BALATRO_ROOT") or "."
    -- Every atlas Card draws from. A wrong count here silently shifts whole rows of art.
    for _, name in ipairs({ "centers", "cards_1", "cards_2" }) do
        local entry = atlas_declaration(game, name)
        T.assert_not_nil(entry.cols, name .. " declares no column count")
        local w = png_dimensions(root .. "/" .. entry.path)
        T.assert_eq(entry.cols, math.floor(w / entry.px), name .. " column count")
    end
end)

suite.test("a card back comes from the declared columns, not the loaded image size", function()
    local game = bootstrap.new_game(5)
    game:apply_deck_config("b_blue")

    -- The Blue Deck's backing is cell 14, which is column 4 of row 1 across ten columns. Read
    -- off the image the stub hands out (a square 512) it would be column 0 of row 2, and on
    -- hardware -- where the sheet is padded to 1024 wide -- column 0 of row 1: three different
    -- cells for the same index, which is the whole reason `cols` is declared.
    local card = Card(0, 0, nil, nil, { rank = 5, suit = "Hearts" }, nil, { face_up = false })
    T.assert_eq(card.back_index, 14, "blue deck back index")
    T.assert_not_nil(card.back_quad, "back quad")
    local x, y, w, h = card.back_quad:getViewport()
    T.assert_eq(x, 4 * CELL_W, "back cell x")
    T.assert_eq(y, 1 * CELL_H, "back cell y")
    T.assert_eq(w, CELL_W, "back cell width")
    T.assert_eq(h, CELL_H, "back cell height")
end)

suite.test("every deck's backing lands on its own cell inside the sheet", function()
    local game = bootstrap.new_game(6)
    local entry = atlas_declaration(game, "centers")
    local root = os.getenv("BALATRO_ROOT") or "."
    local sheet_w, sheet_h = png_dimensions(root .. "/" .. entry.path)

    local seen = {}
    for _, def in ipairs(DECK_DEFS) do
        game:apply_deck_config(def.id)
        local card = Card(0, 0, nil, nil, { rank = 9, suit = "Spades" }, nil, { face_up = false })
        T.assert_eq(card.back_index, def.pos, def.id .. " back index")
        local x, y = card.back_quad:getViewport()
        T.assert_true(x + CELL_W <= sheet_w and y + CELL_H <= sheet_h,
            def.id .. " backing falls outside the sheet")
        T.assert_nil(seen[def.pos], def.id .. " shares a backing with " .. tostring(seen[def.pos]))
        seen[def.pos] = def.id
    end
end)

suite.test("an enhanced card is hidden by the deck's backing, not by its enhancement", function()
    local game = bootstrap.new_game(7)
    game:apply_deck_config("b_black")
    local black_back = game:get_selected_deck_back_index()

    -- Stone, Gold and Steel are the enhancements whose art fills the whole card, so they are the
    -- ones that used to leak onto the back. The reference builds the back sprite from the
    -- selected deck for every playing card whatever its centre (`reference/Balatro/card.lua:213`):
    -- The Wheel turning a card over hides it, it does not debuff or change it.
    for _, enh in ipairs({ "stone", "gold", "steel", "glass", "wild", "bonus", "mult", "lucky" }) do
        local card = Card(0, 0, nil, nil, { rank = 10, suit = "Clubs", enhancement = enh }, nil,
            { face_up = false })
        T.assert_eq(card.back_index, black_back, enh .. " back index")
    end

    -- ...while the face each one shows when it is turned back up is still its own art.
    local faces = { stone = 5, gold = 6, steel = 13, glass = 12, wild = 10, lucky = 11 }
    for enh, index in pairs(faces) do
        local card = Card(0, 0, nil, nil, { rank = 10, suit = "Clubs", enhancement = enh }, nil,
            { face_up = true })
        T.assert_eq(card.face_index, index, enh .. " face index")
    end
end)

return suite
