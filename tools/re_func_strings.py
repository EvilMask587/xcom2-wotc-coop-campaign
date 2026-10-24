"""Strings referenced (lea rip-relative) by the function containing each RVA of a PE64.
The function bounds are guessed from int3 (0xCC) padding. Usage: re_func_strings.py <exe> <hex rva> [...]"""
import sys, pefile, capstone
pe = pefile.PE(sys.argv[1], fast_load=True); base = pe.OPTIONAL_HEADER.ImageBase
data = pe.__data__
md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)

def rstr(va):
    try:
        off = pe.get_offset_from_rva(va - base); b = data[off:off + 200]
    except Exception:
        return None
    if b[1:2] == b"\0" and 32 <= b[0] < 127:
        s = b.decode("utf-16-le", "ignore").split("\0")[0]
    else:
        s = b.split(b"\0")[0].decode("latin1")
    return s if len(s) >= 4 and s.isprintable() else None

for arg in sys.argv[2:]:
    rva = int(arg, 16); off = pe.get_offset_from_rva(rva)
    lo = off
    while lo > off - 0x4000 and not (data[lo - 1] == 0xCC and data[lo - 2] == 0xCC):
        lo -= 1
    hi = off
    while hi < off + 0x8000 and not (data[hi] == 0xCC and data[hi + 1] == 0xCC):
        hi += 1
    start_rva = rva - (off - lo)
    strs = []
    for x in md.disasm(data[lo:hi], base + start_rva):
        if x.mnemonic == "lea" and "rip" in x.op_str and "0x" in x.op_str:
            d = int(x.op_str.split("rip")[1].strip(" +]").replace("- ", "-"), 16)
            s = rstr(x.address + x.size + d)
            if s and s not in strs:
                strs.append(s)
    print(f"{arg}: func 0x{start_rva:x} size 0x{hi - lo:x}:", ascii(strs[:12]))
