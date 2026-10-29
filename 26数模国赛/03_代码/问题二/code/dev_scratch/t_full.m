addpath('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码');
qc = q2_config();
D = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码\out\data.mat').D;
F = q2_forecast(D, qc);
R = q2_solve(D, F, qc);
fprintf('\n--- 全年 ---\n');
fprintf('区间 %s ~ %s，共 %d 天\n', string(R.date(1)), string(R.date(end)), numel(R.date));
fprintf('计划购电量 %.1f kWh | 紧急购电量 %.1f kWh\n', R.summary.qPlanTot, R.summary.qEmTot);
fprintf('计划购电费 %.2f 元 | 紧急购电费 %.2f 元 | 实际合计 %.2f 元\n', ...
    R.summary.costPlanTot, R.summary.costEmTot, R.summary.costTot);
fprintf('发生紧急购电天数 %d / %d ; 单日最大紧急量 %.1f kWh\n', ...
    R.summary.nDayEm, numel(R.date), R.summary.maxEm);
fprintf('flag 非 1 天数 = %d\n', sum(R.flag ~= 1));
fprintf('平台性: mean|gLp-g| = %.2f kW ; Σ费用差 = %.6f 元\n', mean(R.gLpGap), sum(R.costGap));
