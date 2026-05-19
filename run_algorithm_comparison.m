function compare_results = run_algorithm_comparison(varargin)
% 多算法对比实验
%
% 用法：
%   res = run_algorithm_comparison();
%   res = run_algorithm_comparison('filename','mk01-A.txt','num_runs',10);
%
% 可选参数：
%   'filename'  - 数据文件名（默认 'mk01-A.txt'）
%   'num_runs'  - 每个算法独立重复次数（默认 5）
%   'pop_size'  - 种群/粒子数（默认 50）
%   'max_gen'   - 最大代数（默认 100）
%   'seed_base' - 随机种子基数（默认 2024）
%   'save_csv'  - 是否保存csv（默认 true）
%
% 对比算法：
%   1. GA-VNS  （混合遗传-变邻域，本文算法）
%   2. GA      （标准遗传算法，无VNS无自适应）
%   3. SA      （模拟退火）
%   4. PSO     （离散粒子群）
%   5. TS      （禁忌搜索）

%% 解析参数
p = inputParser;
addParameter(p, 'filename', 'mk01-A.txt', @ischar);
addParameter(p, 'num_runs', 5, @isnumeric);
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

%% 定义算法
alg_names = {'GA-VNS', 'GA', 'SA', 'PSO', 'TS'};
num_algs  = numel(alg_names);
num_runs  = opts.num_runs;
max_gen   = opts.max_gen;
pop_size  = opts.pop_size;

% 结果容器
results_makespan = zeros(num_algs, num_runs);
results_time     = zeros(num_algs, num_runs);
results_history  = cell(num_algs, num_runs);

%% 颜色和线型
colors = [0    0.45  0.74;    % GA-VNS 蓝
          0.85 0.33  0.10;    % GA     橙
          0.93 0.69  0.13;    % SA     黄
          0.49 0.18  0.56;    % PSO    紫
          0.47 0.67  0.19];   % TS     绿
line_styles = {'-', '--', '-.', ':', '-'};
markers = {'none', 'none', 'none', 'none', 'none'};

fprintf('=============================================================\n');
fprintf('多算法对比实验  数据=%s  pop=%d  gen=%d  runs=%d\n', ...
    opts.filename, pop_size, max_gen, num_runs);
fprintf('=============================================================\n');

%% 逐算法运行
for a = 1:num_algs
    alg_name = alg_names{a};
    fprintf('\n[%d/%d] %s\n', a, num_algs, alg_name);

    for r = 1:num_runs
        rng(opts.seed_base + r);  % 固定种子

        t0 = tic;
        switch alg_name
            case 'GA-VNS'
                params = struct();
                params.pop_size       = pop_size;
                params.max_gen        = max_gen;
                params.crossover_prob = 0.8;
                params.mutation_prob  = 0.1;
                params.elite_ratio    = 0.1;
                params.vns_ratio      = 0.05;
                params.vns_interval   = 5;
                params.adaptive       = true;
                params.enabled_neighborhoods = true(1,5);
                params.verbose        = false;
                [~, ms, hist] = ga_vns_main(num_machines, machine_data, ...
                    fixture_data, job_operation_num, num_fixture_types, params);

            case 'GA'
                params = struct();
                params.pop_size       = pop_size;
                params.max_gen        = max_gen;
                params.crossover_prob = 0.8;
                params.mutation_prob  = 0.1;
                params.elite_ratio    = 0.1;
                params.verbose        = false;
                [~, ms, hist] = ga_standard(num_machines, machine_data, ...
                    fixture_data, job_operation_num, num_fixture_types, params);

            case 'SA'
                params = struct();
                params.max_gen     = max_gen;
                params.inner_iter  = 20;
                params.T0          = 500;
                params.T_min       = 1;
                params.alpha       = 0.95;
                params.pop_size    = pop_size;
                params.verbose     = false;
                [~, ms, hist] = sa_solver(num_machines, machine_data, ...
                    fixture_data, job_operation_num, num_fixture_types, params);

            case 'PSO'
                params = struct();
                params.pop_size = pop_size;
                params.max_gen  = max_gen;
                params.w        = 0.5;
                params.c1       = 0.3;
                params.c2       = 0.2;
                params.verbose  = false;
                [~, ms, hist] = pso_solver(num_machines, machine_data, ...
                    fixture_data, job_operation_num, num_fixture_types, params);

            case 'TS'
                params = struct();
                params.max_gen      = max_gen;
                params.tabu_tenure  = 15;
                params.neighborhood = 20;
                params.pop_size     = pop_size;
                params.verbose      = false;
                [~, ms, hist] = ts_solver(num_machines, machine_data, ...
                    fixture_data, job_operation_num, num_fixture_types, params);
        end
        elapsed = toc(t0);

        results_makespan(a, r) = ms;
        results_time(a, r)     = elapsed;
        results_history{a, r}  = hist;

        fprintf('  run %2d/%d : makespan=%8.2f  time=%6.1fs\n', r, num_runs, ms, elapsed);
    end
end

%% 统计汇总
fprintf('\n=============================================================\n');
fprintf('多算法对比汇总\n');
fprintf('=============================================================\n');
fprintf('%-8s | %10s %10s %10s %10s | %10s\n', ...
    '算法', 'best', 'mean', 'std', 'worst', 'avg_time(s)');
fprintf('---------+-------------------------------------------+-----------\n');

compare_results = struct();
for a = 1:num_algs
    ms = results_makespan(a, :);
    tm = results_time(a, :);
    compare_results(a).name     = alg_names{a};
    compare_results(a).best     = min(ms);
    compare_results(a).mean     = mean(ms);
    compare_results(a).std      = std(ms);
    compare_results(a).worst    = max(ms);
    compare_results(a).avg_time = mean(tm);
    compare_results(a).all_runs = ms;
    compare_results(a).histories = results_history(a, :);

    fprintf('%-8s | %10.2f %10.2f %10.2f %10.2f | %10.1f\n', ...
        alg_names{a}, compare_results(a).best, compare_results(a).mean, ...
        compare_results(a).std, compare_results(a).worst, compare_results(a).avg_time);
end

%% 保存 CSV
if opts.save_csv
    csv_name = sprintf('comparison_%s_%s.csv', opts.filename, datestr(now,'yyyymmdd_HHMMSS'));
    fid = fopen(csv_name, 'w');
    fprintf(fid, 'algorithm,best,mean,std,worst,avg_time');
    for r = 1:num_runs
        fprintf(fid, ',run%d', r);
    end
    fprintf(fid, '\n');
    for a = 1:num_algs
        fprintf(fid, '%s,%.4f,%.4f,%.4f,%.4f,%.4f', ...
            compare_results(a).name, compare_results(a).best, ...
            compare_results(a).mean, compare_results(a).std, ...
            compare_results(a).worst, compare_results(a).avg_time);
        for r = 1:num_runs
            fprintf(fid, ',%.4f', results_makespan(a, r));
        end
        fprintf(fid, '\n');
    end
    fclose(fid);
    fprintf('\n结果已保存至 %s\n', csv_name);
end

%% 可视化1：收敛曲线（所有算法均值）
figure('Name', '多算法收敛曲线对比', 'NumberTitle', 'off', ...
       'Position', [100, 100, 800, 500]);
hold on;
legend_str = cell(num_algs, 1);
for a = 1:num_algs
    H = cell2mat(results_history(a,:)');
    mean_curve = mean(H, 1);
    plot(1:max_gen, mean_curve, ...
        'Color', colors(a,:), 'LineWidth', 2, ...
        'LineStyle', line_styles{a}, 'Marker', markers{a});
    legend_str{a} = sprintf('%s (best=%.1f)', alg_names{a}, compare_results(a).best);
end
xlabel('迭代代数', 'FontSize', 12);
ylabel('最优 Makespan', 'FontSize', 12);
title(sprintf('算法对比收敛曲线 (%s, %d runs 均值)', opts.filename, num_runs), 'FontSize', 14);
legend(legend_str, 'Location', 'northeast', 'FontSize', 10);
grid on;
hold off;

%% 可视化2：箱线图
try
    figure('Name', '多算法Makespan分布', 'NumberTitle', 'off', ...
           'Position', [150, 150, 600, 450]);
    boxplot(results_makespan', alg_names);
    ylabel('Makespan', 'FontSize', 12);
    title(sprintf('算法对比 Makespan 分布 (%s, %d runs)', opts.filename, num_runs), 'FontSize', 14);
    grid on;
catch
    % 没有 Statistics Toolbox 时跳过箱线图
    fprintf('(箱线图需要 Statistics Toolbox，已跳过)\n');
end

%% 可视化3：运行时间柱状图
figure('Name', '算法运行时间对比', 'NumberTitle', 'off', ...
       'Position', [200, 200, 600, 400]);
avg_times = [compare_results.avg_time];
b = bar(avg_times, 'FaceColor', 'flat');
for a = 1:num_algs
    b.CData(a,:) = colors(a,:);
end
set(gca, 'XTickLabel', alg_names, 'FontSize', 10);
ylabel('平均运行时间 (s)', 'FontSize', 12);
title('算法平均运行时间对比', 'FontSize', 14);
grid on;
% 在柱顶标注数值
for a = 1:num_algs
    text(a, avg_times(a) + max(avg_times)*0.02, ...
        sprintf('%.1fs', avg_times(a)), ...
        'HorizontalAlignment', 'center', 'FontSize', 9);
end

end
