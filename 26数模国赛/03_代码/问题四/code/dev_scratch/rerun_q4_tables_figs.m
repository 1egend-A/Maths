function rerun_q4_tables_figs()
% RERUN_Q4_TABLES_FIGS  只重跑 run_q4_all 的第 9、10 步（论文表 + 配图）。
%
% 为什么需要它：run_q4_all 第 9 步（q4_paper_tables）曾因 R2 字段名不匹配
% （R2 用 gPlan / c / d，而 q3_paper_tables 只认 G / C / D）抛错，
% 且第 9 步没有 try/catch —— 于是第 10 步配图【根本没跑】，
% 问题四/out/figures/ 为空。
%
% 修好 compatP2 之后，没有必要把整条流水线（含两轮 LP 求解）重跑一遍：
% R2 / R3 已经落在 out42/ 与 out43/ 里，直接读回来喂给后两步即可。
% 这既省时间，也避免"重跑一遍求解器"引入新的不确定性。
%
% ⚠️ 本脚本只读 out42 / out43 的 .mat，只写 out/ 下的论文表与 figures/，
%    不写任何交付解文件（沿用问题三事故的隔离原则）。

HERE = fileparts(mfilename('fullpath'));
Q4   = fileparts(HERE);                 % 问题四/code
addpath(Q4);
cd(Q4);

qc = q4_config();
D  = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码\out\data.mat').D;

f2 = [qc.outdir42 'q4_solution_p2.mat'];
f3 = [qc.outdir43 'q4_solution_p3.mat'];
assert(isfile(f2), '缺少 %s', f2);
assert(isfile(f3), '缺少 %s', f3);
R2 = load(f2, 'R2').R2;
R3 = load(f3, 'R3').R3;

ff = [qc.outdir 'q4_forecast.mat'];
assert(isfile(ff), '缺少 %s（请先跑 run_q4_all 的前 4 步）', ff);
S = load(ff);  F2 = S.F2;  F3 = S.F3;

% ⚠️ 两套框架的字段层级不同：R2 有顶层 costTot（逐日向量），R3 只在 summary 里存总费用。
%    写死了 R3.costTot 会报「无法识别的字段名称 "costTot"」。
fprintf('读入 R2：总费用 %.2f 元（%d 天）\n', R2.summary.costTot, numel(R2.costTot));
fprintf('读入 R3：总费用 %.2f 元（%d 天）\n', R3.summary.costTot, R3.summary.nDay);

fprintf('\n[9/10] 论文表\n');
q4_paper_tables(R2, R3, qc, D, F2, F3);

fprintf('\n[10/10] 配图\n');
figs = q4_visualization(R2, R3, qc, D, F2, F3);
fprintf('配图完成：%d 张\n', numel(figs));

fprintf('\n---- 产物核对 ----\n');
d = dir([qc.outdir 'paper_q4_*.csv']);
fprintf('论文表 %d 个：\n', numel(d));
for i = 1:numel(d), fprintf('  %s  (%d bytes)\n', d(i).name, d(i).bytes); end
d = dir([qc.outdir 'figures' filesep '*.png']);
fprintf('配图 %d 张：\n', numel(d));
for i = 1:numel(d), fprintf('  %s  (%d bytes)\n', d(i).name, d(i).bytes); end
end
