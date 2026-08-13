local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local NumberFormat = require("number_format")

local suite = T.suite("number format")

suite.test("integers under a thousand are left alone", function()
    T.assert_eq(NumberFormat.format(0), "0")
    T.assert_eq(NumberFormat.format(7), "7")
    T.assert_eq(NumberFormat.format(300), "300")
    T.assert_eq(NumberFormat.format(999), "999")
end)

suite.test("the integer part is grouped in threes", function()
    T.assert_eq(NumberFormat.format(1000), "1,000")
    T.assert_eq(NumberFormat.format(6247326), "6,247,326")
    T.assert_eq(NumberFormat.format(1234567890), "1,234,567,890")
end)

--- The grouping runs over the reversed string, so a sign in front of the digits is the case
--- most likely to shift every separator by one.
suite.test("a negative number groups from the decimal point, not the sign", function()
    T.assert_eq(NumberFormat.format(-1000), "-1,000")
    T.assert_eq(NumberFormat.format(-6247326), "-6,247,326")
end)

--- Reference sliding precision (`misc_functions.lua:964`): an x-mult of 1.25 has to survive.
suite.test("non-integers keep decimals, fewer as the number grows", function()
    T.assert_eq(NumberFormat.format(1.25), "1.25")
    T.assert_eq(NumberFormat.format(12.5), "12.5")
    T.assert_eq(NumberFormat.format(1234.5), "1,234")
    T.assert_eq(NumberFormat.format(1234567.5), "1,234,568")
end)

suite.test("the switch point hands off to scientific notation", function()
    local e = NumberFormat.E_SWITCH_POINT
    T.assert_eq(NumberFormat.format(e - 1), "99,999,999,999")
    T.assert_eq(NumberFormat.format(e), "1.000e11")
    T.assert_eq(NumberFormat.format(1.234e11), "1.234e11")
    T.assert_eq(NumberFormat.format(5e20), "5.000e20")
end)

--- The reference prints this as "10.000e11": `%.4g` rounds the mantissa up to a full power of
--- ten and its `log` lands a hair under the matching exponent. The mantissa is normalised here
--- instead, which is the one place this deliberately does not match the reference.
suite.test("a mantissa that rounds up carries into the exponent", function()
    T.assert_eq(NumberFormat.format(9.9999e11), "1.000e12")
    T.assert_eq(NumberFormat.format(1e15), "1.000e15")
end)

suite.test("a non-number is passed through rather than raising", function()
    T.assert_eq(NumberFormat.format(nil), "")
    T.assert_eq(NumberFormat.format("None"), "None")
end)

--- `%.4g` of infinity is "inf", which `tonumber` refuses; unguarded, the exponent branch calls
--- `math.log(nil)` and takes the frame down mid-score.
suite.test("a non-finite value is reported rather than raising", function()
    T.assert_eq(NumberFormat.format(math.huge), "inf")
    T.assert_eq(NumberFormat.format(-math.huge), "-inf")
    T.assert_eq(NumberFormat.format(0 / 0), "nan")
end)

--- Every score readout goes through one formatter, so the display sites stay in step. These
--- are the two the player watches most.
suite.test("the score and counter readouts are grouped", function()
    bootstrap.load()
    local g = Game()
    _G.G = g
    local top = TopUI()

    g.round_score = 6247326
    top:update_score(0)
    T.assert_eq(top:score_readout(), "6,247,326")

    T.assert_eq(top:chips_readout(52340), "52,340")
    T.assert_eq(top:mult_readout(1200), "1,200")
    T.assert_eq(top:mult_readout(1.5), "1.50")
end)

--- The memo is keyed on the value, so a rebuild has to follow a change and only a change.
suite.test("the counter memos rebuild on a new value and not otherwise", function()
    bootstrap.load()
    local g = Game()
    _G.G = g
    local top = TopUI()

    local first = top:chips_readout(1000)
    T.assert_true(rawequal(first, top:chips_readout(1000)), "unchanged is not rebuilt")
    T.assert_eq(top:chips_readout(2000), "2,000", "a new value rebuilds")
end)

return suite
