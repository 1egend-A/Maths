function Tab = t_q3_downscale()
% T_Q3_DOWNSCALE  降尺度方法对比：stair / linear / shape
%
% 附件3 是【整点】粒度的光伏预报，而决策是【10 分钟】粒度，必须降尺度。
% 三种做法（数据预处理阶段已实现于 p0_downscale.m，均以"逐小时均值守恒"为硬约束）：
%
%   stair   阶梯：小时内 6 个槽全取该小时值（不做形状修正）
%   linear  线性：相邻整点之间线性插值（再按小时均值归一）
%   shape   形状：按光伏实测统计出的 24×6 日内形状权重分配（本模型默认）
%
% 三者的小时均值完全相同，差别只在【小时内怎么摆】。本脚本量化的正是这一点对
% 最终费用的影响——它同时回答了一个更一般的问题：10 分钟粒度的决策到底需要
% 多细的预报，还是整点粒度就够。
%
% 落盘：out/t_q3_downscale.csv / out/t_q3_downscale.mat
%
% 用法：Tab = t_q3_downscale();

D  = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码\out\data.mat').D;
qc = q3_config();  qc.verbose = false;

methods = {'stair','linear','shape'};
nm = numel(methods);
cost = zeros(nm,1); qBuy = zeros(nm,1); rmse = zeros(nm,1); sec = zeros(nm,1);
costPlan = zeros(nm,1); costAdj = zeros(nm,1); costEm = zeros(nm,1);

fprintf('===== 降尺度方法对比（整点 → 10 分钟）=====\n');
for m = 1:nm
    q2 = qc;  q2.dsMethod = methods{m};
    fprintf('  [%s] 求解中...\n', methods{m});
    t0 = tic;
    F = q3_forecast(D, q2);
    R = q3_solve(D, F, q2);
    sec(m) = toc(t0);
    cost(m) = R.summary.costTot;
    costPlan(m) = R.summary.costPlanTot;
    costAdj(m)  = R.summary.costAdjTot;
    costEm(m)   = R.summary.costEmTot;
    qBuy(m) = R.summary.qAdjTot + R.summary.qEmTot;
    % 10 分钟粒度的预报偏差：拿 0:00 那套预报与实测比（全时段）
    r = F.Phat4(:, :, 1) - D.actual.pv;
    rmse(m) = sqrt(mean(r(:).^2));
    fprintf('       费用 %.2f 元，10 分钟级 RMSE %.2f kW（%.1f s）\n', cost(m), rmse(m), sec(m));
end

Tab = table(methods', costPlan, costAdj, costEm, cost, ...
    cost - cost(3), 100*(cost-cost(3))/cost(3), qBuy, rmse, sec, ...
    'VariableNames', {'降尺度方法','计划购电费','调整购电费','紧急购电费','总费用', ...
                      '相对shape差','相对差_pct','购电量_kWh','PV_RMSE_kW','用时_s'});

fprintf('\n%-10s %14s %14s %12s %14s %12s %14s %12s\n', ...
    '方法','计划购电费','调整购电费','紧急购电费','总费用','相对shape差','购电量kWh','PV_RMSE');
for m = 1:nm
    fprintf('%-10s %14.2f %14.2f %12.2f %14.2f %12.2f %14.0f %12.2f\n', ...
        methods{m}, costPlan(m), costAdj(m), costEm(m), cost(m), ...
        cost(m)-cost(3), qBuy(m), rmse(m));
end
fprintf('\n  三种方法的小时均值完全相同（p0_downscale 内有硬 assert 保证），\n');
fprintf('  差异只来自"小时内怎么摆"，最大相对差 %.3f%%。\n', ...
    max(abs(cost-cost(3)))/cost(3)*100);

% ---- 落盘 ----
outdir = qc.outdir;  if ~isfolder(outdir), mkdir(outdir); end
writetable(Tab, [outdir 't_q3_downscale.csv'], 'Encoding', 'UTF-8');
methods_ = methods; cost_ = cost; rmse_ = rmse;  %#ok<NASGU>
save([outdir 't_q3_downscale.mat'], 'Tab', 'methods_', 'cost_', 'rmse_');
fprintf('\n  已写出：%s\n', [outdir 't_q3_downscale.csv']);
end
