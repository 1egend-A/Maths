function outputFile = q1_export_result1(sol,templateFile,outDir)
% q1_export_result1
% 将问题一结果写入官方 result1.xlsx 模板并保留原模板工作表结构。
%
% 注意：
% 官方 result1 模板中的144个时间标签与附件1右端点标签存在10分钟显示错位。
% 本程序不修改官方模板的标签，只按官方模板的144个数据行顺序写入144个求解结果，
% 以避免破坏提交模板结构。论文中的时段解释仍采用预处理章节统一的右端点口径。

if nargin<3 || isempty(outDir), outDir='out'; end
if ~isfile(templateFile), error('找不到 result1.xlsx 模板：%s',templateFile); end

outputFile=fullfile(outDir,'result1_filled.xlsx');
copyfile(templateFile,outputFile,'f');

% 工作表1：计划购电量
% B2:B145 对应模板中144行
writematrix(sol.grid_kWh,outputFile, ...
    'Sheet','计划购电量','Range','B2');

% 工作表2：充放电量
writematrix(sol.Table2.充电量_kWh,outputFile, ...
    'Sheet','充放电量','Range','B2');
writematrix(sol.Table2.放电量_kWh,outputFile, ...
    'Sheet','充放电量','Range','C2');

% 0:00 与24:00储电量
writematrix(sol.SOC(1),outputFile, ...
    'Sheet','充放电量','Range','E2');
writematrix(sol.SOC(end),outputFile, ...
    'Sheet','充放电量','Range','E3');

fprintf('  已生成：%s\n',outputFile);
end
