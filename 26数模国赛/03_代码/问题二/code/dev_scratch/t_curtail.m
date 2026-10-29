function t_curtail()
% T_CURTAIL  复核问题二「弃电」变量 curt 的量级与【来源分解】（工作纪实用）
%
% 背景：问题一发现弃电变量 e 从未被激活；本问重新复核，不沿用旧结论，且要分清
%       弃电到底来自「光伏装不下」还是「报童买多了」——两者在式 (13) 的 max(·)
%       里相加，事后不能凭总量区分，必须用解的结构来分。
%
% 关键代数（q2_solve.m 第 187-209 行）：
%   Q_raw = Ns + c - d  ⇒  z_(k80) = Nhat + c - d + r_(k80)
%   内点解（g>0）：g = Nhat + c - d + r_(k80)
%        ⇒ e = g + d - c - Nact = r_(k80) - r_act     ← 纯【计划侧富余】
%   边界解（z_(k80)<0 ⇒ g=0）：
%        ⇒ e = max(0, d - c - Nact)                    ← 真实的【光伏/供给富余】
%   故按 g>0 / g=0 分档，即可把两种来源分开。
rootDir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
cd(rootDir);
R = load(fullfile(rootDir,'out','q2_solution.mat')).R;
D = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码\out\data.mat').D;

dt = 1/6;
e    = R.curt;              % 334×144 kW
g    = R.gPlan;             % 计划购电量 kW
r    = R.Nact - R.Nhat;     % 当天实际残差（净负荷）
interior = g > 1e-9;        % 内点解：g > 0
eInt = e .* interior;
eBnd = e .* ~interior;

fprintf('==== 弃电总量与来源分解 ====\n');
fprintf('弃电总量                    = %12.1f kWh\n', sum(e(:))*dt);
fprintf('  内点档（g>0，计划侧富余）  = %12.1f kWh（占 %5.1f%%），时段数 %d\n', ...
    sum(eInt(:))*dt, 100*sum(eInt(:))/sum(e(:)), nnz(interior));
fprintf('  边界档（g=0，供给侧富余）  = %12.1f kWh（占 %5.1f%%），时段数 %d\n', ...
    sum(eBnd(:))*dt, 100*sum(eBnd(:))/sum(e(:)), nnz(~interior));

fprintf('\n==== 内点档的代数核验（应 e = r_(k80) - r_act）====\n');
% 复算 r_(k80)：用 F 里的残差样本（近 30 天）逐日取第 24 个次序统计量
nS = 30; k80 = ceil(0.8*nS);
% R.Nhat 按【求解日序号 k】排列，不是 data.mat 的行号，pool 取的是行号，
% 所以先把它摊回 365 行的完整数组；踩过坑。
nd = numel(R.dayIdx);
fullNhat = nan(size(D.actual.load));
fullNhat(R.dayIdx, :) = R.Nhat;
r80 = zeros(nd, 144);
for k = 1:nd
    d = R.dayIdx(k);  pool = (d-nS):(d-1);  pool = pool(pool>=1);
    Rm = (D.actual.load(pool,:)-D.actual.pv(pool,:)) - fullNhat(pool,:);
    S  = sort(Rm, 1, 'ascend');
    r80(k,:) = S(min(k80, size(S,1)), :);
end
pred = max(0, r80 - r);
err  = abs(e - pred);
fprintf('用 e = max(0, r_(k80) - r_act) 预测全表弃电：最大偏差 %.6f kW，均值 %.6f kW\n', ...
    max(err(:)), mean(err(:)));

fprintf('\n==== 与光伏发电量的对比 ====\n');
pv = D.actual.pv(R.dayIdx, :);
fprintf('同期实际光伏发电量 = %.1f kWh\n', sum(pv(:))*dt);
fprintf('边界档（真光伏富余）/ 光伏 = %.2f%%\n', 100*sum(eBnd(:))/sum(pv(:)));
fprintf('弃电总量         / 光伏 = %.2f%%\n', 100*sum(e(:))/sum(pv(:)));

fprintf('\n==== 边界档的时段分布（看是否落在午间）====\n');
bySlot = sum(eBnd, 1)*dt;
[~, ord] = sort(bySlot, 'descend');
for j = 1:6
    tt = ord(j);
    fprintf('  第 %3d 槽（%02d:%02d-%02d:%02d）边界档弃电 %10.1f kWh\n', tt, ...
        floor((tt-1)*10/60), mod((tt-1)*10,60), floor(tt*10/60), mod(tt*10,60), bySlot(tt));
end
fprintf('  边界档弃电集中在 10:00-15:00（槽 61-90）：%.1f kWh（占边界档 %.1f%%）\n', ...
    sum(bySlot(61:90)), 100*sum(bySlot(61:90))/sum(bySlot));

fprintf('\n==== 夜间（0:00-5:00，PV 恒为 0）====\n');
fprintf('  全部弃电 %.1f kWh —— 其中边界档 %.1f kWh（应为 0，PV=0 时不可能有供给富余）\n', ...
    sum(e(:,1:30),'all')*dt, sum(eBnd(:,1:30),'all')*dt);
end
