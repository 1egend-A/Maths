function g0_feb01()
% G0_FEB01  阶段 0 验收闸门 G0：算 2025-02-01 0:00 的 SOC
%
% 为什么这是闸门：Q2/Q3 的优化区间从 2025-02-01 开始，但题目只给了
% 2025-01-01 0:00 的初始 SOC = 6000 kWh。2/1 的 SOC 必须把整个 1 月
% 逐日跑一遍才能得到（链式依赖）。
%
% 关键结论：这个值【强烈依赖「日末 SOC 口径」】。三种口径全部算出来，
% 三人必须先定死用哪个，否则 Q2/Q3 起点不同、结果不可比。

cfg = p0_config();
D   = p0_load(cfg);

janIdx = find(D.actual.dates >= datetime(2025,1,1) & D.actual.dates <= datetime(2025,1,31));

fprintf('##########################################################\n');
fprintf('⚠️  这不是题目答案，是【阶段 0 验收闸门 G0】的对照实验。\n');
fprintf('    目的：暴露「日末 SOC 口径」对结果影响多大。\n');
fprintf('    该口径目前【待定】（p0_config.m 口径 2），三种政策仅作比较。\n');
fprintf('##########################################################\n');
fprintf('==========================================================\n');
fprintf(' 阶段 0 验收闸门 G0：2025-02-01 0:00 的 SOC\n');
fprintf('==========================================================\n');
fprintf(' 一月天数        = %d\n', numel(janIdx));
fprintf(' 起始 SOC        = %.1f kWh (2025-01-01 0:00)\n', cfg.S0);
fprintf(' 效率口径        = %s\n', cfg.effConv);
fprintf(' SOC 允许区间    = [%.0f, %.0f] kWh\n', cfg.S_min, cfg.S_max);
fprintf('==========================================================\n\n');

pols = {'free', 'close', 'fixed'};
out  = struct();

for p = 1:numel(pols)
    c2 = cfg;
    c2.termPolicy = pols{p};

    S = cfg.S0;
    totCost = 0; Smin_t = S; Smax_t = S; badFlag = 0;
    traj = zeros(numel(janIdx),1);
    costd = zeros(numel(janIdx),1);

    for k = 1:numel(janIdx)
        i = janIdx(k);
        switch c2.termPolicy
            case 'free';  Se = [];
            case 'close'; Se = S;
            case 'fixed'; Se = c2.S_end;
        end
        [~, cc, dd, cost, info] = day_lp(D.actual.price(i,:), D.actual.load(i,:), ...
                                         D.actual.pv(i,:), S, c2, Se);
        if info.flag ~= 1
            badFlag = badFlag + 1;
        end
        [~, si] = soc_sim(cc, dd, S, c2);
        S = si.endS;

        traj(k) = S; costd(k) = cost;
        totCost = totCost + cost;
        Smin_t = min(Smin_t, si.minS);
        Smax_t = max(Smax_t, si.maxS);
    end

    fprintf(' 政策 %-6s → 2/1 0:00 SOC = %9.2f kWh | 一月总费用 %11.2f 元 | 一月内 SOC ∈ [%.1f, %.1f] | 求解异常 %d 天\n', ...
        pols{p}, S, totCost, Smin_t, Smax_t, badFlag);

    out.(pols{p}) = struct('SOC_feb1', S, 'costJan', totCost, 'traj', traj, ...
                           'costDay', costd, 'SOCmin', Smin_t, 'SOCmax', Smax_t, ...
                           'badFlag', badFlag);
end

fprintf('\n【结论】2/1 起始 SOC 完全由「日末 SOC 口径」决定，三种口径给出的值差异巨大。\n');
fprintf('        这一条必须三人当面定死并写进论文，否则 Q2/Q3 的起点不可比。\n');

fid = fopen(fullfile(cfg.outdir, 'g0_feb01.txt'), 'w', 'n', 'UTF-8');
fprintf(fid, '##########################################################\n');
fprintf(fid, '⚠️  这不是题目答案。这是【阶段 0 验收闸门 G0】的对照实验记录。\n');
fprintf(fid, '\n');
fprintf(fid, '它算的是 2025-02-01 0:00 的 SOC，用来暴露「日末 SOC 口径」对结果\n');
fprintf(fid, '的影响有多大。这些数字【不是】Q2/Q3 的答案：Q2 要用报童临界分位\n');
fprintf(fid, '建模、Q3 要滚动调整，本阶段都还没做。\n');
fprintf(fid, '\n');
fprintf(fid, '而且「日末 SOC 口径」目前是【待定】状态（p0_config.m 口径 2），\n');
fprintf(fid, '下面三种政策的结果只用于比较，采用哪一种须三人当面定死。\n');
fprintf(fid, '##########################################################\n');
fprintf(fid, '\nG0: 2025-02-01 0:00 SOC  (effConv=%s, S0=%.1f)\n\n', cfg.effConv, cfg.S0);
for p = 1:numel(pols)
    o = out.(pols{p});
    fprintf(fid, '政策 %-6s : SOC_feb1 = %.2f kWh, costJan = %.2f 元, SOC区间 [%.1f, %.1f], 异常 %d 天\n', ...
        pols{p}, o.SOC_feb1, o.costJan, o.SOCmin, o.SOCmax, o.badFlag);
end
fprintf(fid, '\n[free 政策] 一月逐日末 SOC:\n');
for k = 1:numel(janIdx)
    fprintf(fid, '  %s  %9.2f kWh   (当日费用 %10.2f 元)\n', ...
        datestr(D.actual.dates(janIdx(k)), 'yyyy-mm-dd'), out.free.traj(k), out.free.costDay(k));
end
fclose(fid);

save(fullfile(cfg.outdir, 'g0_feb01.mat'), 'out', '-v7.3');
fprintf('\n结果已写入: %s\n', fullfile(cfg.outdir, 'g0_feb01.txt'));

fprintf('\n[free 政策] 一月逐日末 SOC (kWh):\n');
for k = 1:numel(janIdx)
    fprintf('  %s  %9.2f\n', datestr(D.actual.dates(janIdx(k)), 'yyyy-mm-dd'), out.free.traj(k));
end
end
