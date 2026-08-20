--- Score formatting, ported from `reference/Balatro/functions/misc_functions.lua:956`.
---
--- Two rules, both the reference's:
---
--- * Below the switch point, group the integer part in threes - `6247326` reads `6,247,326`.
---   Without this a seven-figure score is a wall of digits on a 240p panel and the player
---   cannot tell 6 million from 62 million at a glance, which is the whole job of the readout.
--- * At or above the switch point, drop to scientific notation - `1.234e11`. Balatro runs do
---   not plateau; a deep endless run reaches numbers with more digits than the screen has
---   pixels, and grouping them would be no more readable than not.
---
--- Non-integers keep the reference's sliding precision (two decimals under 10, one under 100,
--- none above), so an x-mult of 1.25 does not print as `1`.
local NumberFormat = {}

--- Where grouped digits give way to `1.234e11`. The reference keeps this on `G` so a mod can
--- move it (`misc_functions.lua:957`); nothing here does, so it is a plain constant.
NumberFormat.E_SWITCH_POINT = 100000000000

--- `math.log(x, base)` is a Lua 5.2 addition. LövePotion's 3DS build is Lua 5.1, so the base
--- has to be divided out by hand - the two-argument form would be a runtime error on console
--- while working fine under a 5.2+ desktop host.
local LOG10 = math.log(10)

--- @param num number|nil
--- @return string
function NumberFormat.format(num)
    if type(num) ~= "number" then return tostring(num or "") end

    -- A long enough x-mult chain overflows to inf, and `%.4g` renders that as "inf", which
    -- `tonumber` refuses - the exponent branch below would then call `math.log(nil)` and take
    -- the frame down. The reference has no guard here and does crash on it.
    if num ~= num then return "nan" end
    if num == math.huge or num == -math.huge then return num > 0 and "inf" or "-inf" end

    if num >= NumberFormat.E_SWITCH_POINT then
        -- %.4g first, so the mantissa is rounded to the four digits that will be shown before
        -- the exponent is taken off it (the reference does the same).
        local x = tonumber(string.format("%.4g", num))
        local fac = math.floor(math.log(x) / LOG10)
        -- log is not exact at powers of ten - log(1e12)/log(10) lands a hair under 12 - and the
        -- reference wears that: it prints 9.9999e11 as "10.000e11". Normalising the mantissa
        -- afterwards is cheap and cannot be wrong, since one correction is always enough.
        local mantissa = x / (10 ^ fac)
        if mantissa >= 10 then
            fac = fac + 1
            mantissa = x / (10 ^ fac)
        elseif mantissa < 1 then
            fac = fac - 1
            mantissa = x / (10 ^ fac)
        end
        return string.format("%.3f", mantissa) .. "e" .. fac
    end

    local fmt = "%.0f"
    if num ~= math.floor(num) then
        if num >= 100 then fmt = "%.0f"
        elseif num >= 10 then fmt = "%.1f"
        else fmt = "%.2f" end
    end

    -- Grouping runs back-to-front so it counts from the decimal point rather than the sign:
    -- a leading "-" would otherwise be counted as a digit and shift every separator.
    local s = string.format(fmt, num):reverse():gsub("(%d%d%d)", "%1,"):gsub(",$", "")
    return (s:reverse())
end

return NumberFormat
