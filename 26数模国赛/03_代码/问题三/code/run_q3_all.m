%% run_q3_all.m
% 2026 高教社杯全国大学生数学建模竞赛 C题 问题三
% 一键流程（对标 run_q1_all / run_q2_all，步骤一一对应）：
%   1) 读配置与预处理数据（附件1 电价 + 附件2 实际值 + 附件3 光伏预报）
%   2) 构造四套净负荷预报（负载自预测 + 附件3 四个发布时刻的光伏预报 + 降尺度）
%   3) 四阶段滚动随机规划求解（0:00 定计划；6/12/18 定调整）
%   4) 四层校验 + 四档基准对照（完美信息 / 无储能 / 不调整 / 本模型）
%   5) 生成官方模板 out\result3.xlsx
%   6) 生成论文表（4 个典型日）+ 逐月费用汇总
%   7) 生成论文配图
%   8) 四组敏感性/消融实验（预报时刻消融 / 降尺度 / 结算粒度 / 日末闭环）
%   9) 交叉校验：只读 out\result3.xlsx 与原始数据，独立重算守恒与费用
%
% 使用方法：
%   在 MATLAB 命令行运行：  run_q3_all
%   快速跑通（不跑第 8、9 步）：  run_q3_all_fast
%
% 前置：已跑过 数据预处理代码\run_p0_all.m（或至少生成 out\data.mat）。
%       本脚本只需 Optimization Toolbox（linprog）。全流程约 3~5 分钟。

clear; clc; close all;

rootDir = fileparts(mfilename('fullpath'));
if isempty(rootDir), rootDir = pwd; end
addpath(rootDir);

P0DIR = 'D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码';
addpath(P0DIR);
if ~isfolder(fullfile(rootDir,'out')), mkdir(fullfile(rootDir,'out')); end

fprintf('===== C题 问题三：开始 =====\n');
tAll = tic;

%% 1. 配置 + 数据
fprintf('[1/9] 读取配置与预处理数据...\n');
qc = q3_config();
D  = load(fullfile(P0DIR,'out','data.mat')).D;
fprintf('      区间 %s ~ %s（%d 天）；电价 = 附件1（逐日相同）\n', ...
    string(qc.dateFirst), string(qc.dateLast), numel(qc.dayIdx));
fprintf('      信息集 = 附件3 官方光伏预报 + 自预测负载（口径 7）\n');
fprintf('      决策时刻 %s；分位 计划 %.2f / 调整 %.2f~%.2f\n', ...
    mat2str(qc.fcIssHours), qc.qPlan, qc.qAdjLo, qc.qAdjHi);

%% 2. 预测与降尺度
fprintf('[2/9] 构造四套净负荷预报（负载 %s / 光伏 %s / 降尺度 %s）...\n', ...
    qc.loadMethod, qc.pvSource, qc.dsMethod);
F = q3_forecast(D, qc);
save(fullfile(qc.outdir,'q3_forecast.mat'), 'F', '-v7.3');

%% 3. 四阶段滚动求解
fprintf('[3/9] 四阶段滚动随机规划求解（情景数 %d）...\n', qc.nScen);
% ⚠️ saveSolution 是【显式开关】：q3_solve 默认不落盘，只有这里（正式全量跑）才置真。
%    理由见 q3_solve.m 落盘处的大段注释——诊断脚本反复调用曾把交付解覆盖成残件。
qc.saveSolution = true;
R = q3_solve(D, F, qc);          % 内部落盘 q3_solution.mat

%% 4. 校验 + 基准对照
fprintf('[4/9] 四层校验与基准对照...\n');
ok = q3_validate(D, F, qc, R);
if ~ok
    warning('校验未全部通过，请查看 out\\q3_validate_report.txt');
end

%% 5. 官方模板 result3.xlsx
fprintf('[5/9] 生成 result3.xlsx...\n');
outFile = q3_export_result3(R, qc, D, F);
fprintf('      已写出 %s\n', outFile);

%% 6. 论文表格
fprintf('[6/9] 生成论文表与逐月汇总...\n');
q3_paper_tables(R, qc, D, F);

%% 7. 配图
fprintf('[7/9] 生成论文配图...\n');
figs = q3_visualization(R, F, qc, D);
fprintf('      共 %d 张\n', numel(figs));

%% 8. 实验（消融 / 降尺度 / 粒度 / 闭环）
fprintf('[8/9] 敏感性实验（较慢，逐个尝试，失败不影响前 7 步交付物）...\n');
for f = {'t_q3_ablation','t_q3_downscale','t_q3_granularity','t_q3_term_policy'}
    try
        feval(f{1});
    catch ME
        warning('%s 未完成（%s）', f{1}, ME.message);
    end
end

%% 9. 交叉校验（只读交付文件）
fprintf('[9/9] 交叉校验 result3.xlsx（不读求解代码）...\n');
try
    q3_crosscheck();
catch ME
    warning('交叉校验未完成（%s）', ME.message);
end

%% 汇总
fprintf('\n===== 问题三完成（用时 %.1f s）=====\n', toc(tAll));
S = R.summary;
fprintf('计划购电费：%14.2f 元 | 调整购电费：%12.2f 元 | 紧急购电费：%12.2f 元\n', ...
    S.costPlanTot, S.costAdjTot, S.costEmTot);
fprintf('当日购电总费用：%14.2f 元\n', S.costTot);
fprintf('滚动调整共省 %.2f 元（%.3f%%）\n', ...
    S.costNoAdjTot - S.costTot, 100*(S.costNoAdjTot-S.costTot)/S.costNoAdjTot);
bFile = fullfile(qc.outdir,'q3_bench.mat');
if isfile(bFile)
    B = load(bFile).bench;
    fprintf('  ├ 只调购电量（留用 0:00 充放电）：省 %.2f 元（%.3f%%）\n', ...
        B.saveAdjOnly, 100*B.saveAdjOnly/B.cNoAdj);
    fprintf('  └ 重排充放电（用新信息）：      省 %.2f 元（%.3f%%）\n', ...
        B.saveResched, 100*B.saveResched/B.cNoAdj);
    fprintf('无储能基准 %.2f 元（储能价值 %.2f 元）；完美信息下界 %.2f 元（预测误差代价 %.2f 元）\n', ...
        B.cBase, B.saveStorage, sum(B.cOr), B.costForecast);
end
fprintf('结果目录：%s\n', qc.outdir);
fprintf('  校验报告      out\\q3_validate_report.txt\n');
fprintf('  交叉校验      out\\q3_crosscheck_report.txt\n');
fprintf('  官方模板结果  out\\result3.xlsx\n');
fprintf('  填写说明      out\\result3_填写说明.txt\n');
fprintf('  论文表格      out\\paper_q3_*.csv\n');
fprintf('  论文配图      out\\figures\\fig_q3_*.png\n');
