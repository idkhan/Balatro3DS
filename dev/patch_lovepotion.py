#!/usr/bin/env python3
"""Teach LövePotion to boot a game out of RomFS.

LövePotion locates a game one of two ways: the fused layout (a zip appended to
the .3dsx, reopened through argv[0]) or a "game" folder resolved against the
working directory. Titles installed as a CIA are launched by the home menu with
argc == 0, so neither path is reachable and love falls through to its no-game
screen. The build also carries a 3DS audio fix. The patches applied are:

1. main.cpp: when argv is empty, fill arg[-2] with a RomFS path so boot.lua
   takes its normal fused branch against the CIA's own RomFS. The path defaults
   to "romfs:/game" and is set per-project via the command line.

2. physfs/filesystem.cpp: PhysFS's 3DS port derives its base and user dirs from
   the path passed to PHYSFS_init, and love builds the save directory from the
   user dir. A RomFS executable path would pin saves to read-only romfs: — the
   first love.filesystem.write then aborts inside create_directories. Anchor
   PhysFS to the sdmc directory the .3dsx build lives in instead, so both
   builds save to sdmc:/3ds/save/<identity>.

3. source_ext.cpp: initialize and validate the NDSP buffer count. Upstream
   leaves it uninitialized for static Sources, so cloning an overlapping sound
   can walk beyond buffers[2] and trigger an ARM11 data abort.

4. source_ext.cpp / wrap_source.cpp: implement Source pitch through the NDSP
   channel rate. Upstream's 3DS Lua binding validates setPitch and then silently
   ignores it, making Balatro's 0.7x soundtrack play at full speed.

5. vorbisdecoder.cpp: convert LOVE's seconds to Tremor's milliseconds when
   seeking. Without this, synchronizing a new music stem at 42 seconds seeks it
   to 42 milliseconds.

6. graphics.tcc: cache the corner trigonometry for rounded rectangles. The
   corner angles depend only on the point count, never on the rectangle, but
   upstream recomputes them with cosf/sinf on every call. This port draws ~37
   rounded rectangles a frame (panels, trays, tooltips), which is ~1500
   software transcendental calls a frame on an ARM11 with no hardware trig.

7. renderer_ext.cpp: stop deep-copying every draw command. Render() pushed
   command.Clone() into the pending list -- two extra heap allocations plus a
   full vertex copy per draw -- and FlushVertices then copied the vertices a
   second time into the C3D buffer. Every caller passes a stack temporary it
   never touches again, so the command can simply be moved.

8. wrap_mesh.cpp: implement Mesh:setVertices. wrap_mesh.hpp declares it but
   upstream never wrote the binding, so the only way to change a mesh's
   vertices from Lua is to allocate a new Mesh -- which is what fx.lua had to
   do per pass, per node, per frame for card edition effects. The Mesh vertex
   buffer is plain CPU memory that Draw() re-reads every frame, so the binding
   is a straight rewrite of the buffer using newMesh's own vertex parser.

9. renderer.tcc / renderer_ext: per-frame counters that separate logical LOVE
   draw operations from actual C3D submissions, latched at Present so a reader
   always sees a frame that has finished. Exposed as love.graphics.getBatchStats
   and love.graphics.getRuntimeInfo for benchmark.lua.

10. renderer_ext.cpp: coalesce adjacent compatible draw commands into one GPU
   submission. Upstream queued commands but still issued one C3D_DrawArrays per
   command. Runs are contiguous slices of the queue -- nothing is reordered --
   keyed on format, primitive type and shader; fans and strips are taken apart
   into independent triangles through batch_indices.hpp, installed as a new
   file, and the run goes out as one C3D_DrawArrays(GPU_TRIANGLES).

   The obvious alternative -- keep the vertices, submit an index buffer through
   C3D_DrawElements -- was implemented, measured, and removed. It hangs the GPU
   on a New 3DS: the picture freezes with the audio still playing, which is the
   main thread stuck in C3D_FrameBegin, so there is no ARM11 exception and no
   crash dump. Expansion is what citro2d does and it is fine.

   The state setters that citro3d applies at the next draw rather than at the
   call (blend, scissor, cull, colour mask, stencil, viewport) now flush first,
   which is both the batching barrier and a correctness fix: a queue spanning
   one of them was already being drawn under the later state.

11. drawcommand.tcc: small-buffer optimisation for the tiny commands. A
   four-vertex quad used to reach newlib's malloc three times -- a vertex array,
   a position array and a one-element std::vector for its texture handle -- and
   free all three a frame later. Commands of six vertices or fewer now carry
   their vertices inline, and the ctr handle list is a one-slot inline array.

12. quad.hpp / quad.cpp / texture_ext.cpp: cache the PICA-ready texture
   coordinates a Quad resolves to. Every textured draw rebuilt them from
   scratch through eight double divisions, for atlas quads that are built once
   at load and drawn thousands of times. The key is the quad's viewport
   (invalidated in Refresh, which Quad:setViewport goes through) plus the
   PHYSICAL size of the texture being drawn and whether it is a render target,
   because both change the answer.

13. wrap_graphics_ext.cpp: run the backdrop field on the New3DS spare core. The
   field is ~200 float ops per vertex over a 1813-vertex grid and was 980 us of
   main-thread CPU a frame; it touches no GPU state and writes only a buffer the
   GPU is not reading, so the whole sweep goes to core 2 -- the additional
   application core every New3DS-mode title gets, which needs no APT CPU time
   grant. The main thread keeps every C3D call, the buffer promotion and the
   draw, and never waits: a late worker means the last complete field is drawn
   again. Old 3DS, a failed thread creation and the runtime toggle all fall back
   to the synchronous banded path.

Only 3DS builds are touched, and the argv-present (.3dsx) path is untouched.
Idempotent: running it against an already-patched tree is a no-op, except the
game root define is refreshed if it changed.
"""

import re
import os
import shutil
import subprocess
import sys
from pathlib import Path

DEFAULT_GAME_ROOT = "romfs:/game"
DEFINE_RE = re.compile(r'(#define\s+LOVE_CTR_ROMFS_GAME\s+")[^"]*(")')

MAIN_CPP = Path("source/main.cpp")
FS_CPP = Path("source/modules/filesystem/physfs/filesystem.cpp")
AUDIO_CPP = Path("platform/ctr/source/objects/source_ext.cpp")
AUDIO_HPP = Path("platform/ctr/include/objects/source_ext.hpp")
AUDIO_WRAP_CPP = Path("source/objects/source/wrap_source.cpp")
VORBIS_CPP = Path("source/utilities/decoder/types/vorbisdecoder.cpp")
GRAPHICS_TCC = Path("include/modules/graphics/graphics.tcc")
RENDERER_CPP = Path("platform/ctr/source/utilities/driver/renderer/renderer_ext.cpp")
WRAP_MESH_CPP = Path("source/objects/mesh/wrap_mesh.cpp")
SCREEN_EXT_CPP = Path("platform/ctr/source/common/screen_ext.cpp")
SPRITEBATCH_CPP = Path("source/objects/spritebatch/spritebatch.cpp")
RENDERER_HPP = Path("platform/ctr/include/utilities/driver/renderer_ext.hpp")
WRAP_GRAPHICS_HPP = Path("include/modules/graphics/wrap_graphics.hpp")
WRAP_GRAPHICS_EXT_CPP = Path("platform/ctr/source/modules/wrap_graphics_ext.cpp")
RENDERER_TCC = Path("include/utilities/driver/renderer/renderer.tcc")
DRAWCOMMAND_TCC = Path("include/utilities/driver/renderer/drawcommand.tcc")
QUAD_HPP = Path("include/objects/quad/quad.hpp")
QUAD_CPP = Path("source/objects/quad/quad.cpp")
TEXTURE_EXT_CPP = Path("platform/ctr/source/objects/texture_ext.cpp")

MAIN_PATCHES = {
    "marker": "LOVE_CTR_ROMFS_GAME",
    "replacements": [
        (
            "#include <string.h>\n",
            """#include <string.h>

/* Balatro3DS: default RomFS game location for CIA builds. */
#if defined(__3DS__) && !defined(LOVE_CTR_ROMFS_GAME)
    #define LOVE_CTR_ROMFS_GAME "romfs:/game"
#endif
""",
        ),
        (
            """        if (argc > 0)
        {
            lua_pushstring(L, argv[0]);
            lua_rawseti(L, -2, -2);
        }
""",
            """        if (argc > 0)
        {
            lua_pushstring(L, argv[0]);
            lua_rawseti(L, -2, -2);
        }
#if defined(__3DS__)
        else
        {
            /* Balatro3DS: installed titles get no argv, so hand love the RomFS
               copy of the game as if it were a fused executable. */
            lua_pushstring(L, LOVE_CTR_ROMFS_GAME);
            lua_rawseti(L, -2, -2);
        }
#endif
""",
        ),
    ],
}

FS_PATCHES = {
    "marker": "physfsArgv0",
    "replacements": [
        (
            """    if (!PHYSFS_init(this->executablePath.c_str()))
        throw love::Exception("Failed to initialize filesystem: %s", Filesystem::GetLastError());
""",
            """    const char* physfsArgv0 = this->executablePath.c_str();
#if defined(__3DS__)
    /* Balatro3DS: PhysFS's 3DS port derives its base and user dirs from this
       path, and love builds the save directory from the user dir. A RomFS
       executable path would pin saves to read-only romfs:, so anchor PhysFS
       to the sdmc directory the .3dsx build lives in; both builds then save
       to sdmc:/3ds/save/. Only the directory part matters. */
    if (this->executablePath.rfind("romfs:", 0) == 0)
        physfsArgv0 = "sdmc:/3ds/lovepotion.3dsx";
#endif

    if (!PHYSFS_init(physfsArgv0))
        throw love::Exception("Failed to initialize filesystem: %s", Filesystem::GetLastError());
""",
        ),
    ],
}

AUDIO_PATCHES = {
    "marker": "Balatro3DS: static Sources own exactly one NDSP buffer",
    "replacements": [
        (
            """    this->sampleRate    = soundData->GetSampleRate();
    this->channels      = soundData->GetChannelCount();
    this->bitDepth      = soundData->GetBitDepth();
    this->samplesOffset = 0;

    std::fill_n(this->buffers, 2, ndspWaveBuf {});
""",
            """    this->sampleRate    = soundData->GetSampleRate();
    this->channels      = soundData->GetChannelCount();
    this->bitDepth      = soundData->GetBitDepth();
    /* Balatro3DS: static Sources own exactly one NDSP buffer. */
    this->bufferCount   = 1;
    this->samplesOffset = 0;

    std::fill_n(this->buffers, 2, ndspWaveBuf {});
""",
        ),
        (
            """    this->sampleRate    = sampleRate;
    this->channels      = channels;
    this->bitDepth      = bitDepth;
    this->bufferCount   = buffers;
    this->samplesOffset = 0;

    if (buffers < 1 || (size_t)buffers > Source::MAX_BUFFERS)
        buffers = MAX_BUFFERS;
""",
            """    if (buffers < 1 || (size_t)buffers > Source::MAX_BUFFERS)
        buffers = MAX_BUFFERS;

    this->sampleRate    = sampleRate;
    this->channels      = channels;
    this->bitDepth      = bitDepth;
    this->bufferCount   = buffers;
    this->samplesOffset = 0;
""",
        ),
        (
            """    this->bitDepth      = other.bitDepth;
    this->bufferCount   = other.bufferCount;
    this->samplesOffset = other.samplesOffset;
""",
            """    this->bitDepth      = other.bitDepth;
    this->bufferCount   = this->sourceType == TYPE_STATIC
                              ? 1
                              : std::clamp(other.bufferCount, 1, (int)MAX_BUFFERS);
    this->samplesOffset = other.samplesOffset;
""",
        ),
        (
            """    for (size_t index = 0; index < this->bufferCount; index++)
""",
            """    for (size_t index = 0; index < (size_t)this->bufferCount; index++)
""",
        ),
    ],
}

AUDIO_PITCH_HPP_PATCHES = {
    "marker": "Balatro3DS: NDSP playback-rate pitch",
    "replacements": [
        (
            """        void SetVolume(float volume);

        float GetVolume() const;
""",
            """        void SetVolume(float volume);

        float GetVolume() const;

        /* Balatro3DS: NDSP playback-rate pitch. */
        void SetPitch(float pitch);

        float GetPitch() const;
""",
        ),
        (
            """        ndspWaveBuf buffers[2];
""",
            """        ndspWaveBuf buffers[2];

        float pitch = 1.0f;
""",
        ),
    ],
}

AUDIO_PITCH_CPP_PATCHES = {
    "marker": "Balatro3DS: apply pitch by changing the NDSP playback rate",
    "replacements": [
        (
            """    this->bitDepth      = other.bitDepth;
    this->bufferCount   = this->sourceType == TYPE_STATIC
""",
            """    this->bitDepth      = other.bitDepth;
    this->pitch         = other.pitch;
    this->bufferCount   = this->sourceType == TYPE_STATIC
""",
        ),
        (
            """    ::DSP::Instance().ChannelReset(this->channel, this->channels, this->bitDepth, this->sampleRate);
""",
            """    ::DSP::Instance().ChannelReset(this->channel, this->channels, this->bitDepth,
                                     (int)(this->sampleRate * this->pitch));
""",
        ),
        (
            """float Source<Console::CTR>::GetVolume() const
{
    if (this->valid)
        return ::DSP::Instance().ChannelGetVolume(this->channel);

    return this->volume;
}

/* todo */
""",
            """float Source<Console::CTR>::GetVolume() const
{
    if (this->valid)
        return ::DSP::Instance().ChannelGetVolume(this->channel);

    return this->volume;
}

void Source<Console::CTR>::SetPitch(float pitch)
{
    /* Balatro3DS: apply pitch by changing the NDSP playback rate. */
    this->pitch = pitch;
    if (this->valid)
        ndspChnSetRate(this->channel, this->sampleRate * this->pitch);
}

float Source<Console::CTR>::GetPitch() const
{
    return this->pitch;
}

/* todo */
""",
        ),
    ],
}

AUDIO_PITCH_WRAP_PATCHES = {
    "marker": "lua_pushnumber(L, self->GetPitch());",
    "replacements": [
        (
            """    // self->SetPitch(pitch);

    return 0;
}

int Wrap_Source::GetPitch(lua_State* L)
{
    return 0;
}
""",
            """    self->SetPitch(pitch);

    return 0;
}

int Wrap_Source::GetPitch(lua_State* L)
{
    auto* self = Wrap_Source::CheckSource(L, 1);
    lua_pushnumber(L, self->GetPitch());
    return 1;
}
""",
        ),
    ],
}

VORBIS_SEEK_PATCHES = {
    "marker": "Balatro3DS: Tremor time positions are milliseconds",
    "replacements": [
        (
            """    else
        result = ov_time_seek(&this->handle, position);
""",
            """    else
        /* Balatro3DS: Tremor time positions are milliseconds; LOVE uses seconds. */
        result = ov_time_seek(&this->handle, position * 1000.0);
""",
        ),
    ],
}


ROUND_RECT_PATCHES = {
    "marker": "Balatro3DS: rounded-rectangle corner trigonometry",
    "replacements": [
        (
            """            return std::max(points, 8.0f);
        }
""",
            """            return std::max(points, 8.0f);
        }

        /* Balatro3DS: rounded-rectangle corner trigonometry, cached by point count.
           The corner angles are a function of `points` alone -- phi runs
           quadrant*halfPi + step*angleShift regardless of the rectangle's position,
           size or radius -- yet the loops below called cosf/sinf for every one on
           every draw. The UI here draws roughly 37 rounded rectangles a frame, which
           is ~1500 software transcendental calls on an ARM11 with no hardware trig.

           Values are cached exactly as the original loops accumulate them, so the
           coordinate arithmetic downstream is bit-identical. The table covers
           points 1..8; CalculateEllipsePoints only exceeds that above a ~51 px corner
           radius, and Lua can also pass a point count directly, so those fall through
           to live trig rather than being clamped.

           Zero-initialized POD, so it is constant-initialized with no lazy-init guard.
           Graphics calls are main-thread only in LOVE, so the unsynchronized fill is
           safe here. */
        static constexpr int ROUND_RECT_MAX_POINTS = 8;
        static constexpr int ROUND_RECT_MAX_STEPS  = ROUND_RECT_MAX_POINTS + 3;

        struct RoundRectTrig
        {
            float cosines[4][ROUND_RECT_MAX_STEPS];
            float sines[4][ROUND_RECT_MAX_STEPS];
            bool built;
        };

        static const RoundRectTrig* GetRoundRectTrig(int points)
        {
            if (points < 1 || points > ROUND_RECT_MAX_POINTS)
                return nullptr;

            static RoundRectTrig cache[ROUND_RECT_MAX_POINTS + 1] {};
            RoundRectTrig& entry = cache[points];

            if (!entry.built)
            {
                const float halfPi     = static_cast<float>(LOVE_M_PI / 2);
                const float angleShift = halfPi / ((float)points + 1.0f);
                const int steps        = points + 3;

                for (int quadrant = 0; quadrant < 4; ++quadrant)
                {
                    float phi = quadrant * halfPi;

                    for (int step = 0; step < steps; ++step, phi += angleShift)
                    {
                        entry.cosines[quadrant][step] = cosf(phi);
                        entry.sines[quadrant][step]   = sinf(phi);
                    }
                }

                entry.built = true;
            }

            return &entry;
        }
""",
        ),
        (
            """            const float halfPi = static_cast<float>(LOVE_M_PI / 2);
            float angleShift   = halfPi / ((float)points + 1.0f);

            int pointCount = (points + 2) * 4;

            Vector2 coords[pointCount + 1] {};
            float phi = 0.0f;

            for (int index = 0; index <= points + 2; ++index, phi += angleShift)
            {
                coords[index].x = x + rx * (1 - cosf(phi));
                coords[index].y = y + ry * (1 - sinf(phi));
            }

            phi = halfPi;

            for (int index = points + 2; index <= 2 * (points + 2); ++index, phi += angleShift)
            {
                coords[index].x = x + width - rx * (1 + cosf(phi));
                coords[index].y = y + ry * (1 - sinf(phi));
            }

            phi = 2 * halfPi;

            for (int index = 2 * (points + 2); index <= 3 * (points + 2);
                 ++index, phi += angleShift)
            {
                coords[index].x = x + width - rx * (1 + cosf(phi));
                coords[index].y = y + height - ry * (1 + sinf(phi));
            }

            phi = 3 * halfPi;

            for (int index = 3 * (points + 2); index <= 4 * (points + 2);
                 ++index, phi += angleShift)
            {
                coords[index].x = x + rx * (1 - cosf(phi));
                coords[index].y = y + height - ry * (1 + sinf(phi));
            }

            coords[pointCount] = coords[0];
""",
            """            const float halfPi = static_cast<float>(LOVE_M_PI / 2);
            float angleShift   = halfPi / ((float)points + 1.0f);

            int pointCount = (points + 2) * 4;

            Vector2 coords[pointCount + 1] {};

            /* Balatro3DS: the four corner loops this replaces differed only in which
               edge they measured from; folding them into one quadrant loop is what
               lets the cached angles above be indexed directly. Each quadrant still
               starts at the same index and phi the original assigned, and writes the
               same expression, so the emitted vertices are bit-identical. */
            const RoundRectTrig* trig = GetRoundRectTrig(points);
            const int steps           = points + 3;

            for (int quadrant = 0; quadrant < 4; ++quadrant)
            {
                int index = quadrant * (points + 2);
                float phi = quadrant * halfPi;

                for (int step = 0; step < steps; ++step, ++index, phi += angleShift)
                {
                    float cosPhi, sinPhi;

                    if (trig != nullptr)
                    {
                        cosPhi = trig->cosines[quadrant][step];
                        sinPhi = trig->sines[quadrant][step];
                    }
                    else
                    {
                        cosPhi = cosf(phi);
                        sinPhi = sinf(phi);
                    }

                    coords[index].x = (quadrant == 1 || quadrant == 2)
                                          ? x + width - rx * (1 + cosPhi)
                                          : x + rx * (1 - cosPhi);
                    coords[index].y = (quadrant >= 2) ? y + height - ry * (1 + sinPhi)
                                                      : y + ry * (1 - sinPhi);
                }
            }

            coords[pointCount] = coords[0];
""",
        ),
    ],
}

RENDERER_MOVE_PATCHES = {
    "marker": "Balatro3DS: move the command instead of cloning it",
    "replacements": [
        (
            """#include <algorithm>
""",
            """#include <algorithm>
#include <utility> /* Balatro3DS: std::move in Render, below. */

#include <utilities/driver/batch_indices.hpp> /* Balatro3DS: the batching flush's indices. */
""",
        ),
        (
            """bool Renderer<Console::CTR>::Render(DrawCommand& command)
{
    Shader<Console::CTR>::defaults[command.shader]->Attach();

    // check if texture is the same, or no texture at all
    if (command.handles.empty() || (this->currentTexture == command.handles.back()))
    {
        ++drawCalls;
        m_commands.push_back(command.Clone());
        return true;
    }
    else
    {
        FlushVertices();

        if (!command.handles.empty())
        {
            if (this->currentTexture != command.handles.back())
                this->currentTexture = command.handles.back();

            C3D_TexBind(0, command.handles.back());
        }

        ++drawCalls;
        m_commands.push_back(command.Clone());
        return true;
    }

    return false;
}
""",
            """bool Renderer<Console::CTR>::Render(DrawCommand& command)
{
    /* Balatro3DS: move the command instead of cloning it.
       Clone() allocates a second positions[] and vertices[] and copies every vertex
       into them, and FlushVertices then copies the vertices again into the C3D
       buffer -- four heap allocations and two vertex copies per draw where two and
       one will do. At ~120 draw commands a frame that is a few hundred needless
       malloc/free pairs on newlib's allocator.

       Every caller (graphics.tcc Polygon/Draw, mesh, spritebatch, textbatch, font,
       polyline, texture_ext) builds a DrawCommand as a local and lets it die on the
       next line, so taking ownership is safe. The move must stay the last use of
       `command`: `handles` is read below before the texture bind.

       This also carries `cullMode`, which Clone() silently dropped. The 3DS flush
       path does not read it, so nothing changes on-screen today. */
    Shader<Console::CTR>::defaults[command.shader]->Attach();

    // check if texture is the same, or no texture at all
    if (command.handles.empty() || (this->currentTexture == command.handles.back()))
    {
        ++drawCalls;
        m_commands.push_back(std::move(command));
        return true;
    }
    else
    {
        FlushVertices();

        if (!command.handles.empty())
        {
            if (this->currentTexture != command.handles.back())
                this->currentTexture = command.handles.back();

            C3D_TexBind(0, command.handles.back());
        }

        ++drawCalls;
        m_commands.push_back(std::move(command));
        return true;
    }

    return false;
}
""",
        ),
    ],
}


MESH_SETVERTICES_PATCHES = {
    "marker": "Balatro3DS: implement Mesh:setVertices",
    "replacements": [
        (
            """// clang-format off
static constexpr luaL_Reg functions[]
{
""",
            """/* Balatro3DS: implement Mesh:setVertices.
   wrap_mesh.hpp declares SetVertices but upstream never wrote the binding, so
   Lua's only way to change a mesh was to allocate a whole new Mesh. The vertex
   buffer is plain CPU memory (mesh.cpp GetVertexData returns buffer.data() and
   Draw() re-reads it every frame), so this is a straight rewrite of that buffer.

   The per-vertex parse below is copied field-for-field from newStandardMesh in
   wrap_graphics.cpp -- position xy, optional uv, optional colour clamped to
   [0,1] -- so a mesh updated here is bit-identical to one rebuilt with newMesh
   from the same table. LOVE's optional startvertex argument is honoured; the
   count is capped against the mesh like upstream LOVE, not silently grown,
   because the buffer's size is fixed at construction. */
int Wrap_Mesh::SetVertices(lua_State* L)
{
    auto* self = Wrap_Mesh::CheckMesh(L, 1);

    luaL_checktype(L, 2, LUA_TTABLE);
    size_t vertexCount = luax::ObjectLength(L, 2);
    long startIndex    = luaL_optinteger(L, 3, 1) - 1;

    if (startIndex < 0)
        return luaL_error(L, "Invalid vertex start index (must be at least 1)");

    if (startIndex + vertexCount > self->GetVertexCount())
        return luaL_error(L, "Too many vertices (expected at most %d, got %d)",
                          (int)self->GetVertexCount() - (int)startIndex, (int)vertexCount);

    auto* vertices = (Vertex*)self->GetVertexData() + startIndex;

    for (size_t index = 1; index <= vertexCount; index++)
    {
        lua_rawgeti(L, 2, (int)index);

        if (lua_type(L, -1) != LUA_TTABLE)
        {
            luax::TypeError(L, 2, "table of tables");
            return 0;
        }

        for (int j = 1; j <= 8; j++)
            lua_rawgeti(L, -j, j);

        Vertex vertex {};

        vertex.position[0] = luaL_checknumber(L, -8);
        vertex.position[1] = luaL_checknumber(L, -7);
        vertex.position[2] = 0.0f;

        vertex.texcoord[0] = luaL_optnumber(L, -6, 0.0f);
        vertex.texcoord[1] = luaL_optnumber(L, -5, 0.0f);

        vertex.color[0] = luax::OptNumberClamped01(L, -4, 1.0);
        vertex.color[1] = luax::OptNumberClamped01(L, -3, 1.0);
        vertex.color[2] = luax::OptNumberClamped01(L, -2, 1.0);
        vertex.color[3] = luax::OptNumberClamped01(L, -1, 1.0);

        lua_pop(L, 9);
        vertices[index - 1] = vertex;
    }

    self->SetVertexDataModified(startIndex * self->GetVertexStride(),
                                vertexCount * self->GetVertexStride());

    return 0;
}

// clang-format off
static constexpr luaL_Reg functions[]
{
    { "setVertices",    Wrap_Mesh::SetVertices    },
""",
        ),
    ],
}


def patch_file(path: Path, spec: dict) -> bool:
    with open(path, "r", newline="") as handle:
        source = handle.read()

    if spec["marker"] in source:
        print(f"already patched: {path}")
        return True

    # Upstream keeps CRLF line endings; match them so the diff stays minimal.
    eol = "\r\n" if "\r\n" in source else "\n"
    replacements = [
        (anchor.replace("\n", eol), patched.replace("\n", eol))
        for anchor, patched in spec["replacements"]
    ]

    for anchor, _ in replacements:
        count = source.count(anchor)
        if count != 1:
            print(
                f"error: expected exactly one match in {path}, found {count}.\n"
                f"Upstream has changed; update {Path(__file__).name}.\n"
                f"--- anchor ---\n{anchor}",
                file=sys.stderr,
            )
            return False

    for anchor, patched in replacements:
        source = source.replace(anchor, patched)

    with open(path, "w", newline="") as handle:
        handle.write(source)

    print(f"patched: {path}")
    return True


def write_file(path: Path, spec: dict) -> bool:
    """Install a whole new file. Rewritten every run so an edit here always lands.

    patch_file cannot express a file that upstream does not have, and the batching index
    helpers have to be a file of their own: they are the one piece of the flush that is pure
    arithmetic, and a host compiler can build them without any of citro3d, which is what lets
    tests/test_batch_indices.lua check the fan and strip conversions against real code rather
    than against a Lua restatement of it.
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    text = spec["contents"]
    if path.is_file() and path.read_text(newline="") == text:
        print(f"already written: {path}")
        return True

    with open(path, "w", newline="") as handle:
        handle.write(text)

    print(f"wrote: {path}")
    return True


def set_game_root(main_cpp: Path, game_root: str) -> None:
    with open(main_cpp, "r", newline="") as handle:
        source = handle.read()

    updated = DEFINE_RE.sub(lambda m: m.group(1) + game_root + m.group(2), source)
    if updated != source:
        with open(main_cpp, "w", newline="") as handle:
            handle.write(updated)
    print(f"game root: {game_root}")


SPRITEBATCH_COLOR_PATCHES = {
    "marker": "Balatro3DS: honour the batch colour",
    "replacements": [
        (
            """    std::array<float, 0x04> color = { 1.0f, 1.0f, 1.0f, 1.0f };
""",
            """    /* Balatro3DS: honour the batch colour instead of hardcoding white.

       SpriteBatch::SetColor validates and stores its argument in this->color, and
       GetColor hands it back, but Add never read it -- every sprite went into the
       buffer with {1,1,1,1}, so SpriteBatch:setColor was a silent no-op on every
       console. Upstream desktop backends hide this because they re-tint at draw
       time; the ctr path does not.

       That matters here because SpriteBatch is the only batching primitive this
       backend has (canvases do not render on ctr, and a Mesh loses to individual
       draws on marshalling cost), and it is 8x cheaper per quad than an individual
       draw. Without per-sprite colour it cannot express a card shadow pass, a
       debuff wash, lifecycle alpha or a tinted particle -- which is most of what
       this game draws, so the whole primitive was unusable.

       Colour is baked per sprite at Add time, which is the LOVE 11 semantic: set
       the colour, add the sprite, and the sprite keeps the colour it was added
       with. Callers that want a uniform tint set it once before their add loop. */
    std::array<float, 0x04> color = this->color.array();
""",
        ),
    ],
}


# --------------------------------------------------------------------------- backdrop
# The animated backdrop is the reference game's background.fs, which is a fragment shader. The
# PICA200 has no fragment programmability, so the field is evaluated per vertex over a screen
# covering grid and handed to the fragment stage as a texture coordinate; a 256-wide ramp holds
# the three colour weights so band edges still resolve per pixel. See dev/shaders/backdrop.v.pica.
#
# Three pieces of global GPU state have to be put back after the draw, and each one was found
# the hard way by reading the renderer:
#
#   * the vertex buffer binding, set once in the renderer's constructor and never again;
#   * the projection uniform, which FlushVertices only re-uploads when s_dirtyProjection is set
#     -- our shader's uniform lands in the same register bank and would otherwise corrupt every
#     later 2D draw for the rest of the process;
#   * the TexEnv stage cache, which early-outs when the format has not changed
#     (vertex_ext.hpp:57), so stage 0 would never be rebuilt after we overwrite it.

RENDERER_BACKDROP_HPP_PATCHES = {
    "marker": "Balatro3DS: backdrop draws from its own vertex buffer",
    "replacements": [
        (
            """        static void FlushVertices();
""",
            """        static void FlushVertices();

        /* Balatro3DS: backdrop draws from its own vertex buffer and its own shader program, and
           citro3d's buffer binding and projection upload are global. The binding is established
           once in the constructor, so restoring it is just re-issuing it; the projection is only
           re-sent by FlushVertices when it is marked dirty, and our program writes the same
           uniform bank, so it has to be marked. */
        void RestoreBufInfo()
        {
            C3D_SetBufInfo(&this->bufferInfo);

            /* Render() skips C3D_TexBind whenever a command's texture matches currentTexture,
               so a foreign draw that binds its own texture leaves this cache describing
               something that is no longer bound -- and the next 2D draw that happens to match
               it samples the foreign texture instead of its own. Forgetting the binding forces
               the next textured command to re-issue it. */
            this->currentTexture = nullptr;
        }

        static void AfterForeignDraw();
""",
        ),
    ],
}

RENDERER_BACKDROP_CPP_PATCHES = {
    "marker": "Balatro3DS: put back the state a foreign draw disturbed",
    "replacements": [
        (
            """void Renderer<Console::CTR>::Present()
""",
            """/* Balatro3DS: put back the state a foreign draw disturbed. Lives here, not at the call site,
   because both flags are only reachable from this translation unit.

   The projection: the backdrop binds its own shader program, whose uniforms occupy the same
   vertex uniform registers as this renderer's projection and model-view matrices. FlushVertices
   only re-sends those when this flag is set, so without it every 2D draw after the first
   backdrop frame would be transformed by whatever the backdrop left behind.

   The TexEnv format: SetTexEnvFunction early-outs when the format has not changed
   (vertex_ext.hpp:57), and s_format is `static` at namespace scope -- internal linkage, one
   copy per translation unit. Only this file can invalidate the copy FlushVertices reads. */
void Renderer<Console::CTR>::AfterForeignDraw()
{
    s_dirtyProjection                   = true;
    love::vertex::attributes::s_format  = CommonFormat::NONE;
}

void Renderer<Console::CTR>::Present()
""",
        ),
    ],
}

WRAP_GRAPHICS_HPP_PATCHES = {
    "marker": "Balatro3DS: drawBackdrop",
    "replacements": [
        (
            """    int GetDepth(lua_State* L);
""",
            """    int GetDepth(lua_State* L);

    /* Balatro3DS: drawBackdrop -- the animated background, evaluated on the GPU. */
    int DrawBackdrop(lua_State* L);
""",
        ),
    ],
}

BACKDROP_BINDING_PATCHES = {
    "marker": "Balatro3DS: the animated menu backdrop",
    "replacements": [
        (
            """#include <modules/graphics/wrap_graphics.hpp>
#include <modules/graphics_ext.hpp>

using namespace love;
""",
            """#include <modules/graphics/wrap_graphics.hpp>
#include <modules/graphics_ext.hpp>

/* Balatro3DS: the animated menu backdrop -- splash.fs, evaluated on the CPU.

   The reference paints this with a fragment shader (Game:main_menu builds SPLASH_BACK with
   shader = 'splash', game.lua:1548). The PICA200 has no fragment programmability, and an
   attempt to run the field in a custom VERTEX program had to be abandoned: it assembled
   cleanly, passed every off-console check, and wedged the GPU so hard the HOME menu could not
   be reached. An on-device bisect settled it -- this same geometry, indices, ramp bind and
   TexEnv chain drawn through the STOCK shader program booted fine, and a stage of the custom
   program that computed nothing at all still hung. Binding a custom vertex program is itself
   what this runtime cannot survive.

   So the field moves to the ARM11 and everything else stays. The stock vertex shader passes
   texcoords through untouched, so writing each vertex's `paint` value into its texcoord leaves
   the ramp lookup happening PER PIXEL in TexEnv -- which is what resolves the colour bands
   crisply, and is the whole reason this looks like paint rather than a smeared gradient.
   Interpolating colours across the grid instead would blur exactly that.

   What that costs: the field is ~200 float ops per vertex, so the grid is sized against the
   ARM11 rather than the GPU, and the sine is a parabola approximation rather than libm's --
   sixteen sinf calls per vertex would be several times the frame budget on its own. */
#include <utilities/driver/renderer_ext.hpp>

#include <3ds.h>
#include <citro3d.h>

#include <cmath>
#include <cstdio>
#include <cstring>

using namespace love;

namespace
{
    /* Sized against the ARM11, not the GPU. `paint` is interpolated between these vertices,
       so density is the fidelity knob; 48x36 keeps the per-frame field cost near 3 ms on a
       268 MHz Old 3DS, which is where this has to fit. */
    constexpr int GRID_W = 48;
    constexpr int GRID_H = 36;

    /* The field is refreshed in this many row bands, one band per frame, so a frame pays a
       fraction of the grid rather than all of it. This is what lets a grid this dense be
       carried at all: the first hardware measurement of a whole-grid-per-frame version was
       14.8 ms on a New 3DS -- 30 fps -- and even after the libm calls came out of the sine, a
       static shop frame was spending 3.7 ms of a 16.7 ms budget here across both screens.
       Eight bands halve that again.

       The bands refresh an OFF-SCREEN buffer, and the drawn buffer only ever changes when a
       sweep completes (see the flip in DrawBackdrop). An earlier revision refreshed the drawn
       buffer in place, on the theory that the warp moves ~0.3 rad/s and a seven-frame-stale
       seam would be unresolvable -- but `sp` advances inside the warp iterations at ~2 rad/s,
       sixty times that estimate, and on hardware the fresh/stale boundary read as a slow CRT
       scan marching down the screen (observed on a New 3DS, Aug 2026). Double-buffering trades
       that for the field animating in whole steps at 60/FIELD_BANDS fps, which against smoke
       this slow is quantisation nobody sees; fewer bands buy a higher step rate at
       proportionally more CPU per frame. */
    constexpr int FIELD_BANDS = 8;
    constexpr int VERTS  = (GRID_W + 1) * (GRID_H + 1);
    constexpr int INDICES = GRID_W * GRID_H * 6;

    /* LovePotion's own attribute layout: 3 position, 4 colour, 2 texcoord. Using it unchanged
       means the draw swaps only the buffer binding -- never the attribute config, and never
       the shader program. */
    constexpr int FLOATS_PER_VERT = 9;
    constexpr int TC_OFFSET       = 7;

    constexpr int RAMP_W = 256;
    constexpr int RAMP_H = 8;

    /* The reference uses two different shaders. The main menu is splash.fs -- two colours over
       a hardcoded slate, a swirl that spreads with radius from the outset, a smoke term with a
       soft knee, and a white bloom on the brightest cores (game.lua:1548). Every other screen
       is background.fs -- three eased colours, a contrast that also reshapes the colour
       weights, and a swirl whose radius dependence only appears as spin_amount rises
       (game.lua:2283). They share the five warp iterations exactly and little else. */
    enum FieldMode
    {
        MODE_SPLASH     = 0,
        MODE_BACKGROUND = 1,
        MODE_COUNT      = 2,
    };

    struct Grid
    {
        /* Two buffers: [front] is what the GPU draws, the other is refilled band by band and
           shown only once every band of it is from the same sweep. Refilling the drawn buffer
           in place put a fresh/stale seam on screen that scanned downward like a slow CRT --
           see the FIELD_BANDS comment. 65 KB of linear heap per copy. */
        float* vbo[2] = { nullptr, nullptr };   /* interleaved, GPU-visible */
        float* angle  = nullptr;   /* atan2(uv.y, uv.x) per vertex, CPU only */
        float* radius = nullptr;   /* length(uv) per vertex, CPU only */
        C3D_BufInfo buf[2] {};
        bool built = false;
        int front = 0;     /* which vbo the GPU draws; the other is being refilled */
        int band = 0;      /* which row band of the back buffer refreshes next */
        /* Balatro3DS: this grid is on screen and would like a sweep, and when it last got
           one. Both screens draw every frame and each has its own grid, so the worker has to
           be shared out between them rather than handed to whoever asks first. */
        bool wants = false;
        unsigned int lastPosted = 0;
        /* Field parameters frozen at the start of the sweep now filling the back buffer, so
           every band of a shown buffer samples the same instant. */
        float sp = 0.0f, A = 0.0f, B = 0.0f, K = 0.0f;
        float lastTime = 0.0f;   /* re-prime after a long gap rather than show a stale field */
        bool primed = false;
    };

    struct BackdropState
    {
        bool attempted = false;
        bool ready     = false;
        u16* ibo       = nullptr;
        C3D_Tex ramp {};
        bool rampReady = false;
        /* [mode][screen]. background.fs offsets uv by 0.12 in x and splash.fs does not, so
           the precomputed swirl angle and radius differ between them. */
        Grid grids[MODE_COUNT][2];
        int rampMode  = -1;
        float rampKey = -1.0e9f;
        unsigned int postCounter = 0;   /* orders grids by how long they have waited */
        const char* reason = "ok";
        char report[192]   = "not attempted";
    };

    BackdropState g_bd;

    /* Fold to [-pi, pi], then the standard parabola y = B*x - C*x*|x| refined once by
       y += P*(y*|y| - y). Error under 0.002 -- far below anything a 240p panel resolves once
       the field is quantised into colour bands -- for about a tenth of libm's cost, which is
       the difference between this fitting in a frame and not. */
    inline float FastSin(float x)
    {
        /* Range reduction without a library call. Adding and subtracting 1.5*2^23 forces a
           float to drop its fractional bits, which is round-to-nearest for anything inside
           that magnitude -- exactly what floor(v + 0.5) was doing.

           This matters more than it looks. std::floor is a call into libm, this runs sixteen
           times per vertex, and the first hardware measurement of the CPU-side field came back
           at 14.8 ms a frame on a New 3DS -- the game dropped to 30 fps. The ARM11's VFP is
           slow enough that a per-call overhead repeated this often is most of the cost. */
        constexpr float MAGIC = 12582912.0f;   /* 1.5 * 2^23 */
        float k = x * 0.15915494f;
        k = (k + MAGIC) - MAGIC;
        x -= 6.28318531f * k;

        const float ax = x < 0.0f ? -x : x;
        const float y  = 1.27323954f * x - 0.40528473f * x * ax;
        const float ay = y < 0.0f ? -y : y;
        return 0.225f * (y * ay - y) + y;
    }

    inline float FastCos(float x)
    {
        return FastSin(x + 1.57079633f);
    }

    /* PICA textures are tiled in 8x8 blocks, Morton-ordered within each block with y as the
       low bit. tex3ds does this offline for art; the ramp is generated here, so it does it
       itself. */
    inline int TileOffset(int x, int y, int width)
    {
        const int blockX = x >> 3, blockY = y >> 3;
        int ix = x & 7, iy = y & 7;

        ix = (ix | (ix << 2)) & 0x33;
        ix = (ix | (ix << 1)) & 0x55;
        iy = (iy | (iy << 2)) & 0x33;
        iy = (iy | (iy << 1)) & 0x55;

        return ((blockY * (width >> 3) + blockX) << 6) | (ix | (iy << 1));
    }

    /* splash.fs's three weights as a function of smoke_res, in RGB, with its white bloom in
       alpha. smoke_res spans -2..2 there, so the ramp is indexed by (smoke + 2)/4.

       Texture memory is bytes [A,B,G,R], so as a little-endian u32 the red weight takes the
       TOP byte. The TexEnv constant registers below use the opposite order. Confusing the two
       channel-scrambles the whole effect. */
    void BuildRamp(int mode, float contrastMod)
    {
        if (!g_bd.rampReady)
        {
            if (!C3D_TexInit(&g_bd.ramp, RAMP_W, RAMP_H, GPU_RGBA8))
                return;
            C3D_TexSetFilter(&g_bd.ramp, GPU_LINEAR, GPU_LINEAR);
            C3D_TexSetWrap(&g_bd.ramp, GPU_CLAMP_TO_EDGE, GPU_CLAMP_TO_EDGE);
            g_bd.rampReady = true;
        }

        u32* out = (u32*)g_bd.ramp.data;
        if (out == nullptr)
            return;

        for (int x = 0; x < RAMP_W; x++)
        {
            const float t = (float)x / (float)(RAMP_W - 1);
            float c1p, c2p, flash = 0.0f;

            if (mode == MODE_BACKGROUND)
            {
                /* background.fs spans 0..2 and its factors ARE contrast_mod, which is why this
                   ramp has to be rebuilt whenever contrast eases to a new value. It has no
                   bloom term. */
                const float paint = t * 2.0f;
                c1p = 1.0f - contrastMod * std::fabs(1.0f - paint);
                c2p = 1.0f - contrastMod * std::fabs(paint);
                c1p = c1p < 0.0f ? 0.0f : c1p;
                c2p = c2p < 0.0f ? 0.0f : c2p;
            }
            else
            {
            const float smoke = t * 4.0f - 2.0f;

            c1p = 1.0f - 2.0f * std::fabs(1.0f - smoke);
            c2p = 1.0f - 2.0f * smoke;
            c1p = c1p < 0.0f ? 0.0f : c1p;
            c2p = c2p < 0.0f ? 0.0f : c2p;

            /* splash.fs never clamps these: at the blue core c2p runs past 3, and that excess
               is what blows out toward white on screen. An 8-bit channel cannot carry it, so
               the channel clamps and the excess feeds the bloom -- which is where the
               reference's over-bright core visually ends up anyway. */
            const float peak = c1p > c2p ? c1p : c2p;

            flash = peak * 5.0f - 4.4f;
            flash = flash < 0.0f ? 0.0f : (flash > 1.0f ? 1.0f : flash);
            }

            const float sum = c1p + c2p;
            const float cb  = 1.0f - (sum > 1.0f ? 1.0f : sum);
            c1p = c1p > 1.0f ? 1.0f : c1p;
            c2p = c2p > 1.0f ? 1.0f : c2p;

            const u32 texel = ((u32)(c1p * 255.0f) << 24) | ((u32)(c2p * 255.0f) << 16) |
                              ((u32)(cb * 255.0f) << 8) | (u32)(flash * 255.0f);

            for (int y = 0; y < RAMP_H; y++)
                out[TileOffset(x, y, RAMP_W)] = texel;
        }

        C3D_TexFlush(&g_bd.ramp);
    }

    /* Positions are in SCREEN pixels, not clip space: these vertices go through the stock
       shader, which applies the renderer's ortho projection like any other geometry. The swirl
       angle and radius depend only on the vertex, so they are computed once here and kept off
       to the side rather than recomputed 60 times a second. */
    bool BuildGrid(Grid& grid, int width, int mode)
    {
        const float w = (float)width, h = 240.0f;
        const float diag = std::sqrt(w * w + h * h);

        grid.vbo[0] = (float*)linearAlloc(sizeof(float) * FLOATS_PER_VERT * VERTS);
        grid.vbo[1] = (float*)linearAlloc(sizeof(float) * FLOATS_PER_VERT * VERTS);
        grid.angle  = (float*)std::malloc(sizeof(float) * VERTS);
        grid.radius = (float*)std::malloc(sizeof(float) * VERTS);

        if (grid.vbo[0] == nullptr || grid.vbo[1] == nullptr || grid.angle == nullptr ||
            grid.radius == nullptr)
            return false;

        float* v = grid.vbo[0];
        for (int gy = 0, i = 0; gy <= GRID_H; gy++)
        {
            for (int gx = 0; gx <= GRID_W; gx++, i++)
            {
                const float u = (float)gx / (float)GRID_W;
                const float t = (float)gy / (float)GRID_H;

                /* splash.fs: uv = (screen - 0.5*size)/length(size). No 0.12 offset -- that one
                   belongs to background.fs, and is what puts its swirl off-centre. */
                const float ux = (u * w - 0.5f * w) / diag
                                 - (mode == MODE_BACKGROUND ? 0.12f : 0.0f);
                const float uy = (t * h - 0.5f * h) / diag;

                grid.angle[i]  = std::atan2(uy, ux);
                grid.radius[i] = std::sqrt(ux * ux + uy * uy);

                v[0] = u * w;
                v[1] = t * h;
                v[2] = 0.0f;
                v[3] = v[4] = v[5] = v[6] = 1.0f;
                v[7] = 0.5f;
                v[8] = 0.5f;
                v += FLOATS_PER_VERT;
            }
        }

        std::memcpy(grid.vbo[1], grid.vbo[0], sizeof(float) * FLOATS_PER_VERT * VERTS);

        for (int side = 0; side < 2; side++)
        {
            BufInfo_Init(&grid.buf[side]);
            if (BufInfo_Add(&grid.buf[side], grid.vbo[side], sizeof(float) * FLOATS_PER_VERT,
                            3, 0x210) < 0)
                return false;
        }

        grid.built = true;
        return true;
    }

    /* The field, per vertex, per frame -- what the vertex shader was going to do.

       This is splash.fs line for line: the radius-dependent swirl, five domain-warp iterations,
       and the smoke term with its soft knee below 0.2. Only the ramp coordinate is written
       back; positions never move. */
    void UpdateField(Grid& grid, float* vbo, int mode, float sp, float A, float B, float K)
    {
        /* One band per call, into whichever buffer the caller says -- the back buffer during
           a sweep, the front one when priming. The banding is purely a way to spread the work
           across frames; nothing partial is ever shown. */
        const int rows = GRID_H + 1;
        const int first = (rows * grid.band) / FIELD_BANDS;
        const int last  = (rows * (grid.band + 1)) / FIELD_BANDS;
        grid.band = (grid.band + 1) % FIELD_BANDS;

        const int stride = GRID_W + 1;
        int i = first * stride;
        float* v = vbo + TC_OFFSET + (size_t)i * FLOATS_PER_VERT;

        for (int row = first; row < last; row++)
        {
            for (int col = 0; col < stride; col++, i++, v += FLOATS_PER_VERT)
            {
                const float len = grid.radius[i];
                /* Both shaders reduce to the same shape -- a base angle, a radius term and a
                   per-frame constant -- so the caller folds each one's arithmetic into A and B
                   and this loop never learns which shader it is running. */
                const float a = grid.angle[i] + A * len + B;

                float x = len * 30.0f * FastCos(a);
                float y = len * 30.0f * FastSin(a);

                float ax = x + y, ay = x + y;

                for (int it = 0; it < 5; it++)
                {
                    const float m = FastSin(x > y ? x : y);
                    ax += m + x;
                    ay += m + y;

                    const float nx = x + 0.5f * FastCos(5.1123314f + 0.353f * ay + sp * 0.131121f);
                    const float ny = y + 0.5f * FastSin(ax - 0.113f * sp);
                    const float k  = FastCos(nx + ny) - FastSin(nx * 0.711f - ny);

                    x = nx - k;
                    y = ny - k;
                }

                /* length(sv)*0.12. sqrtf is a VSQRT, which is one of the slowest things the
                   VFP does; the reciprocal-square-root estimate followed by one multiply is
                   materially cheaper and the error lands far below a ramp texel. */
                const float d2 = x * x + y * y;
                const float dist = d2 > 1.0e-12f ? d2 / std::sqrt(d2) : 0.0f;

                if (mode == MODE_BACKGROUND)
                {
                    /* background.fs: clamp(length(uv)*0.035*contrast_mod, 0, 2), no knee.
                       K carries the 0.035*contrast_mod factor. */
                    float paint = dist * K;
                    paint = paint < 0.0f ? 0.0f : (paint > 2.0f ? 2.0f : paint);
                    v[0] = paint * 0.5f;
                }
                else
                {
                    float smoke = 1.5f + dist * 0.12f - K;

                    /* splash.fs flattens everything under 0.2 to 60% slope. Branchless:
                       out = smoke - 0.4*min(smoke - 0.2, 0) */
                    const float d = smoke - 0.2f;
                    smoke -= 0.4f * (d < 0.0f ? d : 0.0f);

                    smoke = smoke < -2.0f ? -2.0f : (smoke > 2.0f ? 2.0f : smoke);
                    v[0] = (smoke + 2.0f) * 0.25f;
                }
            }
        }
    }

    /* Grids are built the first time a mode and screen are actually asked for. Four exist --
       two shaders by two screen widths -- and a session that never leaves the menu should not
       pay for the two it will never draw. */
    Grid* EnsureGrid(int mode, int width)
    {
        Grid& grid = g_bd.grids[mode][(width == 320) ? 1 : 0];
        if (grid.built)
            return &grid;
        if (!BuildGrid(grid, width, mode))
        {
            g_bd.reason = "grid alloc failed";
            return nullptr;
        }
        return &grid;
    }

    bool EnsureBackdrop()
    {
        if (g_bd.attempted)
            return g_bd.ready;

        g_bd.attempted = true;

        g_bd.ibo = (u16*)linearAlloc(sizeof(u16) * INDICES);
        if (g_bd.ibo == nullptr)
        {
            g_bd.reason = "index buffer alloc failed";
            return false;
        }

        /* Indexed, and not for tidiness: unindexed this grid would be 10368 vertices out of
           the 24576 the whole frame gets, in a buffer that is memcpy'd into with no bounds
           check. Indexed it is 1813 vertices in a buffer of its own and touches neither. */
        u16* index = g_bd.ibo;
        for (int gy = 0; gy < GRID_H; gy++)
        {
            for (int gx = 0; gx < GRID_W; gx++)
            {
                const u16 a = (u16)(gy * (GRID_W + 1) + gx);
                const u16 b = (u16)(a + 1);
                const u16 c = (u16)(a + GRID_W + 1);
                const u16 d = (u16)(c + 1);

                *index++ = a; *index++ = b; *index++ = c;
                *index++ = b; *index++ = d; *index++ = c;
            }
        }

        g_bd.reason = "ok";
        g_bd.ready  = true;
        std::snprintf(g_bd.report, sizeof(g_bd.report),
                      "cpu-field ok: grid %dx%d, %d verts in %d bands (%d/frame), "
                      "double-buffered sweep flip, %d indices, ramp %dx%d, stock shader",
                      GRID_W, GRID_H, VERTS, FIELD_BANDS, VERTS / FIELD_BANDS,
                      INDICES, RAMP_W, RAMP_H);
        return true;
    }
} // namespace
""",
        ),
        (
            """// clang-format off
static constexpr luaL_Reg functions[] =
{
    { "get3D",    Wrap_Graphics::Get3D    },
    { "set3D",    Wrap_Graphics::Set3D    },
    { "getDepth", Wrap_Graphics::GetDepth }
};""",
            """/* Balatro3DS: drawBackdrop(width, mode, time, p1, p2, contrast,
                              c1r,c1g,c1b, c2r,c2g,c2b, c3r,c3g,c3b)

   One draw call for the whole background, in either shader the reference uses.

     mode 0, splash.fs     -- the main menu. p1 = vort_speed, p2 = vort_offset; contrast and
                              the third colour are unused (that shader hardcodes its slate).
     mode 1, background.fs -- every other screen. p1 = spin_time, p2 = spin_amount, and all
                              three colours and the contrast are live.

   Lua never touches GPU state. Returns (drawn, report); false is the caller's cue to paint its
   fallback gradient instead. */
int Wrap_Graphics::DrawBackdrop(lua_State* L)
{
    if (!EnsureBackdrop())
    {
        luax::PushBoolean(L, false);
        lua_pushstring(L, g_bd.reason);
        return 2;
    }

    const int width      = (int)luaL_checknumber(L, 1);
    const int modeArg    = (int)luaL_checknumber(L, 2);
    const int mode       = (modeArg == MODE_BACKGROUND) ? MODE_BACKGROUND : MODE_SPLASH;
    const float time     = (float)luaL_checknumber(L, 3);
    const float p1       = (float)luaL_checknumber(L, 4);
    const float p2       = (float)luaL_checknumber(L, 5);
    const float contrast = (float)luaL_checknumber(L, 6);

    float colours[3][3];
    for (int c = 0; c < 3; c++)
        for (int i = 0; i < 3; i++)
            colours[c][i] = (float)luaL_checknumber(L, 7 + c * 3 + i);

    /* Everything that is a pure function of time, including both shaders' min() calls,
       resolved once here rather than per vertex. A and B fold each shader's swirl into the
       same base + A*radius + B shape; K carries whatever scales the field's length on its way
       to the ramp. */
    float sp, A, B, K, contrastMod;

    if (mode == MODE_BACKGROUND)
    {
        /* background.fs's swirl is
             atan2 + (spin_time*0.1 + 302.2) - 10*(spin_amount*len + (1 - spin_amount))
           which rearranges to base + (-10*spin_amount)*len + (speed - 10 + 10*spin_amount).
           With spin parked at zero the radius term vanishes and it becomes a pure rotation,
           which is why an idle in-run backdrop churns without spiralling. */
        const float speed = p1 * 0.1f + 302.2f;

        sp = time * 2.0f;
        A  = -10.0f * p2;
        B  = speed - 10.0f + 10.0f * p2;

        contrastMod = 0.25f * contrast + 0.5f * p2 + 1.2f;
        K = 0.035f * contrastMod;
    }
    else
    {
        const float speed  = time * p1;
        const float capped = speed < 6.0f ? speed : 6.0f;

        sp = time * 6.0f * p1 + p2 + 1033.0f;
        A  = 2.2f + 0.4f * capped;
        B  = -1.0f - speed * 0.05f - capped * speed * 0.02f + p2;

        const float rev = (time * 1.2f - 4.0f) < 10.0f ? (time * 1.2f - 4.0f) : 10.0f;
        K = 0.17f * rev;
        contrastMod = 0.0f;   /* splash.fs's weights are fixed; its ramp ignores this */
    }

    if (g_bd.rampMode != mode || g_bd.rampKey != contrastMod)
    {
        BuildRamp(mode, contrastMod);
        g_bd.rampMode = mode;
        g_bd.rampKey  = contrastMod;
    }

    /* Checked AFTER the build, which is the only order that works: rampReady starts false and
       BuildRamp is what sets it. Testing it beforehand -- as an earlier revision did, having
       moved the build down into the mode branch without moving the check with it -- declines
       on the first call and therefore on every call, and the backdrop silently never draws. */
    if (!g_bd.rampReady)
    {
        g_bd.reason = "ramp texture init failed";
        luax::PushBoolean(L, false);
        lua_pushstring(L, g_bd.reason);
        return 2;
    }

    Grid* gridPtr = EnsureGrid(mode, width);
    if (gridPtr == nullptr)
    {
        luax::PushBoolean(L, false);
        lua_pushstring(L, g_bd.reason);
        return 2;
    }
    Grid& grid = *gridPtr;

    /* Writing the back buffer is safe against the GPU: the renderer reuses ONE shared vertex
       buffer whose offset resets at Present, which is only sound if a frame's command list has
       fully executed before the next frame's writes begin -- so by the time a buffer that was
       front is written as back, the GPU is done reading it.

       A grid that has not been drawn for a while (menu grid during a run, and vice versa)
       still holds a field from minutes ago; easing through it looks like a glitch, so a gap
       re-primes instead. The 0.5 s threshold is far above any frame-to-frame delta and far
       below any real state dwell. */
    if (grid.primed && std::fabs(time - grid.lastTime) > 0.5f)
        grid.primed = false;
    grid.lastTime = time;

    if (!grid.primed)
    {
        /* Fill the FRONT buffer whole so the first shown frame is coherent -- otherwise the
           screen renders from the flat 0.5 the buffer was built with. The back buffer starts
           its first sweep, with fresh parameters, on the next call. */
        grid.sp = sp; grid.A = A; grid.B = B; grid.K = K;
        grid.band = 0;
        for (int i = 0; i < FIELD_BANDS; i++)
            UpdateField(grid, grid.vbo[grid.front], mode, sp, A, B, K);
        grid.primed = true;
    }
    else
    {
        /* One band of the back buffer per frame, under parameters frozen when its sweep
           started; the flip below is the only moment the drawn field ever changes, so no
           fresh/stale seam can exist on screen. */
        if (grid.band == 0)
        {
            grid.sp = sp; grid.A = A; grid.B = B; grid.K = K;
        }
        UpdateField(grid, grid.vbo[grid.front ^ 1], mode, grid.sp, grid.A, grid.B, grid.K);
        if (grid.band == 0)   /* wrapped: the sweep is complete and the buffer coherent */
            grid.front ^= 1;
    }

    auto& renderer = Renderer<Console::CTR>::Instance();
    renderer.EnsureInFrame();

    /* Depth off, and depth WRITES off. The renderer runs GPU_GEQUAL with GPU_WRITE_ALL over an
       ortho spanning Z_NEAR -10 to Z_FAR 10, and ordinary 2D geometry sits at z = 0 -- the
       middle of that range. A background never needs to test or write depth, and writing it
       once made every later 2D draw in the frame fail the >= test and vanish. */
    C3D_DepthTest(false, GPU_ALWAYS, GPU_WRITE_COLOR);

    /* Anything the 2D path has queued must be submitted while its buffer is still bound. */
    Renderer<Console::CTR>::FlushVertices();

    C3D_SetBufInfo(&grid.buf[grid.front]);
    C3D_TexBind(0, &g_bd.ramp);

    /* ret_col = c1*c1p + c2*c2p + BLACK*cb, then lerped toward white by the bloom in alpha.
       The weights arrive per pixel from the ramp's channels -- which is why the bands stay
       crisp -- and the colours are stage constants, which is what makes per-state recolouring
       work at all. BLACK is splash.fs's own 0.6*vec4(79,99,103)/255. */
    auto pack = [](float r, float g, float b, float a) -> u32 {
        auto ch = [](float v) -> u32 {
            const float c = v < 0.0f ? 0.0f : (v > 1.0f ? 1.0f : v);
            return (u32)(c * 255.0f);
        };
        return (ch(a) << 24) | (ch(b) << 16) | (ch(g) << 8) | ch(r);
    };

    static const GPU_TEVOP_RGB pick[3] = { GPU_TEVOP_RGB_SRC_R, GPU_TEVOP_RGB_SRC_G,
                                           GPU_TEVOP_RGB_SRC_B };
    const float slate[3] = { 0.6f * 79.0f / 255.0f, 0.6f * 99.0f / 255.0f,
                             0.6f * 103.0f / 255.0f };

    /* background.fs weights its whole colour sum by (1 - k) and adds k*colour_1 back as a
       constant; splash.fs has no such term, so k is zero there and the scale is 1. */
    const float k = (mode == MODE_BACKGROUND)
                        ? 0.3f / (contrast <= 0.0f ? 1.0f : contrast) : 0.0f;
    const float scale = 1.0f - k;
    const float* band[3] = { colours[0], colours[1],
                             (mode == MODE_BACKGROUND) ? colours[2] : slate };

    for (int stage = 0; stage < 3; stage++)
    {
        C3D_TexEnv* env = C3D_GetTexEnv(stage);
        C3D_TexEnvInit(env);
        C3D_TexEnvColor(env, pack(band[stage][0] * scale, band[stage][1] * scale,
                                  band[stage][2] * scale, 1.0f));

        if (stage == 0)
        {
            C3D_TexEnvSrc(env, C3D_RGB, GPU_TEXTURE0, GPU_CONSTANT, GPU_PRIMARY_COLOR);
            C3D_TexEnvOpRgb(env, pick[stage], GPU_TEVOP_RGB_SRC_COLOR, GPU_TEVOP_RGB_SRC_COLOR);
            C3D_TexEnvFunc(env, C3D_RGB, GPU_MODULATE);
        }
        else
        {
            C3D_TexEnvSrc(env, C3D_RGB, GPU_TEXTURE0, GPU_CONSTANT, GPU_PREVIOUS);
            C3D_TexEnvOpRgb(env, pick[stage], GPU_TEVOP_RGB_SRC_COLOR, GPU_TEVOP_RGB_SRC_COLOR);
            C3D_TexEnvFunc(env, C3D_RGB, GPU_MULTIPLY_ADD);
        }

        C3D_TexEnvSrc(env, C3D_Alpha, GPU_CONSTANT, GPU_CONSTANT, GPU_CONSTANT);
        C3D_TexEnvFunc(env, C3D_Alpha, GPU_REPLACE);
    }

    {
        C3D_TexEnv* env = C3D_GetTexEnv(3);
        C3D_TexEnvInit(env);
        if (mode == MODE_BACKGROUND)
        {
            /* background.fs's constant term, k*colour_1, added on top. */
            C3D_TexEnvColor(env, pack(colours[0][0] * k, colours[0][1] * k,
                                      colours[0][2] * k, 1.0f));
            C3D_TexEnvSrc(env, C3D_RGB, GPU_PREVIOUS, GPU_CONSTANT, GPU_PRIMARY_COLOR);
            C3D_TexEnvOpRgb(env, GPU_TEVOP_RGB_SRC_COLOR, GPU_TEVOP_RGB_SRC_COLOR,
                            GPU_TEVOP_RGB_SRC_COLOR);
            C3D_TexEnvFunc(env, C3D_RGB, GPU_ADD);
        }
        else
        {
            /* The white bloom on the brightest cores, without which the arms read flat. */
            C3D_TexEnvColor(env, pack(1.0f, 1.0f, 1.0f, 1.0f));
            C3D_TexEnvSrc(env, C3D_RGB, GPU_CONSTANT, GPU_PREVIOUS, GPU_TEXTURE0);
            C3D_TexEnvOpRgb(env, GPU_TEVOP_RGB_SRC_COLOR, GPU_TEVOP_RGB_SRC_COLOR,
                            GPU_TEVOP_RGB_SRC_ALPHA);
            C3D_TexEnvFunc(env, C3D_RGB, GPU_INTERPOLATE);
        }
        C3D_TexEnvSrc(env, C3D_Alpha, GPU_CONSTANT, GPU_CONSTANT, GPU_CONSTANT);
        C3D_TexEnvFunc(env, C3D_Alpha, GPU_REPLACE);
    }

    C3D_DrawElements(GPU_TRIANGLES, INDICES, C3D_UNSIGNED_SHORT, g_bd.ibo);

    /* Put back every piece of global state this touched. The shader program is deliberately
       NOT among them: this draw never rebinds it, which is the entire point. */
    for (int stage = 1; stage < 4; stage++)
        C3D_TexEnvInit(C3D_GetTexEnv(stage));

    C3D_DepthTest(true, GPU_GEQUAL, GPU_WRITE_ALL);
    renderer.RestoreBufInfo();
    Renderer<Console::CTR>::AfterForeignDraw();

    luax::PushBoolean(L, true);
    lua_pushstring(L, g_bd.report);
    return 2;
}

// clang-format off
static constexpr luaL_Reg functions[] =
{
    { "get3D",        Wrap_Graphics::Get3D        },
    { "set3D",        Wrap_Graphics::Set3D        },
    { "getDepth",     Wrap_Graphics::GetDepth     },
    { "drawBackdrop", Wrap_Graphics::DrawBackdrop }
};""",
        ),
    ],
}


SCREEN_LOOKUP_PATCHES = {
    "marker": "Balatro3DS: screen id is not an index",
    "replacements": [
        (
            """    const ScreenInfo& GetScreenInfo(Screen id)
    {
        const auto& info = GetScreenInfo();

        return info[id];
    }
""",
            """    const ScreenInfo& GetScreenInfo(Screen id)
    {
        const auto& info = GetScreenInfo();

        /* Balatro3DS: screen id is not an index into the active screen list.

           Screen::BOTTOM is 2, and it is the *second* entry of the two-element
           altScreenInfo used whenever stereoscopic 3D is off -- so `info[id]`
           reads one past the end of that array and lands on screenInfo[0],
           the 400px-wide left eye. CheckScreenName hands the caller an id, not
           an index, so every love.graphics.getWidth("bottom") answered 400
           instead of 320 with the 3D slider down, and every layout derived from
           it (tooltip wrapping, card drag clamping) was 80px too wide.

           Match on the id instead. Falls back to the first entry, which is what
           an out-of-range id would previously have aliased to anyway. */
        for (auto& value : info)
        {
            if (value.id == id)
                return value;
        }

        return info[0];
    }
""",
        ),
    ],
}


# --------------------------------------------------------------------------- instrumentation
# Phase 0 of the hardware optimisation pass. Nothing here changes what is drawn; it makes the
# renderer able to say what it actually did, so a batching change can be proved rather than
# assumed.
#
# The counter that matters is "actual GPU submissions". Until now `drawCallsBatched` counted
# commands as FlushVertices consumed them, which on a backend that issues one C3D_DrawArrays
# per command is the same number as `drawCalls` -- so it could never show a batching win, and
# reading it mid-frame reported the PREVIOUS flush because a flush only happens on a texture
# change or at Present. Both problems are fixed the same way: count real submissions, and latch
# the whole set at Present so a reader always sees a frame that has finished.

RENDERER_COUNTERS_TCC_PATCHES = {
    "marker": "Balatro3DS: per-frame renderer counters",
    "replacements": [
        (
            """    template<Console::Platform T = Console::ALL>
    class Renderer
    {
      public:
        static inline int shaderSwitches   = 0;
        static inline int drawCalls        = 0;
        static inline int drawCallsBatched = 0;
""",
            """    /* Balatro3DS: per-frame renderer counters.

       `drawCalls` is the number of logical LOVE draw operations; `gpuSubmits` is the number of
       C3D_DrawArrays/C3D_DrawElements calls those turned into. Before the batching work those
       two were always equal, which is exactly the finding this pass is trying to move.

       Everything is latched into `lastFrame` at Present. A reader inside a frame cannot see its
       own draws -- the flush that submits them has not happened yet -- so any measurement taken
       during frame N must be read in frame N+1 or it reports frame N-1's flush. `benchmark.lua`
       probes across frames for that reason.

       Cost: a handful of integer increments per draw. Cheap enough to leave in release, and the
       alternative -- a build flag -- means the numbers are unavailable on the build people
       actually run. */
    struct RendererCounters
    {
        int logicalDraws       = 0;  /* LOVE-level draw operations */
        int gpuSubmits         = 0;  /* actual C3D_DrawArrays + C3D_DrawElements */
        int batchRuns          = 0;  /* coalesced runs; equals gpuSubmits when batching */
        int mergedCommands     = 0;  /* commands that joined a run rather than starting one */
        int maxRunLength       = 0;  /* most commands merged into a single submission */
        int textureBinds       = 0;  /* C3D_TexBind calls */
        int stateBarriers      = 0;  /* flushes forced by a state change */
        int vertices           = 0;  /* vertices handed to the GPU */
        int commandAllocs      = 0;  /* DrawCommands that had to reach the heap */
        int preventedOverflows = 0;  /* draws dropped rather than run off a buffer */
        int vertexHighWater    = 0;  /* peak use of the shared frame vertex buffer */
    };

    template<Console::Platform T = Console::ALL>
    class Renderer
    {
      public:
        static inline int shaderSwitches   = 0;
        static inline int drawCalls        = 0;
        static inline int drawCallsBatched = 0;

        /* Balatro3DS: live counters for the frame being built, and the last frame that
           finished. Only the latched copy is trustworthy from Lua. */
        static inline RendererCounters counters {};
        static inline RendererCounters lastFrame {};
""",
        ),
        (
            """        static inline size_t m_vertexOffset = 0;
""",
            """        static inline size_t m_vertexOffset = 0;
""",
        ),
    ],
}


DRAWCOMMAND_ALLOC_COUNTER_PATCHES = {
    "marker": "Balatro3DS: count the commands that reach the heap",
    "replacements": [
        (
            """namespace love
{
    using namespace vertex;
""",
            """namespace love
{
    using namespace vertex;

    /* Balatro3DS: count the commands that reach the heap.

       A four-vertex quad allocating two arrays out of newlib's malloc is the single most
       repeated piece of per-draw bookkeeping in the frame, and the only way to prove it has
       stopped is to count it. An `inline` variable rather than `static inline`: one copy for
       the whole program, not one per translation unit. */
    inline int drawCommandHeapAllocs = 0;
""",
        ),
    ],
}


RENDERER_STATS_LATCH_PATCHES = {
    "marker": "Balatro3DS: latch the frame's counters",
    "replacements": [
        (
            """        ++drawCallsBatched;
        C3D_DrawArrays(*s_primitive, m_vertexOffset, command.count);
        m_vertexOffset += command.count;
""",
            """        ++drawCallsBatched;

        /* Balatro3DS: one command, one submission -- this is the baseline the batching flush
           is measured against. */
        ++counters.gpuSubmits;
        ++counters.batchRuns;
        counters.vertices += (int)command.count;
        if (counters.maxRunLength < 1)
            counters.maxRunLength = 1;

        C3D_DrawArrays(*s_primitive, m_vertexOffset, command.count);
        m_vertexOffset += command.count;
""",
        ),
        (
            """            C3D_TexBind(0, command.handles.back());
        }
""",
            """            ++counters.textureBinds;
            C3D_TexBind(0, command.handles.back());
        }
""",
        ),
        (
            """        FlushVertices();
        C3D_FrameEnd(0);

        m_vertexOffset = 0;

        this->inFrame = false;
    }
""",
            """        FlushVertices();
        C3D_FrameEnd(0);

        /* Balatro3DS: latch the frame's counters before anything resets them.

           This is the only point in the frame where every draw has been submitted, so it is the
           only point where a total is true. Lua reads `lastFrame`; reading the live counters
           from inside a frame reports a mixture of that frame's queued-but-unflushed work and
           the previous frame's tail. */
        counters.logicalDraws    = drawCalls;
        counters.vertexHighWater = (int)m_vertexOffset;
        counters.commandAllocs   = drawCommandHeapAllocs;

        lastFrame             = counters;
        counters              = RendererCounters {};
        drawCommandHeapAllocs = 0;

        m_vertexOffset = 0;

        this->inFrame = false;
    }
""",
        ),
    ],
}


WRAP_GRAPHICS_STATS_HPP_PATCHES = {
    "marker": "Balatro3DS: getBatchStats",
    "replacements": [
        (
            """    /* Balatro3DS: drawBackdrop -- the animated background, evaluated on the GPU. */
    int DrawBackdrop(lua_State* L);
""",
            """    /* Balatro3DS: drawBackdrop -- the animated background, evaluated on the GPU. */
    int DrawBackdrop(lua_State* L);

    /* Balatro3DS: getBatchStats -- what the renderer actually submitted last frame. */
    int GetBatchStats(lua_State* L);

    /* Balatro3DS: getRuntimeInfo -- which build this is and what the console gave it. */
    int GetRuntimeInfo(lua_State* L);

    /* Balatro3DS: setBatching -- runtime A/B switch for the coalescing flush. */
    int SetBatching(lua_State* L);
""",
        ),
    ],
}


WRAP_GRAPHICS_STATS_CPP_PATCHES = {
    "marker": "Balatro3DS: getBatchStats -- what the renderer",
    "replacements": [
        (
            """// clang-format off
static constexpr luaL_Reg functions[] =
{
    { "get3D",        Wrap_Graphics::Get3D        },
    { "set3D",        Wrap_Graphics::Set3D        },
    { "getDepth",     Wrap_Graphics::GetDepth     },
    { "drawBackdrop", Wrap_Graphics::DrawBackdrop }
};""",
            """/* Balatro3DS: getBatchStats -- what the renderer actually submitted last frame.

   Two tables' worth of numbers on one table. The unprefixed keys are the LAST COMPLETED frame,
   which is the only set a caller can trust: a reader inside frame N sees commands that are
   still queued, because the flush that submits them has not run yet. The `live_` keys are the
   frame being built, useful only for watching a single case in isolation.

   `logical` against `submits` is the whole batching argument. `runs`, `maxrun` and `merged`
   say how the coalescing actually landed; `barriers` and `texbinds` say what stopped it. */
int Wrap_Graphics::GetBatchStats(lua_State* L)
{
    const auto& last = Renderer<Console::CTR>::lastFrame;
    const auto& live = Renderer<Console::CTR>::counters;

    lua_createtable(L, 0, 30);

    auto set = [&](const char* key, lua_Integer value) {
        lua_pushinteger(L, value);
        lua_setfield(L, -2, key);
    };

    set("logical", last.logicalDraws);
    set("submits", last.gpuSubmits);
    set("runs", last.batchRuns);
    set("merged", last.mergedCommands);
    set("maxrun", last.maxRunLength);
    set("texbinds", last.textureBinds);
    set("barriers", last.stateBarriers);
    set("verts", last.vertices);
    set("allocs", last.commandAllocs);
    set("overflows", last.preventedOverflows);
    set("vhigh", last.vertexHighWater);

    set("live_logical", Renderer<Console::CTR>::drawCalls);
    set("live_submits", live.gpuSubmits);
    set("live_runs", live.batchRuns);
    set("live_texbinds", live.textureBinds);
    set("live_barriers", live.stateBarriers);
    set("live_overflows", live.preventedOverflows);

    set("vcapacity", Renderer<Console::CTR>::VertexCapacity());

    set("batching", Renderer<Console::CTR>::BatchingMode());

    return 1;
}

/* Balatro3DS: getRuntimeInfo -- which build this is and what the console gave it.

   Written for `benchmark.txt`: a before/after pair of reports is worthless if the two cannot be
   told apart, and every field here is something that silently changes the numbers. The CPU time
   limit in particular is the one New3DS knob this port deliberately does NOT set, and a report
   that does not say so invites someone to "discover" it twice. */
/* Balatro3DS: setBatching(mode) -- pick how the flush merges commands, at runtime, so the
   question can be settled on the console instead of by rebuilding.

     0 / false  off, one submission per command
     1 / true   merge, taking fans and strips apart into triangle lists
     2          merge, keeping the vertices and drawing through an index buffer */
int Wrap_Graphics::SetBatching(lua_State* L)
{
    int mode = 0;

    if (lua_isnumber(L, 1))
        mode = (int)lua_tointeger(L, 1);
    else
        mode = luax::CheckBoolean(L, 1) ? 1 : 0;

    Renderer<Console::CTR>::SetBatchingMode(mode);
    return 0;
}

int Wrap_Graphics::GetRuntimeInfo(lua_State* L)
{
    lua_createtable(L, 0, 10);

    lua_pushstring(L, BALATRO3DS_PATCH_VERSION);
    lua_setfield(L, -2, "patch_version");

    /* Whether the runtime itself was built optimised. A Debug LovePotion is several times
       slower and nothing else in the report would show it. */
#if defined(__OPTIMIZE_SIZE__)
    lua_pushstring(L, "-Os");
#elif defined(__OPTIMIZE__)
    lua_pushstring(L, "-O2/-O3");
#else
    lua_pushstring(L, "-O0 (UNOPTIMISED RUNTIME)");
#endif
    lua_setfield(L, -2, "runtime_opt");

#if defined(NDEBUG)
    lua_pushstring(L, "release");
#else
    lua_pushstring(L, "debug");
#endif
    lua_setfield(L, -2, "runtime_build");

    lua_pushstring(L, __DATE__ " " __TIME__);
    lua_setfield(L, -2, "runtime_compiled");

    bool isNew3DS = false;
    APT_CheckNew3DS(&isNew3DS);
    lua_pushboolean(L, isNew3DS);
    lua_setfield(L, -2, "new3ds");

    /* APT_GetAppCpuTimeLimit reports the share of core 1 (the system core) the application is
       allowed. 0 is the default and means "none": a worker thread cannot run there. Nothing in
       this port sets it; the New3DS worker uses core 2, which needs no grant. */
    u32 cpuLimit = 0;
    if (R_SUCCEEDED(APT_GetAppCpuTimeLimit(&cpuLimit)))
        lua_pushinteger(L, (lua_Integer)cpuLimit);
    else
        lua_pushinteger(L, -1);
    lua_setfield(L, -2, "cpu_time_limit");

    lua_pushinteger(L, (lua_Integer)svcGetSystemTick());
    lua_setfield(L, -2, "tick");

    return 1;
}

// clang-format off
static constexpr luaL_Reg functions[] =
{
    { "get3D",          Wrap_Graphics::Get3D          },
    { "set3D",          Wrap_Graphics::Set3D          },
    { "getDepth",       Wrap_Graphics::GetDepth       },
    { "drawBackdrop",   Wrap_Graphics::DrawBackdrop   },
    { "getBatchStats",  Wrap_Graphics::GetBatchStats  },
    { "getRuntimeInfo", Wrap_Graphics::GetRuntimeInfo },
    { "setBatching",    Wrap_Graphics::SetBatching    }
};""",
        ),
    ],
}


RENDERER_BATCH_HPP_PATCHES = {
    "marker": "Balatro3DS: identifies this set of runtime patches",
    "replacements": [
        (
            """#pragma once

#include <utilities/driver/renderer/renderer.tcc>
""",
            """#pragma once

/* Balatro3DS: identifies this set of runtime patches in benchmark.txt.

   Bump it whenever a patch in dev/patch_lovepotion.py changes something a measurement would
   notice. Two benchmark reports that disagree and cannot be told apart are worse than no
   report at all. */
#define BALATRO3DS_PATCH_VERSION "2026-08-opt1"

#include <utilities/driver/renderer/renderer.tcc>
""",
        ),
        (
            """        static inline constexpr int MAX_OBJECTS        = 0x1000;
        static inline constexpr int VERTEX_BUFFER_SIZE = 6 * MAX_OBJECTS;
        static inline constexpr auto TOTAL_BUFFER_SIZE = VERTEX_BUFFER_SIZE * VERTEX_SIZE;
""",
            """        static inline constexpr int MAX_OBJECTS        = 0x1000;
        static inline constexpr int VERTEX_BUFFER_SIZE = 6 * MAX_OBJECTS;
        static inline constexpr auto TOTAL_BUFFER_SIZE = VERTEX_BUFFER_SIZE * VERTEX_SIZE;

""",
        ),
        (
            """        static void AfterForeignDraw();
""",
            """        static void AfterForeignDraw();

        /* Balatro3DS: sizes of the two shared per-frame arenas, for the overflow report. */
        static constexpr int VertexCapacity()
        {
            return VERTEX_BUFFER_SIZE;
        }

        /* Balatro3DS: how adjacent compatible commands are merged, if at all.

             OFF      one C3D_DrawArrays per command. The pre-batching runtime, exactly.
             EXPAND   fans and strips are taken apart into independent triangles and the run is
                      drawn with one C3D_DrawArrays(GPU_TRIANGLES).

           There was a third mode, and this is the useful part of the comment: the run kept its
           original vertices and got a u16 index stream, submitted with one
           C3D_DrawElements(GPU_TRIANGLES). It is strictly cheaper -- a four-vertex quad stays
           four vertices instead of becoming six, and the index write is 12 bytes against 72 of
           duplicated vertex -- and on a New 3DS it HANGS THE GPU. Not a crash: the picture
           freezes with the audio still playing, because the main thread is stuck in
           C3D_FrameBegin waiting on a render queue that never completes, so there is no ARM11
           exception and Luma writes no dump.

           Measured on hardware, August 2026, by running the same frames through both modes.
           The backdrop draws indexed and is fine, so it is not that C3D_DrawElements is unusable
           here -- something about doing it repeatedly, mid-frame, against the shared vertex
           buffer, is. Alignment of the index pointer and the width of the offset field in
           GPUREG_INDEXBUFFER_CONFIG are the two candidates nobody has ruled out.

           It is deleted rather than left behind a flag, because a mode reachable from a config
           file that locks up the console is a trap, and because expansion already gets the
           win. citro2d expands everything to GPU_TRIANGLES too; this is the trodden path. */
        enum BatchMode
        {
            BATCH_OFF    = 0,
            BATCH_EXPAND = 1
        };

        static int BatchingMode()
        {
            return s_batchMode;
        }

        static void SetBatchingMode(int mode)
        {
            s_batchMode = (mode < BATCH_OFF || mode > BATCH_EXPAND) ? BATCH_OFF : mode;
        }
""",
        ),
        (
            """        static inline CommonFormat m_format = CommonFormat::NONE;
        static inline Vertex* m_vertices    = nullptr;
""",
            """        static inline CommonFormat m_format = CommonFormat::NONE;
        static inline Vertex* m_vertices    = nullptr;


        /* Balatro3DS: on, having had a clean run on a New 3DS. perf_flags.txt can still turn
           it off, which is how the indexed mode above was pinned down. */
        static inline int s_batchMode = BATCH_EXPAND;
""",
        ),
    ],
}




# --------------------------------------------------------------------------- batching
# Phase 1. The renderer already queued commands; it just never merged them. Every queued
# command still got its own C3D_DrawArrays, so twenty same-texture image draws were twenty GPU
# submissions -- measured at 228 us on a New 3DS against 33 us for the same twenty sprites
# through one SpriteBatch submission. The gap is entirely per-submission CPU cost.
#
# What stops a merge, and why:
#
#   * TEXTURE -- already handled upstream at queue time. Render() flushes and rebinds whenever
#     a command's texture differs from the bound one, so every command sitting in the queue
#     shares one texture by construction. It is not part of the run key because it cannot vary.
#   * FORMAT (PRIMITIVE / TEXTURE / FONT) -- selects the TexEnv chain, which is global state.
#   * PRIMITIVE TYPE -- fans, strips and lists cannot share one submission's topology.
#   * SHADER -- carried in the run key for safety. On this backend every command uses
#     STANDARD_DEFAULT (font.cpp and spritebatch.cpp both special-case ctr), and the other two
#     `defaults` slots are never even constructed, so it never varies today.
#   * BLEND, SCISSOR, COLOUR MASK, CULL, STENCIL, VIEWPORT, RENDER TARGET -- these are all
#     issued to citro3d immediately but only take effect when a draw is submitted, so a queue
#     that spans one of them would have drawn its earlier commands under the LATER state. That
#     was already wrong before batching; batching makes the queues longer and would have made
#     it visible. Each of those setters now flushes first, which is both the correctness fix
#     and the barrier the run key needs.
#
# Colour is deliberately NOT a barrier: it is per vertex, baked in at FillVertices time, which
# is exactly what lets a hand of differently tinted cards batch.
#
# Fans are the hard part. A four-vertex image quad arrives as PRIMITIVE_TRIANGLE_FAN, and
# concatenating twenty of those into one 80-vertex fan would draw a spiral. They are submitted
# instead as one indexed GPU_TRIANGLES draw whose index stream names each command's own
# vertices in fan order -- the same triangles, in the same order, from the same vertices.
#
# Nothing is ever reordered. A run is a contiguous slice of the queue, so painter's order is
# bit-for-bit what it was.

BATCH_INDICES_HPP = Path("platform/ctr/include/utilities/driver/batch_indices.hpp")

BATCH_INDICES_FILE = {
    "contents": """#pragma once

/* Balatro3DS: fan and strip to triangle-list conversion, for the batching flush.

   Its own file, and free of every 3DS header, for one reason: this is the only part of the
   coalescing flush that is arithmetic rather than GPU state, it is the part that silently
   draws the wrong triangles if it is wrong, and a host compiler can build it. See
   tests/test_batch_indices.lua, which compiles this header directly and checks the conversion
   against a separately written statement of what a fan and a strip rasterise.

   Why the conversion exists at all: an image quad reaches this backend as a four-vertex
   TRIANGLE FAN. Concatenating twenty of them into the shared vertex buffer and drawing one
   80-vertex fan would draw a spiral, so each command's triangles are written out
   independently and the run goes out as one GPU_TRIANGLES draw -- the same triangles, in the
   same order, from duplicated corners. Duplicating them costs 50% more vertices for a quad
   and is what citro2d does for everything it draws; the alternative, an index buffer, hangs
   this GPU (see BatchMode in renderer_ext.hpp). */

#include <cstddef>

namespace love
{
    namespace batching
    {
        enum class Topology
        {
            Triangles, /* already a list; concatenates without indices */
            Fan,
            Strip,
            Other /* points, quads: not batchable, drawn on their own */
        };

        /* How many vertices -- or equivalently indices, the count is the same either way --
           a command of `vertices` vertices becomes as an independent triangle list.
           n-2 triangles for a fan or a strip, and a list is already itself. */
        constexpr size_t TriangleVertexCount(Topology topology, size_t vertices)
        {
            switch (topology)
            {
                case Topology::Triangles:
                    /* Whole triangles only. A list whose vertex count is not a multiple of
                       three is malformed and its stray vertices draw nothing, so counting them
                       would make this disagree with what ForEachTriangle actually emits. */
                    return vertices - (vertices % 3);
                case Topology::Fan:
                case Topology::Strip:
                    return vertices < 3 ? 0 : (vertices - 2) * 3;
                default:
                    return 0;
            }
        }

        /* Whether a run of more than one command of this topology has to be taken apart at
           all. Triangle lists concatenate directly; anything else would be welded together --
           twenty four-vertex fans laid end to end draw one eighty-vertex spiral. */
        constexpr bool NeedsExpansion(Topology topology)
        {
            return topology == Topology::Fan || topology == Topology::Strip;
        }

        /* The triangles of one command, in rasterisation order, as (a, b, c) triples handed to
           `emit`. The single description of what a fan and a strip mean; both the vertex
           expansion and the index stream below are written in terms of it, so they cannot
           disagree about winding or ordering. */
        template<typename Emit>
        inline void ForEachTriangle(Topology topology, size_t count, Emit emit)
        {
            if (count < 3)
                return;

            if (topology == Topology::Triangles)
            {
                /* Already a list. Included so that TriangleVertexCount and this agree for
                   every topology: the flush never expands a list -- it concatenates them --
                   but a helper whose count says one thing and whose output says another is a
                   trap for the next caller. */
                for (size_t t = 0; t + 2 < count; t += 3)
                    emit(t, t + 1, t + 2);

                return;
            }

            if (topology == Topology::Fan)
            {
                /* (0,1,2) (0,2,3) (0,3,4) ... -- exactly the triangles GPU_TRIANGLE_FAN
                   rasterises, in the order it rasterises them. */
                for (size_t t = 1; t + 1 < count; t++)
                    emit((size_t)0, t, t + 1);

                return;
            }

            if (topology == Topology::Strip)
            {
                /* A strip alternates winding every triangle, and flattening it has to alternate
                   with it. The ctr path runs GPU_CULL_NONE today, so nothing would notice --
                   but SetMeshCullMode can change that, and this must not quietly depend on a
                   default staying put. */
                for (size_t t = 0; t + 2 < count; t++)
                {
                    if ((t & 1) == 0)
                        emit(t, t + 1, t + 2);
                    else
                        emit(t + 1, t, t + 2);
                }
            }
        }

        /* Write one command's triangles out as independent vertices, duplicating the shared
           ones. Returns one past the last vertex written, so a run appends by feeding the
           result back in.

           This is what citro2d does -- it expands everything to GPU_TRIANGLES and draws with
           C3D_DrawArrays -- and it is the only path on this GPU with real mileage on it. The
           cost is 50% more vertices for a four-vertex quad, out of a frame buffer of 24576;
           the benefit is that no new GPU state is involved at all. */
        template<typename Vertex>
        inline Vertex* ExpandTriangles(Topology topology, const Vertex* source, size_t count,
                                       Vertex* out)
        {
            ForEachTriangle(topology, count, [&](size_t a, size_t b, size_t c) {
                *out++ = source[a];
                *out++ = source[b];
                *out++ = source[c];
            });

            return out;
        }

    } // namespace batching
} // namespace love
""",
}

RENDERER_BATCH_CPP_PATCHES = {
    "marker": "Balatro3DS: coalesce adjacent compatible commands",
    "replacements": [
        (
            """void Renderer<Console::CTR>::FlushVertices()
{
    if (s_dirtyProjection)
    {
        const auto uniforms = Shader<Console::CTR>::current->GetUniformLocations();
        C3D_FVUnifMtx4x4(GPU_VERTEX_SHADER, uniforms.uLocProjMtx, &s_projection);
        C3D_FVUnifMtx4x4(GPU_VERTEX_SHADER, uniforms.uLocMdlView, &s_modelView);

        s_dirtyProjection = false;
    }

    for (const auto& command : m_commands)
    {
        std::memcpy(m_vertices + m_vertexOffset, command.Vertices().get(), command.size);
        SetTexEnvFunction(command.format);

        if (s_primitiveType != command.type)
        {
            if (!(s_primitive = primitiveModes.Find(command.type)))
                throw love::Exception("Invalid primitive mode");

            s_primitiveType = command.type;
        }

        ++drawCallsBatched;

        /* Balatro3DS: one command, one submission -- this is the baseline the batching flush
           is measured against. */
        ++counters.gpuSubmits;
        ++counters.batchRuns;
        counters.vertices += (int)command.count;
        if (counters.maxRunLength < 1)
            counters.maxRunLength = 1;

        C3D_DrawArrays(*s_primitive, m_vertexOffset, command.count);
        m_vertexOffset += command.count;
    }

    m_commands.clear();
}
""",
            """/* Balatro3DS: how many extra vertices a command may cost before merging it stops paying.

   Merging saves one C3D_DrawArrays; taking a fan apart costs the duplicated corners. Measured
   on a New 3DS, August 2026, by running the same cases through the merging and non-merging
   flush:

     4-vertex quad   -> 6 vertices, +2   rect_fill_square 8.60 -> 7.77 us, particles -20%,
                                         image_draw_20_one_texture 228 -> 148 us
     16-vertex fan   -> 42 vertices, +26 rect_fill_round4 13.44 -> 15.33 us
     20-vertex fan   -> 54 vertices, +34 rect_fill_round8 14.13 -> 17.59 us

   So a C3D_DrawArrays is worth well under the ~3.5 us that expanding a rounded rectangle
   costs -- it only appends a dozen words to the command buffer, and the 8 us that "one draw
   command" measures is nearly all CPU-side construction, not submission. The saving is real
   for quads and negative for anything with a corner fan on it.

   Eight is inside the proven-good region rather than at a measured break-even: +2 wins and
   +26 loses, and nothing between them has been measured. It admits fans and strips up to
   seven vertices, which is every image, every card, every particle and every plain rectangle
   this game draws. Rounded rectangles keep their own submission, exactly as before. */
static constexpr size_t EXPANSION_BUDGET = 8;

/* Balatro3DS: which of the index helpers' topologies a LOVE primitive is. */
static inline batching::Topology TopologyOf(PrimitiveType type)
{
    switch (type)
    {
        case PRIMITIVE_TRIANGLES:
            return batching::Topology::Triangles;
        case PRIMITIVE_TRIANGLE_FAN:
            return batching::Topology::Fan;
        case PRIMITIVE_TRIANGLE_STRIP:
            return batching::Topology::Strip;
        default:
            return batching::Topology::Other;
    }
}

/* Balatro3DS: coalesce adjacent compatible commands into one GPU submission.

   The queue is walked front to back and never reordered. A run is the longest contiguous slice
   whose commands agree on format, primitive type and shader -- the three pieces of state a
   single submission cannot express two of. Texture is not in the key because Render() has
   already flushed on every texture change, so the whole queue shares one bound texture; the
   state that DOES vary independently (blend, scissor, cull, colour mask, stencil, viewport,
   render target) now flushes at its setter, so it cannot span a run either.

   Three submission shapes come out of that:

     one command                -> C3D_DrawArrays with its own primitive. Identical to before.
     several triangle LISTS     -> C3D_DrawArrays over the concatenation. Lists concatenate.
     several fans or strips     -> one indexed C3D_DrawElements(GPU_TRIANGLES). Concatenating
                                   their vertices would weld them into one giant fan, so the
                                   index stream re-states each command's own triangles.

   Neither arena is ever overrun. The vertex arena is the one that used to be written past with
   no check at all -- a corruption that surfaced as an ARM11 prefetch abort several seconds and
   one unrelated allocation later -- so a command that will not fit is dropped and counted
   instead. The index arena is softer: a run that will not fit falls back to one submission per
   command, which needs no indices, so its size is a speed knob and not a correctness one. */
void Renderer<Console::CTR>::FlushVertices()
{
    if (s_dirtyProjection)
    {
        const auto uniforms = Shader<Console::CTR>::current->GetUniformLocations();
        C3D_FVUnifMtx4x4(GPU_VERTEX_SHADER, uniforms.uLocProjMtx, &s_projection);
        C3D_FVUnifMtx4x4(GPU_VERTEX_SHADER, uniforms.uLocMdlView, &s_modelView);

        s_dirtyProjection = false;
    }

    const size_t commandCount = m_commands.size();
    size_t first              = 0;

    while (first < commandCount)
    {
        const DrawCommand& head = m_commands[first];

        /* The arena is full. Everything still queued is dropped rather than written past the
           end of a linearAlloc block; a missing card is a bug report, a clobbered heap is a
           crash somewhere else entirely. */
        if (m_vertexOffset + head.count > (size_t)VERTEX_BUFFER_SIZE)
        {
            counters.preventedOverflows += (int)(commandCount - first);
            break;
        }

        const auto topology = TopologyOf(head.type);

        /* Whether merging this run means taking its commands apart. A run of one never does --
           it is drawn with its own primitive, exactly as before -- so the budget below counts
           each command at its MERGED cost, and a command that will not fit merged simply ends
           up in a run of one and is drawn natively at its smaller cost. */
        const bool expands = batching::NeedsExpansion(topology);

        /* What merging would cost this command in vertices, and whether that is worth a
           submission. A command too expensive to take apart is drawn on its own, exactly as
           the unbatched renderer drew it. */
        const auto mergedCost = [&](size_t count) {
            return expands ? batching::TriangleVertexCount(topology, count) : count;
        };
        const auto worthMerging = [&](size_t count) {
            return mergedCost(count) <= count + EXPANSION_BUDGET;
        };

        size_t last   = first + 1;
        size_t staged = mergedCost(head.count);

        if (s_batchMode != BATCH_OFF && worthMerging(head.count))
        {
            while (last < commandCount)
            {
                const DrawCommand& next = m_commands[last];

                if (next.format != head.format || next.type != head.type ||
                    next.shader != head.shader)
                    break;

                if (!worthMerging(next.count))
                    break;

                const size_t cost = mergedCost(next.count);

                if (m_vertexOffset + staged + cost > (size_t)VERTEX_BUFFER_SIZE)
                    break;

                staged += cost;
                ++last;
            }
        }

        const bool takeApart = (last - first) > 1 && expands;

        SetTexEnvFunction(head.format);

        if (s_primitiveType != head.type)
        {
            if (!(s_primitive = primitiveModes.Find(head.type)))
                throw love::Exception("Invalid primitive mode");

            s_primitiveType = head.type;
        }

        const size_t vertexStart = m_vertexOffset;

        for (size_t k = first; k < last; k++)
        {
            const DrawCommand& command = m_commands[k];
            const size_t base          = m_vertexOffset;

            if (takeApart)
            {
                /* Independent triangles, written straight into the frame's vertex buffer.
                   Costs the duplicated corners and buys a draw that uses nothing this GPU is
                   not asked to do on every citro2d frame. */
                Vertex* out = batching::ExpandTriangles(topology, command.Vertices().get(),
                                                        command.count, m_vertices + base);
                m_vertexOffset = (size_t)(out - m_vertices);
                continue;
            }

            std::memcpy(m_vertices + base, command.Vertices().get(), command.size);
            m_vertexOffset += command.count;
        }

        const size_t count = last - first;

        drawCallsBatched += (int)count;
        counters.vertices += (int)(m_vertexOffset - vertexStart);
        counters.mergedCommands += (int)(count - 1);
        ++counters.batchRuns;
        ++counters.gpuSubmits;

        if ((int)count > counters.maxRunLength)
            counters.maxRunLength = (int)count;

        const size_t drawn = m_vertexOffset - vertexStart;

        /* A merged run of fans has been taken apart, so it is a triangle list now whatever it
           arrived as. A run of one still goes out under its own primitive. A run of degenerate
           fans -- fewer than three vertices each -- produces nothing, and a zero-vertex draw is
           a command list entry that asks the GPU for nothing. */
        if (drawn > 0)
            C3D_DrawArrays(takeApart ? GPU_TRIANGLES : *s_primitive, (int)vertexStart,
                           (int)drawn);

        first = last;
    }

    m_commands.clear();
}
""",
        ),
        # --- state barriers ---------------------------------------------------------------
        (
            """void Renderer<Console::CTR>::SetScissor(const Rect& scissor, bool canvasActive)
{
    this->targets[love::GetActiveScreen()].SetScissor(scissor, canvasActive);
}
""",
            """void Renderer<Console::CTR>::SetScissor(const Rect& scissor, bool canvasActive)
{
    /* Balatro3DS: barrier. C3D_SetScissor only marks citro3d's context dirty; the register is
       written by C3Di_UpdateContext, which runs inside the next draw submission. Queued
       commands would therefore have been clipped by a scissor set after they were issued. */
    Renderer::FlushBarrier();

    this->targets[love::GetActiveScreen()].SetScissor(scissor, canvasActive);
}
""",
        ),
        (
            """    C3D_StencilTest(enabled, *compareOp, value, 0xFFFFFFFF, 0xFFFFFFFF);
""",
            """    /* Balatro3DS: barrier -- see SetScissor. */
    Renderer::FlushBarrier();

    C3D_StencilTest(enabled, *compareOp, value, 0xFFFFFFFF, 0xFFFFFFFF);
""",
        ),
        (
            """    if (this->context.cullMode == mode)
        return;

    C3D_CullFace(*cullMode);
""",
            """    if (this->context.cullMode == mode)
        return;

    /* Balatro3DS: barrier -- see SetScissor. */
    Renderer::FlushBarrier();

    C3D_CullFace(*cullMode);
""",
        ),
        (
            """    if (this->context.colorMask == mask)
        return;

    this->context.colorMask = mask;
    C3D_DepthTest(true, GPU_GEQUAL, (GPU_WRITEMASK)writeMask);
""",
            """    if (this->context.colorMask == mask)
        return;

    /* Balatro3DS: barrier -- see SetScissor. */
    Renderer::FlushBarrier();

    this->context.colorMask = mask;
    C3D_DepthTest(true, GPU_GEQUAL, (GPU_WRITEMASK)writeMask);
""",
        ),
        (
            """    if (this->context.blendState == state)
        return;

    this->context.blendState = state;
    C3D_AlphaBlend(*opRGB, *opAlpha, *srcColor, *dstColor, *srcAlpha, *dstAlpha);
""",
            """    if (this->context.blendState == state)
        return;

    /* Balatro3DS: barrier -- see SetScissor. This is the one that mattered most: a queue that
       spanned a setBlendMode drew its earlier commands with the later blend function. */
    Renderer::FlushBarrier();

    this->context.blendState = state;
    C3D_AlphaBlend(*opRGB, *opAlpha, *srcColor, *dstColor, *srcAlpha, *dstAlpha);
""",
        ),
        (
            """void Renderer<Console::CTR>::SetViewport(const Rect& rect, bool tilt)
{
    if (this->viewport == rect)
        return;

    this->viewport = rect;
""",
            """void Renderer<Console::CTR>::SetViewport(const Rect& rect, bool tilt)
{
    if (this->viewport == rect)
        return;

    /* Balatro3DS: barrier -- see SetScissor. BindFramebuffer already flushes before it gets
       here, so in practice this only catches a viewport change that arrives on its own. */
    Renderer::FlushBarrier();

    this->viewport = rect;
""",
        ),
    ],
}


RENDERER_BARRIER_HELPER_PATCHES = {
    "marker": "Balatro3DS: flush because a piece of GPU state is about to change",
    "replacements": [
        (
            """        static void AfterForeignDraw();
""",
            """        static void AfterForeignDraw();

        /* Balatro3DS: flush because a piece of GPU state is about to change.

           citro3d applies blend, scissor, cull, colour-mask, stencil and viewport changes
           inside the NEXT draw submission, not at the call. Anything already queued has to be
           submitted first or it renders under state it was never issued under. Counted
           separately from ordinary flushes so a report can say what is breaking up the runs. */
        static void FlushBarrier()
        {
            if (!m_commands.empty())
                ++counters.stateBarriers;

            FlushVertices();
        }
""",
        ),
    ],
}


# --------------------------------------------------------------------------- tiny commands
# Phase 2. With the flush coalescing, what is left on the per-draw path is construction cost,
# and most of it is malloc. A four-vertex textured quad used to reach newlib's allocator three
# times -- a 144-byte vertex array, and a one-element std::vector for its texture handle, and
# for primitives a 32-byte position array as well -- and free all of them a frame later. At the
# ~120 draws a frame this port issues that is several hundred malloc/free pairs a frame doing
# nothing but carrying four vertices across a queue.
#
# Small-buffer optimisation rather than a frame arena: the arena is the better endpoint (the
# command becomes offsets into the vertex buffer and the staging memcpy disappears entirely)
# but it changes the ownership model for every backend and every call site, and the allocation
# is the part that is actually expensive. This keeps the existing API -- `command.vertices[i]`,
# `command.Vertices().get()`, `std::move(command)` -- exactly as it was.
#
# The handle list is the same argument. On 3DS every command carries zero or one texture, so
# the vector is replaced with a one-slot inline list; the other consoles keep the vector,
# because cafe compares whole lists and hac binds several at once.

DRAWCOMMAND_SSO_PATCHES = {
    "marker": "Balatro3DS: inline storage for the small commands",
    "replacements": [
        (
            """#include <utilities/driver/renderer/vertex.hpp>

#include <memory>
""",
            """#include <utilities/driver/renderer/vertex.hpp>

#include <initializer_list>
#include <memory>
#include <vector>
""",
        ),
        (
            """#if defined(__3DS__)
    using Handle = C3D_Tex;
#else
    using Handle = Texture<Console::Which>;
#endif
    struct DrawCommand
    {
      public:
        DrawCommand()
        {}

        DrawCommand(size_t count, PrimitiveType type = PRIMITIVE_TRIANGLES,
                    Shader<>::StandardShader shader = Shader<>::STANDARD_DEFAULT) :
            positions {},
            count(count),
            size(count * VERTEX_SIZE),
            format(CommonFormat::PRIMITIVE),
            type(type),
            shader(shader)
        {
            if (count == 0)
                throw love::Exception("Vertex count cannot be zero.");

            try
            {
                this->positions = std::make_unique<Vector2[]>(count);
                this->vertices  = std::make_unique<Vertex[]>(count);
            }
            catch (std::bad_alloc&)
            {
                throw love::Exception("Out of memory.");
            }
        }

        DrawCommand(size_t count, Shader<>::StandardShader shader, CommonFormat format) :
            count(count),
            size(count * VERTEX_SIZE),
            format(format),
            shader(shader)
        {
            if (count == 0)
                throw love::Exception("Vertex count cannot be zero.");

            try
            {
                this->vertices = std::make_unique<Vertex[]>(count);
            }
            catch (std::bad_alloc&)
            {
                throw love::Exception("Out of memory.");
            }
        }

        DrawCommand Clone()
        {
            /* init count, size, shader, and type */
            DrawCommand clone(this->count, this->type, this->shader);
            clone.format  = this->format;
            clone.handles = this->handles;

            if (this->positions)
                std::copy_n(this->Positions().get(), this->count, clone.Positions().get());

            std::copy_n(this->Vertices().get(), this->count, clone.Vertices().get());

            return clone;
        }

        const std::unique_ptr<Vector2[]>& Positions() const
        {
            return this->positions;
        }

        const std::span<Vector2> GetPositions() const
        {
            return std::span<Vector2>(this->positions.get(), this->count);
        }

        const std::unique_ptr<Vertex[]>& Vertices() const
        {
            return this->vertices;
        }

        const std::span<Vertex> GetVertices() const
        {
            return std::span<Vertex>(this->vertices.get(), this->count);
        }
""",
            """#if defined(__3DS__)
    using Handle = C3D_Tex;
#else
    using Handle = Texture<Console::Which>;
#endif

#if defined(__3DS__)
    /* Balatro3DS: the texture handle list, without the allocation.

       Every DrawCommand this backend builds carries exactly zero or one handle -- texture_ext,
       font, textbatch, spritebatch and mesh all assign a one-element list -- and a std::vector
       holding one pointer is a malloc and a free on the hottest path in the frame. Other
       consoles keep the vector: the cafe renderer compares whole lists for equality and the hac
       one binds several units at once. */
    struct HandleList
    {
        static constexpr size_t CAPACITY = 1;

        HandleList& operator=(std::initializer_list<Handle*> list)
        {
            this->used = 0;

            for (auto* handle : list)
            {
                if (this->used < CAPACITY)
                    this->items[this->used++] = handle;
            }

            return *this;
        }

        bool empty() const
        {
            return this->used == 0;
        }

        size_t size() const
        {
            return this->used;
        }

        Handle* back() const
        {
            return this->items[this->used - 1];
        }

        Handle* operator[](size_t index) const
        {
            return this->items[index];
        }

        Handle* items[CAPACITY] { nullptr };
        size_t used = 0;
    };
#else
    using HandleList = std::vector<Handle*>;
#endif

    /* Balatro3DS: a pointer that still answers to the old unique_ptr-shaped API.

       Call sites do `command.vertices[i]`, `command.vertices.get()` and
       `command.Vertices().get()`, and one does `if (this->positions)`. Keeping all four
       working is what lets the storage underneath change without touching every backend. */
    template<typename T>
    struct DrawStorage
    {
        T* pointer = nullptr;

        T* get() const
        {
            return this->pointer;
        }

        T& operator[](size_t index) const
        {
            return this->pointer[index];
        }

        explicit operator bool() const
        {
            return this->pointer != nullptr;
        }
    };

    struct DrawCommand
    {
      public:
        /* Balatro3DS: inline storage for the small commands, which are nearly all of them.

           Six covers a textured quad (4), a fill rectangle (4), one sprite (6) and one glyph
           (6). Bigger commands -- rounded rectangles, whole text runs, SpriteBatches, meshes --
           still take the heap, and should: they are a handful per frame, and the allocation is
           noise against the vertex work they carry. Raising the inline size to cover them would
           cost more in moving the command through the queue than it saves in mallocs. */
        static constexpr size_t INLINE_VERTICES = 6;

        DrawCommand()
        {}

        DrawCommand(size_t count, PrimitiveType type = PRIMITIVE_TRIANGLES,
                    Shader<>::StandardShader shader = Shader<>::STANDARD_DEFAULT) :
            count(count),
            size(count * VERTEX_SIZE),
            format(CommonFormat::PRIMITIVE),
            type(type),
            shader(shader)
        {
            if (count == 0)
                throw love::Exception("Vertex count cannot be zero.");

            this->Allocate(true);
        }

        DrawCommand(size_t count, Shader<>::StandardShader shader, CommonFormat format) :
            count(count),
            size(count * VERTEX_SIZE),
            format(format),
            shader(shader)
        {
            if (count == 0)
                throw love::Exception("Vertex count cannot be zero.");

            this->Allocate(false);
        }

        /* The inline arrays make the compiler-generated move wrong -- it would copy the bytes
           and leave both commands' pointers aimed at the source's storage -- so both moves and
           both copies are written out. Only `count` vertices are carried, not the whole inline
           array, which is what keeps a four-vertex quad's move at 144 bytes. */
        DrawCommand(DrawCommand&& other) noexcept
        {
            this->Adopt(std::move(other));
        }

        DrawCommand& operator=(DrawCommand&& other) noexcept
        {
            if (this != &other)
                this->Adopt(std::move(other));

            return *this;
        }

        DrawCommand(const DrawCommand& other)
        {
            this->Duplicate(other);
        }

        DrawCommand& operator=(const DrawCommand& other)
        {
            if (this != &other)
                this->Duplicate(other);

            return *this;
        }

        DrawCommand Clone()
        {
            return DrawCommand(*this);
        }

        DrawStorage<Vector2> Positions() const
        {
            return this->positions;
        }

        const std::span<Vector2> GetPositions() const
        {
            return std::span<Vector2>(this->positions.get(), this->count);
        }

        DrawStorage<Vertex> Vertices() const
        {
            return this->vertices;
        }

        const std::span<Vertex> GetVertices() const
        {
            return std::span<Vertex>(this->vertices.get(), this->count);
        }
""",
        ),
        (
            """      public:
        std::unique_ptr<Vector2[]> positions;
        std::unique_ptr<Vertex[]> vertices;

        size_t count;
        size_t size;

        CommonFormat format;
        PrimitiveType type;
        Shader<>::StandardShader shader;
        std::vector<Handle*> handles;
        CullMode cullMode;
    }; // namespace love
""",
            """      private:
        /* Point the public handles at whichever storage this command ended up using. */
        void Allocate(bool withPositions)
        {
            /* Cleared unconditionally: a command being copy-assigned over may already have a
               positions pointer, and the storage behind it was just released. Leaving it set
               would dangle for exactly as long as it took someone to draw a textured quad
               through a command that used to be a primitive. */
            this->positions.pointer = nullptr;

            if (this->count <= INLINE_VERTICES)
            {
                this->vertices.pointer  = this->inlineVertices();
                if (withPositions)
                    this->positions.pointer = this->inlinePositions();
                return;
            }

            try
            {
                this->heapVertices     = std::make_unique<Vertex[]>(this->count);
                this->vertices.pointer = this->heapVertices.get();

                if (withPositions)
                {
                    this->heapPositions     = std::make_unique<Vector2[]>(this->count);
                    this->positions.pointer = this->heapPositions.get();
                }
            }
            catch (std::bad_alloc&)
            {
                throw love::Exception("Out of memory.");
            }

            ++drawCommandHeapAllocs;
        }

        void CopyScalars(const DrawCommand& other)
        {
            this->count    = other.count;
            this->size     = other.size;
            this->format   = other.format;
            this->type     = other.type;
            this->shader   = other.shader;
            this->cullMode = other.cullMode;
        }

        void Adopt(DrawCommand&& other) noexcept
        {
            /* Move ASSIGNMENT can land on a command that already owns heap storage, and the
               inline branches below never touch the unique_ptrs -- so without this the old
               allocation would stay held while the pointers moved off it. */
            this->heapVertices.reset();
            this->heapPositions.reset();

            this->CopyScalars(other);
            this->handles = std::move(other.handles);

            if (other.heapVertices)
            {
                this->heapVertices     = std::move(other.heapVertices);
                this->vertices.pointer = this->heapVertices.get();
            }
            else if (other.vertices.pointer != nullptr)
            {
                std::copy_n(other.vertices.pointer, this->count, this->inlineVertices());
                this->vertices.pointer = this->inlineVertices();
            }
            else
                this->vertices.pointer = nullptr;

            if (other.heapPositions)
            {
                this->heapPositions     = std::move(other.heapPositions);
                this->positions.pointer = this->heapPositions.get();
            }
            else if (other.positions.pointer != nullptr)
            {
                std::copy_n(other.positions.pointer, this->count, this->inlinePositions());
                this->positions.pointer = this->inlinePositions();
            }
            else
                this->positions.pointer = nullptr;

            other.vertices.pointer  = nullptr;
            other.positions.pointer = nullptr;
            other.count             = 0;
            other.size              = 0;
        }

        void Duplicate(const DrawCommand& other)
        {
            this->heapVertices.reset();
            this->heapPositions.reset();

            this->CopyScalars(other);
            this->handles = other.handles;

            if (this->count == 0)
            {
                this->vertices.pointer  = nullptr;
                this->positions.pointer = nullptr;
                return;
            }

            this->Allocate(other.positions.pointer != nullptr);

            if (other.vertices.pointer != nullptr)
                std::copy_n(other.vertices.pointer, this->count, this->vertices.pointer);

            if (other.positions.pointer != nullptr && this->positions.pointer != nullptr)
                std::copy_n(other.positions.pointer, this->count, this->positions.pointer);
        }

      public:
        DrawStorage<Vector2> positions {};
        DrawStorage<Vertex> vertices {};

        size_t count = 0;
        size_t size  = 0;

        CommonFormat format = CommonFormat::NONE;
        PrimitiveType type  = PRIMITIVE_TRIANGLES;
        Shader<>::StandardShader shader = Shader<>::STANDARD_DEFAULT;
        HandleList handles {};
        CullMode cullMode = CULL_NONE;

      private:
        /* Raw floats rather than Vertex[] and Vector2[], and this is not a style choice.
           Vector2 and Vector3 both zero themselves in their default constructors, so an array
           of them is zeroed on every DrawCommand -- 30 float stores at construction, and 30
           more when the command is move-constructed into the queue. Every command paid that,
           including the ones too large to use inline storage at all, which is what made a
           16-vertex rounded rectangle measurably slower than before any of this existed
           (13.44 -> 14.96 us on a New 3DS).

           These are the same nine and two floats laid out the same way, with no constructor to
           run, cast at the point of use -- which is exactly what the renderer already does
           with the frame's vertex buffer, `(Vertex*)linearAlloc(...)`. Nothing reads an element
           before FillVertices or a transform has written it. */
        static_assert(sizeof(Vertex) == sizeof(float) * 9, "Vertex is nine floats");
        static_assert(sizeof(Vector2) == sizeof(float) * 2, "Vector2 is two floats");

        alignas(Vertex) float inlineVertexStorage[9 * INLINE_VERTICES];
        alignas(Vector2) float inlinePositionStorage[2 * INLINE_VERTICES];

        Vertex* inlineVertices()
        {
            return reinterpret_cast<Vertex*>(this->inlineVertexStorage);
        }

        Vector2* inlinePositions()
        {
            return reinterpret_cast<Vector2*>(this->inlinePositionStorage);
        }

        std::unique_ptr<Vertex[]> heapVertices;
        std::unique_ptr<Vector2[]> heapPositions;
    }; // namespace love
""",
        ),
    ],
}


# --------------------------------------------------------------------------- quad uvs
# Phase 3. Every textured draw rebuilt its Quad's texture coordinates from scratch: four
# positions, four texcoords through eight DOUBLE divisions, and then four more writes to flip
# them for the PICA's texture origin. None of it depends on anything that changes between
# frames -- this port's atlas quads are built once at load and drawn thousands of times -- and
# the ARM11's VFP is slow enough at doubles that this was a measurable slice of the 12.8 us an
# image_quad_draw costs.
#
# The cache cannot be keyed on the Quad alone. The final coordinates depend on the PHYSICAL
# dimensions of the texture being drawn (a 1000x600 atlas is padded to 1024x1024, and the
# divisor is the padded size) and on whether the target is a render target, whose orientation
# differs. The same Quad drawn against a different texture must recompute, so both are part of
# the key, and Quad::Refresh -- the one place the viewport can change, including through
# Quad:setViewport from Lua -- drops the cache.

QUAD_UV_CACHE_HPP_PATCHES = {
    "marker": "Balatro3DS: cached ctr texture coordinates",
    "replacements": [
        (
            """        void SetLayer(int layer);

        int GetLayer() const;

      private:
""",
            """        void SetLayer(int layer);

        int GetLayer() const;

        /* Balatro3DS: cached ctr texture coordinates.

           `vertexTextureCoords` holds the PICA-ready (v-flipped, physical-size) coordinates
           after the first draw, and they only stop being right if the viewport changes -- which
           goes through Refresh, which clears the flag -- or if the quad is drawn against a
           texture of a different physical size, or against a render target rather than a plain
           texture. All three are in the key. */
        bool CtrCoordsValid(float physicalWidth, float physicalHeight, bool renderTarget) const
        {
            return this->ctrCoordsReady && this->ctrPhysicalWidth == physicalWidth &&
                   this->ctrPhysicalHeight == physicalHeight &&
                   this->ctrRenderTarget == renderTarget;
        }

        void MarkCtrCoordsValid(float physicalWidth, float physicalHeight, bool renderTarget)
        {
            this->ctrCoordsReady     = true;
            this->ctrPhysicalWidth   = physicalWidth;
            this->ctrPhysicalHeight  = physicalHeight;
            this->ctrRenderTarget    = renderTarget;
        }

      private:
        bool ctrCoordsReady       = false;
        bool ctrRenderTarget      = false;
        float ctrPhysicalWidth    = -1.0f;
        float ctrPhysicalHeight   = -1.0f;

""",
        ),
    ],
}


QUAD_UV_CACHE_CPP_PATCHES = {
    "marker": "Balatro3DS: any change to the viewport invalidates",
    "replacements": [
        (
            """void Quad::Refresh(const Viewport& viewport, double sourceWidth, double sourceHeight)
{
    this->viewport     = viewport;
""",
            """void Quad::Refresh(const Viewport& viewport, double sourceWidth, double sourceHeight)
{
    /* Balatro3DS: any change to the viewport invalidates the ctr coordinate cache. This is the
       only door into vertexTextureCoords other than the flip in texture_ext, so clearing it
       here covers the constructor, Quad:setViewport from Lua, and a redraw against a texture of
       a different physical size. */
    this->ctrCoordsReady = false;

    this->viewport     = viewport;
""",
        ),
    ],
}


TEXTURE_QUAD_CACHE_PATCHES = {
    "marker": "Balatro3DS: skip the whole refresh when the coordinates are already right",
    "replacements": [
        (
            """static void refreshQuad(StrongReference<Quad> quad, const Quad::Viewport& viewport,
                        const Vector2& virtualDim, const Vector2& physicalDim, bool isRenderTarget)
{
    quad->Refresh(viewport, physicalDim.x, physicalDim.y);
    const auto* texCoords = quad->GetVertexTextureCoords();

    if (isRenderTarget)
    {
        auto coord = getVertex(0, 0, virtualDim, physicalDim);
        quad->SetVertexTextureCoord(0, coord);

        coord = getVertex(0, virtualDim.y, virtualDim, physicalDim);
        quad->SetVertexTextureCoord(1, coord);

        coord = getVertex(virtualDim.x, virtualDim.y, virtualDim, physicalDim);
        quad->SetVertexTextureCoord(2, coord);

        coord = getVertex(virtualDim.x, 0.0f, virtualDim, physicalDim);
        quad->SetVertexTextureCoord(3, coord);

        return;
    }

    quad->SetVertexTextureCoord(0, Vector2(texCoords[0].x, 1.0f - texCoords[0].y));
    quad->SetVertexTextureCoord(1, Vector2(texCoords[1].x, 1.0f - texCoords[1].y));
    quad->SetVertexTextureCoord(2, Vector2(texCoords[2].x, 1.0f - texCoords[2].y));
    quad->SetVertexTextureCoord(3, Vector2(texCoords[3].x, 1.0f - texCoords[3].y));
}
""",
            """/* Balatro3DS: skip the whole refresh when the coordinates are already right.

   The quad is taken as a raw pointer rather than a StrongReference by value: the caller
   already owns a reference for the duration of the draw, and taking one by value was a retain
   and a release on every textured draw in the frame. */
static void refreshQuad(Quad* quad, const Quad::Viewport& viewport, const Vector2& virtualDim,
                        const Vector2& physicalDim, bool isRenderTarget)
{
    if (quad->CtrCoordsValid(physicalDim.x, physicalDim.y, isRenderTarget))
        return;

    quad->Refresh(viewport, physicalDim.x, physicalDim.y);
    const auto* texCoords = quad->GetVertexTextureCoords();

    if (isRenderTarget)
    {
        auto coord = getVertex(0, 0, virtualDim, physicalDim);
        quad->SetVertexTextureCoord(0, coord);

        coord = getVertex(0, virtualDim.y, virtualDim, physicalDim);
        quad->SetVertexTextureCoord(1, coord);

        coord = getVertex(virtualDim.x, virtualDim.y, virtualDim, physicalDim);
        quad->SetVertexTextureCoord(2, coord);

        coord = getVertex(virtualDim.x, 0.0f, virtualDim, physicalDim);
        quad->SetVertexTextureCoord(3, coord);

        quad->MarkCtrCoordsValid(physicalDim.x, physicalDim.y, isRenderTarget);
        return;
    }

    quad->SetVertexTextureCoord(0, Vector2(texCoords[0].x, 1.0f - texCoords[0].y));
    quad->SetVertexTextureCoord(1, Vector2(texCoords[1].x, 1.0f - texCoords[1].y));
    quad->SetVertexTextureCoord(2, Vector2(texCoords[2].x, 1.0f - texCoords[2].y));
    quad->SetVertexTextureCoord(3, Vector2(texCoords[3].x, 1.0f - texCoords[3].y));

    quad->MarkCtrCoordsValid(physicalDim.x, physicalDim.y, isRenderTarget);
}
""",
        ),
    ],
}


# --------------------------------------------------------------------------- backdrop worker
# Phase 7. The backdrop field is ~200 float ops per vertex over a 1813-vertex grid, and it is
# the largest single piece of pure arithmetic in the frame: 980 us of main-thread CPU on a New
# 3DS even after the banding spreads it across eight frames.
#
# It is also the piece that has no reason to be on the main thread at all. It touches no C3D
# state, submits nothing, and writes only into a buffer the GPU is not reading. And the
# benchmark says a permanently busy worker costs the Lua thread nothing measurable --
# lua_arith_1k was 308.147 us alone and 308.140 us next to a spinner.
#
# So on a New 3DS the whole sweep goes to core 2, the additional application core every title
# running in New3DS mode is given. Not core 1: that is the system core, it needs an APT CPU
# time grant, and it takes the time from the OS. Not on an Old 3DS: core 2 does not exist, and
# the backdrop is already gated off there because the field costs about 11 ms at 268 MHz.
#
# The ownership rule is simple and absolute. The worker computes floats into the buffer that is
# NOT bound; the main thread owns every C3D call, the promotion of a finished buffer, and the
# draw. If the worker is late the last complete field is drawn again -- the game never waits.

BACKDROP_WORKER_PATCHES = {
    "marker": "Balatro3DS: the band index is an argument",
    "replacements": [
        (
            """    void UpdateField(Grid& grid, float* vbo, int mode, float sp, float A, float B, float K)
    {
        /* One band per call, into whichever buffer the caller says -- the back buffer during
           a sweep, the front one when priming. The banding is purely a way to spread the work
           across frames; nothing partial is ever shown. */
        const int rows = GRID_H + 1;
        const int first = (rows * grid.band) / FIELD_BANDS;
        const int last  = (rows * (grid.band + 1)) / FIELD_BANDS;
        grid.band = (grid.band + 1) % FIELD_BANDS;
""",
            """    void UpdateField(Grid& grid, float* vbo, int mode, float sp, float A, float B, float K,
                     int band)
    {
        /* One band per call, into whichever buffer the caller says -- the back buffer during
           a sweep, the front one when priming. The banding is purely a way to spread the work
           across frames; nothing partial is ever shown.

           Balatro3DS: the band index is an argument rather than state on the grid. The New3DS
           worker runs a whole sweep on another core while the main thread may be re-priming
           the other buffer of the same grid, and a counter shared between the two would be a
           race that buys nothing. */
        const int rows = GRID_H + 1;
        const int first = (rows * band) / FIELD_BANDS;
        const int last  = (rows * (band + 1)) / FIELD_BANDS;
""",
        ),
        (
            """    /* Grids are built the first time a mode and screen are actually asked for. Four exist --
       two shaders by two screen widths -- and a session that never leaves the menu should not
       pay for the two it will never draw. */
""",
            """    /* ------------------------------------------------------------ Balatro3DS: the field, on
       the New3DS spare core.

       What the worker may touch: the float array it was handed, and the read-only angle and
       radius tables of the grid it was handed. That is all. It makes no C3D call, changes no
       render state, and submits nothing.

       What the main thread keeps: every C3D call, the decision to promote a finished buffer,
       and the draw. It never blocks on the worker -- a late job simply means the last complete
       field is drawn for another frame, which against smoke moving at 0.3 rad/s is invisible.

       The buffer the worker writes is the one the GPU is not reading. `front` only changes on
       the main thread, at the moment a job is found to have finished, and the next job is
       posted against the newly retired buffer -- by which point C3D_FrameBegin's SYNCDRAW has
       already waited out the frame that was reading it. */
    struct FieldWorker
    {
        Thread thread = nullptr;
        LightEvent wake {};

        volatile bool busy = false;   /* a job is outstanding; worker writes, main reads */
        volatile bool quit = false;

        bool started   = false;
        bool attempted = false;
        /* Balatro3DS: on, having had a clean run on a New 3DS. perf_flags.txt can still turn
           it off; the synchronous banded path is what runs then, and on every Old 3DS. */
        bool enabled   = true;
        const char* reason = "not started";

        /* The job. Written by the main thread only while `busy` is false. */
        Grid* grid   = nullptr;
        float* vbo   = nullptr;
        size_t bytes = 0;
        int mode     = 0;
        float sp = 0.0f, A = 0.0f, B = 0.0f, K = 0.0f;

        /* Whose back buffer the outstanding job is filling, so the main thread knows what to
           promote when it finishes. Main thread only. */
        Grid* pending = nullptr;
    };

    FieldWorker g_worker;

    void FieldWorkerMain(void*)
    {
        while (true)
        {
            LightEvent_Wait(&g_worker.wake);

            if (g_worker.quit)
                break;

            Grid* grid = g_worker.grid;

            if (grid != nullptr && g_worker.vbo != nullptr)
            {
                for (int band = 0; band < FIELD_BANDS; band++)
                {
                    UpdateField(*grid, g_worker.vbo, g_worker.mode, g_worker.sp, g_worker.A,
                                g_worker.B, g_worker.K, band);
                }

                /* The core that wrote the data writes it back. C3D_FrameEnd flushes the
                   whole linear heap, but it does that from the main thread's core, and ARM11
                   cache maintenance is not broadcast between cores -- that arrived with ARMv7.
                   So a flush issued on core 0 cannot be assumed to reach lines still dirty in
                   core 2's L1.

                   svcFlushProcessDataCache and NOT GSPGPU_FlushDataCache. They sound
                   interchangeable and are not: the GSPGPU one is an IPC round trip on the
                   gsp::Gpu session handle that the main thread is using continuously for its
                   own GX submissions, whereas this is a plain supervisor call with no session
                   behind it at all. Syscall 84 is in the exheader's granted list
                   (dev/cia/balatro.rsf), so it is available to this title. */
                svcFlushProcessDataCache(CUR_PROCESS_HANDLE, (u32)g_worker.vbo,
                                         (u32)g_worker.bytes);
            }

            __dmb();
            g_worker.busy = false;
        }
    }

    bool StartFieldWorker()
    {
        if (g_worker.attempted)
            return g_worker.started && g_worker.enabled;

        g_worker.attempted = true;

        if (!g_worker.enabled)
        {
            g_worker.reason = "disabled";
            return false;
        }

        bool isNew3DS = false;
        APT_CheckNew3DS(&isNew3DS);

        if (!isNew3DS)
        {
            /* Core 2 does not exist on an Old 3DS, and core 1 is the system core -- putting
               the field there would need an APT CPU time grant and would take the time from
               the OS. The Old 3DS falls back to the synchronous banded path below, which is
               what it has always run. */
            g_worker.reason = "old 3ds: synchronous";
            return false;
        }

        LightEvent_Init(&g_worker.wake, RESET_ONESHOT);

        s32 priority = 0x30;
        svcGetThreadPriority(&priority, CUR_THREAD_HANDLE);

        /* Core 2 is the additional application core a New3DS gives every title running in
           New3DS mode. It needs no APT_SetAppCpuTimeLimit and takes nothing from the system,
           which is why it is preferred over the core-1 route. 16 KB of stack is far more than
           a loop over a float array can use. */
        g_worker.thread = threadCreate(FieldWorkerMain, nullptr, 16 * 1024, priority, 2, false);

        if (g_worker.thread == nullptr)
        {
            g_worker.reason = "thread creation failed: synchronous";
            return false;
        }

        g_worker.started = true;
        g_worker.reason  = "core 2";
        return true;
    }

    void PostFieldJob(Grid& grid, float* vbo, int mode, float sp, float A, float B, float K)
    {
        g_worker.grid  = &grid;
        g_worker.vbo   = vbo;
        g_worker.bytes = sizeof(float) * FLOATS_PER_VERT * VERTS;
        g_worker.mode  = mode;
        g_worker.sp    = sp;
        g_worker.A     = A;
        g_worker.B     = B;
        g_worker.K     = K;

        g_worker.pending = &grid;

        __dmb();
        g_worker.busy = true;
        LightEvent_Signal(&g_worker.wake);
    }

    /* Block until nothing is outstanding. Only ever called from the debug toggle, never from a
       frame: the whole design is that the game does not wait for this. */
    void FieldWorkerDrain()
    {
        while (g_worker.busy)
            svcSleepThread(1000000); /* 1 ms */

        __dmb();
        g_worker.pending = nullptr;
    }

    const char* FieldWorkerStatus()
    {
        if (!g_worker.attempted)
            return "not started";

        return g_worker.enabled ? g_worker.reason : "disabled";
    }

    /* Joined at exit, so a worker never outlives the process whose memory it is writing. */
    struct FieldWorkerShutdown
    {
        ~FieldWorkerShutdown()
        {
            if (!g_worker.started)
                return;

            g_worker.quit = true;
            __dmb();
            LightEvent_Signal(&g_worker.wake);

            threadJoin(g_worker.thread, U64_MAX);
            threadFree(g_worker.thread);

            g_worker.started = false;
        }
    };

    FieldWorkerShutdown g_workerShutdown;

    /* Grids are built the first time a mode and screen are actually asked for. Four exist --
       two shaders by two screen widths -- and a session that never leaves the menu should not
       pay for the two it will never draw. */
""",
        ),
        (
            """    if (grid.primed && std::fabs(time - grid.lastTime) > 0.5f)
        grid.primed = false;
    grid.lastTime = time;

    if (!grid.primed)
    {
        /* Fill the FRONT buffer whole so the first shown frame is coherent -- otherwise the
           screen renders from the flat 0.5 the buffer was built with. The back buffer starts
           its first sweep, with fresh parameters, on the next call. */
        grid.sp = sp; grid.A = A; grid.B = B; grid.K = K;
        grid.band = 0;
        for (int i = 0; i < FIELD_BANDS; i++)
            UpdateField(grid, grid.vbo[grid.front], mode, sp, A, B, K);
        grid.primed = true;
    }
    else
    {
        /* One band of the back buffer per frame, under parameters frozen when its sweep
           started; the flip below is the only moment the drawn field ever changes, so no
           fresh/stale seam can exist on screen. */
        if (grid.band == 0)
        {
            grid.sp = sp; grid.A = A; grid.B = B; grid.K = K;
        }
        UpdateField(grid, grid.vbo[grid.front ^ 1], mode, grid.sp, grid.A, grid.B, grid.K);
        if (grid.band == 0)   /* wrapped: the sweep is complete and the buffer coherent */
            grid.front ^= 1;
    }
""",
            """    if (grid.primed && std::fabs(time - grid.lastTime) > 0.5f)
    {
        /* Balatro3DS: re-priming rewrites the FRONT buffer with fresh parameters, which makes
           any job still filling the back one stale by definition. Its promotion is dropped --
           it finishes into a buffer nobody will look at, and the next post starts a clean
           sweep. The two writes cannot collide: they are different buffers, and the band
           counter is no longer shared. */
        if (g_worker.pending == &grid)
            g_worker.pending = nullptr;

        grid.primed = false;
    }
    grid.lastTime = time;

    if (!grid.primed)
    {
        /* Fill the FRONT buffer whole so the first shown frame is coherent -- otherwise the
           screen renders from the flat 0.5 the buffer was built with. The back buffer starts
           its first sweep, with fresh parameters, on the next call. */
        grid.sp = sp; grid.A = A; grid.B = B; grid.K = K;
        grid.band = 0;
        for (int i = 0; i < FIELD_BANDS; i++)
            UpdateField(grid, grid.vbo[grid.front], mode, sp, A, B, K, i);
        grid.primed = true;
    }
    else if (StartFieldWorker())
    {
        /* Balatro3DS: the whole sweep runs on core 2, and the main thread's part of it is this
           -- one non-blocking test, one buffer promotion and one post. Roughly nothing.

           A job that has not finished is simply not waited for: the field advances in whole
           steps at 60/FIELD_BANDS fps when the worker keeps up, and a little slower when it
           does not, and against smoke moving at 0.3 rad/s neither is visible. What must never
           happen is the game stalling on it. */
        grid.wants = true;

        if (!g_worker.busy)
        {
            __dmb(); /* the worker's writes are visible before anything is promoted */

            if (g_worker.pending != nullptr)
            {
                /* Whichever grid the finished job filled -- not necessarily this one, if the
                   backdrop changed mode while it ran. That buffer is complete either way. */
                g_worker.pending->front ^= 1;
                g_worker.pending = nullptr;
            }

            /* Serve the grid that has waited longest, which is not necessarily this one.

               Both screens draw a backdrop every frame, out of two different grids -- 400 wide
               on top, 320 on the bottom -- and one worker serves both. "Whoever finds the
               worker idle posts for itself" hands every job to whichever screen happens to
               draw first, and the other grid never gets a sweep after its initial prime: it
               keeps drawing one frozen field for the rest of the session. That is exactly what
               a New 3DS showed -- a swirling top screen over a still bottom one.

               The field parameters are shared, so posting for the other screen's grid with
               this frame's sp/A/B/K is correct: only `angle` and `radius` differ between the
               two, and those are per-vertex constants baked when the grid was built. */
            Grid* target = &grid;
            for (int side = 0; side < 2; side++)
            {
                Grid& other = g_bd.grids[mode][side];
                if (!other.built || !other.primed || !other.wants)
                    continue;
                if (other.lastPosted < target->lastPosted)
                    target = &other;
            }

            target->wants = false;
            target->lastPosted = ++g_bd.postCounter;
            target->sp = sp; target->A = A; target->B = B; target->K = K;
            PostFieldJob(*target, target->vbo[target->front ^ 1], mode, sp, A, B, K);
        }
    }
    else
    {
        /* One band of the back buffer per frame, under parameters frozen when its sweep
           started; the flip below is the only moment the drawn field ever changes, so no
           fresh/stale seam can exist on screen. */
        if (grid.band == 0)
        {
            grid.sp = sp; grid.A = A; grid.B = B; grid.K = K;
        }
        UpdateField(grid, grid.vbo[grid.front ^ 1], mode, grid.sp, grid.A, grid.B, grid.K,
                    grid.band);
        grid.band = (grid.band + 1) % FIELD_BANDS;
        if (grid.band == 0)   /* wrapped: the sweep is complete and the buffer coherent */
            grid.front ^= 1;
    }
""",
        ),
        (
            """    lua_pushinteger(L, (lua_Integer)svcGetSystemTick());
    lua_setfield(L, -2, "tick");
""",
            """    lua_pushstring(L, FieldWorkerStatus());
    lua_setfield(L, -2, "backdrop_worker");

    lua_pushinteger(L, (lua_Integer)svcGetSystemTick());
    lua_setfield(L, -2, "tick");
""",
        ),
        (
            """    { "setBatching",    Wrap_Graphics::SetBatching    }
};""",
            """    { "setBatching",    Wrap_Graphics::SetBatching    },
    { "setBackdropWorker", Wrap_Graphics::SetBackdropWorker }
};""",
        ),
        (
            """int Wrap_Graphics::GetRuntimeInfo(lua_State* L)
{""",
            """/* Balatro3DS: setBackdropWorker(enabled) -- A/B the New3DS field worker on the console.

   Turning it off drains any outstanding job first. The synchronous path writes the same back
   buffer the worker does, so handing the buffer over while a job is still in it would be the
   one race this design otherwise does not have. The drain is bounded by one sweep and only
   ever runs from this toggle, never from a frame. */
int Wrap_Graphics::SetBackdropWorker(lua_State* L)
{
    const bool enabled = luax::CheckBoolean(L, 1);

    if (!enabled && g_worker.started)
        FieldWorkerDrain();

    g_worker.enabled = enabled;

    /* Let a previously declined start be retried, so the toggle works in both directions. */
    if (enabled && !g_worker.started)
        g_worker.attempted = false;

    return 0;
}

int Wrap_Graphics::GetRuntimeInfo(lua_State* L)
{""",
        ),
    ],
}


WRAP_GRAPHICS_WORKER_HPP_PATCHES = {
    "marker": "Balatro3DS: setBackdropWorker",
    "replacements": [
        (
            """    /* Balatro3DS: setBatching -- runtime A/B switch for the coalescing flush. */
    int SetBatching(lua_State* L);
""",
            """    /* Balatro3DS: setBatching -- runtime A/B switch for the coalescing flush. */
    int SetBatching(lua_State* L);

    /* Balatro3DS: setBackdropWorker -- runtime A/B switch for the New3DS field worker. */
    int SetBackdropWorker(lua_State* L);
""",
        ),
    ],
}


def main() -> int:
    if not 2 <= len(sys.argv) <= 3:
        print(f"usage: {sys.argv[0]} <lovepotion-checkout> [romfs:/game]", file=sys.stderr)
        return 2

    checkout = Path(sys.argv[1])
    game_root = sys.argv[2] if len(sys.argv) == 3 else DEFAULT_GAME_ROOT
    if '"' in game_root:
        print("error: game root must not contain quotes", file=sys.stderr)
        return 2

    targets = [
        (checkout / MAIN_CPP, MAIN_PATCHES),
        (checkout / FS_CPP, FS_PATCHES),
        (checkout / AUDIO_CPP, AUDIO_PATCHES),
        (checkout / AUDIO_HPP, AUDIO_PITCH_HPP_PATCHES),
        (checkout / AUDIO_CPP, AUDIO_PITCH_CPP_PATCHES),
        (checkout / AUDIO_WRAP_CPP, AUDIO_PITCH_WRAP_PATCHES),
        (checkout / VORBIS_CPP, VORBIS_SEEK_PATCHES),
        (checkout / GRAPHICS_TCC, ROUND_RECT_PATCHES),
        (checkout / RENDERER_TCC, RENDERER_COUNTERS_TCC_PATCHES),
        (checkout / DRAWCOMMAND_TCC, DRAWCOMMAND_ALLOC_COUNTER_PATCHES),
        (checkout / DRAWCOMMAND_TCC, DRAWCOMMAND_SSO_PATCHES),
        (checkout / RENDERER_CPP, RENDERER_MOVE_PATCHES),
        (checkout / RENDERER_CPP, RENDERER_STATS_LATCH_PATCHES),
        (checkout / BATCH_INDICES_HPP, BATCH_INDICES_FILE),
        (checkout / RENDERER_CPP, RENDERER_BATCH_CPP_PATCHES),
        (checkout / WRAP_MESH_CPP, MESH_SETVERTICES_PATCHES),
        (checkout / SCREEN_EXT_CPP, SCREEN_LOOKUP_PATCHES),
        (checkout / QUAD_HPP, QUAD_UV_CACHE_HPP_PATCHES),
        (checkout / QUAD_CPP, QUAD_UV_CACHE_CPP_PATCHES),
        (checkout / TEXTURE_EXT_CPP, TEXTURE_QUAD_CACHE_PATCHES),
        (checkout / SPRITEBATCH_CPP, SPRITEBATCH_COLOR_PATCHES),
        (checkout / RENDERER_HPP, RENDERER_BACKDROP_HPP_PATCHES),
        (checkout / RENDERER_HPP, RENDERER_BARRIER_HELPER_PATCHES),
        (checkout / RENDERER_HPP, RENDERER_BATCH_HPP_PATCHES),
        (checkout / RENDERER_CPP, RENDERER_BACKDROP_CPP_PATCHES),
        (checkout / WRAP_GRAPHICS_HPP, WRAP_GRAPHICS_HPP_PATCHES),
        (checkout / WRAP_GRAPHICS_HPP, WRAP_GRAPHICS_STATS_HPP_PATCHES),
        (checkout / WRAP_GRAPHICS_EXT_CPP, BACKDROP_BINDING_PATCHES),
        (checkout / WRAP_GRAPHICS_HPP, WRAP_GRAPHICS_WORKER_HPP_PATCHES),
        (checkout / WRAP_GRAPHICS_EXT_CPP, WRAP_GRAPHICS_STATS_CPP_PATCHES),
        (checkout / WRAP_GRAPHICS_EXT_CPP, BACKDROP_WORKER_PATCHES),
    ]
    for path, spec in targets:
        if "contents" not in spec and not path.is_file():
            print(f"error: {path} not found; is this a lovepotion checkout?", file=sys.stderr)
            return 1

    for path, spec in targets:
        if "contents" in spec:
            if not write_file(path, spec):
                return 1
        elif not patch_file(path, spec):
            return 1

    # Prove every patch left its marker behind.
    #
    # The marker is what makes a re-run a no-op, and a marker that never matches its own output
    # is invisible until someone patches twice -- which nothing does, because setup.sh
    # hard-resets first. Two of these had been wrong for months: one differed from the inserted
    # text by a capital letter, and one was written across a line break so it could not match
    # anything. Checking here turns "not idempotent" into a first-run failure.
    for path, spec in targets:
        if "contents" in spec:
            continue
        if spec["marker"] not in path.read_text(newline=""):
            print(
                f"error: {path} does not contain this patch's marker after applying it.\n"
                f"The marker has to be a single-line string that appears in the patched file,\n"
                f"or re-running this script will try to apply the patch again and fail.\n"
                f"--- marker ---\n{spec['marker']}",
                file=sys.stderr,
            )
            return 1

    set_game_root(checkout / MAIN_CPP, game_root)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
