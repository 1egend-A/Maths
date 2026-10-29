function F = q3_forecast(D, qc)
% Q3_FORECAST  问题三的【分时刻信息集】构造器
%
% 与问题二的差别（口径 7）：
%   问题二【严格字面】——只用附件1 + 附件2，负载与光伏都自预测；
%   问题三【官方预报】——题面明确给出附件3（未来24 小时整点光伏预报），
%       故光伏改用附件3；负载【没有官方预报】，仍用自预测。
%   这使 Q2 → Q3 成为「无官方预报 → 有官方预报」的受控对照。
%
% 附件3 的语义（口径 5，calib_fc_offset.m 用 21876 样本实证标定）：
%   第 k 列 = 区间 [发布时刻 + (k−1)h, 发布时刻 + k·h)，k = 1..24。
%   于是【本日之内】发布时刻 τ 覆盖小时 h0 的列号为  k = h0 − τ + 1（h0 ≥ τ）。
%   τ=18 的「预报1小时」= 18:00-19:00，正是本日 h0 = 18。
%
% 降尺度：附件3 是【整点】粒度，决策是【10 分钟】粒度，必须降尺度。
%   调用 数据预处理代码/p0_downscale.m（末尾有硬 assert 保证逐小时均值严格守恒）。
%
% 输出 F:
%   F.Lhat       365×144      负载日前预测（kW），与问题二同一套 blend 预测器
%   F.Nact       365×144      实际净负荷 L − PV（kW）
%   F.Phat4      365×144×4    四个发布时刻的光伏预报（10 分钟粒度，已降尺度）
%   F.Nhat4      365×144×4    对应的净负荷预报
%   F.Nhat       365×144      = Nhat4(:,:,1)，0:00 的净负荷预报（计划阶段用）
%   F.PhatSelf   365×144      自预测光伏（mean7），仅消融对照用
%   F.issHours   1×4          发布时刻 [0 6 12 18]
%   F.dsMethod / F.note        方法说明
%
% ⚠️ 信息集纪律：第 d 天、第 τ 时刻可见的预报只用到
%    ① 第 d 天 0:00–τ:00 的【已实现】实测值（用实际小时均值替代，残差为 0）
%    ② 附件3 中 (第 d 天, 发布时刻 τ) 的那一行
%   不触碰任何未来数据。

L = D.actual.load;                 % 365×144
P = D.actual.pv;                   % 365×144
nd = size(L,1);  nt = size(L,2);
issH = qc.fcIssHours(:)';          % [0 6 12 18]
nIss = numel(issH);
assert(nt == 144, '本函数假定 10 分钟粒度共 144 槽');

% ================= 1. 负载预测（与问题二完全同一套，保证可比）=================
F.Lhat = nan(nd, nt);
for d = 1:nd
    F.Lhat(d,:) = fcLoad(L, d, qc.loadMethod);
end

% ================= 2. 自预测光伏（消融对照支路）=================
F.PhatSelf = nan(nd, nt);
for d = 1:nd
    F.PhatSelf(d,:) = fcPV(P, d, qc.pvSelfMethod);
end

% ================= 3. 附件3 官方预报 → 四套降尺度光伏预报 =================
% ---- 3.1 建立 (日, 发布时刻) → D.fc 行号 的映射（不靠约定，靠断言）----
issRaw = D.fc.issue;
if isdatetime(issRaw)
    issRaw = hour(issRaw);            % datetime → 小时数
elseif isduration(issRaw)
    issRaw = issRaw.Hours;            % duration → 小时数（含小数，本处恒为整点）
elseif isstring(issRaw) || ischar(issRaw) || iscellstr(issRaw)
    % data.mat 里存的是形如 "0:00" / "12:00" 的文本
    issRaw = double(extractBefore(string(issRaw), ':'));
end
issRaw = double(issRaw(:));
assert(all(ismember(unique(issRaw), issH)), ...
    'D.fc.issue 的取值不是 %s（实际唯一值：%s）', mat2str(issH), mat2str(unique(issRaw)'));

keyFC  = D.fc.dates(:) + hours(issRaw);              % 1460×1
keyTgt = D.actual.dates(:) + hours(issH);            % 365×4（隐式扩展）
[tf, loc] = ismember(keyTgt, keyFC);
assert(all(tf(:)), '附件3 中有 %d 个 (日, 发布时刻) 组合在 data.mat 里找不到', sum(~tf(:)));
locM = reshape(loc, nd, nIss);                       % locM(d, j) = D.fc 行号
assert(numel(unique(locM(:))) == nd*nIss, '附件3 的 (日, 发布时刻) 映射不唯一，数据可能重复');

% ---- 3.2 形状权重（降尺度用）----
if isempty(which('p0_config'))
    addpath('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码');
end
cfg = p0_config();
SH = pv_shape(D, cfg);                               % 24×6

% ---- 3.3 逐日逐时刻拼小时序列并降尺度 ----
% 光伏预报来源（qc.pvSource，供消融实验换源；默认 'a3'）：
%   'a3'     ：附件3 官方预报（本问默认，题面给出）
%   'self'   ：不用附件3，改用自预测（近 7 日同时刻均值，与问题二同一套）
%   'blend3' ：w·附件3 + (1−w)·自预测（w = qc.pvBlendW）
% 三个分支的【已实现时段】一律用实测小时均值，只有未实现时段换源，
% 这样三者的信息结构完全同构，费用差异可干净地归因到"预报从哪来"。
srcMode = 'a3';
if isfield(qc,'pvSource') && ~isempty(qc.pvSource), srcMode = lower(qc.pvSource); end
if ~isfield(qc,'pvBlendW') || isempty(qc.pvBlendW), wBlend = 0.15; else, wBlend = qc.pvBlendW; end

F.Phat4 = nan(nd, nt, nIss);
for d = 1:nd
    PactHour  = hourMeans(P(d,:));                    % 1×24，当天实测小时均值
    SelfHour  = hourMeans(F.PhatSelf(d,:));           % 1×24，自预测的小时序列
    for j = 1:nIss
        tau = issH(j);
        H = zeros(1,24);
        for h0 = 0:tau-1                                % 已实现：用实测小时均值
            H(h0+1) = PactHour(h0+1);
        end
        for h0 = tau:23                                 % 未实现：按来源取
            k = h0 - tau + 1;
            assert(k >= 1 && k <= size(D.fc.pv,2));
            fcVal = D.fc.pv(locM(d,j), k);
            switch srcMode
                case 'a3',     H(h0+1) = fcVal;
                case 'self',   H(h0+1) = SelfHour(h0+1);
                case 'blend3', H(h0+1) = wBlend*fcVal + (1-wBlend)*SelfHour(h0+1);
                otherwise, error('q3_forecast: 未知 pvSource = %s', srcMode);
            end
        end
        X = p0_downscale(H, qc.dsMethod, cfg, SH);       % 1×144（内部 assert 守恒）
        F.Phat4(d,:,j) = X;
    end
end
F.Nhat4 = reshape(F.Lhat, nd, nt, 1) - F.Phat4;       % 隐式扩展

% ================= 4. 汇总 =================
F.Nact     = L - P;
F.Nhat     = F.Nhat4(:,:,1);
F.issHours = issH;
F.dsMethod = qc.dsMethod;
F.pvSource = srcMode;
switch srcMode
    case 'a3',     srcTxt = '附件3 官方预报';
    case 'self',   srcTxt = sprintf('自预测(%s)，不用附件3', qc.pvSelfMethod);
    case 'blend3', srcTxt = sprintf('混合 w=%.2f·附件3 + %.2f·自预测', wBlend, 1-wBlend);
    otherwise,     srcTxt = srcMode;
end
F.note = sprintf('负载: %s（自预测，附件3 无负载预报）| 光伏: %s | 降尺度: %s', ...
                 qc.loadMethod, srcTxt, qc.dsMethod);

% ---- 自检 A：a3 分支下 0:00 的预报必须【整日】来自附件3（不掺任何实测）----
%      换源分支（self/blend3）本来就不取自附件3，此检跳过。
if strcmp(srcMode, 'a3')
    d0 = 100;
    Href = D.fc.pv(locM(d0,1), :);                  % 1×24，附件3 的 0:00 行
    Xref = p0_downscale(Href, qc.dsMethod, cfg, SH);
    assert(max(abs(F.Phat4(d0,:,1) - Xref)) < 1e-9, ...
        '0:00 预报未整日取自附件3（降尺度结果与设计式不符）');
end

% ---- 自检 B：降尺度的小时均值守恒（对全部日/时刻抽检）----
% ⚠️ 参考值必须按【本分支实际取用的来源】选，不能一律拿附件3 当参考。
%    换源分支（self / blend3）下 Phat4 来自自预测（或混合权重），与附件3 本就不同，
%    拿附件3 作参考必然误报「降尺度破坏守恒」——该错误曾让 t_q3_ablation 的实验二
%    （预报来源对照）在 S1 上抛错中断，使消融只剩实验一。判据的本意是
%    「降尺度把小时值摊到 6 个槽后，6 槽均值必须回升到那个小时值」，
%    这里的"那个小时值"是来源值，不是附件3 的值。
chkD = [1 50 150 300 365];  chkJ = 1:nIss;
for d = chkD
    SelfHour = hourMeans(F.PhatSelf(d,:));           % 1×24，与来源分支同一套
    for j = chkJ
        tau = issH(j);
        for h0 = tau:23
            blk = F.Phat4(d, 6*h0+(1:6), j);
            switch srcMode
                case 'a3',     ref = D.fc.pv(locM(d,j), h0-tau+1);
                case 'self',   ref = SelfHour(h0+1);
                case 'blend3', ref = wBlend*D.fc.pv(locM(d,j), h0-tau+1) ...
                                    + (1-wBlend)*SelfHour(h0+1);
                otherwise,     error('q3_forecast: 未知 pvSource = %s', srcMode);
            end
            assert(abs(mean(blk) - ref) < 1e-9*max(1,abs(ref)), ...
                '降尺度破坏了第 %d 天 第 %d 时刻 h0=%d 的小时均值', d, tau, h0);
        end
    end
end

% ---- 自检 C：负载预测器与问题二的输出必须逐位一致（可比性的前提）----
if isfield(D,'_q2check')  % 预留钩子，默认不触发
    assert(false, '未使用');
end

if qc.verbose
    fprintf('  q3_forecast：负载 %s | 光伏 附件3(%s) | 降尺度 %s\n', qc.loadMethod, qc.pvSource, qc.dsMethod);
    fprintf('    四套净负荷预报已生成：%s\n', mat2str(F.issHours));
    % 精度对照（客观数据事实，可引用）。
    % ⚠️ 必须只统计该发布时刻【尚未发生】的时段——否则「18:00 的预报」里有一整天
    %    实测值冒充预报，RMSE 会被虚低。下表第二列即此偏差，勿引用。
    dr = qc.dayIdx(:);
    rS = F.PhatSelf(dr,:) - P(dr,:);
    r0 = F.Phat4(dr,:,1) - P(dr,:);
    fprintf('    —— 首日同口径对照（均覆盖整日 144 槽，可直接比较）——\n');
    fprintf('       自预测 mean7     PV RMSE %7.2f kW\n', sqrt(mean(rS(:).^2)));
    fprintf('       附件3 0:00 预报  PV RMSE %7.2f kW\n', sqrt(mean(r0(:).^2)));
    fprintf('    —— 各发布时刻的【剩余时段】预报精度（只统计该时刻尚未发生的槽）——\n');
    for j = 1:nIss
        tau = issH(j);
        fut = false(1, nt);  fut(6*tau+1:end) = true;
        if ~any(fut), continue; end
        rJ = F.Phat4(dr,:,j) - P(dr,:);
        rJf = rJ(:, fut);
        fprintf('       %02d:00 预报（剩 %2d 槽） PV RMSE %7.2f kW\n', ...
            tau, sum(fut), sqrt(mean(rJf(:).^2)));
    end
end
end

% ======================================================================
function y = fcLoad(X, d, method)
% 负载预测，与问题二 q2_forecast.m 的 fcLoad 逐位一致（保证两问可比）
switch lower(method)
    case 'blend'
        ks = 7*(1:4);
        ks = ks(d - ks >= 1);
        if isempty(ks)
            y = X(max(1, d-1), :);
        else
            base = mean(X(d-ks, :), 1);
            if d - 7 >= 1
                y = 0.5*X(d-7, :) + 0.5*base;
            else
                y = base;
            end
        end
    otherwise
        error('q3_forecast: 未知负载预测法 %s', method);
end
end

function y = fcPV(X, d, method)
% 自预测光伏（仅消融对照用）
switch lower(method)
    case 'mean7'
        if d == 1
            y = X(1, :);                 % 无历史：退化为当日（仅第 1 天，Q3 区间不含）
        else
            y = mean(X(max(1,d-7):d-1, :), 1);
        end
    otherwise
        error('q3_forecast: 未知光伏自预测法 %s', method);
end
end

function h = hourMeans(row)
% 144 槽 → 24 个小时均值（1×24）
h = mean(reshape(row, 6, 24), 1);
end

