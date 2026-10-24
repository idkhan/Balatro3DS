-- Example Jokers: copy this folder into the game's mods folder to try it (see MODDING.md).

-- Every card is its own image in assets/1x, like the game's own art: Jokers are 70x94,
-- consumables a 64x128 file with the card in the top 64x96, vouchers 72x95. Name the .png;
-- the 3DS loads the .t3x beside it, so ship both (the .png is for desktop testing).
-- Make each .t3x with: tex3ds -f rgba plus_four.png -o plus_four.t3x
--
-- Negative art: the 3DS can't recolour a card the way the PC game's shader does, so a Negative
-- copy draws `negative_sprite`. Without one, it keeps its normal art.

-- Flat Mult when the hand scores.
SMODS.Joker {
    key = "plus_four",
    loc_txt = {
        name = "Plus Four",
        text = { "{C:mult}+#1#{} Mult" },
    },
    config = { extra = { mult = 4 } },
    rarity = 1,
    cost = 3,
    sprite = "plus_four.png",
    negative_sprite = "plus_four_negative.png",
    blueprint_compat = true,
    loc_vars = function(self, info_queue, card)
        return { vars = { card.ability.extra.mult } }
    end,
    calculate = function(self, card, context)
        if context.joker_main then
            return { mult = card.ability.extra.mult }
        end
    end,
}

-- Chips for every scored 7.
SMODS.Joker {
    key = "lucky_sevens",
    loc_txt = {
        name = "Lucky Sevens",
        text = { "Each played {C:attention}7{}", "gives {C:chips}+#1#{} Chips", "when scored" },
    },
    config = { extra = { chips = 30 } },
    rarity = 1,
    cost = 4,
    sprite = "lucky_sevens.png",
    negative_sprite = "lucky_sevens_negative.png",
    blueprint_compat = true,
    loc_vars = function(self, info_queue, card)
        return { vars = { card.ability.extra.chips } }
    end,
    calculate = function(self, card, context)
        if context.individual and context.cardarea == G.play and context.other_card:get_id() == 7 then
            return { chips = card.ability.extra.chips }
        end
    end,
}

-- Grows every time a Flush is played, and pays out at the end of the round.
SMODS.Joker {
    key = "grower",
    loc_txt = {
        name = "Grower",
        text = {
            "Gains {C:money}$#2#{} of payout",
            "when a {C:attention}Flush{} is played",
            "{C:inactive}(Currently {C:money}$#1#{C:inactive})",
        },
    },
    config = { extra = { money = 0, gain = 1 } },
    rarity = 2,
    cost = 6,
    sprite = "grower.png",
    negative_sprite = "grower_negative.png",
    loc_vars = function(self, info_queue, card)
        return { vars = { card.ability.extra.money, card.ability.extra.gain } }
    end,
    calculate = function(self, card, context)
        if context.before and next(context.poker_hands["Flush"]) and not context.blueprint then
            card.ability.extra.money = card.ability.extra.money + card.ability.extra.gain
            return { message = localize("k_upgrade_ex") }
        end
    end,
    calc_dollar_bonus = function(self, card)
        if card.ability.extra.money > 0 then return card.ability.extra.money end
    end,
}

--------------------------------------------------------------------------------
-- Consumables and Vouchers
--------------------------------------------------------------------------------

-- A Tarot that needs no code: `max_highlighted` is how many cards it targets and `mod_conv`
-- is the enhancement it applies.
SMODS.Consumable {
    set = "Tarot",
    key = "gild",
    loc_txt = {
        name = "Gild",
        text = { "Enhances up to {C:attention}#1#{}", "selected cards into", "{C:money}Gold Cards{}" },
    },
    config = { max_highlighted = 2, mod_conv = "m_gold" },
    sprite = "gild.png",
    negative_sprite = "gild_negative.png",
    loc_vars = function(self, info_queue, card)
        return { vars = { card.ability.max_highlighted } }
    end,
}

-- A Spectral with code: `can_use` decides when it lights up, `use` does the work.
SMODS.Consumable {
    set = "Spectral",
    key = "windfall",
    loc_txt = {
        name = "Windfall",
        text = { "Gain {C:money}$#1#{}", "{C:inactive}(Only while under $#2#)" },
    },
    config = { extra = { dollars = 15, cap = 50 } },
    cost = 4,
    sprite = "windfall.png",
    loc_vars = function(self, info_queue, card)
        return { vars = { card.ability.extra.dollars, card.ability.extra.cap } }
    end,
    can_use = function(self, card)
        return G.money < card.ability.extra.cap
    end,
    use = function(self, card, area, copier)
        ease_dollars(card.ability.extra.dollars)
    end,
}

-- Vouchers. `h_size`, `d_size`, `hands`, `joker_slots` and `consumable_slots` in `config` apply
-- for as long as the voucher is owned, with no code. `requires` makes the second a tier-two
-- upgrade of the first, and `redeem` runs once when it is bought.
SMODS.Voucher {
    key = "bigger_hand",
    loc_txt = {
        name = "Bigger Hand",
        text = { "{C:attention}+#1#{} hand size" },
    },
    config = { h_size = 1 },
    sprite = "bigger_hand.png",
    loc_vars = function(self, info_queue, card)
        return { vars = { card.ability.h_size } }
    end,
}

SMODS.Voucher {
    key = "biggest_hand",
    loc_txt = {
        name = "Biggest Hand",
        text = { "{C:attention}+#1#{} hand size again,", "and gain {C:money}$#2#{} now" },
    },
    config = { h_size = 1, extra = { dollars = 5 } },
    cost = 12,
    requires = { "bigger_hand" },
    sprite = "biggest_hand.png",
    loc_vars = function(self, info_queue, card)
        return { vars = { card.ability.h_size, card.ability.extra.dollars } }
    end,
    redeem = function(self, card)
        ease_dollars(card.ability.extra.dollars)
    end,
}

--------------------------------------------------------------------------------
-- Decks
--------------------------------------------------------------------------------

-- A deck. `config` takes vanilla Balatro's Back keys (hand_size, discards, dollars, joker_slot,
-- consumables, vouchers, ...) and needs no code; `calculate` hears the same contexts a Joker
-- does, after the Jokers. `sprite` is the card back every playing card wears, 72x95.
-- `back.effect.config` is the run's own copy of `config`, saved with the run.
SMODS.Back {
    key = "scholar",
    loc_txt = {
        name = "Scholar's Deck",
        text = { "{C:attention}+#1#{} hand size", "{C:mult}+#2#{} Mult when you play", "a {C:attention}High Card{}" },
    },
    config = { hand_size = 1, extra = { mult = 10 } },
    sprite = "scholar_back.png",
    loc_vars = function(self, info_queue, back)
        return { vars = { back.effect.config.hand_size, back.effect.config.extra.mult } }
    end,
    calculate = function(self, back, context)
        if context.joker_main and context.scoring_name == "High Card" then
            return { mult = back.effect.config.extra.mult }
        end
    end,
}

--------------------------------------------------------------------------------
-- Editions
--------------------------------------------------------------------------------

-- An edition. `config` takes Steamodded's edition numbers (chips, mult, x_mult, p_dollars) and
-- needs no code. `in_shop` with a `weight` lets the shop and packs roll it, on Steamodded's
-- scale (Foil is 20). The 3DS can't run a shader, so `fx` describes the look instead: a `tint`
-- over the art, a `glow` on top, and the glow's `animation`.
SMODS.Edition {
    key = "gilded",
    loc_txt = {
        name = "Gilded",
        text = { "Earn {C:money}$#1#{} when", "this card scores" },
    },
    config = { p_dollars = 2 },
    extra_cost = 3,
    in_shop = true,
    weight = 10,
    sound = { sound = "gold_seal", per = 1.2, vol = 0.4 },
    fx = { tint = { 1.0, 0.92, 0.7 }, glow = { 1.0, 0.85, 0.35, 0.45 }, animation = "sweep" },
    loc_vars = function(self, info_queue, card)
        return { vars = { self.config.p_dollars } }
    end,
}

--------------------------------------------------------------------------------
-- Card faces
--------------------------------------------------------------------------------

-- A set of Jack, Queen and King art for Spades, offered in Options > Art beside the built-in
-- collab sets. `sprite` is one 216x95 strip: three 72x95 cells, J, Q and K left to right,
-- transparent around the art so the card front shows through. `hc_sprite` is the version used
-- when the player ticks High Contrast for the suit.
SMODS.DeckSkin {
    key = "royal_court",
    suit = "Spades",
    loc_txt = { name = "Royal Court" },
    sprite = "royal_court_spades.png",
    hc_sprite = "royal_court_spades_hc.png",
}
