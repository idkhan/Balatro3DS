# Modding Balatro3DS

Balatro3DS loads mods written in the [Steamodded](https://github.com/Steamodded/smods) style: a folder with a `.json` manifest and a Lua file that calls `SMODS.Joker { ... }`, `SMODS.Consumable { ... }`, `SMODS.Voucher { ... }` and `SMODS.DeckSkin { ... }`. Simple Steamodded Jokers, such as the ones in [Steamodded's examples](https://github.com/Steamodded/examples/tree/master/Mods/JokerExamples), port with few changes. The main one is the art: here **every card is its own image file**, the way the game stores its own Jokers and consumables, instead of Steamodded's atlases. This is not Steamodded, though. There is no Lovely, no `G.GAME` and no shaders, and for now mods can add **Jokers, Tarots, Planets, Spectrals, Vouchers and face-card sets**.

A working example is in [`dev/example_mods/ExampleJokers`](dev/example_mods/ExampleJokers).

## Where mods go

Mods live in a `mods` folder in the game's save directory on the SD card, next to the run saves (`Balatro3DS_run_save_1.lua` and friends). The game creates the folder the first time it starts.

```
mods/
├── mods_log.txt                 written every boot: what loaded, and why anything didn't
├── disabled.txt                 the mods turned off in Options → Mods (only while any are)
└── ExampleJokers/
    ├── ExampleJokers.json       manifest
    ├── ExampleJokers.lua        main file
    └── assets/1x/               one image per card
        ├── plus_four.t3x        what the 3DS loads
        ├── plus_four.png        optional, for desktop testing
        ├── plus_four_negative.t3x
        └── ...
```

**Options → Mods** in the game lists every mod, whether it loaded, and any errors. Each mod has an **ON/OFF** switch: tap its row, or pick it with Up/Down and press A. The change takes effect at once, with no restart. A mod that is turned off doesn't run at all, and mods that depend on it don't load either. The ids of the mods that are off are kept in `mods/disabled.txt`, one per line, which you can also edit by hand.

## Manifest

Steamodded's format. `id`, `prefix` and `main_file` are required.

```json
{
    "id": "ExampleJokers",
    "name": "Example Jokers",
    "author": ["You"],
    "description": "What it does.",
    "prefix": "exj",
    "main_file": "ExampleJokers.lua",
    "version": "1.0.0",
    "dependencies": ["SomeOtherMod (>=1.0.0)"]
}
```

- **`prefix`** namespaces everything the mod defines. A Joker with `key = "plus_four"` becomes `j_exj_plus_four`. Use letters, digits and `_` only. Two mods can't share a prefix.
- **`dependencies`** name other mods by `id`; the version clause is not checked. `Steamodded` is ignored, so manifests copied from Steamodded mods work as they are.
- **`version`** matters for saves (see below). Change it whenever a change would affect a run in progress.

## Images: one file per card, as `.t3x`

Each card points at its own image in `assets/1x/` with `sprite = "plus_four.png"`. The game handles mod images exactly like its own: it loads one when the card first appears and frees it when the last copy goes, so a mod's art costs memory only while it's on screen.

The 3DS only loads textures in its own `.t3x` format, and the game does not convert anything. You do. Name the file as a `.png`. When asked for `plus_four.png`, the console loads `plus_four.t3x` from the same folder. Ship the `.t3x`; the `.png` is only needed for desktop testing.

```sh
tex3ds -f rgba plus_four.png -o plus_four.t3x
```

`tex3ds` comes with [devkitPro](https://devkitpro.org/wiki/Getting_Started) (`3ds-dev`).

Use the same sizes as the game's own art:

| Card | Image |
|---|---|
| Joker (and its soul and negative images) | 70 × 94 |
| Tarot, Planet, Spectral | 64 × 128, with the card in the top 64 × 96 and the rest transparent |
| Voucher | 72 × 95 |
| Deck skin (face cards) | 216 × 95: three 72 × 95 cells, J, Q, K |

Consumables are padded to 64 × 128 on purpose. A `.t3x` is stored at power-of-two sizes, and the game's own consumables use that exact layout so the card is never stretched. Copy it.

- **Missing images:** a missing image file (neither the `.png` nor the `.t3x`) is a load error that names the file.
- **`SMODS.Atlas`:** raises an error that tells you to use `sprite` instead. To port a Steamodded mod, cut its atlas into one image per card.

## Jokers

```lua
SMODS.Joker {
    key = "plus_four",
    loc_txt = { name = "Plus Four", text = { "{C:mult}+#1#{} Mult" } },
    config = { extra = { mult = 4 } },
    rarity = 1,              -- 1-4, or "Common" / "Uncommon" / "Rare" / "Legendary"
    cost = 3,
    sprite = "plus_four.png",
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
```

### Supported fields

| Field | Notes |
|---|---|
| `key` | Required. The Joker's id is `j_<prefix>_<key>`. |
| `loc_txt.name`, `loc_txt.text` | Name, and description lines. `#1#` is replaced from `loc_vars`. |
| `config` | Copied into `card.ability` for each copy of the Joker, so two copies scale separately. Saved with the run. |
| `rarity`, `cost` | Sell value is half the cost, minimum 1. |
| `sprite` | Required. The Joker's image in `assets/1x`. |
| `soul_sprite` | The floating layer Legendary Jokers have, drawn over the card. |
| `negative_sprite` | Art for a Negative copy (see [Negative art](#negative-art)). |
| `blueprint_compat` | Defaults to `false`, as in Steamodded. |
| `eternal_compat`, `perishable_compat` | Default `true`. |
| `unlocked`, `discovered` | Mod Jokers are unlocked by default. |
| `loc_vars(self, info_queue, card)` | Return `{ vars = { ... } }`. `info_queue` is accepted and ignored. |
| `calculate(self, card, context)` | See below. |
| `calc_dollar_bonus(self, card)` | Money paid at the end of the round, listed in the round's payout. |
| `in_pool(self, args)` | Return `false` to keep the Joker out of the shop and every random roll. `args` is an empty table. |
| `set_ability(self, card, initial)` | Called whenever a copy of the Joker is created (including shop cards), after `config` has been copied into `card.ability`. A loaded run then restores the saved `card.ability` over it. |
| `add_to_deck(self, card, from_debuff)`, `remove_from_deck(...)` | Called when the Joker is gained or lost. Not called when a saved run is loaded, because the save already includes their effects. |

**Description markup:** `{C:mult}`, `{C:chips}`, `{C:money}`, `{C:attention}`, `{C:green}`, `{C:red}`, `{C:purple}` and `{C:inactive}` work, and `{}` resets the colour. `{X:...}` uses its colour for the text. `{s:...}` and `{V:n}` are ignored.

### `calculate` contexts

| Context | When |
|---|---|
| `context.before` | A hand is played, before anything scores. |
| `context.individual` + `context.cardarea == G.play` | Each scored card. `context.other_card` is the card. |
| `context.individual` + `context.cardarea == G.hand` | Each card held in hand. |
| `context.repetition` | Asked per scored card: return `{ repetitions = n }` to retrigger it. |
| `context.retrigger_joker_check` | Asked each time a Joker triggers. `context.other_card` is that Joker and `context.other_context` the context it triggered in. Return `{ repetitions = n }` to run its effect `n` more times; during those passes it sees `context.retrigger_joker`. A repeat is never repeated again. Check `context.other_card ~= card` unless the Joker should repeat itself. There is no `context.other_ret`. Unlike Steamodded, no `optional_features` opt-in is needed. |
| `context.post_trigger` | After each Joker triggers, with the same `other_card` and `other_context`. What you return scores as if this Joker had triggered on that event. |
| `context.probability_success` | Port only. A chance roll just succeeded: Lucky Card, Bloodstone, Business Card, Reserved Parking, Space Joker, 8 Ball, Hallucination, Wheel of Fortune, or a mod's `SMODS.pseudorandom_probability`. Return `{ repetitions = n }` to fire its effect `n` more times. `context.identifier` names the roll and `context.numerator` / `context.denominator` give its odds. Rolls that only go one way (Glass breaking, Gros Michel and Cavendish going extinct, The Wheel) are not asked. |
| `context.mod_probability`, `context.fix_probability` | Before any roll, the game's or a mod's. Return `{ numerator = x, denominator = y }` to change the odds. Every `mod_probability` answer is applied in Joker order, then every `fix_probability` answer. Oops! All 6s is already counted. `context.identifier` names the roll; `context.trigger_obj` is what the mod passed, or nil for the game's own rolls. |
| `context.pseudorandom_result` | After any roll, with `context.result` (true when it hit) and the same fields. A returned `message` is shown; other returns are ignored. |
| `context.joker_main` | The Joker's main scoring step. |
| `context.final_scoring_step` | After every Joker has scored, before the total lands and before Plasma Deck balances it. Returns score as usual. |
| `context.after` | After the hand has scored. |
| `context.end_of_round` | End of the round. |
| `context.blind_defeated` | The Blind's score has been reached, before the end-of-round payouts. |
| `context.discard` | Each discarded card (`context.other_card`). Also `context.pre_discard`. |
| `context.setting_blind`, `context.first_hand_drawn` | Blind selected; first hand of the round. |
| `context.hand_drawn` | A deal to the hand has finished during a round. `context.hand_drawn` is the list of cards just drawn. |
| `context.skip_blind` | A Blind was skipped, after its Tag was given. |
| `context.ante_change` | The Ante changed. `context.ante_change` is the amount (`1`, or `-1` from Hieroglyph and Petroglyph) and `context.ante_end` is true when a Boss was beaten. |
| `context.selling_card`, `context.selling_self` | A Joker is sold; `selling_self` when it's this one. |
| `context.card_added` | A Joker was gained (bought, created or given). `context.card` is the new Joker. Not raised when a saved run is loaded. |
| `context.tag_added` | A Tag was gained. `context.tag_added` is the Tag. |
| `context.starting_shop`, `context.ending_shop` | The shop opens; the player leaves it. |
| `context.reroll_shop`, `context.buying_card`, `context.open_booster`, `context.skipping_booster`, `context.using_consumeable` | Shop and pack events. |
| `context.playing_card_added`, `context.remove_playing_cards` | Cards added to or destroyed from the deck. |

Also available on `context`:
- `blueprint` and `blueprint_card`: set when Blueprint or Brainstorm is copying this Joker.
- `poker_hands`: use `next(context.poker_hands["Flush"])` to check whether the played hand contains a Flush.
- `scoring_name`, `scoring_hand` and `full_hand`. In `pre_discard` and `discard`, `full_hand` is the cards being discarded.
- `port`: the game's own event table, for anything not translated above.

Playing cards support `:get_id()` (2 to 14, where Jack is 11 and Ace is 14), `:is_face()`, `:is_suit("Hearts")`, `.base.suit` and `.debuff`.

### Return values

`chips`, `mult`, `xmult` (also `x_mult` and `Xmult`), `dollars` and `message`, plus `extra` to chain another table. They score exactly like a vanilla Joker's, with the same popups, sounds and timing. A return with only a `message` (such as `"Upgrade!"`) shows it and counts as the Joker triggering.

### Helpers

All of these use the run's seed:
- `SMODS.pseudorandom_probability(card, seed, numerator, denominator, identifier, no_mod)` returns whether the roll hit. As a port extension, it also returns how many times the effect should run: 1, plus any `probability_success` repetitions. Use `local hit, times = ...` to support Jokers like Natural 20!.
- `SMODS.get_probability_vars(card, numerator, denominator, identifier)` returns the odds a roll would use, for tooltips.
- `pseudorandom(seed)`
- `pseudorandom_element(list, seed)`

Oops! All 6s and every `mod_probability` / `fix_probability` Joker are counted, unless `no_mod` is true. `localize("k_upgrade_ex")` and a few other common message keys work, and so does `ease_dollars(n)`.

## Negative art

The PC game recolours a Negative card with a shader. The 3DS can't, so vanilla ships a separate negative image for every Joker, and a mod can do the same. Jokers and consumables accept `negative_sprite = "plus_four_negative.png"`, an image the same size as the normal one.

Without it, a Negative copy keeps its normal art. The example mod has negative art for all its Jokers and its Tarot.

### Making negative art

Don't recolour it by hand: run the shader's own transform over the normal image. It reproduces the game's own `Jokers1_negative_*.png` files pixel for pixel.

```sh
python3 dev/make_negative.py plus_four.png                 # writes plus_four_negative.png
python3 dev/make_negative.py *.png --t3x                   # every image, plus each .t3x (needs tex3ds)
python3 dev/make_negative.py plus_four.png -o neg.png      # choose the output name
```

It needs only Python 3, nothing to install. With Aseprite, `dev/aseprite/hsl_invert_transform.lua` does the same thing, either from **File → Scripts**, or from the command line:

```sh
aseprite -b plus_four.png --script dev/aseprite/hsl_invert_transform.lua --save-as plus_four_negative.png
```

Run it on the finished normal image; don't edit the negative afterwards.

## Translations

`loc_txt` can hold one table per language, as in Steamodded. Use `en-us` for English, and the game's own codes (as in `locales/`, e.g. `zh_CN`) for the others:

```lua
loc_txt = {
    ["en-us"] = { name = "Plus Four", text = { "{C:mult}+#1#{} Mult" } },
    zh_CN     = { name = "加四", text = { "{C:mult}+#1#{}倍率" } },
},
```

The card shows the player's chosen language when it has one, and English when it doesn't. A single `{ name, text }` table works too; it is used for every language.

## Modifiers

A Joker or Voucher changes these numbers just by declaring them in `config`. The effect lasts while the Joker is held or the Voucher is owned, and needs no code:

| Key | Changes |
|---|---|
| `h_size` | Hand size |
| `d_size` | Discards per round |
| `hands` | Hands per round |
| `joker_slots` | Joker slots |
| `consumable_slots` | Consumable slots |

```lua
config = { h_size = 1 }   -- like Juggler
```

## Consumables

```lua
SMODS.Consumable {
    set = "Tarot",           -- "Tarot", "Planet" or "Spectral"
    key = "gild",            -- id is c_<prefix>_<key>
    loc_txt = { name = "Gild", text = { "Enhances up to {C:attention}#1#{}", "cards into {C:money}Gold Cards{}" } },
    config = { max_highlighted = 2, mod_conv = "m_gold" },
    sprite = "gild.png",     -- 64x128, card in the top 64x96
    loc_vars = function(self, info_queue, card)
        return { vars = { card.ability.max_highlighted } }
    end,
}
```

They appear in packs and the shop alongside the vanilla cards of their set, and in the collection.

**Built in.** As in Steamodded, a consumable that only declares data needs no code:

| `config` | Does |
|---|---|
| `max_highlighted`, `min_highlighted` | How many selected cards it needs (`min` defaults to 1). It can't be used until that many are selected. |
| `mod_conv = "m_gold"` | Enhances the selected cards: `m_bonus`, `m_mult`, `m_wild`, `m_glass`, `m_steel`, `m_stone`, `m_gold`, `m_lucky`. |
| `suit_conv = "Hearts"` | Changes the selected cards to that suit. |
| `hand_type = "Flush"` | Planet only: levels up that hand, with the vanilla level-up animation. |

**Code:**
- **`can_use(self, card)`:** return `true` when the card can be used right now. The game has already checked that consumables can be used at all, and that the right number of cards is selected.
- **`use(self, card, area, copier)`:** does the effect. It runs after any built-in conversion. For a Planet with a `hand_type`, it runs after the level-up.
- **Selection:** `G.hand.highlighted` is the list of selected cards, in order, while either function runs.
- **State:** `card.ability` is this copy's own copy of `config` and is saved with the run.
- **Other fields:** `cost` (defaults to the set's price) and `negative_sprite`.

Using a mod consumable counts toward The Fool, consumable stats, and Jokers that react to consumables being used.

## Vouchers

```lua
SMODS.Voucher {
    key = "bigger_hand",     -- id is v_<prefix>_<key>
    loc_txt = { name = "Bigger Hand", text = { "{C:attention}+#1#{} hand size" } },
    config = { h_size = 1 },
    sprite = "bigger_hand.png",   -- 72x95
    loc_vars = function(self, info_queue, card)
        return { vars = { card.ability.h_size } }
    end,
}

SMODS.Voucher {
    key = "biggest_hand",
    loc_txt = { name = "Biggest Hand", text = { "{C:attention}+1{} hand size again" } },
    config = { h_size = 1 },
    requires = { "bigger_hand" },
    cost = 12,
    sprite = "biggest_hand.png",
    redeem = function(self, card) ease_dollars(5) end,
}
```

- **`requires`:** the voucher only appears in the shop once all of these are owned. Each entry can be a vanilla voucher's id (Steamodded's `v_overstock_norm` and `v_reroll_surplus` work too), a full mod id, or one of your own keys. Define a required voucher before the one that requires it.
- **`config`:** its [modifiers](#modifiers) apply for as long as the voucher is owned.
- **`redeem(self, card)`:** runs once, when the voucher is bought.
- **`cost`:** defaults to 10.
- **`loc_vars`:** fills the description shown in the shop and the collection.

Mod vouchers join the shop's voucher pool after the vanilla ones. With no mods installed the pool, and so every seed, is exactly vanilla's.

## Card faces

```lua
SMODS.DeckSkin {
    key = "royal_court",
    suit = "Spades",                          -- "Hearts", "Clubs", "Diamonds" or "Spades"
    loc_txt = { name = "Royal Court" },       -- or just loc_txt = "Royal Court"
    sprite = "royal_court_spades.png",        -- 216x95 strip: J, Q, K
    hc_sprite = "royal_court_spades_hc.png",  -- optional high-contrast strip
}
```

A deck skin is a set of Jack, Queen and King art for one suit, like the built-in collab sets. It shows up in **Options → Art** at the end of its suit's carousel, and the player picks it there the same way.

- **`sprite`:** one strip of three 72 × 95 cells, Jack, Queen and King from left to right. This is the same format as the game's own sets in `resources/textures/1x/collabs/`. Keep everything outside the art transparent so the card front shows through. The deck's own faces keep their art between x = 6 and x = 64 of each cell.
- **`hc_sprite`:** the strip used when the player ticks High Contrast for the suit. Without one, `sprite` is used at both settings.
- **Ranks:** only the face cards can be replaced. If `ranks` is given, it must be `{ "Jack", "Queen", "King" }`.
- **Atlases:** Steamodded's `lc_atlas` and `hc_atlas` aren't supported. Use `sprite` and `hc_sprite`.

Deck skins are cosmetic. If the mod is removed, a suit that used one goes back to the deck's own art.

## Saved runs and mods

A run remembers exactly which mods, and which versions, it was played with. It can only be continued with that same set installed and turned on. If a mod is missing, turned off, at a different version, or newly added, **Continue** opens the Mods screen and lists what to install, turn on, or turn off. The save is kept, not deleted, and works again once the mods match. Switching mods on that screen updates the list as you go.

This is why `version` matters: bump it when a change would break a run in progress (adding or removing a card, changing what `config` holds), and keep it when it wouldn't.

## What doesn't work (yet)

- **No other content yet.** Decks, editions, seals, enhancements, blinds, booster packs and poker hands can't be added. Vouchers have no `calculate`, and deck skins cover only the face cards.
- **No `G.GAME`, `G.jokers.cards`, `G.E_MANAGER`, `SMODS.destroy_cards`, `SMODS.calculate_effect`, hooks into `Game:init_game_object`, or `reset_game_globals`.** The port's game state is laid out differently. Code that touches these raises a runtime error. The error is caught: that Joker does nothing for that call, and the error appears on the Mods screen and in `mods_log.txt`.
- **No shaders.** Foil, Holographic and Polychrome mod Jokers are drawn with the port's own additive texture passes, like vanilla Jokers. Negative needs its own art (see [Negative art](#negative-art)).
- **`yes_pool_flag`, `no_pool_flag` and `info_queue` are ignored.** `in_pool` returns only whether the Joker can roll; a second `allow_duplicates` return is ignored.
- **Contexts not raised yet:** `blind_disabled`, `debuff_card`, `debuff_hand`, `destroy_card` (`destroying_card`), `modify_scoring_hand`, `evaluate_poker_hand`, `check_enhancement`, `money_altered`, `initial_scoring_step`, `playing_card_end_of_round`, `change_rank` and `change_suit`. These need deeper changes to the port's scoring and deck code.

## Debugging

- **Load errors:** a mod that fails to load (bad manifest, missing dependency, an error in its main file) is undone completely and listed on the Mods screen with the reason. Other mods still load.
- **Runtime errors:** errors inside `calculate`, `loc_vars`, `can_use`, `use` or `redeem` are caught and listed. The game keeps running.
- **Log:** `mods_log.txt` is rewritten at every boot and on every runtime error, so it is always up to date when you read it off the SD card.
