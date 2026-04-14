-- Joker Catalog 

---@type table<string, table>
JOKER_DEFS = {
    -- j_joker
    j_joker = {
        id = "j_joker",
        name = "Joker",
        order = 1,
        unlocked = true,
        start_alerted = true,
        discovered = true,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 1,
        cost = 2,

        sell_cost = 1,
        effect = "Mult",
        config = { mult = 4 },
        pos = {
            atlas = "Joker1_p1",
            index = 0
        }
    },

    -- j_greedy_joker
    j_greedy_joker = {
        id = "j_greedy_joker",
        name = "Greedy Joker",
        order = 2,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 1,
        cost = 5,

        sell_cost = 2,
        effect = "Suit Mult",
        config = { extra = { s_mult = 3, suit = "Diamonds" } },
        pos = {
            atlas = "Joker1_p1",
            index = 16
        }
    },

    -- j_lusty_joker
    j_lusty_joker = {
        id = "j_lusty_joker",
        name = "Lusty Joker",
        order = 3,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 1,
        cost = 5,

        sell_cost = 2,
        effect = "Suit Mult",
        config = { extra = { s_mult = 3, suit = "Hearts" } },
        pos = {
            atlas = "Joker1_p1",
            index = 17
        }
    },

    -- j_wrathful_joker
    j_wrathful_joker = {
        id = "j_wrathful_joker",
        name = "Wrathful Joker",
        order = 4,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 1,
        cost = 5,

        sell_cost = 2,
        effect = "Suit Mult",
        config = { extra = { s_mult = 3, suit = "Spades" } },
        pos = {
            atlas = "Joker1_p1",
            index = 18
        }
    },

    -- j_gluttenous_joker
    j_gluttenous_joker = {
        id = "j_gluttenous_joker",
        name = "Gluttonous Joker",
        order = 5,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 1,
        cost = 5,

        sell_cost = 2,
        effect = "Suit Mult",
        config = { extra = { s_mult = 3, suit = "Clubs" } },
        pos = {
            atlas = "Joker1_p1",
            index = 19
        }
    },

    -- j_jolly
    j_jolly = {
        id = "j_jolly",
        name = "Jolly Joker",
        order = 6,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 1,
        cost = 3,

        sell_cost = 1,
        effect = "Type Mult",
        config = { t_mult = 8, type = "Pair" },
        pos = {
            atlas = "Joker1_p1",
            index = 2
        }
    },

    -- j_zany
    j_zany = {
        id = "j_zany",
        name = "Zany Joker",
        order = 7,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 1,
        cost = 4,

        sell_cost = 2,
        effect = "Type Mult",
        config = { t_mult = 12, type = "Three of a Kind" },
        pos = {
            atlas = "Joker1_p1",
            index = 3
        }
    },

    -- j_mad
    j_mad = {
        id = "j_mad",
        name = "Mad Joker",
        order = 8,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 1,
        cost = 4,

        sell_cost = 2,
        effect = "Type Mult",
        config = { t_mult = 10, type = "Two Pair" },
        pos = {
            atlas = "Joker1_p1",
            index = 4
        }
    },

    -- j_crazy
    j_crazy = {
        id = "j_crazy",
        name = "Crazy Joker",
        order = 9,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 1,
        cost = 4,

        sell_cost = 2,
        effect = "Type Mult",
        config = { t_mult = 12, type = "Straight" },
        pos = {
            atlas = "Joker1_p1",
            index = 5
        }
    },

    -- j_droll
    j_droll = {
        id = "j_droll",
        name = "Droll Joker",
        order = 10,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 1,
        cost = 4,

        sell_cost = 2,
        effect = "Type Mult",
        config = { t_mult = 10, type = "Flush" },
        pos = {
            atlas = "Joker1_p1",
            index = 6
        }
    },

    j_sly = {
        id = "j_sly",
        name = "Sly Joker",
        order = 11,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 1,
        cost = 3,

        sell_cost = 1,
        config = { t_chips = 50, type = "Pair" },
        pos = {
            atlas = "Joker2_p3",
            index = 2
        }
    },

    j_wily = {
        id = "j_wily",
        name = "Wily Joker",
        order = 12,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 1,
        cost = 4,

        sell_cost = 2,
        config = { t_chips = 100, type = "Three of a Kind" },
        pos = {
            atlas = "Joker2_p3",
            index = 3
        }
    },

    j_clever = {
        id = "j_clever",
        name = "Clever Joker",
        order = 13,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 1,
        cost = 4,

        sell_cost = 2,
        config = { t_chips = 80, type = "Two Pair" },
        pos = {
            atlas = "Joker2_p3",
            index = 4
        }
    },

    j_devious = {
        id = "j_devious",
        name = "Devious Joker",
        order = 14,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 1,
        cost = 4,

        sell_cost = 2,
        config = { t_chips = 100, type = "Straight" },
        pos = {
            atlas = "Joker2_p3",
            index = 5
        }
    },

    j_crafty = {
        id = "j_crafty",
        name = "Crafty Joker",
        order = 15,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 1,
        cost = 4,

        sell_cost = 2,
        config = { t_chips = 80, type = "Flush" },
        pos = {
            atlas = "Joker2_p3",
            index = 6
        }
    },

    j_half = {
        id = "j_half",
        name = "Half Joker",
        order = 16,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 1,
        cost = 5,

        sell_cost = 2,
        effect = "Hand Size Mult",
        config = { extra = { mult = 20, size = 3 } },
        pos = {
            atlas = "Joker1_p1",
            index = 7
        }
    },

    j_stencil = {
        id = "j_stencil",
        name = "Joker Stencil",
        order = 17,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 2,
        cost = 8,

        sell_cost = 4,
        effect = "Stencil Mult",
        config = {},
        pos = {
            atlas = "Joker1_p3",
            index = 4
        }
    },

    j_four_fingers = {
        id = "j_four_fingers",
        name = "Four Fingers",
        order = 18,
        unlocked = true,
        discovered = false,
        blueprint_compat = false,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 2,
        cost = 7,

        sell_cost = 3,
        config = {},
        pos = {
            atlas = "Joker1_p3",
            index = 18
        }
    },

    j_mime = {
        id = "j_mime",
        name = "Mime",
        order = 19,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 2,
        cost = 5,

        sell_cost = 2,
        effect = "Hand card double",
        config = { extra = 1 },
        pos = {
            atlas = "Joker1_p1",
            index = 14
        }
    },

    j_credit_card = {
        id = "j_credit_card",
        name = "Credit Card",
        order = 20,
        unlocked = true,
        discovered = false,
        blueprint_compat = false,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 1,
        cost = 1,

        sell_cost = 1,
        effect = "Credit",
        config = { extra = 20 },
        pos = {
            atlas = "Joker1_p1",
            index = 15
        }
    },

    j_ceremonial = {
        id = "j_ceremonial",
        name = "Ceremonial Dagger",
        order = 21,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = false,
        eternal_compat = true,
        rarity = 2,
        cost = 6,

        sell_cost = 3,
        effect = "Destroy Joker",
        config = { mult = 0 },
        pos = {
            atlas = "Joker1_p3",
            index = 7
        }
    },

    j_banner = {
        id = "j_banner",
        name = "Banner",
        order = 22,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 1,
        cost = 5,

        sell_cost = 2,
        effect = "Discard Chips",
        config = { extra = 30 },
        pos = {
            atlas = "Joker1_p1",
            index = 21
        }
    },

    j_mystic_summit = {
        id = "j_mystic_summit",
        name = "Mystic Summit",
        order = 23,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 1,
        cost = 5,

        sell_cost = 2,
        effect = "No Discard Mult",
        config = { extra = { mult = 15, d_remaining = 0 } },
        pos = {
            atlas = "Joker1_p1",
            index = 22
        }
    },

    j_marble = {
        id = "j_marble",
        name = "Marble Joker",
        order = 24,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 2,
        cost = 6,

        sell_cost = 3,
        effect = "Stone card hands",
        config = { extra = 1 },
        pos = {
            atlas = "Joker1_p1",
            index = 23
        }
    },

    j_loyalty_card = {
        id = "j_loyalty_card",
        name = "Loyalty Card",
        order = 25,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 2,
        cost = 5,

        sell_cost = 2,
        effect = "1 in 6 mult",
        config = { extra = { Xmult = 4, every = 6, remaining = 6 } },
        pos = {
            atlas = "Joker1_p2",
            index = 0
        }
    },

    j_8_ball = {
        id = "j_8_ball",
        name = "8 Ball",
        order = 26,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 1,
        cost = 5,

        sell_cost = 2,
        effect = "Spawn Tarot",
        config = { extra = 4 },
        pos = {
            atlas = "Joker1_p3",
            index = 2
        }
    },

    j_misprint = {
        id = "j_misprint",
        name = "Misprint",
        order = 27,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 1,
        cost = 4,

        sell_cost = 2,
        effect = "Random Mult",
        config = { extra = { max = 23, min = 0 } },
        pos = {
            atlas = "Joker1_p2",
            index = 2
        }
    },

    j_dusk = {
        id = "j_dusk",
        name = "Dusk",
        order = 28,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 2,
        cost = 5,

        sell_cost = 2,
        config = { extra = 1 },
        pos = {
            atlas = "Joker1_p4",
            index = 2
        }
    },

    j_raised_fist = {
        id = "j_raised_fist",
        name = "Raised Fist",
        order = 29,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 1,
        cost = 5,

        sell_cost = 2,
        effect = "Socialized Mult",
        config = {},
        pos = {
            atlas = "Joker1_p2",
            index = 4
        }
    },

    j_chaos = {
        id = "j_chaos",
        name = "Chaos the Clown",
        order = 30,
        unlocked = true,
        discovered = false,
        blueprint_compat = false,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 1,
        cost = 4,

        sell_cost = 2,
        effect = "Bonus Rerolls",
        config = { extra = 1 },
        pos = {
            atlas = "Joker1_p1",
            index = 1
        }
    },

    j_fibonacci = {
        id = "j_fibonacci",
        name = "Fibonacci",
        order = 31,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 2,
        cost = 8,

        sell_cost = 4,
        effect = "Card Mult",
        config = { extra = 8 },
        pos = {
            atlas = "Joker1_p3",
            index = 3
        }
    },

    j_steel_joker = {
        id = "j_steel_joker",
        name = "Steel Joker",
        order = 32,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 2,
        cost = 7,

        sell_cost = 3,
        effect = "Steel Card Buff",
        config = { extra = 0.2 },
        pos = {
            atlas = "Joker1_p2",
            index = 3
        }
    },

    j_scary_face = {
        id = "j_scary_face",
        name = "Scary Face",
        order = 33,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 1,
        cost = 4,

        sell_cost = 2,
        effect = "Scary Face Cards",
        config = { extra = 30 },
        pos = {
            atlas = "Joker1_p2",
            index = 8
        }
    },

    j_abstract = {
        id = "j_abstract",
        name = "Abstract Joker",
        order = 34,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 1,
        cost = 4,

        sell_cost = 2,
        effect = "Joker Mult",
        config = { extra = 3 },
        pos = {
            atlas = "Joker1_p2",
            index = 9
        }
    },

    j_delayed_grat = {
        id = "j_delayed_grat",
        name = "Delayed Gratification",
        order = 35,
        unlocked = true,
        discovered = false,
        blueprint_compat = false,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 1,
        cost = 4,

        sell_cost = 2,
        effect = "Discard dollars",
        config = { extra = 2 },
        pos = {
            atlas = "Joker1_p2",
            index = 10
        }
    },

    j_hack = {
        id = "j_hack",
        name = "Hack",
        order = 36,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 2,
        cost = 6,

        sell_cost = 3,
        effect = "Low Card double",
        config = { extra = 1 },
        pos = {
            atlas = "Joker1_p2",
            index = 1
        }
    },

    j_pareidolia = {
        id = "j_pareidolia",
        name = "Pareidolia",
        order = 37,
        unlocked = true,
        discovered = false,
        blueprint_compat = false,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 2,
        cost = 5,

        sell_cost = 2,
        effect = "All face cards",
        config = {},
        pos = {
            atlas = "Joker1_p2",
            index = 12
        }
    },

    j_gros_michel = {
        id = "j_gros_michel",
        name = "Gros Michel",
        order = 38,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = false,
        rarity = 1,
        cost = 5,

        sell_cost = 2,
        config = { extra = { odds = 6, mult = 15 } },
        pos = {
            atlas = "Joker1_p3",
            index = 19
        }
    },

    j_even_steven = {
        id = "j_even_steven",
        name = "Even Steven",
        order = 39,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 1,
        cost = 4,

        sell_cost = 2,
        effect = "Even Card Buff",
        config = { extra = 4 },
        pos = {
            atlas = "Joker1_p2",
            index = 14
        }
    },

    j_odd_todd = {
        id = "j_odd_todd",
        name = "Odd Todd",
        order = 40,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 1,
        cost = 4,

        sell_cost = 2,
        effect = "Odd Card Buff",
        config = { extra = 31 },
        pos = {
            atlas = "Joker1_p2",
            index = 15
        }
    },

    j_scholar = {
        id = "j_scholar",
        name = "Scholar",
        order = 41,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 1,
        cost = 4,

        sell_cost = 2,
        effect = "Ace Buff",
        config = { extra = { mult = 4, chips = 20 } },
        pos = {
            atlas = "Joker1_p2",
            index = 16
        }
    },

    j_business = {
        id = "j_business",
        name = "Business Card",
        order = 42,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 1,
        cost = 4,

        sell_cost = 2,
        effect = "Face Card dollar Chance",
        config = { extra = 2 },
        pos = {
            atlas = "Joker1_p2",
            index = 17
        }
    },

    j_supernova = {
        id = "j_supernova",
        name = "Supernova",
        order = 43,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 1,
        cost = 5,

        sell_cost = 2,
        effect = "Hand played mult",
        config = { extra = 1 },
        pos = {
            atlas = "Joker1_p2",
            index = 18
        }
    },

    j_ride_the_bus = {
        id = "j_ride_the_bus",
        name = "Ride the Bus",
        order = 44,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = false,
        eternal_compat = true,
        rarity = 1,
        cost = 6,

        sell_cost = 3,
        config = { extra = 1 },
        pos = {
            atlas = "Joker1_p3",
            index = 13
        }
    },

    j_space = {
        id = "j_space",
        name = "Space Joker",
        order = 45,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 2,
        cost = 5,

        sell_cost = 2,
        effect = "Upgrade Hand chance",
        config = { extra = 4 },
        pos = {
            atlas = "Joker1_p3",
            index = 5
        }
    },

    j_egg = {
        id = "j_egg",
        name = "Egg",
        order = 46,
        unlocked = true,
        discovered = false,
        blueprint_compat = false,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 1,
        cost = 4,

        sell_cost = 2,
        config = { extra = 3 },
        pos = {
            atlas = "Joker2_p1",
            index = 10
        }
    },

    j_burglar = {
        id = "j_burglar",
        name = "Burglar",
        order = 47,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 2,
        cost = 6,

        sell_cost = 3,
        config = { extra = 3 },
        pos = {
            atlas = "Joker2_p1",
            index = 11
        }
    },

    j_blackboard = {
        id = "j_blackboard",
        name = "Blackboard",
        order = 48,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 2,
        cost = 6,

        sell_cost = 3,
        config = { extra = 3 },
        pos = {
            atlas = "Joker2_p1",
            index = 12
        }
    },

    j_runner = {
        id = "j_runner",
        name = "Runner",
        order = 49,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = false,
        eternal_compat = true,
        rarity = 1,
        cost = 5,

        sell_cost = 2,
        config = { extra = { chips = 0, chip_mod = 15 } },
        pos = {
            atlas = "Joker2_p1",
            index = 13
        }
    },

    j_ice_cream = {
        id = "j_ice_cream",
        name = "Ice Cream",
        order = 50,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = false,
        rarity = 1,
        cost = 5,

        sell_cost = 2,
        config = { chips = 100, chip_mod = 5 },
        pos = {
            atlas = "Joker2_p1",
            index = 14
        }
    },

    j_dna = {
        id = "j_dna",
        name = "DNA",
        order = 51,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 3,
        cost = 8,

        sell_cost = 4,
        config = {},
        pos = {
            atlas = "Joker2_p1",
            index = 15
        }
    },

    j_splash = {
        id = "j_splash",
        name = "Splash",
        order = 52,
        unlocked = true,
        discovered = false,
        blueprint_compat = false,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 1,
        cost = 3,

        sell_cost = 1,
        config = {},
        pos = {
            atlas = "Joker2_p1",
            index = 16
        }
    },

    j_blue_joker = {
        id = "j_blue_joker",
        name = "Blue Joker",
        order = 53,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 1,
        cost = 5,

        sell_cost = 2,
        config = { extra = 2 },
        pos = {
            atlas = "Joker2_p1",
            index = 17
        }
    },

    j_sixth_sense = {
        id = "j_sixth_sense",
        name = "Sixth Sense",
        order = 54,
        unlocked = true,
        discovered = false,
        blueprint_compat = false,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 2,
        cost = 6,

        sell_cost = 3,
        config = {},
        pos = {
            atlas = "Joker2_p1",
            index = 18
        }
    },

    j_constellation = {
        id = "j_constellation",
        name = "Constellation",
        order = 55,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = false,
        eternal_compat = true,
        rarity = 2,
        cost = 6,

        sell_cost = 3,
        config = { extra = 0.1, Xmult = 1 },
        pos = {
            atlas = "Joker2_p1",
            index = 19
        }
    },

    j_hiker = {
        id = "j_hiker",
        name = "Hiker",
        order = 56,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 2,
        cost = 5,

        sell_cost = 2,
        config = { extra = 5 },
        pos = {
            atlas = "Joker2_p1",
            index = 20
        }
    },

    j_faceless = {
        id = "j_faceless",
        name = "Faceless Joker",
        order = 57,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 1,
        cost = 4,

        sell_cost = 2,
        config = { extra = { dollars = 5, faces = 3 } },
        pos = {
            atlas = "Joker2_p1",
            index = 21
        }
    },

    j_green_joker = {
        id = "j_green_joker",
        name = "Green Joker",
        order = 58,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = false,
        eternal_compat = true,
        rarity = 1,
        cost = 4,

        sell_cost = 2,
        config = { extra = { hand_add = 1, discard_sub = 1 } },
        pos = {
            atlas = "Joker2_p1",
            index = 22
        }
    },

    j_superposition = {
        id = "j_superposition",
        name = "Superposition",
        order = 59,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 1,
        cost = 4,

        sell_cost = 2,
        config = {},
        pos = {
            atlas = "Joker2_p1",
            index = 23
        }
    },

    j_todo_list = {
        id = "j_todo_list",
        name = "To Do List",
        order = 60,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 1,
        cost = 4,

        sell_cost = 2,
        config = { extra = { dollars = 4, poker_hand = "High Card" } },
        pos = {
            atlas = "Joker2_p2",
            index = 0
        }
    },

    j_cavendish = {
        id = "j_cavendish",
        name = "Cavendish",
        order = 61,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = false,
        rarity = 1,
        cost = 4,

        sell_cost = 2,
        config = { extra = { odds = 1000, Xmult = 3 } },
        pos = {
            atlas = "Joker2_p2",
            index = 1
        }
    },

    j_card_sharp = {
        id = "j_card_sharp",
        name = "Card Sharp",
        order = 62,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 2,
        cost = 6,

        sell_cost = 3,
        config = { extra = { Xmult = 3 } },
        pos = {
            atlas = "Joker2_p2",
            index = 2
        }
    },

    j_red_card = {
        id = "j_red_card",
        name = "Red Card",
        order = 63,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = false,
        eternal_compat = true,
        rarity = 1,
        cost = 5,

        sell_cost = 2,
        config = { extra = 3 },
        pos = {
            atlas = "Joker2_p2",
            index = 3
        }
    },

    j_madness = {
        id = "j_madness",
        name = "Madness",
        order = 64,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = false,
        eternal_compat = true,
        rarity = 2,
        cost = 7,

        sell_cost = 3,
        config = { extra = 0.5 },
        pos = {
            atlas = "Joker2_p2",
            index = 4
        }
    },

    j_square = {
        id = "j_square",
        name = "Square Joker",
        order = 65,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = false,
        eternal_compat = true,
        rarity = 1,
        cost = 4,

        sell_cost = 2,
        config = { extra = { chips = 0, chip_mod = 4 } },
        pos = {
            atlas = "Joker2_p2",
            index = 5
        }
    },

    j_seance = {
        id = "j_seance",
        name = "Seance",
        order = 66,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 2,
        cost = 6,

        sell_cost = 3,
        config = { extra = { poker_hand = "Straight Flush" } },
        pos = {
            atlas = "Joker2_p2",
            index = 6
        }
    },

    j_riff_raff = {
        id = "j_riff_raff",
        name = "Riff-raff",
        order = 67,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 1,
        cost = 6,

        sell_cost = 3,
        config = { extra = 2 },
        pos = {
            atlas = "Joker2_p2",
            index = 7
        }
    },

    j_vampire = {
        id = "j_vampire",
        name = "Vampire",
        order = 68,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = false,
        eternal_compat = true,
        rarity = 2,
        cost = 7,

        sell_cost = 3,
        config = { extra = 0.1, Xmult = 1 },
        pos = {
            atlas = "Joker2_p2",
            index = 8
        }
    },

    j_shortcut = {
        id = "j_shortcut",
        name = "Shortcut",
        order = 69,
        unlocked = true,
        discovered = false,
        blueprint_compat = false,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 2,
        cost = 7,

        sell_cost = 3,
        config = {},
        pos = {
            atlas = "Joker2_p2",
            index = 9
        }
    },

    j_hologram = {
        id = "j_hologram",
        name = "Hologram",
        order = 70,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = false,
        eternal_compat = true,
        rarity = 2,
        cost = 7,

        sell_cost = 3,
        config = { extra = 0.25, Xmult = 1 },
        pos = {
            atlas = "Joker2_p2",
            index = 10
        }
    },

    j_vagabond = {
        id = "j_vagabond",
        name = "Vagabond",
        order = 71,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 3,
        cost = 8,

        sell_cost = 4,
        config = { extra = 4 },
        pos = {
            atlas = "Joker2_p2",
            index = 11
        }
    },

    j_baron = {
        id = "j_baron",
        name = "Baron",
        order = 72,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 3,
        cost = 8,

        sell_cost = 4,
        config = { extra = 1.5 },
        pos = {
            atlas = "Joker2_p2",
            index = 12
        }
    },

    j_cloud_9 = {
        id = "j_cloud_9",
        name = "Cloud 9",
        order = 73,
        unlocked = true,
        discovered = false,
        blueprint_compat = false,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 2,
        cost = 7,

        sell_cost = 3,
        config = { extra = 1 },
        pos = {
            atlas = "Joker2_p2",
            index = 13
        }
    },

    j_rocket = {
        id = "j_rocket",
        name = "Rocket",
        order = 74,
        unlocked = true,
        discovered = false,
        blueprint_compat = false,
        perishable_compat = false,
        eternal_compat = true,
        rarity = 2,
        cost = 6,

        sell_cost = 3,
        config = { extra = { dollars = 1, increase = 2 } },
        pos = {
            atlas = "Joker2_p2",
            index = 14
        }
    },

    j_obelisk = {
        id = "j_obelisk",
        name = "Obelisk",
        order = 75,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = false,
        eternal_compat = true,
        rarity = 3,
        cost = 8,

        sell_cost = 4,
        config = { extra = 0.2, Xmult = 1 },
        pos = {
            atlas = "Joker2_p2",
            index = 15
        }
    },

    j_midas_mask = {
        id = "j_midas_mask",
        name = "Midas Mask",
        order = 76,
        unlocked = true,
        discovered = false,
        blueprint_compat = false,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 2,
        cost = 7,

        sell_cost = 3,
        config = {},
        pos = {
            atlas = "Joker2_p2",
            index = 16
        }
    },

    j_luchador = {
        id = "j_luchador",
        name = "Luchador",
        order = 77,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = false,
        rarity = 2,
        cost = 5,

        sell_cost = 2,
        config = {},
        pos = {
            atlas = "Joker2_p2",
            index = 17
        }
    },

    j_photograph = {
        id = "j_photograph",
        name = "Photograph",
        order = 78,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 1,
        cost = 5,

        sell_cost = 2,
        config = { extra = 2 },
        pos = {
            atlas = "Joker2_p2",
            index = 18
        }
    },

    j_gift = {
        id = "j_gift",
        name = "Gift Card",
        order = 79,
        unlocked = true,
        discovered = false,
        blueprint_compat = false,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 2,
        cost = 6,

        sell_cost = 3,
        config = { extra = 1 },
        pos = {
            atlas = "Joker2_p2",
            index = 19
        }
    },

    j_turtle_bean = {
        id = "j_turtle_bean",
        name = "Turtle Bean",
        order = 80,
        unlocked = true,
        discovered = false,
        blueprint_compat = false,
        perishable_compat = true,
        eternal_compat = false,
        rarity = 2,
        cost = 6,

        sell_cost = 3,
        config = { extra = { h_size = 5, h_mod = 1 } },
        pos = {
            atlas = "Joker2_p2",
            index = 20
        }
    },

    j_erosion = {
        id = "j_erosion",
        name = "Erosion",
        order = 81,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 2,
        cost = 6,

        sell_cost = 3,
        config = { extra = 4 },
        pos = {
            atlas = "Joker2_p2",
            index = 21
        }
    },

    j_reserved_parking = {
        id = "j_reserved_parking",
        name = "Reserved Parking",
        order = 82,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 1,
        cost = 6,

        sell_cost = 3,
        config = { extra = { odds = 2, dollars = 1 } },
        pos = {
            atlas = "Joker2_p2",
            index = 22
        }
    },

    j_mail = {
        id = "j_mail",
        name = "Mail-In Rebate",
        order = 83,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 1,
        cost = 4,

        sell_cost = 2,
        config = { extra = 5 },
        pos = {
            atlas = "Joker2_p2",
            index = 23
        }
    },

    j_to_the_moon = {
        id = "j_to_the_moon",
        name = "To the Moon",
        order = 84,
        unlocked = true,
        discovered = false,
        blueprint_compat = false,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 2,
        cost = 5,

        sell_cost = 2,
        config = { extra = 1 },
        pos = {
            atlas = "Joker2_p3",
            index = 0
        }
    },

    j_hallucination = {
        id = "j_hallucination",
        name = "Hallucination",
        order = 85,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 1,
        cost = 4,

        sell_cost = 2,
        config = { extra = 2 },
        pos = {
            atlas = "Joker2_p3",
            index = 1
        }
    },

    j_smiley_face = { 
        id = "j_smiley_face",
        name = "Smiley Face", 
        order = 104,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 1, 
        cost = 4, 
        sell_cost = 2,

        pos = { 
            atlas = "Joker2_p3", 
            index = 18 
        } 
    },

    j_ticket = {
        id = "j_ticket",
        name = "Golden Ticket",
        order = 106,
        unlocked = false,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 1,
        cost = 5,

        sell_cost = 2,
        effect = "dollars for Gold cards",
        config = { extra = 4 },
        pos = {
            atlas = "Joker1_p2",
            index = 11
        }
    },

    j_mr_bones = {
        id = "j_mr_bones",
        name = "Mr. Bones",
        order = 107,
        unlocked = false,
        discovered = false,
        blueprint_compat = false,
        perishable_compat = true,
        eternal_compat = false,
        rarity = 2,
        cost = 5,

        sell_cost = 2,
        effect = "Prevent Death",
        config = {},
        pos = {
            atlas = "Joker1_p2",
            index = 19
        }
    },

    j_acrobat = {
        id = "j_acrobat",
        name = "Acrobat",
        order = 108,
        unlocked = false,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 2,
        cost = 6,

        sell_cost = 3,
        effect = "Shop size",
        config = { extra = 3 },
        pos = {
            atlas = "Joker1_p1",
            index = 12
        }
    },

    j_sock_and_buskin = {
        id = "j_sock_and_buskin",
        name = "Sock and Buskin",
        order = 109,
        unlocked = false,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 2,
        cost = 6,

        sell_cost = 3,
        effect = "Face card double",
        config = { extra = 1 },
        pos = {
            atlas = "Joker1_p1",
            index = 13
        }
    },

    j_swashbuckler = {
        id = "j_swashbuckler",
        name = "Swashbuckler",
        order = 110,
        unlocked = false,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 1,
        cost = 4,

        sell_cost = 2,
        effect = "Set Mult",
        config = { mult = 1 },
        pos = {
            atlas = "Joker1_p3",
            index = 11
        }
    },

    j_troubadour = {
        id = "j_troubadour",
        name = "Troubadour",
        order = 111,
        unlocked = false,
        discovered = false,
        blueprint_compat = false,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 2,
        cost = 6,

        sell_cost = 3,
        effect = "Hand Size, Plays",
        config = { extra = { h_size = 2, h_plays = -1 } },
        pos = {
            atlas = "Joker1_p1",
            index = 20
        }
    },

    j_certificate = {
        id = "j_certificate",
        name = "Certificate",
        order = 112,
        unlocked = false,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 2,
        cost = 6,

        sell_cost = 3,
        config = {},
        pos = {
            atlas = "Joker1_p4",
            index = 16
        }
    },

    j_smeared = {
        id = "j_smeared",
        name = "Smeared Joker",
        order = 113,
        unlocked = false,
        discovered = false,
        blueprint_compat = false,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 2,
        cost = 7,

        sell_cost = 3,
        config = {},
        pos = {
            atlas = "Joker1_p3",
            index = 16
        }
    },

    j_throwback = {
        id = "j_throwback",
        name = "Throwback",
        order = 114,
        unlocked = false,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 2,
        cost = 6,

        sell_cost = 3,
        config = { extra = 0.25 },
        pos = {
            atlas = "Joker1_p4",
            index = 3
        }
    },

    j_hanging_chad = {
        id = "j_hanging_chad",
        name = "Hanging Chad",
        order = 115,
        unlocked = false,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 1,
        cost = 4,

        sell_cost = 2,
        config = { extra = 2 },
        pos = {
            atlas = "Joker1_p3",
            index = 21
        }
    },

    j_rough_gem = {
        id = "j_rough_gem",
        name = "Rough Gem",
        order = 116,
        unlocked = false,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 2,
        cost = 7,

        sell_cost = 3,
        config = { extra = 1 },
        pos = {
            atlas = "Joker1_p4",
            index = 7
        }
    },

    j_bloodstone = {
        id = "j_bloodstone",
        name = "Bloodstone",
        order = 117,
        unlocked = false,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 2,
        cost = 7,

        sell_cost = 3,
        config = { extra = { odds = 2, Xmult = 1.5 } },
        pos = {
            atlas = "Joker1_p4",
            index = 8
        }
    },

    j_arrowhead = {
        id = "j_arrowhead",
        name = "Arrowhead",
        order = 118,
        unlocked = false,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 2,
        cost = 7,

        sell_cost = 3,
        config = { extra = 50 },
        pos = {
            atlas = "Joker1_p4",
            index = 9
        }
    },

    j_onyx_agate = {
        id = "j_onyx_agate",
        name = "Onyx Agate",
        order = 119,
        unlocked = false,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 2,
        cost = 7,

        sell_cost = 3,
        config = { extra = 7 },
        pos = {
            atlas = "Joker1_p4",
            index = 10
        }
    },

    j_glass = {
        id = "j_glass",
        name = "Glass Joker",
        order = 120,
        unlocked = false,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = false,
        eternal_compat = true,
        rarity = 2,
        cost = 6,

        sell_cost = 3,
        effect = "Glass Card",
        config = { extra = 0.75, Xmult = 1 },
        pos = {
            atlas = "Joker1_p2",
            index = 7
        }
    },

    j_ring_master = {
        id = "j_ring_master",
        name = "Showman",
        order = 121,
        unlocked = false,
        discovered = false,
        blueprint_compat = false,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 2,
        cost = 5,

        sell_cost = 2,
        config = {},
        pos = {
            atlas = "Joker1_p3",
            index = 8
        }
    },

    j_flower_pot = {
        id = "j_flower_pot",
        name = "Flower Pot",
        order = 122,
        unlocked = false,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 2,
        cost = 6,

        sell_cost = 3,
        config = { extra = 3 },
        pos = {
            atlas = "Joker1_p3",
            index = 12
        }
    },

    j_blueprint = {
        id = "j_blueprint",
        name = "Blueprint",
        order = 123,
        unlocked = false,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 3,
        cost = 10,

        sell_cost = 5,
        effect = "Copycat",
        config = {},
        pos = {
            atlas = "Joker1_p2",
            index = 6
        }
    },

    j_wee = {
        id = "j_wee",
        name = "Wee Joker",
        order = 124,
        unlocked = false,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = false,
        eternal_compat = true,
        rarity = 3,
        cost = 8,

        sell_cost = 4,
        config = { extra = { chips = 0, chip_mod = 8 } },
        pos = {
            atlas = "Joker1_p1",
            index = 0
        }
    },

    j_merry_andy = {
        id = "j_merry_andy",
        name = "Merry Andy",
        order = 125,
        unlocked = false,
        discovered = false,
        blueprint_compat = false,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 2,
        cost = 7,

        sell_cost = 3,
        config = { d_size = 3, h_size = -1 },
        pos = {
            atlas = "Joker1_p1",
            index = 8
        }
    },

    j_oops = {
        id = "j_oops",
        name = "Oops! All 6s",
        order = 126,
        unlocked = false,
        discovered = false,
        blueprint_compat = false,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 2,
        cost = 4,

        sell_cost = 2,
        config = {},
        pos = {
            atlas = "Joker1_p3",
            index = 17
        }
    },

    j_idol = {
        id = "j_idol",
        name = "The Idol",
        order = 127,
        unlocked = false,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 2,
        cost = 6,

        sell_cost = 3,
        config = { extra = 2 },
        pos = {
            atlas = "Joker1_p4",
            index = 4
        }
    },

    j_seeing_double = {
        id = "j_seeing_double",
        name = "Seeing Double",
        order = 128,
        unlocked = false,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 2,
        cost = 6,

        sell_cost = 3,
        effect = "X1.5 Mult club 7",
        config = { extra = 2 },
        pos = {
            atlas = "Joker1_p2",
            index = 20
        }
    },

    j_matador = {
        id = "j_matador",
        name = "Matador",
        order = 129,
        unlocked = false,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 2,
        cost = 7,

        sell_cost = 3,
        config = { extra = 8 },
        pos = {
            atlas = "Joker1_p3",
            index = 6
        }
    },

    j_hit_the_road = {
        id = "j_hit_the_road",
        name = "Hit the Road",
        order = 130,
        unlocked = false,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 3,
        cost = 8,

        sell_cost = 4,
        effect = "Jack Discard Effect",
        config = { extra = 0.5 },
        pos = {
            atlas = "Joker1_p3",
            index = 10
        }
    },

    j_duo = {
        id = "j_duo",
        name = "The Duo",
        order = 131,
        unlocked = false,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 3,
        cost = 8,

        sell_cost = 4,
        effect = "X1.5 Mult",
        config = { Xmult = 2, type = "Pair" },
        pos = {
            atlas = "Joker1_p2",
            index = 21
        }
    },

    j_trio = {
        id = "j_trio",
        name = "The Trio",
        order = 132,
        unlocked = false,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 3,
        cost = 8,

        sell_cost = 4,
        effect = "X2 Mult",
        config = { Xmult = 3, type = "Three of a Kind" },
        pos = {
            atlas = "Joker1_p2",
            index = 22
        }
    },

    j_family = {
        id = "j_family",
        name = "The Family",
        order = 133,
        unlocked = false,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 3,
        cost = 8,

        sell_cost = 4,
        effect = "X3 Mult",
        config = { Xmult = 4, type = "Four of a Kind" },
        pos = {
            atlas = "Joker1_p2",
            index = 23
        }
    },

    j_order = {
        id = "j_order",
        name = "The Order",
        order = 134,
        unlocked = false,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 3,
        cost = 8,

        sell_cost = 4,
        effect = "X3 Mult",
        config = { Xmult = 3, type = "Straight" },
        pos = {
            atlas = "Joker1_p3",
            index = 0
        }
    },

    j_tribe = {
        id = "j_tribe",
        name = "The Tribe",
        order = 135,
        unlocked = false,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 3,
        cost = 8,

        sell_cost = 4,
        effect = "X3 Mult",
        config = { Xmult = 2, type = "Flush" },
        pos = {
            atlas = "Joker1_p3",
            index = 1
        }
    },

    j_stuntman = {
        id = "j_stuntman",
        name = "Stuntman",
        order = 136,
        unlocked = false,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 3,
        cost = 7,

        sell_cost = 3,
        config = { extra = { h_size = 2, chip_mod = 250 } },
        pos = {
            atlas = "Joker1_p3",
            index = 20
        }
    },

    j_invisible = {
        id = "j_invisible",
        name = "Invisible Joker",
        order = 137,
        unlocked = false,
        discovered = false,
        blueprint_compat = false,
        perishable_compat = true,
        eternal_compat = false,
        rarity = 3,
        cost = 8,

        sell_cost = 4,
        config = { extra = 2 },
        pos = {
            atlas = "Joker1_p3",
            index = 23
        }
    },

    j_brainstorm = {
        id = "j_brainstorm",
        name = "Brainstorm",
        order = 138,
        unlocked = false,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 3,
        cost = 10,

        sell_cost = 5,
        effect = "Copycat",
        config = {},
        pos = {
            atlas = "Joker1_p4",
            index = 5
        }
    },

    j_satellite = {
        id = "j_satellite",
        name = "Satellite",
        order = 139,
        unlocked = false,
        discovered = false,
        blueprint_compat = false,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 2,
        cost = 6,

        sell_cost = 3,
        config = { extra = 1 },
        pos = {
            atlas = "Joker1_p4",
            index = 6
        }
    },

    j_shoot_the_moon = {
        id = "j_shoot_the_moon",
        name = "Shoot the Moon",
        order = 140,
        unlocked = false,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 1,
        cost = 5,

        sell_cost = 2,
        config = { extra = 13 },
        pos = {
            atlas = "Joker1_p3",
            index = 14
        }
    },

    j_drivers_license = {
        id = "j_drivers_license",
        name = "Driver's License",
        order = 141,
        unlocked = false,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 3,
        cost = 7,

        sell_cost = 3,
        config = { extra = 3 },
        pos = {
            atlas = "Joker1_p3",
            index = 22
        }
    },

    j_cartomancer = {
        id = "j_cartomancer",
        name = "Cartomancer",
        order = 142,
        unlocked = false,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 2,
        cost = 6,

        sell_cost = 3,
        effect = "Tarot Buff",
        config = {},
        pos = {
            atlas = "Joker1_p2",
            index = 13
        }
    },

    j_astronomer = {
        id = "j_astronomer",
        name = "Astronomer",
        order = 143,
        unlocked = false,
        discovered = false,
        blueprint_compat = false,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 2,
        cost = 8,

        sell_cost = 4,
        config = {},
        pos = {
            atlas = "Joker1_p4",
            index = 0
        }
    },

    j_burnt = {
        id = "j_burnt",
        name = "Burnt Joker",
        order = 144,
        unlocked = false,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 3,
        cost = 8,

        sell_cost = 4,
        config = { h_size = 0, extra = 4 },
        pos = {
            atlas = "Joker1_p4",
            index = 1
        }
    },

    j_bootstraps = {
        id = "j_bootstraps",
        name = "Bootstraps",
        order = 145,
        unlocked = false,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 2,
        cost = 7,

        sell_cost = 3,
        config = { extra = { mult = 2, dollars = 5 } },
        pos = {
            atlas = "Joker1_p4",
            index = 17
        }
    },

    j_canio = {
        id = "j_canio",
        name = "Canio",
        order = 146,
        unlocked = false,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 4,
        cost = 20,

        sell_cost = 10,
        config = { extra = 1 },
        pos = {
            atlas = "Joker1_p4",
            index = 11
        }
    },

    j_triboulet = {
        id = "j_triboulet",
        name = "Triboulet",
        order = 147,
        unlocked = false,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 4,
        cost = 20,

        sell_cost = 10,
        config = { extra = 2 },
        pos = {
            atlas = "Joker1_p4",
            index = 12
        }
    },

    j_yorick = {
        id = "j_yorick",
        name = "Yorick",
        order = 148,
        unlocked = false,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 4,
        cost = 20,

        sell_cost = 10,
        config = { extra = { xmult = 1, discards = 23 } },
        pos = {
            atlas = "Joker1_p4",
            index = 13
        }
    },

    j_chicot = {
        id = "j_chicot",
        name = "Chicot",
        order = 149,
        unlocked = false,
        discovered = false,
        blueprint_compat = false,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 4,
        cost = 20,

        sell_cost = 10,
        config = {},
        pos = {
            atlas = "Joker1_p4",
            index = 14
        }
    },

    j_perkeo = {
        id = "j_perkeo",
        name = "Perkeo",
        order = 150,
        unlocked = false,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 4,
        cost = 20,

        sell_cost = 10,
        config = {},
        pos = {
            atlas = "Joker1_p4",
            index = 15
        }
    },

    j_fortune_teller = { 
        id = "j_fortune_teller",
        name = "Fortune Teller", 
        order = 86,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 1, 
        cost = 6, 

        sell_cost = 3,
        pos = { 
            atlas = "Joker1_p3", 
            index = 9 
        } 
    },
    
    j_juggler = { 
        id = "j_juggler",
        name = "Juggler", 
        order = 87,
        unlocked = true,
        discovered = false,
        blueprint_compat = false,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 1, 
        cost = 4, 
        sell_cost = 2,
        pos = { 
            atlas = "Joker1_p1", 
            index = 10 
        } 
    },

    j_drunkard = { 
        id = "j_drunkard",
        name = "Drunkard",
        order = 88,
        unlocked = true,
        discovered = false,
        blueprint_compat = false,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 1,
        cost = 4, 
        sell_cost = 2,
        pos = { 
            atlas = "Joker1_p1", 
            index = 11 
        } 
    },

    j_stone_joker = { 
        id = "j_stone_joker",
        name = "Stone Joker",
        order = 89,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 2, 
        cost = 6, 
        sell_cost = 3,
        pos = { 
            atlas = "Joker1_p1", 
            index = 9 
        } 
    },
    j_golden_joker = { 
        id = "j_golden_joker",
        name = "Golden Joker", 
        order = 90,
        unlocked = true,
        discovered = false,
        blueprint_compat = false,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 1, 
        cost = 6, 
        sell_cost = 3,
        pos = { 
            atlas = "Joker1_p2", 
            index = 5 
        } 
    },
    
    j_lucky_cat = { 
        id = "j_lucky_cat",
        name = "Lucky Cat", 
        order = 91,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = false,
        eternal_compat = true,
        rarity = 2, 
        cost = 6, 
        sell_cost = 3,
        pos = { 
            atlas = "Joker2_p3", 
            index = 7 
        } 
    },
    
    j_bull = { 
        id = "j_bull",
        name = "Bull", 
        order = 93,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 2, 
        cost = 6, 
        sell_cost = 3,
        pos = { 
            atlas = "Joker2_p3", 
            index = 9 
        } 
    },

    j_baseball_card = { 
        id = "j_baseball_card",
        name = "Baseball Card", 
        order = 92,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 3, 
        cost = 8, 
        sell_cost = 4,
        pos = { 
            atlas = "Joker2_p3", 
            index = 8 
        } 
    },

    j_trading_card = { 
        id = "j_trading_card",
        name = "Trading Card", 
        order = 95,
        unlocked = true,
        discovered = false,
        blueprint_compat = false,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 2, 
        cost = 6, 
        sell_cost = 3,
        pos = { 
            atlas = "Joker2_p3", 
            index = 11 
        } 
    },

    j_flash_card = { 
        id = "j_flash_card",
        name = "Flash Card", 
        order = 96,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = false,
        eternal_compat = true,
        rarity = 2, 
        cost = 5, 
        sell_cost = 2,
        pos = { 
            atlas = "Joker2_p3", 
            index = 12 
        } 
    },

    j_popcorn = { 
        id = "j_popcorn",
        name = "Popcorn", 
        order = 97,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = false,
        rarity = 1, 
        cost = 5, 
        sell_cost = 2,
        pos = { 
            atlas = "Joker2_p3", 
            index = 13 
        } 
    },

    j_spare_trousers = { 
        id = "j_spare_trousers",
        name = "Spare Trousers", 
        order = 98,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = false,
        eternal_compat = true,
        rarity = 2, 
        cost = 6, 
        sell_cost = 3,
        pos = { 
            atlas = "Joker2_p3", 
            index = 16 
        } 
    },

    j_ancient_joker = { 
        id = "j_ancient_joker",
        name = "Ancient Joker", 
        order = 99,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 3, 
        cost = 8, 
        sell_cost = 4,
        pos = { 
            atlas = "Joker2_p3", 
            index = 19 
        } 
    },

    j_ramen = { 
        id = "j_ramen",
        name = "Ramen", 
        order = 100,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = false,
        rarity = 2, 
        cost = 6, 
        sell_cost = 3,
        config = { Xmult = 2},
        pos = { 
            atlas = "Joker2_p3", 
            index = 14 
        } 
    },

    j_walkie_talkie = { 
        id = "j_walkie_talkie",
        name = "Walkie Talkie", 
        order = 101,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 1, 
        cost = 4, 
        sell_cost = 2,
        pos = { 
            atlas = "Joker2_p3", 
            index = 20 
        } 
    },

    j_seltzer = { 
        id = "j_seltzer",
        name = "Seltzer", 
        order = 102,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = false,
        rarity = 2, 
        cost = 6, 
        sell_cost = 3,
        config = {duration = 10},
        pos = { 
            atlas = "Joker2_p3", 
            index = 15
        } 
    },

    j_castle = { 
        id = "j_castle",
        name = "Castle", 
        order = 103,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = false,
        eternal_compat = true,
        rarity = 2, 
        cost = 6, 
        sell_cost = 3,
        pos = { 
            atlas = "Joker2_p3", 
            index = 21 
        } 
    },
    
    j_campfire = {
        id = "j_campfire",
        name = "Campfire",
        order = 105,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = true,
        rarity = 3,
        cost = 9,
        sell_cost = 4,
        pos = {
            atlas = "Joker2_p3",
            index = 17
        }
    },    

}
-- Missing jokers that were previously injected from CSV metadata are now explicit.
local MISSING_JOKERS = {
    j_diet_cola = {
        name = "Diet Cola",
        order = 94,
        unlocked = true,
        discovered = false,
        blueprint_compat = true,
        perishable_compat = true,
        eternal_compat = false,
        rarity = 2,
        cost = 6,
        pos = { atlas = "Joker1_p2", index = 2 },
    },
}

-- Catalog-owned tooltip text (Balatro-style; *word* used for emphasis in UI).
local TOOLTIP_BY_ID = {
    j_joker = { "+4 Mult" },
    j_greedy_joker = {
        "Played cards with *Diamond* suit give",
        "+3 Mult when scored",
    },
    j_lusty_joker = {
        "Played cards with *Heart* suit give",
        "+3 Mult when scored",
    },
    j_wrathful_joker = {
        "Played cards with *Spade* suit give",
        "+3 Mult when scored",
    },
    j_gluttenous_joker = {
        "Played cards with *Club* suit give",
        "+3 Mult when scored",
    },
    j_jolly = { "+8 Mult if played hand contains a", "*Pair*" },
    j_zany = { "+12 Mult if played hand contains a", "*Three of a Kind*" },
    j_mad = { "+10 Mult if played hand contains a", "*Two Pair*" },
    j_crazy = { "+12 Mult if played hand contains a", "*Straight*" },
    j_droll = { "+10 Mult if played hand contains a", "*Flush*" },
    j_sly = { "+50 Chips if played hand contains a", "*Pair*" },
    j_wily = { "+100 Chips if played hand contains a", "*Three of a Kind*" },
    j_clever = { "+80 Chips if played hand contains a", "*Two Pair*" },
    j_devious = { "+100 Chips if played hand contains a", "*Straight*" },
    j_crafty = { "+80 Chips if played hand contains a", "*Flush*" },
    j_half = {
        "+20 Mult if played hand contains",
        "3 or fewer cards",
    },
    j_stencil = {
        "*X1 Mult* for each empty Joker slot",
        "Joker Stencil included",
        "(Currently *X1*)",
    },
    j_four_fingers = {
        "All *Flushes* and *Straights* can be made",
        "with 4 cards",
    },
    j_mime = { "Retrigger all card held in hand abilities" },
    j_credit_card = { "Go up to -$20 in debt" },
    j_ceremonial = {
        "When Blind is selected, destroy Joker to the right",
        "and permanently add double its sell value",
        "to this Mult",
        "(Currently +0 Mult)",
    },
    j_banner = { "+30 Chips for each remaining discard" },
    j_mystic_summit = { "+15 Mult when 0 discards remaining" },
    j_marble = {
        "Adds one Stone card to the deck",
        "when Blind is selected",
    },
    j_loyalty_card = {
        "*X4 Mult* every 6 hands played",
        "5 remaining",
    },
    j_8_ball = {
        "1 in 4 chance for each played 8 to create a",
        "Tarot card when scored",
        "(Must have room)",
    },
    j_misprint = { "+0-23 Mult" },
    j_dusk = {
        "Retrigger all played cards in",
        "final hand of the round",
    },
    j_raised_fist = {
        "Adds double the rank of lowest ranked card",
        "held in hand to Mult",
    },
    j_chaos = { "1 free Reroll per shop" },
    j_fibonacci = {
        "Each played Ace, 2, 3, 5, or 8 gives",
        "+8 Mult when scored",
    },
    j_steel_joker = {
        "Gives *X0.2 Mult* for each Steel Card",
        "in your full deck",
        "(Currently *X1 Mult*)",
    },
    j_scary_face = { "Played face cards give +30 Chips when scored" },
    j_abstract = {
        "+3 Mult for each Joker card",
        "(Currently +0 Mult)",
    },
    j_delayed_grat = {
        "Earn *$2* per discard if no discards are used",
        "by end of the round",
    },
    j_hack = { "Retrigger each played 2, 3, 4, or 5" },
    j_pareidolia = { "All cards are considered face cards" },
    j_gros_michel = {
        "+15 Mult",
        "1 in 6 chance this is destroyed at the end of round.",
    },
    j_even_steven = {
        "Played cards with even rank give +4 Mult",
        "when scored",
        "(10, 8, 6, 4, 2)",
    },
    j_odd_todd = {
        "Played cards with odd rank give +31 Chips",
        "when scored",
        "(A, 9, 7, 5, 3)",
    },
    j_scholar = {
        "Played Aces give +20 Chips",
        "and +4 Mult when scored",
    },
    j_business = {
        "Played face cards have a 1 in 2 chance",
        "to give *$2* when scored",
    },
    j_supernova = {
        "Adds the number of times poker hand has been",
        "played this run to Mult",
    },
    j_ride_the_bus = {
        "This Joker gains +1 Mult per consecutive hand",
        "played without a scoring face card",
        "(Currently +0 Mult)",
    },
    j_space = {
        "1 in 4 chance to upgrade level of",
        "played poker hand",
    },
    j_egg = { "Gains *$3* of sell value at end of round" },
    j_burglar = {
        "When Blind is selected, gain +3 Hands",
        "and lose all discards",
    },
    j_blackboard = {
        "*X3 Mult* if all cards held in hand are",
        "* Spades* or * Clubs*",
    },
    j_runner = {
        "Gains +15 Chips if played hand contains a *Straight*",
        "(Currently +0 Chips)",
    },
    j_ice_cream = {
        "+100 Chips",
        "-5 Chips for every hand played",
        "(Currently +100 Chips)",
    },
    j_dna = {
        "If first hand of round has only 1 card,",
        "add a permanent copy to deck and draw it to hand",
    },
    j_splash = { "Every played card counts in scoring" },
    j_blue_joker = {
        "+2 Chips for each remaining card in deck",
        "(Currently +104 Chips)",
    },
    j_sixth_sense = {
        "If first hand of round is a single 6, destroy it",
        "and create a Spectral card",
        "(Must have room)",
    },
    j_constellation = {
        "This Joker gains *X0.1 Mult* every time",
        "a Planet card is used",
        "(Currently *X1 Mult*)",
    },
    j_hiker = {
        "Every played card permanently gains",
        "+5 Chips when scored",
    },
    j_faceless = {
        "Earn *$5* if 3 or more face cards are",
        "discarded at the same time",
    },
    j_green_joker = {
        "+1 Mult per hand played",
        "-1 Mult per discard",
        "(Currently +0 Mult)",
    },
    j_superposition = {
        "Create a Tarot card if poker hand contains",
        "an Ace and a *Straight*",
        "(Must have room)",
    },
    j_todo_list = {
        { kind = "current", text = "Earn *$4* if poker hand is a *High Card*," },
        "poker hand changes at end of round",
    },
    j_cavendish = {
        "*X3 Mult*",
        "1 in 1000 chance this card is destroyed",
        "at the end of round",
    },
    j_card_sharp = {
        "*X3 Mult* if played poker hand has",
        "already been played this round",
    },
    j_red_card = {
        "This Joker gains +3 Mult when any",
        "Booster Pack is skipped",
        "(Currently +0 Mult)",
    },
    j_madness = {
        "When Small Blind or Big Blind is selected,",
        "gain *X0.5 Mult* and destroy a random Joker",
        "(Currently *X1 Mult*)",
    },
    j_square = {
        "This Joker gains +4 Chips if played hand",
        "has exactly 4 cards",
        "(Currently 0 Chips)",
    },
    j_seance = {
        "If poker hand is a *Straight Flush*,",
        "create a random Spectral card",
        "(Must have room)",
    },
    j_riff_raff = {
        "When Blind is selected, create 2 Common Jokers",
        "(Must have room)",
    },
    j_vampire = {
        "This Joker gains *X0.1 Mult*",
        "per scoring Enhanced card played,",
        "removes card Enhancement",
        "(Currently *X1 Mult*)",
    },
    j_shortcut = {
        "Allows *Straights* to be made with gaps of 1 rank",
        "(ex: 10 8 6 5 3)",
    },
    j_hologram = {
        "This Joker gains *X0.25 Mult* every time",
        "a playing card is added to your deck",
        "(Currently *X1 Mult*)",
    },
    j_vagabond = {
        "Create a Tarot card if hand is played",
        "with *$4* or less",
    },
    j_baron = { "Each King held in hand gives *X1.5 Mult*" },
    j_cloud_9 = {
        "Earn *$1* for each 9 in your full deck",
        "at end of round",
        "(Currently *$4*)",
    },
    j_rocket = {
        "Earn *$1* at end of round.",
        "Payout increases by *$2* when Boss Blind is defeated",
        "(Currently $1)",
    },
    j_obelisk = {
        "This Joker gains *X0.2 Mult* per consecutive hand",
        "played without playing your most played poker hand",
        "(Currently *X1 Mult*)",
    },
    j_midas_mask = { "All played face cards become Gold cards when scored" },
    j_luchador = { "Sell this card to disable the current Boss Blind" },
    j_photograph = { "First played face card gives *X2 Mult* when scored" },
    j_gift = {
        "Add *$1* of sell value to every Joker",
        "and Consumable card at end of round",
    },
    j_turtle_bean = {
        "+5 hand size, reduces by 1 each round",
        "(Currently +5 hand size)",
    },
    j_erosion = {
        "+4 Mult for each card below",
        "[the deck's starting size] in your full deck",
        "(Currently +0 Mult)",
    },
    j_reserved_parking = {
        "Each face card held in hand has a 1 in 2",
        "chance to give *$1*",
    },
    j_mail = {
        { kind = "current", text = "Earn *$5* for each discarded Ace," },
        "rank changes every round",
    },
    j_to_the_moon = {
        "Earn an extra *$1* of interest for every *$5*",
        "you have at end of round",
    },
    j_hallucination = {
        "1 in 2 chance to create a Tarot card",
        "when any Booster Pack is opened",
        "(Must have room)",
    },
    j_ticket = { "Played Gold cards earn *$4* when scored" },
    j_mr_bones = {
        "Prevents Death if chips scored are at least",
        "25% of required chips",
        "self destructs",
    },
    j_acrobat = { "*X3 Mult* on final hand of round" },
    j_sock_and_buskin = { "Retrigger all played face cards" },
    j_swashbuckler = {
        "Adds the sell value of all other",
        "owned Jokers to Mult",
        "(Currently +1 Mult)",
    },
    j_troubadour = {
        "+2 hand size,",
        "-1 hand each round",
    },
    j_certificate = {
        "When round begins, add a random playing card",
        "with a random seal to your hand",
    },
    j_smeared = {
        "* Hearts* and * Diamonds* count as the same suit,",
        "* Spades* and * Clubs* count as the same suit",
    },
    j_throwback = {
        "*X0.25 Mult* for each Blind skipped this run",
        "(Currently *X1 Mult*)",
    },
    j_hanging_chad = {
        "Retrigger first played card used in scoring",
        "2 additional times",
    },
    j_rough_gem = {
        "Played cards with * Diamond* suit earn",
        "*$1* when scored",
    },
    j_bloodstone = {
        "1 in 2 chance for played cards with * Heart* suit",
        "to give *X1.5 Mult* when scored",
    },
    j_arrowhead = {
        "Played cards with * Spade* suit give",
        "+50 Chips when scored",
    },
    j_onyx_agate = {
        "Played cards with * Club* suit give",
        "+7 Mult when scored",
    },
    j_glass = {
        "This Joker gains *X0.75 Mult* for every",
        "Glass Card that is destroyed",
        "(Currently *X1 Mult*)",
    },
    j_ring_master = {
        "Joker, Tarot, Planet, and Spectral cards",
        "may appear multiple times",
    },
    j_flower_pot = {
        "*X3 Mult* if poker hand contains a * Diamond* card,",
        "* Club* card, * Heart* card, and * Spade* card",
    },
    j_blueprint = { "Copies ability of Joker to the right" },
    j_wee = {
        "This Joker gains +8 Chips when",
        "each played 2 is scored",
        "(Currently +0 Chips)",
    },
    j_merry_andy = {
        "+3 discards each round,",
        "-1 hand size",
    },
    j_oops = {
        "Doubles all listed probabilities",
        "(ex: 1 in 3 -> 2 in 3)",
    },
    j_idol = {
        { kind = "current", text = "Each played Ace of Hearts gives *X3 Mult* when scored," },
        "Card changes every round",
    },
    j_seeing_double = {
        "*X2 Mult* if played hand has a scoring * Club* card",
        "and a scoring card of any other suit",
    },
    j_matador = {
        "Earn *$8* if played hand triggers",
        "the Boss Blind ability",
    },
    j_hit_the_road = {
        "This Joker gains *X0.5 Mult* for every",
        "Jack discarded this round",
        "(Currently *X1 Mult*)",
    },
    j_duo = { "*X2 Mult* if played hand contains a", "*Pair*" },
    j_trio = { "*X3 Mult* if played hand contains a", "*Three of a Kind*" },
    j_family = { "*X4 Mult* if played hand contains a", "*Four of a Kind*" },
    j_order = { "*X3 Mult* if played hand contains a", "*Straight*" },
    j_tribe = { "*X2 Mult* if played hand contains a", "*Flush*" },
    j_stuntman = {
        "+250 Chips,",
        "-2 hand size",
    },
    j_invisible = {
        "After 2 rounds, sell this card",
        "to Duplicate a random Joker",
        "(Currently 0/2)",
        "(Removes Negative from copy)",
    },
    j_brainstorm = { "Copies the ability of leftmost Joker" },
    j_satellite = {
        "Earn *$1* at end of round per unique",
        "Planet card used this run",
    },
    j_shoot_the_moon = { "Each Queen held in hand gives +13 Mult" },
    j_drivers_license = {
        "*X3 Mult* if you have at least 16 Enhanced",
        "cards in your full deck",
        "(Currently 0)",
    },
    j_cartomancer = {
        "Create a Tarot card when Blind is selected",
        "(Must have room)",
    },
    j_astronomer = {
        "All Planet cards and Celestial Packs",
        "in the shop are free",
    },
    j_burnt = {
        "Upgrade the level of the first discarded",
        "poker hand each round",
    },
    j_bootstraps = {
        "+2 Mult for every *$5* you have",
        "(Currently +0 Mult)",
    },
    j_canio = {
        "This Joker gains *X1 Mult* when",
        "a face card is destroyed",
        "(Currently *X1 Mult*)",
    },
    j_triboulet = {
        "Played Kings and Queens each give",
        "*X2 Mult* when scored",
    },
    j_yorick = {
        "This Joker gains *X1 Mult* every",
        "23 cards discarded",
        "(Currently *X1 Mult*)",
    },
    j_chicot = { "Disables effect of every Boss Blind" },
    j_perkeo = {
        "Creates a Negative copy of 1 random consumable",
        "in your possession at the end of the shop",
    },
    j_fortune_teller = {
        "+1 Mult per Tarot card used this run",
        "(Currently +0)",
    },
    j_juggler = { "+1 hand size" },
    j_drunkard = { "+1 discard each round" },
    j_stone_joker = {
        "Gives +25 Chips for each Stone Card",
        "in your full deck",
        "(Currently +0 Chips)",
    },
    j_golden_joker = { "Earn *$4* at end of round" },
    j_lucky_cat = {
        "This Joker gains *X0.25 Mult* every time",
        "a Lucky card successfully triggers",
        "(Currently *X1 Mult*)",
    },
    j_baseball_card = { "Uncommon Jokers each give *X1.5 Mult*" },
    j_bull = {
        "+2 Chips for each *$1* you have",
        "(Currently +0 Chips)",
    },
    j_diet_cola = { "Sell this card to create a free Double Tag" },
    j_trading_card = {
        "If first discard of round has only 1 card,",
        "destroy it and earn *$3*",
    },
    j_flash_card = {
        "This Joker gains +2 Mult per reroll",
        "in the shop",
        "(Currently +0 Mult)",
    },
    j_popcorn = {
        "+20 Mult",
        "-4 Mult per round played",
    },
    j_spare_trousers = {
        "This Joker gains +2 Mult if played hand",
        "contains a Two Pair",
        "(Currently +0 Mult)",
    },
    j_ancient_joker = {
        {
            kind = "current",
            text = "Each played card with Hearts gives X1.5 Mult when scored",
        },
    },
    j_ramen = {
        "*X2 Mult*, loses *X0.01 Mult*",
        "per card discarded",
        "(Currently X2 Mult)",
    },
    j_walkie_talkie = {
        "Each played 10 or 4 gives +10 Chips",
        "and +4 Mult when scored",
    },
    j_seltzer = {
        "Retrigger all cards played for the",
        "next 10 hands",
        "(Currently 10 hands remaining)",
    },
    j_castle = {
        {
            kind = "current",
            text = "This Joker gains +3 Chips per discarded Hearts card,",
        },
        "card, suit changes every round",
        {
            kind = "current",
            text = "(Currently +0 Chips)",
        },
    },
    j_smiley_face = { "Played face cards give +5 Mult when scored" },
    j_campfire = {
        "This Joker gains *X0.25 Mult* for each card sold,",
        "resets when Boss Blind is defeated",
        "(Currently *X1 Mult*)",
    },
}

local function build_structured_tooltip_line(text)
    if type(text) ~= "string" then return nil end
    local kind = "text"
    if text:find("(Currently", 1, true) then
        kind = "current"
    end
    return {
        kind = kind,
        text = text,
    }
end

local function build_structured_tooltip_lines(lines)
    if type(lines) ~= "table" then return nil end
    local out = {}
    for _, line in ipairs(lines) do
        if type(line) == "string" then
            local structured = build_structured_tooltip_line(line)
            if structured then
                table.insert(out, structured)
            end
        elseif type(line) == "table" then
            table.insert(out, line)
        end
    end
    if #out <= 0 then return nil end
    return out
end

local function rarity_label_for_def(def)
    local r = def and tonumber(def.rarity)
    if r == 1 then return "Common"
    elseif r == 2 then return "Uncommon"
    elseif r == 3 then return "Rare"
    elseif r == 4 then return "Legendary"
    end
    return nil
end

local function prepend_rarity_tooltip_line(def)
    local r = def and tonumber(def.rarity)
    local label = rarity_label_for_def(def)
    if not label or not r or r < 1 or r > 4 or type(def.tooltip) ~= "table" then return end
    table.insert(def.tooltip, 1, { kind = "rarity_badge", text = label, rarity = r })
end

for id, def in pairs(JOKER_DEFS) do
    if type(def.tooltip) ~= "table" then
        local lines = TOOLTIP_BY_ID[id]
        if lines then
            def.tooltip = build_structured_tooltip_lines(lines)
        elseif type(def.effect) == "string" then
            def.tooltip = build_structured_tooltip_lines({ def.effect })
        else
            def.tooltip = build_structured_tooltip_lines({ def.name or id })
        end
    else
        def.tooltip = build_structured_tooltip_lines(def.tooltip) or def.tooltip
    end

    if id == "j_loyalty_card" and type(def.tooltip) == "table" then
        for _, line in ipairs(def.tooltip) do
            if type(line) == "table" and type(line.text) == "string" and line.text:find("remaining", 1, true) then
                line.kind = "current"
            end
        end
    end

    prepend_rarity_tooltip_line(def)
end
