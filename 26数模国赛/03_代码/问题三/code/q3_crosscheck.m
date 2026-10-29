function ok = q3_crosscheck()
% Q3_CROSSCHECK  交叉校验：只读 out/result3.xlsx 与原始数据，不看任何求解代码
%
% 目的：q3_validate.m 用的是求解器的工作区对象（R / F）。万一 q3_solve 与 F 的
%       接口约定有偏差，验证会跟着一起错。本脚本刻意绕开全部中间产物，只从
%       【已落盘的交付文件】出发重新推导：
%
%           result3.xlsx（4 张表） + data.mat（实际负载/光伏/电价） → 结论
%
% ------------------------------------------------------------
% 交付文件能支持到什么程度（先说清楚边界，免得把"没查"当成"查过了"）
%
%   可以逐槽复算的：计划购电量 G_t、调整购电量 A_t、电价 p_t、实际净负荷。
%   只给合计数量的：充放电量（每天 6 个 4 小时段的充电/放电合计 + 首末储电量）、
%                   紧急购电量（每天若干个合并区间 + 每区间电量合计）。
%
%   因此：
%     · 逐槽能量平衡与逐槽弃电，只能由 q3_validate.m 的 B 层负责（它手上有 R）；
%     · 本脚本改为核【逐日总量】平衡——把三张表各自的日合计拼起来，仍然是一条
%       独立的、非平凡的能量守恒式（见第 4 节），只是粒度从 10 分钟降到 1 天；
%     · 紧急购电费无法精确重算：区间内各槽电价不同，区间电量合计还原不出分段
%       价格。故只给区间价格带 [5·q·min p, 5·q·max p] 并核总费用落在带内。
%       逐槽精确值同样由 q3_validate.m 的 C3 负责。
%
% 用法：ok = q3_crosscheck()

BASE = 'D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\';
RES  = [BASE '问题三\out\result3.xlsx'];
TXT  = [BASE '问题三\out\result3_填写说明.txt'];
lines = {};

    function say(varargin)
        lines{end+1} = sprintf(varargin{:});
    end

say('==========================================================');
say(' 问题三 result3.xlsx 交叉校验（不读求解代码）');
say('==========================================================');
assert(isfile(RES), '找不到 %s，请先运行 q3_export_result3', RES);
assert(isfile(TXT), '找不到 %s，请先运行 q3_export_result3', TXT);

% ---------------- 读原始数据 ----------------
D  = load([BASE '数据预处理代码\out\data.mat']).D;
qc = q3_config();
nd = 334;  nT = 144;  dt = qc.dt;  eta = qc.eta;
DateList = D.actual.dates(32:365);
Nact = D.actual.load(32:365, :) - D.actual.pv(32:365, :);   % 净负荷 kW
PV   = D.actual.pv(32:365, :);
pr   = repmat(D.day144.price(:)', nd, 1);

%% ---------------- 1. 结构一致性 ----------------
say('');
say('---- 1. 结构一致性 ----');
tpl = qc.tplFile;
assert(isfile(tpl), '找不到官方模板：%s', tpl);
shGot = cellstr(sheetnames(RES));
shExp = cellstr(sheetnames(tpl));
okS1 = isequal(shGot, shExp);
say('1.1 工作表：%s', strjoin(shGot, ' | '));
say('    与官方模板一致   -> %s', pass(okS1));

Mp = readcell(RES, 'Sheet', '计划购电量');
Ma = readcell(RES, 'Sheet', '调整购电量');
okS2 = size(Mp,1) == nd+1 && size(Mp,2) == 147;
say('1.2 [计划购电量] %d 行 x %d 列（应为 %d x 147）   -> %s', ...
    size(Mp,1), size(Mp,2), nd+1, pass(okS2));
okS3 = size(Ma,1) == nd+1 && size(Ma,2) == 147;
say('1.3 [调整购电量] %d 行 x %d 列（应为 %d x 147）   -> %s', ...
    size(Ma,1), size(Ma,2), nd+1, pass(okS3));

Tp = readcell(tpl, 'Sheet', '计划购电量');
okDate = false;
try
    dGot = datetime([Mp{2:end,1}])';
    dTpl = datetime([Tp{2:end,1}])';
    okDate = numel(dGot) == nd && isequal(dGot, DateList) && isequal(dGot, dTpl);
catch ME
    say('    日期列读取失败：%s', ME.message);
end
say('1.4 日期列 = 2025-02-01 … 2025-12-31，与模板逐格一致   -> %s', pass(okDate));

G = cell2mat(Mp(2:end, 2:145));      % kWh
A = cell2mat(Ma(2:end, 2:145));      % kWh
EP1 = cell2mat(Mp(2:end, 146));  EQ1 = cell2mat(Mp(2:end, 147));
EP2 = cell2mat(Ma(2:end, 146));  EQ2 = cell2mat(Ma(2:end, 147));
okNum = all(isfinite(G(:))) && all(isfinite(A(:)));
say('1.5 时段块 334×144 全为有限值   -> %s', pass(okNum));

%% ---------------- 2. 购电量表的自洽性 ----------------
say('');
say('---- 2. 购电量表（两张，逐槽可复算）----');
okN1 = min(G(:)) >= -1e-9 && min(A(:)) >= -1e-9;
say('2.1 G、A 均非负（min G = %.3e，min A = %.3e kWh）   -> %s', ...
    min(G(:)), min(A(:)), pass(okN1));
nHead = 36;                                    % 0:00–6:00 的槽，任何调整都动不了
violH = sum(sum(abs(A(:,1:nHead) - G(:,1:nHead)) > 1e-6));
okN2 = violH == 0;
say('2.2 0:00–6:00 的 %d 个槽 A_t ≡ G_t（已执行不可调），违例 = %d   -> %s', ...
    nHead, violH, pass(okN2));
okN3 = max(max(abs(EP1 - sum(G,2)))) < 1e-6 && max(max(abs(EP2 - sum(A,2)))) < 1e-6;
say('2.3 两张表的 EP 列 = 该行时段之和   -> %s', pass(okN3));
okN4 = all(EQ1 >= -1e-6) && all(EQ2 >= -1e-6);
say('2.4 EQ 列（计划费 / 调整费）均非负   -> %s', pass(okN4));

%% ---------------- 3. 充放电量表与储能闭环 ----------------
say('');
say('---- 3. 充放电量表与储能闭环 ----');
Cd = readcell(RES, 'Sheet', '充放电量');
segN = nT/6;
Cblk = zeros(nd,6);  Dblk = zeros(nd,6);  soc0 = zeros(nd,1);  soc24 = zeros(nd,1);
for k = 1:nd
    r0 = 1 + (k-1)*6;
    Cblk(k,:) = cell2mat(Cd(r0+(1:6), 3))';
    Dblk(k,:) = cell2mat(Cd(r0+(1:6), 4))';
    soc0(k)  = Cd{r0+1, 6};
    soc24(k) = Cd{r0+2, 6};
end
okC1 = all(abs(soc0 - qc.S0) < 1e-9) && all(abs(soc24 - qc.S_end) < 1e-9);
say('3.1 334 天的 0:00 与 24:00 储电量均为 6000 kWh   -> %s', pass(okC1));
okC2 = all(Cblk(:) >= -1e-9) && all(Dblk(:) >= -1e-9);
say('3.2 各段充放电量非负   -> %s', pass(okC2));
mxBlk = max([max(Cblk(:)) max(Dblk(:))]) / 6;      % 4 小时段 → 平均功率 kW
okC3 = mxBlk <= qc.P_max + 1e-6;
say('3.3 各段平均功率 max = %.1f kW，上限 %g kW   -> %s', mxBlk, qc.P_max, pass(okC3));

% ★ 闭环恒等式：S_144 − S_0 = Σ(η·c − d/η)·dt = 0  ⇒  Σ d = η²·Σ c
oChg = sum(Cblk,2);  oDis = sum(Dblk,2);
resC = max(abs(oDis - eta^2 * oChg));
okC4 = resC < 1e-6;
say('3.4 逐日储能闭环 Σd = η²·Σc = %.4f·Σc：最大偏差 %.3e kWh   -> %s', ...
    eta^2, resC, pass(okC4));
say('      （日均充电 %.1f kWh、放电 %.1f kWh；η = %.2f，充放损耗 %.1f%%）', ...
    mean(oChg), mean(oDis), eta, 100*(1-eta^2));

%% ---------------- 4. 逐日总量能量平衡（三张表联合）----------------
say('');
say('---- 4. 逐日总量能量平衡 ----');
eDay = readcell(RES, 'Sheet', '紧急购电量');
eTotDay = zeros(nd,1);  segIdx = cell(nd,1);  nSeg = 0;
curDate = NaT;
for r = 2:size(eDay,1)
    dv = eDay{r,1};
    if isdatetime(dv), curDate = dv; end
    seg = eDay{r,2};
    if isa(seg,'missing') || isempty(seg), continue; end
    qv = eDay{r,3};
    if isa(qv,'missing') || ~isnumeric(qv), continue; end
    k = find(DateList == curDate, 1);
    assert(~isempty(k), '紧急购电量表出现未知日期：%s', string(curDate));
    [s1m, s2m] = parseSeg(char(seg));
    i1 = floor(s1m/10) + 1;  i2 = s2m/10;                 % 分钟 → 槽号（右端点约定）
    assert(i1 >= 1 && i2 <= nT && i1 <= i2, '区间越界：%s', char(seg));
    % ⚠️ 必须显式接两个输出：在矩阵字面量里写 priceRange(...) 只会取【第一个】输出，
    %    拼接结果只有 4 列，后面按 5/6 列取值就会"索引超出数组边界"。
    [pLo_, pHi_] = priceRange(pr(k,:), i1, i2);
    segIdx{k} = [segIdx{k}; i1, i2, qv, pLo_, pHi_]; %#ok<AGROW>
    eTotDay(k) = eTotDay(k) + qv;
    nSeg = nSeg + 1;
end
say('4.0 紧急购电表共 %d 个区间，覆盖 %d 天，合计 %.1f kWh', ...
    nSeg, sum(eTotDay > 1e-9), sum(eTotDay));

% 逐日：Σ(A+e)·dt + ΣD·dt − ΣNact·dt − ΣC·dt = 弃电 ≥ 0
lhs = sum(A,2)*1 + eTotDay + sum(Dblk,2) - sum(Nact,2)*dt - sum(Cblk,2);
% 注意 A 已是 kWh；Nact 是 kW 需 ×dt；Cblk/Dblk 已是 kWh
okD1 = min(lhs) > -1e-6;
say('4.1 逐日供能 ≥ 需求（弃电非负）：min 日残差 = %.4f kWh   -> %s', min(lhs), pass(okD1));
% ⚠️ 不能写成「逐日弃电 ≤ 该日光伏富余」：弃电还有第二个来源——按报童分位买进来的电，
%    实际用不完就回吐（以及日末回充必须放掉的部分）。正确的上界是
%        弃电 ≤ 该日光伏富余 + 该日购电量
%    （溢出的能量只能来自"太阳能/买来的电"，不可能凭空多出来）。
excessPV = sum(max(0, -Nact),2)*dt;      % 该日净负荷为负的时段所对应的光伏富余量
capDaily = excessPV + sum(A,2);          % 富余 + 当日购电（A 已是 kWh）
okD2 = all(lhs <= capDaily + 1e-6);
say('4.2 逐日弃电 ≤ 光伏富余 + 当日购电：超界天数 = %d   -> %s', ...
    sum(lhs > capDaily + 1e-6), pass(okD2));
nOver = sum(sum(lhs > excessPV + 1e-6));
say('     其中弃电超过光伏富余的天数 = %d / %d（超出部分即分位超买回吐，非光伏弃电）', ...
    nOver, nd);
qPvTot = sum(PV(:))*dt;
say('     全年：光伏发电 %.0f kWh | 弃电 %.0f kWh（占光伏 %.2f%%）', ...
    qPvTot, sum(lhs), 100*sum(lhs)/qPvTot);
say('           实际购电 %.0f kWh（计划 %.0f + 紧急 %.0f；调整后总量 %.0f）', ...
    sum(A(:)) + sum(eTotDay), sum(G(:)), sum(eTotDay), sum(A(:)));
say('     日均弃电 %.1f kWh/天，最大 %.1f kWh/天（%s）', ...
    mean(lhs), max(lhs), string(DateList(find(lhs == max(lhs), 1))));

%% ---------------- 5. 费用对账 ----------------
say('');
say('---- 5. 费用对账（从表里按定义重算）----');
% ⚠️ 这里【不再乘 dt】：本脚本的 G/A 是从 result3.xlsx 读出来的，已经是"每 10 分钟
%    电量（kWh）"而不是功率（kW）。q3_validate 里 R.A 是 kW 才需要乘 dt。
%    曾多乘一次 dt，费用正好小 1/dt = 6 倍（2,208,916 vs 13,253,499），对账必挂。
cPlan = sum(sum(pr .* min(G, A)));
cAdj  = sum(sum(pr .* (qc.kUnder*max(0,G-A) + qc.kOver*max(0,A-G))));
% 紧急购电费：区间内电价不唯一 ⇒ 只能给价格带
cEmLo = 0;  cEmHi = 0;
for k = 1:nd
    S = segIdx{k};
    for z = 1:size(S,1)
        pLo = S(z,4);  pHi = S(z,5);              % 该区间内 5p 的下界/上界（含 5 倍）
        cEmLo = cEmLo + S(z,3) * pLo;
        cEmHi = cEmHi + S(z,3) * pHi;
    end
end
say('5.1 计划购电费 = Σ p·dt·min(G,A)                 = %16.2f 元', cPlan);
say('5.2 调整购电费 = Σ p·dt·[0.5(G−A)⁺+1.5(A−G)⁺]   = %16.2f 元', cAdj);
say('5.3 紧急购电费 ∈ [%.2f, %.2f] 元（区间内电价不唯一，只给价格带）', cEmLo, cEmHi);

t = fileread(TXT);
rPlanQ = pick(t, '计划购电量合计\s*([\d\.]+)\s*kWh');
rPlanC = pick(t, '计划购电费合计\s*([\d\.]+)\s*元');
rAdjQ  = pick(t, '调整后购电量合计\s*([\d\.]+)\s*kWh');
rAdjC  = pick(t, '调整购电费合计\s*([\d\.]+)\s*元');
rEmQ   = pick(t, '紧急购电量合计\s*([\d\.]+)\s*kWh');
rEmC   = pick(t, '紧急购电费合计\s*([\d\.]+)\s*元');
rTot   = pick(t, '当日购电总费用合计\s*([\d\.]+)\s*元');

eP1 = abs(cPlan - rPlanC);   eP2 = abs(sum(G(:)) - rPlanQ);
eP3 = abs(cAdj  - rAdjC);    eP4 = abs(sum(A(:)) - rAdjQ);
eP5 = abs(sum(eTotDay) - rEmQ);
% ⚠️ 对账容差必须是【相对】的，不能用 1e-2 这种绝对阈值。
%    txt 里的合计是双精度全精度值，xlsx 里的数经过 Excel 的 15 位有效数字存储后回读，
%    天然带 ~1e-7 相对误差：实测三项差分别为 0.0033 / 0.034 / 0.045 kWh，对应
%    1.5e-10 / 1.6e-9 / 1.7e-7 的相对偏差——不是模型误差，是文件精度。
%    绝对 0.01 的阈值会把 0.045 kWh（≈ 1.4 kW 负载跑 2 分钟）判成 FAIL，属度不准。
% 逐项按【自身】的相对尺度判：每对误差都配一个同量纲的基准，不共用一把尺子。
relTol = 1e-6;
okF1 = eP1 < relTol*abs(rPlanC) && eP2 < relTol*sum(G(:)) && ...
       eP3 < relTol*abs(rAdjC)  && eP4 < relTol*sum(A(:)) && ...
       eP5 < relTol*sum(eTotDay);
say('5.4 与 result3_填写说明.txt 对账：');
% ⚠️ 格式串里不要再留 LaTeX 风格的 \( \)：sprintf 不认识 \ 转义，会刷「转义字符 '\(' 无效」
%    警告，且把反斜杠原样打进报告里。
say('      计划电量差 %.4g kWh | 计划费差 %.4g 元', eP2, eP1);
say('      调整电量差 %.4g kWh | 调整费差 %.4g 元', eP4, eP3);
say('      紧急电量差 %.4g kWh（表 4 合计 vs 说明）', eP5);
say('    -> %s', pass(okF1));
okF2 = rEmC >= cEmLo - 1e-2 && rEmC <= cEmHi + 1e-2;
say('5.5 说明里的紧急购电费 %.2f 元落在价格带内   -> %s', rEmC, pass(okF2));
eTot3 = abs((cPlan + cAdj + rEmC) - rTot);
okF3 = eTot3 < 1e-2;
say('5.6 三块之和 %.2f = 说明里的总费用 %.2f（差 %.4g）   -> %s', ...
    cPlan + cAdj + rEmC, rTot, eTot3, pass(okF3));

%% ---------------- 汇总 ----------------
allok = okS1&&okS2&&okS3&&okDate&&okNum && okN1&&okN2&&okN3&&okN4 && ...
        okC1&&okC2&&okC3&&okC4 && okD1&&okD2 && okF1&&okF2&&okF3;
say('');
say('==========================================================');
say(' 交叉校验总判定：%s', pass(allok));
say(' 覆盖：结构/日期列、两张购电表的逐槽自洽与作用域、储能闭环恒等式、');
say('       逐日总量能量平衡、三块费用的独立重算与对账。');
say(' 未覆盖（交付文件粒度不够）：逐槽能量平衡、逐槽弃电、逐槽紧急购电费——');
say('       这三项由 q3_validate.m 的 B1/B3/C3 负责，两者互补。');
say('==========================================================');

ok = allok;
txt = strjoin(lines, sprintf('\n'));
fid = fopen([BASE '问题三\out\q3_crosscheck_report.txt'], 'w', 'n', 'UTF-8');
fprintf(fid, '%s\n', txt);
fclose(fid);
fprintf('\n%s\n', txt);
end

% ======================================================================
function [s1, s2] = parseSeg(str)
% 解析表 4 风格区间 "13:00-14:30" → 起止分钟数
% ⚠️ 不能只把 ':' 换成空格再 sscanf('%d %d %d %d')：区间里的连字符会被当成【负号】，
%    "7:50-8:00" → "7 50-8 00" → v = [7;50;-8;0]，第 3 段解析成 -8 时，i2 = -48 越界。
%    正确做法是按 ':' 和 '-' 一起切分，逐段读「时:分」。
parts = regexp(str, '(\d+)\s*:\s*(\d+)', 'tokens');
assert(numel(parts) == 2, '区间格式无法解析：%s', str);
h1 = str2double(parts{1}{1});  m1 = str2double(parts{1}{2});
h2 = str2double(parts{2}{1});  m2 = str2double(parts{2}{2});
assert(all(isfinite([h1 m1 h2 m2])), '区间格式无法解析：%s', str);
s1 = h1*60 + m1;
s2 = h2*60 + m2;
end

function [pLo, pHi] = priceRange(prRow, i1, i2)
% 该区间内 5·p_t 的下界与上界（紧急购电按 5 倍电价计）
seg = prRow(i1:i2);
pLo = 5*min(seg);  pHi = 5*max(seg);
end

function v = pick(t, pat)
tk = regexp(t, pat, 'tokens', 'once');
if isempty(tk), v = NaN; else, v = str2double(tk{1}); end
end

function s = pass(b)
if b, s = 'PASS'; else, s = 'FAIL'; end
end
