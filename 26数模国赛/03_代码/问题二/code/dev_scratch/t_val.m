addpath('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码');
S = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\问题二\out\q2_solution.mat');
ok = q2_validate([], [], S.qc, S.R);
fprintf('\n>>> q2_validate 返回 ok = %d\n', ok);
