--- The batching flush's state barriers, checked against the patch source.
---
--- citro3d applies blend, scissor, cull, colour-mask, stencil and viewport changes inside the
--- NEXT draw submission rather than at the call, so anything the renderer has queued when one
--- of them arrives would be drawn under state it was never issued under. That was already
--- wrong before the coalescing flush; coalescing makes the queues longer, and would have made
--- it visible.
---
--- None of that can be observed without a PICA200, and the failure mode of removing a barrier
--- is a subtle wrong-looking frame rather than a crash. What CAN be checked anywhere is the
--- structure: that every setter which mutates global GPU state flushes first, and that the run
--- key still compares everything a single submission cannot express two of. Both are one-line
--- deletions away from silently regressing, which is what this guards.
---
--- The on-hardware counterpart is benchmark.lua's `batch_alternating_20` (submits must stay at
--- 20) and `batch_barrier_scissor` (submits must be 3, not 1).

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

suite.test("every state setter flushes before it mutates GPU state", function()
    local source = patcher_source()

    -- Each entry is a fragment of the patched replacement that must sit immediately after a
    -- FlushBarrier call, so a barrier that is deleted or moved below the mutation is caught.
    local setters = {
        { name = "SetScissor", after = "this->targets[love::GetActiveScreen()].SetScissor" },
        { name = "SetStencil", after = "C3D_StencilTest(enabled" },
        { name = "SetMeshCullMode", after = "C3D_CullFace(*cullMode)" },
        { name = "SetColorMask", after = "this->context.colorMask = mask;" },
        { name = "SetBlendMode", after = "this->context.blendState = state;" },
        { name = "SetViewport", after = "this->viewport = rect;" },
    }

    -- Matched literally rather than as a pattern: the C++ is full of brackets and dots, and
    -- an accidentally-escaped one would make this pass for the wrong reason.
    for _, setter in ipairs(setters) do
        local expected = "    Renderer::FlushBarrier();\n\n    " .. setter.after
        T.assert_true(source:find(expected, 1, true) ~= nil,
            setter.name .. " must flush the queue before it changes GPU state")
    end
end)

suite.test("the barrier helper counts and flushes", function()
    local source = patcher_source()
    T.assert_true(source:find("static void FlushBarrier()", 1, true) ~= nil,
        "the helper should exist")
    -- A barrier that forgot to flush would be a correctness bug wearing a counter.
    local helper = source:match("static void FlushBarrier%(%)%s*{(.-)\n%s*}")
    T.assert_true(helper ~= nil, "the helper body should be findable")
    T.assert_true(helper:find("FlushVertices();", 1, true) ~= nil,
        "the barrier must actually flush")
    T.assert_true(helper:find("counters.stateBarriers", 1, true) ~= nil,
        "and count itself, so a report can say what broke the runs up")
end)

suite.test("the run key compares everything one submission cannot express twice", function()
    local source = patcher_source()
    local key = source:match("if %(next%.format != head%.format(.-)\n%s*break;")
    T.assert_true(key ~= nil, "the run-extension test should be findable")

    -- Texture is deliberately absent: Render() has already flushed on every texture change,
    -- so the whole queue shares one bound texture. Colour is deliberately absent too: it is
    -- baked per vertex, which is what lets a hand of differently tinted cards batch.
    T.assert_true(key:find("next.type != head.type", 1, true) ~= nil,
        "primitive type must break a run")
    T.assert_true(key:find("next.shader != head.shader", 1, true) ~= nil,
        "shader must break a run")
end)

suite.test("the vertex arena is bounds-checked before it is written", function()
    local source = patcher_source()

    T.assert_true(source:find("m_vertexOffset + head.count > (size_t)VERTEX_BUFFER_SIZE", 1, true)
        ~= nil, "checked before the first command of a run")
    -- At its MERGED cost, which is the larger one: taking a four-vertex fan apart into
    -- triangles writes six. Budgeting the unmerged cost would overrun by half.
    T.assert_true(
        source:find("m_vertexOffset + staged + cost > (size_t)VERTEX_BUFFER_SIZE", 1, true)
        ~= nil, "and before every command that extends one, at its merged cost")
    T.assert_true(source:find("counters.preventedOverflows", 1, true) ~= nil,
        "and a drop must be counted rather than silent")
end)

--- The index buffer is gone, and must stay gone: submitting one hangs this GPU. The finding
--- cost a bisection session on hardware and is the kind of thing that gets re-attempted by
--- someone reading the flush and noticing the duplicated corners.
suite.test("nothing submits an indexed draw", function()
    local source = patcher_source()
    T.assert_true(source:find("C3D_DrawElements(GPU_TRIANGLES, (int)used", 1, true) == nil,
        "the batching flush must not submit indexed draws")
    T.assert_true(source:find("HANGS THE GPU", 1, true) ~= nil,
        "and the reason must stay written down where the next person will look")
end)

return suite
