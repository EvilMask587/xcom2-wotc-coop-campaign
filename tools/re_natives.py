"""Name the UnrealScript native (exec...) functions that contain given addresses.
UE3 registers natives as {const char* "UClassexecName", void* func} pairs in data; this collects
those pairs and, for each RVA, prints the nearest registered function at or below it.
Usage: re_natives.py <exe> <hex rva> [...]"""
import sys, struct, bisect, pefile
pe = pefile.PE(sys.argv[1], fast_load=True); base = pe.OPTIONAL_HEADER.ImageBase; data = pe.__data__
text = next(s for s in pe.sections if s.Name.startswith(b".text"))
tlo, thi = base + text.VirtualAddress, base + text.VirtualAddress + text.Misc_VirtualSize

def cstr(va):
    try:
        off = pe.get_offset_from_rva(va - base)
    except Exception:
        return None
    end = data.find(b"\0", off, off + 128)
    return data[off:end].decode("ascii", "replace") if end > off else None

funcs = {}
for s in pe.sections:
    if s.Name.startswith((b".rdata", b".data")):
        blob = s.get_data()
        for k in range(0, len(blob) - 15, 8):
            p, f = struct.unpack_from("<QQ", blob, k)
            if tlo <= f < thi and base <= p < base + pe.OPTIONAL_HEADER.SizeOfImage:
                name = cstr(p)
                # stored as class + function, e.g. "UXComGameStateHistoryexecGetGameStateForObjectID"
                if name and "exec" in name and name.isidentifier():
                    funcs[f] = name
starts = sorted(funcs)
print(f"{len(starts)} natives")
for a in sys.argv[2:]:
    va = base + int(a, 16)
    i = bisect.bisect_right(starts, va) - 1
    print(f"0x{int(a, 16):x}: {funcs[starts[i]]}+0x{va - starts[i]:x}" if i >= 0 else f"0x{a}: ?")
