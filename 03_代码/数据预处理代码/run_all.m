function run_all()
% RUN_ALL  阶段 0 全流程：读入 → 验收 → 闸门 G0
% 用法：matlab -batch "run_all"

cfg = p0_config();
fprintf('########## 阶段 0：数据管道 ##########\n');
fprintf('数据目录: %s\n', cfg.base);
fprintf('输出目录: %s\n\n', cfg.outdir);

D = p0_load(cfg);
fprintf('[1/3] p0_load 完成\n');
fprintf('      附件1 时段 %d | 附件2/4 天数 %d | 附件3 预报 %d x %d\n', ...
    numel(D.day144.price), D.meta.nDays, size(D.fc.pv,1), size(D.fc.pv,2));
fprintf('      日期区间 %s .. %s\n\n', datestr(D.meta.dateFirst,'yyyy-mm-dd'), datestr(D.meta.dateLast,'yyyy-mm-dd'));

fprintf('[2/3] p0_check 验收中...\n\n');
ok = p0_check();

fprintf('\n[3/3] 闸门 G0 ...\n\n');
g0_feb01();

fprintf('\n########## 阶段 0 结束：p0_check = %d ##########\n', ok);
end
