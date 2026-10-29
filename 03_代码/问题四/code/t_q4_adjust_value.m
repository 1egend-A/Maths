function Tab = t_q4_adjust_value(modes)
% T_Q4_ADJUST_VALUE  「附件3 预报 + 滚动调整」在逐日电价下还值不值？——2×2 归因
%
% ============================================================
%  问题四最反直觉的一个结果：
%     问题二/三（附件1 电价）下，引入附件3 预报 + 6/12/18 三次滚动调整能省钱；
%     问题四（附件4 逐日电价）下，同样的机制反而【更贵】——
%         Q4-3（附件3+调整）15,386,858.33 元  >  Q4-2（自预测+不调整）15,239,965.81 元
%  但直接比这两个数是【混同比较】：它们同时变了两个因素
%     ① 光伏预报来源（附件3 官方 vs 自预测 mean7）
%     ② 调整机制（有无 6/12/18 三次调整 + 重排充放电）
%  故必须做 2×2 分解，把两个主效应与交互项分开：
%
%                    不调整(useStages=[1 0 0 0])   调整(useStages=[1 1 1 1])
%      自预测 pvSource='self'      A                              B
%      附件3  pvSource='a3'        C                              D  (= Q4-3)
%
%      预报来源效应（self→a3），调整关 ： C − A
%      预报来源效应（self→a3），调整开 ： D − B
%      调整机制效应（关→开），用附件3  ： D − C
%      调整机制效应（关→开），用自预测 ： B − A
%      交互项 = (D − C) − (B − A)：两机制的联合效果不是各自效果的简单相加
%
%  ⚠️ 口径说明：四格全部用【问题三的滚动框架同一套代码】，只拨 pvSource 与 useStages
%     两个开关，故格间的差异只可能来自这两个因素，不含实现差异。
%     每格都重新跑 q3_forecast（预报来源不同必须重新生成预报，不能只改配置标志）。
%
%  ⚠️ 诚实提示（写进论文）：A 格（Q3 框架 + 自预测 + 不调整）在理论上应等于
%     问题二的框架。两者若不完全相等，差额来自「负载预测器是否同一套」——
%     q2_forecast 与 q3_forecast 的负载方法与融合权重可能不同。脚本会把两者并列
%     并给出差异，不做掩饰。
%
% 用法：Tab = t_q4_adjust_value();             % 只跑附件4 电价（4 格，约 3.5 min）
%       Tab = t_q4_adjust_value({'volatile','fixed'});   % 两种电价都跑（8 格）
%
% 落盘：out/t_q4_adjust_value.csv、out/t_q4_adjust_value.mat

if nargin < 1 || isempty(modes), modes = {'volatile'}; end
if ischar(modes), modes = {modes}; end

ROOT = 'D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\';
D  = load([ROOT '数据预处理代码\out\data.mat']).D;
qc0 = q4_config();
qc0.verbose = false;
nd = numel(qc0.dayIdx);

fprintf('===== 问题四：「附件3 预报 + 滚动调整」的价值归因（2×2 分解）=====\n');
fprintf('区间 %d 天（%s ~ %s）\n', nd, string(qc0.dateFirst), string(qc0.dateLast));

cells = {'A', 'self', [1 0 0 0], '自预测 + 不调整'; ...
         'B', 'self', [1 1 1 1], '自预测 + 调整'; ...
         'C', 'a3',   [1 0 0 0], '附件3  + 不调整'; ...
         'D', 'a3',   [1 1 1 1], '附件3  + 调整'};
nC = size(cells, 1);  nM = numel(modes);
cost = nan(nM, nC);  qBuy = nan(nM, nC);

for m = 1:nM
    qc0.priceMode = modes{m};
    fprintf('\n---- 电价口径：%s ----\n', modes{m});
    for i = 1:nC
        q2 = qc0;
        q2.pvSource  = cells{i,2};
        q2.useStages = logical(cells{i,3});
        fprintf('  [%s %s] 重新生成预报 + 求解中...', cells{i,1}, cells{i,4});
        F = q3_forecast(D, q2);
        R = q3_solve(D, F, q2);
        cost(m,i) = R.summary.costTot;
        qBuy(m,i) = R.summary.qAdjTot + R.summary.qEmTot;
        fprintf(' 费用 %14.2f 元 | 购电 %12.1f kWh\n', cost(m,i), qBuy(m,i));
    end

    A = cost(m,1);  B = cost(m,2);  Cc = cost(m,3);  Dd = cost(m,4);
    fprintf('\n  【%s：2×2 分解】\n', modes{m});
    fprintf('    %-22s %16s %16s %14s\n', '格', '不调整（元）', '调整（元）', '调整的效应');
    fprintf('    %-22s %16.2f %16.2f %14.2f\n', '自预测', A, B, B-A);
    fprintf('    %-22s %16.2f %16.2f %14.2f\n', '附件3',  Cc, Dd, Dd-Cc);
    fprintf('    %-22s %16.2f %16.2f\n', '预报来源的效应', Cc-A, Dd-B);
    fprintf('    %-22s %+14.2f 元\n', '交互项 (D−C)−(B−A)', (Dd-Cc)-(B-A));
    fprintf('    %-22s %+14.2f 元（%+.3f%%）\n', '调整机制（附件3 下）', Dd-Cc, 100*(Dd-Cc)/Cc);
    fprintf('    %-22s %+14.2f 元（%+.3f%%）\n', '引入附件3（调整关）', Cc-A, 100*(Cc-A)/A);
    if (Dd-Cc) > 0
        fprintf('    ★ 在【%s】下，调整机制不是省钱的，而是【多花钱】的：\n', modes{m});
        fprintf('      正因附件3 的光伏预报精度不如自预测（RMSE 644.72 vs 303.86 kW），\n');
        fprintf('      按它去调量，多买的部分要付 1.5 倍价，少买的部分只退 0.5 倍价，\n');
        fprintf('      非对称罚则让"调错方向"的代价大于"调对方向"的收益。\n');
    else
        fprintf('    ★ 在【%s】下，调整机制净省钱 %.2f 元（%.3f%%）。\n', ...
            modes{m}, Cc-Dd, 100*(Cc-Dd)/Cc);
    end
end

%% ---- 与问题二框架的交叉核对（只在 volatile 口径下做）----
fprintf('\n---- 交叉核对：A 格（自预测+不调整）vs 问题二框架（result4-2）----\n');
f42 = [qc0.outdir42 'q4_solution_p2.mat'];
iV = find(strcmp(modes, 'volatile'), 1);
if ~isempty(iV) && isfile(f42)
    cR2 = load(f42, 'R2').R2.summary.costTot;
    fprintf('  A 格 %14.2f 元 | 问题二框架 %14.2f 元 | 差 %+12.2f 元（%+.4f%%）\n', ...
        cost(iV,1), cR2, cost(iV,1)-cR2, 100*(cost(iV,1)-cR2)/cR2);
    if abs(cost(iV,1)-cR2) < 1e-3*abs(cR2)
        fprintf('  -> 两者一致：自预测+不调整确实复现了问题二框架\n');
    else
        fprintf(['  -> 两者不等。原因：q2_forecast 与 q3_forecast 的【负载预测器】\n' ...
                 '     不是同一套（前者不带附件3 相关的融合，后者带）。故"不调整"这一格\n' ...
                 '     在两种框架下并不完全同构，论文引用时须注明，不可当作同一基准。\n']);
    end
else
    fprintf('  （未找到 %s，跳过）\n', f42);
end

%% ---- 落盘 ----
mcol = {}; ccol = []; lblcol = {}; costcol = []; qcol = [];
for m = 1:nM
    for i = 1:nC
        mcol{end+1,1}  = modes{m};       %#ok<AGROW>
        ccol(end+1,1)  = i;              %#ok<AGROW>
        lblcol{end+1,1}= sprintf('%s %s', cells{i,1}, cells{i,4}); %#ok<AGROW>
        costcol(end+1,1)= cost(m,i);     %#ok<AGROW>
        qcol(end+1,1)  = qBuy(m,i);      %#ok<AGROW>
    end
end
Tab = table(mcol, ccol, lblcol, costcol, qcol, ...
    'VariableNames', {'电价口径','格','组合','总费用_元','购电量_kWh'});
writetable(Tab, [qc0.outdir 't_q4_adjust_value.csv'], 'Encoding', 'UTF-8');
save([qc0.outdir 't_q4_adjust_value.mat'], 'Tab', 'cost', 'qBuy', 'modes', 'cells');
fprintf('\n  已写出：%s\n', [qc0.outdir 't_q4_adjust_value.csv']);
fprintf('  已写出：%s\n', [qc0.outdir 't_q4_adjust_value.mat']);
end
