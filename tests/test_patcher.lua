--- The LövePotion patcher's idempotency.
---
--- `dev/patch_lovepotion.py` is anchor-based string surgery against upstream sources, and the
--- only thing stopping a second run from applying every patch twice is each spec's marker --
--- a string that must appear in the file AFTER the patch lands. A marker that never matches
--- its own output is invisible, because `dev/setup.sh` hard-resets the checkout before
--- patching and so nothing ever patches twice in practice. Two of them had been wrong for
--- months: one differed from the inserted text by a capital letter, and one was written across
--- a line break.
---
--- The script now checks its own markers, which turns that into a first-run failure. This runs
--- it twice against the already-patched checkout to prove the check works and that a re-run is
--- genuinely a no-op. Skipped without a checkout, which is a fresh clone and CI.

local T = require("tests.testlib")
local suite = T.suite()

local ROOT = os.getenv("BALATRO_ROOT") or "."
local CHECKOUT = ROOT .. "/dev/.cache/lovepotion"
local PATCHER = ROOT .. "/dev/patch_lovepotion.py"
local PATCHED_MARK = CHECKOUT .. "/platform/ctr/include/utilities/driver/batch_indices.hpp"

local function exists(path)
    local handle = io.open(path, "r")
    if not handle then return false end
    handle:close()
    return true
end

local function run(command)
    local pipe = io.popen(command .. " 2>&1")
    if not pipe then return false, "popen failed" end
    local output = pipe:read("*a")
    local ok = pipe:close()
    return ok and true or false, output
end

suite.test("re-running the patcher against a patched checkout is a no-op", function()
    if not exists(PATCHER) then T.skip("no patcher") end
    -- Only run against a checkout that is ALREADY patched: patching a pristine one here would
    -- be a test with a side effect on the build tree.
    if not exists(PATCHED_MARK) then
        T.skip("no patched LovePotion checkout; run ./dev/setup.sh")
    end

    for attempt = 1, 2 do
        local ok, output = run(string.format("python3 %q %q romfs:/Balatro3DS", PATCHER, CHECKOUT))
        T.assert_true(ok, "run " .. attempt .. " should succeed:\n" .. tostring(output))
        T.assert_true(output:find("already patched", 1, true) ~= nil,
            "run " .. attempt .. " should recognise the file as patched:\n" .. tostring(output))
        T.assert_true(output:find("^patched:") == nil,
            "and should not have applied anything again")
    end
end)

return suite
