--- The batching flush's index conversion, compiled and run on the host.
---
--- Everything else about the coalescing renderer needs a PICA200 to observe. This does not:
--- fan-to-triangle-list conversion is pure arithmetic, it lives in a header with no 3DS
--- dependency for exactly that reason, and getting it wrong draws the wrong triangles without
--- throwing anything. So the header the console compiles is compiled here too, against a
--- separately written statement of what a fan and a strip are defined to rasterise.
---
--- Skipped rather than failed when the LovePotion checkout is not present, which is a fresh
--- clone and is CI. `./dev/setup.sh` is what makes it run.

local T = require("tests.testlib")
local suite = T.suite()

local ROOT = os.getenv("BALATRO_ROOT") or "."
local INCLUDE = ROOT .. "/dev/.cache/lovepotion/platform/ctr/include"
local HEADER = INCLUDE .. "/utilities/driver/batch_indices.hpp"
local SOURCE = ROOT .. "/tests/native/batch_indices_test.cpp"

local function exists(path)
    local handle = io.open(path, "r")
    if not handle then return false end
    handle:close()
    return true
end

local function run(command)
    local pipe = io.popen(command .. " 2>&1")
    if not pipe then return nil, "popen failed" end
    local output = pipe:read("*a")
    local ok = pipe:close()
    return ok and true or false, output
end

suite.test("fans and strips convert to the triangles they rasterise", function()
    if not exists(HEADER) then
        T.skip("no patched LovePotion checkout; run ./dev/setup.sh")
    end

    local compiler = os.getenv("CXX")
    if not compiler then
        local ok = run("command -v c++")
        compiler = ok and "c++" or nil
    end
    if not compiler then
        T.skip("no host C++ compiler")
    end

    -- os.tmpname() creates the file, and a compiler writing over an existing plain file does
    -- not add the execute bit -- so take the name, drop the file, and build alongside it.
    local stem = os.tmpname()
    os.remove(stem)
    local binary = stem .. "_batchtest"
    local ok, output = run(string.format(
        "%s -std=c++20 -O1 -I%q %q -o %q", compiler, INCLUDE, SOURCE, binary))
    -- LuaJIT's file:close() on a popen handle does not report the child's exit status, so a
    -- failed compile looks like a success. The binary either exists or it does not.
    if not (ok and exists(binary)) then
        os.remove(binary)
        error("the triangle helpers did not compile:\n" .. tostring(output), 0)
    end

    local ran, result = run(string.format("%q", binary))
    os.remove(binary)
    T.assert_true(ran, "the index conversion checks failed:\n" .. tostring(result))
    T.assert_true(result:find("ok", 1, true) ~= nil,
        "expected the harness to report ok, got:\n" .. tostring(result))
end)

return suite
