function improved_individual = variable_neighborhood_search(individual, ...
    num_machines, machine_data, fixture_data, job_operation_num, num_Line_side, num_fixture_types, vns_params)
% 变邻域搜索（Variable Neighborhood Search, VNS）
%
% vns_params 字段：
%   .max_iter              - 最大迭代次数（默认30）
%   .k_max                 - 最大邻域编号（默认5）
%   .enabled_neighborhoods - 长度为5的逻辑向量，指定哪些邻域启用
%                            （默认 [true true true true true]）
%                            用于邻域消融实验

if nargin < 7 || isempty(vns_params)
    vns_params = struct();
end
if ~isfield(vns_params, 'max_iter'), vns_params.max_iter = 30; end
if ~isfield(vns_params, 'k_max'),    vns_params.k_max = 5;    end
if ~isfield(vns_params, 'enabled_neighborhoods')
    vns_params.enabled_neighborhoods = true(1, 5);
end

% 构造启用的邻域列表（保持原有顺序）
enabled_list = find(vns_params.enabled_neighborhoods(1:vns_params.k_max));
if isempty(enabled_list)
    % 没有任何邻域启用 → 直接返回原个体（用于"无VNS"基线）
    improved_individual = individual;
    return;
end

total_ops = length(individual) / 4;
len = total_ops;

best = individual;
[~, best_makespan] = decode_makespan(best, num_machines, machine_data, fixture_data, job_operation_num, num_fixture_types);

no_improve_count = 0;

for iter = 1:vns_params.max_iter
    k_idx = 1;     % 指向 enabled_list 中的位置
    improved = false;

    while k_idx <= numel(enabled_list)
        k = enabled_list(k_idx);  % 实际邻域编号

        % 1. Shaking
        neighbor = shake(best, k, len, machine_data, fixture_data, num_Line_side, job_operation_num);

        % 2. Local Search
        neighbor = local_search(neighbor, num_machines, machine_data, fixture_data, ...
                                job_operation_num, num_Line_side, num_fixture_types);

        % 3. Move or Not
        [~, neighbor_makespan] = decode_makespan(neighbor, num_machines, machine_data, ...
                                                  fixture_data, job_operation_num, num_fixture_types);

        if neighbor_makespan < best_makespan
            best = neighbor;
            best_makespan = neighbor_makespan;
            k_idx = 1;
            improved = true;
        else
            k_idx = k_idx + 1;
        end
    end

    if ~improved
        no_improve_count = no_improve_count + 1;
    else
        no_improve_count = 0;
    end

    if no_improve_count >= 5
        break;
    end
end

improved_individual = best;
end

%% ======================== 摇晃函数 ========================
function neighbor = shake(individual, k, len, machine_data, fixture_data, num_Line_side, job_operation_num)
    neighbor = individual;

    switch k
        case 1
            % 邻域1：工序排序-交换变异（小扰动）
            offset = 3 * len;
            pos1 = randi(len);
            pos2 = randi(len);
            while pos1 == pos2, pos2 = randi(len); end
            temp = neighbor(offset + pos1);
            neighbor(offset + pos1) = neighbor(offset + pos2);
            neighbor(offset + pos2) = temp;

        case 2
            % 邻域2：工序排序-插入变异（中扰动）
            offset = 3 * len;
            sched = neighbor(offset+1 : offset+len);
            pos1 = randi(len);
            pos2 = randi(len);
            while pos1 == pos2, pos2 = randi(len); end
            gene = sched(pos1);
            sched(pos1) = [];
            if pos2 > pos1, pos2 = pos2 - 1; end
            sched = [sched(1:pos2-1), gene, sched(pos2:end)];
            neighbor(offset+1 : offset+len) = sched;

        case 3
            % 邻域3：工序排序-逆序变异（大扰动）
            offset = 3 * len;
            pts = sort(randperm(len, 2));
            seg = neighbor(offset + pts(1) : offset + pts(2));
            neighbor(offset + pts(1) : offset + pts(2)) = fliplr(seg);

        case 4
            % 邻域4：机器选择变异
            num_changes = randi([1, max(1, round(len * 0.1))]);
            positions = randperm(len, num_changes);
            for p = positions
                [job, op] = get_job_op(p, job_operation_num);
                optional_num = size(machine_data{job}{op}, 1);
                if optional_num > 1
                    current = neighbor(p);
                    candidates = setdiff(1:optional_num, current);
                    neighbor(p) = candidates(randi(length(candidates)));
                end
            end

        case 5
            % 邻域5：混合扰动
            num_m = randi([2, min(3, len)]);
            m_pos = randperm(len, num_m);
            for p = m_pos
                [job, op] = get_job_op(p, job_operation_num);
                optional_num = size(machine_data{job}{op}, 1);
                neighbor(p) = randi(optional_num);
            end
            offset = 3 * len;
            for swap = 1:2
                p1 = randi(len); p2 = randi(len);
                while p1 == p2, p2 = randi(len); end
                temp = neighbor(offset + p1);
                neighbor(offset + p1) = neighbor(offset + p2);
                neighbor(offset + p2) = temp;
            end
            offset_ls = 2 * len;
            num_ls = randi([1, 2]);
            ls_pos = randperm(len, num_ls);
            for p = ls_pos
                neighbor(offset_ls + p) = randi(num_Line_side);
            end
    end
end

%% ======================== 局部搜索函数 ========================
function improved = local_search(individual, num_machines, machine_data, fixture_data, ...
                                  job_operation_num, num_Line_side, num_fixture_types) %#ok<INUSD>
    improved = individual;
    total_ops = length(individual) / 4;
    offset = 3 * total_ops;

    [~, current_makespan] = decode_makespan(improved, num_machines, machine_data, ...
                                             fixture_data, job_operation_num, num_fixture_types);

    num_tries = min(20, total_ops - 1);
    positions = randperm(total_ops - 1, num_tries);

    for pos = positions
        candidate = improved;
        temp = candidate(offset + pos);
        candidate(offset + pos) = candidate(offset + pos + 1);
        candidate(offset + pos + 1) = temp;

        [~, new_makespan] = decode_makespan(candidate, num_machines, machine_data, ...
                                             fixture_data, job_operation_num, num_fixture_types);
        if new_makespan < current_makespan
            improved = candidate;
            current_makespan = new_makespan;
        end
    end
end
