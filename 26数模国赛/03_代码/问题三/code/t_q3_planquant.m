function Tab = t_q3_planquant()
% T_Q3_PLANQUANT  计划量临界分位 qPlan 的实证扫描（本问解析内核的数值验证）
%
% 本问最要紧的一条解析结论是【计划量 G_t 的最优分位】。
% 直觉会给出 0.5（「偏离的罚则 0.5 与 1.5 上下对称 ⇒ 取中位数」），
% 但这个直觉是错的：它漏掉了 5 倍紧急购电对计划量的对冲需求。
%
% 正确的边际分析（见 q3_config.m 的推导）分区域：
%   · 调整【不起作用】的时段（A = G，占多数）：∂C/∂G = p·[1 − 5·P(Q>G)] = 0
%     ⇒ P(Q>G*) = 0.2 ⇒ G* = Q_(0.8) —— 与问题二【同一个分位】；
%   · 调整【起作用】的时段：A>G 侧边际 −0.5p（该调高）、A<G 侧边际 +0.5p（该调低），
%     把 G 拉向 A 的分布中心，故最优 qPlan 会略低于 0.8。
%
% 本脚本把 qPlan 从 0.4 扫到 0.9，用实测费用曲线验证上面的结论，并给出
% 「0.8 相对经验最优的代价」——这是论文里必须如实交代的一个数字。
%
% ⚠️ 为避免 6 次全量求解（每次约 52 s），扫描在【60 天子区间】上做（2/1 ~ 4/1）。
%    子区间跨冬末春初，光伏抬升、负载形态变化，代表性足够；且结论是"曲线的形状"
%    而非绝对值，子区间扫描足以支撑。全量基准值另在 out/q3_solution.mat 里。
%
% 落盘：out/t_q3_planquant.csv / .mat
%
% 用法：Tab = t_q3_planquant();

D  = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码\out\data.mat').D;
qc = q3_config();  qc.verbose = false;
sub = qc.dayIdx(1):qc.dayIdx(1)+59;         % 60 天子区间
assert(numel(sub) == 60);

qs = [0.40 0.50 0.60 0.70 0.80 0.90];
nq = numel(qs);
F = q3_forecast(D, qc);                     % 预报与 qPlan 无关，只算一次

cost = zeros(nq,1); cPlan = zeros(nq,1); cAdj = zeros(nq,1); cEm = zeros(nq,1);
nHi = zeros(nq,1); nLo = zeros(nq,1);

fprintf('===== 计划量分位 qPlan 扫描（%d 天子区间）=====\n', numel(sub));
for i = 1:nq
    q2 = qc;  q2.qPlan = qs(i);
    R = q3_solve(D, F, q2, sub);
    cost(i) = R.summary.costTot;
    cPlan(i)= R.summary.costPlanTot;
    cAdj(i) = R.summary.costAdjTot;
    cEm(i)  = R.summary.costEmTot;
    nHi(i)  = R.summary.nClipHi;
    nLo(i)  = R.summary.nClipLo;
    fprintf('  qPlan = %.2f -> 费用 %14.2f 元\n', qs(i), cost(i));
end

[best, ib] = min(cost);
rel = 100*(cost - best)/best;
i80 = find(abs(qs-0.8) < 1e-12);
i05 = find(abs(qs-0.5) < 1e-12);

Tab = table(qs', cPlan, cAdj, cEm, cost, rel, nHi, nLo, ...
    'VariableNames', {'qPlan','计划购电费','调整购电费','紧急购电费','总费用', ...
                      '相对最优偏离_pct','上修槽数','下修槽数'});

fprintf('\n qPlan |         总费用(元)       调整费(元)       紧急费(元) |       上修槽数       下修槽数 |  相对最优\n');
for i = 1:nq
    fprintf('  %.2f | %20.2f %15.2f %15.2f | %12d %12d | %8.3f%%\n', ...
        qs(i), cost(i), cAdj(i), cEm(i), nHi(i), nLo(i), rel(i));
end
fprintf('\n  经验最优 qPlan = %.2f（费用 %.2f 元）\n', qs(ib), best);
fprintf('  解析值 0.80 的费用 %.2f 元，相对经验最优偏离 %.3f%%\n', cost(i80), rel(i80));
fprintf('  直觉值 0.50 的费用 %.2f 元，相对经验最优偏离 %.3f%%\n', cost(i05), rel(i05));
if rel(i80) < 0.05
    fprintf('  ✅ 解析值 0.80 与经验最优几乎重合，且它是闭式可证的（与问题二同源）。\n');
end

% ---- 落盘 ----
outdir = qc.outdir;  if ~isfolder(outdir), mkdir(outdir); end
writetable(Tab, [outdir 't_q3_planquant.csv'], 'Encoding', 'UTF-8');
qs_=qs; cost_=cost; rel_=rel; sub_=sub;  %#ok<NASGU>
save([outdir 't_q3_planquant.mat'], 'Tab', 'qs_', 'cost_', 'rel_', 'sub_');
fprintf('\n  已写出：%s\n', [outdir 't_q3_planquant.csv']);
end
