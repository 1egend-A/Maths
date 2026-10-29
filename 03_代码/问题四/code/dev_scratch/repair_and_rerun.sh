#!/bin/bash
# repair_and_rerun.sh —— 修复被诊断脚本覆盖的两份交付解，并按序重跑 Q3/Q4 流水线
#
# 事故：q2_solve.m / q3_solve.m 都在结尾【无条件】把解写进 qc.outdir。
#       诊断脚本（t_q4_clone_check 跑 5 天；t_q3_planquant / t_q3_lpcoef 跑 60 天）
#       沿用交付 outdir，把全量解覆盖成残件：
#         问题二\out\q2_solution.mat  14,565,425.45 元  →  261,173.17 元（5 天）
#         问题三\out\q3_solution.mat  14,724,901.09 元  →  约 2.55e6 元（60 天子区间）
#       修法：q3_solve 改为显式开关 qc.saveSolution（默认不写）；
#             q2_solve 已交付不可改，故在 t_q4_clone_check 侧把 outdir 指到隔离目录。
# 本脚本：① 重算问题二全量解并核对三个交付数字；
#         ② 重跑问题三流水线（恢复 canonical 落盘）；
#         ③ 重跑问题四流水线。

ROOT="D:/HuaweiMoveData/Users/26313/Desktop/2026数模国赛"
LOG="$ROOT/问题四/code/dev_scratch/repair.log"
: > "$LOG"

say() { echo "$@" | tee -a "$LOG"; }

say "################ [1/3] 修复问题二交付解 ################"
cd "$ROOT/问题二/code" || exit 1
matlab -batch "
addpath('$ROOT/问题二/code','$ROOT/数据预处理代码');
D = load('$ROOT/数据预处理代码/out/data.mat').D;
q2c = q2_config();  q2c.verbose = true;
F2 = q2_forecast(D, q2c);
R = q2_solve(D, F2, q2c);          % 全量 334 天，写回 问题二/out/q2_solution.mat
fprintf('\n== 修复核对（期望：14565425.45 / 22099227.8 / 295713.1 / 331）==\n');
fprintf('   costTot  = %.2f 元\n', R.summary.costTot);
fprintf('   qPlanTot = %.1f kWh\n', R.summary.qPlanTot);
fprintf('   qEmTot   = %.1f kWh\n', R.summary.qEmTot);
fprintf('   nDayEm   = %d 天\n',   R.summary.nDayEm);
ok = abs(R.summary.costTot-14565425.45) < 0.05 && ...
     abs(R.summary.qPlanTot-22099227.8) < 1   && ...
     abs(R.summary.qEmTot-295713.1)   < 1;
if ok, fprintf('   判定：PASS（交付解已复原）\n');
else,  fprintf('   判定：FAIL（交付解未复原）\n'); end
assert(ok, '问题二交付解未能复原，停止后续步骤');
fprintf('RESTORE_Q2_OK\n');
" 2>&1 | iconv -f GBK -t UTF-8 | tee -a "$LOG"
grep -q RESTORE_Q2_OK "$LOG" || { say "!! 问题二修复失败，中止"; exit 1; }

say ""
say "################ [2/3] 重跑问题三流水线 ################"
cd "$ROOT/问题三/code" || exit 1
matlab -batch "run_q3_all" 2>&1 | iconv -f GBK -t UTF-8 | tee -a "$LOG"

say ""
say "################ [3/3] 重跑问题四流水线 ################"
cd "$ROOT/问题四/code" || exit 1
matlab -batch "run_q4_all" 2>&1 | iconv -f GBK -t UTF-8 | tee -a "$LOG"

say ""
say "################ 完成 ################"
