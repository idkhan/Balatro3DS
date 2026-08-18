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
    "marker": "Balatro3DS: backdrop",
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
       fraction of the grid rather than all of it. The warp's phase moves about 0.3 rad/s, so
       the oldest band in a four-band rotation is three frames -- about 0.015 rad -- behind
       the newest. The seams that produces sit on single rows and are not resolvable. This is
       what lets a grid this dense be carried at all: the first hardware measurement put the
       whole-grid-per-frame version at 14.8 ms on a New 3DS, which is 30 fps. */
    constexpr int FIELD_BANDS = 4;
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
        float* vbo    = nullptr;   /* interleaved, GPU-visible */
        float* angle  = nullptr;   /* atan2(uv.y, uv.x) per vertex, CPU only */
        float* radius = nullptr;   /* length(uv) per vertex, CPU only */
        C3D_BufInfo buf {};
        bool built = false;
        int band = 0;      /* which row band refreshes next */
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

        grid.vbo    = (float*)linearAlloc(sizeof(float) * FLOATS_PER_VERT * VERTS);
        grid.angle  = (float*)std::malloc(sizeof(float) * VERTS);
        grid.radius = (float*)std::malloc(sizeof(float) * VERTS);

        if (grid.vbo == nullptr || grid.angle == nullptr || grid.radius == nullptr)
            return false;

        float* v = grid.vbo;
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

        BufInfo_Init(&grid.buf);
        if (BufInfo_Add(&grid.buf, grid.vbo, sizeof(float) * FLOATS_PER_VERT, 3, 0x210) < 0)
            return false;

        grid.built = true;
        return true;
    }

    /* The field, per vertex, per frame -- what the vertex shader was going to do.

       This is splash.fs line for line: the radius-dependent swirl, five domain-warp iterations,
       and the smoke term with its soft knee below 0.2. Only the ramp coordinate is written
       back; positions never move. */
    void UpdateField(Grid& grid, int mode, float sp, float A, float B, float K)
    {
        /* One band per frame. Rows rather than scattered vertices deliberately: a spatially
           interleaved update would put neighbouring vertices one frame apart and shimmer,
           where a contiguous band confines the discontinuity to a single row. */
        const int rows = GRID_H + 1;
        const int first = (rows * grid.band) / FIELD_BANDS;
        const int last  = (rows * (grid.band + 1)) / FIELD_BANDS;
        grid.band = (grid.band + 1) % FIELD_BANDS;

        const int stride = GRID_W + 1;
        int i = first * stride;
        float* v = grid.vbo + TC_OFFSET + (size_t)i * FLOATS_PER_VERT;

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
                      "%d indices, ramp %dx%d, stock shader",
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

    if (!g_bd.rampReady)
    {
        g_bd.reason = "ramp texture init failed";
        luax::PushBoolean(L, false);
        lua_pushstring(L, g_bd.reason);
        return 2;
    }

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

    Grid* gridPtr = EnsureGrid(mode, width);
    if (gridPtr == nullptr)
    {
        luax::PushBoolean(L, false);
        lua_pushstring(L, g_bd.reason);
        return 2;
    }
    Grid& grid = *gridPtr;

    /* The banded refresh leaves the other bands holding whatever was there before, so the
       first frame on each grid has to fill all of them -- otherwise half the screen renders
       from the flat 0.5 the buffer was built with. */
    if (!grid.primed)
    {
        for (int i = 0; i < FIELD_BANDS; i++)
            UpdateField(grid, mode, sp, A, B, K);
        grid.primed = true;
    }
    else
    {
        UpdateField(grid, mode, sp, A, B, K);
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

    C3D_SetBufInfo(&grid.buf);
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
        (checkout / RENDERER_CPP, RENDERER_MOVE_PATCHES),
        (checkout / WRAP_MESH_CPP, MESH_SETVERTICES_PATCHES),
        (checkout / SCREEN_EXT_CPP, SCREEN_LOOKUP_PATCHES),
        (checkout / SPRITEBATCH_CPP, SPRITEBATCH_COLOR_PATCHES),
        (checkout / RENDERER_HPP, RENDERER_BACKDROP_HPP_PATCHES),
        (checkout / RENDERER_CPP, RENDERER_BACKDROP_CPP_PATCHES),
        (checkout / WRAP_GRAPHICS_HPP, WRAP_GRAPHICS_HPP_PATCHES),
        (checkout / WRAP_GRAPHICS_EXT_CPP, BACKDROP_BINDING_PATCHES),
    ]
    for path, _ in targets:
        if not path.is_file():
            print(f"error: {path} not found; is this a lovepotion checkout?", file=sys.stderr)
            return 1

    for path, spec in targets:
        if not patch_file(path, spec):
            return 1

    set_game_root(checkout / MAIN_CPP, game_root)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
