% T_AFTER_SOLVE  开发期：复用已落盘的解，只跑校验/导出/论文表/交叉校验
D = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码\out\data.mat').D;
qc = q3_config();
F = load([qc.outdir 'q3_forecast.mat']).F;
R = load([qc.outdir 'q3_solution.mat']).R;

fprintf('===== [C] 校验 =====\n');
ok = q3_validate(D, F, qc, R);
fprintf('q3_validate -> %d\n', ok);

fprintf('\n===== [D] 导出 result3.xlsx =====\n');
q3_export_result3(R, qc, D, F);

fprintf('\n===== [E] 论文表 =====\n');
q3_paper_tables(R, qc, D, F);

fprintf('\n===== [F] 交叉校验 =====\n');
q3_crosscheck();
fprintf('\n===== 完成 =====\n');
