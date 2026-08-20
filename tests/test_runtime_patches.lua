--- Invariants of the runtime patches that cannot be observed without a 3DS.
---
--- Two of the changes in the hardware optimisation pass have failure modes that no headless
--- harness can reach and that hardware only shows as "something looks slightly wrong" or, in
--- the worker's case, as an intermittent crash. Both are also one careless edit away from
--- regressing. So what is asserted here is the structure of the patch source: not that the
--- code is correct, but that the specific properties correctness rests on are still stated.
---
--- The behavioural counterparts are on the console: `benchmark.txt`'s backdrop worker line,
--- `backdrop_frame` against `backdrop_frame_sync`, and `image_quad_draw`.

local T = require("tests.testlib")
local suite = T.suite()

local ROOT = os.getenv("BALATRO_ROOT") or "."

local function patcher_source()
    local handle = io.open(ROOT .. "/dev/patch_lovepotion.py", "r")
    assert(handle, "dev/patch_lovepotion.py should be readable")
    local text = handle:read("*a")
    handle:close()
    return text
end

local function contains(source, needle, why)
    T.assert_true(source:find(needle, 1, true) ~= nil, why)
end

--------------------------------------------------------------------------------
-- the Quad texture-coordinate cache
--------------------------------------------------------------------------------

--- The cache holds PICA-ready coordinates on the Quad, and the same Quad can legitimately be
--- drawn against textures of different physical sizes -- a 1000x600 atlas is padded to
--- 1024x1024 and the padded size is the divisor. Keying on the Quad alone would hand the
--- second texture the first one's UVs, which reads as art sampled from the wrong place.
suite.test("the quad UV cache is keyed on everything that changes the answer", function()
    local source = patcher_source()

    contains(source, "bool CtrCoordsValid(float physicalWidth, float physicalHeight, bool renderTarget) const",
        "the key must take the physical size and the render-target flag")
    contains(source, "this->ctrPhysicalWidth == physicalWidth",
        "physical width must be compared")
    contains(source, "this->ctrPhysicalHeight == physicalHeight",
        "physical height must be compared")
    contains(source, "this->ctrRenderTarget == renderTarget",
        "a render target's coordinates are oriented differently and must not be shared")
end)

suite.test("changing a quad's viewport drops its cached coordinates", function()
    local source = patcher_source()

    -- Quad::Refresh is the only door into the coordinates other than the flip in texture_ext,
    -- and Quad:setViewport from Lua goes through it. Matched as the whole patched prologue so
    -- the invalidation cannot drift below the write it is protecting.
    contains(source, "    this->ctrCoordsReady = false;\n\n    this->viewport     = viewport;",
        "Refresh must invalidate before it rewrites anything")
end)

suite.test("the render-target branch marks the cache too", function()
    local source = patcher_source()
    -- Two exits from refreshQuad, and an unmarked one would re-do the work every frame --
    -- silently, since the output would still be correct.
    local marks = 0
    for _ in source:gmatch("quad%->MarkCtrCoordsValid%(physicalDim%.x, physicalDim%.y, isRenderTarget%)") do
        marks = marks + 1
    end
    T.assert_eq(marks, 2, "both the render-target and the ordinary exit must mark the cache")
end)

--------------------------------------------------------------------------------
-- the New 3DS field worker
--------------------------------------------------------------------------------

--- The worker's whole safety argument is that it touches nothing but its own float buffer. A
--- C3D call from the second core would be a race against the renderer over citro3d's global
--- context, and it would show up as intermittent corruption rather than as a crash at the
--- offending line.
suite.test("the worker makes no GPU call", function()
    local source = patcher_source()
    local body = source:match("void FieldWorkerMain%(void%*%)%s*\n%s*{(.-)\n    }\n")
    T.assert_true(body ~= nil, "the worker body should be findable")

    -- Comments explain what the worker deliberately does NOT do, and name the calls it must
    -- not make while doing so. Strip them, or the test fails on its own justification.
    local code = body:gsub("/%*.-%*/", "")

    for _, forbidden in ipairs({ "C3D_", "GPUCMD_", "Renderer<", "FlushVertices", "lua_" }) do
        T.assert_true(code:find(forbidden, 1, true) == nil,
            "the worker must not call " .. forbidden .. ": it runs beside the renderer")
    end

    -- What it IS allowed to do, and must: write the field, and write it back out of the cache
    -- of the core that computed it.
    contains(code, "UpdateField(", "the worker's job is the field")
    contains(code, "svcFlushProcessDataCache(CUR_PROCESS_HANDLE",
        "the core that wrote the data must be the core that flushes it")

    -- Not GSPGPU_FlushDataCache. The two sound interchangeable and are not: that one is an IPC
    -- round trip on the gsp::Gpu session handle the main thread uses continuously for its own
    -- GX submissions, and reaching for it from a second core was the first version of this.
    T.assert_true(code:find("GSPGPU_", 1, true) == nil,
        "the worker must not touch the gsp session; it is not its to use")
end)

suite.test("the worker is only ever started on a New 3DS, on the spare core", function()
    local source = patcher_source()
    local body = source:match("bool StartFieldWorker%(%)%s*\n%s*{(.-)\n    }\n")
    T.assert_true(body ~= nil, "the start function should be findable")

    contains(body, "APT_CheckNew3DS(&isNew3DS)", "the console has to be asked")
    contains(body, "if (!isNew3DS)", "and an Old 3DS must decline")
    contains(body, "threadCreate(FieldWorkerMain, nullptr, 16 * 1024, priority, 2, false)",
        "core 2 is the spare application core; core 1 would need an APT CPU time grant")
    contains(body, "if (g_worker.thread == nullptr)", "a failed creation must fall back")
    contains(body, "synchronous", "and both fallbacks must say so in the status")
end)

suite.test("the frame path never waits for the worker", function()
    local source = patcher_source()
    -- The drain exists, but only the debug toggle may call it: a frame that blocks on the
    -- worker would trade a background cost for a foreground stall, which is the opposite of
    -- the point.
    local drains = 0
    for _ in source:gmatch("FieldWorkerDrain%(%)") do drains = drains + 1 end
    T.assert_eq(drains, 2, "one definition and exactly one caller")
    contains(source, "if (!enabled && g_worker.started)\n        FieldWorkerDrain();",
        "and that caller is the A/B toggle")

    -- The frame path's only interaction is a non-blocking test.
    contains(source, "if (!g_worker.busy)",
        "a frame checks whether a job finished; it does not wait for one")
end)

suite.test("the worker is joined at exit", function()
    local source = patcher_source()
    local body = source:match("struct FieldWorkerShutdown%s*\n%s*{(.-)\n    };")
    T.assert_true(body ~= nil, "the shutdown hook should be findable")
    contains(body, "g_worker.quit = true", "it has to ask the worker to stop")
    contains(body, "LightEvent_Signal(&g_worker.wake)", "and wake it to notice")
    contains(body, "threadJoin(g_worker.thread, U64_MAX)", "and wait for it")
    contains(body, "threadFree(g_worker.thread)", "and release it")
end)

--- The two paths write the same back buffer, so they must not both be live, and they must not
--- share the band counter -- which is why it became an argument.
suite.test("the synchronous and worker paths cannot race over the band counter", function()
    local source = patcher_source()
    contains(source, "void UpdateField(Grid& grid, float* vbo, int mode, float sp, float A, float B, float K,\n                     int band)",
        "the band must be an argument, not state on the grid")
    contains(source, "const int first = (rows * band) / FIELD_BANDS;",
        "and the range must come from that argument")
end)

--- One worker, two grids -- 400 wide for the top screen, 320 for the bottom -- and both draw
--- every frame. "Whoever finds the worker idle posts for itself" hands every job to whichever
--- screen draws first, and the other grid never gets a sweep after its initial prime: it draws
--- one frozen field for the rest of the session. A New 3DS showed exactly that, a swirling top
--- screen over a still bottom one.
suite.test("the worker is shared between both screens' grids", function()
    local source = patcher_source()

    contains(source, "Grid* target = &grid;",
        "the grid served must be chosen, not assumed to be the calling one")
    contains(source, "if (other.lastPosted < target->lastPosted)",
        "and chosen by which has waited longest")
    contains(source, "target->lastPosted = ++g_bd.postCounter;",
        "with the choice recorded, or the same grid wins every time")
    contains(source, "grid.wants = true;",
        "a grid that is on screen has to register that it wants a sweep")
end)

return suite
