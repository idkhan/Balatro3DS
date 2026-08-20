--- The on-device benchmark harness.
---
--- The numbers only mean anything on hardware, so what is testable here is the harness: that
--- every case runs, that none of them throws, that a case which cannot run is reported as
--- skipped rather than as a suspiciously fast zero, and that the run terminates and produces
--- a report. A case that silently fails on device would be worse than no benchmark at all.

local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

--- Drive the whole suite the way the menu screen does: update then draw, one frame at a
--- time, until it reports itself finished.
local function run_to_completion(game, Benchmark, max_frames)
    local frames = 0
    Benchmark.start(game)
    while Benchmark.is_running() and frames < (max_frames or 4000) do
        frames = frames + 1
        Benchmark.update(game, 1 / 60)
        Benchmark.draw_step(game)
    end
    return frames
end

--- The stub clock is frozen so tests stay deterministic, which would make every case
--- measure exactly zero. A monotonic counter is enough to exercise the arithmetic.
local function with_moving_clock(body)
    local original_time = love.timer.getTime
    local original_write = love.filesystem and love.filesystem.write
    local tick = 0
    love.timer.getTime = function()
        tick = tick + 0.0001
        return tick
    end
    love.filesystem = love.filesystem or {}
    local wrote
    love.filesystem.write = function(name, data) wrote = { name = name, data = data } return true end

    local ok, err = pcall(body, function() return wrote end)

    love.timer.getTime = original_time
    if original_write then love.filesystem.write = original_write end
    if not ok then error(err, 0) end
end

suite.test("every case completes without throwing", function()
    local game = bootstrap.new_game(1)
    local Benchmark = require("benchmark")
    with_moving_clock(function()
        local frames = run_to_completion(game, Benchmark)
        T.assert_true(Benchmark.is_finished(), "the run should terminate")
        T.assert_true(frames < 4000, "and not spin: took " .. frames .. " frames")

        local failed = {}
        for _, r in ipairs(Benchmark.results()) do
            if r.value == nil and r.status ~= "skipped" then
                failed[#failed + 1] = r.group .. "/" .. r.name
            end
        end
        T.assert_eq(#failed, 0, "cases that threw: " .. table.concat(failed, ", "))
    end)
end)

--- No frame may finish two cases. The `stepped_this_frame` guard is what enforces it, and
--- it matters for two reasons: a frame that ran a CPU case and then a draw case would fold
--- both their costs into one frame's budget, and the progress readout would skip. Draw cases
--- now span several frames, so a frame advancing nothing is normal -- what must never happen
--- is a frame advancing two.
suite.test("no frame completes more than one case", function()
    local game = bootstrap.new_game(1)
    local Benchmark = require("benchmark")
    with_moving_clock(function()
        Benchmark.start(game)
        local previous, frames = 0, 0
        while Benchmark.is_running() and frames < 4000 do
            frames = frames + 1
            Benchmark.update(game, 1 / 60)
            Benchmark.draw_step(game)
            local done = select(1, Benchmark.progress())
            T.assert_true(done - previous <= 1, string.format(
                "frame %d advanced %d cases", frames, done - previous))
            previous = done
        end
        T.assert_true(Benchmark.is_finished(), "and the run still finishes")
    end)
end)

suite.test("the run reports progress against a real total", function()
    local game = bootstrap.new_game(1)
    local Benchmark = require("benchmark")
    with_moving_clock(function()
        Benchmark.start(game)
        local done, total = Benchmark.progress()
        T.assert_eq(done, 0, "nothing done yet")
        T.assert_true(total > 20, "the suite should be substantial, got " .. total)
        run_to_completion(game, Benchmark)
        local final_done, final_total = Benchmark.progress()
        T.assert_eq(final_done, final_total, "every case accounted for")

        -- Some cases also record detail rows -- draw-command counts, the frame case's c3d
        -- split -- marked by the "  ^" name prefix, so results are a superset of cases;
        -- every case must still contribute exactly one primary row.
        local timing_rows, detail_rows = 0, 0
        for _, r in ipairs(Benchmark.results()) do
            if r.name:sub(1, 3) == "  ^" then detail_rows = detail_rows + 1
            else timing_rows = timing_rows + 1 end
        end
        T.assert_eq(timing_rows, final_total, "one primary row per case")
        T.assert_true(detail_rows > 0, "the composite cases should report draw commands")
    end)
end)

suite.test("a finished run writes a paged report", function()
    local game = bootstrap.new_game(1)
    local Benchmark = require("benchmark")
    with_moving_clock(function(wrote)
        run_to_completion(game, Benchmark)
        local report = Benchmark.report()
        T.assert_true(report ~= nil and #report > 0, "there should be a report")
        T.assert_true(report:find("environment", 1, true) ~= nil, "it names the environment")
        T.assert_true(report:find("particles", 1, true) ~= nil, "and the particle group")

        local written = wrote()
        T.assert_true(written ~= nil, "the report is written out")
        T.assert_eq(written.name, Benchmark.REPORT_FILE, "to the expected file")
        T.assert_eq(written.data, report, "with the report as its contents")
        T.assert_true(Benchmark.page_count(game) > 1, "and it pages")
    end)
end)

suite.test("paging clamps at both ends", function()
    local game = bootstrap.new_game(1)
    local Benchmark = require("benchmark")
    with_moving_clock(function()
        run_to_completion(game, Benchmark)
        local count = Benchmark.page_count(game)
        T.assert_eq(Benchmark.turn_page(game, -5), 1, "cannot page before the first")
        T.assert_eq(Benchmark.turn_page(game, count + 10), count, "or past the last")
        T.assert_eq(Benchmark.turn_page(game, -1), count - 1, "and steps back normally")
    end)
end)

--- A case whose fixture is missing has to say so. Reporting it as 0.000 us would read as
--- "this operation is free", which is the opposite of the truth.
suite.test("an unavailable case is skipped, not recorded as zero", function()
    local game = bootstrap.new_game(1)
    local Benchmark = require("benchmark")
    local original = love.graphics.newMesh
    love.graphics.newMesh = nil
    with_moving_clock(function()
        run_to_completion(game, Benchmark)
        local skipped = 0
        for _, r in ipairs(Benchmark.results()) do
            if r.status == "skipped" then
                skipped = skipped + 1
                T.assert_eq(r.value, nil, r.name .. " should carry no value")
            end
        end
        T.assert_true(skipped > 0, "the mesh cases should be skipped without newMesh")
    end)
    love.graphics.newMesh = original
    -- The probe caches its answer for the process, so it has to be cleared or every later
    -- test in the suite sees batching as unavailable.
    require("particles").reset_batch_probe()
end)

--- The suite mutates the particle pool and loads textures; leaving either changed would
--- corrupt whatever the player does next.
suite.test("the run leaves particle batching off", function()
    local game = bootstrap.new_game(1)
    local Benchmark = require("benchmark")
    local Particles = require("particles")
    with_moving_clock(function()
        run_to_completion(game, Benchmark)
        local enabled = Particles.batched()
        T.assert_eq(enabled, false, "batching must not leak out of the benchmark")
    end)
end)

--- The suite warms atlases, switches blend modes, flips particle batching and writes a
--- scratch file. Anything it leaves behind lands on whatever the player does next, so the
--- run has to put it all back.
suite.test("the run restores the state it disturbed", function()
    local game = bootstrap.new_game(1)
    local Benchmark = require("benchmark")
    local Particles = require("particles")

    local removed
    love.filesystem = love.filesystem or {}
    local original_remove = love.filesystem.remove
    love.filesystem.remove = function(name) removed = name return true end

    with_moving_clock(function()
        run_to_completion(game, Benchmark)
    end)

    love.filesystem.remove = original_remove

    T.assert_eq(Particles.batched(), false, "particle batching is back off")
    T.assert_eq(game.ASSET_ATLAS.centers.image, nil, "centers is freed again")
    T.assert_eq(game.ASSET_ATLAS.cards_2.image, nil, "cards_2 is freed again")
    T.assert_eq(removed, "benchmark_scratch.bin", "the scratch file is cleaned up")
end)

--- Every case has to be reachable. A typo in a phase would leave a case that no caller ever
--- steps, and the run would stall on it until the frame guard gave up.
--- A case whose `phase` no caller steps would hold the index forever, so what has to be
--- proven is that every case is reached and released. Exact frame accounting stopped being
--- the way to show that once draw cases began spanning frames: a case skipped for a missing
--- fixture releases the index on its first frame rather than running its chunks, and how
--- many are skipped depends on what the host provides. So the bound is asserted instead,
--- with the stronger guarantee -- every case produced exactly one row -- carried by the
--- progress test above.
suite.test("every case is claimed by a phase that runs it", function()
    local game = bootstrap.new_game(1)
    local Benchmark = require("benchmark")
    with_moving_clock(function()
        local frames = run_to_completion(game, Benchmark)
        local _, total = Benchmark.progress()
        -- At least one frame per case, plus the frame that notices the list is done.
        T.assert_true(frames >= total + 1,
            "every case needs a frame: " .. frames .. " for " .. total)
        -- And never more than the chunking schedule calls for.
        T.assert_true(frames <= total + Benchmark.extra_frames() + 1,
            "no case overran its schedule: " .. frames .. " frames for " .. total .. " cases")
    end)
end)

--- The crash this whole chunking mechanism exists to prevent: on hardware the frame's vertex
--- buffer is 24576 vertices, written with no bounds check, so a case that submits more than
--- that inside one frame corrupts the linear heap and takes the console down several cases
--- later. Every draw case that submits geometry must therefore declare a `verts` cost, and
--- its per-frame chunk must fit the budget.
suite.test("no draw case can overrun the frame vertex buffer", function()
    local Benchmark = require("benchmark")
    local budget, cases = Benchmark.vertex_budget()
    T.assert_true(budget <= 24576, "the budget must fit the hardware buffer")

    for _, c in ipairs(cases) do
        if c.phase == "draw" then
            T.assert_true(c.verts * c.chunk <= budget, string.format(
                "%s submits %d vertices a frame, over the %d budget",
                c.name, c.verts * c.chunk, budget))
            -- A case that draws but claims zero vertices would silently skip chunking, which
            -- is the exact hole that crashed the console.
            -- The only case that may draw without a declared cost is one submitting through
            -- its own vertex buffer, and it has to say so.
            if c.count_draws and not c.own_buffer then
                T.assert_true(c.verts > 0, c.name .. " draws but declares no vertex cost")
            end
        end
    end
end)

--- The submit probe. It is the only part of the harness whose arithmetic can be wrong
--- without anything throwing, and getting it wrong is what produced "70 draw commands, 0 gpu
--- submits" on the first hardware run: the renderer only submits queued commands at a flush,
--- so a counter read inside the frame that issued them describes the previous flush.
---
--- The stub models exactly that. Draw calls accumulate into `pending`; `latched` is copied
--- from `pending` at the end of each frame, which is what the runtime does at Present; and
--- `getBatchStats` only ever returns `latched`. If the probe read its own frame, or compared
--- the wrong pair of frames, the recorded count would not equal the number of draws the case
--- actually issues.
suite.test("the draw-count probe measures the frame the case ran in", function()
    local game = bootstrap.new_game(1)
    local Benchmark = require("benchmark")

    local FIELDS = { "logical", "submits", "runs", "maxrun", "texbinds", "barriers",
                     "verts", "indices", "allocs" }
    local pending, latched = {}, {}
    for _, key in ipairs(FIELDS) do pending[key], latched[key] = 0, 0 end

    local originals = {}
    for _, name in ipairs({ "draw", "rectangle", "print", "printf" }) do
        originals[name] = love.graphics[name]
        love.graphics[name] = function(...)
            pending.logical = pending.logical + 1
            pending.submits = pending.submits + 1
            return originals[name](...)
        end
    end
    love.graphics.getBatchStats = function()
        local copy = { batching = true, vcapacity = 24576, icapacity = 49152 }
        for _, key in ipairs(FIELDS) do copy[key] = latched[key] end
        return copy
    end

    with_moving_clock(function()
        Benchmark.start(game)
        local frames = 0
        while Benchmark.is_running() and frames < 8000 do
            frames = frames + 1
            Benchmark.update(game, 1 / 60)
            Benchmark.draw_step(game)
            for _, key in ipairs(FIELDS) do latched[key] = pending[key] end
        end
        T.assert_true(Benchmark.is_finished(), "the run still terminates")

        -- batch_rects_60_untextured issues exactly sixty rectangle calls per repetition, and
        -- nothing else in the harness draws under the stub, so the probe's answer is knowable
        -- to the unit.
        -- Order matters as much as the value: results are printed in the order they are
        -- recorded, so a detail row written before its case's own row is printed under the
        -- name of the case above it. The first hardware report read "particles_rect_70 ...
        -- 1 draw command" for exactly that reason.
        local rows, seen = Benchmark.results(), false
        for i, r in ipairs(rows) do
            if r.name == "batch_rects_60_untextured" then
                local counted = rows[i + 1]
                T.assert_true(counted ~= nil and counted.name == "  ^ draw commands",
                    "the case's own row comes first, then its detail rows")
                T.assert_eq(counted.value, 60, "one row per rectangle the case draws")
                seen = true
            end
        end
        T.assert_true(seen, "the batching case should be present and probed")
    end)

    for name, fn in pairs(originals) do love.graphics[name] = fn end
    love.graphics.getBatchStats = nil
end)

--- The frame case samples across real frames rather than looping inside one, so its
--- machinery is different from every other case's and deserves its own check: it must
--- produce a primary timing row from the sampled deltas, not stall and not read as zero.
suite.test("the frame case records a sampled frame time", function()
    local game = bootstrap.new_game(1)
    local Benchmark = require("benchmark")
    with_moving_clock(function()
        run_to_completion(game, Benchmark)
        local row
        for _, r in ipairs(Benchmark.results()) do
            if r.name == "frame_time_60" then row = r end
        end
        T.assert_true(row ~= nil, "the frame case should report")
        T.assert_true(row.value ~= nil and row.value > 0,
            "with a real sampled dt, got " .. tostring(row and row.value))
        T.assert_eq(row.unit, "ms", "in milliseconds")
    end)
end)

return suite

