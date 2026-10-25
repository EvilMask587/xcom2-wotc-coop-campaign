"""Direct call sites (E8 rel32) of a function VA in a PE64, with strings of each caller function.
Usage: re_calls.py <exe> <hex va>"""
import sys, struct, re, subprocess, os, pefile
pe = pefile.PE(sys.argv[1], fast_load=True); base = pe.OPTIONAL_HEADER.ImageBase; data = pe.__data__
target = int(sys.argv[2], 16)
text = next(s for s in pe.sections if s.Name.startswith(b".text"))
t0 = text.PointerToRawData; code = data[t0:t0 + text.SizeOfRawData]; tva = base + text.VirtualAddress
hits = []
for m in re.finditer(rb"\xe8", code):
    i = m.start()
    if i + 5 > len(code): break
    d = struct.unpack_from("<i", code, i + 1)[0]
    if tva + i + 5 + d == target:
        hits.append(tva + i)
print("callers:", [hex(h) for h in hits])
if hits:
    here = os.path.dirname(os.path.abspath(__file__))
    subprocess.run([sys.executable, "-I", os.path.join(here, "re_func_strings.py"), sys.argv[1]] + [hex(h - base)[2:] for h in hits[:12]])
