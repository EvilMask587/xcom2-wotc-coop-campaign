"""Run an exe under a minimal debugger; print DLL loads, debug strings, exceptions, exit code.
Usage: trace_start.py <exe> <cwd> [args...]"""
import ctypes, sys, os
from ctypes import wintypes as w
k = ctypes.WinDLL("kernel32", use_last_error=True)
class SI(ctypes.Structure):
    _fields_ = [("cb", w.DWORD), ("r", w.LPWSTR), ("d", w.LPWSTR), ("t", w.LPWSTR)] + \
               [(n, w.DWORD) for n in "x y xs ys xc yc fa fl".split()] + \
               [("sw", w.WORD), ("cb2", w.WORD), ("r2", ctypes.c_void_p), ("i", w.HANDLE), ("o", w.HANDLE), ("e", w.HANDLE)]
class PI(ctypes.Structure):
    _fields_ = [("hp", w.HANDLE), ("ht", w.HANDLE), ("pid", w.DWORD), ("tid", w.DWORD)]
class DE(ctypes.Structure):
    _fields_ = [("code", w.DWORD), ("pid", w.DWORD), ("tid", w.DWORD), ("pad", w.DWORD), ("u", ctypes.c_byte * 160)]
exe, cwd = sys.argv[1], sys.argv[2]
cmd = '"%s" %s' % (exe, " ".join(sys.argv[3:]))
si = SI(); si.cb = ctypes.sizeof(SI); pi = PI()
assert k.CreateProcessW(None, ctypes.c_wchar_p(cmd), None, None, False, 0x1 | 0x2, None, cwd, ctypes.byref(si), ctypes.byref(pi)), ctypes.get_last_error()
GetFinalPath = k.GetFinalPathNameByHandleW
ev = DE()
while k.WaitForDebugEvent(ctypes.byref(ev), 120000):
    c, cont = ev.code, 0x00010002  # DBG_CONTINUE
    u = bytes(ev.u)
    if c == 6:  # LOAD_DLL
        h = int.from_bytes(u[0:8], "little"); buf = ctypes.create_unicode_buffer(512)
        if h and GetFinalPath(w.HANDLE(h), buf, 512, 0): print("DLL", os.path.basename(buf.value))
        if h: k.CloseHandle(w.HANDLE(h))
    elif c == 1:  # EXCEPTION
        code = int.from_bytes(u[0:4], "little"); first = int.from_bytes(u[152:156], "little")
        if code not in (0x80000003, 0x406D1388):
            print("EXC", hex(code), "addr", hex(int.from_bytes(u[16:24], "little")), "first" if first else "second")
            cont = 0x80010001  # DBG_EXCEPTION_NOT_HANDLED
    elif c == 8:  # OUTPUT_DEBUG_STRING
        print("ODS", "(debug string)")
    elif c == 5:  # EXIT_PROCESS
        print("EXIT", int.from_bytes(u[0:4], "little")); k.ContinueDebugEvent(ev.pid, ev.tid, cont); break
    k.ContinueDebugEvent(ev.pid, ev.tid, cont)
