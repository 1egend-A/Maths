function outFiles = q4_export_result4(R2, R3, qc, D)
% Q4_EXPORT_RESULT4  把问题四的两套结果分别填进官方 result4-2.xlsx / result4-3.xlsx
%
% 模板实况（probe_a5.m 实测，附件5）：
%   result4-2.xlsx  3 张表：计划购电量 | 充放电量 | 紧急购电量
%       —— 与 result2.xlsx【完全同构】，即问题二框架 + 附件4 逐日电价
%   result4-3.xlsx  4 张表：计划购电量 | 调整购电量 | 充放电量 | 紧急购电量
%       —— 与 result3.xlsx【完全同构】，即问题三框架 + 附件4 逐日电价
%   两张模板的「计划购电量」都是 335 行 × 147 列（144 时段 + 全天购电量 + 全天购电费），
%   「充放电量」与「紧急购电量」只给样例行 ⇒ 必须由本脚本铺满并覆盖掉模板的省略号行。
%
% 单位：全部 kWh（能量），与附件5「单位：kWh」一致，即功率值 × dt。
%
% 口径 6（positional）与口径 2（日末 SOC = 6000）与 Q1/Q2/Q3 完全一致，
% 保证四问的 result 文件横向可比。理由见各问的 *_填写说明.txt。
%
% 用法：
%   outFiles = q4_export_result4(R2, R3, qc, D);   % 两套都写
%   outFiles = q4_export_result4(R2, [], qc, D);   % 只写 result4-2

if nargin < 4 || isempty(D)
    D = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码\out\data.mat').D;
end
if nargin < 3 || isempty(qc), qc = q4_config(); end

outFiles = {};
if nargin >= 1 && ~isempty(R2), outFiles{end+1} = exportOne(R2, qc, qc.tplFile2, qc.resFile2, 'result4-2', false, D); end
if nargin >= 2 && ~isempty(R3), outFiles{end+1} = exportOne(R3, qc, qc.tplFile,  qc.resFile3, 'result4-3', true,  D); end
end

% ======================================================================
function outFile = exportOne(R, qc, tplFile, outFile, tag, hasAdj, D)
% 写一个 result 文件。hasAdj 决定是否包含「调整购电量」工作表（4-3 有、4-2 无）。
% D 用于在填写说明里【现场计算】电价口径的数字（不可硬编码，见 notesFor）。

outDir = fileparts(outFile);
if ~isfolder(outDir), mkdir(outDir); end
assert(isfile(tplFile), '找不到模板：%s', tplFile);
copyfile(tplFile, outFile, 'f');
fprintf('  已复制模板 %s -> %s\n', tplFile, outFile);

nd  = numel(R.date);
% ⚠️ P2 框架的结果里计划量叫 gPlan、没有 G 字段（G/A 是 Q3 滚动框架的命名）。
%    曾直接写 size(R.G,2)，导出 result4-2 时报「无法识别的字段名称 "G"」而中断。
if hasAdj
    nT = size(R.G, 2);             % Q3 滚动框架
else
    nT = size(R.gPlan, 2);         % Q2 框架
end
dt  = qc.dt;

if hasAdj
    Gk = R.G * dt;  Ak = R.A * dt;
else
    Gk = R.gPlan * dt;  Ak = [];
end

%% 工作表 1：计划购电量
writematrix(Gk, outFile, 'Sheet', '计划购电量', 'Range', 'B2');
writematrix(sum(Gk, 2), outFile, 'Sheet', '计划购电量', 'Range', 'EP2');
writematrix(R.costPlan, outFile, 'Sheet', '计划购电量', 'Range', 'EQ2');
fprintf('  [计划购电量] 已写 %d 天 x %d 时段 + 全天购电量/购电费\n', nd, nT);

%% 工作表 2：调整购电量（仅 4-3）
if hasAdj
    writematrix(Ak, outFile, 'Sheet', '调整购电量', 'Range', 'B2');
    writematrix(sum(Ak, 2), outFile, 'Sheet', '调整购电量', 'Range', 'EP2');
    writematrix(R.costAdj, outFile, 'Sheet', '调整购电量', 'Range', 'EQ2');
    fprintf('  [调整购电量] 已写 %d 天 x %d 时段 + 全天调整后电量/调整购电费\n', nd, nT);
end

%% 工作表：充放电量
blkName = {'0:00-4:00','4:00-8:00','8:00-12:00','12:00-16:00','16:00-20:00','20:00-24:00'};
nb  = numel(blkName);                       % 6
seg = nT / nb;                              % 每段 24 个 10 分钟槽
% ⚠️ 充放电字段的命名在两套框架里不同：
%      Q2 框架（q2_solve / q4_solve_p2）用小写 R.c / R.d
%      Q3 滚动框架（q3_solve）用大写 R.C / R.D（因为 c/d 在同文件里被用作阶段变量名）
%    曾只写 R.c，导出 result4-3 时会报「无法识别的字段名称 'c'」。
if hasAdj
    Cf = R.C;  Df = R.D;
else
    Cf = R.c;  Df = R.d;
end
C2  = cell(1 + nd*nb, 6);
C2(1, :) = {'日期','时间段','充电量','放电量','时刻','储电量'};
for k = 1:nd
    r0 = 1 + (k-1)*nb;
    C2{r0+1, 1} = R.date(k);
    for b = 1:nb
        r   = r0 + b;
        idx = (b-1)*seg + (1:seg);
        C2{r, 2} = blkName{b};
        C2{r, 3} = sum(Cf(k, idx)) * dt;    % 充电量 kWh
        C2{r, 4} = sum(Df(k, idx)) * dt;    % 放电量 kWh
    end
    % ⚠️ R.Soc(k,t) 是【第 t 个时段末】的储电量 ⇒ 0:00 处写 S_0 本身，不是 R.Soc(k,1)。
    C2{r0+1, 5} = '0';
    C2{r0+2, 5} = '24:00';
    C2{r0+1, 6} = qc.S0;
    C2{r0+2, 6} = R.Soc(k, nT);
end
writecell(C2, outFile, 'Sheet', '充放电量', 'Range', 'A1');
fprintf('  [充放电量] 已写 %d 行（%d 天 x %d 段）\n', size(C2,1), nd, nb);

%% 工作表：紧急购电量（连续时段合并）
rows = {'日期','购电时间段','购电量'};
nSegTot = 0; qSegTot = 0;
for k = 1:nd
    e = R.gEm(k, :) * dt;                  % kWh
    m = e > 1e-9;
    if ~any(m), continue; end
    d2 = diff([0 m 0]);
    s  = find(d2 == 1);  t2 = find(d2 == -1) - 1;
    for z = 1:numel(s)
        q = sum(e(s(z):t2(z)));
        rows(end+1, :) = {R.date(k), ...
            sprintf('%s-%s', mm2lab((s(z)-1)*10), mm2lab(t2(z)*10)), q}; %#ok<AGROW>
        nSegTot = nSegTot + 1;  qSegTot = qSegTot + q;
    end
end
writecell(rows, outFile, 'Sheet', '紧急购电量', 'Range', 'A1');
fprintf('  [紧急购电量] 已写 %d 个区间，合计 %.1f kWh\n', nSegTot, qSegTot);

%% 口径说明
txtFile = fullfile(outDir, [tag '_填写说明.txt']);
fid = fopen(txtFile, 'w', 'n', 'UTF-8');
fprintf(fid, '%s\n', strjoin(notesFor(R, qc, tag, hasAdj, nSegTot, qSegTot, D), sprintf('\n')));
fclose(fid);
fprintf('  已生成：%s\n', txtFile);
fprintf('导出完成：%s\n', outFile);
end

% ======================================================================
function txt = notesFor(R, qc, tag, hasAdj, nSeg, qSeg, D)
% ⚠️ 电价口径的一切数字都在这里【现场算出】，不得硬编码。
%    曾经硬编码过「max|附件1 − 年内均值| = 5.2e-5」，实测真值是 3.065e-2 元/kWh
%    （相差 600 倍）——那个数来自一次口径不同的早期探查，与本节的定义并非同一件事。
%    本文件随 result4-*.xlsx 一同交付，写错即交付错误，故一律由数据现算。

% 附件1 剖面 vs 附件4 在本求解区间上的逐槽均值
pA1  = D.day144.price(:)';
pM4  = mean(R.price, 1);
dPro = max(abs(pA1 - pM4));
% 峰谷比
rt4  = max(R.price(:)) / min(R.price(:));
rt1  = max(pA1) / min(pA1);
% 近零价计数（本求解区间的全部报价点）
pAll = R.price(:);
n05  = sum(pAll < 0.05);  n10 = sum(pAll < 0.10);
sd4  = std(pAll);         sd1 = std(pA1);

txt = { ...
 sprintf('%s.xlsx 生成说明（口径与计量约定）', tag); ...
 '=========================================================='; ...
 sprintf('生成时间：%s', datestr(now, 'yyyy-mm-dd HH:MM:SS')); ...
 sprintf('求解区间：%s ~ %s，共 %d 天', string(R.date(1)), string(R.date(end)), numel(R.date)); ...
 ''; ...
 '【电价来源】附件4 逐日逐时段实测电价（本问相对问题二/三的唯一输入差异）。'; ...
 '        问题二/三用附件1 的 144 段典型日报价（逐日相同）；问题四用附件4 的'; ...
 '        逐日实测电价。两者不是同一个电价，实测对比（本求解区间内现算）：'; ...
 sprintf('          附件1 剖面 vs 附件4 逐槽均值：max|差| = %.4g 元/kWh', dPro); ...
 sprintf('          峰谷比：附件4 %.1f 倍  vs  附件1 %.2f 倍', rt4, rt1); ...
 sprintf('          报价点标准差：附件4 %.4f  vs  附件1 %.4f 元/kWh', sd4, sd1); ...
 sprintf('          近零价报价点：< 0.05 元/kWh 共 %d 个，< 0.10 共 %d 个（附件1 为 0 个）', n05, n10); ...
 '        故问题四不是「问题二换个价格串」，而是「典型日 → 逐日实际」的口径切换。'; ...
 ''; ...
 '【信息结构】两条保底结果分别对应两种信息结构：'; ...
 '        result4-2 = 问题二框架：无附件3 预报，负载与光伏均自预测（口径 7 严格字面）；'; ...
 '        result4-3 = 问题三框架：附件3 官方光伏预报 + 自预测负载，并在 6/12/18 三次调整。'; ...
 '        两者共用同一套求解内核（result4-3 直接调用 问题三/code/q3_solve.m），'; ...
 '        故差异只来自信息结构，不含实现差异。'; ...
 ''; ...
 '【单位】全部工作表为 kWh（能量），与附件5「单位：kWh」一致，即功率值 × dt。'; ...
 ''; ...
 '【口径 2 日末储电量】每天 0:00 与 24:00 储电量均为 6000 kWh（S_0 = S_144 = 6000）。'; ...
 '        与问题一/二/三一致保证四问可比。⚠️ 该口径在问题四的代价【远大于】问题二/三：'; ...
 '        逐日电价不同 ⇒ 跨日搬运储能存在真实价差，放开日末闭环的收益见 t_q4_term_policy.m。'; ...
 ''; ...
 '【口径 6 模板填充】positional。官方模板的 144 个时段标签整体错位一个槽'; ...
 '        （0:00-0:10 整条标签不存在，末尾多出 0:00-0:10+1）。'; ...
 '        本文件【不改模板标签】，模板第 i 个数据列写本队第 i 个时段（0:00-0:10 起），'; ...
 '        与问题一 result1、问题二 result2、问题三 result3 处理方式完全一致。'; ...
};
if hasAdj
    txt = [txt; {
     ''; ...
     '【调整购电量表的填法】表 2 的时段格填【调整后的最终购电量 A_t】，不是增量。'; ...
     '        依据题面「计划购电量高于调整购电量的部分…」「调整购电量高于计划购电量的'; ...
     '        部分…」把二者并列比较，可知 A_t 本身是购电量而非差额。'; ...
     '        表 1 EP/EQ = 计划购电量 Σ G_t·dt / 计划购电费用（元）'; ...
     '        表 2 EP/EQ = 调整后购电量 Σ A_t·dt / 调整购电量的相关费用（元，恒非负）'; ...
     '        ⚠️ 表 2 的 EP 与 EQ 不是同一个量：EP 是调整后的全天电量合计，'; ...
     '           EQ 是调整这一动作带来的费用 Σ p·dt·[0.5(G−A)⁺ + 1.5(A−G)⁺]。'; ...
     '        当日购电总费用 = 表1 EQ + 表2 EQ + 紧急购电费。'; ...
    }];
end
txt = [txt; {
 sprintf('【数据核对】计划购电量合计 %14.1f kWh，计划购电费合计 %14.2f 元', ...
     R.summary.qPlanTot, R.summary.costPlanTot); ...
 sprintf('            紧急购电量合计 %14.1f kWh（%d 个区间），紧急购电费合计 %12.2f 元', ...
     qSeg, nSeg, R.summary.costEmTot); ...
 sprintf('            当日购电总费用合计 %35.2f 元', R.summary.costTot); ...
}];
if hasAdj
    txt = [txt; {
     sprintf('            调整后购电量合计 %12.1f kWh，调整购电费合计 %12.2f 元', ...
         R.summary.qAdjTot, R.summary.costAdjTot); ...
     ''; ...
     sprintf('【模型对照】不使用 6/12/18 调整（只按 0:00 计划执行）费用为 %.2f 元；', ...
         R.summary.costNoAdjTot); ...
     sprintf('            四阶段滚动调整后为 %.2f 元，共省 %.2f 元（%.3f%%）。', ...
         R.summary.costTot, R.summary.costNoAdjTot - R.summary.costTot, ...
         100*(R.summary.costNoAdjTot - R.summary.costTot)/R.summary.costNoAdjTot); ...
    }];
end
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
