function Tab = t_q3_ablation()
% T_Q3_ABLATION  问题三必答开放题：是否需要引入其他时刻的预报制定调整购电策略
%
% 题面末句：「请分析是否需要引入其他时刻的预报制定调整购电策略。」
% 本脚本用【消融实验】给出定量判据，而不是表态。两组实验：
%
% ── 实验一：预报时刻消融（同一套预报来源，逐个放开调整时刻）──
%   A0  [1 0 0 0]  只用 0:00 预报，制定计划后不再调整
%   A1  [1 1 0 0]  追加 6:00 预报做一次调整
%   A2  [1 1 1 0]  追加 12:00 预报
%   A3  [1 1 1 1]  追加 18:00 预报（全用）
%   看【边际收益曲线】：每多用一个时刻省多少钱，收益是否递减、会不会转负。
%
% ── 实验二：预报来源对照（同样用满四个时刻，只换光伏预报从哪来）──
%   S1  自预测（近 7 日同时刻均值，不用附件3）
%   S2  附件3 官方预报（本问默认）
%   S3  0.15·附件3 + 0.85·自预测（按预处理阶段实测的最优线性混合权重）
%   看【官方预报到底值不值】：因为预处理阶段已实测附件3 的精度不如持续性预测，
%   若 S2 反而不如 S1，那"引入更多时刻的官方预报"就更要谨慎——这是本问最反直觉
%   也最值得写进论文的一条。
%
% 落盘：out/t_q3_ablation.csv（实验一）、out/t_q3_ablation_source.csv（实验二）
%       out/t_q3_ablation.mat
%
% 用法：Tab = t_q3_ablation();
%
% 注：每个分组都是一次完整的 334 天滚动求解，实验一约 2 分钟，实验二约 3 分钟。

D  = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码\out\data.mat').D;
qc = q3_config();
qc.verbose = false;

fprintf('===== 问题三 消融实验 =====\n');
fprintf('区间 %d 天（%s ~ %s）\n', numel(qc.dayIdx), ...
    string(qc.dateFirst), string(qc.dateLast));

%% ---------------- 实验一：预报时刻消融 ----------------
groups = { 'A0 只用 0:00',         [1 0 0 0]; ...
           'A1 +6:00',             [1 1 0 0]; ...
           'A2 +6:00,12:00',       [1 1 1 0]; ...
           'A3 +6:00,12:00,18:00', [1 1 1 1] };

ng = size(groups,1);
costG = zeros(ng,1);  qG = zeros(ng,1);  secG = zeros(ng,1);
cPlanG = zeros(ng,1); cAdjG = zeros(ng,1); cEmG = zeros(ng,1);
nAdjG = zeros(ng,1);  hiG = zeros(ng,1);   loG = zeros(ng,1);

fprintf('\n---- 实验一：预报时刻消融 ----\n');
for g = 1:ng
    fprintf('  [%s] 求解中...\n', groups{g,1});
    q2 = qc;  q2.useStages = logical(groups{g,2});
    t0 = tic;
    F = q3_forecast(D, q2);
    R = q3_solve(D, F, q2);
    secG(g) = toc(t0);
    costG(g) = R.summary.costTot;
    cPlanG(g)= R.summary.costPlanTot;
    cAdjG(g) = R.summary.costAdjTot;
    cEmG(g)  = R.summary.costEmTot;
    qG(g)    = R.summary.qAdjTot + R.summary.qEmTot;
    nAdjG(g) = R.summary.nSlotAdj;
    hiG(g)   = R.summary.nClipHi;
    loG(g)   = R.summary.nClipLo;
    fprintf('       费用 %.2f 元（%.1f s）\n', costG(g), secG(g));
end

% 边际收益：相对上一组省了多少
savePrev  = [NaN; costG(1:end-1) - costG(2:end)];
saveTotal = costG(1) - costG;
Tab = table(groups(:,1), cPlanG, cAdjG, cEmG, costG, ...
    savePrev, saveTotal, 100*saveTotal/costG(1), nAdjG, hiG, loG, secG, ...
    'VariableNames', {'分组','计划购电费','调整购电费','紧急购电费','总费用', ...
    '较上一组节省','较A0节省','较A0降幅_pct','调整槽数','上修槽数','下修槽数','用时_s'});

fprintf('\n%-24s %13s %12s %12s %14s %13s %13s %9s\n', ...
    '分组','计划购电费','调整购电费','紧急购电费','总费用','较上一组省','较A0省','降幅%');
for g = 1:ng
    if isnan(savePrev(g)), sp = '—'; else, sp = sprintf('%.2f', savePrev(g)); end
    fprintf('%-24s %13.2f %12.2f %12.2f %14.2f %13s %13.2f %9.3f\n', ...
        groups{g,1}, cPlanG(g), cAdjG(g), cEmG(g), costG(g), sp, saveTotal(g), 100*saveTotal(g)/costG(1));
end

% ---- 结论判据 ----
% ⚠️ 曾写成 char("递减" + (dec==0)*"不递减")：MATLAB 的 string 不支持【加法】，
%    该表达式在本题必被求值（marg(end) > 0 时走 else 分支），脚本会抛
%    「数据类型无效。参量必须为数值、字符或逻辑值」而中断。改用显式分支。
% ⚠️ 另：判据【不是】「边际收益必须逐级递减」——实测序列是
%    [66370.8, 181803.98, 405.60]，第二项反而【高于】第一项，单调递减为假。
%    原因（写进论文 8.3）：
%      · 6:00 的调整只保住 37..72 槽——这些槽在 12:00 会被【再次覆盖】，
%        故它单独贡献的增量仅限这 6 小时；
%      · 12:00 的调整覆盖 73..144 槽（72 个槽，是前者的两倍），且用的是
%        只差 12 小时而非 18 小时的预报，两者叠加使其边际价值最大；
%      · 18:00 只剩 109..144 槽（36 槽），且 12:00 对这段的预报已经足够准，
%        故边际价值塌缩到 405.60 元（0.0028%）——这才是开放题的答案主体。
%    真正的判据是：①每个追加时刻的边际收益 ≥ 0（否则不必引入）；
%                  ②【最后一个】时刻的边际收益是否值得其运行成本。
marg = -diff(costG);                       % 每组相对上一组的节省（正 = 有效）
dec  = all(diff(marg) <= 1e-6);            % 严格单调递减？（本数据集为 false）
allPos = all(marg > -1e-6);
fprintf('\n  边际收益序列（每多用一个预报时刻省下的钱）：%s 元\n', mat2str(round(marg,2)', 6));
if dec
    fprintf('  边际收益逐级递减：是（符合"信息越多、增量越小"的一般预期）\n');
else
    fprintf('  边际收益逐级递减：否（12:00 的边际价值高于 6:00——覆盖槽数是其两倍，\n');
    fprintf('                        且预报比 6:00 新鲜 6 小时；详见本节结论）\n');
end
if ~allPos
    fprintf('  ⚠️ 存在非正的边际收益——该时刻不必引入。\n');
elseif marg(end) <= 0.01 * marg(1)
    fprintf('  ✅ 三个时刻的边际收益全为正，但【18:00 几乎无增量】：%.2f 元，\n', marg(end));
    fprintf('     仅为 6:00 边际收益的 %.3f%%。结论：引入 0:00/6:00/12:00 三段即可，\n', ...
        100*marg(end)/marg(1));
    fprintf('     18:00 这一次调整的收益不足以覆盖其预报与执行成本。\n');
else
    fprintf('  ✅ 三个追加时刻的边际收益全为正且量级相当，建议全部引入。\n');
end

%% ---------------- 实验二：预报来源对照 ----------------
% 自预测 / 附件3 / 最优混合权重（预处理阶段实测 0.15）
fprintf('\n---- 实验二：光伏预报来源对照（均用满四个时刻）----\n');
srcNames = {'S1 自预测(mean7)', 'S2 附件3 官方', 'S3 混合(w=0.15 附件3)'};
nS3 = numel(srcNames);
costS = zeros(nS3,1);  qS = zeros(nS3,1);
for s = 1:nS3
    q2 = qc;  q2.useStages = [true true true true];
    switch s
        case 1
            q2.pvSource = 'self';
        case 2
            q2.pvSource = 'a3';
        case 3
            q2.pvSource = 'blend3';
            q2.pvBlendW = 0.15;
    end
    fprintf('  [%s] 求解中...\n', srcNames{s});
    F = q3_forecast(D, q2);
    R = q3_solve(D, F, q2);
    costS(s) = R.summary.costTot;
    qS(s)    = R.summary.qAdjTot + R.summary.qEmTot;
    fprintf('       费用 %.2f 元\n', costS(s));
end
TabS = table(srcNames', costS, qS, ...
    costS - costS(2), 100*(costS - costS(2))/costS(2), ...
    'VariableNames', {'预报来源','总费用','购电量_kWh','相对附件3的差','相对差_pct'});
fprintf('\n%-24s %14s %14s %14s %10s\n', '预报来源','总费用','购电量kWh','相对附件3差','差%');
for s = 1:nS3
    fprintf('%-24s %14.2f %14.1f %14.2f %10.3f\n', ...
        srcNames{s}, costS(s), qS(s), costS(s)-costS(2), 100*(costS(s)-costS(2))/costS(2));
end

%% ---------------- 落盘 ----------------
outdir = qc.outdir;
if ~isfolder(outdir), mkdir(outdir); end
writetable(Tab,  [outdir 't_q3_ablation.csv'], 'Encoding', 'UTF-8');
writetable(TabS, [outdir 't_q3_ablation_source.csv'], 'Encoding', 'UTF-8');
margG = marg; srcNameS = srcNames;  %#ok<NASGU>
save([outdir 't_q3_ablation.mat'], 'Tab', 'TabS', 'costG', 'margG', ...
     'costS', 'srcNameS', 'groups', 'nAdjG', 'hiG', 'loG');
fprintf('\n  已写出：%s\n', [outdir 't_q3_ablation.csv']);
fprintf('  已写出：%s\n', [outdir 't_q3_ablation_source.csv']);
fprintf('  已写出：%s\n', [outdir 't_q3_ablation.mat']);
end
