# -*- coding: utf-8 -*-
"""PATCH_MEASURE_PDF  让体检脚本能查出"未渲染的 LaTeX 宏"这一类瑕疵。

原实现只枚举 `**` / `$$` / `\\text` / `\\frac` / `\\eta` 五个词。问题在于
本渲染器对不支持的宏【不报错】，而是把反斜杠原样印进 PDF —— 实测漏过
`\\mathrm{CVaR}`、`\\in`、`\\bar`、`\\equiv`、`\\#`、`\\%` 共 15 处，
而 `measure_pdf.py` 仍然报「瑕疵: 无」。**枚举法对"未知的未知"无效。**

改为：**凡正文出现反斜杠，一律判瑕疵**，并打印前几处的上下文便于定位。
（正文是中文 + 数字 + 已渲染的公式，正常情况不该有任何反斜杠。）

用法：python patch_measure_pdf.py <measure_pdf.py> [...]
"""
import io, sys

OLD = (
    '    for token, what in (("**", "未渲染的粗体标记"),\n'
    '                        ("$$", "未渲染的行间公式"),\n'
    '                        ("\\\\text", "未渲染的 LaTeX \\\\text"),\n'
    '                        ("\\\\frac", "未渲染的 LaTeX \\\\frac"),\n'
    '                        ("\\\\eta", "未渲染的 \\\\eta")):\n'
    '        n = txt.count(token)\n'
    '        if n:\n'
    '            bad.append("%s x%d（%s）" % (token, n, what))\n'
)

NEW = (
    '    for token, what in (("**", "未渲染的粗体标记"),\n'
    '                        ("$$", "未渲染的行间公式")):\n'
    '        n = txt.count(token)\n'
    '        if n:\n'
    '            bad.append("%s x%d（%s）" % (token, n, what))\n'
    '    # ⚠️ 关键补充：渲染器只支持 mathtext 的一个子集，不支持的宏【不报错】，\n'
    '    #    而是把反斜杠原样印进版面（实测漏过 \\\\mathrm{CVaR}、\\\\in、\\\\bar、\n'
    '    #    \\\\equiv、\\\\#、\\\\% 共 15 处），旧版仍报「瑕疵: 无」。\n'
    '    #    枚举法查不出"未知的未知"，故改为【凡有反斜杠一律判瑕疵】。\n'
    '    #    正文是中文 + 数字 + 已渲染的公式，正常情况下不该出现任何反斜杠。\n'
    '    idxs = [i for i, c in enumerate(txt) if c == "\\\\"]\n'
    '    if idxs:\n'
    '        ctx = " | ".join(txt[max(0, i - 22):i + 14].replace("\\n", " ")\n'
    '                         for i in idxs[:4])\n'
    '        bad.append("残留反斜杠 x%d（疑似未渲染的 LaTeX）：%s" % (len(idxs), ctx))\n'
)


def patch(path):
    s = io.open(path, encoding="utf-8").read()
    if OLD not in s:
        print("  ⚠️ %s：未找到预期片段，跳过" % path)
        return
    io.open(path, "w", encoding="utf-8").write(s.replace(OLD, NEW))
    print("  %s：已改为「凡有反斜杠即判瑕疵」" % path)


if __name__ == "__main__":
    for p in sys.argv[1:]:
        patch(p)
