function probe()
% 精确探查四个附件的结构，为管道定型
base = 'D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\CUMCM2026Problems\C题\附件\';
fprintf('附件目录存在 = %d\n\n', isfolder(base));

ls = dir(base);
names = {ls.name};
fprintf('=== 目录内容 ===\n');
for i = 1:numel(names)
    if ls(i).isdir
        fprintf('  [DIR]  %s\n', names{i});
    else
        fprintf('        %s  (%d bytes)\n', names{i}, ls(i).bytes);
    end
end

% 找附件 xlsx
isAtt = contains(names, '附件') & endsWith(names, '.xlsx');
att = names(isAtt);
fprintf('\n找到 %d 个附件 xlsx: %s\n', numel(att), strjoin(att, ' | '));

for i = 1:numel(att)
    fn = [base att{i}];
    fprintf('\n############ %s ############\n', att{i});
    sn = sheetnames(fn);
    fprintf('工作表 (%d): %s\n', numel(sn), strjoin(string(sn)', ' | '));
    for k = 1:numel(sn)
        C = readcell(fn, 'Sheet', k);
        [nr, nc] = size(C);
        fprintf('  [%s] %d 行 x %d 列\n', sn{k}, nr, nc);
        if nr >= 2
            fprintf('    第1行 前5格: ');
            for j = 1:min(5,nc); fprintf('%s | ', cellrepr(C{1,j})); end
            fprintf('\n');
            fprintf('    第2行 前5格: ');
            for j = 1:min(5,nc); fprintf('%s | ', cellrepr(C{2,j})); end
            fprintf('\n');
            fprintf('    末  行 前5格: ');
            for j = 1:min(5,nc); fprintf('%s | ', cellrepr(C{nr,j})); end
            fprintf('\n');
        end
    end
end

% 附件1 的时间列：全量分类
fprintf('\n\n=== 附件1 时间列全量分类 ===\n');
fn1 = [base att{1}];
C1 = readcell(fn1);
col = C1(2:end, 1);
n = numel(col);
fprintf('共 %d 个时间格\n', n);
cls = cellfun(@(v) string(class(v)), col);
u = unique(cls);
for i = 1:numel(u)
    idx = find(cls == u(i));
    fprintf('  类型 %-10s : %d 个   例: ', u(i), numel(idx));
    for j = 1:min(4, numel(idx)); fprintf('%s  ', cellrepr(col{idx(j)})); end
    fprintf('\n');
end
fprintf('  索引 1..4    : %s | %s | %s | %s\n', cellrepr(col{1}), cellrepr(col{2}), cellrepr(col{3}), cellrepr(col{4}));
fprintf('  索引 end-3..end: %s | %s | %s | %s\n', cellrepr(col{end-3}), cellrepr(col{end-2}), cellrepr(col{end-1}), cellrepr(col{end}));

% 附件2 的日期列
fprintf('\n=== 附件2 各表日期列 ===\n');
fn2 = [base att{2}];
sn2 = sheetnames(fn2);
for k = 1:numel(sn2)
    C = readcell(fn2, 'Sheet', k);
    d = C(2:end, 1);
    fprintf('  [%s] 日期列 %d 个  首=%s (%s)  末=%s (%s)\n', sn2{k}, numel(d), ...
        cellrepr(d{1}), class(d{1}), cellrepr(d{end}), class(d{end}));
end

% 附件3 日期与预报时刻
fprintf('\n=== 附件3 ===\n');
fn3 = [base att{3}];
C3 = readcell(fn3);
d3 = C3(2:end, 1); t3 = C3(2:end, 2);
fprintf('  数据行 %d\n', numel(d3));
fprintf('  日期列类型 %s  首=%s  末=%s\n', class(d3{1}), cellrepr(d3{1}), cellrepr(d3{end}));
ut = unique(cellfun(@(v) string(v), t3));
fprintf('  预报时刻 (%d 种): %s\n', numel(ut), strjoin(ut', ' | '));
ud = unique(cellfun(@(v) string(v), d3));
fprintf('  日期 (%d 种): %s ... %s\n', numel(ud), ud(1), ud(end));

% 附件4 日期列
fprintf('\n=== 附件4 ===\n');
fn4 = [base att{4}];
C4 = readcell(fn4);
d4 = C4(2:end, 1);
fprintf('  数据行 %d\n', numel(d4));
fprintf('  日期列类型 %s  首=%s  末=%s\n', class(d4{1}), cellrepr(d4{1}), cellrepr(d4{end}));
end

function s = cellrepr(v)
if ischar(v) || isstring(v)
    s = sprintf("'%s'", string(v));
elseif isnumeric(v)
    s = sprintf('%.6g', v);
elseif isdatetime(v)
    s = sprintf('DT(%s)', string(v, 'yyyy-MM-dd'));
elseif isduration(v)
    s = sprintf('DUR(%s)', string(v));
elseif ismissing(v)
    s = '<missing>';
else
    s = sprintf('<%s>', class(v));
end
end
