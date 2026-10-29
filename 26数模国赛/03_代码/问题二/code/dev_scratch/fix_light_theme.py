# -*- coding: utf-8 -*-
"""fix_light_theme.py —— 把 q2_visualization.m 的配图主题钉成【浅色白底】。

背景：R2025a 起 figure 多了 Theme 属性，默认**跟随 MATLAB 桌面主题**。桌面开深色时，
即使写了 figure('Color','w')，axes 底色与文字仍被主题刷成深底浅字，导出的 PNG 就是黑底图。
实测：GraphicsTheme('BaseColorStyle','dark') 能把新 axes 默认成 Color=0.07/字符 0.85（复现黑底）；
而**显式设置能压住主题**。主题【不支持】set(groot,'defaultFigureTheme',...)（MATLAB 明确报错），
所以只能逐图钉 —— 见新增的 newfig()。

用文件落盘而非 heredoc：正则里有反斜杠，heredoc 会折损（踩过坑）。
"""
import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(os.path.dirname(HERE), 'q2_visualization.m')

# ---- 1) 颜色默认值（第二层保险；全部实测为合法 groot 名）----
ANCHOR = "figDir = [qc.outdir 'figures\\'];\nif ~isfolder(figDir), mkdir(figDir); end\n"

DEFAULTS = ANCHOR + r"""
%% ---------- 强制浅色白底（不依赖任何人的 MATLAB 桌面主题）----------
% R2025a 起 figure 的 Theme 属性默认跟随桌面主题：桌面开深色时，axes 底色与文字会被刷成
% 深底浅字，导出即【黑底图】——本队曾整批踩中。主题不支持 set(groot,'defaultFigureTheme',…)
% （MATLAB 明确报错“Theme 属性中不允许存在默认值”），故每张图建好后逐图钉，见 newfig()。
% 下面这组颜色默认值是第二层保险：实测【显式设置能压住主题】。
set(groot, 'defaultFigureColor',            'w');
set(groot, 'defaultAxesColor',              'w');
set(groot, 'defaultAxesXColor',             [0.13 0.13 0.13]);
set(groot, 'defaultAxesYColor',             [0.13 0.13 0.13]);
set(groot, 'defaultAxesZColor',             [0.13 0.13 0.13]);
set(groot, 'defaultAxesGridColor',          [0.55 0.55 0.55]);
set(groot, 'defaultAxesGridColorMode',      'manual');
set(groot, 'defaultAxesGridAlpha',          0.35);
set(groot, 'defaultAxesMinorGridColor',     [0.75 0.75 0.75]);
set(groot, 'defaultAxesMinorGridColorMode', 'manual');
set(groot, 'defaultAxesMinorGridAlpha',     0.25);
set(groot, 'defaultTextColor',              [0.10 0.10 0.10]);
set(groot, 'defaultLegendTextColor',        [0.10 0.10 0.10]);
set(groot, 'defaultLegendColor',            'none');
set(groot, 'defaultLegendEdgeColor',        [0.60 0.60 0.60]);
set(groot, 'defaultColorbarColor',          'w');
"""

# ---- 2) 局部函数 newfig()：逐图钉主题 ----
NEWFIG = r"""function f = newfig(pos)
% NEWFIG  新建【白底】图：把图形主题钉成 light，再把底色显式覆白。
% 背景：R2025a+ 的 figure.Theme 默认跟随 MATLAB 桌面主题，别人桌面是深色时导出即黑底图。
% 主题不支持设全局默认值，只能逐图钉。两步都要：先钉主题（axes 文字才会是深色），
% 再覆底色（防止主题把 Color 拉走）。显式设置实测能压住主题。
f = figure('Color', 'w', 'Position', pos);
try
    f.Theme = matlab.graphics.theme.GraphicsTheme('BaseColorStyle', 'light');
catch
    % 老版本没有 Theme 机制；颜色默认值仍由上面的 groot 设置兜底
end
set(f, 'Color', 'w');
end


"""


def main():
    raw = io.open(SRC, 'rb').read()
    for enc in ('utf-8', 'gbk'):
        try:
            s = raw.decode(enc)
            break
        except UnicodeDecodeError:
            s = None
    if s is None:
        print('无法解码源文件'); return 1

    if 'newfig(' in s:
        print('已经打过补丁了，跳过'); return 0

    # 1) 插入颜色默认值
    assert s.count(ANCHOR) == 1, '锚点命中 %d 次' % s.count(ANCHOR)
    s = s.replace(ANCHOR, DEFAULTS)

    # 2) figure(...) -> newfig(...)
    pat = re.compile(r"figure\('Color','w','Position',(\[[^\]]*\])\)")
    n_fig = len(pat.findall(s))
    s = pat.sub(r"newfig(\1)", s)

    # 3) 插入 newfig 局部函数（放在 savepng 之前）
    anchor2 = "function savepng(f, name)"
    assert s.count(anchor2) == 1, 'savepng 锚点命中 %d 次' % s.count(anchor2)
    s = s.replace(anchor2, NEWFIG + anchor2)

    io.open(SRC, 'w', encoding=enc, newline='').write(s)
    print('已改写 %s' % SRC)
    print('  插入颜色默认值 1 处；figure() -> newfig() 共 %d 处；新增 newfig() 局部函数' % n_fig)
    return 0


if __name__ == '__main__':
    sys.exit(main())
