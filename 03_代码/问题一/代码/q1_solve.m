function sol = q1_solve(dataFile,outDir)
% q1_solve
% 问题一确定性线性规划模型。
%
% 决策变量（功率口径）：
%   g_t : 外网购电功率 kW
%   c_t : 交流侧充电功率 kW
%   d_t : 交流侧放电功率 kW
%   w_t : 弃光/富余功率 kW
%
% 功率平衡：
%   g_t + PV_t + d_t = L_t + c_t + w_t
%
% SOC动态：
%   S_t = S_{t-1} + (eta*c_t - d_t/eta)*dt
%
% 目标：
%   min sum(price_t * g_t * dt)

if nargin<2 || isempty(outDir), outDir='out'; end
if ~exist(outDir,'dir'), mkdir(outDir); end

T=readtable(dataFile,'VariableNamingRule','preserve');
price=T.price_yuan_per_kWh(:);
loadP=T.load_kW(:);
pvP=T.pv_forecast_kW(:);
n=height(T);

% 参数
dt   = 1/6;      % h
eta  = 0.90;
S0   = 6000;     % kWh
Smin = 1200;
Smax = 10800;
Pmax = 5000;     % kW

% x=[g,c,d,w]
ig=1:n;
ic=n+(1:n);
id=2*n+(1:n);
iw=3*n+(1:n);

% 目标函数
f=zeros(4*n,1);
f(ig)=price*dt;

% 等式：功率平衡 + 日末SOC回到S0
Aeq=zeros(n+1,4*n);
beq=zeros(n+1,1);
for t=1:n
    Aeq(t,ig(t))= 1;
    Aeq(t,ic(t))=-1;
    Aeq(t,id(t))= 1;
    Aeq(t,iw(t))=-1;
    beq(t)=loadP(t)-pvP(t);
end
Aeq(n+1,ic)= eta*dt;
Aeq(n+1,id)=-dt/eta;
beq(n+1)=0;

% SOC上下界
% C*x = S_t-S0
C=zeros(n,4*n);
for t=1:n
    C(t,ic(1:t))= eta*dt;
    C(t,id(1:t))=-dt/eta;
end
A=[-C;C];
b=[(S0-Smin)*ones(n,1);(Smax-S0)*ones(n,1)];

% 变量边界
lb=zeros(4*n,1);
ub=inf(4*n,1);
ub(ic)=Pmax;
ub(id)=Pmax;

% 求解
opts=optimoptions('linprog','Algorithm','dual-simplex','Display','none');
[x,fval,exitflag,output]=linprog(f,A,b,Aeq,beq,lb,ub,opts);
if exitflag<=0
    error('线性规划求解失败：%s',output.message);
end

g=x(ig); c=x(ic); d=x(id); w=x(iw);
SOC=[S0; S0+cumsum((eta*c-d/eta)*dt)];

% 转换成时段电量
grid_kWh      = g*dt;
charge_kWh    = c*dt;
discharge_kWh = d*dt;
curtail_kWh   = w*dt;

% 指标
totalPurchase=sum(grid_kWh);
totalCost=sum(price.*grid_kWh);
baseGrid=max(loadP-pvP,0);
baseCost=sum(price.*baseGrid*dt);
saving=baseCost-totalCost;
savingRate=saving/baseCost;

metrics=struct( ...
    'totalLoad_kWh',sum(loadP)*dt, ...
    'totalPV_kWh',sum(pvP)*dt, ...
    'totalPurchase_kWh',totalPurchase, ...
    'totalCost_yuan',totalCost, ...
    'baseCost_yuan',baseCost, ...
    'saving_yuan',saving, ...
    'savingRate',savingRate, ...
    'socMin_kWh',min(SOC), ...
    'socMax_kWh',max(SOC), ...
    'soc0_kWh',SOC(1), ...
    'soc24_kWh',SOC(end), ...
    'curtailment_kWh',sum(curtail_kWh), ...
    'simultaneousSlots',nnz(c>1e-7 & d>1e-7), ...
    'objectiveValue',fval);

% 表1：指定时段
startMin=[600 720 840 960 1080 1200];
labels=["10:00-10:10";"12:00-12:10";"14:00-14:10"; ...
        "16:00-16:10";"18:00-18:10";"20:00-20:10"];
idx=startMin/10+1;
Table1=table(labels,grid_kWh(idx), ...
    'VariableNames',{'时间段','购电量_kWh'});

% 表2：六个4小时段
segStart=(0:240:1200)';
segLabel=strings(6,1);
segC=zeros(6,1);
segD=zeros(6,1);
for k=1:6
    mask=T.interval_start_min>=segStart(k) & ...
         T.interval_start_min<segStart(k)+240;
    segC(k)=sum(charge_kWh(mask));
    segD(k)=sum(discharge_kWh(mask));
    segLabel(k)=sprintf('%d:00-%d:00',segStart(k)/60,(segStart(k)+240)/60);
end
Table2=table(segLabel,segC,segD, ...
    'VariableNames',{'时间段','充电量_kWh','放电量_kWh'});

% 完整结果
R=T;
R.grid_kW=g;
R.charge_kW=c;
R.discharge_kW=d;
R.curtail_kW=w;
R.grid_kWh=grid_kWh;
R.charge_kWh=charge_kWh;
R.discharge_kWh=discharge_kWh;
R.curtail_kWh=curtail_kWh;
R.soc_end_kWh=SOC(2:end);

writetable(R,fullfile(outDir,'q1_solution.csv'));
writetable(Table1,fullfile(outDir,'q1_table1.csv'));
writetable(Table2,fullfile(outDir,'q1_table2.csv'));

M=struct2table(metrics);
writetable(M,fullfile(outDir,'q1_summary.csv'));

% 返回结构体
sol=struct();
sol.T=T;
sol.price=price;
sol.loadP=loadP;
sol.pvP=pvP;
sol.g=g; sol.c=c; sol.d=d; sol.w=w;
sol.SOC=SOC;
sol.dt=dt; sol.eta=eta;
sol.S0=S0; sol.Smin=Smin; sol.Smax=Smax; sol.Pmax=Pmax;
sol.grid_kWh=grid_kWh;
sol.charge_kWh=charge_kWh;
sol.discharge_kWh=discharge_kWh;
sol.curtail_kWh=curtail_kWh;
sol.metrics=metrics;
sol.Table1=Table1;
sol.Table2=Table2;
sol.R=R;

fprintf('  全天购电量 = %.3f kWh\n',totalPurchase);
fprintf('  全天购电费 = %.3f 元\n',totalCost);
fprintf('  无储能基准费用 = %.3f 元\n',baseCost);
fprintf('  节省 = %.3f 元（%.2f%%）\n',saving,100*savingRate);
end
