function t_verify_q1()
% T_VERIFY_Q1  独立复核队友「问题一」结果（只做对照，不改任何模型口径）
%
% 背景：队友的 PDF 用 e_t（弃电/剩余电量）作为变量，平衡式 g+e+PV+d = L+c。
%       本项目的 day_lp 没有 e_t（等价于强制 e=0）。本脚本用 day_lp 独立重算，
%       与队友 PDF 的数字逐项对照，差异即为两处建模假设的差。
%
% 用法：matlab -batch "t_verify_q1"

cfg = p0_config();
D   = p0_load(cfg);
pr = D.day144.price(:); ld = D.day144.load(:); pv = D.day144.pv(:);
n  = numel(pr);

fprintf('==========================================================\n');
fprintf(' 问题一独立复核（本队 day_lp  vs  队友 PDF）\n');
fprintf('==========================================================\n');
fprintf('附件1 典型日 %d 时段\n', n);
fprintf('  电价 %.4f ~ %.4f 元/kWh\n', min(pr), max(pr));
fprintf('  负载 %.2f ~ %.2f kW\n', min(ld), max(ld));
fprintf('  光伏 %.2f ~ %.2f kW（非零 %d 段）\n', min(pv), max(pv), sum(pv>0));
sv = pv - ld;   % 正=光伏富余
fprintf('  光伏富余时段 %d 个，最大富余 %.2f kW（%.2f kWh/时段）\n', ...
    sum(sv>0), max(sv), max(sv)*cfg.dt);
fprintf('  储能单时段最大吞吐 %.2f kWh\n', cfg.P_max*cfg.dt);

% ================= 1. 基准：无储能，光伏优先供负载，缺口外购，富余弃用 =========
gBase = max(0, ld - pv);
baseQ = sum(gBase)*cfg.dt;
baseC = sum(pr .* gBase)*cfg.dt;
fprintf('\n---- 1. 基准（无储能）----\n');
fprintf('  本队  购电量 %9.2f kWh | 购电费 %10.2f 元\n', baseQ, baseC);
fprintf('  队友  购电量 %9.2f kWh | 购电费 %10.2f 元\n', 61789.94, 48052.05);
fprintf('  差    %+15.2f     | %+15.2f\n', baseQ-61789.94, baseC-48052.05);

% ================= 2. 优化：S0 = S_end = 6000（口径 2 'close'）=================
[g,c,d,cost,info] = day_lp(pr, ld, pv, cfg.S0, cfg, cfg.S0);
[S,si] = soc_sim(c,d,cfg.S0,cfg);
fprintf('\n---- 2. 优化（有储能，S0 = S_end = 6000）----\n');
fprintf('  linprog flag=%d  变量 %d  约束 %d\n', info.flag, info.nVar, info.nCon);
fprintf('  本队  购电量 %9.2f kWh | 购电费 %10.2f 元\n', sum(g)*cfg.dt, cost);
fprintf('  队友  购电量 %9.2f kWh | 购电费 %10.2f 元\n', 59482.70, 35126.95);
fprintf('  差    %+15.2f     | %+15.2f\n', sum(g)*cfg.dt-59482.70, cost-35126.95);
fprintf('  本队  累计充电 %9.2f | 累计放电 %9.2f kWh\n', sum(c)*cfg.dt, sum(d)*cfg.dt);
fprintf('  队友  累计充电 %9.2f | 累计放电 %9.2f kWh\n', 20740.67, 16799.94);
fprintf('  本队  SOC 最低 %.2f  最高 %.2f  末值 %.2f\n', si.minS, si.maxS, si.endS);
fprintf('  同时充放冲突时段 %d 个\n', sum(c>1e-6 & d>1e-6));

% ================= 3. 指定时段购电量 =================
segName = ["10:00-10:10","12:00-12:10","14:00-14:10","16:00-16:10","18:00-18:10","20:00-20:10"];
segEnd  = ["10:10","12:10","14:10","16:10","18:10","20:10"];
teammate= [0.00; 480.41; 0.00; 445.43; 531.89; 0.00];
fprintf('\n---- 3. 指定时段购电量（kWh）----\n');
fprintf('  %-14s %10s %10s %10s\n', '时段', '本队', '队友', '差');
for k = 1:numel(segEnd)
    idx = find(strcmp(string(D.slots.label), segEnd(k)), 1);
    if isempty(idx)
        fprintf('  %-14s  标签 %s 未找到\n', segName(k), segEnd(k)); continue;
    end
    v = g(idx)*cfg.dt;
    fprintf('  %-14s %10.2f %10.2f %+10.2f\n', segName(k), v, teammate(k), v-teammate(k));
end

% ================= 4. 分 4 小时充放电汇总 =================
fprintf('\n---- 4. 分 4 小时充放电汇总（kWh）----\n');
fprintf('  %-13s %10s %10s\n', '时段', '充电', '放电');
edg = 0:4:24;
seg = zeros(6,2);
for k = 1:6
    i1 = 6*edg(k)+1; i2 = 6*edg(k+1);
    seg(k,:) = [sum(c(i1:i2))*cfg.dt, sum(d(i1:i2))*cfg.dt];
    fprintf('  %2d:00-%2d:00  %10.2f %10.2f\n', edg(k), edg(k+1), seg(k,1), seg(k,2));
end
fprintf('  %-13s %10.2f %10.2f\n', '合计', sum(seg(:,1)), sum(seg(:,2)));
fprintf('\n  队友 PDF 充电: 4500.00 / 833.33 / 4787.96 / 5286.04 / 0.00 / 5333.33\n');
fprintf('  队友 PDF 放电:    0.00 / 6365.84 / 1703.00 / 2859.87 / 91.10 / 5780.13\n');

% ================= 5. 结论 =================
fprintf('\n==========================================================\n');
fprintf(' 供对照的真正「无储能」基准购电费 = %.2f 元\n', baseC);
fprintf(' 储能套利收益（本队）= %.2f 元（降幅 %.2f%%）\n', ...
    baseC - cost, (baseC-cost)/baseC*100);
fprintf(' 队友声称           = 12925.10 元（降幅 26.90%%）\n');
fprintf('==========================================================\n');
end
