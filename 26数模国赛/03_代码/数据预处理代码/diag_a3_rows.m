function diag_a3_rows()
% DIAG_A3_ROWS  直接读附件3 的日期列/发布时刻列，确定真实行序
cfg = p0_config(); D = p0_load(cfg);
L = {};
L{end+1} = '==== 附件3 行序实况 ====';
L{end+1} = sprintf('总行数 %d，唯一日期数 %d，唯一发布时刻数 %d', ...
    numel(D.fc.dates), numel(unique(D.fc.dates)), numel(unique(D.fc.issue)));
L{end+1} = sprintf('发布时刻取值: %s', strjoin(cellstr(unique(D.fc.issue)).', ', '));
L{end+1} = '';
L{end+1} = ' 行号 |   日期     | 发布时刻 |  峰值(kW)';
for i = 1:12
    L{end+1} = sprintf(' %4d | %s | %8s | %9.1f', i, ...
        datestr(D.fc.dates(i),'yyyy-mm-dd'), char(D.fc.issue(i)), max(D.fc.pv(i,:)));
end
L{end+1} = ' ...';
for i = 38:45
    L{end+1} = sprintf(' %4d | %s | %8s | %9.1f', i, ...
        datestr(D.fc.dates(i),'yyyy-mm-dd'), char(D.fc.issue(i)), max(D.fc.pv(i,:)));
end
L{end+1} = ' ...（决策日 2025-04-10 = 第 100 天，其日块 397..400）';
for i = 395:402
    L{end+1} = sprintf(' %4d | %s | %8s | %9.1f', i, ...
        datestr(D.fc.dates(i),'yyyy-mm-dd'), char(D.fc.issue(i)), max(D.fc.pv(i,:)));
end
L{end+1} = ' ...（第 200 天 = 2025-07-19，其日块 797..800）';
for i = 795:802
    L{end+1} = sprintf(' %4d | %s | %8s | %9.1f', i, ...
        datestr(D.fc.dates(i),'yyyy-mm-dd'), char(D.fc.issue(i)), max(D.fc.pv(i,:)));
end

% 结构判定
d = D.fc.dates;
sameBlock = all(d(1:4) == d(1));           % 前 4 行是否同一天
L{end+1} = '';
L{end+1} = sprintf(' 前 4 行同一天？ %d  ⇒ %s', sameBlock, ...
    ternary(sameBlock, '日主序 (day-major)', '发布时刻主序 (issue-major)'));

% 每个日期的行数分布
[u, ~, ic] = unique(d);
cnt = accumarray(ic, 1);
L{end+1} = sprintf(' 每个日期出现次数: 唯一值 = %s（共 %d 个日期）', ...
    mat2str(unique(cnt).'), numel(u));

fid = fopen(fullfile(cfg.outdir,'diag_a3_rows.txt'), 'w', 'n', 'UTF-8');
for i = 1:numel(L), fprintf(fid, '%s\n', L{i}); end
fclose(fid);
fprintf('diag_a3_rows -> %s\n', fullfile(cfg.outdir,'diag_a3_rows.txt'));
end

function s = ternary(c, a, b)
if c, s = a; else, s = b; end
end
