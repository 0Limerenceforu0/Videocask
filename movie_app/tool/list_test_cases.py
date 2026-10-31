import re
import glob

pat = re.compile(r"^\s*test(?:Widgets)?\(\s*'(.*?)'", re.M)
files = sorted(glob.glob("test/**/*_test.dart", recursive=True))
total = 0
for f in files:
    src = open(f, encoding="utf-8").read()
    names = pat.findall(src)
    if not names:
        continue
    total += len(names)
    print("### %s  (%d)" % (f, len(names)))
    for n in names:
        print("   -", n)
print("TOTAL", total)
