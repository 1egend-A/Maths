function D = p0_load(cfg)
% P0_LOAD  读取四个附件 → 归一化为统一结构 D，并落盘 data.mat
%
% 返回结构：
%   D.day144.time/price/load/pv   附件1：单日 144 时段（Q1 的日）
%   D.actual.dates                365x1 datetime（2025-01-01..2025-12-31）
%   D.actual.load / pv / price    365x144（附件2 两表 + 附件4）
%   D.fc.dates / issue / pv       附件3：365x4 个预报时刻 x 24 小时
%   D.slots.*                     144 个时段的标签与分钟数
%   D.meta.*                      来源与规模
%
% 环境注意：本机 MATLAB 的 readtable 因 @tabular/dotAssign.m 被覆盖而不可用，
% 故全程使用 readcell；不要在本项目里用 readtable 或 T.新列 = ... 。

% ---------------- 定位附件 ----------------
ls = dir(cfg.base);
names = {ls.name};
fn = struct();
for i = 1:numel(names)
    nm = names{i};
    if ls(i).isdir || ~endsWith(nm, '.xlsx') || ~contains(nm, '附件')
        continue;
    end
    tok = regexp(nm, '附件(\d)', 'tokens', 'once');
    if ~isempty(tok)
        fn.(sprintf('a%s', tok{1})) = fullfile(cfg.base, nm);
    end
end
for k = ["a1","a2","a3","a4"]
    assert(isfield(fn, k), '未找到附件 %s', k);
end

D = struct();
D.meta.base = cfg.base;
D.meta.files = fn;
D.meta.loadedAt = datestr(now, 'yyyy-mm-dd HH:MM:SS');

% ---------------- 附件1：单日 144 时段 ----------------
C = readcell(fn.a1);
n1 = size(C,1) - 1;
t1 = strings(n1, 1);
for i = 1:n1
    t1(i) = timeLabel(C{i+1, 1});
end
D.day144.time  = t1;
D.day144.price = cells2mat(C(2:end, 2));
D.day144.load  = cells2mat(C(2:end, 3));
D.day144.pv    = cells2mat(C(2:end, 4));

% ---------------- 附件2：全年实际负载 / 光伏 ----------------
[lab, dd, Mload] = readTimeMatrix(fn.a2, 1);
D.actual.dates = dd;
D.actual.load  = Mload;
[lab2, dd2, Mpv] = readTimeMatrix(fn.a2, 2);
D.actual.pv = Mpv;
assert(isequal(dd, dd2), '附件2 两个工作表日期列不一致');
assert(isequal(lab, lab2), '附件2 两个工作表时间标签不一致');

% 全表统一的时间标签（与附件1 交叉比对，必须一致）
assert(isequal(lab(:), D.day144.time), ...
    '附件1 与 附件2 的时段标签不一致：附件1 首个=%s，附件2 首个=%s', ...
    D.day144.time(1), lab(1));
D.slots.label   = lab(:);
D.slots.minutes = minutesOf(D.slots.label);

% ---------------- 附件3：4 预报时刻 x 24 小时 ----------------
C = readcell(fn.a3);
D.fc.dates = fillForwardDates(C(2:end, 1));
D.fc.issue = strings(size(C,1)-1, 1);
for i = 2:size(C,1)
    D.fc.issue(i-1) = string(C{i,2});
end
D.fc.pv = cells2mat(C(2:end, 3:end));
D.fc.horizon = 1:size(D.fc.pv, 2);   % 预报1小时..预报24小时

% ---------------- 附件4：全年电价 ----------------
[~, dd4, Mprice] = readTimeMatrix(fn.a4, 1);
D.actual.price = Mprice;
assert(isequal(dd4, D.actual.dates), '附件2 与 附件4 的日期列不一致');

% ---------------- 元数据 ----------------
D.meta.size.day144   = [numel(D.day144.price), 1];
D.meta.size.actual   = size(D.actual.price);
D.meta.size.fc       = size(D.fc.pv);
D.meta.nDays         = numel(D.actual.dates);
D.meta.dateFirst     = D.actual.dates(1);
D.meta.dateLast      = D.actual.dates(end);
D.meta.issueLevels   = unique(D.fc.issue);
D.meta.fcDatesUnique = unique(D.fc.dates);

% ---------------- 落盘 ----------------
save(fullfile(cfg.outdir, 'data.mat'), 'D', '-v7.3');
end

% ======================================================================
%                             局部函数
% ======================================================================

function [labels, dates, M] = readTimeMatrix(f, sheet)
% 读「日期\时间 + 145 个日分数」格式的表（附件2、附件4）
% 第 1 行是表头（第 1 格是 '日期\时间'，第 2.. 格是日分数）
% 第 1 列是日期，第 2.. 列是数据
% 【坑】不能用 readmatrix 直接读，它会把第 1 行的日分数当成数据。
C = readcell(f, 'Sheet', sheet);
nr = size(C,1); nc = size(C,2);

labels = strings(1, nc-1);
for j = 2:nc
    labels(j-1) = timeLabel(C{1, j});
end

dates = NaT(nr-1, 1);
for i = 2:nr
    v = C{i, 1};
    if isdatetime(v)
        dates(i-1) = v;
    elseif ischar(v) || isstring(v)
        dates(i-1) = datetime(strtrim(string(v)), 'InputFormat', 'yyyy-M-d');
    else
        error('第 %d 行日期列类型异常: %s', i, class(v));
    end
end

M = cells2mat(C(2:end, 2:end));
end

function M = cells2mat(C)
% cell → double 矩阵，missing 记为 NaN，遇到非数值直接报错（不静默）
M = zeros(size(C));
for i = 1:numel(C)
    v = C{i};
    if isnumeric(v) && isscalar(v)
        M(i) = v;
    elseif ismissing(v)
        M(i) = NaN;
    else
        error('cells2mat: 第 %d 格不是标量数值，而是 %s（疑似表头/合并单元格未排除）', i, class(v));
    end
end
end

function lab = timeLabel(v)
% 统一时间标签：double 日分数 或 'HH:MM' / 'H:MM+1' → 'HH:MM' / 'HH:MM+1'
if isnumeric(v)
    mins = round(v * 1440);
else
    s = strtrim(string(v));
    plus1 = endsWith(s, '+1');
    if plus1
        s = extractBefore(s, '+1');
    end
    p = split(s, ':');
    assert(numel(p) == 2, '无法解析时间标签: %s', s);
    mins = str2double(p(1)) * 60 + str2double(p(2));
    if plus1
        mins = mins + 1440;
    end
end
lab = minsLabel(mins);
end

function lab = minsLabel(mins)
% 分钟数 → 标签（1440 分钟 = 次日 00:00）
if mins < 1440
    lab = string(sprintf('%02d:%02d', floor(mins/60), mod(mins, 60)));
else
    lab = string(sprintf('%02d:%02d+1', floor((mins-1440)/60), mod(mins, 60)));
end
end

function m = minutesOf(labels)
% 标签 → 自当日 00:00 起的分钟数
n = numel(labels);
m = zeros(n, 1);
for i = 1:n
    s = labels(i);
    plus1 = endsWith(s, '+1');
    if plus1
        s = extractBefore(s, '+1');
    end
    p = split(s, ':');
    v = str2double(p(1)) * 60 + str2double(p(2));
    if plus1
        v = v + 1440;
    end
    m(i) = v;
end
end

function d = fillForwardDates(col)
% 附件3 的日期列是合并单元格（每 4 行只填一次），向下填充
n = numel(col);
d = NaT(n, 1);
last = NaT;
for i = 1:n
    v = col{i};
    if isdatetime(v) && ~isnat(v)
        last = v;
    elseif ischar(v) || isstring(v)
        s = strtrim(string(v));
        if strlength(s) > 0
            last = datetime(s, 'InputFormat', 'yyyy-M-d');
        end
    end
    d(i) = last;
end
assert(~any(isnat(d)), '附件3 日期列向下填充后仍有空值');
end
