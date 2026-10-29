addpath('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码');
D = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码\out\data.mat').D;
S = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\问题二\out\q2_solution.mat'); R=S.R; qc=S.qc;
% oracle 自身一致性：抽 5 天，检查可行性与守恒
for d = [32 33 100 200 365]
    [c,q,g,fl] = q2_oracle(D.day144.price, D.actual.load(d,:), D.actual.pv(d,:), qc.S0, qc.S_end, qc);
    fprintf('日 %3d (%s) flag=%d 费用=%10.2f 购电=%9.2f kWh\n', d, ...
        string(D.actual.dates(d)), fl, c, q);
end
% 全年对照：oracle 费用应 <= 本模型实际费用
nd = numel(R.dayIdx); cOr = zeros(nd,1);
for k = 1:nd
    [cOr(k),~,~,fl] = q2_oracle(D.day144.price, D.actual.load(R.dayIdx(k),:), ...
        D.actual.pv(R.dayIdx(k),:), qc.S0, qc.S_end, qc);
    assert(fl==1, 'oracle 日 %d 未达最优', R.dayIdx(k));
end
fprintf('\n完美信息基准 Σ费用 = %.2f 元\n', sum(cOr));
fprintf('本模型实际 Σ费用   = %.2f 元\n', R.summary.costTot);
fprintf('本模型期望 Σ费用   = %.2f 元\n', R.summary.costExpTot);
fprintf('下界性检验 基准 <= 实际 ? %d （差 %.2f 元）\n', sum(cOr)<=R.summary.costTot, R.summary.costTot-sum(cOr));
