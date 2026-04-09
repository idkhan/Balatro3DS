JokerEffects = {}

local function has_hand_type(ctx, name)
    if not ctx then return false end
    if ctx.hand_type == name then return true end
    local contains = ctx.contains_hand_types
    return type(contains) == "table" and contains[name] == true
end

local function add_mult(ctx, n) ctx.mult = (tonumber(ctx.mult) or 0) + (tonumber(n) or 0) end
local function add_chips(ctx, n) ctx.chips = (tonumber(ctx.chips) or 0) + (tonumber(n) or 0) end
local function mul_mult(ctx, n) ctx.mult = (tonumber(ctx.mult) or 1) * (tonumber(n) or 1) end
local function add_money(n)
    if G and G.money ~= nil then
        G.money = (tonumber(G.money) or 0) + (tonumber(n) or 0)
    end
end
local function rank_is_face(rank) rank = tonumber(rank); return rank == 11 or rank == 12 or rank == 13 end
local function rank_is_even(rank) rank = tonumber(rank); return rank and rank ~= 14 and rank % 2 == 0 end
local function rank_is_odd(rank) rank = tonumber(rank); return rank and (rank == 14 or rank % 2 == 1) end
local function count_full_deck(pred)
    if G and G.count_cards_in_full_deck then return G:count_cards_in_full_deck(pred) end
    return 0
end
local function held_cards(ctx)
    local out = {}
    local played = {}
    for _, n in ipairs((ctx and ctx.played_cards) or {}) do played[n] = true end
    local hand_nodes = G and G.hand and G.hand.card_nodes or {}
    for _, node in ipairs(hand_nodes) do
        if not played[node] and node and node.card_data then table.insert(out, node.card_data) end
    end
    return out
end

local SHAKE_MAX_DURATION = 0.22

--- Default trigger matching for catalog-driven `effect_type` jokers (non-SPECIAL ids).
local function legacy_matches_trigger(self, event_name, ctx)
    if self.effect_type == "Hand card double" then
        return false
    end

    if self.effect_type == nil then
        return false
    end

    local default_event = nil
    if self.effect_type == "Mult" or self.effect_type == "Chips" then
        default_event = "on_hand_scored"
    elseif self.effect_type == "Suit Mult" or self.effect_type == "Suit Chips" then
        default_event = "card_played"
    elseif self.effect_type == "Type Mult" or self.effect_type == "Type Chips" then
        default_event = "on_hand_scored"
    elseif self.effect_type == "Hand Size Mult" then
        default_event = "on_hand_scored"
    elseif self.effect_type == "Stencil Mult" then
        default_event = "on_hand_scored"
    elseif self.effect_type == "Discard Chips" then
        default_event = "on_hand_scored"
    elseif self.effect_type == "No Discard Mult" then
        default_event = "on_hand_scored"
    elseif self.effect_type == "Stone card hands" then
        default_event = "on_blind_selected"
    elseif self.effect_type == "1 in 6 mult" or self.effect_type == "1 in 10 mult" then
        default_event = "on_hand_scored"
    end

    local expected_event = default_event
    if expected_event and expected_event ~= event_name then
        return false
    end

    local cfg = self.effect_config or {}
    if self.effect_type == "Suit Mult" or self.effect_type == "Suit Chips" then
        local extra = type(cfg.extra) == "table" and cfg.extra or {}
        if extra.suit ~= nil then
            if ctx == nil or ctx.suit ~= extra.suit then return false end
        end
    elseif self.effect_type == "Type Mult" or self.effect_type == "Type Chips" then
        if ctx == nil then return false end

        if ctx.hand_type ~= cfg.type then
            local contains = ctx.contains_hand_types
            if type(contains) ~= "table" or contains[cfg.type] ~= true then
                return false
            end
        end
    elseif self.effect_type == "Hand Size Mult" then
        if ctx == nil then return false end
        local extra = type(cfg.extra) == "table" and cfg.extra or {}
        local max_size = tonumber(extra.size) or 3
        local cards = ctx.cards
        if type(cards) ~= "table" or #cards > max_size then
            return false
        end
    elseif self.effect_type == "Stencil Mult" then
        if ctx == nil then return false end
        if tonumber(ctx.free_joker_slots) == nil then
            return false
        end
        self.free_joker_slots = tonumber(ctx.free_joker_slots)
    elseif self.effect_type == "No Discard Mult" then
        local d_remaining = tonumber((type(cfg.extra) == "table" and cfg.extra.d_remaining)) or 0
        local discards_left = tonumber((ctx and ctx.discards_left) or (G and G.discards)) or 0
        if discards_left ~= d_remaining then
            return false
        end
    elseif self.effect_type == "Destroy Joker" then
        if event_name == "on_blind_selected" then
            local joker_list = G and type(G.jokers) == "table" and G.jokers
            if not joker_list then
                return false
            end
            local self_index = nil
            for i, joker in ipairs(joker_list) do
                if joker == self then
                    self_index = i
                    break
                end
            end
            local target_index = self_index and (self_index + 1) or nil
            if not (target_index and joker_list[target_index]) then
                return false
            end
        elseif event_name == "on_hand_scored" then
            if (tonumber(self.stored_mult) or 0) <= 0 then
                return false
            end
        else
            return false
        end
    elseif self.effect_type == "1 in 6 mult" or self.effect_type == "1 in 10 mult" then
        local extra = type(cfg.extra) == "table" and cfg.extra or {}
        local every = math.max(1, tonumber(extra.every) or 6)
        local remaining = tonumber(self.loyalty_remaining)
        if remaining == nil then
            remaining = tonumber(extra.remaining) or every
        end
        if remaining < 1 or remaining > every then
            remaining = every
        end
        remaining = remaining - 1
        if remaining <= 0 then
            self.loyalty_remaining = every
            return true
        end
        self.loyalty_remaining = remaining
        return false
    end

    return true
end

--- Default apply for catalog-driven `effect_type` jokers (non-SPECIAL ids).
local function legacy_apply_effect(self, ctx)
    ctx = ctx or {}
    local cfg = self.effect_config or {}

    local en = ctx.event_name
    local do_scoring_shake = en == "on_hand_scored"
    if self.effect_type == "Stone card hands" and en == "on_blind_selected" then do_scoring_shake = true end
    if self.effect_type == "Destroy Joker" and (en == "on_blind_selected" or en == "on_hand_scored") then do_scoring_shake = true end
    if do_scoring_shake and not ctx._suppress_joker_apply_shake then
        self.scoring_shake_timer = SHAKE_MAX_DURATION
        self.scoring_shake_t0 = love.timer.getTime()
    end

    if self.effect_type == "Mult" then
        local amount = tonumber(cfg.mult) or 0
        ctx.mult = (tonumber(ctx.mult) or 0) + amount
        Sfx.play_mult()
    elseif self.effect_type == "Chips" then
        local amount = tonumber(cfg.chips) or 0
        ctx.chips = (tonumber(ctx.chips) or 0) + amount
    elseif self.effect_type == "Suit Mult" then
        local extra = type(cfg.extra) == "table" and cfg.extra or {}
        local amount = tonumber(extra.s_mult) or 0
        ctx.mult = (tonumber(ctx.mult) or 0) + amount
        Sfx.play_mult()
    elseif self.effect_type == "Suit Chips" then
        local extra = type(cfg.extra) == "table" and cfg.extra or {}
        local amount = tonumber(extra.s_chips) or 0
        ctx.chips = (tonumber(ctx.chips) or 0) + amount
    elseif self.effect_type == "Type Mult" then
        local amount = tonumber(cfg.t_mult) or 0
        ctx.mult = (tonumber(ctx.mult) or 0) + amount
        Sfx.play_mult()
    elseif self.effect_type == "Type Chips" then
        local amount = tonumber(cfg.t_chips) or 0
        ctx.chips = (tonumber(ctx.chips) or 0) + amount
    elseif self.effect_type == "Hand Size Mult" then
        local extra = type(cfg.extra) == "table" and cfg.extra or {}
        local amount = tonumber(extra.mult) or tonumber(cfg.mult) or 0
        ctx.mult = (tonumber(ctx.mult) or 0) + amount
        Sfx.play_mult()
    elseif self.effect_type == "Stencil Mult" then
        local free_slots = tonumber(ctx.free_joker_slots) or 0
        local factor = free_slots + 1
        ctx.mult = (tonumber(ctx.mult) or 0) * factor
        Sfx.play_mult2()
    elseif self.effect_type == "Discard Chips" then
        local extra = tonumber(cfg.extra) or 0
        local discards_left = tonumber((ctx and ctx.discards_left) or (G and G.discards)) or 0
        ctx.chips = (tonumber(ctx.chips) or 0) + (extra * math.max(0, discards_left))
    elseif self.effect_type == "No Discard Mult" then
        local extra = type(cfg.extra) == "table" and cfg.extra or {}
        local amount = tonumber(extra.mult) or tonumber(cfg.mult) or 0
        ctx.mult = (tonumber(ctx.mult) or 0) + amount
        Sfx.play_mult()
    elseif self.effect_type == "Stone card hands" then
        local deck = (ctx and ctx.deck) or (G and G.deck)
        if not (deck and deck.cards) then
            return
        end
        local suits = { "Hearts", "Clubs", "Diamonds", "Spades" }
        local MIN_RANK = 2
        local MAX_RANK = 14
        local suit = suits[math.random(1, #suits)]
        local rank = math.random(MIN_RANK, MAX_RANK)
        table.insert(deck.cards, { rank = rank, suit = suit, enhancement = "stone" })
    elseif self.effect_type == "1 in 6 mult" or self.effect_type == "1 in 10 mult" then
        local extra = type(cfg.extra) == "table" and cfg.extra or {}
        local factor = tonumber(extra.Xmult) or tonumber(cfg.Xmult) or 1
        ctx.mult = (tonumber(ctx.mult) or 0) * factor
        Sfx.play_mult2()

    elseif self.effect_type == "Destroy Joker" then
        if ctx.event_name == "on_hand_scored" then
            local amount = tonumber(self.stored_mult) or 0
            if amount > 0 then
                ctx.mult = (tonumber(ctx.mult) or 0) + amount
                Sfx.play_mult()
            end
            return
        end

        local joker_list = G and type(G.jokers) == "table" and G.jokers
        if not joker_list then
            return
        end

        local self_index = nil
        for i, joker in ipairs(joker_list) do
            if joker == self then
                self_index = i
                break
            end
        end

        local target_index = self_index and (self_index + 1) or nil
        if target_index and joker_list[target_index] then
            local victim = joker_list[target_index]
            local gained = tonumber(victim and victim.sell_cost) or 0
            self.stored_mult = (tonumber(self.stored_mult) or 0) + (gained * 2)
            if G and G.remove_owned_joker_at then
                G:remove_owned_joker_at(target_index)
            else
                victim = table.remove(joker_list, target_index)
                if victim and G and G.remove then
                    G:remove(victim)
                end
            end
            Sfx.play("resources/sounds/slice1.ogg")

        end
    end
end

local DEFAULT_IMPL = {
    matches_trigger = function(joker, event_name, ctx)
        return legacy_matches_trigger(joker, event_name, ctx) == true
    end,
    apply_effect = function(joker, ctx)
        legacy_apply_effect(joker, ctx)
    end,
}

--- Blueprint / Brainstorm: only copy when `src` would fire; shake the copycat, not `src`.
local function delegate_joker_effect(delegator, src, ctx)
    if type(src) ~= "table" or type(src.apply_effect) ~= "function" then return end
    local en = type(ctx) == "table" and ctx.event_name or nil
    if type(en) == "string" and en ~= "" and type(src.matches_trigger) == "function" then
        if src:matches_trigger(en, ctx) ~= true then return end
    end
    local prev_suppress = type(ctx) == "table" and ctx._suppress_joker_apply_shake or nil
    if type(ctx) == "table" then ctx._suppress_joker_apply_shake = true end
    src:apply_effect(ctx)
    if type(ctx) == "table" then ctx._suppress_joker_apply_shake = prev_suppress end
    if delegator then
        delegator.scoring_shake_timer = SHAKE_MAX_DURATION
        delegator.scoring_shake_t0 = love.timer.getTime()
    end
end

local SPECIAL = {
    j_blueprint = {
        matches_trigger = function(_, _, _) return true end,
        apply_effect = function(joker, ctx)
            if type(G and G.jokers) ~= "table" then return end
            for i, jj in ipairs(G.jokers) do
                if jj == joker then
                    delegate_joker_effect(joker, G.jokers[i + 1], ctx)
                    return
                end
            end
        end,
        tooltip_lines = function() return { "Copies ability of Joker to the right" } end
    },
    j_brainstorm = {
        matches_trigger = function(_, _, _) return true end,
        apply_effect = function(brainstorm, ctx)
            local src = G and G.jokers and G.jokers[1]
            if src == brainstorm then return end
            delegate_joker_effect(brainstorm, src, ctx)
        end,
        tooltip_lines = function() return { "Copies ability of leftmost Joker" } end
    },
    j_misprint = {
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        apply_effect = function(_, ctx) add_mult(ctx, math.random(0, 23)) end
    },
    j_abstract = {
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        apply_effect = function(_, ctx) add_mult(ctx, 3 * ((G and G.jokers and #G.jokers) or 0)) end
    },
    j_supernova = {
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        apply_effect = function(_, ctx)
            local i = tonumber(ctx.hand_index)
            local c = (G and G.hand_play_counts and i and G.hand_play_counts[i]) or 0
            add_mult(ctx, c)
        end
    },
    j_banner = {
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        apply_effect = function(_, ctx) add_chips(ctx, 30 * (tonumber(ctx.discards_left) or tonumber(G and G.discards) or 0)) end
    },
    j_blue_joker = {
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        apply_effect = function(_, ctx) add_chips(ctx, 2 * count_full_deck()) end
    },
    j_stone_joker = {
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        apply_effect = function(_, ctx) add_chips(ctx, 25 * count_full_deck(function(c) return c.enhancement == "stone" end)) end
    },
    j_bull = {
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        apply_effect = function(_, ctx) add_chips(ctx, 2 * (tonumber(G and G.money) or 0)) end
    },
    j_bootstraps = {
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        apply_effect = function(_, ctx) add_mult(ctx, math.floor((tonumber(G and G.money) or 0) / 5) * 2) end
    },
    j_green_joker = {
        matches_trigger = function(_, e) return e == "on_hand_played" or e == "on_discard" or e == "on_hand_scored" end,
        apply_effect = function(j, ctx)
            if ctx.event_name == "on_hand_played" then j.stored_mult = (tonumber(j.stored_mult) or 0) + 1
            elseif ctx.event_name == "on_discard" then j.stored_mult = (tonumber(j.stored_mult) or 0) - 1
            else add_mult(ctx, tonumber(j.stored_mult) or 0) end
        end
    },
    j_runner = {
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        apply_effect = function(j, ctx)
            if has_hand_type(ctx, "Straight") then j.stored_chips = (tonumber(j.stored_chips) or 0) + 15 end
            add_chips(ctx, tonumber(j.stored_chips) or 0)
        end
    },
    j_square = {
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        apply_effect = function(j, ctx)
            if type(ctx.cards) == "table" and #ctx.cards == 4 then j.stored_chips = (tonumber(j.stored_chips) or 0) + 4 end
            add_chips(ctx, tonumber(j.stored_chips) or 0)
        end
    },
    j_spare_trousers = {
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        apply_effect = function(j, ctx)
            if has_hand_type(ctx, "Two Pair") then j.stored_mult = (tonumber(j.stored_mult) or 0) + 2 end
            add_mult(ctx, tonumber(j.stored_mult) or 0)
        end
    },
    j_flash_card = {
        matches_trigger = function(_, e) return e == "on_shop_reroll" or e == "on_hand_scored" end,
        apply_effect = function(j, ctx)
            if ctx.event_name == "on_shop_reroll" then j.stored_mult = (tonumber(j.stored_mult) or 0) + 2
            else add_mult(ctx, tonumber(j.stored_mult) or 0) end
        end
    },
    j_popcorn = {
        matches_trigger = function(_, e) return e == "on_round_end" or e == "on_hand_scored" end,
        apply_effect = function(j, ctx)
            if j.runtime_counter == 0 then j.stored_mult = 20 end
            if ctx.event_name == "on_round_end" then
                j.stored_mult = math.max(0, (tonumber(j.stored_mult) or 0) - 4)
            else
                add_mult(ctx, tonumber(j.stored_mult) or 0)
            end
            j.runtime_counter = (tonumber(j.runtime_counter) or 0) + 1
        end
    },
    j_constellation = {
        matches_trigger = function(_, e) return e == "on_consumable_used" or e == "on_hand_scored" end,
        apply_effect = function(j, ctx)
            if ctx.event_name == "on_consumable_used" and ctx.consumable_kind == "planet" then
                j.stored_xmult = (tonumber(j.stored_xmult) or 1) + 0.1
            elseif ctx.event_name == "on_hand_scored" then
                mul_mult(ctx, tonumber(j.stored_xmult) or 1)
            end
        end
    },
    j_hologram = {
        matches_trigger = function(_, e) return e == "on_shop_buy" or e == "on_hand_scored" end,
        apply_effect = function(j, ctx)
            if ctx.event_name == "on_shop_buy" and ctx.offer_kind ~= "joker" then
                j.stored_xmult = (tonumber(j.stored_xmult) or 1) + 0.25
            elseif ctx.event_name == "on_hand_scored" then
                mul_mult(ctx, tonumber(j.stored_xmult) or 1)
            end
        end
    },
    j_lucky_cat = {
        matches_trigger = function(_, e) return e == "card_played" or e == "on_hand_scored" end,
        apply_effect = function(j, ctx)
            if ctx.event_name == "card_played" and math.random(1, 5) == 1 then
                j.stored_xmult = (tonumber(j.stored_xmult) or 1) + 0.25
            elseif ctx.event_name == "on_hand_scored" then
                mul_mult(ctx, tonumber(j.stored_xmult) or 1)
            end
        end
    },
    j_campfire = {
        matches_trigger = function(_, e) return e == "on_joker_sold" or e == "on_round_end" or e == "on_hand_scored" end,
        apply_effect = function(j, ctx)
            if ctx.event_name == "on_joker_sold" then
                j.stored_xmult = (tonumber(j.stored_xmult) or 1) + 0.25
            elseif ctx.event_name == "on_round_end" and ctx.is_boss_blind then
                j.stored_xmult = 1
            elseif ctx.event_name == "on_hand_scored" then
                mul_mult(ctx, tonumber(j.stored_xmult) or 1)
            end
        end
    },
    j_certificate = {
        matches_trigger = function(_, e) return e == "on_round_begin" end,
        apply_effect = function(_, _)
            local hand = G and G.hand
            if not hand or not hand.add_card then return end
            local suits = { "Hearts", "Clubs", "Diamonds", "Spades" }
            local seals = { "gold", "red", "blue", "purple" }
            local cd = {
                rank = math.random(2, 14),
                suit = suits[math.random(1, #suits)],
                enhancement = nil,
                seal = seals[math.random(1, #seals)],
            }
            hand:add_card(cd, true)
        end,
    },
    j_egg = { matches_trigger = function(_, e) return e == "on_round_end" end, apply_effect = function(j, _) j.sell_cost = (tonumber(j.sell_cost) or 0) + 3 end },
    j_golden_joker = { matches_trigger = function(_, e) return e == "on_round_end" end, apply_effect = function(_, _) add_money(4) end },
    j_cloud_9 = {
        matches_trigger = function(_, e) return e == "on_round_end" end,
        apply_effect = function(_, _) add_money(count_full_deck(function(c) return tonumber(c.rank) == 9 end)) end
    },
    j_to_the_moon = { matches_trigger = function(_, e) return e == "on_round_end" end, apply_effect = function(_, _) add_money(math.floor((tonumber(G and G.money) or 0) / 5)) end },
    j_reserved_parking = {
        matches_trigger = function(_, e) return e == "card_held" end,
        apply_effect = function(_, ctx) if rank_is_face(ctx.rank) and math.random(1, 2) == 1 then add_money(1) end end
    },
    j_baron = { matches_trigger = function(_, e) return e == "card_held" end, apply_effect = function(_, ctx) if tonumber(ctx.rank) == 13 then mul_mult(ctx, 1.5) end end },
    j_shoot_the_moon = { matches_trigger = function(_, e) return e == "card_held" end, apply_effect = function(_, ctx) if tonumber(ctx.rank) == 12 then add_mult(ctx, 13) end end },
    j_scary_face = { matches_trigger = function(_, e) return e == "card_played" end, apply_effect = function(_, ctx) if rank_is_face(ctx.rank) then add_chips(ctx, 30) end end },
    j_smiley_face = { matches_trigger = function(_, e) return e == "card_played" end, apply_effect = function(_, ctx) if rank_is_face(ctx.rank) then add_mult(ctx, 5) end end },
    j_even_steven = { matches_trigger = function(_, e) return e == "card_played" end, apply_effect = function(_, ctx) if rank_is_even(ctx.rank) then add_mult(ctx, 4) end end },
    j_odd_todd = { matches_trigger = function(_, e) return e == "card_played" end, apply_effect = function(_, ctx) if rank_is_odd(ctx.rank) then add_chips(ctx, 31) end end },
    j_scholar = { matches_trigger = function(_, e) return e == "card_played" end, apply_effect = function(_, ctx) if tonumber(ctx.rank) == 14 then add_chips(ctx, 20); add_mult(ctx, 4) end end },
    j_fibonacci = {
        matches_trigger = function(_, e) return e == "card_played" end,
        apply_effect = function(_, ctx)
            local r = tonumber(ctx.rank)
            if r == 14 or r == 2 or r == 3 or r == 5 or r == 8 then add_mult(ctx, 8) end
        end
    },
    j_rough_gem = { matches_trigger = function(_, e) return e == "card_played" end, apply_effect = function(_, ctx) if ctx.suit == "Diamonds" then add_money(1) end end },
    j_arrowhead = { matches_trigger = function(_, e) return e == "card_played" end, apply_effect = function(_, ctx) if ctx.suit == "Spades" then add_chips(ctx, 50) end end },
    j_onyx_agate = { matches_trigger = function(_, e) return e == "card_played" end, apply_effect = function(_, ctx) if ctx.suit == "Clubs" then add_mult(ctx, 7) end end },
    j_bloodstone = {
        matches_trigger = function(_, e) return e == "card_played" end,
        apply_effect = function(_, ctx) if ctx.suit == "Hearts" and math.random(1, 2) == 1 then mul_mult(ctx, 1.5) end end
    },
    j_8_ball = {
        matches_trigger = function(_, e) return e == "card_played" end,
        apply_effect = function(joker, ctx)
            if tonumber(ctx.rank) ~= 8 then return end
            local odds = tonumber((joker.effect_config or {}).extra) or 4
            odds = math.max(2, odds)
            if math.random(1, odds) ~= 1 then return end
            if not G or not G.can_add_consumable or not G.add_consumable or not G.random_consumable_id_of_kind then return end
            if not G:can_add_consumable() then return end
            local tid = G:random_consumable_id_of_kind("tarot")
            if tid then G:add_consumable(tid) end
        end,
    },
    j_riff_raff = {
        matches_trigger = function(_, e) return e == "on_blind_selected" end,
        apply_effect = function(_, _)
            if not (G and G.add_joker_by_def and JOKER_DEFS) then return end
            local spawned = 0
            for id, def in pairs(JOKER_DEFS) do
                if tonumber(def.rarity) == 1 and G:add_joker_by_def(id) then
                    spawned = spawned + 1
                    if spawned >= 2 then break end
                end
            end
        end
    },
    j_duo = { matches_trigger = function(_, e) return e == "on_hand_scored" end, apply_effect = function(_, ctx) if has_hand_type(ctx, "Pair") then mul_mult(ctx, 2) end end },
    j_trio = { matches_trigger = function(_, e) return e == "on_hand_scored" end, apply_effect = function(_, ctx) if has_hand_type(ctx, "Three of a Kind") then mul_mult(ctx, 3) end end },
    j_family = { matches_trigger = function(_, e) return e == "on_hand_scored" end, apply_effect = function(_, ctx) if has_hand_type(ctx, "Four of a Kind") then mul_mult(ctx, 4) end end },
    j_order = { matches_trigger = function(_, e) return e == "on_hand_scored" end, apply_effect = function(_, ctx) if has_hand_type(ctx, "Straight") then mul_mult(ctx, 3) end end },
    j_tribe = { matches_trigger = function(_, e) return e == "on_hand_scored" end, apply_effect = function(_, ctx) if has_hand_type(ctx, "Flush") then mul_mult(ctx, 2) end end },
    j_wee = {
        matches_trigger = function(_, e) return e == "card_played" or e == "on_hand_scored" end,
        apply_effect = function(j, ctx)
            if ctx.event_name == "card_played" and tonumber(ctx.rank) == 2 then
                j.stored_chips = (tonumber(j.stored_chips) or 0) + 8
            elseif ctx.event_name == "on_hand_scored" then
                add_chips(ctx, tonumber(j.stored_chips) or 0)
            end
        end
    },
    j_flower_pot = {
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        apply_effect = function(_, ctx)
            local suits = {}
            for _, n in ipairs((ctx and ctx.cards) or {}) do
                local s = n and n.card_data and n.card_data.suit
                if s then suits[s] = true end
            end
            if suits.Hearts and suits.Clubs and suits.Diamonds and suits.Spades then
                mul_mult(ctx, 3)
            end
        end
    },
    j_business = { matches_trigger = function(_, e) return e == "card_played" end, apply_effect = function(_, ctx) if rank_is_face(ctx.rank) and math.random(1, 2) == 1 then add_money(2) end end },
    j_ticket = { matches_trigger = function(_, e) return e == "card_played" end, apply_effect = function(_, ctx) local cd = ctx.card_node and ctx.card_node.card_data; if cd and cd.enhancement == "gold" then add_money(4) end end },
    j_photograph = {
        matches_trigger = function(_, e) return e == "card_played" or e == "on_hand_played" end,
        apply_effect = function(j, ctx)
            if ctx.event_name == "on_hand_played" then
                return
            end
            local target = ctx.photograph_first_face_node
            if not target or ctx.card_node ~= target then
                return
            end
            local r = tonumber(ctx.rank)
            if ctx.photograph_pareidolia or rank_is_face(r) then
                mul_mult(ctx, 2)
                if not ctx._suppress_joker_apply_shake then
                    j.scoring_shake_timer = SHAKE_MAX_DURATION
                    j.scoring_shake_t0 = love.timer.getTime()
                end
            end
        end
    },
    j_steel_joker = {
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        apply_effect = function(_, ctx) mul_mult(ctx, 1 + 0.2 * count_full_deck(function(c) return c.enhancement == "steel" end)) end
    },
    j_blackboard = {
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        apply_effect = function(_, ctx)
            local cards = held_cards(ctx)
            if #cards == 0 then return end
            for _, c in ipairs(cards) do
                if c.suit ~= "Spades" and c.suit ~= "Clubs" then return end
            end
            mul_mult(ctx, 3)
        end
    },
    j_erosion = {
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        apply_effect = function(_, ctx)
            local cnt = count_full_deck()
            add_mult(ctx, math.max(0, (52 - cnt) * 4))
        end
    },
    j_drivers_license = {
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        apply_effect = function(_, ctx)
            local enhanced = count_full_deck(function(c) return c.enhancement ~= nil and c.enhancement ~= "" end)
            if enhanced >= 16 then mul_mult(ctx, 3) end
        end
    },
    j_throwback = {
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        apply_effect = function(j, ctx)
            local skipped = tonumber(j.runtime_counter) or 0
            mul_mult(ctx, 1 + (0.25 * skipped))
        end
    },
    j_yorick = {
        matches_trigger = function(_, e) return e == "on_discard" or e == "on_hand_scored" end,
        apply_effect = function(j, ctx)
            if ctx.event_name == "on_discard" then
                local n = type(ctx.discarded_cards) == "table" and #ctx.discarded_cards or 0
                j.runtime_counter = (tonumber(j.runtime_counter) or 0) + n
                while (tonumber(j.runtime_counter) or 0) >= 23 do
                    j.runtime_counter = j.runtime_counter - 23
                    j.stored_xmult = (tonumber(j.stored_xmult) or 1) + 1
                end
            else
                mul_mult(ctx, tonumber(j.stored_xmult) or 1)
            end
        end
    },
    j_triboulet = {
        matches_trigger = function(_, e) return e == "card_played" end,
        apply_effect = function(_, ctx) local r = tonumber(ctx.rank); if r == 12 or r == 13 then mul_mult(ctx, 2) end end
    },
    j_caino = {
        matches_trigger = function(_, e) return e == "on_discard" or e == "on_hand_scored" end,
        apply_effect = function(j, ctx)
            if ctx.event_name == "on_discard" and type(ctx.discarded_cards) == "table" then
                for _, c in ipairs(ctx.discarded_cards) do
                    local r = tonumber(c and c.rank)
                    if r == 11 or r == 12 or r == 13 then
                        j.stored_xmult = (tonumber(j.stored_xmult) or 1) + 1
                    end
                end
            else
                mul_mult(ctx, tonumber(j.stored_xmult) or 1)
            end
        end
    },
}

function JokerEffects.get(joker)
    local def = joker and joker.def or {}
    local id = def.id
    if SPECIAL[id] then return SPECIAL[id] end
    return DEFAULT_IMPL
end

