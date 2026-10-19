"""Inspect devkitPro BCFNT output and normalize its FINF cell metrics."""
import struct
from pathlib import Path

def inspect(path):
    b=Path(path).read_bytes()
    assert b[:4]==b'CFNT' and struct.unpack_from('<H',b,4)[0]==0xfeff
    assert struct.unpack_from('<I',b,12)[0]==len(b), 'BCFNT length mismatch'
    finf=struct.unpack_from('<H',b,6)[0]
    assert b[finf:finf+4]==b'FINF'
    tglp,cwdh,cmap=struct.unpack_from('<III',b,finf+16)
    assert b[tglp-8:tglp-4]==b'TGLP'
    cell_w,cell_h,baseline,max_width=struct.unpack_from('<4B',b,tglp)
    sheet_bytes,sheets,fmt,columns,rows,width,height,offset=struct.unpack_from('<I6HI',b,tglp+4)
    assert fmt==11 and offset+sheet_bytes*sheets<=len(b)
    mappings={}; visited=set()
    while cmap:
        assert cmap not in visited, 'CMAP cycle'
        visited.add(cmap)
        assert b[cmap-8:cmap-4]==b'CMAP'
        lo,hi,method,_,next_map=struct.unpack_from('<4HI',b,cmap)
        p=cmap+12
        if method==0:
            base=struct.unpack_from('<H',b,p)[0]
            mappings.update((cp,base+cp-lo) for cp in range(lo,hi+1))
        elif method==1:
            for cp in range(lo,hi+1):
                index=struct.unpack_from('<H',b,p+2*(cp-lo))[0]
                if index!=65535: mappings[cp]=index
        elif method==2:
            count=struct.unpack_from('<H',b,p)[0]
            for i in range(count):
                cp,index=struct.unpack_from('<HH',b,p+2+i*4)
                mappings[cp]=index
        else: raise ValueError('Unknown CMAP method')
        cmap=next_map
    assert all(i<columns*rows*sheets for i in mappings.values())
    return dict(bytes=len(b),cell_width=cell_w,cell_height=cell_h,baseline=baseline,
        finf_height=b[finf+28],finf_ascent=b[finf+30],glyphs=len(mappings),
        sheets=sheets,sheet_bytes=sheet_bytes,texture_bytes=sheet_bytes*sheets,
        mappings=mappings,finf_offset=finf)

def normalize_metrics(path):
    info=inspect(path)
    b=bytearray(Path(path).read_bytes()); p=info['finf_offset']
    # mkbcfnt 2.3.0 writes font-unit bbox/64 as FINF height, while ascent is
    # in raster pixels. LÖVE Potion subtracts these as uint8, so height must
    # be in raster pixels too, or descent can wrap to a huge value.
    b[p+28]=info['cell_height']; b[p+30]=info['baseline']
    Path(path).write_bytes(b)
    return inspect(path)
