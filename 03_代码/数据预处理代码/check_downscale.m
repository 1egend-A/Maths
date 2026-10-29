function ok = check_downscale()
% CHECK_DOWNSCALE  验收降尺度与形状权重（任务 #2）
%   1) 三种降尺度方法的【小时均值守恒】不变量
%   2) 形状权重 pv_shape 的合理性
%
% 定位：本脚本只做【数据加工层】的验收——降尺度不得改变给定的小时预报值，
%       形状权重必须物理合理。不含任何预测方法或优化结果。
% 输出 out/check_downscale_report.txt

cfg = p0_config();
D   = p0_load(cfg);
ok  = true;
lines = {};
lines{end+1} = '==========================================================';
lines{end+1} = ' 降尺度与形状权重验收（check_downscale.m）';
lines{end+1} = '==========================================================';

% ================= 1) 降尺度均值守恒 =================
lines{end+1} = '';
lines{end+1} = '---- 1) p0_downscale 小时均值守恒不变量 ----';
rng(7);
H = rand(5, 24) * 1000;
Sm = pv_shape(D, cfg);
for m = {'stair','linear','shape'}
    if strcmp(m{1},'shape')
        X = p0_downscale(H, m{1}, cfg, Sm);
    else
        X = p0_downscale(H, m{1}, cfg);
    end
    Hq = zeros(size(H));
    for h = 1:24, Hq(:,h) = mean(X(:,6*(h-1)+(1:6)), 2); end
    e = max(abs(Hq(:) - H(:)));
    lines{end+1} = sprintf('   %-7s : 尺寸 %dx%d，小时均值最大偏差 %.3e  %s', ...
        m{1}, size(X,1), size(X,2), e, mark(e < 1e-9));
    ok = ok && (e < 1e-9);
end
% 真实尺度下的守恒（用附件2 实际光伏的小时均值）
Hp = zeros(365,24);
for h = 1:24, Hp(:,h) = mean(D.actual.pv(:,6*(h-1)+(1:6)), 2); end
Xa = p0_downscale(Hp(1:30,:), 'shape', cfg, Sm);
ea = max(abs(reshape(mean(reshape(Xa,30,6,24),2),30,24) - Hp(1:30,:)), [], 'all');
lines{end+1} = sprintf('   真实光伏尺度 shape 法：最大偏差 %.3e  %s', ea, mark(ea < 1e-9));
ok = ok && (ea < 1e-9);

% ================= 2) 形状权重 =================
lines{end+1} = '';
lines{end+1} = '---- 2) pv_shape 形状权重（24×6，每行均值=1）----';
lines{end+1} = '  小时 |  槽1    槽2    槽3    槽4    槽5    槽6  | 行均值 行和';
for h = 1:24
    lines{end+1} = sprintf('   %2d  | %s | %.4f %.4f', h, ...
        sprintf('%6.3f ', Sm(h,:)), mean(Sm(h,:)), sum(Sm(h,:)));
end
rowOk = max(abs(mean(Sm,2) - 1)) < 1e-12;
lines{end+1} = sprintf('   每行均值=1 ? %s', mark(rowOk));
ok = ok && rowOk;
% 退化（样本不足 → 均匀权重）只应发生在夜间小时。若白天也退化说明阈值过高，
% 若 04:00-05:00 之类的晨昏小时未退化说明阈值过低（曾出现 [0 0 2.3 0 3.5] 的噪声形状）。
uni = find(all(abs(Sm - 1) < 1e-12, 2)).';
nightOnly = all(ismember(uni, [1 2 3 4 5 20 21 22 23 24]));
lines{end+1} = sprintf('   退化为均匀权重的小时 = %s  ⇒ 仅夜间 ? %s', mat2str(uni), mark(nightOnly));
ok = ok && nightOnly;
% 正午爬坡应上行：11-13 点的槽1..槽6 应大致递增（上午）或递减（下午）
lines{end+1} = sprintf('   13 点(下午)形状 %s  ⇒ 应递减', mat2str(round(Sm(13,:),3)));
lines{end+1} = sprintf('   11 点(上午)形状 %s  ⇒ 应递增', mat2str(round(Sm(11,:),3)));

lines{end+1} = '';
lines{end+1} = sprintf('===== 总判定：%s =====', mark(ok));

fid = fopen(fullfile(cfg.outdir,'check_downscale_report.txt'), 'w', 'n', 'UTF-8');
for i = 1:numel(lines), fprintf(fid, '%s\n', lines{i}); end
fclose(fid);
save(fullfile(cfg.outdir,'pv_shape.mat'), 'Sm');
fprintf('check_downscale: ok=%d -> %s\n', ok, fullfile(cfg.outdir,'check_downscale_report.txt'));
end

% ------------------------------------------------------------------
function s = mark(c)
if c, s = '[PASS]'; else, s = '[FAIL]'; end
end
