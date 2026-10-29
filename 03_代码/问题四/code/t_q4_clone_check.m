function ok = t_q4_clone_check()
% T_Q4_CLONE_CHECK  q4_solve_p2 与 q2_solve 的等价性自检（克隆正确性的担保）
%
% 背景：问题二已交付，其 q2_solve.m 不得改动；而问题四的 result4-2 需要
%       「问题二框架 + 附件4 逐日电价」。故 q4_solve_p2.m 是 q2_solve.m 的受控克隆，
%       唯一的概念差异是电价逐日不同。
%
% 本脚本给出该克隆的正确性证明：
%       把电价强制回「附件1 逐日相同」（prOverride = repmat(D.day144.price,nd,1)），
%       在同一 F、同一天集上跑两个求解器，结果必须【逐位一致】。
%       若不一致，说明克隆时手滑改了别的东西，result4-2 不可信。
%
% 校验对象：gPlan(计划购电量) / gLp(LP 原始解) / c / d / Soc / costPlan / costEm /
%           qPlan / qEm / costExp —— 覆盖决策变量、实际量与费用三方面。
%
% 用法：ok = t_q4_clone_check();

% ⚠️ 必须先调 q4_config：它负责把 数据预处理代码/问题二/问题三 三个目录加进 path。
%    若先调 q2_config 会报「函数或变量 'q2_config' 无法识别」——不是 q2_config 有问题，
%    是本进程的 path 还没被建立起来。这里显式补一次，免得依赖调用顺序。
addpath('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\问题二\code', ...
        'D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\问题三\code', ...
        'D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码');

D    = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码\out\data.mat').D;
q4c  = q4_config();
q2c  = q2_config();

fprintf('===== q4_solve_p2 vs q2_solve 等价性自检 =====\n');

% ---- 前置：两套配置的物理参数与口径必须逐项相同，否则比较无意义 ----
pars = {'eta','P_max','S_min','S_max','S0','S_end','dt','nScen'};
for i = 1:numel(pars)
    p = pars{i};
    assert(isequal(q2c.(p), q4c.(p)), ...
        '参数 %s 在 q2_config 与 q4_config 中不一致（%g vs %g）', p, q2c.(p), q4c.(p));
end
assert(isequal(q2c.dayIdx, q4c.dayIdx), 'dayIdx 不一致');
fprintf('  参数对齐：%s 逐项相同，dayIdx 相同（%d 天）\n', strjoin(pars, '/'), numel(q2c.dayIdx));

% ---- 同一套预测（q2_forecast），只用前 5 天做比较（足以暴露任何差异）----
F2  = q2_forecast(D, q2c);
ns  = 5;
sub = q2c.dayIdx(1:ns);
fprintf('  比较区间：%s ~ %s（%d 天）\n', ...
    string(D.actual.dates(sub(1))), string(D.actual.dates(sub(end))), ns);

% ---- 运行 1：问题二原版（逐日相同电价）----
% ⚠️⚠️ 必须把 outdir 指到隔离目录，否则【会覆盖问题二已交付的全量解】。
%    机理：q2_solve.m 结尾无条件 save([qc.outdir 'q2_solution.mat'], ...)（第 245 行），
%    而 q2_config 的 outdir 就是 问题二\out\。本自检只跑 5 天（sub = dayIdx(1:5)），
%    一旦沿用交付 outdir，就会把 334 天、14,565,425.45 元的交付解【覆盖成 5 天的残件】。
%    本队实测已中招一次：问题二\out\q2_solution.mat 被写成 261,173.17 元的 5 天残件，
%    连带 q4_validate 的四问对照表把 Q2 读成 261,173.17 元（真值 14,565,425.45 元）。
%    故此处物理隔离，交付目录一个字节都不碰。
SCO = fullfile(fileparts(mfilename('fullpath')), 'dev_scratch', 'out');
if ~isfolder(SCO), mkdir(SCO); end
q2c.outdir  = [SCO '\'];
q4c.outdir  = [SCO '\'];
q2c.verbose = false;
Rq2 = q2_solve(D, F2, q2c, sub);

% ---- 运行 2：克隆，电价强制回附件1 剖面 ----
prFix = repmat(D.day144.price(:)', ns, 1);
q4c.verbose = false;
Rq4 = q4_solve_p2(D, F2, q4c, sub, prFix);

% ---- 逐位比较 ----
flds = {'gPlan','gLp','c','d','Soc','costPlan','costEm','costExp','qPlan','qEm','gEm','curt'};
ok = true;
fprintf('\n  %-10s %-14s %-14s %s\n', '字段', '最大绝对差', '相对尺度', '判定');
for i = 1:numel(flds)
    a = Rq2.(flds{i});  b = Rq4.(flds{i});
    assert(isequal(size(a), size(b)), '字段 %s 维度不一致', flds{i});
    dmax = max(abs(a(:) - b(:)));
    scale = max([abs(a(:)); 1]);
    good = dmax <= 1e-9 * max(scale, 1);
    ok = ok && good;
    fprintf('  %-10s %-14.3e %-14.3e %s\n', flds{i}, dmax, scale, pass(good));
end

% ---- 费用总量复核 ----
fprintf('\n  总费用：q2_solve %.6f 元 | q4_solve_p2 %.6f 元 | 差 %.3e 元\n', ...
    Rq2.summary.costTot, Rq4.summary.costTot, abs(Rq2.summary.costTot - Rq4.summary.costTot));
ok = ok && abs(Rq2.summary.costTot - Rq4.summary.costTot) < 1e-6;

% ---- 反例检查：用【附件4 逐日电价】跑必须给出不同结果 ----
% 否则说明 prOverride 通道没接上，上面的一致性可能是"两边都忽略了电价"造成的假一致。
Rq4v = q4_solve_p2(D, F2, q4c, sub);
dCost = abs(Rq4v.summary.costTot - Rq4.summary.costTot);
fprintf('  对照（改用附件4 逐日电价）：总费用 %.6f 元，与固定电价差 %.3f 元\n', ...
    Rq4v.summary.costTot, dCost);
assert(dCost > 1e-6, 'prOverride 通道疑似未生效：换电价后费用没变，上面的"一致"是假一致');
fprintf('  ✓ 电价通道确实生效（换电价 ⇒ 费用改变），故上面的一致性是真一致\n');

fprintf('\n  自检结论：%s\n', pass(ok));
if ~ok
    error('q4_solve_p2 与 q2_solve 不等价——result4-2 不可信，须先修克隆');
end
end

function s = pass(b)
if b, s = 'PASS'; else, s = 'FAIL'; end
end
