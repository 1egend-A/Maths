function ok = q2_validate(D, F, qc, R)
% Q2_VALIDATE  问题二求解结果的独立校验 + 基准对照
%
% 校验分四层：
%   A 结构不变量：SOC 递推、上下限、日末闭环、充放功率上限、无同时充放
%   B 守恒律（按当天【实际】净负荷）：g + g^em + PV + d = L + c + e，e >= 0
%   C 费用复算：计划费 = Σ p*g*dt，紧急费 = Σ 5p*g^em*dt
%   D 模型论断验证：报童临界分位 0.8、最优计划量的「平台」结构
% 基准对照：
%   · 完美信息基准 q2_oracle（费用下界）→ 量化「预测误差的代价」
%   · 无储能基准                        → 量化「储能的价值」
%
% 用法：
%   ok = q2_validate()                    % 自动读取 out/q2_solution.mat
%   ok = q2_validate(D, F, qc, R)         % 复用已算好的对象
%
% 注：本文件用【嵌套函数】而非局部函数来实现日志收集——MATLAB 的局部函数
%     有自己的工作区，对 lines 的写入不会传回调用者（会静默丢掉全部日志）。

% ---------------- 载入 ----------------
matFile = fullfile(q2_outdir(), 'q2_solution.mat');
if nargin < 4 || isempty(R) || nargin < 3 || isempty(qc)
    assert(isfile(matFile), '未找到 %s，请先运行 q2_solve', matFile);
    S = load(matFile);
    if nargin < 4 || isempty(R),  R  = S.R;  end
    if nargin < 3 || isempty(qc), qc = S.qc; end
end
if nargin < 1 || isempty(D) || nargin < 2 || isempty(F)
    assert(~isempty(which('q2_forecast')), '函数路径未设置');
    D = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码\out\data.mat').D;
    F = q2_forecast(D, qc);
end

TOL  = 1e-6;
lines = {};

    function say(varargin)
        lines{end+1} = sprintf(varargin{:});
    end

say('==========================================================');
say(' 问题二求解结果校验报告');
say('==========================================================');
say('区间 %s ~ %s，共 %d 天', string(R.date(1)), string(R.date(end)), numel(R.date));
say('电价 = 附件1 逐日相同；信息集 = 附件1 + 附件2（口径 7 严格字面）');
say('');

nT = size(R.gPlan,2);  dt = qc.dt; eta = qc.eta;
nd = numel(R.dayIdx);
pr = D.day144.price(:)';

%% ---------------- A. 结构不变量 ----------------
say('---- A. 结构不变量 ----');
% A1 SOC 递推：S_t = S_{t-1} + (eta*c_t - d_t/eta)*dt
Srec = zeros(nd, nT);
Sprev = qc.S0 * ones(nd,1);
for t = 1:nT
    Sprev = Sprev + (eta*R.c(:,t) - R.d(:,t)/eta)*dt;
    Srec(:,t) = Sprev;
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
mx = max([max(R.c(:)), max(R.d(:))]);
okA4 = mx <= qc.P_max + TOL;
say('A4 充放功率 max = %.4f kW，上限 %g kW  -> %s', mx, qc.P_max, pass(okA4));

% A5 无同时充放
nBoth = sum(sum(R.c > 1e-6 & R.d > 1e-6));
okA5 = nBoth == 0;
say('A5 同时充放时段数 = %d  -> %s', nBoth, pass(okA5));

% A6 计划购电量非负
okA6 = min(R.gPlan(:)) >= -TOL;
say('A6 计划购电量最小 = %.4f kW  -> %s', min(R.gPlan(:)), pass(okA6));

%% ---------------- B. 守恒律（实际净负荷）----------------
say('');
say('---- B. 守恒律（按当天实际负载/光伏）----');
% g + g^em + PV + d = L + c + e  ⇔  e = g + g^em + d - (L-PV) - c
ee = R.gPlan + R.gEm + R.d - R.Nact - R.c;
eB1 = max(abs(ee(:) - R.curt(:)));
okB1 = eB1 < 1e-6;
say('B1 弃电量与解算值一致 max = %.3e   -> %s', eB1, pass(okB1));
okB2 = min(ee(:)) >= -TOL;
say('B2 弃电量非负 min = %.6f   -> %s', min(ee(:)), pass(okB2));
% 负载不被欠供
short = sum(sum(R.gPlan + R.gEm + R.d + D.actual.pv(R.dayIdx,:) < ...
                D.actual.load(R.dayIdx,:) - TOL));
okB3 = short == 0;
say('B3 供能低于负载的时段数 = %d   -> %s', short, pass(okB3));

%% ---------------- C. 费用复算 ----------------
say('');
say('---- C. 费用复算 ----');
cPlan = sum(sum(pr .* R.gPlan))*dt;
cEm   = sum(sum(5*pr .* R.gEm))*dt;
eC1 = abs(cPlan - R.summary.costPlanTot);
eC2 = abs(cEm   - R.summary.costEmTot);
okC = eC1 < 1e-4 && eC2 < 1e-4;
say('C1 计划购电费复算差 = %.3e 元   -> %s', eC1, pass(okC));
say('C2 紧急购电费复算差 = %.3e 元   -> %s', eC2, pass(okC));

%% ---------------- D. 模型论断验证 ----------------
say('');
say('---- D. 模型论断验证（报童临界分位与最优平台）----');
nS = qc.nScen;  k80 = ceil(0.8*nS);
gap = zeros(nd,1); plateW = zeros(nd,1); flatIn = zeros(nd,1); riseOut = zeros(nd,1);
cntIn = 0; nIn = 0; cntClip = 0; nClip = 0; wIn = [];
for k = 1:nd
    d = R.dayIdx(k);
    Rs = scenResid(F, d, nS, nT);
    Ns = F.Nhat(d,:)' + Rs;
    Q  = Ns + R.c(k,:)' - R.d(k,:)';
    Qs = sort(Q,2);
    gap(k) = mean(abs(R.gPlan(k,:)' - max(0, Qs(:,k80))));
    % 一阶条件 #{s : Q_s > g_t}：内点解应恰好 = nS/5；边界解（z_(k80)<0 ⇒ g*=0）应 <= nS/5
    g0 = R.gPlan(k,:)';
    cntNow = sum(Q > g0 + 1e-9, 2);
    isIn = Qs(:,k80) > 0;                     % 未触发 g>=0 截断的时段
    cntIn  = cntIn  + sum(cntNow(isIn));   nIn    = nIn    + sum(isIn);
    cntClip= cntClip+ sum(cntNow(~isIn));  nClip  = nClip  + sum(~isIn);
    wIn = [wIn; Qs(isIn,k80+1) - Qs(isIn,k80)];
    % 可行域（g>=0）内的最优平台 = [max(0,z_(k80)), max(0,z_(k80+1)))
    gLo = max(0, Qs(:,k80));
    gHi = max(0, Qs(:,k80+1));
    plateW(k) = mean(gHi - gLo);
    gIn  = (gLo + gHi)/2;                  % 平台中点（两端点费用应完全相同）
    gOut = max(0, Qs(:,k80) - 200);        % 平台外：低 200 kW
    E    = @(gg) sum(pr'.*gg)*dt + sum(5*pr'.*mean(max(0, Q - gg),2))*dt;
    flatIn(k)  = E(gIn)  - E(gLo);
    riseOut(k) = E(gOut) - E(gLo);
end
cntIn = cntIn/nIn;  cntClip = cntClip/nClip;
okD1 = max(gap) < 1e-6;
say('D1 计划购电量 vs max(0, z_(%d))：最大偏差 %.3e kW   -> %s', k80, max(gap), pass(okD1));
say('D2 一阶条件 #{s : Q_s > g_t}（应 = nS/5 = %.1f）：', nS/5);
say('     内点解时段（%.1f%%）均值 = %.6f   <- 严格取等', ...
    100*nIn/(nIn+nClip), cntIn);
say('     边界解时段（%.1f%%，z_(%d)<0 ⇒ g*=0）均值 = %.4f   <- 应 <= %.1f', ...
    100*nClip/(nIn+nClip), k80, cntClip, nS/5);
say('D3 可行域内最优平台宽度均值 = %.2f kW（全体）/ %.2f kW（内点时段）', ...
    mean(plateW), mean(wIn));
say('D4 平台【内部】全天期望费用差均值 = %.6e 元（应 = 0 ⇒ 最优不唯一）', mean(flatIn));
say('D5 平台【外部】少购 200 kW 的全天期望费用增加均值 = %.2f 元', mean(riseOut));
okD = abs(cntIn - nS/5) < 1e-9 && cntClip <= nS/5 + 1e-9 && ...
      mean(riseOut) > 0 && mean(flatIn) < 1e-6 && max(gap) < 1e-6;
say('    -> %s', pass(okD));
say('    说明：g_t 不进入 SOC 约束，故给定 (c,d) 时目标在平台内恒为常数，');
say('          最优计划量是一段区间而非单点；本模型按报童规则取平台左端 max(0,z_(%d)) = Q_0.8。', k80);

%% ---------------- 基准对照 ----------------
say('');
say('---- 基准对照 ----');
% E. 完美信息基准（费用下界）
cOr = zeros(nd,1); qOr = zeros(nd,1); flOr = zeros(nd,1);
for k = 1:nd
    d = R.dayIdx(k);
    [cOr(k), qOr(k), ~, flOr(k)] = q2_oracle(D.day144.price, D.actual.load(d,:), ...
                                 D.actual.pv(d,:), qc.S0, qc.S_end, qc);
end
say('    （完美信息基准 %d 天全部求得最优，flag 非 1 天数 = %d）', nd, sum(flOr ~= 1));
% F. 无储能基准
gBase = max(0, R.Nact);
cBase = sum(sum(pr .* gBase))*dt;
qBase = sum(sum(gBase))*dt;

cOurs = R.summary.costTot;
say('E  完美信息基准（费用下界） 购电 %12.1f kWh | 费用 %14.2f 元', sum(qOr), sum(cOr));
say('F  无储能基准               购电 %12.1f kWh | 费用 %14.2f 元', qBase, cBase);
say('G  本模型（日前计划+紧急购电）购电 %12.1f kWh | 费用 %14.2f 元（期望 %.2f）', ...
    R.summary.qPlanTot + R.summary.qEmTot, cOurs, R.summary.costExpTot);
say('');
say('    储能的价值（无储能 ↓ 本模型）    ： %12.2f 元（降幅 %.2f%%）', ...
    cBase - cOurs, (cBase-cOurs)/cBase*100);
say('    预测误差的代价（完美信息 ↑ 本模型）： %12.2f 元（升幅 %.2f%%）', ...
    cOurs - sum(cOr), (cOurs-sum(cOr))/sum(cOr)*100);
say('    紧急购电费占本模型总费用          ： %.2f%%', R.summary.costEmTot/cOurs*100);

% 落盘基准（供 q2_visualization 复用，免去重算 oracle 的 10 s）
bench = struct('cOr', cOr, 'qOr', qOr, 'cBase', cBase, 'qBase', qBase, ...
               'cOurs', cOurs, 'saveCost', cBase - cOurs, ...
               'forecastCost', cOurs - sum(cOr), 'price', pr, 'dt', dt);
if ~isfolder(qc.outdir), mkdir(qc.outdir); end
save([qc.outdir 'q2_bench.mat'], 'bench');

%% ---------------- 汇总 ----------------
okA = okA1&&okA2&&okA3&&okA4&&okA5&&okA6;
okB = okB1&&okB2&&okB3;
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
if ~isfolder(qc.outdir), mkdir(qc.outdir); end
fid = fopen([qc.outdir 'q2_validate_report.txt'], 'w', 'n', 'UTF-8');
fprintf(fid, '%s\n', txt);
fclose(fid);
fprintf('\n%s\n', txt);
end

% ======================================================================
function Rs = scenResid(F, d, nS, nT)
% 与 q2_solve 完全一致的情景残差取样（近 nS 天，只用 d-1 及以前）
pool = (d-nS):(d-1);
pool = pool(pool >= 1);
if isempty(pool)
    Rs = zeros(nT, nS);  return;
end
Rmat = F.Nact(pool,:) - F.Nhat(pool,:);
np_  = size(Rmat,1);
if np_ >= nS
    Rs = Rmat(end-nS+1:end, :)';
else
    Rs = repmat(Rmat', 1, ceil(nS/np_));
    Rs = Rs(:, 1:nS);
end
end

function s = pass(b)
if b, s = 'PASS'; else, s = 'FAIL'; end
end

function d = q2_outdir()
qc = q2_config();
d = qc.outdir;
end
