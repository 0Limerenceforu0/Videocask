"""扫描 lib/ 下零引用的 .dart 文件（候选死代码）。

判定：文件没有被任何 lib/ test/ tool/ 下的文件通过
import / export / part / part of 引用，且不是 main 入口、不是条件导入 stub。

用法：python tool/dead_code_scan.py
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

IMPORT_RE = re.compile(r"^\s*(?:import|export|part)\s+['\"]([^'\"]+)['\"]", re.M)


def dart_files(base):
    out = []
    for dirpath, _, names in os.walk(base):
        for n in names:
            if n.endswith(".dart"):
                out.append(os.path.join(dirpath, n))
    return out


def main():
    lib_dir = os.path.join(ROOT, "lib")
    files = dart_files(lib_dir)
    rel = {f: os.path.relpath(f, ROOT).replace("\\", "/") for f in files}

    # 收集所有引用（相对 import 解析到具体文件）
    referenced = {}
    for f in files:
        relf = rel[f]
        # 该文件引用了谁
        targets = []
        try:
            src = open(f, encoding="utf-8", errors="ignore").read()
        except OSError:
            continue
        for m in IMPORT_RE.finditer(src):
            spec = m.group(1)
            if spec.startswith("dart:") or spec.startswith("package:"):
                continue
            p = os.path.normpath(os.path.join(os.path.dirname(f), spec))
            targets.append(os.path.relpath(p, ROOT).replace("\\", "/"))
        referenced[relf] = targets

    # 反查：谁被引用
    incoming = {r: [] for r in rel.values()}
    for src, tgts in referenced.items():
        for t in tgts:
            if t in incoming and t != src:
                incoming[t].append(src)

    # 其它目录（test/tool/bin）里的引用
    other_roots = [os.path.join(ROOT, "test"), os.path.join(ROOT, "tool"),
                   os.path.join(ROOT, "bin"), os.path.join(ROOT, "web")]
    other_refs = set()
    blob = []
    for r in other_roots:
        if not os.path.isdir(r):
            continue
        for dirpath, _, names in os.walk(r):
            for n in names:
                if n.endswith((".dart", ".py", ".js", ".sh", ".ps1")):
                    try:
                        blob.append(open(os.path.join(dirpath, n), encoding="utf-8",
                                         errors="ignore").read())
                    except OSError:
                        pass
    blob_text = "\n".join(blob)
    for r in rel.values():
        base = os.path.basename(r)
        if base in blob_text:
            other_refs.add(r)

    cands = []
    for f in files:
        r = rel[f]
        src = open(f, encoding="utf-8", errors="ignore").read()
        lines = src.count("\n") + 1
        base = os.path.basename(f)
        stem = base[:-5]
        reasons = []
        if incoming[r]:
            continue
        if r in other_refs:
            reasons.append("外部目录提及")
        if "main(" in src and ("void main" in src or "main(List" in src):
            reasons.append("含 main()")
        # 条件导入 stub：_io/_web/_stub/_mobile/_desktop 结尾且存在配对基础文件
        for suf in ("_io", "_web", "_stub", "_mobile", "_desktop", "_windows",
                    "_android", "_linux", "_macos"):
            if stem.endswith(suf):
                peer = os.path.join(os.path.dirname(f), stem[: -len(suf)] + ".dart")
                if os.path.exists(peer):
                    reasons.append("条件导入 stub(peer 存在)")
        cands.append((r, lines, "; ".join(reasons)))

    cands.sort(key=lambda x: -x[1])
    total = sum(c[1] for c in cands)
    print("候选死代码 %d 个, 共 %d 行\n" % (len(cands), total))
    for r, lines, reason in cands:
        flag = "  <<< " + reason if reason else ""
        print("%5d  %s%s" % (lines, r, flag))
    return 0


if __name__ == "__main__":
    sys.exit(main())
