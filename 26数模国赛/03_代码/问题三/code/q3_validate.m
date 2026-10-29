function ok = q3_validate(D, F, qc, R, tag)
% Q3_VALIDATE  问题三求解结果的独立校验 + 基准对照
%
% 校验分四层（体例克隆 q2_validate.m，但每层都针对本问的新结构）：
%   A 结构不变量：SOC 递推、上下限、日末闭环、充放功率上限、无同时充放、非负性
%   B 守恒律与实际结算：逐槽能量平衡、弃电非负、弃电/紧急购电逐槽互斥且弃电必有来源、
%     【已冻结时段不可改】——阶段 τ 只能改 t > 6τ 的槽，故 t ≤ 36 处须有 A_t = G_t
%   C 费用复算：题面三块费用逐块按定义重算，并与 Sadj 对账
%   D 模型论断验证：把每阶段的情景净需求 Q^(j)_t 【从预报与快照独立重建】，
%     再核两条解析结论——
%        (1) 计划量  G_t = max(0, Q^(1)_(0.8))          且 #{s:Q>G} ≤ nS·0.2
%        (2) 调整量  A_t = min( max(G_t, Q_(0.7)), Q_(0.9) )，且逐槽落在 [Q_0.7, Q_0.9]
%     ⚠️ D 层刻意【不读】q3_solve 存下来的 q07/q09/AgLo/AgHi（那等于拿求解器的
%        输出验证它自己，是循环论证）。Q 由 F.Nhat4 + F.Nact 残差池 + R.Csnap/Dsnap
%        重建，与 q3_solve 只有数据接口、没有代码接口。
%     ⚠️ R.Csnap/Dsnap 存的是各阶段 LP【自己解出的】充放电（不是"解之前已有的"）：
%        Q^(j) = Nhat_j + 残差 + c^(j) − d^(j)，其中的 (c,d) 正是这一次 LP 的输出。
%        存成输入的话阶段 1 会少掉 LP0 自己选的充放电，重建的 Q 与求解器实际用的 Q
%        差至 5000 kW（= P_max），D 层整体误判。
%     ⚠️ 调整阶段只核「本阶段认领的槽」（见循环内注释）：A_t 会被后续阶段再次覆盖，
%        存下来的最终值只属于最后一个碰到它的阶段，全体对账会重复计数。
%
% 基准对照（四档，逐档加信息/加机制）：
%   E 完美信息基准  ：含储能、净负荷完全已知（用 q3_lp 直接解，无预测误差）→ 费用下界
%   F 无储能基准    ：G_t = 实际净负荷，无储能、无调整
%   G 只定计划不调整：本模型的信息集，但从不使用 6/12/18 的调整（= R.costNoAdj）
%   H 本模型        ：四阶段滚动调整
%   由此得到三个可直接写进论文的价差：
%       调整机制的价值 = G − H；储能的价值 = F − H；预测误差的代价 = H − E
%
% 用法：
%   ok = q3_validate()                 % 自动读取 out/q3_solution.mat
%   ok = q3_validate(D, F, qc, R)      % 复用已算好的对象（省去重跑 oracle 的 ~20 s）
%   ok = q3_validate(D, F, qc, R, tag) % 同上，且产物文件名加前缀 tag（跨问转调时用）
%
% ⚠️ 输出目录【由传入的 qc 决定】，不再无条件取 q3_config()。
%    曾经 outdir = q3_outdir() 是无参的、内部自调 q3_config()，于是【无视】传入的 qc：
%    q4_validate 转调本函数校验【附件4】的 R3 时，本意是"报告落在问题四 out/ 下"，
%    实际却写进了 问题三/out/q3_validate_report.txt —— 把问题三自己的校验报告
%    （result3 = 14 724 901.09 元）覆盖成了附件4 的数字（15 386 858.33 元），
%    报告与 result3.xlsx 互相矛盾。调用方 q4_validate.m:112 写了注释想防这件事，
%    但被调方直接无视了 qc ⇒ 防御意图被静默作废。**跨问转调必须同时传 tag。**
%
% 注：本文件用【嵌套函数】而非局部函数来收集日志——MATLAB 局部函数有自己的
%     工作区，对 lines 的写入不会传回调用者（会静默丢掉全部日志）。q2_validate 同款。

% ---------------- 载入 ----------------
if nargin < 5 || isempty(tag), tag = ''; end
qcOwn = q3_config();
if nargin >= 3 && ~isempty(qc)
    outdir = qc.outdir;          % 谁调用，就写谁家 out/ —— 不污染问题三
else
    outdir = qcOwn.outdir;
end
matFile = fullfile(qcOwn.outdir, 'q3_solution.mat');   % 读：始终找问题三自己的解
if nargin < 4 || isempty(R) || nargin < 3 || isempty(qc)
    assert(isfile(matFile), '未找到 %s，请先运行 q3_solve', matFile);
    S = load(matFile);
    if nargin < 4 || isempty(R),  R  = S.R;  end
    if nargin < 3 || isempty(qc), qc = S.qc; end
end
if nargin < 1 || isempty(D) || nargin < 2 || isempty(F)
    D = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码\out\data.mat').D;
    fcFile = fullfile(outdir, 'q3_forecast.mat');
    if isfile(fcFile)
        F = load(fcFile).F;
    else
        F = q3_forecast(D, qc);
    end
end

TOL   = 1e-6;
lines = {};

    function say(varargin)
        lines{end+1} = sprintf(varargin{:});
    end

nd  = numel(R.dayIdx);
nT  = 144;
nS  = qc.nScen;
dt  = qc.dt;
eta = qc.eta;
issH = qc.fcIssHours(:)';
nIss = numel(issH);

say('==========================================================');
say(' 问题三求解结果校验报告');
say('==========================================================');
say('区间 %s ~ %s，共 %d 天', string(R.date(1)), string(R.date(end)), nd);
% ⚠️ 电价口径必须按【实际传入的 qc.priceMode】写，不能硬编码成"附件1 逐日相同"。
%    本函数会被问题四借用（q4_validate 的 D' 层用它校验 result4-3），
%    而 result4-3 用的是附件4 逐日电价。硬编码会让报告开头把口径写反——
%    报告是要随结果一起交付的，写反即交付错误。
switch lower(qc.priceMode)
    case 'fixed'
        say('电价 = 附件1 逐日相同（典型日剖面，问题二/三口径）；信息集 = 附件3 官方光伏预报 + 自预测负载（口径 7）');
    case 'volatile'
        say('电价 = 附件4 逐日逐时（实测电价，问题四口径）；信息集 = 附件3 官方光伏预报 + 自预测负载（口径 7）');
    otherwise
        say('电价 = priceMode = %s；信息集 = 附件3 官方光伏预报 + 自预测负载（口径 7）', qc.priceMode);
end
say('决策时刻 %s（0:00 定计划，其余定调整）；情景数 nS = %d', ...
    mat2str(issH), nS);
say('分位：qPlan = %.2f | qAdjLo = %.2f | qAdjHi = %.2f', qc.qPlan, qc.qAdjLo, qc.qAdjHi);
say('');

pr = R.price;                       % nd×144（'fixed' 时逐日相同）

%% ================= A. 结构不变量 =================
say('---- A. 结构不变量 ----');
% A1 SOC 递推（逐日循环以尊重 d = 1..nT-1 的递推次序）
Srec = zeros(nd, nT);
for k = 1:nd
    Sp = qc.S0;
    for t = 1:nT
        Sp = Sp + (eta*R.C(k,t) - R.D(k,t)/eta)*dt;
        Srec(k,t) = Sp;
    end
end
eA1 = max(abs(Srec(:) - R.Soc(:)));
okA1 = eA1 < 1e-6;
say('A1 SOC 递推残差 max = %.3e   -> %s', eA1, pass(okA1));

% A2 SOC 上下限
lo = min(R.Soc(:)); hi = max(R.Soc(:));
okA2 = lo >= qc.S_min - TOL && hi <= qc.S_max + TOL;
say('A2 SOC 范围 [%.4f, %.4f]，要求 [%g, %g]  -> %s', lo, hi, qc.S_min, qc.S_max, pass(okA2));

% A3 日末闭环
eA3 = max(abs(R.Soc(:,end) - qc.S_end));
okA3 = eA3 < 1e-6;
say('A3 日末 SOC 均为 %g（口径 2），偏差 max = %.3e  -> %s', qc.S_end, eA3, pass(okA3));

% A4 充放功率上限
mx = max([max(R.C(:)), max(R.D(:))]);
okA4 = mx <= qc.P_max + TOL;
say('A4 充放功率 max = %.4f kW，上限 %g kW  -> %s', mx, qc.P_max, pass(okA4));

% A5 无同时充放
nBoth = sum(sum(R.C > 1e-6 & R.D > 1e-6));
okA5 = nBoth == 0;
say('A5 同时充放时段数 = %d  -> %s', nBoth, pass(okA5));

% A6 计划量与调整量非负
okA6 = min(R.G(:)) >= -TOL && min(R.A(:)) >= -TOL;
say('A6 计划量 min = %.6f kW，调整量 min = %.6f kW  -> %s', ...
    min(R.G(:)), min(R.A(:)), pass(okA6));

%% ================= B. 守恒律与实际结算 =================
say('');
say('---- B. 守恒律与实际结算 ----');
% B1 逐槽能量平衡：A + e + D − (净负荷 + C) = 弃电
res = R.A + R.gEm + R.D - (F.Nact(R.dayIdx,:) + R.C);
eB1 = max(abs(res(:) - R.curt(:)));
okB1 = eB1 < 1e-6;
say('B1 弃电量与解算值一致 max = %.3e kW   -> %s', eB1, pass(okB1));

% B2 弃电与紧急购电非负
okB2 = min(R.curt(:)) >= -TOL && min(R.gEm(:)) >= -TOL;
say('B2 弃电 min = %.6e，紧急购电 min = %.6e kW   -> %s', ...
    min(R.curt(:)), min(R.gEm(:)), pass(okB2));

% B3 ★ 弃电的判定标准（判据曾写错两版，均在此留痕）
%   ⚠️ 第 1 版：「弃电 ⇒ 实际净负荷 Nact < 0」。实测 29546 槽违例。不是 bug，是判据错：
%      本模型按报童分位购电（G = Q_(0.8)，A = clip(Q_(0.7), Q_(0.9))）。当某情景的
%      【实际】净负荷低于所买的分位值时，买进来的电用不完，多出的部分就是弃电——此时
%      Nact 完全可以是正的（白天光伏照常、只是负载比预报低）。这是分位对冲的固有代价。
%   ⚠️ 第 2 版：「弃电 ⇒ A_t > 0 或 Nact < 0」。仍错，漏了【放电】。逐槽平衡是
%        A + e + D = Nact + C + curt
%      弃电的直接条件是「供给侧 A + D 超过需求侧 Nact + C」。储能按分位计划充了电、
%      日末又必须回到 6000，多充的电只能在低需求时段放掉；放出去没人用，同样是弃电。
%      故 A = 0 的槽也可能弃电。
%   正确的硬约束（两版都漏）：
%     ① 逐槽互斥：同一槽不可能既弃电又紧急购电（不平衡量只可能是一边）；
%     ② 弃电必有来源：A_t > 0（超买）或 D_t > 0（多放）或 Nact_t < 0（光伏富余），
%        三者至少其一。三者皆无 ⇒ 供给侧为 0、需求侧非负，不可能溢出。
gEmCur  = R.gEm  > 1e-6;
curtCur = R.curt > 1e-6;
srcA = R.A > TOL;  srcD = R.D > TOL;  srcN = F.Nact(R.dayIdx,:) < -TOL;
nBoth   = sum(sum(gEmCur & curtCur));
badCurt = sum(sum(curtCur & ~(srcA | srcD | srcN)));
okB3 = nBoth == 0 && badCurt == 0;
say('B3 弃电与紧急购电逐槽互斥（重叠 %d 槽）   -> %s', nBoth, pass(nBoth == 0));
say('     弃电来源（可重叠）：超买 A_t>0 %d 槽 / 多放 D_t>0 %d 槽 / 光伏富余 Nact<0 %d 槽', ...
    sum(sum(curtCur & srcA)), sum(sum(curtCur & srcD)), sum(sum(curtCur & srcN)));
say('     按净负荷符号：光伏富余 %d 槽 / 净负荷为正（分位对冲与日末回充的代价）%d 槽', ...
    sum(sum(curtCur & srcN)), sum(sum(curtCur & ~srcN)));
say('     无来源的弃电 %d 槽（应为 0）   -> %s', badCurt, pass(badCurt == 0));
pvTot = sum(sum(D.actual.pv(R.dayIdx,:)))*dt;
say('     全期弃电 %.0f kWh（占光伏发电 %.0f kWh 的 %.2f%%；光伏富余段的弃电占大头）', ...
    sum(R.curt(:))*dt, pvTot, 100*sum(R.curt(:))*dt/pvTot);

% B4 ★ 调整的作用域
%   槽 t 只可能被满足 6τ < t 的阶段改到。最晚的调整在 18:00（6τ = 108），
%   故 t ≤ 36 的槽【任何阶段都动不了】（6:00 阶段从第 37 槽起），必有 A_t ≡ G_t。
%   ⚠️ 注意 37..108 的槽【是】可调的——它们只在 6:00 那一次被定下来，之后冻结。
%      曾误写成「A_t ≡ G_t 对所有 t ≤ 6τ」——那是把每个阶段各自的冻结前缀当成了
%      全局结论，实际 stage 2 会写 37..144。
nHead = 6*issH(2);                       % 36：首个调整时刻之前的槽数
violH = sum(sum(abs(R.A(:,1:nHead) - R.G(:,1:nHead)) > 1e-6));
okB4a = violH == 0;
say('B4 0:00–6:00 的 %d 个槽不可调（A_t ≡ G_t），违例 = %d   -> %s', ...
    nHead, violH, pass(okB4a));

% B5 调整量的记录范围：AgLo/AgHi 只在 t ≥ 37 有值，且 37..144 被阶段 2 全覆盖
inScope = R.AgLo(:, nHead+1:end);
% ⚠️ all(矩阵) 返回【逐列】的行向量，不是标量；必须再套 all(...,'all') 或 (:)
okB5 = all(isnan(R.AgLo(:,1:nHead)), 'all') && all(isfinite(inScope(:)));
nAdjChk = numel(inScope);
say('B5 调整量落位记录覆盖 6:00 之后的全部 %d 个槽（前 %d 个为 NaN）   -> %s', ...
    nAdjChk, nHead, pass(okB5));
say('      （口径 3 = 逐 10 分钟：A_t 与 G_t 逐槽比较；前 %d 个槽在 6:00 时已执行）', nHead);

%% ================= C. 费用复算 =================
say('');
say('---- C. 费用复算（按题面三块的定义逐块重算）----');
over  = max(0, R.A - R.G);
under = max(0, R.G - R.A);
cPlan = sum(sum(pr .* dt .* min(R.G, R.A)));
cAdj  = sum(sum(pr .* dt .* (qc.kUnder*under + qc.kOver*over)));
cEm   = sum(sum(qc.kEm * pr .* dt .* R.gEm));

eC1 = abs(cPlan - R.summary.costPlanTot);
eC2 = abs(cAdj  - R.summary.costAdjTot);
eC3 = abs(cEm   - R.summary.costEmTot);
okC = max([eC1 eC2 eC3]) < 1e-4;
say('C1 计划购电费 %14.2f 元，复算差 = %.3e   -> %s', R.summary.costPlanTot, eC1, pass(okC));
say('C2 调整购电费 %14.2f 元，复算差 = %.3e   -> %s', R.summary.costAdjTot,  eC2, pass(okC));
say('C3 紧急购电费 %14.2f 元，复算差 = %.3e   -> %s', R.summary.costEmTot,   eC3, pass(okC));
eC4 = abs((cPlan + cAdj + cEm) - sum(R.Sadj));
okC4 = eC4 < 1e-6;
say('C4 三块之和与 Sadj 之差 = %.3e 元（应为 0：题面「总费用 = 三块之和」）  -> %s', eC4, pass(okC4));
say('     调整购电费恒非负：min(逐日值) = %.4f 元', min(R.costAdj));

% C5 调整的两条收益渠道自洽：Sadj ≤ 只调购电量 ≤ 完全不调
okC5 = sum(R.Sadj) <= sum(R.costAdjOnly) + 1e-6 && ...
       sum(R.costAdjOnly) <= sum(R.costNoAdj) + 1e-6;
say('C5 费用单调性 不调整 ≥ 只调购电量 ≥ 全调整：%.2f ≥ %.2f ≥ %.2f 元   -> %s', ...
    sum(R.costNoAdj), sum(R.costAdjOnly), sum(R.Sadj), pass(okC5));

%% ================= D. 模型论断验证（独立重建 Q）=================
say('');
say('---- D. 模型论断验证（从预报与快照独立重建情景净需求）----');

kPr = max(1, min(nS, ceil(qc.qPlan  *nS)));   % 0.8 分位的次序统计量下标
kLo = max(1, min(nS, ceil(qc.qAdjLo*nS)));    % 0.7
kHi = max(1, min(nS, ceil(qc.qAdjHi*nS)));    % 0.9

maxGapG = 0;  maxGapA = 0;  nClipFalse = 0;  nClipTrue = 0;
cntAboveIn = 0; nIn = 0;  cntAboveClip = 0; nClip = 0;
cntAdjSlot = 0;  loAgLo = inf;  loAgHi = inf;
nStation = 0;  nG0 = 0;
for k = 1:nd
    d    = R.dayIdx(k);
    pool = (d-nS):(d-1);  pool = pool(pool >= 1);
    if isempty(pool), pool = d; end          % 与 q3_solve 的退化分支一致

    for j = 1:nIss
        if j >= 2 && ~qc.useStages(j), continue; end
        if j == 1
            H = 1:nT;
        else
            H = (6*issH(j)+1):nT;
            if isempty(H), continue; end
        end
        % ★ 重建：Q = 预报 + 残差 + 当时的充放电（快照）
        % ⚠️ 三维数组用 (k, H', j) 这种"下标形状不一致"的写法时，结果维度按
        %    MATLAB 的拼接规则走，容易得到 1×nH 而不是 nH×1，与 nH×nS 相加即报
        %    「数组的大小不兼容」。先 reshape 成列再按 H 取，维度才确定。
        Cs = reshape(R.Csnap(k, :, j), [], 1);
        Ds = reshape(R.Dsnap(k, :, j), [], 1);
        Ns = F.Nhat4(d, H, j)' + residPool(F, pool, H, j, nS) ...
             + Cs(H) - Ds(H);                               % nH×nS
        Qs = sort(Ns, 2);

        if j == 1
            gRef = max(0, Qs(:, kPr));                       % 计划量闭式
            maxGapG = max(maxGapG, max(abs(gRef - R.G(k,H)')));
            ab = sum(Ns > R.G(k,H)' + 1e-9, 2);
            isIn = Qs(:,kPr) > 0;                            % 未触发 g≥0 截断
            cntAboveIn = cntAboveIn + sum(ab(isIn));  nIn   = nIn   + sum(isIn);
            cntAboveClip = cntAboveClip + sum(ab(~isIn)); nClip = nClip + sum(~isIn);
            nG0 = nG0 + sum(~isIn);
            nStation = nStation + numel(H);
        else
            q07 = max(0, Qs(:, kLo));
            q09 = max(0, Qs(:, kHi));
            % ★ 只比「本阶段拥有的槽」
            %   槽 t 的 A_t / clipHi 会被【后续阶段再次覆盖】（阶段 3 会重写 73..144、
            %   阶段 4 会重写 109..144），存下来的最终值只反映【最后一个碰到它的阶段】。
            %   若每个阶段都拿 R.A(k,H) 全体去比，早期阶段就在和"后来被改过的 A"对账，
            %   且槽被重复计数——实测受检调整槽 334×216=72144（应为 334×108=36072），
            %   D1/D3/D4/D5 全数误判。故本阶段只认领「后面没有活跃阶段再覆盖」的那些槽：
            %   阶段 j 认领 (6τ_j, 6τ_{j+1}]，且仅当阶段 j+1 确实启用时才切分。
            if j < nIss && qc.useStages(j+1)
                own = (6*issH(j)+1):(6*issH(j+1));
            else
                own = H;
            end
            own = own(own >= H(1) & own <= nT);
            rel = own - H(1) + 1;                            % 在 Qs 行里的相对位置
            q07o = q07(rel);  q09o = q09(rel);  Aown = R.A(k,own)';  Gown = R.G(k,own)';

            aRef = max(min(max(Gown, q07o), q09o), 0);       % 调整量闭式
            maxGapA = max(maxGapA, max(abs(aRef - Aown)));
            cntAdjSlot = cntAdjSlot + numel(own);
            loAgLo = min(loAgLo, min(Aown - q07o));
            loAgHi = min(loAgHi, min(q09o - Aown));
            % 剪枝标志应恰好对应「触界」的槽（本阶段自己的记录）
            nClipTrue  = nClipTrue  + sum(q07o > Gown + 1e-9);
            nClipFalse = nClipFalse + sum(R.clipHi(k,own)');
        end
    end
end

okD1 = maxGapG < 1e-6;
say('D1 计划量 G_t = max(0, Q_(%.2f))：逐槽最大偏差 %.3e kW   -> %s', ...
    qc.qPlan, maxGapG, pass(okD1));
say('D2 计划阶段一阶条件 #{s : Q_s > G_t}（内点时段应 = nS·(1−qPlan) = %.1f）：', nS*(1-qc.qPlan));
if nIn > 0
    say('     内点时段（%.1f%%）均值 = %.6f   <- 严格取等', 100*nIn/(nIn+nClip), cntAboveIn/nIn);
end
if nClip > 0
    say('     截断时段（%.1f%%，G* = 0）均值 = %.4f   <- 应 ≤ %.1f', ...
        100*nClip/(nIn+nClip), cntAboveClip/nClip, nS*(1-qc.qPlan));
end
okD2 = (nIn == 0 || abs(cntAboveIn/nIn - nS*(1-qc.qPlan)) < 1e-9) && ...
       (nClip == 0 || cntAboveClip/nClip <= nS*(1-qc.qPlan) + 1e-9);
say('     -> %s', pass(okD2));

okD3 = maxGapA < 1e-6;
say('D3 调整量 A_t = min(max(G_t, Q_(%.2f)), Q_(%.2f))：逐槽最大偏差 %.3e kW   -> %s', ...
    qc.qAdjLo, qc.qAdjHi, maxGapA, pass(okD3));
okD4 = loAgLo > -1e-9 && loAgHi > -1e-9;
say('D4 调整量落位 Q_(%.2f) ≤ A_t ≤ Q_(%.2f)：min(A−Q_lo) = %.3e，min(Q_hi−A) = %.3e   -> %s', ...
    qc.qAdjLo, qc.qAdjHi, loAgLo, loAgHi, pass(okD4));
say('     受检调整槽 %d 个（应为 nd×108 = %d：6:00 之后每个槽只由【最后一个】碰到它的阶段认领）', ...
    cntAdjSlot, nd*108);
say('     其中因计划偏低上修 %d 槽、因计划偏低下修 %d 槽', sum(R.clipHi(:)), sum(R.clipLo(:)));
okD5 = nClipTrue == sum(R.clipHi(:)) && nClipFalse == sum(R.clipHi(:));
say('D5 上修标志与「G < Q_(%.2f)」逐槽一致（%d vs 记录 %d；误置标志 %d 槽）   -> %s', ...
    qc.qAdjLo, nClipTrue, sum(R.clipHi(:)), nClipFalse - sum(R.clipHi(:)), pass(okD5));
say('     说明：计划阶段 G_t 不进入 SOC 递推，给定充放电时最优 G 是一段区间而非单点，');
say('           故「先解 LP 得充放电、再按报童分位定购电量」是【精确两步法】而非近似');

%% ================= 基准对照 =================
say('');
say('---- 基准对照（逐档加信息 / 加机制）----');
% E. 完美信息基准：净负荷完全已知，Rs = 0
cOr = zeros(nd,1); qOr = zeros(nd,1); flOr = zeros(nd,1);
for k = 1:nd
    d = R.dayIdx(k);
    [cOr(k), qOr(k), flOr(k)] = oracleDay(F.Nact(d,:)', pr(1,:)', qc);
end
say('    （完美信息基准 %d 天全部求得最优，flag 非 1 天数 = %d）', nd, sum(flOr ~= 1));

% F. 无储能基准
gBase = max(0, F.Nact(R.dayIdx,:));
cBase = sum(sum(pr .* gBase))*dt;
qBase = sum(sum(gBase))*dt;

cNoAdj  = sum(R.costNoAdj);
cAdjOnly= sum(R.costAdjOnly);
cOurs   = sum(R.Sadj);
say('');
say('E  完美信息基准（含储能，费用下界）  购电 %12.1f kWh | 费用 %14.2f 元', sum(qOr), sum(cOr));
say('F  无储能基准                        购电 %12.1f kWh | 费用 %14.2f 元', qBase, cBase);
say('G  只定计划、永不调整                购电 %12.1f kWh | 费用 %14.2f 元', ...
    R.summary.qPlanTot, cNoAdj);
say('H  本模型（四阶段滚动调整）          购电 %12.1f kWh | 费用 %14.2f 元', ...
    R.summary.qAdjTot + R.summary.qEmTot, cOurs);
say('');
say('    ★ 调整机制的价值（G ↓ H）        ： %12.2f 元（降幅 %.3f%%）', ...
    cNoAdj - cOurs, (cNoAdj-cOurs)/cNoAdj*100);
say('        └ 只调整购电量（留用 0:00 充放电）： %12.2f 元（%.3f%%）', ...
    cNoAdj - cAdjOnly, (cNoAdj-cAdjOnly)/cNoAdj*100);
say('        └ 重排充放电（新信息再优化）    ： %12.2f 元（%.3f%%）', ...
    cAdjOnly - cOurs, (cAdjOnly-cOurs)/cNoAdj*100);
say('      储能的价值（F ↓ H）            ： %12.2f 元（降幅 %.2f%%）', ...
    cBase - cOurs, (cBase-cOurs)/cBase*100);
say('      预测误差的代价（E ↑ H）        ： %12.2f 元（升幅 %.2f%%）', ...
    cOurs - sum(cOr), (cOurs-sum(cOr))/sum(cOr)*100);
say('      紧急购电费占比                 ： %.2f%%（发生紧急购电 %d 天 / %d 天）', ...
    R.summary.costEmTot/cOurs*100, R.summary.nDayEm, nd);

% 落盘基准（供 q3_visualization 复用）
bench = struct('cOr', cOr, 'qOr', qOr, 'cBase', cBase, 'qBase', qBase, ...
               'cNoAdj', cNoAdj, 'cAdjOnly', cAdjOnly, 'cOurs', cOurs, ...
               'saveAdj', cNoAdj - cOurs, 'saveAdjOnly', cNoAdj - cAdjOnly, ...
               'saveResched', cAdjOnly - cOurs, 'saveStorage', cBase - cOurs, ...
               'costForecast', cOurs - sum(cOr), 'price', pr, 'dt', dt);
if ~isfolder(outdir), mkdir(outdir); end
save([outdir tag 'q3_bench.mat'], 'bench');

%% ================= 汇总 =================
okA = okA1&&okA2&&okA3&&okA4&&okA5&&okA6;
okB = okB1&&okB2&&okB3&&okB4a&&okB5;
okC = okC && okC4 && okC5;
okD = okD1&&okD2&&okD3&&okD4&&okD5;
allok = okA && okB && okC && okD;
say('');
say('==========================================================');
say(' 结论：A 结构不变量 %s | B 守恒律 %s | C 费用复算 %s | D 模型论断 %s', ...
    pass(okA), pass(okB), pass(okC), pass(okD));
say(' 总判定：%s', pass(allok));
say('==========================================================');

ok = allok;

% 落盘（UTF-8）
txt = strjoin(lines, sprintf('\n'));
if ~isfolder(outdir), mkdir(outdir); end
fid = fopen([outdir tag 'q3_validate_report.txt'], 'w', 'n', 'UTF-8');
fprintf(fid, '%s\n', txt);
fclose(fid);
fprintf('\n%s\n', txt);
end

% ======================================================================
function Rs = residPool(F, pool, cols, j, nS)
% 与 q3_solve 的 residualMat 完全相同的取样规则（近 nS 天的该发布时刻残差）
Rm = F.Nact(pool, cols) - F.Nhat4(pool, cols, j);
np_ = size(Rm,1);
if np_ >= nS
    Rs = Rm(end-nS+1:end, :)';
else
    Rs = repmat(Rm', 1, ceil(nS/np_));
    Rs = Rs(:, 1:nS);
end
end

function [cOpt, qOpt, flag] = oracleDay(Nact, prc, qc)
% 完美信息基准：净负荷完全已知（残差恒为 0），一次性解全天 LP
% 残差为零 ⇒ Q 退化为确定值 ⇒ 报童计划量 G = max(0, Q)，紧急购电量恒为 0，
% 故目标值只含 Σp·dt·max(0, Q) 一项，即该日费用的理论下界。
nT  = numel(Nact);
out = q3_lp(prc, qc.S0, Nact, zeros(nT,1), qc);
flag = out.flag;
if flag ~= 1
    cOpt = nan;  qOpt = nan;  return;
end
Q = out.Ns + out.c - out.d;
G = max(0, Q);
cOpt = sum(prc .* qc.dt .* G);
qOpt = sum(G) * qc.dt;
end

function s = pass(b)
if b, s = 'PASS'; else, s = 'FAIL'; end
end

% ⚠️ q3_outdir() 已删除：它是一个无参局部函数，内部自调 q3_config()，
%    因而【看不见调用者传入的 qc】，是上面那起"覆盖问题三报告"事故的根源。
%    outdir 现在在函数开头按传入的 qc 直接算（见"载入"段）。
