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
}

