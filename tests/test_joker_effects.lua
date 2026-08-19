--- Structural smoke test over the joker catalog and its effect implementations.
---
--- joker_effects.lua is ~1800 lines of one-line closures. Exercising each one properly
--- would need a scored hand, popups and live geometry, which is not worth building here.
--- What is worth catching is the cheap structural breakage that a refactor actually
--- causes: an effect keyed to an id that no longer exists, a catalog entry that silently
--- lost its implementation, a duplicated id, a malformed def.
---
--- The one behavioural assertion is that every `matches_trigger` is callable across every
--- event name without raising. Those predicates run on every joker on every event, so a
--- raise there is a hard crash mid-scoring.

local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

bootstrap.load()

--- Catalog ids that legitimately have no entry in joker_effects.lua. These jokers are
--- passive: nothing triggers them, other systems query ownership with `G:hasJoker(id)`
--- at the point their rule applies (hand.lua for Four Fingers, game.lua for Credit Card,
--- and so on). Anything that drops out of joker_effects and is not on this list is a
--- regression.
local PASSIVE_JOKERS = {
    j_astronomer = true, j_burglar = true, j_chaos = true, j_chicot = true,
    j_credit_card = true, j_drunkard = true, j_four_fingers = true, j_juggler = true,
    j_luchador = true, j_merry_andy = true, j_mr_bones = true, j_oops = true,
    j_pareidolia = true, j_ring_master = true, j_shortcut = true, j_smeared = true,
    j_splash = true, j_troubadour = true,
}

--- Every event name dispatched anywhere in joker_effects.lua.
local EVENT_NAMES = {
    "on_hand_scored", "card_played", "on_round_end", "on_discard", "on_hand_played",
    "on_blind_selected", "on_joker_sold", "on_round_begin", "card_held",
    "on_shop_reroll", "on_destroy", "on_consumable_used", "on_cards_added_to_deck",
    "on_booster_skip", "lucky_trigger", "on_boss_effect_triggered", "on_booster_open",
    "on_hand_after", "on_pre_discard",
    "glass_broken",
}

--- Sorted catalog ids.
---@return string[]
local function catalog_ids()
    local ids = {}
    for id in pairs(JOKER_DEFS) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids
end

--- The minimum a joker instance needs for `JokerEffects.get` and the trigger
--- predicates. Deliberately not a real Joker: constructing one pulls in Moveable
--- geometry and tooltip layout that this test has no use for.
---@param id string
---@return table
local function fake_joker(id)
    local def = JOKER_DEFS[id]
    return {
        def = def,
        config = def and def.config,
        edition = nil,
        sell_cost = def and def.sell_cost or 1,
        stored_mult = 0,
        stored_chips = 0,
        stored_xmult = 1,
        runtime_counter = 0,
        VT = { x = 0, y = 0, w = 10, h = 10 },
    }
end

local IDS = catalog_ids()

--------------------------------------------------------------------------------
-- Catalog integrity
--------------------------------------------------------------------------------

suite.test("the catalog loaded and is non-trivial", function()
    T.assert_eq(type(JOKER_DEFS), "table", "JOKER_DEFS should be a global table")
    T.assert_true(#IDS > 100,
        string.format("expected well over 100 jokers, found %d", #IDS))
end)

suite.test("every catalog entry's id matches its key", function()
    -- The catalog is keyed by id, and lookups go both ways (key -> def, def.id -> key).
    -- A mismatch makes a joker unbuyable or unsellable depending on which path runs.
    local bad = {}
    for _, key in ipairs(IDS) do
        local def = JOKER_DEFS[key]
        if type(def) ~= "table" then
            bad[#bad + 1] = key .. ": not a table"
        elseif def.id ~= key then
            bad[#bad + 1] = string.format("%s: def.id is %s", key, T.repr(def.id))
        end
    end
    T.assert_eq(#bad, 0, "id/key mismatches: " .. table.concat(bad, "; "))
end)

suite.test("no two jokers share an id", function()
    -- JOKER_DEFS is a map, so a duplicate literal key would have been silently
    -- overwritten at load. Compare against the raw source to catch that.
    local fh = assert(io.open((os.getenv("BALATRO_ROOT") or ".") .. "/joker_catalog.lua", "r"))
    local src = fh:read("*a")
    fh:close()

    local seen, dupes = {}, {}
    for id in src:gmatch('\n%s+id%s*=%s*"([^"]+)"') do
        if seen[id] then
            dupes[#dupes + 1] = id
        end
        seen[id] = true
    end
    T.assert_eq(#dupes, 0, "duplicate joker ids in joker_catalog.lua: "
        .. table.concat(dupes, ", "))
end)

suite.test("every joker carries the fields the UI reads unconditionally", function()
    local bad = {}
    for _, id in ipairs(IDS) do
        local def = JOKER_DEFS[id]
        if type(def.name) ~= "string" or def.name == "" then
            bad[#bad + 1] = id .. ".name"
        end
        if type(def.rarity) ~= "number" or def.rarity < 1 or def.rarity > 4 then
            bad[#bad + 1] = string.format("%s.rarity=%s", id, T.repr(def.rarity))
        end
        if type(def.cost) ~= "number" then
            bad[#bad + 1] = string.format("%s.cost=%s", id, T.repr(def.cost))
        end
        if type(def.pos) ~= "table" or def.pos.atlas == nil or def.pos.index == nil then
            bad[#bad + 1] = id .. ".pos"
        end
    end
    T.assert_eq(#bad, 0, "malformed joker defs: " .. table.concat(bad, ", "))
end)

suite.test("every joker has a structured tooltip", function()
    -- joker_catalog.lua rewrites def.tooltip into structured lines at load. If that
    -- pass stops running, every tooltip in the game silently empties.
    local bad = {}
    for _, id in ipairs(IDS) do
        local tip = JOKER_DEFS[id].tooltip
        if type(tip) ~= "table" or #tip == 0 then
            bad[#bad + 1] = id
        elseif type(tip[1]) ~= "table" or tip[1].kind ~= "rarity_badge" then
            bad[#bad + 1] = id .. " (first line is not a rarity badge)"
        end
    end
    T.assert_eq(#bad, 0, "jokers with a broken tooltip: " .. table.concat(bad, ", "))
end)

suite.test("sell cost is never above cost", function()
    local bad = {}
    for _, id in ipairs(IDS) do
        local def = JOKER_DEFS[id]
        local cost = tonumber(def.cost) or 0
        local sell = tonumber(def.sell_cost) or 0
        if sell > cost then
            bad[#bad + 1] = string.format("%s (cost %d, sell %d)", id, cost, sell)
        end
    end
    T.assert_eq(#bad, 0, "jokers that sell for more than they cost: "
        .. table.concat(bad, ", "))
end)

--------------------------------------------------------------------------------
-- Catalog <-> effects correspondence
--------------------------------------------------------------------------------

suite.test("every non-passive joker resolves to an effect implementation", function()
    local missing = {}
    for _, id in ipairs(IDS) do
        if not PASSIVE_JOKERS[id] then
            if JokerEffects.get(fake_joker(id)) == nil then
                missing[#missing + 1] = id
            end
        end
    end
    T.assert_eq(#missing, 0,
        "catalog jokers with no effect implementation and not on the passive list: "
        .. table.concat(missing, ", "))
end)

suite.test("every joker on the passive list is really passive", function()
    -- Keeps the allowlist honest: once a passive joker gains an implementation it must
    -- come off this list, or the previous test stops guarding it.
    local now_implemented = {}
    for id in pairs(PASSIVE_JOKERS) do
        if JOKER_DEFS[id] and JokerEffects.get(fake_joker(id)) ~= nil then
            now_implemented[#now_implemented + 1] = id
        end
    end
    table.sort(now_implemented)
    T.assert_eq(#now_implemented, 0,
        "these jokers now have an implementation and should leave PASSIVE_JOKERS: "
        .. table.concat(now_implemented, ", "))
end)

suite.test("every joker on the passive list still exists in the catalog", function()
    local stale = {}
    for id in pairs(PASSIVE_JOKERS) do
        if JOKER_DEFS[id] == nil then stale[#stale + 1] = id end
    end
    table.sort(stale)
    T.assert_eq(#stale, 0, "PASSIVE_JOKERS names jokers that no longer exist: "
        .. table.concat(stale, ", "))
end)

suite.test("an unknown joker id resolves to no implementation", function()
    T.assert_nil(JokerEffects.get({ def = { id = "j_does_not_exist" } }))
    T.assert_nil(JokerEffects.get({ def = {} }))
    T.assert_nil(JokerEffects.get(nil))
end)

--------------------------------------------------------------------------------
-- Implementation shape
--------------------------------------------------------------------------------

suite.test("every implementation exposes a usable entry point", function()
    -- Five jokers are retrigger-only (Mime, Hack, Dusk, Sock and Buskin, Hanging Chad)
    -- and legitimately have no apply_effect. An entry with neither is dead weight that
    -- can never fire.
    local inert = {}
    for _, id in ipairs(IDS) do
        local impl = JokerEffects.get(fake_joker(id))
        if impl then
            local has_apply = type(impl.apply_effect) == "function"
            local has_retrigger = type(impl.query_retrigger) == "function"
            local has_tooltip = type(impl.tooltip_lines) == "function"
            if not (has_apply or has_retrigger or has_tooltip) then
                inert[#inert + 1] = id
            end
        end
    end
    T.assert_eq(#inert, 0, "effect entries with no callable entry point: "
        .. table.concat(inert, ", "))
end)

suite.test("every implementation field is a function", function()
    local bad = {}
    local FIELDS = { "matches_trigger", "apply_effect", "query_retrigger", "tooltip_lines" }
    for _, id in ipairs(IDS) do
        local impl = JokerEffects.get(fake_joker(id))
        if impl then
            for _, field in ipairs(FIELDS) do
                local v = impl[field]
                if v ~= nil and type(v) ~= "function" then
                    bad[#bad + 1] = string.format("%s.%s is a %s", id, field, type(v))
                end
            end
        end
    end
    T.assert_eq(#bad, 0, table.concat(bad, ", "))
end)

suite.test("matches_trigger is callable for every joker and every event", function()
    -- These predicates run for every owned joker on every event, so any raise here is
    -- a crash in the middle of scoring. They must also return a boolean: `Joker`
    -- compares the result with `== true`, so a truthy non-boolean silently never fires.
    local errors = {}
    local non_boolean = {}

    for _, id in ipairs(IDS) do
        local impl = JokerEffects.get(fake_joker(id))
        if impl and type(impl.matches_trigger) == "function" then
            local joker = fake_joker(id)
            for _, event in ipairs(EVENT_NAMES) do
                local ctx = { event_name = event }
                local ok, res = pcall(impl.matches_trigger, joker, event, ctx)
                if not ok then
                    errors[#errors + 1] = string.format("%s on %s: %s", id, event, tostring(res))
                elseif type(res) ~= "boolean" and res ~= nil then
                    non_boolean[#non_boolean + 1] =
                        string.format("%s on %s returned %s", id, event, T.repr(res))
                end
            end
        end
    end

    if #errors > 0 then
        error({
            __test_failure = true,
            message = string.format("%d matches_trigger call(s) raised:\n  %s",
                #errors, table.concat(errors, "\n  ")),
        }, 0)
    end
    T.assert_eq(#non_boolean, 0, "matches_trigger returned a non-boolean: "
        .. table.concat(non_boolean, "; "))
end)

--- Jokers that copy the effect of a neighbour, so answering true to every event is
--- correct: they cannot know what they are copying until apply_effect delegates.
local DELEGATING_JOKERS = { j_blueprint = true, j_brainstorm = true }

--- A context carrying a plausible value for every field the trigger predicates read.
--- A bare `{ event_name = e }` makes predicates that guard on payload look inert when
--- they are simply being asked an unanswerable question.
---@param event string
---@param overrides table|nil fields to replace, for probing the other side of a guard
---@return table
local function rich_ctx(event, overrides)
    local ctx = {
        event_name = event,
        cards = { {}, {} },
        full_hand = { {}, {} },
        played_cards = { {}, {} },
        discarded_cards = { {} },
        destroyed_cards = {},
        discard_reason = "discard",
        discards_left = 1,
        rank = 12,
        suit = "Hearts",
        hand_type = "Pair",
        hand_index = 11,
        chips = 10,
        mult = 2,
        held = {},
        count = 1,
        free_joker_slots = 2,
        is_boss_blind = false,
        consumable_kind = "tarot",
        contains_hand_types = { Pair = true },
        card_node = { card_data = { rank = 12, suit = "Hearts" } },
        add_round_win_payout = function() end,
    }
    for k, v in pairs(overrides or {}) do ctx[k] = v end
    return ctx
end

--- Several predicates guard on a resource being exhausted (no discards left, last hand)
--- rather than available. A joker counts as live if any of these fires it.
local CTX_VARIANTS = {
    {},
    { discards_left = 0, cards = {}, played_cards = {} },
    { discard_reason = "hand_played", is_boss_blind = true, free_joker_slots = 0 },
}

suite.test("matches_trigger is selective rather than always true", function()
    -- A predicate that answers true to everything fires its joker on every event.
    -- Only the delegating jokers may legitimately do that.
    local always = {}
    for _, id in ipairs(IDS) do
        local impl = JokerEffects.get(fake_joker(id))
        if impl and type(impl.matches_trigger) == "function" and not DELEGATING_JOKERS[id] then
            local joker = fake_joker(id)
            local hits = 0
            for _, event in ipairs(EVENT_NAMES) do
                local ok, res = pcall(impl.matches_trigger, joker, event, rich_ctx(event))
                if ok and res == true then hits = hits + 1 end
            end
            if hits == #EVENT_NAMES then always[#always + 1] = id end
        end
    end
    T.assert_eq(#always, 0, "jokers whose matches_trigger is true for every event: "
        .. table.concat(always, ", "))
end)

suite.test("the delegating jokers do answer every event", function()
    -- Keeps the allowlist above honest in the other direction.
    for id in pairs(DELEGATING_JOKERS) do
        local impl = JokerEffects.get(fake_joker(id))
        T.assert_not_nil(impl, id .. " should have an implementation")
        for _, event in ipairs(EVENT_NAMES) do
            local ok, res = pcall(impl.matches_trigger, fake_joker(id), event, rich_ctx(event))
            T.assert_true(ok and res == true,
                id .. " should match " .. event .. " so it can copy its neighbour")
        end
    end
end)

suite.test("every joker matches at least one event or offers a retrigger", function()
    -- A joker whose predicate never fires and which has no retrigger hook is inert:
    -- the player buys it and nothing ever happens.
    --
    -- Some predicates inspect the joker's own accumulated state or its position among
    -- the owned jokers, so the fake is given a non-zero counter and a neighbour.
    local never = {}
    if not _G.G then bootstrap.new_game() end
    local saved_jokers = G.jokers

    for _, id in ipairs(IDS) do
        local impl = JokerEffects.get(fake_joker(id))
        if impl and type(impl.matches_trigger) == "function"
            and type(impl.query_retrigger) ~= "function" then
            local joker = fake_joker(id)
            joker.stored_mult = 4
            joker.stored_chips = 20
            joker.stored_xmult = 2
            joker.runtime_counter = 3
            -- Give it a right-hand neighbour: several triggers check for one.
            G.jokers = { joker, fake_joker("j_joker") }

            local hits = 0
            for _, event in ipairs(EVENT_NAMES) do
                for _, overrides in ipairs(CTX_VARIANTS) do
                    local ok, res = pcall(impl.matches_trigger, joker, event,
                        rich_ctx(event, overrides))
                    if ok and res == true then hits = hits + 1 end
                end
            end
            if hits == 0 then never[#never + 1] = id end
        end
    end

    G.jokers = saved_jokers
    T.assert_eq(#never, 0, "jokers whose matches_trigger never fires: "
        .. table.concat(never, ", "))
end)

--------------------------------------------------------------------------------
-- Madness
--------------------------------------------------------------------------------

--- Run Madness' on_blind_selected effect against a given joker list, with removals
--- recorded rather than performed (the real removal drags in Moveable teardown).
---@param owned table[] the contents of G.jokers, one of which is the Madness fake
---@param madness table the Madness fake inside `owned`
---@param is_boss_blind boolean|nil
---@return integer[] removed indices passed to remove_owned_joker_at
local function run_madness_blind_select(owned, madness, is_boss_blind)
    -- The effect reads the global G. Earlier files in the suite leave one installed;
    -- build one if this file is run on its own.
    if not _G.G then bootstrap.new_game() end
    local saved_jokers, saved_remove = G.jokers, G.remove_owned_joker_at
    local removed = {}
    G.jokers = owned
    G.remove_owned_joker_at = function(_, index) removed[#removed + 1] = index end

    local impl = JokerEffects.get(madness)
    local ok, err = pcall(impl.apply_effect, madness,
        { event_name = "on_blind_selected", is_boss_blind = is_boss_blind == true })

    G.jokers, G.remove_owned_joker_at = saved_jokers, saved_remove
    assert(ok, tostring(err))
    return removed
end

suite.test("Madness alone destroys nothing and still gains its Xmult", function()
    -- Regression: the destroy target used to be picked by rerolling math.random until
    -- it landed on a joker other than Madness itself. With Madness as the only joker
    -- that loop never terminates, so selecting a non-boss blind hung the game.
    local madness = fake_joker("j_madness")
    madness.stored_xmult = 1

    local removed = run_madness_blind_select({ madness }, madness)

    T.assert_eq(#removed, 0, "Madness alone should destroy nothing")
    T.assert_eq(madness.stored_xmult, 1.5, "Madness should still gain its Xmult")
end)

suite.test("Madness destroys a non-eternal neighbour", function()
    local madness = fake_joker("j_madness")
    madness.stored_xmult = 1
    local victim = fake_joker("j_joker")

    local removed = run_madness_blind_select({ madness, victim }, madness)

    T.assert_eq(#removed, 1, "Madness should destroy exactly one joker")
    T.assert_eq(removed[1], 2, "Madness should destroy the other joker, not itself")
    T.assert_eq(madness.stored_xmult, 1.5, "Madness should gain its Xmult")
end)

suite.test("Madness spares eternal jokers", function()
    -- reference card.lua:2507 excludes eternals from the destructible pool. Without
    -- that exclusion the reroll loop can only pick a joker the game refuses to remove.
    local madness = fake_joker("j_madness")
    madness.stored_xmult = 1
    local protected = fake_joker("j_joker")
    protected.eternal = true

    local removed = run_madness_blind_select({ madness, protected }, madness)

    T.assert_eq(#removed, 0, "an eternal joker should never be destroyed")
    T.assert_eq(madness.stored_xmult, 1.5, "Madness should still gain its Xmult")
end)

suite.test("Madness does nothing on a boss blind", function()
    local madness = fake_joker("j_madness")
    madness.stored_xmult = 1
    local victim = fake_joker("j_joker")

    local removed = run_madness_blind_select({ madness, victim }, madness, true)

    T.assert_eq(#removed, 0, "a boss blind should not trigger Madness")
    T.assert_eq(madness.stored_xmult, 1, "a boss blind should not raise the Xmult")
end)

--------------------------------------------------------------------------------
-- Context helpers
--------------------------------------------------------------------------------

suite.test("the effect context helpers are present and callable", function()
    for _, name in ipairs({ "get", "begin_apply_context", "mark_effect_applied",
                            "mark_created_item", "should_shake_for_context",
                            "apply_shake_if_needed" }) do
        T.assert_eq(type(JokerEffects[name]), "function", "JokerEffects." .. name)
    end
end)

suite.test("marking an effect applied is visible to should_shake_for_context", function()
    local ctx = { event_name = "on_hand_scored" }
    JokerEffects.begin_apply_context(ctx)
    T.assert_false(JokerEffects.should_shake_for_context(ctx),
        "a context with nothing applied should not request a shake")

    JokerEffects.begin_apply_context(ctx)
    JokerEffects.mark_effect_applied(ctx)
    T.assert_true(JokerEffects.should_shake_for_context(ctx),
        "a context with an applied effect should request a shake")
end)

suite.test("the context helpers tolerate a nil context", function()
    -- They are called from dispatch paths that do not always build a context.
    T.assert_no_error(function() JokerEffects.begin_apply_context(nil) end)
    T.assert_no_error(function() JokerEffects.mark_effect_applied(nil) end)
    T.assert_no_error(function() JokerEffects.mark_created_item(nil) end)
    T.assert_no_error(function() JokerEffects.should_shake_for_context(nil) end)
end)

--------------------------------------------------------------------------------
-- Trigger cadence
--------------------------------------------------------------------------------

local function trigger_joker(x, calls, applies)
    return {
        T = { x = x },
        matches_trigger = function() return true end,
        apply_effect = function(self, ctx)
            calls[#calls + 1] = self
            ctx._joker_effect_applied_now = applies ~= false
        end,
    }
end

suite.test("joker emit starts only one triggering joker per beat", function()
    local game = bootstrap.new_game(2201)
    local calls = {}
    local first = trigger_joker(10, calls)
    local second = trigger_joker(20, calls)
    game.jokers = { first, second }

    T.assert_true(game:begin_joker_emit("card_played", {}), "batch should pause scoring")
    T.assert_eq(#calls, 1, "only the first trigger belongs to the opening beat")
    T.assert_eq(calls[1], first, "slot order")

    game:_update_joker_emit_queue(game.JOKER_EMIT_INTERVAL)
    T.assert_eq(#calls, 2, "second trigger waits for the next beat")
    T.assert_eq(calls[2], second, "second slot follows")
end)

suite.test("joker emit skips no-ops without spending a beat", function()
    local game = bootstrap.new_game(2202)
    local calls = {}
    local noop = trigger_joker(10, calls, false)
    local trigger = trigger_joker(20, calls)
    game.jokers = { noop, trigger }

    T.assert_true(game:begin_joker_emit("on_hand_scored", {}), "later trigger should keep the batch")
    T.assert_eq(#calls, 2, "no-op is scanned through immediately")
    T.assert_eq(calls[2], trigger, "first real trigger owns the beat")
end)

suite.test("played card gets one beat before its first joker and no tail beat", function()
    local game = bootstrap.new_game(2206)
    local called = 0
    local saved_begin = game.begin_joker_emit
    game.begin_joker_emit = function(_, event_name, ctx)
        called = called + 1
        T.assert_eq(event_name, "card_played", "pending event")
        T.assert_true(type(ctx) == "table", "pending context")
        return true
    end
    local hand = setmetatable({
        _play_sequence = {
            phase = "trigger",
            timer = 0,
            trigger_wait = 0.75,
            pending_joker_ctx = { chips = 10, mult = 2 },
            play_rep = 1,
            play_rep_total = 1,
        },
    }, { __index = Hand })

    hand:_update_play_sequence(0.74)
    T.assert_eq(called, 0, "joker does not overlap the card beat")
    hand:_update_play_sequence(0.02)
    T.assert_eq(called, 1, "joker begins on the following beat")
    T.assert_eq(hand._play_sequence.phase, "wait_jokers", "scoring waits on the batch")
    T.assert_true(hand._play_sequence.joker_wait_resume.delay_next_trigger == false,
        "batch completion adds no empty tail beat")

    game.begin_joker_emit = saved_begin
end)

suite.test("Cartomancer triggers at blind selection when there is room", function()
    local game = bootstrap.new_game(2203)
    local impl = JokerEffects.get(fake_joker("j_cartomancer"))
    local added
    game.random_consumable_id_of_kind = function() return "tarot_fool" end
    game.add_consumable = function(_, id) added = id; return true end
    local ctx = { event_name = "on_blind_selected" }

    JokerEffects.begin_apply_context(ctx)
    impl.apply_effect(nil, ctx)

    T.assert_eq(added, "tarot_fool", "Cartomancer creates a Tarot")
    T.assert_true(ctx._joker_effect_created_item_now == true, "creation announces the trigger")
end)

suite.test("DNA readiness pulse uses real time and stops after the first hand", function()
    local game = bootstrap.new_game(2204)
    game.hands = game:get_effective_hands_per_round()
    game.real_dt = 0.4
    local pulses = 0
    local dna = {
        def = { id = "j_dna" },
        juice_up = function() pulses = pulses + 1 end,
    }
    setmetatable(dna, { __index = Joker })

    dna:start_ready_pulse()
    T.assert_eq(pulses, 1, "first hand draw pulses immediately")
    dna:update_ready_pulse(game.real_dt)
    dna:update_ready_pulse(game.real_dt)
    T.assert_eq(pulses, 2, "repeats after 0.8 real seconds")

    game.hands = game.hands - 1
    dna:update_ready_pulse(0.8)
    T.assert_eq(pulses, 2, "playing the first hand disarms DNA")
    T.assert_true(dna._ready_pulse_active == nil, "pulse loop stopped")
end)

suite.test("Trading Card readiness pulse stops after the first discard", function()
    local game = bootstrap.new_game(2205)
    game.discards = game:get_effective_discards_per_round()
    local pulses = 0
    local trading = {
        def = { id = "j_trading_card" },
        juice_up = function() pulses = pulses + 1 end,
    }
    setmetatable(trading, { __index = Joker })

    trading:start_ready_pulse()
    trading:update_ready_pulse(0.8)
    T.assert_eq(pulses, 2, "armed Trading Card repeats")

    game.discards = game.discards - 1
    trading:update_ready_pulse(0.8)
    T.assert_eq(pulses, 2, "first discard disarms Trading Card")
end)

--------------------------------------------------------------------------------
-- Scoring pipeline parity
--------------------------------------------------------------------------------

local function runtime_joker(id, fields)
    local joker = fake_joker(id)
    for key, value in pairs(fields or {}) do joker[key] = value end
    joker.VT = { x = 0, y = 0, w = 10, h = 10, scale = 1 }
    joker.effect_impl = JokerEffects.get(joker)
    joker.matches_trigger = Joker.matches_trigger
    joker.apply_effect = Joker.apply_effect
    joker.apply_edition_on_hand_scored = Joker.apply_edition_on_hand_scored
    joker.juice_up = function() end
    return setmetatable(joker, { __index = Joker })
end

suite.test("Blueprint and Brainstorm copy payouts without advancing source state", function()
    local game = bootstrap.new_game(2210)
    local old_top = _G.Top
    _G.Top = { addPopup = function() end }
    local green = runtime_joker("j_green_joker", { stored_mult = 5 })
    local blueprint = runtime_joker("j_blueprint")
    local brainstorm = runtime_joker("j_brainstorm")

    game.jokers = { blueprint, green }
    blueprint:apply_effect({ event_name = "on_hand_played", mult = 1 })
    T.assert_eq(green.stored_mult, 5, "Blueprint must not advance Green Joker")

    local copied_payout = { event_name = "on_hand_scored", mult = 1 }
    blueprint:apply_effect(copied_payout)
    T.assert_eq(copied_payout.mult, 6, "Blueprint still receives Green Joker's current payout")
    T.assert_eq(green.stored_mult, 5, "copied payout leaves source state intact")

    game.jokers = { green, brainstorm }
    brainstorm:apply_effect({ event_name = "on_hand_played", mult = 1 })
    T.assert_eq(green.stored_mult, 5, "Brainstorm must not advance Green Joker")

    local dagger = runtime_joker("j_ceremonial", { stored_mult = 3 })
    local victim = runtime_joker("j_joker", { sell_cost = 4 })
    game.jokers = { blueprint, dagger, victim }
    blueprint:apply_effect({ event_name = "on_blind_selected", mult = 1 })
    T.assert_eq(#game.jokers, 3, "Blueprint must not destroy Ceremonial Dagger's neighbour")
    T.assert_eq(dagger.stored_mult, 3, "Blueprint must not scale Ceremonial Dagger")
    _G.Top = old_top
end)

suite.test("polychrome joker edition applies after its own effect", function()
    local game = bootstrap.new_game(2211)
    local joker = {
        T = { x = 0 },
        edition = "polychrome",
        normalize_edition = Joker.normalize_edition,
        juice_up = function() end,
        matches_trigger = function() return true end,
        apply_effect = function(_, ctx) ctx.mult = ctx.mult + 2 end,
        apply_edition_on_hand_scored = Joker.apply_edition_on_hand_scored,
    }
    game.jokers = { joker }

    local ctx = { chips = 0, mult = 1 }
    game:emit_joker_event("on_hand_scored", ctx)
    T.assert_eq(ctx.mult, 4.5, "the Joker's +2 applies before Polychrome x1.5")
end)

suite.test("full played hand controls Half, Square, DNA, and Sixth Sense", function()
    local game = bootstrap.new_game(2212)
    local old_top = _G.Top
    _G.Top = { addPopup = function() end }
    local scoring_only = { card_data = { rank = 6, suit = "Hearts" } }
    local full_hand = { scoring_only, {}, {}, {} }

    local half = JokerEffects.get(fake_joker("j_half"))
    T.assert_false(half.matches_trigger(nil, "on_hand_scored", { cards = { scoring_only }, full_hand = full_hand }),
        "Half Joker must count all played cards, not only scoring cards")
    T.assert_true(half.matches_trigger(nil, "on_hand_scored", { cards = { scoring_only }, full_hand = { scoring_only, {}, {} } }),
        "Half Joker triggers for at most three played cards")

    local square_joker = fake_joker("j_square")
    square_joker.stored_chips = 0
    local square = JokerEffects.get(square_joker)
    square.apply_effect(square_joker, {
        event_name = "on_hand_scored",
        cards = { scoring_only },
        full_hand = full_hand,
        chips = 0,
        VT = { x = 0, y = 0, w = 10, h = 10, scale = 1 },
    })
    T.assert_eq(square_joker.stored_chips, 4, "Square Joker scales from four played cards")

    local old_hand, old_hands, old_notify = game.hand, game.hands, game.notify_cards_added_to_deck
    local copied = 0
    game.hand = {
        add_card = function(_, _) copied = copied + 1; return true end,
    }
    game.notify_cards_added_to_deck = function() end
    game.hands = game:get_effective_hands_per_round() - 1

    local dna = JokerEffects.get(fake_joker("j_dna"))
    dna.apply_effect(nil, { event_name = "on_hand_played", cards = { scoring_only }, full_hand = { scoring_only, {} } })
    T.assert_eq(copied, 0, "DNA must reject a multi-card played hand even with one scoring card")

    local destroyed = 0
    game.hand = {
        destroy_card_node = function() destroyed = destroyed + 1; return true end,
    }
    local sixth = JokerEffects.get(fake_joker("j_sixth_sense"))
    sixth.apply_effect(nil, { event_name = "on_hand_after", cards = { scoring_only }, full_hand = { scoring_only, {} } })
    T.assert_eq(destroyed, 0, "Sixth Sense must reject a multi-card played hand")

    game.hand, game.hands, game.notify_cards_added_to_deck = old_hand, old_hands, old_notify
    _G.Top = old_top
end)

suite.test("Blackboard ignores played cards and Raised Fist uses the rightmost low held card", function()
    local game = bootstrap.new_game(2213)
    local old_hand, old_top = game.hand, _G.Top
    _G.Top = { addPopup = function() end }
    local played = { card_data = { rank = 8, suit = "Hearts" } }
    local rightmost_low = { card_data = { rank = 2, suit = "Clubs" } }
    local higher = { card_data = { rank = 5, suit = "Spades" } }
    game.hand = { card_nodes = { played, higher, rightmost_low } }

    local blackboard = JokerEffects.get(fake_joker("j_blackboard"))
    local blackboard_ctx = {
        event_name = "on_hand_scored",
        played_cards = { played, higher, rightmost_low },
        mult = 1,
        VT = { x = 0, y = 0, w = 10, h = 10, scale = 1 },
    }
    blackboard.apply_effect(nil, blackboard_ctx)
    T.assert_eq(blackboard_ctx.mult, 3, "Blackboard triggers when no cards are held")

    local raised_fist = JokerEffects.get(fake_joker("j_raised_fist"))
    local raised_ctx = {
        event_name = "card_held",
        card_node = rightmost_low,
        played_cards = { played },
        mult = 1,
        VT = { x = 0, y = 0, w = 10, h = 10, scale = 1 },
    }
    raised_fist.apply_effect(nil, raised_ctx)
    T.assert_eq(raised_ctx.mult, 5, "Raised Fist adds twice the rightmost lowest held rank")

    local stone = { card_data = { enhancement = "stone" } }
    local ordinary = { card_data = { rank = 5, suit = "Diamonds" } }
    game.hand = { card_nodes = { played, stone, ordinary } }
    raised_ctx = {
        event_name = "card_held",
        card_node = ordinary,
        played_cards = { played },
        mult = 1,
        VT = { x = 0, y = 0, w = 10, h = 10, scale = 1 },
    }
    raised_fist.apply_effect(nil, raised_ctx)
    T.assert_eq(raised_ctx.mult, 11, "Raised Fist ignores rankless Stone Cards")

    game.hand, _G.Top = old_hand, old_top
end)

suite.test("stone cards do not expose rank or suit to card-played jokers", function()
    local game = bootstrap.new_game(2220)
    local old_top = _G.Top
    _G.Top = { addPopup = function() end }
    local ctx = {
        event_name = "card_played",
        rank = nil,
        suit = nil,
        mult = 1,
        VT = { x = 0, y = 0, w = 10, h = 10, scale = 1 },
    }
    JokerEffects.get(fake_joker("j_fibonacci")).apply_effect(nil, ctx)
    JokerEffects.get(fake_joker("j_greedy_joker")).apply_effect(nil, ctx)
    T.assert_eq(ctx.mult, 1, "rank and suit jokers must not trigger from a Stone Card")
    _G.Top = old_top
end)

suite.test("rankless Stone Cards cannot make hands and score a flat fifty chips", function()
    local game = bootstrap.new_game(2222)
    local function hand_name(cards)
        local hand = Hand(game)
        hand.card_nodes = cards
        hand.selected = cards
        hand:calculate_play()
        return G.handlist[G.selectedHand]
    end
    local function node(rank, suit, enhancement)
        return { card_data = { rank = rank, suit = suit, enhancement = enhancement }, face_up = true }
    end

    T.assert_eq(hand_name({ node(7, "Hearts"), node(nil, nil, "stone") }), "High Card",
        "a Stone Card cannot complete a pair")
    T.assert_eq(hand_name({
        node(2, "Hearts"), node(5, "Hearts"), node(7, "Hearts"), node(9, "Hearts"),
        node(nil, nil, "stone"),
    }), "High Card", "a Stone Card cannot complete a flush")
    T.assert_eq(hand_name({
        node(2, "Hearts"), node(3, "Clubs"), node(4, "Diamonds"), node(5, "Spades"),
        node(nil, nil, "stone"),
    }), "High Card", "a Stone Card cannot complete a straight")

    local hand = Hand(game)
    local stone = setmetatable({
        enhancement = "stone",
        VT = { x = 0, y = 0, w = 10, h = 10, scale = 1 },
        collision_offset = { x = 0, y = 0 },
    }, { __index = Card })
    local chips, mult = hand:accumulate_card_score(0, 1, {
        card_data = { enhancement = "stone" },
        VT = stone.VT,
        collision_offset = stone.collision_offset,
    })
    local ctx = { chips = chips, mult = mult }
    stone:do_enhancement(ctx)
    T.assert_eq(ctx.chips, 50, "a Stone Card scores its flat fifty chips")
end)

suite.test("Marble Joker creates a rankless and suitless Stone Card", function()
    local game = bootstrap.new_game(2221)
    local marble = JokerEffects.get(fake_joker("j_marble"))
    local old_notify = game.notify_cards_added_to_deck
    local deck = { cards = {} }
    game.notify_cards_added_to_deck = function() end

    marble.apply_effect(nil, { event_name = "on_blind_selected", deck = deck })

    local created = deck.cards[1]
    T.assert_not_nil(created, "Marble Joker creates a card")
    T.assert_eq(created.enhancement, "stone")
    T.assert_nil(created.rank, "Marble Stone Card has no rank")
    T.assert_nil(created.suit, "Marble Stone Card has no suit")
    game.notify_cards_added_to_deck = old_notify
end)

suite.test("Baseball Card excludes itself from uncommon multipliers", function()
    local game = bootstrap.new_game(2214)
    local old_top = _G.Top
    _G.Top = { addPopup = function() end }
    local baseball = fake_joker("j_baseball_card")
    local uncommon = fake_joker("j_joker")
    uncommon.rarity = 2
    game.jokers = { baseball, uncommon }
    local ctx = {
        event_name = "on_hand_scored",
        mult = 1,
        VT = { x = 0, y = 0, w = 10, h = 10, scale = 1 },
    }

    JokerEffects.get(baseball).apply_effect(baseball, ctx)

    T.assert_eq(ctx.mult, 1.5, "only the other uncommon joker should receive Baseball Card's Xmult")
    _G.Top = old_top
end)

suite.test("Dusk and Seltzer do not retrigger held cards", function()
    local game = bootstrap.new_game(2215)
    game.hands = 0
    local dusk = JokerEffects.get(fake_joker("j_dusk"))
    local seltzer_joker = fake_joker("j_seltzer")
    seltzer_joker.runtime_counter = 3
    local seltzer = JokerEffects.get(seltzer_joker)

    T.assert_eq(dusk.query_retrigger(nil, { held = true }), 0, "Dusk must not retrigger held cards")
    T.assert_eq(seltzer.query_retrigger(seltzer_joker, { held = true }), 0,
        "Seltzer must not retrigger held cards")
    T.assert_eq(dusk.query_retrigger(nil, { held = false }), 1, "Dusk still retriggers played cards")
    T.assert_eq(seltzer.query_retrigger(seltzer_joker, { held = false }), 1,
        "Seltzer still retriggers played cards")
end)

suite.test("Mime retriggers held cards only after an effective first pass", function()
    local mime = JokerEffects.get(fake_joker("j_mime"))
    T.assert_eq(mime.query_retrigger(nil, { held = true, held_first_pass_effect_applied = false }), 0,
        "Mime must not add a second chance roll to an empty first pass")
    T.assert_eq(mime.query_retrigger(nil, { held = true, held_first_pass_effect_applied = true }), 1,
        "Mime retriggers a held card whose first pass applied an effect")
end)

suite.test("Ceremonial Dagger cannot gain Mult from an eternal neighbour", function()
    local game = bootstrap.new_game(2216)
    local dagger = fake_joker("j_ceremonial")
    dagger.stored_mult = 3
    local eternal = fake_joker("j_joker")
    eternal.eternal = true
    eternal.sell_cost = 5
    local removed = {}
    local old_remove = game.remove_owned_joker_at
    game.jokers = { dagger, eternal }
    game.remove_owned_joker_at = function(_, index) removed[#removed + 1] = index end

    JokerEffects.get(dagger).apply_effect(dagger, { event_name = "on_blind_selected" })

    T.assert_eq(dagger.stored_mult, 3, "an eternal joker must not grant free Mult")
    T.assert_eq(#removed, 0, "an eternal joker must not be sliced")
    game.remove_owned_joker_at = old_remove
end)

suite.test("Bull and Bootstraps ignore negative money", function()
    local game = bootstrap.new_game(2217)
    game.money = -6
    local bull_ctx = { event_name = "on_hand_scored", chips = 10 }
    local boots_ctx = { event_name = "on_hand_scored", mult = 3 }

    JokerEffects.get(fake_joker("j_bull")).apply_effect(nil, bull_ctx)
    JokerEffects.get(fake_joker("j_bootstraps")).apply_effect(nil, boots_ctx)

    T.assert_eq(bull_ctx.chips, 10, "Bull must not subtract chips while in debt")
    T.assert_eq(boots_ctx.mult, 3, "Bootstraps must not subtract Mult while in debt")
end)

suite.test("Ramen is consumed when its Xmult reaches one", function()
    local game = bootstrap.new_game(2218)
    local old_top = _G.Top
    _G.Top = { addPopup = function() end }
    local ramen = fake_joker("j_ramen")
    ramen.runtime_counter = 1.01
    local removed = {}
    local old_remove = game.remove_owned_joker_at
    game.jokers = { ramen }
    game.remove_owned_joker_at = function(_, index) removed[#removed + 1] = index end

    -- The discard pass dispatches one event per discarded card, each carrying that card.
    JokerEffects.get(ramen).apply_effect(ramen, {
        event_name = "on_discard",
        discarded_cards = { {} },
        card = {},
        card_index = 1,
        is_last = true,
        VT = { x = 0, y = 0, w = 10, h = 10, scale = 1 },
    })

    T.assert_eq(ramen.runtime_counter, 1, "the discard should reduce Ramen to exactly X1")
    T.assert_eq(removed[1], 1, "Ramen at exactly X1 must be consumed")
    game.remove_owned_joker_at = old_remove
    _G.Top = old_top
end)

suite.test("Obelisk keeps scaling while another visible hand ties its play count", function()
    local game = bootstrap.new_game(2219)
    game.handlist = { "Secret A", "Secret B", "Secret C", "Pair", "High Card" }
    game.hand_play_counts = { [4] = 3, [5] = 3 }
    local obelisk = fake_joker("j_obelisk")
    obelisk.stored_xmult = 1
    local old_top = _G.Top
    _G.Top = { addPopup = function() end }
    local ctx = {
        event_name = "on_hand_scored",
        hand_index = 4,
        mult = 1,
        VT = { x = 0, y = 0, w = 10, h = 10, scale = 1 },
    }

    JokerEffects.get(obelisk).apply_effect(obelisk, ctx)

    T.assert_eq(obelisk.stored_xmult, 1.2, "a tied visible hand must preserve Obelisk scaling")
    T.assert_eq(ctx.mult, 1.2, "Obelisk applies the newly increased Xmult")
    _G.Top = old_top
end)

suite.test("Satellite pays for unique Planets used, rather than leveled hands", function()
    local game = bootstrap.new_game(2220)
    game.hand_stats[1].level = 9 -- Space/Burnt levels must not affect Satellite.
    game:track_consumable_use({ id = "planet_mercury", kind = "planet" })
    game:track_consumable_use({ id = "planet_mercury", kind = "planet" })
    game:track_consumable_use({ id = "planet_venus", kind = "planet" })

    local satellite = fake_joker("j_satellite")
    local paid = 0
    JokerEffects.get(satellite).apply_effect(satellite, {
        event_name = "on_round_end",
        add_round_win_payout = function(_, amount) paid = amount end,
    })

    T.assert_eq(satellite.running_count, 2, "duplicate Planet uses count once")
    T.assert_eq(paid, 2, "Satellite pays one dollar per unique Planet")
end)

suite.test("Burnt Joker keeps its first-discard trigger when The Hook discards", function()
    local game = bootstrap.new_game(2223)
    game.current_boss_blind_id = "bl_hook"
    game.selectedHand = 1
    game.hand = Hand(game)
    game.hand:create_card({ rank = 9, suit = "Clubs" })
    game.hand:create_card({ rank = 10, suit = "Spades" })
    T.assert_true(game:add_joker_by_def("j_burnt"))
    local burnt = game.jokers[1]
    local upgrades = 0
    game.upgrade_hand_level_at_index = function()
        upgrades = upgrades + 1
        return true
    end

    game:boss_after_play_before_draw()

    T.assert_eq(upgrades, 0, "The Hook must not spend Burnt Joker's upgrade")
    T.assert_false(burnt._burnt_used_this_round == true, "Burnt remains armed for a player discard")

    -- Burnt is a `pre_discard` joker: it levels the hand the discarded cards make before any
    -- of them is evaluated (reference/Balatro/card.lua:2748-2755).
    JokerEffects.get(burnt).apply_effect(burnt, {
        event_name = "on_pre_discard",
        discard_reason = "discard",
    })
    T.assert_eq(upgrades, 1, "a player discard's pre-discard pass spends it")
    T.assert_true(burnt._burnt_used_this_round == true, "and only once a round")
end)

suite.test("Mail takes its rerolled rank from the deck and Castle and Mail skip debuffed cards", function()
    local game = bootstrap.new_game(2224)
    game.deck = {
        random_card = function()
            return { rank = 13, suit = "Hearts" }
        end,
    }
    local mail = fake_joker("j_mail")
    JokerEffects.get(mail).apply_effect(mail, { event_name = "on_round_end" })
    T.assert_eq(game:get_joker_shared_pick("j_mail").random_rank, 13,
        "Mail's requested rank must be represented in the deck")

    local castle = fake_joker("j_castle")
    castle.random_suit = "Hearts"
    local old_top = _G.Top
    _G.Top = { addPopup = function() end }
    game.money = 0
    mail.random_rank = 13
    local subject = { rank = 13, suit = "Hearts", debuff = true }
    local ctx = {
        event_name = "on_discard",
        discard_reason = "discard",
        discarded_cards = { subject },
        card = subject,
        card_index = 1,
        is_last = true,
        VT = { x = 0, y = 0, w = 10, h = 10, scale = 1 },
    }
    JokerEffects.get(castle).apply_effect(castle, ctx)
    JokerEffects.get(mail).apply_effect(mail, ctx)
    T.assert_eq(castle.runtime_counter, 0, "a debuffed card must not grow Castle")
    T.assert_eq(game.money, 0, "a debuffed card must not pay Mail")

    subject.debuff = false
    JokerEffects.get(castle).apply_effect(castle, ctx)
    JokerEffects.get(mail).apply_effect(mail, ctx)
    T.assert_eq(castle.runtime_counter, 3, "a non-debuffed matching suit grows Castle")
    T.assert_eq(game.money, 5, "a non-debuffed matching rank pays Mail")
    _G.Top = old_top
end)

--- End-of-round held effects build a `reps` list per card from the Red Seal and from every
--- joker (`state_events.lua:171-207`), so they repeat exactly like held scoring does.
suite.test("end-of-round card effects retrigger from a Red Seal and from Mime", function()
    local game = bootstrap.new_game(2232)
    game.hand = Hand(game)
    game.hand:create_card({ rank = 5, suit = "Hearts", enhancement = "gold" })
    game.money = 0
    game:emit_hand_cards_event("on_round_end", {})
    T.assert_eq(game.money, 3, "a plain Gold card pays once")

    -- Gold + Red Seal pays twice.
    game.hand = Hand(game)
    game.hand:create_card({ rank = 5, suit = "Hearts", enhancement = "gold", seal = "red" })
    game.money = 0
    game:emit_hand_cards_event("on_round_end", {})
    T.assert_eq(game.money, 6, "the Red Seal repeats the payout")

    -- Mime repeats every held card's end-of-round effect.
    game.hand = Hand(game)
    game.hand:create_card({ rank = 5, suit = "Hearts", enhancement = "gold" })
    T.assert_true(game:add_joker_by_def("j_mime"))
    game.money = 0
    game:emit_hand_cards_event("on_round_end", {})
    T.assert_eq(game.money, 6, "Mime doubles end-of-round income")

    -- A card with no end-of-round effect is not repeated at all.
    game.hand = Hand(game)
    game.hand:create_card({ rank = 5, suit = "Hearts", seal = "red" })
    game.money = 0
    game:emit_hand_cards_event("on_round_end", {})
    T.assert_eq(game.money, 0)
end)

--- The Hook's forced discard runs through the same discard path as a player discard
--- (`blind.lua:466-484` → `state_events.lua:400` `calculate_seal{discard = true}`), so a
--- Purple Seal still makes its Tarot.
suite.test("a Purple Seal fires when The Hook discards the card", function()
    local game = bootstrap.new_game(2230)
    game.get_active_boss_blind_id = function() return "bl_hook" end
    game.hand = Hand(game)
    game.hand:create_card({ rank = 9, suit = "Clubs", seal = "purple" })
    game.hand:create_card({ rank = 10, suit = "Spades", seal = "purple" })

    local created = 0
    game.add_consumable = function() created = created + 1 return true end
    game.can_add_consumable = function() return true end
    game.random_non_fool_tarot_id = function() return "tarot_magician" end

    game:boss_after_play_before_draw()
    T.assert_eq(created, 2, "both discarded Purple Seals pay out")
end)

--- Reference `j_idol config = {extra = 2}` → X2 Mult. The port shipped X3.
suite.test("The Idol gives X2 Mult on its chosen card", function()
    bootstrap.new_game(2231)
    local idol = fake_joker("j_idol")
    idol.random_rank = 14
    idol.random_suit = "Hearts"

    local old_top = _G.Top
    _G.Top = { addPopup = function() end }
    local VT = { x = 0, y = 0, w = 10, h = 10, scale = 1 }

    local ctx = { event_name = "card_played", rank = 14, suit = "Hearts", chips = 0, mult = 4, VT = VT }
    JokerEffects.get(idol).apply_effect(idol, ctx)
    T.assert_eq(ctx.mult, 8, "4 mult doubles, not triples")

    local miss = { event_name = "card_played", rank = 13, suit = "Hearts", chips = 0, mult = 4, VT = VT }
    JokerEffects.get(idol).apply_effect(idol, miss)
    T.assert_eq(miss.mult, 4, "a non-matching card is untouched")
    _G.Top = old_top
end)

return suite
