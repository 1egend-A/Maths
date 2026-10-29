% T_SMOKE  问题三冒烟测试：5 天全流程 + 关键不变量（非交付物）
D = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码\out\data.mat');
D = D.D;
fprintf('D 字段：%s\n', strjoin(fieldnames(D)', ', '));
fprintf('day144.price: %s | actual.price: %s | fc.pv: %s | fc.issue uniq: %s\n', ...
    mat2str(size(D.day144.price)), mat2str(size(D.actual.price)), ...
    mat2str(size(D.fc.pv)), mat2str(unique(D.fc.issue)'));

qc = q3_config();
qc.verbose = true;
qc.outdir  = 'D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\问题三\code\dev_scratch\out\';
if ~isfolder(qc.outdir), mkdir(qc.outdir); end

tic; F = q3_forecast(D, qc); fprintf('q3_forecast 用时 %.1f s\n', toc);

dl = 32:36;
tic; R = q3_solve(D, F, qc, dl); fprintf('q3_solve 用时 %.1f s\n', toc);

% ---- 不变量 1：SOC 界与日末闭环 ----
fprintf('\n[SOC] 全局 min %.4f max %.4f | 日末值 %s\n', ...
    min([qc.S0; R.Soc(:)]), max([qc.S0; R.Soc(:)]), mat2str(round(R.Soc(:,end),6)'));
assert(all(R.Soc(:) >= qc.S_min - 1e-6) && all(R.Soc(:) <= qc.S_max + 1e-6), 'SOC 越界');
assert(max(abs(R.Soc(:,end) - qc.S_end)) < 1e-6, '日末未闭环');

% ---- 不变量 2：逐槽守恒律（用实际值）----
dt = qc.dt;
% 能量平衡：购电 + 紧急购电 + 放电 −（净负荷 + 充电）= 弃电（富余的无法上网部分）
res = R.A + R.gEm + R.D - (F.Nact(R.dayIdx,:) + R.C);
assert(max(abs(res(:) - R.curt(:))) < 1e-6, '守恒律残差不为零');
fprintf('[守恒] 逐槽残差 max %.3e kW，弃电合计 %.1f kWh\n', ...
    max(abs(res(:) - R.curt(:))), sum(R.curt(:))*dt);

% ---- 不变量 3：分位数论断 ----
%   计划阶段 #{s: Q > G} 应 ≤ nS*(1-0.5) = 15
fprintf('[分位] 计划阶段 #above 均值 %.3f（理论 ≤ %d）\n', ...
    mean(R.nAboveG(:)), qc.nScen*(1-qc.qPlan));
assert(all(R.nAboveG(:) <= qc.nScen*(1-qc.qPlan) + 1e-9), '计划分位不符');
%   调整阶段 A 必须落在 [Q_0.7, Q_0.9] 内
ok = isfinite(R.AgLo(:));
fprintf('[分位] 调整槽 %d 个；min(A−Q0.7) = %.3e；min(Q0.9−A) = %.3e\n', ...
    sum(ok), min(R.AgLo(ok)), min(R.AgHi(ok)));
assert(min(R.AgLo(ok)) > -1e-9 && min(R.AgHi(ok)) > -1e-9, '调整量未落在 70~90 分位区间');

% ---- 不变量 4：费用对账 ----
lhs = sum(R.costPlan) + sum(R.costAdj) + sum(R.costEm);
fprintf('[费用] 三块和 %.4f | Sadj %.4f | 差 %.3e\n', lhs, sum(R.Sadj), lhs - sum(R.Sadj));
assert(abs(lhs - sum(R.Sadj)) < 1e-6, '费用三块之和与总额不符');
fprintf('[费用] 不调整对照 %.2f 元 → 调整后 %.2f 元（省 %.2f，%.3f%%）\n', ...
    sum(R.costNoAdj), sum(R.Sadj), sum(R.costNoAdj)-sum(R.Sadj), ...
    100*(sum(R.costNoAdj)-sum(R.Sadj))/sum(R.costNoAdj));

% ---- 不变量 5：调整必须有利 ----
assert(sum(R.Sadj) <= sum(R.costNoAdj) + 1e-6, '调整后费用高于不调整，模型有问题');
fprintf('\n✅ 冒烟测试全部通过\n');
