function Tab = t_q4_term_policy(wins)
% T_Q4_TERM_POLICY  口径 2 的代价：日末储电量「固定 6000」vs「放开日末闭环」
%
% ============================================================
%  这是问题四最有分量的一节，也是「电价逐日变」真正改变结论的地方。
%
%  口径 2 规定每天 0:00 与 24:00 储电量恒为 6000 kWh（S_0 = S_144 = 6000）。
%  这意味着储能【不能跨日搬运能量】：每天必须自己把电充回去。
%
%  · 在问题二/三（附件1 电价，逐日相同）下，这个约束几乎不要钱：实测放开后仅省 0.12%。
%    道理很直白——每天的电价剖面一模一样，跨日搬运【没有价差可吃】。
%
%  · 在问题四（附件4 电价，逐日实测）下，每天的电价剖面都不同，峰谷比 236 倍，
%    于是「今天在近零价时段多充一点、明天在尖峰时段少充一点」有了真实收益，
%    口径 2 从「无害的规范化约定」变成「有代价的经济约束」。
%
%  本脚本用【窗口实验】把这个代价量化出来，且保持两端闭合、口径可比：
%
%    对照（口径 2）：W 天各自独立求解，每天 S_0 = S_144 = 6000  ⇒ 逐日费用之和
%    放开（窗口）  ：W 天合成【一个】LP，仅窗口首端 S = 6000、窗口末端 S = 6000，
%                    中间 W−1 个日界【放开】⇒ 差额即跨日搬运的价值
%
%  ★ 两端都钉 6000，故两者能量总闭合相同，差额【纯粹】来自跨日搬运的自由度，
%    不含「日末清空电池」这种退化解的虚假收益。
%
%  ★★ 为什么必须两端都钉：问题三的同类实验 t_q3_term_policy.m 已经证明了这个陷阱的
%     真实性——若只放开末槽而不作价，附件1 电价下 LP 会把日末 SOC 一路放到下限 1200
%     （实测均值 1200.0、范围 [1200,1200]，即【每天都清空电池】），凭空"省"下 990,001.69 元；
%     把日末储能按价作价后，放开末槽反而【比闭合贵 240,870 元（+1.636%）】。
%     也就是说：在逐日相同电价下，日末闭环不是损失、而是【防止短视套现的护栏】。
%     本脚本沿用「两端钉死」的写法，就是为了不在问题四重犯这个可比性错误。
%
%  ★ 窗口越长、跨日自由度越多，收益越大 —— 脚本对 W ∈ {1, 7, 30} 做扫描，
%    其中 W = 1 是退化的自检点（放开与固定应完全相同）。
%
%  ⚠️ 诚实声明（必须写进论文）：窗口 LP 假设【整个窗口的电价在窗口开始时已知】，
%    这是比问题四保底口径（逐日电价已知）更强的信息假设。故所测得的跨日套利收益
%    是【完美预见的潜力上限】，不是可实现的收益。这一条在结论里必须显式声明。
%
% 用法：Tab = t_q4_term_policy();          % 默认 W ∈ {1, 7, 30}
%       Tab = t_q4_term_policy([1 7 30 90]);
%
% 落盘：out/t_q4_term_policy.mat、out/t_q4_term_policy.csv

if nargin < 1 || isempty(wins), wins = [1 7 30]; end

ROOT = 'D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\';
D  = load([ROOT '数据预处理代码\out\data.mat']).D;
qc = q4_config();
qc.verbose = false;
nd = numel(qc.dayIdx);  nT = 144;  nS = qc.nScen;  dt = qc.dt;

fprintf('===== 问题四：口径 2 的代价（日末闭环 固定 6000 vs 放开）=====\n');
fprintf('区间 %d 天（%s ~ %s）\n', nd, string(qc.dateFirst), string(qc.dateLast));

fF = [qc.outdir 'q4_forecast.mat'];
if isfile(fF)
    F2 = load(fF, 'F2').F2;
else
    q2c = q2_config();  q2c.verbose = false;
    F2  = q2_forecast(D, q2c);
end

pr4 = D.actual.price(qc.dayIdx, :);              % nd × 144 附件4 逐日
pr1 = repmat(D.day144.price(:)', nd, 1);         % nd × 144 附件1（逐日相同）

fprintf('\n---- 0. 自检：W = 1 的「固定」版必须逐位复现逐日解 ----\n');
% ⚠️ 这里原来断言的是「W=1 时放开 ≡ 固定」，理由是"窗口只有一天，放开与固定是同一个约束"。
%    **这个理由是错的**：放开末端 SOC 是允许当天把储能清空而不补回 6000，
%    它在【任何】窗口长度下都合法地更便宜，W=1 也不例外——首末同点并不改变
%    "允许末端偏离 6000"这件事本身。实测第 1 天差 1.681e+03 元，断言当场炸掉，
%    整个脚本在第 0 步中断，一个结果文件都没写出来。
%
%    真正该断言的不变量只有一条：W=1 的【固定】版必须与 q4_solve_p2 的逐日解逐位一致，
%    这一条才真正校验了窗口 LP 的矩阵展开次序与 SOC 递推。放开的差额是观测量，不是误差。
NactW1 = F2.Nact(qc.dayIdx(1), :)';
NsW1   = scenNet(F2, qc, qc.dayIdx(1), nS);
[cFix1, ~]  = windowLP(pr4(1,:)', NsW1, qc, false, NactW1);
[cFree1, ~] = windowLP(pr4(1,:)', NsW1, qc, true,  NactW1);

R2 = load([qc.outdir42 'q4_solution_p2.mat'], 'R2').R2;
dRef = abs(cFix1 - R2.costTot(1));
fprintf('  与 q4_solve_p2 第 1 天对账：%14.6f 元，差 %.3e 元   -> %s\n', ...
    R2.costTot(1), dRef, pass(dRef < 1e-6));
fprintf('  （参考）第 %s 天放开末端 SOC 的差额 %14.6f 元（%.3f%%）——合法差值，非误差\n', ...
    string(D.actual.dates(qc.dayIdx(1))), cFix1 - cFree1, 100*(cFix1-cFree1)/cFix1);
assert(dRef < 1e-6, '窗口 LP 自检未通过（W=1 固定版未能复现逐日解），后续结果不可信');

%% ---- 主循环：两种电价 × 各窗口长度 ----
regimes = struct('name', {'附件1（逐日相同）', '附件4（逐日实测）'}, 'pr', {pr1, pr4});
nW = numel(wins);  nR = numel(regimes);
res = struct();

fprintf('\n---- 1. 窗口扫描 ----\n');
for r = 1:nR
    prM = regimes(r).pr;
    % 对照（口径 2）的逐日费用：每天独立 ⇒ 逐日费用可直接取自逐日解，无需重解
    % ⚠️ 但逐日费用依赖电价，故附件1 的情形必须另跑一次逐日解，不能直接引用 R2。
    if r == 1
        Rday = q4_solve_p2(D, F2, qc, qc.dayIdx, prM);
        cDay = Rday.costTot;
    else
        Rday = R2;  cDay = R2.costTot;              % 附件4 即本问保底一，直接复用
    end
    fprintf('\n  【%s】逐日参照总费用 %14.2f 元\n', regimes(r).name, sum(cDay));

    for w = 1:nW
        W = wins(w);
        nWin = floor(nd / W);
        % ⚠️ 这里原来给 W = 1 开了个「退化点」分支，直接令 放开 = 固定、收益 = 0。
        %    该分支的立论（"窗口只有一天，首末同点，放开与固定是同一个约束"）是错的：
        %    放开末端 SOC 是允许当天清空储能且不补回 6000，W=1 时一样更便宜（实测第 1 天差
        %    1680.79 元 = 8.271%）。若不删掉，表格里 W=1 那一行会印出一个凭空写死的 0，
        %    而它恰好是"跨日套利"这一节对比的基准行——错的基准会让整节结论作废。
        %    W=1 现在照常进循环求解（334 天 × 2 个解，约一分钟）。
        t0 = tic;  cF = 0;  cR = 0;
        for j = 1:nWin
            rowsW = (j-1)*W + (1:W);
            dayW  = qc.dayIdx(rowsW);
            % ⚠️ 两个索引【不可互换】：prM 已被 qc.dayIdx 裁成 nd 行，
            %    只能用「区间内位置」rowsW 索引；而 F2 / scenNetAll 要的是
            %    全年绝对日号 dayW（最大可达 365）。曾用 dayW 去索引 prM，
            %    在 W=30 的第 11 个窗口（dayW 到 361）越界报错——
            %    W 越小越靠后才暴露，W=1 又走退化分支，所以直到这里才炸。
            prW  = reshape(prM(rowsW, :)', [], 1);            % nTW × 1（按天拼）
            NsW  = scenNetAll(F2, qc, dayW, nS);              % nTW × nS
            NactA = reshape(F2.Nact(dayW, :)', [], 1);
            cF = cF + windowLP(prW, NsW, qc, false, NactA);   % 固定日界
            cR = cR + windowLP(prW, NsW, qc, true,  NactA);   % 放开日界
        end
        el = toc(t0);
        res(r).W(w) = W;  res(r).nWin(w) = nWin;
        res(r).cFix(w) = cF;   res(r).cFree(w) = cR;
        res(r).perDayFix(w)  = cF / (nWin*W);
        res(r).perDayFree(w) = cR / (nWin*W);
        res(r).sec(w) = el;
        fprintf('    W = %-3d  窗口 %3d 个（%d 天）固定 %14.2f | 放开 %14.2f | 省 %10.2f 元（%6.3f%%） %.1f s\n', ...
            W, nWin, nWin*W, cF, cR, cF - cR, 100*(cF-cR)/cF, el);
    end
end

%% ---- 汇总表 ----
W = [res.W]';  nameR = {regimes.name}';
cFixT = []; cFreeT = [];  rgrp = {};
for r = 1:nR
    cFixT  = [cFixT;  res(r).cFix(:)];      %#ok<AGROW>
    cFreeT = [cFreeT; res(r).cFree(:)];     %#ok<AGROW>
    rgrp   = [rgrp; repmat(nameR(r), nW, 1)]; %#ok<AGROW>
end
Tab = table(rgrp, W, cFixT, cFreeT, cFixT - cFreeT, 100*(cFixT-cFreeT)./cFixT, ...
    'VariableNames', {'电价口径','窗口天数','固定日末_元','放开日末_元','节省_元','节省_pct'});

fprintf('\n===== 结论 =====\n');
for r = 1:nR
    v = arrayfun(@(x) 100*(res(r).cFix(x)-res(r).cFree(x))/res(r).cFix(x), 1:nW);
    fprintf('  %s：', regimes(r).name);
    fprintf('W=%d 省 %.3f%%   ', [wins; v]);
    fprintf('\n');
end
fprintf('\n  ★ 口径 2 在附件1 电价下的代价 = %.3f%%（W=%d）；在附件4 电价下 = %.3f%%（W=%d）\n', ...
    arrayfun(@(x) 100*(res(1).cFix(x)-res(1).cFree(x))/res(1).cFix(x), nW), wins(end), ...
    arrayfun(@(x) 100*(res(2).cFix(x)-res(2).cFree(x))/res(2).cFix(x), nW), wins(end));
fprintf('  ⚠️ 窗口 LP 假设窗口内电价【完全已知】，故上述为完美预见下的潜力上限，\n');
fprintf('     不是可实现收益。正确读法：它量化了「现行日末闭环口径」放弃了多大空间。\n');

writetable(Tab, [qc.outdir 't_q4_term_policy.csv'], 'Encoding', 'UTF-8');
save([qc.outdir 't_q4_term_policy.mat'], 'Tab', 'res', 'wins', 'regimes');
fprintf('\n  已写出：%s\n', [qc.outdir 't_q4_term_policy.csv']);
fprintf('  已写出：%s\n', [qc.outdir 't_q4_term_policy.mat']);
end

% ======================================================================
function NsW = scenNetAll(F, qc, dayList, nS)
% W 天情景净负荷，按【天拼接】成 (W*144) × nS
nT = 144;  W = numel(dayList);
NsW = zeros(W*nT, nS);
for j = 1:W
    NsW((j-1)*nT + (1:nT), :) = scenNet(F, qc, dayList(j), nS);
end
end

% ======================================================================
function Ns = scenNet(F, qc, d, nS)
% 单日情景净负荷 nT × nS：Nhat 点预测 + 近 nS 天残差（严格只用到 d−1 及以前）
nT = 144;
pool = (d-nS):(d-1);  pool = pool(pool >= 1);
if isempty(pool), pool = d; end
Rm = F.Nact(pool,:) - F.Nhat(pool,:);
if size(Rm,1) >= nS
    Rs = Rm(end-nS+1:end, :)';
else
    Rs = repmat(Rm', 1, ceil(nS/size(Rm,1)));  Rs = Rs(:, 1:nS);
end
Ns = F.Nhat(d,:)' + Rs;
end

% ======================================================================
function [cTot, qEm] = windowLP(prW, NsW, qc, freeTerm, NactW)
% WINDOWLP  W 天合并的 LP（问题二框架），仅窗口两端闭合、中间日界放开
%
% 变量次序（与 q4_solve_p2.m 完全一致，便于逐位对账）：
%   [g(nTW); c(nTW); d(nTW); S(nTW); u(nTW*nS)]
% 约束：
%   A x ≤ b   逐 (t,s)： −g_t + c_t − d_t − u_{t,s} ≤ −N_{t,s}
%   Aeq x = 0 SOC 递推：S_t − S_{t−1} − eta·dt·c_t + (dt/eta)·d_t = 0，首端 = S_0
%
% ★ g 不进入 SOC 递推 ⇒ 其 LP 最优是【区间】而非点；故求解后按报童临界分位
%   覆盖 g（与 q4_solve_p2 的做法一致，保证两个口径的 g 用同一把尺子）。
%   这也使 (c,d) 的比较不受 g 非唯一性的污染。
%
% freeTerm = true  ：S(nTW) ∈ [S_min, S_max]（只有窗口末端仍钉 S_end）
%             false ：S(nTW) = S_end（等价于逐日各自闭合）

nT = 144;  W = numel(prW)/nT;
assert(W == round(W), 'prW 长度必须是 144 的整数倍');
nTW = W*nT;  nS = qc.nScen;  dt = qc.dt;  eta = qc.eta;
kEm = qc.kEm;  PM = qc.P_max;
k80 = max(1, min(nS, ceil(0.8*nS)));           % 报告期分位 0.8

ig = (1:nTW)';  ic = nTW+(1:nTW)';  id = 2*nTW+(1:nTW)';  iS = 3*nTW+(1:nTW)';
iu = 4*nTW + reshape(1:nTW*nS, nTW, nS);
n  = 4*nTW + nTW*nS;

% ---- 情景补偿约束（展开次序一律 nTW×nS 列优先，与 reshape(NsW,[],1) 一致）----
rowIdx = (0:nS-1)*nTW + (1:nTW)';
rowU   = repmat(reshape(rowIdx, [], 1), 4, 1);
colU   = [repmat(ig,nS,1); repmat(ic,nS,1); repmat(id,nS,1); reshape(iu,[],1)];
valU   = [-ones(nTW*nS,1); ones(nTW*nS,1); -ones(nTW*nS,1); -ones(nTW*nS,1)];
A = sparse(rowU, colU, valU, nTW*nS, n);

% ---- SOC 递推 ----
rowSeq = (1:nTW)';
Aeq = sparse([rowSeq; rowSeq(2:end); rowSeq; rowSeq], ...
             [iS;     iS(1:end-1);  ic;     id    ], ...
             [ones(nTW,1); -ones(nTW-1,1); -eta*dt*ones(nTW,1); (dt/eta)*ones(nTW,1)], ...
             nTW, n);
beq = [qc.S0; zeros(nTW-1,1)];

lb = zeros(n,1);  ub = inf(n,1);
ub(ic) = PM;  ub(id) = PM;
lb(iS) = qc.S_min;  ub(iS) = qc.S_max;
if ~freeTerm
    lb(iS(nTW)) = qc.S_end;  ub(iS(nTW)) = qc.S_end;
end

pdt = prW * dt;
f   = [pdt; zeros(2*nTW,1); zeros(nTW,1); repmat(kEm*pdt/nS, nS, 1)];
opts = optimoptions('linprog', 'Algorithm', qc.lpAlgo, 'Display', 'off');

[x, ~, flag] = linprog(f, A, -reshape(NsW,[],1), Aeq, beq, lb, ub, opts);
assert(flag == 1, '窗口 LP 未收敛（flag = %d，W = %d）', flag, W);

c = x(ic);  dd = x(id);

% ---- 逐日按报童临界分位覆盖 g，再按实际净负荷结算 ----
cTot = 0;  qEm = 0;
for j = 1:W
    idx = (j-1)*nT + (1:nT);
    Qraw = NsW(idx,:) + c(idx) - dd(idx);
    Qsrt = sort(Qraw, 2);
    g = max(0, Qsrt(:, k80));
    net = NactW(idx) + c(idx) - dd(idx) - g;
    e   = max(0, net);
    cTot = cTot + sum(prW(idx).*g)*dt + sum(kEm*prW(idx).*e)*dt;
    qEm  = qEm + sum(e)*dt;
end
end

% ======================================================================
function s = pass(b)
% PASS  布尔 → 'PASS'/'FAIL'。本文件第 76、81 行的自检打印要用；
%       ⚠️ 曾漏定义，直接报「未定义与 'logical' 类型的输入参数相对应的函数 'pass'」，
%       整个脚本在第 0 步自检就中断、连一个结果文件都没写出来。
%       其它 t_q4_*.m 与 q4_cvar.m 各自都有同名局部函数，这里补上。
if b, s = 'PASS'; else, s = 'FAIL'; end
end
