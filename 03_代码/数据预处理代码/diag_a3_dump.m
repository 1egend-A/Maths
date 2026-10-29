function diag_a3_dump()
% DIAG_A3_DUMP  把某日 4 个发布行与实际逐小时摊开对照
cfg = p0_config(); D = p0_load(cfg);
ah = zeros(365,24);
for h = 1:24, ah(:,h) = mean(D.actual.pv(:, 6*(h-1)+(1:6)), 2); end

L = {};
for d = [32 200]
    lo = 4*(d-1)+1;
    L{end+1} = sprintf('==== 日 %d (%s) ====', d, datestr(D.actual.dates(d),'yyyy-mm-dd'));
    L{end+1} = '  h  |   实际   |  0:00行  |  6:00行  | 12:00行  | 18:00行';
    for h = 1:24
        L{end+1} = sprintf(' %2d  | %8.1f | %8.1f | %8.1f | %8.1f | %8.1f', h, ah(d,h), ...
            D.fc.pv(lo,h), D.fc.pv(lo+1,h), D.fc.pv(lo+2,h), D.fc.pv(lo+3,h));
    end
    rs = zeros(1,4);
    for k = 0:3
        c = corrcoef(D.fc.pv(lo+k,:), ah(d,:)); rs(k+1) = c(1,2);
    end
    L{end+1} = sprintf(' 与实际相关系数: 0:00 %+.3f | 6:00 %+.3f | 12:00 %+.3f | 18:00 %+.3f', rs);
    L{end+1} = sprintf(' 各列自身均值:  实际 %7.1f | %7.1f | %7.1f | %7.1f | %7.1f', mean(ah(d,:)), ...
        mean(D.fc.pv(lo,:)), mean(D.fc.pv(lo+1,:)), mean(D.fc.pv(lo+2,:)), mean(D.fc.pv(lo+3,:)));
    L{end+1} = '';
end

% 全局重复检测：附件3 各行峰值是否大量重复
pk = max(D.fc.pv, [], 2);
[up, ~, ic] = unique(round(pk));
cnt = accumarray(ic, 1);
L{end+1} = sprintf('附件3 峰值重复情况：1460 行中不同峰值 %d 个', numel(up));
L{end+1} = sprintf('  出现次数 >=3 的峰值: %d 个；最高重复次数 = %d', sum(cnt>=3), max(cnt));
[pks, ord] = sort(cnt, 'descend');
L{end+1} = '  重复最多的 5 个峰值:';
for i = 1:5
    L{end+1} = sprintf('    %.1f kW  出现 %d 次', up(ord(i)), pks(i));
end
% 实际数据的峰值重复
pka = max(ah, [], 2);
L{end+1} = sprintf('对照：附件2 实际 365 天峰值，不同值 %d 个（应≈365）', numel(unique(round(pka))));

fid = fopen(fullfile(cfg.outdir,'diag_a3_dump.txt'), 'w', 'n', 'UTF-8');
for i = 1:numel(L), fprintf(fid, '%s\n', L{i}); end
fclose(fid);
fprintf('diag_a3_dump -> %s\n', fullfile(cfg.outdir,'diag_a3_dump.txt'));
end
