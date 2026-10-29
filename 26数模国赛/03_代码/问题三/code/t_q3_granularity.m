function Tab = t_q3_granularity()
% T_Q3_GRANULARITY  口径 3 敏感性：调整量的结算粒度（逐 10 分钟 vs 全天总量）
%
% 题面说「计划购电量高于调整购电量的部分，违约电价是…50%」，但没说这个"部分"
% 是【逐时段比出来】还是【按全天总量比出来】。两种读法给出不同的费用：
%
%   口径 3a 逐 10 分钟（本队采用）：逐槽比 G_t 与 A_t，罚则逐槽计。
%   口径 3b 全天总量        ：先把全天电量各自加总 G_tot、A_tot，只比一次，
%                          罚则按总量差计。日内"这里多了那里少了"会被抵消掉。
%
% 本脚本【不改决策】，只用同一组 (G, A, C, D) 按两种口径分别【结算】，
% 因此差异纯由结算口径产生，可与模型选择解耦。
%
% ⚠️ 总量口径下价格如何归集没有唯一答案（日内 144 段电价不同，而总量只有一个数）。
%    本脚本取当日【简单时段均价】p̄ = mean(p_t)，并在报告里显式声明——这是把
%    "总量口径"落到实处时绕不开的一步近似，也是该口径本身的粗糙之处，正是本节
%    想展示的：粗粒度结算不仅换个数，还会改变"该上修还是该下修"的判断。
%
% 落盘：out/t_q3_granularity.csv / .mat
%
% 用法：Tab = t_q3_granularity();

D  = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码\out\data.mat').D;
qc = q3_config();
R  = load([qc.outdir 'q3_solution.mat']).R;

dt = qc.dt;  pr = R.price;  nd = numel(R.dayIdx);

fprintf('===== 口径 3 敏感性：调整量结算粒度 =====\n');

% ---- 口径 3a：逐 10 分钟（= 模型自身的口径，直接取）----
cPlanA = R.costPlan;  cAdjA = R.costAdj;  cEmA = R.costEm;
totA   = R.Sadj;

% ---- 口径 3b：全天总量 ----
Gtot = sum(R.G,2)*dt;            % kWh
Atot = sum(R.A,2)*dt;
pBar = mean(pr, 2);              % 当日简单时段均价
cPlanB = pBar .* min(Gtot, Atot);
cAdjB  = pBar .* (qc.kUnder*max(0, Gtot-Atot) + qc.kOver*max(0, Atot-Gtot));
cEmB   = cEmA;                   % 紧急购电本身就是逐槽的，两种口径一致
totB   = cPlanB + cAdjB + cEmB;

% 逐槽口径下是否发生调整、朝哪个方向
nHi = arrayfun(@(k) sum(R.clipHi(k,:)), 1:nd)';
nLo = arrayfun(@(k) sum(R.clipLo(k,:)), 1:nd)';
dirSlot = sign(nHi - nLo);               % +1 上修为主，−1 下修为主，0 不动
dirTot  = sign(Atot - Gtot);             % 总量口径下的方向
nFlip   = sum(dirSlot ~= 0 & dirTot ~= 0 & dirSlot ~= dirTot);

Tab = table(sum(totA), sum(totB), sum(totB)-sum(totA), ...
    100*(sum(totB)-sum(totA))/sum(totA), ...
    sum(sum(abs(R.A-R.G) > 1e-9)), sum(dirSlot ~= 0), nFlip, ...
    'VariableNames', {'逐10分钟_元','全天总量_元','差额_元','差额_pct', ...
                      '被调整的槽数','有净调整的天数','方向相反的天数'});

fprintf('\n%-16s %16s %12s %12s\n', '口径','总费用(元)','有净调整天数','方向相反天数');
fprintf('%-16s %16.2f %12d %12s\n', '逐 10 分钟', sum(totA), sum(dirSlot~=0), '—');
fprintf('%-16s %16.2f %12d %12d\n', '全天总量',   sum(totB), sum(dirTot~=0), nFlip);
fprintf('\n  差额 %.2f 元（%.3f%%），方向相反 %d 天\n', ...
    sum(totB)-sum(totA), 100*(sum(totB)-sum(totA))/sum(totA), nFlip);
fprintf('  被逐槽调整的时段共 %d 个（占 6:00 之后 %d 槽的 %.2f%%）\n', ...
    sum(sum(abs(R.A-R.G) > 1e-9)), sum(sum(isfinite(R.AgLo))), ...
    100*sum(sum(abs(R.A-R.G) > 1e-9))/sum(sum(isfinite(R.AgLo))));

% ---- 落盘 ----
outdir = qc.outdir;  if ~isfolder(outdir), mkdir(outdir); end
writetable(Tab, [outdir 't_q3_granularity.csv'], 'Encoding', 'UTF-8');
totA_=totA; totB_=totB; dirSlot_=dirSlot; dirTot_=dirTot;  %#ok<NASGU>
save([outdir 't_q3_granularity.mat'], 'Tab', 'totA_', 'totB_', 'dirSlot_', 'dirTot_');
fprintf('\n  已写出：%s\n', [outdir 't_q3_granularity.csv']);
end
