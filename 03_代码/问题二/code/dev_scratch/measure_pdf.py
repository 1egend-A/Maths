# -*- coding: utf-8 -*-
"""measure_pdf.py —— 量每一页的墨迹填充率 / 底部留白，并检查排版瑕疵。

用法: python measure_pdf.py _probe.pdf
墨迹判定: 以 dpi=50 渲染灰度，逐行扫描「是否存在灰度 < 200 的像素」。
"""
import sys
import fitz

DPI = 50
SCALE = DPI / 72.0          # pt -> px
PT_PER_CM = 72 / 2.54


def main():
    pdf = sys.argv[1] if len(sys.argv) > 1 else "_probe.pdf"
    d = fitz.open(pdf)
    H = d[0].rect.height
    print("pages = %d   (page height %.1f pt)" % (len(d), H))

    total = 0.0
    for pno in range(len(d)):
        pg = d[pno]
        pm = pg.get_pixmap(dpi=DPI, colorspace=fitz.csGRAY)
        w, h = pm.width, pm.height
        buf = pm.samples
        last = 0
        for y in range(h):
            row = buf[y * w:(y + 1) * w]
            if min(row) < 200:
                last = y
        ink_bottom = last / SCALE
        fill = 100.0 * ink_bottom / H
        gap_cm = (H - ink_bottom) / PT_PER_CM
        total += ink_bottom
        print("p%-3d fill=%5.1f%%  gap=%5.1f cm   ink_bottom=%.0f pt"
              % (pno + 1, fill, gap_cm, ink_bottom))

    print("content = %.0f pt = %.2f pages" % (total, total / H))

    # ---- 排版瑕疵体检 ----
    txt = "\n".join(d[i].get_text() for i in range(len(d)))
    bad = []
    for token, what in (("**", "未渲染的粗体标记"),
                        ("$$", "未渲染的行间公式"),
                        ("\\text", "未渲染的 LaTeX \\text"),
                        ("\\frac", "未渲染的 LaTeX \\frac"),
                        ("\\eta", "未渲染的 \\eta")):
        n = txt.count(token)
        if n:
            bad.append("%s x%d（%s）" % (token, n, what))
    print("瑕疵:", "；".join(bad) if bad else "无")


if __name__ == "__main__":
    main()
