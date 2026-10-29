function diag_fc()
% DIAG_FC  直接看附件3 预报与附件2 实际的对照，判断对齐关系
cfg = p0_config();
D   = p0_load(cfg);

P = D.actual.pv;
Hd = zeros(365,24);
for h = 1:24
    Hd(:,h) = mean(P(:, 6*(h-1)+1 : 6*h), 2);
end

F = zeros(365,4,24);
for d = 1:365
    for j = 1:4
        F(d,j,:) = D.fc.pv(4*(d-1)+j, :);
    end
end

fprintf('=== 实际每小时平均光伏 数值分布 ===\n');
fprintf('  Hd: min=%.1f max=%.1f mean=%.1f  >0 占 %.2f\n', ...
    min(Hd(:)), max(Hd(:)), mean(Hd(:)), mean(Hd(:)>0));
fprintf('=== 附件3 预报值分布 ===\n');
fprintf('  F : min=%.1f max=%.1f mean=%.1f  >0 占 %.2f\n', ...
    min(F(:)), max(F(:)), mean(F(:)), mean(F(:)>0));

% 找出实际光伏最大的那天
[~, li] = max(Hd(:));
[bd, bh] = ind2sub(size(Hd), li);
fprintf('\n实际光伏峰值: 第 %d 天 (2025 第 %d 日) 第 %d 小时 = %.1f kW\n', ...
    bd, bd, bh, Hd(bd,bh));

days = [bd, 166, 100];
for t = 1:numel(days)
    d = days(t);
    fprintf('\n########## 第 %d 天 (%s) ##########\n', d, datestr(D.actual.dates(d), 'yyyy-mm-dd'));
    fprintf(' 小时 |   实际   | 报0:00 报6:00 报12:00 报18:00 (预报第1小时)\n');
    for h = 1:24
        fprintf('  %2d  | %8.1f | %7.1f %7.1f %7.1f %7.1f\n', ...
            h-1, Hd(d,h), F(d,1,h), F(d,2,h), F(d,3,h), F(d,4,h));
    end
    fprintf(' 实际全天: %s\n', sprintf('%.0f ', Hd(d,:)));
end

% 相关性：实际 vs 预报各步长
fprintf('\n=== 相关系数（实际小时均值 vs 预报第k小时，全样本）===\n');
A = [];
for j = 1:4
    for k = 1:24
        f = zeros(365,1); hh = zeros(365,1);
        for d = 1:365
            f(d) = F(d,j,k);
            hh(d) = Hd(d,k);       % 同一天、同一小时（对齐到当天钟点）
        end
        c = corrcoef(f, hh);
        if k <= 6 || mod(k,6)==0
            fprintf('  发布 %s 预报%2d小时 : corr = %+.4f\n', ...
                string(D.fc.issue(4*(1-1)+j)), k, c(1,2));
        end
    end
end
end
