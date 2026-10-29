addpath('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码');
D = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码\out\data.mat').D;
S = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\问题二\out\q2_solution.mat'); qc=S.qc;
d=32; n=144; dt=qc.dt; eta=qc.eta;
price=D.day144.price(:); load=D.actual.load(d,:)'; pv=D.actual.pv(d,:)'; N=load-pv;
ig=1:n; ic=n+(1:n); id=2*n+(1:n); iS=3*n+(1:n); ie=4*n+(1:n); nVar=5*n;
Aeq1=sparse(repmat((1:n)',5,1),[ig(:);id(:);ie(:);ic(:);iS(:)], ...
    [ones(n,1);ones(n,1);-ones(n,1);-ones(n,1);zeros(n,1)],n,nVar);
Aeq2=sparse(repmat((1:n)',4,1),[iS(:);iS(:);ic(:);id(:)], ...
    [ones(n,1);[-ones(n-1,1);0];-eta*dt*ones(n,1);(dt/eta)*ones(n,1)],n,nVar);
Aeq=[Aeq1;Aeq2]; beq=[N;[qc.S0;zeros(n-1,1)]];
% 显式可行点：c=d=0, S 恒为 6000, g=max(N,0), e=max(-N,0)
x=zeros(nVar,1); x(iS)=qc.S0*ones(n,1); x(ig)=max(N,0); x(ie)=max(-N,0);
r=Aeq*x-beq;
fprintf('显式点残差 max=%.3e , 非零行=%d\n', max(abs(r)), sum(abs(r)>1e-9));
fprintf('  g>=0:%d e>=0:%d c=d=0 S=6000 在[%g,%g]内, S_144=%g\n', ...
    all(x(ig)>=-1e-9), all(x(ie)>=-1e-9), qc.S_min, qc.S_max, x(iS(n)));
fprintf('  N 范围 [%.1f, %.1f] , 日净能量 Σ N*dt = %.1f kWh\n', min(N), max(N), sum(N)*dt);
% 单变量加界测试
f=zeros(nVar,1); f(ig)=price*dt;
opts=optimoptions('linprog','Display','off');
ub=inf(nVar,1); lb=zeros(nVar,1);
[~,~,fl]=linprog(f,[],[],Aeq,beq,lb,ub,opts); fprintf(' 只有 S 上界? (无) flag=%d\n',fl);
ub2=ub; ub2(iS)=qc.S_max; lb2=lb; lb2(iS)=qc.S_min;
[~,~,fl]=linprog(f,[],[],Aeq,beq,lb2,ub2,opts); fprintf(' 仅加 S∈[1200,10800]  flag=%d\n',fl);
ub3=ub; ub3(ic)=qc.P_max; ub3(id)=qc.P_max;
[~,~,fl]=linprog(f,[],[],Aeq,beq,lb,ub3,opts); fprintf(' 仅加 c,d<=5000       flag=%d\n',fl);

jj = find(abs(r)>1e-9);
for q = jj(:)'
    fprintf('行 %d : 残差 %.4f ; Aeq*x 项 = ', q, r(q));
    [cc,~,vv] = find(Aeq(q,:));
    for z = 1:numel(cc), fprintf('[%d]*%.4g=%.4g ', cc(z), full(vv(z)), full(vv(z))*x(cc(z))); end
    fprintf('| beq = %.4g\n', beq(q));
end
