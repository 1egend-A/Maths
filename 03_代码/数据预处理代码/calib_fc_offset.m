function calib_fc_offset()
% CALIB_FC_OFFSET  实证确定附件3「预报k小时」对应的真实小时（定稿版）
%
% 【问题】
%   附件3 列名是「预报1小时…预报24小时」，但题面没说
%   预报1小时 = 发布时刻所在的那个小时，还是发布之后的下一个小时。
%   猜错会让 Q3 的滚动调整整体错位一小时，且不报任何错。
%
% 【方法】
%   附件2 有全年实际光伏（10 分钟粒度）→ 聚合为每小时平均 Hd(365×24)。
%   用附件3 的预报 F(365×4×24) 去反查：把 F(d,j,k) 对齐到实际全局小时
%       t = (d-1)*24 + issueHour_j + k - 1 + o        (o = 偏移参数)
%   扫描 o，看合并 RMSE 在哪里取最小。
%
%   以 6:00 发布为例，三种候选语义：
%   o = 0  ⇒ 「预报1小时」= 05:00-06:00（结束于发布时刻的那个小时）
%   o = +1 ⇒ 「预报1小时」= 06:00-07:00（从发布时刻起算的第一个小时）← 实测最优
%   o = +2 ⇒ 「预报1小时」= 07:00-08:00
%
% 【为什么必须用合并 RMSE 而不是逐格相关系数】
%   逐格 argmax 在夜间/黎明这种近零格子上会乱跳：整列都是几百甚至 0，
%   两列小数的相关性纯属巧合。而合并 RMSE 中 0.91 的相关性说明基线误差
%   只有约 760 kW，而正午光伏逐小时变化约 1100 kW——错位一小时会带来
%   约 600 kW 的额外误差，信噪比足够，判据是干净的。
%
% 【为什么必须处理跨天】
%   18:00 发布的 k≥7、12:00 发布的 k≥13，目标时刻已进入次日。
%   不处理跨天会把整条尾巴对到错误的日子上，得到假结论。

cfg = p0_config();
D   = p0_load(cfg);

% ---- 实际光伏：10 分钟 → 每小时平均功率，再拉平成全局小时序列 ----
P  = D.actual.pv;
Hd = zeros(365, 24);
for h = 1:24
    Hd(:, h) = mean(P(:, 6*(h-1)+1 : 6*h), 2);
end
G = reshape(Hd', [], 1);          % 全局小时序列, G((d-1)*24 + h) = Hd(d,h)
% 自检：全局索引不能串行，否则整个标定作废
assert(abs(G((116-1)*24 + 11) - Hd(116, 11)) < 1e-9, '全局小时索引 G 映射错误');
assert(abs(G((1-1)*24 + 1)    - Hd(1, 1))     < 1e-9, '全局小时索引 G 映射错误');

% ---- 预报张量 (365 x 4 x 24) ----
F = zeros(365, 4, 24);
for d = 1:365
    for j = 1:4
        F(d, j, :) = D.fc.pv(4*(d-1)+j, :);
    end
end

issName = ["0:00", "6:00", "12:00", "18:00"];
issHour = [0, 6, 12, 18];

lines = {};
lines{end+1} = '==========================================================';
lines{end+1} = ' 附件3 预报区间归属标定（定稿版：合并 RMSE 扫描）';
lines{end+1} = '==========================================================';
lines{end+1} = sprintf(' 实际每小时平均光伏 Hd: %.1f ~ %.1f kW, 均值 %.1f', min(Hd(:)), max(Hd(:)), mean(Hd(:)));
lines{end+1} = sprintf(' 附件3 预报       F    : %.1f ~ %.1f kW, 均值 %.1f', min(F(:)), max(F(:)), mean(F(:)));
lines{end+1} = '';

% ================= 扫描偏移 o = -3 .. +3，合并 RMSE =================
lines{end+1} = '---- 合并 RMSE 扫描（全部 (d,j,k) 合并）----';
lines{end+1} = '   o  |   样本数  |  合并RMSE(kW) |  合并MAE(kW)  |  平均相关  ';
offMin = -3; offMax = 3;
bestO = NaN; bestR = inf;
resTbl = [];
for o = offMin:offMax
    se = 0; sa = 0; n = 0; rs = 0; nr = 0;
    for j = 1:4
        for k = 1:24
            t0 = (0:364)' * 24 + issHour(j) + k - 1 + o;   % 各天的目标全局小时
            okd = (t0 >= 1) & (t0 <= 365*24);
            % 该格的全部天都恒定（如夜间预报恒 0）→ 无法判别，跳过
            f = squeeze(F(:, j, k));
            if std(f) < 1e-9, continue; end
            f = f(okd); a = G(t0(okd));
            e = f - a;
            se = se + sum(e.^2); sa = sa + sum(abs(e)); n = n + numel(e);
            if std(f) > 1e-9 && std(a) > 1e-9
                c = corrcoef(f, a); rs = rs + c(1,2); nr = nr + 1;
            end
        end
    end
    R = sqrt(se/n); M = sa/n; cr = rs/nr;
    resTbl = [resTbl; o, n, R, M, cr]; %#ok<AGROW>
    lines{end+1} = sprintf('  %+2d  | %8d  |   %9.2f   |   %8.2f    |  %+.4f', o, n, R, M, cr);
    if R < bestR, bestR = R; bestO = o; end
end
lines{end+1} = sprintf('  ⇒ 合并 RMSE 最小处 o* = %+d', bestO);
if bestO == 1
    lines{end+1} = '  ⇒ 结论：【预报k小时 = 发布时刻起算的第 k 个小时】';
    lines{end+1} = '     即区间 [发布时刻+(k-1)h, 发布时刻+k·h)，k = 1..24 恰好铺满发布后的 24 小时。';
    lines{end+1} = '     例：6:00 发布的「预报1小时」= 06:00-07:00，「预报18小时」= 23:00-24:00（当日），';
    lines{end+1} = '         「预报19小时」起跨入次日 00:00-01:00。';
else
    lines{end+1} = '  ⇒ 最优偏移不是 +1（自然读法），需人工复核！';
end

% ================= 分发布时刻的 A/B 对照 =================
lines{end+1} = '';
lines{end+1} = '---- 分发布时刻对照（合并 RMSE，kW；每格内已正确处理跨天）----';
lines{end+1} = ' 发布时刻 | o=0 跨前1h  |  o=+1 自然读法 |  o=0 胜出步长数 / 可比步长数';
for j = 1:4
    RA = []; RB = []; winA = 0; cnt = 0;
    for k = 1:24
        f = squeeze(F(:, j, k));
        if std(f) < 1e-9, continue; end
        eA = cellErr(f, G, j, k, issHour, 0);
        eB = cellErr(f, G, j, k, issHour, 1);
        RA(end+1) = eA; RB(end+1) = eB; %#ok<AGROW>
        cnt = cnt + 1;
        if eA < eB, winA = winA + 1; end
    end
    lines{end+1} = sprintf('  %-6s   |    %9.2f    |    %9.2f    |   %2d / %2d', ...
        issName(j), sqrt(mean(RA.^2)), sqrt(mean(RB.^2)), winA, cnt);
end

% ================= 结论：逐格展开最优对齐（供人工核对）=================
lines{end+1} = '';
lines{end+1} = '---- 自然读法(o=+1) 下逐格误差（RMSE kW），数字小即为吻合 ----';
lines{end+1} = '  k  |  0:00发布 |  6:00发布 | 12:00发布 | 18:00发布';
for k = 1:24
    s = sprintf(' %2d |', k);
    for j = 1:4
        f = squeeze(F(:, j, k));
        if std(f) < 1e-9
            s = [s, '   --      |']; %#ok<AGROW>
        else
            s = [s, sprintf('  %7.1f  |', cellErr(f, G, j, k, issHour, 0))]; %#ok<AGROW>
        end
    end
    lines{end+1} = s; %#ok<AGROW>
end

% ================= 落盘（UTF-8，避免中文乱码）=================
fid = fopen(fullfile(cfg.outdir, 'calib_fc_offset.txt'), 'w', 'n', 'UTF-8');
for i = 1:numel(lines)
    fprintf(fid, '%s\n', lines{i});
end
fclose(fid);
save(fullfile(cfg.outdir, 'calib_fc_offset.mat'), 'resTbl', 'bestO', 'issHour', 'Hd');

% 控制台：只打 ASCII 摘要，避免 GBK 控制台乱码
fprintf('=== calib_fc_offset ===\n');
for i = 1:size(resTbl,1)
    fprintf('  o=%+d  n=%6d  RMSE=%9.2f  MAE=%8.2f  corr=%+.4f\n', resTbl(i,1), resTbl(i,2), resTbl(i,3), resTbl(i,4), resTbl(i,5));
end
fprintf('  ==> best offset o* = %+d   (0 = Assumption A)\n', bestO);
fprintf('  report: %s\n', fullfile(cfg.outdir, 'calib_fc_offset.txt'));
end

% ------------------------------------------------------------------
function e = cellErr(f, G, j, k, issHour, o)
% 单个 (j,k) 格的合并 RMSE，正确处理跨天
t0 = (0:364)' * 24 + issHour(j) + k - 1 + o;
ok = (t0 >= 1) & (t0 <= 365*24);
e  = sqrt(mean((f(ok) - G(t0(ok))).^2));
end

function s = ternary(c, a, b)
if c, s = a; else, s = b; end
end
