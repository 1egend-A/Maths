function t_check_claims()
addpath('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码');
S = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\问题二\out\q2_solution.mat');
R = S.R; qc = S.qc;
D = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码\out\data.mat').D;
pr = D.day144.price(:);
lab = {'10:00-10:10','12:00-12:10','14:00-14:10','16:00-16:10','18:00-18:10','20:00-20:10'};
ts  = [61 73 85 97 109 121];
fprintf('--- 六个指定时段的电价 ---\n');
for i=1:6, fprintf('  时段%3d %s  p = %.6f 元/kWh\n', ts(i), lab{i}, pr(ts(i))); end
fprintf('  全日最低价 = %.4f (时段 %d)，最高价 = %.4f (时段 %d)\n', ...
    min(pr), find(pr==min(pr),1), max(pr), find(pr==max(pr),1));
fprintf('\n--- 各时段「全年 g=0 的天数」/334 ---\n');
for i=1:6, fprintf('  %s : %d 天\n', lab{i}, sum(R.gPlan(:,ts(i))<1e-9)); end
fprintf('\n--- 「16:00-20:00 充电量恒为 0」是否全 334 天成立 ---\n');
seg = 96/6;  % 时段 97..120 = 16:00-20:00
idx = 97:120;
cseg = sum(R.c(:,idx),2);
fprintf('  该四小时段充电量 > 0 的天数 = %d / %d\n', sum(cseg>1e-6), numel(cseg));
fprintf('  该段充电量最大值 = %.4f kWh\n', max(cseg));
% 六个 4 小时段的充电量全年统计
fprintf('\n--- 六个 4 小时段：全年充电量合计 / 最大值 / 非零天数 ---\n');
for b=1:6
    ii = (b-1)*24+(1:24);
    cc = sum(R.c(:,ii),2);
    fprintf('  段%d(时段%3d-%3d): 合计 %12.1f kWh, 单日最大 %9.2f, 非零 %3d 天\n', ...
        b, ii(1), ii(end), sum(cc), max(cc), sum(cc>1e-6));
end
fprintf('\n--- 334 天日 SOC 极值 ---\n');
mx = max(R.Soc,[],2); mn = min(R.Soc,[],2);
fprintf('  日最大 SOC: 全部 = 10800 的天数 = %d / %d，最小者 = %.4f\n', sum(abs(mx-10800)<1e-6), numel(mx), min(mx));
fprintf('  日最小 SOC: 全部 = 1200  的天数 = %d / %d，最大者 = %.4f\n', sum(abs(mn-1200)<1e-6),  numel(mn), max(mn));
fprintf('\n--- 紧急购电段统计 ---\n');
nseg = 0; lenAll = [];
for k=1:numel(R.date)
    m = R.gEm(k,:)*qc.dt > 1e-9;
    if ~any(m), continue; end
    d2 = diff([0 m 0]); s = find(d2==1); t2 = find(d2==-1)-1;
    nseg = nseg + numel(s);  lenAll = [lenAll; (t2-s+1)'];
end
fprintf('  全年段数 = %d，平均段长 = %.2f 时段，最大段长 = %d\n', nseg, mean(lenAll), max(lenAll));
e = R.gEm*qc.dt;  qd = sum(e,2);
fprintf('  发生紧急购电的天数 = %d，日均 %.1f，中位 %.1f，95%%分位 %.0f，最大 %.0f\n', ...
    sum(qd>1e-9), mean(qd), median(qd), quantile(qd,0.95), max(qd));
fprintf('  单向最大值(逐时段口径) = %.0f kWh\n', max(e(:)));
end
