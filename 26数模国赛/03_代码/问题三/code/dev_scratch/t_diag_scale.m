% T_DIAG_SCALE  量级对账：Q1 / Q2 / Q3 在同一天上的购电量与费用是否可比（非交付物）
S = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码\out\data.mat');
D = S.D;
addpath('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码');
addpath('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\问题二\code');

cfg = p0_config();
dl  = 32:36;
dt  = cfg.dt;

L = D.actual.load(dl,:);  P = D.actual.pv(dl,:);
fprintf('=== 原始量级（%d 天）===\n', numel(dl));
fprintf('  负载  日均 %.1f kWh（均功率 %.1f kW）\n', mean(sum(L,2))*dt, mean(L(:)));
fprintf('  光伏  日均 %.1f kWh\n', mean(sum(P,2))*dt);
fprintf('  净负荷日均 %.1f kWh（= 无储能时必须外购）\n', mean(sum(L-P,2))*dt);

% 附件1 典型日对照
fprintf('=== 附件1 典型日 ===\n');
fprintf('  负载 %.1f kWh | 光伏 %.1f kWh | 净负荷 %.1f kWh\n', ...
    sum(D.day144.load)*dt, sum(D.day144.pv)*dt, sum(D.day144.load-D.day144.pv)*dt);
fprintf('  电价均值 %.4f 元/kWh\n', mean(D.day144.price));

fprintf('=== 各日电价均值（元/kWh）===\n');
fprintf('  附件1 %.4f | 附件4 各日 %s\n', mean(D.day144.price), ...
    mat2str(round(mean(D.actual.price(dl,:),2)',4)));

% ---- Q1 式单日 LP（完美信息、无预测误差）----
qc2 = q2_config();  qc2.verbose = false;
F2  = q2_forecast(D, qc2);
c1 = 0; c2 = 0; c3 = 0; q1 = 0; q2_ = 0; q3 = 0;
for k = 1:numel(dl)
    d = dl(k);
    [g,c,dd,costQ1] = day_lp(D.day144.price(:), L(k,:)', P(k,:)', cfg.S0, cfg, cfg.S_end);
    c1 = c1 + costQ1;  q1 = q1 + sum(g)*dt;
end
R2 = q2_solve(D, F2, qc2, dl);
fprintf('\n=== 同期对照（%s）===\n', mat2str(dl));
fprintf('  Q1 式（完美信息、附件1 电价、附件1 负载剖面不适用）→ 仅作 LP 尺度参考: %.2f 元 / %.1f kWh\n', c1, q1);
fprintf('  Q2（0.8 分位计划 + 5x 紧急）: %.2f 元 | 购电 %.1f kWh | 紧急 %.1f kWh\n', ...
    R2.summary.costTot, R2.summary.qPlanTot, R2.summary.qEmTot);

qc3 = q3_config();  qc3.verbose = false;
qc3.outdir = 'D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\问题三\code\dev_scratch\out\';
F3 = q3_forecast(D, qc3);
R3 = q3_solve(D, F3, qc3, dl);
fprintf('  Q3（0.5 分位计划 + 调整 + 5x 紧急）: %.2f 元 | 计划 %.1f | 调整后 %.1f | 紧急 %.1f kWh\n', ...
    R3.summary.costTot, R3.summary.qPlanTot, R3.summary.qAdjTot, R3.summary.qEmTot);
fprintf('  Q3 不调整对照: %.2f 元\n', R3.summary.costNoAdjTot);
fprintf('  Q3 计划阶段折扣 vs Q2: %.3f%%\n', 100*(R2.summary.costTot - R3.summary.costTot)/R2.summary.costTot);
