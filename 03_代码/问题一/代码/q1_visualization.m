function q1_visualization(sol,figDir)
% q1_visualization
% 生成问题一论文主图：
% 1) 典型日负载、光伏预测与电价
% 2) 最优购电/充放电 + SOC
% 3) 优化前后购电费用对比
%
% 输出PNG，300 dpi。

if nargin<2 || isempty(figDir), figDir='figures'; end
if ~exist(figDir,'dir'), mkdir(figDir); end

% 中文字体：Windows优先微软雅黑
set(groot,'defaultAxesFontName','Microsoft YaHei');
set(groot,'defaultTextFontName','Microsoft YaHei');
set(groot,'defaultAxesFontSize',10);

n=numel(sol.g);
t=(1:n)/6;

%% 图1 典型日数据
f1=figure('Color','w','Position',[100 100 900 420]);
yyaxis left
plot(t,sol.loadP,'LineWidth',1.6); hold on;
plot(t,sol.pvP,'LineWidth',1.6);
ylabel('功率 / kW');
yyaxis right
plot(t,sol.price,'--','LineWidth',1.4);
ylabel('电价 / (元·kWh^{-1})');
xlabel('时间 / h');
xlim([0 24]); xticks(0:4:24); grid on;
legend('小区负载','光伏预测功率','电价', ...
    'Location','northwest','Box','off');
title('典型日负载、光伏预测与电价变化');
exportgraphics(f1,fullfile(figDir,'fig_q1_data_profile.png'),'Resolution',300);

%% 图2 最优调度与SOC
f2=figure('Color','w','Position',[100 100 900 620]);
tiledlayout(2,1,'TileSpacing','compact','Padding','compact');

nexttile;
plot(t,sol.loadP,'LineWidth',1.6); hold on;
plot(t,sol.pvP,'LineWidth',1.3);
plot(t,sol.g,'LineWidth',1.4);
area(t,sol.c,'FaceAlpha',0.18,'EdgeColor','none');
area(t,-sol.d,'FaceAlpha',0.18,'EdgeColor','none');
yline(0,'k-');
xlim([0 24]); xticks(0:4:24); grid on;
ylabel('功率 / kW');
legend('负载','光伏预测','电网购电','储能充电','储能放电', ...
    'Location','north','NumColumns',5,'Box','off');
title('最优购电与储能充放电策略');

nexttile;
ts=(0:n)/6;
plot(ts,sol.SOC,'LineWidth',1.7); hold on;
yline(sol.Smin,'--','下限 1200 kWh','LineWidth',1.0);
yline(sol.Smax,'--','上限 10800 kWh','LineWidth',1.0);
xlim([0 24]); xticks(0:4:24); grid on;
xlabel('时间 / h');
ylabel('储电量 / kWh');
legend('SOC','Location','north','Box','off');
exportgraphics(f2,fullfile(figDir,'fig_q1_dispatch_soc.png'),'Resolution',300);

%% 图3 费用对比
f3=figure('Color','w','Position',[100 100 620 400]);
baseCost=sol.metrics.baseCost_yuan;
totalCost=sol.metrics.totalCost_yuan;
bar([baseCost,totalCost],0.55);
set(gca,'XTickLabel',{'无储能基准','优化策略'});
ylabel('全天购电费 / 元'); grid on;
title('优化前后全天购电费用对比');
text(1,baseCost,sprintf('%.0f',baseCost), ...
    'HorizontalAlignment','center','VerticalAlignment','bottom');
text(2,totalCost,sprintf('%.0f',totalCost), ...
    'HorizontalAlignment','center','VerticalAlignment','bottom');
text(1.5,max([baseCost,totalCost])*0.93, ...
    sprintf('节省 %.0f 元（%.1f%%）', ...
    baseCost-totalCost,100*(baseCost-totalCost)/baseCost), ...
    'HorizontalAlignment','center');
exportgraphics(f3,fullfile(figDir,'fig_q1_cost_compare.png'),'Resolution',300);

close([f1 f2 f3]);
end
