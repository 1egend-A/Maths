function qc = q4_config(overrides)
% Q4_CONFIG  问题四专属参数与口径（在 q3_config 基础上只换电价来源）
%
% ============================================================
%  问题四与问题三的关系（本题最要紧的一条）
%
%  题目问题4 原文：「假设各时段的风光发电功率、负载功率和电价均是可以提前预知的，
%                    请重新制定…最优购电策略」+「附件4」逐日实测电价。
%
%  故 Q4【不是】另一个模型，而是把 Q2/Q3 的框架原样搬到附件4 的逐日逐时段电价上：
%      result4-2.xlsx  ← 问题二框架（无附件3 预报，负载与光伏都自预测）+ 附件4 电价
%      result4-3.xlsx  ← 问题三框架（附件3 预报 + 三次滚动调整）      + 附件4 电价
%
%  本文件的做法：直接调 q3_config 并把 priceMode 改成 'volatile'，
%  其余物理参数、口径、罚则系数、报童分位【一字不改】。
%  这样 Q3 与 Q4 的任何差异都只能来自电价，是可解释的受控对照。
%
%  ------------------------------------------------------------
%  为什么"换个价格串"仍值得单列一问（三个必须写进论文的事实，均已实测）
%
%   (1) 附件1 是全年【均值】剖面，不是真实某天。
%       实测 max|附件1.price − mean_t(附件4.price)| = 3.065e-2 元/kWh（逐槽误差
%       最大约 0.03 元/kWh，相当于均价的 4%）。故 Q2/Q3 是"典型日"、Q4 是"逐日
%       实际"，是干净对照而非重复劳动。
%       ⚠️ 该数曾误记为 5.2e-5（相差 600 倍，系早期一次口径不同的探查残留）。
%          凡写进交付物的同类数字一律【现场算出】，见 q4_export_result4.m 的 notesFor。
%
%   (2) 近零价套利。附件4 最低 0.0076 元/kWh（9 个时段 < 0.05、28 个 < 0.10），
%       最高 1.7936，峰谷比 236 倍（附件1 只有 3.76 倍）。
%       储能在 Q4 从"风险对冲工具"变成"套利工具"——归因见 t_q4_nearzero.m。
%
%   (3) 口径 2（日末 SOC 固定 6000）的代价在 Q4 会翻转。
%       Q2/Q3 逐日电价相同 ⇒ 跨日搬运储能无价差 ⇒ 放开闭环只省 0.12%（可忽略）；
%       Q4 电价逐日不同 ⇒ 跨日价差真实存在 ⇒ 该对照从"可忽略"变成"有意义"。
%       见 t_q4_term_policy.m，这是问题四最亮的一节。
%
%  ------------------------------------------------------------
%  ⚠️ 本问【不修改】任何已交付文件：
%     问题二/code/*.m、问题三/code/*.m 均只读调用；result3.xlsx 与 Q3 的 out/ 不受影响。
%     q4_solve_p2.m 是 q2_solve.m 的受控克隆（唯一差异：电价逐日不同），
%     并有 t_q4_clone_check.m 在 priceMode='fixed' 下逐位复现 q2_solve 作保底。
% ============================================================
%
% 用法：
%   qc = q4_config();                       % 默认
%   qc = q4_config(struct('useStages',[1 0 0 0]));   % 消融

Q4ROOT = 'D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\问题四\';
Q2DIR  = 'D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\问题二\code';
Q3DIR  = 'D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\问题三\code';
if isempty(which('p0_config')), addpath('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码'); end
if isempty(which('q2_config')), addpath(Q2DIR); end
if isempty(which('q3_config')), addpath(Q3DIR); end

% ---------- 继承 Q3 的全部口径，只把电价换成附件4 逐日实测 ----------
qc = q3_config(struct('priceMode', 'volatile'));

% ---------- 路径：绝不复用问题三的 outdir / resFile ----------
% ⚠️ q3_config 的 qc.resFile 指向 问题三\out\result3.xlsx，若原样继承，
%    问题四的导出会把已交付的 result3.xlsx 覆盖掉。下面三个路径必须逐个改掉。
qc.dirQ4    = Q4ROOT;
qc.outdir   = [Q4ROOT 'out\'];       % 公共产物：配图、论文表、实验落盘
qc.outdir42 = [Q4ROOT 'out42\'];     % 问题二框架（保底结果一）
qc.outdir43 = [Q4ROOT 'out43\'];     % 问题三框架（保底结果二）
qc.dirQ2    = Q2DIR;
qc.dirQ3    = Q3DIR;

% ---------- 官方模板（只读，导出时 copyfile 到本问 out 下）----------
tplDir = fileparts(qc.tplFile);                      % …\附件5
qc.tplFile2 = fullfile(tplDir, 'result4-2.xlsx');    % 3 张表：计划/充放电/紧急
qc.tplFile  = fullfile(tplDir, 'result4-3.xlsx');    % 4 张表：计划/调整/充放电/紧急
qc.resFile2 = [qc.outdir42 'result4-2.xlsx'];
qc.resFile3 = [qc.outdir43 'result4-3.xlsx'];

% ---------- 求解区间（与 Q2/Q3 一致，保证四问可比）----------
% q3_config 已设 dayIdx = 32:365 = 2025-02-01 … 12-31，与附件5 模板行数 334 一致。
assert(numel(qc.dayIdx) == 334, 'Q4 求解区间应为 334 天');

% ---------- 附属脚注 ----------
qc.priceNote = 'volatile=附件4 逐日实测电价（365×144，本问取 2025-02-01…12-31）';

% ---------- 调用者覆盖 ----------
if nargin >= 1 && ~isempty(overrides)
    fn = fieldnames(overrides);
    for i = 1:numel(fn)
        qc.(fn{i}) = overrides.(fn{i});
    end
end

% ---------- 目录自建（导出函数也会建，这里先建好避免竞态）----------
for d = {qc.outdir, qc.outdir42, qc.outdir43}
    if ~isfolder(d{1}), mkdir(d{1}); end
end
% out/ 下再放一个 figures 子目录给配图用
if ~isfolder([qc.outdir 'figures']), mkdir([qc.outdir 'figures']); end
end
