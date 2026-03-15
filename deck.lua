---@class Deck
Deck = Object:extend()

local SUITS = { "Hearts", "Clubs", "Diamonds", "Spades" }
local MIN_RANK = 2
local MAX_RANK = 14  -- 2..10, 11=J, 12=Q, 13=K, 14=A

function Deck:init()
    self.cards = {}
    self:fill()
end

function Deck:fill()
    self.cards = {}
    for _, suit in ipairs(SUITS) do
        for rank = MIN_RANK, MAX_RANK do
            table.insert(self.cards, { rank = rank, suit = suit })
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

--- Pop a card from the deck. Returns the card or nil if deck is empty.
---@return table|nil
function Deck:draw()
    if #self.cards == 0 then return nil end
    return table.remove(self.cards)
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

function Deck:empty()
    return #self.cards == 0
end
