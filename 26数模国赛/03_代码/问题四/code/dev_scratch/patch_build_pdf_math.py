# -*- coding: utf-8 -*-
"""PATCH_BUILD_PDF_MATH  修 build_pdf.py 里公式渲染的两个真 bug。

症状（都已实测）：PDF 里原样印出 `\\mathrm{CVaR}`、`\\in`、`\\bar p`、`\\equiv`、
`\\#`、`\\%` —— 公式没渲染，反斜杠直接进了版面。measure_pdf.py 只查
`**` / `$$` / `\\frac`，查不出这一类，所以之前判了"瑕疵: 无"。

根因（两个，互相独立）：

  (1) 单字母假设。`re.sub(r"\\\\(?:mathbb|mathrm|mathcal)\\{([A-Za-z])\\}",
      r"\\1", s)` 的字符类是 `[A-Za-z]`，只吃【一个字母】。
      `\\mathcal{T}` 侥幸命中，`\\mathrm{CVaR}`（4 个字母）命中不了，原样漏出。

  (2) 处理顺序错误（更要命）。`\\mathcal{T}` → `T` 发生在希腊字母/符号表之前，
      于是 `\\in\\mathcal{T}` 被粘成 `\\inT` 这一个"宏名"，而
      `\\\\([A-Za-z]+)` 贪婪地整个吃掉 ⇒ `\\in` 连带丢失，印成 `\\inT`。
      ---- 这条正是 1 个宏出错却带着邻居一起坏的典型。

修法：
  · 把 `\\mathbb/\\mathrm/\\mathcal` 的处理**挪到希腊字母与符号表之后**；
  · 字符类放宽为 `[A-Za-z]+`（多字母）；
  · 符号表补 `\\equiv \\# \\%`；
  · `\\bar`/`\\overline` 在通用宏规则**之前**吃掉（本渲染器不画上划线，
    保留字母本身即可，语义在上下文中不受影响）。

用法：python patch_build_pdf_math.py <build_pdf.py> [...]
"""
import io, sys

OLD_DECOR = (
    '    s = re.sub(r"\\\\(?:mathbb|mathrm|mathcal)\\{([A-Za-z])\\}", r"\\1", s)\n'
)

NEW_BLOCK = (
    '    # ⚠️ 下面两条 `\\\\bar`/`\\\\overline` 必须在通用宏规则 `\\\\([A-Za-z]+)` 之前，\n'
    '    #    否则它们会被当成"未知宏"原样留下（实测印出 `\\bar p`）。\n'
    '    #    本渲染器不画上划线，抹掉修饰、保留字母本身即可。\n'
    '    s = re.sub(r"\\\\overline\\s*", "", s)\n'
    '    s = re.sub(r"\\\\bar\\s*", "", s)\n'
)

OLD_MACRO = (
    '    s = re.sub(r"\\\\([A-Za-z]+)", lambda m: GREEK.get(m.group(1), m.group(0)), s)\n'
)

NEW_MACRO = (
    '    s = re.sub(r"\\\\([A-Za-z]+)", lambda m: GREEK.get(m.group(1), m.group(0)), s)\n'
    '    # ⚠️ 顺序！`\\\\mathcal{T}` 等【必须】在上面那步之后再化掉。\n'
    '    #    曾经它排在前面：`\\\\in\\\\mathcal{T}` 先变成 `\\\\inT`，随后被\n'
    '    #    `\\\\([A-Za-z]+)` 贪婪吞成一个未知宏名，`\\\\in` 跟着一起漏出来。\n'
    '    #    字符类也要 `+` 而非单个字母——原来的 `[A-Za-z]` 吃不下 `\\\\mathrm{CVaR}`。\n'
    '    s = re.sub(r"\\\\(?:mathbb|mathrm|mathcal)\\{([A-Za-z]+)\\}", r"\\1", s)\n'
)

OLD_SYM_TAIL = '    (r"\\\\max", "max"), (r"\\\\min", "min"), (r"\\\\exp", "exp"), (r"\\\\log", "log"),\n'

NEW_SYM_TAIL = (
    '    (r"\\\\max", "max"), (r"\\\\min", "min"), (r"\\\\exp", "exp"), (r"\\\\log", "log"),\n'
    '    # 补：实测漏出去过的三个。`\\\\#` 与 `\\\\%` 的字符不是字母，\n'
    '    #     通用宏规则 `\\\\([A-Za-z]+)` 根本匹配不到，必须单列。\n'
    '    (r"\\\\equiv", "≡"), (r"\\\\#", "#"), (r"\\\\%", "%"),\n'
)


def patch(path):
    s = io.open(path, encoding="utf-8").read()
    changed = []

    if OLD_DECOR in s:
        s = s.replace(OLD_DECOR, NEW_BLOCK)
        changed.append("移除前置的单字母 mathbb/mathrm/mathcal 替换")
    else:
        print("  ⚠️ 未找到待移除的旧替换行，跳过")

    if OLD_MACRO in s:
        s = s.replace(OLD_MACRO, NEW_MACRO)
        changed.append("在希腊字母之后插入多字母 mathrm/mathcal 替换")
    else:
        print("  ⚠️ 未找到通用宏规则行，跳过")

    if OLD_SYM_TAIL in s:
        s = s.replace(OLD_SYM_TAIL, NEW_SYM_TAIL)
        changed.append("符号表补 equiv / # / %")
    else:
        print("  ⚠️ 未找到符号表结尾，跳过")

    io.open(path, "w", encoding="utf-8").write(s)
    print("%s\n   -> %s" % (path, "；".join(changed) if changed else "无改动"))


if __name__ == "__main__":
    for p in sys.argv[1:]:
        patch(p)
