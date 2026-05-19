function [best_individual, best_makespan, history] = ga_vns_main(num_machines, machine_data, ...
    fixture_data, job_operation_num, num_fixture_types, ga_params)
% 混合遗传算法-变邻域搜索（GA-VNS）主循环
%
% ga_params 新增字段：
%   .enabled_neighborhoods - 长度为5的逻辑向量，传给VNS（默认 true(1,5)）
%                            消融实验时使用
%   .verbose               - 是否打印进度（默认true，消融批跑时建议false）

%% 参数默认值
if nargin < 5 || isempty(ga_params), ga_params = struct(); end
if ~isfield(ga_params, 'pop_size'),       ga_params.pop_size = 100;        end
if ~isfield(ga_params, 'max_gen'),        ga_params.max_gen = 200;         end
if ~isfield(ga_params, 'crossover_prob'), ga_params.crossover_prob = 0.8;  end
if ~isfield(ga_params, 'mutation_prob'),  ga_params.mutation_prob = 0.1;   end
if ~isfield(ga_params, 'elite_ratio'),    ga_params.elite_ratio = 0.1;     end
if ~isfield(ga_params, 'vns_ratio'),      ga_params.vns_ratio = 0.05;      end
if ~isfield(ga_params, 'vns_interval'),   ga_params.vns_interval = 5;      end
if ~isfield(ga_params, 'adaptive'),       ga_params.adaptive = true;       end
if ~isfield(ga_params, 'enabled_neighborhoods')
    ga_params.enabled_neighborhoods = true(1, 5);
end
if ~isfield(ga_params, 'verbose'),        ga_params.verbose = true;        end

pop_size = ga_params.pop_size;
max_gen  = ga_params.max_gen;
total_operations = sum(job_operation_num);

layout = create_layout_info(num_machines);
num_Line_side = layout.num_Line_side;

%% 1. 初始化种群
pop = init_population(num_Line_side, pop_size, job_operation_num, machine_data, fixture_data);

%% 2. 评估初始种群
fitness = zeros(pop_size, 1);
for i = 1:pop_size
    [~, fitness(i)] = decode_makespan(pop(i,:), num_machines, machine_data, ...
                                       fixture_data, job_operation_num, num_fixture_types);
end

[best_makespan, best_idx] = min(fitness);
best_individual = pop(best_idx, :);
history = zeros(max_gen, 1);

if ga_params.verbose
    fprintf('初始最优 makespan: %.2f\n', best_makespan);
end

%% 3. 主循环
crossover_prob = ga_params.crossover_prob;
mutation_prob  = ga_params.mutation_prob;
stagnation_count = 0;
prev_best = best_makespan;

for gen = 1:max_gen
    % 3.1 精英保留
    num_elite = max(2, round(pop_size * ga_params.elite_ratio));
    [sorted_fitness, sorted_idx] = sort(fitness);
    elite_pop = pop(sorted_idx(1:num_elite), :);
    elite_fitness = sorted_fitness(1:num_elite);   % 缓存elite的fitness，避免后面重算

    % 3.2 锦标赛选择
    tournament_size = 3;
    selected_pop = zeros(pop_size, size(pop, 2));
    for i = 1:pop_size
        candidates = randperm(pop_size, tournament_size);
        [~, winner_idx] = min(fitness(candidates));
        selected_pop(i, :) = pop(candidates(winner_idx), :);
    end

    % 3.3 交叉
    pop_crossed = crossover(selected_pop, crossover_prob, total_operations, job_operation_num);

    % 3.4 变异
    pop_muted = mutation(pop_crossed, mutation_prob, total_operations, ...
                         machine_data, fixture_data, num_Line_side, job_operation_num);

    % 3.5 评估新种群
    pop = pop_muted;
    new_fitness = zeros(pop_size, 1);
    for i = 1:pop_size
        [~, new_fitness(i)] = decode_makespan(pop(i,:), num_machines, machine_data, ...
                                               fixture_data, job_operation_num, num_fixture_types);
    end

    % 3.6 精英替换：用上一代最好的num_elite个替换本代最差的num_elite个
    %     【优化】直接复用上一代缓存的fitness，不再重新decode
    [~, worst_idx] = sort(new_fitness, 'descend');
    for e = 1:num_elite
        pop(worst_idx(e), :) = elite_pop(e, :);
        new_fitness(worst_idx(e)) = elite_fitness(e);
    end
    fitness = new_fitness;

    % 3.7 VNS
    if mod(gen, ga_params.vns_interval) == 0
        num_vns = max(1, round(pop_size * ga_params.vns_ratio));
        [~, best_indices] = sort(fitness);
        vns_params = struct( ...
            'max_iter', 15, ...
            'k_max', 5, ...
            'enabled_neighborhoods', ga_params.enabled_neighborhoods);

        for v = 1:num_vns
            idx = best_indices(v);
            improved = variable_neighborhood_search(pop(idx,:), ...
                num_machines, machine_data, fixture_data, job_operation_num, ...
                num_Line_side, num_fixture_types, vns_params);
            [~, imp_makespan] = decode_makespan(improved, num_machines, machine_data, ...
                                                 fixture_data, job_operation_num, num_fixture_types);
            if imp_makespan < fitness(idx)
                pop(idx, :) = improved;
                fitness(idx) = imp_makespan;
            end
        end
    end

    % 3.8 更新全局最优
    [gen_best, gen_best_idx] = min(fitness);
    if gen_best < best_makespan
        best_makespan = gen_best;
        best_individual = pop(gen_best_idx, :);
    end
    history(gen) = best_makespan;

    % 3.9 自适应参数
    if ga_params.adaptive
        if best_makespan < prev_best
            stagnation_count = 0;
        else
            stagnation_count = stagnation_count + 1;
        end

        if stagnation_count > 10
            mutation_prob  = min(0.4, mutation_prob * 1.2);
            crossover_prob = max(0.5, crossover_prob * 0.95);
        elseif stagnation_count == 0
            mutation_prob  = ga_params.mutation_prob;
            crossover_prob = ga_params.crossover_prob;
        end
        prev_best = best_makespan;
    end

    % 3.10 进度
    if ga_params.verbose && mod(gen, 10) == 0
        fprintf('第 %d 代 | 最优 makespan: %.2f | 变异率: %.3f | 交叉率: %.3f\n', ...
                gen, best_makespan, mutation_prob, crossover_prob);
    end
end

if ga_params.verbose
    fprintf('\n最终最优 makespan: %.2f\n', best_makespan);
end
end
