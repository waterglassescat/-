function pop_muted = mutation(pop_crossed, mutation_prob, total_operations, ...
                              machine_data, fixture_data, num_Line_side, job_operation_num)
% 变异操作（性能优化版，逻辑与原版完全等价）
%
% 优化要点：
%   1) 预计算 pos -> (job, op) 查找表，避免每次 get_job_op 调用
%   2) 预计算每个位置的可选机器数/可选夹具数，避免循环中的 size() 调用
%   3) 一次性生成变异掩码矩阵，只遍历需要变异的位置（对 p=0.1 可减 10x 循环）
%   4) 用 O(1) 模运算替代 setdiff(1:n, cur)

pop_size = size(pop_crossed, 1);
pop_muted = pop_crossed;

len_machine  = total_operations;
len_fixture  = total_operations;
len_location = total_operations;
len_schedule = total_operations;

offset_fixture  = len_machine;
offset_location = len_machine + len_fixture;
offset_schedule = len_machine + len_fixture + len_location;

%% 预计算查找表（仅第一次调用，或 job_operation_num 改变时重算）
persistent cached_jon cached_pos2job cached_pos2op cached_nMach cached_nFix
need_rebuild = isempty(cached_jon) || ~isequal(cached_jon, job_operation_num) ...
               || numel(cached_pos2job) ~= total_operations;
if need_rebuild
    cached_jon     = job_operation_num;
    cached_pos2job = zeros(total_operations, 1);
    cached_pos2op  = zeros(total_operations, 1);
    cached_nMach   = zeros(total_operations, 1);
    cached_nFix    = zeros(total_operations, 1);
    k = 0;
    for j = 1:length(job_operation_num)
        for o = 1:job_operation_num(j)
            k = k + 1;
            cached_pos2job(k) = j;
            cached_pos2op(k)  = o;
            cached_nMach(k)   = size(machine_data{j}{o}, 1);
            cached_nFix(k)    = size(fixture_data{j}{o}, 1);
        end
    end
end
nMach_tbl = cached_nMach;
nFix_tbl  = cached_nFix;

%% 1. 机器编码变异（一次性生成掩码）
% 先生成掩码，再只处理有变异的位置
M_mask = rand(pop_size, len_machine) < mutation_prob;
[rows, cols] = find(M_mask);
for ii = 1:numel(rows)
    r = rows(ii); c = cols(ii);
    n = nMach_tbl(c);
    if n > 1
        cur = pop_muted(r, c);
        % 等价于 setdiff(1:n, cur) 中随机选一个：从 1..n-1 中选后跳过 cur
        pick = randi(n - 1);
        if pick >= cur, pick = pick + 1; end
        pop_muted(r, c) = pick;
    end
end

%% 2. 夹具编码变异
F_mask = rand(pop_size, len_fixture) < mutation_prob;
[rows, cols] = find(F_mask);
for ii = 1:numel(rows)
    r = rows(ii); c = cols(ii);
    n = nFix_tbl(c);
    if n > 1
        col_abs = offset_fixture + c;
        cur = pop_muted(r, col_abs);
        pick = randi(n - 1);
        if pick >= cur, pick = pick + 1; end
        pop_muted(r, col_abs) = pick;
    end
end

%% 3. 库位编码变异（邻域微调 ±1~3）
L_mask = rand(pop_size, len_location) < mutation_prob;
[rows, cols] = find(L_mask);
for ii = 1:numel(rows)
    r = rows(ii); c = cols(ii);
    col_abs = offset_location + c;
    new_ls = pop_muted(r, col_abs) + randi([-10, 10]);
    if new_ls < 1, new_ls = 1; end
    if new_ls > num_Line_side, new_ls = num_Line_side; end
    pop_muted(r, col_abs) = new_ls;
end

%% 4. 工序排序编码变异（每个个体概率 mutation_prob 触发一次）
% 这部分原本就是每个个体一次判定，无需掩码优化
for i = 1:pop_size
    if rand() < mutation_prob
        sched_start = offset_schedule + 1;
        sched_end   = offset_schedule + len_schedule;
        sched = pop_muted(i, sched_start:sched_end);

        r = rand();
        if r < 0.33
            % 交换
            pos1 = randi(len_schedule);
            pos2 = randi(len_schedule);
            while pos1 == pos2, pos2 = randi(len_schedule); end
            temp = sched(pos1);
            sched(pos1) = sched(pos2);
            sched(pos2) = temp;

        elseif r < 0.66
            % 插入
            pos1 = randi(len_schedule);
            pos2 = randi(len_schedule);
            while pos1 == pos2, pos2 = randi(len_schedule); end
            gene = sched(pos1);
            sched(pos1) = [];
            if pos2 > pos1
                pos2 = pos2 - 1;
            end
            sched = [sched(1:pos2-1), gene, sched(pos2:end)];

        else
            % 逆序
            pts = sort(randperm(len_schedule, 2));
            sched(pts(1):pts(2)) = fliplr(sched(pts(1):pts(2)));
        end

        pop_muted(i, sched_start:sched_end) = sched;
    end
end
end