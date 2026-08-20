--- Joker unlock progression.
---
--- The catalog has always carried `unlocked = false` on 45 Jokers, but nothing read it, so
--- every Joker was available from the first run. This is the missing half: the conditions
--- themselves, an evaluator per condition type, and the per-profile record of what has been
--- earned. Data is transcribed from the reference's `unlock_condition` fields
--- (`reference/Balatro/game.lua`), and the evaluators follow `check_for_unlock`
--- (`reference/Balatro/functions/common_events.lua:1163-1620`).
---
--- Two rules from the top of `check_for_unlock` matter and are honoured in `Game:check_unlock`:
--- a seeded run and a challenge run earn nothing.
---
--- The five Legendaries are `hidden = true` in the reference and carry no condition. They are
--- rarity 4, which `get_current_pool` exempts from the unlock filter outright
--- (`common_events.lua:1987`), because the only way to see one is The Soul.

JokerUnlocks = {}

--- Condition per locked Joker, keyed by this port's ids (nine differ from the reference's;
--- see the rename list in the audit). `stat` names match the career-stat keys below.
JokerUnlocks.CONDITIONS = {
    -- Career totals, counted across every run on the profile.
    j_acrobat         = { type = "career_stat", stat = "c_hands_played", amount = 200 },
    j_burnt           = { type = "career_stat", stat = "c_cards_sold", amount = 50 },
    j_sock_and_buskin = { type = "career_stat", stat = "c_face_cards_played", amount = 300 },
    j_swashbuckler    = { type = "career_stat", stat = "c_jokers_sold", amount = 20 },
    j_mr_bones        = { type = "career_stat", stat = "c_losses", amount = 5 },

    -- Best single hand, in chips.
    j_oops     = { type = "chip_score", chips = 10000 },
    j_idol     = { type = "chip_score", chips = 1000000 },
    j_stuntman = { type = "chip_score", chips = 100000000 },

    -- Reaching an ante.
    j_ring_master = { type = "ante_up", ante = 4 },
    j_flower_pot  = { type = "ante_up", ante = 8 },

    -- Holding money.
    j_satellite = { type = "money", amount = 400 },

    -- Deck composition, checked whenever the deck changes.
    j_arrowhead        = { type = "modify_deck", count = 30, suit = "Spades" },
    j_bloodstone       = { type = "modify_deck", count = 30, suit = "Hearts" },
    j_onyx_agate       = { type = "modify_deck", count = 30, suit = "Clubs" },
    j_rough_gem        = { type = "modify_deck", count = 30, suit = "Diamonds" },
    j_glass            = { type = "modify_deck", count = 5, enhancement = "glass" },
    j_smeared          = { type = "modify_deck", count = 3, enhancement = "wild" },
    j_drivers_license  = { type = "modify_deck", count = 16, enhanced_tally = true },

    -- Owned Jokers.
    j_bootstraps = { type = "modify_jokers", count = 2, edition = "polychrome" },

    -- Collection progress.
    j_cartomancer = { type = "discover_amount", kind = "tarot", amount = 22 },
    j_astronomer  = { type = "discover_amount", kind = "planet", amount = 12 },

    -- A Gold Card that also carries a Gold Seal (`card.lua:305`).
    j_certificate = { type = "double_gold" },

    -- Resuming a saved run (`game.lua:2028`).
    j_throwback = { type = "continue_game" },

    -- Emptying every Heart out of the deck and hand (`state_events.lua:521`).
    j_shoot_the_moon = { type = "play_all_hearts" },

    -- Contents of a played hand.
    j_seeing_double = { type = "hand_contents", rule = "four_sevens_of_clubs" },
    j_ticket        = { type = "hand_contents", rule = "five_gold_cards" },

    -- Contents of a discard.
    j_hit_the_road = { type = "discard_custom", rule = "five_jacks" },
    j_brainstorm   = { type = "discard_custom", rule = "royal_straight_flush" },

    -- Winning a round in a particular way.
    j_matador      = { type = "round_win", rule = "boss_first_hand_no_discards" },
    j_hanging_chad = { type = "round_win", rule = "boss_won_with", hand = "High Card" },
    j_troubadour   = { type = "round_win", rule = "single_hand_streak", amount = 5 },

    -- Winning a run.
    j_merry_andy = { type = "win", max_rounds = 12 },
    j_wee        = { type = "win", max_rounds = 18 },
    j_duo        = { type = "win_no_hand", hand = "Pair" },
    j_trio       = { type = "win_no_hand", hand = "Three of a Kind" },
    j_family     = { type = "win_no_hand", hand = "Four of a Kind" },
    j_order      = { type = "win_no_hand", hand = "Straight" },
    j_tribe      = { type = "win_no_hand", hand = "Flush" },
    j_blueprint  = { type = "win_custom", rule = "any_win" },
    j_invisible  = { type = "win_custom", rule = "max_four_joker_slots" },
}

--- Career counters this module needs, so a fresh profile starts them all at zero rather
--- than nil-checking at every increment.
JokerUnlocks.CAREER_STATS = {
    "c_hands_played",
    "c_cards_sold",
    "c_face_cards_played",
    "c_jokers_sold",
    "c_losses",
    "c_single_hand_round_streak",
    "c_best_hand_chips",
    -- High-water marks behind the stats page. The reference keeps these in `high_scores`
    -- rather than `career_stats` (`game.lua:864-874`); here one persisted table serves both,
    -- since the difference is only which screen reads them.
    "c_furthest_round",
    "c_furthest_ante",
    "c_most_money",
    "c_win_streak",
    "c_current_streak",
}

--- Jokers exempt from the unlock filter entirely. The reference exempts rarity 4 in
--- `get_current_pool` (`common_events.lua:1987`): a Legendary is only ever spawned by
--- The Soul, never rolled from a pool.
---@param def table|nil
---@return boolean
function JokerUnlocks.is_exempt(def)
    return type(def) == "table" and tonumber(def.rarity) == 4
end

---@param id string|nil
---@return table|nil
function JokerUnlocks.condition_for(id)
    if type(id) ~= "string" then return nil end
    return JokerUnlocks.CONDITIONS[id]
end

local function rank_is_face(rank)
    local r = tonumber(rank)
    return r == 11 or r == 12 or r == 13
end

--- Cards a played/discarded hand hands us, normalised to plain data tables.
local function card_data_list(cards)
    local out = {}
    for _, c in ipairs(cards or {}) do
        out[#out + 1] = (type(c) == "table" and c.card_data) or c
    end
    return out
end

--- Every playing card in the run: draw pile, discard pile and hand. The reference walks
--- `G.playing_cards`, which is the same set.
---@param game table
---@return table[]
local function run_playing_cards(game)
    local out = {}
    local deck = game and game.deck
    for _, c in ipairs((deck and deck.cards) or {}) do out[#out + 1] = c end
    for _, c in ipairs((deck and deck.discard_pile) or {}) do out[#out + 1] = c end
    for _, c in ipairs((game and game.hand and game.hand.cards) or {}) do out[#out + 1] = c end
    return out
end

--- Evaluators, one per condition type. Each returns true when the condition is met.
--- `data` is whatever the trigger site passed.
local EVALUATORS = {}

EVALUATORS.career_stat = function(game, cond)
    return (tonumber(game:get_career_stat(cond.stat)) or 0) >= (tonumber(cond.amount) or 0)
end

EVALUATORS.chip_score = function(game, cond, data)
    local chips = tonumber(data and data.chips) or tonumber(game:get_career_stat("c_best_hand_chips")) or 0
    return chips >= (tonumber(cond.chips) or 0)
end

EVALUATORS.ante_up = function(_, cond, data)
    -- The reference matches the ante exactly, since it fires once per ante-up.
    return (tonumber(data and data.ante) or 0) >= (tonumber(cond.ante) or 0)
end

EVALUATORS.money = function(game, cond)
    return (tonumber(game.money) or 0) >= (tonumber(cond.amount) or 0)
end

EVALUATORS.modify_deck = function(game, cond)
    local cards = run_playing_cards(game)
    local count = 0
    for _, c in ipairs(cards) do
        if cond.suit then
            if c.suit == cond.suit then count = count + 1 end
        elseif cond.enhancement then
            if c.enhancement == cond.enhancement then count = count + 1 end
        elseif cond.enhanced_tally then
            local e = c.enhancement
            if type(e) == "string" and e ~= "" and e ~= "none" then count = count + 1 end
        end
    end
    return count >= (tonumber(cond.count) or 0)
end

EVALUATORS.modify_jokers = function(game, cond)
    local count = 0
    for _, j in ipairs(game.jokers or {}) do
        local ed = Joker and Joker.normalize_edition(j and j.edition) or nil
        if ed == cond.edition then count = count + 1 end
    end
    return count >= (tonumber(cond.count) or 0)
end

EVALUATORS.discover_amount = function(game, cond)
    return game:count_discovered_consumables(cond.kind) >= (tonumber(cond.amount) or 0)
end

EVALUATORS.double_gold = function() return true end
EVALUATORS.continue_game = function() return true end

EVALUATORS.play_all_hearts = function(game)
    -- Every Heart gone from both the deck and the hand. Stone cards have no suit and so
    -- cannot hold one back (`common_events.lua:1344-1355`).
    for _, c in ipairs(run_playing_cards(game)) do
        if c.enhancement ~= "stone" and c.suit == "Hearts" then return false end
    end
    return true
end

EVALUATORS.hand_contents = function(_, cond, data)
    local cards = card_data_list(data and data.cards)
    if cond.rule == "four_sevens_of_clubs" then
        local tally = 0
        for _, c in ipairs(cards) do
            if tonumber(c.rank) == 7 and c.suit == "Clubs" then tally = tally + 1 end
        end
        return tally >= 4
    end
    if cond.rule == "five_gold_cards" then
        local tally = 0
        for _, c in ipairs(cards) do
            if c.enhancement == "gold" then tally = tally + 1 end
        end
        return tally >= 5
    end
    return false
end

EVALUATORS.discard_custom = function(game, cond, data)
    local cards = card_data_list(data and data.cards)
    if cond.rule == "five_jacks" then
        local tally = 0
        for _, c in ipairs(cards) do
            if tonumber(c.rank) == 11 then tally = tally + 1 end
        end
        return tally >= 5
    end
    if cond.rule == "royal_straight_flush" then
        -- A Straight Flush whose lowest card is a 10, i.e. a Royal Flush, discarded whole.
        if #cards < 5 then return false end
        local lowest = 15
        for _, c in ipairs(cards) do
            local r = tonumber(c.rank) or 0
            if r < lowest then lowest = r end
        end
        if lowest ~= 10 then return false end
        if not (game.hand and game.hand.evaluate_cards) then return false end
        local eval = game.hand:evaluate_cards(cards)
        return eval == "Straight Flush" or eval == "Royal Flush"
    end
    return false
end

EVALUATORS.round_win = function(game, cond, data)
    data = data or {}
    if cond.rule == "boss_first_hand_no_discards" then
        return data.is_boss_blind == true
            and (tonumber(data.hands_played) or 0) == 1
            and (tonumber(data.discards_used) or 0) == 0
    end
    if cond.rule == "boss_won_with" then
        return data.is_boss_blind == true and data.last_hand == cond.hand
    end
    if cond.rule == "single_hand_streak" then
        return (tonumber(game:get_career_stat("c_single_hand_round_streak")) or 0)
            >= (tonumber(cond.amount) or 0)
    end
    return false
end

EVALUATORS.win = function(_, cond, data)
    return (tonumber(data and data.rounds) or math.huge) <= (tonumber(cond.max_rounds) or 0)
end

EVALUATORS.win_no_hand = function(game, cond)
    local idx
    for i, name in ipairs(game.handlist or {}) do
        if name == cond.hand then idx = i break end
    end
    if not idx then return false end
    return (tonumber(game.hand_play_counts and game.hand_play_counts[idx]) or 0) == 0
end

EVALUATORS.win_custom = function(game, cond)
    if cond.rule == "any_win" then return true end
    if cond.rule == "max_four_joker_slots" then
        return (tonumber(game.joker_capacity) or 5) <= 4
    end
    return false
end

--- Evaluate every locked Joker whose condition matches `event_type`.
---@param game table
---@param event_type string
---@param data table|nil
---@return string[] newly unlocked joker ids
function JokerUnlocks.evaluate(game, event_type, data)
    local unlocked = {}
    for id, cond in pairs(JokerUnlocks.CONDITIONS) do
        if cond.type == event_type and not game:is_joker_unlocked(id) then
            local evaluator = EVALUATORS[event_type]
            if evaluator and evaluator(game, cond, data) then
                unlocked[#unlocked + 1] = id
            end
        end
    end
    table.sort(unlocked)
    return unlocked
end

return JokerUnlocks
