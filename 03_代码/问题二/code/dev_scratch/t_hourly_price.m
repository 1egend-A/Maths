function t_hourly_price()
P0DIR = 'D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码';
if isempty(which('p0_config')), addpath(P0DIR); end
qc = q2_config();
D  = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码\out\data.mat').D;
pr = D.day144.price(:);
fprintf('中位数 %.4f  最小 %.4f(idx %d)  最大 %.4f(idx %d)\n', ...
    median(pr), min(pr), find(pr==min(pr),1), max(pr), find(pr==max(pr),1));
fprintf('\n逐小时电价（该小时 6 个时段的均值）：\n');
for h = 0:23
    ii = h*6 + (1:6);
    fprintf('  %2d:00-%2d:00  %.4f\n', h, h+1, mean(pr(ii)));
end
R = load([qc.outdir 'q2_solution.mat']).R;
slotT1 = (600:120:1200)/10 + 1;
lab = {'10:00','12:00','14:00','16:00','18:00','20:00'};
fprintf('\n指定时段：电价 / 全年 g>0 天数 / 全年充电量(kWh)\n');
for c = 1:6
    j = slotT1(c);
    fprintf('  %s  p=%.4f  g>0 = %3d/334  充电 = %.1f\n', ...
        lab{c}, pr(j), sum(R.gPlan(:,j)>1e-9), sum(R.c(:,j))*qc.dt);
end
fprintf('\n17:00-21:00 全年充电量 = %.1f kWh\n', sum(sum(R.c(:, 17*6+1 : 21*6)))*qc.dt);
end
