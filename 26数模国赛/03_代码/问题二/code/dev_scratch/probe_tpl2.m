fn2 = 'D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\CUMCM2026Problems\C题\附件\附件5\result2.xlsx';
for sn = {'充放电量','紧急购电量'}
    C = readcell(fn2,'Sheet',sn{1});
    fprintf('\n===== %s  (%d x %d) =====\n', sn{1}, size(C,1), size(C,2));
    for r = 1:size(C,1)
        fprintf('  r%02d: ', r);
        for c = 1:size(C,2)
            v = C{r,c};
            if ismissing(v), s='<>'; elseif isnumeric(v), s=sprintf('%g',v); else, s=char(string(v)); end
            fprintf('%-14s', s);
        end
        fprintf('\n');
    end
end
C = readcell(fn2,'Sheet','计划购电量','Range','A1:A6');
fprintf('\n计划购电量 A1:A6 = ');
for r=1:6, fprintf('%s | ', char(string(C{r}))); end
fprintf('\n');
