JokerEffects = {}

JokerEffects.SHAKE_MAX_DURATION = 0.22

local function has_hand_type(ctx, name)
    if not ctx then return false end
    if ctx.hand_type == name then return true end
    local contains = ctx.contains_hand_types
    return type(contains) == "table" and contains[name] == true
end

local function mark_effect_applied(ctx)
    if type(ctx) ~= "table" then return end
    ctx._joker_effect_applied = true
    ctx._joker_effect_applied_now = true
end

local function mark_created_item(ctx)
    if type(ctx) ~= "table" then return end
    ctx._joker_effect_created_item = true
    ctx._joker_effect_created_item_now = true
end

local function add_mult(ctx, n)
    ctx.mult = (tonumber(ctx.mult) or 0) + (tonumber(n) or 0)
    if(n > 0) then 
        mark_effect_applied(ctx)
        Sfx.play_mult()
    end
end
local function add_chips(ctx, n)
    ctx.chips = (tonumber(ctx.chips) or 0) + (tonumber(n) or 0)
    if(n > 0) then 
        mark_effect_applied(ctx) 
        Sfx.play_chips()
    end
end
local function mul_mult(ctx, n)
    ctx.mult = (tonumber(ctx.mult) or 1) * (tonumber(n) or 1)
    if(n > 1) then
        mark_effect_applied(ctx)
        Sfx.play_mult2()
    end
end
local function add_money(ctx, n)
    if G and G.money ~= nil then
        G.money = (tonumber(G.money) or 0) + (tonumber(n) or 0)
        if(n > 0) then 
            mark_effect_applied(ctx) 
            Sfx.play_money()
        end
    end
end

--- During `on_round_end`, register money for the round-win payout table (and wallet) when available.
local function add_round_win_money(ctx, joker, n)
    n = math.floor(tonumber(n) or 0)
    if n <= 0 then return end
    if type(ctx) == "table" and type(ctx.add_round_win_payout) == "function" then
        local label = (joker and joker.def and joker.def.name) or "Joker"
        ctx.add_round_win_payout(label, n)
    else
        add_money(ctx, n)
    end
end
local function rank_is_face(rank) rank = tonumber(rank); return rank == 11 or rank == 12 or rank == 13 or G:hasJoker("j_pareidolia") end
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

local function deep_copy_runtime_value(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, vv in pairs(v) do
        out[k] = deep_copy_runtime_value(vv)
    end
    return out
end

local function copy_joker_runtime_state(dst, src)
    if type(dst) ~= "table" or type(src) ~= "table" then return end
    local skip = {
        def = true, params = true, effect_impl = true,
        T = true, VT = true, velocity = true, drag = true, hovering = true,
        _hover_last = true, _touch_state = true, children = true, parent = true,
        front_quads = true, back_quads = true, sprite_batch = true,
    }
    for k, v in pairs(src) do
        if not skip[k] and type(v) ~= "function" then
            dst[k] = deep_copy_runtime_value(v)
        end
    end
end

--- Lowest `card_data.rank` among cards still in hand but not in the current play (`ctx.cards` are played nodes).
local function lowest_rank_among_held_not_played(ctx)
    local played = {}
    for _, n in ipairs((ctx and ctx.cards) or {}) do
        played[n] = true
    end
    local lowest = nil
    local hand_nodes = G and G.hand and G.hand.card_nodes or {}
    for _, node in ipairs(hand_nodes) do
        if not played[node] and node and node.card_data then
            local r = tonumber(node.card_data.rank)
            if r and (lowest == nil or r < lowest) then
                lowest = r
            end
        end
    end
    return lowest
end

--- Default trigger matching for catalog-driven `effect_type` jokers (non-SPECIAL ids).
local function legacy_matches_trigger(self, event_name, ctx)
    if self.effect_type == "Hand card double"
        or self.effect_type == "Low Card double"
        or self.effect_type == "Face card double" then
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

    if self.effect_type == "Mult" then
        add_mult(ctx, tonumber(cfg.mult) or 0)
    elseif self.effect_type == "Chips" then
        add_chips(ctx, tonumber(cfg.chips) or 0)
    elseif self.effect_type == "Suit Mult" then
        local extra = type(cfg.extra) == "table" and cfg.extra or {}
        add_mult(ctx, tonumber(extra.s_mult) or 0)
    elseif self.effect_type == "Suit Chips" then
        local extra = type(cfg.extra) == "table" and cfg.extra or {}
        add_chips(ctx, tonumber(extra.s_chips) or 0)
    elseif self.effect_type == "Type Mult" then
        add_mult(ctx, tonumber(cfg.t_mult) or 0)
    elseif self.effect_type == "Type Chips" then
        add_chips(ctx, tonumber(cfg.t_chips) or 0)
    elseif self.effect_type == "Hand Size Mult" then
        local extra = type(cfg.extra) == "table" and cfg.extra or {}
        add_mult(ctx, tonumber(extra.mult) or tonumber(cfg.mult) or 0)
    elseif self.effect_type == "Stencil Mult" then
        local free_slots = tonumber(ctx.free_joker_slots) or 0
        local factor = free_slots + 1
        mul_mult(ctx, factor)
    elseif self.effect_type == "Discard Chips" then
        local extra = tonumber(cfg.extra) or 0
        local discards_left = tonumber((ctx and ctx.discards_left) or (G and G.discards)) or 0
        add_chips(ctx, extra * math.max(0, discards_left))
    elseif self.effect_type == "No Discard Mult" then
        local extra = type(cfg.extra) == "table" and cfg.extra or {}
        add_mult(ctx, tonumber(extra.mult) or tonumber(cfg.mult) or 0)
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
        mark_effect_applied(ctx)
        mark_created_item(ctx)
    elseif self.effect_type == "1 in 6 mult" or self.effect_type == "1 in 10 mult" then
        local extra = type(cfg.extra) == "table" and cfg.extra or {}
        local factor = tonumber(extra.Xmult) or tonumber(cfg.Xmult) or 1
        mul_mult(ctx, factor)

    elseif self.effect_type == "Destroy Joker" then
        if ctx.event_name == "on_hand_scored" then
            local amount = tonumber(self.stored_mult) or 0
            if amount > 0 then
                add_mult(ctx, amount)
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
            mark_effect_applied(ctx)
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
    query_retrigger = function()
        return 0
    end,
}

--- Blueprint / Brainstorm: only copy when `src` would fire; shake the copycat, not `src`.
local function is_blueprint_copy_target(src)
    if type(src) ~= "table" then return false end
    local def = src.def
    if type(def) ~= "table" then return false end
    return def.blueprint_compat == true
end

local function delegate_joker_effect(delegator, src, ctx)
    if not is_blueprint_copy_target(src) then return end
    if type(src) ~= "table" or type(src.apply_effect) ~= "function" then return end
    local en = type(ctx) == "table" and ctx.event_name or nil
    if type(en) == "string" and en ~= "" and type(src.matches_trigger) == "function" then
        if src:matches_trigger(en, ctx) ~= true then return end
    end
    local prev_suppress = type(ctx) == "table" and ctx._suppress_joker_apply_shake or nil
    if type(ctx) == "table" then ctx._suppress_joker_apply_shake = true end
    src:apply_effect(ctx)
    if type(ctx) == "table" then ctx._suppress_joker_apply_shake = prev_suppress end
end

local function delegate_joker_retrigger(delegator, src, ctx)
    if type(src) ~= "table" or src == delegator then return 0 end
    if not is_blueprint_copy_target(src) then return 0 end
    if type(src.query_retrigger) ~= "function" then return 0 end
    return tonumber(src:query_retrigger(ctx)) or 0
end

local function first_scoring_play_node(played_cards)
    if type(played_cards) ~= "table" then return nil end
    for _, n in ipairs(played_cards) do
        if n and n.counts_for_play_score == true then
            return n
        end
    end
    return nil
end

local SPECIAL = {
    j_hanging_chad = {
        matches_trigger = function(joker, event_name, ctx)
            return legacy_matches_trigger(joker, event_name, ctx) == true
        end,
        apply_effect = function(joker, ctx)
            legacy_apply_effect(joker, ctx)
        end,
        query_retrigger = function(joker, ctx)
            if ctx.held then return 0 end
            local node = ctx.card_node or ctx.retrigger_card
            local first = first_scoring_play_node(ctx.played_cards)
            if not first or node ~= first then return 0 end
            local n = tonumber((joker.effect_config or {}).extra)
            if n == nil and type(joker.def) == "table" and type(joker.def.config) == "table" then
                n = tonumber(joker.def.config.extra)
            end
            n = n or 2
            return math.max(0, n)
        end,
    },
    j_mime = {
        matches_trigger = function(joker, event_name, ctx)
            return legacy_matches_trigger(joker, event_name, ctx) == true
        end,
        apply_effect = function(joker, ctx)
            legacy_apply_effect(joker, ctx)
        end,
        query_retrigger = function(_, ctx)
            if ctx.held then return 1 end
            return 0
        end,
    },
    j_hack = {
        matches_trigger = function(joker, event_name, ctx)
            return legacy_matches_trigger(joker, event_name, ctx) == true
        end,
        apply_effect = function(joker, ctx)
            legacy_apply_effect(joker, ctx)
        end,
        query_retrigger = function(_, ctx)
            if ctx.held then return 0 end
            local node = ctx.card_node or ctx.retrigger_card
            local r = tonumber(node and node.card_data and node.card_data.rank)
            if r and r >= 2 and r <= 5 then return 1 end
            return 0
        end,
    },
    j_sock_and_buskin = {
        matches_trigger = function(joker, event_name, ctx)
            return legacy_matches_trigger(joker, event_name, ctx) == true
        end,
        apply_effect = function(joker, ctx)
            legacy_apply_effect(joker, ctx)
        end,
        query_retrigger = function(_, ctx)
            if ctx.held then return 0 end
            local node = ctx.card_node or ctx.retrigger_card
            local r = tonumber(node and node.card_data and node.card_data.rank)
            if rank_is_face(r) then return 1 end
            return 0
        end,
    },
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
        query_retrigger = function(joker, ctx)
            if type(G and G.jokers) ~= "table" then return 0 end
            for i, jj in ipairs(G.jokers) do
                if jj == joker then
                    return delegate_joker_retrigger(joker, G.jokers[i + 1], ctx)
                end
            end
            return 0
        end,
        tooltip_lines = function(joker)
            if type(G and G.jokers) ~= "table" then return {} end
            for i, jj in ipairs(G.jokers) do
                if jj == joker then
                    local src = G.jokers[i + 1]
                    if type(src) == "table" and not is_blueprint_copy_target(src) then
                        return { "Incompatible" }
                    end
                    break
                end
            end
            return {}
        end,
    },
    j_brainstorm = {
        matches_trigger = function(_, _, _) return true end,
        apply_effect = function(brainstorm, ctx)
            local src = G and G.jokers and G.jokers[1]
            if src == brainstorm then return end
            delegate_joker_effect(brainstorm, src, ctx)
        end,
        query_retrigger = function(brainstorm, ctx)
            local src = G and G.jokers and G.jokers[1]
            return delegate_joker_retrigger(brainstorm, src, ctx)
        end,
        tooltip_lines = function(joker)
            if type(G and G.jokers) ~= "table" then return {} end
            local src = G.jokers[1]
            if src == joker then return {} end
            if type(src) == "table" and not is_blueprint_copy_target(src) then
                return { "Incompatible" }
            end
            return {}
        end,
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
        apply_effect = function(_, ctx) 
            if count_full_deck(function(c) return c.enhancement == "stone" end) > 0 then
                add_chips(ctx, 25 * count_full_deck(function(c) return c.enhancement == "stone" end))
            end 
        end
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
            elseif ctx.event_name == "on_discard" and ctx.discard_reason == "discard" then j.stored_mult = (tonumber(j.stored_mult) or 0) - 1
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
        matches_trigger = function(_, e) return e == "lucky_trigger" or e == "on_hand_scored" end,
        apply_effect = function(j, ctx)
            if ctx.event_name == "lucky_trigger" then
                j.stored_xmult = (tonumber(j.stored_xmult) or 1) + 0.25
            elseif ctx.event_name == "on_hand_scored" and j.stored_xmult > 1 then
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
        apply_effect = function(_, ctx)
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
            mark_effect_applied(ctx)
            mark_created_item(ctx)
        end,
    },
    j_egg = { matches_trigger = function(_, e) return e == "on_round_end" end, apply_effect = function(j, ctx) j.sell_cost = (tonumber(j.sell_cost) or 0) + 3; mark_effect_applied(ctx) end },
    j_golden_joker = { matches_trigger = function(_, e) return e == "on_round_end" end, apply_effect = function(j, ctx) add_round_win_money(ctx, j, 4) end },
    j_cloud_9 = {
        matches_trigger = function(_, e) return e == "on_round_end" end,
        apply_effect = function(j, ctx) add_round_win_money(ctx, j, count_full_deck(function(c) return tonumber(c.rank) == 9 end)) end
    },
    j_to_the_moon = { matches_trigger = function(_, e) return e == "on_round_end" end, apply_effect = function(j, ctx) add_round_win_money(ctx, j, math.floor((tonumber(G and G.money) or 0) / 5)) end },
    j_reserved_parking = {
        matches_trigger = function(_, e) return e == "card_held" end,
        apply_effect = function(_, ctx) if rank_is_face(ctx.rank) and G:do_random(1, 2, 1) then add_money(ctx, 1) end end
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
    j_rough_gem = { matches_trigger = function(_, e) return e == "card_played" end, apply_effect = function(_, ctx) if ctx.suit == "Diamonds" then add_money(ctx, 1) end end },
    j_arrowhead = { matches_trigger = function(_, e) return e == "card_played" end, apply_effect = function(_, ctx) if ctx.suit == "Spades" then add_chips(ctx, 50) end end },
    j_onyx_agate = { matches_trigger = function(_, e) return e == "card_played" end, apply_effect = function(_, ctx) if ctx.suit == "Clubs" then add_mult(ctx, 7) end end },
    j_bloodstone = {
        matches_trigger = function(_, e) return e == "card_played" end,
        apply_effect = function(_, ctx) if ctx.suit == "Hearts" and G:do_random(1, 2, 1) then mul_mult(ctx, 1.5) end end
    },
    j_8_ball = {
        matches_trigger = function(_, e) return e == "card_played" end,
        apply_effect = function(joker, ctx)
            if tonumber(ctx.rank) ~= 8 then return end
            local odds = tonumber((joker.effect_config or {}).extra) or 4
            odds = math.max(2, odds)
            if not G:do_random(1, odds, 1) then return end
            if not G or not G.can_add_consumable or not G.add_consumable or not G.random_consumable_id_of_kind then return end
            if not G:can_add_consumable() then return end
            local tid = G:random_consumable_id_of_kind("tarot")
            if tid then
                G:add_consumable(tid)
                mark_effect_applied(ctx)
                mark_created_item(ctx)
            end
        end,
    },
    j_riff_raff = {
        matches_trigger = function(_, e) return e == "on_blind_selected" end,
        apply_effect = function(_, ctx)
            if not (G and G.add_joker_by_def and G.random_joker_def_id_by_rarity) then return end
            local spawned = 0
            local allow_duplicates = G.hasJoker and G:hasJoker("j_ring_master")
            if allow_duplicates then
                for _ = 1, 2 do
                    local id = G:random_joker_def_id_by_rarity(1)
                    if G:add_joker_by_def(id) then
                        spawned = spawned + 1
                        mark_effect_applied(ctx)
                        mark_created_item(ctx)
                    end
                end
            else
                local picked = {}
                local tries = 0
                local max_tries = 20
                while spawned < 2 and tries < max_tries do
                    tries = tries + 1
                    local id = G:random_joker_def_id_by_rarity(1)
                    if id and not picked[id] and G:add_joker_by_def(id) then
                        picked[id] = true
                        spawned = spawned + 1
                        mark_effect_applied(ctx)
                        mark_created_item(ctx)
                    end
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
    j_business = { matches_trigger = function(_, e) return e == "card_played" end, apply_effect = function(_, ctx) if rank_is_face(ctx.rank) and G:do_random(1, 2, 1) then add_money(ctx, 2) end end },
    j_ticket = { matches_trigger = function(_, e) return e == "card_played" end, apply_effect = function(_, ctx) local cd = ctx.card_node and ctx.card_node.card_data; if cd and cd.enhancement == "gold" then add_money(ctx, 4) end end },
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
            if rank_is_face(r) then
                mul_mult(ctx, 2)
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
            if ctx.event_name == "on_discard" and ctx.discard_reason == "discard" then
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
    j_canio = {
        matches_trigger = function(_, e) return e == "on_destroy" or e == "on_hand_scored" end,
        apply_effect = function(j, ctx)
            if ctx.event_name == "on_destroy" and type(ctx.destroyed_cards) == "table" then
                for _, c in ipairs(ctx.destroyed_cards) do
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
    j_fortune_teller = {
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        apply_effect = function(_, ctx)
            local tarot_uses = tonumber(G and G.tarots_used) or 0
            if tarot_uses <= 0 then return end
            add_mult(ctx, tarot_uses)
            mark_effect_applied(ctx)
        end
    },

    j_baseball_card = {
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        apply_effect = function(_, ctx)
            local list = G and G.jokers
            if type(list) ~= "table" then return end
            for _, jo in ipairs(list) do
                local r = jo and (tonumber(jo.rarity) or (jo.def and tonumber(jo.def.rarity)))
                if r == 2 then
                    mul_mult(ctx, 1.5)
                end
            end
        end,
    },
    j_trading_card = {
        matches_trigger = function(_, e, ctx) return e == "on_discard" and ctx.discard_reason == "discard" end,
        apply_effect = function(_, ctx)
            local discardCount = G:get_effective_discards_per_round() - 1
            local discarded = ctx.discarded_cards
            if type(discarded) ~= "table" or #discarded ~= 1 or discardCount ~= G.discards then return end
            local deck = G and G.deck
            local pile = deck and deck.discard_pile
            if type(pile) ~= "table" or #pile < 1 then return end
            local destroyed = table.remove(pile, #pile)
            if destroyed and G and G.emit_on_destroy_cards and Deck and Deck.copy_card_data then
                local snap = Deck.copy_card_data(destroyed)
                if snap then
                    G:emit_on_destroy_cards({ snap })
                end
            end
            add_money(ctx, 3)
        end,
    },

    j_ancient_joker = {
        matches_trigger = function(_,e) return e == "card_played" or e == "on_round_end" end,
        apply_effect = function(j, ctx)
            if ctx.event_name == "card_played" and ctx.suit == j.random_suit then
                mul_mult(ctx, 1.5)
            elseif ctx.event_name == "on_round_end" then
                local suits = { "Hearts", "Clubs", "Diamonds", "Spades" }
                j.random_suit = suits[math.random(1, #suits)]
                mark_effect_applied(ctx)
            end
        end
    },

    j_ramen = {
        matches_trigger = function(_, e, ctx)
            if e == "on_hand_scored" then return true end
            if e == "on_discard" and type(ctx) == "table" and ctx.discard_reason == "discard" then
                return true
            end
            return false
        end,
        apply_effect = function(j, ctx)
            if ctx.event_name == "on_hand_scored" then
                mul_mult(ctx, tonumber(j.runtime_counter) or 1)
            elseif ctx.event_name == "on_discard" then
                local discardCount = type(ctx.discarded_cards) == "table" and #ctx.discarded_cards or 0
                if discardCount < 1 then return end
                local x = tonumber(j.runtime_counter) or 0
                j.runtime_counter = x - (0.01 * discardCount)
                if j.runtime_counter < 1 then
                    if G and type(G.jokers) == "table" and G.remove_owned_joker_at then
                        for i, jj in ipairs(G.jokers) do
                            if jj == j then
                                Sfx.play("resources/sounds/slice1.ogg")
                                G:remove_owned_joker_at(i)
                                break
                            end
                        end
                    end
                    return
                end
                mark_effect_applied(ctx)
            end
        end
    },

    j_walkie_talkie = {
        matches_trigger = function(_, e) return e == "card_played" end,
        apply_effect = function(j, ctx)
            if ctx.event_name == "card_played" then
                if ctx.rank == 10 or ctx.rank == 4 then
                    add_chips(ctx, 10)
                    add_mult(ctx, 4)
                end
            end
        end
    },

    j_seltzer = {
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        apply_effect = function(j, ctx)
            j.runtime_counter = (tonumber(j.runtime_counter) or 0) - 1
            if (tonumber(j.runtime_counter) or 0) < 1 then
                if G and type(G.jokers) == "table" and G.remove_owned_joker_at then
                    for i, jj in ipairs(G.jokers) do
                        if jj == j then
                            Sfx.play("resources/sounds/slice1.ogg")
                            G:remove_owned_joker_at(i)
                            break
                        end
                    end
                end
            end
        end,
        query_retrigger = function(j, ctx)
            if (tonumber(j.runtime_counter) or 0) > 0 then
                return 1
            end
            return 0
        end
    },

    j_castle = {
        matches_trigger = function(_, e, ctx)
            if e == "on_hand_scored" then return true end
            if e == "on_discard" and type(ctx) == "table" and ctx.discard_reason == "discard" then
                return true
            end
            return false
        end,
        apply_effect = function(j, ctx)
            if ctx.event_name == "on_hand_scored" then
                add_chips(ctx, tonumber(j.runtime_counter) or 0)
            elseif ctx.event_name == "on_discard" then
                local discarded = ctx.discarded_cards
                for n,c in ipairs(discarded) do
                    if c.suit == j.random_suit then
                        j.runtime_counter = (tonumber(j.runtime_counter) or 0) + 3
                    end
                end
            end
        end
    },

    j_midas_mask = {
        matches_trigger = function(_, e) return e == "card_played" end,
        apply_effect = function(_, ctx)
            if rank_is_face(ctx.rank) then
                local node = ctx.card_node
                if node and type(node.set_enhancement) == "function" then
                    node:set_enhancement("gold")
                    mark_effect_applied(ctx)
                end
            end
        end
    },

    j_dusk = {
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        query_retrigger = function(joker, ctx)
            if G.hands == 0 then
                return 1
            end
            return 0
        end,
    },

    j_gros_michel = {
        matches_trigger = function(_, e) return e == "on_hand_scored" or e == "on_round_end" end,
        apply_effect = function(j, ctx)
            if ctx.event_name == "on_hand_scored" then
                add_mult(ctx, 15)
            else
                if G:do_random(1, 6, 1) then
                    if G and type(G.jokers) == "table" and G.remove_owned_joker_at then
                        for i, jj in ipairs(G.jokers) do
                            if jj == j then
                                Sfx.play("resources/sounds/slice1.ogg")
                                G:remove_owned_joker_at(i)
                                break
                            end
                        end
                    end
                    return
                end
            end
        end
    },

    j_ride_the_bus = {
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        apply_effect = function(j, ctx)
            local cards = (ctx and ctx.cards) or {}
            local face = false
            for _, node in ipairs(cards) do
                local r = node and node.card_data and node.card_data.rank
                if rank_is_face(r) then
                    face = true
                    break
                end
            end
            if not face then
                j.runtime_counter = (tonumber(j.runtime_counter) or 0) + 1
            else
                j.runtime_counter = 0
            end
            add_mult(ctx, tonumber(j.runtime_counter))
        end
    },

    j_space = {
        matches_trigger = function(_, e) return e == "on_hand_played" end,
        apply_effect = function(_, ctx)
            if not G:do_random(1, 4, 1) then return end
            local idx = ctx and tonumber(ctx.hand_index)
            if not G or not idx or not G.upgrade_hand_level_at_index then return end
            if G:upgrade_hand_level_at_index(idx) then
                mark_effect_applied(ctx)
            end
        end
    },

    j_ice_cream = {
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        apply_effect = function(j, ctx)
            add_chips(ctx, tonumber(j.runtime_counter) or 0)
            j.runtime_counter = tonumber(j.runtime_counter) - 5
            if tonumber(j.runtime_counter) <= 0 then
                if G and type(G.jokers) == "table" and G.remove_owned_joker_at then
                    for i, jj in ipairs(G.jokers) do
                        if jj == j then
                            Sfx.play("resources/sounds/slice1.ogg")
                            G:remove_owned_joker_at(i)
                            break
                        end
                    end
                end
                return
            end
        end
    },

    j_delayed_grat = {
        matches_trigger = function(_, e) return e == "on_round_end" end,
        apply_effect = function(j, ctx)
            local discards = G and G.discards or 0
            if G and G:get_effective_discards_per_round() == discards then
                add_round_win_money(ctx, j, 2 * discards)
            end
        end
    },

    j_raised_fist = {
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        apply_effect = function(_, ctx)
            if ctx.event_name ~= "on_hand_scored" then return end
            local r = lowest_rank_among_held_not_played(ctx)
            if r then
                if r == 14 then
                    r = 11
                elseif r > 10 then
                    r = 10
                end
                add_mult(ctx, r * 2)
            end
        end
    },

    j_dna = {
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        apply_effect = function(_, ctx)
            if ctx.event_name ~= "on_hand_scored" then return end
            if type(ctx.cards) ~= "table" or #ctx.cards ~= 1 then return end
            local eff = G and G.get_effective_hands_per_round and G:get_effective_hands_per_round()
            print(eff.." : "..G.hands)
            if (tonumber(G and G.hands) or 0) ~= eff - 1 then return end

            local node = ctx.cards[1]
            local cd = node and node.card_data
            local hand = G and G.hand
            if not cd or not hand or not hand.add_card then return end

            local copy = (G.deep_copy_card_data and G:deep_copy_card_data(cd)) or (Deck and Deck.copy_card_data(cd))
            if not copy then return end
            if G.ensure_card_uid then G:ensure_card_uid(copy) end
            if hand:add_card(copy, true) then
                mark_created_item(ctx)
            end
        end,
    },

    j_sixth_sense = {
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        apply_effect = function(_, ctx)
            if ctx.event_name ~= "on_hand_scored" then return end
            local eff = G and G.get_effective_hands_per_round and G:get_effective_hands_per_round() or 5
            if (tonumber(G and G.hands) or 0) ~= eff - 1 then return end
            if type(ctx.cards) ~= "table" or #ctx.cards ~= 1 then return end
            local node = ctx.cards[1]
            local cd = node and node.card_data
            if not cd or tonumber(cd.rank) ~= 6 then return end
            local hand = G and G.hand
            if not hand or not hand.destroy_card_node then return end
            if hand:destroy_card_node(node) then
                local tid = G:random_consumable_id_of_kind("spectral")
                if tid then
                    G:add_consumable(tid)
                    mark_created_item(ctx)
                end
                mark_effect_applied(ctx)
                Sfx.play("resources/sounds/slice1.ogg")
            end
        end,
    },

    j_hiker = {
        matches_trigger = function(_, e) return e == "card_played" end,
        apply_effect = function(j, ctx)
            if ctx.event_name ~= "card_played" then return end
            local node = ctx.card_node
            if not node or node.counts_for_play_score ~= true then return end
            local cd = node.card_data
            if type(cd) ~= "table" then return end
            local add = tonumber(j and j.effect_config and j.effect_config.extra) or 5
            add = math.floor(add)
            if add <= 0 then return end
            local cur = math.floor(tonumber(cd.Bonus) or tonumber(cd.bonus) or 0)
            cd.Bonus = cur + add
            cd.bonus = nil
            mark_effect_applied(ctx)
            Sfx.play_chips()
        end,
    },

    j_faceless = {
        matches_trigger = function(_, e) return e == "on_discard" end,
        apply_effect = function(j, ctx) 
            if(ctx.discard_reason == "discard") then
                local discarded = ctx.discarded_cards
                local faceCount = 0
                for n,c in ipairs(discarded) do
                    if rank_is_face(c.rank) then
                        faceCount = faceCount + 1
                    end
                end
                if faceCount >= 3 then
                    add_money(ctx, 5)
                end
            end
        end
    },

    j_cavendish = {
        matches_trigger = function(_, e) return e == "on_round_end" or e == "on_hand_scored" end,
        apply_effect = function(j, ctx)
            if ctx.event_name == "on_round_end" then
                if G:do_random(1, j.config and j.config.extra and j.config.extra.odds or 1000, 1) then
                    --Destroy Joker
                    if G and type(G.jokers) == "table" and G.remove_owned_joker_at then
                        for i, jj in ipairs(G.jokers) do
                            if jj == j then
                                Sfx.play("resources/sounds/slice1.ogg")
                                G:remove_owned_joker_at(i)
                                break
                            end
                        end
                    end
                end
            elseif ctx.event_name == "on_hand_scored" then
                mul_mult(ctx, j.config and j.config.extra and j.config.extra.Xmult or 3)
            end
        end
    },

    j_gift = {
        matches_trigger = function(_, e) return e == "on_round_end" end,
        apply_effect = function(j, ctx)
            if ctx.event_name ~= "on_round_end" then return end
            local add = tonumber(j and j.effect_config and j.effect_config.extra)
                or tonumber(j and j.def and j.def.config and j.def.config.extra) or 1
            add = math.max(0, math.floor(add))
            if add <= 0 then return end
            if G and type(G.jokers) == "table" then
                for _, jj in ipairs(G.jokers) do
                    if jj then
                        jj.sell_cost = (tonumber(jj.sell_cost) or 0) + add
                    end
                end
            end
            if G and type(G.consumables) == "table" then
                for i, c in ipairs(G.consumables) do
                    if type(c) == "table" then
                        c.sell_cost = (tonumber(c.sell_cost) or 0) + add
                        local node = G.consumable_nodes and G.consumable_nodes[i]
                        if node then
                            node.sell_cost = (tonumber(node.sell_cost) or 0) + add
                        end
                    end
                end
            end
            mark_effect_applied(ctx)
        end,
    },

    j_turtle_bean = {
        matches_trigger = function(_, e) return e == "on_round_end" end,
        apply_effect = function(j, ctx)
            j.runtime_counter = j.runtime_counter - 1 
            if j.runtime_counter < 1  then 
                --Destroy Joker
                if G and type(G.jokers) == "table" and G.remove_owned_joker_at then
                    for i, jj in ipairs(G.jokers) do
                        if jj == j then
                            Sfx.play("resources/sounds/slice1.ogg")
                            G:remove_owned_joker_at(i)
                            break
                        end
                    end
                end
            end
        end
    },

    j_red_card = {
        matches_trigger = function(_, e) return e == "on_booster_skip" or e == "on_hand_scored" end,
        apply_effect = function(j, ctx)
            if ctx.event_name == "on_booster_skip" then
                j.stored_mult = (tonumber(j.stored_mult) or 0) + 3
                mark_effect_applied(ctx)
            else
                add_mult(ctx, tonumber(j.stored_mult) or 0)
            end
        end
    },

    j_superposition = {
        matches_trigger = function(_, e) return e == "on_hand_played" end,
        apply_effect = function(j, ctx)
            local cards = ctx.cards
            if has_hand_type(ctx, "Straight") then 
                for _, card in ipairs(cards) do
                    if card.card_data.rank == 14 then
                        local tid = G:random_consumable_id_of_kind("tarot")
                        if tid then
                            G:add_consumable(tid)
                            mark_created_item(ctx)
                        end
                        return
                    end
                end
            end
        end
    },

    j_todo_list = {
        matches_trigger = function(_, e) return e == "on_hand_played" or e == "on_round_end" end,
        apply_effect = function(j, ctx)
            if ctx.event_name == "on_hand_played" then
                if ctx.hand_type == j.random_hand then
                    add_money(ctx, tonumber(j.config and j.config.extra and j.config.extra.dollars or 4))
                end
            else
                local found = false
                while not found do
                    local pos = math.random(1, #G.handlist)
                    if (pos < 4) then -- Secret hands only show if played before
                        if (G.hand_play_counts[pos] and G.hand_play_counts[pos] > 0) then
                            found = true
                        end
                    else
                        found = true
                    end
                    j.random_hand = G.handlist[pos]
                end
            end
        end
    },

    j_hallucination = {
        matches_trigger = function(_, e) return e == "on_booster_open" end,
        apply_effect = function(j, ctx)
            if ctx.event_name ~= "on_booster_open" then return end
            if G:do_random(1, j.config and j.config.extra or 2, 1) then
                local tid = G:random_consumable_id_of_kind("tarot")
                if tid then
                    G:add_consumable(tid)
                    mark_created_item(ctx)
                end
            end
        end
    },

    j_vampire = {
        matches_trigger = function(_,e) return e == "card_played" or e == "on_hand_scored" end,
        apply_effect = function(j, ctx)
            if ctx.event_name == "card_played" then
                card = ctx.card_node
                if(card.card_data.enhancement or card.card_data.enhancement ~= "none") then
                    j.stored_xmult = (tonumber(j.stored_xmult) or 0) + 0.1
                    card:set_enhancement("none")
                    mark_effect_applied(ctx)
                end
            else
                mul_mult(ctx, tonumber(j.stored_xmult) or 0)
            end
        end
    },

    j_vagabond = {
        matches_trigger = function(_, e) return e == "on_hand_played" end,
        apply_effect = function(_,ctx)
            if G and G.money and G.money < 4 then
                local tid = G:random_consumable_id_of_kind("tarot")
                if tid then
                    G:add_consumable(tid)
                    mark_created_item(ctx)
                end
            end
        end
    },

    j_rocket = {
        matches_trigger = function(_, e) return e == "on_round_end" end,
        apply_effect = function(j, ctx)
            if ctx.event_name ~= "on_round_end" then return end
            if ctx.is_boss_blind then
                j.running_count = (tonumber(j.running_count) or 1) + 2
            end
            local add = tonumber(j.running_count) or 1
            add_round_win_money(ctx, j, add)
        end
    },

    j_mail = {
        matches_trigger = function(_, e) return e == "on_discard" or e == "on_round_end" end,
        apply_effect = function(j, ctx)
            if ctx.event_name == "on_discard" then
                if ctx.discard_reason == "discard" then
                    local payout = tonumber(type(j.def) == "table" and j.def.config and j.def.config.extra) or 5
                    local discarded = ctx.discarded_cards
                    for _, c in ipairs(discarded or {}) do
                        if c and tonumber(c.rank) == tonumber(j.random_rank) then
                            add_money(ctx, payout)
                        end
                    end
                end
            else
                j.random_rank = math.random(2, 14)
            end
        end
    },

    j_acrobat = {
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        apply_effect = function(j, ctx)
            if G.hands == 0 then
                mul_mult(ctx, 3)
            end
        end
    },
    j_matador = {
        matches_trigger = function(_, e) return e == "on_boss_effect_triggered" end,
        apply_effect = function(_, ctx)
            add_money(ctx, 8)
        end
    },

    j_swashbuckler = {
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        apply_effect = function(j, ctx)
            local sum = 0
            for n,jj in ipairs(G.jokers) do
                if jj ~= j then
                    sum = sum + jj.sell_cost
                end
            end
            add_mult(ctx, sum)
        end
    },

    j_glass = {
        matches_trigger = function(_, e) return e == "on_hand_scored" or e == "glass_broken" end,
        apply_effect = function(j, ctx)
            if ctx.event_name == "on_hand_scored" then
                mul_mult(ctx, j.stored_xmult)
            else
                j.stored_xmult = tonumber(j.stored_xmult or 1) + 0.75
            end
        end
    },

    j_idol = {
        matches_trigger = function(_, e) return e == "card_played" or e == "on_round_end" end,
        apply_effect = function(j, ctx)
            if ctx.event_name == "card_played" then
                if j.random_rank == nil or j.random_suit == nil then return end
                local cr = tonumber(ctx.rank)
                local jr = tonumber(j.random_rank)
                local cs = tostring(ctx.suit or ""):lower()
                local js = tostring(j.random_suit or ""):lower()
                if cr == jr and cs ~= "" and cs == js then
                    mul_mult(ctx, 3)
                end
            elseif ctx.event_name == "on_round_end" then
                local deck = G and G.deck
                if not deck or not deck.random_card then return end
                local card = deck:random_card()
                if card then
                    j.random_rank = card.rank
                    j.random_suit = card.suit
                    mark_effect_applied(ctx)
                end
            end
        end
    },

    j_card_sharp = {
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        apply_effect = function(j, ctx)
            --IF Poker hand has been played this round
            if ctx.event_name == "on_hand_scored" then
                local hand_idx = tonumber(ctx.hand_index)
                local played_count = (G and G.blind_hand_play_counts and hand_idx and G.blind_hand_play_counts[hand_idx]) or 0
                if played_count > 1 then
                    mul_mult(ctx, tonumber(j.config and j.config.extra and j.config.extra.Xmult) or 3)
                end
            end
        end
    },

    j_seance = {
        matches_trigger = function(_, e) return e == "on_hand_played" end,
        apply_effect = function(j, ctx)
            if ctx.event_name == "on_hand_played" then
                local hand = "Straight Flush"
                if ctx.hand_type == hand then
                    local tid = G:random_consumable_id_of_kind("spectral")
                    if tid then
                        G:add_consumable(tid)
                        mark_created_item(ctx)
                    end
                end
            end
        end
    },

    j_madness = {
        matches_trigger = function(_, e) return e == "on_blind_selected" or e == "on_hand_scored" end,
        apply_effect = function(j, ctx)
            if ctx.event_name == "on_blind_selected" then
                if not ctx.is_boss_blind then
                    print("trigger")
                    j.stored_xmult = tonumber(j.stored_xmult or 1) + 0.5
                    if G and type(G.jokers) == "table" and G.remove_owned_joker_at then
                        local notIt = false
                        local pos = math.random(1, #G.jokers)
                        while not notIt do
                            if G.jokers[pos] ~= j then
                                notIt = true
                            else 
                                pos = math.random(1, #G.jokers)
                            end
                        end
                        if notIt then
                            Sfx.play("resources/sounds/slice1.ogg")
                            G:remove_owned_joker_at(pos)
                        end
                    end
                end
            else
                if ctx.event_name == "on_hand_scored" then
                    mul_mult(ctx, tonumber(j.stored_xmult) or 1)
                end
            end
        end
    },

    j_obelisk = {
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        apply_effect = function(j, ctx)
            if ctx.event_name == "on_hand_scored" then
                local hand_idx = tonumber(ctx.hand_index)
                --Find most played 
                local max_idx, max_val = nil, nil
                if G and type(G.hand_play_counts) == "table" then
                    for idx, val in pairs(G.hand_play_counts) do
                        if type(val) == "number" and (max_val == nil or val > max_val) then
                            max_val = val
                            max_idx = idx
                        end
                    end
                end
                if hand_idx == max_idx then
                    j.stored_xmult = 1
                else 
                    j.stored_xmult = tonumber(j.stored_xmult or 1) + 0.2
                end
                mul_mult(ctx, j.stored_xmult or 1)
            end
        end
    },

    j_satellite = {
        matches_trigger = function(_, e) return e == "on_round_end" end,
        apply_effect = function(j, ctx)
            local unique = 0
            for n,c in ipairs(G.hand_stats) do
                if c.level > 1 then
                    unique = unique + 1
                end
            end
            j.running_count = unique
            add_round_win_money(ctx, j, j.running_count)
        end
    },

    j_seeing_double = {
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        apply_effect = function(j, ctx)
            if ctx.event_name == "on_hand_scored" then
                cards = ctx.cards
                local hasClubs = false
                local hasOther = false
                for _, card in ipairs(cards) do
                    if card.card_data.suit == "Clubs" then
                        hasClubs = true
                    else
                        hasOther = true
                    end
                end
                if hasClubs and hasOther then
                    mul_mult(ctx, 2)
                end
            end
        end
    },

    j_cartomancer = {
        matches_trigger = function(_, e) return e == "on_blind_selected" end,
        apply_effect = function(_, ctx)
            local tid = G:random_consumable_id_of_kind("tarot")
            if tid then
                G:add_consumable(tid)
                mark_created_item(ctx)
            end
        end
    },

    j_perkeo = {
        matches_trigger = function(_, e) return e == "on_blind_selected" end,
        apply_effect = function(_, ctx)
            if ctx.event_name ~= "on_blind_selected" then return end
            if not (G and G.add_consumable and type(G.consumables) == "table") then return end
            if #G.consumables < 1 then return end
            local src = G.consumables[math.random(1, #G.consumables)]
            if type(src) ~= "table" or type(src.id) ~= "string" or src.id == "" then return end
            local params = {}
            for k, v in pairs(src) do
                if k ~= "edition" then
                    if type(v) == "table" then
                        if G.deep_copy_card_data then
                            params[k] = G:deep_copy_card_data(v)
                        else
                            params[k] = v
                        end
                    else
                        params[k] = v
                    end
                end
            end
            params.edition = "negative"
            if G:add_consumable(src.id, params) then
                mark_effect_applied(ctx)
                mark_created_item(ctx)
            end
        end
    },

    j_burnt = {
        matches_trigger = function(_, e) return e == "on_discard" or e == "on_round_begin" or e == "on_blind_selected" end,
        apply_effect = function(j, ctx)
            if ctx.event_name == "on_round_begin" or ctx.event_name == "on_blind_selected" then
                j._burnt_used_this_round = false
                return
            end
            if ctx.event_name ~= "on_discard" or ctx.discard_reason ~= "discard" then return end
            if j._burnt_used_this_round == true then return end
            local hand_idx = tonumber(G and G.selectedHand)
            if not hand_idx or hand_idx < 1 then return end
            if G and G.upgrade_hand_level_at_index and G:upgrade_hand_level_at_index(hand_idx) then
                j._burnt_used_this_round = true
                mark_effect_applied(ctx)
            end
        end
    },

    j_invisible = {
        matches_trigger = function(_, e) return e == "on_round_end" or e == "on_joker_sold" end,
        apply_effect = function(j, ctx)
            if ctx.event_name == "on_round_end" then
                j.runtime_counter = math.min(2, (tonumber(j.runtime_counter) or 0) + 1)
                mark_effect_applied(ctx)
                return
            end
            if ctx.invisible_duplicated == true then return end
            if ctx.event_name ~= "on_joker_sold" or ctx.joker ~= j then return end
            if not (G and G.add_joker_by_def and type(G.jokers) == "table") then return end
            local required = math.max(1, math.floor(tonumber(j.def and j.def.config and j.def.config.extra) or 2))
            if (tonumber(j.runtime_counter) or 0) < required then return end
            if #G.jokers <= 0 then return end

            local src = G.jokers[math.random(1, #G.jokers)]
            if not (src and src.def and src.def.id) then return end

            local src_edition = Joker and Joker.normalize_edition and Joker.normalize_edition(src.edition) or tostring(src.edition or "base")
            local clone_edition = (src_edition == "negative") and "base" or src_edition
            if not G:add_joker_by_def(src.def.id, { edition = clone_edition }) then return end

            local clone = G.jokers[#G.jokers]
            if not clone then return end
            copy_joker_runtime_state(clone, src)
            clone.edition = clone_edition
            if clone.refresh_quads then clone:refresh_quads() end
            mark_effect_applied(ctx)
            mark_created_item(ctx)
        end
    },

    j_hit_the_road = {
        matches_trigger = function(_, e) return e == "on_discard" or e == "on_hand_scored" end,
        apply_effect = function(j, ctx)
            if ctx.event_name == "on_discard" and ctx.discard_reason == "discard" then
                local discarded = ctx.discarded_cards
                for _, c in ipairs(discarded or {}) do
                    if c and tonumber(c.rank) == 11 then
                        j.stored_xmult = j.stored_xmult + 0.5
                    end
                end
            elseif ctx.event_name == "on_hand_scored" then
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

function JokerEffects.begin_apply_context(ctx)
    if type(ctx) ~= "table" then return end
    ctx._joker_effect_applied_now = false
    ctx._joker_effect_created_item_now = false
end

function JokerEffects.mark_effect_applied(ctx)
    mark_effect_applied(ctx)
end

function JokerEffects.mark_created_item(ctx)
    mark_created_item(ctx)
end

function JokerEffects.should_shake_for_context(ctx)
    if type(ctx) ~= "table" then return false end
    if ctx._suppress_joker_apply_shake then return false end
    return ctx._joker_effect_applied_now == true or ctx._joker_effect_created_item_now == true
end

function JokerEffects.apply_shake_if_needed(joker, ctx)
    if not joker or not JokerEffects.should_shake_for_context(ctx) then return false end
    joker.scoring_shake_timer = JokerEffects.SHAKE_MAX_DURATION
    joker.scoring_shake_t0 = love.timer.getTime()
    return true
end

