function figFiles = q4_visualization(R2, R3, qc, D, ~, ~)
% Q4_VISUALIZATION  问题四论文配图（全部可用本脚本一键复现）
%
% 规范与问题二/三逐条一致（便于四问图集统一）：字体 Microsoft YaHei、300 dpi、
% 同一物理量全文同色、线宽 >= 1.5、字号 >= 9pt、坐标轴必带单位。
% ⚠️ 黑底图防线：R2025a+ 的 figure.Theme 跟随桌面主题，每张图都走 newfig()。
%
% 出图清单：
%   fig_q4_price_structure  两套电价的结构对比（剖面 + 分布 + 峰谷比）        ⭐
%   fig_q4_typical_day      典型日调度（近零价日 / 尖峰日各一天）             ⭐
%   fig_q4_nearzero         近零价套利归因（充电能量的价格分布 + 反事实）
%   fig_q4_term_policy      跨日套利价值 vs 窗口长度（两种电价对照）          ⭐ 本问最亮
%   fig_q4_adjust           2×2 归因：附件3 预报与调整机制在逐日电价下的价值
%   fig_q4_cvar_frontier    CVaR 有效前沿（E 费用 vs 尾部风险）               ⭐
%   fig_q4_cvar_oos         样本外实付费用分布（各 λ 的箱线图）
%
% 依赖：各分析脚本的落盘 .mat（t_q4_nearzero / t_q4_term_policy / q4_cvar /
%       t_q4_adjust_value）。缺失的图会自动跳过并提示，不中断其余图。
%
% 用法：q4_visualization()

if nargin < 4 || isempty(D)
    D = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码\out\data.mat').D;
end
if nargin < 3 || isempty(qc), qc = q4_config(); end
if nargin < 1 || isempty(R2), R2 = load([qc.outdir42 'q4_solution_p2.mat'], 'R2').R2; end
if nargin < 2 || isempty(R3)
    f = [qc.outdir43 'q4_solution_p3.mat'];
    if isfile(f), R3 = load(f, 'R3').R3; else, R3 = []; end
end

figDir = [qc.outdir 'figures\'];
if ~isfolder(figDir), mkdir(figDir); end

%% ---------- 强制浅色白底 ----------
set(groot, 'defaultFigureColor', 'w');
set(groot, 'defaultAxesColor', 'w');
set(groot, 'defaultAxesXColor', [0.13 0.13 0.13]);
set(groot, 'defaultAxesYColor', [0.13 0.13 0.13]);
set(groot, 'defaultAxesGridColor', [0.55 0.55 0.55]);
set(groot, 'defaultAxesGridColorMode', 'manual');
set(groot, 'defaultAxesGridAlpha', 0.35);
set(groot, 'defaultTextColor', [0.10 0.10 0.10]);
set(groot, 'defaultLegendTextColor', [0.10 0.10 0.10]);
set(groot, 'defaultLegendColor', 'none');
set(groot, 'defaultLegendEdgeColor', [0.60 0.60 0.60]);
set(groot, 'defaultAxesFontName', 'Microsoft YaHei');
set(groot, 'defaultTextFontName', 'Microsoft YaHei');
set(groot, 'defaultAxesFontSize', 10);
set(groot, 'defaultAxesColorOrder', [ ...
    0.00 0.32 0.75; 0.92 0.49 0.10; 0.55 0.72 0.10; 0.49 0.18 0.56; 0.35 0.35 0.38]);

C_GRID = [0.00 0.32 0.75];  C_ADJ = [0.92 0.49 0.10];
C_PV = [0.55 0.72 0.10];    C_CHG = [0.49 0.18 0.56];
C_SOC = [0.20 0.20 0.22];   C_EM = [0.80 0.20 0.20];
C_PRC = [0.55 0.55 0.55];
C_A4 = [0.85 0.33 0.10];    C_A1 = [0.00 0.32 0.75];   % 附件4 / 附件1 电价

dt = qc.dt;  nT = 144;  nd = numel(R2.date);
th = (0:nT)/6;
figFiles = {};

%% ============ 图 9-1：两套电价的结构对比 ============
p1 = D.day144.price(:)';
p4 = D.actual.price(qc.dayIdx, :);
f = newfig([60 60 1060 680]);
tl = tiledlayout(2,2, 'TileSpacing', 'compact');

nexttile; hold on;
plot(th, [p1 p1(end)], '-', 'Color', C_A1, 'LineWidth', 2.0);
plot(th, [mean(p4,1) mean(p4(:,end))], '--', 'Color', C_A4, 'LineWidth', 2.0);
xlabel('时刻（h）');  ylabel('电价（元/kWh）');
legend({'附件1 典型日剖面（问题二/三）', '附件4 逐日均值剖面（问题四）'}, ...
    'Location', 'northwest', 'FontSize', 9);
title('(a) 两套电价的日内剖面', 'FontSize', 10);  grid on;  box on;

nexttile; hold on;
histogram(p4(:), 60, 'FaceColor', C_A4, 'EdgeColor', 'none', 'Normalization', 'pdf');
xline(mean(p1), '-', 'Color', C_A1, 'LineWidth', 2.0);
xlabel('电价（元/kWh）');  ylabel('概率密度');
legend({'附件4 逐日实测', sprintf('附件1 单一剖面（%.3f 元/kWh）', mean(p1))}, ...
    'Location', 'northwest', 'FontSize', 9);
title(sprintf('(b) 电价分布：峰谷比 %.0f 倍 vs %.2f 倍', ...
    max(p4(:))/min(p4(:)), max(p1)/min(p1)), 'FontSize', 10);  grid on;  box on;

nexttile; hold on;
% 逐小时均价：p4 是 nDay×144，按「天 × 6 槽 × 24 小时」重排后对天与槽取均值
h4 = mean(reshape(p4, [], 6, 24), [1 2]);   % → 1×1×24
h4 = reshape(h4, 1, 24);
h1 = mean(reshape(p1, 6, 24), 1);
bar((1:24)-0.2, h4, 0.4, 'FaceColor', C_A4, 'EdgeColor', 'none'); hold on;
bar((1:24)+0.2, h1, 0.4, 'FaceColor', C_A1, 'EdgeColor', 'none');
xlabel('小时');  ylabel('均价（元/kWh）');
legend({'附件4 年均', '附件1'}, 'Location', 'northwest', 'FontSize', 9);
title('(c) 逐小时均价对比', 'FontSize', 10);  grid on;  box on;

nexttile; hold on;
srt = sort(p4(:));
plot(linspace(0,100,numel(srt)), srt, '-', 'Color', C_A4, 'LineWidth', 1.8);
yline(min(p1), '--', 'Color', C_A1, 'LineWidth', 1.5);
yline(max(p1), '--', 'Color', C_A1, 'LineWidth', 1.5);
xline(100*sum(p4(:) < 0.10)/numel(p4), ':', 'Color', C_EM, 'LineWidth', 1.5);
xlabel('报价点累计占比（%）');  ylabel('电价（元/kWh）');
legend({'附件4 分位曲线', '附件1 的价格上下限', ...
    sprintf('近零价 (<0.10) 占 %.2f%%', 100*sum(p4(:)<0.10)/numel(p4))}, ...
    'Location', 'northwest', 'FontSize', 9);
title('(d) 报价点分布函数：近零价的长尾', 'FontSize', 10);  grid on;  box on;
figFiles{end+1} = savepng(f, [figDir 'fig_q4_price_structure.png']);

%% ============ 图 9-2：典型日调度（近零价日 / 尖峰日）============
% 选「附件4 逐日均价最低」与「最高」各一天，看储能在两种极端日的行为差异。
dm = mean(D.actual.price(qc.dayIdx, :), 2);
[~, kLow] = min(dm);  [~, kHigh] = max(dm);
f = newfig([60 60 1060 700]);
tl = tiledlayout(3,2, 'TileSpacing', 'compact');
for col = 1:2
    if col == 1, kk = kLow;  tagT = '近零价日'; else, kk = kHigh;  tagT = '尖峰日'; end
    prRow = D.actual.price(qc.dayIdx(kk), :);

    nexttile; hold on;
    plot(th, [R2.gPlan(kk,:) R2.gPlan(kk,end)], '-', 'Color', C_GRID, 'LineWidth', 1.5);
    plot(th, [R2.Soc(kk,:) R2.Soc(kk,end)], '-', 'Color', C_SOC, 'LineWidth', 1.5);
    yyaxis right;
    plot(th, [prRow prRow(end)], '-', 'Color', C_A4, 'LineWidth', 1.4);
    ylabel('电价（元/kWh）');
    xlabel('时刻（h）');  ylabel('购电量 / 储电量');
    legend({'计划购电量', '储电量', '电价'}, 'Location', 'northwest', 'FontSize', 8);
    title(sprintf('(%c) %s：%s', 'a'+col-1, tagT, string(R2.date(kk))), 'FontSize', 10);
    grid on;  box on;

    nexttile; hold on;
    area(th, [max(0,R2.c(kk,:)) 0], 'FaceColor', C_CHG, 'FaceAlpha', 0.6, 'EdgeColor', 'none');
    area(th, [-max(0,R2.d(kk,:)) 0], 'FaceColor', C_ADJ, 'FaceAlpha', 0.6, 'EdgeColor', 'none');
    yline(0, '-', 'Color', [0.4 0.4 0.4]);
    xlabel('时刻（h）');  ylabel('充放电功率（kW）');
    legend({'充电', '放电'}, 'Location', 'northwest', 'FontSize', 8);
    cm = sum(R2.c(kk,:))*dt;  dm2 = sum(R2.d(kk,:))*dt;
    pe = sum(prRow .* (R2.c(kk,:)+R2.d(kk,:)))*dt;
    title(sprintf('充 %.0f / 放 %.0f kWh，能量成本 %.0f 元', cm, dm2, pe), 'FontSize', 9);
    grid on;  box on;
end
% 第三行：两天的紧急购电量对比
nexttile([1 2]); hold on;
b = bar(th(1:end-1), [R2.gEm(kLow,:)*dt; R2.gEm(kHigh,:)*dt]', 1.0, 'grouped');
b(1).FaceColor = [0.20 0.55 0.85];  b(2).FaceColor = C_EM;
xlabel('时刻（h）');  ylabel('紧急购电量（kWh）');
legend({sprintf('%s %s', string(R2.date(kLow)), '（近零价日）'), ...
        sprintf('%s %s', string(R2.date(kHigh)), '（尖峰日）')}, ...
    'Location', 'northwest', 'FontSize', 9);
title(sprintf('(e) 两天的紧急购电量：近零价日 %.0f kWh vs 尖峰日 %.0f kWh', ...
    sum(R2.gEm(kLow,:))*dt, sum(R2.gEm(kHigh,:))*dt), 'FontSize', 10);
grid on;  box on;
figFiles{end+1} = savepng(f, [figDir 'fig_q4_typical_day.png']);

%% ============ 图 9-3：近零价套利归因 ============
fnz = [qc.outdir 't_q4_nearzero.mat'];
if isfile(fnz)
    S = load(fnz);
    f = newfig([60 60 1020 440]);
    tl = tiledlayout(1,2, 'TileSpacing', 'compact');

    nexttile; hold on;
    b = bar(1:10, S.cByDec, 0.6, 'FaceColor', C_CHG, 'EdgeColor', 'none');
    yyaxis right;
    plot(1:10, S.pByDec, '-o', 'Color', C_A4, 'LineWidth', 1.6, 'MarkerFaceColor', 'w');
    ylabel('该十分位的均价（元/kWh）');
    xlabel('电价十分位（1 = 最便宜）');  ylabel('充电量（kWh）');
    legend({'充电量', '均价'}, 'Location', 'northwest', 'FontSize', 9);
    title('(a) 储能在最便宜的两个十分位吸走大部分电', 'FontSize', 10);
    grid on;  box on;

    nexttile; hold on;
    vals = [S.cB, S.cM];
    b = bar([1 2], vals, 0.5, 'FaceColor', C_GRID, 'EdgeColor', 'none');
    for i = 1:2
        text(i, vals(i), sprintf('%.0f 元', vals(i)), 'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'bottom', 'FontSize', 9);
    end
    set(gca, 'XTick', [1 2], 'XTickLabel', {'原价（含近零价）', '近零价抬到当日中位数'});
    ylabel('总费用（元）');
    title(sprintf('(b) 反事实重定价：近零价贡献 %.0f 元（%.3f%%）', ...
        S.cM - S.cB, 100*(S.cM-S.cB)/S.cB), 'FontSize', 10);
    grid on;  box on;
    figFiles{end+1} = savepng(f, [figDir 'fig_q4_nearzero.png']);
else
    fprintf('  （未找到 %s，跳过图 9-3）\n', fnz);
end

%% ============ 图 9-4：跨日套利价值 vs 窗口长度 ============
ftp = [qc.outdir 't_q4_term_policy.mat'];
if isfile(ftp)
    S = load(ftp);
    f = newfig([60 60 900 470]);  hold on;
    mk = {'o', 's', '^'};
    for m = 1:numel(S.res)
        W = S.res(m).W;  cF = S.res(m).cFix;  cR = S.res(m).cFree;
        pctv = 100*(cF - cR) ./ cF;
        col = C_A1;  if m == 2, col = C_A4; end
        plot(W, pctv, ['-' mk{min(m,numel(mk))}], 'Color', col, 'LineWidth', 2.0, ...
            'MarkerFaceColor', 'w', 'MarkerSize', 9);
    end
    xlabel('窗口长度 W（天）—— 组内日界放开，只在窗口两端闭合');
    ylabel('跨日搬运储能带来的节省（%）');
    legend({S.regimes(1).name, S.regimes(2).name}, 'Location', 'northwest', 'FontSize', 9);
    title('图 9-4　口径 2（日末固定 6000）的代价：窗口越长、逐日电价的价差越可用', ...
        'FontSize', 11);
    grid on;  box on;
    figFiles{end+1} = savepng(f, [figDir 'fig_q4_term_policy.png']);
else
    fprintf('  （未找到 %s，跳过图 9-4）\n', ftp);
end

%% ============ 图 9-5：2×2 归因（附件3 预报 × 调整机制）============
fav = [qc.outdir 't_q4_adjust_value.mat'];
if isfile(fav)
    S = load(fav);
    f = newfig([60 60 900 480]);  hold on;
    nM = numel(S.modes);
    for m = 1:nM
        c = S.cost(m,:);
        subplot(1, nM, m);  hold on;
        b = bar([1 2], [c(1) c(3); c(2) c(4)]', 0.6, 'grouped');
        b(1).FaceColor = C_CHG;  b(2).FaceColor = C_A4;
        set(gca, 'XTick', [1 2], 'XTickLabel', {'不调整', '调整'});
        ylabel('总费用（元）');
        title(sprintf('%s', S.modes{m}), 'FontSize', 10);
        legend({'自预测', '附件3'}, 'Location', 'northwest', 'FontSize', 8);
        grid on;  box on;
        for j = 1:2
            text(j-0.15, c(j*2-1), sprintf('%.2g', c(j*2-1)), 'FontSize', 7, ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom');
            text(j+0.15, c(j*2), sprintf('%.2g', c(j*2)), 'FontSize', 7, ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom');
        end
    end
    figFiles{end+1} = savepng(f, [figDir 'fig_q4_adjust.png']);
else
    fprintf('  （未找到 %s，跳过图 9-5）\n', fav);
end

%% ============ 图 9-6：CVaR 有效前沿 ============
fcv = [qc.outdir 'q4_cvar.mat'];
if isfile(fcv)
    S = load(fcv);  F = S.F;
    f = newfig([60 60 1020 460]);
    tl = tiledlayout(1,2, 'TileSpacing', 'compact');

    nexttile; hold on;
    plot(F.Cbar, F.Ebar, '-o', 'Color', C_GRID, 'LineWidth', 2.0, ...
        'MarkerFaceColor', 'w', 'MarkerSize', 8);
    for i = 1:numel(F.lams)
        text(F.Cbar(i), F.Ebar(i), sprintf('  \\lambda=%.2f', F.lams(i)), 'FontSize', 9);
    end
    xlabel(sprintf('CVaR_{%.2f}（最坏 %.0f%% 尾部）的费用（元）', F.alpha, 100*(1-F.alpha)));
    ylabel('期望费用（元）');
    title('(a) 有效前沿：期望与尾部风险的权衡（样本内）', 'FontSize', 10);
    grid on;  box on;

    nexttile; hold on;
    plot(F.lams, F.Ebar, '-o', 'Color', C_GRID, 'LineWidth', 1.8, 'MarkerFaceColor', 'w');
    plot(F.lams, F.Cbar, '-s', 'Color', C_EM, 'LineWidth', 1.8, 'MarkerFaceColor', 'w');
    xlabel('风险厌恶系数 \lambda');  ylabel('费用（元）');
    legend({'E[费用]', sprintf('CVaR_{%.2f}', F.alpha)}, 'Location', 'northwest', 'FontSize', 9);
    title('(b) 随 \lambda 上升：期望略升、尾部风险下降', 'FontSize', 10);
    grid on;  box on;
    figFiles{end+1} = savepng(f, [figDir 'fig_q4_cvar_frontier.png']);

    % 样本外箱线图
    f = newfig([60 60 900 470]);  hold on;
    V = [];  G = {};
    for i = 1:numel(F.lams)
        v = F.RealC(i, F.idxOut);  v = v(isfinite(v));
        V = [V; v(:)];                       %#ok<AGROW>
        G = [G; repmat({sprintf('%.2f', F.lams(i))}, numel(v), 1)]; %#ok<AGROW>
    end
    % ⚠️ 本机【不能用 boxplot】：它内部走 @tabular/dotAssign.m，而该文件被
    %    plot3 演示脚本覆盖（已知环境故障，详见《MATLAB dotAssign 损坏》备忘录），
    %    调用直接报「不支持将脚本 dotAssign 作为函数执行」，整张图生不出来。
    %    故这里自己画箱线图：四分位箱体 + 1.5×IQR 触须 + 离群点。
    %    分位数也【不能】用 quantile（属 Statistics Toolbox），改成本地线性插值实现。
    drawBoxes(V, G, F.lams);
    xlabel('风险厌恶系数 \lambda');  ylabel('样本外逐日实付费用（元）');
    title('图 9-7　样本外检验：各 \lambda 的逐日实付费用分布（\lambda 是唯一被拟合的量）', ...
        'FontSize', 11);
    grid on;  box on;
    figFiles{end+1} = savepng(f, [figDir 'fig_q4_cvar_oos.png']);
else
    fprintf('  （未找到 %s，跳过图 9-6/9-7）\n', fcv);
end

fprintf('\n  q4_visualization：已生成 %d 张图于 %s\n', numel(figFiles), figDir);
for i = 1:numel(figFiles), fprintf('    %s\n', figFiles{i}); end
end

% ======================================================================
function f = newfig(pos)
% NEWFIG  新建【白底】图（R2025a+ 的 Theme 跟随桌面主题，故逐图钉 light）
f = figure('Position', pos, 'Color', 'w');
try
    f.Theme = matlab.graphics.theme.GraphicsTheme('BaseColorStyle', 'light');
catch
end
set(f, 'Color', 'w');
end

% ======================================================================
function drawBoxes(V, G, lams)
% DRAWBOXES  自绘箱线图（替代 boxplot，原因见调用处注释）
nG = numel(lams);
for i = 1:nG
    v = V(strcmp(G, sprintf('%.2f', lams(i))));
    v = sort(v(isfinite(v)));
    if isempty(v), continue; end
    q1 = myQuant(v, 0.25);  q2 = myQuant(v, 0.50);  q3 = myQuant(v, 0.75);
    iq = q3 - q1;
    lo = min(v(v >= q1 - 1.5*iq));
    hi = max(v(v <= q3 + 1.5*iq));
    w  = 0.30;  cBox = [0.20 0.35 0.60];
    patch([i-w i+w i+w i-w], [q1 q1 q3 q3], [0.85 0.90 0.97], ...
        'EdgeColor', cBox, 'LineWidth', 1.1);
    plot([i-w i+w], [q2 q2], '-', 'Color', [0.75 0.20 0.20], 'LineWidth', 1.8);
    plot([i i], [q3 hi], '-', 'Color', cBox, 'LineWidth', 1.0);
    plot([i i], [lo q1], '-', 'Color', cBox, 'LineWidth', 1.0);
    plot([i-w/2 i+w/2], [hi hi], '-', 'Color', cBox, 'LineWidth', 1.0);
    plot([i-w/2 i+w/2], [lo lo], '-', 'Color', cBox, 'LineWidth', 1.0);
    o = v(v < lo | v > hi);
    if ~isempty(o)
        plot(i*ones(size(o)), o, '.', 'Color', [0.45 0.45 0.45], 'MarkerSize', 5);
    end
end
xlim([0.4, nG + 0.6]);  xticks(1:nG);
xticklabels(arrayfun(@(x) sprintf('%.2f', x), lams, 'UniformOutput', false));
end

% ======================================================================
function q = myQuant(v, p)
% MYQUANT  线性插值分位数（不依赖 Statistics Toolbox 的 quantile）
v = sort(v(:));  n = numel(v);
if n == 1, q = v; return; end
h  = (n - 1)*p + 1;
lo = floor(h);  hi = min(lo + 1, n);
q  = v(lo) + (h - lo)*(v(hi) - v(lo));
end

% ======================================================================
function name = savepng(f, name)
ax = findall(f, 'Type', 'axes');
for a = ax', a.Toolbar.Visible = 'off'; end
exportgraphics(f, name, 'Resolution', 300);
end
