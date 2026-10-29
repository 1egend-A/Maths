function F = q2_forecast(D, qc)
% Q2_FORECAST  问题二的日前预测器（严格只用决策日之前的历史）
%
% 口径 7 取【严格字面】：问题二只用附件1（电价）+ 附件2（负载/光伏实际），
% 不引用附件3。因此第 d 天 0:00 制定计划时，负载与光伏都必须自己预测。
%
% 方法（由 t_forecast_backtest.m 在 334 天 × 144 时段 = 48096 个样本上回测选定）：
%   负载  f_load = 0.5*lag7 + 0.5*mean28w      MAPE 3.93%
%         lag7   = 上周同一天的同时刻值        （负载有强「星期」周期）
%         mean28w= 过去 4 周同一星期几的同时刻均值
%   光伏  f_pv   = mean7 = 近 7 日同时刻均值    RMSE 303.86 / 白天RMSE 430.19
%         （光伏由天气驱动、无星期结构，故 lag7 反而更差：RMSE 419.95）
%
% 历史不足时的退化（只影响开头几天；第 29 天起与上式完全一致）：
%   f_load: 可用星期几滞后不足 4 个时按可用的取均值；再不足则退回前一日的值
%   f_pv  : 前 7 天用「已有全部历史」的同时刻均值
%
% 输出 F:
%   F.Lhat / F.Phat / F.Nhat   365×144  负载/光伏/净负荷的日前预测（kW）
%   F.method                   方法说明字符串
%
% 注：第 d 天的预测只用到第 1..d-1 天的数据，严格无未来信息。

L = D.actual.load;      % 365×144
P = D.actual.pv;        % 365×144
nd = size(L,1);
nt = size(L,2);

F.Lhat = nan(nd, nt);
F.Phat = nan(nd, nt);

for d = 1:nd
    F.Lhat(d,:) = fcLoad(L, d);
    F.Phat(d,:) = fcPV(P, d);
end

F.Nhat = F.Lhat - F.Phat;

% 实际净负荷（供情景残差与事后核算用）
F.Nact = L - P;

F.method = sprintf('负载: 0.5*lag7+0.5*mean28w | 光伏: mean7 | 信息集: %s', qc.infoSet);

% 自查：第 29 天起应严格等于 0.5*lag7 + 0.5*mean28w
chk = 29;
ref = 0.5*L(chk-7,:) + 0.5*mean(L(chk-[7 14 21 28],:),1);
assert(max(abs(F.Lhat(chk,:) - ref)) < 1e-9, '负载预测与设计式不符');
refp = mean(P(chk-7:chk-1,:),1);
assert(max(abs(F.Phat(chk,:) - refp)) < 1e-9, '光伏预测与设计式不符');
end

% ======================================================================
function y = fcLoad(X, d)
% 负载预测：0.5*上周同日 + 0.5*近4周同星期几均值
ks = 7*(1:4);
ks = ks(d - ks >= 1);                  % 可用的同星期几滞后
if isempty(ks)
    y = X(max(1, d-1), :);             % 前 7 天：退化为前一日
else
    base = mean(X(d-ks, :), 1);        % ks=7 时即 lag7
    if d - 7 >= 1
        y = 0.5*X(d-7, :) + 0.5*base;
    else
        y = base;
    end
end
end

function y = fcPV(X, d)
% 光伏预测：近 7 日同时刻均值；历史不足时用已有全部历史
i1 = max(1, d-7);
y  = mean(X(i1:d-1, :), 1);
end
