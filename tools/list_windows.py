"""List or retitle top-level windows of a process. Usage: list_windows.py <pid> [new title]"""
import ctypes, sys
from ctypes import wintypes as w
u = ctypes.WinDLL("user32", use_last_error=True)
pid = int(sys.argv[1]); new = sys.argv[2] if len(sys.argv) > 2 else None
CB = ctypes.WINFUNCTYPE(w.BOOL, w.HWND, w.LPARAM)
def cb(h, _):
    p = w.DWORD(); u.GetWindowThreadProcessId(h, ctypes.byref(p))
    if p.value == pid:
        t = ctypes.create_unicode_buffer(256); c = ctypes.create_unicode_buffer(256)
        u.GetWindowTextW(h, t, 256); u.GetClassNameW(h, c, 256)
        print(hex(h or 0), repr(c.value), repr(t.value), "visible" if u.IsWindowVisible(h) else "")
        if new and t.value: u.SetWindowTextW(h, new)
    return True
u.EnumWindows(CB(cb), 0)
