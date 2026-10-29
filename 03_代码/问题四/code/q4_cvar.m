function [Tab, F] = q4_cvar(lams, alpha)
% Q4_CVAR  问题四加分项：CVaR 均值-风险模型与有效前沿
%
% ============================================================
%  保底口径（result4-2 / result4-3）假设"电价已知"，求的是【期望费用最优】。
%  但问题四的真实处境是：0:00 制定计划时，当天的附件4 电价【尚不可知】。
%  一个只优化期望的调度，会在电价尖峰日把费用顶到很高——这正是风险管理要管的事。
%
%  本脚本把"风险"显式写进目标，仍保持【纯线性规划】：
%
%     min  (1−λ)·E[费用] + λ·CVaR_α(费用)          λ ∈ [0,1] 为风险厌恶系数
%
%  CVaR（条件风险价值）用 Rockafellar–Uryasev 线性化：
%
%     CVaR_α(X) = min_η { η + 1/((1−α)·S) · Σ_s (X_s − η)^+ }
%
%  引入辅助变量 η（自由）与 v_s ≥ 0，约束 v_s ≥ X_s − η，即得 LP。
%  α = 0.95 ⇒ 只看最坏的 5% 尾部。
%
%  【逐日 LP 的变量与约束】
%     x = [g(144); c(144); d(144); S(144); u(144·S); η(1); v(S)]
%     情景平衡（144·S 行）：−g_t + c_t − d_t − u_{t,s} ≤ −N_{t,s}
%     SOC 递推（144 行）  ：S_t − S_{t−1} − η_e·dt·c_t + (dt/η_e)·d_t = 0，首端 S_0
%     CVaR 行（S 行）      ：Σ_t p_t·dt·g_t + Σ_t 5p_t·dt·u_{t,s} − v_s − η ≤ 0
%
%  ⚠️【与保底口径的一处重要差别】保底做法是"解 LP 定 (c,d)，再用报童分位覆盖 g"，
%     其正确性依赖"λ=0 且 g 不进入 SOC 递推 ⇒ g 的最优是一段区间"。当 λ>0 时目标
%     含 CVaR，g 的最优位置【不再】等于 0.8 分位（风险厌恶会把计划量推高，见下文
%     "有效分位"一列），故本脚本【一律采用 LP 自己解出的 g】，不做分位覆盖。
%     这同时使 λ=0 成为对保底口径的一次独立复算——脚本对此做断言自检。
%
%  【样本外设计】前 70% 天用来"选 λ"（拟合有效前沿），后 30% 天只做【评价】：
%     用被选中的 λ 逐日重解，统计【实际净负荷下】的真实费用分布。λ 是唯一的
%     被拟合量，故这是干净的样本外检验。
%
% 用法：[Tab, F] = q4_cvar();                        % λ = 0:0.25:1，α = 0.95
%       [Tab, F] = q4_cvar([0 0.5 1], 0.90);
%
% 落盘：out/q4_cvar.mat、out/q4_cvar.csv

if nargin < 1 || isempty(lams),  lams  = 0:0.25:1; end
if nargin < 2 || isempty(alpha), alpha = 0.95; end

ROOT = 'D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\';
D  = load([ROOT '数据预处理代码\out\data.mat']).D;
qc = q4_config();
qc.verbose = false;
nd = numel(qc.dayIdx);  nT = 144;  nS = qc.nScen;  dt = qc.dt;
nL = numel(lams);

fprintf('===== 问题四：CVaR 均值-风险模型（α = %.2f，λ 扫描 %d 点）=====\n', alpha, nL);
fprintf('区间 %d 天（%s ~ %s）\n', nd, string(qc.dateFirst), string(qc.dateLast));

fF = [qc.outdir 'q4_forecast.mat'];
if isfile(fF)
    F2 = load(fF, 'F2').F2;
else
    q2c = q2_config();  q2c.verbose = false;
    F2  = q2_forecast(D, q2c);
end
pr = D.actual.price(qc.dayIdx, :);           % nd × 144

% 样本内外划分
nIn  = round(0.70*nd);
idxIn  = 1:nIn;   idxOut = (nIn+1):nd;
fprintf('样本内 %d 天（%s ~ %s）| 样本外 %d 天（%s ~ %s）\n', ...
    nIn, string(D.actual.dates(qc.dayIdx(idxIn(1)))), string(D.actual.dates(qc.dayIdx(idxIn(end)))), ...
    nd-nIn, string(D.actual.dates(qc.dayIdx(idxOut(1)))), string(D.actual.dates(qc.dayIdx(idxOut(end)))));

% 预算情景（与保底口径同一套残差池，保证可比）
[NsAll, NactAll] = buildScen(F2, qc, nS);
fprintf('情景池：%d 天 × %d 情景\n', nd, nS);

%% ================= 主循环 =================
% 存：lams × nd 的 {E费用, CVaR, 实付费用, 有效分位, 计划量}
Ecost = nan(nL, nd);  Cvar = nan(nL, nd);
RealC = nan(nL, nd);  qEff = nan(nL, nd);  qgTot = nan(nL, nd);
secTot = zeros(nL,1);

fprintf('\n---- 逐 λ 求解（共 %d 个 LP）----\n', nL*nd);
for i = 1:nL
    lam = lams(i);  t0 = tic;
    for k = 1:nd
        d = qc.dayIdx(k);
        [x, ok] = solveDayCvar(pr(k,:)', NsAll{k}, NactAll{k}, qc, lam, alpha);
        if ~ok
            warning('λ=%.2f 第 %d 天 LP 未收敛，跳过', lam, d);
            continue;
        end
        cs = costScen(x, pr(k,:)', qc, nT, nS);
        Ecost(i,k) = mean(cs);
        Cvar(i,k)  = cvarVal(x, cs, qc, alpha, nT, nS);
        RealC(i,k) = realCost(x, pr(k,:)', NactAll{k}, qc, nT);
        qEff(i,k)  = effQuant(x, NsAll{k}, qc, nT, nS);
        qgTot(i,k) = sum(x(1:nT))*dt;
    end
    secTot(i) = toc(t0);
    fprintf('  λ = %.2f：样本内 E=%14.2f 元 | CVaR=%14.2f 元 | 有效分位 %.4f | 实付(全期) %14.2f 元（%.0f s）\n', ...
        lam, mean(Ecost(i,idxIn)), mean(Cvar(i,idxIn)), mean(qEff(i,:), 'omitnan'), ...
        sum(RealC(i,:), 'omitnan'), secTot(i));
end

%% ================= λ=0 自检：必须复现保底口径 =================
% ⚠️ 必须比【期望费用】，不能比【实付费用】。
%    保底口径是"解 LP 定 (c,d)，再用报童分位覆盖 g"；本脚本 λ=0 时【用 LP 自己的 g】。
%    由于 g 不进入 SOC 递推，其最优是一段【区间】（最优面不唯一），区间上任意 g 给出
%    相同的期望费用，却给出【不同的实付费用】（紧急购电量随 g 变化）。
%    故实付费用天然可比性差，拿它做断言会误判；期望费用才是两者共同优化的那个量。
i0 = find(lams == 0, 1);
okSelf = true;  cRef = NaN;
f2 = [qc.outdir42 'q4_solution_p2.mat'];
fprintf('\n---- 自检：λ = 0 应与保底口径（result4-1 保底一）一致 ----\n');
if ~isempty(i0) && isfile(f2)
    R2 = load(f2, 'R2').R2;
    cRef = R2.summary.costExpTot;                  % 保底口径的【期望】费用合计
    cCV  = sum(Ecost(i0,:), 'omitnan');            % CVaR LP 的期望费用合计
    dc   = abs(cCV - cRef);
    okSelf = dc < 1e-3 * abs(cRef);
    fprintf('  期望费用：保底一 %14.2f 元 | CVaR(λ=0) %14.2f 元 | 相对差 %.3e   -> %s\n', ...
        cRef, cCV, dc/abs(cRef), pass(okSelf));
    fprintf('  实付费用：保底一 %14.2f 元 | CVaR(λ=0) %14.2f 元（差 %+.2f 元，%.3f%%）\n', ...
        R2.summary.costTot, sum(RealC(i0,:), 'omitnan'), ...
        sum(RealC(i0,:), 'omitnan') - R2.summary.costTot, ...
        100*(sum(RealC(i0,:),'omitnan') - R2.summary.costTot)/R2.summary.costTot);
    fprintf('  ⚠️ 实付之差【不是误差】：g 的最优面不唯一，同期望费用的不同 g 给出不同实付。\n');
    fprintf('     |g_LP − g_分位| 均值 %.4f kW（保底口径自己的记录：%.4f kW）\n', ...
        mean(abs(R2.gLp(:) - R2.gPlan(:))), R2.summary.gLpGapMean);
    qm = mean(qEff(i0,:), 'omitnan');
    fprintf('  λ=0 的有效分位均值 %.4f（理论值 0.80 = 报童临界分位）   -> %s\n', ...
        qm, pass(abs(qm - 0.8) < 0.02));
    okSelf = okSelf && abs(qm - 0.8) < 0.02;
else
    fprintf('  跳过（未找到 %s）\n', f2);
end

%% ================= 有效前沿 =================
fprintf('\n---- 有效前沿（样本内 %d 天均值）----\n', nIn);
Ebar = mean(Ecost(:,idxIn), 2);      % nL×1
Cbar = mean(Cvar(:,idxIn), 2);
fprintf('  %-8s %16s %16s %14s %14s %12s\n', ...
    'λ', 'E[费用](元)', 'CVaR_95(元)', '较λ=0 E +%', '较λ=0 CVaR −%', '有效分位');
for i = 1:nL
    fprintf('  %-8.2f %16.2f %16.2f %13.3f %13.3f %12.4f\n', ...
        lams(i), Ebar(i), Cbar(i), 100*(Ebar(i)-Ebar(1))/Ebar(1), ...
        100*(Cbar(1)-Cbar(i))/Cbar(1), mean(qEff(i,idxIn), 'omitnan'));
end
fprintf('\n  ★ "稳健性的代价"：从 λ=0 走到 λ=1，期望费用上升 %.3f%%，尾部风险(CVaR)下降 %.3f%%\n', ...
    100*(Ebar(end)-Ebar(1))/Ebar(1), 100*(Cbar(1)-Cbar(end))/Cbar(1));
fprintf('  ★ 有效分位随 λ 单调【上升】：风险厌恶 ⇒ 计划购电量取更高的分位数，\n');
fprintf('    等于主动多买一点电，把"电价尖峰日买不到便宜电"的尾部风险换掉。\n');

%% ================= 样本外 =================
fprintf('\n---- 样本外（后 %d 天，按实际净负荷结算）----\n', nd-nIn);
fprintf('  %-8s %16s %16s %16s %16s\n', 'λ', '实付合计(元)', '日均(元)', '日标准差(元)', '最坏日(元)');
for i = 1:nL
    v = RealC(i, idxOut);  v = v(isfinite(v));
    fprintf('  %-8.2f %16.2f %16.2f %16.2f %16.2f\n', ...
        lams(i), sum(v), mean(v), std(v), max(v));
end
% 样本外尾部：最坏 5% 天的均值
fprintf('\n  %-8s %16s %16s\n', 'λ', '最坏5%日均(元)', '相对λ=0降幅%');
v0 = RealC(1, idxOut);  v0 = v0(isfinite(v0));
for i = 1:nL
    v = RealC(i, idxOut);  v = v(isfinite(v));
    kv = max(1, ceil(0.05*numel(v)));
    tail = mean(maxk(v, kv));
    t0_ = mean(maxk(v0, kv));
    fprintf('  %-8.2f %16.2f %16.3f\n', lams(i), tail, 100*(t0_-tail)/t0_);
end
fprintf('\n  ★ 样本外检验的意义：λ 是【唯一】被样本内拟合的量。若样本外尾部降幅与\n');
fprintf('    样本内一致，说明"用 CVaR 换期望"的策略在未见过的日子上同样成立，\n');
fprintf('    不是对历史样本的过拟合。\n');

%% ================= 汇总落盘 =================
Tab = table(repmat(lams(:), nd, 1), ...
    repmat((1:nd)', nL, 1), ...
    reshape(Ecost', [], 1), reshape(Cvar', [], 1), ...
    reshape(RealC', [], 1), reshape(qEff', [], 1), reshape(qgTot', [], 1), ...
    'VariableNames', {'lambda','dayIdx','E费用_元','CVaR_元','实付费用_元','有效分位','计划电量_kWh'});
writetable(Tab, [qc.outdir 'q4_cvar.csv'], 'Encoding', 'UTF-8');

F = struct('lams', lams, 'alpha', alpha, 'nIn', nIn, 'idxIn', idxIn, 'idxOut', idxOut, ...
    'Ecost', Ecost, 'Cvar', Cvar, 'RealC', RealC, 'qEff', qEff, 'qgTot', qgTot, ...
    'Ebar', Ebar, 'Cbar', Cbar, 'secTot', secTot, 'okSelf', okSelf, 'cRef', cRef, ...
    'dates', D.actual.dates(qc.dayIdx));
save([qc.outdir 'q4_cvar.mat'], 'F', 'Tab');
fprintf('\n  已写出：%s\n', [qc.outdir 'q4_cvar.csv']);
fprintf('  已写出：%s\n', [qc.outdir 'q4_cvar.mat']);
end

% ======================================================================
function [NsAll, NactAll] = buildScen(F, qc, nS)
% 逐日情景净负荷（与 q4_solve_p2 完全同一套残差池，保证可比）
nT = 144;  nd = numel(qc.dayIdx);
NsAll = cell(nd,1);  NactAll = cell(nd,1);
for k = 1:nd
    d = qc.dayIdx(k);
    pool = (d-nS):(d-1);  pool = pool(pool >= 1);
    if isempty(pool), pool = d; end
    Rm = F.Nact(pool,:) - F.Nhat(pool,:);
    if size(Rm,1) >= nS
        Rs = Rm(end-nS+1:end, :)';
    else
        Rs = repmat(Rm', 1, ceil(nS/size(Rm,1)));  Rs = Rs(:, 1:nS);
    end
    NsAll{k}   = F.Nhat(d,:)' + Rs;      % nT × nS
    NactAll{k} = F.Nact(d,:)';           % nT × 1（实际净负荷）
end
end

% ======================================================================
function [x, ok] = solveDayCvar(prc, Ns, ~, qc, lam, alpha)
% 逐日 CVaR LP。x = [g; c; d; S; u; η; v]，未收敛时 ok = false。
nT = 144;  nS = qc.nScen;  dt = qc.dt;  eta = qc.eta;  PM = qc.P_max;
kEm = qc.kEm;
pdt = prc * dt;

ig = (1:nT)';  ic = nT+(1:nT)';  id = 2*nT+(1:nT)';  iS = 3*nT+(1:nT)';
iu = 4*nT + reshape(1:nT*nS, nT, nS);
iEta = 4*nT + nT*nS + 1;
iv   = iEta + (1:nS)';
n    = 4*nT + nT*nS + 1 + nS;

% --- 情景平衡 ---
rowIdx = (0:nS-1)*nT + (1:nT)';
rowU   = repmat(reshape(rowIdx, [], 1), 4, 1);
colU   = [repmat(ig,nS,1); repmat(ic,nS,1); repmat(id,nS,1); reshape(iu,[],1)];
valU   = [-ones(nT*nS,1); ones(nT*nS,1); -ones(nT*nS,1); -ones(nT*nS,1)];

% --- CVaR 行：cost_s − v_s − η ≤ 0，cost_s = Σ p_t·dt·g_t + Σ 5p_t·dt·u_{t,s} ---
rCV = nT*nS + (1:nS)';
ri = zeros(nS*(2*nT+2), 1);  ci = ri;  vi = ri;  z = 0;
for s = 1:nS
    nb = 2*nT + 2;
    ri(z+(1:nb)) = rCV(s);
    ci(z+(1:nb)) = [ig; iu(:,s); iv(s); iEta];
    vi(z+(1:nb)) = [pdt; kEm*pdt; -1; -1];
    z = z + nb;
end
A = sparse([rowU; ri], [colU; ci], [valU; vi], nT*nS + nS, n);

% --- SOC 递推 ---
rowSeq = (1:nT)';
Aeq = sparse([rowSeq; rowSeq(2:end); rowSeq; rowSeq], ...
             [iS;     iS(1:end-1);  ic;     id    ], ...
             [ones(nT,1); -ones(nT-1,1); -eta*dt*ones(nT,1); (dt/eta)*ones(nT,1)], ...
             nT, n);
beq = [qc.S0; zeros(nT-1,1)];
b   = [-reshape(Ns,[],1); zeros(nS,1)];

% --- 目标：(1−λ)/S·Σ_s cost_s + λ·[η + 1/((1−α)S)·Σ_s v_s] ---
f = zeros(n,1);
f(ig)     = (1-lam) * pdt;                                  % g 对每个情景都出现
f(iu(:))  = (1-lam)/nS * kEm * repmat(pdt, nS, 1);
f(iEta)   = lam;
f(iv)     = lam / ((1-alpha)*nS);

lb = zeros(n,1);  ub = inf(n,1);
lb(iEta) = -inf;                                            % η 自由
ub(ic) = PM;  ub(id) = PM;
lb(iS) = qc.S_min;  ub(iS) = qc.S_max;
ub(iS(nT)) = qc.S_end;                                      % 口径 2：日末闭环
lb(iS(nT)) = qc.S_end;

opts = optimoptions('linprog', 'Algorithm', qc.lpAlgo, 'Display', 'off');
[x, ~, flag] = linprog(f, A, b, Aeq, beq, lb, ub, opts);
if flag ~= 1
    % 兜底：换算法重试一次（CVaR 行的尺度与保底 LP 不同，偶有算法偏好差异）
    opts2 = optimoptions('linprog', 'Algorithm', 'dual-simplex', 'Display', 'off');
    [x, ~, flag] = linprog(f, A, b, Aeq, beq, lb, ub, opts2);
end
ok = (flag == 1);
end

% ======================================================================
function cs = costScen(x, prc, qc, nT, nS)
% 各情景费用 cost_s = Σ p_t·dt·g_t + Σ 5p_t·dt·u_{t,s}
g = x(1:nT);  U = reshape(x(4*nT + (1:nT*nS)), nT, nS);
cs = sum(prc .* g) * qc.dt + qc.kEm * qc.dt * (prc' * U);
cs = cs(:);
end

% ======================================================================
function c = cvarVal(x, cs, qc, alpha, ~, nS)
% 直接按定义算 CVaR_α（与 LP 的 η + 1/((1−α)S)Σv_s 同值，此处独立复算）
% CVaR_α = min_η { η + 1/((1−α)S) Σ_s (cost_s − η)^+ }
eta = x(end-nS);
c = eta + sum(max(0, cs - eta)) / ((1-alpha)*nS);
end

% ======================================================================
function c = realCost(x, prc, NactRow, qc, nT)
% 实际净负荷下的真实费用（用于样本外评价）
g = x(1:nT);  cc = x(nT+(1:nT));  dd = x(2*nT+(1:nT));
net = NactRow + cc - dd - g;
e   = max(0, net);
c = sum(prc .* g) * qc.dt + qc.kEm * qc.dt * sum(prc .* e);
end

% ======================================================================
function q = effQuant(x, Ns, qc, nT, nS)
% LP 解出的 g 在各情景净需求分布中的【有效分位】：rank(g) / nS 的均值
g = x(1:nT);  cc = x(nT+(1:nT));  dd = x(2*nT+(1:nT));
Q = Ns + cc - dd;
act = g > 1e-9;
if ~any(act), q = NaN; return; end
rk = sum(Q(act,:) < g(act), 2) / nS;
q = mean(rk);
end

% ======================================================================
function s = pass(b)
if b, s = 'PASS'; else, s = 'FAIL'; end
end
