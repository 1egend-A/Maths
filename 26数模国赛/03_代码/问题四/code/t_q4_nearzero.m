function Tab = t_q4_nearzero(thr)
% T_Q4_NEARZERO  问题四的「近零价套利」归因分析（问题四论文的三大结论之一）
%
% 背景：附件4 的实测电价存在【近零价】报价点（最低 0.0076 元/kWh），峰谷比高达 236 倍；
%       而问题二/三用的附件1 只是【全年均值剖面】，峰谷比仅 3.76 倍，根本不出现近零价。
%       电价结构变了，储能的经济角色也就变了：
%           问题二/三：储能是【风险对冲工具】——用来削平负载/光伏预报误差的冲击；
%           问题四   ：储能是【套利工具】—— 在近零价时段吸电，在高价时段放出。
%       本节把这句定性判断落成四个定量问题。
%
% 四个子分析：
%   N1 近零价的【存在性】：两套电价的峰谷结构对比（分布、时段分布）
%   N2 储能【在哪取电】：充电能量按价格十分位的分布（若为套利，应高度集中在低价位）
%   N3 近零价的【贡献量化】：反事实重定价——把 p < thr 的报价点抬到当日中位数后重解，
%      费用增量即为「近零价本身」创造的节省
%   N4 储能价值在两种电价下的对照：无储能基准（闭式，无需 LP）vs 有储能结果
%
% ★ 本脚本顺带给出一个【引理级】的数值验证：报童分位 g*_t 与电价 p_t 无关。因为紧急
%   电价为 5p_t，一阶条件 #{s : Q^s_t > g_t} = nS/k_em 中 p_t 被约掉。故 N3 的重定价
%   只应改变 LP 对 (c,d) 的取舍，【不应改变 g*】——脚本对此做逐元素断言（N3 的第 1 条）。
%
% 用法：Tab = t_q4_nearzero();         % 默认 thr = 0.10 元/kWh
%       Tab = t_q4_nearzero(0.05);     % 稳健性检查
%
% 落盘：out/t_q4_nearzero.mat、out/t_q4_nearzero.csv

if nargin < 1 || isempty(thr), thr = 0.10; end

ROOT = 'D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\';
D  = load([ROOT '数据预处理代码\out\data.mat']).D;
qc = q4_config();
qc.verbose = false;
nd = numel(qc.dayIdx);
nT = 144;  dt = qc.dt;  nS = qc.nScen;  kEm = qc.kEm;
k80 = max(1, min(nS, ceil(0.8*nS)));

fprintf('===== 问题四：近零价套利归因（阈值 p < %.2f 元/kWh）=====\n', thr);
fprintf('区间 %d 天（%s ~ %s）\n', nd, string(qc.dateFirst), string(qc.dateLast));

pr   = D.actual.price(qc.dayIdx, :);        % nd × 144，附件4 逐日实测
pr1  = D.day144.price(:)';                  % 1 × 144，附件1 典型日剖面

% 预报（优先复用 run_q4_all 的落盘产物，避免重复计算）
fF = [qc.outdir 'q4_forecast.mat'];
if isfile(fF)
    F2 = load(fF, 'F2').F2;
    fprintf('预报来源：%s（复用）\n', fF);
else
    fprintf('预报来源：现场计算（未找到 %s）\n', fF);
    q2c = q2_config();  q2c.verbose = false;
    F2  = q2_forecast(D, q2c);
end

%% ================= N1. 近零价的存在性 =================
fprintf('\n---- N1 近零价的存在性（附件4 vs 附件1）----\n');
pAll = pr(:);  nP = numel(pAll);
pMin = min(pAll);  pMax = max(pAll);
fprintf('  附件4：%d 个报价点，最低 %.4f，最高 %.4f，峰谷比 %.1f 倍\n', ...
    nP, pMin, pMax, pMax/pMin);
bands = [0.05 0.10 0.20 0.50 1.00];
cntB = zeros(numel(bands),1);
for i = 1:numel(bands), cntB(i) = sum(pAll < bands(i)); end
for i = 1:numel(bands)
    fprintf('      p < %.2f 元/kWh：%6d 点（%6.3f%%）\n', bands(i), cntB(i), 100*cntB(i)/nP);
end
fprintf('  附件1：最低 %.4f，最高 %.4f，峰谷比 %.2f 倍，低于 %.2f 的点 %d 个\n', ...
    min(pr1), max(pr1), max(pr1)/min(pr1), thr, sum(pr1 < thr));
dv4 = std(pr(:));  dv1 = std(repmat(pr1, nd, 1), 0, 'all');
fprintf('  全期报价标准差（衡量可用价差空间）：附件4 %.4f vs 附件1 %.4f 元/kWh\n', dv4, dv1);

% 近零价落在哪些钟点（按时段聚合）
lowMask = pr < thr;                          % nd × 144
hourOf  = floor(((1:nT)-1)/6) + 1;           % 1..24
lowByHour = sum(lowMask, 1);
lowHour = zeros(24,1);
for h = 1:24, lowHour(h) = sum(lowByHour(hourOf == h)); end
fprintf('  近零价时段最多的 5 个钟点：\n');
[~, ord] = sort(lowHour, 'descend');
for h = 1:5
    fprintf('      %02d:00-%02d:00  %6d 次（占该钟点全部报价的 %.1f%%）\n', ...
        ord(h)-1, ord(h), lowHour(ord(h)), 100*lowHour(ord(h))/(nd*6));
end

%% ================= N2. 储能充放电在价格十分位上的分布 =================
fprintf('\n---- N2 储能取电的价格结构（充电能量按价格十分位）----\n');
R2 = solveOrLoad(D, F2, qc, pr);
pvQ = pr(:);
edges = quantile(pvQ, 0:0.1:1);
edges(end) = edges(end) + 1e-9;
decId = discretize(pvQ, edges);              % 1..10
cE = (R2.c * dt)';   cE = cE(:);             % nd*144 × 1 充电量 kWh
dE = (R2.d * dt)';   dE = dE(:);
gE = (R2.gPlan * dt)';  gE = gE(:);          % 计划（被执行）购电量 kWh
ecQ = (R2.curt * dt)';  ecQ = ecQ(:);
cByDec = zeros(10,1);  dByDec = zeros(10,1);
gByDec = zeros(10,1);  xByDec = zeros(10,1);  pByDec = zeros(10,1);
for i = 1:10
    m = (decId == i);
    cByDec(i) = sum(cE(m));  dByDec(i) = sum(dE(m));
    gByDec(i) = sum(gE(m));  xByDec(i) = sum(ecQ(m));
    pByDec(i) = mean(pvQ(m));
end
fprintf('  %-6s %-12s %14s %14s %14s %12s\n', '十分位','均价(元/kWh)','充电量(kWh)','放电量(kWh)','购电量(kWh)','弃电(kWh)');
for i = 1:10
    fprintf('  D%-5d %-12.4f %14.1f %14.1f %14.1f %12.1f\n', ...
        i, pByDec(i), cByDec(i), dByDec(i), gByDec(i), xByDec(i));
end
fprintf('  充电能量的价格重心：%.4f 元/kWh（全期成交量加权均价 %.4f 元/kWh）\n', ...
    sum(pByDec.*cByDec)/sum(cByDec), sum(pvQ.*gE)/sum(gE));
fprintf('  -> 充电最低两个十分位占全部充电量的 %.1f%%，最高两个十分位仅 %.1f%%\n', ...
    100*sum(cByDec(1:2))/sum(cByDec), 100*sum(cByDec(9:10))/sum(cByDec));

%% ================= N3. 反事实重定价 =================
fprintf('\n---- N3 反事实重定价：把 p < %.2f 抬到当日中位数 ----\n', thr);
prMod = pr;
nFix = 0;
for k = 1:nd
    pm = median(pr(k,:));
    m  = pr(k,:) < thr;
    prMod(k, m) = pm;
    nFix = nFix + sum(m);
end
fprintf('  被抬高的报价点：%d 个（%.3f%%）\n', nFix, 100*nFix/nP);
Rcf = solveOrLoad(D, F2, qc, prMod, 'cf');

% N3.1 ★ 分位不变性断言（引理验证）
dG = max(abs(R2.gPlan(:) - Rcf.gPlan(:)));
fprintf('  N3.1 分位不变性：|g*_重定价 − g*_原价| 最大 %.3e kW   -> %s\n', ...
    dG, pass(dG < 1e-6));
fprintf('       （理论依据：紧急价 5p_t 使一阶条件 #{s:Q_s>g}=nS/k_em 中 p_t 约掉，');
fprintf('故 g* 与电价无关）\n');

% N3.2 费用增量
cB = R2.summary.costTot;  cM = Rcf.summary.costTot;
fprintf('  N3.2 抬高近零价后的总费用 %16.2f 元（原 %16.2f 元）\n', cM, cB);
fprintf('       增量 %+12.2f 元 = 近零价创造节省的【下界】（%.3f%%）\n', ...
    cM - cB, 100*(cM - cB)/cB);
dC = max(abs(R2.c(:) - Rcf.c(:)));
fprintf('       同时充放电安排改变：|c_重定价 − c_原价| 最大 %.2f kW（平均值 %.2f kW）\n', ...
    dC, mean(abs(R2.c(:) - Rcf.c(:))));
fprintf('       -> 重定价只改变储能的充放取舍，不改变购电计划量，与引理一致\n');

% N3.3 尖峰侧的对称检查：把高价削到当日中位数
prCut = pr;  nCut = 0;
for k = 1:nd
    pm = median(pr(k,:));
    m  = pr(k,:) > 1.00;                 % 1.00 元/kWh 以上视作尖峰
    prCut(k, m) = pm;
    nCut = nCut + sum(m);
end
Rcut = solveOrLoad(D, F2, qc, prCut, 'cut');
fprintf('  N3.3 对称检查：把 p > 1.00 的 %d 个尖峰点削到当日中位数，\n', nCut);
fprintf('       总费用 %16.2f 元（变化 %+12.2f 元，%+.3f%%）\n', ...
    Rcut.summary.costTot, Rcut.summary.costTot - cB, 100*(Rcut.summary.costTot - cB)/cB);
fprintf('       -> 尖峰与深谷两侧共同构成储能套利的价差空间\n');

%% ================= N4. 储能价值：两种电价下对照 =================
fprintf('\n---- N4 储能的价值：附件1 电价 vs 附件4 电价 ----\n');
[cNS1, cNS4] = deal(0, 0);
for k = 1:nd
    d = qc.dayIdx(k);
    pool = (d-nS):(d-1);  pool = pool(pool >= 1);
    if isempty(pool), pool = d; end
    Rm = F2.Nact(pool,:) - F2.Nhat(pool,:);
    if size(Rm,1) >= nS
        Rs = Rm(end-nS+1:end, :)';
    else
        Rs = repmat(Rm', 1, ceil(nS/size(Rm,1)));  Rs = Rs(:, 1:nS);
    end
    Ns = F2.Nhat(d,:)' + Rs;
    cNS1 = cNS1 + costNoStorage(Ns, pr1', qc);
    cNS4 = cNS4 + costNoStorage(Ns, pr(k,:)', qc);
end
fprintf('  %-34s %16s %16s\n', '口径', '总费用(元)', '相对无储能');
fprintf('  %-34s %16.2f %16s\n', '附件1 电价 · 无储能', cNS1, '—');
fprintf('  %-34s %16.2f %15.2f%%\n', '附件4 电价 · 无储能', cNS4, 100*(cNS4-cNS1)/cNS1);
% Q3 的「有储能」总费用从盘上取（不在本脚本里重算，避免与问题三的口径分叉）
fq3 = [ROOT '问题三\out\q3_solution.mat'];
cS1 = NaN;
if isfile(fq3)
    cS1 = load(fq3, 'R').R.summary.costTot;
    fprintf('  %-34s %16.2f %15.2f%%\n', '附件1 电价 · 有储能(问题三结果)', cS1, ...
        100*(cS1-cNS1)/cNS1);
else
    fprintf('  %-34s %16s %16s\n', '附件1 电价 · 有储能', '（未找到问题三结果）', '—');
end
fprintf('  %-34s %16.2f %15.2f%%\n', '附件4 电价 · 有储能(本问保底一)', cB, 100*(cB-cNS4)/cNS4);
if isfinite(cS1)
    fprintf('  储能价值：附件1 电价下 %.2f 元（%.2f%%）；附件4 电价下 %.2f 元（%.2f%%）\n', ...
        cNS1 - cS1, 100*(cNS1-cS1)/cNS1, cNS4 - cB, 100*(cNS4-cB)/cNS4);
else
    fprintf('  储能价值（附件4 电价）：%.2f 元（%.2f%%）\n', cNS4 - cB, 100*(cNS4-cB)/cNS4);
end

%% ================= 汇总 =================
Tab = table(bands(:), cntB, 100*cntB/nP, 'VariableNames', {'阈值','报价点数','占比_pct'});
fprintf('\n  已写出：%s\n', [qc.outdir 't_q4_nearzero.csv']);
writetable(Tab, [qc.outdir 't_q4_nearzero.csv'], 'Encoding', 'UTF-8');
save([qc.outdir 't_q4_nearzero.mat'], 'Tab', 'thr', 'bands', 'cntB', ...
     'pByDec', 'cByDec', 'dByDec', 'gByDec', 'xByDec', 'lowHour', ...
     'pMin', 'pMax', 'nFix', 'cB', 'cM', 'cNS1', 'cNS4', 'dG', 'dC');
fprintf('  已写出：%s\n', [qc.outdir 't_q4_nearzero.mat']);
end

% ======================================================================
function R = solveOrLoad(D, F2, qc, pr, tag)
% 求解（或复用）一套 P2 框架结果。tag 为 [] 时允许从盘上复用 out42 的结果。
if nargin < 5, tag = []; end
fF = [qc.outdir42 'q4_solution_p2.mat'];
base = isempty(tag) && isequal(size(pr), [numel(qc.dayIdx) 144]);
if base && isfile(fF)
    R = load(fF, 'R2').R2;
    if isequal(R.price, pr)
        fprintf('  （复用 %s）\n', fF);
        return;
    end
end
R = q4_solve_p2(D, F2, qc, qc.dayIdx, pr);
end

% ======================================================================
function cTot = costNoStorage(Ns, prc, qc)
% 无储能基准的【闭式】费用：c = d = 0 时，目标对 g 可分，逐时段取报童临界分位
%   Q^s_t = Nhat_t + 残差_s（即 Ns 本⾝），g*_t = max(0, Q_(0.8))
%   cost = Σ p_t·g*_t·dt + Σ 5p_t·dt·mean_s(max(0, Q^s_t − g*_t))
% 无需 LP：这正是「两阶段精确性」的推论——g 不进入 SOC 递推，故 g 可解析定出。
nS = qc.nScen;  k80 = max(1, min(nS, ceil(0.8*nS)));
Qs = sort(Ns, 2);
gg = max(0, Qs(:, k80));
cTot = sum(prc .* gg) * qc.dt + sum(qc.kEm * prc .* mean(max(0, Ns - gg), 2)) * qc.dt;
end

% ======================================================================
function s = pass(b)
if b, s = 'PASS'; else, s = 'FAIL'; end
end
