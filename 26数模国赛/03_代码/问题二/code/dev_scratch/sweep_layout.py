# -*- coding: utf-8 -*-
"""sweep_layout.py —— 试几档字号/行距，看页数与填充率，挑「不挤又 ≤7 页」的档。

只临时改 build_pdf.py 里那两行 CSS，跑完必还原（try/finally），不留脏状态。
"""
import io
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
BUILD = os.path.join(ROOT, "build_pdf.py")
MD = "问题二_求解与结果_论文版.md"

COMBOS = [(10.0, 1.45), (10.2, 1.50), (10.3, 1.52), (10.4, 1.55), (10.5, 1.58)]


def measure(pdf):
    import fitz
    d = fitz.open(pdf)
    H = d[0].rect.height
    fills, tot = [], 0.0
    for p in range(len(d)):
        pm = d[p].get_pixmap(dpi=50, colorspace=fitz.csGRAY)
        w, h = pm.width, pm.height
        buf, last = pm.samples, 0
        for y in range(h):
            if min(buf[y * w:(y + 1) * w]) < 200:
                last = y
        fills.append(100.0 * (last * 72.0 / 50) / H)
        tot += last * 72.0 / 50
    return len(d), fills, tot


def main():
    src = io.open(BUILD, encoding="utf-8").read()
    old = re.search(r"font-size: ([\d.]+)pt; line-height: ([\d.]+);", src)
    assert old, "找不到 CSS 字号行"
    orig = old.group(0)
    print("原始:", orig, "\n")
    try:
        for fs, lh in COMBOS:
            new = "font-size: %gpt; line-height: %g;" % (fs, lh)
            io.open(BUILD, "w", encoding="utf-8", newline="\n").write(
                src.replace(orig, new))
            subprocess.run([sys.executable, "build_pdf.py", MD, "_probe.pdf"],
                           cwd=ROOT, stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, check=True)
            n, fills, tot = measure(os.path.join(ROOT, "_probe.pdf"))
            head = " ".join("%.0f" % f for f in fills)
            print("%4.1fpt/%.2f  ->  %d 页   content %5.0fpt   fills: %s"
                  % (fs, lh, n, tot, head))
    finally:
        io.open(BUILD, "w", encoding="utf-8", newline="\n").write(src)
        print("\n已还原 build_pdf.py")


if __name__ == "__main__":
    main()
