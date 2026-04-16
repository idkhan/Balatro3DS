---@class Deck
Deck = Object:extend()

local SUITS = { "Hearts", "Clubs", "Diamonds", "Spades" }
local MIN_RANK = 2
local MAX_RANK = 14 -- 2..10, 11=J, 12=Q, 13=K, 14=A

--- Shallow copy of a card data table (rank/suit/extras). Avoids shared refs between hand and piles.
---@param data table|nil
---@return table|nil
function Deck.copy_card_data(data)
    if type(data) ~= "table" then return nil end
    local c = {}
    for k, v in pairs(data) do
        c[k] = v
    end
    return c
end

function Deck:init()
    self.cards = {}
    --- Logical cards discarded from the hand (and similar). Not the same as UI discard animation queue.
    self.discard_pile = {}
    self:fill()
end

function Deck:fill()
    self.cards = {}
    --local enhancements = { "mult", "steel", "none", "bonus", "gold", "glass", "lucky", "stone", "wild"}
    --local seals = { "gold", "red", "blue", "purple", "none" }
    for _, suit in ipairs(SUITS) do
        for rank = MIN_RANK, MAX_RANK do
            --local enhancement = enhancements[math.random(1, #enhancements)]
            --local seal = seals[math.random(1, #seals)]
            table.insert(self.cards, { rank = rank, suit = suit, enhancement = nil, seal = nil })
        end
    end
end

function Deck:shuffle()
    local n = #self.cards
    for i = n, 2, -1 do
        local j = math.random(1, i)
        self.cards[i], self.cards[j] = self.cards[j], self.cards[i]
    end
end

--- Add a logical card to the discard pile (stores a copy). Used when the player **discards** — not when a card is **destroyed** (destroyed cards leave the game entirely).
---@param card_data table|nil
function Deck:push_discard(card_data)
    local c = Deck.copy_card_data(card_data)
    if c then
        table.insert(self.discard_pile, c)
    end
end

--- Move every card still in the draw pile into the discard pile (each copied).
function Deck:move_draw_pile_to_discard()
    while #self.cards > 0 do
        local c = table.remove(self.cards)
        self:push_discard(c)
    end
end

--- Shuffle discard into the draw pile. Call once when the **round** ends (not when the draw pile is empty mid-round).
function Deck:shuffle_discard_into_draw()
    if #self.discard_pile == 0 then return end
    for _, c in ipairs(self.discard_pile) do
        table.insert(self.cards, c)
    end
    self.discard_pile = {}
    self:shuffle()
end

--- Recycle the full deck at blind/round end: remaining draw pile and discard pile merge, then shuffle into draw.
function Deck:end_round()
    self:move_draw_pile_to_discard()
    self:shuffle_discard_into_draw()
end

--- Use after a game/run: the discard pile becomes the only source for the next game's draw pile.
--- Remaining cards in `self.cards` are left untouched; call `move_draw_pile_to_discard()` first if they should be included.
function Deck:set_next_game_draw_from_discard()
    self.cards = {}
    for _, c in ipairs(self.discard_pile) do
        table.insert(self.cards, Deck.copy_card_data(c))
    end
    self.discard_pile = {}
    self:shuffle()
end

---@return integer
function Deck:discard_size()
    return #self.discard_pile
end

--- Pop a card from the draw pile. Does **not** pull from the discard pile mid-run; call `end_round()` / `shuffle_discard_into_draw()` when the round ends.
---@return table|nil
function Deck:draw()
    if #self.cards == 0 then return nil end
    return table.remove(self.cards)
end

--- Return a **copy** of a uniformly random card's data from the draw pile (`self.cards`).
--- Does not remove the card. Does **not** include the discard pile. Returns nil if empty.
---@return table|nil
function Deck:random_card()
    local n = #self.cards
    if n == 0 then return nil end
    local i = math.random(1, n)
    return Deck.copy_card_data(self.cards[i])
end

--- Draw a card and add it to the given hand list. Returns the card or nil.
---@param hand table
---@return table|nil
function Deck:draw_to_hand(hand)
    local card = self:draw()
    if card and hand then
        table.insert(hand, card)
    end
    return card
end

function Deck:size()
    return #self.cards
end

--- Insert a copy of `card_data` at a random position in the draw pile (1 .. #cards+1).
---@param card_data table|nil
function Deck:insert_random(card_data)
    local c = Deck.copy_card_data(card_data)
    if not c then return end
    local n = #self.cards
    local pos = math.random(1, n + 1)
    table.insert(self.cards, pos, c)
end

function Deck:empty()
    return #self.cards == 0
end
