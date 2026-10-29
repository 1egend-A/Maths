base = 'D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\CUMCM2026Problems\C题\附件\';
fn1 = [base '附件5\result1.xlsx'];
sh1 = sheetnames(fn1);
fprintf('result1 sheets: %s\n', strjoin(cellstr(sh1), ' | '));
for k = 1:numel(sh1)
    C = readcell(fn1,'Sheet',sh1(k));
    fprintf('  [%s] size=%dx%d  行1前4列: ', sh1(k), size(C,1), size(C,2));
    for c=1:min(4,size(C,2)), fprintf('%s | ', char(string(C{1,c}))); end
    fprintf('\n     行1末4列: ');
    for c=max(1,size(C,2)-3):size(C,2), fprintf('%s | ', char(string(C{1,c}))); end
    fprintf('\n');
end

S = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码\out\data.mat');
D = S.D;
fprintf('\n附件1 slots.label  (共 %d 个)\n', numel(D.slots.label));
fprintf('  前 4: %s\n', strjoin(cellstr(string(D.slots.label(1:4))), ' | '));
fprintf('  末 4: %s\n', strjoin(cellstr(string(D.slots.label(end-3:end))), ' | '));
if isfield(D.slots,'start') && isfield(D.slots,'stop')
    fprintf('  slots.start 前2 = %s ; 末2 = %s\n', ...
        strjoin(cellstr(string(D.slots.start(1:2))),','), strjoin(cellstr(string(D.slots.start(end-1:end))),','));
end
disp(fieldnames(D.slots));

% 附件5 result2 表头 与 附件1 slots 对齐检查
fn2 = [base '附件5\result2.xlsx'];
C2 = readcell(fn2,'Sheet','计划购电量','Range','A1:ET1');
lab2 = string(C2(2:end));
fprintf('\nresult2 表头 %d 个\n', numel(lab2));
fprintf('  首2: %s ; 末2: %s\n', lab2(1), lab2(end));
fprintf('  表头末2列名 = %s , %s\n', lab2(143), lab2(144));
