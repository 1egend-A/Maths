addpath('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码');
S = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\问题二\out\q2_solution.mat');
R = S.R; qc = S.qc; dt = qc.dt;
nd = numel(R.date);
% 每天紧急购电的区间数、总量
nseg = zeros(nd,1); nslot = zeros(nd,1); qE = zeros(nd,1);
for k = 1:nd
    e = R.gEm(k,:)*dt;                       % kWh，144
    m = e > 1e-9;
    nslot(k) = sum(m);
    qE(k) = sum(e);
    % 数连续段
    d2 = diff([0 m 0]);
    nseg(k) = sum(d2 == 1);
end
fprintf('紧急购电：总段数 = %d ，平均 %.1f 段/天，最大 %d 段/天\n', sum(nseg), mean(nseg), max(nseg));
fprintf('有紧急购电的时段总数 = %d （总时段 %d，占 %.2f%%）\n', sum(nslot), nd*144, 100*sum(nslot)/(nd*144));
fprintf('单段平均长度 = %.2f 个时段\n', sum(nslot)/sum(nseg));
% 阈值影响
for thr = [0 0.1 0.5 1 5 10]
    ns = 0; qq = 0;
    for k = 1:nd
        e = R.gEm(k,:)*dt;  m = e >= thr;
        d2 = diff([0 m 0]);  ns = ns + sum(d2==1);  qq = qq + sum(e(e>=thr));
    end
    fprintf('  阈值 %5.1f kWh : 段数 %6d ，保留电量 %10.1f kWh（占 %.3f%%）\n', ...
        thr, ns, qq, 100*qq/sum(qE));
end
% 单段电量分布
qc_seg = [];
for k = 1:nd
    e = R.gEm(k,:)*dt;  m = e > 1e-9;
    d2 = diff([0 m 0]);  s = find(d2==1);  t2 = find(d2==-1);
    for z = 1:numel(s), qc_seg(end+1) = sum(e(s(z):t2(z)-1)); end
end
fprintf('\n单段电量分位：min=%.3f 25%%=%.3f 50%%=%.3f 75%%=%.3f 95%%=%.3f max=%.1f kWh\n', ...
    min(qc_seg), quantile(qc_seg,.25), median(qc_seg), quantile(qc_seg,.75), ...
    quantile(qc_seg,.95), max(qc_seg));
fprintf('总电量中位段贡献 = %.4f%%\n', 100*median(qc_seg)/sum(qE));
