"""Close a handle inside another process owned by the same user (no admin needed).
Usage: python -I close_remote_handle.py <pid> <hex handle> [<hex handle> ...]"""
import ctypes, sys
from ctypes import wintypes as w
k32 = ctypes.WinDLL("kernel32", use_last_error=True)
k32.OpenProcess.restype = w.HANDLE
k32.OpenProcess.argtypes = [w.DWORD, w.BOOL, w.DWORD]
k32.DuplicateHandle.argtypes = [w.HANDLE, w.HANDLE, w.HANDLE, ctypes.POINTER(w.HANDLE), w.DWORD, w.BOOL, w.DWORD]
PROCESS_DUP_HANDLE, DUPLICATE_CLOSE_SOURCE = 0x40, 0x1
pid = int(sys.argv[1])
proc = k32.OpenProcess(PROCESS_DUP_HANDLE, False, pid)
if not proc:
    sys.exit(f"OpenProcess failed: {ctypes.get_last_error()}")
for hx in sys.argv[2:]:
    ok = k32.DuplicateHandle(proc, w.HANDLE(int(hx, 16)), None, None, 0, False, DUPLICATE_CLOSE_SOURCE)
    print(hx, "closed" if ok else f"failed {ctypes.get_last_error()}")
