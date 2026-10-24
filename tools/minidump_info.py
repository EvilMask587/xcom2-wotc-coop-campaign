"""Exception code/address of a Windows minidump, mapped to module+offset.
Usage: minidump_info.py <file.dmp>. Also scans the crashing thread's stack for return
addresses inside loaded modules (heuristic: values that fall into a module's range)."""
import struct, sys

def main(path):
    d = open(path, 'rb').read()
    sig, ver, nstreams, dir_rva = struct.unpack_from('<4sIII', d, 0)
    assert sig == b'MDMP', sig
    streams = {}
    for i in range(nstreams):
        st, size, rva = struct.unpack_from('<III', d, dir_rva + 12 * i)
        streams[st] = (size, rva)
    mods = []
    size, rva = streams[4]                      # ModuleListStream
    n, = struct.unpack_from('<I', d, rva)
    for i in range(n):
        o = rva + 4 + 108 * i
        base, msize = struct.unpack_from('<QI', d, o)
        name_rva, = struct.unpack_from('<I', d, o + 20)
        ln, = struct.unpack_from('<I', d, name_rva)
        name = d[name_rva + 4:name_rva + 4 + ln].decode('utf-16le').split(chr(92))[-1]
        mods.append((base, base + msize, name))
    def where(a):
        for b, e, nm in mods:
            if b <= a < e:
                return f'{nm}+0x{a - b:x}'
        return '?'
    size, rva = streams[6]                      # ExceptionStream
    tid, = struct.unpack_from('<I', d, rva)
    code, flags, rec, addr, nparams = struct.unpack_from('<IIQQI', d, rva + 8)
    params = struct.unpack_from('<15Q', d, rva + 8 + 32)[:nparams]
    print(f'thread {tid} code 0x{code:08x} at 0x{addr:x} = {where(addr)}')
    print('params', [hex(p) for p in params])
    ctx_size, ctx_rva = struct.unpack_from('<II', d, rva + 8 + 152)
    rsp, = struct.unpack_from('<Q', d, ctx_rva + 0x98)
    rip, = struct.unpack_from('<Q', d, ctx_rva + 0xF8)
    print(f'rip {where(rip)} rsp 0x{rsp:x}')
    # stack memory of the crashing thread (MemoryListStream 5 or Memory64ListStream 9)
    mem = []
    if 5 in streams:
        size, rva = streams[5]
        n, = struct.unpack_from('<I', d, rva)
        for i in range(n):
            start, dsize, drva = struct.unpack_from('<QII', d, rva + 4 + 16 * i)
            mem.append((start, d[drva:drva + dsize]))
    if 9 in streams:
        size, rva = streams[9]
        n, base_rva = struct.unpack_from('<QQ', d, rva)
        off = base_rva
        for i in range(n):
            start, dsize = struct.unpack_from('<QQ', d, rva + 16 + 16 * i)
            mem.append((start, d[off:off + dsize])); off += dsize
    for start, blob in mem:
        if start <= rsp < start + len(blob):
            k = rsp - start
            print('stack candidates:')
            shown = 0
            while k + 8 <= len(blob) and shown < 25:
                v, = struct.unpack_from('<Q', blob, k)
                w = where(v)
                if w != '?' and not w.startswith('ntdll') or (w.startswith('ntdll') and shown < 3 and w != '?'):
                    print(f'  rsp+0x{k - (rsp - start):x}: {w}'); shown += 1
                k += 8
            break

main(sys.argv[1])
