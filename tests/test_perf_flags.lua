--- The SD-card switches for the two subsystems that can only be validated on hardware.
---
--- This exists because the alternative loop is a rebuild and a reinstall per boolean, several
--- minutes a step, while chasing a crash that produces no stack trace. It is also the piece of
--- code that must not itself be able to stop the game booting -- a crash-diagnosis mechanism
--- that crashes is worse than none -- so most of what is checked here is that every bad input
--- lands somewhere harmless.

local T = require("tests.testlib")
require("tests.bootstrap").load()

local PerfFlags = require("perf_flags")
local suite = T.suite()

suite.test("flags parse to the mode number the runtime takes", function()
    local flags = PerfFlags.parse("batching=1\nworker=true\n")
    T.assert_eq(flags.batching, 1, "1 is mode 1")
    T.assert_eq(flags.worker, 1, "true is 1")

    T.assert_eq(PerfFlags.parse("batching=2").batching, 2, "2 selects the indexed mode")

    for _, text in ipairs({ "batching=0", "batching=", "batching=no", "batching=off",
                            "batching=maybe" }) do
        T.assert_eq(PerfFlags.parse(text).batching, 0, text .. " must be off")
    end
end)

suite.test("the format is forgiving about whitespace, case and line endings", function()
    local flags = PerfFlags.parse("  BATCHING = YES \r\nworker=On\r\n")
    T.assert_eq(flags.batching, 1, "keys and values are case-insensitive, spaces ignored")
    T.assert_eq(flags.worker, 1, "and CRLF is a line ending")
end)

suite.test("junk parses to nothing rather than raising", function()
    for _, text in ipairs({ "", "\n\n", "# a comment", "not a flag line",
                            "=1", "batching", string.rep("x", 4096) }) do
        local ok, flags = pcall(PerfFlags.parse, text)
        T.assert_true(ok, "parsing must not raise on: " .. text:sub(1, 20))
        T.assert_eq(flags.batching, nil, "and must not invent a flag")
    end

    local ok = pcall(PerfFlags.parse, nil)
    T.assert_true(ok, "even a nil file must parse")
end)

suite.test("unknown keys are ignored", function()
    local flags = PerfFlags.parse("frobnicate=1\nbatching=1\n")
    T.assert_eq(flags.batching, 1, "the known key still applies")
    T.assert_eq(flags.frobnicate, 1, "unknown keys parse but nothing reads them")
end)

--- Applying has to work on a runtime with neither binding, which is desktop, nest and this
--- stub -- and on one where the binding exists but throws.
suite.test("applying is safe without the bindings", function()
    local g = love.graphics
    local saved = { setBatching = g.setBatching, setBackdropWorker = g.setBackdropWorker }
    g.setBatching, g.setBackdropWorker = nil, nil

    local ok, state = pcall(PerfFlags.apply)

    g.setBatching, g.setBackdropWorker = saved.setBatching, saved.setBackdropWorker
    T.assert_true(ok, "apply must never raise: " .. tostring(state))
    T.assert_eq(state.batching, nil, "and must report that nothing was applied")
end)

suite.test("a throwing binding is contained", function()
    local g = love.graphics
    local saved = { setBatching = g.setBatching, setBackdropWorker = g.setBackdropWorker }
    g.setBatching = function() error("no") end
    g.setBackdropWorker = function() error("no") end

    local ok = pcall(PerfFlags.apply)

    g.setBatching, g.setBackdropWorker = saved.setBatching, saved.setBackdropWorker
    T.assert_true(ok, "a binding that throws must not take the boot down with it")
end)

suite.test("with no file, neither subsystem is touched", function()
    local g = love.graphics
    local saved = { setBatching = g.setBatching, setBackdropWorker = g.setBackdropWorker,
                    getInfo = love.filesystem.getInfo }
    local asked = {}
    g.setBatching = function(on) asked.batching = on end
    g.setBackdropWorker = function(on) asked.worker = on end
    love.filesystem.getInfo = function() return nil end

    local ok, state = pcall(PerfFlags.apply)

    g.setBatching, g.setBackdropWorker = saved.setBatching, saved.setBackdropWorker
    love.filesystem.getInfo = saved.getInfo

    T.assert_true(ok, "apply should succeed")
    T.assert_eq(asked.batching, nil, "the runtime's own default is left alone")
    T.assert_eq(asked.worker, nil, "for both of them")
    T.assert_eq(state.source, "defaults", "and the report should say where that came from")
end)

suite.test("a file that asks for both turns both on", function()
    local g = love.graphics
    local saved = { setBatching = g.setBatching, setBackdropWorker = g.setBackdropWorker,
                    getInfo = love.filesystem.getInfo, read = love.filesystem.read }
    local asked = {}
    g.setBatching = function(on) asked.batching = on end
    g.setBackdropWorker = function(on) asked.worker = on end
    love.filesystem.getInfo = function() return { type = "file" } end
    love.filesystem.read = function() return "batching=1\nworker=1\n" end

    local ok, state = pcall(PerfFlags.apply)

    g.setBatching, g.setBackdropWorker = saved.setBatching, saved.setBackdropWorker
    love.filesystem.getInfo, love.filesystem.read = saved.getInfo, saved.read

    T.assert_true(ok, "apply should succeed")
    T.assert_eq(asked.batching, 1, "batching on")
    T.assert_eq(asked.worker, true, "worker on")
    T.assert_eq(state.source, PerfFlags.FILE, "and the report should name the file")
end)

--- A file that names one subsystem must say nothing about the other, or a bisection step
--- would change two variables at once.
suite.test("a flag file only touches what it names", function()
    local g = love.graphics
    local saved = { setBatching = g.setBatching, setBackdropWorker = g.setBackdropWorker,
                    getInfo = love.filesystem.getInfo, read = love.filesystem.read,
                    write = love.filesystem.write }
    local asked = {}
    g.setBatching = function(on) asked.batching = on end
    g.setBackdropWorker = function(on) asked.worker = on end
    love.filesystem.getInfo = function() return { type = "file" } end
    love.filesystem.read = function() return "batching=0\n" end
    love.filesystem.write = function() return true end

    local ok = pcall(PerfFlags.apply)

    g.setBatching, g.setBackdropWorker = saved.setBatching, saved.setBackdropWorker
    love.filesystem.getInfo, love.filesystem.read = saved.getInfo, saved.read
    love.filesystem.write = saved.write

    T.assert_true(ok, "apply should succeed")
    T.assert_eq(asked.batching, 0, "the named flag applies")
    T.assert_eq(asked.worker, nil, "the unnamed one is left exactly as the runtime had it")
end)

return suite
