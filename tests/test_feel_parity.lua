--- Feel-parity behaviours ported from the reference: the payout-scaled blind defeat beat,
--- the always-on room drift, and the selection lift running through the card spring.
local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")
local DynaText = require("dyna_text")
local Particles = require("particles")

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

local function count_cue(cues, wanted)
    local n = 0
    for _, c in ipairs(cues) do
        if c.cue == wanted then n = n + 1 end
    end
    return n
end

-- Reference `state_events.lua:1150`: 1.3*min(dollars+2,7)/2*0.15 + 0.5.
local function expected_hold(dollars)
    return 1.3 * math.min(dollars + 2, 7) / 2 * 0.15 + 0.5
end

suite.test("the blind defeat hold scales with the payout", function()
    local g = bootstrap.new_game()
    g.STATE = g.STATES.SELECTING_HAND

    g:begin_blind_defeat(3)
    T.assert_near(g._blind_defeat.hold, expected_hold(3), 1e-9)

    g:begin_blind_defeat(8)
    local capped = g._blind_defeat.hold
    T.assert_near(capped, expected_hold(8), 1e-9)
    -- dollars+2 is clamped at 7, so a fat payout stops growing the beat.
    g:begin_blind_defeat(40)
    T.assert_near(g._blind_defeat.hold, capped, 1e-9)
end)

suite.test("the defeat rings one descending ping per dollar, capped at seven", function()
    local g = bootstrap.new_game()
    g.STATE = g.STATES.SELECTING_HAND
    with_recorded_cues(function(cues)
        g:begin_blind_defeat(3)
        g:_update_blind_defeat(5)
        T.assert_eq(count_cue(cues, "cancel"), 5, "dollars + 2 pings")
        local last_pitch
        for _, c in ipairs(cues) do
            if c.cue == "cancel" then
                if last_pitch then T.assert_true(c.pitch < last_pitch, "pings descend") end
                last_pitch = c.pitch
            end
        end
    end)

    local g2 = bootstrap.new_game()
    g2.STATE = g2.STATES.SELECTING_HAND
    with_recorded_cues(function(cues)
        g2:begin_blind_defeat(40)
        g2:_update_blind_defeat(5)
        T.assert_eq(count_cue(cues, "cancel"), 7, "ping count is clamped at seven")
        -- Reference `blind.lua:308` only lands the closing whoosh on a long ladder.
        T.assert_eq(count_cue(cues, "whoosh2"), 1)
    end)
end)

suite.test("a short defeat ladder gets no closing whoosh", function()
    local g = bootstrap.new_game()
    g.STATE = g.STATES.SELECTING_HAND
    with_recorded_cues(function(cues)
        g:begin_blind_defeat(0)
        g:_update_blind_defeat(5)
        T.assert_eq(count_cue(cues, "cancel"), 2)
        T.assert_eq(count_cue(cues, "whoosh2"), 0)
    end)
end)

suite.test("the defeat hold gates play input and is abandoned on leaving the round", function()
    local g = bootstrap.new_game()
    g.STATE = g.STATES.SELECTING_HAND
    g:begin_blind_defeat(3)
    T.assert_true(g:scene_transition_active(), "input is suppressed while the blind rings out")

    g.STATE = g.STATES.MENU
    g:_update_blind_defeat(0.1)
    T.assert_eq(g._blind_defeat, nil, "leaving the round drops the pending state change")
    T.assert_eq(g.STATE, g.STATES.MENU, "and does not fire the cashout entry from the menu")
end)

suite.test("the room drifts when nothing is shaking", function()
    local g = bootstrap.new_game()
    g.jiggle = 0
    -- Sampled across a full period of the slower axis; a frozen room would never move.
    local moved = false
    for _ = 1, 60 do
        g:update_shake(0.05)
        local ox, oy = g:get_shake_offset()
        if ox ~= 0 or oy ~= 0 then moved = true end
    end
    T.assert_true(moved, "the reference's room drift runs regardless of jiggle")
end)

suite.test("the drift clock survives a shake decaying out", function()
    local g = bootstrap.new_game()
    g:shake(1)
    for _ = 1, 40 do g:update_shake(0.05) end
    T.assert_eq(g.jiggle, 0, "the shake has settled")
    local before = g._room_drift_t
    g:update_shake(0.05)
    T.assert_true(g._room_drift_t > before, "the drift clock is never reset")
end)

--- `UI_definitions.lua:2305,2308`: the base game exposes a 0-100 screenshake slider and a
--- reduced-motion toggle. Neither existed here, so a player who needs the board to hold
--- still had no way to ask for it.
suite.test("screenshake scales with its setting and reduced motion stills the board", function()
    local g = bootstrap.new_game()

    --- Peak travel from one shake. Sampled across frames rather than read on a single one:
    --- the offset is a sine, so any given frame can legitimately sit at zero.
    local function peak_travel(pct, reduced)
        g.SETTINGS.SCREENSHAKE = pct
        g.SETTINGS.REDUCED_MOTION = reduced
        g.jiggle, g._jiggle_t, g._room_drift_t = 0, 0, 0
        g:shake(3)
        local peak = 0
        for _ = 1, 12 do
            g:update_shake(0.05)
            local ox, oy = g:get_shake_offset()
            peak = math.max(peak, math.abs(ox), math.abs(oy))
        end
        return peak
    end

    local full = peak_travel(100, false)
    T.assert_true(full > 1, "a shake moves the board at 100%")
    T.assert_true(peak_travel(50, false) < full, "halving the setting shakes less")
    -- At zero only the idle drift remains, which is barely a pixel and is not a shake.
    T.assert_true(peak_travel(0, false) <= 1, "no shake travel at 0%")
    T.assert_eq(peak_travel(100, true), 0, "reduced motion holds the board completely still")
end)

suite.test("the screenshake and motion settings persist", function()
    local g = bootstrap.new_game()
    g:set_screenshake_percent(40)
    g:set_reduced_motion(true)

    local snap = g:snapshot_settings()
    T.assert_eq(snap.SCREENSHAKE, 40)
    T.assert_eq(snap.REDUCED_MOTION, true)

    local restored = g:normalize_settings(snap)
    T.assert_eq(restored.SCREENSHAKE, 40)
    T.assert_eq(restored.REDUCED_MOTION, true)

    -- Out-of-range values clamp rather than propagating.
    T.assert_eq(g:normalize_settings({ SCREENSHAKE = 500 }).SCREENSHAKE, 100)
    T.assert_eq(g:normalize_settings({ SCREENSHAKE = -20 }).SCREENSHAKE, 0)
    T.assert_eq(g:normalize_settings({}).SCREENSHAKE, 100, "the default is full shake")
    T.assert_eq(g:normalize_settings({}).REDUCED_MOTION, false)
end)

suite.test("selecting a card lifts its target, not its draw position", function()
    local g = bootstrap.new_game()
    g.STATE = g.STATES.SELECTING_HAND
    local hand = Hand(g)
    g.hand = hand
    g.deck = Deck()
    g.deck.cards = {
        { rank = 2, suit = "Hearts" },
        { rank = 3, suit = "Clubs" },
    }
    hand:fill_from_deck()
    -- Deals arrive on a beat, so pump the draw queue until the fan is populated.
    for _ = 1, 60 do
        hand:update(0.1)
        if #hand.card_nodes >= 2 then break end
    end
    hand:layout(true)
    local node = hand.card_nodes[1]
    T.assert_true(node ~= nil, "the hand dealt")

    local resting_t = node.T.y
    local resting_draw = select(2, node:get_layout_draw_xy())

    hand:toggle_selection(node)
    T.assert_true(node.T.y < resting_t, "the lift goes into the spring target")
    -- VT has not been touched, so the card is still visually down here and will rise over
    -- the following frames instead of snapping. That easing is the whole point.
    T.assert_near(select(2, node:get_layout_draw_xy()), resting_draw, 1e-9)

    hand:toggle_selection(node)
    T.assert_near(node.T.y, resting_t, 1e-9, "deselecting retargets back down")
end)

local function hand_of(g, cards)
    -- Dealing pops from `deck.cards`, and that is the very table passed in, so the target
    -- count has to be taken before the deck is handed over.
    local want = #cards
    local hand = Hand(g)
    g.hand = hand
    g.deck = Deck()
    g.deck.cards = cards
    hand:fill_from_deck()
    for _ = 1, 120 do
        hand:update(0.1)
        if #hand.card_nodes >= want then break end
    end
    return hand
end

suite.test("a suit conversion ripples across the picked cards", function()
    local g = bootstrap.new_game()
    g.STATE = g.STATES.SELECTING_HAND
    local hand = hand_of(g, {
        { rank = 2, suit = "Hearts" },
        { rank = 3, suit = "Hearts" },
        { rank = 4, suit = "Hearts" },
    })
    local nodes = hand.card_nodes

    with_recorded_cues(function(cues)
        g:convert_suit_ripple(nodes, "Spades")
        -- Gameplay data changes at once; only the drawn face waits for each card's pinch.
        for _, node in ipairs(nodes) do
            T.assert_eq(node.card_data.suit, "Spades", "the logical suit is immediate")
        end
        T.assert_eq(count_cue(cues, "card1"), 0, "nothing has flipped on the first frame")

        -- Cards turn over one after another, not together.
        g:_update_card_ripple(0.16)
        T.assert_eq(count_cue(cues, "card1"), 1, "the ripple is staggered")
        g:_update_card_ripple(0.5)
        T.assert_eq(count_cue(cues, "card1"), 3, "every picked card turns over")

        local pitches = {}
        for _, c in ipairs(cues) do
            if c.cue == "card1" then pitches[#pitches + 1] = c.pitch end
        end
        T.assert_true(pitches[1] > pitches[3], "the ladder descends across the run")
    end)
    T.assert_eq(g._card_ripple, nil, "the ripple retires once it has run out")
end)

suite.test("an enhancement conversion applies outright and ripples over the top", function()
    local g = bootstrap.new_game()
    g.STATE = g.STATES.SELECTING_HAND
    local hand = hand_of(g, {
        { rank = 5, suit = "Clubs" },
        { rank = 6, suit = "Clubs" },
    })
    local nodes = hand.card_nodes

    g:convert_enhancement_ripple(nodes, "steel", 2)
    -- Set outright: Card:set_enhancement carries the Stone Card rank/suit logic, so deferring
    -- it would leave the hand readout describing cards that no longer exist.
    for _, node in ipairs(nodes) do
        T.assert_eq(node.card_data.enhancement, "steel")
    end
    T.assert_true(g._card_ripple ~= nil, "the flip and pop still run")
end)

suite.test("a conversion affects only as many cards as the tarot allows", function()
    local g = bootstrap.new_game()
    g.STATE = g.STATES.SELECTING_HAND
    local hand = hand_of(g, {
        { rank = 7, suit = "Diamonds" },
        { rank = 8, suit = "Diamonds" },
    })
    g:convert_enhancement_ripple(hand.card_nodes, "gold", 1)
    T.assert_eq(hand.card_nodes[1].card_data.enhancement, "gold")
    T.assert_eq(hand.card_nodes[2].card_data.enhancement, nil, "the second pick is untouched")
end)

suite.test("money, hands and discards bump when they change", function()
    local g = bootstrap.new_game()
    local ui = g.topUI or TopUI(g)
    G.real_dt = 1 / 60

    G.money, G.hands, G.discards = 4, 3, 2
    ui:update_fields(1 / 60)
    T.assert_eq(ui.field_juice.money, nil, "the first frame only records the baseline")

    G.money = 9
    ui:update_fields(1 / 60)
    T.assert_true(ui.field_juice.money ~= nil, "gaining money pops the readout")
    T.assert_eq(ui.field_juice.hands, nil, "an unchanged field stays still")

    -- The pop is finite: it settles rather than latching on.
    for _ = 1, 120 do ui:update_fields(1 / 60) end
    T.assert_eq(ui.field_juice.money, nil, "the pop settles")
end)

suite.test("a destroyed joker collapses instead of blinking out", function()
    local g = bootstrap.new_game()
    T.assert_true(g:add_joker_by_def("j_joker"))
    local node = g.jokers[1]

    g:remove_owned_joker_at(1, false, true)
    T.assert_eq(#g.jokers, 0, "it leaves run state at once")
    T.assert_true(node._card_lifecycle ~= nil, "the node plays out on screen")
    T.assert_eq(node:lifecycle_collapse(), 1, "at full size on the frame it starts")
    node:advance_lifecycle(0.2)
    T.assert_true(node:lifecycle_collapse() < 1, "and shrinks from there")

    g:_update_dissolving_nodes(Moveable.DISSOLVE_DURATION + 0.01)
    T.assert_eq(node._card_lifecycle, nil, "the ghost is unlinked once it has run out")
    T.assert_eq(g._dissolving_nodes, nil)
end)

suite.test("removing a joker without asking for a dissolve is instant", function()
    local g = bootstrap.new_game()
    T.assert_true(g:add_joker_by_def("j_joker"))
    local node = g.jokers[1]
    -- Dissolve is opt-in, so run teardown and load can drop a whole row without ghosts.
    -- Selling asks for it explicitly; see the sell test below.
    g:remove_owned_joker_at(1)
    T.assert_eq(node._card_lifecycle, nil)
    T.assert_eq(g._dissolving_nodes, nil)
end)

suite.test("a used consumable flies out before it comes apart", function()
    local g = bootstrap.new_game()
    g.STATE = g.STATES.SELECTING_HAND
    T.assert_true(g:add_consumable("tarot_hermit"))
    local node = g.consumable_nodes[1]
    T.assert_true(node ~= nil)

    local resting_x, resting_y = node.T.x, node.T.y
    T.assert_true(g:use_consumable(1))
    T.assert_eq(#g.consumables, 0, "the effect resolves on this frame")
    T.assert_true(node.T.x ~= resting_x or node.T.y ~= resting_y, "it is retargeted to centre")
    T.assert_eq(node._card_lifecycle, nil, "it does not start dissolving until it lands")

    -- Fly, then hold, then come apart.
    g:_update_consumable_flight(0.36)
    T.assert_eq(node._card_lifecycle, nil, "it holds once it arrives")
    g:_update_consumable_flight(0.21)
    T.assert_eq(g._consumable_flight, nil)
    T.assert_true(node._card_lifecycle ~= nil, "then it dissolves")
end)

--- Two Planets used inside one flight (a Celestial pack resolving both picks, or a fast
--- double tap) used to overwrite the single flight slot, and the node it was holding was never
--- handed to the dissolve list -- it stayed parked at screen centre for the rest of the run.
suite.test("a second consumable used mid-flight does not strand the first", function()
    local g = bootstrap.new_game()
    g.STATE = g.STATES.SELECTING_HAND
    T.assert_true(g:add_consumable("planet_pluto"))
    T.assert_true(g:add_consumable("planet_mercury"))
    local first = g.consumable_nodes[1]
    local second = g.consumable_nodes[2]

    T.assert_true(g:use_consumable(1))
    T.assert_eq(g._consumable_flight.node, first)
    T.assert_true(g:use_consumable(1))

    T.assert_eq(g._consumable_flight.node, second, "the newer card owns the flight")
    T.assert_true(first._card_lifecycle ~= nil, "and the older one is coming apart, not stuck")
end)

suite.test("a planet is held on screen for the whole level-up", function()
    local g = bootstrap.new_game()
    g.STATE = g.STATES.SELECTING_HAND
    T.assert_true(g:add_consumable("planet_pluto"))
    local node = g.consumable_nodes[1]
    T.assert_true(g:use_consumable(1))

    -- Parked clear of the readout panel it is playing against, not over it.
    T.assert_eq(node._draw_screen, "top")
    T.assert_true(node.T.y >= 108, "the card must not sit on top of the level-up it caused")

    -- The ladder rings three times over 2.3 s; a card that dissolved on the reference's
    -- default hold would be gone before the second beat, and two of the three juices would
    -- land on nothing.
    g:_update_consumable_flight(0.36)
    g:_update_consumable_flight(2.0)
    T.assert_true(g._consumable_flight ~= nil, "still up while the readout is climbing")
    T.assert_eq(node._card_lifecycle, nil)
    g:_update_consumable_flight(0.7)
    T.assert_eq(g._consumable_flight, nil, "and leaves as the readout blanks")
    T.assert_true(node._card_lifecycle ~= nil)
end)

suite.test("a conversion ripple waits for the consumable to arrive", function()
    local g = bootstrap.new_game()
    g.STATE = g.STATES.SELECTING_HAND
    local hand = hand_of(g, { { rank = 2, suit = "Hearts" } })

    -- With nothing in flight the ripple starts on its own beat.
    g:convert_suit_ripple(hand.card_nodes, "Spades")
    local without_lead = g._card_ripple.queue[1].at
    g._card_ripple = nil

    g._consumable_flight = { phase = "fly", t = 0 }
    g:convert_suit_ripple(hand.card_nodes, "Clubs")
    T.assert_true(g._card_ripple.queue[1].at > without_lead,
        "cards wait rather than turning over while the tarot is still in the air")
end)

suite.test("dissolve and materialise share one set of durations", function()
    local g = bootstrap.new_game()
    local hand = hand_of(g, { { rank = 4, suit = "Spades" } })
    local node = hand.card_nodes[1]

    node:begin_lifecycle("materialize")
    T.assert_eq(node._card_lifecycle.duration, Moveable.MATERIALIZE_DURATION)
    -- A card can be destroyed while it is still fading in, so a dissolve overrides it.
    node:begin_lifecycle("dissolve")
    T.assert_eq(node._card_lifecycle.duration, Moveable.DISSOLVE_DURATION)
    node:begin_lifecycle("materialize")
    T.assert_eq(node._card_lifecycle.kind, "dissolve", "an in-flight dissolve is left alone")

    T.assert_true(node:advance_lifecycle(Moveable.DISSOLVE_DURATION + 0.01))
    T.assert_eq(node:lifecycle_collapse(), 1, "an idle node is unscaled")
end)

suite.test("each cash-out row reveals its label as it lands", function()
    local g = bootstrap.new_game()
    g.STATE = g.STATES.ROUND_EVAL
    g._round_win_display_lines = {
        { "Blind reward", 5, "pending", slot = "blind" },
        { "Remaining Hands ($1 each)", 3, "pending" },
    }
    g._round_win_lines_revealed = 0

    g:_reveal_one_round_win_line()
    local first = g._round_win_row_dyna[1]
    T.assert_true(first ~= nil, "the row gets its own reveal state")
    T.assert_true(first.pop_start ~= nil, "and starts revealing on arrival")
    T.assert_eq(g._round_win_row_dyna[2], nil, "a row that has not landed is not animating")

    -- Letters land in sequence rather than all at once.
    T.assert_eq(DynaText.pop_scale(first, 1, first.pop_start), 0)
    T.assert_eq(DynaText.pop_scale(first, 1, first.pop_start + first.pop_rise), 1)
    T.assert_eq(DynaText.pop_scale(first, 5, first.pop_start + first.pop_rise), 0,
        "a later glyph is still waiting its turn")

    g:_reveal_one_round_win_line()
    T.assert_true(g._round_win_row_dyna[2] ~= nil, "the next row reveals when it lands")
end)

suite.test("a price tag bumps when its number changes", function()
    local state = DynaText.new({ bump_amount = 0.25 })
    local t = 100

    DynaText.update(state, "$5", t)
    T.assert_eq(state.bump_start, nil, "the opening value is not a change")

    DynaText.update(state, "$5", t + 1)
    T.assert_eq(state.bump_start, nil, "redrawing the same price is inert")

    DynaText.update(state, "$4", t + 2)
    T.assert_eq(state.bump_start, t + 2, "a discount knocks the tag")

    local _, _, peak = DynaText.letter_transform(state, 1, t + 2 + state.bump_duration * 0.5)
    T.assert_true(peak > 1, "the glyph swells")
    local _, _, settled = DynaText.letter_transform(state, 1, t + 2 + state.bump_duration + 0.01)
    T.assert_eq(settled, 1, "and settles back")
end)

suite.test("a playing card edition is applied exactly once", function()
    local g = bootstrap.new_game()
    local hand = hand_of(g, { { rank = 5, suit = "Hearts" } })
    local node = hand.card_nodes[1]
    node.card_data.modifier = { edition = "foil" }

    -- Foil is +50 chips. A base-5 card contributes 5, so one application is 55.
    local chips = select(1, hand:accumulate_card_score(0, 1, node))
    T.assert_eq(chips, 55, "the one-shot path applies it once")

    -- The animated sequencer skips it here and applies it itself afterwards, so that it lands
    -- after the card's own listeners. Asking for both would double the bonus.
    local deferred = select(1, hand:accumulate_card_score(0, 1, node, false))
    T.assert_eq(deferred, 5, "the deferred path leaves it out")
    T.assert_eq(hand:apply_playing_card_edition(deferred, 1, node.card_data), 55,
        "and applying it afterwards reaches the same total")
end)

--- Run one card all the way through the scoring sequencer and report how long the sequencer
--- held for it, in beats.
local function beats_for_card(card_data)
    local g = bootstrap.new_game()
    g.STATE = g.STATES.SELECTING_HAND
    local hand = hand_of(g, { card_data })
    local node = hand.card_nodes[1]
    hand:toggle_selection(node)
    hand:play_selected()

    local waits = {}
    local seq = hand._play_sequence
    T.assert_true(seq ~= nil, "the play sequence started")
    -- Pump until the card's trigger has been charged, recording each hold.
    for _ = 1, 400 do
        local before = hand._play_sequence and hand._play_sequence.trigger_wait or 0
        hand:update(1 / 60)
        local after = hand._play_sequence and hand._play_sequence.trigger_wait or 0
        if after > before then waits[#waits + 1] = after - before end
        if not hand._play_sequence then break end
    end
    return waits
end

suite.test("a card holds one beat per effect", function()
    -- Chips only: the base beat and nothing more.
    local plain = beats_for_card({ rank = 5, suit = "Hearts" })
    local plain_max = 0
    for _, w in ipairs(plain) do if w > plain_max then plain_max = w end end

    -- Steel adds mult on top of chips, so its pass is charged twice.
    local steel = beats_for_card({ rank = 5, suit = "Hearts", enhancement = "mult" })
    local steel_max = 0
    for _, w in ipairs(steel) do if w > steel_max then steel_max = w end end

    -- The reference's non-chip effect beat is 0.65*1.25. Both measurements are one frame
    -- short, since the hold is already ticking down by the time it is read back.
    T.assert_near(steel_max - plain_max, 0.8125, 1e-6,
        "the mult modifier buys exactly one more effect beat")
end)

suite.test("top-screen labels are cached and keep their formatting", function()
    local g = bootstrap.new_game()
    local ui = g.topUI or TopUI(g)

    local a = ui:cached_label("money", 12, "$")
    T.assert_eq(a, "$12")
    T.assert_true(rawequal(a, ui:cached_label("money", 12, "$")), "unchanged value is not reformatted")
    T.assert_eq(ui:cached_label("money", 13, "$"), "$13", "a change rebuilds")
    -- Separate keys must not collide.
    T.assert_eq(ui:cached_label("seed", "ABCD", "Seed "), "Seed ABCD")
    T.assert_eq(ui:cached_label("money", 13, "$"), "$13")

    -- The reward readout is one pip per dollar, not the number.
    T.assert_eq(ui:cached_reward_pips(3), "$$$$+")
    T.assert_eq(ui:cached_reward_pips(0), "$+")
end)

suite.test("selling a joker pops it and dissolves it gold", function()
    local g = bootstrap.new_game()
    T.assert_true(g:add_joker_by_def("j_joker"))
    local node = g.jokers[1]
    local money_before = g.money

    T.assert_true(g:sell_owned_joker(1))
    T.assert_eq(#g.jokers, 0)
    T.assert_true(g.money > money_before, "the sale paid out")
    -- Reference `card.lua:1590-1612`: juice_up, then start_dissolve in gold.
    T.assert_true(node._card_lifecycle ~= nil, "the sold joker plays out rather than vanishing")
    T.assert_true(node.juice ~= nil or node.juice_scale ~= nil, "and pops on the way")
end)

suite.test("anteing up pops the counter and is not silent", function()
    local g = bootstrap.new_game()
    local ui = g.topUI or TopUI(g)
    G.real_dt = 1 / 60
    G.ante, G.round = 1, 1
    ui:update_fields(1 / 60)

    with_recorded_cues(function(cues)
        G.ante = 2
        ui:update_fields(1 / 60)
        T.assert_true(ui.field_juice.ante ~= nil, "the ante readout pops")
        T.assert_eq(count_cue(cues, "generic1"), 1, "and the reference's cue plays")
    end)

    -- Going backwards (a restored run, say) must not fire the progress cue.
    with_recorded_cues(function(cues)
        G.ante = 1
        ui:update_fields(1 / 60)
        T.assert_eq(count_cue(cues, "generic1"), 0)
    end)

    -- Money still pops, and still without a cue of its own.
    with_recorded_cues(function(cues)
        G.money = (G.money or 0) + 5
        ui:update_fields(1 / 60)
        T.assert_true(ui.field_juice.money ~= nil)
        T.assert_eq(count_cue(cues, "generic1"), 0, "only progress counters ring")
    end)
end)

suite.test("the round counter pops silently on shop exit", function()
    local g = bootstrap.new_game()
    local ui = g.topUI or TopUI(g)
    G.real_dt = 1 / 60
    G.ante, G.round = 1, 1
    ui:update_fields(1 / 60)

    -- The base game plays nothing when the shop closes; its `ease_round` cue belongs to
    -- blind select, a moment this port's round counter never sees.
    with_recorded_cues(function(cues)
        G.round = 2
        ui:update_fields(1 / 60)
        T.assert_true(ui.field_juice.round ~= nil, "the round readout still pops")
        T.assert_eq(count_cue(cues, "generic1"), 0, "but no cue rings")
        T.assert_eq(count_cue(cues, "highlight2"), 0)
    end)
end)

suite.test("levelling a hand rings three beats, not one", function()
    local g = bootstrap.new_game()
    g.STATE = g.STATES.SELECTING_HAND
    with_recorded_cues(function(cues)
        g:begin_hand_levelup_flourish("Pair", 1, 10, 2, 2, 25, 4)
        g:_update_hand_levelup(0.4)
        T.assert_eq(count_cue(cues, "tarot1"), 0, "the readout populates before the first ring")
        g:_update_hand_levelup(0.2)
        T.assert_eq(count_cue(cues, "tarot1"), 1)
        g:_update_hand_levelup(0.5)
        T.assert_eq(count_cue(cues, "tarot1"), 1, "the rest are spaced out")
        g:_update_hand_levelup(0.5)
        T.assert_eq(count_cue(cues, "tarot1"), 2)
        g:_update_hand_levelup(1.0)
        T.assert_eq(count_cue(cues, "tarot1"), 3, "reference rings three")
        g:_update_hand_levelup(1.0)
    end)
    T.assert_eq(g._hand_levelup, nil, "and then retires")
end)

suite.test("a level-up walks the readout up one slot per beat", function()
    local g = bootstrap.new_game()
    g.STATE = g.STATES.SELECTING_HAND
    g:begin_hand_levelup_flourish("Pair", 1, 10, 2, 2, 25, 4)

    local hand, level = g._hand_levelup.hand, g:readout_hand_level()
    local chips, mult = g:readout_chips_mult()
    T.assert_eq(hand, "Pair", "the readout points at the hand being levelled")
    T.assert_eq(level, 1, "starting on the numbers it had before the Planet landed")
    T.assert_eq(chips, 10)
    T.assert_eq(mult, 2)

    -- Mult first, then chips, then the level (`common_events.lua:475-486`).
    g:_update_hand_levelup(0.5)
    chips, mult = g:readout_chips_mult()
    T.assert_eq(mult, 4, "mult goes first")
    T.assert_eq(chips, 10)
    T.assert_eq(g._hand_levelup.mult_delta, "+2", "under a plate carrying the gain")
    T.assert_true(g._hand_levelup.mult_cover > 0)
    T.assert_eq(g:readout_hand_level(), 1, "the level has not moved yet")

    g:_update_hand_levelup(0.9)
    chips = g:readout_chips_mult()
    T.assert_eq(chips, 25, "then chips")
    T.assert_eq(g._hand_levelup.chips_delta, "+15")
    T.assert_eq(g:readout_hand_level(), 1)

    g:_update_hand_levelup(0.9)
    T.assert_eq(g:readout_hand_level(), 2, "and the level lands last")

    g:_update_hand_levelup(0.7)
    T.assert_eq(g._hand_levelup, nil, "then the readout goes back to the selected hand")
    T.assert_eq(g:readout_hand_level(), nil)
end)

suite.test("using a Planet drives the readout off the hand it levels", function()
    local g = bootstrap.new_game()
    g.STATE = g.STATES.SELECTING_HAND
    local idx
    for i, name in ipairs(g.handlist) do
        if name == CONSUMABLE_DEFS.planet_pluto.hand then idx = i break end
    end
    T.assert_true(idx ~= nil)
    local before_level, before_chips, before_mult = g:get_hand_display_stats(idx)

    T.assert_true(g:add_consumable("planet_pluto"))
    T.assert_true(g:use_consumable(1))

    local f = g._hand_levelup
    T.assert_true(f ~= nil, "a Planet starts the flourish")
    T.assert_eq(f.hand, CONSUMABLE_DEFS.planet_pluto.hand)
    T.assert_eq(f.level, before_level, "showing the pre-upgrade numbers first")
    T.assert_eq(f.chips, before_chips)
    T.assert_eq(f.mult, before_mult)
    T.assert_eq(f.to_level, before_level + 1)
    T.assert_eq(f.to_chips, select(2, g:get_hand_display_stats(idx)))
end)

suite.test("a level-up is bracketed by the readout handover cues", function()
    local g = bootstrap.new_game()
    g.STATE = g.STATES.SELECTING_HAND
    with_recorded_cues(function(cues)
        -- `button` at 0.8 hands the readout over, 0.9 rides the level landing, 1.1 blanks it
        -- (`card.lua:1265`, `common_events.lua:486`, `card.lua:1267`).
        g:begin_hand_levelup_flourish("Pair", 1, 10, 2, 2, 25, 4)
        T.assert_eq(cues[1].cue, "button")
        T.assert_eq(cues[1].pitch, 0.8)
        g:_update_hand_levelup(2.4)
        T.assert_eq(count_cue(cues, "button"), 2, "the level lands under its own button")
        g:_update_hand_levelup(0.6)
        T.assert_eq(count_cue(cues, "button"), 3)
        T.assert_eq(cues[#cues].pitch, 1.1, "and the last one blanks the readout")
    end)
end)

suite.test("an Orbital tag shows its three levels instead of applying them silently", function()
    local g = bootstrap.new_game()
    g.STATE = g.STATES.SELECTING_HAND
    local idx = 5
    local before_level = g:get_hand_display_stats(idx)

    local tag = Tag("orbital")
    tag.orbital_hand_index = idx
    tag:apply()

    local f = g._hand_levelup
    T.assert_true(f ~= nil, "the strongest hand upgrade in the game is not the quietest")
    T.assert_eq(f.hand, g.handlist[idx])
    T.assert_eq(f.level, before_level)
    T.assert_eq(f.to_level, before_level + 3, "all three levels in one ladder")
end)

suite.test("Black Hole shows every hand levelling at once", function()
    local g = bootstrap.new_game()
    g.STATE = g.STATES.SELECTING_HAND
    -- No single number to climb, so the reference substitutes placeholders (`card.lua:1154`).
    g:apply_consumable_effect({ kind = "spectral", id = "spectral_black_hole" })
    local f = g._hand_levelup
    T.assert_true(f ~= nil)
    T.assert_eq(f.hand, "All Hands")
    T.assert_eq(f.level, nil, "the level slot starts blank")
    T.assert_eq(select(1, g:readout_chips_mult()), "...")
    g:_update_hand_levelup(2.3)
    T.assert_eq(f.mult_delta, "+")
    T.assert_eq(g:readout_hand_level(), "+1")
end)

suite.test("the drop zone under the finger lights up", function()
    local g = bootstrap.new_game()
    local DragZonesUI = require("drag_zones_ui")
    local zones = {
        top = DragZonesUI.make_zone("Use", true, { 1, 1, 1 }, "use", true),
        bottom = DragZonesUI.make_zone("Sell", true, { 1, 1, 1 }, "sell", true),
    }
    zones.top.rect = { x = 0, y = 0, w = 320, h = 64 }
    zones.bottom.rect = { x = 0, y = 176, w = 320, h = 64 }

    local alphas = {}
    local real_setColor = love.graphics.setColor
    love.graphics.setColor = function(c, ...)
        if type(c) == "table" and c[4] then alphas[#alphas + 1] = c[4] end
        return real_setColor(c, ...)
    end
    g._ui_press = { x = 10, y = 10, held = true }
    local ok = pcall(DragZonesUI.draw, g, zones)
    love.graphics.setColor = real_setColor
    T.assert_true(ok)

    local brightest = 0
    for _, a in ipairs(alphas) do if a > brightest then brightest = a end end
    T.assert_true(brightest > 0.55, "the hovered zone is drawn brighter than a resting one")
end)

suite.test("a zone that would refuse the drop does not light up", function()
    local g = bootstrap.new_game()
    local DragZonesUI = require("drag_zones_ui")
    -- Brightening a disabled zone would promise a drop that is going to be rejected.
    local zone = DragZonesUI.make_zone("Buy", false, { 1, 1, 1 }, "buy", true)
    zone.rect = { x = 0, y = 0, w = 320, h = 64 }
    local zones = { top = zone }

    local alphas = {}
    local real_setColor = love.graphics.setColor
    love.graphics.setColor = function(c, ...)
        if type(c) == "table" and c[4] then alphas[#alphas + 1] = c[4] end
        return real_setColor(c, ...)
    end
    g._ui_press = { x = 10, y = 10, held = true }
    pcall(DragZonesUI.draw, g, zones)
    love.graphics.setColor = real_setColor

    for _, a in ipairs(alphas) do
        T.assert_true(a <= 0.65, "a disabled zone stays dim under the finger")
    end
end)

--------------------------------------------------------------------------------
-- Cash out
--------------------------------------------------------------------------------

--- Cash out is the one screen that exists to be read rather than played, and the port ran it
--- at nearly double the reference's pace.
suite.test("cash-out rows land at the reference's cadence", function()
    -- `delay(0.2)` then the row's own `trigger = 'before', delay = 0.5`
    -- (`common_events.lua:953-957`).
    T.assert_near(Game.ROUND_WIN_LINE_DELAY, 0.2 + 0.5, 1e-9)
end)

--- The per-dollar ladder was already right; pin it so the row change above cannot drag it.
--- Reference: `0.18 - ((n > 20 and 0.13) or (n > 9 and 0.1) or 0)` (`common_events.lua:1041`).
suite.test("the per-dollar coin ladder tightens as the payout grows", function()
    local g = bootstrap.new_game(8080)

    local function interval_for(amount)
        g._round_win_display_lines = { { "Blind", amount } }
        g._round_win_lines_revealed = 0
        g._round_win_row_dyna = nil
        g:_reveal_one_round_win_line()
        local tick = g._round_win_row_tick
        g._round_win_row_tick = nil
        return tick and tick.interval
    end

    T.assert_near(interval_for(5), 0.18, 1e-9)
    T.assert_near(interval_for(15), 0.08, 1e-9)
    T.assert_near(interval_for(30), 0.05, 1e-9)
end)

--------------------------------------------------------------------------------
-- Gamepad focus
--------------------------------------------------------------------------------

--- The hand cursor has always popped the card it lands on. Every other focus row only rang a
--- cue, so on a screen with no cursor the player heard that focus moved but could not see
--- where it went.
suite.test("focus popping the node it lands on", function()
    local g = bootstrap.new_game(5150)

    local node = { juiced = nil }
    node.juice_up = function(self, scale, rot)
        self.juiced = { scale = scale, rot = rot }
    end

    g:announce_focus_move(node)
    T.assert_not_nil(node.juiced, "the focused node popped")
    -- Matched to the hand cursor's own values rather than a second set of magic numbers.
    T.assert_eq(node.juiced.scale, 0.05)
    T.assert_eq(node.juiced.rot, 0.03)
end)

--- Holding a direction steps every 200 ms; popping on each step would shake the whole row.
--- The cue is already damped for exactly this reason.
suite.test("a held direction does not pop what it passes over", function()
    local g = bootstrap.new_game(5150)

    local node = { juiced = nil }
    node.juice_up = function(self) self.juiced = true end

    g._dpad_repeating = true
    g:announce_focus_move(node)
    T.assert_eq(node.juiced, nil, "auto-repeat is silent and still")

    g._dpad_repeating = nil
    g:announce_focus_move(node)
    T.assert_true(node.juiced == true, "a fresh press still pops")
end)

--- A voucher or booster slot is a panel rect, not a node - focus there must not crash.
suite.test("focus on a target with no node is harmless", function()
    local g = bootstrap.new_game(5150)
    g:announce_focus_move(nil)
    g:announce_focus_move({})
end)

--------------------------------------------------------------------------------
-- Booster ambience
--------------------------------------------------------------------------------

--- The ambient fields have to be dense enough to read as an atmosphere and sparse enough to
--- leave the shared 96-particle pool room for a burst. `rate * lifetime` is the steady-state
--- population, so it is the number worth pinning.
suite.test("every pack's ambient field stays inside the particle budget", function()
    local BoosterPackUI = require("booster_pack_ui")
    local fields = BoosterPackUI.AMBIENT_FIELDS
    T.assert_not_nil(fields, "the fields are exposed for this test")

    local n = 0
    for pack, field in pairs(fields) do
        n = n + 1
        local population = field.rate * field.lifetime
        T.assert_true(population <= BoosterPackUI.AMBIENT_POPULATION_CAP,
            pack .. " holds " .. population .. " particles, over the budget")
        -- The floor is the point of the change: below about twenty the field reads as a few
        -- specks drifting past rather than as weather.
        T.assert_true(population >= 20,
            pack .. " only holds " .. population .. " particles, too sparse to read")
    end
    T.assert_eq(n, 5, "all five pack types have a field")
end)

--------------------------------------------------------------------------------
-- Materialise
--------------------------------------------------------------------------------

--- Node the burst maths can run against without standing a real Joker up. The lifecycle
--- methods are the real ones, so the durations under test are the shipped durations.
local function fake_node(x, y, w, h)
    local node = {
        VT = { x = x, y = y, w = w, h = h, scale = 1 },
        kind = "tarot",
    }
    node.begin_lifecycle = Moveable.begin_lifecycle
    node.advance_lifecycle = Moveable.advance_lifecycle
    return node
end

--- Collect the specs handed to `Particles.emit`, copied because the emitter reuses one table.
local function with_recorded_shards(fn)
    local original = Particles.emit
    local shards = {}
    Particles.emit = function(spec)
        shards[#shards + 1] = {
            x = spec.x, y = spec.y, vx = spec.vx, vy = spec.vy,
            lifetime = spec.lifetime, colour = spec.colour,
        }
        return original(spec)
    end
    local ok, err = pcall(fn, shards)
    Particles.emit = original
    if not ok then error(err, 0) end
end

suite.test("a materialising node's shards converge on it", function()
    local g = bootstrap.new_game()
    g.STAGE = g.STAGES.RUN
    g.STATE = g.STATES.SHOP

    with_recorded_shards(function(shards)
        g:begin_materialize_burst(fake_node(100, 60, 40, 60))
        T.assert_true(#shards > 0, "the burst emitted something")

        -- Every shard has to be heading at the node's centre, which is the whole difference
        -- between this and the dissolve burst it shares a primitive with.
        local cx, cy = 100 + 20, 60 + 30
        for _, p in ipairs(shards) do
            local to_centre_x, to_centre_y = cx - p.x, cy - p.y
            -- Positive dot product between "where it is going" and "where the centre is".
            T.assert_true(p.vx * to_centre_x + p.vy * to_centre_y > 0,
                "shard travels toward the centre, not away from it")
            -- And it must arrive rather than sail past: straight-line convergence.
            T.assert_near(p.x + p.vx * p.lifetime, cx, 0.001)
            T.assert_near(p.y + p.vy * p.lifetime, cy, 0.001)
        end
    end)
end)

--- Run setup deals starting consumables and a restore rebuilds every owned node. Bursting on
--- either would flash the whole board on entry.
suite.test("creation is silent during a restore and outside a run", function()
    local g = bootstrap.new_game()
    g.STAGE = g.STAGES.RUN
    g.STATE = g.STATES.SHOP

    with_recorded_shards(function(shards)
        g._restoring_run_snapshot = true
        g:begin_materialize_burst(fake_node(0, 0, 40, 60))
        T.assert_eq(#shards, 0, "a restore does not burst")

        g._restoring_run_snapshot = nil
        g.STATE = g.STATES.BLIND_SELECT
        g:begin_materialize_burst(fake_node(0, 0, 40, 60))
        T.assert_eq(#shards, 0, "a state the player cannot create in does not burst")

        g.STATE = g.STATES.SELECTING_HAND
        g:begin_materialize_burst(fake_node(0, 0, 40, 60))
        T.assert_true(#shards > 0, "creating under the player's eyes does burst")
    end)
end)

--- The tint is what says which set turned up before the art is legible.
suite.test("the materialise tint follows the set", function()
    local g = bootstrap.new_game()
    local function tint(kind)
        return g:materialize_colour_for({ kind = kind })
    end
    T.assert_true(tint("tarot") ~= tint("planet"), "tarot and planet differ")
    T.assert_true(tint("spectral") ~= tint("tarot"), "spectral and tarot differ")
    -- Anything with no set of its own still gets a colour rather than nil.
    T.assert_not_nil(tint(nil), "an unset node falls back rather than crashing")
end)

--- A fade-in must not unlink the node the way a dissolve does - it is joining the run.
suite.test("a finished materialise leaves its node in the run", function()
    local g = bootstrap.new_game()
    g.STAGE = g.STAGES.RUN
    g.STATE = g.STATES.SHOP

    local node = fake_node(0, 0, 40, 60)
    local removed = false
    g.remove = function(_, n) if n == node then removed = true end end

    g:begin_materializing_node(node)
    T.assert_not_nil(node._card_lifecycle, "the tween started")

    for _ = 1, 60 do g:_update_materializing_nodes(0.05) end
    T.assert_true(removed == false, "the node was not unlinked")
    T.assert_eq(g._materializing_nodes, nil, "the list emptied out")
end)

return suite
