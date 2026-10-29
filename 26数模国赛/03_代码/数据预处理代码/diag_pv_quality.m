function diag_pv_quality()
% DIAG_PV_QUALITY  附件3 预报质量 vs 持续性外推 —— 判别与混合
%
% 回答三个问题：
%   A) cfg.fcOffset=+1 在【每一个发布时刻】上是否都成立？（按发布时刻分列重扫）
%   B) 附件3 官方预报是否真的打不过「昨天照抄」？（只看白天，排除夜间噪声）
%   C) 两者加权混合能否同时打败各自？

cfg = p0_config(); D = p0_load(cfg);
dd  = (32:365)';                       % 2025-02-01 .. 12-31
nd  = numel(dd);

% ---- 全局小时序列 G（实际值的小时均值），G((d-1)*24+h) ----
ah = zeros(365,24);
for h = 1:24, ah(:,h) = mean(D.actual.pv(:, 6*(h-1)+(1:6)), 2); end
G = zeros(1, 365*24);
for d = 1:365, G((d-1)*24+(1:24)) = ah(d,:); end

oss = -3:3;
L = {};
L{end+1} = '==========================================================';
L{end+1} = ' 附件3 预报质量判别（diag_pv_quality.m）';
L{end+1} = '==========================================================';
L{end+1} = '';
L{end+1} = '【A】按发布时刻分列的偏移量扫描';
L{end+1} = '  判据1 = 全部小时单元的 RMSE；判据2 = 仅白天(实际>50kW)单元的 RMSE+相关系数';
L{end+1} = '  行 = 发布时刻；列 = 偏移量 o（预报k小时 ==> 全局小时 issueHour+(k-1)+o）';

for j = 1:4
    ih = cfg.fcIssHours(j);
    L{end+1} = '';
    L{end+1} = sprintf('  --- 发布时刻 %d:00 ---', ih);
    L{end+1} = '    o    |  全部RMSE  |  白天RMSE  |   白天r   |  白天单元数';
    for o = oss
        t0 = (dd-1)*24 + ih + (1:24) - 1 + o;        % nd×24
        Fm = D.fc.pv(4*(dd-1)+j, :);                 % nd×24
        ok = (t0 >= 1) & (t0 <= 365*24);
        % ⚠️ 必须显式转列：G 是【行】向量而 t0(ok) 是【列】向量，
        %    直接相减会触发隐式扩展，得到 8016×8016 的矩阵。
        gm = G(t0(ok)); gm = gm(:);
        e  = Fm(ok);    e  = e(:) - gm;
        day = abs(gm) > 50;
        L{end+1} = sprintf('   %+2d   |  %8.2f  |  %8.2f  |  %+7.4f  |  %6d', ...
            o, sqrt(mean(e.^2)), sqrt(mean(e(day).^2)), rho(e(day), gm(day)), sum(day));
    end
end

% ---- B) 官方预报 vs 持续性，10 分钟口径 ----
L{end+1} = '';
L{end+1} = '【B】10 分钟口径：附件3(0:00列, o=cfg.fcOffset) vs 昨日持续性';
Sm = pv_shape(D, cfg);
A = D.actual.pv(dd, :);                              % nd×144 实际
f3 = zeros(nd,24); pres = zeros(nd,24);
for i = 1:nd
    d = dd(i);
    t0 = (d-1)*24 + 0 + (1:24) - 1 + cfg.fcOffset;
    ok = (t0>=1) & (t0<=365*24);
    f3(i,ok) = D.fc.pv(4*(d-1)+1, ok);                % 预报值（0:00 列）
    pres(i,:) = ah(max(d-1,1), :);                    % 昨日实际小时均值
end
P3 = p0_downscale(f3,   'shape', cfg, Sm);
PP = p0_downscale(pres, 'shape', cfg, Sm);
Ad = A > 50;                                          % 只看白天
r1 = sqrt(mean((P3(:)-A(:)).^2));  r2 = sqrt(mean((PP(:)-A(:)).^2));
L{end+1} = sprintf('   附件3  : MAE %7.2f  RMSE %7.2f kW（白天 RMSE %7.2f）', ...
    mean(abs(P3(:)-A(:))), r1, sqrt(mean((P3(Ad)-A(Ad)).^2)));
L{end+1} = sprintf('   持续性 : MAE %7.2f  RMSE %7.2f kW（白天 RMSE %7.2f）', ...
    mean(abs(PP(:)-A(:))), r2, sqrt(mean((PP(Ad)-A(Ad)).^2)));

% ---- C) 混合权重扫描 ----
L{end+1} = '';
L{end+1} = '【C】小时域加权混合 P = w*附件3 + (1-w)*昨日实际（再形状降尺度）';
L{end+1} = '     w   |  全天RMSE  |  白天RMSE  |   白天MAE';
best = [inf, 0];
for w = 0:0.1:1
    Pm = p0_downscale(w*f3 + (1-w)*pres, 'shape', cfg, Sm);
    e  = Pm(:) - A(:);
    ed = Pm(Ad) - A(Ad);
    L{end+1} = sprintf('   %4.1f  |  %8.2f  |  %8.2f  |  %8.2f', ...
        w, sqrt(mean(e.^2)), sqrt(mean(ed.^2)), mean(abs(ed)));
    if sqrt(mean(ed.^2)) < best(1), best = [sqrt(mean(ed.^2)), w]; end
end
L{end+1} = sprintf('   ⇒ 白天 RMSE 最优权重 w = %.1f（RMSE %.2f kW）', best(2), best(1));

fid = fopen(fullfile(cfg.outdir,'diag_pv_quality.txt'), 'w', 'n', 'UTF-8');
for i = 1:numel(L), fprintf(fid, '%s\n', L{i}); end
fclose(fid);
fprintf('diag_pv_quality -> %s\n', fullfile(cfg.outdir,'diag_pv_quality.txt'));
end

% ------------------------------------------------------------------
function r = rho(a, b)
% 皮尔逊相关系数（corr2 需要 Image Processing Toolbox，本机没有）
a = a(:); b = b(:);
if numel(a) < 2 || std(a) < 1e-12 || std(b) < 1e-12, r = NaN; return; end
c = corrcoef(a, b);
r = c(1,2);
end
