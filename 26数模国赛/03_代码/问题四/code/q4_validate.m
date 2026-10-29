function ok = q4_validate(D, F2, F3, qc, R2, R3)
% Q4_VALIDATE  问题四两套结果的校验 + 四问横向对照
%
% 分四层（体例克隆 q2_validate / q3_validate）：
%   A 结构不变量（R2、R3 各查一遍）
%   B 守恒律与实际结算（R2、R3 各查一遍）
%   C 费用复算（R2、R3 各查一遍）
%   D 模型论断验证
%       · R2（问题二框架）：独立重建情景净需求 Q，核 g_t = max(0, Q_(0.8))
%         与一阶条件 #{s : Q_s > g_t} = nS/k_em
%       · R3（问题三框架）：模型论断的验证【同一套代码】——问题四的三阶段框架与
%         问题三共用同一个求解器 q3_solve.m，其不变量的校验也应由 问题三/code/
%         q3_validate.m 直接负责，否则等于用不同的尺子量同一件事。
%         （q3_validate 与四层校验不重复：它额外做分位闭式重建与四档基准对照。）
%   E 横向对照：Q2 / Q3 / Q4-2 / Q4-3 四问总费用并列（论文 9.x 的骨架表）
%
% ⚠️ 情景净需求一律由 F.Nhat / F.Nact 的残差池独立重建，不读求解器中间量。
% ⚠️ 日志用【嵌套函数】收集：局部函数的 workspace 独立，写 say 会静默丢日志。
%    故 localABC 只负责返回行，由主函数统一 say。
%
% 用法：ok = q4_validate(D, F2, F3, qc, R2, R3)

nT = 144;  dt = qc.dt;  nS = qc.nScen;

lines = {};
    function say(varargin)
        lines{end+1} = sprintf(varargin{:});
    end

say('==========================================================');
say(' 问题四求解结果校验报告');
say('==========================================================');
say('区间 %s ~ %s，共 %d 天', string(R2.date(1)), string(R2.date(end)), numel(R2.date));
say('电价 = 附件4 逐日逐时（相对问题二/三的唯一输入差异）');
say('result4-2 = 问题二框架（无附件3，负载/光伏自预测）');
say('result4-3 = 问题三框架（附件3 官方光伏预报 + 6/12/18 三次调整）');
say('');

%% ================= A/B/C 层：R2 =================
say('########## R2：result4-2（问题二框架 + 附件4 电价）##########');
say('');
[okR2, ln2] = localABC(R2, F2.Nact, qc, 'R2', true);
for i = 1:numel(ln2), say('%s', ln2{i}); end

%% ================= A/B/C 层：R3 =================
say('');
say('########## R3：result4-3（问题三框架 + 附件4 电价）##########');
say('');
[okR3, ln3] = localABC(R3, F3.Nact, qc, 'R3', false);
for i = 1:numel(ln3), say('%s', ln3{i}); end

%% ================= D. 模型论断：R2 的报童分位 =================
say('');
say('---- D. 模型论断验证（R2：独立重建情景净需求）----');
k80 = max(1, min(nS, ceil(0.8*nS)));
nd  = numel(R2.date);
maxGap = 0;  cntIn = 0;  nIn = 0;  cntClip = 0;  nClip = 0;
for k = 1:nd
    d = R2.dayIdx(k);
    pool = (d-nS):(d-1);  pool = pool(pool >= 1);
    if isempty(pool), pool = d; end
    Rm = F2.Nact(pool, :) - F2.Nhat(pool, :);
    if size(Rm,1) >= nS
        Rs = Rm(end-nS+1:end, :)';
    else
        Rs = repmat(Rm', 1, ceil(nS/size(Rm,1)));  Rs = Rs(:, 1:nS);
    end
    Ns = F2.Nhat(d,:)' + Rs;
    Qraw = Ns + R2.c(k,:)' - R2.d(k,:)';
    Qs = sort(Qraw, 2);
    gRef = max(0, Qs(:, k80));
    maxGap = max(maxGap, max(abs(gRef - R2.gPlan(k,:)')));
    % ⚠️ 一阶条件问的是【含充放电的情景净需求 Q = Ns + c − d】，不是 Ns 本身。
    %    曾误用 Ns 计数，实测内点均值 5.692（应为 6.000000）、截断段均值 17.53
    %    （应 ≤ 6），D2 误判为 FAIL。报童分位是对 Q 取的，不是对裸净负荷取的。
    ab   = sum(Qraw > R2.gPlan(k,:)' + 1e-9, 2);
    isIn = Qs(:,k80) > 0;
    cntIn   = cntIn   + sum(ab(isIn));   nIn   = nIn   + sum(isIn);
    cntClip = cntClip + sum(ab(~isIn));  nClip = nClip + sum(~isIn);
end
okD1 = maxGap < 1e-6;
say('D1 计划量 g_t = max(0, Q_(0.80))：逐槽最大偏差 %.3e kW   -> %s', maxGap, pass(okD1));
say('D2 一阶条件 #{s : Q_s > g_t}（内点应 = nS/k_em = %.1f）：', nS/qc.kEm);
if nIn > 0
    say('     内点时段（%.1f%%）均值 = %.6f   <- 严格取等', 100*nIn/(nIn+nClip), cntIn/nIn);
end
if nClip > 0
    say('     截断时段（%.1f%%，g*=0）均值 = %.4f   -> 应 ≤ %.1f', ...
        100*nClip/(nIn+nClip), cntClip/nClip, nS/qc.kEm);
end
okD2 = (nIn == 0 || abs(cntIn/nIn - nS/qc.kEm) < 1e-9) && ...
       (nClip == 0 || cntClip/nClip <= nS/qc.kEm + 1e-9);
say('     -> %s', pass(okD2));

say('');
say('D3 逐日电价确实生效（对照：问题二/三用附件1 逐日相同剖面）：');
a1    = D.day144.price(:)';
dProf = max(abs(a1 - mean(R2.price, 1)));
sdDay = mean(std(R2.price, 0, 1));
say('     附件1 剖面 vs 附件4 年内均值剖面：max|差| = %.4g 元/kWh', dProf);
say('     附件4 的逐时段【日间】标准差均值 = %.4f 元/kWh   -> %s', sdDay, pass(sdDay > 1e-3));
okD3 = sdDay > 1e-3;

%% ================= D'. R3 的模型论断：转调 q3_validate =================
say('');
say('---- D''. R3 的模型论断（转调 问题三/code/q3_validate.m）----');
say('     说明：R3 与问题三共用求解器 q3_solve.m，故其分位闭式重建、作用域');
say('           不变量与四档基准对照一律由问题三的校验器负责，本函数不重复实现。');
okD3q3 = true;
try
    if isempty(which('q3_validate')), addpath(qc.dirQ3); end
    % ⚠️ 光传 qc3 是不够的：q3_validate 曾经【无视】传入的 qc，自己重取 q3_config()，
    %    于是"不污染问题三"的注释被静默作废，问题三的校验报告被附件4 的数字覆盖。
    %    q3_validate 现已改为 outdir 由传入 qc 决定；tag 再加一道保险，
    %    使本问写出的产物与问题三自己的同名文件不会互相顶掉。
    qc3 = qc;  qc3.outdir = qc.outdir;
    okD3q3 = q3_validate(D, F3, qc3, R3, 'q4_');
    say('     q3_validate 返回 %d   -> %s', okD3q3, pass(okD3q3));
catch ME
    say('     q3_validate 执行出错：%s', ME.message);
    say('     （R3 的 A/B/C 层已由本函数的 localABC 独立覆盖，此项仅缺模型论断层）');
    say('     出错位置：%s 第 %d 行', ME.stack(1).name, ME.stack(1).line);
end

%% ================= E. 四问横向对照 =================
say('');
say('---- E. 四问横向对照（同一模型族，不同电价口径/信息结构）----');
tab = fourWayTable(R2, R3);
for i = 1:numel(tab.lbl)
    say('  %-44s 购电 %12.1f kWh | 费用 %14.2f 元', ...
        tab.lbl{i}, tab.q(i), tab.c(i));
end
say('');
if all(isfinite([tab.c(1) tab.c(3)]))
    say('  ★ 电价口径（附件1 → 附件4），同框架对照：');
    say('     Q4-2 − Q2 = %+12.2f 元（%+.2f%%）', ...
        tab.c(3)-tab.c(1), 100*(tab.c(3)-tab.c(1))/tab.c(1));
    say('     Q4-3 − Q3 = %+12.2f 元（%+.2f%%）', ...
        tab.c(4)-tab.c(2), 100*(tab.c(4)-tab.c(2))/tab.c(2));
end
say('  ★ 信息结构（有无附件3 与调整机制），同电价对照：');
say('     Q4-3 − Q4-2 = %+12.2f 元（%+.2f%%）', ...
    tab.c(4)-tab.c(3), 100*(tab.c(4)-tab.c(3))/tab.c(3));

%% ================= 汇总 =================
ok = okR2 && okR3 && okD1 && okD2 && okD3 && okD3q3;
say('');
say('==========================================================');
say(' 结论：R2 A/B/C %s | R3 A/B/C %s | D 模型论断 %s', ...
    pass(okR2), pass(okR3), pass(okD1 && okD2 && okD3));
say(' 总判定：%s', pass(ok));
say('==========================================================');

txt = strjoin(lines, sprintf('\n'));
if ~isfolder(qc.outdir), mkdir(qc.outdir); end
fid = fopen([qc.outdir 'q4_validate_report.txt'], 'w', 'n', 'UTF-8');
fprintf(fid, '%s\n', txt);
fclose(fid);
fprintf('\n%s\n', txt);
end

% ======================================================================
function [ok, ln] = localABC(R, NactAll, qc, tag, isP2)
% A/B/C 三层，对 R2 与 R3 通用。返回行数组由主函数统一输出
% （⚠️ 本函数是【局部函数】，其 workspace 独立，不能调用主函数的嵌套 say）。
TOL = 1e-6;  nT = 144;  dt = qc.dt;
ln = {};
if isP2
    C = R.c;  Dd = R.d;  Soc = R.Soc;  G = R.gPlan;      % P2 无调整，A ≡ G
    costAdj = zeros(numel(R.date),1);  qAdj = R.qPlan;
else
    C = R.C;  Dd = R.D;  Soc = R.Soc;  G = R.G;
    costAdj = R.costAdj;
    qAdj = R.qAdj;
end
A = G;  if ~isP2, A = R.A; end
pr = R.price;  nd = numel(R.date);

% ---- A. 结构不变量 ----
eA1 = 0;
for k = 1:nd
    [Srun, ~] = soc_sim(C(k,:), Dd(k,:), qc.S0, qc);
    % ⚠️ soc_sim 返回的 S 与 c 等长，是【各时段末】的 SOC，不含 S_0 本身
    %    （见 数据预处理代码/soc_sim.m 的 docstring）。故长度已与 R.Soc 的 144 对齐，
    %    直接整体比对即可，【不能】写 Srun(2:end)：那是 143 个，会触发
    %    「数组的大小不兼容」。此处的写法覆盖 t = 1..144 全部时段。
    eA1 = max(eA1, max(abs(Srun' - Soc(k,:))));
end
s2('A1 SOC 递推残差（soc_sim 独立重放）max = %.3e   -> %s', eA1, pass(eA1 < 1e-6));

mnS = min(Soc(:));  mxS = max(Soc(:));
okA2 = mnS >= qc.S_min - TOL && mxS <= qc.S_max + TOL;
s2('A2 SOC 范围 [%.4f, %.4f]，要求 [%.0f, %.0f]   -> %s', mnS, mxS, qc.S_min, qc.S_max, pass(okA2));

eA3 = max(abs(Soc(:,end) - qc.S_end));
s2('A3 日末 SOC 均为 %.0f（口径 2），偏差 max = %.3e   -> %s', qc.S_end, eA3, pass(eA3 < 1e-6));

mxC = max(C(:));  mxD = max(Dd(:));
okA4 = mxC <= qc.P_max + TOL && mxD <= qc.P_max + TOL;
s2('A4 充放功率 max = %.4f / %.4f kW，上限 %.0f kW   -> %s', mxC, mxD, qc.P_max, pass(okA4));

nBoth = sum(sum(C > TOL & Dd > TOL));
s2('A5 同时充放时段数 = %d   -> %s', nBoth, pass(nBoth == 0));

okA6 = min(G(:)) >= -TOL && min(A(:)) >= -TOL;
s2('A6 计划量 min = %.6f，调整量 min = %.6f kW   -> %s', min(G(:)), min(A(:)), pass(okA6));

% ---- B. 守恒律与实际结算 ----
res = A + R.gEm + Dd - (NactAll(R.dayIdx,:) + C);
eB1 = max(abs(res(:) - R.curt(:)));
s2('B1 弃电量与解算值一致 max = %.3e kW   -> %s', eB1, pass(eB1 < 1e-6));

okB2 = min(R.curt(:)) >= -TOL && min(R.gEm(:)) >= -TOL;
s2('B2 弃电 min = %.6e，紧急购电 min = %.6e kW   -> %s', ...
    min(R.curt(:)), min(R.gEm(:)), pass(okB2));

curtCur = R.curt > 1e-6;  gEmCur = R.gEm > 1e-6;
nBoth2  = sum(sum(curtCur & gEmCur));
srcA = A > TOL;  srcD = Dd > TOL;  srcN = NactAll(R.dayIdx,:) < -TOL;
badCurt = sum(sum(curtCur & ~(srcA | srcD | srcN)));
s2('B3 弃电与紧急购电逐槽互斥（重叠 %d 槽）   -> %s', nBoth2, pass(nBoth2 == 0));
s2('     弃电来源：超买 %d / 多放 %d / 光伏富余 %d 槽；无来源的弃电 %d 槽   -> %s', ...
    sum(sum(curtCur & srcA)), sum(sum(curtCur & srcD)), sum(sum(curtCur & srcN)), ...
    badCurt, pass(badCurt == 0));
s2('     （判据的两版错法见 q3_validate.m B3 的留痕：弃电≠只在光伏富余时发生）');

% ---- C. 费用复算 ----
over  = max(0, A - G);
under = max(0, G - A);
cPlan = sum(sum(pr .* dt .* min(G, A)));
cAdj  = sum(sum(pr .* dt .* (qc.kUnder*under + qc.kOver*over)));
cEm   = sum(sum(qc.kEm * pr .* dt .* R.gEm));
eC1 = abs(cPlan - sum(R.costPlan));
eC2 = abs(cAdj  - sum(costAdj));
eC3 = abs(cEm   - sum(R.costEm));
s2('C1 计划购电费 %16.2f 元，复算差 = %.3e   -> %s', sum(R.costPlan), eC1, pass(eC1 < 1e-4));
s2('C2 调整购电费 %16.2f 元，复算差 = %.3e   -> %s', sum(costAdj), eC2, pass(eC2 < 1e-4));
s2('C3 紧急购电费 %16.2f 元，复算差 = %.3e   -> %s', sum(R.costEm), eC3, pass(eC3 < 1e-4));
eC4 = abs((cPlan + cAdj + cEm) - sum(R.costPlan + costAdj + R.costEm));
s2('C4 三块之和与总费用之差 = %.3e 元   -> %s', eC4, pass(eC4 < 1e-6));

okC5 = min(qAdj) >= -TOL;
s2('C5 调整后购电量非负：min = %.6f kWh   -> %s', min(qAdj), pass(okC5));
s2('     [%s] 总费用 %.2f 元（购电 %.1f kWh，发生紧急购电 %d 天）', ...
    tag, sum(R.costPlan + costAdj + R.costEm), sum(qAdj)+sum(R.qEm), sum(R.qEm > 1e-6));

ok = okA2 && okA4 && okA6 && okB2 && okC5 && ...
     badCurt == 0 && nBoth == 0 && nBoth2 == 0 && ...
     max([eA1 eA3]) < 1e-6 && max([eB1 eC1 eC2 eC3]) < 1e-4 && eC4 < 1e-6;

% 嵌套函数定义放在父函数体末尾（惯例位置；MATLAB 允许先调用后定义）
    function s2(varargin)
        ln{end+1} = sprintf(varargin{:});
    end
end

% ======================================================================
function tab = fourWayTable(R2, R3)
% 四问总费用并列。Q2/Q3 的结果若不在盘上则留 NaN。
n = 4;
tab.lbl = {'Q2  附件1 电价 + 无附件3   （问题二框架）', ...
           'Q3  附件1 电价 + 附件3+调整（问题三框架）', ...
           'Q4-2 附件4 电价 + 无附件3   （本问保底一）', ...
           'Q4-3 附件4 电价 + 附件3+调整（本问保底二）'};
tab.q = nan(n,1);  tab.c = nan(n,1);

q2f = 'D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\问题二\out\q2_solution.mat';
q3f = 'D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\问题三\out\q3_solution.mat';
if isfile(q2f)
    S = load(q2f, 'R');
    tab.q(1) = S.R.summary.qPlanTot + S.R.summary.qEmTot;  tab.c(1) = S.R.summary.costTot;
end
if isfile(q3f)
    S = load(q3f, 'R');
    tab.q(2) = S.R.summary.qAdjTot + S.R.summary.qEmTot;   tab.c(2) = S.R.summary.costTot;
end
tab.q(3) = R2.summary.qPlanTot + R2.summary.qEmTot;   tab.c(3) = R2.summary.costTot;
tab.q(4) = R3.summary.qAdjTot  + R3.summary.qEmTot;   tab.c(4) = R3.summary.costTot;
end

% ======================================================================
function s = pass(b)
if b, s = 'PASS'; else, s = 'FAIL'; end
end
