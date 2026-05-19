function pop = init_population(num_Line_side, pop_size, job_operation_num, job_machine_time, fixture_data)
% 改进的初始化种群
% 策略：混合初始化
%   - 前20%个体：贪心启发式（SPT最短加工时间规则选机器+夹具，就近选库位）
%   - 中20%个体：负载均衡启发式（优先选当前负载最轻的机器）
%   - 后60%个体：纯随机（保持多样性）
%
% 输入：
%   num_Line_side      - 库位数
%   pop_size           - 种群规模
%   job_operation_num  - 各工件工序数
%   job_machine_time   - 加工时间数据 {job}{op}(machine_idx, :) = [machine_id, time]
%   fixture_data       - 夹具数据

total_jobs = length(job_operation_num);
total_operations = sum(job_operation_num);
pop = zeros(pop_size, 4 * total_operations);

% 划分三类个体的数量
num_greedy  = max(1, round(pop_size * 0.2));   % 20% 贪心SPT
num_balance = max(1, round(pop_size * 0.2));   % 20% 负载均衡
% 剩余为纯随机

for i = 1:pop_size

    % ======================== 机器选择编码 ========================
    machine_code = zeros(1, total_operations);
    idx = 0;

    if i <= num_greedy
        % --- 贪心策略：选加工时间最短的机器 ---
        for job = 1:total_jobs
            for op = 1:job_operation_num(job)
                idx = idx + 1;
                times = job_machine_time{job}{op};  % 每行: [机器ID, 加工时间]
                [~, min_idx] = min(times(:, end));   % 选加工时间最小的行
                machine_code(idx) = min_idx;
            end
        end

    elseif i <= num_greedy + num_balance
        % --- 负载均衡策略：优先选当前累计负载最小的机器 ---
        machine_load = containers.Map('KeyType', 'int32', 'ValueType', 'double');
        for job = 1:total_jobs
            for op = 1:job_operation_num(job)
                idx = idx + 1;
                times = job_machine_time{job}{op};
                best_idx = 1;
                best_load = inf;
                for m = 1:size(times, 1)
                    m_id = times(m, 1);
                    m_time = times(m, end);
                    if machine_load.isKey(m_id)
                        cur_load = machine_load(m_id) + m_time;
                    else
                        cur_load = m_time;
                    end
                    if cur_load < best_load
                        best_load = cur_load;
                        best_idx = m;
                    end
                end
                machine_code(idx) = best_idx;
                % 更新负载
                chosen_id = times(best_idx, 1);
                chosen_time = times(best_idx, end);
                if machine_load.isKey(chosen_id)
                    machine_load(chosen_id) = machine_load(chosen_id) + chosen_time;
                else
                    machine_load(chosen_id) = chosen_time;
                end
            end
        end

    else
        % --- 纯随机 ---
        for job = 1:total_jobs
            for op = 1:job_operation_num(job)
                idx = idx + 1;
                optional_machines_num = size(job_machine_time{job}{op}, 1);
                machine_code(idx) = randi(optional_machines_num);
            end
        end
    end

    % ======================== 夹具选择编码 ========================
    fixture_code = zeros(1, total_operations);
    idx = 0;

    if i <= num_greedy
        % 贪心：选装卸时间最短的夹具
        for job = 1:total_jobs
            for op = 1:job_operation_num(job)
                idx = idx + 1;
                fix_info = fixture_data{job}{op};
                if size(fix_info, 1) > 1
                    [~, min_idx] = min(fix_info(:, end));
                    fixture_code(idx) = min_idx;
                else
                    fixture_code(idx) = 1;
                end
            end
        end
    else
        % 随机
        for job = 1:total_jobs
            for op = 1:job_operation_num(job)
                idx = idx + 1;
                optional_fixture_num = size(fixture_data{job}{op}, 1);
                fixture_code(idx) = randi(optional_fixture_num);
            end
        end
    end

    % ======================== 库位选择编码 ========================
    Line_side_code = zeros(1, total_operations);
    idx = 0;

    if i <= num_greedy
        % 贪心：为同一工件的相邻工序分配相近库位，减少RGV运输
        for job = 1:total_jobs
            % 为该工件随机选一个基准库位
            base_ls = randi(num_Line_side);
            for op = 1:job_operation_num(job)
                idx = idx + 1;
                % 在基准库位附近小范围波动
                offset = randi([-2, 2]);
                ls = base_ls + offset;
                ls = max(1, min(num_Line_side, ls));  % 边界约束
                Line_side_code(idx) = ls;
            end
        end
    else
        % 随机
        for job = 1:total_jobs
            for op = 1:job_operation_num(job)
                idx = idx + 1;
                Line_side_code(idx) = randi(num_Line_side);
            end
        end
    end

    % ======================== 工序排序编码 ========================
    schedule_code = [];
    for job = 1:total_jobs
        schedule_code = [schedule_code, repmat(job, 1, job_operation_num(job))];
    end
    schedule_code = schedule_code(randperm(total_operations));

    % 组合四段编码
    pop(i, :) = [machine_code, fixture_code, Line_side_code, schedule_code];
end
end