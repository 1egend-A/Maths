addpath('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码');
qc = q2_config();
tp = qc.tplFile;
for name = {'充放电量', '紧急购电量'}
    C = readcell(tp, 'Sheet', name{1});
    [nr, nc] = size(C);
    fprintf('\n########## [%s] %d x %d ##########\n', name{1}, nr, nc);
    for r = 1:nr
        row = strings(1,nc);
        for c = 1:nc
            v = C{r,c};
            if all(ismissing(v))
                row(c) = "·";
            else
                s = string(v);
                if all(strlength(s) == 0), row(c) = "·"; else, row(c) = s(1); end
            end
        end
        fprintf(' r%-3d | %s\n', r, strjoin(cellstr(row), ' | '));
    end
end
% 计划购电量 表头完整列出
C = readcell(tp, 'Sheet', '计划购电量');
hdr = string(C(1,:));
fprintf('\n########## 计划购电量 表头（%d 列）##########\n', numel(hdr));
fprintf(' 列1   = %s\n', hdr(1));
fprintf(' 列2   = %s\n', hdr(2));
fprintf(' 列145 = %s\n', hdr(145));
fprintf(' 列146 = %s\n', hdr(146));
fprintf(' 列147 = %s\n', hdr(147));
fprintf(' 中间抽查: 列80=%s 列144=%s\n', hdr(80), hdr(144));
