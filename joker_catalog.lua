-- Joker Catalog (data-driven definitions)
-- This file is meant to eventually contain the full 150-joker dataset.
-- For now, it includes the subset you pasted, normalized into an engine-friendly shape.
-- TODO: replace the current placeholder sprite atlas indices with the correct per-joker cell indices.

---@type table<string, table>
JOKER_DEFS = {
    -- j_joker
    j_joker = {
        id = "j_joker",
        name = "Joker",
        rarity = 1,
        sell_value = 2,
        effect = "Mult",
        config = { mult = 4 },
        pos = {
            atlas = "Joker1",
            index = 0
        }
    },

    -- j_greedy_joker
    j_greedy_joker = {
        id = "j_greedy_joker",
        name = "Greedy Joker",
        rarity = 1,
        sell_value = 5,
        effect = "Suit Mult",
        config = { extra = { s_mult = 3, suit = "Diamonds" } },
        pos = {
            atlas = "Joker1",
            index = 16
        }
    },

    -- j_lusty_joker
    j_lusty_joker = {
        id = "j_lusty_joker",
        name = "Lusty Joker",
        rarity = 1,
        sell_value = 5,
        effect = "Suit Mult",
        config = { extra = { s_mult = 3, suit = "Hearts" } },
        pos = {
            atlas = "Joker1",
            index = 17
        }
    },

    -- j_wrathful_joker
    j_wrathful_joker = {
        id = "j_wrathful_joker",
        name = "Wrathful Joker",
        rarity = 1,
        sell_value = 5,
        effect = "Suit Mult",
        config = { extra = { s_mult = 3, suit = "Spades" } },
        pos = {
            atlas = "Joker1",
            index = 18
        }
    },

    -- j_gluttenous_joker
    j_gluttenous_joker = {
        id = "j_gluttenous_joker",
        name = "Gluttonous Joker",
        rarity = 1,
        sell_value = 5,
        effect = "Suit Mult",
        config = { extra = { s_mult = 3, suit = "Clubs" } },
        pos = {
            atlas = "Joker1",
            index = 19
        }
    },

    -- j_jolly
    j_jolly = {
        id = "j_jolly",
        name = "Jolly Joker",
        rarity = 1,
        sell_value = 3,
        effect = "Type Mult",
        config = { t_mult = 8, type = "Pair" },
        pos = {
            atlas = "Joker1",
            index = 2
        }
    },

    -- j_zany
    j_zany = {
        id = "j_zany",
        name = "Zany Joker",
        rarity = 1,
        sell_value = 4,
        effect = "Type Mult",
        config = { t_mult = 12, type = "Three of a Kind" },
        pos = {
            atlas = "Joker1",
            index = 3
        }
    },

    -- j_mad
    j_mad = {
        id = "j_mad",
        name = "Mad Joker",
        rarity = 1,
        sell_value = 4,
        effect = "Type Mult",
        config = { t_mult = 10, type = "Two Pair" },
        pos = {
            atlas = "Joker1",
            index = 4
        }
    },

    -- j_crazy
    j_crazy = {
        id = "j_crazy",
        name = "Crazy Joker",
        rarity = 1,
        sell_value = 4,
        effect = "Type Mult",
        config = { t_mult = 12, type = "Straight" },
        pos = {
            atlas = "Joker1",
            index = 5
        }
    },

    -- j_droll
    j_droll = {
        id = "j_droll",
        name = "Droll Joker",
        rarity = 1,
        sell_value = 4,
        effect = "Type Mult",
        config = { t_mult = 10, type = "Flush" },
        pos = {
            atlas = "Joker1",
            index = 6
        }
    },

    j_sly = {
        id = "j_sly",
        name = "Sly Joker",
        rarity = 1,
        sell_value = 3,
        config = { t_chips = 50, type = "Pair" },
        pos = {
            atlas = "Joker2",
            index = 50
        }
    },

    j_wily = {
        id = "j_wily",
        name = "Wily Joker",
        rarity = 1,
        sell_value = 4,
        config = { t_chips = 100, type = "Three of a Kind" },
        pos = {
            atlas = "Joker2",
            index = 51
        }
    },

    j_clever = {
        id = "j_clever",
        name = "Clever Joker",
        rarity = 1,
        sell_value = 4,
        config = { t_chips = 80, type = "Two Pair" },
        pos = {
            atlas = "Joker2",
            index = 52
        }
    },

    j_devious = {
        id = "j_devious",
        name = "Devious Joker",
        rarity = 1,
        sell_value = 4,
        config = { t_chips = 100, type = "Straight" },
        pos = {
            atlas = "Joker2",
            index = 53
        }
    },

    j_crafty = {
        id = "j_crafty",
        name = "Crafty Joker",
        rarity = 1,
        sell_value = 4,
        config = { t_chips = 80, type = "Flush" },
        pos = {
            atlas = "Joker2",
            index = 54
        }
    },

    j_half = {
        id = "j_half",
        name = "Half Joker",
        rarity = 1,
        sell_value = 5,
        effect = "Hand Size Mult",
        config = { extra = { mult = 20, size = 3 } },
        pos = {
            atlas = "Joker1",
            index = 7
        }
    },

    j_stencil = {
        id = "j_stencil",
        name = "Joker Stencil",
        rarity = 2,
        sell_value = 8,
        effect = "Stencil Mult",
        config = {},
        pos = {
            atlas = "Joker1",
            index = 52
        }
    },

    j_four_fingers = {
        id = "j_four_fingers",
        name = "Four Fingers",
        rarity = 2,
        sell_value = 7,
        config = {},
        pos = {
            atlas = "Joker1",
            index = 66
        }
    },

    j_mime = {
        id = "j_mime",
        name = "Mime",
        rarity = 2,
        sell_value = 5,
        effect = "Hand card double",
        config = { extra = 1 },
        pos = {
            atlas = "Joker1",
            index = 14
        }
    },

    j_credit_card = {
        id = "j_credit_card",
        name = "Credit Card",
        rarity = 1,
        sell_value = 1,
        effect = "Credit",
        config = { extra = 20 },
        pos = {
            atlas = "Joker1",
            index = 15
        }
    },

    j_ceremonial = {
        id = "j_ceremonial",
        name = "Ceremonial Dagger",
        rarity = 2,
        sell_value = 6,
        config = { mult = 0 },
        pos = {
            atlas = "Joker1",
            index = 55
        }
    },

    j_banner = {
        id = "j_banner",
        name = "Banner",
        rarity = 1,
        sell_value = 5,
        effect = "Discard Chips",
        config = { extra = 30 },
        pos = {
            atlas = "Joker1",
            index = 21
        }
    },

    j_mystic_summit = {
        id = "j_mystic_summit",
        name = "Mystic Summit",
        rarity = 1,
        sell_value = 5,
        effect = "No Discard Mult",
        config = { extra = { mult = 15, d_remaining = 0 } },
        pos = {
            atlas = "Joker1",
            index = 22
        }
    },

    j_marble = {
        id = "j_marble",
        name = "Marble Joker",
        rarity = 2,
        sell_value = 6,
        effect = "Stone card hands",
        config = { extra = 1 },
        pos = {
            atlas = "Joker1",
            index = 23
        }
    },

    j_loyalty_card = {
        id = "j_loyalty_card",
        name = "Loyalty Card",
        rarity = 2,
        sell_value = 5,
        effect = "1 in 10 mult",
        config = { extra = { Xmult = 4, every = 5, remaining = "5 remaining" } },
        pos = {
            atlas = "Joker1",
            index = 24
        }
    },

    j_8_ball = {
        id = "j_8_ball",
        name = "8 Ball",
        rarity = 1,
        sell_value = 5,
        effect = "Spawn Tarot",
        config = { extra = 4 },
        pos = {
            atlas = "Joker1",
            index = 50
        }
    },

    j_misprint = {
        id = "j_misprint",
        name = "Misprint",
        rarity = 1,
        sell_value = 4,
        effect = "Random Mult",
        config = { extra = { max = 23, min = 0 } },
        pos = {
            atlas = "Joker1",
            index = 26
        }
    },

    j_dusk = {
        id = "j_dusk",
        name = "Dusk",
        rarity = 2,
        sell_value = 5,
        config = { extra = 1 },
        pos = {
            atlas = "Joker1",
            index = 74
        }
    },

    j_raised_fist = {
        id = "j_raised_fist",
        name = "Raised Fist",
        rarity = 1,
        sell_value = 5,
        effect = "Socialized Mult",
        config = {},
        pos = {
            atlas = "Joker1",
            index = 28
        }
    },

    j_chaos = {
        id = "j_chaos",
        name = "Chaos the Clown",
        rarity = 1,
        sell_value = 4,
        effect = "Bonus Rerolls",
        config = { extra = 1 },
        pos = {
            atlas = "Joker1",
            index = 1
        }
    },

    j_fibonacci = {
        id = "j_fibonacci",
        name = "Fibonacci",
        rarity = 2,
        sell_value = 8,
        effect = "Card Mult",
        config = { extra = 8 },
        pos = {
            atlas = "Joker1",
            index = 51
        }
    },

    j_steel_joker = {
        id = "j_steel_joker",
        name = "Steel Joker",
        rarity = 2,
        sell_value = 7,
        effect = "Steel Card Buff",
        config = { extra = 0.2 },
        pos = {
            atlas = "Joker1",
            index = 27
        }
    },

    j_scary_face = {
        id = "j_scary_face",
        name = "Scary Face",
        rarity = 1,
        sell_value = 4,
        effect = "Scary Face Cards",
        config = { extra = 30 },
        pos = {
            atlas = "Joker1",
            index = 32
        }
    },

    j_abstract = {
        id = "j_abstract",
        name = "Abstract Joker",
        rarity = 1,
        sell_value = 4,
        effect = "Joker Mult",
        config = { extra = 3 },
        pos = {
            atlas = "Joker1",
            index = 33
        }
    },

    j_delayed_grat = {
        id = "j_delayed_grat",
        name = "Delayed Gratification",
        rarity = 1,
        sell_value = 4,
        effect = "Discard dollars",
        config = { extra = 2 },
        pos = {
            atlas = "Joker1",
            index = 34
        }
    },

    j_hack = {
        id = "j_hack",
        name = "Hack",
        rarity = 2,
        sell_value = 6,
        effect = "Low Card double",
        config = { extra = 1 },
        pos = {
            atlas = "Joker1",
            index = 25
        }
    },

    j_pareidolia = {
        id = "j_pareidolia",
        name = "Pareidolia",
        rarity = 2,
        sell_value = 5,
        effect = "All face cards",
        config = {},
        pos = {
            atlas = "Joker1",
            index = 36
        }
    },

    j_gros_michel = {
        id = "j_gros_michel",
        name = "Gros Michel",
        rarity = 1,
        sell_value = 5,
        config = { extra = { odds = 6, mult = 15 } },
        pos = {
            atlas = "Joker1",
            index = 67
        }
    },

    j_even_steven = {
        id = "j_even_steven",
        name = "Even Steven",
        rarity = 1,
        sell_value = 4,
        effect = "Even Card Buff",
        config = { extra = 4 },
        pos = {
            atlas = "Joker1",
            index = 38
        }
    },

    j_odd_todd = {
        id = "j_odd_todd",
        name = "Odd Todd",
        rarity = 1,
        sell_value = 4,
        effect = "Odd Card Buff",
        config = { extra = 31 },
        pos = {
            atlas = "Joker1",
            index = 39
        }
    },

    j_scholar = {
        id = "j_scholar",
        name = "Scholar",
        rarity = 1,
        sell_value = 4,
        effect = "Ace Buff",
        config = { extra = { mult = 4, chips = 20 } },
        pos = {
            atlas = "Joker1",
            index = 40
        }
    },

    j_business = {
        id = "j_business",
        name = "Business Card",
        rarity = 1,
        sell_value = 4,
        effect = "Face Card dollar Chance",
        config = { extra = 2 },
        pos = {
            atlas = "Joker1",
            index = 41
        }
    },

    j_supernova = {
        id = "j_supernova",
        name = "Supernova",
        rarity = 1,
        sell_value = 5,
        effect = "Hand played mult",
        config = { extra = 1 },
        pos = {
            atlas = "Joker1",
            index = 42
        }
    },

    j_ride_the_bus = {
        id = "j_ride_the_bus",
        name = "Ride the Bus",
        rarity = 1,
        sell_value = 6,
        config = { extra = 1 },
        pos = {
            atlas = "Joker1",
            index = 61
        }
    },

    j_space = {
        id = "j_space",
        name = "Space Joker",
        rarity = 2,
        sell_value = 5,
        effect = "Upgrade Hand chance",
        config = { extra = 4 },
        pos = {
            atlas = "Joker1",
            index = 53
        }
    },

    j_egg = {
        id = "j_egg",
        name = "Egg",
        rarity = 1,
        sell_value = 4,
        config = { extra = 3 },
        pos = {
            atlas = "Joker2",
            index = 10
        }
    },

    j_burglar = {
        id = "j_burglar",
        name = "Burglar",
        rarity = 2,
        sell_value = 6,
        config = { extra = 3 },
        pos = {
            atlas = "Joker2",
            index = 11
        }
    },

    j_blackboard = {
        id = "j_blackboard",
        name = "Blackboard",
        rarity = 2,
        sell_value = 6,
        config = { extra = 3 },
        pos = {
            atlas = "Joker2",
            index = 12
        }
    },

    j_runner = {
        id = "j_runner",
        name = "Runner",
        rarity = 1,
        sell_value = 5,
        config = { extra = { chips = 0, chip_mod = 15 } },
        pos = {
            atlas = "Joker2",
            index = 13
        }
    },

    j_ice_cream = {
        id = "j_ice_cream",
        name = "Ice Cream",
        rarity = 1,
        sell_value = 5,
        config = { extra = { chips = 100, chip_mod = 5 } },
        pos = {
            atlas = "Joker2",
            index = 14
        }
    },

    j_dna = {
        id = "j_dna",
        name = "DNA",
        rarity = 3,
        sell_value = 8,
        config = {},
        pos = {
            atlas = "Joker2",
            index = 15
        }
    },

    j_splash = {
        id = "j_splash",
        name = "Splash",
        rarity = 1,
        sell_value = 3,
        config = {},
        pos = {
            atlas = "Joker2",
            index = 16
        }
    },

    j_blue_joker = {
        id = "j_blue_joker",
        name = "Blue Joker",
        rarity = 1,
        sell_value = 5,
        config = { extra = 2 },
        pos = {
            atlas = "Joker2",
            index = 17
        }
    },

    j_sixth_sense = {
        id = "j_sixth_sense",
        name = "Sixth Sense",
        rarity = 2,
        sell_value = 6,
        config = {},
        pos = {
            atlas = "Joker2",
            index = 18
        }
    },

    j_constellation = {
        id = "j_constellation",
        name = "Constellation",
        rarity = 2,
        sell_value = 6,
        config = { extra = 0.1, Xmult = 1 },
        pos = {
            atlas = "Joker2",
            index = 19
        }
    },

    j_hiker = {
        id = "j_hiker",
        name = "Hiker",
        rarity = 2,
        sell_value = 5,
        config = { extra = 5 },
        pos = {
            atlas = "Joker2",
            index = 20
        }
    },

    j_faceless = {
        id = "j_faceless",
        name = "Faceless Joker",
        rarity = 1,
        sell_value = 4,
        config = { extra = { dollars = 5, faces = 3 } },
        pos = {
            atlas = "Joker2",
            index = 21
        }
    },

    j_green_joker = {
        id = "j_green_joker",
        name = "Green Joker",
        rarity = 1,
        sell_value = 4,
        config = { extra = { hand_add = 1, discard_sub = 1 } },
        pos = {
            atlas = "Joker2",
            index = 22
        }
    },

    j_superposition = {
        id = "j_superposition",
        name = "Superposition",
        rarity = 1,
        sell_value = 4,
        config = {},
        pos = {
            atlas = "Joker2",
            index = 23
        }
    },

    j_todo_list = {
        id = "j_todo_list",
        name = "To Do List",
        rarity = 1,
        sell_value = 4,
        config = { extra = { dollars = 4, poker_hand = "High Card" } },
        pos = {
            atlas = "Joker2",
            index = 24
        }
    },

    j_cavendish = {
        id = "j_cavendish",
        name = "Cavendish",
        rarity = 1,
        sell_value = 4,
        config = { extra = { odds = 1000, Xmult = 3 } },
        pos = {
            atlas = "Joker2",
            index = 25
        }
    },

    j_card_sharp = {
        id = "j_card_sharp",
        name = "Card Sharp",
        rarity = 2,
        sell_value = 6,
        config = { extra = { Xmult = 3 } },
        pos = {
            atlas = "Joker2",
            index = 26
        }
    },

    j_red_card = {
        id = "j_red_card",
        name = "Red Card",
        rarity = 1,
        sell_value = 5,
        config = { extra = 3 },
        pos = {
            atlas = "Joker2",
            index = 27
        }
    },

    j_madness = {
        id = "j_madness",
        name = "Madness",
        rarity = 2,
        sell_value = 7,
        config = { extra = 0.5 },
        pos = {
            atlas = "Joker2",
            index = 28
        }
    },

    j_square = {
        id = "j_square",
        name = "Square Joker",
        rarity = 1,
        sell_value = 4,
        config = { extra = { chips = 0, chip_mod = 4 } },
        pos = {
            atlas = "Joker2",
            index = 29
        }
    },

    j_seance = {
        id = "j_seance",
        name = "Seance",
        rarity = 2,
        sell_value = 6,
        config = { extra = { poker_hand = "Straight Flush" } },
        pos = {
            atlas = "Joker2",
            index = 30
        }
    },

    j_riff_raff = {
        id = "j_riff_raff",
        name = "Riff-raff",
        rarity = 1,
        sell_value = 6,
        config = { extra = 2 },
        pos = {
            atlas = "Joker2",
            index = 31
        }
    },

    j_vampire = {
        id = "j_vampire",
        name = "Vampire",
        rarity = 2,
        sell_value = 7,
        config = { extra = 0.1, Xmult = 1 },
        pos = {
            atlas = "Joker2",
            index = 32
        }
    },

    j_shortcut = {
        id = "j_shortcut",
        name = "Shortcut",
        rarity = 2,
        sell_value = 7,
        config = {},
        pos = {
            atlas = "Joker2",
            index = 33
        }
    },

    j_hologram = {
        id = "j_hologram",
        name = "Hologram",
        rarity = 2,
        sell_value = 7,
        config = { extra = 0.25, Xmult = 1 },
        pos = {
            atlas = "Joker2",
            index = 34
        }
    },

    j_vagabond = {
        id = "j_vagabond",
        name = "Vagabond",
        rarity = 3,
        sell_value = 8,
        config = { extra = 4 },
        pos = {
            atlas = "Joker2",
            index = 35
        }
    },

    j_baron = {
        id = "j_baron",
        name = "Baron",
        rarity = 3,
        sell_value = 8,
        config = { extra = 1.5 },
        pos = {
            atlas = "Joker2",
            index = 36
        }
    },

    j_cloud_9 = {
        id = "j_cloud_9",
        name = "Cloud 9",
        rarity = 2,
        sell_value = 7,
        config = { extra = 1 },
        pos = {
            atlas = "Joker2",
            index = 37
        }
    },

    j_rocket = {
        id = "j_rocket",
        name = "Rocket",
        rarity = 2,
        sell_value = 6,
        config = { extra = { dollars = 1, increase = 2 } },
        pos = {
            atlas = "Joker2",
            index = 38
        }
    },

    j_obelisk = {
        id = "j_obelisk",
        name = "Obelisk",
        rarity = 3,
        sell_value = 8,
        config = { extra = 0.2, Xmult = 1 },
        pos = {
            atlas = "Joker2",
            index = 39
        }
    },

    j_midas_mask = {
        id = "j_midas_mask",
        name = "Midas Mask",
        rarity = 2,
        sell_value = 7,
        config = {},
        pos = {
            atlas = "Joker2",
            index = 40
        }
    },

    j_luchador = {
        id = "j_luchador",
        name = "Luchador",
        rarity = 2,
        sell_value = 5,
        config = {},
        pos = {
            atlas = "Joker2",
            index = 41
        }
    },

    j_photograph = {
        id = "j_photograph",
        name = "Photograph",
        rarity = 1,
        sell_value = 5,
        config = { extra = 2 },
        pos = {
            atlas = "Joker2",
            index = 42
        }
    },

    j_gift = {
        id = "j_gift",
        name = "Gift Card",
        rarity = 2,
        sell_value = 6,
        config = { extra = 1 },
        pos = {
            atlas = "Joker2",
            index = 43
        }
    },

    j_turtle_bean = {
        id = "j_turtle_bean",
        name = "Turtle Bean",
        rarity = 2,
        sell_value = 6,
        config = { extra = { h_size = 5, h_mod = 1 } },
        pos = {
            atlas = "Joker2",
            index = 44
        }
    },

    j_erosion = {
        id = "j_erosion",
        name = "Erosion",
        rarity = 2,
        sell_value = 6,
        config = { extra = 4 },
        pos = {
            atlas = "Joker2",
            index = 45
        }
    },

    j_reserved_parking = {
        id = "j_reserved_parking",
        name = "Reserved Parking",
        rarity = 1,
        sell_value = 6,
        config = { extra = { odds = 2, dollars = 1 } },
        pos = {
            atlas = "Joker2",
            index = 46
        }
    },

    j_mail = {
        id = "j_mail",
        name = "Mail-In Rebate",
        rarity = 1,
        sell_value = 4,
        config = { extra = 5 },
        pos = {
            atlas = "Joker2",
            index = 47
        }
    },

    j_to_the_moon = {
        id = "j_to_the_moon",
        name = "To the Moon",
        rarity = 2,
        sell_value = 5,
        config = { extra = 1 },
        pos = {
            atlas = "Joker2",
            index = 48
        }
    },

    j_hallucination = {
        id = "j_hallucination",
        name = "Hallucination",
        rarity = 1,
        sell_value = 4,
        config = { extra = 2 },
        pos = {
            atlas = "Joker2",
            index = 49
        }
    },

    j_ticket = {
        id = "j_ticket",
        name = "Golden Ticket",
        rarity = 1,
        sell_value = 5,
        effect = "dollars for Gold cards",
        config = { extra = 4 },
        pos = {
            atlas = "Joker1",
            index = 33
        }
    },

    j_mr_bones = {
        id = "j_mr_bones",
        name = "Mr. Bones",
        rarity = 2,
        sell_value = 5,
        effect = "Prevent Death",
        config = {},
        pos = {
            atlas = "Joker1",
            index = 43
        }
    },

    j_acrobat = {
        id = "j_acrobat",
        name = "Acrobat",
        rarity = 2,
        sell_value = 6,
        effect = "Shop size",
        config = { extra = 3 },
        pos = {
            atlas = "Joker1",
            index = 12
        }
    },

    j_sock_and_buskin = {
        id = "j_sock_and_buskin",
        name = "Sock and Buskin",
        rarity = 2,
        sell_value = 6,
        effect = "Face card double",
        config = { extra = 1 },
        pos = {
            atlas = "Joker1",
            index = 13
        }
    },

    j_swashbuckler = {
        id = "j_swashbuckler",
        name = "Swashbuckler",
        rarity = 1,
        sell_value = 4,
        effect = "Set Mult",
        config = { mult = 1 },
        pos = {
            atlas = "Joker1",
            index = 59
        }
    },

    j_troubadour = {
        id = "j_troubadour",
        name = "Troubadour",
        rarity = 2,
        sell_value = 6,
        effect = "Hand Size, Plays",
        config = { extra = { h_size = 2, h_plays = -1 } },
        pos = {
            atlas = "Joker1",
            index = 20
        }
    },

    j_certificate = {
        id = "j_certificate",
        name = "Certificate",
        rarity = 2,
        sell_value = 6,
        config = {},
        pos = {
            atlas = "Joker1",
            index = 88
        }
    },

    j_smeared = {
        id = "j_smeared",
        name = "Smeared Joker",
        rarity = 2,
        sell_value = 7,
        config = {},
        pos = {
            atlas = "Joker1",
            index = 64
        }
    },

    j_throwback = {
        id = "j_throwback",
        name = "Throwback",
        rarity = 2,
        sell_value = 6,
        config = { extra = 0.25 },
        pos = {
            atlas = "Joker1",
            index = 75
        }
    },

    j_hanging_chad = {
        id = "j_hanging_chad",
        name = "Hanging Chad",
        rarity = 1,
        sell_value = 4,
        config = { extra = 2 },
        pos = {
            atlas = "Joker1",
            index = 69
        }
    },

    j_rough_gem = {
        id = "j_rough_gem",
        name = "Rough Gem",
        rarity = 2,
        sell_value = 7,
        config = { extra = 1 },
        pos = {
            atlas = "Joker1",
            index = 79
        }
    },

    j_bloodstone = {
        id = "j_bloodstone",
        name = "Bloodstone",
        rarity = 2,
        sell_value = 7,
        config = { extra = { odds = 2, Xmult = 1.5 } },
        pos = {
            atlas = "Joker1",
            index = 80
        }
    },

    j_arrowhead = {
        id = "j_arrowhead",
        name = "Arrowhead",
        rarity = 2,
        sell_value = 7,
        config = { extra = 50 },
        pos = {
            atlas = "Joker1",
            index = 81
        }
    },

    j_onyx_agate = {
        id = "j_onyx_agate",
        name = "Onyx Agate",
        rarity = 2,
        sell_value = 7,
        config = { extra = 7 },
        pos = {
            atlas = "Joker1",
            index = 82
        }
    },

    j_glass = {
        id = "j_glass",
        name = "Glass Joker",
        rarity = 2,
        sell_value = 6,
        effect = "Glass Card",
        config = { extra = 0.75, Xmult = 1 },
        pos = {
            atlas = "Joker1",
            index = 31
        }
    },

    j_ring_master = {
        id = "j_ring_master",
        name = "Showman",
        rarity = 2,
        sell_value = 5,
        config = {},
        pos = {
            atlas = "Joker1",
            index = 56
        }
    },

    j_flower_pot = {
        id = "j_flower_pot",
        name = "Flower Pot",
        rarity = 2,
        sell_value = 6,
        config = { extra = 3 },
        pos = {
            atlas = "Joker1",
            index = 60
        }
    },

    j_blueprint = {
        id = "j_blueprint",
        name = "Blueprint",
        rarity = 3,
        sell_value = 10,
        effect = "Copycat",
        config = {},
        pos = {
            atlas = "Joker1",
            index = 30
        }
    },

    j_wee = {
        id = "j_wee",
        name = "Wee Joker",
        rarity = 3,
        sell_value = 8,
        config = { extra = { chips = 0, chip_mod = 8 } },
        pos = {
            atlas = "Joker1",
            index = 0
        }
    },

    j_merry_andy = {
        id = "j_merry_andy",
        name = "Merry Andy",
        rarity = 2,
        sell_value = 7,
        config = { d_size = 3, h_size = -1 },
        pos = {
            atlas = "Joker1",
            index = 8
        }
    },

    j_oops = {
        id = "j_oops",
        name = "Oops! All 6s",
        rarity = 2,
        sell_value = 4,
        config = {},
        pos = {
            atlas = "Joker1",
            index = 65
        }
    },

    j_idol = {
        id = "j_idol",
        name = "The Idol",
        rarity = 2,
        sell_value = 6,
        config = { extra = 2 },
        pos = {
            atlas = "Joker1",
            index = 76
        }
    },

    j_seeing_double = {
        id = "j_seeing_double",
        name = "Seeing Double",
        rarity = 2,
        sell_value = 6,
        effect = "X1.5 Mult club 7",
        config = { extra = 2 },
        pos = {
            atlas = "Joker1",
            index = 44
        }
    },

    j_matador = {
        id = "j_matador",
        name = "Matador",
        rarity = 2,
        sell_value = 7,
        config = { extra = 8 },
        pos = {
            atlas = "Joker1",
            index = 54
        }
    },

    j_hit_the_road = {
        id = "j_hit_the_road",
        name = "Hit the Road",
        rarity = 3,
        sell_value = 8,
        effect = "Jack Discard Effect",
        config = { extra = 0.5 },
        pos = {
            atlas = "Joker1",
            index = 58
        }
    },

    j_duo = {
        id = "j_duo",
        name = "The Duo",
        rarity = 3,
        sell_value = 8,
        effect = "X1.5 Mult",
        config = { Xmult = 2, type = "Pair" },
        pos = {
            atlas = "Joker1",
            index = 45
        }
    },

    j_trio = {
        id = "j_trio",
        name = "The Trio",
        rarity = 3,
        sell_value = 8,
        effect = "X2 Mult",
        config = { Xmult = 3, type = "Three of a Kind" },
        pos = {
            atlas = "Joker1",
            index = 46
        }
    },

    j_family = {
        id = "j_family",
        name = "The Family",
        rarity = 3,
        sell_value = 8,
        effect = "X3 Mult",
        config = { Xmult = 4, type = "Four of a Kind" },
        pos = {
            atlas = "Joker1",
            index = 47
        }
    },

    j_order = {
        id = "j_order",
        name = "The Order",
        rarity = 3,
        sell_value = 8,
        effect = "X3 Mult",
        config = { Xmult = 3, type = "Straight" },
        pos = {
            atlas = "Joker1",
            index = 48
        }
    },

    j_tribe = {
        id = "j_tribe",
        name = "The Tribe",
        rarity = 3,
        sell_value = 8,
        effect = "X3 Mult",
        config = { Xmult = 2, type = "Flush" },
        pos = {
            atlas = "Joker1",
            index = 49
        }
    },

    j_stuntman = {
        id = "j_stuntman",
        name = "Stuntman",
        rarity = 3,
        sell_value = 7,
        config = { extra = { h_size = 2, chip_mod = 250 } },
        pos = {
            atlas = "Joker1",
            index = 68
        }
    },

    j_invisible = {
        id = "j_invisible",
        name = "Invisible Joker",
        rarity = 3,
        sell_value = 8,
        config = { extra = 2 },
        pos = {
            atlas = "Joker1",
            index = 71
        }
    },

    j_brainstorm = {
        id = "j_brainstorm",
        name = "Brainstorm",
        rarity = 3,
        sell_value = 10,
        effect = "Copycat",
        config = {},
        pos = {
            atlas = "Joker1",
            index = 77
        }
    },

    j_satellite = {
        id = "j_satellite",
        name = "Satellite",
        rarity = 2,
        sell_value = 6,
        config = { extra = 1 },
        pos = {
            atlas = "Joker1",
            index = 78
        }
    },

    j_shoot_the_moon = {
        id = "j_shoot_the_moon",
        name = "Shoot the Moon",
        rarity = 1,
        sell_value = 5,
        config = { extra = 13 },
        pos = {
            atlas = "Joker1",
            index = 62
        }
    },

    j_drivers_license = {
        id = "j_drivers_license",
        name = "Driver's License",
        rarity = 3,
        sell_value = 7,
        config = { extra = 3 },
        pos = {
            atlas = "Joker1",
            index = 70
        }
    },

    j_cartomancer = {
        id = "j_cartomancer",
        name = "Cartomancer",
        rarity = 2,
        sell_value = 6,
        effect = "Tarot Buff",
        config = {},
        pos = {
            atlas = "Joker1",
            index = 37
        }
    },

    j_astronomer = {
        id = "j_astronomer",
        name = "Astronomer",
        rarity = 2,
        sell_value = 8,
        config = {},
        pos = {
            atlas = "Joker1",
            index = 72
        }
    },

    j_burnt = {
        id = "j_burnt",
        name = "Burnt Joker",
        rarity = 3,
        sell_value = 8,
        config = { h_size = 0, extra = 4 },
        pos = {
            atlas = "Joker1",
            index = 73
        }
    },

    j_bootstraps = {
        id = "j_bootstraps",
        name = "Bootstraps",
        rarity = 2,
        sell_value = 7,
        config = { extra = { mult = 2, dollars = 5 } },
        pos = {
            atlas = "Joker1",
            index = 89
        }
    },

    j_caino = {
        id = "j_caino",
        name = "Caino",
        rarity = 4,
        sell_value = 20,
        config = { extra = 1 },
        pos = {
            atlas = "Joker1",
            index = 83
        }
    },

    j_triboulet = {
        id = "j_triboulet",
        name = "Triboulet",
        rarity = 4,
        sell_value = 20,
        config = { extra = 2 },
        pos = {
            atlas = "Joker1",
            index = 84
        }
    },

    j_yorick = {
        id = "j_yorick",
        name = "Yorick",
        rarity = 4,
        sell_value = 20,
        config = { extra = { xmult = 1, discards = 23 } },
        pos = {
            atlas = "Joker1",
            index = 85
        }
    },

    j_chicot = {
        id = "j_chicot",
        name = "Chicot",
        rarity = 4,
        sell_value = 20,
        config = {},
        pos = {
            atlas = "Joker1",
            index = 86
        }
    },

    j_perkeo = {
        id = "j_perkeo",
        name = "Perkeo",
        rarity = 4,
        sell_value = 20,
        config = {},
        pos = {
            atlas = "Joker1",
            index = 87
        }
    },

}

