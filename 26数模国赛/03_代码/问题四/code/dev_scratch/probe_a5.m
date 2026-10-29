% PROBE_A5  开发期：探查 result4-2 / result4-3 官方模板的结构（不改模板）
% ⚠️ 只读，绝不 writematrix 回模板目录。
R2 = 'D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\CUMCM2026Problems\C题\附件\附件5\result4-2.xlsx';
R3 = 'D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\CUMCM2026Problems\C题\附件\附件5\result4-3.xlsx';

for f = {R2, R3}
    ff = f{1};
    fprintf('\n================ %s ================\n', ff);
    sh = sheetnames(ff);
    fprintf('工作表（%d 个）：%s\n', numel(sh), strjoin(cellstr(sh), ' | '));
    for si = 1:numel(sh)
        s = char(sh(si));
        fprintf('\n---- [%s] ----\n', s);
        try
            C = readcell(ff, 'Sheet', s);
        catch ME
            fprintf('  readcell 失败：%s\n', ME.message);
            continue;
        end
        fprintf('  尺寸 %d x %d\n', size(C,1), size(C,2));
        nr = min(size(C,1), 6);  ncl = min(size(C,2), 8);
        for r = 1:nr
            parts = cell(1, ncl);
            for c2 = 1:ncl
                v = C{r,c2};
                if isa(v,'missing') || (isnumeric(v) && all(isnan(v)))
                    parts{c2} = '.';
                elseif ischar(v) || isstring(v)
                    parts{c2} = char(v);
                elseif isdatetime(v)
                    parts{c2} = datestr(v, 'yyyy-mm-dd');
                elseif isnumeric(v)
                    parts{c2} = sprintf('%.4g', v);
                else
                    parts{c2} = class(v);
                end
            end
            fprintf('   r%-3d| %s\n', r, strjoin(parts, ' | '));
        end
        % 末尾几行（看合计行）
        if size(C,1) > nr
            fprintf('   ...（中略 %d 行）...\n', size(C,1)-nr-2);
            for r = max(1,size(C,1)-2):size(C,1)
                parts = cell(1, ncl);
                for c2 = 1:ncl
                    v = C{r,c2};
                    if isa(v,'missing') || (isnumeric(v) && all(isnan(v))), parts{c2} = '.';
                    elseif ischar(v) || isstring(v), parts{c2} = char(v);
                    elseif isdatetime(v), parts{c2} = datestr(v,'yyyy-mm-dd');
                    elseif isnumeric(v), parts{c2} = sprintf('%.6g', v);
                    else, parts{c2} = class(v); end
                end
                fprintf('   r%-3d| %s\n', r, strjoin(parts, ' | '));
            end
        end
    end
end
fprintf('\n探查完成（模板未被修改）\n');
