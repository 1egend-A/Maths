> 状态：2026-11-23 · 本机环境与工具踩坑速查（换机器时先读这一节）

# 环境

## Python

| 环境 | 用途 | 关键包 |
|---|---|---|
| `C:\ProgramData\anaconda3` | base，通用科学栈 | numpy / scipy / matplotlib / pandas / openpyxl / PyMuPDF |
| `C:\ProgramData\anaconda3\envs\ai_start_py11` | 只放 PyMuPDF | fitz（无 numpy） |
| `%USERPROFILE%\.conda\envs\exp` | 量化 / 主项目 | numpy 2.2 / pandas / akshare / torch |

- **`python` 在 PATH 上是商店存根，静默失败（exit 49、零输出）**——一律用绝对路径。
- **装包必加清华镜像**：`pip install <包> -i https://pypi.tuna.tsinghua.edu.cn/simple`。国际线路实测 3–5 分钟，镜像几秒。
- 往 base 混装 conda-forge 包会升降级现有科学栈，优先用 pip。
- `-I` 隔离模式会把脚本目录移出 `sys.path`：流水线脚本若只插了项目根，加 `-I` 会 ModuleNotFoundError。只在读外部数据、防同名模块劫持时才加。
- 中文输出：`PYTHONIOENCODING=utf-8`；别设 `PYTHONUTF8=1`（某些 conda 环境有 GBK `.pth`，会崩在 site 初始化）。
- matplotlib 中文：设 `font.sans-serif = [SimHei, Microsoft YaHei]` 且 `axes.unicode_minus = False`，否则方框。
- ffmpeg：`pip install imageio-ffmpeg`，脚本里 `plt.rcParams["animation.ffmpeg_path"] = imageio_ffmpeg.get_ffmpeg_exe()`。

## MATLAB

| 症状 | 根因 | 解法 |
|---|---|---|
| `readtable` 全不能用，`T.新列=` 报错 | 工具箱里 `@tabular/dotAssign.m` 被演示脚本覆盖 | 用 `readcell` / `readmatrix` / `writecell`；或写 `fig_readtable.m` 包装兜底 |
| 导出图黑底浅字 | R2025a 起 `figure.Theme` 跟随桌面主题 | `f.Theme = GraphicsTheme('BaseColorStyle','light')` 再 `set(f,'Color','w')`；逐图钉，主题设不了全局默认 |
| 新字体装不上、静默回落宋体 | 只认 `C:\Windows\Fonts` 扫描；可变字体只取到一个实例 | 先 `listfonts` 找同谱系替代（中文衬线可用华文宋体）；验生效要读 PDF 内嵌字体名 |
| 新建 `.m` 解析不到，老文件正常 | toolbox 路径缓存过期 | `rehash toolboxcache`，写进入口脚本开头 |
| `boxplot` / `quantile` 用不了 | 同一损坏文件 / 无工具箱 | 自绘盒须图 + 线性插值分位数 |

- `matlab -batch` 输出是 GBK：`2>&1 | iconv -f GBK -t UTF-8`；报告文件用 `fopen(fid,'w','n','UTF-8')`。
- 局部函数有独立工作区，要往外累加须用嵌套函数。
- 函数名不能以 `_` 开头。
- `sparse` 会累加重复坐标，声明行数必须覆盖最大行号。
- `readmatrix` 会把表头的「日分数」（0.0069 这类）当数据读进，导致最小值、近零计数全错——先 `readcell` 再显式丢表头。

## LaTeX / Overleaf

- **中文工程先查四条**：编译器必须是 XeLaTeX（魔法注释不认，用 `latexmkrc` 钉死）；`fontset=windows` 必挂，改 `fandol`；Windows 字体名硬写会中止编译；图路径跨目录必 File not found。
- **静默丢字**：用「字符类交给宋体」的声明换到 Fandol 后没有对应字形，编译成功但符号消失 ⇒ 逐个 `\newunicodechar` 映射到数学模式。
- **假超时**：表格列宽 `\dimexpr` 写法撞 calc，报错后卡死不退出。统一改成 calc 写法 `p{(...)*\real{0.0769}}`。同一份文档两种写法混用时，会「内容少的编不过、内容多的编得过」。
- **压缩页数**：先调行距（1.38 → 1.28 视觉等同五号单倍，31 页回 30 页、一个字不删）再删字；按章并行改写 + 数字双向守恒校验（新 ⊆ 旧、旧 − 新 = 0）。
- **打包上传**：别用 `Compress-Archive`（目录分隔符写成 `\`，Linux 解压后图全丢），用 .NET `ZipArchive` 显式换 `/`；中文路径先复制到纯 ASCII 临时目录。
- 数模竞赛论文统一套 `cumcmthesis` 模板：四边 25mm、行距 1.38、公式手工 `\tag{n}`、三线表、摘要每问一段带核心数字。

## PDF 与文档

- 本机无 pandoc / LaTeX / wkhtmltopdf / libreoffice；**Chrome headless** 是唯一 Markdown→PDF 链路。
- `pdftotext -layout` 会把中文全丢成空格——**去掉 `-layout`**，加 `-enc UTF-8`。
- PyMuPDF（fitz）可渲染、可提取、可盖页码（内置中文字体 `china-ss`，离线可用）。
- 大量数字核验走 fitz 文本层 + 归一化匹配；注意页脚数字粘连、目录页抢命中。
- 交付前删干净临时产物（`_probe.pdf`、`_pg*.png`），成果目录只放成果。

## Windows / PowerShell

- 给脚本的 `.ps1` 一律**纯 ASCII**：本机 PowerShell 5.1 把无 BOM 的 UTF-8 按 GBK 读，中文注释可能吞掉下一行，表现为「某个变量莫名是空值」。必须中文就存 UTF-8 with BOM。
- 中文路径下跑 perl/cmd 驱动的安装器（如 TeX Live）必挂 → 在用户目录建**ASCII 目录联接**再启动：`New-Item -ItemType Junction`。
- `mklink /J` 处理中文路径会报错，必须用 PowerShell。
- 目录联接不是副本：打包时别从联接的上一层递归，会把文件数算两遍。

## Git / 网络

- 网络不稳时 `git ls-remote` / `push` 可能超时；`api.github.com` 比 `github.com` 稳。
- 本机凭据存在 Windows 凭据管理器，`credential.helper=manager`；没有 `gh` 时可用 API + 凭据读取。
- 提交身份只写仓库级配置，不动全局。
- `git switch -c X origin/main` 会把上游绑成 `origin/main`，之后裸 `git push` 会直推主分支 —— 推新分支一律用显式 refspec。
- 删除文件/目录前先确认它是不是目录联接（删链接不动真文件，但工具链会找不到目录）。

## libsvm / SVM 实验（2026-11-25）

- 官方 Windows 预编译包拿不到时（官网镜像 502、GitHub 被重置），用 `pip install libsvm-official`（清华镜像）：同一 C++ 内核的 Python 绑定，`svm_train/svm_predict` 与命令行语义一致，默认 γ = 1/num_features、coef0 = 0。
- `svm-scale` 的默认语义（源码 svm-scale.c 确认）：特征缩到 [−1,1]；参数只用训练集统计；**常数列整列删除**；特征值按 `%g` 输出 6 位有效数字；零元素省略；目标值默认不缩放。
- 预计算核（`-t 4`）：libsvm 按**节点位置**取核值（`x[(int)(y->value)].value`）。稠密矩阵转 scipy 稀疏时显式零会被丢掉，第 0 个占位节点（值 0）一丢就整行错位——必须手工构造保留显式零的 CSR。症状：验证误差突然变成 62%、预测全判一类。
- 自查配方：先用线性核做"内置核 vs 预计算核"小样本对照，准确率一致后再接自定义核。
