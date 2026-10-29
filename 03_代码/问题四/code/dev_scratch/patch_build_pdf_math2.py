# -*- coding: utf-8 -*-
"""PATCH_BUILD_PDF_MATH2  把 mathbb/mathrm/mathcal 的替换挪到【符号表之后】。

第一版补丁把它插在希腊字母之后、LATEX_SYM 之前，**位置还是错的**：
`\\in\\mathcal{T}` 仍会被粘成 `\\inT`，而 LATEX_SYM 里的
`\\\\in(?![a-zA-Z])` 看到 `\\in` 后面跟着字母 `T`，负向先行断言失败 ⇒ 不替换 ⇒
`\\inT` 原样漏进 PDF（实测 Q4 还剩 1 处、Q3 还剩 4 处）。

正确位置：LATEX_SYM 循环**之后**——那时 `\\in` 已经变成 `∈`，
再化 `\\mathcal{T}` 就不会粘连。顺带把 `\\mathbf{...}` 也纳入（Q3 印出过 `\\mathbf{0.70}`）。

用法：python patch_build_pdf_math2.py <build_pdf.py> [...]
"""
import io, sys

OLD = (
    '    s = re.sub(r"\\\\([A-Za-z]+)", lambda m: GREEK.get(m.group(1), m.group(0)), s)\n'
    '    # ⚠️ 顺序！`\\\\mathcal{T}` 等【必须】在上面那步之后再化掉。\n'
    '    #    曾经它排在前面：`\\\\in\\\\mathcal{T}` 先变成 `\\\\inT`，随后被\n'
    '    #    `\\\\([A-Za-z]+)` 贪婪吞成一个未知宏名，`\\\\in` 跟着一起漏出来。\n'
    '    #    字符类也要 `+` 而非单个字母——原来的 `[A-Za-z]` 吃不下 `\\\\mathrm{CVaR}`。\n'
    '    s = re.sub(r"\\\\(?:mathbb|mathrm|mathcal)\\{([A-Za-z]+)\\}", r"\\1", s)\n'
    '    for pat, rep in LATEX_SYM:\n'
    '        s = re.sub(pat, rep, s)\n'
)

NEW = (
    '    s = re.sub(r"\\\\([A-Za-z]+)", lambda m: GREEK.get(m.group(1), m.group(0)), s)\n'
    '    for pat, rep in LATEX_SYM:\n'
    '        s = re.sub(pat, rep, s)\n'
    '    # ⚠️⚠️ 位置是踩了两次才对的：`\\\\mathbb/\\\\mathrm/\\\\mathcal` 的替换\n'
    '    #    【必须排在 LATEX_SYM 之后】。排在它之前时，`\\\\in\\\\mathcal{T}` 会先被\n'
    '    #    粘成 `\\\\inT`，而符号表里的 `\\\\in(?![a-zA-Z])` 看到后面是字母 T，\n'
    '    #    负向先行断言失败 ⇒ `\\\\in` 不替换 ⇒ `\\\\inT` 原样印进 PDF。\n'
    '    #    排在之后时，`\\\\in` 早已变成 `∈`，再化 `\\\\mathcal{T}` 就不粘连。\n'
    '    #    字符类用 `+`：原来的 `[A-Za-z]`（单字母）吃不下 `\\\\mathrm{CVaR}`。\n'
    '    #    `\\\\mathbf{0.70}` 也一并纳入（Q3 曾原样印出过）。\n'
    '    s = re.sub(r"\\\\(?:mathbb|mathrm|mathcal|mathbf)\\{([A-Za-z0-9.]+)\\}", r"\\1", s)\n'
)


def patch(path):
    s = io.open(path, encoding="utf-8").read()
    if OLD not in s:
        print("  ⚠️ %s：未找到预期片段，跳过" % path)
        return
    s = s.replace(OLD, NEW)
    io.open(path, "w", encoding="utf-8").write(s)
    print("  %s：已把 mathrm 系列挪到符号表之后，并纳入 mathbf" % path)


if __name__ == "__main__":
    for p in sys.argv[1:]:
        patch(p)
