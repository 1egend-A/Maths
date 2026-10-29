function t_charge_timing()
qc = q2_config();
D  = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码\out\data.mat').D;
pr = D.day144.price(:);
R  = load([qc.outdir 'q2_solution.mat']).R;
nd = numel(R.date);  nT = 144;

% 1) 每天 SOC 何时首次摸到 10800？何时跌到 1200？
tf = NaN(nd,1); tl = NaN(nd,1);
for k = 1:nd
    a = find(R.Soc(k,:) >= qc.S_max - 1e-6, 1);
    b = find(R.Soc(k,:) <= qc.S_min + 1e-6, 1);
    if ~isempty(a), tf(k) = a; end
    if ~isempty(b), tl(k) = b; end
end
fprintf('摸到 10800 的时段序号：中位 %s（%d 天）\n', slabel(median(tf(~isnan(tf)))), sum(~isnan(tf)));
fprintf('跌到 1200  的时段序号：中位 %s（%d 天）\n', slabel(median(tl(~isnan(tl)))), sum(~isnan(tl)));
fprintf('两者都在 0:00-6:00 的天数 = %d / %d\n\n', sum(tl < 36), nd);

% 2) 代表日（紧急购电中位的那天）逐小时 c/d/SOC
qem = R.qEm;  mk = find(qem == median(qem), 1);
fprintf('代表日 %s（当日紧急购电 %.1f kWh，中位）\n', string(R.date(mk)), qem(mk));
fprintf(' 小时    电价     充电/kWh   放电/kWh    时段末SOC\n');
for h = 0:23
    ii = h*6 + (1:6);
    fprintf('%2d-%2d  %6.4f   %8.1f  %8.1f   %8.1f\n', h, h+1, mean(pr(ii)), ...
        sum(R.c(mk,ii))*qc.dt, sum(R.d(mk,ii))*qc.dt, R.Soc(mk,ii(end)));
end

% 3) 低价窗口的吸收能力 vs 每日实际循环量
fprintf('\n每日充电量 中位 %.1f kWh，最大 %.1f kWh\n', median(sum(R.c,2))*qc.dt, max(sum(R.c,2))*qc.dt);
cheap = [22*6+1 : 24*6, 1:12, 11*6+1 : 13*6];   % 22-24, 0-2, 11-13
fprintf('上述六个低价小时的理论最大吸收 = 6*5000*dt = %.1f kWh/天\n', 6*5000*qc.dt);
fprintf('落在六个低价小时内的充电量占比 = %.1f %%\n', ...
    100*sum(sum(R.c(:,cheap),2))/sum(sum(R.c,2)));
end

function s = slabel(t)
m = (t-1)*10;  s = sprintf('%d:%02d', floor(m/60), mod(m,60));
end
