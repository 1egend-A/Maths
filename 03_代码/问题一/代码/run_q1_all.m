%% run_q1_all.m
% 2026 高教社杯全国大学生数学建模竞赛 C题 问题一
% 一键流程：
% 1) 读取并预处理附件1
% 2) 建立并求解线性规划
% 3) 结果校验
% 4) 按官方模板生成 result1_filled.xlsx
% 5) 生成论文配图
%
% 使用方法：
%   将以下文件放在本脚本同级目录：
%   - 附件1.xlsx
%   - result1.xlsx（官方模板）
%   然后在 MATLAB 命令行运行：
%       run_q1_all
%
% 需要 Optimization Toolbox（linprog）。

clear; clc; close all;

rootDir = fileparts(mfilename('fullpath'));
if isempty(rootDir), rootDir = pwd; end

rawFile      = fullfile(rootDir,'附件1.xlsx');
templateFile = fullfile(rootDir,'result1.xlsx');
outDir       = fullfile(rootDir,'out');
figDir       = fullfile(outDir,'figures');
if ~exist(outDir,'dir'), mkdir(outDir); end
if ~exist(figDir,'dir'), mkdir(figDir); end

fprintf('===== C题 问题一：开始 =====\n');

%% 1. 数据预处理
fprintf('[1/5] 数据预处理...\n');
dataFile = q1_preprocess(rawFile,outDir);

%% 2. 求解
fprintf('[2/5] 线性规划求解...\n');
sol = q1_solve(dataFile,outDir);

%% 3. 校验
fprintf('[3/5] 结果校验...\n');
q1_validate(sol,outDir);

%% 4. 写入官方 result1 模板
fprintf('[4/5] 生成 result1...\n');
if isfile(templateFile)
    q1_export_result1(sol,templateFile,outDir);
else
    warning('未找到 result1.xlsx 模板，跳过官方结果文件写入。');
end

%% 5. 生成论文配图
fprintf('[5/5] 生成论文配图...\n');
q1_visualization(sol,figDir);
q1_make_flowchart(figDir);

fprintf('\n===== 问题一完成 =====\n');
fprintf('全天购电量：%.3f kWh\n',sol.metrics.totalPurchase_kWh);
fprintf('全天购电费：%.3f 元\n',sol.metrics.totalCost_yuan);
fprintf('无储能基准费用：%.3f 元\n',sol.metrics.baseCost_yuan);
fprintf('节省费用：%.3f 元（%.2f%%）\n', ...
    sol.metrics.saving_yuan,100*sol.metrics.savingRate);
fprintf('结果目录：%s\n',outDir);
