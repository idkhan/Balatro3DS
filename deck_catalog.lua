
DECK_DEFS = {
    {
        id = "b_red",
        name = "Red Deck",
        order = 1,
        pos = 0,
        unlocked = true,
        stake = 1,
        config = { discards = 1 },
        description = "+1 Discard every round",
    },
    {
        id = "b_blue",
        name = "Blue Deck",
        order = 2,
        pos = 14,
        unlocked = false,
        stake = 1,
        unlock_condition = { type = "discover_amount", amount = 20, text = "Discover 20 Cards" },
        config = { hands = 1 },
        description = "+1 Hand every round",
    },
    {
        id = "b_yellow",
        name = "Yellow Deck",
        order = 3,
        pos = 15,
        unlocked = false,
        stake = 1,
        unlock_condition = { type = "discover_amount", amount = 50, text = "Discover 50 Cards" },
        config = { dollars = 10 },
        description = "Start with $10",
    },
    {
        id = "b_green",
        name = "Green Deck",
        order = 4,
        pos = 16,
        unlocked = false,
        stake = 1,
        unlock_condition = { type = "discover_amount", amount = 75, text = "Discover 75 Cards" },
        config = { extra_hand_bonus = 2, extra_discard_bonus = 1, no_interest = true },
        description = "+$2 per remaining Hand, +$1 per remaining Discard. No interest earned.",
    },
    {
        id = "b_black",
        name = "Black Deck",
        order = 5,
        pos = 17,
        unlocked = false,
        stake = 1,
        unlock_condition = { type = "discover_amount", amount = 100, text = "Discover 100 Cards" },
        config = { joker_slots = 1, hands = -1 },
        description = "+1 Joker slot. -1 Hand per round.",
    },
    {
        id = "b_magic",
        name = "Magic Deck",
        order = 6,
        pos = 21,
        unlocked = false,
        stake = 1,
        unlock_condition = { type = "deck_win", deck_id = "b_red", text = "Win a run with the Red Deck on any difficulty"},
        config = { },
        description = "Start with Crystal Ball and 2 copies of The Fool",
        start_vouchers = { "v_crystal_ball" },
        start_consumables = { "tarot_fool", "tarot_fool" }
    },
    {
        id = "b_nebula",
        name = "Nebula Deck",
        order = 7,
        pos = 3,
        unlocked = false,
        stake = 1,
        unlock_condition = { type = "deck_win", deck_id = "b_blue", text = "Win a run with the Blue Deck on any difficulty" },
        config = { consumable_slots = -1 },
        description = "-1 Consumable slot. Start run with the Telescope voucher ",
        start_vouchers = { "v_telescope" }
    },
    {
        id = "b_ghost",
        name = "Ghost Deck",
        order = 8,
        pos = 20,
        unlocked = false,
        stake = 1,
        unlock_condition = { type = "deck_win", deck_id = "b_yellow", text = "Win a run with the Yellow Deck on any difficulty" },
        config = { spectral_rate = 2 },
        description = "Spectral cards may appear in the shop. Start with a Hex card.",
        start_consumables = { "spectral_hex" }
    },
    {
        id = "b_abandoned",
        name = "Abandoned Deck",
        order = 9,
        pos = 24,
        unlocked = false,
        stake = 1,
        unlock_condition = { type = "deck_win", deck_id = "b_green", text = "Win a run with the Green Deck on any difficulty" },
        config = { no_face_cards = true },
        description = "Start run with no Face Cards in your deck ",
    },
    {
        id = "b_checkered",
        name = "Checkered Deck",
        order = 10,
        pos = 22,
        unlocked = false,
        stake = 1,
        unlock_condition = { type = "deck_win", deck_id = "b_black", text = "Win a run with the Black Deck on any difficulty" },
        config = { suit_split = { "Spades", "Hearts" } },
        description = "Start run with 26 Spades and 26 Hearts in deck ",
    },
    {
        id = "b_zodiac",
        name = "Zodiac Deck",
        order = 11,
        pos = 31,
        unlocked = false,
        stake = 1,
        unlock_condition = { type = "deck_win", stake_id = "stake_red", text = "Win a run with any deck on the Red Stake difficulty" },
        config = {},
        description = "Start run with Tarot Merchant, Planet Merchant, and Overstock",
        start_vouchers = { "v_tarot_merchant", "v_planet_merchant", "v_overstock" },
    },
    {
        id = "b_painted",
        name = "Painted Deck",
        order = 12,
        pos = 25,
        unlocked = false,
        stake = 1,
        unlock_condition = { type = "deck_win", stake_id = "stake_green", text = "Win a run with any deck on the Green Stake difficulty" },
        config = { hand_size = 2, joker_slots = -1 },
        description = "+2 Hand size. -1 Joker slot.",
    },
    {
        id = "b_anaglyph",
        name = "Anaglyph Deck",
        order = 13,
        pos = 30,
        unlocked = false,
        stake = 1,
        unlock_condition = { type = "deck_win", stake_id = "stake_black", text = "Win a run with any deck on the Black Stake difficulty" },
        config = {},
        description = "After defeating each Boss Blind, gain a Double Tag.",
        special = "anaglyph",
    },
    {
        id = "b_plasma",
        name = "Plasma Deck",
        order = 14,
        pos = 18,
        unlocked = false,
        stake = 1,
        unlock_condition = { type = "deck_win", stake_id = "stake_blue", text = "Win a run with any deck on the Blue Stake difficulty"},
        config = {},
        description = "Balance Chips and Mult when scoring. x2 Base Blind Size.",
        special = "plasma",
    },
    {
        id = "b_erratic",
        name = "Erratic Deck",
        order = 15,
        pos = 23,
        unlocked = false,
        stake = 1,
        unlock_condition = { type = "deck_win", stake_id = "stake_orange", text = "Win a run with any deck on the Orange Stake difficulty" },
        config = {},
        description = "All card Ranks and Suits in deck are randomised.",
        special = "erratic",
    },
    {
        -- Challenge runs choose their cards from challenge_catalog.lua; this Back
        -- only supplies the reference Challenge Deck card back (game.lua:644).
        id = "b_challenge",
        name = "Challenge Deck",
        order = 16,
        pos = 32,
        unlocked = true,
        stake = 1,
        config = {},
        description = "Used by Challenge runs.",
        omit = true,
    },
}

DECK_DEFS_BY_ID = {}
DECK_SELECT_DEFS = {}
for _, d in ipairs(DECK_DEFS) do
    DECK_DEFS_BY_ID[d.id] = d
    if d.omit ~= true then DECK_SELECT_DEFS[#DECK_SELECT_DEFS + 1] = d end
end

STAKE_DEFS = {
    {
        id = "stake_white",
        name = "White Stake",
        order = 1,
        pos = 0,
        unlocked = true,
        colour = { 1, 1, 1, 1 },
        config = { ante_mult = 0 },
        description = "No modifiers.",
    },
    {
        id = "stake_red",
        name = "Red Stake",
        order = 2,
        pos = 1,
        unlocked = false,
        colour = { 0.996, 0.373, 0.333, 1 },
        config = { ante_mult = 0, no_small_reward = true },  -- effectively 1x (base)
        description = "Small Blind gives no reward money",
    },
    {
        id = "stake_green",
        name = "Green Stake",
        order = 3,
        pos = 2,
        unlocked = false,
        colour = { 0.294, 0.761, 0.573, 1 },
        config = { ante_mult = 1, no_small_reward = true},
        description = "Required score scales faster for each Ante",
    },
    {
        id = "stake_black",
        name = "Black Stake",
        order = 4,
        pos = 4,
        unlocked = false,
        colour = { 0, 0, 0, 1 },
        config = { ante_mult = 1, no_small_reward = true, eternal_jokers = true },
        description = "30% chance for Jokers in shops or booster packs to have an Eternal sticker",
    },
    {
        id = "stake_blue",
        name = "Blue Stake",
        order = 5,
        pos = 3,
        unlocked = false,
        colour = { 0, 0.616, 1, 1 },
        config = { 
            ante_mult = 1, 
            no_small_reward = true,
            eternal_jokers = true,
            stake_discard = -1 
        },
        description = "-1 Discard",
    },
    {
        id = "stake_purple",
        name = "Purple Stake",
        order = 6,
        pos = 5,
        unlocked = false,
        colour = { 0.533, 0.404, 0.647, 1 },
        config = {
            ante_mult = 2,
            no_small_reward = true,
            eternal_jokers = true,
            stake_discard = -1 
        },
        description = "Required score scales even faster for each Ante",
    },
    {
        id = "stake_orange",
        name = "Orange Stake",
        order = 7,
        pos = 6,
        unlocked = false,
        colour = { 0.992, 0.635, 0, 1 },
        config = {
            ante_mult = 2,
            no_small_reward = true,
            eternal_jokers = true,
            stake_discard = -1,
            perishable_jokers = true
        },
        description = "30% chance for Jokers in shops or booster packs to have a Perishable sticker",
    },
    {
        id = "stake_gold",
        name = "Gold Stake",
        order = 8,
        pos = 7,
        unlocked = false,
        colour = { 0.918, 0.753, 0.345, 1 },
        config = {
            ante_mult = 2,
            no_small_reward = true,
            eternal_jokers = true,
            stake_discard = -1,
            perishable_jokers = true,
            rental_jokers = true
        },
        description = "30% chance for Jokers in shops or booster packs to have a Rental sticker",
    },
}

STAKE_DEFS_BY_ID = {}
for _, s in ipairs(STAKE_DEFS) do
    STAKE_DEFS_BY_ID[s.id] = s
end

function Game:apply_deck_config(deck_id)
    local def = DECK_DEFS_BY_ID[deck_id or "b_red"]
    if not def then def = DECK_DEFS[1] end

    self.selected_deck_id = def.id
    local cfg = def.config or {}

    self.deck_hands = (tonumber(cfg.hands) or 0)
    self.deck_discards = (tonumber(cfg.discards) or 0)


    if (tonumber(cfg.dollars) or 0) ~= 0 then
        self.money = math.max(0, (tonumber(self.money) or 0) + (tonumber(cfg.dollars) or 0))
    end

    if (tonumber(cfg.extra_hand_bonus) or 0) ~= 0 then
        self.extra_hand_bonus = (tonumber(cfg.extra_hand_bonus) or 0)
    end

    if (tonumber(cfg.extra_discard_bonus) or 0) ~= 0 then
        self.extra_discard_bonus = (tonumber(cfg.extra_discard_bonus) or 0)
    end

    if (tonumber(cfg.hand_size) or 0) ~= 0 then
        self.deck_hand_size = (tonumber(cfg.hand_size) or 0)
    end

    if (tonumber(cfg.consumable_slots) or 0) ~= 0 then
        self.deck_consumable_slots = (tonumber(cfg.consumable_slots) or 0)
    end

    if cfg.no_interest then
        self._deck_no_interest = true
    end

    if (tonumber(cfg.joker_slots) or 0) ~= 0 then
        self.deck_joker_slots = (tonumber(cfg.joker_slots) or 0)
        self:refresh_joker_capacity_from_negatives()
    end

    if (tonumber(cfg.spectral_rate) or 0) ~= 0 then
        self.deck_spectral_rate = (tonumber(cfg.spectral_rate) or 0)
    end

    if def.special == "erratic" then
        self:_apply_erratic_deck()
    elseif cfg.no_face_cards then
        self:_apply_no_face_cards()
    elseif cfg.suit_filter then
        self:_apply_suit_filter(cfg.suit_filter)
    elseif cfg.suit_split then
        self:_apply_suit_split(cfg.suit_split)
    end

    if def.start_consumables and type(def.start_consumables) == "table" then
        for _, cid in ipairs(def.start_consumables) do
            self:_give_start_consumable(cid)
        end
    end

    if def.start_vouchers and type(def.start_vouchers) == "table" then
        for _, vid in ipairs(def.start_vouchers) do
            if not self:has_voucher(vid) then
                table.insert(self.vouchers, vid)
                self:apply_voucher_effect(vid)
            end
        end
    end

    self._deck_special = def.special or nil
    if self.refresh_playing_card_backs then
        self:refresh_playing_card_backs()
    end
end

--- Atlas cell index for a deck's playing-card back (`DECK_DEFS.pos` in `centers`).
---@param id string|nil deck id; nil falls back to the run's deck, then the pending one
---@return integer
function Game:get_deck_back_index(id)
    id = id or self.selected_deck_id or self._pending_deck_id or "b_red"
    local def = DECK_DEFS_BY_ID and DECK_DEFS_BY_ID[id]
    if not def and DECK_DEFS then
        def = DECK_DEFS[1]
    end
    return tonumber(def and def.pos) or 0
end

--- The back every playing card in the current run wears.
---@return integer
function Game:get_selected_deck_back_index()
    return self:get_deck_back_index(nil)
end

function Game:refresh_playing_card_backs()
    for _, node in ipairs(self.nodes or {}) do
        if node and node.card_data and node.refresh_quads then
            node:refresh_quads()
        end
    end
end

function Game:apply_stake_config(stake_id)
    local def = STAKE_DEFS_BY_ID[stake_id or "stake_white"]
    if not def then def = STAKE_DEFS[1] end

    self.selected_stake_id    = def.id
    self.selected_stake_order = def.order
    local cfg = def.config or {}

    -- Green/Purple select their alternate ante tables (reference game.lua:2049-2057).
    self._stake_ante_mult = tonumber(cfg.ante_mult) or 0
    self._stake_no_small_reward = cfg.no_small_reward or false -- Red
    self._stake_eternal_jokers = cfg.eternal_jokers or false -- Black
    self._stake_discard = cfg.stake_discard or 0 -- Blue
    self._stake_perishable_jokers = cfg.perishable_jokers or false -- Orange
    self._stake_rental_jokers = cfg.rental_jokers or false -- Gold
    print("Stake Config Applied:", def.id)
    print("Stake Config:", self._stake_no_small_reward, self._stake_eternal_jokers, self._stake_discard, self._stake_perishable_jokers, self._stake_rental_jokers)
end

function Game:_apply_erratic_deck()
    if not self.deck then return end
    local suits = { "Hearts", "Clubs", "Diamonds", "Spades" }
    for _, c in ipairs(self.deck.cards or {}) do
        c.rank  = self:random("erratic", 2, 14)
        c.suit  = suits[self:random("erratic", 1, 4)]
    end
end

function Game:_apply_no_face_cards()
    if not self.deck then return end
    local kept = {}
    for _, c in ipairs(self.deck.cards or {}) do
        if not (c.rank >= 11 and c.rank <= 13) then
            table.insert(kept, c)
        end
    end
    self.deck.cards = kept
end

function Game:_apply_suit_filter(suit)
    if not self.deck then return end
    local kept = {}
    for _, c in ipairs(self.deck.cards or {}) do
        if c.suit == suit then
            table.insert(kept, c)
        end
    end
    self.deck.cards = kept
end

function Game:_apply_suit_split(suits)
    if not self.deck or type(suits) ~= "table" or #suits < 2 then return end
    local new_cards = {}
    for _, suit in ipairs(suits) do
        for r = 2, 14 do
            for _ = 1, 2 do
                table.insert(new_cards, { rank = r, suit = suit, enhancement = nil, seal = nil })
            end
        end
    end
    self.deck.cards = new_cards
end

function Game:_give_start_consumable(cid)
    self:add_consumable(cid)
end

function Game:draw_deck_select_ui()
    local W, H = 320, 240
    local font_s = self.FONTS.PIXEL.SMALL
    local font_m = self.FONTS.PIXEL.MEDIUM

    love.graphics.setColor(self.C.BLOCK.BACK)
    love.graphics.rectangle("fill", 0, 0, W, H)

    love.graphics.setFont(font_m)
    love.graphics.setColor(self.C.WHITE)
    love.graphics.printf("Choose Deck", 0, 8, W, "center")

    local deck_list = DECK_SELECT_DEFS or DECK_DEFS or {}
    local sel_idx   = tonumber(self._deck_select_idx) or 1
    local view_size = 5
    local scroll    = math.max(0, sel_idx - math.ceil(view_size / 2))
    scroll = math.min(scroll, math.max(0, #deck_list - view_size))

    local item_h = 28
    local list_x = 10
    local list_y = 36
    local list_w = W - 20

    self._deck_select_rects = self._deck_select_rects or {}
    self._deck_select_rects = {}

    for i = 1, view_size do
        local idx = scroll + i
        local def = deck_list[idx]
        if not def then break end

        local iy = list_y + (i - 1) * item_h
        local selected = (idx == sel_idx)
        local locked   = not def.unlocked

        if selected then
            love.graphics.setColor(self.C.BLUE[1], self.C.BLUE[2], self.C.BLUE[3], 0.8)
        else
            love.graphics.setColor(self.C.BLOCK.SHADOW)
        end
        love.graphics.rectangle("fill", list_x, iy, list_w, item_h - 2, 4, 4)

        if locked then
            love.graphics.setColor(self.C.GREY)
        elseif selected then
            love.graphics.setColor(self.C.WHITE)
        else
            love.graphics.setColor(self.C.DARK_WHITE or self.C.GREY)
        end
        love.graphics.setFont(font_s)
        love.graphics.printf(
            (locked and "[?] " or "") .. def.name,
            list_x + 6, iy + 7, list_w - 12, "left"
        )

        self._deck_select_rects[idx] = { x = list_x, y = iy, w = list_w, h = item_h - 2 }
    end

    local sel_def = deck_list[sel_idx]
    if sel_def then
        local desc_y = list_y + view_size * item_h + 4
        love.graphics.setFont(font_s)
        love.graphics.setColor(sel_def.unlocked and self.C.WHITE or self.C.GREY)
        love.graphics.printf(
            sel_def.unlocked and sel_def.description or "Not yet unlocked.",
            list_x, desc_y, list_w, "left"
        )
    end

    love.graphics.setFont(font_s)
    love.graphics.setColor(self.C.GREY)
    love.graphics.printf("A/Y: Confirm  B/X: Back", 0, H - 18, W, "center")
end

function Game:draw_stake_select_ui()
    local W, H = 320, 240
    local font_s = self.FONTS.PIXEL.SMALL
    local font_m = self.FONTS.PIXEL.MEDIUM

    love.graphics.setColor(self.C.BLOCK.BACK)
    love.graphics.rectangle("fill", 0, 0, W, H)

    love.graphics.setFont(font_m)
    love.graphics.setColor(self.C.WHITE)
    love.graphics.printf("Choose Stake", 0, 8, W, "center")

    local stake_list = STAKE_DEFS or {}
    local sel_idx    = tonumber(self._stake_select_idx) or 1

    local item_h = 24
    local list_x = 10
    local list_y = 36
    local list_w = W - 20

    self._stake_select_rects = {}

    for i, def in ipairs(stake_list) do
        local iy = list_y + (i - 1) * item_h
        if iy + item_h > H - 30 then break end

        local selected = (i == sel_idx)
        local locked   = not def.unlocked

        local col = def.colour or { 1, 1, 1, 1 }
        if locked then
            love.graphics.setColor(0.3, 0.3, 0.3, 1)
        else
            love.graphics.setColor(col[1], col[2], col[3], col[4] or 1)
        end
        love.graphics.rectangle("fill", list_x, iy + 4, 10, item_h - 8, 2, 2)

        if selected then
            love.graphics.setColor(col[1] or 1, col[2] or 1, col[3] or 1, 0.2)
            love.graphics.rectangle("fill", list_x + 14, iy, list_w - 14, item_h - 2, 4, 4)
        end

        love.graphics.setFont(font_s)
        love.graphics.setColor(locked and self.C.GREY or self.C.WHITE)
        love.graphics.printf(
            (locked and "[?] " or "") .. def.name,
            list_x + 18, iy + 6, list_w - 24, "left"
        )

        self._stake_select_rects[i] = { x = list_x, y = iy, w = list_w, h = item_h - 2 }
    end

    local sel_def = stake_list[sel_idx]
    if sel_def then
        local desc_y = list_y + #stake_list * item_h + 4
        love.graphics.setFont(font_s)
        love.graphics.setColor(sel_def.unlocked and self.C.WHITE or self.C.GREY)
        love.graphics.printf(
            sel_def.unlocked and sel_def.description or "Not yet unlocked.",
            list_x, desc_y, list_w, "left"
        )
    end

    love.graphics.setFont(font_s)
    love.graphics.setColor(self.C.GREY)
    love.graphics.printf("A/Y: Confirm  B/X: Back", 0, H - 18, W, "center")
end

function Game:deck_select_touch(x, y)
    if not self._deck_select_rects then return false end
    for idx, rect in pairs(self._deck_select_rects) do
        if self:_point_in_rect_simple(x, y, rect) then
            local def = DECK_DEFS[idx]
            if def then
                if self._deck_select_idx == idx and def.unlocked then
                    self:_confirm_deck_selection()
                    return true
                else
                    self._deck_select_idx = idx
                end
                return true
            end
        end
    end
    return false
end

function Game:deck_select_button(btn)
    local list = DECK_DEFS or {}
    local idx  = tonumber(self._deck_select_idx) or 1

    if btn == "dpright" then
        self._deck_select_idx = math.max(1, idx - 1)
    elseif btn == "dpleft" then
        self._deck_select_idx = math.min(#list, idx + 1)
    elseif self:is_menu_activate(btn) then
        local def = list[idx]
        if def and def.unlocked then
            self:_confirm_deck_selection()
        end
    elseif self:is_role(btn, "cancel") then
        self:set_state(self.STATES.MENU)
        self._menu_sub_state = "main"
    end
end

function Game:stake_select_button(btn)
    local list = STAKE_DEFS or {}
    local idx  = tonumber(self._stake_select_idx) or 1

    if btn == "up" then
        self._stake_select_idx = math.max(1, idx - 1)
    elseif btn == "down" then
        self._stake_select_idx = math.min(#list, idx + 1)
    elseif self:is_menu_activate(btn) then
        self:_confirm_run_selection()
    elseif self:is_role(btn, "cancel") then
        self._menu_sub_state = "deck_select"
    end
end

function Game:_confirm_run_selection()
    local deck_idx = tonumber(self._deck_select_idx) or 1
    local stake_idx = tonumber(self._stake_select_idx) or 1
    local deck_def = DECK_DEFS and DECK_DEFS[deck_idx]
    local stake_def = STAKE_DEFS and STAKE_DEFS[stake_idx]
    if not deck_def or not deck_def.unlocked then return end
    if not stake_def or not stake_def.unlocked then return end

    self._pending_deck_id = deck_def.id
    self._pending_stake_id = stake_def.id
    -- Retired by the first run-start step, under the cover (`Game:_run_start_leave_menu`).

    if self.start_new_run_from_main_menu then
        self:start_new_run_from_main_menu()
    elseif self.initialize_run_loop then
        self:initialize_run_loop()
    end
end

function Game:_confirm_deck_selection()
    local idx = tonumber(self._deck_select_idx) or 1
    local def = DECK_DEFS and DECK_DEFS[idx]
    if not def or not def.unlocked then return end
    self._pending_deck_id = def.id
end

function Game:_confirm_stake_selection()
    self:_confirm_run_selection()
end
