function T = q2_paper_tables(R, qc, D)
% Q2_PAPER_TABLES  生成论文中问题二要求的表 1 / 表 2 / 表 3
%
% 题目原文（问题2 段）：
%   「在论文中按表 1 和表 2 的格式给出表 3 中指定日期的结果，按表 3 的格式给出
%     紧急购电的结果」
%   表 3 指定日期：2025.3.20 / 2025.6.21 / 2025.9.23 / 2025.12.21
%   表 1 指定时段：10:00-10:10, 12:00-12:10, 14:00-14:10, 16:00-16:10,
%                  18:00-18:10, 20:00-20:10（+ 全天购电量、全天购电费）
%   表 2 指定时段：0:00-4:00, 4:00-8:00, 8:00-12:00, 12:00-16:00,
%                  16:00-20:00, 20:00-24:00（+ 0:00 储电量、24:00 储电量）
%   表 4 紧急购电填写示例：日期 | 紧急购电时间段 | 紧急购电量（连续时段合并）
%
% 单位全部为 kWh；时段标签用【区间形式】（表 1 的写法），与附件5 模板自身的
% 右端点错位标签无关（模板那一处见 q2_config 的口径 6 说明）。
%
% 落盘（UTF-8 CSV）：
%   out/paper_table1.csv / paper_table2.csv / paper_table3.csv / paper_table4_收支.csv
%
% 用法：T = q2_paper_tables(R, qc, D)

if nargin < 3 || isempty(D)
    D = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码\out\data.mat').D;
end
if nargin < 2 || isempty(qc), qc = q2_config(); end
if nargin < 1 || isempty(R), R = load([qc.outdir 'q2_solution.mat']).R; end

dt = qc.dt;  nT = size(R.gPlan, 2);
pr = D.day144.price(:)';                 % 元/kWh

% 表 3 指定日期 -> 行号
want  = [datetime(2025,3,20), datetime(2025,6,21), datetime(2025,9,23), datetime(2025,12,21)];
kIdx  = zeros(1, numel(want));
dateStr = strings(1, numel(want));
for z = 1:numel(want)
    kIdx(z) = find(R.date == want(z));
    assert(~isempty(kIdx(z)), '结果中找不到日期 %s', string(want(z)));
    dateStr(z) = string(want(z), 'yyyy-MM-dd');
end
assert(all(diff(kIdx) > 0), '指定日期应全部落在求解区间内');

% 表 1 指定时段：起点分钟 600,720,840,960,1080,1200 -> 时段号 = (起点/10)+1
slotMin  = 600:120:1200;
slotT1   = slotMin/10 + 1;
lab1     = {'10:00-10:10','12:00-12:10','14:00-14:10','16:00-16:10','18:00-18:10','20:00-20:10'};

% 表 2 六个四小时段
lab2 = {'0:00-4:00','4:00-8:00','8:00-12:00','12:00-16:00','16:00-20:00','20:00-24:00'};
seg  = nT/numel(lab2);                   % 24

%% ---------------- 表 1 ----------------
% 列：日期 | 6 个指定时段购电量 | 全天购电量 | 全天购电费
hdr1 = [{'日期'}, lab1, {'全天购电量/kWh','全天购电费/元'}];
rows1 = cell(numel(kIdx), numel(hdr1));
for z = 1:numel(kIdx)
    k = kIdx(z);
    rows1(z,1) = {char(dateStr(z))};
    for c = 1:numel(lab1)
        rows1(z,1+c) = {R.gPlan(k, slotT1(c)) * dt};
    end
    rows1(z, end-1) = {R.qPlan(k)};          % 全天计划购电量
    rows1(z, end)   = {R.costPlan(k)};       % 全天计划购电费
end
T.t1 = [hdr1; rows1];
wcsv([qc.outdir 'paper_table1.csv'], T.t1);

%% ---------------- 表 2 ----------------
% 列：日期 | 6 段充电量 | 6 段放电量 | 0:00 储电量 | 24:00 储电量
hdr2 = [{'日期'}, strcat('充电量_', lab2), strcat('放电量_', lab2), ...
        {'0:00储电量/kWh','24:00储电量/kWh'}];
rows2 = cell(numel(kIdx), numel(hdr2));
for z = 1:numel(kIdx)
    k = kIdx(z);
    rows2(z,1) = {char(dateStr(z))};
    for b = 1:numel(lab2)
        idx = (b-1)*seg + (1:seg);
        rows2(z, 1+b)             = {sum(R.c(k, idx))*dt};
        rows2(z, 1+numel(lab2)+b) = {sum(R.d(k, idx))*dt};
    end
    rows2(z, end-1) = {qc.S0};               % 0:00 储电量（口径 2：恒 6000）
    rows2(z, end)   = {R.Soc(k, nT)};        % 24:00 储电量
end
T.t2 = [hdr2; rows2];
wcsv([qc.outdir 'paper_table2.csv'], T.t2);

%% ---------------- 表 3（= 紧急购电量，格式同表 4）----------------
rows3 = {'日期','紧急购电时间段','紧急购电量/kWh'};
for z = 1:numel(kIdx)
    k = kIdx(z);
    e = R.gEm(k,:) * dt;
    m = e > 1e-9;
    if ~any(m), continue; end
    d2 = diff([0 m 0]);
    s = find(d2 == 1);  t2 = find(d2 == -1) - 1;
    for j = 1:numel(s)
        rows3(end+1, :) = {char(dateStr(z)), ...
            sprintf('%s-%s', mm2lab((s(j)-1)*10), mm2lab(t2(j)*10)), ...
            sum(e(s(j):t2(j)))};             %#ok<AGROW>
    end
end
T.t3 = rows3;
wcsv([qc.outdir 'paper_table3.csv'], rows3, true);

%% ---------------- 表 3【题目格式】宽表：四个日期并列 ----------------
% 题目表3 的版式是「每个日期一组 时间段|购电量，四组并列」。
% 上面的 T.t3 是便于程序处理的窄表；这里转成题目要求的那一版，直接贴论文。
segPer = zeros(1, numel(kIdx));
segList = cell(1, numel(kIdx));
segSum = zeros(1, numel(kIdx));
for z = 1:numel(kIdx)
    k = kIdx(z);
    e = R.gEm(k,:) * dt;  m = e > 1e-9;
    d2 = diff([0 m 0]);  s = find(d2 == 1);  t2 = find(d2 == -1) - 1;
    segList{z} = zeros(numel(s), 3);
    for j = 1:numel(s)
        % ⚠️ 段购电量必须对段内【逐时段求和】sum(e(s:t2))，不能取 e(s)（那只是段首时段的值）。
        %    曾误用 e(s)，时间区间对得上、数值却系统性偏小，极易蒙混过关。
        segList{z}(j,:) = [s(j), t2(j), sum(e(s(j):t2(j)))];
    end
    segPer(z) = numel(s);
    segSum(z) = sum(segList{z}(:,3));
    % 与窄表（T.t3）同源，必须完全一致；对不上说明这段转换写错了
    assert(abs(segSum(z) - R.qEm(k)) < 1e-6, ...
        '表3 宽表与逐日紧急购电量不一致：%s', char(dateStr(z)));
end
nr = max(segPer);
hdr3w = {'时间段','购电量','时间段','购电量','时间段','购电量','时间段','购电量'};
rows3w = hdr3w;
for r = 1:nr
    row = cell(1, 2*numel(kIdx));
    for z = 1:numel(kIdx)
        if r <= segPer(z)
            s = segList{z}(r,1);  t2 = segList{z}(r,2);  v = segList{z}(r,3);
            row{2*z-1} = sprintf('%s-%s', mm2lab((s-1)*10), mm2lab(t2*10));
            row{2*z}   = v;
        else
            row{2*z-1} = '';  row{2*z} = '';
        end
    end
    rows3w(end+1,:) = row;   %#ok<AGROW>
end
T.t3wide = rows3w;
wcsv([qc.outdir 'paper_table3_表3格式.csv'], rows3w, true);

%% ---------------- 附：四个指定日期的收支汇总（供结果分析用）----------------
rows4 = {'日期','计划购电量/kWh','计划购电费/元','紧急购电量/kWh','紧急购电费/元', ...
         '当日总购电费/元','紧急购电费占比/%','紧急购电时段数'};
for z = 1:numel(kIdx)
    k = kIdx(z);
    nseg = size(rows3,1) - 1;                            % 占位，下面按日重算
    e = R.gEm(k,:) * dt;  m = e > 1e-9;
    d2 = diff([0 m 0]);
    nseg = sum(d2 == 1);
    rows4(end+1, :) = {char(dateStr(z)), R.qPlan(k), R.costPlan(k), R.qEm(k), ...
        R.costEm(k), R.costTot(k), 100*R.costEm(k)/R.costTot(k), nseg}; %#ok<AGROW>
end
T.t4 = rows4;
wcsv([qc.outdir 'paper_table4_收支.csv'], rows4);

% 控制台速览
fprintf('\n===== 表 1：指定时段购电量（kWh）=====\n');
fprintf('%-12s', hdr1{:}); fprintf('\n');
for z = 1:numel(kIdx)
    fprintf('%-12s', rows1{z,1});
    for c = 2:numel(hdr1), fprintf('%-12.2f', rows1{z,c}); end
    fprintf('\n');
end
fprintf('\n===== 表 2：充放电量（kWh）与 0:00/24:00 储电量 =====\n');
for z = 1:numel(kIdx)
    fprintf('  %s : 充电 %s\n', rows2{z,1}, mat2str(cell2mat(rows2(z,2:7)), 6));
    fprintf('  %s : 放电 %s\n', rows2{z,1}, mat2str(cell2mat(rows2(z,8:13)), 6));
    fprintf('  %s : 0:00/24:00 储电量 = %.1f / %.1f\n', rows2{z,1}, rows2{z,14}, rows2{z,15});
end
fprintf('\n===== 表 3：紧急购电 =====\n');
fprintf('%-12s %-16s %s\n', rows3{1,:});
for r = 2:size(rows3,1)
    fprintf('%-12s %-16s %.2f\n', rows3{r,:});
end
fprintf('\n===== 四日收支汇总 =====\n');
fprintf('%-12s %12s %13s %12s %12s %13s %10s %6s\n', rows4{1,:});
for r = 2:size(rows4,1)
    fprintf('%-12s %12.1f %13.2f %12.1f %12.2f %13.2f %10.2f %6d\n', ...
        rows4{r,1}, rows4{r,2}, rows4{r,3}, rows4{r,4}, rows4{r,5}, rows4{r,6}, rows4{r,7}, rows4{r,8});
end
end

% ======================================================================
function wcsv(path, rows, wideNum)
if nargin < 3, wideNum = false; end
fid = fopen(path, 'w', 'n', 'UTF-8');
for r = 1:size(rows,1)
    cells = strings(1, size(rows,2));
    for c = 1:size(rows,2)
        v = rows{r,c};
        if ischar(v),      cells(c) = string(v);
        elseif isstring(v), cells(c) = v;
        else,              cells(c) = string(v);
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
