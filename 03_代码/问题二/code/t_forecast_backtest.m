function t_forecast_backtest()
% T_FORECAST_BACKTEST  问题二预测方法回测与选型依据
%
% 背景：问题二按「严格字面」口径，信息集 = 附件1（电价，逐日相同）+ 附件2（负载/光伏实际），
%       **不引用附件3**。因此在每天 0:00 制定当天计划时，负载与光伏都必须自己预测。
%
% 纪律：预测第 d 天时只允许用第 d-1 天及更早的数据（严格无未来信息）。
%
% 输出：1) 头部方法横向对比  2) 负载混合权重扫描  3) 光伏候选扫描
%       4) 逐月稳健性  5) 选型结论
%
% 用法：matlab -batch "t_forecast_backtest"

%% ---------- 载入附件2（复用预处理阶段的统一结构 D）----------
addpath('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码');
S = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码\out\data.mat');
D = S.D;

L = D.actual.load;      % 365 x 144  kW
P = D.actual.pv;        % 365 x 144  kW
nd = size(L,1); nt = size(L,2);
assert(nd==365 && nt==144);

q2 = 32:nd;             % 问题二区间 2025-02-01 ~ 12-31（result2 模板 334 行）

fprintf('==========================================================\n');
fprintf(' 问题二预测方法回测（预测第 d 天只用第 d-1 天及更早数据）\n');
fprintf('==========================================================\n');
fprintf('评测区间：2025-02-01~12-31，共 %d 天 × %d 时段 = %d 个样本\n\n', ...
    numel(q2), nt, numel(q2)*nt);

%% ---------- 1. 头部方法横向对比 ----------
methods = {
    'lag1    昨日同时刻',        @(X,d) X(d-1,:)
    'lag7    上周同日同时刻',    @(X,d) X(d-7,:)
    'mean7   近7日同时刻均值',   @(X,d) mean(X(d-7:d-1,:),1)
    'mean28w 近4周同星期几均值', @(X,d) mean(X(d-[7 14 21 28],:),1)
    'blend   0.5*lag7+0.5*mean28w', @(X,d) 0.5*X(d-7,:) + 0.5*mean(X(d-[7 14 21 28],:),1)
};
fprintf('---- 1. 方法横向对比 ----\n');
for isPV = 0:1
    if isPV, X = P; nm = '光伏'; else, X = L; nm = '负载'; end
    fprintf('%-6s %-30s %9s %9s %9s\n', nm, '方法', 'MAE', 'RMSE', 'MAPE(%)');
    for m = 1:size(methods,1)
        [mae,rmse,mape] = score(X, methods{m,2}, q2);
        fprintf('%-6s %-30s %9.2f %9.2f %9.3f\n', nm, methods{m,1}, mae, rmse, mape);
    end
    fprintf('  （MAPE 只统计真值>50 kW 的时段，避免夜间近零值放大）\n\n');
end

%% ---------- 2. 负载：混合权重扫描 ----------
fprintf('---- 2. 负载  w*lag7 + (1-w)*mean28w  权重扫描 ----\n');
fprintf('%6s %9s %9s %9s\n', 'w', 'MAE', 'RMSE', 'MAPE(%)');
wList = 0:0.1:1; bestW = struct('w',nan,'mape',inf);
for w = wList
    f = @(X,d) w*X(d-7,:) + (1-w)*mean(X(d-[7 14 21 28],:),1);
    [mae,rmse,mape] = score(L, f, q2);
    fprintf('%6.1f %9.2f %9.2f %9.3f\n', w, mae, rmse, mape);
    if mape < bestW.mape, bestW = struct('w',w,'mape',mape); end
end
fprintf('  → 负载最优权重 w = %.1f\n\n', bestW.w);

%% ---------- 3. 光伏候选扫描 ----------
fprintf('---- 3. 光伏 候选扫描 ----\n');
pvCand = {
    'lag1            ', @(X,d) X(d-1,:)
    'lag7            ', @(X,d) X(d-7,:)
    'mean3           ', @(X,d) mean(X(d-3:d-1,:),1)
    'mean5           ', @(X,d) mean(X(d-5:d-1,:),1)
    'mean7           ', @(X,d) mean(X(d-7:d-1,:),1)
    'mean10          ', @(X,d) mean(X(d-10:d-1,:),1)
    'mean14          ', @(X,d) mean(X(d-14:d-1,:),1)
    'mean21          ', @(X,d) mean(X(d-21:d-1,:),1)
    'mean28w         ', @(X,d) mean(X(d-[7 14 21 28],:),1)
    '0.5lag1+0.5mean7', @(X,d) 0.5*X(d-1,:)+0.5*mean(X(d-7:d-1,:),1)
    '0.5lag7+0.5mean7', @(X,d) 0.5*X(d-7,:)+0.5*mean(X(d-7:d-1,:),1)
    'clim 历史同时刻均值', @(X,d) cummean_before(X,d)
};
fprintf('%-20s %9s %9s %9s %11s\n', '候选', 'MAE', 'RMSE', 'MAPE(%)', '白天RMSE');
for m = 1:size(pvCand,1)
    f = pvCand{m,2};
    [mae,rmse,mape,drmse] = score(P, f, q2);
    fprintf('%-20s %9.2f %9.2f %9.3f %11.2f\n', pvCand{m,1}, mae, rmse, mape, drmse);
end
fprintf('  （白天RMSE 只统计真值>100 kW 的时段，光伏夜间恒 0 不参与）\n\n');

%% ---------- 4. 逐月稳健性（MAPE %）----------
fprintf('---- 4. 逐月 MAPE（负载，检验方法是否全季节稳定）----\n');
fprintf('%6s %10s %10s %10s\n','月份','blend','lag7','mean7');
for mo = 2:12
    d0 = find(D.actual.dates == datetime(2025,mo,1));
    moEnd = eomday(2025,mo);
    idx = d0:(d0+moEnd-1); idx = idx(29<=idx & idx<=365);
    v = zeros(1,3);
    fs = {@(X,d) 0.5*X(d-7,:)+0.5*mean(X(d-[7 14 21 28],:),1), ...
          @(X,d) X(d-7,:), @(X,d) mean(X(d-7:d-1,:),1)};
    for j = 1:3
        [~,~,v(j)] = score(L, fs{j}, idx);
    end
    fprintf('%6d %10.3f %10.3f %10.3f\n', mo, v(1), v(2), v(3));
end

%% ---------- 5. 结论 ----------
fprintf('\n==========================================================\n');
fprintf(' 选型结论\n');
fprintf('  · 负载：blend = %.1f*lag7 + %.1f*mean28w\n', bestW.w, 1-bestW.w);
fprintf('  · 光伏：mean7 = 近 7 日同时刻均值\n');
fprintf('  · 物理诠释：负载有强「星期」周期（lag7 远胜 lag1 与 mean7），\n');
fprintf('    光伏受天气驱动、无星期结构（mean7 胜 lag7），两者的最优法不同。\n');
fprintf('==========================================================\n');
end

% ======================================================================
function [mae,rmse,mape,drmse] = score(X, f, days)
nt = size(X,2);
E = nan(numel(days), nt); Y = E;
for k = 1:numel(days)
    d = days(k);
    E(k,:) = f(X,d) - X(d,:);
    Y(k,:) = X(d,:);
end
mae  = mean(abs(E(:)));
rmse = sqrt(mean(E(:).^2));
mk   = Y > 50;   mape = mean(abs(E(mk)./Y(mk)))*100;
dk   = Y > 100;  drmse = sqrt(mean(E(dk).^2));
end

function c = cummean_before(X,d)
% 展开窗口气候态：第 d 天用第 1..d-1 天的同时刻均值（严格因果）
c = mean(X(1:d-1,:),1);
end
