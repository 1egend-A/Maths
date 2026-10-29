function [S, info] = soc_sim(c, d, S0, cfg)
% SOC_SIM  由充放电功率序列推 SOC 轨迹
%   c, d : 各时段充电 / 放电功率 (kW)，等长
%   S0   : 起始 SOC (kWh)
%   S    : 各时段【末】的 SOC (kWh)，与 c 等长
%
% 口径由 cfg.effConv 决定，见 p0_config.m。

c = c(:); d = d(:);
assert(numel(c) == numel(d), 'c 与 d 长度必须一致');

switch cfg.effConv
    case 'ac'
        delta = (c*cfg.eta - d/cfg.eta) * cfg.dt;
    case 'dc'
        delta = (c - d) * cfg.dt;
    otherwise
        error('未知 cfg.effConv = %s', cfg.effConv);
end

S = S0 + cumsum(delta);

info.S0       = S0;
info.minS     = min([S0; S]);
info.maxS     = max([S0; S]);
info.endS     = S(end);
info.violLow  = sum(S < cfg.S_min - 1e-6);
info.violHigh = sum(S > cfg.S_max + 1e-6);
info.ok       = (info.violLow == 0) && (info.violHigh == 0);
end
