% T_RUN_FULL  全量 334 天求解（非交付物；run_q3_all.m 的第 2 步等价物）
S = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码\out\data.mat');
D = S.D;
qc = q3_config();  qc.verbose = true;
tic; F = q3_forecast(D, qc); save([qc.outdir 'q3_forecast.mat'], 'F', '-v7.3');
fprintf('q3_forecast 用时 %.1f s\n', toc);
tic; R = q3_solve(D, F, qc); fprintf('q3_solve 总用时 %.1f s\n', toc);
