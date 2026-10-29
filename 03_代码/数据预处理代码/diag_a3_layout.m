function diag_a3_layout()
% DIAG_A3_LAYOUT  无假设检验附件3 的行结构
%
% 不预设 (day-major, issue-minor)，直接问：
%   对若干测试日，附件3 的哪一行与该日【实际小时曲线】相关性最高？
% 若行索引正确，最佳行必定是 4*(d-1)+1..4*(d-1)+4 中的一个，且 r 应很高。
% 若 r 普遍很低（<0.5），说明附件3 与附件2 的光伏根本不是同一条曲线，
% 之前所有基于它的结论都必须推翻。

cfg = p0_config(); D = p0_load(cfg);
[NR, NC] = size(D.fc.pv);
fprintf('D.fc.pv 尺寸 = %d x %d ， D.actual.pv 尺寸 = %d x %d\n', ...
    NR, NC, size(D.actual.pv,1), size(D.actual.pv,2));

ah = zeros(365,24);
for h = 1:24, ah(:,h) = mean(D.actual.pv(:, 6*(h-1)+(1:6)), 2); end

L = {};
L{end+1} = '==========================================================';
L{end+1} = ' 附件3 行结构无假设检验（diag_a3_layout.m）';
L{end+1} = '==========================================================';
L{end+1} = sprintf('  D.fc.pv = %d x %d ;  D.actual.pv = 365 x 144', NR, NC);
L{end+1} = '';
L{end+1} = ' 对每个测试日，扫描全部附件3 行，列出相关性最高的 3 行，并检查';
L{end+1} = ' 它们是否落在 4*(d-1)+1 .. 4*(d-1)+4 这个"日块"内。';
L{end+1} = '';
L{end+1} = '   测试日 |  最佳行 |    r    | 次佳行 |    r    | 第3行 |    r    | 日块范围';

tests = [32 60 100 150 200 250 300 365];
for d = tests
    a = ah(d,:);
    rr = zeros(NR,1);
    for r = 1:NR
        x = D.fc.pv(r,:); y = a;
        if std(x) < 1e-9 || std(y) < 1e-9, rr(r) = NaN; continue; end
        c = corrcoef(x, y); rr(r) = c(1,2);
    end
    [~, ord] = sort(rr, 'descend', 'MissingPlacement','last');
    top = ord(1:3);
    lo = 4*(d-1)+1; hi = 4*(d-1)+4;
    L{end+1} = sprintf('   %5d  |  %5d  | %+6.3f  | %5d  | %+6.3f  | %5d | %+6.3f  | %d..%d %s', ...
        d, top(1), rr(top(1)), top(2), rr(top(2)), top(3), rr(top(3)), lo, hi, ...
        ternary(all(top>=lo & top<=hi), '<== 命中', '<== 未命中'));
end

% ---- 四行日块内部比较：同一日 4 个发布时刻行，谁与实际最像 ----
L{end+1} = '';
L{end+1} = ' 日块内部：每一日的 4 行分别与实际日的相关性（行=日，列=发布次序 1..4）';
L{end+1} = '   日   |   行1    行2    行3    行4   |  该日实际曲线峰值(kW)';
for d = tests(1:min(4,numel(tests)))
    lo = 4*(d-1)+1; hi = lo+3;
    rs = zeros(1,4);
    for r = lo:hi
        c = corrcoef(D.fc.pv(r,:), ah(d,:)); rs(r-lo+1) = c(1,2);
    end
    L{end+1} = sprintf('  %5d | %s |  %8.1f', d, sprintf('%+6.3f ', rs), max(ah(d,:)));
end

% ---- 直接目视：某一日的实际 vs 预报 ----
L{end+1} = '';
L{end+1} = ' 目视对照（日 = 200，取该日块第 1 行 = 0:00 发布）:';
L{end+1} = '   小时 |    实际     |    预报     |   差值';
d = 200; r = 4*(d-1)+1;
for h = 1:24
    L{end+1} = sprintf('   %4d | %10.1f  | %10.1f  | %8.1f', ...
        h, ah(d,h), D.fc.pv(r,h), D.fc.pv(r,h)-ah(d,h));
end

fid = fopen(fullfile(cfg.outdir,'diag_a3_layout.txt'), 'w', 'n', 'UTF-8');
for i = 1:numel(L), fprintf(fid, '%s\n', L{i}); end
fclose(fid);
fprintf('diag_a3_layout -> %s\n', fullfile(cfg.outdir,'diag_a3_layout.txt'));
end

% ------------------------------------------------------------------
function s = ternary(c, a, b)
if c, s = a; else, s = b; end
end
