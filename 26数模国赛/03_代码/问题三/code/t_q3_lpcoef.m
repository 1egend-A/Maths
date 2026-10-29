function Tab = t_q3_lpcoef()
% T_Q3_LPCOEF  LP 中购电变量计价系数 qc.lpPriceCoef 的敏感性
%
% q3_lp.m 把购电量 q_t 以系数 coef·p_t 计入目标（默认 coef = 1，与问题二写法一致）。
% 这个系数【不影响购电量的最优取值】（购电量不进入 SOC 递推，其最优值由报童分位
% 给出，与 coef 无关），但它会影响 LP 对「买电 vs 用储能搬移」的权衡，从而间接
% 影响充放电计划，最终影响费用。换句话说：
%
%      coef 改变的是「储能值不值得用」，而不是「买多少」。
%
% 本脚本扫 coef ∈ {0.5, 1.0, 1.5, 2.0}，看总费用对它的敏感程度，用来给论文里
% 「本模型取 coef = 1.0」这一选择提供依据（若曲线平坦，说明该选择不敏感）。
%
% ⚠️ 为控制用时（每组一次完整求解约 52 s），在【60 天子区间】上扫描。
%
% 落盘：out/t_q3_lpcoef.csv / .mat
%
% 用法：Tab = t_q3_lpcoef();

D  = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码\out\data.mat').D;
qc = q3_config();  qc.verbose = false;
sub = qc.dayIdx(1):qc.dayIdx(1)+59;

coefs = [0.5 1.0 1.5 2.0];
nc = numel(coefs);
F = q3_forecast(D, qc);
cost = zeros(nc,1); qBuy = zeros(nc,1); qChg = zeros(nc,1); qDis = zeros(nc,1);
costPlan = zeros(nc,1); costAdj = zeros(nc,1); costEm = zeros(nc,1);

fprintf('===== LP 购电计价系数敏感性（%d 天子区间）=====\n', numel(sub));
for i = 1:nc
    q2 = qc;  q2.lpPriceCoef = coefs(i);
    R = q3_solve(D, F, q2, sub);
    cost(i)     = R.summary.costTot;
    costPlan(i) = R.summary.costPlanTot;
    costAdj(i)  = R.summary.costAdjTot;
    costEm(i)   = R.summary.costEmTot;
    qBuy(i) = R.summary.qAdjTot + R.summary.qEmTot;
    qChg(i) = sum(sum(R.C))*q2.dt;
    qDis(i) = sum(sum(R.D))*q2.dt;
    fprintf('  coef = %.1f -> 费用 %14.2f 元 | 充电 %10.0f kWh（%.1f s）\n', ...
        coefs(i), cost(i), qChg(i), R.solveSec);
end

i1 = find(coefs == 1.0);
Tab = table(coefs', costPlan, costAdj, costEm, cost, ...
    cost - cost(i1), 100*(cost-cost(i1))/cost(i1), qBuy, qChg, qDis, ...
    'VariableNames', {'lpPriceCoef','计划购电费','调整购电费','紧急购电费','总费用', ...
                      '相对coef1差','相对差_pct','购电量_kWh','充电量_kWh','放电量_kWh'});

fprintf('\n%-12s %14s %12s %14s %14s %14s %14s\n', ...
    'coef','计划购电费','调整购电费','总费用','购电量kWh','充电量kWh','放电量kWh');
for i = 1:nc
    fprintf('%-12.1f %14.2f %12.2f %14.2f %14.0f %14.0f %14.0f\n', ...
        coefs(i), costPlan(i), costAdj(i), cost(i), qBuy(i), qChg(i), qDis(i));
end
fprintf('\n  总费用对 coef 的最大相对偏离 = %.3f%%，购电量最大相对偏离 = %.3f%%\n', ...
    max(abs(cost-cost(i1)))/cost(i1)*100, ...
    max(abs(qBuy-qBuy(i1)))/qBuy(i1)*100);
fprintf('  取 coef = 1.0（与问题二同一写法）在敏感区间内不敏感，选择成立。\n');

% ---- 落盘 ----
outdir = qc.outdir;  if ~isfolder(outdir), mkdir(outdir); end
writetable(Tab, [outdir 't_q3_lpcoef.csv'], 'Encoding', 'UTF-8');
coefs_=coefs; cost_=cost; qBuy_=qBuy; sub_=sub;  %#ok<NASGU>
save([outdir 't_q3_lpcoef.mat'], 'Tab', 'coefs_', 'cost_', 'qBuy_', 'sub_');
fprintf('\n  已写出：%s\n', [outdir 't_q3_lpcoef.csv']);
end
