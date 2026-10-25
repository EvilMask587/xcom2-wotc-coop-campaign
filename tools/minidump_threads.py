"""Every thread of a Windows minidump: rip and the return-address candidates on its stack
(values inside loaded modules), mapped to module+offset.
Usage: minidump_threads.py <file.dmp> [max candidates per thread, default 14]"""
import struct, sys

def main(path, limit):
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
        return None
    size, rva = streams[6]                      # ExceptionStream
    crashed, = struct.unpack_from('<I', d, rva)
    size, rva = streams[3]                      # ThreadListStream
    n, = struct.unpack_from('<I', d, rva)
    for i in range(n):
        o = rva + 4 + 48 * i
        tid, = struct.unpack_from('<I', d, o)
        start, ssize, srva = struct.unpack_from('<QII', d, o + 24)
        csize, crva = struct.unpack_from('<II', d, o + 40)
        rip, = struct.unpack_from('<Q', d, crva + 0xF8)
        found = []
        for off in range(0, ssize - 7, 8):
            v, = struct.unpack_from('<Q', d, srva + off)
            w = where(v)
            if w and not w.startswith(('ntdll', 'KERNEL')):
                found.append(w)
            if len(found) >= limit:
                break
        mark = ' <-- crashed' if tid == crashed else ''
        print(f'thread {tid} rip {where(rip)}{mark}')
        print('   ' + ' '.join(found))

main(sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 14)
