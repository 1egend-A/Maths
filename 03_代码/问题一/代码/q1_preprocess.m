function dataFile = q1_preprocess(rawFile,outDir)
% q1_preprocess
% 对附件1进行问题一所需的最小预处理：
% - 保留原始144行顺序
% - 建立统一的10分钟时段索引
% - 数值完整性检查
% - 输出标准化 CSV
%
% 采用“右端点”口径：
%   附件中的 00:10 表示区间 00:00-00:10；
%   附件中的 0:00+1 表示区间 23:50-24:00。

if nargin<1 || isempty(rawFile), rawFile='附件1.xlsx'; end
if nargin<2 || isempty(outDir), outDir='out'; end
if ~isfile(rawFile), error('找不到附件1：%s',rawFile); end
if ~exist(outDir,'dir'), mkdir(outDir); end

T0 = readtable(rawFile,'VariableNamingRule','preserve');

% 使用列序号读取，避免不同 MATLAB 版本对中文列名处理不一致
if width(T0)<4
    error('附件1至少应包含4列：时间、电价、小区负载、光伏发电预测功率。');
end

rawTime = T0{:,1};
price   = double(T0{:,2});
loadP   = double(T0{:,3});
pvP     = double(T0{:,4});

n = height(T0);
if n~=144
    error('附件1应有144个10分钟时段，当前读取到 %d 行。',n);
end

if any(~isfinite(price)) || any(~isfinite(loadP)) || any(~isfinite(pvP))
    error('附件1存在缺失值或非有限数值。');
end
if any(price<0) || any(loadP<0) || any(pvP<0)
    error('附件1存在负值，请检查原始数据。');
end

% 统一时段索引
interval_start_min = (0:n-1)'*10;
interval_end_min   = (1:n)'*10;
interval_end_min(interval_end_min==1440)=1440;
t_index = (1:n)';

% 原始时间标签转字符串，仅用于核查
try
    raw_time_label = string(rawTime);
catch
    raw_time_label = strings(n,1);
    for i=1:n
        raw_time_label(i)=string(rawTime(i));
    end
end

T = table(t_index,interval_start_min,interval_end_min,raw_time_label, ...
          price,loadP,pvP, ...
          'VariableNames',{'t_index','interval_start_min','interval_end_min', ...
          'raw_time_label','price_yuan_per_kWh','load_kW','pv_forecast_kW'});

dataDir=fullfile(outDir,'data');
if ~exist(dataDir,'dir'), mkdir(dataDir); end
dataFile=fullfile(dataDir,'attachment1_10min.csv');
writetable(T,dataFile);

fprintf('  已输出：%s\n',dataFile);
fprintf('  电价范围：[%.4f, %.4f] 元/kWh\n',min(price),max(price));
fprintf('  负载范围：[%.4f, %.4f] kW\n',min(loadP),max(loadP));
fprintf('  光伏范围：[%.4f, %.4f] kW\n',min(pvP),max(pvP));
end
