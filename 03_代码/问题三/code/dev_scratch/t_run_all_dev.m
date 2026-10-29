% T_RUN_ALL_DEV  开发期：全流程 2~6 步（预测/求解/校验/导出/论文表/交叉校验）
% 非交付物。正式的交付入口是 code/../run_q3_all.m，配图与实验另行补上。
D = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码\out\data.mat').D;
qc = q3_config();

fprintf('===== [A] 预测 =====\n');
tic; F = q3_forecast(D, qc); fprintf('q3_forecast %.1f s\n', toc);
save([qc.outdir 'q3_forecast.mat'], 'F', '-v7.3');

fprintf('\n===== [B] 求解 =====\n');
tic; R = q3_solve(D, F, qc); fprintf('q3_solve %.1f s\n', toc);

fprintf('\n===== [C] 校验 =====\n');
ok = q3_validate(D, F, qc, R);
fprintf('q3_validate -> %d\n', ok);

fprintf('\n===== [D] 导出 result3.xlsx =====\n');
q3_export_result3(R, qc, D, F);

fprintf('\n===== [E] 论文表 =====\n');
q3_paper_tables(R, qc, D, F);

fprintf('\n===== [F] 交叉校验 =====\n');
q3_crosscheck();

fprintf('\n===== 开发全流程结束 =====\n');
