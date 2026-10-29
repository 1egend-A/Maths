addpath('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码');
qc = q2_config();
tp = qc.tplFile;
fprintf('模板路径：%s\n存在：%d\n', tp, isfile(tp));
sh = sheetnames(tp);
fprintf('工作表：%s\n', strjoin(cellstr(sh), ' | '));
for s = 1:numel(sh)
    C = readcell(tp, 'Sheet', sh{s});
    [nr, nc] = size(C);
    fprintf('\n===== [%s] %d 行 x %d 列 =====\n', sh{s}, nr, nc);
    fprintf(' R1 前8: %s\n', j(cellstr(string(C(1,1:min(8,nc))))));
    fprintf(' R1 末6: %s\n', j(cellstr(string(C(1,max(1,nc-5):nc)))));
    for rr = 2:min(4,nr)
        fprintf(' R%d 前6: %s  || 末4: %s\n', rr, ...
            j(cellstr(string(C(rr,1:min(6,nc))))), ...
            j(cellstr(string(C(rr,max(1,nc-3):nc)))));
    end
    colA = string(C(:,1));
    isd = ~ismissing(colA) & colA ~= "";
    ii = find(isd);
    fprintf(' A列非空 %d 个；首=%s 末=%s\n', numel(ii), colA(ii(1)), colA(ii(end)));
    fprintf(' 前12个非空 A: %s\n', j(cellstr(colA(ii(1:min(12,numel(ii))))')));
end

function s = j(c)
s = strjoin(c, ' | ');
end
