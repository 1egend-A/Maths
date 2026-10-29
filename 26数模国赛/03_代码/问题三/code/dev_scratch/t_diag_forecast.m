% T_DIAG_FORECAST  附件3 官方预报 vs 自预测：偏倚/相关/融合价值（非交付物）
S = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码\out\data.mat');
D = S.D;
qc = q3_config();  qc.verbose = false;
qc.outdir = 'D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\问题三\code\dev_scratch\out\';
F = q3_forecast(D, qc);

dr = qc.dayIdx(:);  P = D.actual.pv(dr,:);
A3 = F.Phat4(dr,:,1);        % 附件3 0:00 预报
SE = F.PhatSelf(dr,:);       % 自预测 mean7
day = false(1,144); day(37:108) = true;      % 06:00-18:00 视为白天（光伏非零）
fprintf('=== 全时段（144 槽）===\n');
fprintf('  附件3 : RMSE %7.2f | 偏倚 %+7.2f | 去偏后 RMSE %7.2f\n', ...
    rmse(A3,P), mean(A3(:)-P(:)), rmse(A3-mean(A3(:)-P(:)), P));
fprintf('  自预测: RMSE %7.2f | 偏倚 %+7.2f | 去偏后 RMSE %7.2f\n', ...
    rmse(SE,P), mean(SE(:)-P(:)), rmse(SE-mean(SE(:)-P(:)), P));
e1 = A3-P; e2 = SE-P;
fprintf('  两误差相关系数 = %+.4f\n', corr(e1(:), e2(:)));

fprintf('=== 白天（06:00-18:00，%d 槽）===\n', sum(day));
a = A3(:,day); s = SE(:,day); p = P(:,day);
fprintf('  附件3 : RMSE %7.2f | 偏倚 %+7.2f | 去偏后 RMSE %7.2f\n', ...
    rmse(a,p), mean(a(:)-p(:)), rmse(a-mean(a(:)-p(:)), p));
fprintf('  自预测: RMSE %7.2f | 偏倚 %+7.2f | 去偏后 RMSE %7.2f\n', ...
    rmse(s,p), mean(s(:)-p(:)), rmse(s-mean(s(:)-p(:)), p));
fprintf('  两误差相关系数 = %+.4f\n', corr((a(:)-p(:)), (s(:)-p(:))));

% 最优线性融合 w*a3 + (1-w)*self
ws = 0:0.05:1;  rr = zeros(size(ws));
for i = 1:numel(ws)
    rr(i) = rmse(ws(i)*a + (1-ws(i))*s, p);
end
[best, ib] = min(rr);
fprintf('  白天最优线性融合：w(附件3) = %.2f → RMSE %7.2f（当前 附件3 单独 %.2f，自预测单独 %.2f）\n', ...
    ws(ib), best, rmse(a,p), rmse(s,p));

% 按发布时刻看「同一槽位」的精度改善（消除"剩余时段不同"的混淆）
fprintf('=== 同一槽位上，等到 τ 时刻再报 的精度（只统计 06:00-18:00 的白天槽）===\n');
for j = 2:4
    tau = qc.fcIssHours(j);
    cols = find(day & ((1:144) > 6*tau));
    if isempty(cols), continue; end
    A3j = F.Phat4(dr,cols,j);
    fprintf('  τ=%02d:00（%2d 个白天槽）本期预报 RMSE %7.2f | 而 0:00 预报在同一批槽上 RMSE %7.2f | 改善 %+.1f%%\n', ...
        tau, numel(cols), rmse(A3j,P(:,cols)), rmse(A3(:,cols),P(:,cols)), ...
        100*(rmse(A3(:,cols),P(:,cols))-rmse(A3j,P(:,cols)))/rmse(A3(:,cols),P(:,cols)));
end

function r = rmse(A,P)
r = sqrt(mean((A(:)-P(:)).^2));
end
