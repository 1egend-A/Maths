function R = q2_solve(D, F, qc, dayList)
% Q2_SOLVE  问题二：逐日两阶段随机规划（日前计划 + 紧急购电补偿）
%
% ============================================================
%  模型（口径 7 = 严格字面：只用附件1 电价 + 附件2 历史）
%
%  【关键化简】负载 L 与光伏 PV 在全部约束与费用中只以差值出现：
%      供需平衡  g + g^em + PV + d = L + c + e
%      ⇔        g + g^em + d = (L - PV) + c + e = N + c + e
%  故问题二的随机性完全由【净负荷 N = L - PV】承载，无需分别刻画 L 与 PV。
%
%  【两阶段结构】
%   第一阶段（here-and-now，每日 0:00 制定）：
%       计划购电量 g_t、充电量 c_t、放电量 d_t  （t = 1..144）
%       —— 由 result2 模板的「计划购电量」与「充放电量」两张表分别落账，
%          说明题目确实要求把充放电计划也一并定死。
%       —— SOC 递推 S_t = S_{t-1} + (eta*c_t - d_t/eta)*dt
%          受 1200 <= S_t <= 10800 与日末闭环 S_144 = S_0 = 6000 约束。
%
%   第二阶段（recourse，日内实际实现后）：
%       紧急购电量 g^em_{t,s} = max(0, N^s_t + c_t - d_t - g_t)
%       —— 即「微网提供的电能低于负载」时的缺口，电价 5 倍。
%       —— 弃电 e_{t,s} = max(0, g_t + d_t - c_t - N^s_t)。
%
%  【费用】题面「其他时间段的购电费用均按计划购电量计算」⇒ 计划电量按计划数
%   结算，实际多发少发都不退不补：
%       计划购电费 = Σ_t p_t * g_t * dt
%       紧急购电费 = Σ_t 5*p_t * E_s[ g^em_{t,s} ] * dt
%   目标 = 两者之和的期望，最小化。
%
%  【不确定性描述（情景生成）】用【同一预测器】在近 nScen 天留下的净负荷残差
%   作为经验分布样本（等概率）：
%       r_{j,t} = Nact_{j,t} - Nhat_{j,t},   j ∈ {d-nScen, ..., d-1}
%       N^s_t   = Nhat_{d,t} + r_{d-s,t}
%
%  ------------------------------------------------------------
%  【解析内核：报童临界分位 + 最优计划量不唯一性】
%
%   注意 g_t 只出现在目标函数与补偿约束里，【不进入 SOC 递推】。因此给定
%   任意可行的 (c_t, d_t)，目标对 g_t 的边际为
%       ∂/∂g_t = p_t*dt * ( 1 - 5 * #{s : N^s_t + c_t - d_t > g_t} / nS )
%   记 z_(1) <= ... <= z_(nS) 为 N^s_t + c_t - d_t 的升序次序统计量，则
%       #{s : z_s > g_t} = k  <=>  g_t ∈ [ z_(nS-k), z_(nS-k+1) )
%   边际为 0 当且仅当 k = nS/5 = 6，即
%       g*_t ∈ [ z_(nS-k), z_(nS-k+1) ),   k = nS/5
%   ⇒ **最优计划购电量是一个区间，不是单点**（等权离散经验分布的必然结果）。
%     该区间两端对应同一期望费用，故必须另外声明选择规则。
%
%   取报童规则的临界分位点（使 P(不缺电) >= 0.8 的最小 g）：
%       g*_t = z_(k80),  k80 = ceil(0.8*nS)
%   其中临界分位 = c_u/(c_u+c_o) = (5p-p)/((5p-p)+p) = 4/5 = 0.8。
%   nS=30 时 k80 = 24，P(N+c-d <= g*) = 24/30 = 0.8 恰取等号。
%
%   由于 SOC 约束不含 g，取区间内任一点都不改变 (c,d) 的最优性与目标值，
%   所以「先解 LP 得 (c,d)、再按分位定 g」是【精确】的两步法，不是近似。
%   q2_solve 同时记录 LP 原始解与分位解的期望费用之差，用于验证该论断。
%  ------------------------------------------------------------
%
% 输入：D（data.mat 统一结构）、F（q2_forecast 输出）、qc（q2_config）
% 输出：R，含每日计划/实际/费用/SOC/紧急购电等，并落盘 out/q2_solution.mat
% ============================================================

if nargin < 4 || isempty(dayList)
    dayList = qc.dayIdx;
end

nT = size(F.Nhat, 2);          % 144
nS = qc.nScen;
dt = qc.dt;  eta = qc.eta;  PM = qc.P_max;  S0 = qc.S0;  SEND = qc.S_end;

k80 = ceil(0.8*nS);            % 报童临界分位对应的次序统计量编号
assert(k80 >= 1 && k80 <= nS);

% 电价：口径「每天的电价相同」⇒ 全部日期共用附件1 的同一份 144 段报价
price = D.day144.price(:);                 % 元/kWh，144×1
assert(numel(price) == nT);
pdt   = price * dt;                        % 每时段单价（元/kW·时段）

% ---------------- 一次性构造 LP（A、f、lb、ub 与日期无关）----------------
ig = (1:nT)';  ic = nT+(1:nT)';  id = 2*nT+(1:nT)';  iS = 3*nT+(1:nT)';
iu = 4*nT + reshape(1:nT*nS, nT, nS);      % iu(t,s)
n  = 4*nT + nT*nS;

% 行 1..nT*nS（不等式 A x <= b）：情景补偿约束  N^s_t + c_t - d_t - g_t - u_{t,s} <= 0
%   每条约束有 4 个非零元（g_t、c_t、d_t、u_{t,s}），故行号要重复 4 遍。
%   ⚠️ 展开次序必须与 colU / b 完全一致：一律按 nT×nS 矩阵【列优先】展开，
%      即线性位置 k ↔ (t,s) = (mod(k-1,nT)+1, floor((k-1)/nT)+1)。
%      曾因 rowU 误按 nS×nT 展开（把 s 当快变维），约束被绑到错误的
%      (时段,情景) 对上——模型仍可解、flag 仍为 1、守恒律也仍然成立，
%      但解无意义（LP 解与报童分位差 1000+ kW）。下面加对齐自检兜底。
rowIdx = (0:nS-1)*nT + (1:nT)';            % nT×nS，rowIdx(t,s) = (s-1)*nT + t
rowU   = repmat(reshape(rowIdx, [], 1), 4, 1);
colU   = [repmat(ig,nS,1); repmat(ic,nS,1); repmat(id,nS,1); reshape(iu,[],1)];
valU   = [-ones(nT*nS,1); ones(nT*nS,1); -ones(nT*nS,1); -ones(nT*nS,1)];
A = sparse(rowU, colU, valU, nT*nS, n);

% ---- 三元组对齐自检 ----
iuV = reshape(iu, [], 1);
for chkK = [1, nT, nT+1, nT*nS]
    [tc, sc] = ind2sub([nT nS], chkK);
    assert(rowU(chkK) == (sc-1)*nT + tc,        'rowU 与 (t,s) 展开次序不一致');
    assert(colU(chkK) == ig(tc),                'colU 第 1 块（g）次序不一致');
    assert(colU(nT*nS+chkK) == ic(tc),          'colU 第 2 块（c）次序不一致');
    assert(colU(2*nT*nS+chkK) == id(tc),        'colU 第 3 块（d）次序不一致');
    assert(colU(3*nT*nS+chkK) == iuV(chkK),     'colU 第 4 块（u）次序不一致');
end

% SOC 递推（【等式】Aeq x = beq）：
%     S_t - S_{t-1} - eta*dt*c_t + (dt/eta)*d_t = 0,   t = 1..144
% ⚠️ 必须是等式。若误写成不等式，储能可以「凭空少掉电量」，
%    等价于允许 d_t 超出实际可放出的电量，模型会给出虚假的低成本解。
rowSeq = (1:nT)';
Aeq = sparse([rowSeq; rowSeq(2:end); rowSeq; rowSeq], ...
             [iS;     iS(1:end-1);  ic;     id    ], ...
             [ones(nT,1); -ones(nT-1,1); -eta*dt*ones(nT,1); (dt/eta)*ones(nT,1)], ...
             nT, n);

% 目标：Σ p_t*dt*g_t + Σ_t (5*p_t*dt/nS) * Σ_s u_{t,s}
f = [pdt; zeros(2*nT,1); zeros(nT,1); repmat(5*pdt/nS, nS, 1)];

% 变量界
lb = zeros(n,1);  ub = inf(n,1);
ub(ic) = PM;  ub(id) = PM;
lb(iS) = qc.S_min;  ub(iS) = qc.S_max;
lb(iS(nT)) = SEND;  ub(iS(nT)) = SEND;      % 口径 2：日末闭环

beqSoc = [S0; zeros(nT-1,1)];               % SOC 递推右端（首段含 -S_0 移项）

opts = optimoptions('linprog', 'Algorithm', qc.lpAlgo, 'Display', 'off');

% ---------------- 逐日求解 ----------------
nd = numel(dayList);
R.dayIdx  = dayList(:);
R.date    = D.actual.dates(dayList);
R.gPlan   = zeros(nd, nT);     % 计划购电量 kW（分位定，即最终采用值）
R.gLp     = zeros(nd, nT);     % LP 原始返回的 g（用于展示最优不唯一性）
R.c       = zeros(nd, nT);     % 充电 kW
R.d       = zeros(nd, nT);     % 放电 kW
R.Soc     = zeros(nd, nT);     % 时段末 SOC kWh
R.gEm     = zeros(nd, nT);     % 实际紧急购电量 kW（按当天实际净负荷事后核算）
R.curt    = zeros(nd, nT);     % 实际弃电 kW
R.Nact    = F.Nact(dayList, :);
R.Nhat    = F.Nhat(dayList, :);
R.costPlan = zeros(nd,1);      % 实际发生的计划购电费 元
R.costEm   = zeros(nd,1);      % 实际发生的紧急购电费 元
R.costExp  = zeros(nd,1);      % 模型期望总费用 元（情景均值，即目标值）
R.qPlan    = zeros(nd,1);      % 计划购电量 kWh
R.qEm      = zeros(nd,1);      % 紧急购电量 kWh
R.flag     = zeros(nd,1);
R.gLpGap   = zeros(nd,1);      % |g_LP - g_分位| 的时段均值 kW  ← 最优不唯一性的度量
R.costGap  = zeros(nd,1);      % 期望费用(取 g_LP) - 期望费用(取分位) 元 ← 应 ≈ 0
R.plateauW = zeros(nd,1);      % 最优平台宽度（相邻次序统计量之差）均值 kW

t0 = tic;
for k = 1:nd
    d = dayList(k);

    % ---- 情景净负荷（近 nS 天残差，严格只用到 d-1 及以前）----
    pool = (d-nS):(d-1);
    pool = pool(pool >= 1);
    if isempty(pool)
        warning('第 %d 天无残差样本，退化为完美信息', d);
        Rs = zeros(nT, nS);
    else
        Rmat = F.Nact(pool,:) - F.Nhat(pool,:);      % npool × nT
        np_  = size(Rmat,1);
        if np_ >= nS
            Rs = Rmat(end-nS+1:end, :)';             % nT × nS
        else                                     % 历史不足：重复铺满
            Rs = repmat(Rmat', 1, ceil(nS/np_));
            Rs = Rs(:, 1:nS);
        end
    end
    Ns = F.Nhat(d,:)' + Rs;                          % nT × nS

    b = -reshape(Ns, [], 1);

    [x, ~, flag] = linprog(f, A, b, Aeq, beqSoc, lb, ub, opts);
    if flag ~= 1
        warning('第 %d 天（%s）linprog flag=%d', d, string(R.date(k)), flag);
    end
    R.flag(k) = flag;

    gLP = x(ig);  c = x(ic);  dd = x(id);  S = x(iS);

    % ---- 用报童临界分位确定最终采用的计划购电量 ----
    Qraw  = Ns + c - dd;                 % nT × nS，情景下的「需外购净需求」
    Qsrt  = sort(Qraw, 2);
    gStar = max(0, Qsrt(:, k80));        % g* = z_(k80)
    gStar = min(gStar, max(0, Qsrt(:, min(k80+1,nS))));   % 数值保护，不出平台

    R.gLp(k,:)   = gLP';
    R.gPlan(k,:) = gStar';
    R.c(k,:) = c';  R.d(k,:) = dd';  R.Soc(k,:) = S';

    % ---- 平台性验证：两种取法期望费用之差（应 ≈ 0）----
    Ecost = @(gg) sum(price.*gg)*dt + sum(5*price.*mean(max(0, Qraw - gg),2))*dt;
    R.costExp(k)  = Ecost(gStar);
    R.gLpGap(k)   = mean(abs(gLP - gStar));
    R.costGap(k)  = Ecost(gLP) - Ecost(gStar);
    if k80 < nS
        R.plateauW(k) = mean(Qsrt(:, k80+1) - Qsrt(:, k80));
    end

    % ---- 按【当天实际】净负荷事后核算紧急购电与弃电 ----
    NactRow = F.Nact(d,:)';
    net = NactRow + c - dd - gStar;                  % >0 为缺口
    R.gEm(k,:)  = max(0, net)';
    R.curt(k,:) = max(0, -net)';

    R.qPlan(k)    = sum(gStar)*dt;
    R.qEm(k)      = sum(R.gEm(k,:))*dt;
    R.costPlan(k) = sum(price .* gStar)*dt;
    R.costEm(k)   = sum(5*price .* R.gEm(k,:)')*dt;
end
R.solveSec = toc(t0);

% ---------------- 汇总 ----------------
R.price   = price;
R.costTot = R.costPlan + R.costEm;
R.summary = struct( ...
    'nDay',        nd, ...
    'qPlanTot',    sum(R.qPlan), ...
    'qEmTot',      sum(R.qEm), ...
    'costPlanTot', sum(R.costPlan), ...
    'costEmTot',   sum(R.costEm), ...
    'costTot',     sum(R.costTot), ...
    'costExpTot',  sum(R.costExp), ...
    'nDayEm',      sum(R.qEm > 1e-6), ...
    'maxEm',       max(R.qEm), ...
    'solveSec',    R.solveSec);

if qc.verbose
    fprintf('  求解完成：%d 天，用时 %.1f s（%.3f s/天）\n', nd, R.solveSec, R.solveSec/nd);
    fprintf('  计划购电量 %.1f kWh | 紧急购电量 %.1f kWh | 发生紧急购电 %d 天\n', ...
        R.summary.qPlanTot, R.summary.qEmTot, R.summary.nDayEm);
    fprintf('  计划购电费 %.2f 元 | 紧急购电费 %.2f 元 | 实际合计 %.2f 元\n', ...
        R.summary.costPlanTot, R.summary.costEmTot, R.summary.costTot);
    fprintf('  模型期望总费用 %.2f 元\n', R.summary.costExpTot);
    fprintf('  平台性验证：|g_LP - g_分位| 均值 %.1f kW，期望费用差 %.4f 元（应≈0）\n', ...
        mean(R.gLpGap), sum(R.costGap));
end

if ~isfolder(qc.outdir), mkdir(qc.outdir); end
save([qc.outdir 'q2_solution.mat'], 'R', 'qc', '-v7.3');
end
