function t_cycle_check()
qc = q2_config();
D  = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码\out\data.mat').D;
R  = load([qc.outdir 'q2_solution.mat']).R;
nd = numel(R.date); dt = qc.dt;

% (1) 晚间触底：21:00 末（slot 126）是否为每日最低 1200
fprintf('SOC(21:00) = 1200 的天数        : %d / %d\n', sum(abs(R.Soc(:,126)-qc.S_min)<1e-6), nd);
fprintf('SOC(10:30) 附近触底的天数(slot<=66): %d / %d\n', ...
    sum(min(R.Soc(:,1:66),[],2) < qc.S_min+1e-6), nd);

% (2) 21:00-24:00 充电量是否每天完全相同
blk = sum(R.c(:, 21*6+1:24*6), 2)*dt;
fprintf('\n21:00-24:00 日充电量: 均值 %.2f  标准差 %.4f  最小 %.2f  最大 %.2f\n', ...
    mean(blk), std(blk), min(blk), max(blk));
fprintf('  恰等于 5333.3 的天数 = %d / %d\n', sum(abs(blk-5333.333)<1e-3), nd);

% (3) SOC 日内触底次数（下穿 1200 的独立次数）
nTrough = zeros(nd,1);
for k = 1:nd
    m = abs(R.Soc(k,:) - qc.S_min) < 1e-6;
    nTrough(k) = sum(diff([0 m 0]) == 1);
end
fprintf('\n日内触底(1200)次数分布: %s\n', mat2str(histcounts(nTrough, 0:5)));
fprintf('  触底 2 次的天数 = %d / %d\n', sum(nTrough==2), nd);
end
