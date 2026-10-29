addpath('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码');
S = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\问题二\out\q2_solution.mat');
R = S.R; qc = S.qc;
f = qc.resFile;

% ---- 计划购电量 ----
C = readcell(f, 'Sheet', '计划购电量');
fprintf('[计划购电量] %d x %d\n', size(C,1), size(C,2));
fprintf('  表头 列1=%s 列2=%s 列145=%s 列146=%s 列147=%s\n', ...
    string(C{1,1}), string(C{1,2}), string(C{1,145}), string(C{1,146}), string(C{1,147}));
fprintf('  A列 首=%s 末=%s\n', string(C{2,1}), string(C{end,1}));
M = cell2mat(C(2:end, 2:145));
pEP = cell2mat(C(2:end, 146));  pEQ = cell2mat(C(2:end, 147));
fprintf('  Σ时段 = %.1f kWh（应 %.1f）偏差 %.3e\n', sum(M(:)), R.summary.qPlanTot, ...
    abs(sum(M(:)) - R.summary.qPlanTot));
fprintf('  ΣEP   = %.1f kWh  与 Σ时段一致? %d\n', sum(pEP), abs(sum(pEP)-sum(M(:)))<1e-6);
fprintf('  ΣEQ   = %.2f 元（应 %.2f）偏差 %.3e\n', sum(pEQ), R.summary.costPlanTot, ...
    abs(sum(pEQ) - R.summary.costPlanTot));
fprintf('  行和 vs EP 最大偏差 = %.3e\n', max(abs(sum(M,2) - pEP)));
% 抽查第 1 天第 1 段
fprintf('  抽查 D1S1 = %.4f kWh（应 %.4f）\n', M(1,1), R.gPlan(1,1)*qc.dt);

% ---- 充放电量 ----
C = readcell(f, 'Sheet', '充放电量');
fprintf('\n[充放电量] %d x %d\n', size(C,1), size(C,2));
fprintf('  表头: %s\n', strjoin(cellstr(string(C(1,:))), ' | '));
fprintf('  第1天块: ');  fprintf('%s/%.1f/%.1f/%s/%s | ', string(C{2,2}), C{2,3}, C{2,4}, string(C{2,5}), string(C{2,6}));
fprintf('%s/%.1f/%.1f/%s/%s\n', string(C{3,2}), C{3,3}, C{3,4}, string(C{3,5}), string(C{3,6}));
fprintf('  末行: %s | %s | %.1f | %.1f | %s | %s\n', ss(C{end,1}), ss(C{end,2}), ...
    C{end,3}, C{end,4}, ss(C{end,5}), ss(C{end,6}));
cE = sum(cell2mat(C(2:end,3)));  dE = sum(cell2mat(C(2:end,4)));
fprintf('  Σ充电量 = %.1f kWh（应 %.1f）Σ放电量 = %.1f kWh\n', cE, sum(sum(R.c))*qc.dt, dE);
soc = cell2mat(C(2:end,6));
ok6 = soc(~isnan(soc));
fprintf('  储电量: 有效 %d 个（应 668），全部 = 6000 ? %d\n', numel(ok6), all(abs(ok6-6000)<1e-9));
fprintf('  日期列非空 = %d（应 334）\n', sum(~ismissing(string(C(2:end,1)))));

% ---- 紧急购电量 ----
C = readcell(f, 'Sheet', '紧急购电量');
fprintf('\n[紧急购电量] %d x %d\n', size(C,1), size(C,2));
fprintf('  表头: %s\n', strjoin(cellstr(string(C(1,:))), ' | '));
for i = 2:min(4,size(C,1))
    fprintf('   %s | %s | %.2f\n', string(C{i,1}), string(C{i,2}), C{i,3});
end
qE = cell2mat(C(2:end,3));
fprintf('  Σ购电量 = %.1f kWh（应 %.1f）偏差 %.3e\n', sum(qE), R.summary.qEmTot, ...
    abs(sum(qE)-R.summary.qEmTot));
% 当天区间数统计
dv = string(C(2:end,1));  u = unique(dv);
fprintf('  覆盖天数 = %d（应 %d）\n', numel(u), R.summary.nDayEm);
% 抽查 2025-03-20 的紧急购电
tgt = "2025-03-20";
ii = find(dv == tgt);
fprintf('  2025-03-20 共 %d 段：\n', numel(ii));
for z = ii(1:min(6,numel(ii)))'
    fprintf('     %s -> %.2f kWh\n', string(C{z+1,2}), C{z+1,3});
end

function s = ss(v)
if all(ismissing(v)), s = '·'; else, s = string(v); end
end
