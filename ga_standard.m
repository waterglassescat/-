function [best_individual, best_makespan, history] = ga_standard(num_machines, machine_data, ...
    fixture_data, job_operation_num, num_fixture_types, ga_params)
% 标准遗传算法（Standard GA）
% 作为对比基线：无VNS局部搜索、无自适应参数调整
%
% 编码方式与 GA-VNS 完全一致：[machine_code, fixture_code, line_side_code, schedule_code]
% 复用 init_population, crossover, mutation, decode_makespan
%
% 输入/输出格式与 ga_vns_main 相同

%% 参数默认值
if nargin < 5 || isempty(ga_params), ga_params = struct(); end
if ~isfield(ga_params, 'pop_size'),       ga_params.pop_size = 100;        end
if ~isfield(ga_params, 'max_gen'),        ga_params.max_gen = 200;         end
if ~isfield(ga_params, 'crossover_prob'), ga_params.crossover_prob = 0.8;  end
if ~isfield(ga_params, 'mutation_prob'),  ga_params.mutation_prob = 0.1;   end
if ~isfield(ga_params, 'elite_ratio'),    ga_params.elite_ratio = 0.1;     end
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
    fprintf('[标准GA] 初始最优 makespan: %.2f\n', best_makespan);
end

%% 3. 主循环
crossover_prob = ga_params.crossover_prob;
mutation_prob  = ga_params.mutation_prob;

for gen = 1:max_gen
    % 3.1 精英保留
    num_elite = max(2, round(pop_size * ga_params.elite_ratio));
    [sorted_fitness, sorted_idx] = sort(fitness);
    elite_pop     = pop(sorted_idx(1:num_elite), :);
    elite_fitness = sorted_fitness(1:num_elite);

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

    % 3.5 评估 + 精英替换
    pop = pop_muted;
    new_fitness = zeros(pop_size, 1);
    for i = 1:pop_size
        [~, new_fitness(i)] = decode_makespan(pop(i,:), num_machines, machine_data, ...
                                               fixture_data, job_operation_num, num_fixture_types);
    end

    [~, worst_idx] = sort(new_fitness, 'descend');
    for e = 1:num_elite
        pop(worst_idx(e), :)      = elite_pop(e, :);
        new_fitness(worst_idx(e)) = elite_fitness(e);
    end
    fitness = new_fitness;

    % 3.6 更新全局最优
    [gen_best, gen_best_idx] = min(fitness);
    if gen_best < best_makespan
        best_makespan = gen_best;
        best_individual = pop(gen_best_idx, :);
    end
    history(gen) = best_makespan;

    if ga_params.verbose && mod(gen, 10) == 0
        fprintf('[标准GA] 第 %d 代 | 最优 makespan: %.2f\n', gen, best_makespan);
    end
end

if ga_params.verbose
    fprintf('[标准GA] 最终最优 makespan: %.2f\n', best_makespan);
end
end
