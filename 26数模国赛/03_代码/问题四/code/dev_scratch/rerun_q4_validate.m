function rerun_q4_validate()
% RERUN_Q4_VALIDATE  只重跑第 7 步 q4_validate，复用已落盘的 mat，不重解 LP。
%
% 背景：q3_validate 曾无视传入的 qc、把报告写进 问题三/out/，
%       导致问题三的校验报告被本问的附件4 结果覆盖（已修）。
%       修好后需要重跑一次 q4_validate，让
%         · 问题四/out/q4_validate_report.txt 反映修正后的 D' 层
%         · 问题四/out/q4_q3_validate_report.txt 落位（带 q4_ 前缀）
%       而不再触碰 问题三/out/。

addpath('..');
here = fileparts(mfilename('fullpath'));
addpath(here);
root = fileparts(fileparts(here));

qc = q4_config();
fprintf('读入预报 %s\n', fullfile(root, 'out', 'q4_forecast.mat'));
L  = load(fullfile(root, 'out', 'q4_forecast.mat'), 'F2', 'F3');
L2 = load(fullfile(root, 'out42', 'q4_solution_p2.mat'), 'R2');
L3 = load(fullfile(root, 'out43', 'q4_solution_p3.mat'), 'R3');
D  = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码\out\data.mat').D;

fprintf('R2 总费用 %14.2f 元（%d 天）\n', L2.R2.summary.costTot, L2.R2.summary.nDay);
fprintf('R3 总费用 %14.2f 元（%d 天）\n', L3.R3.summary.costTot, L3.R3.summary.nDay);

ok = q4_validate(D, L.F2, L.F3, qc, L2.R2, L3.R3);
fprintf('\nq4_validate -> %d\n', ok);
end
