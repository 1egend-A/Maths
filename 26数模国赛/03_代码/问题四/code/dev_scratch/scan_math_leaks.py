# -*- coding: utf-8 -*-
"""SCAN_MATH_LEAKS  找出论文源里【渲染器不支持】的 LaTeX 命令。

背景：本机 build_pdf.py 走的公式渲染器只支持 mathtext 的一个子集。
不支持的宏不会报错，而是【原样印进 PDF】：`\\mathrm{CVaR}` 就真的印成
`\\mathrm{CVaR}`、`\\%` 就印成 `\\%`。measure_pdf.py 只查 `**` / `$$` / `\\frac`
三类瑕疵，查不出这一类，所以必须单独扫。

用法：python scan_math_leaks.py <论文.md> [...]
"""
import io, re, sys

# 实测会泄漏的宏（渲染器不支持）。\\% 单独处理：它即便在数学模式里也会原样印出。
BAD = [r"\mathrm", r"\overline", r"\bar", r"\mathcal", r"\mathbf",
       r"\equiv", r"\#", r"\text{", r"\%", r"\left", r"\right"]

def scan(path):
    s = io.open(path, encoding="utf-8").read()
    lines = s.split("\n")
    hits = {}
    for i, ln in enumerate(lines, 1):
        for b in BAD:
            if b in ln:
                hits.setdefault(b, []).append(i)
    print("=" * 60)
    print(path)
    if not hits:
        print("  无泄漏宏")
        return
    for b, ls in sorted(hits.items()):
        print("  %-12s  行 %s" % (b, ", ".join(map(str, ls))))
        for i in ls[:3]:
            print("        L%-5d %s" % (i, lines[i - 1].strip()[:110]))

if __name__ == "__main__":
    for p in sys.argv[1:]:
        scan(p)
