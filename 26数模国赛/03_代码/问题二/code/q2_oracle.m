function [cost, qBuy, g, flag] = q2_oracle(price, load, pv, S0, SEND, qc)
% Q2_ORACLE  完美信息基准（问题二的费用下界）
%
% 假想微网在 0:00 就【准确知道】当天的负载与光伏：此时无需紧急购电，
% 决策退化为确定性的单日线性规划，其结果给出问题二在给定储能参数下的
% 理论最优费用下界，用于衡量「预测误差的代价」。
%
%   min  Σ_t price_t * g_t * dt
%   s.t. g_t + d_t + (PV_t - e_t) = L_t + c_t    （e_t = 被弃掉的光伏，e_t >= 0）
%        ⇔ g_t + d_t - e_t - c_t = L_t - PV_t
%        S_t = S_{t-1} + (eta*c_t - d_t/eta)*dt
%        S_min <= S_t <= S_max ,  S_144 = SEND ,  0 <= c_t,d_t <= P_max
%
% 与 p0 的 day_lp 的区别：本函数【含弃电变量 e_t】。day_lp 强制 e ≡ 0，
% 在光伏富余超过储能吞吐能力时会不可行，故基准须用带 e 的版本。

n  = numel(price);
price = price(:); load = load(:); pv = pv(:);
dt = qc.dt; eta = qc.eta;

ig = 1:n; ic = n+(1:n); id = 2*n+(1:n); iS = 3*n+(1:n); ie = 4*n+(1:n);
nVar = 5*n;

% 平衡（等式）：g + d - e - c = L - PV      （e = 被弃掉的光伏，故取负号）
Aeq1 = sparse(repmat((1:n)',5,1), ...
              [ig(:); id(:); ie(:); ic(:); iS(:)], ...
              [ones(n,1); ones(n,1); -ones(n,1); -ones(n,1); zeros(n,1)], n, nVar);
% SOC 递推（等式）：S_t - S_{t-1} - eta*dt*c_t + (dt/eta)*d_t = 0
% ⚠️ 行号必须与列号【成对】写：-S_{t-1} 只存在于 t=2..n（t=1 的 S_0 是常数、不是变量）。
%    若图省事写成 repmat((1:n)',4,1) 配 iS(:) 两遍，第 1 行会同时拿到 +S_1 与 -S_1，
%    sparse 把二者相加抵消 ⇒ S_1 项凭空消失，第 1 行退化成 -0.15c_1+0.1852d_1=6000，
%    逼出 d_1>=32400 kW，LP 直接报不可行（flag=-2）。第 n 行同理会丢掉 -S_{n-1}。
Aeq2 = sparse([(1:n)'; (2:n)'; (1:n)'; (1:n)'], ...
              [iS(:); iS(1:n-1)'; ic(:); id(:)], ...
              [ones(n,1); -ones(n-1,1); -eta*dt*ones(n,1); (dt/eta)*ones(n,1)], ...
              n, nVar);
Aeq = [Aeq1; Aeq2];
beq = [load - pv; [S0; zeros(n-1,1)]];

f = zeros(nVar,1); f(ig) = price * dt;

lb = zeros(nVar,1);  ub = inf(nVar,1);
ub(ic) = qc.P_max;  ub(id) = qc.P_max;
lb(iS) = qc.S_min;  ub(iS) = qc.S_max;
lb(iS(n)) = SEND;   ub(iS(n)) = SEND;

opts = optimoptions('linprog','Display','off');
[x, cost, flag] = linprog(f, [], [], Aeq, beq, lb, ub, opts);
if flag ~= 1
    warning('q2_oracle: linprog flag=%d', flag);
end
g = x(ig);
qBuy = sum(g)*dt;
end
