function Tab = t_q3_reading()
% T_Q3_READING  费用口径的两种读法：对同一组决策分别结算，量化差额
%
% 题面：「计划购电量高于调整购电量的部分，违约电价是交易时刻电价的 50%；
%        调整购电量高于计划购电量的部分，超出部分的电价是交易时刻电价的 1.5 倍。
%        总的购电费用包括计划购电费用、紧急购电费用和调整购电量的相关费用。」
%
% 这两句话可以被读成两种账（本队采用读法 B）：
%
%   读法 A：计划购电量【全部】按全额 p 计费，未被用掉的部分再另按 50% 计违约费
%           C_A = Σ p·dt·G_t + Σ p·dt·[0.5(G−A)⁺ + 1.5(A−G)⁺] + 紧急费
%   读法 B：被用掉的部分按全额 p 计费，未被用掉的部分【只】按 50% 计
%           C_B = Σ p·dt·min(G,A) + Σ p·dt·[0.5(G−A)⁺ + 1.5(A−G)⁺] + 紧急费
%
% 两式的差恰好是一个可以写出来的闭式：
%           C_A − C_B = Σ p_t·dt·(G_t − A_t)⁺      ← 被"计划了但没买"的那部分电量的全价
% 因为 (G)^+ = min(G,A) + (G−A)^+。本脚本用实测数据把这个差额算出来。
%
% ★ 为什么采用读法 B
%   题面「违约电价是交易时刻电价的 50%」的语义是【该部分按半价结算】；
%   读法 A 等于对同一度电收 1.0 倍 + 0.5 倍 = 1.5 倍，与"违约电价是 50%"
%   这句话直接冲突（50% 指的是电价本身，不是附加的罚率）。
%   读法 A 还会把最优计划分位从 0.8 拉低到 0.25 附近，因为"计划了就要付全价"
%   会极度抑制计划量——那与题面「可根据 0:00 的预报制定当天的计划购电策略」
%   的意图不符（那样 0:00 预报就几乎没用了）。
%
% ⚠️ 本脚本【不改决策】，只用同一组 (G, A, C, D) 按两种读法分别结算。若读法 A
%    被采纳，最优决策本身也会变，故这里的差额是【同决策下的口径差】，不是
%    「两种模型的最优值之差」。这一区别在论文里必须讲明。
%
% 落盘：out/t_q3_reading.csv / .txt
%
% 用法：Tab = t_q3_reading();

D  = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码\out\data.mat').D;
qc = q3_config();
R  = load([qc.outdir 'q3_solution.mat']).R;

dt = qc.dt;  pr = R.price;  nd = numel(R.dayIdx);
fprintf('===== 费用口径两读法对照 =====\n');

over  = max(0, R.A - R.G);          % 多买（1.5 倍）
under = max(0, R.G - R.A);          % 少买（0.5 倍）

penPlanB = sum(sum(pr .* dt .* min(R.G, R.A)));      % 读法 B 的计划购电费
penPlanA = sum(sum(pr .* dt .* R.G));                % 读法 A 的计划购电费（全额）
waste    = sum(sum(pr .* dt .* under));              % = C_A − C_B
cAdj     = sum(sum(pr .* dt .* (qc.kUnder*under + qc.kOver*over)));
cEm      = sum(sum(qc.kEm * pr .* dt .* R.gEm));
cB = penPlanB + cAdj + cEm;
cA = penPlanA + cAdj + cEm;

assert(abs((cA - cB) - waste) < 1e-6, 'C_A − C_B 应恒等于 Σp·dt·(G−A)⁺');

nUnderDay = sum(under*dt > 0, 2);
Tab = table({'读法 B（本队采用）'; '读法 A（不采用）'}, ...
    [penPlanB; penPlanA], [cAdj; cAdj], [cEm; cEm], [cB; cA], ...
    [0; cA-cB], [0; 100*(cA-cB)/cB], ...
    'VariableNames', {'读法','计划购电费','调整购电费','紧急购电费','总费用', ...
                      '较读法B差','较读法B差_pct'});

fprintf('\n%-20s %16s %14s %14s %16s %14s %10s\n', ...
    '读法','计划购电费','调整购电费','紧急购电费','总费用','较B差','差%');
fprintf('%-20s %16.2f %14.2f %14.2f %16.2f %14s %10s\n', 'B（本队采用）', ...
    penPlanB, cAdj, cEm, cB, '—', '—');
fprintf('%-20s %16.2f %14.2f %14.2f %16.2f %14.2f %10.3f\n', 'A（不采用）', ...
    penPlanA, cAdj, cEm, cA, cA-cB, 100*(cA-cB)/cB);
fprintf('\n  差额恒等于「计划了但没买」那部分电量的全价：Σp·dt·(G−A)⁺ = %.2f 元\n', waste);
fprintf('  涉及 %d 天（占 %d 天的 %.1f%%），日均 %.2f 元\n', ...
    sum(nUnderDay > 0), nd, 100*sum(nUnderDay > 0)/nd, waste/nd);
fprintf('  被"多报"的总电量 %.1f kWh（占计划购电量 %.2f%%）\n', ...
    sum(sum(under))*dt, 100*sum(sum(under))*dt/sum(R.qPlan));

% ---- 落盘 ----
outdir = qc.outdir;  if ~isfolder(outdir), mkdir(outdir); end
writetable(Tab, [outdir 't_q3_reading.csv'], 'Encoding', 'UTF-8');
txt = { '费用口径两读法对照（问题三）'; '=========================================================='; ...
    sprintf('读法 B（本队采用）：C = Σp·dt·min(G,A) + Σp·dt·[0.5(G−A)⁺+1.5(A−G)⁺] + 紧急费'); ...
    sprintf('                    合计 %.2f 元', cB); ...
    sprintf('读法 A（不采用）  ：C = Σp·dt·G      + Σp·dt·[0.5(G−A)⁺+1.5(A−G)⁺] + 紧急费'); ...
    sprintf('                    合计 %.2f 元', cA); ...
    sprintf('差额 %.2f 元（%.3f%%），恰为 Σp·dt·(G−A)⁺ = %.2f 元', cA-cB, 100*(cA-cB)/cB, waste); ...
    ''; ...
    '不采用读法 A 的理由：题面「违约电价是交易时刻电价的 50%」的语义是该部分按半价'; ...
    '结算；读法 A 等于对同一度电收 1.0+0.5=1.5 倍，与题面直接冲突。读法 A 还会把'; ...
    '最优计划分位从 0.8 拉到 0.25 量级，使 0:00 预报近乎失去意义。'; ...
    ''; ...
    '⚠️ 本对照是在【同一组决策】下重算的，即口径差；若改采读法 A，最优决策本身也会变，'; ...
    '   故不可把此差额解释为"两种模型最优值之差"。' };
fid = fopen([outdir 't_q3_reading.txt'], 'w', 'n', 'UTF-8');
fprintf(fid, '%s\n', strjoin(txt, sprintf('\n')));
fclose(fid);
fprintf('\n  已写出：%s\n', [outdir 't_q3_reading.csv']);
end
