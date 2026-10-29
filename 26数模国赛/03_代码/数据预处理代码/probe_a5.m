function probe_a5()
% PROBE_A5  探查附件5 模板（result1/2/3/4-2/4-3）的真实结构
% 只做诊断，不产出任何业务结果。输出写 UTF-8 文本，供人读。
cfg = p0_config();
dir5 = fullfile(cfg.base, '附件5');
files = {'result1.xlsx','result2.xlsx','result3.xlsx','result4-2.xlsx','result4-3.xlsx'};

lines = {};
lines{end+1} = '==========================================================';
lines{end+1} = ' 附件5 输出模板结构探查（probe_a5.m）';
lines{end+1} = '==========================================================';

for f = 1:numel(files)
    fp = fullfile(dir5, files{f});
    lines{end+1} = '';
    lines{end+1} = sprintf('################ %s ################', files{f});
    if ~isfile(fp)
        lines{end+1} = '  [文件不存在]';
        continue;
    end
    sh = sheetnames(fp);
    lines{end+1} = sprintf('  工作表: %s', strjoin(cellstr(sh), ' | '));

    for s = 1:numel(sh)
        C = readcell(fp, 'Sheet', sh{s});
        [nr, nc] = size(C);
        lines{end+1} = sprintf('  ---- sheet【%s】尺寸 %d 行 × %d 列 ----', sh{s}, nr, nc);

        showRows = unique([1:min(3,nr), max(1,nr-2):nr]);
        for r = showRows
            nmax = min(nc, 14);
            parts = cell(1, nmax);
            for c = 1:nmax
                parts{c} = fmtCell(C{r,c});
            end
            lines{end+1} = sprintf('    行%4d | %s', r, strjoin(parts, ' | '));
            if nc > nmax
                lines{end+1} = sprintf('           ... (共 %d 列，以上仅示前 %d 列)', nc, nmax);
            end
        end

        % 列类型画像：每列的非空数量与前两个非空样本
        lines{end+1} = '    列画像（前 20 列）:';
        for c = 1:min(nc, 20)
            vals = C(:, c);
            nonEmpty = 0; k1 = ''; k2 = '';
            for r = 1:nr
                v = vals{r};
                if ~(isempty(v) || (ischar(v) && all(isspace(v))))
                    nonEmpty = nonEmpty + 1;
                    if isempty(k1), k1 = fmtCell(v); elseif isempty(k2), k2 = fmtCell(v); end
                end
            end
            lines{end+1} = sprintf('      列%3d: 非空 %4d | 样本 %s , %s', c, nonEmpty, k1, k2);
        end
    end
end

fid = fopen(fullfile(cfg.outdir, 'probe_a5.txt'), 'w', 'n', 'UTF-8');
for i = 1:numel(lines), fprintf(fid, '%s\n', lines{i}); end
fclose(fid);
fprintf('probe_a5 done -> %s\n', fullfile(cfg.outdir, 'probe_a5.txt'));
end

% ------------------------------------------------------------------
function s = fmtCell(v)
if isempty(v)
    s = '<空>';
    return;
end
if ischar(v)
    s = strtrim(v);
    if isempty(s), s = '<空串>'; end
    if numel(s) > 22, s = [s(1:22) '…']; end
    return;
end
if isdatetime(v)
    s = datestr(v, 'yyyy-mm-dd HH:MM');
    return;
end
if isnumeric(v)
    if isnan(v), s = '<NaN>'; else, s = sprintf('%.6g', v); end
    return;
end
if ismissing(v)
    s = '<missing>'; return;
end
s = sprintf('<%s>', class(v));
end
