% T_DIAG_QPLAN  计划量临界分位的实测最优值（非交付物）
%
% 理论：∂E[cost]/∂G = 0.5p·(Pr(A<G) − Pr(A>G)) = 0  ⇒  G* = A 的中位数。
% 实现上以「0:00 情景集 Q 的中位数」近似 A 的中位数——本脚本检验该近似的代价，
% 并给出 qPlan 的经验最优值。若最优值明显偏离 0.5，说明近似需要修正。
S = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码\out\data.mat');
D = S.D;
dl = 32:91;                          % 60 天加速扫
qs = [0.4 0.5 0.6 0.7 0.8 0.9];
fprintf('扫描区间：%d 天（%s … %s）\n', numel(dl), string(D.actual.dates(dl(1))), string(D.actual.dates(dl(end))));
fprintf('%6s | %14s %12s %12s | %10s %10s\n', 'qPlan', '总费用(元)', '调整费(元)', '紧急费(元)', '上修槽数', '下修槽数');

res = zeros(numel(qs),1);
for i = 1:numel(qs)
    qc = q3_config();  qc.verbose = false;  qc.qPlan = qs(i);
    qc.outdir = 'D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\问题三\code\dev_scratch\out\';
    F = q3_forecast(D, qc);
    R = q3_solve(D, F, qc, dl);    % 每次都重跑（(c,d) 与 G 无关，故结果近似可复用）
    res(i) = R.summary.costTot;
    fprintf('%6.2f | %14.2f %12.2f %12.2f | %10d %10d\n', qs(i), ...
        R.summary.costTot, R.summary.costAdjTot, R.summary.costEmTot, ...
        R.summary.nClipHi, R.summary.nClipLo);
end
[best, ib] = min(res);
fprintf('\n经验最优 qPlan = %.2f（费用 %.2f 元）；理论值 0.5 的费用 %.2f 元；差 %.3f%%\n', ...
    qs(ib), best, res(qs==0.5), 100*(res(qs==0.5)-best)/best);

% 分位数的「成本平坦度」：q 从 0.4 扫到 0.9 的相对变化
fprintf('费用相对最优的偏离（%%）：%s\n', mat2str(round(100*(res-best)/best, 3)'));
