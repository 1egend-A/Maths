function figFiles = q3_visualization(R, F, qc, D)
% Q3_VISUALIZATION  问题三论文配图（全部可用本脚本一键复现）
%
% 规范遵循《论文配图建议.md》与问题二的既有做法（体例逐条对齐，便于四问图集统一）：
%   · 字体：中文用 Microsoft YaHei（显式设置，不依赖默认，避免中文方框）
%   · 导出：exportgraphics(..., 'Resolution', 300)，文件 fig_q3_<内容>.png
%   · 配色：同一物理量全文同色 —— 购电=蓝、放电=橙、光伏=黄绿、充电=紫、储电量=深灰
%           不依赖单一颜色区分，叠加曲线一律线型/线宽分开
%   · 线宽 >= 1.5，字号 >= 9pt，坐标轴必带单位
%   · 图内叠加多条曲线时，颜色不够就【用线型区分】，不新造颜色
%
% ⚠️ 黑底图防线（本机踩过，整批中招）：R2025a+ 的 figure.Theme 跟随桌面主题，
%    桌面开深色时导出即黑底。故每张图都走 newfig()，且先钉 groot 的颜色默认值。
%
% 出图清单（对应配图建议的 Q3 条目）：
%   fig_q3_rolling         四阶段滚动决策的时间轴与作用域（本问的信息结构图解）⭐
%   fig_q3_penalty         非对称罚则下的分段成本曲线与三条临界分位          ⭐
%   fig_q3_adjust          调整前/调整后的购电量对比与效果（逐日 + 月度）     ⭐
%   fig_q3_typical_day     典型日（调整日）完整调度剖面
%   fig_q3_ablation        预报时刻的边际价值（消融实验，回答必答开放题）      ⭐
%   fig_q3_downscale       降尺度方法对比：精度 vs 费用（非线性关系）
%   fig_q3_monthly         月度汇总（购电量、紧急购电量、费用、弃电）
%
% 用法：q3_visualization()  或  q3_visualization(R, F, qc, D)

if nargin < 4 || isempty(D)
    D = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码\out\data.mat').D;
end
if nargin < 3 || isempty(qc), qc = q3_config(); end
if nargin < 2 || isempty(F), F = q3_forecast(D, qc); end
if nargin < 1 || isempty(R)
    f = [qc.outdir 'q3_solution.mat'];
    assert(isfile(f), '找不到 %s，请先跑 run_q3_all', f);
    R = load(f).R;
end

figDir = [qc.outdir 'figures\'];
if ~isfolder(figDir), mkdir(figDir); end

%% ---------- 强制浅色白底（不依赖任何人的 MATLAB 桌面主题）----------
set(groot, 'defaultFigureColor',            'w');
set(groot, 'defaultAxesColor',              'w');
set(groot, 'defaultAxesXColor',             [0.13 0.13 0.13]);
set(groot, 'defaultAxesYColor',             [0.13 0.13 0.13]);
set(groot, 'defaultAxesZColor',             [0.13 0.13 0.13]);
set(groot, 'defaultAxesGridColor',          [0.55 0.55 0.55]);
set(groot, 'defaultAxesGridColorMode',      'manual');
set(groot, 'defaultAxesGridAlpha',          0.35);
set(groot, 'defaultTextColor',              [0.10 0.10 0.10]);
set(groot, 'defaultLegendTextColor',        [0.10 0.10 0.10]);
set(groot, 'defaultLegendColor',            'none');
set(groot, 'defaultLegendEdgeColor',        [0.60 0.60 0.60]);
set(groot, 'defaultAxesFontName', 'Microsoft YaHei');
set(groot, 'defaultTextFontName', 'Microsoft YaHei');
set(groot, 'defaultAxesFontSize', 10);
set(groot, 'defaultAxesColorOrder', [ ...
    0.00 0.32 0.75;    % 1 计划购电  蓝
    0.92 0.49 0.10;    % 2 调整购电  橙
    0.55 0.72 0.10;    % 3 光伏      黄绿
    0.49 0.18 0.56;    % 4 充电      紫
    0.35 0.35 0.38]);  % 5 储电量    深灰

C_GRID = [0.00 0.32 0.75];  C_ADJ = [0.92 0.49 0.10];
C_PV = [0.55 0.72 0.10];    C_CHG = [0.49 0.18 0.56];
C_SOC = [0.20 0.20 0.22];   C_EM = [0.80 0.20 0.20];
C_PRC = [0.55 0.55 0.55];   C_NEU = [0.30 0.30 0.30];

dt = qc.dt;  nT = size(R.G, 2);  nd = numel(R.date);
th = (0:nT)/6;                       % 小时轴，145 点（含 24:00）
figFiles = {};

%% ============ 图 8-1：四阶段滚动决策的时间轴与作用域 ============
% 本图是「信息结构」的图解：横轴一天，四条横带表示四个发布时刻各自【能改哪些槽】。
f = newfig([80 80 900 420]);
hold on;
% 已执行（不可改）的背景带
patch([0 6 6 0], [0 0 0.16 0.16], [0.90 0.90 0.90], 'EdgeColor', 'none');
text(3, 0.08, '已执行，不可改', 'HorizontalAlignment', 'center', ...
    'FontSize', 9, 'Color', [0.35 0.35 0.35]);
bandCol = {C_GRID, C_ADJ, C_PV, C_CHG};
bandLb  = {'\tau=0:00  定计划 G_t（全天 144 槽）', ...
           '\tau=6:00  调整 37..144 槽', ...
           '\tau=12:00 调整 73..144 槽', ...
           '\tau=18:00 调整 109..144 槽'};
for j = 1:4
    a0 = (j-1)*6;  a1 = 24;  y0 = 0.84 - (j-1)*0.19;
    patch([a0 a1 a1 a0], [y0 y0 y0+0.14 y0+0.14], bandCol{j}, ...
        'EdgeColor', 'none', 'FaceAlpha', 0.85);
    text(a0 + 0.15, y0 - 0.055, bandLb{j}, 'FontSize', 9, 'Color', [0.15 0.15 0.15]);
end
xline(6, '--', 'Color', C_ADJ, 'LineWidth', 1.2);
xline(12, '--', 'Color', C_PV, 'LineWidth', 1.2);
xline(18, '--', 'Color', C_CHG, 'LineWidth', 1.2);
xlim([0 24]);  ylim([-0.05 1.02]);
xlabel('时刻（h）');  yticks([]);
title('图 8-1　四阶段滚动决策：每个发布时刻只能修改尚未执行的时段', 'FontSize', 11);
box on;  grid on;
figFiles{end+1} = savepng(f, [figDir 'fig_q3_rolling.png']);

%% ============ 图 8-2：非对称罚则下的分段成本曲线与三条临界分位 ============
% 本问的核心机制图：把「少买 0.5 倍 / 多买 1.5 倍 / 不够则 5 倍紧急」三段成本
% 画在同一条量纲上，报童临界分位就从曲线的斜率比里直接读出来。
f = newfig([80 80 900 460]);
hold on;
gm = linspace(0, 1.6, 600);          % 以"计划量"为 1 的相对尺度
q = gm;
cost = zeros(size(gm));
for i = 1:numel(gm)
    a = gm(i);
    cost(i) = min(1, a) + qc.kUnder*max(0, 1-a) + qc.kOver*max(0, a-1);
end
plot(gm, cost, '-', 'Color', C_GRID, 'LineWidth', 2.0);
plot(gm, gm, '--', 'Color', C_PRC, 'LineWidth', 1.5);
% 三条临界分位对应的相对调整量（用 0.5/0.7/0.9 的示意位置标在曲线上）
xq = [0.55 0.78 1.00];
lbq = {sprintf('A=Q_{0.7} 向上调整（边际 %.1f 倍价）', qc.kOver), ...
       'G=Q_{0.8} 计划量（问题二同构）', ...
       sprintf('A=Q_{0.9} 向下调整（边际 %.1f 倍价）', qc.kUnder)};
colq = {C_ADJ, C_GRID, C_CHG};
for i = 1:numel(xq)
    xline(xq(i), ':', 'Color', colq{i}, 'LineWidth', 1.3);
end
plot(xq, interp1(gm, cost, xq), 'o', 'MarkerSize', 7, ...
    'MarkerFaceColor', 'w', 'MarkerEdgeColor', 'k', 'LineWidth', 1.2);
xlabel('调整后购电量 A_t  /  情景净需求 Q_t（相对量）');
ylabel('单位电价下的成本（相对量）');
title('图 8-2　非对称罚则的分段成本：斜率比给出三条临界分位 0.7 / 0.8 / 0.9', 'FontSize', 11);
legend([{'分段成本曲线'}, {'45° 参考线'}, lbq], 'Location', 'northwest', 'FontSize', 9);
xlim([0 1.6]);  ylim([0 2.0]);  grid on;  box on;
figFiles{end+1} = savepng(f, [figDir 'fig_q3_penalty.png']);

%% ============ 图 8-3：调整前 / 调整后的购电量对比 ============
% 上半：逐日「只定计划」与「滚动调整」的费用对比；下半：月度调整前后购电量
f = newfig([80 80 1000 520]);
tl = tiledlayout(2,1, 'TileSpacing', 'compact');
nexttile; hold on;
cNo = R.costNoAdj;  cAd = R.Sadj;
plot(R.date, cNo, '-', 'Color', C_GRID, 'LineWidth', 1.4);
plot(R.date, cAd, '-', 'Color', C_ADJ, 'LineWidth', 1.4);
dSave = cNo - cAd;
plot(R.date, dSave, '-', 'Color', C_NEU, 'LineWidth', 1.0);
yline(0, ':', 'Color', [0.5 0.5 0.5]);
ylabel('费用（元/天）');
legend({'只按 0:00 计划执行', '四阶段滚动调整后', '逐日节省（可负）'}, ...
    'Location', 'northwest', 'FontSize', 9);
title('图 8-3　滚动调整的逐日效果（节省为负的日子是分位对冲的固有代价，见正文）', 'FontSize', 11);
grid on;  box on;

nexttile; hold on;
mo = month(R.date);  mm = unique(mo);
qNo = zeros(size(mm));  qAd = zeros(size(mm));
for i = 1:numel(mm)
    s = (mo == mm(i));
    qNo(i) = sum(R.qPlan(s));
    qAd(i) = sum(R.qAdj(s));
end
b = bar(mm, [qNo qAd], 'grouped');
b(1).FaceColor = C_GRID;  b(2).FaceColor = C_ADJ;
xlabel('月份');  ylabel('月度购电量（kWh）');
legend({'计划购电量', '调整后购电量'}, 'Location', 'northwest', 'FontSize', 9);
xticks(mm);  xticklabels(compose('%d月', mm));
grid on;  box on;
figFiles{end+1} = savepng(f, [figDir 'fig_q3_adjust.png']);

%% ============ 图 8-4：典型日完整调度剖面 ============
% 选「调整最活跃的一天」，把 G/A 两条购电量曲线、充放电、SOC、实时净负荷画在一起。
segLen = sum(abs(R.A - R.G) > 1e-6, 2);
[~, kd] = max(segLen);
f = newfig([80 80 1000 620]);
tl = tiledlayout(3,1, 'TileSpacing', 'compact');

nexttile; hold on;
plot(th, [R.G(kd,:) R.G(kd,end)], '-', 'Color', C_GRID, 'LineWidth', 1.6);
plot(th, [R.A(kd,:) R.A(kd,end)], '-', 'Color', C_ADJ, 'LineWidth', 1.6);
plot(th, [F.Nact(R.dayIdx(kd),:) F.Nact(R.dayIdx(kd),end)], '-', ...
    'Color', C_PRC, 'LineWidth', 1.2);
for j = 2:4
    xline(6*(j-1), '--', 'Color', [0.6 0.6 0.6], 'LineWidth', 1.0);
end
ylabel('功率（kW）');
legend({'计划购电量 G_t', '调整后购电量 A_t', '实际净负荷'}, ...
    'Location', 'northwest', 'FontSize', 9);
title(sprintf('图 8-4　典型日调度剖面：%s（调整覆盖 %d 个时段）', ...
    string(R.date(kd)), segLen(kd)), 'FontSize', 11);
grid on;  box on;

nexttile; hold on;
area(th, [max(0,R.C(kd,:)) 0], 'FaceColor', C_CHG, 'FaceAlpha', 0.55, 'EdgeColor', 'none');
area(th, [-max(0,R.D(kd,:)) 0], 'FaceColor', C_ADJ, 'FaceAlpha', 0.55, 'EdgeColor', 'none');
plot(th, [R.C(kd,:) 0], '-', 'Color', C_CHG, 'LineWidth', 1.5);
plot(th, [-R.D(kd,:) 0], '-', 'Color', C_ADJ, 'LineWidth', 1.5);
yline(0, '-', 'Color', [0.4 0.4 0.4]);
ylabel('充放电功率（kW）');
legend({'充电', '放电'}, 'Location', 'northwest', 'FontSize', 9);
grid on;  box on;

nexttile; hold on;
yyaxis left;
plot(th, [R.Soc(kd,:) R.Soc(kd,end)], '-', 'Color', C_SOC, 'LineWidth', 1.8);
ylabel('储电量（kWh）');  ylim([qc.S_min*0.9 qc.S_max*1.05]);
yyaxis right;
plot(th, [R.price(kd,:) R.price(kd,end)], '-', 'Color', C_PRC, 'LineWidth', 1.3);
ylabel('电价（元/kWh）');
xlabel('时刻（h）');  xlim([0 24]);
legend({'储电量', '电价'}, 'Location', 'northwest', 'FontSize', 9);
grid on;  box on;
figFiles{end+1} = savepng(f, [figDir 'fig_q3_typical_day.png']);

%% ============ 图 8-5：预报时刻的边际价值（消融实验）============
% 必答开放题的正面回答：把「多引入一个预报时刻能省多少」画出来，并标出塌缩点。
fa = [qc.outdir 't_q3_ablation.mat'];
if isfile(fa)
    S = load(fa);
    if isfield(S, 'costG') && isfield(S, 'margG'), marg = S.margG; costG = S.costG;
    elseif isfield(S, 'costG'), marg = -diff(S.costG); costG = S.costG;
    else, marg = []; costG = []; end
else
    marg = []; costG = [];
end
if ~isempty(marg)
    f = newfig([80 80 900 440]);
    xb = 1:numel(marg);
    bb = bar(xb, marg, 0.55, 'FaceColor', C_GRID, 'EdgeColor', 'none');
    hold on;
    for i = 1:numel(marg)
        text(xb(i), marg(i), sprintf('%.0f 元', marg(i)), ...
            'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'FontSize', 9);
    end
    plot(xb, marg, '-o', 'Color', C_ADJ, 'LineWidth', 1.6, 'MarkerFaceColor', 'w');
    yline(0, '-', 'Color', [0.4 0.4 0.4]);
    set(gca, 'YScale', 'log');
    xlabel('新增的预报发布时刻');
    ylabel('边际节省（元，对数轴）');
    xticklabels({'6:00', '12:00', '18:00'});
    title('图 8-5　逐步引入预报时刻的边际价值：18:00 一次调整的增量塌缩到 405.60 元', ...
        'FontSize', 11);
    grid on;  box on;
    figFiles{end+1} = savepng(f, [figDir 'fig_q3_ablation.png']);

    % 附一张累计曲线（同图另存，供正文择用）
    f = newfig([80 80 900 420]);
    hold on;
    plot(0:numel(costG)-1, costG, '-o', 'Color', C_GRID, 'LineWidth', 1.8, ...
        'MarkerFaceColor', 'w');
    plot([0 numel(costG)-1], [costG(1) costG(end)], '--', 'Color', C_NEU, 'LineWidth', 1.2);
    for i = 1:numel(costG)
        text(i-1, costG(i), sprintf('%.0f', costG(i)), 'FontSize', 8, ...
            'HorizontalAlignment', 'left', 'VerticalAlignment', 'bottom');
    end
    set(gca, 'YScale', 'log');
    xlabel('使用的预报时刻个数');  ylabel('总费用（元，对数轴）');
    xticks(0:numel(costG)-1);
    xticklabels({'仅0:00','+6:00','+12:00','+18:00'});
    title('图 8-5b　预报时刻消融的总费用曲线', 'FontSize', 11);
    grid on;  box on;
    figFiles{end+1} = savepng(f, [figDir 'fig_q3_ablation_cost.png']);
else
    fprintf('  （未找到 %s，跳过图 8-5）\n', fa);
end

%% ============ 图 8-6：降尺度方法对比 —— 精度 vs 费用 ============
fd = [qc.outdir 't_q3_downscale.mat'];
if isfile(fd)
    S = load(fd);
    if isfield(S, 'Tab')
        T = S.Tab;
        vn = T.Properties.VariableNames;
        vC = find(contains(vn, '费用'), 1);
        vR = find(contains(vn, 'RMSE'), 1);
        if ~isempty(vC) && ~isempty(vR)
            nm = string(T{:,1});
            f = newfig([80 80 820 460]);
            hold on;
            for i = 1:numel(nm)
                plot(T{i,vR}, T{i,vC}, 'o', 'MarkerSize', 11, ...
                    'MarkerFaceColor', C_GRID, 'MarkerEdgeColor', 'w', 'LineWidth', 1.2);
                text(T{i,vR}, T{i,vC}, sprintf('  %s', nm(i)), 'FontSize', 9, ...
                    'VerticalAlignment', 'middle');
            end
            xlabel('10 分钟级 RMSE（kW）—— 越小越准');
            ylabel('总费用（元）');
            title('图 8-6　降尺度方法：精度更高的方法【费用未必更低】（判据非线性）', ...
                'FontSize', 11);
            grid on;  box on;
            figFiles{end+1} = savepng(f, [figDir 'fig_q3_downscale.png']);
        end
    end
else
    fprintf('  （未找到 %s，跳过图 8-6）\n', fd);
end

%% ============ 图 8-7：月度汇总 ============
f = newfig([80 80 1000 620]);
tl = tiledlayout(2,2, 'TileSpacing', 'compact');

nexttile; hold on;
qE = zeros(size(mm));  qC = zeros(size(mm));
for i = 1:numel(mm)
    s = (mo == mm(i));
    qE(i) = sum(R.qEm(s));  qC(i) = sum(R.curt(s))*dt;
end
b = bar(mm, [qE qC], 'grouped');
b(1).FaceColor = C_EM;  b(2).FaceColor = C_PV;
ylabel('电量（kWh）');  xlabel('月份');
legend({'紧急购电量', '弃电量'}, 'Location', 'northwest', 'FontSize', 9);
xticks(mm);  xticklabels(compose('%d月', mm));  grid on;  box on;
title('紧急购电与弃电的月度分布', 'FontSize', 10);

nexttile; hold on;
cP = zeros(size(mm));  cA = zeros(size(mm));  cE = zeros(size(mm));
for i = 1:numel(mm)
    s = (mo == mm(i));
    cP(i) = sum(R.costPlan(s));  cA(i) = sum(R.costAdj(s));  cE(i) = sum(R.costEm(s));
end
b = bar(mm, [cP cA cE], 'stacked');
b(1).FaceColor = C_GRID;  b(2).FaceColor = C_ADJ;  b(3).FaceColor = C_EM;
ylabel('费用（元）');  xlabel('月份');
legend({'计划购电费', '调整购电费', '紧急购电费'}, 'Location', 'northwest', 'FontSize', 9);
xticks(mm);  xticklabels(compose('%d月', mm));  grid on;  box on;
title('三项费用的月度构成', 'FontSize', 10);

nexttile; hold on;
rS = zeros(size(mm));
for i = 1:numel(mm)
    s = (mo == mm(i));
    rS(i) = 100*(sum(R.costNoAdj(s)) - sum(R.Sadj(s))) / sum(R.costNoAdj(s));
end
b = bar(mm, rS, 0.55, 'FaceColor', C_ADJ, 'EdgeColor', 'none');
hold on;  yline(0, '-', 'Color', [0.4 0.4 0.4]);
ylabel('滚动调整的节省率（%）');  xlabel('月份');
xticks(mm);  xticklabels(compose('%d月', mm));  grid on;  box on;
title('调整机制价值的月度稳定性', 'FontSize', 10);

nexttile; hold on;
nEm = zeros(size(mm));
for i = 1:numel(mm)
    nEm(i) = sum(R.qEm(mo == mm(i)) > 1e-6);
end
b = bar(mm, nEm, 0.55, 'FaceColor', C_EM, 'EdgeColor', 'none');
ylabel('发生紧急购电的天数');  xlabel('月份');
xticks(mm);  xticklabels(compose('%d月', mm));  grid on;  box on;
title('紧急购电的发生频率', 'FontSize', 10);
figFiles{end+1} = savepng(f, [figDir 'fig_q3_monthly.png']);

fprintf('\n  q3_visualization：已生成 %d 张图于 %s\n', numel(figFiles), figDir);
for i = 1:numel(figFiles)
    fprintf('    %s\n', figFiles{i});
end
end

% ======================================================================
function f = newfig(pos)
% NEWFIG  新建【白底】图：把图形主题钉成 light，再把底色显式覆白。
% 背景：R2025a+ 的 figure.Theme 默认跟随 MATLAB 桌面主题，别人桌面是深色时导出即黑底图。
%      Theme 属性不支持 groot 全局默认（MATLAB 明确报错），故逐图钉。
f = figure('Position', pos, 'Color', 'w');
try
    f.Theme = matlab.graphics.theme.GraphicsTheme('BaseColorStyle', 'light');
catch
    % 老版本没有 Theme 机制；颜色默认值仍由上面的 groot 设置兜底
end
set(f, 'Color', 'w');
end

% ======================================================================
function name = savepng(f, name)
% 300 dpi PNG；先关掉坐标区工具栏，否则工具栏会被一并导出到图里
ax = findall(f, 'Type', 'axes');
for a = ax', a.Toolbar.Visible = 'off'; end
exportgraphics(f, name, 'Resolution', 300);
end
