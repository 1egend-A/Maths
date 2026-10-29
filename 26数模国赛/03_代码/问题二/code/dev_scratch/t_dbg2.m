addpath('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码');
D = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码\out\data.mat').D;
S = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\问题二\out\q2_solution.mat'); qc = S.qc;
d = 32;
[c, q, g, fl] = q2_oracle(D.day144.price, D.actual.load(d,:), D.actual.pv(d,:), qc.S0, qc.S_end, qc);
fprintf('flag = %d , cost = %g , q = %g\n', fl, c, q);
fprintf('qc.S_min=%g S_max=%g S0=%g S_end=%g P_max=%g dt=%g eta=%g\n', ...
    qc.S_min, qc.S_max, qc.S0, qc.S_end, qc.P_max, qc.dt, qc.eta);
