function T = q4_paper_tables(R2, R3, qc, D, F2, F3) %#ok<INUSD>
% Q4_PAPER_TABLES  问题四论文表（按题面表 1 / 表 2 / 表 3 的格式）
%
% ============================================================
%  本文件【不重写】表格逻辑，而是转调 问题三/code/q3_paper_tables.m。
%  理由：问题四与问题三的表格版式要求完全相同（同一张题面表 1/2/3、
%  同一批指定日期 2025.3.20 / 6.21 / 9.23 / 12.21、同一批指定时段），
%  差异只在【电价口径】（附件4 逐日 vs 附件1 逐日相同）。
%  各写一套必然产生两份会漂移的代码——这正是团队铁律
%  「禁止各自生成求解器再拼接」在【后处理】侧的同一道理。
%
%  ⚠️ 与问题三的唯一实质差异：问题四没有「调整前 / 调整后」两版并存的必要吗？
%     有。result4-2（问题二框架）没有调整机制，result4-3（问题三框架）有。
%     故论文表必须【分别对 R2 与 R3 各出一套】，且文件名要能区分。
%     本函数对传入的 R 统一出一套，落在 qc.outdir 下并用 q4 前缀。
%
% 用法：
%   T2 = q4_paper_tables(R2, qc, D);              % 问题二框架（无调整）
%   T3 = q4_paper_tables(R3, qc, D);              % 问题三框架（含调整）—— 默认
%
% 落盘（UTF-8 CSV，均在 qc.outdir 下，文件名已把 q3 换成 q4）：
%   paper_q4_table1_计划.csv / paper_q4_table1_调整.csv / paper_q4_table2.csv
%   paper_q4_table3.csv / paper_q4_table3_表3格式.csv
%   paper_q4_daily.csv / paper_q4_monthly.csv

if nargin < 6, F2 = []; end %#ok<NASGU>
if nargin < 4 || isempty(D)
    D = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码\out\data.mat').D;
end
if nargin < 3 || isempty(qc), qc = q4_config(); end
if nargin < 2 || isempty(R3)
    f = [qc.outdir43 'q4_solution_p3.mat'];
    assert(isfile(f), '未找到 %s，请先跑 q4_solve_p3', f);
    R3 = load(f, 'R3').R3;
end
if nargin < 1 || isempty(R2)
    f2 = [qc.outdir42 'q4_solution_p2.mat'];
    if isfile(f2), R2 = load(f2, 'R2').R2; else, R2 = []; end
end

% ---- 转调问题三的表格生成器 ----
if isempty(which('q3_paper_tables')), addpath(qc.dirQ3); end

% ⚠️ 两套框架的字段命名不同，q3_paper_tables 只认问题三（滚动框架）的命名：
%      Q3 滚动框架（q3_solve）：G, A, C, D, gEm, costPlan, costAdj, costEm, clipHi/clipLo …
%      Q2 单阶段框架（q4_solve_p2）：gPlan（无 G）、c, d（小写）、且【没有】调整量 A
%    故对问题二框架必须先做一次字段兼容映射，否则会报「无法识别的字段名称 "G"」。
%    无调整机制 ⇒ A ≡ G（最终申报量恒等于计划量），调整费与调整槽数恒为 0/0，
%    这不是"造数"，而是该框架的真实语义。
if ~isempty(R2)
    R2 = compatP2(R2);
end

% ---- 两套框架各出一套表，用文件名区分（_p2 = 问题二框架，_p3 = 问题三框架）----
%      题面的三张表只要求给「本问的结果」，但本问有两个并列交付（result4-2 / result4-3），
%      故两套都出，论文正文引 _p3 那套（含调整机制），_p2 那套放附录作对照。
ren = {'paper_q3_table1_计划.csv',   'paper_q4_table1_计划'; ...
       'paper_q3_table1_调整.csv',   'paper_q4_table1_调整'; ...
       'paper_q3_table2.csv',        'paper_q4_table2'; ...
       'paper_q3_table3.csv',        'paper_q4_table3'; ...
       'paper_q3_table3_表3格式.csv', 'paper_q4_table3_表3格式'; ...
       'paper_q3_daily.csv',         'paper_q4_daily'; ...
       'paper_q3_monthly.csv',       'paper_q4_monthly'};

for pass = 1:2
    if pass == 1
        if isempty(R3), continue; end
        Rcur = R3;  sfx = '_p3';
    else
        if isempty(R2), continue; end
        Rcur = R2;  sfx = '_p2';
    end
    try
        T = q3_paper_tables(Rcur, qc, D, F3);
    catch ME
        fprintf('  ⚠️ q4_paper_tables：%s 那套表未生成（%s）\n', sfx, ME.message);
        continue;
    end
    for i = 1:size(ren, 1)
        src = fullfile(qc.outdir, ren{i,1});
        dst = fullfile(qc.outdir, [ren{i,2} sfx '.csv']);
        if isfile(src), movefile(src, dst, 'f'); end
    end
    fprintf('  q4_paper_tables：已写出 paper_q4_*%s.csv（转调 q3_paper_tables）\n', sfx);
end
end

% ======================================================================
function R = compatP2(R)
% COMPATP2  把问题二（单阶段）框架的结果映射成问题三（滚动）框架的字段命名。
% ⚠️ 纯粹是【重命名 + 补零】，不含任何数值近似：
%    无调整机制 ⇒ A ≡ G、调整费 ≡ 0、调整槽数 ≡ 0、不调整对照 ≡ 本框架自身费用。
if ~isfield(R, 'G'), R.G = R.gPlan; end
if ~isfield(R, 'A'), R.A = R.G;     end
if ~isfield(R, 'C'), R.C = R.c;     end
if ~isfield(R, 'D'), R.D = R.d;     end
nd = size(R.G, 1);  nT = size(R.G, 2);
if ~isfield(R, 'costAdj'),  R.costAdj  = zeros(nd, 1); end
if ~isfield(R, 'qAdj'),     R.qAdj     = zeros(nd, 1); end
if ~isfield(R, 'costNoAdj')                         % 无调整 ⇒ 本框架自身即"不调整"
    R.costNoAdj = R.costPlan(:) + R.costEm(:);
end

% ⚠️ Sadj 是【当日总费用】nd×1，不是 SOC！
%    q3_solve.m:109 的定义：R.Sadj = costPlan + costAdj + costEm（逐日）。
%    曾凭名字猜成"S after adjustment ≈ 荷电状态"而写成 R.Sadj = R.Soc，
%    于是 334×144 的 SOC 被塞进一个本该 334×1 的费用列：
%    MATLAB 的线性索引照单全收、不报错，表格里那一列就变成了 6000 / 6750
%    ——SOC 的数值伪装成了购电费。**凭字段名猜语义是这里唯一的错源。**
%    故下面一律补形状断言：错了就当场炸掉，而不是印出一个看着像数的数。
R.Sadj = R.costPlan(:) + R.costAdj(:) + R.costEm(:);
R.costAdjOnly = R.Sadj;          % 本框架无调整机制 ⇒ "仅调购电量"与自身同值

if ~isfield(R, 'clipHi'),   R.clipHi   = false(nd, nT); end
if ~isfield(R, 'clipLo'),   R.clipLo   = false(nd, nT); end

% ---- 形状断言：兼容层的输出必须与 q3_paper_tables 的期望逐字段一致 ----
for chk = {'G','A','C','D','Soc'}
    assert(isequal(size(R.(chk{1})), [nd nT]), '%s 形状应为 %d×%d', chk{1}, nd, nT);
end
for chk = {'costPlan','costAdj','costEm','costNoAdj','costAdjOnly','Sadj','qPlan','qAdj','qEm'}
    assert(isequal(size(R.(chk{1})), [nd 1]), '%s 形状应为 %d×1（费用/电量为逐日向量）', chk{1}, nd);
end
assert(numel(R.date) == nd, 'date 长度应为 %d', nd);
end
