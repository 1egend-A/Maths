function R = q4_solve_p2(D, F, qc, dayList, prOverride)
% Q4_SOLVE_P2  问题四保底结果之一：把【问题二框架】搬到附件4 的逐日实测电价上
%
% ============================================================
%  ⚠️ 本函数是 问题二/code/q2_solve.m 的【受控克隆】，不是重新建模。
%
%     与 q2_solve.m 的差异【只有一处】：
%        q2_solve :  price = D.day144.price(:);            % 循环外，全年同一份报价
%        本函数   :  prc   = D.actual.price(d, :)';        % 循环内，逐日逐时段不同
%     由此，目标向量 f 也必须逐日重建（它含 prc），其余常数矩阵不变。
%
%     为什么克隆而不是改 q2_solve.m：问题二已交付，交付物不得改动（见交付纪律）。
%     克隆的正确性由 t_q4_clone_check.m 担保——把 priceMode 置回 'fixed' 后，
%     本函数与 q2_solve 在同样天数上的 gPlan / c / d / costPlan / costEm
%     必须逐元素一致（容差 1e-9）。该自检不通过则本文件不可信。
%
%     这也不违反「禁止各自生成求解器再拼接」：问题四的两个框架
%     （result4-2 用本函数、result4-3 用 问题三/code/q3_solve.m）是
%     同一套模型在【不同信息结构】下的两次求解，不是三个人各写一套再拼。
% ============================================================
%
%  【模型（与问题二完全一致，口径 7 严格字面）】
%    第一阶段（0:00）：计划购电量 g_t、充电 c_t、放电 d_t（t = 1..144）
%    第二阶段（日内实现）：紧急购电量 g^em_{t,s} = max(0, N^s_t + c_t − d_t − g_t)
%    费用：计划按计划数结算 Σ p_t·g_t·dt；紧急按 5·p_t 计。
%
%  【解析内核：报童临界分位】g_t 不进入 SOC 递推 ⇒ 其最优值是一段【区间】；
%    取临界分位 g*_t = Q_(0.8)（Q = 净负荷 + 充电 − 放电 的升序次序统计量）。
%    Q4 的电价逐日变，但该分位【不变】——因为紧急电价是 5·p_t，
%    边际条件 #{s : Q^s_t > g_t} = nS/k_em 中 p_t 被约掉（见 q3_config.m）。
%    逐日电价只改变 LP 对「买电 vs 用储能搬移」的权衡，从而改变 (c,d) 与费用。
%
% 输入：D（data.mat）、F（q2_forecast 输出，含 .Nhat/.Nact）、qc（q4_config）、dayList
%       prOverride（可选）nd×144 电价矩阵，覆盖从 D.actual.price 取值。
%       该参数【只服务于自检】：传入 repmat(D.day144.price(:)',nd,1) 时，
%       本函数应逐位复现 q2_solve 的结果——见 t_q4_clone_check.m。
% 输出：R（字段与 q2_solve 对齐，便于克隆导出/论文表）

if nargin < 4 || isempty(dayList), dayList = qc.dayIdx; end
if nargin < 5, prOverride = []; end

nT = size(F.Nhat, 2);          % 144
nS = qc.nScen;
dt = qc.dt;  eta = qc.eta;  PM = qc.P_max;  S0 = qc.S0;  SEND = qc.S_end;
kEm = qc.kEm;

k80 = ceil(0.8*nS);
assert(k80 >= 1 && k80 <= nS);

% ---------------- 常数矩阵（与日期、电价均无关，只构造一次）----------------
% 行 1..nT*nS（A x <= b）：情景补偿约束  N^s_t + c_t − d_t − g_t − u_{t,s} <= 0
ig = (1:nT)';  ic = nT+(1:nT)';  id = 2*nT+(1:nT)';  iS = 3*nT+(1:nT)';
iu = 4*nT + reshape(1:nT*nS, nT, nS);
n  = 4*nT + nT*nS;

% ⚠️ 展开次序必须与 reshape(Ns,[],1) 一致：一律按 nT×nS【列优先】。
rowIdx = (0:nS-1)*nT + (1:nT)';
rowU   = repmat(reshape(rowIdx, [], 1), 4, 1);
colU   = [repmat(ig,nS,1); repmat(ic,nS,1); repmat(id,nS,1); reshape(iu,[],1)];
valU   = [-ones(nT*nS,1); ones(nT*nS,1); -ones(nT*nS,1); -ones(nT*nS,1)];
A = sparse(rowU, colU, valU, nT*nS, n);

iuV = reshape(iu, [], 1);
for chkK = [1, nT, nT+1, nT*nS]
    [tc, sc] = ind2sub([nT nS], chkK);
    assert(rowU(chkK) == (sc-1)*nT + tc, 'rowU 与 (t,s) 展开次序不一致');
    assert(colU(chkK) == ig(tc),             'colU 第 1 块（g）次序不一致');
    assert(colU(nT*nS+chkK) == ic(tc),       'colU 第 2 块（c）次序不一致');
    assert(colU(2*nT*nS+chkK) == id(tc),     'colU 第 3 块（d）次序不一致');
    assert(colU(3*nT*nS+chkK) == iuV(chkK),  'colU 第 4 块（u）次序不一致');
end

% SOC 递推（等式）：S_t − S_{t−1} − eta·dt·c_t + (dt/eta)·d_t = 0
rowSeq = (1:nT)';
Aeq = sparse([rowSeq; rowSeq(2:end); rowSeq; rowSeq], ...
             [iS;     iS(1:end-1);  ic;     id    ], ...
             [ones(nT,1); -ones(nT-1,1); -eta*dt*ones(nT,1); (dt/eta)*ones(nT,1)], ...
             nT, n);

lb = zeros(n,1);  ub = inf(n,1);
ub(ic) = PM;  ub(id) = PM;
lb(iS) = qc.S_min;  ub(iS) = qc.S_max;
lb(iS(nT)) = SEND;  ub(iS(nT)) = SEND;      % 口径 2：日末闭环（与 Q2/Q3 一致）

beqSoc = [S0; zeros(nT-1,1)];
opts = optimoptions('linprog', 'Algorithm', qc.lpAlgo, 'Display', 'off');

% ---------------- 逐日求解 ----------------
nd = numel(dayList);
R.dayIdx  = dayList(:);
R.date    = D.actual.dates(dayList);
R.gPlan   = zeros(nd, nT);     % 计划购电量 kW
R.gLp     = zeros(nd, nT);     % LP 原始返回的 g（用于展示最优不唯一性）
R.c       = zeros(nd, nT);
R.d       = zeros(nd, nT);
R.Soc     = zeros(nd, nT);
R.gEm     = zeros(nd, nT);
R.curt    = zeros(nd, nT);
R.Nact    = F.Nact(dayList, :);
R.Nhat    = F.Nhat(dayList, :);
R.nAboveG = zeros(nd, nT);     % #{s : Q^s_t > g_t}，内点时段应 = nS/k_em = 6
R.costPlan = zeros(nd,1);
R.costEm   = zeros(nd,1);
R.costExp  = zeros(nd,1);
R.qPlan    = zeros(nd,1);
R.qEm      = zeros(nd,1);
R.flag     = zeros(nd,1);
R.gLpGap   = zeros(nd,1);
R.costGap  = zeros(nd,1);
R.plateauW = zeros(nd,1);
PR         = zeros(nd, nT);    % 逐日电价（Q4 与 Q2 的唯一差别）

t0 = tic;
for k = 1:nd
    d   = dayList(k);
    if isempty(prOverride)
        prc = D.actual.price(d, :)';       % ★ 本函数与 q2_solve 的唯一差异
    else
        prc = prOverride(k, :)';           % 自检通道：喂入与 q2_solve 相同的电价
    end
    PR(k,:) = prc';

    % ---- 情景净负荷（近 nS 天残差，严格只用到 d−1 及以前）----
    pool = (d-nS):(d-1);
    pool = pool(pool >= 1);
    if isempty(pool)
        warning('第 %d 天无残差样本，退化为完美信息', d);
        Rs = zeros(nT, nS);
    else
        Rmat = F.Nact(pool,:) - F.Nhat(pool,:);
        np_  = size(Rmat,1);
        if np_ >= nS
            Rs = Rmat(end-nS+1:end, :)';
        else
            Rs = repmat(Rmat', 1, ceil(nS/np_));
            Rs = Rs(:, 1:nS);
        end
    end
    Ns = F.Nhat(d,:)' + Rs;                       % nT × nS
    b  = -reshape(Ns, [], 1);

    % ---- 目标向量逐日重建（这是"把循环外的 f 挪进循环"的落点）----
    pdt = prc * dt;
    f   = [pdt; zeros(2*nT,1); zeros(nT,1); repmat(kEm*pdt/nS, nS, 1)];

    [x, ~, flag] = linprog(f, A, b, Aeq, beqSoc, lb, ub, opts);
    if flag ~= 1
        warning('第 %d 天（%s）linprog flag=%d', d, string(R.date(k)), flag);
    end
    R.flag(k) = flag;

    gLP = x(ig);  c = x(ic);  dd = x(id);  S = x(iS);

    % ---- 报童临界分位定最终计划量 ----
    Qraw = Ns + c - dd;
    Qsrt = sort(Qraw, 2);
    gStar = max(0, Qsrt(:, k80));
    gStar = min(gStar, max(0, Qsrt(:, min(k80+1,nS))));   % 数值保护，不出平台

    R.gLp(k,:)   = gLP';
    R.gPlan(k,:) = gStar';
    R.c(k,:) = c';  R.d(k,:) = dd';  R.Soc(k,:) = S';

    % ---- 平台性验证：两种取法的期望费用之差（应 ≈ 0）----
    Ecost = @(gg) sum(prc.*gg)*dt + sum(kEm*prc.*mean(max(0, Qraw - gg),2))*dt;
    R.costExp(k)  = Ecost(gStar);
    R.gLpGap(k)   = mean(abs(gLP - gStar));
    R.costGap(k)  = Ecost(gLP) - Ecost(gStar);
    if k80 < nS
        R.plateauW(k) = mean(Qsrt(:, k80+1) - Qsrt(:, k80));
    end
    R.nAboveG(k,:) = sum(Qraw > gStar + 1e-9, 2)';

    % ---- 按当天实际净负荷事后核算 ----
    NactRow = F.Nact(d,:)';
    net = NactRow + c - dd - gStar;
    R.gEm(k,:)  = max(0, net)';
    R.curt(k,:) = max(0, -net)';

    R.qPlan(k)    = sum(gStar)*dt;
    R.qEm(k)      = sum(R.gEm(k,:))*dt;
    R.costPlan(k) = sum(prc .* gStar)*dt;
    R.costEm(k)   = sum(kEm*prc .* R.gEm(k,:)')*dt;
end
R.solveSec = toc(t0);

% ---------------- 汇总 ----------------
R.price    = PR;
R.priceMode = qc.priceMode;
R.costTot  = R.costPlan + R.costEm;
R.summary = struct( ...
    'nDay',        nd, ...
    'qPlanTot',    sum(R.qPlan), ...
    'qEmTot',      sum(R.qEm), ...
    'costPlanTot', sum(R.costPlan), ...
    'costEmTot',   sum(R.costEm), ...
    'costTot',     sum(R.costTot), ...
    'costExpTot',  sum(R.costExp), ...
    'nDayEm',      sum(R.qEm > 1e-6), ...
    'solveSec',    R.solveSec, ...
    'gLpGapMean',  mean(R.gLpGap), ...
    'costGapMean', mean(R.costGap), ...
    'plateauWMean', mean(R.plateauW));
if qc.verbose
    fprintf('  [q4_solve_p2] %d 天，购电 %.1f kWh，费用 %.2f 元（%.1f s）\n', ...
        nd, R.summary.qPlanTot, R.summary.costTot, R.solveSec);
    fprintf('     最优不唯一性：|g_LP − g_分位| 均值 %.4f kW，期望费用差 %.3e 元\n', ...
        R.summary.gLpGapMean, R.summary.costGapMean);
end

end
