function [best_individual, best_makespan, history] = sa_solver(num_machines, machine_data, ...
    fixture_data, job_operation_num, num_fixture_types, sa_params)
% 模拟退火算法（Simulated Annealing）
%
% 编码方式与 GA-VNS 完全一致：[machine_code, fixture_code, line_side_code, schedule_code]
% 复用 init_population, decode_makespan
%
% sa_params 字段：
%   .max_gen          - 外层迭代数（用于与GA对齐x轴，默认200）
%   .inner_iter       - 每个温度下的内层迭代次数（默认20）
%   .T0               - 初始温度（默认500）
%   .T_min            - 最低温度（默认1）
%   .alpha            - 降温系数（默认0.95）
%   .pop_size         - 初始生成候选数（取最优作为初始解，默认50）
%   .verbose          - 是否打印进度（默认true）

%% 参数默认值
if nargin < 5 || isempty(sa_params), sa_params = struct(); end
if ~isfield(sa_params, 'max_gen'),     sa_params.max_gen = 200;      end
if ~isfield(sa_params, 'inner_iter'),  sa_params.inner_iter = 20;    end
if ~isfield(sa_params, 'T0'),          sa_params.T0 = 500;           end
if ~isfield(sa_params, 'T_min'),       sa_params.T_min = 1;          end
if ~isfield(sa_params, 'alpha'),       sa_params.alpha = 0.95;       end
if ~isfield(sa_params, 'pop_size'),    sa_params.pop_size = 50;      end
if ~isfield(sa_params, 'verbose'),     sa_params.verbose = true;     end

max_gen    = sa_params.max_gen;
inner_iter = sa_params.inner_iter;
T          = sa_params.T0;
T_min      = sa_params.T_min;
alpha      = sa_params.alpha;

layout = create_layout_info(num_machines);
num_Line_side = layout.num_Line_side;
total_ops = sum(job_operation_num);

%% 1. 初始解：从随机种群中选最优
init_pop = init_population(num_Line_side, sa_params.pop_size, job_operation_num, machine_data, fixture_data);
init_fit = zeros(sa_params.pop_size, 1);
for i = 1:sa_params.pop_size
    [~, init_fit(i)] = decode_makespan(init_pop(i,:), num_machines, machine_data, ...
                                        fixture_data, job_operation_num, num_fixture_types);
end
[current_makespan, best_idx] = min(init_fit);
current = init_pop(best_idx, :);

best_individual = current;
best_makespan   = current_makespan;
history = zeros(max_gen, 1);

if sa_params.verbose
    fprintf('[SA] 初始最优 makespan: %.2f, T0=%.1f\n', best_makespan, T);
end

%% 2. 主循环（按代数迭代，与GA横轴对齐）
for gen = 1:max_gen
    for inner = 1:inner_iter
        % 2.1 生成邻域解（多种扰动随机选择）
        neighbor = sa_perturb(current, total_ops, machine_data, fixture_data, ...
                              num_Line_side, job_operation_num);

        % 2.2 评估
        [~, neighbor_makespan] = decode_makespan(neighbor, num_machines, machine_data, ...
                                                  fixture_data, job_operation_num, num_fixture_types);

        % 2.3 Metropolis准则
        delta = neighbor_makespan - current_makespan;
        if delta < 0
            current = neighbor;
            current_makespan = neighbor_makespan;
        else
            if T > 0 && rand() < exp(-delta / T)
                current = neighbor;
                current_makespan = neighbor_makespan;
            end
        end

        % 2.4 更新全局最优
        if current_makespan < best_makespan
            best_makespan   = current_makespan;
            best_individual = current;
        end
    end

    % 降温
    T = max(T * alpha, T_min);
    history(gen) = best_makespan;

    if sa_params.verbose && mod(gen, 10) == 0
        fprintf('[SA] 第 %d 代 | 最优: %.2f | T=%.2f\n', gen, best_makespan, T);
    end
end

if sa_params.verbose
    fprintf('[SA] 最终最优 makespan: %.2f\n', best_makespan);
end
end

%% ======================== SA 邻域扰动 ========================
function neighbor = sa_perturb(individual, total_ops, machine_data, fixture_data, ...
                                num_Line_side, job_operation_num)
    neighbor = individual;
    r = rand();

    if r < 0.35
        % --- 工序排序扰动（交换两个位置）---
        offset = 3 * total_ops;
        p1 = randi(total_ops);
        p2 = randi(total_ops);
        while p1 == p2, p2 = randi(total_ops); end
        temp = neighbor(offset + p1);
        neighbor(offset + p1) = neighbor(offset + p2);
        neighbor(offset + p2) = temp;

    elseif r < 0.55
        % --- 工序排序扰动（插入）---
        offset = 3 * total_ops;
        sched = neighbor(offset+1 : offset+total_ops);
        p1 = randi(total_ops);
        p2 = randi(total_ops);
        while p1 == p2, p2 = randi(total_ops); end
        gene = sched(p1);
        sched(p1) = [];
        if p2 > p1, p2 = p2 - 1; end
        sched = [sched(1:p2-1), gene, sched(p2:end)];
        neighbor(offset+1 : offset+total_ops) = sched;

    elseif r < 0.70
        % --- 工序排序扰动（逆序片段）---
        offset = 3 * total_ops;
        pts = sort(randperm(total_ops, 2));
        neighbor(offset+pts(1) : offset+pts(2)) = ...
            fliplr(neighbor(offset+pts(1) : offset+pts(2)));

    elseif r < 0.85
        % --- 机器选择扰动（改1~2个位置）---
        num_changes = randi([1, 2]);
        positions = randperm(total_ops, min(num_changes, total_ops));
        for p = positions
            [job, op] = get_job_op(p, job_operation_num);
            n = size(machine_data{job}{op}, 1);
            if n > 1
                cur = neighbor(p);
                pick = randi(n - 1);
                if pick >= cur, pick = pick + 1; end
                neighbor(p) = pick;
            end
        end

    elseif r < 0.95
        % --- 夹具选择扰动 ---
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
        % --- 库位扰动 ---
        p = randi(total_ops);
        col = 2 * total_ops + p;
        new_ls = neighbor(col) + randi([-3, 3]);
        if new_ls < 1, new_ls = 1; end
        if new_ls > num_Line_side, new_ls = num_Line_side; end
        neighbor(col) = new_ls;
    end
end
