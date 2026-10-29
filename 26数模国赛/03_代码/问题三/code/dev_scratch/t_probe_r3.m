% T_PROBE_R3  读取官方 result3.xlsx 模板的真实结构（非交付物）
f = 'D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\CUMCM2026Problems\C题\附件\附件5\result3.xlsx';
sh = sheetnames(f);
fprintf('工作表：%s\n', strjoin(cellstr(sh)', ' | '));
for i = 1:numel(sh)
    C = readcell(f, 'Sheet', sh(i));
    fprintf('\n===== [%s] %d 行 x %d 列 =====\n', sh(i), size(C,1), size(C,2));
    nr = min(size(C,1), 10);  nc = min(size(C,2), 8);
    rowsShow = [1:nr, max(nr+1, size(C,1)-2):size(C,1)];
    for r = unique(rowsShow)
        v = '';
        for c = 1:nc
            v = [v sprintf('%-14s', fmt(C{r,c}))]; %#ok<AGROW>
        end
        fprintf('R%-3d %s\n', r, v);
        if r == nr && size(C,1) > nr+3, fprintf('  ...\n'); end
    end
end

function s = fmt(x)
if isa(x, 'missing'),          s = '.';
elseif isnumeric(x) || islogical(x)
    if isempty(x) || all(isnan(x)), s = '.'; else, s = sprintf('%.4g', x(1)); end
elseif isdatetime(x),          s = datestr(x, 'yyyy-mm-dd');
elseif isduration(x),          s = char(string(x));
elseif ischar(x),              s = x;
elseif isstring(x),            s = char(x);
elseif iscategorical(x),       s = char(string(x));
elseif iscell(x),              s = ['{' class(x{1}) '}'];
else,                          s = ['<' class(x) '>'];
end
end
