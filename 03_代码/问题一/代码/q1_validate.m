function q1_validate(sol,outDir)
% q1_validate
% 独立校验问题一最优解：
% - 逐时段功率平衡
% - SOC动态与边界
% - 充放电功率上限
% - 首末SOC
% - 同时充放电检查
% - 费用复算

if nargin<2 || isempty(outDir), outDir='out'; end

tol=1e-6;

g=sol.g; c=sol.c; d=sol.d; w=sol.w;
L=sol.loadP; PV=sol.pvP; p=sol.price;
SOC=sol.SOC;
dt=sol.dt; eta=sol.eta;

balanceResidual = g + PV + d - L - c - w;
maxBalanceErr=max(abs(balanceResidual));

socStep = diff(SOC) - (eta*c-d/eta)*dt;
maxSocStepErr=max(abs(socStep));

costRecalc=sum(p.*g*dt);
costErr=abs(costRecalc-sol.metrics.totalCost_yuan);

okBalance=maxBalanceErr<1e-5;
okSOCStep=maxSocStepErr<1e-5;
okSOCBound=all(SOC>=sol.Smin-tol & SOC<=sol.Smax+tol);
okPower=all(c<=sol.Pmax+tol & d<=sol.Pmax+tol & c>=-tol & d>=-tol);
okTerminal=abs(SOC(end)-sol.S0)<1e-5;
simul=nnz(c>1e-7 & d>1e-7);
okCost=costErr<1e-6;

if ~(okBalance && okSOCStep && okSOCBound && okPower && okTerminal && okCost)
    error('结果校验未全部通过，请查看 q1_validation.txt。');
end

reportFile=fullfile(outDir,'q1_validation.txt');
fid=fopen(reportFile,'w','n','UTF-8');
fprintf(fid,'C题问题一结果校验报告\n');
fprintf(fid,'========================\n');
fprintf(fid,'最大功率平衡误差: %.12g kW\n',maxBalanceErr);
fprintf(fid,'最大SOC递推误差: %.12g kWh\n',maxSocStepErr);
fprintf(fid,'SOC最小值: %.6f kWh\n',min(SOC));
fprintf(fid,'SOC最大值: %.6f kWh\n',max(SOC));
fprintf(fid,'0:00 SOC: %.6f kWh\n',SOC(1));
fprintf(fid,'24:00 SOC: %.6f kWh\n',SOC(end));
fprintf(fid,'最大充电功率: %.6f kW\n',max(c));
fprintf(fid,'最大放电功率: %.6f kW\n',max(d));
fprintf(fid,'同时充放电时段数: %d\n',simul);
fprintf(fid,'全天弃光量: %.6f kWh\n',sum(w)*dt);
fprintf(fid,'费用复算误差: %.12g 元\n',costErr);
fprintf(fid,'校验结论: 全部通过\n');
fclose(fid);

fprintf('  校验通过：平衡误差 %.3e，SOC范围 [%.3f, %.3f] kWh。\n', ...
    maxBalanceErr,min(SOC),max(SOC));
end
