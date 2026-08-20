"""Minimal RGBA8 PNG reader/writer.

There is no Pillow in this environment and adding one would put a dependency between
the asset bake and a working `pip`, so the bake carries its own codec. It handles the
subset the game's art actually uses: 8-bit truecolour with or without alpha, plus the
five standard scanline filters. Anything else raises rather than guessing.
"""

import struct
import zlib


def read_rgba(path):
    """Return (width, height, bytearray of RGBA8 rows)."""
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("%s: not a PNG" % path)

    pos = 8
    header = None
    idat = bytearray()
    palette = None
    trns = None
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos : pos + 4])
        kind = data[pos + 4 : pos + 8]
        body = data[pos + 8 : pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat += body
        elif kind == b"PLTE":
            palette = body
        elif kind == b"tRNS":
            trns = body
        elif kind == b"IEND":
            break

    width, height, depth, colour, compression, filt, interlace = header
    if depth != 8 or interlace != 0 or compression != 0 or filt != 0:
        raise ValueError("%s: only 8-bit non-interlaced PNGs are supported" % path)

    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[colour]
    raw = zlib.decompress(bytes(idat))
    stride = width * channels

    out = bytearray(stride * height)
    prev = bytearray(stride)
    src = 0
    for y in range(height):
        ftype = raw[src]
        src += 1
        line = bytearray(raw[src : src + stride])
        src += stride
        if ftype == 1:
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 0xFF
        elif ftype == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif ftype == 3:
            for i in range(stride):
                left = line[i - channels] if i >= channels else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 0xFF
        elif ftype == 4:
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                b = prev[i]
                c = prev[i - channels] if i >= channels else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pred) & 0xFF
        elif ftype != 0:
            raise ValueError("%s: unknown filter %d" % (path, ftype))
        out[y * stride : (y + 1) * stride] = line
        prev = line

    rgba = bytearray(width * height * 4)
    for i in range(width * height):
        s, d = i * channels, i * 4
        if colour == 6:
            rgba[d : d + 4] = out[s : s + 4]
        elif colour == 2:
            rgba[d : d + 3] = out[s : s + 3]
            rgba[d + 3] = 255
        elif colour == 0:
            rgba[d] = rgba[d + 1] = rgba[d + 2] = out[s]
            rgba[d + 3] = 255
        elif colour == 4:
            rgba[d] = rgba[d + 1] = rgba[d + 2] = out[s]
            rgba[d + 3] = out[s + 1]
        elif colour == 3:
            idx = out[s]
            rgba[d : d + 3] = palette[idx * 3 : idx * 3 + 3]
            rgba[d + 3] = trns[idx] if trns and idx < len(trns) else 255
    return width, height, rgba


def write_rgba(path, width, height, rgba):
    """Write RGBA8. Filter 0 throughout; these sheets compress fine and tex3ds
    re-encodes anyway, so the extra passes are not worth the bake time."""
    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)
        raw += rgba[y * stride : (y + 1) * stride]

    def chunk(kind, body):
        return (
            struct.pack(">I", len(body))
            + kind
            + body
            + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)
        )

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    open(path, "wb").write(png)
