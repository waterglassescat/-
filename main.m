filename = 'mk01-A.txt'; % 数据文件名    
% 读取数据
[job_data, machine_data, fixture_data, fixture_times, num_jobs, num_machines, num_fixture_types, total_operations] = read_production_data(filename);

% 将 job_data 转换为 job_operation_num = [工序数，工序数，...]
job_operation_num = zeros(length(job_data), 1);
for i = 1:length(job_data)
    job_operation_num(i) = job_data{i}.num_operations;  
end

%% ========== 公共参数 ==========
pop_size = 150;
max_gen  = 200;

%% ========== 1. GA-VNS ==========
fprintf('\n========== GA-VNS ==========\n');
ga_vns_params = struct();
ga_vns_params.pop_size              = pop_size;
ga_vns_params.max_gen               = max_gen;
ga_vns_params.crossover_prob        = 0.8;
ga_vns_params.mutation_prob         = 0.1;
ga_vns_params.elite_ratio           = 0.1;
ga_vns_params.vns_ratio             = 0.05;
ga_vns_params.vns_interval          = 5;
ga_vns_params.adaptive              = true;
ga_vns_params.enabled_neighborhoods = true(1,5);
ga_vns_params.verbose               = true;

[best_individual, best_makespan, history_gavns] = ga_vns_main(...
    num_machines, machine_data, fixture_data, job_operation_num, num_fixture_types, ga_vns_params);

%% ========== 2. 标准GA ==========
fprintf('\n========== 标准GA ==========\n');
ga_params = struct();
ga_params.pop_size       = pop_size;
ga_params.max_gen        = max_gen;
ga_params.crossover_prob = 0.8;
ga_params.mutation_prob  = 0.1;
ga_params.elite_ratio    = 0.1;
ga_params.verbose        = true;

[~, ~, history_ga] = ga_standard(...
    num_machines, machine_data, fixture_data, job_operation_num, num_fixture_types, ga_params);

%% ========== 3. 模拟退火（SA）==========
fprintf('\n========== SA ==========\n');
sa_params = struct();
sa_params.max_gen    = max_gen;
sa_params.inner_iter = 20;
sa_params.T0         = 500;
sa_params.T_min      = 1;
sa_params.alpha      = 0.95;
sa_params.pop_size   = pop_size;
sa_params.verbose    = true;

[~, ~, history_sa] = sa_solver(...
    num_machines, machine_data, fixture_data, job_operation_num, num_fixture_types, sa_params);

%% ========== 4. 离散PSO ==========
fprintf('\n========== PSO ==========\n');
pso_params = struct();
pso_params.pop_size = pop_size;
pso_params.max_gen  = max_gen;
pso_params.w        = 0.5;
pso_params.c1       = 0.3;
pso_params.c2       = 0.2;
pso_params.verbose  = true;

[~, ~, history_pso] = pso_solver(...
    num_machines, machine_data, fixture_data, job_operation_num, num_fixture_types, pso_params);

%% ========== 5. 禁忌搜索（TS）==========
fprintf('\n========== TS ==========\n');
ts_params = struct();
ts_params.max_gen      = max_gen;
ts_params.tabu_tenure  = 15;
ts_params.neighborhood = 20;
ts_params.pop_size     = pop_size;
ts_params.verbose      = true;

[~, ~, history_ts] = ts_solver(...
    num_machines, machine_data, fixture_data, job_operation_num, num_fixture_types, ts_params);

%% ========== 解码最优个体（GA-VNS），获取详细调度方案 + RGV日志 ==========
[best_schedule_info, final_makespan, rgv_log] = decode_makespan2(...
    best_individual, num_machines, machine_data, fixture_data, job_operation_num, num_fixture_types);

rgv_summary = analyze_rgv(rgv_log, final_makespan);

fprintf('\n最终最优 Makespan (GA-VNS): %.2f\n', final_makespan);

%% ========== 可视化 ==========

% 1. 多算法迭代收敛曲线
figure('Name', '多算法迭代收敛曲线', 'NumberTitle', 'off', ...
       'Position', [100, 100, 900, 550]);
hold on;

gen_axis = 1:max_gen;
plot(gen_axis, history_gavns, '-o',  'Color', [0    0.45  0.74], 'LineWidth', 2.0, 'MarkerIndices', 1:round(max_gen/10):max_gen, 'MarkerSize', 7, 'MarkerFaceColor', [0    0.45  0.74]);
plot(gen_axis, history_ga,    '--s', 'Color', [0.85 0.33  0.10], 'LineWidth', 1.8, 'MarkerIndices', 1:round(max_gen/10):max_gen, 'MarkerSize', 7, 'MarkerFaceColor', [0.85 0.33  0.10]);
plot(gen_axis, history_sa,    '-.d', 'Color', [0.93 0.69  0.13], 'LineWidth', 1.8, 'MarkerIndices', 1:round(max_gen/10):max_gen, 'MarkerSize', 7, 'MarkerFaceColor', [0.93 0.69  0.13]);
plot(gen_axis, history_pso,   ':^',  'Color', [0.49 0.18  0.56], 'LineWidth', 1.8, 'MarkerIndices', 1:round(max_gen/10):max_gen, 'MarkerSize', 7, 'MarkerFaceColor', [0.49 0.18  0.56]);
plot(gen_axis, history_ts,    '-v',  'Color', [0.47 0.67  0.19], 'LineWidth', 1.8, 'MarkerIndices', 1:round(max_gen/10):max_gen, 'MarkerSize', 7, 'MarkerFaceColor', [0.47 0.67  0.19]);

xlabel('迭代次数', 'FontSize', 12);
ylabel('最优 Makespan', 'FontSize', 12);
title('多算法迭代收敛曲线对比', 'FontSize', 14);
legend({sprintf('GA-VNS (%.1f)', history_gavns(end)), ...
        sprintf('GA (%.1f)',     history_ga(end)), ...
        sprintf('SA (%.1f)',     history_sa(end)), ...
        sprintf('PSO (%.1f)',    history_pso(end)), ...
        sprintf('TS (%.1f)',     history_ts(end))}, ...
    'Location', 'northeast', 'FontSize', 10);
grid on;
hold off;

% 2. 最终makespan柱状图
figure('Name', '最终Makespan对比', 'NumberTitle', 'off', ...
       'Position', [150, 150, 600, 400]);
final_values = [history_gavns(end), history_ga(end), history_sa(end), ...
                history_pso(end), history_ts(end)];
alg_labels = {'GA-VNS', 'GA', 'SA', 'PSO', 'TS'};
colors = [0    0.45  0.74;
          0.85 0.33  0.10;
          0.93 0.69  0.13;
          0.49 0.18  0.56;
          0.47 0.67  0.19];
b = bar(final_values, 'FaceColor', 'flat');
for k = 1:5
    b.CData(k,:) = colors(k,:);
end
set(gca, 'XTickLabel', alg_labels, 'FontSize', 10);
ylabel('最终 Makespan', 'FontSize', 12);
title('各算法最终 Makespan 对比', 'FontSize', 14);
grid on;
% 标注数值
for k = 1:5
    text(k, final_values(k) + max(final_values)*0.01, ...
        sprintf('%.1f', final_values(k)), ...
        'HorizontalAlignment', 'center', 'FontSize', 10, 'FontWeight', 'bold');
end

%% ========== 绘制甘特图（GA-VNS最优解） ==========
plot_gantt_with_rgv(best_schedule_info, rgv_log, final_makespan, num_machines, job_operation_num);

%% ========== 不同算例不同算法对比图 =========
%   需要单独运行一行
%   res = run_batch_benchmark();                                 % 默认配置
%   res = run_batch_benchmark('instances', {'mk01-A','mk01-B'}); % 指定算例
%   res = run_batch_benchmark('num_runs', 5, 'max_gen', 100);

%% ========== 消融实验 =========
%   需要单独运行一行
%   res = run_neighborhood_ablation();                       % 默认配置
%   res = run_neighborhood_ablation('filename','mk01-A.txt');
%   res = run_neighborhood_ablation('filename','mk01-A.txt','num_runs',10,'max_gen',100);