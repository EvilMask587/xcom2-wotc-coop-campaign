"""Find call sites of imported APIs in a PE64 and print nearby LEA'd strings.
Usage: re_callers.py <exe> <ApiName> [...]"""
import sys, pefile, capstone
pe = pefile.PE(sys.argv[1], fast_load=False)
base = pe.OPTIONAL_HEADER.ImageBase
iat = {}
for e in pe.DIRECTORY_ENTRY_IMPORT:
    for i in e.imports:
        if i.name: iat[i.address] = i.name.decode()
want = {a for a, n in iat.items() if n in sys.argv[2:]}
text = next(s for s in pe.sections if s.Name.startswith(b".text"))
code = text.get_data(); tva = base + text.VirtualAddress
md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64); md.detail = False
def rstr(va):
    try:
        off = pe.get_offset_from_rva(va - base); b = pe.__data__[off:off+160]
    except Exception: return None
    if b[1:2] == b"\0" and 32 <= b[0] < 127:
        s = b.decode("utf-16-le", "ignore").split("\0")[0]
    else:
        s = b.split(b"\0")[0].decode("latin1")
    return s if len(s) >= 3 and s.isprintable() else None
import re
pat = re.compile(rb"\xff\x15(....)", re.S)   # call [rip+disp32]
for m in pat.finditer(code):
    at = tva + m.start(); tgt = at + 6 + int.from_bytes(m.group(1), "little", signed=True)
    if tgt in want:
        lo = max(0, m.start() - 120)
        ins = list(md.disasm(code[lo:m.start()+6], tva + lo))
        strs = []
        for x in ins:
            if x.mnemonic == "lea" and "rip" in x.op_str:
                d = int(x.op_str.split("rip")[1].strip(" +]").replace("- ","-"), 16) if "0x" in x.op_str else 0
                s = rstr(x.address + x.size + d)
                if s: strs.append(s)
        print(hex(at), iat[tgt], ascii(strs[-4:]))
