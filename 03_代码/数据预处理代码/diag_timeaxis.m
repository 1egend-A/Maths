function diag_timeaxis()
% DIAG_TIMEAXIS  判定附件1/2/4 时间轴的标注语义：起点标注 or 终点标注
%
% 【为什么这是根口径】
%   附件1/2 的时间列是 00:10,00:20,...,00:00+1（不是 0:00 起）。
%   附件5 模板的时间段也是 0:10-0:20,...,0:00+1-0:10+1。
%   两种语义给出【相差一个槽】的物理区间，会导致全年购电量整体错位 10 分钟。
%
% 【判据】中国分时电价按整点切换，跳变一定发生在整点边界。
%   若相邻两槽标号为 07:50 与 08:00 之间跳变 ⇒ 标号 = 区间【起点】
%   若相邻两槽标号为 08:00 与 08:10 之间跳变 ⇒ 标号 = 区间【终点】
%
% 【第二判据】光伏夜间恒 0、白天为正，日出/日落边界应对齐整点附近；
%   且 0 值段的长度应等于夜间时长（≈整点数）。

cfg = p0_config();
D   = p0_load(cfg);
L   = string(D.slots.label);        % 144 个标签

lines = {};
lines{end+1} = '==========================================================';
lines{end+1} = ' 时间轴语义判定（diag_timeaxis.m）';
lines{end+1} = '==========================================================';
lines{end+1} = sprintf(' 标签序列: %s ... %s', L(1), L(144));

% ---------------- 判据1：附件1 分时电价的跳变边界 ----------------
pr = D.day144.price(:);
lines{end+1} = '';
lines{end+1} = '---- 判据1：附件1 分时电价（每天相同）的阶梯边界 ----';
lines{end+1} = ' 找出相邻两槽电价不同的位置，打印两侧标签与价格：';
nchg = 0;
for i = 2:144
    if abs(pr(i) - pr(i-1)) > 1e-9
        nchg = nchg + 1;
        lines{end+1} = sprintf('   边界%2d : 槽%3d(标签 %-9s 价 %.4f) | 槽%3d(标签 %-9s 价 %.4f)', ...
            nchg, i-1, L(i-1), pr(i-1), i, L(i), pr(i));
    end
end
lines{end+1} = sprintf(' 附件1 电价共 %d 处跳变', nchg);

% 规范化判断：跳变的"右侧标签"是不是整点（HH:00）
rightIsHour = true; leftIsHour = true;
for i = 2:144
    if abs(pr(i) - pr(i-1)) > 1e-9
        hR = labelMinutes(L(i));   hL = labelMinutes(L(i-1));
        if mod(hR, 60) ~= 0, rightIsHour = false; end
        if mod(hL, 60) ~= 0, leftIsHour  = false; end
    end
end
lines{end+1} = sprintf('   ⇒ 所有跳变的【右侧】标签都是整点? %s', string(rightIsHour));
lines{end+1} = sprintf('   ⇒ 所有跳变的【左侧】标签都是整点? %s', string(leftIsHour));
if rightIsHour && ~leftIsHour
    lines{end+1} = '   ⇒ 判据1 结论：【标号 = 区间终点】(整点处换价，新价从整点后的那一槽开始)';
elseif leftIsHour && ~rightIsHour
    lines{end+1} = '   ⇒ 判据1 结论：【标号 = 区间起点】(整点处换价，新价从整点那一槽开始)';
else
    lines{end+1} = '   ⇒ 判据1 不确定，需看判据2';
end

% 附件1 电价逐槽明细（便于人工核对阶梯形状）
lines{end+1} = '';
lines{end+1} = ' 附件1 电价逐槽（每 3 槽一行，即每 30 分钟一行）：';
for i = 1:3:144
    j = min(i+2, 144);
    s = '';
    for k = i:j
        s = [s sprintf('%s=%.4f  ', L(k), pr(k))]; %#ok<AGROW>
    end
    lines{end+1} = ['   ' s]; %#ok<AGROW>
end

% ---------------- 判据2：附件2 光伏的昼夜边界 ----------------
PV = D.actual.pv;
lines{end+1} = '';
lines{end+1} = '---- 判据2：附件2 光伏的日出/日落边界（取 6/21 与 12/21 两天）----';
% 2025-06-21 是该年第 172 天, 2025-12-21 是第 355 天
for d = [172, 355]
    v = PV(d, :);
    lines{end+1} = sprintf(' 第 %d 天 (%s)：', d, datestr(D.actual.dates(d), 'yyyy-mm-dd'));
    firstPos = find(v > 1e-9, 1, 'first');
    lastPos  = find(v > 1e-9, 1, 'last');
    if ~isempty(firstPos)
        lines{end+1} = sprintf('   首个 >0 槽 : 第%3d 槽 标签 %s  值 %.2f', firstPos, L(firstPos), v(firstPos));
        lines{end+1} = sprintf('   末个 >0 槽 : 第%3d 槽 标签 %s  值 %.2f', lastPos,  L(lastPos),  v(lastPos));
        lines{end+1} = sprintf('   夜间 0 值段: 槽 %d..144 与 1..%d', lastPos+1, firstPos-1);
    end
end

% ---------------- 判据3：附件4 近零电价的位置 ----------------
v4 = D.actual.price(:);
lines{end+1} = '';
lines{end+1} = '---- 判据3：附件4 全年近零(<0.10)电价发生时点的标签分布 ----';
idx = find(v4 < 0.10);
lines{end+1} = sprintf(' 共 %d 个 <0.10 的槽', numel(idx));
inDay = 0; edge = 0;
for t = 1:numel(idx)
    d = floor((idx(t)-1)/144) + 1;
    hh = mod(idx(t)-1, 144) + 1;
    if hh >= 61 && hh <= 102      % 标签 10:10..17:00 视为白天中段
        inDay = inDay + 1;
    else
        edge = edge + 1;
    end
    if t <= 12
        lines{end+1} = sprintf('   #%2d : 日期索引%3d 槽%3d 标签 %-9s 价 %.4f', t, d, hh, L(hh), v4(idx(t)));
    end
end
lines{end+1} = sprintf(' 其中落在【槽标签 10:10~17:00】区间内 = %d，其余 = %d', inDay, edge);

fid = fopen(fullfile(cfg.outdir, 'diag_timeaxis.txt'), 'w', 'n', 'UTF-8');
for i = 1:numel(lines), fprintf(fid, '%s\n', lines{i}); end
fclose(fid);
fprintf('diag_timeaxis done -> %s\n', fullfile(cfg.outdir, 'diag_timeaxis.txt'));

% 控制台 ASCII 摘要
fprintf('=== time axis ===\n');
fprintf('  right label at price step is whole hour : %d\n', rightIsHour);
fprintf('  left  label at price step is whole hour : %d\n', leftIsHour);
fprintf('  price steps = %d\n', nchg);
fprintf('  near-zero price slots: total %d, midday %d\n', numel(idx), inDay);
end

% ------------------------------------------------------------------
function m = labelMinutes(lbl)
% '19:10' -> 1150 ; '0:00+1' -> 1440
s = char(lbl);
plusOne = endsWith(s, '+1');
s = erase(s, '+1');
p = strsplit(s, ':');
m = str2double(p{1})*60 + str2double(p{2});
if plusOne, m = m + 1440; end
end
