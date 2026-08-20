/* Host-side check of the batching flush's index conversion.
 *
 * The header this includes is the real one the 3DS renderer compiles -- installed into the
 * LovePotion checkout by dev/patch_lovepotion.py -- not a restatement of it. That is the whole
 * point: fan-to-list conversion is the piece of the coalescing flush that fails silently, by
 * drawing the wrong triangles rather than by crashing, and it is also the only piece that does
 * not need citro3d to run.
 *
 * Built and run by tests/test_batch_indices.lua, which skips when the checkout is absent (a
 * fresh clone, or CI) rather than failing.
 */

#include <utilities/driver/batch_indices.hpp>

#include <cstdio>
#include <vector>

using namespace love::batching;

static int failures = 0;

static void check(bool condition, const char* what)
{
    if (!condition)
    {
        std::printf("FAIL %s\n", what);
        failures++;
    }
}

/* The triangles a topology is defined to rasterise, as flat vertex ids, written out
 * independently of the code under test so the comparison is against the definition rather than
 * against itself. */
static std::vector<int> expectedTriangles(Topology topology, size_t count)
{
    std::vector<int> out;
    auto push = [&](size_t a, size_t b, size_t c) {
        out.push_back((int)(1000 + a));
        out.push_back((int)(1000 + b));
        out.push_back((int)(1000 + c));
    };

    if (count < 3)
        return out;

    if (topology == Topology::Fan)
    {
        for (size_t t = 1; t + 1 < count; t++)
            push(0, t, t + 1);
    }
    else if (topology == Topology::Triangles)
    {
        for (size_t t = 0; t + 2 < count; t += 3)
            push(t, t + 1, t + 2);
    }
    else if (topology == Topology::Strip)
    {
        /* GPU_TRIANGLE_STRIP's own winding: even triangles (t, t+1, t+2), odd ones swapped. */
        for (size_t t = 0; t + 2 < count; t++)
        {
            if ((t & 1) == 0)
                push(t, t + 1, t + 2);
            else
                push(t + 1, t, t + 2);
        }
    }

    return out;
}

struct Tagged
{
    int id;
};

static void checkExpansion(Topology topology, size_t count)
{
    std::vector<Tagged> source(count);
    for (size_t i = 0; i < count; i++)
        source[i].id = (int)(1000 + i);

    const size_t expected = TriangleVertexCount(topology, count);

    std::vector<Tagged> expanded(expected + 4, Tagged { -1 });
    Tagged* end = ExpandTriangles(topology, source.data(), count, expanded.data());

    check((size_t)(end - expanded.data()) == expected,
          "ExpandTriangles wrote exactly TriangleVertexCount() vertices");

    /* Nothing may be written past what TriangleVertexCount promised: the flush reserves
     * exactly that much room and hands out the next command's slot immediately after. */
    for (size_t i = expected; i < expanded.size(); i++)
        check(expanded[i].id == -1, "ExpandTriangles did not write past its reservation");

    const std::vector<int> want = expectedTriangles(topology, count);
    check(want.size() == expected, "the definition and the count agree");

    /* Guarded, because a disagreement above would otherwise walk off the end of `want` and
       turn a failed assertion into a segfault -- which is how this test found that
       ExpandTriangles used to emit nothing for a triangle list while TriangleVertexCount
       claimed it emitted `count`. */
    for (size_t i = 0; i < expected && i < want.size(); i++)
        check(expanded[i].id == want[i], "the expanded vertex is the one the topology names");
}

int main()
{
    /* A four-vertex quad, the shape nearly every draw in this game is. */
    check(TriangleVertexCount(Topology::Fan, 4) == 6, "a quad fan is two triangles");
    check(NeedsExpansion(Topology::Fan), "and a run of them has to be taken apart");
    check(NeedsExpansion(Topology::Strip), "as does a run of strips");
    check(!NeedsExpansion(Topology::Triangles), "lists concatenate as they are");
    check(!NeedsExpansion(Topology::Other), "unbatchable topologies are drawn alone");

    /* A list is already its own triangles. Whole ones: a count that is not a multiple of three
     * is malformed input, and its stray vertices draw nothing. */
    check(TriangleVertexCount(Topology::Triangles, 6) == 6, "a list expands to itself");
    check(TriangleVertexCount(Topology::Triangles, 7) == 6, "and a stray vertex is not a triangle");

    /* Every shape the renderer can hand it: a quad, a rounded rectangle's corner fan, a
     * polyline strip, a SpriteBatch-sized run, and the degenerate ones. */
    for (size_t count : { (size_t)0, (size_t)1, (size_t)2, (size_t)3, (size_t)4, (size_t)5,
                          (size_t)6, (size_t)16, (size_t)20, (size_t)120 })
    {
        checkExpansion(Topology::Fan, count);
        checkExpansion(Topology::Strip, count);
        checkExpansion(Topology::Triangles, count);

        check(TriangleVertexCount(Topology::Fan, count) == (count < 3 ? 0 : (count - 2) * 3),
              "a fan is n-2 triangles");
        check(TriangleVertexCount(Topology::Strip, count) == (count < 3 ? 0 : (count - 2) * 3),
              "and so is a strip");
    }

    /* Expanding costs vertices, and the flush budgets against that: a four-vertex quad becomes
     * six, so a frame holds two thirds as many of them. */
    const size_t VERTEX_BUFFER_SIZE = 24576;
    check(6 * (VERTEX_BUFFER_SIZE / 6) <= VERTEX_BUFFER_SIZE,
          "a frame of expanded quads still fits the arena");

    if (failures == 0)
        std::printf("ok\n");

    return failures == 0 ? 0 : 1;
}
