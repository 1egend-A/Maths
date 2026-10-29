function [g, c, d, cost, info] = day_lp(price, load, pv, S_start, cfg, S_end)
% DAY_LP  单日优化（Q1 雏形：只买电，无紧急购电、无调整）
%
% 决策变量 x = [g(1..n); c(1..n); d(1..n)]
%   min  sum_t  price_t * g_t * dt
%   s.t. 功率平衡 / SOC 递归 / SOC 上下限 / 充放功率上限
%
% 输入
%   price, load, pv : 该日 n 个时段（144）
%   S_start         : 当日 0:00 的 SOC (kWh)
%   cfg             : p0_config() 结果
%   S_end           : 日末 SOC 目标；[] = 不约束（由 cfg.termPolicy 决定要不要传）
%
% 输出
%   g, c, d : 最优购电 / 充电 / 放电功率 (kW)
%   cost    : 最优日购电费 (元)
%   info    : 求解诊断

n = numel(price);
price = price(:); load = load(:); pv = pv(:);
assert(numel(load) == n && numel(pv) == n, 'price/load/pv 长度必须一致');
if nargin < 6
    S_end = [];
end

% ---- 按口径展开系数 ----
switch cfg.effConv
    case 'ac'
        bc = -1;          bd =  1;           % 平衡: g + bc*c + bd*d = L - PV
        ac =  cfg.eta;    ad = -1/cfg.eta;   % SOC : 增量 = (ac*c + ad*d)*dt
    case 'dc'
        bc = -1/cfg.eta;  bd =  cfg.eta;
        ac =  1;          ad = -1;
    otherwise
        error('未知 cfg.effConv = %s', cfg.effConv);
end

ig = 1:n; ic = n+1:2*n; id = 2*n+1:3*n;
hasTerm = ~isempty(S_end);

% ---- 等式约束：功率平衡 (+ 可选日末 SOC) ----
Aeq = zeros(n + hasTerm, 3*n);
for t = 1:n
    Aeq(t, ig(t)) = 1;
    Aeq(t, ic(t)) = bc;
    Aeq(t, id(t)) = bd;
end
beq = load - pv;
if hasTerm
    Aeq(n+1, ic) = ac * cfg.dt;
    Aeq(n+1, id) = ad * cfg.dt;
    beq = [beq; S_end - S_start];
end

% ---- 不等式约束：SOC 轨迹 S_start + cumsum(...) 落于 [S_min, S_max] ----
C = zeros(n, 3*n);
for t = 1:n
    C(t, ic(1:t)) = ac * cfg.dt;
    C(t, id(1:t)) = ad * cfg.dt;
end
A = [-C; C];
b = [-(cfg.S_min - S_start) * ones(n,1); (cfg.S_max - S_start) * ones(n,1)];

% ---- 目标 ----
f = zeros(3*n, 1);
f(ig) = price * cfg.dt;

% ---- 变量边界 ----
lb = zeros(3*n, 1);
ub = inf(3*n, 1);
ub(ic) = cfg.P_max;
ub(id) = cfg.P_max;

opts = optimoptions('linprog', 'Display', 'off');
[x, cost, flag, out] = linprog(f, A, b, Aeq, beq, lb, ub, opts);

if flag ~= 1
    warning('day_lp: linprog 退出标志 = %d (%s)', flag, out.message);
end

g = x(ig); c = x(ic); d = x(id);

info.flag  = flag;
info.msg   = out.message;
info.nVar  = 3*n;
info.nCon  = size(A,1) + size(Aeq,1);
info.term  = hasTerm;
info.effConv = cfg.effConv;
end
