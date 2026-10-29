function t_hourly_profile()
qc = q2_config();
D  = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码\out\data.mat').D;
pr = D.day144.price(:);
R  = load([qc.outdir 'q2_solution.mat']).R;
fprintf('小时  电价均值   全年充电量/kWh   有充电天数  全年放电量/kWh  有放电天数\n');
tot = 0;
for h = 0:23
    ii = h*6 + (1:6);
    ec = sum(sum(R.c(:,ii)))*qc.dt;
    ed = sum(sum(R.d(:,ii)))*qc.dt;
    tot = tot + ec;
    fprintf('%2d-%2d  %7.4f   %13.1f   %9d   %13.1f  %9d\n', h, h+1, ...
        mean(pr(ii)), ec, sum(sum(R.c(:,ii),2) > 1e-9), ed, sum(sum(R.d(:,ii),2) > 1e-9));
end
fprintf('\n全年充电合计 %.1f  放电合计 %.1f kWh\n', tot, sum(sum(R.d))*qc.dt);
end
