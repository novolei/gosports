"""Check that every res:// path mentioned in scripts / scenes / project.godot exists (ignores %s templates)."""
import os, re, sys

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
pat = re.compile(r'res://[A-Za-z0-9_./\- ]+\.[A-Za-z0-9]+')
bad = 0
for base, dirs, files in os.walk(root):
    dirs[:] = [d for d in dirs if d not in (".godot", "build", ".git")]
    for f in files:
        if not f.endswith((".gd", ".tscn", ".godot", ".cfg", ".tres")):
            continue
        p = os.path.join(base, f)
        try:
            txt = open(p, encoding="utf-8", errors="ignore").read()
        except OSError:
            continue
        for m in pat.finditer(txt):
            ref = m.group(0)
            if "%" in ref:
                continue
            fs = os.path.join(root, ref[6:].replace("/", os.sep))
            if not os.path.exists(fs):
                print("MISSING", ref, " <- ", os.path.relpath(p, root))
                bad += 1
print("missing:", bad)
sys.exit(1 if bad else 0)
