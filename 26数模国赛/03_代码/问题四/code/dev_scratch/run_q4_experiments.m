function run_q4_experiments()
% RUN_Q4_EXPERIMENTS  顺序跑问题四的四个分析/加分脚本，失败互不影响。
%
% 为什么要 try/catch 逐个包：run_q4_all 的第 9 步曾因一个字段名错误直接中断，
% 连带把后面的配图整步吞掉（无 try/catch）。这四个脚本各自要跑几百天的 LP，
% 任何一个中途抛错都不应该让其余三个白等。
%
% 落盘：全部落在 问题四/out/ 下（qc.outdir），不碰问题一/二/三的交付目录。

HERE = fileparts(mfilename('fullpath'));
addpath(HERE);  addpath(fileparts(HERE));
cd(fileparts(HERE));

jobs = {'t_q4_nearzero', 't_q4_term_policy', 't_q4_adjust_value', 'q4_cvar'};
t0 = tic;
for i = 1:numel(jobs)
    f = jobs{i};
    fprintf('\n######## [%d/%d] %s ########\n', i, numel(jobs), f);
    ta = tic;
    try
        feval(f);
        fprintf('######## %s 完成，用时 %.1f s ########\n', f, toc(ta));
    catch ME
        fprintf('######## %s 失败（%.1f s）：%s ########\n', f, toc(ta), ME.message);
        for k = 1:numel(ME.stack)
            fprintf('    at %s:%d\n', ME.stack(k).name, ME.stack(k).line);
        end
    end
end
fprintf('\n==== 四个实验跑完，总用时 %.1f s ====\n', toc(t0));
end
