"""Make a hard-link clone of a test install (files linked, dirs created).
Writable dirs (Config, Logs, SaveData, Mods) are skipped so each clone writes its own."""
import os, sys
src, dst = sys.argv[1], sys.argv[2]
SKIP = {"logs", "savedata"}
n = 0
for root, dirs, files in os.walk(src):
    rel = os.path.relpath(root, src)
    dirs[:] = [d for d in dirs if d.lower() not in SKIP]
    os.makedirs(os.path.join(dst, rel), exist_ok=True)
    for f in files:
        s, d = os.path.join(root, f), os.path.join(dst, rel, f)
        if not os.path.exists(d):
            os.link(s, d); n += 1
print("linked", n)
