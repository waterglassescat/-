function pop_crossed = crossover(pop_selected, crossover_prob, total_operations, job_operation_num)
% 改进的交叉操作
% 改进点：
%   1. 机器/夹具/库位编码：均匀交叉替代单点交叉（打破位置偏好，搜索更均匀）
%   2. 工序排序编码：POX + JBX随机切换（增加交叉多样性）
%   3. 自适应交叉概率（可选，通过外部传入）

pop_size = size(pop_selected, 1);
pop_crossed = pop_selected;
total_jobs = length(job_operation_num);

len_machine  = total_operations;
len_fixture  = total_operations;
len_location = total_operations;

for i = 1:2:pop_size-1
    if rand() < crossover_prob
        parent1 = pop_selected(i, :);
        parent2 = pop_selected(i+1, :);

        % ---------------------- 提取各部分编码 ----------------------
        machine1  = parent1(1:len_machine);
        fixture1  = parent1(len_machine+1 : len_machine+len_fixture);
        location1 = parent1(len_machine+len_fixture+1 : len_machine+len_fixture+len_location);
        schedule1 = parent1(len_machine+len_fixture+len_location+1 : end);

        machine2  = parent2(1:len_machine);
        fixture2  = parent2(len_machine+1 : len_machine+len_fixture);
        location2 = parent2(len_machine+len_fixture+1 : len_machine+len_fixture+len_location);
        schedule2 = parent2(len_machine+len_fixture+len_location+1 : end);

        % ---------------------- 机器选择：均匀交叉 ----------------------
        mask = rand(1, total_operations) < 0.5;
        machine_code1 = machine1;
        machine_code2 = machine2;
        machine_code1(mask)  = machine2(mask);
        machine_code2(mask)  = machine1(mask);

        % ---------------------- 夹具选择：均匀交叉 ----------------------
        mask_f = rand(1, total_operations) < 0.5;
        fixture_code1 = fixture1;
        fixture_code2 = fixture2;
        fixture_code1(mask_f) = fixture2(mask_f);
        fixture_code2(mask_f) = fixture1(mask_f);

        % ---------------------- 库位选择：两点交叉 ----------------------
        % 两点交叉比单点交叉能产生更多样的后代
        pts = sort(randperm(total_operations-1, 2));
        p1 = pts(1); p2 = pts(2);
        location_code1 = [location1(1:p1), location2(p1+1:p2), location1(p2+1:end)];
        location_code2 = [location2(1:p1), location1(p1+1:p2), location2(p2+1:end)];

        % ---------------------- 工序排序：POX / JBX 随机选择 ----------------------
        if rand() < 0.5
            % === POX交叉（Precedence Operation Crossover）===
            [offspring_sched1, offspring_sched2] = pox_crossover(...
                schedule1, schedule2, total_operations, total_jobs);
        else
            % === JBX交叉（Job-Based Crossover）===
            [offspring_sched1, offspring_sched2] = jbx_crossover(...
                schedule1, schedule2, total_operations, total_jobs);
        end

        % ---------------------- 组合 ----------------------
        pop_crossed(i, :)   = [machine_code1, fixture_code1, location_code1, offspring_sched1];
        pop_crossed(i+1, :) = [machine_code2, fixture_code2, location_code2, offspring_sched2];
    end
end
end

%% ============================= POX交叉 =============================
function [child1, child2] = pox_crossover(sched1, sched2, total_ops, total_jobs)
    % 随机划分工件为两个非空子集
    rand_jobs = randperm(total_jobs);
    subset_size = randi(total_jobs - 1);
    job_subset1 = rand_jobs(1:subset_size);
    job_subset2 = rand_jobs(subset_size+1:end);

    % 子代1：保留父代1中属于subset1的位置，从父代2填入subset2
    child1 = zeros(1, total_ops);
    for k = 1:total_ops
        if ismember(sched1(k), job_subset1)
            child1(k) = sched1(k);
        end
    end
    idx = 1;
    for k = 1:total_ops
        if ismember(sched2(k), job_subset2)
            while idx <= total_ops && child1(idx) ~= 0
                idx = idx + 1;
            end
            if idx <= total_ops
                child1(idx) = sched2(k);
            end
        end
    end

    % 子代2：对称操作
    child2 = zeros(1, total_ops);
    for k = 1:total_ops
        if ismember(sched2(k), job_subset2)
            child2(k) = sched2(k);
        end
    end
    idx = 1;
    for k = 1:total_ops
        if ismember(sched1(k), job_subset1)
            while idx <= total_ops && child2(idx) ~= 0
                idx = idx + 1;
            end
            if idx <= total_ops
                child2(idx) = sched1(k);
            end
        end
    end
end

%% ============================= JBX交叉 =============================
function [child1, child2] = jbx_crossover(sched1, sched2, total_ops, total_jobs)
    % JBX (Job-Based Crossover)
    % 随机选一半工件，子代1从父代1继承这些工件的全部工序（保持相对位置），
    % 剩余工件从父代2按顺序填入

    rand_jobs = randperm(total_jobs);
    subset_size = randi(total_jobs - 1);
    selected_jobs = rand_jobs(1:subset_size);

    child1 = build_jbx_child(sched1, sched2, total_ops, selected_jobs);
    child2 = build_jbx_child(sched2, sched1, total_ops, selected_jobs);
end

function child = build_jbx_child(primary, secondary, total_ops, selected_jobs)
    % primary中selected_jobs的工序保持原位，其余位置从secondary按顺序填入非selected的工序
    child = zeros(1, total_ops);
    % 标记primary中selected_jobs所占的位置
    for k = 1:total_ops
        if ismember(primary(k), selected_jobs)
            child(k) = primary(k);
        end
    end
    % 从secondary中按顺序取出非selected_jobs的工序
    idx = 1;
    for k = 1:total_ops
        if ~ismember(secondary(k), selected_jobs)
            while idx <= total_ops && child(idx) ~= 0
                idx = idx + 1;
            end
            if idx <= total_ops
                child(idx) = secondary(k);
            end
        end
    end
end