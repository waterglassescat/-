function [best_individual, best_makespan, history] = ts_solver(num_machines, machine_data, ...
    fixture_data, job_operation_num, num_fixture_types, ts_params)
% 禁忌搜索算法（Tabu Search）
%
% 编码方式与 GA-VNS 完全一致：[machine_code, fixture_code, line_side_code, schedule_code]
% 复用 init_population, decode_makespan
%
% ts_params 字段：
%   .max_gen       - 最大迭代数（默认200）
%   .tabu_tenure   - 禁忌长度（默认15）
%   .neighborhood  - 每代邻域采样数（默认20）
%   .pop_size      - 初始生成候选数（取最优作为初始解，默认50）
%   .verbose       - 是否打印进度（默认true）

%% 参数默认值
if nargin < 5 || isempty(ts_params), ts_params = struct(); end
if ~isfield(ts_params, 'max_gen'),      ts_params.max_gen = 200;      end
if ~isfield(ts_params, 'tabu_tenure'),  ts_params.tabu_tenure = 15;   end
if ~isfield(ts_params, 'neighborhood'), ts_params.neighborhood = 20;  end
if ~isfield(ts_params, 'pop_size'),     ts_params.pop_size = 50;      end
if ~isfield(ts_params, 'verbose'),      ts_params.verbose = true;     end

max_gen       = ts_params.max_gen;
tabu_tenure   = ts_params.tabu_tenure;
num_neighbors = ts_params.neighborhood;
total_ops     = sum(job_operation_num);

layout = create_layout_info(num_machines);
num_Line_side = layout.num_Line_side;

%% 1. 初始解
init_pop = init_population(num_Line_side, ts_params.pop_size, job_operation_num, machine_data, fixture_data);
init_fit = zeros(ts_params.pop_size, 1);
for i = 1:ts_params.pop_size
    [~, init_fit(i)] = decode_makespan(init_pop(i,:), num_machines, machine_data, ...
                                        fixture_data, job_operation_num, num_fixture_types);
end
[current_makespan, best_idx] = min(init_fit);
current = init_pop(best_idx, :);

best_individual = current;
best_makespan   = current_makespan;
history = zeros(max_gen, 1);

% 禁忌表：记录最近的移动（用哈希值近似）
tabu_list = zeros(tabu_tenure, 1);  % 存储邻居的哈希值
tabu_ptr  = 1;  % 环形指针

if ts_params.verbose
    fprintf('[TS] 初始最优 makespan: %.2f\n', best_makespan);
end

%% 2. 主循环
for gen = 1:max_gen
    % 生成邻域
    best_neighbor     = [];
    best_neighbor_fit = inf;
    best_neighbor_hash = 0;

    for n = 1:num_neighbors
        % 生成邻居（多种扰动随机选择）
        neighbor = ts_perturb(current, total_ops, machine_data, fixture_data, ...
                              num_Line_side, job_operation_num);

        [~, nfit] = decode_makespan(neighbor, num_machines, machine_data, ...
                                     fixture_data, job_operation_num, num_fixture_types);

        % 计算哈希值（用于禁忌检查）
        nhash = ts_hash(neighbor);
        is_tabu = any(tabu_list == nhash);

        % 接受准则：非禁忌 或 藐视准则（比全局最优还好）
        if nfit < best_neighbor_fit
            if ~is_tabu || nfit < best_makespan
                best_neighbor     = neighbor;
                best_neighbor_fit = nfit;
                best_neighbor_hash = nhash;
            end
        end
    end

    % 移动到最优邻居
    if ~isempty(best_neighbor)
        current = best_neighbor;
        current_makespan = best_neighbor_fit;

        % 更新禁忌表
        tabu_list(tabu_ptr) = best_neighbor_hash;
        tabu_ptr = mod(tabu_ptr, tabu_tenure) + 1;

        % 更新全局最优
        if current_makespan < best_makespan
            best_makespan   = current_makespan;
            best_individual = current;
        end
    end

    history(gen) = best_makespan;

    if ts_params.verbose && mod(gen, 10) == 0
        fprintf('[TS] 第 %d 代 | 当前: %.2f | 最优: %.2f\n', gen, current_makespan, best_makespan);
    end
end

if ts_params.verbose
    fprintf('[TS] 最终最优 makespan: %.2f\n', best_makespan);
end
end

%% ======================== TS 邻域扰动 ========================
function neighbor = ts_perturb(individual, total_ops, machine_data, fixture_data, ...
                                num_Line_side, job_operation_num)
    neighbor = individual;
    r = rand();

    if r < 0.4
        % 工序排序：交换
        offset = 3 * total_ops;
        p1 = randi(total_ops); p2 = randi(total_ops);
        while p1 == p2, p2 = randi(total_ops); end
        temp = neighbor(offset + p1);
        neighbor(offset + p1) = neighbor(offset + p2);
        neighbor(offset + p2) = temp;

    elseif r < 0.6
        % 工序排序：插入
        offset = 3 * total_ops;
        sched = neighbor(offset+1 : offset+total_ops);
        p1 = randi(total_ops); p2 = randi(total_ops);
        while p1 == p2, p2 = randi(total_ops); end
        gene = sched(p1);
        sched(p1) = [];
        if p2 > p1, p2 = p2 - 1; end
        sched = [sched(1:p2-1), gene, sched(p2:end)];
        neighbor(offset+1 : offset+total_ops) = sched;

    elseif r < 0.8
        % 机器选择
        p = randi(total_ops);
        [job, op] = get_job_op(p, job_operation_num);
        n = size(machine_data{job}{op}, 1);
        if n > 1
            cur = neighbor(p);
            pick = randi(n - 1);
            if pick >= cur, pick = pick + 1; end
            neighbor(p) = pick;
        end

    elseif r < 0.9
        % 夹具选择
        p = randi(total_ops);
        [job, op] = get_job_op(p, job_operation_num);
        n = size(fixture_data{job}{op}, 1);
        if n > 1
            cur = neighbor(total_ops + p);
            pick = randi(n - 1);
            if pick >= cur, pick = pick + 1; end
            neighbor(total_ops + p) = pick;
        end

    else
        % 库位扰动
        p = randi(total_ops);
        col = 2 * total_ops + p;
        new_ls = neighbor(col) + randi([-3, 3]);
        if new_ls < 1, new_ls = 1; end
        if new_ls > num_Line_side, new_ls = num_Line_side; end
        neighbor(col) = new_ls;
    end
end

%% ======================== 简易哈希 ========================
function h = ts_hash(individual)
    % 快速哈希：用若干采样位做加权求和
    n = length(individual);
    step = max(1, floor(n / 50));
    idx = 1:step:n;
    weights = (1:numel(idx))';
    h = mod(sum(individual(idx)' .* weights), 1e9 + 7);
end
