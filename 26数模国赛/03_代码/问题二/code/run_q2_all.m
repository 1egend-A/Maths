%% run_q2_all.m
% 2026 高教社杯全国大学生数学建模竞赛 C题 问题二
% 一键流程：
%   1) 读配置与预处理数据（附件1 电价 + 附件2 负载/光伏）
%   2) 日前预测（负载 blend / 光伏 mean7）
%   3) 两阶段随机规划求解（计划购电量 + 紧急购电）
%   4) 结果校验 + 与两个基准对照
%   5) 生成官方模板 out\result2.xlsx
%   6) 生成论文表 1/表 2/表 3
%   7) 生成论文配图
%   8) 口径 2 敏感性实验（日末闭环的代价）
%
% 使用方法：
%   在 MATLAB 命令行运行：  run_q2_all
%
% 前置：已跑过 数据预处理代码\run_p0_all.m（或至少生成 out\data.mat）。
%       本脚本只需 Optimization Toolbox（linprog）。
%
% 与问题一的对应关系：本文件对标队友的 run_q1_all.m，步骤一一对应，
% 另加第 8 步（口径 2 敏感性），因为问题二多出一条「日末闭环」口径需要交代。

clear; clc; close all;

rootDir = fileparts(mfilename('fullpath'));
if isempty(rootDir), rootDir = pwd; end

P0DIR = 'D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码';
addpath(P0DIR);
if ~isfolder(fullfile(rootDir,'out')), mkdir(fullfile(rootDir,'out')); end

fprintf('===== C题 问题二：开始 =====\n');
tAll = tic;

%% 1. 配置 + 数据
fprintf('[1/8] 读取配置与预处理数据...\n');
qc = q2_config();
D  = load(fullfile(P0DIR,'out','data.mat')).D;
fprintf('      区间 %s ~ %s（%d 天）；信息集 = %s\n', ...
    string(qc.dateFirst), string(qc.dateLast), numel(qc.dayIdx), qc.infoSet);

%% 2. 预测
fprintf('[2/8] 日前预测（负载 %s / 光伏 %s）...\n', qc.loadMethod, qc.pvMethod);
F = q2_forecast(D, qc);

%% 3. 求解
fprintf('[3/8] 两阶段随机规划求解（情景数 %d）...\n', qc.nScen);
R = q2_solve(D, F, qc);

%% 4. 校验 + 基准对照
fprintf('[4/8] 校验与基准对照...\n');
ok = q2_validate(D, F, qc, R);
if ~ok
    warning('校验未全部通过，请查看 out\\q2_validate_report.txt');
end

%% 5. 官方模板 result2.xlsx
fprintf('[5/8] 生成 result2.xlsx...\n');
outFile = q2_export_result2(R, qc, D);
fprintf('      已写出 %s\n', outFile);

%% 6. 论文表格
fprintf('[6/8] 生成论文表 1/2/3...\n');
q2_paper_tables(R, qc, D);

%% 7. 配图
fprintf('[7/8] 生成论文配图...\n');
figs = q2_visualization(R, F, qc, D);
fprintf('      共 %d 张\n', numel(figs));

%% 8. 口径 2 敏感性（可选：大 LP，约需数分钟）
fprintf('[8/8] 口径 2 敏感性实验（全区间 LP，较慢）...\n');
try
    t_q2_term_policy();
catch ME
    warning('口径 2 敏感性实验未完成（%s），不影响前 7 步的交付物。', ME.message);
end

%% 汇总
fprintf('\n===== 问题二完成（用时 %.1f s）=====\n', toc(tAll));
fprintf('计划购电量：%.1f kWh  计划购电费：%.2f 元\n', ...
    R.summary.qPlanTot, R.summary.costPlanTot);
fprintf('紧急购电量：%.1f kWh  紧急购电费：%.2f 元\n', ...
    R.summary.qEmTot, R.summary.costEmTot);
fprintf('全日购电费合计：%.2f 元\n', R.summary.costTot);
% 基准值由 q2_validate 落盘到 q2_bench.mat，这里直接读，避免重复求解
bFile = fullfile(qc.outdir,'q2_bench.mat');
if isfile(bFile)
    B = load(bFile).bench;
    fprintf('无储能基准：%.2f 元（储能价值 %.2f 元，降幅 %.2f%%）\n', ...
        B.cBase, B.saveCost, 100*B.saveCost/B.cBase);
    fprintf('完美信息下界：%.2f 元（预测误差代价 %.2f 元，升幅 %.2f%%）\n', ...
        sum(B.cOr), B.forecastCost, 100*B.forecastCost/sum(B.cOr));
    fprintf('紧急购电费占比：%.2f%%\n', 100*R.summary.costEmTot/R.summary.costTot);
else
    fprintf('（未找到 q2_bench.mat，基准对照见 out\\q2_validate_report.txt）\n');
end
fprintf('结果目录：%s\n', qc.outdir);
fprintf('  校验报告      out\\q2_validate_report.txt\n');
fprintf('  官方模板结果  out\\result2.xlsx\n');
fprintf('  填写说明      out\\result2_填写说明.txt\n');
fprintf('  论文表格      out\\paper_table1.csv ~ paper_table4_收支.csv\n');
fprintf('  论文配图      out\\figures\\fig_q2_*.png\n');
