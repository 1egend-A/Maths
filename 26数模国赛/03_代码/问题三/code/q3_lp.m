function out = q3_lp(prc, Sstart, Nhat, Rs, qc)
% Q3_LP  问题三/问题四【通用阶段 LP】——一次求解一个滚动阶段的充放电与购电
%
% 本函数是问题三与问题四【共用】的求解内核：问题四只是把 prc 换成附件4 的
% 逐日实测电价，模型结构一字不改（团队铁律「禁止各自生成求解器再拼接」的落地）。
%
% ------------------------------------------------------------
% 时域：任意长度 nH 的【连续余下时段】，总是以当日第 144 槽结束。
% 决策变量（全部为功率 kW，SOC 为 kWh）：
%   q_t            购电量（阶段 0 是【计划】G_t，阶段 ≥6 是【调整】A_t）
%   c_t, d_t       充电 / 放电功率（交流侧计量，口径 1）
%   S_t            时段末储电量
%   u_{t,s}        情景 s 下的紧急购电量（第二阶段的 recourse）
%
% 约束：
%   ① 情景供需平衡（不等式，多余部分即弃电，代价 0）
%        N^s_t + c_t − d_t − q_t − u_{t,s} ≤ 0
%      即「购电 + 紧急购电 ≥ 净负荷 + 充电 − 放电」。
%   ② SOC 递推（【等式】，绝不可写成不等式——否则储能能凭空少掉电量）
%        S_t − S_{t−1} − η·dt·c_t + (dt/η)·d_t = 0,   S_0 = Sstart
%   ③ 变量界：0 ≤ c,d ≤ P_max；S_min ≤ S ≤ S_max；末槽 S = S_end（口径 2 闭环）
%
% 目标：Σ_t coef·p_t·dt·q_t + Σ_t (k_em·p_t·dt/nS)·Σ_s u_{t,s}
%   其中 coef = qc.lpPriceCoef（默认 1，即基准交易电价，与问题二写法一致）。
%
% ------------------------------------------------------------
% ★ 为什么购电量可以「先解 LP、再按分位数覆盖」
%
%   购电量 q_t 在全部约束里都【只以自身出现】，不进入 SOC 递推（递推只含 c,d）。
%   因此给定任意可行的 (c,d)，目标对 q_t 的边际为
%       ∂/∂q_t = coef·p_t·dt·( 1 − (k_em/coef)·#{s : Q^s_t > q_t}/nS )
%   记 z_(1) ≤ … ≤ z_(nS) 为 Q^s_t = N^s_t + c_t − d_t 的升序次序统计量，则边际为 0
%   当且仅当 #{s : z_s > q_t} = nS·coef/k_em，即 q*_t 落在【一个区间】内：
%       q*_t ∈ [ z_(nS−k), z_(nS−k+1) ),   k = nS·coef/k_em
%   ⇒ **最优购电量不唯一**（等权离散经验分布的必然结果，问题二已实测确认）。
%     区间内任一点都给出同一个目标值与同一组最优 (c,d)，故
%     「先解 LP 得 (c,d)，再按报童临界分位定 q」是【精确】的两步法，不是近似。
%   分位数的选择规则见 q3_config.m 的「报童临界分位」一节。
% ------------------------------------------------------------
%
% 输入：
%   prc     nH×1   该阶段余下时段适用的电价（元/kWh）
%   Sstart  标量   该阶段起点的储电量 kWh（由已执行段的 soc_sim 给出）
%   Nhat    nH×1   净负荷点预测（kW）
%   Rs      nH×nS  净负荷预测残差的情景矩阵（kW）
%   qc              q3_config / q4_config 输出
%
% 输出 out:
%   .q .c .d .S     各 nH×1
%   .u              nH×nS
%   .Ns             nH×nS  = Nhat + Rs
%   .Sext           (nH+1)×1 含起点
%   .flag           1 = 最优
%   .objval         目标值（元）

persistent CACHE
nH = numel(prc);
nS = size(Rs, 2);
assert(size(Rs,1) == nH, 'Rs 的行数必须等于时域长度');

% ⚠️ 缓存键必须含 termPolicy：'close'/'free' 只差末槽的上下界，若只按 (nH,nS)
%    缓存，先跑 'free' 再跑 'close' 会命中到错的常数矩阵，且解仍"看起来正常"。
if isfield(qc,'termPolicy') && ~isempty(qc.termPolicy), tp = lower(qc.termPolicy); else, tp = 'close'; end
key = sprintf('h%d_s%d_%s', nH, nS, tp);
optKey = ['opts_' matlab.lang.makeValidName(qc.lpAlgo)];   % 'dual-simplex' → 合法字段名
if isempty(CACHE), CACHE = struct(); end
if ~isfield(CACHE, key)
    CACHE.(key) = buildConst(nH, nS, qc, tp);
end
if ~isfield(CACHE, optKey)
    % optimoptions 本身不便宜，而 1336 次调用只用到一套选项——缓存起来
    CACHE.(optKey) = optimoptions('linprog', 'Algorithm', qc.lpAlgo, 'Display', 'off');
end
K = CACHE.(key);

% ---- 情景净负荷与右端项 ----
Ns = Nhat(:) + Rs;                        % nH×nS
b  = -reshape(Ns, [], 1);
beq = [Sstart; zeros(nH-1,1)];

% ---- 目标函数（只依赖电价与该阶段长度，重建代价极低）----
f = [qc.lpPriceCoef * prc(:) * qc.dt; ...
     zeros(2*nH,1); ...
     zeros(nH,1); ...
     repmat(qc.kEm * prc(:) * qc.dt / nS, nS, 1)];

[x, objval, flag] = linprog(f, K.A, b, K.Aeq, beq, K.lb, K.ub, CACHE.(optKey));

out.flag   = flag;
out.objval = objval;
out.Ns     = Ns;
out.Sext   = [Sstart; zeros(nH,1)];
if flag == 1
    out.q = x(K.iq);  out.c = x(K.ic);  out.d = x(K.id);  out.S = x(K.iS);
    out.u = reshape(x(K.iu), nH, nS);
    out.Sext = [Sstart; out.S];
else
    out.q = nan(nH,1); out.c = nan(nH,1); out.d = nan(nH,1); out.S = nan(nH,1);
    out.u = nan(nH,nS);
end
end

% ======================================================================
function K = buildConst(nH, nS, qc, tp)
% 构造与本阶段时域长度相关、但【与电价/预测无关】的稀疏常数矩阵
% 缓存键 (nH, nS, tp)，四个阶段×两种末槽政策只需各构造一次。
% tp：'close' = 末槽钉死 S_end；'free' = 末槽只受 [S_min, S_max]（见调用处说明）。

dt = qc.dt;  eta = qc.eta;  PM = qc.P_max;

% ---- 变量分块 ----
iq = (1:nH)';
ic = nH     + (1:nH)';
id = 2*nH   + (1:nH)';
iS = 3*nH   + (1:nH)';
iu = 4*nH   + reshape(1:nH*nS, nH, nS);      % iu(t,s)
n  = 4*nH + nH*nS;

% ---- 行 1..nH*nS：情景补偿约束 ----
% ⚠️ 展开次序必须与 reshape(Ns,[],1) 完全一致：一律按 nH×nS【列优先】。
%    曾因把 s 当快变维而绑错 (t,s) 对——模型仍可解、flag 仍为 1、守恒律也成立，
%    但解无意义。下面四行对齐自检兜底。
rowIdx = (0:nS-1)*nH + (1:nH)';               % rowIdx(t,s) = (s-1)*nH + t
rowU   = repmat(reshape(rowIdx, [], 1), 4, 1);
colU   = [repmat(iq,nS,1); repmat(ic,nS,1); repmat(id,nS,1); reshape(iu,[],1)];
valU   = [-ones(nH*nS,1); ones(nH*nS,1); -ones(nH*nS,1); -ones(nH*nS,1)];
A = sparse(rowU, colU, valU, nH*nS, n);

% ---- 三元组对齐自检 ----
% ⚠️ 抽样点要挡住 nS = 1 的退化情形：此时 nH*nS = nH，原本的 [1, nH, nH+1, nH*nS]
%    里 nH 与 nH*nS 撞号、nH+1 越界，自检自己会先报错。故去重并裁到合法范围。
iuV = reshape(iu, [], 1);
ckList = unique([1, nH, nH+1, nH*nS]);
ckList = ckList(ckList >= 1 & ckList <= nH*nS);
for ck = ckList
    [tc, sc] = ind2sub([nH nS], ck);
    assert(rowU(ck) == (sc-1)*nH + tc, 'rowU 与 (t,s) 展开次序不一致');
    assert(colU(ck) == iq(tc),             'colU 第 1 块（q）次序不一致');
    assert(colU(nH*nS + ck) == ic(tc),     'colU 第 2 块（c）次序不一致');
    assert(colU(2*nH*nS + ck) == id(tc),   'colU 第 3 块（d）次序不一致');
    assert(colU(3*nH*nS + ck) == iuV(ck),  'colU 第 4 块（u）次序不一致');
end

% ---- SOC 递推（等式）----
rowSeq = (1:nH)';
Aeq = sparse([rowSeq; rowSeq(2:end); rowSeq; rowSeq], ...
             [iS;     iS(1:end-1);  ic;     id    ], ...
             [ones(nH,1); -ones(nH-1,1); -eta*dt*ones(nH,1); (dt/eta)*ones(nH,1)], ...
             nH, n);

% ---- 变量界 ----
lb = zeros(n,1);  ub = inf(n,1);
ub(ic) = PM;  ub(id) = PM;
lb(iS) = qc.S_min;  ub(iS) = qc.S_max;
% 口径 2：'close' = 日末固定 S_end（默认，与问题一/二一致）；
%         'free'  = 末槽只受 [S_min, S_max] 约束，用于 t_q3_term_policy.m 的对照。
% 注意 'free' 本身会让储能每天"占便宜"（可以把电留到明天不花钱），
% 故对照时必须按 p̄·(S_144 − S_0) 给日末储能计价才公平——见 t_q3_term_policy.m。
if strcmp(tp, 'close')
    lb(iS(nH)) = qc.S_end;  ub(iS(nH)) = qc.S_end;
end

K = struct('A',A,'Aeq',Aeq,'lb',lb,'ub',ub, ...
           'iq',iq,'ic',ic,'id',id,'iS',iS,'iu',iu,'n',n);
end
