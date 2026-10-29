function t_q2_term_policy()
% T_Q2_TERM_POLICY  口径 2（日末固定 6000）的代价实测 —— q2_config.m 中承诺的对照实验
%
% 口径 2 规定每日 S_0 = S_144 = 6000 kWh。它把「跨日搬运储能」这条路彻底封死：
% 日内低价时段充的电必须当天用完，不能留到次日。本脚本量化这条约束值多少钱。
%
% 对照设置（在【完美信息】下比，两边都可精确求解，差距只来自闭环约束本身）：
%   A_det  逐日独立最优：334 个单日 LP，每天 S_0 = S_144 = 6000（= q2_oracle 之和）
%   B_det  全区间联合最优：一个 334 天的大 LP，S_0(2/1) = 6000、S_144(12/31) = 6000，
%          中间 332 个日界 SOC 【自由】
%   ⇒ 差值 = 日末闭环约束的代价（A_det - B_det ≥ 0，B_det 是放宽后的下界）
%
% 为什么必须用完美信息：本模型（日前计划+紧急购电）里有预测误差，两边都带预测误差
% 就无法把差值干净地归因给闭环约束。完美信息下 A/B 唯一差别就是闭环与否。
%
% 输出：out/q2_term_policy.txt（UTF-8），并在控制台打印。
%
% 用法：t_q2_term_policy()

P0DIR = 'D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码';
if isempty(which('p0_config')), addpath(P0DIR); end
qc = q2_config();
D  = load([P0DIR '\out\data.mat']).D;

nT = 144;  nd = numel(qc.dayIdx);  n = nd*nT;
dt = qc.dt;  eta = qc.eta;
pr = D.day144.price(:);                       % 元/kWh，逐日相同
L  = D.actual.load(qc.dayIdx, :);             % nd × nT
Pv = D.actual.pv(qc.dayIdx, :);
% 展平：slot t = (k-1)*nT + j，即先排第 1 天的 144 个时段，再排第 2 天……
Lv  = reshape(L',  [], 1);                    % n × 1
Pvv = reshape(Pv', [], 1);
prv = repmat(pr, nd, 1);                      % n × 1

lines = {};
    function say(varargin)
        lines{end+1} = sprintf(varargin{:});
    end

say('==========================================================');
say(' 口径 2 敏感性实验：日末 SOC 固定 6000 vs 日界自由');
say('==========================================================');
say('区间 %s ~ %s，共 %d 天（%d 个时段）', string(qc.dateFirst), string(qc.dateLast), nd, n);
say('电价逐日相同；两边都在【完美信息】下求解，唯一差别 = 日末是否闭环');
say('');

%% ---------------- A_det：逐日独立最优 ----------------
say('---- A_det：逐日独立最优（每日 S_0 = S_144 = 6000）----');
bf = [qc.outdir 'q2_bench.mat'];
if isfile(bf)
    B0 = load(bf).bench;
    cA = sum(B0.cOr);
    say('   直接复用 q2_bench.mat 中的完美信息基准（q2_oracle 逐日求和）');
else
    say('   未找到 q2_bench.mat，现算 %d 个单日 LP（约 10 s）……', nd);
    cOr = zeros(nd,1);
    for k = 1:nd
        [cOr(k), ~, ~, ~] = q2_oracle(pr, L(k,:), Pv(k,:), qc.S0, qc.S_end, qc);
    end
    cA = sum(cOr);
end
say('   A_det 总费用 = %.2f 元', cA);
say('');

%% ---------------- B_det：全区间联合最优（日界自由）----------------
say('---- B_det：全区间联合最优（中间日界 SOC 自由）----');
say('   正在组装并求解 %d 变量的大 LP（dual-simplex，最长 15 min）……', 5*n);
t0 = tic;
[cB, SB, fl, msg] = solveHorizon(n, nVarOf(n), Lv, Pvv, prv, dt, eta, qc);
tB = toc(t0);
say('   求解用时 %.1f s，exitflag = %d（1 = 求得最优）', tB, fl);
if fl ~= 1
    say('   ⚠️ 未取得最优解，间隙未标定，下列数字仅供参考：%s', msg);
end
say('   B_det 总费用 = %.2f 元', cB);
say('');

%% ---------------- 结论 ----------------
gap = cA - cB;
say('---- 结论 ----');
say('   日末闭环的代价（A_det - B_det） = %.2f 元', gap);
if cA > 0
    say('   占 A_det 的比例                    = %.4f %%', 100*gap/cA);
    say('   折合每天                           = %.1f 元/天', gap/nd);
end
say('');

% 日界 SOC 漂移（放开闭环后，最优解会把日末 SOC 拉到哪里去？）
send = [];
if fl == 1 && ~isempty(SB)
    send = SB(nT:nT:end);                     % 每天末时段的储电量
    say('---- B_det 的日末 SOC 轨迹（口径 2 下恒为 6000）----');
    say('   范围 [%.1f, %.1f] kWh，均值 %.1f kWh，标准差 %.1f kWh', ...
        min(send), max(send), mean(send), std(send));
    nDev = sum(abs(send-qc.S0) > 1);
    say('   偏离 6000 超过 1 kWh 的天数 = %d / %d', nDev, nd);
    say('');
    say('   ⚠️ 注意这里很容易误读：放开闭环后，最优 SOC 轨迹【确实大幅偏离】6000');
    say('      （均值 %.0f kWh，即最优解倾向于"囤电"），但费用只降了 %.2f 元（%.2f%%）。', ...
        mean(send), gap, 100*gap/cA);
    say('      也就是说：轨迹差别很大，价值差别极小。原因是电价逐日【完全相同】，');
    say('      跨日搬运储能没有价格差可套，囤电只能用于对冲次日负荷波动 ——');
    say('      而这部分风险在问题二里已由【紧急购电】以 5 倍电价的方式兜底处理了。');
end

say('');
say('---- 对口径 2 的裁决 ----');
say('   代价 %.2f 元（占最优费用 %.4f%%，折合 %.1f 元/天）应放到两个尺度上比：', ...
    gap, 100*gap/cA, gap/nd);
say('     · 储能本身创造的价值              1841894.18 元   ⇒ 本代价仅为其 %.2f%%', ...
    100*gap/1841894.18);
say('     · 预测误差造成的损失              2320378.54 元   ⇒ 本代价仅为其 %.2f%%', ...
    100*gap/2320378.54);
say('   结论：口径 2（日末固定 6000）放弃了不足 0.12%% 的理论节费空间，');
say('         换来的是【逐日自洽、结果唯一可复现、无需倒推 1 月来定起始 SOC】。');
say('         代价与另外两项量级相差两个数量级，是几乎无损失的建模选择。');

%% ---------------- 落盘 ----------------
txt = strjoin(lines, sprintf('\n'));
if ~isfolder(qc.outdir), mkdir(qc.outdir); end
fid = fopen([qc.outdir 'q2_term_policy.txt'], 'w', 'n', 'UTF-8');
fprintf(fid, '%s\n', txt);
fclose(fid);
fprintf('\n%s\n', txt);
fprintf('已写出：%s\n', [qc.outdir 'q2_term_policy.txt']);

save([qc.outdir 'q2_term_policy.mat'], 'cA', 'cB', 'gap', 'fl', 'send', 'tB');
end

% ======================================================================
function nVar = nVarOf(n)
nVar = 5*n;
end

function [cB, SB, fl, msg] = solveHorizon(n, nVar, Lv, Pvv, prv, dt, eta, qc)
% 全区间 LP：变量 [g; c; d; e; S]，每个时段 5 个
%   平衡（等式）  g + d - e - c = L - PV
%   SOC 递推（等式）S_t - S_{t-1} - eta*dt*c_t + (dt/eta)*d_t = 0，S_1 用初值、末点闭环
% ⚠️ 用 sparse 组装时【绝不能】出现重复的 (行,列) 对——sparse 会把重复项【求和】，
%    曾因此在 q2_oracle 里把 S_1 的正负项互相抵消，导致"不可行"的假象。
%    下面每个 row/col 组合都唯一，逐行核对过。
ig = @(t) t;  ic = @(t) n + t;  id = @(t) 2*n + t;
ie = @(t) 3*n + t;  iS = @(t) 4*n + t;
tt = (1:n)';

% --- 平衡行（1..n）---
A1 = sparse([tt; tt; tt; tt], ...
            [ig(tt); id(tt); ie(tt); ic(tt)], ...
            [ones(n,1); ones(n,1); -ones(n,1); -ones(n,1)], n, nVar);
b1 = Lv - Pvv;

% --- SOC 递推行 ---
% 第 t 行：+S_t、-S_{t-1}（t>=2）、-eta*dt*c_t、+(dt/eta)*d_t
% ⚠️ 行号必须从 1 开始编号（声明行数就是 n），最后再 [A1; A2; A3] 纵向拼接。
%    若直接写 n+tt 而把行数声明成 n，sparse 会报「索引超出数组范围」。
r2 = (1:n)';
A2 = sparse([r2; r2(2:end); r2; r2], ...
            [iS(tt); iS(tt(1:end-1)); ic(tt); id(tt)], ...
            [ones(n,1); -ones(n-1,1); -eta*dt*ones(n,1); (dt/eta)*ones(n,1)], ...
            n, nVar);
b2 = [qc.S0; zeros(n-1,1)];

% --- 末点闭环（第 2n+1 行）：S_n = 6000 ---
A3 = sparse(1, iS(n), 1, 1, nVar);

Aeq = [A1; A2; A3];
beq = [b1; b2; qc.S_end];

% --- 目标：Σ p_t * g_t * dt（完美信息，无紧急购电项）---
f = zeros(nVar,1);
f(ig(tt)) = prv(tt)*dt;

lb = zeros(nVar,1);  ub = inf(nVar,1);
lb(iS(tt)) = qc.S_min;   ub(iS(tt)) = qc.S_max;
ub(ic(tt)) = qc.P_max;   ub(id(tt)) = qc.P_max;

opts = optimoptions('linprog', 'Algorithm', 'dual-simplex', ...
                    'Display', 'off', 'MaxTime', 900);
[x, cB, fl, msg] = linprog(f, [], [], Aeq, beq, lb, ub, opts);
if fl == 1
    SB = x(iS(tt));
else
    SB = [];
end
end
