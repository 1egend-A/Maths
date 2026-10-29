addpath('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码');
D = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\数据预处理代码\out\data.mat').D;
S = load('D:\HuaweiMoveData\Users\26313\Desktop\2026数模国赛\问题二\out\q2_solution.mat'); R=S.R; qc=S.qc;
d=32; n=144; dt=qc.dt; eta=qc.eta;
price=D.day144.price(:); load=D.actual.load(d,:)'; pv=D.actual.pv(d,:)'; N=load-pv;
ig=1:n; ic=n+(1:n); id=2*n+(1:n); iS=3*n+(1:n); ie=4*n+(1:n); nVar=5*n;
Aeq1=sparse(repmat((1:n)',5,1),[ig(:);id(:);ie(:);ic(:);iS(:)], ...
    [ones(n,1);ones(n,1);-ones(n,1);-ones(n,1);zeros(n,1)],n,nVar);
Aeq2=sparse(repmat((1:n)',4,1),[iS(:);iS(:);ic(:);id(:)], ...
    [ones(n,1);[-ones(n-1,1);0];-eta*dt*ones(n,1);(dt/eta)*ones(n,1)],n,nVar);
Aeq=[Aeq1;Aeq2]; beq=[N;[qc.S0;zeros(n-1,1)]];
f=zeros(nVar,1); f(ig)=price*dt;
fprintf('R.Soc(1,1:3) = %s\n', mat2str(R.Soc(1,1:3),8));
fprintf('R.c(1,1:3)   = %s , R.d(1,1:3) = %s\n', mat2str(R.c(1,1:3),8), mat2str(R.d(1,1:3),8));
opts=optimoptions('linprog','Display','off');
lb=zeros(nVar,1); ub=inf(nVar,1);
[~,~,fl]=linprog(f,[],[],Aeq,beq,lb,ub,opts);      fprintf('L1 仅非负下界           flag=%d\n',fl);
ub(ic)=qc.P_max; ub(id)=qc.P_max;
[~,~,fl]=linprog(f,[],[],Aeq,beq,lb,ub,opts);      fprintf('L2 +P_max 上界          flag=%d\n',fl);
lb(iS)=qc.S_min; ub(iS)=qc.S_max;
[~,~,fl]=linprog(f,[],[],Aeq,beq,lb,ub,opts);      fprintf('L3 +SOC 上下限          flag=%d\n',fl);
lb(iS(n))=qc.S_end; ub(iS(n))=qc.S_end;
[~,~,fl]=linprog(f,[],[],Aeq,beq,lb,ub,opts);      fprintf('L4 +日末闭环            flag=%d\n',fl);
fprintf('  lb NaN=%d Inf=%d | ub NaN=%d Inf=%d | numel lb=%d ub=%d\n', ...
    sum(isnan(lb)),sum(isinf(lb)),sum(isnan(ub)),sum(isinf(ub)),numel(lb),numel(ub));
fprintf('  size(Aeq)=%dx%d numel(beq)=%d\n', size(Aeq,1),size(Aeq,2),numel(beq));
