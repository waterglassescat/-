function ablation_results = run_neighborhood_ablation(varargin)
% 邻域结构消融实验
%
% 用法：
%   res = run_neighborhood_ablation();                       % 默认配置
%   res = run_neighborhood_ablation('filename','mk01-A.txt');
%   res = run_neighborhood_ablation('num_runs',10,'max_gen',100);
%
% 可选参数（key-value）:
%   'filename'  - 数据文件名（默认 'mk01-A.txt'）
%   'num_runs'  - 每个配置独立重复次数（默认 5）
%   'pop_size'  - 种群规模（默认 50）
%   'max_gen'   - 最大代数（默认 100）
%   'seed_base' - 随机种子基数（默认 2024，第k次运行用 seed_base+k）
%   'save_csv'  - 是否保存csv（默认 true）
%
% 输出：
%   ablation_results - 结构体数组，每个元素对应一个配置的统计结果
%
% 实验设计：
%   配置 0: ALL                  - 全部5个邻域启用（基线）
%   配置 1: NO_N1                - 关闭邻域1（工序-交换）
%   配置 2: NO_N2                - 关闭邻域2（工序-插入）
%   配置 3: NO_N3                - 关闭邻域3（工序-逆序）
%   配置 4: NO_N4                - 关闭邻域4（机器选择）
%   配置 5: NO_N5                - 关闭邻域5（混合扰动）
%   配置 6: NO_VNS               - 全部关闭（无VNS对照组）
%
% Leave-one-out 设计：每个配置去掉一个邻域，比较与全开基线的差异，
% 即可定量评估每个邻域对算法性能的贡献。

%% 解析参数
p = inputParser;
addParameter(p, 'filename', 'mk01-A.txt', @ischar);
addParameter(p, 'num_runs', 10, @isnumeric);
addParameter(p, 'pop_size', 50, @isnumeric);
addParameter(p, 'max_gen',  100, @isnumeric);
addParameter(p, 'seed_base', 2024, @isnumeric);
addParameter(p, 'save_csv', true, @islogical);
parse(p, varargin{:});
opts = p.Results;

%% 读取数据
[job_data, machine_data, fixture_data, ~, ~, num_machines, num_fixture_types, ~] = ...
    read_production_data(opts.filename);
job_operation_num = zeros(length(job_data), 1);
for i = 1:length(job_data)
    job_operation_num(i) = job_data{i}.num_operations;
end

%% 定义实验配置
configs = struct( ...
    'name', {'ALL','NO_N1','NO_N2','NO_N3','NO_N4','NO_N5','NO_VNS'}, ...
    'mask', {[1 1 1 1 1], ...
             [0 1 1 1 1], ...
             [1 0 1 1 1], ...
             [1 1 0 1 1], ...
             [1 1 1 0 1], ...
             [1 1 1 1 0], ...
             [0 0 0 0 0]});

num_configs = numel(configs);
num_runs    = opts.num_runs;

% 结果容器
results_makespan = zeros(num_configs, num_runs);
results_time     = zeros(num_configs, num_runs);
results_history  = cell(num_configs, num_runs);

%% 主循环
fprintf('=========================================================\n');
fprintf('邻域消融实验  数据=%s  pop=%d  gen=%d  runs=%d\n', ...
    opts.filename, opts.pop_size, opts.max_gen, num_runs);
fprintf('=========================================================\n');

for c = 1:num_configs
    cfg = configs(c);
    fprintf('\n[配置 %d/%d] %s   邻域掩码=[%s]\n', ...
        c, num_configs, cfg.name, num2str(cfg.mask));

    for r = 1:num_runs
        % 固定种子，使各配置在相同初始种群下比较
        rng(opts.seed_base + r);

        ga_params = struct();
        ga_params.pop_size              = opts.pop_size;
        ga_params.max_gen               = opts.max_gen;
        ga_params.crossover_prob        = 0.8;
        ga_params.mutation_prob         = 0.1;
        ga_params.elite_ratio           = 0.1;
        ga_params.vns_ratio             = 0.05;
        ga_params.vns_interval          = 5;
        ga_params.adaptive              = true;
        ga_params.enabled_neighborhoods = logical(cfg.mask);
        ga_params.verbose               = false;

        t0 = tic;
        [~, best_makespan, history] = ga_vns_main( ...
            num_machines, machine_data, fixture_data, job_operation_num, num_fixture_types, ga_params);
        elapsed = toc(t0);

        results_makespan(c, r) = best_makespan;
        results_time(c, r)     = elapsed;
        results_history{c, r}  = history;

        fprintf('  run %2d/%d : makespan=%8.2f  time=%6.1fs\n', ...
            r, num_runs, best_makespan, elapsed);
    end
end

%% 统计汇总
fprintf('\n=========================================================\n');
fprintf('消融实验汇总\n');
fprintf('=========================================================\n');
fprintf('%-8s | %10s %10s %10s %10s | %10s\n', ...
    '配置', 'best', 'mean', 'std', 'worst', 'avg_time(s)');
fprintf('---------+-------------------------------------------+-----------\n');

ablation_results = struct();
for c = 1:num_configs
    ms = results_makespan(c, :);
    tm = results_time(c, :);
    ablation_results(c).name      = configs(c).name;
    ablation_results(c).mask      = configs(c).mask;
    ablation_results(c).best      = min(ms);
    ablation_results(c).mean      = mean(ms);
    ablation_results(c).std       = std(ms);
    ablation_results(c).worst     = max(ms);
    ablation_results(c).avg_time  = mean(tm);
    ablation_results(c).all_runs  = ms;
    ablation_results(c).histories = results_history(c, :);

    fprintf('%-8s | %10.2f %10.2f %10.2f %10.2f | %10.1f\n', ...
        configs(c).name, ablation_results(c).best, ablation_results(c).mean, ...
        ablation_results(c).std, ablation_results(c).worst, ablation_results(c).avg_time);
end

%% 相对基线（ALL）的退化幅度
baseline_mean = ablation_results(1).mean;
fprintf('\n相对基线 ALL 的均值退化幅度（正值表示更差）：\n');
for c = 2:num_configs
    delta = ablation_results(c).mean - baseline_mean;
    pct = 100 * delta / baseline_mean;
    fprintf('  %-8s : %+8.2f  (%+6.2f%%)\n', ablation_results(c).name, delta, pct);
end

%% 保存结果到 CSV
if opts.save_csv
    csv_name = sprintf('ablation_%s_%s.csv', opts.filename, datestr(now,'yyyymmdd_HHMMSS'));
    fid = fopen(csv_name, 'w');
    fprintf(fid, 'config,mask,best,mean,std,worst,avg_time');
    for r = 1:num_runs
        fprintf(fid, ',run%d', r);
    end
    fprintf(fid, '\n');
    for c = 1:num_configs
        fprintf(fid, '%s,"[%s]",%.4f,%.4f,%.4f,%.4f,%.4f', ...
            ablation_results(c).name, num2str(ablation_results(c).mask), ...
            ablation_results(c).best, ablation_results(c).mean, ...
            ablation_results(c).std, ablation_results(c).worst, ...
            ablation_results(c).avg_time);
        for r = 1:num_runs
            fprintf(fid, ',%.4f', results_makespan(c, r));
        end
        fprintf(fid, '\n');
    end
    fclose(fid);
    fprintf('\n结果已保存至 %s\n', csv_name);
end

%% 可视化：箱线图
try
    figure('Name', '邻域消融-Makespan分布', 'NumberTitle', 'off');
    boxplot(results_makespan', {configs.name});
    ylabel('Makespan');
    title(sprintf('邻域消融实验 (%s, %d runs)', opts.filename, num_runs));
    grid on;
catch
    % 如果没有 Statistics Toolbox，跳过
end

%% 可视化：各配置平均收敛曲线
figure('Name', '邻域消融-收敛曲线', 'NumberTitle', 'off');
hold on;
colors = lines(num_configs);
legend_str = cell(num_configs, 1);
for c = 1:num_configs
    H = cell2mat(results_history(c,:)');   % num_runs x max_gen
    mean_curve = mean(H, 1);
    plot(1:opts.max_gen, mean_curve, '-', 'Color', colors(c,:), 'LineWidth', 1.5);
    legend_str{c} = configs(c).name;
end
xlabel('迭代代数');
ylabel('平均最优 Makespan');
title('各配置平均收敛曲线');
legend(legend_str, 'Location', 'northeast');
grid on;
hold off;

end
