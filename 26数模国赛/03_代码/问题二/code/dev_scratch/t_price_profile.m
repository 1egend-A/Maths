function t_price_profile()
addpath('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码');
S = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\问题二\out\q2_solution.mat');
R = S.R; qc = S.qc;
D = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码\out\data.mat').D;
pr = D.day144.price(:);
fprintf('电价：min %.4f (时段%d)  中位 %.4f  max %.4f (时段%d)\n', ...
    min(pr), find(pr==min(pr),1), median(pr), max(pr), find(pr==max(pr),1));
fprintf('\n每整点电价（时段号 = 小时*6+1）：\n');
for h = 0:23
    t = h*6+1;
    fprintf('  %2d:00  p=%.4f   g=0天数 %3d/334   c段合计中该小时=%.0f kWh\n', ...
        h, pr(t), sum(R.gPlan(:,t)<1e-9), sum(R.c(:,t+0:min(t+5,144))*qc.dt, 'all'));
end
fprintf('\n各小时充电量合计（全年，kWh）——看充电集中在哪些时段：\n');
for h = 0:23
    ii = h*6+(1:6);
    fprintf('  %2d:00-%2d:00  %12.1f\n', h, h+1, sum(sum(R.c(:,ii)))*qc.dt);
end
end
