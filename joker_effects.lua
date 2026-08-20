JokerEffects = {}

--- Randomness for pitch jitter, 0..1. Deliberately not `math.random`: the run reseeds that
--- stream for reproducibility, and a sound must never advance it.
local function sfx_jitter()
    if love and love.math and love.math.random then return love.math.random() end
    return 0.5
end

--- Ladder pitch for a cue raised during hand scoring; 1 outside a scoring run. Resolved
--- through the global so a headless load of this module alone still works.
local function scoring_pitch()
    if Hand and Hand.scoring_pitch then return Hand.scoring_pitch() end
    return 1
end

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

--- Declare that this application of the effect changed runtime state but has nothing to
--- announce, so `Joker:apply_effect`'s snapshot heuristic must not read the change as a
--- trigger. The reference decides this per branch by returning a message or returning bare
--- (Yorick's non-payoff tick is `return` with no table, `reference/Balatro/card.lua:2787-2801`);
--- a silent branch costs no beat of the staggered emit queue and raises no juice.
local function mark_effect_silent(ctx)
    if type(ctx) ~= "table" then return end
    ctx._joker_effect_silent = true
end

--- Hold this trigger's beat for `seconds` instead of the default. Mirrors the reference's
--- per-eval `delay` field, which `card_eval_status_text` scales by 1.25
--- (`reference/Balatro/functions/common_events.lua:853-878`) -- so the reference's `delay = 0.2`
--- is 0.25 s here, against the 0.9375 s an eval with no `delay` gets.
local function set_effect_delay(ctx, seconds)
    if type(ctx) ~= "table" then return end
    ctx._joker_effect_delay = tonumber(seconds)
end

local function card_center_x(node)
    return node.x + (node.w / 2) * node.scale
end

local function card_center_y(node)
    return node.y + (node.h / 2) * node.scale
end

local function add_mult(ctx, n)
    ctx.mult = (tonumber(ctx.mult) or 0) + (tonumber(n) or 0)
    if(n > 0) then 
        mark_effect_applied(ctx)

        local p = Popup()
        p:spawn(n, "mult", card_center_x(ctx.VT), card_center_y(ctx.VT))
        Top:addPopup(p)

        Sfx.play_mult(scoring_pitch())
    end
end
local function add_chips(ctx, n)
    ctx.chips = (tonumber(ctx.chips) or 0) + (tonumber(n) or 0)
    if(n > 0) then 
        mark_effect_applied(ctx) 

        local p = Popup()
        p:spawn(n, "chips", card_center_x(ctx.VT), card_center_y(ctx.VT))
        Top:addPopup(p)

        Sfx.play_chips(scoring_pitch())
    end
end
local function mul_mult(ctx, n)
    ctx.mult = (tonumber(ctx.mult) or 1) * (tonumber(n) or 1)
    if(n > 1) then
        mark_effect_applied(ctx)

        local p = Popup()
        p:spawn(n, "xmult", card_center_x(ctx.VT), card_center_y(ctx.VT))
        Top:addPopup(p)

        -- xmult sits under the other scoring cues in the reference mix (vol 0.7).
        Sfx.play_mult2(scoring_pitch(), 0.7)
    end
end
local function add_money(ctx, n)
    if G and G.money ~= nil then
        G.money = (tonumber(G.money) or 0) + (tonumber(n) or 0)
        if(n > 0) then 
            mark_effect_applied(ctx) 

            local p = Popup()
            p:spawn(n, "money", card_center_x(ctx.VT), card_center_y(ctx.VT))
            Top:addPopup(p)

            Sfx.play_money(scoring_pitch())
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
local function rank_is_even(rank) 
    rank = tonumber(rank)
    if rank and rank < 14 and rank > 10 then
        return false
    end
    return rank and rank ~= 14 and rank % 2 == 0 
end
local function rank_is_odd(rank) 
    rank = tonumber(rank);
    if rank and rank < 14 and rank > 10 then
        return false
    end
    return rank and (rank == 14 or rank % 2 == 1) 
end

--- Suit match; with Smeared Joker, Hearts↔Diamonds and Spades↔Clubs count as the same.
local function is_suit(suit, check)
    if suit == nil or check == nil then return false end
    local smeared = G and G.hasJoker and G:hasJoker("j_smeared")
    if smeared then
        if check == "Hearts" or check == "Diamonds" then
            return suit == "Hearts" or suit == "Diamonds"
        elseif check == "Spades" or check == "Clubs" then
            return suit == "Spades" or suit == "Clubs"
        end
    end
    return suit == check
end

local function discarded_card_is_debuffed(ctx, index, card)
    if card and card.debuff == true then return true end
    local node = type(ctx) == "table" and type(ctx.discarded_nodes) == "table"
        and ctx.discarded_nodes[index] or nil
    if node and (node.debuffed == true or node.debuffed_for_scoring == true) then return true end
    return node ~= nil and G and G.boss_is_card_debuffed_for_scoring
        and G:boss_is_card_debuffed_for_scoring(node) == true
end

local function count_full_deck(pred)
    if G and G.count_cards_in_full_deck then return G:count_cards_in_full_deck(pred) end
    return 0
end
local function count_cards_in_deck(pred)
    if G and G.count_cards_in_deck then return G:count_cards_in_deck(pred) end
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

--- Blueprint / Brainstorm: only copy when `src` would fire; shake the copycat, not `src`.
local function is_blueprint_copy_target(src)
    if type(src) ~= "table" then return false end
    local def = src.def
    if type(def) ~= "table" then return false end
    return def.blueprint_compat == true
end

local function joker_def_id(joker)
    local def = type(joker) == "table" and joker.def
    return type(def) == "table" and def.id or nil
end

local function blueprint_immediate_target(joker)
    if type(G and G.jokers) ~= "table" then return nil end
    for i, jj in ipairs(G.jokers) do
        if jj == joker then
            return G.jokers[i + 1]
        end
    end
    return nil
end

local function brainstorm_immediate_target(joker)
    return G and G.jokers and G.jokers[1]
end

--- Walk Blueprint/Brainstorm links to the real joker; nil on cycle or incompatible target.
local function resolve_copy_target(src, visited)
    if type(src) ~= "table" then return nil end
    visited = visited or {}
    if visited[src] then return nil end
    visited[src] = true

    local id = joker_def_id(src)
    if id == "j_brainstorm" then
        local next_src = brainstorm_immediate_target(src)
        if type(next_src) ~= "table" or next_src == src then return nil end
        return resolve_copy_target(next_src, visited)
    end
    if id == "j_blueprint" then
        local next_src = blueprint_immediate_target(src)
        return resolve_copy_target(next_src, visited)
    end

    if not is_blueprint_copy_target(src) then return nil end
    return src
end

local function delegate_joker_effect(delegator, src, ctx)
    local resolved = resolve_copy_target(src)
    if type(resolved) ~= "table" or resolved == delegator then return end
    if type(resolved.apply_effect) ~= "function" then return end
    -- The copied calculation can pay out, but must not advance or consume its source
    -- (`reference/Balatro/card.lua:3412-3569`).
    local prev_blueprint = type(ctx) == "table" and ctx.blueprint or nil
    local prev_blueprint_card = type(ctx) == "table" and ctx.blueprint_card or nil
    if type(ctx) == "table" then
        ctx.blueprint = true
        ctx.blueprint_card = delegator
    end
    local en = type(ctx) == "table" and ctx.event_name or nil
    if type(en) == "string" and en ~= "" and type(resolved.matches_trigger) == "function" then
        if resolved:matches_trigger(en, ctx) ~= true then
            if type(ctx) == "table" then
                ctx.blueprint = prev_blueprint
                ctx.blueprint_card = prev_blueprint_card
            end
            return
        end
    end
    local prev_suppress = type(ctx) == "table" and ctx._suppress_joker_apply_shake or nil
    if type(ctx) == "table" then ctx._suppress_joker_apply_shake = true end
    resolved:apply_effect(ctx)
    if type(ctx) == "table" then
        ctx._suppress_joker_apply_shake = prev_suppress
        ctx.blueprint = prev_blueprint
        ctx.blueprint_card = prev_blueprint_card
    end
end

local function delegate_joker_retrigger(delegator, src, ctx)
    local resolved = resolve_copy_target(src)
    if type(resolved) ~= "table" or resolved == delegator then return 0 end
    if type(resolved.query_retrigger) ~= "function" then return 0 end
    return tonumber(resolved:query_retrigger(ctx)) or 0
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
    j_joker = {
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        apply_effect = function(_, ctx) add_mult(ctx, 4) end,
    },
    j_greedy_joker = {
        matches_trigger = function(_, e) return e == "card_played" end,
        apply_effect = function(_, ctx) if is_suit(ctx.suit, "Diamonds") then add_mult(ctx, 3) end end,
    },
    j_lusty_joker = {
        matches_trigger = function(_, e) return e == "card_played" end,
        apply_effect = function(_, ctx) if is_suit(ctx.suit, "Hearts") then add_mult(ctx, 3) end end,
    },
    j_wrathful_joker = {
        matches_trigger = function(_, e) return e == "card_played" end,
        apply_effect = function(_, ctx) if is_suit(ctx.suit, "Spades") then add_mult(ctx, 3) end end,
    },
    j_gluttenous_joker = {
        matches_trigger = function(_, e) return e == "card_played" end,
        apply_effect = function(_, ctx) if is_suit(ctx.suit, "Clubs") then add_mult(ctx, 3) end end,
    },
    j_jolly = {
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        apply_effect = function(_, ctx) if has_hand_type(ctx, "Pair") then add_mult(ctx, 8) end end,
    },
    j_zany = {
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        apply_effect = function(_, ctx) if has_hand_type(ctx, "Three of a Kind") then add_mult(ctx, 12) end end,
    },
    j_mad = {
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        apply_effect = function(_, ctx) if has_hand_type(ctx, "Two Pair") then add_mult(ctx, 10) end end,
    },
    j_crazy = {
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        apply_effect = function(_, ctx) if has_hand_type(ctx, "Straight") then add_mult(ctx, 12) end end,
    },
    j_droll = {
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        apply_effect = function(_, ctx) if has_hand_type(ctx, "Flush") then add_mult(ctx, 10) end end,
    },
    j_sly = {
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        apply_effect = function(_, ctx) if has_hand_type(ctx, "Pair") then add_chips(ctx, 50) end end,
    },
    j_wily = {
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        apply_effect = function(_, ctx) if has_hand_type(ctx, "Three of a Kind") then add_chips(ctx, 100) end end,
    },
    j_clever = {
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        apply_effect = function(_, ctx) if has_hand_type(ctx, "Two Pair") then add_chips(ctx, 80) end end,
    },
    j_crafty = {
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        apply_effect = function(_, ctx) if has_hand_type(ctx, "Flush") then add_chips(ctx, 80) end end,
    },
    j_devious = {
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        apply_effect = function(_, ctx) if has_hand_type(ctx, "Straight") then add_chips(ctx, 100) end end,
    },
    j_half = {
        matches_trigger = function(_, e, ctx)
            if e ~= "on_hand_scored" then return false end
            local cards = ctx and ctx.full_hand
            return type(cards) == "table" and #cards <= 3
        end,
        apply_effect = function(_, ctx) add_mult(ctx, 20) end,
    },
    j_stencil = {
        matches_trigger = function(j, e, ctx)
            if e ~= "on_hand_scored" then return false end
            if ctx == nil or tonumber(ctx.free_joker_slots) == nil then return false end
            j.free_joker_slots = tonumber(ctx.free_joker_slots)
            return true
        end,
        apply_effect = function(_, ctx)
            mul_mult(ctx, (tonumber(ctx.free_joker_slots) or 0) + 1)
        end,
    },
    j_ceremonial = {
        matches_trigger = function(j, e)
            if e == "on_hand_scored" then
                return (tonumber(j.stored_mult) or 0) > 0
            end
            if e ~= "on_blind_selected" then return false end
            if type(G and G.jokers) ~= "table" then return false end
            for i, jj in ipairs(G.jokers) do
                if jj == j and G.jokers[i + 1] then return true end
            end
            return false
        end,
        apply_effect = function(j, ctx)
            if ctx.event_name == "on_hand_scored" then
                add_mult(ctx, tonumber(j.stored_mult) or 0)
                return
            end
            if ctx.blueprint then return end
            if type(G and G.jokers) ~= "table" then return end
            for i, jj in ipairs(G.jokers) do
                if jj == j then
                    local target_index = i + 1
                    local victim = G.jokers[target_index]
                    -- reference/Balatro/card.lua:2566 — eternal neighbours cannot be sliced,
                    -- so they must not grant Ceremonial Dagger any Mult.
                    if not victim or victim.eternal then return end
                    j.stored_mult = (tonumber(j.stored_mult) or 0) + (tonumber(victim.sell_cost) or 0) * 2
                    mark_effect_applied(ctx)
                    if G.remove_owned_joker_at then
                        G:remove_owned_joker_at(target_index, false, true)
                    else
                        table.remove(G.jokers, target_index)
                        if G.remove then G:remove(victim) end
                    end
                    -- The one place the reference uses `slice1`: this joker cuts its
                    -- neighbour rather than dissolving it (`reference/Balatro/card.lua:2575`).
                    Sfx.play("slice1", 0.96 + sfx_jitter() * 0.08)
                    return
                end
            end
        end,
    },
    j_mystic_summit = {
        matches_trigger = function(_, e, ctx)
            if e ~= "on_hand_scored" then return false end
            local discards_left = tonumber((ctx and ctx.discards_left) or (G and G.discards)) or 0
            return discards_left == 0
        end,
        apply_effect = function(_, ctx) add_mult(ctx, 15) end,
    },
    j_marble = {
        matches_trigger = function(_, e) return e == "on_blind_selected" end,
        apply_effect = function(_, ctx)
            local deck = (ctx and ctx.deck) or (G and G.deck)
            if not (deck and deck.cards) then return end
            -- Stone cards are rankless and suitless (reference/Balatro/card.lua:2580-2589).
            table.insert(deck.cards, {
                enhancement = "stone",
            })
            if G and G.notify_cards_added_to_deck then
                G:notify_cards_added_to_deck(1)
            end
            mark_effect_applied(ctx)
            mark_created_item(ctx)
        end,
    },
    j_loyalty_card = {
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        apply_effect = function(j, ctx)
            local extra = type(j.effect_config.extra) == "table" and j.effect_config.extra or {}
            local every = math.max(1, tonumber(extra.every) or 6)
            local remaining = tonumber(j.runtime_counter) or every
            if remaining < 1 or remaining > every then remaining = every end
            remaining = remaining - 1
            if remaining <= 0 then
                if not ctx.blueprint then j.runtime_counter = every end
                mul_mult(ctx, tonumber(extra.Xmult) or tonumber(j.effect_config.Xmult) or 4)
            elseif not ctx.blueprint then
                j.runtime_counter = remaining
            end
        end,
    },
    j_hanging_chad = {
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
        query_retrigger = function(_, ctx)
            -- Mime repeats only held cards whose initial pass produced an effect
            -- (reference/Balatro/card.lua:3387-3394).
            if ctx.held and ctx.held_first_pass_effect_applied == true then return 1 end
            return 0
        end,
    },
    j_hack = {
        query_retrigger = function(_, ctx)
            if ctx.held then return 0 end
            local node = ctx.card_node or ctx.retrigger_card
            local r = tonumber(node and node.card_data and node.card_data.rank)
            if r and r >= 2 and r <= 5 then return 1 end
            return 0
        end,
    },
    j_sock_and_buskin = {
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
                    if type(src) == "table" and not resolve_copy_target(src) then
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
            if type(src) == "table" and not resolve_copy_target(src) then
                return { "Incompatible" }
            end
            return {}
        end,
    },
    j_misprint = {
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        apply_effect = function(_, ctx) add_mult(ctx, G:random("misprint", 0, 23)) end
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
        apply_effect = function(_, ctx) add_chips(ctx, 2 * count_cards_in_deck()) end
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
        apply_effect = function(_, ctx)
            -- reference/Balatro/card.lua:3936-3941 — debt cannot subtract chips.
            add_chips(ctx, 2 * math.max(0, tonumber(G and G.money) or 0))
        end
    },
    j_bootstraps = {
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        apply_effect = function(_, ctx)
            -- reference/Balatro/card.lua:4046-4050 — require at least one whole $5.
            local dollars = math.floor((tonumber(G and G.money) or 0) / 5)
            if dollars >= 1 then add_mult(ctx, dollars * 2) end
        end
    },
    j_green_joker = {
        matches_trigger = function(_, e) return e == "on_hand_played" or e == "on_discard" or e == "on_hand_scored" end,
        apply_effect = function(j, ctx)
            if ctx.event_name == "on_hand_played" and not ctx.blueprint then j.stored_mult = (tonumber(j.stored_mult) or 0) + 1
            -- Once per discard, not once per card: the reference gates on the last card of
            -- the discarded set (reference/Balatro/card.lua:2847-2858).
            elseif ctx.event_name == "on_discard" and ctx.discard_reason == "discard"
                and ctx.is_last ~= false and not ctx.blueprint then
                j.stored_mult = math.max(0, (tonumber(j.stored_mult) or 0) - 1)
            elseif ctx.event_name == "on_hand_scored" then add_mult(ctx, tonumber(j.stored_mult) or 0) end
        end
    },
    j_runner = {
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        apply_effect = function(j, ctx)
            if has_hand_type(ctx, "Straight") and not ctx.blueprint then j.stored_chips = (tonumber(j.stored_chips) or 0) + 15 end
            add_chips(ctx, tonumber(j.stored_chips) or 0)
        end
    },
    j_square = {
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        apply_effect = function(j, ctx)
            if type(ctx.full_hand) == "table" and #ctx.full_hand == 4 and not ctx.blueprint then
                j.stored_chips = (tonumber(j.stored_chips) or 0) + 4
            end
            add_chips(ctx, tonumber(j.stored_chips) or 0)
        end
    },
    j_spare_trousers = {
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        apply_effect = function(j, ctx)
            if has_hand_type(ctx, "Two Pair") and not ctx.blueprint then j.stored_mult = (tonumber(j.stored_mult) or 0) + 2 end
            add_mult(ctx, tonumber(j.stored_mult) or 0)
        end
    },
    j_flash_card = {
        matches_trigger = function(_, e) return e == "on_shop_reroll" or e == "on_hand_scored" end,
        apply_effect = function(j, ctx)
            if ctx.event_name == "on_shop_reroll" and not ctx.blueprint then j.stored_mult = (tonumber(j.stored_mult) or 0) + 2
            elseif ctx.event_name == "on_hand_scored" then add_mult(ctx, tonumber(j.stored_mult) or 0) end
        end
    },
    j_popcorn = {
        matches_trigger = function(_, e) return e == "on_round_end" or e == "on_hand_scored" end,
        apply_effect = function(j, ctx)
            if j.runtime_counter == 0 and not ctx.blueprint then
                j.stored_mult = 20 
                j.runtime_counter = 1
            end
            if ctx.event_name == "on_round_end" and not ctx.blueprint then
                j.stored_mult = math.max(0, (tonumber(j.stored_mult) or 0) - 4)
                if j.stored_mult <= 0 then
                    --Destroy Joker
                    if G and type(G.jokers) == "table" and G.remove_owned_joker_at then
                        for i, jj in ipairs(G.jokers) do
                            if jj == j then
                                local p = Popup()
                                p:spawn("Eaten!", "Nope", card_center_x(ctx.VT), card_center_y(ctx.VT))
                                Top:addPopup(p)
                                Card.play_dissolve_sfx()
                                G:remove_owned_joker_at(i, false, true)
                                break
                            end
                        end
                    end
                end
            else
                add_mult(ctx, tonumber(j.stored_mult) or 0)
            end
            if not ctx.blueprint then j.runtime_counter = (tonumber(j.runtime_counter) or 0) + 1 end
        end
    },
    j_constellation = {
        matches_trigger = function(_, e) return e == "on_consumable_used" or e == "on_hand_scored" end,
        apply_effect = function(j, ctx)
            if ctx.event_name == "on_consumable_used" and ctx.consumable_kind == "planet" and not ctx.blueprint then
                j.stored_xmult = (tonumber(j.stored_xmult) or 1) + 0.1
            elseif ctx.event_name == "on_hand_scored" then
                mul_mult(ctx, tonumber(j.stored_xmult) or 1)
            end
        end
    },
    j_hologram = {
        matches_trigger = function(_, e) return e == "on_cards_added_to_deck" or e == "on_hand_scored" end,
        apply_effect = function(j, ctx)
            if ctx.event_name == "on_cards_added_to_deck" then
                local n = math.max(0, math.floor(tonumber(ctx.count) or 0))
                if n > 0 and not ctx.blueprint then
                    j.stored_xmult = (tonumber(j.stored_xmult) or 1) + 0.25 * n
                end
            elseif ctx.event_name == "on_hand_scored" then
                mul_mult(ctx, tonumber(j.stored_xmult) or 1)
            end
        end
    },
    j_lucky_cat = {
        matches_trigger = function(_, e) return e == "lucky_trigger" or e == "on_hand_scored" end,
        apply_effect = function(j, ctx)
            if ctx.event_name == "lucky_trigger" and not ctx.blueprint then
                j.stored_xmult = (tonumber(j.stored_xmult) or 1) + 0.25
            elseif ctx.event_name == "on_hand_scored" and j.stored_xmult > 1 then
                mul_mult(ctx, tonumber(j.stored_xmult) or 1)
            end
        end
    },
    j_campfire = {
        matches_trigger = function(_, e) return e == "on_joker_sold" or e == "on_round_end" or e == "on_hand_scored" end,
        apply_effect = function(j, ctx)
            if ctx.event_name == "on_joker_sold" and not ctx.blueprint then
                j.stored_xmult = (tonumber(j.stored_xmult) or 1) + 0.25
            elseif ctx.event_name == "on_round_end" and ctx.is_boss_blind and not ctx.blueprint then
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
                rank = G:random("cert_fr", 2, 14),
                suit = suits[G:random("cert_fr", 1, #suits)],
                enhancement = nil,
                seal = seals[G:random("certsl", 1, #seals)],
            }
            hand:add_card(cd, true)
            if G.notify_cards_added_to_deck then
                G:notify_cards_added_to_deck(1)
            end
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
        apply_effect = function(_, ctx) if rank_is_face(ctx.rank) and G:do_random(1, 2, 1, "parking") then add_money(ctx, 1) end end
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
    j_rough_gem = { matches_trigger = function(_, e) return e == "card_played" end, apply_effect = function(_, ctx) if is_suit(ctx.suit, "Diamonds") then add_money(ctx, 1) end end },
    j_arrowhead = { matches_trigger = function(_, e) return e == "card_played" end, apply_effect = function(_, ctx) if is_suit(ctx.suit, "Spades") then add_chips(ctx, 50) end end },
    j_onyx_agate = { matches_trigger = function(_, e) return e == "card_played" end, apply_effect = function(_, ctx) if is_suit(ctx.suit, "Clubs") then add_mult(ctx, 7) end end },
    j_bloodstone = {
        matches_trigger = function(_, e) return e == "card_played" end,
        apply_effect = function(_, ctx) if is_suit(ctx.suit, "Hearts") and G:do_random(1, 2, 1, "bloodstone") then mul_mult(ctx, 1.5) end end
    },
    j_8_ball = {
        matches_trigger = function(_, e) return e == "card_played" end,
        apply_effect = function(joker, ctx)
            if tonumber(ctx.rank) ~= 8 then return end
            local odds = tonumber((joker.effect_config or {}).extra) or 4
            odds = math.max(2, odds)
            if not G:do_random(1, odds, 1, "8ball") then return end
            if not G or not G.can_add_consumable or not G.add_consumable or not G.random_consumable_id_of_kind then return end
            if not G:can_add_consumable() then return end
            local tid = G:random_consumable_id_of_kind("tarot", nil, "8ball")
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
            for _ = 1, 2 do
                local id = G:random_joker_def_id_by_rarity(1, "riff_raff")
                if not id then break end
                if G:add_joker_by_def(id) then
                    mark_effect_applied(ctx)
                    mark_created_item(ctx)
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
            if ctx.event_name == "card_played" and tonumber(ctx.rank) == 2 and not ctx.blueprint then
                j.stored_chips = (tonumber(j.stored_chips) or 0) + 8
            elseif ctx.event_name == "on_hand_scored" then
                add_chips(ctx, tonumber(j.stored_chips) or 0)
            end
        end
    },
    j_flower_pot = {
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        apply_effect = function(_, ctx)
            local has = { Hearts = false, Clubs = false, Diamonds = false, Spades = false }
            for _, n in ipairs((ctx and ctx.cards) or {}) do
                local s = n and n.card_data and n.card_data.suit
                if s then
                    if is_suit(s, "Hearts") then has.Hearts = true end
                    if is_suit(s, "Clubs") then has.Clubs = true end
                    if is_suit(s, "Diamonds") then has.Diamonds = true end
                    if is_suit(s, "Spades") then has.Spades = true end
                end
            end
            if has.Hearts and has.Clubs and has.Diamonds and has.Spades then
                mul_mult(ctx, 3)
            end
        end
    },
    j_business = { matches_trigger = function(_, e) return e == "card_played" end, apply_effect = function(_, ctx) if rank_is_face(ctx.rank) and G:do_random(1, 2, 1, "business") then add_money(ctx, 2) end end },
    j_ticket = { matches_trigger = function(_, e) return e == "card_played" end, apply_effect = function(_, ctx) local cd = ctx.card_node and ctx.card_node.card_data; if cd and cd.enhancement == "gold" then add_money(ctx, 4) end end },
    j_photograph = {
        matches_trigger = function(_, e) return e == "card_played" end,
        apply_effect = function(j, ctx)
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
            for _, c in ipairs(cards) do
                if not is_suit(c.suit, "Spades") and not is_suit(c.suit, "Clubs") then return end
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
        apply_effect = function(_, ctx)
            local skipped = (G and tonumber(G.skipsTaken)) or 0
            mul_mult(ctx, 1 + (0.25 * skipped))
        end
    },
    j_yorick = {
        matches_trigger = function(_, e) return e == "on_discard" or e == "on_hand_scored" end,
        apply_effect = function(j, ctx)
            if ctx.event_name == "on_discard" and ctx.discard_reason == "discard" and not ctx.blueprint then
                -- Counted a card at a time (reference/Balatro/card.lua:2788-2800).
                if not ctx.card then return end
                j.runtime_counter = (tonumber(j.runtime_counter) or 0) + 1
                if (tonumber(j.runtime_counter) or 0) >= 23 then
                    j.runtime_counter = j.runtime_counter - 23
                    j.stored_xmult = (tonumber(j.stored_xmult) or 1) + 1
                    -- The payoff is the reference's `delay = 0.2` eval, not the 0.75 default
                    -- (reference/Balatro/card.lua:2787-2796).
                    set_effect_delay(ctx, 0.25)
                    mark_effect_applied(ctx)
                else
                    -- Counting is silent in the reference -- the non-payoff branch returns
                    -- nothing at all, so it raises no status text and holds no beat. Without
                    -- this the counter tick alone reads as a trigger to the snapshot check in
                    -- `Joker:apply_effect`, and every discarded card costs a full beat.
                    mark_effect_silent(ctx)
                end
            elseif ctx.event_name == "on_hand_scored" then
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
            if ctx.event_name == "on_destroy" then
                if not ctx.blueprint and type(ctx.destroyed_cards) == "table" then
                    for _, c in ipairs(ctx.destroyed_cards) do
                        local r = tonumber(c and c.rank)
                        if r == 11 or r == 12 or r == 13 then
                            j.stored_xmult = (tonumber(j.stored_xmult) or 1) + 1
                        end
                    end
                end
            elseif ctx.event_name == "on_hand_scored" then
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
                -- reference/Balatro/card.lua:3397 — Baseball Card excludes itself.
                if jo ~= j and r == 2 then
                    mul_mult(ctx, 1.5)
                end
            end
        end,
    },
    j_trading_card = {
        matches_trigger = function(_, e, ctx) return e == "on_discard" and ctx.discard_reason == "discard" end,
        apply_effect = function(_, ctx)
            if ctx.blueprint then return end
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
            if ctx.event_name == "card_played" and is_suit(ctx.suit, j.random_suit) then
                mul_mult(ctx, 1.5)
            elseif ctx.event_name == "on_round_end" then
                local suits = { "Hearts", "Clubs", "Diamonds", "Spades" }
                if G and G.set_joker_shared_picks then
                    G:set_joker_shared_picks("j_ancient_joker", { random_suit = suits[G:random("anc", 1, #suits)] })
                end
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
                if ctx.blueprint then return end
                -- One card, one bite (reference/Balatro/card.lua:2757-2786): a Ramen that
                -- runs out partway through a discard stops eating the rest of it.
                if not ctx.card then return end
                j.runtime_counter = (tonumber(j.runtime_counter) or 0) - 0.01
                -- reference/Balatro/card.lua:2757-2775 — Ramen is consumed at x1.00 too.
                if j.runtime_counter <= 1 then
                    if G and type(G.jokers) == "table" and G.remove_owned_joker_at then
                        for i, jj in ipairs(G.jokers) do
                            if jj == j then
                                local p = Popup()
                                p:spawn("Eaten!", "Nope", card_center_x(ctx.VT), card_center_y(ctx.VT))
                                Top:addPopup(p)
                                Card.play_dissolve_sfx()
                                G:remove_owned_joker_at(i, false, true)
                                break
                            end
                        end
                    end
                    return
                end
                -- reference/Balatro/card.lua:2757-2786 -- Ramen's bite is a `delay = 0.2` eval.
                set_effect_delay(ctx, 0.25)
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
        -- reference/Balatro/card.lua:3595-3630 -- `after`: the counter drops once the score
        -- has landed, so this hand's retriggers all used the pre-decrement value.
        matches_trigger = function(_, e) return e == "on_hand_after" end,
        apply_effect = function(j, ctx)
            if ctx.blueprint then return end
            mark_effect_applied(ctx)
            j.runtime_counter = (tonumber(j.runtime_counter) or 0) - 1
            if (tonumber(j.runtime_counter) or 0) < 1 then
                if G and type(G.jokers) == "table" and G.remove_owned_joker_at then
                    for i, jj in ipairs(G.jokers) do
                        if jj == j then
                            local p = Popup()
                            p:spawn("Drank!", "Nope", card_center_x(ctx.VT), card_center_y(ctx.VT))
                            Top:addPopup(p)
                            Card.play_dissolve_sfx()
                            G:remove_owned_joker_at(i, false, true)
                            break
                        end
                    end
                end
            end
        end,
        query_retrigger = function(j, ctx)
            -- reference/Balatro/card.lua:3360-3372 — Seltzer only repeats played cards.
            if ctx.held then return 0 end
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
            if e == "on_round_end" then return true end
            return false
        end,
        apply_effect = function(j, ctx)
            if ctx.event_name == "on_hand_scored" then
                add_chips(ctx, tonumber(j.runtime_counter) or 0)
            elseif ctx.event_name == "on_discard" then
                if ctx.blueprint then return end
                -- Debuffed discarded cards do not grow Castle
                -- (reference/Balatro/card.lua:2814-2823).
                local c = ctx.card
                if c and not discarded_card_is_debuffed(ctx, ctx.card_index, c)
                    and is_suit(c.suit, j.random_suit) then
                    j.runtime_counter = (tonumber(j.runtime_counter) or 0) + 3
                    mark_effect_applied(ctx)
                end
            elseif ctx.event_name == "on_round_end" then
                if G and G.roll_joker_shared_picks and G.set_joker_shared_picks then
                    local picks = G:roll_joker_shared_picks("j_castle")
                    if picks then
                        G:set_joker_shared_picks("j_castle", picks)
                    end
                end
            end
        end
    },

    j_midas_mask = {
        -- reference/Balatro/card.lua:3442-3462 -- Midas Mask is a `before` joker: every
        -- scoring face card is gold *before* the first card scores, so whatever enhancement
        -- it carried is gone for this hand, and a Vampire to its right can drain the gold.
        matches_trigger = function(_, e) return e == "on_hand_played" end,
        apply_effect = function(_, ctx)
            if ctx.blueprint then return end
            for _, node in ipairs(ctx.full_hand or {}) do
                local data = node and node.card_data
                if data and node.counts_for_play_score == true
                    and rank_is_face(data.rank)
                    and type(node.set_enhancement) == "function" then
                    node:set_enhancement("gold")
                    mark_effect_applied(ctx)
                end
            end
        end
    },

    j_dusk = {
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        query_retrigger = function(joker, ctx)
            -- reference/Balatro/card.lua:3360-3372 — Dusk only repeats played cards.
            if ctx.held then return 0 end
            -- `jd_preview` is the Joker readout asking what *would* happen if the selection
            -- were played (`joker_display.lua`). The hand has not been spent at that point, so
            -- the final hand still shows one remaining.
            local hands = tonumber(G.hands) or 0
            if ctx.jd_preview then hands = hands - 1 end
            if hands <= 0 then
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
                if G:do_random(1, 6, 1, "gros_michel") then
                    if G and type(G.jokers) == "table" and G.remove_owned_joker_at then
                        for i, jj in ipairs(G.jokers) do
                            if jj == j then
                                Card.play_dissolve_sfx()
                                local p = Popup()
                                p:spawn("Extinct!", "Nope", card_center_x(ctx.VT), card_center_y(ctx.VT))
                                Top:addPopup(p)
                                if G.activate_joker_pool_swap then
                                    G:activate_joker_pool_swap("j_gros_michel", "j_cavendish")
                                end
                                G:remove_owned_joker_at(i, false, true)
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
            if not ctx.blueprint then
                if not face then
                    j.runtime_counter = (tonumber(j.runtime_counter) or 0) + 1
                else
                    j.runtime_counter = 0
                end
            end
            add_mult(ctx, tonumber(j.runtime_counter))
        end
    },

    j_space = {
        matches_trigger = function(_, e) return e == "on_hand_played" end,
        apply_effect = function(_, ctx)
            if not G:do_random(1, 4, 1, "space") then return end
            local idx = ctx and tonumber(ctx.hand_index)
            if not G or not idx or not G.upgrade_hand_level_at_index then return end
            if G:upgrade_hand_level_at_index(idx) then
                mark_effect_applied(ctx)
            end
        end
    },

    j_ice_cream = {
        -- reference/Balatro/card.lua:3570-3594 -- the chips are `joker_main`, but the melt is
        -- `after`: Ice Cream pays in full and only then loses 5.
        matches_trigger = function(_, e) return e == "on_hand_scored" or e == "on_hand_after" end,
        apply_effect = function(j, ctx)
            if ctx.event_name == "on_hand_scored" then
                add_chips(ctx, tonumber(j.runtime_counter) or 0)
                return
            end
            if ctx.blueprint then return end
            -- The reference announces the melt with a blocking status event, so it owns a
            -- beat in the after pass (`state_events.lua:1063-1070`).
            mark_effect_applied(ctx)
            j.runtime_counter = tonumber(j.runtime_counter) - 5
            if tonumber(j.runtime_counter) <= 0 then
                if G and type(G.jokers) == "table" and G.remove_owned_joker_at then
                    for i, jj in ipairs(G.jokers) do
                        if jj == j then
                            local p = Popup()
                            p:spawn("Eaten!", "Nope", card_center_x(ctx.VT), card_center_y(ctx.VT))
                            Top:addPopup(p)
                            Card.play_dissolve_sfx()
                            G:remove_owned_joker_at(i, false, true)
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
        matches_trigger = function(_, e) return e == "card_held" end,
        apply_effect = function(_, ctx)
            local node = ctx and ctx.card_node
            if not node or (node.is_debuffed and node:is_debuffed()) then return end
            local played = {}
            for _, played_node in ipairs((ctx and ctx.played_cards) or {}) do played[played_node] = true end
            local lowest, raised = nil, nil
            -- `<=` deliberately chooses the rightmost equal rank
            -- (`reference/Balatro/card.lua:3320-3340`).
            for _, held_node in ipairs((G and G.hand and G.hand.card_nodes) or {}) do
                local data = held_node and held_node.card_data
                local rank = tonumber(data and data.rank)
                local enhancement = held_node and (held_node.enhancement or (data and data.enhancement))
                if not played[held_node] and enhancement ~= "stone" and rank
                    and (lowest == nil or rank <= lowest) then
                    lowest, raised = rank, held_node
                end
            end
            if raised ~= node then return end
            if lowest == 14 then lowest = 11 elseif lowest > 10 then lowest = 10 end
            add_mult(ctx, lowest * 2)
        end
    },

    j_dna = {
        matches_trigger = function(_, e) return e == "on_hand_played" end,
        apply_effect = function(_, ctx)
            if ctx.event_name ~= "on_hand_played" then return end
            if type(ctx.full_hand) ~= "table" or #ctx.full_hand ~= 1 then return end
            local eff = G and G.get_effective_hands_per_round and G:get_effective_hands_per_round()
            if (tonumber(G and G.hands) or 0) ~= eff - 1 then return end

            local node = ctx.full_hand[1]
            local cd = node and node.card_data
            local hand = G and G.hand
            if not cd or not hand or not hand.add_card then return end

            local copy = (G.deep_copy_card_data and G:deep_copy_card_data(cd)) or (Deck and Deck.copy_card_data(cd))
            if not copy then return end
            if G.ensure_card_uid then G:ensure_card_uid(copy) end
            if hand:add_card(copy, true) then
                if G.notify_cards_added_to_deck then
                    G:notify_cards_added_to_deck(1)
                end
                mark_created_item(ctx)
            end
        end,
    },

    j_sixth_sense = {
        -- reference/Balatro/card.lua:2603-2620 -- `destroying_card`, which the reference runs
        -- after `joker_main` and after the deck's `final_scoring_step`, not during scoring.
        -- The port's nearest slot is the after pass, one step past the chip commit.
        matches_trigger = function(_, e) return e == "on_hand_after" end,
        apply_effect = function(_, ctx)
            if ctx.event_name ~= "on_hand_after" then return end
            if ctx.blueprint then return end
            local eff = G and G.get_effective_hands_per_round and G:get_effective_hands_per_round() or 5
            if (tonumber(G and G.hands) or 0) ~= eff - 1 then return end
            if type(ctx.full_hand) ~= "table" or #ctx.full_hand ~= 1 then return end
            local node = ctx.full_hand[1]
            local cd = node and node.card_data
            if not cd or tonumber(cd.rank) ~= 6 then return end
            local hand = G and G.hand
            if not hand or not hand.destroy_card_node then return end
            if hand:destroy_card_node(node) then
                -- `destroy_card_node` already played the dissolve; the spectral arriving in
                -- its place is the second half of the trade.
                local tid = G:random_consumable_id_of_kind("spectral", nil, "sixth_sense")
                if tid then
                    G:add_consumable(tid)
                    mark_created_item(ctx)
                    Card.play_materialize_sfx()
                end
                mark_effect_applied(ctx)
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
            Sfx.play_chips(scoring_pitch())
        end,
    },

    j_faceless = {
        matches_trigger = function(_, e) return e == "on_discard" end,
        apply_effect = function(j, ctx) 
            -- Once per discard, on the last card of the set
            -- (reference/Balatro/card.lua:2860-2872).
            if ctx.discard_reason == "discard" and ctx.is_last ~= false then
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
                if G:do_random(1, j.config and j.config.extra and j.config.extra.odds or 1000, 1, "cavendish") then
                    --Destroy Joker
                    if G and type(G.jokers) == "table" and G.remove_owned_joker_at then
                        for i, jj in ipairs(G.jokers) do
                            if jj == j then
                                Card.play_dissolve_sfx()
                                local p = Popup()
                                p:spawn("Extinct!", "Nope", card_center_x(ctx.VT), card_center_y(ctx.VT))
                                Top:addPopup(p)
                                G:remove_owned_joker_at(i, false, true)
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
            if ctx.blueprint then return end
            j.runtime_counter = j.runtime_counter - 1 
            if j.runtime_counter < 1  then 
                --Destroy Joker
                if G and type(G.jokers) == "table" and G.remove_owned_joker_at then
                    for i, jj in ipairs(G.jokers) do
                        if jj == j then
                            local p = Popup()
                            p:spawn("Eaten!", "Nope", card_center_x(ctx.VT), card_center_y(ctx.VT))
                            Top:addPopup(p)
                            Card.play_dissolve_sfx()
                            G:remove_owned_joker_at(i, false, true)
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
            if ctx.event_name == "on_booster_skip" and not ctx.blueprint then
                j.stored_mult = (tonumber(j.stored_mult) or 0) + 3
                mark_effect_applied(ctx)
            else
                add_mult(ctx, tonumber(j.stored_mult) or 0)
            end
        end
    },

    j_superposition = {
        -- reference/Balatro/card.lua -- `joker_main`: the tarot arrives after the cards score.
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        apply_effect = function(j, ctx)
            local cards = ctx.cards
            if has_hand_type(ctx, "Straight") then 
                for _, card in ipairs(cards) do
                    if card.card_data.rank == 14 then
                        local tid = G:random_consumable_id_of_kind("tarot", nil, "superposition")
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
            elseif not ctx.blueprint then
                if G and G.roll_joker_shared_picks and G.set_joker_shared_picks then
                    local picks = G:roll_joker_shared_picks("j_todo_list")
                    if picks then
                        G:set_joker_shared_picks("j_todo_list", picks)
                    end
                end
            end
        end
    },

    j_hallucination = {
        matches_trigger = function(_, e) return e == "on_booster_open" end,
        apply_effect = function(j, ctx)
            if ctx.event_name ~= "on_booster_open" then return end
            if G:do_random(1, j.config and j.config.extra or 2, 1, "cartomancer") then
                local tid = G:random_consumable_id_of_kind("tarot", nil, "hallucination")
                if tid then
                    G:add_consumable(tid)
                    mark_created_item(ctx)
                end
            end
        end
    },

    j_vampire = {
        matches_trigger = function(_,e) return e == "on_hand_played" or e == "on_hand_scored" end,
        apply_effect = function(j, ctx)
            if ctx.event_name == "on_hand_played" then
                if ctx.blueprint then return end
                local drained = 0
                for _, card in ipairs(ctx.full_hand or {}) do
                    local data = card and card.card_data
                    if card and data and card.counts_for_play_score == true
                        and card.debuffed_for_scoring ~= true
                        and data.enhancement and data.enhancement ~= "none" then
                        card:set_enhancement("none")
                        drained = drained + 1
                    end
                end
                if drained > 0 then
                    -- Drain before cards are scored, so their enhancement cannot contribute
                    -- this hand (`reference/Balatro/card.lua:3465-3489`).
                    j.stored_xmult = (tonumber(j.stored_xmult) or 0) + 0.1 * drained
                    mark_effect_applied(ctx)
                end
            else
                mul_mult(ctx, tonumber(j.stored_xmult) or 0)
            end
        end
    },

    j_vagabond = {
        -- reference/Balatro/card.lua:3730-3746 -- `joker_main`, so the dollar test sees the
        -- money this hand's cards just paid out (Business Card, Golden Ticket, To Do List).
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        apply_effect = function(_,ctx)
            if G and G.money and G.money <= 4 then
                local tid = G:random_consumable_id_of_kind("tarot", nil, "vagabond")
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
            if ctx.is_boss_blind and not ctx.blueprint then
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
                    -- Debuffed discarded cards do not pay Mail-In Rebate
                    -- (reference/Balatro/card.lua:2825-2833).
                    local c = ctx.card
                    if c and not discarded_card_is_debuffed(ctx, ctx.card_index, c)
                        and tonumber(c.rank) == tonumber(j.random_rank) then
                        add_money(ctx, payout)
                    end
                end
            else
                if G and G.roll_joker_shared_picks and G.set_joker_shared_picks then
                    local picks = G:roll_joker_shared_picks("j_mail")
                    if picks then
                        G:set_joker_shared_picks("j_mail", picks)
                    end
                end
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
        -- reference/Balatro/card.lua:3718-3729 -- `joker_main`, gated on `blind.triggered`,
        -- which the reference clears when the hand is played and sets when a boss ability
        -- fires during it (`state_events.lua:454`). One payout per hand, not one per trigger.
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        apply_effect = function(_, ctx)
            if G and G.blind_triggered_this_hand == true then
                add_money(ctx, 8)
            end
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
            elseif not ctx.blueprint then
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
                if cr == jr and is_suit(ctx.suit, j.random_suit) then
                    -- X2, per the reference's `j_idol config = {extra = 2}`.
                    mul_mult(ctx, 2)
                end
            elseif ctx.event_name == "on_round_end" then
                if G and G.roll_joker_shared_picks and G.set_joker_shared_picks then
                    local picks = G:roll_joker_shared_picks("j_idol")
                    if picks then
                        G:set_joker_shared_picks("j_idol", picks)
                        mark_effect_applied(ctx)
                    end
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
        -- reference/Balatro/card.lua -- `joker_main`: the spectral arrives after the cards score.
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        apply_effect = function(j, ctx)
            if ctx.event_name == "on_hand_scored" then
                local hand = "Straight Flush"
                if ctx.hand_type == hand then
                    local tid = G:random_consumable_id_of_kind("spectral", nil, "seance")
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
            if ctx.event_name == "on_blind_selected" and not ctx.blueprint then
                if not ctx.is_boss_blind then
                    j.stored_xmult = (tonumber(j.stored_xmult) or 1)
                        + (tonumber(j.config and j.config.extra) or 0.5)
                    -- reference card.lua:2505 — collect the destructible jokers first and destroy
                    -- one only if the list is non-empty. Madness alone (or with only eternals)
                    -- gains the Xmult and destroys nothing.
                    if G and type(G.jokers) == "table" and G.remove_owned_joker_at then
                        local destructible = {}
                        for i, jj in ipairs(G.jokers) do
                            if jj ~= j and not jj.eternal then
                                destructible[#destructible + 1] = i
                            end
                        end
                        if #destructible > 0 then
                            local pos = destructible[G:random("madness", 1, #destructible)]
                            Card.play_dissolve_sfx()
                            G:remove_owned_joker_at(pos, false, true)
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
                local current_plays = tonumber(G and G.hand_play_counts and G.hand_play_counts[hand_idx]) or 0
                local another_hand_is_at_least_as_played = false
                if G and type(G.handlist) == "table" then
                    for idx = 1, #G.handlist do
                        if idx ~= hand_idx
                            and (not G.is_hand_stats_visible or G:is_hand_stats_visible(idx))
                            and (tonumber(G.hand_play_counts and G.hand_play_counts[idx]) or 0) >= current_plays then
                            another_hand_is_at_least_as_played = true
                            break
                        end
                    end
                end
                if not ctx.blueprint then
                    -- reference/Balatro/card.lua:3543-3561 — scale whenever another visible
                    -- hand ties or exceeds the current hand, rather than choosing one argmax.
                    if not another_hand_is_at_least_as_played then
                        j.stored_xmult = 1
                    else
                        j.stored_xmult = tonumber(j.stored_xmult or 1) + 0.2
                    end
                end
                mul_mult(ctx, j.stored_xmult or 1)
            end
        end
    },

    j_satellite = {
        matches_trigger = function(_, e) return e == "on_round_end" end,
        apply_effect = function(j, ctx)
            local unique = 0
            -- Satellite pays for distinct Planet cards used, rather than any source of
            -- hand levels (reference/Balatro/card.lua:1667-1673).
            for _, usage in pairs((G and G.consumable_usage) or {}) do
                if type(usage) == "table" and usage.kind == "planet" then
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
                    local s = card and card.card_data and card.card_data.suit
                    if is_suit(s, "Clubs") then
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
            local tid = G:random_consumable_id_of_kind("tarot", nil, "cartomancer")
            if tid and G:add_consumable(tid) then
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
            local src = G.consumables[G:random("perkeo", 1, #G.consumables)]
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
                Card.play_materialize_sfx()
                Joker.play_edition_reveal_sfx("negative")
            end
        end
    },

    j_burnt = {
        -- reference/Balatro/card.lua:2748-2755 -- `pre_discard`: Burnt levels the hand the
        -- discarded cards make *before* any of them are evaluated or leave.
        matches_trigger = function(_, e) return e == "on_pre_discard" or e == "on_round_begin" or e == "on_blind_selected" end,
        apply_effect = function(j, ctx)
            if ctx.event_name == "on_round_begin" or ctx.event_name == "on_blind_selected" then
                j._burnt_used_this_round = false
                return
            end
            -- The Hook's forced discard must leave the first voluntary discard available
            -- (reference/Balatro/card.lua:2749-2755).
            if ctx.event_name ~= "on_pre_discard" or ctx.hook == true then return end
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
                if ctx.blueprint then return end
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

            local src = G.jokers[G:random("invisible", 1, #G.jokers)]
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
            Card.play_materialize_sfx()
            Joker.play_edition_reveal_sfx(clone_edition)
        end
    },

    j_diet_cola = {
        matches_trigger = function(_, e) return e == "on_joker_sold" end,
        apply_effect = function(j, ctx)
            if ctx.event_name ~= "on_joker_sold" or ctx.joker ~= j then return end
            if G and G.addTag then
                G:addTag("double")
                mark_effect_applied(ctx)
            end
        end
    },

    j_hit_the_road = {
        matches_trigger = function(_, e) return e == "on_discard" or e == "on_hand_scored" or e == "on_round_end" end,
        apply_effect = function(j, ctx)
            if ctx.event_name == "on_discard" and ctx.discard_reason == "discard" and not ctx.blueprint then
                -- Per Jack, and a debuffed one does not count
                -- (reference/Balatro/card.lua:2835-2845).
                local c = ctx.card
                if c and tonumber(c.rank) == 11
                    and not discarded_card_is_debuffed(ctx, ctx.card_index, c) then
                    j.stored_xmult = j.stored_xmult + 0.5
                    mark_effect_applied(ctx)
                end
            elseif ctx.event_name == "on_hand_scored" then
                mul_mult(ctx, tonumber(j.stored_xmult) or 1)
            elseif ctx.event_name == "on_round_end" and not ctx.blueprint then
                j.stored_xmult = 1
            end
        end
    },
    
    j_stuntman = {
        matches_trigger = function(_, e) return e == "on_hand_scored" end,
        apply_effect = function(j, ctx)
            if ctx.event_name == "on_hand_scored" then
                add_chips(ctx, j.config and j.config.extra and j.config.extra.chip_mod or 250)
            end
        end
    },


}

function JokerEffects.get(joker)
    local def = joker and joker.def or {}
    local id = def.id
    if type(id) == "string" and SPECIAL[id] then
        return SPECIAL[id]
    end
    return nil
end

function JokerEffects.begin_apply_context(ctx)
    if type(ctx) ~= "table" then return end
    ctx._joker_effect_applied_now = false
    ctx._joker_effect_created_item_now = false
    ctx._joker_effect_silent = nil
    ctx._joker_effect_delay = nil
end

function JokerEffects.mark_effect_silent(ctx)
    mark_effect_silent(ctx)
end

function JokerEffects.set_effect_delay(ctx, seconds)
    set_effect_delay(ctx, seconds)
end

--- Seconds this trigger's beat should hold, or nil for the caller's default.
function JokerEffects.effect_delay(ctx)
    if type(ctx) ~= "table" then return nil end
    return tonumber(ctx._joker_effect_delay)
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

--- Shake the joker that just triggered, and — when the trigger came off one specific playing card
--- (`ctx.shake_card_node`, set by `Hand` for played / held cards) — that card alongside it, so the
--- player can see which card earned the score.
function JokerEffects.apply_shake_if_needed(joker, ctx)
    if not joker or not JokerEffects.should_shake_for_context(ctx) then return false end
    -- Strengths are the reference's: a trigger announcing itself pops at `0.6, 0.1`
    -- (`common_events.lua:894`), while the card it landed on gets the heavier `juice_card`
    -- pop with a free rotation (`common_events.lua:1120`).
    joker:juice_up(0.6, 0.1)
    -- The reference pairs every trigger pop with a room jiggle (`common_events.lua:895`).
    if G and G.shake then G:shake(0.7) end
    local card = ctx.shake_card_node
    if card and card.juice_up then
        card:juice_up(0.7)
    end
    return true
end
