function [best_individual, best_makespan, history] = pso_solver(num_machines, machine_data, ...
    fixture_data, job_operation_num, num_fixture_types, pso_params)
% 离散粒子群优化（Discrete PSO）
%
% 编码方式与 GA-VNS 完全一致：[machine_code, fixture_code, line_side_code, schedule_code]
% 离散PSO策略：
%   - 机器/夹具/库位编码：以概率 w 保持自身，概率 c1 学习个体最优，概率 c2 学习全局最优
%   - 工序排序编码：通过与 pbest/gbest 做部分映射交叉来"飞行"
%
% pso_params 字段：
%   .pop_size   - 粒子数（默认50）
%   .max_gen    - 最大迭代数（默认200）
%   .w          - 惯性权重（默认0.5）
%   .c1         - 个体学习因子（默认0.3）
%   .c2         - 社会学习因子（默认0.2）
%   .verbose    - 是否打印进度（默认true）

%% 参数默认值
if nargin < 5 || isempty(pso_params), pso_params = struct(); end
if ~isfield(pso_params, 'pop_size'), pso_params.pop_size = 50;   end
if ~isfield(pso_params, 'max_gen'),  pso_params.max_gen = 200;   end
if ~isfield(pso_params, 'w'),        pso_params.w = 0.5;         end
if ~isfield(pso_params, 'c1'),       pso_params.c1 = 0.3;        end
if ~isfield(pso_params, 'c2'),       pso_params.c2 = 0.2;        end
if ~isfield(pso_params, 'verbose'),  pso_params.verbose = true;  end

pop_size = pso_params.pop_size;
max_gen  = pso_params.max_gen;
w  = pso_params.w;
c1 = pso_params.c1;
c2 = pso_params.c2;
total_ops = sum(job_operation_num);

layout = create_layout_info(num_machines);
num_Line_side = layout.num_Line_side;

%% 预计算 pos -> (job, op, nMach, nFix) 查找表
pos2job = zeros(total_ops, 1);
pos2op  = zeros(total_ops, 1);
nMach_tbl = zeros(total_ops, 1);
nFix_tbl  = zeros(total_ops, 1);
k = 0;
for j = 1:length(job_operation_num)
    for o = 1:job_operation_num(j)
        k = k + 1;
        pos2job(k) = j;
        pos2op(k)  = o;
        nMach_tbl(k) = size(machine_data{j}{o}, 1);
        nFix_tbl(k)  = size(fixture_data{j}{o}, 1);
    end
end

%% 1. 初始化粒子群
swarm = init_population(num_Line_side, pop_size, job_operation_num, machine_data, fixture_data);

fitness = zeros(pop_size, 1);
for i = 1:pop_size
    [~, fitness(i)] = decode_makespan(swarm(i,:), num_machines, machine_data, ...
                                       fixture_data, job_operation_num, num_fixture_types);
end

% 个体最优
pbest     = swarm;
pbest_fit = fitness;

% 全局最优
[best_makespan, best_idx] = min(fitness);
best_individual = swarm(best_idx, :);
gbest = best_individual;

history = zeros(max_gen, 1);

if pso_params.verbose
    fprintf('[PSO] 初始最优 makespan: %.2f\n', best_makespan);
end

%% 2. 主循环
for gen = 1:max_gen
    % 线性递减惯性权重
    w_cur = w - (w - 0.2) * gen / max_gen;

    for i = 1:pop_size
        particle = swarm(i,:);

        % ---- 2.1 机器/夹具/库位编码更新 ----
        % 对每个基因位，以概率选择来源
        for p = 1:total_ops
            r = rand();
            if r < w_cur
                % 保持自身（惯性）
            elseif r < w_cur + c1
                % 学习 pbest
                particle(p)              = pbest(i, p);                   % 机器
                particle(total_ops + p)  = pbest(i, total_ops + p);       % 夹具
                particle(2*total_ops+p)  = pbest(i, 2*total_ops + p);     % 库位
            elseif r < w_cur + c1 + c2
                % 学习 gbest
                particle(p)              = gbest(p);
                particle(total_ops + p)  = gbest(total_ops + p);
                particle(2*total_ops+p)  = gbest(2*total_ops + p);
            else
                % 随机扰动
                particle(p)             = randi(nMach_tbl(p));
                particle(total_ops + p) = randi(nFix_tbl(p));
                particle(2*total_ops+p) = randi(num_Line_side);
            end
        end

        % ---- 2.2 工序排序编码更新（部分映射策略）----
        sched_start = 3 * total_ops + 1;
        sched_end   = 4 * total_ops;
        my_sched    = particle(sched_start:sched_end);

        r2 = rand();
        if r2 < c1
            % 向 pbest 学习：保留 pbest 中随机一半工件的位置，其余从自身填充
            target_sched = pbest(i, sched_start:sched_end);
            my_sched = pso_schedule_learn(my_sched, target_sched, total_ops, length(job_operation_num));
        elseif r2 < c1 + c2
            % 向 gbest 学习
            target_sched = gbest(sched_start:sched_end);
            my_sched = pso_schedule_learn(my_sched, target_sched, total_ops, length(job_operation_num));
        else
            % 随机扰动（交换两个位置）
            p1 = randi(total_ops); p2 = randi(total_ops);
            while p1 == p2, p2 = randi(total_ops); end
            temp = my_sched(p1);
            my_sched(p1) = my_sched(p2);
            my_sched(p2) = temp;
        end
        particle(sched_start:sched_end) = my_sched;

        swarm(i,:) = particle;

        % ---- 2.3 评估 ----
        [~, fit] = decode_makespan(particle, num_machines, machine_data, ...
                                    fixture_data, job_operation_num, num_fixture_types);
        fitness(i) = fit;

        % 更新个体最优
        if fit < pbest_fit(i)
            pbest_fit(i)  = fit;
            pbest(i, :)   = particle;
        end
    end

    % 更新全局最优
    [gen_best, gen_best_idx] = min(fitness);
    if gen_best < best_makespan
        best_makespan   = gen_best;
        best_individual = swarm(gen_best_idx, :);
        gbest           = best_individual;
    end
    history(gen) = best_makespan;

    if pso_params.verbose && mod(gen, 10) == 0
        fprintf('[PSO] 第 %d 代 | 最优: %.2f | w=%.3f\n', gen, best_makespan, w_cur);
    end
end

if pso_params.verbose
    fprintf('[PSO] 最终最优 makespan: %.2f\n', best_makespan);
end
end

%% ======================== 工序排序学习函数 ========================
function new_sched = pso_schedule_learn(my_sched, target_sched, total_ops, total_jobs)
    % 从 target 中随机选一半工件，保持其在 target 中的位置顺序
    % 其余位置从 my_sched 中按顺序填入
    rand_jobs = randperm(total_jobs);
    subset_size = max(1, round(total_jobs / 2));
    in_sel = false(total_jobs, 1);
    in_sel(rand_jobs(1:subset_size)) = true;

    new_sched = zeros(1, total_ops);
    keep = in_sel(target_sched);
    new_sched(keep) = target_sched(keep);
    fill_vals = my_sched(~in_sel(my_sched));
    new_sched(~keep) = fill_vals;
end
