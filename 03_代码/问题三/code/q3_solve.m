function R = q3_solve(D, F, qc, dayList)
% Q3_SOLVE  问题三：四阶段滚动决策（0:00 定计划，6/12/18 定调整）
%
% 问题四复用本函数：把 qc.priceMode 设成 'volatile' 即可（附件4 逐日实测电价）。
%
% ============================================================
%  滚动结构（每天 4 个决策时刻，题面直接给出）
%
%   τ    已冻结槽      待决策槽      决策量      采用值
%  ---------------------------------------------------------------
%   0     ∅            1..144        计划 G      G = Q 分布的 0.8 分位
%   6    1..36        37..144        调整 A      A = clip(G, Q_0.7, Q_0.9)
%  12    1..72        73..144        调整 A      同上
%  18    1..108      109..144        调整 A      同上
%  ---------------------------------------------------------------
%  「已冻结」= 该槽已经执行过，其充放电与购电量不可再改。
%  qc.useStages = [1 0 0 0] 时退化为「只定计划、永不调整」，即消融实验的 A0 组。
%
%  每个阶段：用【该发布时刻可见】的净负荷预报 + 近 nScen 天该时刻预报留下的
%  残差情景集，解一次 q3_lp，得到余下时段的充放电计划；再按报童临界分位
%  把购电量覆盖为分位数（精确两步法，理由见 q3_lp.m 顶部）。
%
%  调整量的一次性闭式：A_t = min( max(G_t, Q_(0.7)), Q_(0.9) )。
%    · 计划偏低（G < Q_0.7）时向上取到 70 分位——再多买就不划算（边际 1.5p ≥ 5p·0.3）
%    · 计划偏高（G > Q_0.9）时向下取到 90 分位——少买到此为止（边际 0.5p = 5p·0.1）
%    · 处于两者之间则【不动】，保持原计划
%  故恒有 Q_0.7 ≤ A_t ≤ Q_0.9，这一不变量在 q3_validate.m 的 D 层被逐槽核查。
%
%  费用结算（口径逐字对应题面三句话，见 q3_config.m）：
%    计划购电费 C_plan = Σ p_t·dt·min(G_t, A_t)
%    调整购电费 C_adj  = Σ p_t·dt·[0.5·(G_t−A_t)^+ + 1.5·(A_t−G_t)^+]
%    紧急购电费 C_em   = Σ 5·p_t·dt·e_t,   e_t = (Nact_t + C_t − D_t − A_t)^+
%
% 输入：D（data.mat）、F（q3_forecast 输出）、qc（q3_config）、dayList（可选）
% 输出：R，并落盘 qc.outdir/q3_solution.mat
% ============================================================

if nargin < 4 || isempty(dayList), dayList = qc.dayIdx(:); end
assert(numel(unique(qc.useStages)) > 1 || qc.useStages(1), ...
    'useStages 第 1 位（0:00 制定计划）必须为真');

nd  = numel(dayList);
nT  = 144;
nS  = qc.nScen;
dt  = qc.dt;
issH = qc.fcIssHours(:)';
nIss = numel(issH);
useAdj = logical(qc.useStages(:)');

% ---------------- 电价来源（Q3 固定 / Q4 逐日波动）----------------
switch lower(qc.priceMode)
    case 'fixed'
        PR = repmat(D.day144.price(:)', nd, 1);          % nd×144，逐日相同
    case 'volatile'
        PR = D.actual.price(dayList, :);                 % nd×144，逐日逐时段
    otherwise
        error('q3_solve: 未知 priceMode = %s', qc.priceMode);
end

% ---------------- 结果容器 ----------------
R.dayIdx   = dayList(:);
R.date     = D.actual.dates(dayList);
R.price    = PR;
R.priceMode= qc.priceMode;
R.useStages= qc.useStages;

R.G        = zeros(nd, nT);   % 计划购电量 kW
R.A        = zeros(nd, nT);   % 最终调整购电量 kW（未调整处 = G）
R.C        = zeros(nd, nT);   % 最终执行的充电功率 kW
R.D        = zeros(nd, nT);   % 最终执行的放电功率 kW
R.C0       = zeros(nd, nT);   % 仅 0:00 阶段（不调整）的充电功率 kW
R.D0       = zeros(nd, nT);
R.Soc      = zeros(nd, nT);   % 最终执行的时段末 SOC kWh
R.Soc0     = zeros(nd, nT);   % 不调整时的 SOC（供对照）
R.gEm      = zeros(nd, nT);   % 实际紧急购电量 kW
R.curt     = zeros(nd, nT);   % 实际弃电 kW

R.costPlan = zeros(nd,1);     % 计划购电费 元
R.costAdj  = zeros(nd,1);     % 调整购电费 元（恒非负）
R.costEm   = zeros(nd,1);     % 紧急购电费 元
R.costNoAdj= zeros(nd,1);     % 对照 A：只定计划、不调整、不重排充放电
R.costAdjOnly=zeros(nd,1);    % 对照 B：只调整购电量 A，充放电仍用 0:00 的计划
R.qPlan    = zeros(nd,1);     % 计划购电量 kWh
R.qAdj     = zeros(nd,1);     % 调整后购电量 kWh
R.qEm      = zeros(nd,1);     % 紧急购电量 kWh

R.flagStage= nan(nd, nIss);   % 各阶段 linprog 退出标志
R.lpObjStage = nan(nd, nIss); % 各阶段 LP 目标值（诊断用，不可跨阶段相加）
R.secStage = nan(nd, nIss);

% Csnap/Dsnap：各阶段 LP【自己解出】的充放电功率（校验用）。
% ⚠️ 必须存 LP 的【输出】而不是"解 LP 之前当前的充放电"。理由：该阶段的情景净需求
%    定义为 Q^(j) = Nhat_j + 残差 + c^(j) − d^(j)，其中的 (c,d) 就是这一次 LP 解出来的
%    那一组。若存成输入（阶段 1 的输入是 0），重建出来的 Q 与求解器实际用的 Q 差一个
%    充放电量（实测偏差可达 5000 kW = P_max），D 层会整体误判。
%    只覆盖该阶段自己的时域 H（H 之外置 0），校验时也只取 H 列。
R.Csnap    = zeros(nd, nT, nIss);
R.Dsnap    = zeros(nd, nT, nIss);
R.Sstart   = nan(nd, nIss);        % 各阶段 LP 的 SOC 起点（阶段 1 为 qc.S0）

R.nAboveG  = zeros(nd, nT);   % 计划阶段 #{s: Q^s_t > G_t}，应 = nS·(1−qPlan)
R.nAboveA  = nan(nd, nT);     % 调整阶段 #{s: Q^s_t > A_t}
R.q07      = nan(nd, nT);     % 调整阶段该槽的 Q_0.7
R.q09      = nan(nd, nT);     % 调整阶段该槽的 Q_0.9
R.AgLo     = nan(nd, nT);     % A_t − Q_0.7 ≥ 0（仅在调整过的槽上有值）
R.AgHi     = nan(nd, nT);     % Q_0.9 − A_t ≥ 0
R.clipHi   = false(nd, nT);   % 因 G < Q_0.7 而向上取 70 分位
R.clipLo   = false(nd, nT);   % 因 G > Q_0.9 而向下取 90 分位
R.Sadj     = zeros(nd,1);     % 调整后总费用 = costPlan + costAdj + costEm

t0 = tic;
for k = 1:nd
    d   = dayList(k);
    prc = PR(k,:)';

    % 情景残差池：严格只用第 d−1 天及以前（无未来函数）
    pool = (d-nS):(d-1);
    pool = pool(pool >= 1);
    if isempty(pool)
        warning('第 %d 天无残差样本，退化为完美信息', d);
        pool = d;
    end

    % ================= 阶段 1（τ=0）：制定计划 =================
    ts = tic;
    Nhat0 = F.Nhat4(d, :, 1)';
    Rs0   = residualMat(F, pool, 1:nT, 1, nS);
    R.Sstart(k,1)  = qc.S0;                 % 阶段 1 无已执行时段，起点就是 S_0
    LP0   = q3_lp(prc, qc.S0, Nhat0, Rs0, qc);
    R.Csnap(k,:,1) = LP0.c';  R.Dsnap(k,:,1) = LP0.d';   % 存【本次 LP 自己解出的】充放电
    R.flagStage(k,1) = LP0.flag;  R.lpObjStage(k,1) = LP0.objval;
    if LP0.flag ~= 1
        warning('第 %d 天（%s）阶段 0 linprog flag=%d', d, string(R.date(k)), LP0.flag);
    end

    Q0 = LP0.Ns + LP0.c - LP0.d;                 % nT×nS，情景下的需外购净需求
    G  = max(0, nthRow(Q0, qc.qPlan));           % 报童 0.5 分位

    A  = G;   C = LP0.c;  Dd = LP0.d;            % 当前采用值
    C0 = C;   D0 = Dd;                            % 0:00 的原始计划（对照 B 用）
    Afix = G;                                     % 对照 B 的调整量
    R.nAboveG(k,:) = countAbove(Q0, G)';
    R.secStage(k,1) = toc(ts);

    % ================= 阶段 2..4（τ=6/12/18）：逐次调整 =================
    for j = 2:nIss
        if ~useAdj(j), continue; end
        tau = issH(j);
        nc  = 6*tau;                              % 已执行的槽数（tau 小时 × 6）
        H   = (nc+1):nT;
        if isempty(H), continue; end

        ts = tic;
        [Srun, ~] = soc_sim(C(1:nc), Dd(1:nc), qc.S0, qc);
        Sstart = Srun(end);

        NhatT = F.Nhat4(d, H, j)';
        RsT   = residualMat(F, pool, H, j, nS);
        R.Sstart(k,j)  = Sstart;
        LPT   = q3_lp(prc(H), Sstart, NhatT, RsT, qc);
        R.Csnap(k,H,j) = LPT.c';  R.Dsnap(k,H,j) = LPT.d';  % 只覆盖本阶段时域 H，其余置 0
        R.flagStage(k,j) = LPT.flag;  R.lpObjStage(k,j) = LPT.objval;
        if LPT.flag ~= 1
            warning('第 %d 天（%s）阶段 τ=%d linprog flag=%d', d, string(R.date(k)), tau, LPT.flag);
        end

        C(H)  = LPT.c;  Dd(H) = LPT.d;            % 用新信息重排余下时段的充放电

        QT  = LPT.Ns + LPT.c - LPT.d;             % nH×nS
        q07 = max(0, nthRow(QT, qc.qAdjLo));
        q09 = max(0, nthRow(QT, qc.qAdjHi));
        Anew = min( max(G(H), q07), q09);         % ★ 调整量闭式
        Anew = max(Anew, 0);

        R.clipHi(k, H) = (q07 > G(H))';           % 计划偏低 → 向上补到 70 分位
        R.clipLo(k, H) = (G(H) > q09)';           % 计划偏高 → 向下减到 90 分位
        A(H)     = Anew;
        R.q07(k,H) = q07';  R.q09(k,H) = q09';
        R.AgLo(k,H) = (Anew - q07)';
        R.AgHi(k,H) = (q09 - Anew)';
        R.nAboveA(k,H) = countAbove(QT, Anew)';

        % ---- 对照 B：同样的分位规则，但需外购量按【0:00 的充放电计划】算 ----
        % 用于把「调整购电量」与「重排充放电」两条收益渠道拆开（见论文 8.3）
        QT0 = LPT.Ns + C0(H) - D0(H);
        q07b = max(0, nthRow(QT0, qc.qAdjLo));
        q09b = max(0, nthRow(QT0, qc.qAdjHi));
        Afix(H) = max(min(max(G(H), q07b), q09b), 0);

        R.secStage(k,j) = toc(ts);
    end

    R.G(k,:) = G';  R.A(k,:) = A';
    R.C(k,:) = C';  R.D(k,:) = Dd';
    R.C0(k,:) = C0'; R.D0(k,:) = D0';

    % ================= 事后结算（一律用【当天实际】净负荷）=================
    [Soc, ~]   = soc_sim(C, Dd, qc.S0, qc);
    [Soc0, ~]  = soc_sim(C0, D0, qc.S0, qc);
    R.Soc(k,:) = Soc';  R.Soc0(k,:) = Soc0';

    NactRow = F.Nact(d, :)';
    net     = NactRow + C - Dd - A;               % >0 缺口，<0 富余
    R.gEm(k,:)  = max(0, net)';
    R.curt(k,:) = max(0, -net)';

    over  = max(0, A - G);                        % 调整量高于计划（多买）
    under = max(0, G - A);                        % 计划高于调整量（少买）

    R.costPlan(k) = sum(prc .* dt .* min(G, A));
    R.costAdj(k)  = sum(prc .* dt .* (qc.kUnder*under + qc.kOver*over));
    R.costEm(k)   = sum(qc.kEm * prc .* dt .* R.gEm(k,:)');
    R.Sadj(k)     = R.costPlan(k) + R.costAdj(k) + R.costEm(k);

    % ---- 对照 A：「只定计划、不调整、不重排」：同一 G、同一 (C0,D0)，按 A := G 结算 ----
    e0 = max(0, NactRow + C0 - D0 - G);
    R.costNoAdj(k) = sum(prc .* dt .* G) + sum(qc.kEm * prc .* dt .* e0);

    % ---- 对照 B：「只调整购电量」，充放电仍用 0:00 计划 ----
    netB  = NactRow + C0 - D0 - Afix;
    overB = max(0, Afix - G);   underB = max(0, G - Afix);
    R.costAdjOnly(k) = sum(prc .* dt .* min(G, Afix)) ...
                     + sum(prc .* dt .* (qc.kUnder*underB + qc.kOver*overB)) ...
                     + sum(qc.kEm * prc .* dt .* max(0, netB));

    R.qPlan(k) = sum(G)*dt;
    R.qAdj(k)  = sum(A)*dt;
    R.qEm(k)   = sum(R.gEm(k,:))*dt;
end
R.solveSec = toc(t0);

% ---------------- 汇总 ----------------
R.summary = struct( ...
    'nDay',        nd, ...
    'costPlanTot', sum(R.costPlan), ...
    'costAdjTot',  sum(R.costAdj), ...
    'costEmTot',   sum(R.costEm), ...
    'costTot',     sum(R.Sadj), ...
    'costNoAdjTot',sum(R.costNoAdj), ...
    'costAdjOnlyTot', sum(R.costAdjOnly), ...
    'qPlanTot',    sum(R.qPlan), ...
    'qAdjTot',     sum(R.qAdj), ...
    'qEmTot',      sum(R.qEm), ...
    'nDayEm',      sum(R.qEm > 1e-6), ...
    'nClipHi',     sum(R.clipHi(:)), ...
    'nClipLo',     sum(R.clipLo(:)), ...
    'nSlotAdj',    sum(isfinite(R.AgLo(:))), ...
    'solveSec',    R.solveSec);

if qc.verbose
    fprintf('  q3_solve：%d 天 × %d 阶段，用时 %.1f s（%.3f s/天）\n', ...
        nd, sum(useAdj), R.solveSec, R.solveSec/nd);
    fprintf('    计划购电费 %14.2f 元 | 调整购电费 %12.2f 元 | 紧急购电费 %12.2f 元\n', ...
        R.summary.costPlanTot, R.summary.costAdjTot, R.summary.costEmTot);
    sav    = R.summary.costNoAdjTot - R.summary.costTot;
    savB   = R.summary.costNoAdjTot - R.summary.costAdjOnlyTot;
    base   = max(R.summary.costNoAdjTot, eps);
    fprintf('    调整后合计 %.2f 元\n', R.summary.costTot);
    fprintf('    滚动调整共省 %.2f 元（%.3f%%）=「只调购电量」%.2f 元（%.3f%%）+「重排充放电」%.2f 元\n', ...
        sav, 100*sav/base, savB, 100*savB/base, R.summary.costAdjOnlyTot - R.summary.costTot);
    fprintf('    购电量：计划 %.1f | 调整后 %.1f | 紧急 %.1f kWh\n', ...
        R.summary.qPlanTot, R.summary.qAdjTot, R.summary.qEmTot);
    fprintf('    调整覆盖 %d 槽；因计划偏低上修 %d 槽，因计划偏低下修 %d 槽\n', ...
        R.summary.nSlotAdj, R.summary.nClipHi, R.summary.nClipLo);
end

% ---- 落盘：显式开关，默认【不写】----
% ⚠️ 这里曾是无条件 save([qc.outdir 'q3_solution.mat'], ...)，后果实测如下：
%    诊断脚本（消融、降尺度、粒度、闭环、分位扫描、系数扫描）会以各种【派生配置】
%    反复调用本函数，每次都照写不误 ⇒ 交付解被最后一次诊断的结果覆盖。
%    本队已中招一次：问题三\out\q3_solution.mat 被写成 2,552,947.23 元的 60 天子区间
%    残件（交付值 14,724,901.09 元），连带问题四的四问对照表把 Q3 读错。
%    （同一类事故在问题二也发生过：t_q4_clone_check 调 q2_solve 跑 5 天，
%      把交付的 14,565,425.45 元覆盖成 261,173.17 元。q2_solve 已交付不可改，
%      故那边的修法是把 outdir 指到隔离目录，见 t_q4_clone_check.m。）
%    现在改为【显式开关】：只有置了 qc.saveSolution = true 的正式全量跑才落盘。
if isfield(qc, 'saveSolution') && ~isempty(qc.saveSolution) && qc.saveSolution
    if ~isfolder(qc.outdir), mkdir(qc.outdir); end
    save([qc.outdir 'q3_solution.mat'], 'R', 'qc', '-v7.3');
end
end

% ======================================================================
function Rs = residualMat(F, pool, cols, j, nS)
% 残差情景矩阵：r = Nact − Nhat_第j套预报，取 pool 天、cols 列，展成 numel(cols)×nS
Rm  = F.Nact(pool, cols) - F.Nhat4(pool, cols, j);      % npool × ncol
np_ = size(Rm,1);
if np_ >= nS
    Rs = Rm(end-nS+1:end, :)';
else
    Rs = repmat(Rm', 1, ceil(nS/np_));
    Rs = Rs(:, 1:nS);
end
end

function v = nthRow(M, q)
% 每行取升序第 ceil(q*nS) 个次序统计量（与问题二同款：P(X ≤ v) = k/nS）
nS = size(M, 2);
k  = max(1, min(nS, ceil(q*nS)));
Ms = sort(M, 2);
v  = Ms(:, k);
end

function c = countAbove(Q, v)
% 逐行统计 #{s : Q(t,s) > v_t}（严格大于；有并列时自然偏小，校验时按 ≤ 放行）
c = sum(Q > v, 2);
end
