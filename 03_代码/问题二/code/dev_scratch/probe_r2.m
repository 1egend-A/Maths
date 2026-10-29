fn = 'D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\CUMCM2026Problems\C题\附件\附件5\result2.xlsx';
sh = sheetnames(fn);
fprintf('sheets: %s\n', strjoin(cellstr(sh), ' | '));
for k = 1:numel(sh)
    C = readcell(fn, 'Sheet', sh(k));
    [nr,nc] = size(C);
    fprintf('\n===== sheet %s  size = %d x %d =====\n', sh(k), nr, nc);
    lastRow = 0;
    for r = 1:nr
        if ~all(cellfun(@(x) any(ismissing(x)), C(r,:))), lastRow = r; end
    end
    fprintf('  最后非空行 = %d\n', lastRow);
    for r = 1:min(2,nr)
        for c = 1:min(10,nc)
            v = C{r,c};
            if ismissing(v), s='<>'; elseif isnumeric(v), s=sprintf('%g',v); else, s=char(string(v)); end
            fprintf('  [%d,%d]=%s', r, c, s);
        end
        fprintf('\n');
    end
    % 末尾列预览
    fprintf('  末尾5列 (行1..2): ');
    for c = max(1,nc-4):nc
        s1 = C{1,c}; s2 = C{2,c};
        if ismissing(s1), a='<>'; else, a=char(string(s1)); end
        if ismissing(s2), b='<>'; else, b=char(string(s2)); end
        fprintf('| C%d: %s / %s ', c, a, b);
    end
    fprintf('\n');
    % 每列非空计数
    cnt = zeros(1,nc);
    for c = 1:nc
        cnt(c) = sum(~cellfun(@(x) any(ismissing(x)), C(2:end,c)));
    end
    fprintf('  各列非空数据行数（前12列）: %s\n', mat2str(cnt(1:min(12,nc))));
    fprintf('  非零列数 = %d\n', sum(cnt>0));
end
