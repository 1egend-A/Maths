#!/usr/bin/env python
# -*- coding: utf-8 -*-
r"""
build_pdf.py —— 把论文 Markdown 渲染成 A4 PDF（配图自动内嵌）

为什么不用 pandoc / LaTeX：本机三样都没有（pandoc、xelatex、weasyprint 均未安装），
但装了 Chrome。故走「自带 markdown-lite 转换 → HTML+CSS → Chrome headless --print-to-pdf」
这条路，中文与数学符号渲染已验证正常。

支持的 Markdown 子集（够论文用，不求全）：
  # ## ### 标题        | 管道表格（含对齐行）
  **粗体** *斜体* `代码` | - 无序列表
  > 引用块（论文里当"注/说明"用）
  ![图题](图片路径)     | --- 分隔线
  <!-- pagebreak -->   → 强制分页
  行内/独立数学：$...$ 与 $$...$$（支持 \tag{n} 编号）

数学不是走 LaTeX 引擎，而是本文件里的 tex2uni() 做【受限子集】的 Unicode 替换——
只覆盖本文真正用到的记法。它有三个已经踩过的坑，改它之前先看函数注释：
  ① 花括号的处理顺序（\frac 必须在 \text{}/\mathbb{} 之后）
  ② \hat 的花括号可省、可包多字母
  ③ 不带花括号的上下标（N^s、G_t^*）也要认

用法：
   python build_pdf.py 问题二_求解与结果_论文版.md 问题二_求解与结果.pdf
   不带参数时用上面的默认值。
"""

import base64
import os
import re
import subprocess
import sys

CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"
HERE = os.path.dirname(os.path.abspath(__file__))
FIGDIR = os.path.join(HERE, "out", "figures")

CSS = r"""
/* ── 版面：中文期刊风格。留白要够，正文 10.5pt / 行距 1.5 是「不挤」的下限 ── */
@page { size: A4; margin: 2.0cm 2.0cm; }
* { box-sizing: border-box; }
body {
  font-family: "Times New Roman", "SimSun", serif;
  font-size: 10.2pt; line-height: 1.50; color: #111;
  margin: 0; text-align: justify; text-justify: inter-ideograph;
}
/* 章节标题：深蓝 + 细规线，是「像论文」最省力的一招 */
h1 { font-family: "SimHei", sans-serif; font-size: 16pt; font-weight: normal;
     text-align: center; color: #14365c; letter-spacing: 0.5pt;
     margin: 0 0 3pt 0; line-height: 1.35;
     padding-bottom: 5pt; border-bottom: 1.2pt solid #14365c; }
h2 { font-family: "SimHei", sans-serif; font-size: 12.5pt; font-weight: normal;
     color: #14365c; margin: 13pt 0 5pt 0; padding-bottom: 2pt;
     border-bottom: 0.6pt solid #b9c8dc; }
h3 { font-family: "SimHei", sans-serif; font-size: 11pt; font-weight: normal;
     color: #1d4a7a; margin: 8pt 0 3pt 0; }
p  { margin: 0 0 5.5pt 0; text-indent: 2em; }
ul { margin: 3pt 0 5pt 0; padding-left: 2.1em; }
li { margin: 0 0 2.5pt 0; }
/* 三线表：上下粗、表头下细，不画竖线。学术论文的标准表式 */
table { border-collapse: collapse; width: 100%; margin: 4pt 0 5pt 0;
        font-size: 9pt; font-family: "Times New Roman", "SimSun", serif; }
thead tr { border-top: 1.3pt solid #111; border-bottom: 0.7pt solid #111; }
tbody tr:last-child { border-bottom: 1.3pt solid #111; }
th, td { border: none; padding: 2.6pt 5pt; text-align: center;
         vertical-align: middle; line-height: 1.28; }
th { font-family: "SimHei", sans-serif; font-weight: normal; }
td.l, th.l { text-align: left; }
td.r, th.r { text-align: right; }
tbody tr.grp td { font-family: "SimHei", sans-serif; font-weight: normal;
                  text-align: left; padding-top: 4pt; }
/* 表注：细竖线 + 灰字，不占版面 */
blockquote { margin: 3pt 0 4pt 0; padding: 1pt 0 1pt 8pt;
             border-left: 2pt solid #c8d2e0; color: #444; font-size: 9pt; }
blockquote p { text-indent: 0; margin: 0; }
figure { margin: 6pt 0 7pt 0; text-align: center; page-break-inside: avoid; }
figure img { max-width: 100%; }
figcaption { font-size: 9pt; font-family: "SimHei", sans-serif; margin-top: 4pt;
             text-align: center; line-height: 1.35; color: #222; }
.figrow { display: flex; gap: 10pt; align-items: flex-start;
          page-break-inside: avoid; margin: 5pt 0 6pt 0; }
.figrow figure { flex: 1 1 0; margin: 0; min-width: 0; }
hr { border: none; border-top: 0.6pt solid #ccd6e2; margin: 10pt 0; }
.pb { page-break-after: always; }
code { font-family: Consolas, "Courier New", monospace; font-size: 9.5pt; }
/* 公式：居中、编号右顶格，行距略放大以免上下标被压 */
.math { font-family: "Times New Roman", "Cambria Math", serif; font-style: italic; }
.math sub, .math sup { font-style: normal; }
.eq { text-align: center; margin: 2.2pt 0 2.2pt 0; text-indent: 0; line-height: 1.38;
      font-family: "Times New Roman", "Cambria Math", serif; font-style: italic; }
.eq .tag { font-style: normal; float: right; }
sub, sup { font-size: 0.72em; }
"""


def esc(s: str) -> str:
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


GREEK = {
    "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε",
    "zeta": "ζ", "eta": "η", "theta": "θ", "kappa": "κ", "lambda": "λ",
    "mu": "μ", "nu": "ν", "xi": "ξ", "pi": "π", "rho": "ρ", "sigma": "σ",
    "tau": "τ", "phi": "φ", "chi": "χ", "psi": "ψ", "omega": "ω",
    "Delta": "Δ", "Gamma": "Γ", "Theta": "Θ", "Lambda": "Λ", "Pi": "Π",
    "Sigma": "Σ", "Phi": "Φ", "Omega": "Ω",
    # 算子/修饰符也一并转掉，免得它们带着反斜杠进入后面的 \frac 判断
    "partial": "∂", "nabla": "∇", "infty": "∞", "cdots": "⋯", "ldots": "…",
    "dots": "…", "dotsc": "…", "colon": "：",
    "prime": "′", "ast": "*",
}

# 顺序有讲究：\le 必须在 \left 之前判掉，故先把 \left/\bigl 这类尺寸命令整体拿掉
LATEX_SYM = [
    (r"\\(?:bigl|bigr|Bigl|Bigr|left|right|Big|big|middle)\s*", ""),
    (r"\\le(?![a-zA-Z])", "≤"), (r"\\ge(?![a-zA-Z])", "≥"),
    (r"\\neq(?![a-zA-Z])", "≠"), (r"\\approx(?![a-zA-Z])", "≈"),
    (r"\\times", "×"), (r"\\cdot", "·"), (r"\\pm", "±"),
    (r"\\forall", "∀"), (r"\\in(?![a-zA-Z])", "∈"),
    (r"\\sum", "Σ"), (r"\\prod", "Π"), (r"\\int", "∫"),
    (r"\\lceil", "⌈"), (r"\\rceil", "⌉"),
    (r"\\lfloor", "⌊"), (r"\\rfloor", "⌋"),
    (r"\\qquad", "\u2003"), (r"\\quad", "\u2002"),
    (r"\\[,;:!]", " "), (r"\\ ", " "), (r"\\[{}]", " "),
    (r"\\max", "max"), (r"\\min", "min"), (r"\\exp", "exp"), (r"\\log", "log"),
    # 补：实测漏出去过的三个。`\\#` 与 `\\%` 的字符不是字母，
    #     通用宏规则 `\\([A-Za-z]+)` 根本匹配不到，必须单列。
    (r"\\equiv", "≡"), (r"\\#", "#"), (r"\\%", "%"),
]


def tex2uni(s: str) -> str:
    """LaTeX 记法的【受限子集】→ Unicode。只覆盖本文用到的那些，不做通用渲染。

    步骤顺序是踩过坑的：**必须先把 \\text{}/\\mathbb{} 与希腊字母化掉，再处理 \\frac**。
    早先先做 \\frac，而 \\frac{\\partial \\mathbb{E}[\\text{费用}_t]}{\\partial G_t} 的分子里
    夹着 \\text{...} 的花括号，`[^{}]*` 匹配不到，整条公式就原样漏出来（还会残留 `\\frac`）。
    """
    def frac(m):
        # 只有分子/分母里含加减号时才补括号；单纯含空格（多来自 \, \quad）不补，
        # 否则 \frac{\partial E[\text{费用}_t]}{\partial G_t} 会变成难看的 (∂ E)/(∂ G)。
        a = re.sub(r"\s+", " ", m.group(1).strip())
        b = re.sub(r"\s+", " ", m.group(2).strip())
        if re.search(r"[+\-−]", a):
            a = "(" + a + ")"
        if re.search(r"[+\-−]", b):
            b = "(" + b + ")"
        return "%s/%s" % (a, b)

    # ⚠️ 下面两条 `\\bar`/`\\overline` 必须在通用宏规则 `\\([A-Za-z]+)` 之前，
    #    否则它们会被当成"未知宏"原样留下（实测印出 `\bar p`）。
    #    本渲染器不画上划线，抹掉修饰、保留字母本身即可。
    s = re.sub(r"\\overline\s*", "", s)
    s = re.sub(r"\\bar\s*", "", s)
    s = re.sub(r"\\text\{([^{}]*)\}", r"\1", s)
    # \hat{X} / \hat X —— 花括号可省、可包多字母，故要多留一手
    s = re.sub(r"\\hat\s*\{([A-Za-z]+)\}",
               lambda m: m.group(1)[0] + "\u0302" + m.group(1)[1:], s)
    s = re.sub(r"\\hat\s*([A-Za-z])", lambda m: m.group(1) + "\u0302", s)
    s = re.sub(r"\\([A-Za-z]+)", lambda m: GREEK.get(m.group(1), m.group(0)), s)
    for pat, rep in LATEX_SYM:
        s = re.sub(pat, rep, s)
    # ⚠️⚠️ 位置是踩了两次才对的：`\\mathbb/\\mathrm/\\mathcal` 的替换
    #    【必须排在 LATEX_SYM 之后】。排在它之前时，`\\in\\mathcal{T}` 会先被
    #    粘成 `\\inT`，而符号表里的 `\\in(?![a-zA-Z])` 看到后面是字母 T，
    #    负向先行断言失败 ⇒ `\\in` 不替换 ⇒ `\\inT` 原样印进 PDF。
    #    排在之后时，`\\in` 早已变成 `∈`，再化 `\\mathcal{T}` 就不粘连。
    #    字符类用 `+`：原来的 `[A-Za-z]`（单字母）吃不下 `\\mathrm{CVaR}`。
    #    `\\mathbf{0.70}` 也一并纳入（Q3 曾原样印出过）。
    s = re.sub(r"\\(?:mathbb|mathrm|mathcal|mathbf)\{([A-Za-z0-9.]+)\}", r"\1", s)
    for _ in range(4):                     # \frac 可能嵌套，多跑几轮直到拆净
        new = re.sub(r"\\frac\{([^{}]*)\}\{([^{}]*)\}", frac, s)
        if new == s:
            break
        s = new
    # ⚠️ 这里【不能】盲删 {}：_{...} 与 ^{...} 还要交给 sub_sup 用；
    #    转义过的 \{ \} 已在上面被吃掉，留下的普通花括号都是下标/上标的分组。
    return s


def inline(s: str) -> str:
    """行内标记 → HTML。先抽出行内数学单独处理，避免转义互相打架。"""
    hold = []

    def stash(html: str) -> str:
        hold.append(html)
        return "\x00%d\x00" % (len(hold) - 1)

    s = re.sub(r"\$([^$]+)\$", lambda m: stash(
        '<span class="math">%s</span>' % sub_sup(tex2uni(esc(m.group(1))))), s)
    s = esc(s)
    s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
    s = re.sub(r"\*\*([^*]+)\*\*", r"<b>\1</b>", s)
    s = re.sub(r"(?<!\*)\*([^*]+)\*(?!\*)", r"<i>\1</i>", s)
    s = sub_sup(s)
    return re.sub(r"\x00(\d+)\x00", lambda m: hold[int(m.group(1))], s)


def sub_sup(s: str) -> str:
    s = re.sub(r"_\{([^{}]*)\}", r"<sub>\1</sub>", s)
    s = re.sub(r"\^\{([^{}]*)\}", r"<sup>\1</sup>", s)
    s = re.sub(r"_([A-Za-z0-9])", r"<sub>\1</sub>", s)
    s = re.sub(r"\^([A-Za-z0-9*])", r"<sup>\1</sup>", s)   # 无花括号的上标也要认
    return s


def img_src(path: str) -> str:
    """图片内嵌为 base64，避免 Chrome 的 file:// 跨目录限制。"""
    for cand in (os.path.join(HERE, path), os.path.join(FIGDIR, os.path.basename(path)),
                 path):
        if os.path.isfile(cand):
            b = base64.b64encode(open(cand, "rb").read()).decode("ascii")
            mime = "image/png" if cand.lower().endswith(".png") else "image/jpeg"
            return "data:%s;base64,%s" % (mime, b)
    raise SystemExit("找不到图片：%s" % path)


def split_row(line: str):
    line = line.strip()
    if line.startswith("|"):
        line = line[1:]
    if line.endswith("|"):
        line = line[:-1]
    return [c.strip() for c in line.split("|")]


def is_block(lines, i: int) -> bool:
    """行 i 是否为一个块的起始（段落收集遇到它必须停下）。

    与 conv() 里各分支的判定保持一致；宁可保守多停，也不能把表格/图并进正文。
    """
    t = lines[i].strip()
    if not t:
        return True
    if t.startswith("<!--") and "pagebreak" in t:
        return True
    if set(t) <= {"-", "*", "_"} and len(t) >= 3:
        return True
    if re.match(r"^#{1,4}\s", t):
        return True
    if re.match(r"^!\[[^\]]*\]\([^)]+\)(\{\d+%\})?$", t):
        return True
    if t.startswith("|") or t.startswith(">"):
        return True
    if re.match(r"^[-*]\s+", t) or re.match(r"^\d+\.\s+", t):
        return True
    if t.startswith("$$") and t.endswith("$$") and len(t) > 4:
        return True
    return False


def join_wrapped(buf):
    """把硬换行的若干源行并为一段。

    中文折行处直接相接；仅当断点两侧都是 ASCII 字母数字时才补一个空格，
    避免英文单词被粘死（如 "deep" / "learning"）。
    """
    s = buf[0]
    for nxt in buf[1:]:
        if s and nxt and s[-1].isascii() and s[-1].isalnum() \
                and nxt[0].isascii() and nxt[0].isalnum():
            s += " "
        s += nxt
    return s


def conv(md: str) -> str:
    out, i = [], 0
    lines = md.split("\n")
    while i < len(lines):
        ln = lines[i]
        s = ln.strip()

        if s.startswith("<!--") and "pagebreak" in s:
            out.append('<div class="pb"></div>')
            i += 1
            continue
        if not s:
            i += 1
            continue
        if set(s) <= {"-", "*", "_"} and len(s) >= 3:
            out.append("<hr>")
            i += 1
            continue

        m = re.match(r"^(#{1,4})\s+(.*)$", s)
        if m:
            out.append("<h%d>%s</h%d>" % (len(m.group(1)), inline(m.group(2)),
                                          len(m.group(1))))
            i += 1
            continue

        # 图片：连续多行图片自动并排（省版面），单张可用 {...%} 指定宽度
        if re.match(r"^!\[([^\]]*)\]\(([^)]+)\)(\{\d+%\})?$", s):
            figs = []
            while i < len(lines):
                m = re.match(r"^!\[([^\]]*)\]\(([^)]+)\)(\{\d+%\})?$", lines[i].strip())
                if not m:
                    break
                w = m.group(3)
                style = ' style="width:%s"' % w[1:-1] if w else ""
                figs.append('<figure%s><img src="%s"><figcaption>%s</figcaption></figure>'
                            % (style, img_src(m.group(2)), inline(m.group(1))))
                i += 1
            if len(figs) == 1:
                out.append(figs[0])
            else:
                out.append('<div class="figrow">%s</div>' % "".join(figs))
            continue

        # 表格：本行是 | ... |，下一行是 |---|---|
        if s.startswith("|") and i + 1 < len(lines) and \
                re.match(r"^\|[\s:|-]+\|$", lines[i + 1].strip()):
            hdr = split_row(s)
            # 对齐：# 用 |:---|---:|:---:| 指定左/右/居中，缺省居中。
            # 长文本列（如校验表的「检验项」「实测结果」）居中会把字撑得七零八落。
            als = split_row(lines[i + 1].strip())
            al = []
            for k in range(len(hdr)):
                c = als[k] if k < len(als) else "---"
                al.append("c" if (c.startswith(":") and c.endswith(":")
                                  and len(c) > 1) else
                          "l" if c.startswith(":") else
                          "r" if c.endswith(":") else "c")

            def cell(tag, k, c):
                cls = ' class="%s"' % al[k] if k < len(al) and al[k] != "c" else ""
                return "<%s%s>%s</%s>" % (tag, cls, inline(c), tag)

            j = i + 2
            body = []
            while j < len(lines) and lines[j].strip().startswith("|"):
                body.append(split_row(lines[j].strip()))
                j += 1
            out.append("<table><thead><tr>"
                       + "".join(cell("th", k, c) for k, c in enumerate(hdr))
                       + "</tr></thead><tbody>")
            for r in body:
                # 只有「全行加粗**且至多一个非空格**」的行才算分组标题行（如表 7-2 的
                # 「充电量 / 放电量」）；像表 7-3 的「合计」行虽然加粗，但它是数据行，
                # 必须居中，不能按分组行的左对齐处理。
                cells = [x for x in r if x]
                grp = (len(cells) == 1 and cells[0].startswith("**"))
                tds = "".join(cell("td", k, c) for k, c in enumerate(r))
                out.append('<tr class="grp">%s</tr>' % tds if grp
                           else "<tr>%s</tr>" % tds)
            out.append("</tbody></table>")
            i = j
            continue

        if s.startswith(">"):
            buf = []
            while i < len(lines) and lines[i].strip().startswith(">"):
                buf.append(lines[i].strip().lstrip(">").strip())
                i += 1
            # 逐行 inline 会让跨折行的 **粗体** 漏掉，必须先并段再 inline
            out.append("<blockquote>%s</blockquote>"
                       % inline(join_wrapped([b for b in buf if b])))
            continue

        if re.match(r"^[-*]\s+", s):
            items = []
            while i < len(lines) and re.match(r"^[-*]\s+", lines[i].strip()):
                part = [re.sub(r"^[-*]\s+", "", lines[i].strip())]
                i += 1
                # 列表项同样会被硬换行折断，**粗体** 也可能跨折行：先并再 inline
                while i < len(lines) and not is_block(lines, i):
                    part.append(lines[i].strip())
                    i += 1
                items.append(join_wrapped(part))
            out.append("<ul>%s</ul>" % "".join("<li>%s</li>" % inline(x)
                                               for x in items))
            continue

        if re.match(r"^\d+\.\s+", s):
            items = []
            while i < len(lines) and re.match(r"^\d+\.\s+", lines[i].strip()):
                part = [re.sub(r"^\d+\.\s+", "", lines[i].strip())]
                i += 1
                while i < len(lines) and not is_block(lines, i):
                    part.append(lines[i].strip())
                    i += 1
                items.append(join_wrapped(part))
            out.append("<ol>%s</ol>" % "".join("<li>%s</li>" % inline(x)
                                               for x in items))
            continue

        # 独立成段的公式：$$...$$ 单行；\tag{n} 抽出做右侧编号
        if s.startswith("$$") and s.endswith("$$") and len(s) > 4:
            body = s[2:-2].strip()
            tag = ""
            m2 = re.search(r"\\tag\{([^{}]*)\}", body)
            if m2:
                tag = '<span class="tag">(%s)</span>' % m2.group(1)
                body = (body[:m2.start()] + body[m2.end():]).strip()
            out.append('<p class="eq">%s%s</p>'
                       % (sub_sup(tex2uni(esc(body))), tag))
            i += 1
            continue

        # 普通段落：把硬换行的连续行并成【一个】<p>。
        # 逐行成段有两个恶果：跨行的 **粗体** 匹配不上、星号直接印在纸上；
        # 且每个折行都吃一份段间距，白扔版面。并段后首行缩进 2em、余行齐头，
        # 才是中文论文该有的样子。
        buf = [s]
        i += 1
        while i < len(lines) and not is_block(lines, i):
            buf.append(lines[i].strip())
            i += 1
        out.append("<p>%s</p>" % inline(join_wrapped(buf)))
    return "\n".join(out)


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else "问题二_求解与结果_论文版.md"
    dst = sys.argv[2] if len(sys.argv) > 2 else "问题二_求解与结果.pdf"
    if not os.path.isabs(src):
        src = os.path.join(HERE, src)
    if not os.path.isabs(dst):
        dst = os.path.join(HERE, dst)

    md = open(src, encoding="utf-8").read()
    html = ("<!DOCTYPE html><html><head><meta charset='utf-8'>"
            "<style>%s</style></head><body>%s</body></html>" % (CSS, conv(md)))

    tmp = os.path.join(os.environ.get("TEMP", HERE), "q2_paper.html")
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(html)

    if not os.path.isfile(CHROME):
        raise SystemExit("找不到 Chrome：%s" % CHROME)
    subprocess.run([CHROME, "--headless=new", "--disable-gpu",
                    "--no-pdf-header-footer", "--no-sandbox",
                    "--print-to-pdf=" + dst.replace("/", "\\"),
                    "file:///" + tmp.replace("\\", "/")],
                   check=True, capture_output=True)
    n = open(dst, "rb").read().count(b"/Type /Page") or -1
    print("已生成：%s（约 %d 页，%.0f KB）"
          % (dst, max(n - 1, 0), os.path.getsize(dst) / 1024))


if __name__ == "__main__":
    main()
