-- Challenge definitions derived from reference/Balatro/challenges.lua:58-667.
-- This is intentionally data only: game.lua owns applying a definition to a run.

local function ids(...)
    local out = {}
    for i = 1, select("#", ...) do out[select(i, ...)] = true end
    return out
end

local function start_joker(id, opts)
    opts = opts or {}
    opts.id = id
    return opts
end

local function challenge(id, name, spec)
    spec.id, spec.name = id, name
    spec.deck = spec.deck or { preset = "standard" }
    spec.rules = spec.rules or {}
    spec.banned = spec.banned or {}
    return spec
end

-- `preset` is expanded by Game:apply_challenge_definition.  Keeping repeated
-- 52-card patterns declarative avoids allocating 52 tables for every challenge.
CHALLENGE_DEFS = {
    challenge("c_omelette_1", "The Omelette", {
        custom_rules = ids("no_reward", "no_extra_hand_money", "no_interest"),
        start_jokers = { start_joker("j_egg"), start_joker("j_egg"), start_joker("j_egg"), start_joker("j_egg"), start_joker("j_egg") },
        banned = { cards = ids("v_seed_money", "v_money_tree", "j_to_the_moon", "j_rocket", "j_golden", "j_satellite") },
    }),
    challenge("c_city_1", "15 Minute City", {
        start_jokers = { start_joker("j_ride_the_bus", { eternal = true }), start_joker("j_shortcut", { eternal = true }) },
        deck = { preset = "city" },
    }),
    challenge("c_rich_1", "Rich get Richer", {
        rules = { dollars = 100 }, custom_rules = ids("chips_dollar_cap"),
        start_vouchers = { "v_seed_money", "v_money_tree" },
    }),
    challenge("c_knife_1", "On a Knife's Edge", {
        start_jokers = { start_joker("j_ceremonial", { eternal = true, pinned = true }) },
    }),
    challenge("c_xray_1", "X-ray Vision", { custom_rules = { flipped_cards = 4 } }),
    challenge("c_mad_world_1", "Mad World", {
        custom_rules = ids("no_extra_hand_money", "no_interest"),
        start_jokers = { start_joker("j_pareidolia", { edition = "negative", eternal = true }), start_joker("j_business", { eternal = true }) },
        deck = { preset = "numbered" }, banned = { blinds = ids("bl_plant") },
    }),
    challenge("c_luxury_1", "Luxury Tax", {
        rules = { hand_size = 10 }, custom_rules = { minus_hand_size_per_X_dollar = 5 },
    }),
    challenge("c_non_perishable_1", "Non-Perishable", {
        custom_rules = ids("all_eternal"),
        banned = { cards = ids("j_gros_michel", "j_ice_cream", "j_cavendish", "j_turtle_bean", "j_ramen", "j_diet_cola", "j_selzer", "j_popcorn", "j_mr_bones", "j_invisible", "j_luchador"), blinds = ids("bl_final_leaf") },
    }),
    challenge("c_medusa_1", "Medusa", {
        start_jokers = { start_joker("j_marble", { eternal = true }) }, deck = { preset = "face_stone" },
    }),
    challenge("c_double_nothing_1", "Double or Nothing", {
        custom_rules = ids("debuff_played_cards"), deck = { preset = "gold_seal" },
    }),
    challenge("c_typecast_1", "Typecast", {
        custom_rules = { set_eternal_ante = 4, set_joker_slots_ante = 4 }, banned = { blinds = ids("bl_final_leaf") },
    }),
    challenge("c_inflation_1", "Inflation", {
        custom_rules = ids("inflation"), start_jokers = { start_joker("j_credit_card") }, banned = { cards = ids("v_clearance_sale", "v_liquidation") },
    }),
    challenge("c_bram_poker_1", "Bram Poker", {
        custom_rules = ids("no_shop_jokers"), start_jokers = { start_joker("j_vampire", { eternal = true }) },
        start_consumables = { "tarot_empress", "tarot_emperor" }, start_vouchers = { "v_magic_trick", "v_illusion" },
    }),
    challenge("c_fragile_1", "Fragile", {
        start_jokers = { start_joker("j_oops", { eternal = true, edition = "negative" }), start_joker("j_oops", { eternal = true, edition = "negative" }) },
        deck = { preset = "glass" },
        banned = { cards = ids("tarot_magician", "tarot_empress", "tarot_hierophant", "tarot_chariot", "tarot_devil", "tarot_tower", "tarot_lovers", "spectral_incantation", "spectral_grim", "spectral_familiar", "j_marble", "j_vampire", "j_midas_mask", "j_certificate", "v_magic_trick", "v_illusion"), packs = ids("p_standard_normal_1", "p_standard_normal_2", "p_standard_normal_3", "p_standard_normal_4", "p_standard_jumbo_1", "p_standard_jumbo_2", "p_standard_mega_1", "p_standard_mega_2"), tags = ids("tag_standard") },
    }),
    challenge("c_monolith_1", "Monolith", {
        start_jokers = { start_joker("j_obelisk", { eternal = true }), start_joker("j_marble", { eternal = true, edition = "negative" }) },
    }),
    challenge("c_blast_off_1", "Blast Off", {
        rules = { hands = 2, discards = 2, joker_slots = 4 },
        start_jokers = { start_joker("j_constellation", { eternal = true }), start_joker("j_rocket", { eternal = true }) },
        start_vouchers = { "v_planet_merchant", "v_planet_tycoon" }, banned = { cards = ids("v_grabber", "v_nacho_tong", "j_burglar") },
    }),
    challenge("c_five_card_1", "Five-Card Draw", {
        rules = { hand_size = 5, joker_slots = 7, discards = 6 }, start_jokers = { start_joker("j_card_sharp"), start_joker("j_joker") },
        banned = { cards = ids("j_juggler", "j_troubadour", "j_turtle_bean") },
    }),
    challenge("c_golden_needle_1", "Golden Needle", {
        rules = { hands = 1, discards = 6, dollars = 10 }, custom_rules = { discard_cost = 1 }, start_jokers = { start_joker("j_credit_card") },
        banned = { cards = ids("v_grabber", "v_nacho_tong", "j_burglar") },
    }),
    challenge("c_cruelty_1", "Cruelty", {
        rules = { joker_slots = 3 }, custom_rules = { no_reward_specific = { Small = true, Big = true } },
    }),
    challenge("c_jokerless_1", "Jokerless", {
        rules = { joker_slots = 0 }, custom_rules = ids("no_shop_jokers"),
        banned = { cards = ids("tarot_judgement", "spectral_wraith", "spectral_soul", "v_antimatter"), packs = ids("p_buffoon_normal_1", "p_buffoon_normal_2", "p_buffoon_jumbo_1", "p_buffoon_mega_1"), tags = ids("tag_rare", "tag_uncommon", "tag_holo", "tag_polychrome", "tag_negative", "tag_foil", "tag_buffoon", "tag_top_up"), blinds = ids("bl_final_acorn", "bl_final_heart", "bl_final_leaf") },
    }),
}

CHALLENGE_DEFS_BY_ID = {}
for _, def in ipairs(CHALLENGE_DEFS) do CHALLENGE_DEFS_BY_ID[def.id] = def end

return CHALLENGE_DEFS
