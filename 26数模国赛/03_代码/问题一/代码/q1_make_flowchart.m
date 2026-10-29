function q1_make_flowchart(figDir)
% q1_make_flowchart
% 生成可直接放入论文的问题一横向简洁流程图。

if nargin<1 || isempty(figDir), figDir='figures'; end
if ~exist(figDir,'dir'), mkdir(figDir); end

set(groot,'defaultAxesFontName','Microsoft YaHei');
set(groot,'defaultTextFontName','Microsoft YaHei');

f=figure('Color','w','Position',[100 100 1200 310]);
ax=axes(f,'Position',[0 0 1 1]);
axis(ax,'off');

titles={'输入与预处理','模型建立','优化求解','结果输出'};
body={ ...
    '附件1数据\newline10分钟时段统一', ...
    '购电、充放电、SOC\newline最小化购电费用', ...
    '功率平衡与SOC约束\newlinelinprog求最优解', ...
    '表1、表2、result1\newline费用与调度分析'};

x=[0.035 0.285 0.535 0.785];
w=0.18; y=0.30; h=0.42;

for k=1:4
    rectangle(ax,'Position',[x(k),y,w,h], ...
        'EdgeColor',[0.18 0.25 0.32],'LineWidth',1.1);
    text(ax,x(k)+w/2,y+h*0.68,titles{k}, ...
        'HorizontalAlignment','center','FontWeight','bold','FontSize',12);
    text(ax,x(k)+w/2,y+h*0.31,body{k}, ...
        'HorizontalAlignment','center','FontSize',10);
end

for k=1:3
    annotation(f,'arrow',[x(k)+w+0.012 x(k+1)-0.012],[0.51 0.51], ...
        'LineWidth',1.1,'Color',[0.18 0.25 0.32]);
end

exportgraphics(f,fullfile(figDir,'fig_q1_flow.png'),'Resolution',300);
close(f);
end
