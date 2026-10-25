"""Find where a function VA is referenced: as a 64-bit pointer in data (vtables) and by
rip-relative lea/mov in code. Then list the functions that load those vtables, with their strings.
Usage: re_xrefs.py <exe> <hex va>"""
import sys, struct, re, pefile, capstone
pe = pefile.PE(sys.argv[1], fast_load=True); base = pe.OPTIONAL_HEADER.ImageBase; data = pe.__data__
target = int(sys.argv[2], 16)
text = next(s for s in pe.sections if s.Name.startswith(b".text"))
tstart = text.PointerToRawData; tend = tstart + text.SizeOfRawData; tva = base + text.VirtualAddress
def va_of(off):
    for s in pe.sections:
        if s.PointerToRawData <= off < s.PointerToRawData + s.SizeOfRawData:
            return base + s.VirtualAddress + off - s.PointerToRawData
ptrs = [va_of(m.start()) for m in re.finditer(re.escape(struct.pack("<Q", target)), data)]
print("data pointers to target:", [hex(p) for p in ptrs])
def code_refs(va):
    out = []
    code = data[tstart:tend]
    for m in re.finditer(rb"[\x48\x4c]\x8d[\x05\x0d\x15\x1d\x25\x2d\x35\x3d](....)", code, re.S):
        at = tva + m.start(); d = struct.unpack("<i", m.group(1))[0]
        if at + 7 + d == va:
            out.append(at)
    return out
for p in ptrs:
    # the vtable starts some slots before; look for lea of p-8*k
    for k in range(0, 8):
        refs = code_refs(p - 8 * k)
        if refs:
            print(f"vtable start {hex(p - 8*k)} (slot {k}) loaded at:", [hex(r) for r in refs[:10]])
