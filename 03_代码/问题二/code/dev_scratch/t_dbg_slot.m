addpath('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码');
S = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\问题二\out\q2_solution.mat');
R = S.R; qc = S.qc;
D = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码\out\data.mat').D;
dt = qc.dt; pr = D.day144.price(:);
fprintf('电价：min=%.4f max=%.4f mean=%.4f\n', min(pr), max(pr), mean(pr));
fprintf('指定时段电价：\n');
for t = [61 73 85 97 109 121]
    fprintf('  时段%3d (%s) 电价 = %.4f 元/kWh\n', t, tl((t-1)*10), pr(t));
end
% 检查 gPlan 在各指定时段的分布（全年）
fprintf('\ngPlan 在指定时段为 0 的天数 / 334：\n');
for t = [61 73 85 97 109 121]
    col = R.gPlan(:,t);
    fprintf('  时段%3d (%s): 0 值 %3d 天，均值 %8.2f kW，最大 %9.1f kW\n', ...
        t, tl((t-1)*10), sum(col<1e-9), mean(col), max(col));
end
% 逐时段 gPlan 全年为零的天数（看是否普遍）
zer = sum(R.gPlan < 1e-9, 1);
fprintf('\n全年各时段「g=0」天数：最少 %d 天（时段 %d），最多 %d 天（时段 %d）\n', ...
    min(zer), find(zer==min(zer),1), max(zer), find(zer==max(zer),1));
fprintf('  指定时段：%s\n', mat2str(zer([61 73 85 97 109 121])));
% 2025-03-20 明细
k = find(R.date == datetime(2025,3,20));
fprintf('\n2025-03-20 的 Q 分位与 g（指定时段前后各看几个）：\n');
fprintf(' k=%d 日期=%s\n', k, string(R.date(k)));
for t = 57:2:67
    fprintf('  时段%3d %s  p=%.4f  N=%8.1f  c=%7.1f  d=%7.1f  g=%8.2f\n', ...
        t, tl((t-1)*10), pr(t), R.Nact(k,t), R.c(k,t), R.d(k,t), R.gPlan(k,t));
end
% 该日 g=0 的连续段
g0 = R.gPlan(k,:) < 1e-9;
d2 = diff([0 g0 0]); s = find(d2==1); t2 = find(d2==-1)-1;
fprintf('\n2025-03-20 g=0 的时段段数 = %d，合计 %d 个时段\n', numel(s), sum(g0));
fprintf('  前 8 段：'); for z=1:min(8,numel(s)), fprintf(' %s', tl((s(z)-1)*10)); end; fprintf('\n');

function s = tl(minute)
h = floor(minute/60); mi = mod(minute,60);
if h>=24, s='24:00'; else, s=sprintf('%d:%02d',h,mi); end
end
