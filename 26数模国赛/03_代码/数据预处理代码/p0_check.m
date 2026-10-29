function ok = p0_check()
% P0_CHECK  阶段 0 的验收：双路独立读入互证 + 结构不变量 + 守恒律自检
%
% 【为什么要双路】同一个 xlsx 用不同读法会给出不同结果，且都不报错。
% 例如附件4 用 readmatrix 会把表头那一行的「日分数」当成数据读进去，
% 最小值会从真值 0.0076 变成 0.0069、近零价时段数从 28 变成 42。
% 因此这里用两条完全不同的代码路径读同一个文件，再逐元素比对。
%
% 环境注意：本机 readtable 因 @tabular/dotAssign.m 被覆盖而不可用，
% 本文件全程只用 readcell / readmatrix。

cfg = p0_config();
D   = p0_load(cfg);

L  = {};
ok = true;

% ============ 报告首部免责横幅（每次生成都置顶）============
say('##########################################################');
say('⚠️  这不是题目答案。这是【阶段 0 数据管道验收报告】。');
say('');
say('本报告证明的是：四个附件被正确读入、结构不变量成立、守恒律');
say('自洽、单日 LP 引擎可解。它【不含】Q1–Q4 的任何求解结果，');
say('也【不是】提交给赛区的答案文件。');
say('');
say('文中出现的金额（如 2025-01-01 的求解费用）是管道冒烟测试的');
say('副产物，只用于验证「费用复算一致」这一条，不要引用。');
say('');
say('真正的答案文件由建模阶段生成，文件名与存放位置待队内约定。');
say('##########################################################');
say('');

say('==========================================================');
say(' 阶段 0 数据管道验收报告   %s', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
say('==========================================================');
say('数据目录: %s', cfg.base);
say('');

% ================= 1. 双路独立读入互证 =================
say('---- 1. 双路独立读入互证（readcell 路径 vs readmatrix+Range 路径）----');
A1b = pathB(cfg, 'a1', 1, 2, 145, 2, 4);
chk('附件1 电价',  D.day144.price, A1b(:,1), 1e-9);
chk('附件1 负载',  D.day144.load,  A1b(:,2), 1e-9);
chk('附件1 光伏',  D.day144.pv,    A1b(:,3), 1e-9);

A2b = pathB(cfg, 'a2', 1, 2, 366, 2, 145);
chk('附件2 小区负载', D.actual.load, A2b, 1e-9);
A2c = pathB(cfg, 'a2', 2, 2, 366, 2, 145);
chk('附件2 光伏实际', D.actual.pv,   A2c, 1e-9);

A3b = pathB(cfg, 'a3', 1, 2, 1461, 3, 26);
chk('附件3 预报功率', D.fc.pv, A3b, 1e-9);

A4b = pathB(cfg, 'a4', 1, 2, 366, 2, 145);
chk('附件4 电价', D.actual.price, A4b, 1e-9);

% ================= 2. 结构不变量 =================
say('');
say('---- 2. 结构不变量 ----');
exact('附件1 时段数 = 144',   numel(D.day144.price), 144);
exact('附件2/4 天数 = 365',   D.meta.nDays, 365);
exact('附件3 行数 = 365*4',   numel(D.fc.dates), 1460);
exact('附件3 预报列数 = 24',  size(D.fc.pv, 2), 24);
exact('时段标签数 = 144',     numel(D.slots.label), 144);

exp144 = canonical144();
exact('时段标签序列 00:10..00:00+1', double(isequal(D.slots.label(:), exp144)), 1);

expDates = (datetime(2025,1,1):caldays(1):datetime(2025,12,31))';
exact('附件2/4 日期连续无缺',   double(isequal(D.actual.dates, expDates)), 1);
exact('附件3 去重日期数 = 365', numel(D.meta.fcDatesUnique), 365);
exact('附件3 日期与附件2 一致', double(isequal(D.meta.fcDatesUnique, expDates)), 1);
exact('附件3 预报时刻集合', ...
    double(isequal(sort(D.meta.issueLevels), sort(["0:00";"6:00";"12:00";"18:00"]))), 1);
exact('附件3 每个时刻各 365 次', double(all(countOccur(D.fc.issue) == 365)), 1);
say('  附件3 首个日期的 4 行顺序: %s', strjoin(cellstr(D.fc.issue(1:4)), ' -> '));

% ================= 3. 数值健全性与实测范围 =================
say('');
say('---- 3. 数值健全性与实测范围（NaN 必须为 0）----');
% 参照值来自【第三条独立实现】pandas 的读取结果（不是本代码自己读出来的），
% 容差：电价格 3e-4（足以抓住 0.0076→0.0069 这类表头误读），功率 0.05 kW。
rng3('附件1 电价', D.day144.price,    0, 3,   0.3713,  1.3952,   3e-4);
rng3('附件1 负载', D.day144.load,     0, 1e5, 3309.4,  5959.0,   0.05);
rng3('附件1 光伏', D.day144.pv,       0, 1e5, 0,       7612.3,   0.05);
rng3('附件2 负载', D.actual.load(:),  0, 1e5, 1995.72, 7978.88,  0.05);
rng3('附件2 光伏', D.actual.pv(:),    0, 1e5, 0,       10216.20, 0.05);
rng3('附件4 电价', D.actual.price(:), 0, 3,   0.0076,  1.7936,   3e-4);
rng3('附件3 光伏', D.fc.pv(:),        0, 1e5, 0,       9995.89,  0.05);
say('  附件4 近零价时段: <0.10 共 %d 个，<0.05 共 %d 个', ...
    sum(D.actual.price(:) < 0.10), sum(D.actual.price(:) < 0.05));

% ================= 4. 守恒律自检（用 2025-01-01 跑一次 LP）=================
say('');
say('---- 4. 守恒律自检（day_lp + soc_sim 联跑 2025-01-01）----');
pr = D.actual.price(1,:); ld = D.actual.load(1,:); pvv = D.actual.pv(1,:);
[g, c, d, cost, info] = day_lp(pr, ld, pvv, cfg.S0, cfg, []);
say('  求解: flag=%d  变量 %d  约束 %d  费用 %.2f 元', info.flag, info.nVar, info.nCon, cost);

switch cfg.effConv
    case 'ac'; resid = g + d - c - (ld(:) - pvv(:));
    case 'dc'; resid = g + d*cfg.eta - c/cfg.eta - (ld(:) - pvv(:));
end
say('  功率平衡最大残差 = %.3e kW', max(abs(resid)));
chk2('功率平衡残差 < 1e-6', max(abs(resid)) < 1e-6, sprintf('%.3e kW', max(abs(resid))));

[S, si] = soc_sim(c, d, cfg.S0, cfg);
say('  SOC: 起点 %.2f  最低 %.2f  最高 %.2f  终点 %.2f kWh', si.S0, si.minS, si.maxS, si.endS);
chk2('SOC 全程在 [S_min,S_max] 内', si.violLow == 0 && si.violHigh == 0, ...
     sprintf('越下界 %d 次 / 越上界 %d 次', si.violLow, si.violHigh));
chk2('充放功率不超过 P_max', max([c;d]) <= cfg.P_max + 1e-6, sprintf('实际最大 %.1f kW', max([c;d])));
chk2('购电功率非负', min(g) >= -1e-9, sprintf('最小 %.3e kW', min(g)));
chk2('不同时充放 (eta<1 自动满足)', all(c < 1e-6 | d < 1e-6), ...
     sprintf('冲突时段 %d 个', sum(c > 1e-6 & d > 1e-6)));

costRef = sum(pr(:) .* g) * cfg.dt;
chk2('费用复算一致', abs(cost - costRef) < 1e-6, ...
     sprintf('linprog %.4f / 复算 %.4f', cost, costRef));

% ================= 汇总 =================
say('');
say('==========================================================');
if ok
    say(' 全部通过 ✅   管道可用于后续建模');
else
    say(' 存在失败项 ❌   管道不可用于后续建模');
end
say('==========================================================');

txt = strjoin(L, newline);
fid = fopen(fullfile(cfg.outdir, 'p0_check_report.txt'), 'w');
fprintf(fid, '%s\n', txt);
fclose(fid);
fprintf('%s\n', txt);
fprintf('\n报告已写入: %s\n', fullfile(cfg.outdir, 'p0_check_report.txt'));

% ======================================================================
%  嵌套函数：共享 L 与 ok
% ======================================================================
    function say(fmt, varargin)
        s = sprintf(fmt, varargin{:});
        L{end+1} = s;
    end

    function chk(name, A, B, tol)
        if ~isequal(size(A), size(B))
            good = false; dv = Inf;
        else
            dv = max(abs(A(:) - B(:)));
            good = dv <= tol;
        end
        mark(good, sprintf('  %-16s 形状 %-12s 最大偏差 %.3e', name, mat2str(size(A)), dv));
    end

    function chk2(name, cond, detail)
        mark(cond, sprintf('  %-30s %s', name, detail));
    end

    function exact(name, got, want)
        mark(isequal(got, want), sprintf('  %-30s 实得 %s / 应为 %s', ...
            name, num2str(got), num2str(want)));
    end

    function rng3(name, v, lo, hi, expLo, expHi, tol)
        v = v(:);
        nanN = sum(isnan(v));
        good = nanN == 0 && all(v >= lo) && all(v <= hi) ...
            && abs(min(v) - expLo) < tol && abs(max(v) - expHi) < tol;
        mark(good, sprintf('  %-12s NaN=%d  min=%.4f(期望 %.4f)  max=%.4f(期望 %.4f)', ...
            name, nanN, min(v), expLo, max(v), expHi));
    end

    function mark(good, msg)
        if good
            tag = '[PASS]';
        else
            tag = '[FAIL]';
            ok = false;
        end
        L{end+1} = sprintf('  %s %s', tag, msg);
    end
end

% ======================================================================
%  局部函数（无状态）
% ======================================================================

function M = pathB(cfg, key, sheet, r1, r2, c1, c2)
% 独立读入路径：readmatrix + 显式 A1 记法的 Range，不做任何表头推断
ls = dir(cfg.base); names = {ls.name};
target = '';
for i = 1:numel(names)
    tok = regexp(names{i}, '附件(\d)', 'tokens', 'once');
    if ~isempty(tok) && strcmp(sprintf('a%s', tok{1}), key)
        target = fullfile(cfg.base, names{i});
    end
end
assert(~isempty(target), '未找到附件 %s', key);
rng = sprintf('%s%d:%s%d', colLetter(c1), r1, colLetter(c2), r2);
M = readmatrix(target, 'Sheet', sheet, 'Range', rng);
end

function s = colLetter(n)
s = '';
while n > 0
    s = [char(65 + mod(n-1, 26)) s];
    n = floor((n-1)/26);
end
end

function lab = canonical144()
mins = 10:10:1440;
lab = strings(numel(mins), 1);
for i = 1:numel(mins)
    if mins(i) < 1440
        lab(i) = string(sprintf('%02d:%02d', floor(mins(i)/60), mod(mins(i),60)));
    else
        lab(i) = "00:00+1";
    end
end
end

function cnt = countOccur(v)
u = unique(v);
cnt = zeros(size(u));
for i = 1:numel(u)
    cnt(i) = sum(v == u(i));
end
end
