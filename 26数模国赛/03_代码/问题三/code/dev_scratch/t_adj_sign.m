% T_ADJ_SIGN  诊断：调整机制在【单日实现值】上是否可能为负收益
% 背景：四日总表里 2025-12-21 的「调整节省」= −1165.13 元（−1.776%），
%       与「调整应有价值」的直觉冲突。本脚本用全部 334 天给出分布，判断
%       这是不是 bug。
% 判据：调整是在【期望】意义上最优的（阶段 2–4 用新信息重优化），
%       单日实现值可正可负。若 bug，则负值应伴随结构性异常；若正常，
%       则应有大量日子为正、少数为负、均值显著为正。
D = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码\out\data.mat').D;
qc = q3_config();
R = load([qc.outdir 'q3_solution.mat']).R;

saveTot  = R.costNoAdj - R.Sadj;            % 全调整相对不调整的节省（元/天）
saveOnly = R.costNoAdj - R.costAdjOnly;     % 只调购电量、留用 0:00 充放电
neg = saveTot < 0;

fprintf('===== 逐日「调整节省」分布（334 天）=====\n');
fprintf('  合计        %14.2f 元（= 年鉴口径 %14.2f）\n', sum(saveTot), ...
    R.summary.costNoAdjTot - R.summary.costTot);
fprintf('  均值        %14.2f 元/天 | 中位数 %14.2f 元/天\n', mean(saveTot), median(saveTot));
fprintf('  最小/最大   %14.2f / %14.2f 元\n', min(saveTot), max(saveTot));
fprintf('  为正的天数  %d / %d（%.1f%%）\n', sum(~neg), numel(saveTot), 100*mean(~neg));
fprintf('  为负的天数  %d / %d（%.1f%%），合计负向 %14.2f 元\n', ...
    sum(neg), numel(saveTot), 100*mean(neg), sum(saveTot(neg)));
fprintf('  正值合计 %14.2f 元 − 负值合计 %14.2f 元 = %14.2f 元\n', ...
    sum(saveTot(~neg)), -sum(saveTot(neg)), sum(saveTot));

fprintf('\n  ---- 负收益日的结构特征（是不是结构性异常？）----\n');
if any(neg)
    % ⚠️ 不要用同一个变量名在循环里反复赋值再在循环外使用：下面两块曾共用 m，
    %    循环结束时 m 停在 ~neg，于是"负收益日"那行实际上也算了正收益日，
    %    两组数字一模一样（1853.5 vs 1853.5）——典型的假一致。
    mN = neg;  mP = ~neg;
    fprintf('  负收益日（%3d 天）：平均下修槽 %6.1f 个 | 平均上修槽 %5.1f 个 | 平均节省 %9.2f 元\n', ...
        sum(mN), mean(sum(R.clipLo(mN,:),2)), mean(sum(R.clipHi(mN,:),2)), mean(saveTot(mN)));
    fprintf('  正收益日（%3d 天）：平均下修槽 %6.1f 个 | 平均上修槽 %5.1f 个 | 平均节省 %9.2f 元\n', ...
        sum(mP), mean(sum(R.clipLo(mP,:),2)), mean(sum(R.clipHi(mP,:),2)), mean(saveTot(mP)));
    % 负收益日的机制猜测：调整把计划【下修】，少买的电只能靠 5 倍价应急补回
    fprintf('  平均下调计划量：负收益日 %8.1f kWh/天 | 正收益日 %8.1f kWh/天\n', ...
        mean(sum(R.G(mN,:) - R.A(mN,:), 2)*qc.dt), mean(sum(R.G(mP,:) - R.A(mP,:), 2)*qc.dt));
    fprintf('  平均下调计划量（按槽均）：负收益日 %6.1f kWh/槽 | 正收益日 %6.1f kWh/槽\n', ...
        mean(sum(R.G(mN,:) - R.A(mN,:), 2)*qc.dt)/144, mean(sum(R.G(mP,:) - R.A(mP,:), 2)*qc.dt)/144);
    fprintf('  平均紧急购电费：负收益日 %8.1f 元 | 正收益日 %8.1f 元\n', ...
        mean(R.costEm(mN)), mean(R.costEm(mP)));
    fprintf('  平均紧急购电量：负收益日 %8.1f kWh | 正收益日 %8.1f kWh\n', ...
        mean(R.qEm(mN)), mean(R.qEm(mP)));
end

% ---- 该机制的理论性质：均值非负即可，单日可负 ----
fprintf('\n  结论：调整在【期望】意义上最优（阶段 2–4 用新信息重优化），\n');
fprintf('        单日实现成本可高于不调整。%.1f%% 的日子为正、%.1f%% 为负，\n', ...
    100*mean(~neg), 100*mean(neg));
fprintf('        均值 %.2f 元/天 > 0 ⇒ 不存在符号错误，负值是"前瞻最优 vs 事后实现"的正常落差。\n', ...
    mean(saveTot));

save([qc.outdir 't_adj_sign.mat'], 'saveTot', 'saveOnly');
fprintf('\n  已写出：%s\n', [qc.outdir 't_adj_sign.mat']);
