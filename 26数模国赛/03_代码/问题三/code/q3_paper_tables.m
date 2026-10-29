function T = q3_paper_tables(R, qc, D, F)
% Q3_PAPER_TABLES  生成论文中问题三按题面表 1 / 表 2 / 表 3 格式给出的结果
%
% 题目原文（问题3 段）：
%   「请在论文中按表1、表2 和表3 的格式给出表3 中指定日期的结果」
%   表 3 指定日期：2025.3.20 / 2025.6.21 / 2025.9.23 / 2025.12.21
%   表 1 指定时段：10:00-10:10, 12:00-12:10, 14:00-14:10, 16:00-16:10,
%                  18:00-18:10, 20:00-20:10（+ 全天购电量、全天购电费）
%   表 2 指定时段：0:00-4:00, 4:00-8:00, 8:00-12:00, 12:00-16:00,
%                  16:00-20:00, 20:00-24:00（+ 0:00 储电量、24:00 储电量）
%   表 3 紧急购电：日期 | 时间段 | 购电量（连续时段合并成一区间，版式同表4）
%
% ------------------------------------------------------------
% ★ 本问的表 1 要给两版，不能只给一版
%
%   题面表 1 的抬头是「微网在指定时间段的购电量」。问题三的购电量存在【两个口径】：
%       计划购电量 G_t  —— 按 0:00 预报制定（result3 的「计划购电量」表）
%       调整购电量 A_t  —— 按 6/12/18 预报制定（result3 的「调整购电量」表）
%   题面把二者并列比较并各自规定了罚则电价，说明二者都是有意义的购电量，故论文里
%   两版都给：
%       表 8-1a（计划）  : G_t（6 槽）+ 全天计划购电量 + 全天计划购电费
%       表 8-1b（调整后）: A_t（6 槽）+ 全天调整后购电量 + 全天调整购电费
%   再加一张四日收支总表，把三块费用摆在一起，避免读者以为只付了其中一块。
%
%   单位全部为 kWh；时段标签用【区间形式】（表 1 的写法），与附件5 模板自身的
%   右端点错位标签无关（模板那一处见 q3_config 的口径 6 说明）。
%
% 落盘（UTF-8 CSV，均在 out/ 下）：
%   paper_q3_table1_计划.csv / paper_q3_table1_调整.csv / paper_q3_table2.csv
%   paper_q3_table3.csv（窄表）/ paper_q3_table3_表3格式.csv（四日期宽表）
%   paper_q3_daily.csv（四日收支总表）  paper_q3_monthly.csv（逐月汇总，供结果分析）
%
% 用法：T = q3_paper_tables(R, qc, D, F)

if nargin < 3 || isempty(D)
    D = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码\out\data.mat').D;
end
if nargin < 2 || isempty(qc), qc = q3_config(); end
if nargin < 1 || isempty(R), R = load([qc.outdir 'q3_solution.mat']).R; end
if nargin < 4 || isempty(F)
    fcFile = [qc.outdir 'q3_forecast.mat'];
    if isfile(fcFile), F = load(fcFile).F; end %#ok<NASGU>
end

dt = qc.dt;  nT = size(R.G, 2);
pr = R.price;                              % nd×144

% 表 3 指定日期 -> 行号
want = [datetime(2025,3,20), datetime(2025,6,21), datetime(2025,9,23), datetime(2025,12,21)];
kIdx = zeros(1, numel(want));
dateStr = strings(1, numel(want));
for z = 1:numel(want)
    kIdx(z) = find(R.date == want(z));
    assert(~isempty(kIdx(z)), '结果中找不到日期 %s', string(want(z)));
    dateStr(z) = string(want(z), 'yyyy-MM-dd');
end
assert(all(diff(kIdx) > 0), '指定日期应全部落在求解区间内');

% 表 1 指定时段：起点分钟 600,720,840,960,1080,1200 -> 槽号 = (起点/10)+1
slotMin = 600:120:1200;
slotT1  = slotMin/10 + 1;
lab1    = {'10:00-10:10','12:00-12:10','14:00-14:10','16:00-16:10','18:00-18:10','20:00-20:10'};

% 表 2 六个四小时段
lab2 = {'0:00-4:00','4:00-8:00','8:00-12:00','12:00-16:00','16:00-20:00','20:00-24:00'};
seg  = nT/numel(lab2);                     % 24

Gk = R.G * dt;   Ak = R.A * dt;            % kWh
Ck = R.C * dt;   Dk = R.D * dt;

%% ---------------- 表 8-1a：计划购电量（题面表 1 格式）----------------
hdr1 = [{'日期'}, lab1, {'全天购电量/kWh','全天购电费/元'}];
rows1a = cell(numel(kIdx), numel(hdr1));
for z = 1:numel(kIdx)
    k = kIdx(z);
    rows1a(z,1) = {char(dateStr(z))};
    for c = 1:numel(lab1), rows1a(z,1+c) = {Gk(k, slotT1(c))}; end
    rows1a(z, end-1) = {R.qPlan(k)};             % 全天计划购电量
    rows1a(z, end)   = {R.costPlan(k)};          % 全天计划购电费
end
T.t1a = [hdr1; rows1a];
wcsv([qc.outdir 'paper_q3_table1_计划.csv'], T.t1a);

%% ---------------- 表 8-1b：调整后购电量（题面表 1 格式）----------------
rows1b = cell(numel(kIdx), numel(hdr1));
for z = 1:numel(kIdx)
    k = kIdx(z);
    rows1b(z,1) = {char(dateStr(z))};
    for c = 1:numel(lab1), rows1b(z,1+c) = {Ak(k, slotT1(c))}; end
    rows1b(z, end-1) = {R.qAdj(k)};              % 全天调整后购电量
    rows1b(z, end)   = {R.costAdj(k)};           % 全天调整购电费
end
T.t1b = [hdr1; rows1b];
wcsv([qc.outdir 'paper_q3_table1_调整.csv'], T.t1b);

%% ---------------- 表 8-2：充放电量（题面表 2 格式）----------------
hdr2 = [{'日期'}, strcat('充电量_', lab2), strcat('放电量_', lab2), ...
        {'0:00储电量/kWh','24:00储电量/kWh'}];
rows2 = cell(numel(kIdx), numel(hdr2));
for z = 1:numel(kIdx)
    k = kIdx(z);
    rows2(z,1) = {char(dateStr(z))};
    for b = 1:numel(lab2)
        idx = (b-1)*seg + (1:seg);
        rows2(z, 1+b)             = {sum(Ck(k, idx))};
        rows2(z, 1+numel(lab2)+b) = {sum(Dk(k, idx))};
    end
    rows2(z, end-1) = {qc.S0};                   % 0:00 储电量（口径 2：恒 6000）
    rows2(z, end)   = {R.Soc(k, nT)};            % 24:00 储电量
end
T.t2 = [hdr2; rows2];
wcsv([qc.outdir 'paper_q3_table2.csv'], T.t2);

%% ---------------- 表 8-3：紧急购电（题面表 3 格式）----------------
% 窄表（便于程序处理）+ 宽表（题面版式，直接贴论文）
segPer = zeros(1, numel(kIdx));
segList = cell(1, numel(kIdx));
rows3 = {'日期','紧急购电时间段','紧急购电量/kWh'};
for z = 1:numel(kIdx)
    k = kIdx(z);
    e = R.gEm(k,:) * dt;  m = e > 1e-9;
    d2 = diff([0 m 0]);  s = find(d2 == 1);  t2 = find(d2 == -1) - 1;
    segList{z} = zeros(numel(s), 3);
    for j = 1:numel(s)
        % ⚠️ 段购电量必须对段内【逐槽求和】sum(e(s:t2))，不能取 e(s)（那只是段首槽的值）。
        %    曾误用 e(s)：时间区间对得上、数值却系统性偏小，极易蒙混过关。
        segList{z}(j,:) = [s(j), t2(j), sum(e(s(j):t2(j)))];
        rows3(end+1, :) = {char(dateStr(z)), ...
            sprintf('%s-%s', mm2lab((s(j)-1)*10), mm2lab(t2(j)*10)), ...
            sum(e(s(j):t2(j)))}; %#ok<AGROW>
    end
    segPer(z) = numel(s);
    assert(abs(sum(segList{z}(:,3)) - R.qEm(k)) < 1e-6, ...
        '表3 与逐日紧急购电量不一致：%s', char(dateStr(z)));
end
T.t3 = rows3;
wcsv([qc.outdir 'paper_q3_table3.csv'], rows3, true);

nr = max(segPer);
rows3w = {'时间段','购电量','时间段','购电量','时间段','购电量','时间段','购电量'};
for r = 1:nr
    row = cell(1, 8);
    for z = 1:numel(kIdx)
        if r <= segPer(z)
            s = segList{z}(r,1);  t2 = segList{z}(r,2);  v = segList{z}(r,3);
            row{2*z-1} = sprintf('%s-%s', mm2lab((s-1)*10), mm2lab(t2*10));
            row{2*z}   = v;
        else
            row{2*z-1} = '';  row{2*z} = '';
        end
    end
    rows3w(end+1,:) = row; %#ok<AGROW>
end
T.t3wide = rows3w;
wcsv([qc.outdir 'paper_q3_table3_表3格式.csv'], rows3w, true);

%% ---------------- 四日收支总表（三块费用摆在一起）----------------
% 另附「若不调整」的对照，直接体现调整机制在这四天省了多少
cNoAdjDay = R.costNoAdj;
rows4 = {'日期','计划购电量/kWh','计划购电费/元', ...
         '调整后购电量/kWh','调整购电费/元','调整槽数(上修/下修)', ...
         '紧急购电量/kWh','紧急购电费/元','当日总购电费/元','紧急费占比/%', ...
         '不调整对照/元','调整节省/元','节省占比/%'};
for z = 1:numel(kIdx)
    k = kIdx(z);
    nHi = sum(R.clipHi(k,:));  nLo = sum(R.clipLo(k,:));
    nAdj = sum(abs(R.A(k,:) - R.G(k,:)) > 1e-9);
    savK = cNoAdjDay(k) - R.Sadj(k);
    rows4(end+1, :) = {char(dateStr(z)), R.qPlan(k), R.costPlan(k), ...
        R.qAdj(k), R.costAdj(k), sprintf('%d(%d/%d)', nAdj, nHi, nLo), ...
        R.qEm(k), R.costEm(k), R.Sadj(k), 100*R.costEm(k)/R.Sadj(k), ...
        cNoAdjDay(k), savK, 100*savK/cNoAdjDay(k)}; %#ok<AGROW>
end
T.t4 = rows4;
wcsv([qc.outdir 'paper_q3_daily.csv'], rows4);

%% ---------------- 逐月汇总（供 8.3 结果分析）----------------
mth = month(R.date);
um = unique(mth);
rowsM = {'月份','天数','计划购电量/kWh','调整后购电量/kWh','紧急购电量/kWh', ...
         '计划购电费/元','调整购电费/元','紧急购电费/元','总购电费/元', ...
         '不调整对照/元','调整节省/元','节省占比/%','调整槽数'};
for z = 1:numel(um)
    m = (mth == um(z));
    nAdj = sum(sum(abs(R.A(m,:) - R.G(m,:)) > 1e-9));
    tot = sum(R.Sadj(m));  base = sum(R.costNoAdj(m));
    rowsM(end+1, :) = {sprintf('2025-%02d', um(z)), sum(m), ...
        sum(R.qPlan(m)), sum(R.qAdj(m)), sum(R.qEm(m)), ...
        sum(R.costPlan(m)), sum(R.costAdj(m)), sum(R.costEm(m)), tot, ...
        base, base-tot, 100*(base-tot)/base, nAdj}; %#ok<AGROW>
end
T.tM = rowsM;
wcsv([qc.outdir 'paper_q3_monthly.csv'], rowsM);

%% ---------------- 控制台速览 ----------------
fprintf('\n===== 表 8-1a：指定时段【计划】购电量（kWh）=====\n');
prt(hdr1, rows1a);
fprintf('\n===== 表 8-1b：指定时段【调整后】购电量（kWh）=====\n');
prt(hdr1, rows1b);
fprintf('\n===== 表 8-2：充放电量（kWh）与 0:00/24:00 储电量 =====\n');
for z = 1:numel(kIdx)
    fprintf('  %s : 充电 %s\n', rows2{z,1}, mat2str(cell2mat(rows2(z,2:7)), 6));
    fprintf('  %s : 放电 %s\n', rows2{z,1}, mat2str(cell2mat(rows2(z,8:13)), 6));
    fprintf('  %s : 0:00 / 24:00 储电量 = %.1f / %.1f kWh\n', ...
        rows2{z,1}, rows2{z,14}, rows2{z,15});
end
fprintf('\n===== 表 8-3：紧急购电 =====\n');
for r = 1:size(rows3,1)
    if r == 1
        fprintf('%-12s %-16s %s\n', rows3{r,:});
    else
        fprintf('%-12s %-16s %.2f\n', rows3{r,:});
    end
end
fprintf('\n===== 四日收支总表 =====\n');
fprintf('%-12s %12s %12s %12s %12s %16s %12s %12s %12s %10s %12s %12s %10s\n', rows4{1,:});
for r = 2:size(rows4,1)
    fprintf('%-12s %12.1f %12.2f %12.1f %12.2f %16s %12.1f %12.2f %12.2f %10.2f %12.2f %12.2f %10.3f\n', ...
        rows4{r,1}, rows4{r,2}, rows4{r,3}, rows4{r,4}, rows4{r,5}, rows4{r,6}, ...
        rows4{r,7}, rows4{r,8}, rows4{r,9}, rows4{r,10}, rows4{r,11}, rows4{r,12}, rows4{r,13});
end
fprintf('\n===== 逐月汇总 =====\n');
fprintf('%-9s %5s %14s %14s %13s %14s %13s %13s %14s %14s %13s %9s %8s\n', rowsM{1,:});
for r = 2:size(rowsM,1)
    fprintf('%-9s %5d %14.0f %14.0f %13.0f %14.2f %13.2f %13.2f %14.2f %14.2f %13.2f %9.3f %8d\n', ...
        rowsM{r,1}, rowsM{r,2}, rowsM{r,3}, rowsM{r,4}, rowsM{r,5}, rowsM{r,6}, ...
        rowsM{r,7}, rowsM{r,8}, rowsM{r,9}, rowsM{r,10}, rowsM{r,11}, rowsM{r,12}, rowsM{r,13});
end
end

% ======================================================================
function prt(hdr, rows)
fprintf('%-12s', hdr{1});
for c = 2:numel(hdr)
    if isnumeric(hdr{c}), fprintf('%-12s', hdr{c}); else, fprintf('%-12s', hdr{c}); end
end
fprintf('\n');
for r = 1:size(rows,1)
    fprintf('%-12s', rows{r,1});
    for c = 2:size(rows,2)
        v = rows{r,c};
        if isnumeric(v), fprintf('%-12.3f', v); else, fprintf('%-12s', char(v)); end
    end
    fprintf('\n');
end
end

function wcsv(path, rows, wideNum)
if nargin < 3, wideNum = false; end %#ok<NASGU>
fid = fopen(path, 'w', 'n', 'UTF-8');
for r = 1:size(rows,1)
    cells = strings(1, size(rows,2));
    for c = 1:size(rows,2)
        v = rows{r,c};
        if ischar(v),       cells(c) = string(v);
        elseif isstring(v), cells(c) = v;
        else,               cells(c) = string(v);
        end
    end
    fprintf(fid, '%s\n', strjoin(cellstr(cells), ','));
end
fclose(fid);
fprintf('  已写出：%s\n', path);
end

function s = mm2lab(minute)
h = floor(minute/60);  mi = mod(minute, 60);
if h >= 24
    s = '24:00';
else
    s = sprintf('%d:%02d', h, mi);
end
end
