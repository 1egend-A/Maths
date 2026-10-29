% t_table3_summary.m —— 为论文 表7-3 的精简版算数（四个指定日期）
% 论文里只写「总量 / 段数 / 最大单段 / 涉及时段数 / 紧急购电费及占比」，
% 完整逐时段清单仍由 result2.xlsx 交付。所有数字由本脚本产出，禁止手写。
here = fileparts(mfilename('fullpath'));           % -> .../code/dev_scratch
cd(fileparts(fileparts(here)));                    % -> .../问题二
S = load('out/q2_solution.mat');  R = S.R;  qc = S.qc;

dates = [datetime(2025,3,20); datetime(2025,6,21); ...
         datetime(2025,9,23); datetime(2025,12,21)];
% 时段 t 的起止时刻（10 分钟一格，从 0:00 起）
t2str = @(t) sprintf('%d:%02d', floor((t-1)/6), mod(t-1,6)*10);

fprintf('\n=== 表7-3 精简版（四个指定日期）===\n');
fprintf('%-12s %12s %6s %10s %-14s %6s %14s %9s\n', ...
        '日期','紧急购电量','段数','最大单段','最大段时刻','时段数','紧急购电费','占当日%');
for k = 1:numel(dates)
    i = find(R.date == dates(k));
    assert(~isempty(i), '找不到日期 %s', string(dates(k)));
    e = R.gEm(i,:).' * qc.dt;      % ⚠ gEm 存的是【功率 kW】，×dt 才是电量 kWh
    p = R.price;
    qEm = sum(e);
    fee = sum(5*p.*e);
    tot = R.costTot(i);            % 当日总费用（含计划购电费）
    nz  = find(e > 1e-9);
    % 连续段
    segs = {};
    if ~isempty(nz)
        brk = [0; find(diff(nz) > 1); numel(nz)];
        for j = 1:numel(brk)-1
            tt = nz(brk(j)+1 : brk(j+1));
            segs{end+1} = tt; %#ok<SAGROW>
        end
    end
    smax = 0; tbest = [NaN NaN];
    for j = 1:numel(segs)
        tt = segs{j};
        v = sum(e(tt));
        if v > smax, smax = v; tbest = [tt(1), tt(end)]; end
    end
    fprintf('%-12s %12.2f %6d %10.2f %-14s %6d %14.2f %8.2f%%\n', ...
        string(dates(k),'yyyy.M.d'), qEm, numel(segs), smax, ...
        sprintf('%s-%s', t2str(tbest(1)), t2str(tbest(2)+1)), ...
        numel(nz), fee, 100*fee/tot);
end

% 顺便核对论文表7-3里逐段清单的总计，防止正文与数据脱节
chk = [datetime(2025,3,20); datetime(2025,6,21); ...
       datetime(2025,9,23); datetime(2025,12,21)];
paperTotal = [606.24, 12.25, 1131.15, 427.86];   % 论文表7-3「合计」行
fprintf('\n=== 论文表7-3 合计行核对 ===\n');
for k = 1:numel(chk)
    i = find(R.date == chk(k));
    v = sum(R.gEm(i,:))*S.qc.dt;
    fprintf('%-12s 论文=%9.2f  实算=%9.4f  差=%+.2e %s\n', ...
        string(chk(k),'yyyy.M.d'), paperTotal(k), v, v-paperTotal(k), ...
        ternary(abs(v-paperTotal(k))<0.01,'OK','**不符**'));
end

function s = ternary(c,a,b)
if c, s = a; else, s = b; end
end
