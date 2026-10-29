function R = q4_solve_p3(D, F, qc, dayList)
% Q4_SOLVE_P3  问题四保底结果之二：把【问题三框架】搬到附件4 的逐日实测电价上
%
% ============================================================
%  本函数【就是】问题三的滚动求解器 问题三/code/q3_solve.m，一字不改地调用。
%  问题四与问题三的全部差异已在 q3_solve.m 内部处理（它按 qc.priceMode 取电价）：
%        case 'fixed'     →  附件1 报价，逐日相同（问题三）
%        case 'volatile'  →  附件4 实测电价，逐日逐时段（问题四）
%
%  这正是团队铁律「禁止各自生成求解器再拼接」的落地：Q3 与 Q4 共用同一个求解器，
%  因而两者的差异【只可能】来自电价输入，是可解释的受控对照。
%
%  本包装函数存在的唯一意义，是在调用前把「电价确实是附件4 逐日的」这件事
%  当场验明——否则一旦 priceMode 传错，Q4 会静默地算出问题三的结果。
% ============================================================
%
% 输入：D、F（q3_forecast 输出）、qc（q4_config）、dayList
% 输出：R（与 问题三/out/q3_solution.mat 同构）

if nargin < 4 || isempty(dayList), dayList = qc.dayIdx; end

% ---- 守卫 1：模式必须是 volatile ----
assert(strcmpi(qc.priceMode, 'volatile'), ...
    'q4_solve_p3 要求 qc.priceMode = ''volatile''，当前为 %s', qc.priceMode);

% ---- 守卫 2：附件4 电价必须真的逐日不同 ----
% 若误把附件1 的均值剖面填进 D.actual.price，逐日方差会是 0，Q4 退化成 Q3。
pr = D.actual.price(dayList, :);
sdCol = std(pr, 0, 1);                       % 逐时段的日间标准差
vDay  = mean(pr, 2);                         % 每日均价
assert(mean(sdCol) > 1e-3, ...
    '附件4 电价逐日无差异（日间标准差均值 %.3e），疑似误用附件1 剖面', mean(sdCol));

% ---- 守卫 3：与附件1 均值剖面必须有差别（Q4 ≠ Q2 换价格串的定量依据）----
if isfield(D, 'day144') && isfield(D.day144, 'price')
    a1 = D.day144.price(:)';
    dmax = max(abs(a1 - mean(pr, 1)));
    fprintf('  [守卫] 附件1 剖面 vs 附件4 年均：max|差| = %.4g 元/kWh\n', dmax);
end

% ---- 电价波动画像（论文 9.1 用）----
% ⚠️ 线性索引 → (天, 槽) 的换算必须用 size(pr,2) 作模数（pr 是 nDay×144 的列优先矩阵），
%    且【必须打出日期与时刻】。曾经只打「第几天第几槽」：既看不出是哪一天，
%    又因换算写错而在日志里报出第 166 天 / 第 287 天这种查无实据的位置
%    （真值见下方日期版本）。论文要引用地点就必须能一眼对上日期。
[mn, imn] = min(pr(:));  [mx, imx] = max(pr(:));
nS2 = size(pr, 2);
[dmn, smn] = deal(ceil(imn/nS2), mod(imn-1, nS2) + 1);
[dmx, smx] = deal(ceil(imx/nS2), mod(imx-1, nS2) + 1);
fprintf('  [q4_solve_p3] 电价区间 [%.4f, %.4f] 元/kWh，峰谷比 %.1f 倍\n', ...
    mn, mx, mx/max(mn, eps));
fprintf('     最低价 %.4f 元/kWh：%s %02d:%02d（区间内第 %d 天第 %d 槽）\n', ...
    mn, strD(qc, dayList, dmn), floor((smn-1)/6), mod(smn-1,6)*10, dmn, smn);
fprintf('     最高价 %.4f 元/kWh：%s %02d:%02d（区间内第 %d 天第 %d 槽）\n', ...
    mx, strD(qc, dayList, dmx), floor((smx-1)/6), mod(smx-1,6)*10, dmx, smx);
fprintf('     近零时段（<0.10 元/kWh）全年 %d 个，<0.05 的 %d 个\n', ...
    sum(pr(:) < 0.10), sum(pr(:) < 0.05));
fprintf('     逐日均价：min %.4f / mean %.4f / max %.4f 元/kWh\n', ...
    min(vDay), mean(vDay), max(vDay));

% ---- 直接调用问题三的求解器 ----
if isempty(which('q3_solve')), addpath(qc.dirQ3); end
R = q3_solve(D, F, qc, dayList);
R.framework = 'q3-rolling';
end

% ======================================================================
function s = strD(qc, dayList, iDay)
% STRD  把「区间内第 iDay 天」换成日历日期字符串（供上面的电价地点打印使用）
% dayList 是 D 全年的 day-of-year 下标；qc.dateFirst 是区间第一天的日期。
s = char(qc.dateFirst + (dayList(iDay) - dayList(1)));
end
