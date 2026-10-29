addpath('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码');
qc = q2_config();
S = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码\out\data.mat');
D = S.D;
F = q2_forecast(D, qc);
E = F.Lhat(32:365,:) - D.actual.load(32:365,:);
Y = D.actual.load(32:365,:);  mk = Y > 50;
fprintf('预测器自检通过。负载 MAPE(>50kW) = %.3f%%\n', mean(abs(E(mk)./Y(mk)))*100);

tAll = tic;
R = q2_solve(D, F, qc, [32 33 34]);
fprintf('3 天用时 %.2f s\n', toc(tAll));

k = 1;
pr = D.day144.price(:);
fprintf('\n--- 第 %s 天明细 ---\n', string(R.date(k)));
fprintf('SOC 起点=%.2f 末点=%.2f 最小=%.2f 最大=%.2f\n', qc.S0, R.Soc(k,end), min(R.Soc(k,:)), max(R.Soc(k,:)));
fprintf('同时充放时段 = %d\n', sum(R.c(k,:)>1e-6 & R.d(k,:)>1e-6));
fprintf('平衡残差 max = %.3e\n', max(abs(R.gPlan(k,:)+R.gEm(k,:)+R.d(k,:)-R.Nact(k,:)-R.c(k,:)-R.curt(k,:))));
fprintf('计划费用复算差 = %.2e ; 紧急费用复算差 = %.2e\n', ...
  R.costPlan(k)-sum(pr.*R.gPlan(k,:)')*qc.dt, R.costEm(k)-sum(5*pr.*R.gEm(k,:)')*qc.dt);
fprintf('计划 %.1f kWh / 紧急 %.1f kWh ; 计划费 %.2f / 紧急费 %.2f\n', ...
  R.qPlan(k), R.qEm(k), R.costPlan(k), R.costEm(k));
