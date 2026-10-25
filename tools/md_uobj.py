"""Resolve UE3 objects in a full XCOM 2 minidump (layout found by hand on this build):
GNames is an array of FNameEntry* (entry: 8 bytes flags, int Index<<1, 8 bytes HashNext,
then the ANSI chars); a UObject has its Outer at +0x40, Name (FName index, number) at +0x48
and Class at +0x50.
Usage: md_uobj.py <file.dmp> <hex GNames> scanstack <hex rsp> <bytes>
       md_uobj.py <file.dmp> <hex GNames> obj <hex address>"""
import sys, struct
sys.path.insert(0, __import__('os').path.dirname(__file__))
import mdmem

m = mdmem.Dump(sys.argv[1]); gnames = int(sys.argv[2], 16)

def name(idx):
    if idx < 0 or idx > 3000000:
        return None
    e = m.q(gnames + 8 * idx)
    if not e:
        return None
    b = m.read(e + 20, 96)
    if not b or b'\0' not in b:
        return None
    s = b[:b.index(b'\0')]
    return s.decode('ascii') if s and all(32 < c < 127 for c in s) else None

def objname(p):
    b = m.read(p + 0x40, 0x18)
    if not b:
        return None
    outer, ni, nn, cls = struct.unpack('<QiiQ', b)
    n = name(ni)
    if not n:
        return None
    return n + (f'_{nn - 1}' if nn > 0 else ''), outer, cls

def path(p, depth=0):
    r = objname(p)
    if not r or depth > 6:
        return None
    n, outer, cls = r
    if outer and depth < 6:
        o = path(outer, depth + 1)
        if o:
            return o + '.' + n
    return n

def classname(p):
    r = objname(p)
    return objname(r[2])[0] if r and r[2] and objname(r[2]) else None

if sys.argv[3] == 'obj':
    p = int(sys.argv[4], 16)
    print(path(p), 'class', classname(p))
else:
    rsp = int(sys.argv[4], 16); n = int(sys.argv[5])
    for off in range(0, n, 8):
        v = m.q(rsp + off)
        if not v or v < 0x10000:
            continue
        c = classname(v)
        if c in ('Function', 'State', 'Class') or (c and off < 0x400):
            print(f'rsp+0x{off:x}: {path(v)} [{c}]')
