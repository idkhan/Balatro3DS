--- Static check: every cue name passed to Sfx.play / Sfx.play_random must ship as a
--- file in resources/sounds/.
---
--- sfx.lua takes bare cue names ("chips1"), not paths, and swallows an unknown cue --
--- `pool_for` marks it missing, warns only under G.DEBUG, and `play` then returns false
--- forever. A typo is therefore silent at runtime and invisible in review. This test is
--- the only thing standing between a renamed asset and a sound that never plays again.
---
--- Scanning is textual on purpose: loading every UI module to reach its call sites would
--- be slower, more fragile, and would still miss branches that never execute.

local T = require("tests.testlib")

local suite = T.suite()

local ROOT = os.getenv("BALATRO_ROOT") or "."
local SOUND_DIR = ROOT .. "/resources/sounds"

--------------------------------------------------------------------------------
-- Inputs
--------------------------------------------------------------------------------

--- Cue names present on disk, derived from the .ogg files themselves rather than any
--- list in the code -- otherwise the test would just be comparing sfx.lua to itself.
---@return table<string, boolean>
local function shipped_cues()
    local set = {}
    local p = io.popen("ls " .. SOUND_DIR .. " 2>/dev/null")
    if not p then return set end
    for line in p:lines() do
        local name = line:match("^(.+)%.ogg$")
        if name then set[name] = true end
    end
    p:close()
    return set
end

--- Every .lua file that is part of the game. Excludes the reference copy of the
--- original game, scratch work, the vendored nest shim, build tooling, and this suite.
---@return string[]
local function game_lua_files()
    local files = {}
    local cmd = ("find %s -name '*.lua' -not -path '*/reference/*' -not -path '*/.scratch/*' "
        .. "-not -path '*/nest/*' -not -path '*/dev/*' -not -path '*/tests/*' -not -path '*/.git/*' "
        .. "-not -path '*/.claude/*'")
        :format(ROOT)
    local p = io.popen(cmd .. " 2>/dev/null")
    if not p then return files end
    for line in p:lines() do files[#files + 1] = line end
    p:close()
    table.sort(files)
    return files
end

--------------------------------------------------------------------------------
-- Call-site scanning
--------------------------------------------------------------------------------

--- Walk forward from the open paren of a call and return the argument text, respecting
--- nested parens, braces and quoted strings. Needed because arguments like
--- `Sfx.play("card1", math.min(1, x))` contain parens of their own.
---@param src string
---@param open_at integer index of the "("
---@return string|nil args
---@return integer|nil close_at
local function call_args(src, open_at)
    local depth = 0
    local i = open_at
    local n = #src
    while i <= n do
        local c = src:sub(i, i)
        if c == '"' or c == "'" then
            -- Skip a quoted string, honouring backslash escapes.
            local quote = c
            i = i + 1
            while i <= n do
                local d = src:sub(i, i)
                if d == "\\" then
                    i = i + 2
                elseif d == quote then
                    break
                else
                    i = i + 1
                end
            end
        elseif c == "(" or c == "{" or c == "[" then
            depth = depth + 1
        elseif c == ")" or c == "}" or c == "]" then
            depth = depth - 1
            if depth == 0 and c == ")" then
                return src:sub(open_at + 1, i - 1), i
            end
        end
        i = i + 1
    end
    return nil
end

--- Pull every string literal out of an argument list.
--- In `play(code, pitch, vol)` and `play_random(codes, ...)` every string argument is a
--- cue name -- pitch and volume are numbers -- so this needs no positional logic.
---@param args string
---@return string[]
local function string_literals(args)
    local out = {}
    local i, n = 1, #args
    while i <= n do
        local c = args:sub(i, i)
        if c == '"' or c == "'" then
            local quote = c
            local start = i + 1
            i = i + 1
            local buf = {}
            while i <= n do
                local d = args:sub(i, i)
                if d == "\\" then
                    buf[#buf + 1] = args:sub(i + 1, i + 1)
                    i = i + 2
                elseif d == quote then
                    break
                else
                    buf[#buf + 1] = d
                    i = i + 1
                end
            end
            if i <= n then out[#out + 1] = table.concat(buf) end
            i = i + 1
            local _ = start
        elseif c == "-" and args:sub(i + 1, i + 1) == "-" then
            -- A comment inside an argument list: skip to end of line.
            local nl = args:find("\n", i, true)
            if not nl then break end
            i = nl + 1
        else
            i = i + 1
        end
    end
    return out
end

--- Byte offset -> 1-based line number.
---@param src string
---@param pos integer
---@return integer
local function line_at(src, pos)
    local _, count = src:sub(1, pos):gsub("\n", "")
    return count + 1
end

--- Every cue-name literal reachable from a play call, with source position.
--- Matches `Sfx.play(...)`, `Sfx.play_random(...)` and, inside sfx.lua itself, the
--- module-local `M.play(...)` used by the convenience wrappers (play_mult and friends).
---@return table[] entries { file, line, cue, call }
---@return integer dynamic count of calls whose cue is not a literal
local function scan_call_sites()
    local entries = {}
    local dynamic = 0

    for _, path in ipairs(game_lua_files()) do
        local fh = io.open(path, "r")
        if fh then
            local src = fh:read("*a")
            fh:close()

            local is_sfx_module = path:match("sfx%.lua$") ~= nil
            local search = 1
            while true do
                local s, e, recv, fn = src:find("([%w_]+)%.(play[%w_]*)%s*%(", search)
                if not s then break end
                search = e + 1

                local relevant = (recv == "Sfx" or (is_sfx_module and recv == "M"))
                    and (fn == "play" or fn == "play_random")
                if relevant then
                    local args = call_args(src, e)
                    if args then
                        local lits = string_literals(args)
                        if #lits == 0 then
                            -- Cue chosen at runtime (a variable or a module-level list).
                            -- Not statically checkable; counted so the test can report it.
                            dynamic = dynamic + 1
                        else
                            local line = line_at(src, s)
                            for _, cue in ipairs(lits) do
                                entries[#entries + 1] = {
                                    file = path:gsub("^" .. ROOT:gsub("%p", "%%%0") .. "/", ""),
                                    line = line,
                                    cue = cue,
                                    call = recv .. "." .. fn,
                                }
                            end
                        end
                    end
                end
            end
        end
    end

    return entries, dynamic
end

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

local SHIPPED = shipped_cues()
local CALL_SITES, DYNAMIC_CALLS = scan_call_sites()

--- Return a short, stable source window from a named function declaration.
---@param text string
---@param declaration string
---@return string
local function function_window(text, declaration)
    local start_at = assert(text:find(declaration, 1, true),
        "could not find " .. declaration)
    return text:sub(start_at, start_at + 3000)
end

---@param text string
---@param needle string
---@param message string
local function assert_contains(text, needle, message)
    T.assert_not_nil(text:find(needle, 1, true), message)
end

suite.test("resources/sounds contains sound files", function()
    local n = 0
    for _ in pairs(SHIPPED) do n = n + 1 end
    T.assert_true(n > 0, "found no .ogg files in " .. SOUND_DIR
        .. " -- the scanner is broken or the assets are missing")
end)

suite.test("the scanner found the play call sites", function()
    -- Guards against the scan silently matching nothing, which would make every other
    -- assertion in this file vacuous.
    T.assert_true(#CALL_SITES >= 20,
        string.format("only found %d literal cue arguments across the repo; "
            .. "the Sfx.play scanner has probably stopped matching", #CALL_SITES))
end)

suite.test("every cue passed to Sfx.play exists in resources/sounds", function()
    local bad = {}
    for _, e in ipairs(CALL_SITES) do
        if not SHIPPED[e.cue] then
            bad[#bad + 1] = string.format("%s:%d: %s(\"%s\") -- no resources/sounds/%s.ogg",
                e.file, e.line, e.call, e.cue, e.cue)
        end
    end
    if #bad > 0 then
        table.sort(bad)
        error({
            __test_failure = true,
            message = string.format("%d play call(s) name a cue with no sound file:\n  %s",
                #bad, table.concat(bad, "\n  ")),
        }, 0)
    end
end)

suite.test("sfx.lua's CUES preload manifest matches the shipped files", function()
    -- The manifest is a preload list, not a whitelist, so a stale entry costs a wasted
    -- load attempt on boot rather than a crash. Still worth catching.
    local src = assert(io.open(ROOT .. "/sfx.lua", "r"))
    local text = src:read("*a")
    src:close()

    local block = text:match("local CUES%s*=%s*{(.-)\n}")
    T.assert_not_nil(block, "could not find the CUES table in sfx.lua")

    local missing = {}
    for cue in block:gmatch('"([^"]+)"') do
        if not SHIPPED[cue] then missing[#missing + 1] = cue end
    end
    if #missing > 0 then
        table.sort(missing)
        error({
            __test_failure = true,
            message = "CUES lists cues with no sound file: " .. table.concat(missing, ", "),
        }, 0)
    end
end)

suite.test("sfx.lua does not preload cues without a port event", function()
    local src = assert(io.open(ROOT .. "/sfx.lua", "r"))
    local text = src:read("*a")
    src:close()
    local block = assert(text:match("local CUES%s*=%s*{(.-)\n}"),
        "could not find the CUES table in sfx.lua")
    local removed = {
        "crumpleLong1", "crumpleLong2", "explosion1", "magic_crumple",
        "magic_crumple2", "magic_crumple3", "voice1", "voice2", "voice3",
        "voice4", "voice5", "voice6", "voice7", "voice8", "voice9",
        "voice10", "voice11", "whoosh", "whoosh_long",
    }
    for _, cue in ipairs(removed) do
        T.assert_false(block:find('"' .. cue .. '"', 1, true) ~= nil,
            cue .. " has no port call site and must not consume preload memory")
    end
end)

suite.test("sfx.lua's STREAMED and VOICES tables name real cues", function()
    local src = assert(io.open(ROOT .. "/sfx.lua", "r"))
    local text = src:read("*a")
    src:close()

    local bad = {}
    for _, tbl in ipairs({ "VOICES", "STREAMED" }) do
        local block = text:match("local " .. tbl .. "%s*=%s*{(.-)\n}")
        T.assert_not_nil(block, "could not find the " .. tbl .. " table in sfx.lua")
        for key in block:gmatch("([%w_]+)%s*=") do
            if not SHIPPED[key] then
                bad[#bad + 1] = tbl .. "." .. key
            end
        end
    end
    if #bad > 0 then
        table.sort(bad)
        error({
            __test_failure = true,
            message = "sfx.lua configures cues with no sound file: " .. table.concat(bad, ", "),
        }, 0)
    end
end)

suite.test("no play call site names a streamed cue", function()
    -- Sfx.play refuses streamed cues outright (the music manager owns them), so a play
    -- call naming one is dead code that looks alive.
    local src = assert(io.open(ROOT .. "/sfx.lua", "r"))
    local text = src:read("*a")
    src:close()

    local streamed = {}
    local block = text:match("local STREAMED%s*=%s*{(.-)\n}")
    T.assert_not_nil(block, "could not find the STREAMED table in sfx.lua")
    for key in block:gmatch("([%w_]+)%s*=%s*true") do streamed[key] = true end

    local bad = {}
    for _, e in ipairs(CALL_SITES) do
        -- sfx.lua's own internals are allowed to mention them.
        if streamed[e.cue] and not e.file:match("sfx%.lua$") then
            bad[#bad + 1] = string.format("%s:%d: %s(\"%s\") is streamed and will never play",
                e.file, e.line, e.call, e.cue)
        end
    end
    if #bad > 0 then
        table.sort(bad)
        error({
            __test_failure = true,
            message = table.concat(bad, "\n  "),
        }, 0)
    end
end)

suite.test("dynamically chosen cues are the exception", function()
    -- A rising count here means the static check is covering less of the codebase.
    -- The shared lists (sfx.lua's GLASS, card.lua's CRUMPLE) legitimately account for a few.
    T.assert_true(DYNAMIC_CALLS <= 12,
        string.format("%d play call(s) pass a non-literal cue; static coverage is eroding",
            DYNAMIC_CALLS))
end)

suite.test("shop and payout cues stay on their reference actions", function()
    local fh = assert(io.open(ROOT .. "/game.lua", "r"))
    local text = fh:read("*a")
    fh:close()

    local buy = function_window(text, "function Game:_play_shop_buy_sfx()")
    assert_contains(buy, 'Sfx.play("card1")', "buy should play card1")
    assert_contains(buy, 'Sfx.play("coin1")', "buy should play coin1")
    T.assert_false(buy:find('Sfx.play("coin3"', 1, true) ~= nil,
        "buy must not use the round-eval cue")

    local sell = function_window(text, "function Game:perform_sell_for_target(sell_target)")
    assert_contains(sell, 'Sfx.play("coin2")', "sell should play coin2")
    T.assert_false(sell:find('Sfx.play("other1")', 1, true) ~= nil,
        "sell must not use the reroll layer")

    local reroll = function_window(text, "function Game:reroll_shop_offers()")
    assert_contains(reroll, 'Sfx.play("coin2")', "reroll should play coin2")
    assert_contains(reroll, 'Sfx.play("other1")', "reroll should play other1")

    local voucher = function_window(text, "function Game:buy_shop_voucher(slot_index)")
    assert_contains(voucher, 'Sfx.play("card1")', "voucher redeem should play card1")
    assert_contains(voucher, 'Sfx.play("coin1")', "voucher redeem should play coin1")

    local cash_out = function_window(text, "function Game:continue_from_round_win()")
    assert_contains(cash_out, 'Sfx.play("coin7")', "cash out should play coin7")
    T.assert_false(cash_out:find('Sfx.play("chips2")', 1, true) ~= nil,
        "cash out must not replay the score-commit sting")

    -- `common_events.lua:1015-1016`: a row lands on `cancel` at the ladder pitch, not a coin.
    -- The coins belong to the cash-out itself.
    local payout = function_window(text, "function Game:_reveal_one_round_win_line()")
    assert_contains(payout, 'Sfx.play("cancel", pitch)', "each payout row should play cancel")
    assert_contains(payout, 'Sfx.play("highlight1", 1.5 * pitch, 0.2)', "paired with its ping")
    assert_contains(payout, 'Sfx.play("coin3"', "each payout row should play coin3")
    assert_contains(payout, 'Sfx.play("coin6"', "each payout row should play coin6")
end)

suite.test("verified hand and blind feedback cues stay attached to their events", function()
    local hand_fh = assert(io.open(ROOT .. "/hand.lua", "r"))
    local hand_text = hand_fh:read("*a")
    hand_fh:close()
    assert_contains(function_window(hand_text, "function Hand:sort_by_rank(layout_skip_vt_node)"),
        'Sfx.play("paper1")', "sorting by rank should play paper1")
    assert_contains(function_window(hand_text, "function Hand:sort_by_suit(layout_skip_vt_node)"),
        'Sfx.play("paper1")', "sorting by suit should play paper1")

    local game_fh = assert(io.open(ROOT .. "/game.lua", "r"))
    local game_text = game_fh:read("*a")
    game_fh:close()
    local blind = function_window(game_text, "function Game:_commit_selected_blind()")
    assert_contains(blind, 'Sfx.play("chips1"', "blind requirement should play chips1")
    assert_contains(blind, 'Sfx.play("gold_seal"', "blind requirement should play gold_seal")
end)

suite.test("special-purpose cues remain reserved for their reference events", function()
    local sfx_fh = assert(io.open(ROOT .. "/sfx.lua", "r"))
    local sfx_text = sfx_fh:read("*a")
    sfx_fh:close()
    local chips = sfx_text:match("function M%.play_chips%(pitch, vol%)(.-)\nend")
    T.assert_not_nil(chips, "could not find Sfx.play_chips body")
    assert_contains(chips, 'M.play("chips1", pitch, vol)', "scoring ladder should use chips1")
    T.assert_false(chips:find("M.play_random", 1, true) ~= nil,
        "scoring ladder must not select the chips2 commit sting")

    local tag_fh = assert(io.open(ROOT .. "/tag.lua", "r"))
    local tag_text = tag_fh:read("*a")
    tag_fh:close()
    local activation = function_window(tag_text, "function Tag:Use(context)")
    assert_contains(activation, 'Sfx.play("generic1"', "tag activation should play generic1")
    assert_contains(activation, 'Sfx.play("holo1"', "tag activation should play holo1")

    local game_fh = assert(io.open(ROOT .. "/game.lua", "r"))
    local game_text = game_fh:read("*a")
    game_fh:close()
    assert_contains(game_text, 'Sfx.play("tarot2", 1, 0.4)',
        "Nope! should play its initial tarot2 note")
    assert_contains(game_text, 'Sfx.play("tarot2", 0.76, 0.4)',
        "Nope! should play its delayed tarot2 note")
end)

return suite
