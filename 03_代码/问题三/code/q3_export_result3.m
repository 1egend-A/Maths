function outFile = q3_export_result3(R, qc, D, F)
% Q3_EXPORT_RESULT3  把问题三求解结果填进官方 result3.xlsx 模板
%
% 模板实况（t_probe_r3.m 实测，附件5/result3.xlsx）：
%   计划购电量  335 行 x 147 列：R1 表头；R2..R335 = 334 天（2025-02-01..12-31）；
%               A 列日期【模板已填】；B..EO(2..145) = 144 个 10 分钟时段；
%               EP(146) = 全天购电量；EQ(147) = 全天购电费。
%   调整购电量  与「计划购电量」完全同构的 335 行 x 147 列（本问新增的那张表）。
%   充放电量    【只给了样例】26 行：首两天 + 省略号行 + 末一天，每天 6 行（4 小时一段）。
%               列：A 日期 | B 时间段 | C 充电量 | D 放电量 | E 时刻 | F 储电量。
%               其中 E/F 只在每天第 1、2 行有标签 0 与 24:00 ⇒ 只填两个储电量点。
%   紧急购电量  【只给了样例】9 行：2 天 + 省略号行 + 1 天，每天 3 行。
%               列：A 日期 | B 购电时间段 | C 购电量。连续时段要合并成一个区间。
%   ⇒ 后两张表必须由本脚本铺满 334 天（或全部紧急购电段），并清掉模板的省略号行。
%
% ------------------------------------------------------------
% ★「调整购电量」这张表填什么（本问最容易填错的一处）
%
%   填【调整之后的最终购电量 A_t】，不是填增量 (A_t − G_t)。依据是题面自己的措辞：
%       「计划购电量高于调整购电量的部分，违约电价是…50%」
%       「调整购电量高于计划购电量的部分，超出部分的电价是…1.5 倍」
%   两句话把「计划购电量」与「调整购电量」并列比较，二者显然同为【购电量本身】，
%   故 A_t 是 6/12/18 时刻确定下来的、当日最终执行的购电量。
%
%   两张表的 EP/EQ 列：
%       表 1 计划购电量  EP = Σ G_t·dt（全天计划购电量）  EQ = 计划购电费用
%       表 2 调整购电量  EP = Σ A_t·dt（全天调整后购电量）EQ = 调整购电量的相关费用
%   后者正是题面「总购电费用 = 计划购电费用 + 紧急购电费用 + 调整购电量的相关费用」
%   里的第三块，即 Σ p_t·dt·[0.5(G_t−A_t)^+ + 1.5(A_t−G_t)^+]（恒非负）。
%   ⇒ 当日购电总费用 = 表1 EQ + 表2 EQ + 表4 的紧急购电费。
%   ⚠️ EP 与 EQ 在这张表里【不是同一个量】：EP 是按调整后电量合计，EQ 是调整带来的
%      相关费用（含违约与超量惩罚）。已在 result3_填写说明.txt 中显式说明。
%
% 单位：全部为 kWh（能量），与题目附件5「单位：kWh」一致，即功率值 x dt。
%
% 口径 6（positional）：模板标签整体错位一个槽（0:00-0:10 整条不存在，末尾多出
%   0:00-0:10+1）。本脚本【不改模板标签】，模板第 i 个数据列直接写本队第 i 个时段，
%   与队友 Q1 的 result1、本队 Q2 的 result2 处理方式一致。
%
% 用法：outFile = q3_export_result3(R, qc, D, F)

if nargin < 3 || isempty(D)
    D = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码\out\data.mat').D;
end
if nargin < 2 || isempty(qc), qc = q3_config(); end
if nargin < 1 || isempty(R)
    R = load([qc.outdir 'q3_solution.mat']).R;
end
if nargin < 4 || isempty(F)
    fcFile = [qc.outdir 'q3_forecast.mat'];
    if isfile(fcFile), F = load(fcFile).F; else, F = q3_forecast(D, qc); end
end

if ~isfolder(qc.outdir), mkdir(qc.outdir); end
outFile = qc.resFile;
assert(isfile(qc.tplFile), '找不到模板：%s', qc.tplFile);
copyfile(qc.tplFile, outFile, 'f');
fprintf('  已复制模板 -> %s\n', outFile);

nd  = numel(R.date);
nT  = size(R.G, 2);                % 144
dt  = qc.dt;
pr  = R.price;                     % nd×144

Gk = R.G * dt;                     % kWh
Ak = R.A * dt;                     % kWh

%% ==================== 工作表 1：计划购电量 ====================
writematrix(Gk, outFile, 'Sheet', '计划购电量', 'Range', 'B2');
writematrix(sum(Gk, 2), outFile, 'Sheet', '计划购电量', 'Range', 'EP2');
writematrix(R.costPlan,  outFile, 'Sheet', '计划购电量', 'Range', 'EQ2');
fprintf('  [计划购电量] 已写 %d 天 x %d 时段 + 全天购电量/购电费\n', nd, nT);

%% ==================== 工作表 2：调整购电量 ====================
writematrix(Ak, outFile, 'Sheet', '调整购电量', 'Range', 'B2');
writematrix(sum(Ak, 2), outFile, 'Sheet', '调整购电量', 'Range', 'EP2');
writematrix(R.costAdj,  outFile, 'Sheet', '调整购电量', 'Range', 'EQ2');
fprintf('  [调整购电量] 已写 %d 天 x %d 时段 + 全天调整后电量/调整购电费\n', nd, nT);

%% ==================== 工作表 3：充放电量 ====================
blkName = {'0:00-4:00','4:00-8:00','8:00-12:00','12:00-16:00','16:00-20:00','20:00-24:00'};
nb  = numel(blkName);                       % 6
seg = nT / nb;                              % 每段 24 个 10 分钟槽
C2  = cell(1 + nd*nb, 6);
C2(1, :) = {'日期','时间段','充电量','放电量','时刻','储电量'};
for k = 1:nd
    r0 = 1 + (k-1)*nb;
    C2{r0+1, 1} = R.date(k);               % 每天第 1 行写日期
    for b = 1:nb
        r   = r0 + b;
        idx = (b-1)*seg + (1:seg);
        C2{r, 2} = blkName{b};
        C2{r, 3} = sum(R.C(k, idx)) * dt;  % 充电量 kWh
        C2{r, 4} = sum(R.D(k, idx)) * dt;  % 放电量 kWh
    end
    % 时刻 / 储电量：模板只在每天前两行给标签
    % ⚠️ R.Soc(k,t) 是【第 t 个时段末】的储电量，故 0:00 处应取 S_0 本身，
    %    不能写 R.Soc(k,1)（那是 0:10 的值）。24:00 处才是 R.Soc(k,144)。
    C2{r0+1, 5} = '0';
    C2{r0+2, 5} = '24:00';
    C2{r0+1, 6} = qc.S0;                   % 0:00 储电量（= 6000，口径 2）
    C2{r0+2, 6} = R.Soc(k, nT);            % 24:00 储电量（= 6000，口径 2）
end
writecell(C2, outFile, 'Sheet', '充放电量', 'Range', 'A1');
fprintf('  [充放电量] 已写 %d 行（%d 天 x %d 段）\n', size(C2,1), nd, nb);

%% ==================== 工作表 4：紧急购电量 ====================
rows = {'日期','购电时间段','购电量'};
nSegTot = 0; qSegTot = 0;
for k = 1:nd
    e = R.gEm(k, :) * dt;                  % kWh，144
    m = e > 1e-9;
    if ~any(m), continue; end
    d2 = diff([0 m 0]);
    s  = find(d2 == 1);  t2 = find(d2 == -1) - 1;   % 各连续段的起止槽号
    for z = 1:numel(s)
        q = sum(e(s(z):t2(z)));
        rows(end+1, :) = {R.date(k), ...
            sprintf('%s-%s', mm2lab((s(z)-1)*10), mm2lab(t2(z)*10)), q}; %#ok<AGROW>
        nSegTot = nSegTot + 1;  qSegTot = qSegTot + q;
    end
end
writecell(rows, outFile, 'Sheet', '紧急购电量', 'Range', 'A1');
fprintf('  [紧急购电量] 已写 %d 个区间，合计 %.1f kWh\n', nSegTot, qSegTot);

%% ==================== 口径说明（随结果落盘） ====================
nAdjSlot = sum(sum(abs(R.A - R.G) > 1e-9));
txt = { ...
 'result3.xlsx 生成说明（口径与计量约定）'; ...
 '=========================================================='; ...
 sprintf('生成时间：%s', datestr(now, 'yyyy-mm-dd HH:MM:SS')); ...
 sprintf('求解区间：%s ~ %s，共 %d 天', string(R.date(1)), string(R.date(end)), nd); ...
 ''; ...
 '【单位】四张工作表全部为 kWh（能量），与题目附件5「单位：kWh」一致。'; ...
 sprintf('        即：屏幕上的功率值 × dt（dt = %g h）。', dt); ...
 ''; ...
 '【调整购电量表的填法】表 2 的时段格填【调整后的最终购电量 A_t】，不是增量。'; ...
 '        依据题面「计划购电量高于调整购电量的部分…」「调整购电量高于计划购电量的'; ...
 '        部分…」把二者并列比较，可知 A_t 本身是购电量而非差额。'; ...
 sprintf('        表 1 EP/EQ = 计划购电量 Σ G_t·dt / 计划购电费用（元）'); ...
 sprintf('        表 2 EP/EQ = 调整后购电量 Σ A_t·dt / 调整购电量的相关费用（元，恒非负）'); ...
 '        注意表 2 的 EP 与 EQ 不是同一个量：EP 是调整后的全天电量合计，'; ...
 '        EQ 是调整这一动作本身带来的费用 Σ p·dt·[0.5(G−A)⁺ + 1.5(A−G)⁺]。'; ...
 sprintf('        当日购电总费用 = 表1 EQ + 表2 EQ + 表4 的紧急购电费。'); ...
 ''; ...
 '【口径 2 日末储电量】每天 0:00 与 24:00 储电量均为 6000 kWh（S_0 = S_144 = 6000）。'; ...
 '        与问题一/问题二一致，保证四问可比。放开日末闭环的对照见 t_q3_term_policy.m。'; ...
 ''; ...
 '【口径 3 结算粒度】逐 10 分钟：逐时段比较 A_t 与 G_t。全天总量口径的敏感性见'; ...
 '        t_q3_granularity.m。'; ...
 ''; ...
 '【口径 6 模板填充】positional。官方模板的 144 个时段标签整体错位一个槽'; ...
 '        （0:00-0:10 整条标签不存在，末尾多出 0:00-0:10+1）。'; ...
 '        本文件【不改模板标签】，模板第 i 个数据列写本队第 i 个时段（0:00-0:10 起），'; ...
 '        与队友问题一 result1、本队问题二 result2 的处理方式完全一致。'; ...
 ''; ...
 '【口径 7 信息集】光伏用附件3 官方预报（本问题面给出）；负载无官方预报，'; ...
 '        仍用自预测（与问题二同一套方法），这构成本问调整能力的天然上限。'; ...
 ''; ...
 sprintf('【数据核对】计划购电量合计 %14.1f kWh，计划购电费合计 %14.2f 元', ...
     R.summary.qPlanTot, R.summary.costPlanTot); ...
 sprintf('            调整后购电量合计 %13.1f kWh，调整购电费合计 %13.2f 元', ...
     R.summary.qAdjTot, R.summary.costAdjTot); ...
 sprintf('            紧急购电量合计   %13.1f kWh，紧急购电费合计 %13.2f 元（发生 %d 天）', ...
     R.summary.qEmTot, R.summary.costEmTot, R.summary.nDayEm); ...
 sprintf('            当日购电总费用合计 %35.2f 元', R.summary.costTot); ...
 ''; ...
 sprintf('【模型对照】若不使用 6/12/18 的调整机制（只按 0:00 计划执行），费用为 %.2f 元；', ...
     R.summary.costNoAdjTot); ...
 sprintf('            本模型 4 阶段滚动调整为 %.2f 元，共省 %.2f 元（%.3f%%）。', ...
     R.summary.costTot, R.summary.costNoAdjTot - R.summary.costTot, ...
     100*(R.summary.costNoAdjTot - R.summary.costTot)/R.summary.costNoAdjTot); ...
 sprintf('            其中「只调整购电量、不重排充放电」贡献 %.2f 元，', ...
     R.summary.costNoAdjTot - R.summary.costAdjOnlyTot); ...
 sprintf('            「用新信息重排余下时段充放电」贡献 %.2f 元。', ...
     R.summary.costAdjOnlyTot - R.summary.costTot); ...
 sprintf('            实际被调整的时段共 %d 个（占 6:00 之后时段 %d 个的 %.2f%%）。', ...
     nAdjSlot, sum(sum(isfinite(R.AgLo))), 100*nAdjSlot/sum(sum(isfinite(R.AgLo)))); ...
 };
fid = fopen([qc.outdir 'result3_填写说明.txt'], 'w', 'n', 'UTF-8');
fprintf(fid, '%s\n', strjoin(txt, sprintf('\n')));
fclose(fid);
fprintf('  已生成：%s\n', [qc.outdir 'result3_填写说明.txt']);
fprintf('导出完成：%s\n', outFile);
end

% ======================================================================
function s = mm2lab(minute)
% 把「距 0:00 的分钟数」格式化为表 4 风格的时刻标签（13:00 / 13:30 / 24:00）
h = floor(minute/60);  mi = mod(minute, 60);
if h >= 24
    s = '24:00';
else
    s = sprintf('%d:%02d', h, mi);
end
end
