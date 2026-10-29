%% q1_main.m
% 2026 高教社杯全国大学生数学建模竞赛 C 题 - 问题一
% 功能：读取预处理后的附件1，建立线性规划模型，求解单日购电与储能充放电策略。
% 需要：Optimization Toolbox (linprog)

clear; clc;

%% 1. 参数设置
dataFile = fullfile('..','preprocessed','data','attachment1_10min.csv');
if ~isfile(dataFile)
    dataFile = fullfile('data','attachment1_10min.csv');
end
T = readtable(dataFile, 'VariableNamingRule','preserve');

price = T.price_yuan_per_kWh(:);   % 元/kWh
loadP = T.load_kW(:);              % kW
pvP   = T.pv_forecast_kW(:);       % kW
n = height(T);                     % 144

dt   = 1/6;                       % 10 min = 1/6 h
eta  = 0.90;                       % 单向充放电效率
S0   = 6000;                       % kWh
Smin = 1200;                       % kWh
Smax = 10800;                      % kWh
Pmax = 5000;                       % kW

%% 2. 决策变量
% x = [g_1...g_n, c_1...c_n, d_1...d_n, w_1...w_n]^T
% g：外网购电功率；c：储能充电功率；d：储能放电功率；w：弃光功率，单位均为 kW
ig = 1:n; ic = n+(1:n); id = 2*n+(1:n); iw = 3*n+(1:n);

%% 3. 目标函数：min sum p_t * g_t * dt
f = zeros(4*n,1);
f(ig) = price * dt;

%% 4. 等式约束
% 4.1 功率平衡：g_t + PV_t + d_t = L_t + c_t
% 4.2 日末储电量：S_144 = S_0
Aeq = zeros(n+1,4*n);
beq = zeros(n+1,1);
for t = 1:n
    Aeq(t,ig(t)) = 1;
    Aeq(t,ic(t)) = -1;
    Aeq(t,id(t)) = 1;
    Aeq(t,iw(t)) = -1; % g + PV + d = L + c + w
    beq(t) = loadP(t) - pvP(t);
end
Aeq(n+1,ic) = eta*dt;
Aeq(n+1,id) = -dt/eta;
beq(n+1) = 0;

%% 5. 不等式约束：1200 <= S_t <= 10800
% S_t = S0 + sum_{k=1}^t (eta*c_k - d_k/eta)*dt
C = zeros(n,4*n);
for t = 1:n
    C(t,ic(1:t)) = eta*dt;
    C(t,id(1:t)) = -dt/eta;
end
A = [-C; C];
b = [-(Smin-S0)*ones(n,1); (Smax-S0)*ones(n,1)];

%% 6. 变量范围
lb = zeros(4*n,1);
ub = inf(4*n,1);
ub(ic) = Pmax;
ub(id) = Pmax;

%% 7. 线性规划求解
opts = optimoptions('linprog','Algorithm','dual-simplex','Display','none');
[x,fval,exitflag,output] = linprog(f,A,b,Aeq,beq,lb,ub,opts);
if exitflag ~= 1
    error('线性规划未正常收敛：%s', output.message);
end

g = x(ig); c = x(ic); d = x(id); w = x(iw);
SOC = [S0; S0 + cumsum((eta*c - d/eta)*dt)];

%% 8. 结果指标
purchase_kWh = g*dt;
charge_kWh   = c*dt;
discharge_kWh= d*dt;

totalPurchase = sum(purchase_kWh);
totalCost = sum(price .* purchase_kWh);
baseGrid = max(loadP-pvP,0);
baseCost = sum(price .* baseGrid * dt);
saving = baseCost-totalCost;
savingRate = saving/baseCost;

fprintf('问题一最优解：\n');
fprintf('全天购电量 = %.3f kWh\n', totalPurchase);
fprintf('全天购电费 = %.3f 元\n', totalCost);
fprintf('无储能基准费用 = %.3f 元\n', baseCost);
fprintf('节省费用 = %.3f 元 (%.2f%%)\n', saving, 100*savingRate);
fprintf('SOC范围 = [%.3f, %.3f] kWh\n', min(SOC), max(SOC));
fprintf('0:00 SOC = %.3f kWh, 24:00 SOC = %.3f kWh\n', SOC(1), SOC(end));
fprintf('同时充放电时段数 = %d\n', nnz(c>1e-7 & d>1e-7));
fprintf('全天弃光量 = %.6f kWh\n', sum(w)*dt);

%% 9. 保存完整时序结果
R = T;
R.grid_kW = g;
R.charge_kW = c;
R.discharge_kW = d;
R.curtail_kW = w;
R.grid_kWh = purchase_kWh;
R.charge_kWh = charge_kWh;
R.discharge_kWh = discharge_kWh;
R.soc_end_kWh = SOC(2:end);
writetable(R,'q1_solution_matlab.csv');

%% 10. 生成题目要求的表1数据
startMin = [600 720 840 960 1080 1200];
labels = ["10:00-10:10";"12:00-12:10";"14:00-14:10"; ...
          "16:00-16:10";"18:00-18:10";"20:00-20:10"];
idx = startMin/10 + 1; % 右端点口径：10:00-10:10 对应附件中的 10:10
Table1 = table(labels, purchase_kWh(idx), 'VariableNames',{'时间段','购电量_kWh'});
disp(Table1);

%% 11. 生成题目要求的表2数据
segStart = (0:240:1200)';
segLabel = strings(6,1);
segC = zeros(6,1); segD = zeros(6,1);
for k = 1:6
    mask = T.interval_start_min >= segStart(k) & T.interval_start_min < segStart(k)+240;
    segC(k) = sum(charge_kWh(mask));
    segD(k) = sum(discharge_kWh(mask));
    segLabel(k) = sprintf('%d:00-%d:00',segStart(k)/60,(segStart(k)+240)/60);
end
Table2 = table(segLabel,segC,segD,'VariableNames',{'时间段','充电量_kWh','放电量_kWh'});
disp(Table2);

writetable(Table1,'q1_table1_matlab.csv');
writetable(Table2,'q1_table2_matlab.csv');

%% 12. 调用可视化脚本
q1_visualization;
