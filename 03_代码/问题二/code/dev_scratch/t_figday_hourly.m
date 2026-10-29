function t_figday_hourly()
qc = q2_config();
D  = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码\out\data.mat').D;
R  = load([qc.outdir 'q2_solution.mat']).R;
dt = qc.dt;
for d = [datetime(2025,9,23), datetime(2025,6,21)]
    k = find(R.date == d);
    fprintf('\n===== %s  （紧急购电 %.1f kWh，总费用 %.2f 元）=====\n', ...
        string(d), R.qEm(k), R.costTot(k));
    fprintf(' 小时   电价    充电/kWh  放电/kWh  时段末SOC\n');
    for h = 0:23
        ii = h*6 + (1:6);
        fprintf('%2d-%2d %6.4f %9.1f %9.1f %9.1f\n', h, h+1, ...
            mean(D.day144.price(ii)), sum(R.c(k,ii))*dt, sum(R.d(k,ii))*dt, R.Soc(k,ii(end)));
    end
    fprintf('  0:00=%.1f  24:00=%.1f  min=%.1f max=%.1f\n', ...
        R.Soc(k,1), R.Soc(k,144), min(R.Soc(k,:)), max(R.Soc(k,:)));
end
end
