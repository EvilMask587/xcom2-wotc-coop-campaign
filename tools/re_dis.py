"""Disassemble a PE64 range. Usage: re_dis.py <exe> <hex va> <before bytes> <after bytes>"""
import sys, pefile, capstone
pe = pefile.PE(sys.argv[1], fast_load=True); base = pe.OPTIONAL_HEADER.ImageBase
va = int(sys.argv[2], 16); lo = va - int(sys.argv[3]); n = int(sys.argv[3]) + int(sys.argv[4])
off = pe.get_offset_from_rva(lo - base); code = pe.__data__[off:off+n]
md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
for x in md.disasm(code, lo): print(hex(x.address), x.mnemonic, x.op_str, "<==" if x.address == va else "")
