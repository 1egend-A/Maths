function t_charge_timing2()
qc = q2_config();
D  = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码\out\data.mat').D;
R  = load([qc.outdir 'q2_solution.mat']).R;
nd = numel(R.date);  nT = 144;  dt = qc.dt;

% 代表日：按当日总费用取中位
qem = R.qEm(:);  qem(isnan(qem)) = NaN;
[~, mk] = min(abs(R.costTot - median(R.costTot)));
fprintf('代表日 %s  （当日总费用 %.2f 元，中位）\n', string(R.date(mk)), R.costTot(mk));
fprintf(' 小时    电价     充电/kWh   放电/kWh   时段末SOC\n');
for h = 0:23
    ii = h*6 + (1:6);
    fprintf('%2d-%2d  %6.4f  %9.1f  %9.1f  %9.1f\n', h, h+1, ...
        mean(D.day144.price(ii)), sum(R.c(mk,ii))*dt, sum(R.d(mk,ii))*dt, R.Soc(mk,ii(end)));
end

fprintf('\n--- 校验论文原稿里 2025-09-23 的四个数 ---\n');
k = find(R.date == datetime(2025,9,23));
fprintf('夜间 0:00-4:00   充电 = %.2f kWh\n', sum(R.c(k, 1:24))*dt);
fprintf('上午 8:00-12:00  充电 = %.2f kWh\n', sum(R.c(k, 48:71))*dt);
fprintf('早上 4:00-8:00   放电 = %.2f kWh\n', sum(R.d(k, 24:47))*dt);
fprintf('下午 16:00-20:00 放电 = %.2f kWh\n', sum(R.d(k, 96:119))*dt);

fprintf('\n--- 高/中价充电占比 ---\n');
pr = D.day144.price(:);
cheap = [22*6+1:24*6, 1:12, 11*6+1:13*6];
cAll = sum(sum(R.c));
above = false(nT,1);
for j = 1:nT
    jj = mod(j-1,6)+1 + floor((j-1)/6)*6;                 % 归到小时内
    above(j) = mean(pr((floor((j-1)/6))*6 + (1:6))) > median(pr);
end
fprintf('六个最低价小时占比 = %.1f %%\n', 100*sum(sum(R.c(:,cheap)))/cAll);
fprintf('高于中位价时段占比 = %.1f %%\n', 100*sum(sum(R.c(:,above)))/cAll);
end
