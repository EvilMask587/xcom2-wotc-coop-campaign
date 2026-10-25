"""Read process memory captured in a full Windows minidump (MemoryListStream).
As a module: Dump(path).read(va, n) -> bytes or None. As a script:
mdmem.py <file.dmp> <hex va> [bytes]  prints a hex/ascii dump."""
import struct, sys, bisect

class Dump:
    def __init__(self, path):
        self.d = d = open(path, 'rb').read()
        sig, ver, n, rva = struct.unpack_from('<4sIII', d, 0)
        self.streams = {}
        for i in range(n):
            st, size, r = struct.unpack_from('<III', d, rva + 12 * i)
            self.streams[st] = (size, r)
        rs = []
        size, r = self.streams[5]
        cnt, = struct.unpack_from('<I', d, r)
        for i in range(cnt):
            s, ds, dr = struct.unpack_from('<QII', d, r + 4 + 16 * i)
            rs.append((s, ds, dr))
        rs.sort()
        self.ranges = rs
        self.starts = [x[0] for x in rs]

    def read(self, va, n):
        i = bisect.bisect_right(self.starts, va) - 1
        if i < 0:
            return None
        s, ds, dr = self.ranges[i]
        if va + n > s + ds:
            return None
        return self.d[dr + va - s: dr + va - s + n]

    def q(self, va):
        b = self.read(va, 8)
        return struct.unpack('<Q', b)[0] if b else None

if __name__ == '__main__':
    m = Dump(sys.argv[1])
    va = int(sys.argv[2], 16); n = int(sys.argv[3]) if len(sys.argv) > 3 else 128
    b = m.read(va, n)
    if b is None:
        print('not captured')
    else:
        for k in range(0, len(b), 16):
            row = b[k:k + 16]
            print(f'{va + k:016x}  {row.hex(" ")}  {"".join(chr(c) if 32 <= c < 127 else "." for c in row)}')
