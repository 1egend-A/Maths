function run_q4_all(doExp)
% RUN_Q4_ALL  问题四一键流水线（对标 run_q2_all.m / run_q3_all.m）
%
% 步骤：
%   1  配置与数据
%   2  克隆等价性自检（t_q4_clone_check）—— result4-2 的可信度门槛
%   3  Q2 框架预报（q2_forecast，无附件3）
%   4  Q3 框架预报（q3_forecast，附件3 官方光伏预报 + 自预测负载）
%   5  求解 result4-2（q4_solve_p2，问题二框架 + 附件4 电价）
%   6  求解 result4-3（q4_solve_p3，问题三框架 + 附件4 电价）
%   7  校验（q4_validate：A/B/C 两套 + D 模型论断 + E 四问横向对照）
%   8  导出 result4-2.xlsx / result4-3.xlsx
%   9  论文表（q4_paper_tables）
%  10  配图（q4_visualization）
%  11  附加实验（可选，doExp=true，耗时较长）
%
% 用法：run_q4_all        % 1..10
%       run_q4_all(true)  % 1..11（含附加实验）

if nargin < 1 || isempty(doExp), doExp = false; end
HERE = fileparts(mfilename('fullpath'));
cd(HERE);  addpath(HERE);

t0 = tic;
fprintf('==================================================\n');
fprintf(' 问题四 一键流水线\n');
fprintf('==================================================\n');

%% ---- 1. 配置与数据 ----
fprintf('\n[1/10] 配置与数据\n');
qc = q4_config();
fprintf('  priceMode = %s（%s）\n', qc.priceMode, qc.priceNote);
D = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码\out\data.mat').D;
assert(numel(qc.dayIdx) == 334);
fprintf('  求解区间 %s ~ %s，%d 天\n', ...
    string(D.actual.dates(qc.dayIdx(1))), string(D.actual.dates(qc.dayIdx(end))), numel(qc.dayIdx));

%% ---- 2. 克隆等价性自检 ----
fprintf('\n[2/10] 克隆等价性自检（q4_solve_p2 ≡ q2_solve）\n');
okClone = t_q4_clone_check();
assert(okClone, '克隆自检未通过，result4-2 不可信，流水线中止');

%% ---- 3/4. 两套预报 ----
fprintf('\n[3/10] Q2 框架预报（无附件3）\n');
q2c = q2_config();  q2c.verbose = false;
F2 = q2_forecast(D, q2c);
fprintf('  F2：Nhat/Nact 各 %d x %d\n', size(F2.Nhat,1), size(F2.Nhat,2));

fprintf('\n[4/10] Q3 框架预报（附件3 官方光伏预报 + 自预测负载）\n');
F3 = q3_forecast(D, qc);
fprintf('  已生成 F3（pvSource = %s）\n', F3.pvSource);
save([qc.outdir 'q4_forecast.mat'], 'F2', 'F3', '-v7.3');

%% ---- 5. 求解 result4-2 ----
fprintf('\n[5/10] 求解 result4-2（问题二框架 + 附件4 逐日电价）\n');
R2 = q4_solve_p2(D, F2, qc);
save([qc.outdir42 'q4_solution_p2.mat'], 'R2', '-v7.3');
fprintf('  总费用 %14.2f 元 | 购电 %.1f kWh | 紧急 %d 天（%.1f s）\n', ...
    R2.summary.costTot, R2.summary.qPlanTot + R2.summary.qEmTot, R2.summary.nDayEm, R2.solveSec);

%% ---- 6. 求解 result4-3 ----
fprintf('\n[6/10] 求解 result4-3（问题三框架 + 附件4 逐日电价）\n');
R3 = q4_solve_p3(D, F3, qc);
save([qc.outdir43 'q4_solution_p3.mat'], 'R3', '-v7.3');
fprintf('  总费用 %14.2f 元 | 购电 %.1f kWh | 紧急 %d 天（%.1f s）\n', ...
    R3.summary.costTot, R3.summary.qAdjTot + R3.summary.qEmTot, R3.summary.nDayEm, R3.solveSec);

%% ---- 7. 校验 ----
fprintf('\n[7/10] 校验\n');
okV = q4_validate(D, F2, F3, qc, R2, R3);
fprintf('q4_validate -> %d\n', okV);

%% ---- 8. 导出官方结果 ----
fprintf('\n[8/10] 导出 result4-2.xlsx / result4-3.xlsx\n');
q4_export_result4(R2, R3, qc, D);

%% ---- 9. 论文表 ----
fprintf('\n[9/10] 论文表\n');
if exist('q4_paper_tables', 'file') == 2
    q4_paper_tables(R2, R3, qc, D, F2, F3);
else
    fprintf('  （q4_paper_tables.m 尚未生成，跳过）\n');
end

%% ---- 10. 配图 ----
fprintf('\n[10/10] 配图\n');
if exist('q4_visualization', 'file') == 2
    q4_visualization(R2, R3, qc, D, F2, F3);
else
    fprintf('  （q4_visualization.m 尚未生成，跳过）\n');
end

%% ---- 11. 附加实验 ----
if doExp
    fprintf('\n[附加] 实验脚本\n');
    for s = {'t_q4_nearzero','t_q4_term_policy'}
        if exist(s{1}, 'file') == 2
            fprintf('  ---- %s ----\n', s{1});
            feval(s{1});
        else
            fprintf('  （%s.m 尚未生成，跳过）\n', s{1});
        end
    end
end

fprintf('\n==================================================\n');
fprintf(' 问题四流水线完成，用时 %.1f s\n', toc(t0));
fprintf(' 总判定：校验 %s | 克隆自检 %s\n', pass(okV), pass(okClone));
fprintf('==================================================\n');
end

function s = pass(b)
if b, s = 'PASS'; else, s = 'FAIL'; end
end
