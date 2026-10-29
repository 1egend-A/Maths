addpath('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码');
D = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码\out\data.mat').D;
S = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\问题二\out\q2_solution.mat');
R = S.R; qc = S.qc;
d = 32; n = 144; dt = qc.dt; eta = qc.eta;
price = D.day144.price(:); load = D.actual.load(d,:)'; pv = D.actual.pv(d,:)';
N = load - pv;
ig = 1:n; ic = n+(1:n); id = 2*n+(1:n); iS = 3*n+(1:n); ie = 4*n+(1:n); nVar = 5*n;
Aeq1 = sparse(repmat((1:n)',5,1), [ig(:); id(:); ie(:); ic(:); iS(:)], ...
              [ones(n,1); ones(n,1); -ones(n,1); -ones(n,1); zeros(n,1)], n, nVar);
Aeq2 = sparse(repmat((1:n)',4,1), [iS(:); iS(:); ic(:); id(:)], ...
              [ones(n,1); [-ones(n-1,1); 0]; -eta*dt*ones(n,1); (dt/eta)*ones(n,1)], n, nVar);
Aeq = [Aeq1; Aeq2];
beq = [N; [qc.S0; zeros(n-1,1)]];
fprintf('size(Aeq) = %dx%d , numel(beq) = %d , nVar = %d\n', size(Aeq,1), size(Aeq,2), numel(beq), nVar);
% 手工可行点：借 q2 解的 c,d
c = R.c(1,:)'; dd = R.d(1,:)';
y = N + c - dd;
g = max(0,y); e = max(0,-y);
x = zeros(nVar,1); x(ig)=g; x(ic)=c; x(id)=dd; x(iS)=R.Soc(1,:)'; x(ie)=e;
r = Aeq*x - beq;
fprintf('手工点残差 max = %.3e ，非零行数 = %d\n', max(abs(r)), sum(abs(r)>1e-8));
bad = find(abs(r)>1e-8, 5);
for k = bad(:)', fprintf('  行 %d 残差 %.4f （平衡行=%d, SOC行=%d）\n', k, r(k), k<=n, k>n); end
% 无约束上界检查
fprintf('g>=0? %d , e>=0? %d , c范围[%.1f,%.1f] , d范围[%.1f,%.1f]\n', ...
    all(g>=-1e-9), all(e>=-1e-9), min(c), max(c), min(dd), max(dd));
opts = optimoptions('linprog','Display','off');
f0 = zeros(nVar,1); f0(ig) = price*dt;
[x2,~,fl] = linprog(f0,[],[],Aeq,beq,zeros(nVar,1), ...
    [repmat(inf,nVar,1)], opts);
fprintf('用 inf 上界：flag = %d\n', fl);
