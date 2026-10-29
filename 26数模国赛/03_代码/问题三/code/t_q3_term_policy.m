function Tab = t_q3_term_policy()
% T_Q3_TERM_POLICY  口径 2 敏感性：日末储电量固定 6000 vs 放开闭环
%
% 题面只对问题一写了「储能设备在 0:00 和 24:00 的储电量相同」；问题二/三/四
% 都只说「每天的购电策略」。本队四问统一采用 S_0 = S_144 = 6000，为的是四问可比。
% 本脚本量化这个决定在问题三上花了多少钱。
%
% ★ 对照必须给日末储能计价，否则储能可以"白拿"
%   放开末槽后，模型有强烈动机把电池留空（S_144 → 1200）来少买电，第二天再充。
%   那省下的不是真钱，是把电量欠到了明天。故对照口径取
%        净费用 = 当日购电费 − p̄_d · (S_144 − S_0)
%   即日末多出来的储能按当日【电量加权平均购电价】作价（留电 = 少花了明天的钱，
%   故从费用里减掉）。这样才能把两种闭环政策放在同一张账上比。
%   若不做这步计价，'free' 会比 'close' 便宜一大截，而那是纯粹的记账假象。
%
% 问题三电价逐日相同 ⇒ 跨日搬运没有价差 ⇒ 预期两种政策的净费用几乎相同。
% 问题四电价逐日不同 ⇒ 跨日价差出现，这个对照才会变得有意义（见 t_q4_term_policy.m）。
%
% 落盘：out/t_q3_term_policy.csv / out/t_q3_term_policy.mat / .txt
%
% 用法：Tab = t_q3_term_policy();

D  = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码\out\data.mat').D;
qc = q3_config();

fprintf('===== 口径 2 敏感性：日末储电量 固定 6000 vs 放开 =====\n');

% ---- A. 基准（close）：直接复用已落盘的结果，避免重复求解 ----
solFile = [qc.outdir 'q3_solution.mat'];
if isfile(solFile)
    Ra = load(solFile).R;
    fprintf('  [close] 复用已落盘的 q3_solution.mat\n');
else
    qa = qc;  qa.termPolicy = 'close';  qa.verbose = false;
    F  = q3_forecast(D, qa);   Ra = q3_solve(D, F, qa);
end
cA = sum(Ra.Sadj);

% ---- B. 放开日末闭环 ----
qb = qc;  qb.termPolicy = 'free';  qb.verbose = false;
fprintf('  [free ] 求解中（末槽只受 [%g, %g] 约束）...\n', qb.S_min, qb.S_max);
Fb = q3_forecast(D, qb);
Rb = q3_solve(D, Fb, qb);

% ---- C. 给日末储能偏差计价 ----
% p̄_d = 当日电量加权平均购电价（元/kWh）
pr = Rb.price;
qBuy = Rb.A + Rb.gEm;                                   % nd×144，kWh 当量功率
qSum = sum(qBuy, 2);
pBar = sum(pr .* qBuy, 2) ./ max(qSum, eps);
dS   = Rb.Soc(:,end) - qc.S0;                            % 日末储能相对 6000 的偏差 kWh
valAdj = pBar .* dS;                                     % 留电作价（元）
cB_raw = sum(Rb.Sadj);
cB_net = cB_raw - sum(valAdj);

Tab = table({'close 固定 6000'; 'free 放开末槽'}, ...
    [cA; cB_raw], [0; sum(valAdj)], [cA; cB_net], ...
    [0; cB_net - cA], [0; 100*(cB_net-cA)/cA], ...
    [0; mean(Rb.Soc(:,end))], [0; min(Rb.Soc(:,end))], [0; max(Rb.Soc(:,end))], ...
    'VariableNames', {'政策','购电费','日末储能作价','净费用','较close差','较close差_pct', ...
                      '日末SOC均值','日末SOC最小','日末SOC最大'});

fprintf('\n%-18s %14s %14s %14s %12s %10s\n', ...
    '政策','购电费','日末储能作价','净费用','较close差','差%');
fprintf('%-18s %14.2f %14.2f %14.2f %12s %10s\n', ...
    'close 固定 6000', cA, 0, cA, '—', '—');
fprintf('%-18s %14.2f %14.2f %14.2f %12.2f %10.3f\n', ...
    'free 放开末槽', cB_raw, sum(valAdj), cB_net, cB_net-cA, 100*(cB_net-cA)/cA);
fprintf('\n  free 政策下日末储电量：均值 %.1f，范围 [%.1f, %.1f] kWh\n', ...
    mean(Rb.Soc(:,end)), min(Rb.Soc(:,end)), max(Rb.Soc(:,end)));
fprintf('  日末储能作价合计 %.2f 元（占购电费 %.3f%%）——不做这步作价，\n', ...
    sum(valAdj), 100*sum(valAdj)/cB_raw);
fprintf('  free 会因"把电欠到明天"而虚低 %.2f 元，是不可比的口径。\n', sum(valAdj));

% ---- 落盘 ----
outdir = qc.outdir;  if ~isfolder(outdir), mkdir(outdir); end
writetable(Tab, [outdir 't_q3_term_policy.csv'], 'Encoding', 'UTF-8');
cA_ = cA; cB_raw_ = cB_raw; cB_net_ = cB_net; valAdj_ = valAdj; pBar_ = pBar;
save([outdir 't_q3_term_policy.mat'], 'Tab', 'cA_', 'cB_raw_', 'cB_net_', 'valAdj_', 'pBar_');
txt = { '口径 2 敏感性：日末储电量 固定 6000 vs 放开末槽（问题三）'; ...
        '=========================================================='; ...
        sprintf('区间：%s ~ %s，%d 天', string(qc.dateFirst), string(qc.dateLast), numel(qc.dayIdx)); ...
        ''; ...
        '【对照口径】净费用 = 购电费 − p̄_d·(S_144 − S_0)'; ...
        '        p̄_d = 当日电量加权平均购电价；日末留在电池里的电按这个价作价后从费用中扣除。'; ...
        '        不作价则 free 政策可以把电"欠到明天"，是记账假象。'; ...
        ''; ...
        sprintf('close（固定 6000）净费用 %.2f 元', cA); ...
        sprintf('free （放开末槽）购电费 %.2f 元，日末储能作价 %.2f 元，净费用 %.2f 元', ...
                cB_raw, sum(valAdj), cB_net); ...
        sprintf('差异 %.2f 元（%.3f%%）', cB_net - cA, 100*(cB_net-cA)/cA); ...
        ''; ...
        '【结论】问题三电价逐日相同，跨日搬运储能不存在价差，故放开日末闭环的收益'; ...
        '        基本为零（仅剩"削峰填谷在时间上跨界"的一点余量）。四问统一采用'; ...
        '        固定 6000 是安全的、且保证四问可比。'; ...
      };
fid = fopen([outdir 't_q3_term_policy.txt'], 'w', 'n', 'UTF-8');
fprintf(fid, '%s\n', strjoin(txt, sprintf('\n')));
fclose(fid);
fprintf('\n  已写出：%s\n', [outdir 't_q3_term_policy.csv']);
end
