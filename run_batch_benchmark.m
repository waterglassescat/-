function batch_results = run_batch_benchmark(varargin)
% 批量算例对比实验
% 在多个算例上对比 GA-VNS 与传统算法（GA / SA / PSO / TS），
% 验证 GA-VNS 是否在所有算例上表现优越。
%
% 用法：
%   res = run_batch_benchmark();                                 % 默认配置
%   res = run_batch_benchmark('instances', {'mk01-A','mk01-B'}); % 指定算例
%   res = run_batch_benchmark('num_runs', 10, 'max_gen', 150);
%
% 可选参数：
%   'instances'        - 算例名 cell 数组（不带 .txt 后缀）
%                        默认会自动扫描当前目录所有 mk*-?.txt / mfjs*-?.txt
%   'instance_dir'     - 算例文件所在目录（默认当前目录 './'）
%   'algorithms'       - 要运行的算法列表（默认 {'GA-VNS','GA','SA','PSO','TS'}）
%   'num_runs'         - 每个算法在每个算例上的独立重复次数（默认 5）
%   'pop_size'         - 种群/粒子数（默认 50）
%   'max_gen'          - 最大代数（默认 100）
%   'seed_base'        - 随机种子基数（默认 2024）
%   'rgv_speed_factor' - RGV 速度倍率，5 表示 RGV_speed = avg_pt * 5（默认 5）
%   'output_dir'       - 结果输出目录（默认 './benchmark_results'）
%   'save_mat'         - 是否保存 .mat 完整结果（默认 true）
%
% 输出：
%   batch_results - 结构体数组，每行对应一个 (instance, algorithm) 组合，包含：
%       .instance, .algorithm, .best, .mean, .std, .worst, .avg_time,
%       .all_runs, .histories
%
% 文件输出（保存到 output_dir）：
%   summary_<timestamp>.csv          - 汇总表（每行一个 instance×algorithm）
%   wide_<timestamp>.csv             - 宽表（行=算例，列=算法，值=mean）
%   raw_<timestamp>.mat              - 完整原始数据（含所有 history）
%   convergence_<instance>.png       - 每个算例的收敛曲线对比图
%   makespan_distribution.png        - 全算例 makespan 箱线图

%% 解析参数
p = inputParser;
addParameter(p, 'instances', {}, @iscell);
addParameter(p, 'instance_dir', './', @ischar);
addParameter(p, 'algorithms', {'GA-VNS','GA','SA','PSO','TS'}, @iscell);
addParameter(p, 'num_runs', 5, @isnumeric);
addParameter(p, 'pop_size', 50, @isnumeric);
addParameter(p, 'max_gen', 100, @isnumeric);
addParameter(p, 'seed_base', 2024, @isnumeric);
addParameter(p, 'rgv_speed_factor', 5, @isnumeric);
addParameter(p, 'output_dir', './benchmark_results', @ischar);
addParameter(p, 'save_mat', true, @islogical);
parse(p, varargin{:});
opts = p.Results;

%% 自动扫描算例
if isempty(opts.instances)
    files = [dir(fullfile(opts.instance_dir, 'mk*-*.txt')); ...
             dir(fullfile(opts.instance_dir, 'mfjs*-*.txt'))];
    opts.instances = cell(length(files), 1);
    for i = 1:length(files)
        [~, name, ~] = fileparts(files(i).name);
        opts.instances{i} = name;
    end
    if isempty(opts.instances)
        error('未在目录 %s 找到任何算例文件', opts.instance_dir);
    end
end

%% 设置 RGV 速度倍率（全局生效）
get_rgv_speed_factor(opts.rgv_speed_factor);

%% 准备输出目录
if ~exist(opts.output_dir, 'dir'), mkdir(opts.output_dir); end
timestamp = datestr(now, 'yyyymmdd_HHMMSS');

num_inst = numel(opts.instances);
num_alg  = numel(opts.algorithms);
num_runs = opts.num_runs;
max_gen  = opts.max_gen;

fprintf('=================================================================\n');
fprintf('批量基准测试\n');
fprintf('  算例数: %d  算法数: %d  每组重复: %d  代数: %d  种群: %d\n', ...
    num_inst, num_alg, num_runs, max_gen, opts.pop_size);
fprintf('  RGV速度倍率: %.3f （RGV_speed = 平均加工时间 × 倍率）\n', opts.rgv_speed_factor);
fprintf('  输出目录: %s\n', opts.output_dir);
fprintf('=================================================================\n');

% 颜色配置（与main.m一致）
colors = [0    0.45  0.74;
          0.85 0.33  0.10;
          0.93 0.69  0.13;
          0.49 0.18  0.56;
          0.47 0.67  0.19;
          0.30 0.75  0.93;
          0.64 0.08  0.18];
line_styles = {'-', '--', '-.', ':', '-', '--', '-.'};

batch_results = struct([]);
result_idx = 0;

% 用于宽表汇总
wide_mean = zeros(num_inst, num_alg);
wide_best = zeros(num_inst, num_alg);

%% 主循环：算例 × 算法 × 重复
for i = 1:num_inst
    inst_name = opts.instances{i};
    inst_path = fullfile(opts.instance_dir, [inst_name, '.txt']);
    
    fprintf('\n┌─────────────────────────────────────────────────────────────┐\n');
    fprintf('│ 算例 %d/%d: %s\n', i, num_inst, inst_name);
    fprintf('└─────────────────────────────────────────────────────────────┘\n');
    
    if ~exist(inst_path, 'file')
        fprintf('  [跳过] 文件不存在: %s\n', inst_path);
        continue;
    end
    
    % 读取算例
    [job_data, machine_data, fixture_data, ~, ~, num_machines, num_fixture_types, ~] = ...
        read_production_data(inst_path);
    job_operation_num = zeros(length(job_data), 1);
    for k = 1:length(job_data)
        job_operation_num(k) = job_data{k}.num_operations;
    end
    
    % 显示算例信息
    avg_pt = compute_avg_pt(machine_data);
    fprintf('  工件数=%d, 机器数=%d, 总工序=%d, 平均加工时间=%.2f, RGV速度=%.2f\n', ...
        length(job_data), num_machines, sum(job_operation_num), ...
        avg_pt, avg_pt * opts.rgv_speed_factor);
    
    % 收集本算例所有算法的 history（用于绘收敛图）
    inst_histories = cell(num_alg, 1);
    
    for a = 1:num_alg
        alg = opts.algorithms{a};
        fprintf('\n  [%s]\n', alg);
        
        ms_arr   = zeros(num_runs, 1);
        time_arr = zeros(num_runs, 1);
        hist_mat = zeros(num_runs, max_gen);
        
        for r = 1:num_runs
            rng(opts.seed_base + r);
            
            t0 = tic;
            try
                [~, ms, hist] = run_single_algorithm(alg, ...
                    num_machines, machine_data, fixture_data, job_operation_num, ...
                    num_fixture_types, opts.pop_size, max_gen);
            catch ME
                fprintf('    run %d: 出错: %s\n', r, ME.message);
                ms = NaN; hist = NaN(max_gen, 1);
            end
            elapsed = toc(t0);
            
            ms_arr(r)     = ms;
            time_arr(r)   = elapsed;
            hist_mat(r,:) = hist(:)';
            
            fprintf('    run %d/%d: makespan=%.2f, time=%.1fs\n', ...
                r, num_runs, ms, elapsed);
        end
        
        % 保存到结果
        result_idx = result_idx + 1;
        batch_results(result_idx).instance  = inst_name;
        batch_results(result_idx).algorithm = alg;
        batch_results(result_idx).best      = min(ms_arr);
        batch_results(result_idx).mean      = mean(ms_arr);
        batch_results(result_idx).std       = std(ms_arr);
        batch_results(result_idx).worst     = max(ms_arr);
        batch_results(result_idx).avg_time  = mean(time_arr);
        batch_results(result_idx).all_runs  = ms_arr;
        batch_results(result_idx).histories = hist_mat;
        
        wide_mean(i, a) = mean(ms_arr);
        wide_best(i, a) = min(ms_arr);
        inst_histories{a} = hist_mat;
        
        fprintf('    [%s 汇总] best=%.2f, mean=%.2f, std=%.2f, avg_time=%.1fs\n', ...
            alg, min(ms_arr), mean(ms_arr), std(ms_arr), mean(time_arr));
    end
    
    %% 为本算例绘制收敛曲线对比
    fig = figure('Visible', 'off', 'Position', [100, 100, 900, 550]);
    hold on;
    legend_str = cell(num_alg, 1);
    for a = 1:num_alg
        if isempty(inst_histories{a}), continue; end
        mean_curve = mean(inst_histories{a}, 1);
        c_idx = mod(a-1, size(colors,1)) + 1;
        ls_idx = mod(a-1, numel(line_styles)) + 1;
        plot(1:max_gen, mean_curve, ...
            'Color', colors(c_idx,:), 'LineWidth', 2, ...
            'LineStyle', line_styles{ls_idx});
        legend_str{a} = sprintf('%s (best=%.1f, mean=%.1f)', ...
            opts.algorithms{a}, wide_best(i,a), wide_mean(i,a));
    end
    xlabel('迭代代数', 'FontSize', 12);
    ylabel('最优 Makespan', 'FontSize', 12);
    title(sprintf('算例 %s 多算法收敛曲线 (%d runs 均值)', inst_name, num_runs), ...
        'FontSize', 14, 'Interpreter', 'none');
    legend(legend_str, 'Location', 'northeast', 'FontSize', 9);
    grid on;
    fig_path = fullfile(opts.output_dir, sprintf('convergence_%s_%s.png', inst_name, timestamp));
    saveas(fig, fig_path);
    close(fig);
    fprintf('  收敛曲线已保存: %s\n', fig_path);
end

%% ========== 写出 summary CSV（长表）==========
csv_path = fullfile(opts.output_dir, sprintf('summary_%s.csv', timestamp));
fid = fopen(csv_path, 'w');
fprintf(fid, 'instance,algorithm,best,mean,std,worst,avg_time');
for r = 1:num_runs, fprintf(fid, ',run%d', r); end
fprintf(fid, '\n');
for k = 1:length(batch_results)
    br = batch_results(k);
    fprintf(fid, '%s,%s,%.4f,%.4f,%.4f,%.4f,%.4f', ...
        br.instance, br.algorithm, br.best, br.mean, br.std, br.worst, br.avg_time);
    for r = 1:num_runs
        fprintf(fid, ',%.4f', br.all_runs(r));
    end
    fprintf(fid, '\n');
end
fclose(fid);
fprintf('\n汇总表已保存: %s\n', csv_path);

%% ========== 写出 wide CSV（宽表，便于直接画图/写论文）==========
wide_path = fullfile(opts.output_dir, sprintf('wide_%s.csv', timestamp));
fid = fopen(wide_path, 'w');
% Mean 表
fprintf(fid, '## Mean Makespan\n');
fprintf(fid, 'instance');
for a = 1:num_alg, fprintf(fid, ',%s', opts.algorithms{a}); end
fprintf(fid, '\n');
for i = 1:num_inst
    fprintf(fid, '%s', opts.instances{i});
    for a = 1:num_alg, fprintf(fid, ',%.4f', wide_mean(i,a)); end
    fprintf(fid, '\n');
end
% Best 表
fprintf(fid, '\n## Best Makespan\n');
fprintf(fid, 'instance');
for a = 1:num_alg, fprintf(fid, ',%s', opts.algorithms{a}); end
fprintf(fid, '\n');
for i = 1:num_inst
    fprintf(fid, '%s', opts.instances{i});
    for a = 1:num_alg, fprintf(fid, ',%.4f', wide_best(i,a)); end
    fprintf(fid, '\n');
end
fclose(fid);
fprintf('宽表已保存: %s\n', wide_path);

%% ========== 写出 .mat 完整结果 ==========
if opts.save_mat
    mat_path = fullfile(opts.output_dir, sprintf('raw_%s.mat', timestamp));
    save(mat_path, 'batch_results', 'opts', 'wide_mean', 'wide_best');
    fprintf('完整结果已保存: %s\n', mat_path);
end

%% ========== 打印最终汇总 ==========
fprintf('\n=================================================================\n');
fprintf('最终汇总（mean makespan）\n');
fprintf('=================================================================\n');
fprintf('%-12s', '算例');
for a = 1:num_alg, fprintf('%12s', opts.algorithms{a}); end
fprintf('   |  %s\n', '最优算法');
fprintf('%s\n', repmat('-', 1, 12 + 12*num_alg + 18));
ga_vns_idx = find(strcmp(opts.algorithms, 'GA-VNS'), 1);
ga_vns_wins = 0;
for i = 1:num_inst
    fprintf('%-12s', opts.instances{i});
    for a = 1:num_alg, fprintf('%12.2f', wide_mean(i,a)); end
    [~, best_a] = min(wide_mean(i,:));
    fprintf('   |  %s\n', opts.algorithms{best_a});
    if best_a == ga_vns_idx, ga_vns_wins = ga_vns_wins + 1; end
end
fprintf('\nGA-VNS 在 %d/%d 个算例上取得最优 mean makespan\n', ga_vns_wins, num_inst);

end

%% ============================================================
function [bi, bm, hist] = run_single_algorithm(alg, num_machines, machine_data, ...
    fixture_data, job_operation_num, num_fixture_types, pop_size, max_gen)
% 单算法执行入口
switch alg
    case 'GA-VNS'
        ps = struct('pop_size', pop_size, 'max_gen', max_gen, ...
                    'crossover_prob', 0.8, 'mutation_prob', 0.1, ...
                    'elite_ratio', 0.1, 'vns_ratio', 0.05, ...
                    'vns_interval', 5, 'adaptive', true, ...
                    'enabled_neighborhoods', true(1,5), 'verbose', false);
        [bi, bm, hist] = ga_vns_main(num_machines, machine_data, ...
            fixture_data, job_operation_num, num_fixture_types, ps);
    case 'GA'
        ps = struct('pop_size', pop_size, 'max_gen', max_gen, ...
                    'crossover_prob', 0.8, 'mutation_prob', 0.1, ...
                    'elite_ratio', 0.1, 'verbose', false);
        [bi, bm, hist] = ga_standard(num_machines, machine_data, ...
            fixture_data, job_operation_num, num_fixture_types, ps);
    case 'SA'
        ps = struct('max_gen', max_gen, 'inner_iter', 20, ...
                    'T0', 500, 'T_min', 1, 'alpha', 0.95, ...
                    'pop_size', pop_size, 'verbose', false);
        [bi, bm, hist] = sa_solver(num_machines, machine_data, ...
            fixture_data, job_operation_num, num_fixture_types, ps);
    case 'PSO'
        ps = struct('pop_size', pop_size, 'max_gen', max_gen, ...
                    'w', 0.5, 'c1', 0.3, 'c2', 0.2, 'verbose', false);
        [bi, bm, hist] = pso_solver(num_machines, machine_data, ...
            fixture_data, job_operation_num, num_fixture_types, ps);
    case 'TS'
        ps = struct('max_gen', max_gen, 'tabu_tenure', 15, ...
                    'neighborhood', 20, 'pop_size', pop_size, 'verbose', false);
        [bi, bm, hist] = ts_solver(num_machines, machine_data, ...
            fixture_data, job_operation_num, num_fixture_types, ps);
    otherwise
        error('未知算法: %s', alg);
end
end

%% ============================================================
function avg_pt = compute_avg_pt(machine_data)
all_t = [];
for j = 1:length(machine_data)
    for o = 1:length(machine_data{j})
        all_t = [all_t; machine_data{j}{o}(:, end)]; %#ok<AGROW>
    end
end
avg_pt = mean(all_t);
end
