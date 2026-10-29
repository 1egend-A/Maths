%% q1_visualization.m
% 问题一论文配图。可独立运行：若工作区没有变量，则读取 q1_solution_matlab.csv。

if ~exist('g','var')
    R = readtable('q1_solution_matlab.csv','VariableNamingRule','preserve');
    price = R.price_yuan_per_kWh(:);
    loadP = R.load_kW(:);
    pvP = R.pv_forecast_kW(:);
    g = R.grid_kW(:); c = R.charge_kW(:); d = R.discharge_kW(:);
    dt = 1/6; eta = 0.90; S0 = 6000; Smin = 1200; Smax = 10800;
    SOC = [S0; R.soc_end_kWh(:)];
    baseGrid = max(loadP-pvP,0);
    baseCost = sum(price.*baseGrid*dt);
    totalCost = sum(price.*g*dt);
end

if ~exist('figDir','var')
    figDir = 'figures_matlab';
end
if ~exist(figDir,'dir'); mkdir(figDir); end

set(groot,'defaultAxesFontName','Microsoft YaHei');
set(groot,'defaultTextFontName','Microsoft YaHei');
set(groot,'defaultAxesFontSize',10);

t = (1:numel(g))/6;

%% 图1：典型日负载、光伏与电价
f1 = figure('Color','w','Position',[100 100 900 420]);
yyaxis left
plot(t,loadP,'LineWidth',1.6); hold on;
plot(t,pvP,'LineWidth',1.6);
ylabel('功率 / kW');
yyaxis right
plot(t,price,'--','LineWidth',1.4);
ylabel('电价 / (元·kWh^{-1})');
xlabel('时间 / h'); xlim([0 24]); xticks(0:4:24); grid on;
legend('小区负载','光伏预测功率','电价','Location','northwest','Box','off');
title('典型日负载、光伏预测与电价变化');
exportgraphics(f1,fullfile(figDir,'fig_q1_data_profile.png'),'Resolution',300);

%% 图2：最优调度与 SOC 轨迹
f2 = figure('Color','w','Position',[100 100 900 620]);
tiledlayout(2,1,'TileSpacing','compact','Padding','compact');
nexttile;
plot(t,loadP,'LineWidth',1.6); hold on;
plot(t,pvP,'LineWidth',1.3);
plot(t,g,'LineWidth',1.4);
area(t,c,'FaceAlpha',0.18,'EdgeColor','none');
area(t,-d,'FaceAlpha',0.18,'EdgeColor','none');
yline(0,'k-'); xlim([0 24]); xticks(0:4:24); grid on;
ylabel('功率 / kW');
legend('负载','光伏预测','电网购电','储能充电','储能放电','Location','north','NumColumns',5,'Box','off');
title('最优购电与储能充放电策略');

nexttile;
ts = (0:numel(g))/6;
plot(ts,SOC,'LineWidth',1.7); hold on;
yline(Smin,'--','下限 1200 kWh','LineWidth',1.0);
yline(Smax,'--','上限 10800 kWh','LineWidth',1.0);
xlim([0 24]); xticks(0:4:24); grid on;
xlabel('时间 / h'); ylabel('储电量 / kWh');
legend('SOC','Location','north','Box','off');
exportgraphics(f2,fullfile(figDir,'fig_q1_dispatch_soc.png'),'Resolution',300);

%% 图3：费用对比
f3 = figure('Color','w','Position',[100 100 620 400]);
bar([baseCost,totalCost],0.55);
set(gca,'XTickLabel',{'无储能基准','优化策略'});
ylabel('全天购电费 / 元'); grid on;
title('优化前后全天购电费用对比');
text(1,baseCost,sprintf('%.0f',baseCost),'HorizontalAlignment','center','VerticalAlignment','bottom');
text(2,totalCost,sprintf('%.0f',totalCost),'HorizontalAlignment','center','VerticalAlignment','bottom');
text(1.5,max([baseCost,totalCost])*0.93, ...
    sprintf('节省 %.0f 元（%.1f%%）',baseCost-totalCost,100*(baseCost-totalCost)/baseCost), ...
    'HorizontalAlignment','center');
exportgraphics(f3,fullfile(figDir,'fig_q1_cost_compare.png'),'Resolution',300);
