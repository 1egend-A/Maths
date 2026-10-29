function outFile = q2_export_result2(R, qc, D)
% Q2_EXPORT_RESULT2  把问题二求解结果填进官方 result2.xlsx 模板
%
% 模板实况（t_probe_r2.m / t_probe_r2b.m 实测，附件5/result2.xlsx）：
%   计划购电量  335 行 x 147 列：R1 表头；R2..R335 = 334 天（2025-02-01..12-31）；
%               A 列日期【模板已填】；B..EO(2..145) = 144 个 10 分钟时段；
%               EP(146) = 全天购电量；EQ(147) = 全天购电费。
%   充放电量    【只给了样例】20 行：首两天 + 省略号行 + 末一天，每天 6 行（4 小时一段）。
%               列：A 日期 | B 时间段 | C 充电量 | D 放电量 | E 时刻 | F 储电量。
%               其中 E/F 只在每天第 1、2 行有标签 0 与 24:00 ⇒ 只填两个储电量点。
%   紧急购电量  【只给了样例】9 行：2 天 + 省略号行 + 1 天，每天 3 行。
%               列：A 日期 | B 购电时间段 | C 购电量。按表 4 示例，连续时段要合并。
%   ⇒ 后两张表必须由本脚本铺满 334 天（或全部紧急购电段），并清掉模板的省略号行。
%
% 单位：全部为 kWh（能量）。与队友 q1_export_result1.m 的 sol.grid_kWh 口径一致，
%       即「屏幕上的功率值 x dt」。（题目附件5 明写「单位：kWh」。）
%
% 口径 6（positional）：模板标签整体错位一个槽（0:00-0:10 整条不存在，末尾多出
%   0:00-0:10+1）。本脚本【不改模板标签】，模板第 i 个数据列直接写本队第 i 个时段，
%   与队友 Q1 的 result1 处理方式一致。
%
% 费用口径：EP/EQ 与表 1 的「全天购电量/全天购电费」只计【计划购电量】及其费用；
%   紧急购电量与紧急购电费按题目要求另表给出（表 3 / 紧急购电量 工作表）。
%
% 用法：outFile = q2_export_result2(R, qc, D)

if nargin < 3 || isempty(D)
    D = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码\out\data.mat').D;
end
if nargin < 2 || isempty(qc), qc = q2_config(); end
if nargin < 1 || isempty(R)
    R = load([qc.outdir 'q2_solution.mat']).R;
end

if ~isfolder(qc.outdir), mkdir(qc.outdir); end
outFile = qc.resFile;
assert(isfile(qc.tplFile), '找不到模板：%s', qc.tplFile);
copyfile(qc.tplFile, outFile, 'f');
fprintf('  已复制模板 -> %s\n', outFile);

nd  = numel(R.date);
nT  = size(R.gPlan, 2);            % 144
dt  = qc.dt;
pr  = D.day144.price(:)';          % 元/kWh，逐日相同

%% ==================== 工作表 1：计划购电量 ====================
% B2:EO335 —— 334 x 144，单位 kWh
M = R.gPlan * dt;
writematrix(M, outFile, 'Sheet', '计划购电量', 'Range', 'B2');
% EP = 全天购电量（kWh）；EQ = 全天购电费（元，仅计划部分）
writematrix(sum(M, 2), outFile, 'Sheet', '计划购电量', 'Range', 'EP2');
writematrix(R.costPlan, outFile, 'Sheet', '计划购电量', 'Range', 'EQ2');
fprintf('  [计划购电量] 已写 %d 天 x %d 时段 + 全天购电量/购电费\n', nd, nT);

%% ==================== 工作表 2：充放电量 ====================
% 1 表头 + 334 天 x 6 行 = 2005 行
blkName = {'0:00-4:00','4:00-8:00','8:00-12:00','12:00-16:00','16:00-20:00','20:00-24:00'};
nb = numel(blkName);                       % 6
C2 = cell(1 + nd*nb, 6);
C2(1, :) = {'日期','时间段','充电量','放电量','时刻','储电量'};
seg = nT / nb;                             % 24 个 10 分钟时段 / 段
for k = 1:nd
    r0 = 1 + (k-1)*nb;
    C2{r0+1, 1} = R.date(k);               % 每天第 1 行写日期
    for b = 1:nb
        r = r0 + b;
        C2{r, 2} = blkName{b};
        idx = (b-1)*seg + (1:seg);
        C2{r, 3} = sum(R.c(k, idx)) * dt;  % 充电量 kWh
        C2{r, 4} = sum(R.d(k, idx)) * dt;  % 放电量 kWh
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

%% ==================== 工作表 3：紧急购电量 ====================
% 按表 4 示例：连续时段合并成一个区间；电量取该区间内各时段之和（kWh）
rows = {'日期','购电时间段','购电量'};
nSegTot = 0; qSegTot = 0;
for k = 1:nd
    e = R.gEm(k, :) * dt;                  % kWh，144
    m = e > 1e-9;
    if ~any(m), continue; end
    d2 = diff([0 m 0]);
    s = find(d2 == 1);  t2 = find(d2 == -1) - 1;   % 各连续段的起止时段号
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
txt = { ...
 'result2.xlsx 生成说明（口径与计量约定）'; ...
 '=========================================================='; ...
 sprintf('生成时间：%s', datestr(now, 'yyyy-mm-dd HH:MM:SS')); ...
 sprintf('求解区间：%s ~ %s，共 %d 天', string(R.date(1)), string(R.date(end)), nd); ...
 ''; ...
 '【单位】三张工作表全部为 kWh（能量），与题目附件5「单位：kWh」一致。'; ...
 '        即：屏幕上的功率值 × dt（dt = 1/6 h）。'; ...
 ''; ...
 '【口径 7 信息集】严格字面——只用附件1（电价）+ 附件2（负载/光伏实际）。'; ...
 '        题目问题2 原文只引用附件1、附件2，未引用附件3；且附件3 只有光伏预报、'; ...
 '        无负载预报。故本问的负载与光伏均由历史自行预测（方法见论文 7.1）。'; ...
 ''; ...
 '【口径 2 日末储电量】每天 0:00 与 24:00 储电量均为 6000 kWh（S_0 = S_144 = 6000）。'; ...
 '        理由：与问题一题面要求一致；逐日电价相同 ⇒ 跨日搬运储能的边际价值为零；'; ...
 '        闭环使每日计划自洽，无需先解 1 月来倒推起始 SOC。'; ...
 ''; ...
 '【口径 6 模板填充】positional。官方模板的 144 个时段标签整体错位一个槽'; ...
 '        （0:00-0:10 整条标签不存在，末尾多出 0:00-0:10+1）。'; ...
 '        本文件【不改模板标签】，模板第 i 个数据列写本队第 i 个时段（0:00-0:10 起），'; ...
 '        与队友问题一 result1 的处理方式完全一致。'; ...
 '        论文表格使用《题目》的表 1 标签（10:00-10:10 等区间形式）。'; ...
 ''; ...
 '【费用口径】EP「全天购电量」与 EQ「全天购电费」只计【计划购电量】及其费用：'; ...
 '        EQ = Σ_t p_t · g_t · dt。紧急购电量与紧急购电费按题目要求另表给出'; ...
 '        （紧急购电量 工作表 / 论文表 3），其电价为交易时刻电价的 5 倍。'; ...
 '        当日总购电费 = EQ + 紧急购电费。'; ...
 ''; ...
 sprintf('【数据核对】计划购电量合计 %.1f kWh，计划购电费合计 %.2f 元', ...
     R.summary.qPlanTot, R.summary.costPlanTot); ...
 sprintf('            紧急购电量合计 %.1f kWh，紧急购电费合计 %.2f 元', ...
     R.summary.qEmTot, R.summary.costEmTot); ...
 sprintf('            当日总购电费合计 %.2f 元（发生紧急购电 %d 天）', ...
     R.summary.costTot, R.summary.nDayEm); ...
 };
fid = fopen([qc.outdir 'result2_填写说明.txt'], 'w', 'n', 'UTF-8');
fprintf(fid, '%s\n', strjoin(txt, sprintf('\n')));
fclose(fid);
fprintf('  已生成：%s\n', [qc.outdir 'result2_填写说明.txt']);
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
