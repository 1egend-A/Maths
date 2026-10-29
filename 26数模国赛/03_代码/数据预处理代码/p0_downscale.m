function X = p0_downscale(H, method, cfg, shape)
% P0_DOWNSCALE  小时 → 10 分钟降尺度，【保证每小时均值严格守恒】
%
% 用法：
%   X = p0_downscale(H, method, cfg)           % H: n×24 或 24×1（小时值）
%   X = p0_downscale(H, method, cfg, shape)    % shape: 1×24×6 或 24×6 形状权重
%
% 输入
%   H      : 小时值。行数 = 天数，24 列 = 一天 24 小时（或列向量 = 单日 24 小时）
%   method : 'stair'  阶梯：每小时 6 个槽都取该小时值（均值必然守恒，最保守）
%            'linear' 线性：以小时为节点线性插值到 10 分钟，再按小时重标定保均值
%            'shape'  形状：用 typical 日内 10 分钟形状权重分配到 6 个槽
%   shape  : method='shape' 时的权重。允许 24×6（每小时一行）。
%            缺省时用【内部默认】的屋顶光伏典型形状（正午单峰）。
%
% 输出
%   X      : n×144，10 分钟粒度。列 i 对应第 i 个 10 分钟时段（右端点口径）。
%
% 【不变量】mean(X(:,6*(h-1)+1:6*h), 2) 必须等于 H(:,h)，到机器精度。
%           本函数末尾用 assert 强制校验，任何降尺度方法都不得破坏该守恒。

if nargin < 3 || isempty(cfg), cfg = p0_config(); end
if nargin < 2 || isempty(method), method = 'stair'; end

if isvector(H), H = reshape(H, 1, []); end
[n, nh] = size(H);
if nh == 24
    % 已经是 天数×24，直接用
elseif n == 24
    H = H.'; n = size(H,1);
else
    error('p0_downscale: 输入必须有一维等于 24，当前 %d×%d', n, nh);
end
if size(H,2) ~= 24
    error('p0_downscale: 第二维必须为 24');
end
% 非有限值必须【立即报错】：NaN 参与比较时 NaN > tol 恒为假，末尾的不变量
% 校验会静默放行，把一个含 NaN 的预测悄悄送进优化模型。
if any(~isfinite(H(:)))
    error('p0_downscale: 输入 H 含 NaN/Inf（%d 个），无法保证均值守恒', sum(~isfinite(H(:))));
end

switch lower(method)
    case 'stair'
        % ⚠️ 必须是 kron(H, ones(1,6))，不是 repmat(H,1,6)！
        %    repmat(H,1,6) = [H H H H H H] 是【整块平铺】，第 1 小时的 6 个槽会变成
        %    H(1:6)，整张矩阵被洗牌；实测偏差 5.608e+03 kW。
        %    kron(H, ones(1,6)) 才是「每个元素各复制 6 份」（n×24 → n×144）。
        X = kron(H, ones(1, 6));            % 每小时 6 个槽同值
        X = renormHourly(X, H);            % 冗余但统一，保证不变量对所有方法成立

    case 'linear'
        tq = (0.5:1:143.5) / 6;              % 144 个槽中心（单位：小时）
        X = zeros(n, 144);
        for r = 1:n
            v = interp1(0:23, H(r,:), tq, 'linear', 'extrap');
            X(r,:) = v;
        end
        X = renormHourly(X, H);              % 线性插值会破坏小时均值，必须重标定

    case 'shape'
        if nargin < 4 || isempty(shape)
            shape = defaultShape();
        end
        shape = reshape(shape, 24, 6);
        shape = shape ./ (mean(shape, 2) * ones(1, 6));   % 每小时权重归一化到均值 1
        X = zeros(n, 144);
        for r = 1:n
            for h = 1:24
                X(r, 6*(h-1)+(1:6)) = H(r,h) * shape(h,:);
            end
        end
        X = renormHourly(X, H);

    otherwise
        error('p0_downscale: 未知 method = %s', method);
end

% ---- 不变量校验：每小时均值必须严格守恒 ----
Hq = zeros(n, 24);
for h = 1:24
    Hq(:,h) = mean(X(:, 6*(h-1)+(1:6)), 2);
end
err = max(abs(Hq(:) - H(:)));
if err > 1e-9 * max(1, max(abs(H(:))))
    error('p0_downscale: 小时均值守恒被破坏，最大偏差 %.3e', err);
end
end

% ==================================================================
function X = renormHourly(X, H)
% 逐小时把 6 个槽【按比例重分配】，使该小时均值严格等于 H。
%
% 实现要点（这里是踩过坑之后改的，别简化）：
%   不能用 X(:,idx) = blk .* (tgt./mean(blk,2))：
%   当某个块的均值为【负】或【极接近 0】时，该式要么把符号翻转，
%   要么因 0/0 被迫跳过，导致小时均值守恒被静默破坏。
%   （实测：linear+extrap 在日末端外推出负均值块，偏差达 3.5e+02 kW。）
%
%   正确做法：把块内 6 个槽当【非负权重】看，按 sum(w) 比例分配 tgt*6。
%     - 恒保均值：sum(w .* (6*tgt/sum(w))) / 6 = tgt
%     - 恒保非负：tgt >= 0 且 w >= 0 时结果非负
%     - 退化（权重和 ≈ 0）时均匀铺开为 tgt/6，仍保均值
%   输入约定：H 与 X 必须非负（功率/电量），负权重无物理意义。

[n, ~] = size(X);
tol = 1e-12;
for h = 1:24
    idx = 6*(h-1) + (1:6);
    w   = X(:, idx);
    w(~isfinite(w)) = 0;
    w   = max(w, 0);                    % 权重非负（clamp 掉外推的负值）
    tgt = H(:, h);
    s   = sum(w, 2);

    good = s > tol;
    kk   = ones(n,1);
    kk(good) = 6 * tgt(good) ./ s(good);
    X(:, idx) = w .* kk;                % 退化行此时全 0

    bad = ~good;
    if any(bad)
        X(bad, idx) = repmat(tgt(bad)/6, 1, 6);
    end
end
end

% ==================================================================
function S = defaultShape()
% 默认日内 10 分钟形状：屋顶光伏典型单峰。
% 注意：这是【占位默认值】。真正跑题时应传入用附件2 实际光伏统计出的形状，
%       即 pv_shape(D,cfg)。此处仅保证函数可独立调用。
w = [0.15 0.12 0.12 0.13 0.18 0.30 0.60 0.95 1.25 1.50 1.70 1.85 ...
     1.95 1.95 1.85 1.65 1.35 1.05 0.80 0.55 0.35 0.22 0.18 0.16];
S = repmat(w(:), 1, 6);                  % 24×6
end
