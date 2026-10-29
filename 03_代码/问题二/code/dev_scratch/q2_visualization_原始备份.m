function figFiles = q2_visualization(R, F, qc, D)
% Q2_VISUALIZATION  问题二论文配图（全部可用本脚本一键复现）
%
% 规范遵循《论文配图建议.md》：
%   · 字体：中文用 Microsoft YaHei（显式设置，不依赖默认，避免中文方框）
%   · 导出：exportgraphics(..., 'Resolution', 300)，文件 fig_q2_<内容>.png
%   · 配色：同一物理量全文同色 —— 购电=蓝、放电=橙、光伏=黄绿、充电=紫、SOC=深灰
%           不依赖单一颜色区分，叠加曲线一律线型/线宽分开
%   · 线宽 >= 1.5，字号 >= 9pt，坐标轴必带单位
%
% 出图清单（对应配图建议的 Q2 条目）：
%   fig_q2_forecast_method  预测方法选型（负载/光伏分开）与逐月稳定性   [图 2-D]
%   fig_q2_typical_day      指定日期典型日调度 + SOC/电价              [图 1-A/1-B 改编]
%   fig_q2_newsvendor       报童临界分位与「最优计划量不唯一」          [图 2-A] ⭐
%   fig_q2_emergency        逐日紧急购电量与分布                       [图 2-B] ⭐
%   fig_q2_cumcost          累计费用：本模型 / 无储能 / 完美信息下界    [图 2-C] ⭐
%   fig_q2_monthly          月度汇总（购电量、紧急购电量、费用、SOC）    [补充]
%
% 用法：q2_visualization()  或  q2_visualization(R, F, qc, D)

if nargin < 4 || isempty(D)
    D = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码\out\data.mat').D;
end
if nargin < 3 || isempty(qc), qc = q2_config(); end
if nargin < 2 || isempty(F), F = q2_forecast(D, qc); end
if nargin < 1 || isempty(R), R = load([qc.outdir 'q2_solution.mat']).R; end

figDir = [qc.outdir 'figures\'];
if ~isfolder(figDir), mkdir(figDir); end
set(groot, 'defaultAxesFontName', 'Microsoft YaHei');
set(groot, 'defaultTextFontName', 'Microsoft YaHei');
set(groot, 'defaultAxesFontSize', 10);
set(groot, 'defaultAxesColorOrder', [ ...
    0.00 0.32 0.75;    % 1 购电     蓝
    0.92 0.49 0.10;    % 2 放电     橙
    0.55 0.72 0.10;    % 3 光伏     黄绿
    0.49 0.18 0.56;    % 4 充电     紫
    0.35 0.35 0.38]);  % 5 储电量   深灰

C_GRID = [0.00 0.32 0.75];  C_DIS = [0.92 0.49 0.10];
C_PV = [0.55 0.72 0.10];    C_CHG = [0.49 0.18 0.56];
% 储电量与电价都用灰阶（二者常同图叠加），靠【深浅】区分：储电量近黑、电价浅灰
C_SOC = [0.20 0.20 0.22];   C_EM = [0.80 0.20 0.20];
C_PRC = [0.55 0.55 0.55];

dt = qc.dt;  nT = size(R.gPlan, 2);  nd = numel(R.date);
th = (0:nT)/6;                                  % 小时轴，145 个点（含 24:00）
figFiles = {};

%% ============ 图 1：预测方法选型（论证「为什么用这两个预测器」）============
L = D.actual.load;  P = D.actual.pv;
days = qc.dayIdx;
% 负载候选
[~, rmseL,   ~] = sc(L, @(X,d) X(max(1,d-1),:), days);
[~, rmseL7,  ~] = sc(L, @(X,d) X(max(1,d-7),:), days);
[~, rmseLm7, ~] = sc(L, @(X,d) mean(X(max(1,d-7):d-1,:),1), days);
[~, rmseLbl, ~] = sc(L, @fLoad, days);
% 光伏候选
[~, rmseP1,  ~] = sc(P, @(X,d) X(max(1,d-1),:), days);
[~, rmseP7,  ~] = sc(P, @(X,d) X(max(1,d-7),:), days);
[~, rmsePm7, ~] = sc(P, @(X,d) mean(X(max(1,d-7):d-1,:),1), days);
% 注：近7日均值对【负载】很差（把周末混进来，RMSE 与「前一日」同级），对【光伏】却最好。
%     这正是「负载与光伏不共用同一个预测器」的直接证据。

f = figure('Color','w','Position',[80 80 1080 420]);
tiledlayout(1,2,'TileSpacing','compact','Padding','compact');
nexttile;
Rm = [rmseL rmseL7 rmseLm7 rmseLbl; rmseP1 rmseP7 rmsePm7 nan];
b = bar(Rm, 0.72);
b(1).FaceColor = C_GRID;  b(2).FaceColor = C_DIS;
b(3).FaceColor = C_PV;    b(4).FaceColor = C_CHG;
set(gca,'XTickLabel',{'小区负载','光伏功率'}); grid on;
ylabel('RMSE / kW');
% 数值标注一律画在柱顶【上方】的空白处：柱内标注会与柱色撞色（深色柱上根本看不见）
ymax = max(Rm(:));
for s = 1:numel(b)
    for j = 1:numel(b(s).XEndPoints)
        yv = b(s).YEndPoints(j);
        if isnan(yv), continue; end
        text(b(s).XEndPoints(j), yv + 0.02*ymax, sprintf('%.1f', yv), ...
            'FontSize',9, 'Color',[0.12 0.12 0.12], ...
            'HorizontalAlignment','center', 'VerticalAlignment','bottom');
    end
end
ylim([0 1.62*ymax]);   % 顶部留白要够高：4 行图例约占坐标区三成高，留少了会压住最高柱的数值标
legend({'前一日','上周同日','近7日均值','0.5×上周+0.5×近4周'}, ...
    'Location','northwest','Box','off');
title('(a) 各预测方法的均方根误差（334 天 × 144 时段）');

nexttile;
mo = month(R.date);
mm = unique(mo);
hold on; grid on;
plot(mm, splitMape(L, @fLoad, days, mo, mm), '-o', 'LineWidth',1.8, 'Color',C_CHG, 'MarkerFaceColor','w');
plot(mm, splitMape(L, @(X,d) X(max(1,d-7),:), days, mo, mm), '--s', 'LineWidth',1.5, 'Color',C_GRID, 'MarkerFaceColor','w');
plot(mm, splitMape(L, @(X,d) mean(X(max(1,d-7):d-1,:),1), days, mo, mm), ':^', 'LineWidth',1.5, 'Color',C_DIS, 'MarkerFaceColor','w');
xlabel('月份'); ylabel('负载预测 MAPE / %');
xlim([0.5 12.5]); ylim([1 26]); xticks(mm); grid on;   % 抬高上限给图例腾位
legend({'本文方法 0.5×上周+0.5×近4周','上周同日','近7日均值'}, 'Location','northwest','Box','off');
title('(b) 负载预测逐月稳定性');
figFiles{end+1} = [figDir 'fig_q2_forecast_method.png'];
savepng(f, figFiles{end});

%% ============ 图 2：指定日期典型日调度 ============
pick = [datetime(2025,9,23), datetime(2025,6,21)];   % 高/低紧急购电各一天，形成对照
f = figure('Color','w','Position',[80 80 1080 700]);
tl = tiledlayout(2,2,'TileSpacing','compact','Padding','compact');
for z = 1:2
    k = find(R.date == pick(z));
    nexttile(z); hold on; grid on;
    pv = D.actual.pv(R.dayIdx(k), :);
    area(th(1:end-1)+dt/2, pv, 'FaceColor',C_PV, 'FaceAlpha',0.20, 'EdgeColor','none');
    plot(th(1:end-1)+dt/2, R.Nact(k,:), 'LineWidth',1.7, 'Color',[0.15 0.15 0.15]);  % 实际净负荷
    plot(th(1:end-1)+dt/2, R.Nhat(k,:), '--', 'LineWidth',1.4, 'Color',[0.55 0.55 0.55]); % 日前预测净负荷
    area(th(1:end-1)+dt/2, R.gPlan(k,:), 'FaceColor',C_GRID, 'FaceAlpha',0.18, 'EdgeColor','none');
    plot(th(1:end-1)+dt/2, R.gPlan(k,:), 'LineWidth',1.6, 'Color',C_GRID);
    stem(th(1:end-1)+dt/2, R.gEm(k,:), 'filled', 'Color',C_EM, 'MarkerSize',2.2, 'LineWidth',0.8);
    xlim([0 24]); xticks(0:4:24); ylabel('功率 / kW');
    yl = ylim;  ylim([yl(1) yl(2) + 0.45*(yl(2)-yl(1))]);   % 顶部留白，避免图例压住夜间尖峰
    legend({'光伏实际','实际净负荷 L-PV','日前预测净负荷','计划购电量','紧急购电量'}, ...
        'Location','northwest','Box','off','NumColumns',2);
    title(sprintf('(%c) %s 功率平衡', 'a'+z-1, string(pick(z))));
    nexttile(z+2); hold on; grid on;
    yyaxis left
    plot(th, [qc.S0 R.Soc(k,:)], 'LineWidth',2.0, 'Color',C_SOC);
    yline(qc.S_max,'--','上限 10800','LineWidth',1.0,'Color',[0.6 0.6 0.6],'LabelHorizontalAlignment','left');
    yline(qc.S_min,'--','下限 1200','LineWidth',1.0,'Color',[0.6 0.6 0.6],'LabelHorizontalAlignment','left');
    ylim([0 12000]); ylabel('储电量 / kWh');
    yyaxis right
    stairs(th, [R.price(1) R.price(:)'], '-', 'LineWidth',1.4, 'Color',C_PRC);
    ylabel('电价 / (元·kWh^{-1})'); ylim([0 2.0]);
    xlim([0 24]); xticks(0:4:24); xlabel('时间 / h');
    title(sprintf('(%c) %s 储电量与电价', 'c'+z-1, string(pick(z))));
end
title(tl, '问题二 指定日期日前计划与事后紧急购电（口径 7：严格字面信息集）', 'FontWeight','normal');
figFiles{end+1} = [figDir 'fig_q2_typical_day.png'];
savepng(f, figFiles{end});

%% ============ 图 3：报童临界分位与最优平台 ⭐ ============
[figFiles, f] = local_newsvendor(R, F, qc, D, figDir, C_GRID, C_EM, C_PRC, figFiles, dt, nT);

%% ============ 图 4：逐日紧急购电量与分布 ⭐ ============
f = figure('Color','w','Position',[80 80 1080 420]);
tiledlayout(1,2,'TileSpacing','compact','Padding','compact');
nexttile; hold on; grid on;
qE = R.qEm;
bar(R.date, qE, 1.0, 'FaceColor',C_EM, 'EdgeColor','none');
% ⚠️ 参考线【不用】自带 Label：默认画在右端且压在柱身上，深色字配深红柱完全看不清。
%    改为收集句柄后交给 legend，位置可控且自动避让。
h1 = yline(mean(qE),  '--','LineWidth',1.6,'Color',[0.10 0.10 0.10]);
h2 = yline(median(qE),':', 'LineWidth',1.6,'Color',[0.10 0.10 0.10]);
ylabel('单日紧急购电量 / kWh'); xlabel('日期');
yl = ylim; ylim([0 yl(2)*1.32]);
legend([h1 h2], {sprintf('均值 %.1f kWh', mean(qE)), ...
                 sprintf('中位数 %.1f kWh', median(qE))}, ...
       'Location','northwest','Box','off');
title(sprintf('(a) 逐日紧急购电量（334 天，%d 天发生）', R.summary.nDayEm));
xtickformat('MMM');
nexttile; hold on; grid on;
histogram(qE(qE>0), 40, 'FaceColor',C_EM, 'EdgeColor','w');
h3 = xline(mean(qE),            '--','LineWidth',1.6,'Color',[0.10 0.10 0.10]);
h4 = xline(quantile(qE,0.95),   ':', 'LineWidth',1.6,'Color',[0.10 0.10 0.10]);
xlabel('单日紧急购电量 / kWh'); ylabel('天数 / 天');
yl = ylim; ylim([0 yl(2)*1.28]);
legend([h3 h4], {sprintf('均值 %.0f kWh', mean(qE)), ...
                 sprintf('95%% 分位 %.0f kWh', quantile(qE,0.95))}, ...
       'Location','northeast','Box','off');
title('(b) 紧急购电量分布（仅计入发生紧急购电的天）');
figFiles{end+1} = [figDir 'fig_q2_emergency.png'];
savepng(f, figFiles{end});

%% ============ 图 5：累计费用对比 ⭐ ============
bf = [qc.outdir 'q2_bench.mat'];
if isfile(bf)
    bench = load(bf).bench;
else
    % 未跑校验：现算基准（较慢，约 10 s）
    cOr = zeros(nd,1);
    for k = 1:nd
        cOr(k) = q2_oracle(D.day144.price, D.actual.load(R.dayIdx(k),:), ...
                           D.actual.pv(R.dayIdx(k),:), qc.S0, qc.S_end, qc);
    end
    gBase = max(0, R.Nact);
    bench = struct('cOr', cOr, 'cOurs', R.summary.costTot, ...
        'cBase', sum(sum(D.day144.price(:)' .* gBase))*dt);
end
cumOurs = cumsum(R.costTot);
cumBase = cumsum(max(0, R.Nact) * (D.day144.price(:)*dt));
cumOr   = cumsum(bench.cOr);
f = figure('Color','w','Position',[80 80 1000 640]);
tl = tiledlayout(2,1,'TileSpacing','compact','Padding','compact');
nexttile; hold on; grid on;
plot(R.date, cumOurs, 'LineWidth',2.0, 'Color',C_GRID);
plot(R.date, cumBase, '--', 'LineWidth',1.7, 'Color',C_DIS);
plot(R.date, cumOr,   ':',  'LineWidth',1.9, 'Color',C_PV);
ylabel('累计购电费用 / 元'); xtickformat('MMM');
legend({'本文模型（日前计划 + 紧急购电）','无储能基准','完美信息下界（理想参照）'}, ...
    'Location','northwest','Box','off');
title(sprintf('(a) 累计费用：模型 %.2f 万元 | 无储能 %.2f 万元 | 下界 %.2f 万元', ...
    cumOurs(end)/1e4, cumBase(end)/1e4, cumOr(end)/1e4));
nexttile; hold on; grid on;
% ⚠️ 这里必须是【当天】的节省 = 累计节省的一阶差分。
%    直接画 cumBase-cumOurs 是单调上升的累计量，与「逐日」标题不符（曾出错）。
savDay = [cumBase(1)-cumOurs(1); diff(cumBase - cumOurs)];
bar(R.date, savDay, 1.0, 'FaceColor',C_DIS, 'EdgeColor','none');
yline(0,'k-');
yline(mean(savDay),'--','LineWidth',1.8,'Color',C_GRID);
ylabel('逐日节省 / 元'); xlabel('日期'); xtickformat('MMM');
% 均值信息写进标题，不放图例会占掉柱子上方的画面（柱顶就在附近）
title(sprintf('(b) 逐日节省（相对无储能基准）：日均 %.0f 元，%d/%d 天为负', ...
    mean(savDay), sum(savDay < 0), nd));
figFiles{end+1} = [figDir 'fig_q2_cumcost.png'];
savepng(f, figFiles{end});

%% ============ 图 6：月度汇总 ============
mo = month(R.date);  mm = unique(mo);
qP = zeros(size(mm));  qE2 = zeros(size(mm));  cP = zeros(size(mm));  cE = zeros(size(mm));
socMax = zeros(size(mm));  swing = zeros(size(mm));  emShare = zeros(size(mm));
for i = 1:numel(mm)
    m = mo == mm(i);
    qP(i) = sum(R.qPlan(m));  qE2(i) = sum(R.qEm(m));
    cP(i) = sum(R.costPlan(m));  cE(i) = sum(R.costEm(m));
    Sm = R.Soc(m,:);
    socMax(i) = max(Sm(:));
    % 月均【日】SOC 摆幅（留作自检：实测各月恒为 9600 kWh = 10800-1200，
    % 即储能每天把 SOC 从下限满放到上限，「容量约束是紧的」）。
    swing(i) = mean(max(Sm,[],2) - min(Sm,[],2));
    emShare(i) = 100*cE(i)/(cP(i)+cE(i));    % 紧急购电费占当月总购电费的比例
end
fprintf('月度指标自检：SOC 峰值 %s\n', mat2str(round(socMax), 6));
fprintf('              日均摆幅 %s kWh（各月相同 ⇒ 每日满幅循环）\n', mat2str(round(swing), 6));
fprintf('              紧急购电费占比 %s %%\n', mat2str(round(emShare,2), 6));
f = figure('Color','w','Position',[80 80 1080 420]);
tiledlayout(1,2,'TileSpacing','compact','Padding','compact');
nexttile; hold on; grid on;
b = bar(mm, [qP qE2], 0.8, 'stacked');
b(1).FaceColor = C_GRID;  b(2).FaceColor = C_EM;
ylabel('月度购电量 / kWh'); xlabel('月份'); xticks(mm);
yl = ylim; ylim([0 yl(2)*1.22]);
% ⚠️ 堆叠柱的 legend 默认【自上而下】列条目，与自下而上的视觉顺序相反。
%    必须显式传句柄 [底 顶]，否则图例顺序与柱的堆叠顺序对不上。
legend([b(1) b(2)], {'计划购电量','紧急购电量'}, 'Location','northwest','Box','off');
title('(a) 月度购电量构成');
nexttile;
b2 = bar(mm, [cP cE], 0.8, 'stacked');
b2(1).FaceColor = C_GRID;  b2(2).FaceColor = C_EM;
ylabel('月度购电费 / 元'); xlabel('月份'); xticks(mm);
yl = ylim; ylim([0 yl(2)*1.22]);
% ⚠️ 占比是 [0,100] 的百分数、费用轴量级 1e6 元 —— 同轴画会被压在 0 上，
%    必须走右轴（yyaxis right）；右轴颜色也要显式改掉，否则是 MATLAB 默认的橄榄绿，
%    与全文配色规范冲突。
yyaxis right
hp = plot(mm, emShare, '-o', 'LineWidth',1.9, 'Color', C_EM, 'MarkerFaceColor','w');
ylim([0 max(emShare)*1.45]); ylabel('紧急购电费占比 / %');
ax = gca;  ax.YAxis(2).Color = C_EM;       % 右轴线/刻度/标签统一用紧急购电色
legend([b2(1) b2(2) hp], {'计划购电费','紧急购电费','紧急购电费占比'}, ...
    'Location','northwest','Box','off');
title('(b) 月度费用构成与紧急购电占比');
figFiles{end+1} = [figDir 'fig_q2_monthly.png'];
savepng(f, figFiles{end});

fprintf('\n已生成 %d 张图：\n', numel(figFiles));
for i = 1:numel(figFiles), fprintf('  %s\n', figFiles{i}); end
end

% ======================================================================
function [figFiles, f] = local_newsvendor(R, F, qc, D, figDir, Cg, Cem, Cpr, figFiles, dt, nT)
% 报童临界分位与「最优计划量不唯一」——以 2025-12-21 的 12:00-12:10 时段为例
kDate = datetime(2025,12,21);
k = find(R.date == kDate);
t = 73;                                   % 12:00-12:10
nS = qc.nScen;
pool = (R.dayIdx(k)-nS):(R.dayIdx(k)-1);
Rmat = F.Nact(pool,:) - F.Nhat(pool,:);
Rs = Rmat(end-nS+1:end, :)';              % ⚠️ 144x30：(时段, 情景)，与 q2_solve 一致
Ns = F.Nhat(R.dayIdx(k), t) + Rs(t,:)';   % nS 个情景净负荷（取第 t 个时段那一行）
Q  = sort(Ns + R.c(k,t) - R.d(k,t));      % 该时段的「需外购净需求」次序统计量
p  = D.day144.price(t);

gr = linspace(max(0,Q(1)-2500), Q(end)+500, 4000);
Ec = zeros(size(gr));
for i = 1:numel(gr)
    Ec(i) = p*gr(i)*dt + 5*p*dt*mean(max(0, Q - gr(i)));
end
k80 = ceil(0.8*nS);
gLo = max(0, Q(k80));  gHi = max(0, Q(k80+1));
dE = p*dt*(1 - 5*sum(Q > gr, 1)/nS);      % 边际期望费用

f = figure('Color','w','Position',[80 80 1120 400]);
tl = tiledlayout(1,3,'TileSpacing','compact','Padding','compact');

nexttile; hold on; grid on;
plot(gr, Ec, 'LineWidth',1.9, 'Color',Cg);
xline(gLo,'--','LineWidth',1.6,'Color',Cem);
ylabel('单时段期望购电费用 / 元'); xlabel('计划购电量 g / kW');
title(sprintf('(a) 期望费用曲线（%s %s）', string(kDate), '12:00-12:10'));
legend({'期望费用','最优平台左端 Q_{0.8}'}, 'Location','northeast','Box','off');

nexttile; hold on; grid on;
rr = gr > max(0,gLo-400) & gr < gHi+400;
plot(gr(rr), Ec(rr), 'LineWidth',2.2, 'Color',Cg);
yline(Ec(find(rr,1)),'k:');
xline(gLo,'--','LineWidth',1.6,'Color',Cem);
xline(gHi,':','LineWidth',1.6,'Color',Cpr);
xlabel('计划购电量 g / kW');
title('(b) 平台放大：G 与 G'' 之间费用恒等');
% 右端是第 k80+1 = 25 个次序统计量，分位 = 25/30 = 0.8333（不是整数 0.84）
legend({'期望费用','','平台左端 z_{(24)} = 0.800 分位', ...
        sprintf('平台右端 z_{(25)} = %.3f 分位', (k80+1)/nS)}, ...
       'Location','northwest','Box','off');

nexttile; hold on; grid on;
stairs([gr(1) gr], [dE(1) dE], 'LineWidth',1.6, 'Color',Cem);
yline(0,'k-');
xline(gLo,'--','LineWidth',1.5,'Color',Cg);
xlabel('计划购电量 g / kW'); ylabel('边际期望费用 \partial E/\partial g');
title('(c) 一阶条件：边际费用归零于平台');
legend({'边际期望费用','零点'}, 'Location','northeast','Box','off');
title(tl, sprintf('报童临界分位：缺电代价 5p 与多买代价 p 之比 ⇒ 临界分位 = 4/5 = 0.8（示例时段 p = %.4f 元/kWh）', p), ...
    'FontWeight','normal');
figFiles{end+1} = [figDir 'fig_q2_newsvendor.png'];
savepng(f, figFiles{end});
end

function savepng(f, name)
% 300 dpi PNG；先关掉坐标区工具栏，否则工具栏会被一并导出到图里
ax = findall(f, 'Type', 'axes');
for a = ax', a.Toolbar.Visible = 'off'; end
exportgraphics(f, name, 'Resolution', 300);
end

function y = fLoad(X, d)
ks = 7*(1:4);  ks = ks(d - ks >= 1);
if isempty(ks)
    y = X(max(1,d-1), :);
else
    base = mean(X(d-ks,:), 1);
    if d - 7 >= 1, y = 0.5*X(d-7,:) + 0.5*base; else, y = base; end
end
end

function [mae, rmse, mape] = sc(X, f, days)
nt = size(X,2);
E = zeros(numel(days), nt);  Y = E;
for k = 1:numel(days)
    d = days(k);
    E(k,:) = f(X,d) - X(d,:);
    Y(k,:) = X(d,:);
end
mae = mean(abs(E(:)));  rmse = sqrt(mean(E(:).^2));
mk = Y > 50;  mape = mean(abs(E(mk)./Y(mk)))*100;
end

function v = splitMape(X, f, days, mo, mm)
v = zeros(size(mm));
for i = 1:numel(mm)
    sel = days(mo == mm(i));
    [~,~,v(i)] = sc(X, f, sel);
end
end
