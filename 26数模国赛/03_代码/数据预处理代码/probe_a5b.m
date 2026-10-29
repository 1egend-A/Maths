function probe_a5b()
% PROBE_A5B  细查附件5 的三处要害：多余列、标签错位、充放电量的行结构
cfg = p0_config();
dir5 = fullfile(cfg.base, '附件5');

lines = {};
lines{end+1} = '==========================================================';
lines{end+1} = ' 附件5 细查（probe_a5b.m）';
lines{end+1} = '==========================================================';

% ---------- 1) result1 计划购电量：144 个标签逐个列出 ----------
p1 = fullfile(dir5, 'result1.xlsx');
C = readcell(p1, 'Sheet', '计划购电量');
lines{end+1} = '';
lines{end+1} = sprintf('【1】result1 计划购电量：%d行×%d列', size(C,1), size(C,2));
lines{end+1} = '   A 列全部 145 个取值（含表头）：';
labels = cell(size(C,1),1);
for r = 1:size(C,1)
    labels{r} = char(string(C{r,1}));
end
for r = 1:size(C,1)
    lines{end+1} = sprintf('     行%3d : %s', r, labels{r});
end
% 与标准 144 时段序列比对
std144 = makeStd144();
dataLabels = labels(2:end);
lines{end+1} = sprintf('   数据行数 = %d (标准应为 144)', numel(dataLabels));
same = numel(dataLabels) == 144 && all(strcmp(dataLabels, std144));
lines{end+1} = sprintf('   与标准序列(0:00-0:10,...,23:50-0:00+1)逐项相同? %s', string(same));
if ~same
    lines{end+1} = '   ⇒ 逐位比对：';
    for i = 1:min(numel(dataLabels), 144)
        s = std144{i};
        if ~strcmp(dataLabels{i}, s)
            lines{end+1} = sprintf('      第%3d位: 模板=%-14s 标准=%-14s  <-- 首次分歧', i, dataLabels{i}, s);
            break;
        end
    end
end

% ---------- 2) result2 计划购电量：第 1 行全部 147 个列标签 ----------
p2 = fullfile(dir5, 'result2.xlsx');
C2 = readcell(p2, 'Sheet', '计划购电量');
[nr2, nc2] = size(C2);
lines{end+1} = '';
lines{end+1} = sprintf('【2】result2 计划购电量：%d行×%d列  (1 日期列 + %d 数据列)', nr2, nc2, nc2-1);
lines{end+1} = '   第 1 行全部列标签：';
for c = 1:nc2
    lines{end+1} = sprintf('     列%3d : %s', c, char(string(C2{1,c})));
end
% 日期列首尾
lines{end+1} = sprintf('   行2   日期 = %s', char(string(C2{2,1})));
lines{end+1} = sprintf('   行%d 日期 = %s', nr2, char(string(C2{nr2,1})));
% 日期列是否严格递增、跨度多少天
dts = NaT(nr2-1,1);
for r = 2:nr2
    v = C2{r,1};
    if ischar(v) || isstring(v)
        dts(r-1) = datetime(string(v), 'InputFormat', 'yyyy-MM-dd HH:mm');
    elseif isdatetime(v)
        dts(r-1) = v;
    end
end
lines{end+1} = sprintf('   日期跨度 %s ~ %s，共 %d 天，是否严格递增 = %s', ...
    datestr(dts(1),'yyyy-mm-dd'), datestr(dts(end),'yyyy-mm-dd'), numel(dts), ...
    string(all(diff(dts) == days(1))));

% ---------- 3) 充放电量：result1 / result2 / result3 全部行 ----------
for fn = {'result1.xlsx','result2.xlsx','result3.xlsx','result4-3.xlsx'}
    fp = fullfile(dir5, fn{1});
    if ~isfile(fp), continue; end
    sh = sheetnames(fp);
    if ~ismember('充放电量', cellstr(sh)), continue; end
    Cn = readcell(fp, 'Sheet', '充放电量');
    lines{end+1} = '';
    lines{end+1} = sprintf('【3】%s / 充放电量：%d行×%d列', fn{1}, size(Cn,1), size(Cn,2));
    for r = 1:size(Cn,1)
        parts = cell(1, size(Cn,2));
        for c = 1:size(Cn,2)
            v = Cn{r,c};
            if isempty(v), parts{c} = '<空>';
            elseif ismissing(v), parts{c} = '<missing>';
            elseif isnumeric(v), parts{c} = sprintf('%.6g', v);
            elseif ischar(v) || isstring(v), parts{c} = char(string(v));
            else, parts{c} = ['<' class(v) '>']; end
        end
        lines{end+1} = sprintf('     行%3d | %s', r, strjoin(parts, ' | '));
    end
end

% ---------- 4) 各文件 sheet 清单汇总 ----------
lines{end+1} = '';
lines{end+1} = '【4】五个模板的 sheet 清单';
for fn = {'result1.xlsx','result2.xlsx','result3.xlsx','result4-2.xlsx','result4-3.xlsx'}
    fp = fullfile(dir5, fn{1});
    if ~isfile(fp), continue; end
    sh = cellstr(sheetnames(fp));
    dims = cell(1, numel(sh));
    for s = 1:numel(sh)
        Cc = readcell(fp, 'Sheet', sh{s});
        dims{s} = sprintf('%s(%dx%d)', sh{s}, size(Cc,1), size(Cc,2));
    end
    lines{end+1} = sprintf('   %-16s : %s', fn{1}, strjoin(dims, ' , '));
end

fid = fopen(fullfile(cfg.outdir, 'probe_a5b.txt'), 'w', 'n', 'UTF-8');
for i = 1:numel(lines), fprintf(fid, '%s\n', lines{i}); end
fclose(fid);
fprintf('probe_a5b done -> %s\n', fullfile(cfg.outdir, 'probe_a5b.txt'));
end

% ------------------------------------------------------------------
function s = makeStd144()
% 标准 144 个 10 分钟区间标签：0:00-0:10, 0:10-0:20, ..., 23:50-0:00+1
s = cell(144,1);
for i = 0:143
    a = i*10;                 % 起始分钟
    b = a + 10;               % 结束分钟
    if b <= 24*60
        s{i+1} = sprintf('%d:%02d-%d:%02d', floor(a/60), mod(a,60), floor(b/60), mod(b,60));
    else
        s{i+1} = sprintf('%d:%02d-%d:%02d+1', floor(a/60), mod(a,60), floor(b/60)-24, mod(b,60));
    end
end
end
