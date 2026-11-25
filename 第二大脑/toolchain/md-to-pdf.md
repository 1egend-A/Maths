> 状态：2026-09-21 · Markdown → A4 PDF 自建链路（本机唯一可用方案）

# Markdown → PDF

## 为什么自建

本机没有 pandoc / LaTeX / wkhtmltopdf / weasyprint / reportlab / libreoffice；`pdfinfo`、`pdftoppm` 也没有。唯一可用的渲染器是 Chrome，唯一可靠的版面测量工具是 PyMuPDF（`import fitz`）。

链路：自写 markdown-lite → HTML + CSS → `chrome --headless=new --no-pdf-header-footer --no-sandbox --print-to-pdf=out.pdf file:///...` → PyMuPDF 后处理。

## 四条硬约束

1. **图片必须 base64 内嵌**，否则 `file://` 的跨目录限制会把图吃掉。
2. **Chrome 不支持 CSS 分页页脚**。「第 N 页 / 共 M 页」用 PyMuPDF 逐页盖：内置字体 `china-ss` 离线可用，`fitz.get_text_length(txt, fontname="china-ss")` 求宽居中。比走 CDP `Page.printToPDF` 省事得多。
3. **公式用 MathJax 3 离线 `tex-svg.js`**（2.1 MB，与 HTML 同目录）。SVG 输出无字体依赖，但公式在文本抽取里是空的——「扫反斜杠找未渲染宏」对 SVG 公式看不到内容，只能渲染 PNG 目视。
4. **HTML 里必须转义 `<` `>` `&`**：数学里的 `\(<c^*\)` 会被 Chrome 当标签吃掉，症状是抽出来只剩 `\(`。

## 渲染坑（改写解析器前必读）

- **硬换行的源行必须并成一个 `<p>`**：否则跨行的 `**粗体**` 匹配不上、星号直接印在纸上，还白扔段间距。引用块和列表项同样要并。
- **`\frac` 必须在 `\text{}` / `\mathbb{}` 之后处理**，否则分子里夹花括号，整条公式原样漏出来。
- **`\hat` 的花括号可省、可包多字母**（`\hat N_t`、`\hat{PV}` 都要认）。
- **不带花括号的上下标**（`N^s_t`、`G_t^*`）要单独一条正则。
- **宏替换顺序很要命**：`\mathcal/\mathbb/\mathrm/\mathbf` 必须排在符号表循环**之后**，否则 `\in\mathcal{T}` 会先粘成 `\inT`，符号表断言失败，连带把 `\in` 吞掉。
- **不支持的宏不报错，反斜杠直接印在纸上**。所以体检判据定为：**正文出现任何反斜杠即判瑕疵**，不要用枚举名单——枚举法必然被名单外的第一个案例击穿。
- **不要给 `*x*` 加「单星号变粗体」规则**，会跨 `^*` 配对把整段数学吞掉；强调统一写 `**x**`。

## 版面配比（实测）

- 正文 10.2 pt / 行距 1.50 / 页边距 2.0 cm 是「不挤又装得下」的那一档；10.0/1.45 偏挤，10.3/1.52 起就多一页。**非单调，别插值猜，直接扫**。
- **页数瓶颈几乎从不是字数，而是图的断页留白**。`page-break-inside: avoid` 会让图把上一页留出 5–7 cm 空白。
- 收页顺序：**先收图宽**（92% → 78% 这一档），再缩短图注到一行，最后才考虑删字。一次把 9 页（末页 9.6% 填充）收回 8 页（末页 86%），信息量不掉。
- 量版面：以 dpi≈50 渲染灰度，逐行扫最后着墨行，算每页填充率。
- 交付前删干净临时产物（`_probe.pdf`、`_pg*.png`）。

## 复用方式

把整个项目文件夹一起搬即可，脚本用 `dirname(abspath(__file__))` 定位图片，不需要改路径。

## 2026-11-25 补：表格、插图、代码块与行内 `$` 公式

- 旧配置只认 `\(...\)` 行内公式；正文若写 `$...$`，MathJax 不渲染，PDF 里原样留下美元符号。在 `tex.inlineMath` 加 `['$','$']` 即可，`$$` display 仍会优先匹配。
- 表格：把 `<table>` 与表注 `.tcap` 一起包进 `page-break-inside: avoid` 的容器；否则表格能挤进上页、表注被推到下一页，出现"表注孤行"。
- 插图：`<figure>` + base64 内嵌 + `page-break-inside: avoid`，实测稳定。
- 伪代码用 `<pre>` + 等宽字体；希腊字母直接用 Unicode（α、ε、η、Σ、←），比 ASCII 记号可读得多。
- 段落在页尾只剩一两个字时，Chrome 不一定遵守 `orphans/widows`；必要时要手工拆句或调整分页。
