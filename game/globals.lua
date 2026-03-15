VERSION = '1.0.1o'
VERSION = VERSION..'-FULL'
--check_version

-- basic helpers used by global config
function HEX(hex)
    if #hex <= 6 then hex = hex.."FF" end
  local _,_,r,g,b,a = hex:find('(%x%x)(%x%x)(%x%x)(%x%x)')
  local color = {tonumber(r,16)/255,tonumber(g,16)/255,tonumber(b,16)/255,tonumber(a,16)/255 or 255}
  return color
end

function copy_table(t)
    if type(t) ~= 'table' then return t end
    local nt = {}
    for k, v in pairs(t) do
        if type(v) == 'table' then
            nt[k] = copy_table(v)
        else
            nt[k] = v
        end
    end
    return nt
end

--Globals
function Game:set_globals()
    
    --||||||||||||||||||||||||||||||
    --         Feature Flags
    --||||||||||||||||||||||||||||||
    self.F_QUIT_BUTTON = true               --Include the main menu 'Quit' button
    self.F_SKIP_TUTORIAL = false            --Completely skip the tutorial on fresh save
    self.F_BASIC_CREDITS = false            --Remove references to Daniel Linssens itch.io
    self.F_EXTERNAL_LINKS = true            --Remove all references to any external links (mainly for console)
    self.F_ENABLE_PERF_OVERLAY = false      --Disable debugging tool for performance of each frame
    self.F_NO_SAVING = false                --Disables all 'run' saving
    self.F_MUTE = false                     --Force mute all sounds
    self.F_SOUND_THREAD = true              --Have sound in a separate thread entirely - if not sounds will run on main thread
    self.F_VIDEO_SETTINGS = true            --Let the player change their video settings
    self.F_CTA = false                      --Call to Action video for the Demo - keep this as false
    self.F_VERBOSE = true                   --Extra debug information on screen and in the console
    self.F_HTTP_SCORES = false              --Include HTTP scores to fetch/set high scores
    self.F_RUMBLE = nil                     --Add rumble to the primary controller - adjust this for amount of rumble
    self.F_CRASH_REPORTS = false            --Send Crash reports over the internet
    self.F_NO_ERROR_HAND = false            --Hard crash without error message screen
    self.F_SWAP_AB_PIPS = false             --Swapping button pips for A and B buttons (mainly for switch)
    self.F_SWAP_AB_BUTTONS = false          --Swapping button function for A and B buttons (mainly for switch)
    self.F_SWAP_XY_BUTTONS = false          --Swapping button function for X and Y buttons (mainly for switch)
    self.F_NO_ACHIEVEMENTS = false          --Disable achievements
    self.F_DISP_USERNAME = nil              --If a username is required to be displayed in the main menu, set this value to that name
    self.F_ENGLISH_ONLY = nil               --Disable language selection - only in english
    self.F_GUIDE = false                    --Replace back/select button with 'guide' button
    self.F_JAN_CTA = false                  --Call to action for Jan demo
    self.F_HIDE_BG = false                  --Hiding the game objects when paused
    self.F_TROPHIES = false                 --use 'trophy' terminology instead of 'achievemnt'
    self.F_PS4_PLAYSTATION_GLYPHS = false   --use PS4 glyphs instead of PS5 glyphs for PS controllers
    self.F_LOCAL_CLIPBOARD = false
    self.F_SAVE_TIMER = 30
    self.F_MOBILE_UI = false
    self.F_HIDE_BETA_LANGS = nil


    --||||||||||||||||||||||||||||||
    --             Time
    --||||||||||||||||||||||||||||||
    self.SEED = os.time()
    self.TIMERS = {
        TOTAL=0,
        REAL = 0,
        REAL_SHADER = 0,
        UPTIME = 0,
        BACKGROUND = 0
    }
    self.FRAMES = {
        DRAW = 0,
        MOVE = 0
    }
    self.exp_times = {xy = 0, scale = 0, r = 0}
    --||||||||||||||||||||||||||||||
    --           SETTINGS
    --||||||||||||||||||||||||||||||
    self.SETTINGS = {
        COMP = {
            name = '',
            prev_name = '',
            submission_name = nil,
            score = 0,
        },
        DEMO = {
            total_uptime = 0,
            timed_CTA_shown = false,
            win_CTA_shown = false,
            quit_CTA_shown = false
        },
        ACHIEVEMENTS_EARNED = {},
        crashreports = false,
        colourblind_option = false,
        language = 'en-us',
        screenshake = true,
        run_stake_stickers = false,
        rumble = self.F_RUMBLE,
        play_button_pos = 2,
        GAMESPEED = 1,
        paused = false,
        SOUND = {
            volume = 50,
            music_volume = 100,
            game_sounds_volume = 100,
        },
        WINDOW = {
            screenmode = 'Borderless',
            vsync = 1,
            selected_display = 1,
            display_names = {'[NONE]'},
            DISPLAYS = {
                {
                    name = '[NONE]',
                    screen_res = {w = 1000, h = 650},
                }
            },
        },
        CUSTOM_DECK = {
            Collabs = {
                Spades = 'default',
                Hearts = 'default',
                Clubs = 'default',
                Diamonds = 'default',
            }
        },
        GRAPHICS = {
            texture_scaling = 1,
            shadows = 'On',
            crt = 70,
            bloom = 1
        },
    }

    self.COLLABS = {
        pos = { Jack = {x=0,y=0}, Queen = {x=1,y=0}, King = {x=2,y=0} },
        options = {
            Spades = {
                'default',
                'collab_TW',
                'collab_CYP',
                'collab_SK',
                'collab_DS',
                'collab_AC',
                'collab_STP',
           },
            Hearts = {
              'default',
              'collab_AU',
              'collab_TBoI',
              'collab_CL',
              'collab_D2',
              'collab_CR',
              'collab_BUG',
            },
            Clubs = {
              'default',
              'collab_VS',
              'collab_STS',
              'collab_PC',
              'collab_WF',
              'collab_FO',
              'collab_DBD'
            },
            Diamonds = {
              'default',
              'collab_DTD',
              'collab_SV',
              'collab_EG',
              'collab_XR',
              'collab_C7',
              'collab_R'
            }
          },
      }

    self.METRICS = {
        cards = {
            used = {},
            bought = {},
            appeared = {},
        },
        decks = {
            chosen = {},
            win = {},
            lose = {}
        },
        bosses = {
            faced = {},
            win = {},
            lose = {},
        }
    }

    --||||||||||||||||||||||||||||||
    --           PROFILES
    --||||||||||||||||||||||||||||||
    self.PROFILES = {
        {},
        {},
        {},
    }

    --||||||||||||||||||||||||||||||
    --        RENDER SCALE
    --||||||||||||||||||||||||||||||
    self.TILESIZE = 20
    self.TILESCALE = 3.65
    self.TILE_W = 20
    self.TILE_H = 11.5
    self.DRAW_HASH_BUFF = 2
    self.CARD_W = 2.4*35/41
    self.CARD_H = 2.4*47/41
    self.HIGHLIGHT_H = 0.2*self.CARD_H
    self.COLLISION_BUFFER = 0.05

    self.PITCH_MOD = 1

    --||||||||||||||||||||||||||||||
    --        GAMESTATES
    --||||||||||||||||||||||||||||||
    self.STATES = {
        SELECTING_HAND = 1,
        HAND_PLAYED = 2,
        DRAW_TO_HAND = 3,
        GAME_OVER = 4,
        SHOP = 5,
        PLAY_TAROT = 6,
        BLIND_SELECT = 7,
        ROUND_EVAL = 8,
        TAROT_PACK = 9,
        PLANET_PACK = 10,
        MENU = 11,
        TUTORIAL = 12,
        SPLASH = 13,--DO NOT CHANGE, this has a dependency in the SOUND_MANAGER
        SANDBOX = 14,
        SPECTRAL_PACK = 15,
        DEMO_CTA = 16,
        STANDARD_PACK = 17,
        BUFFOON_PACK = 18,
        NEW_ROUND = 19,
    }

    self.STAGES = {
        MAIN_MENU = 1,
        RUN = 2,
        SANDBOX = 3
    }
    self.STAGE_OBJECTS = {
        {},{},{}
    }
    self.STAGE = self.STAGES.MAIN_MENU
    self.STATE = self.STATES.SPLASH
    self.TAROT_INTERRUPT = nil
    self.STATE_COMPLETE = false

    --||||||||||||||||||||||||||||||
    --          INSTANCES
    --||||||||||||||||||||||||||||||
    self.ARGS = {}
    self.FUNCS = {}
    self.I = {
        NODE = {},
        MOVEABLE = {},
        SPRITE = {},
        UIBOX = {},
        POPUP = {},
        CARD = {},
        CARDAREA = {},
        ALERT = {}
    }
    self.ANIMATION_ATLAS = {}
    self.ASSET_ATLAS = {}
    self.MOVEABLES = {}
    self.ANIMATIONS = {}
    self.DRAW_HASH = {}

    --||||||||||||||||||||||||||||||
    --        CONSTANTS
    --||||||||||||||||||||||||||||||
    self.MIN_CLICK_DIST = 0.9
    self.MIN_HOVER_TIME = 0.1
    self.DEBUG = false
    self.ANIMATION_FPS = 10
    self.VIBRATION = 0
    self.CHALLENGE_WINS = 5

    --||||||||||||||||||||||||||||||
    --        COLOURS
    --||||||||||||||||||||||||||||||
    self.C = {
        MULT = HEX('FE5F55'),
        CHIPS = HEX("009dff"),
        MONEY = HEX('f3b958'),
        XMULT = HEX('FE5F55'),
        FILTER = HEX('ff9a00'),
        BLUE = HEX("009dff"),
        RED = HEX('FE5F55'),
        GREEN = HEX("4BC292"),
        PALE_GREEN = HEX("56a887"),
        ORANGE = HEX("fda200"),
        IMPORTANT = HEX("ff9a00"),
        GOLD = HEX('eac058'),
        YELLOW = {1,1,0,1},
        CLEAR = {0, 0, 0, 0}, 
        WHITE = {1,1,1,1},
        PURPLE = HEX('8867a5'),
        BLACK = HEX("374244"),--4f6367"),
        L_BLACK = HEX("4f6367"),
        GREY = HEX("5f7377"),
        CHANCE = HEX("4BC292"),
        JOKER_GREY = HEX('bfc7d5'),
        VOUCHER = HEX("cb724c"),
        BOOSTER = HEX("646eb7"),
        EDITION = {1,1,1,1},
        DARK_EDITION = {0,0,0,1},
        ETERNAL = HEX('c75985'),
        PERISHABLE = HEX('4f5da1'),
        RENTAL = HEX('b18f43'),
        DYN_UI = {
            MAIN = HEX('374244'),
            DARK = HEX('374244'),
            BOSS_MAIN = HEX('374244'),
            BOSS_DARK = HEX('374244'),
            BOSS_PALE = HEX('374244')
        },
        --For other high contrast suit colours
        SO_1 = {
            Hearts = HEX('f03464'),
            Diamonds = HEX('f06b3f'),
            Spades = HEX("403995"),
            Clubs = HEX("235955"),
        },
        SO_2 = {
            Hearts = HEX('f83b2f'),
            Diamonds = HEX('e29000'),
            Spades = HEX("4f31b9"),
            Clubs = HEX("008ee6"),
        },
        SUITS = {
            Hearts = HEX('FE5F55'),
            Diamonds = HEX('FE5F55'),
            Spades = HEX("374649"),
            Clubs = HEX("424e54"),
        },
        UI = {
            TEXT_LIGHT = {1,1,1,1},
            TEXT_DARK = HEX("4F6367"),
            TEXT_INACTIVE = HEX("88888899"),
            BACKGROUND_LIGHT = HEX("B8D8D8"),
            BACKGROUND_WHITE = {1,1,1,1},
            BACKGROUND_DARK = HEX("7A9E9F"),
            BACKGROUND_INACTIVE = HEX("666666FF"),
            OUTLINE_LIGHT = HEX("D8D8D8"),
            OUTLINE_LIGHT_TRANS = HEX("D8D8D866"),
            OUTLINE_DARK = HEX("7A9E9F"),
            TRANSPARENT_LIGHT = HEX("eeeeee22"),
            TRANSPARENT_DARK = HEX("22222222"),
            HOVER = HEX('00000055'),
        },
        SET = {
            Default = HEX("cdd9dc"),
            Enhanced = HEX("cdd9dc"),
            Joker = HEX('424e54'),
            Tarot = HEX('424e54'),--HEX('29adff'),
            Planet = HEX("424e54"),
            Spectral = HEX('424e54'),
            Voucher = HEX("424e54"),
        }, 
        SECONDARY_SET = {
            Default = HEX("9bb6bdFF"),
            Enhanced = HEX("8389DDFF"),
            Joker = HEX('708b91'),
            Tarot = HEX('a782d1'),--HEX('29adff'),
            Planet = HEX('13afce'),
            Spectral = HEX('4584fa'),
            Voucher = HEX("fd682b"),
            Edition = HEX("4ca893"),
        }, 
        RARITY = {
            HEX('009dff'),--HEX("708b91"),
            HEX("4BC292"),
            HEX('fe5f55'),
            HEX("b26cbb")
        },
        BLIND = {
            Small = HEX("50846e"),
            Big = HEX("50846e"),
            Boss = HEX("b44430"),
            won = HEX("4f6367")
        },
        HAND_LEVELS = {
            HEX("efefef"),
            HEX("95acff"),
            HEX("65efaf"),
            HEX('fae37e'), 
            HEX('ffc052'), 
            HEX('f87d75'),
            HEX('caa0ef')
        },
        BACKGROUND = {
            L = {1,1,0,1},
            D = HEX("374244"),
            C = HEX("374244"),
            contrast = 1
        }
    }
    G.C.HAND_LEVELS[0] = G.C.RED
    G.C.UI_CHIPS = copy_table(G.C.BLUE)
    G.C.UI_MULT = copy_table(G.C.RED)
    --||||||||||||||||||||||||||||||
    --        ENUMS
    --||||||||||||||||||||||||||||||
    self.UIT = {
        T=1, --text
        B=2, --box (can be rounded)
        C=3, --column
        R=4, --row
        O=5, --object - must be a Node
        ROOT=7,
        S=8, --slider
        I=9, --input text box
        padding = 0, --default padding
    }
    self.handlist = {
        "Flush Five",
        "Flush House",
        "Five of a Kind",
        "Straight Flush",
        "Four of a Kind",
        "Full House",
        "Flush",
        "Straight",
        "Three of a Kind",
        "Two Pair",
        "Pair",
        "High Card",
    }
    self.button_mapping = {
        a = G.F_SWAP_AB_BUTTONS and 'b' or nil,
        b = G.F_SWAP_AB_BUTTONS and 'a' or nil,
        y = G.F_SWAP_XY_BUTTONS and 'x' or nil,
        x = G.F_SWAP_XY_BUTTONS and 'y' or nil,
    }
    self.keybind_mapping = {{
        a = 'dpleft',
        d = 'dpright',
        w = 'dpup',
        s = 'dpdown',
        x = 'x',
        c = 'y',
        space = 'a',
        shift = 'b',
        esc = 'start',
        q = 'triggerleft',
        e = 'triggerright',
    }}
end
