function [schedule, makespan] = decode_makespan(pop, num_machines, machine_data, fixture_data, job_operation_num, num_fixture_types)
    % 解码遗传算法个体（性能优化版，逻辑与原版完全等价）
    %
    % 优化要点：
    %   1) layout 持久化缓存，避免每次 decode 都重建
    %   2) 结构体数组改为平铺数值数组，字段访问开销降低一个数量级
    %   3) schedule table 在末尾一次性构造，避免循环中的 table 索引
    %   4) 用整数位置代码替代字符串比较
    %
    % 包含修复：步骤 2.2b 夹具就位检查（防止夹具瞬移）

    %% 0. 持久化缓存（按 num_machines + machine_data 指纹缓存）
    persistent cached_num_machines cached_layout cached_md_fp cached_avg_pt cached_factor
    
    cur_factor = get_rgv_speed_factor();
    
    % 计算 machine_data 的简易指纹（用第一个工件的总加工时间）
    md_fp = 0;
    for jj = 1:length(machine_data)
        for oo = 1:length(machine_data{jj})
            md_fp = md_fp + sum(machine_data{jj}{oo}(:, end));
        end
    end
    
    need_rebuild = isempty(cached_layout) || cached_num_machines ~= num_machines ...
                   || ~isequal(cached_md_fp, md_fp) || cached_factor ~= cur_factor;
    if need_rebuild
        % 计算平均加工时间
        all_times = [];
        for jj = 1:length(machine_data)
            for oo = 1:length(machine_data{jj})
                all_times = [all_times; machine_data{jj}{oo}(:, end)]; %#ok<AGROW>
            end
        end
        cached_avg_pt = mean(all_times);
        rgv_speed_dynamic = cached_avg_pt * cur_factor;
        if rgv_speed_dynamic <= 0, rgv_speed_dynamic = 20; end
        
        cached_layout = create_layout_info(num_machines, rgv_speed_dynamic);
        cached_num_machines = num_machines;
        cached_md_fp = md_fp;
        cached_factor = cur_factor;
    end
    layout = cached_layout;
    rgv_speed = layout.RGV_speed;
    dist_table = layout.dist_table;
    num_LS = layout.num_Line_side;

    % 位置类型常量
    LOC_LOAD = 1;
    LOC_MACH = 2;
    LOC_LS   = 3;

    %% 1. 解析编码
    total_ops = length(pop) / 4;
    machine_code   = pop(1:total_ops);
    fixture_code   = pop(total_ops+1:2*total_ops);
    line_side_code = pop(2*total_ops+1:3*total_ops);
    schedule_code  = pop(3*total_ops+1:4*total_ops);

    %% 2. 工序信息
    [job_info, op_map] = get_job_operation_info(total_ops, schedule_code, job_operation_num);

    %% 3. 初始化平铺状态数组
    % 机器
    ms_busy_until    = zeros(num_machines, 1);
    ms_current_job   = zeros(num_machines, 1);
    ms_current_op    = zeros(num_machines, 1);
    ms_current_fix   = zeros(num_machines, 1);
    ms_line_side_dst = zeros(num_machines, 1);

    % 夹具（num_fixture_types 由 read_production_data 直接提供）
    num_fixtures = num_fixture_types;
    fs_busy_until   = zeros(num_fixtures, 1);
    fs_location     = ones(num_fixtures, 1);
    fs_location_id  = ones(num_fixtures, 1);
    fs_attached_job = zeros(num_fixtures, 1);

    % 线边库
    line_side_status    = zeros(num_LS, 1);
    line_side_available = zeros(num_LS, 1);
    line_side_fixture   = zeros(num_LS, 1);

    % 工件
    max_jobs = length(job_operation_num);
    js_current_op   = zeros(max_jobs, 1); 
    js_location     = ones(max_jobs, 1);
    js_location_id  = ones(max_jobs, 1);
    js_current_fix  = zeros(max_jobs, 1);
    js_ready_time   = zeros(max_jobs, 1);
    js_completed    = false(max_jobs, 1); 

    % RGV
    rgv_loc_type = LOC_LOAD;
    rgv_loc_id   = 1;
    rgv_avail    = 0;

    %% 4. 输出累计数组
    out_JobID         = zeros(total_ops, 1);
    out_Operation     = zeros(total_ops, 1);
    out_Machine       = zeros(total_ops, 1);
    out_Fixture       = zeros(total_ops, 1);
    out_LineSide      = zeros(total_ops, 1);
    out_StartTime     = zeros(total_ops, 1);
    out_EndTime       = zeros(total_ops, 1);
    out_WaitTime      = zeros(total_ops, 1);
    out_TransportTime = zeros(total_ops, 1);

    %% 5. 主循环
    for seq = 1:total_ops
        job_id   = job_info.job_ids(seq);
        op_num   = job_info.op_nums(seq);
        code_idx = op_map(seq);

        [~, ~, ~, ~, line_side_id, machine_id, processing_time, fixture_id] = ...
            get_operation_info(seq, code_idx, machine_code, fixture_code, line_side_code, ...
                              job_info, machine_data, fixture_data);

        t = max(js_ready_time(job_id), rgv_avail);

        % --- 步骤1：等待机器空闲 ---
        if ms_busy_until(machine_id) > t
            t = ms_busy_until(machine_id);
        end

        % =========================================================
        % 步骤2.1：搬走机器上残留工件
        % =========================================================
        if ms_current_job(machine_id) > 0
            old_job_id     = ms_current_job(machine_id);
            old_fixture_id = ms_current_fix(machine_id);
            dest_ls        = ms_line_side_dst(machine_id);

            if rgv_avail > t, t = rgv_avail; end

            old_op_num    = ms_current_op(machine_id);
            total_job_ops = job_operation_num(old_job_id);

            if old_op_num >= total_job_ops
                move_to_type = LOC_LOAD;
                move_to_id   = 1;
            else
                move_to_type = LOC_LS;
                move_to_id   = dest_ls;
            end

            d1 = dist_table(rgv_loc_type, rgv_loc_id, LOC_MACH, machine_id);
            t1 = t + d1 / rgv_speed;
            d2 = dist_table(LOC_MACH, machine_id, move_to_type, move_to_id);
            t2 = t1 + d2 / rgv_speed;

            rgv_avail    = t2;
            rgv_loc_type = move_to_type;
            rgv_loc_id   = move_to_id;

            if move_to_type == LOC_LOAD
                js_location(old_job_id)    = LOC_LOAD;
                js_location_id(old_job_id) = 1;
                js_ready_time(old_job_id)  = t2;
                js_completed(old_job_id)   = true;
                if old_fixture_id > 0
                    fs_busy_until(old_fixture_id)   = t2;
                    fs_location(old_fixture_id)     = LOC_LOAD;
                    fs_location_id(old_fixture_id)  = 1;
                    fs_attached_job(old_fixture_id) = 0;
                end
            else
                js_location(old_job_id)    = LOC_LS;
                js_location_id(old_job_id) = move_to_id;
                js_ready_time(old_job_id)  = t2;
                if old_fixture_id > 0
                    fs_busy_until(old_fixture_id)  = t2;
                    fs_location(old_fixture_id)    = LOC_LS;
                    fs_location_id(old_fixture_id) = move_to_id;
                end
                line_side_status(move_to_id)    = old_job_id;
                line_side_available(move_to_id) = t2;
                line_side_fixture(move_to_id)   = old_fixture_id;
            end

            ms_current_job(machine_id)   = 0;
            ms_current_op(machine_id)    = 0;
            ms_current_fix(machine_id)   = 0;
            ms_line_side_dst(machine_id) = 0;

            t = t2;
        end

        % =========================================================
        % 步骤2.1b：若当前工件仍滞留在上一台机器上，先搬离
        % 这是步骤2.1的对偶：2.1从"目标机器"视角腾位子，2.1b从"工件"视角让它离开原机器。
        % 修复"前一道工序未完成，下一道已在另一台机器开始"的Bug。
        % 前提：工件当前位置是机器，且不是当前目标机器本身（后者由2.1处理）。
        % =========================================================
        if js_location(job_id) == LOC_MACH && js_location_id(job_id) ~= machine_id
            src_m = js_location_id(job_id);
            % 再次确认该机器上的 current_job 确实就是本工件
            if ms_current_job(src_m) == job_id
                src_fixture_id = ms_current_fix(src_m);
                src_dest_ls    = ms_line_side_dst(src_m);
                src_op_num     = ms_current_op(src_m);
                src_total_ops  = job_operation_num(job_id);

                % 必须等上一道工序加工完成
                if ms_busy_until(src_m) > t, t = ms_busy_until(src_m); end
                if rgv_avail > t, t = rgv_avail; end

                % 目的地：若 src_op 是最后一道工序则运回装载站，否则运到对应线边库
                % 正常情况下这里 src_op_num < src_total_ops（因为还有 op_num 要做）
                if src_op_num >= src_total_ops
                    mv_type = LOC_LOAD;
                    mv_id   = 1;
                else
                    mv_type = LOC_LS;
                    mv_id   = src_dest_ls;
                end

                d1 = dist_table(rgv_loc_type, rgv_loc_id, LOC_MACH, src_m);
                t1 = t + d1 / rgv_speed;
                d2 = dist_table(LOC_MACH, src_m, mv_type, mv_id);
                t2b = t1 + d2 / rgv_speed;

                rgv_avail    = t2b;
                rgv_loc_type = mv_type;
                rgv_loc_id   = mv_id;

                if mv_type == LOC_LOAD
                    js_location(job_id)    = LOC_LOAD;
                    js_location_id(job_id) = 1;
                    js_ready_time(job_id)  = t2b;
                    js_completed(job_id)   = true;
                    if src_fixture_id > 0
                        fs_busy_until(src_fixture_id)   = t2b;
                        fs_location(src_fixture_id)     = LOC_LOAD;
                        fs_location_id(src_fixture_id)  = 1;
                        fs_attached_job(src_fixture_id) = 0;
                    end
                else
                    js_location(job_id)    = LOC_LS;
                    js_location_id(job_id) = mv_id;
                    js_ready_time(job_id)  = t2b;
                    if src_fixture_id > 0
                        fs_busy_until(src_fixture_id)  = t2b;
                        fs_location(src_fixture_id)    = LOC_LS;
                        fs_location_id(src_fixture_id) = mv_id;
                    end
                    line_side_status(mv_id)    = job_id;
                    line_side_available(mv_id) = t2b;
                    line_side_fixture(mv_id)   = src_fixture_id;
                end

                % 清空源机器
                ms_current_job(src_m)   = 0;
                ms_current_op(src_m)    = 0;
                ms_current_fix(src_m)   = 0;
                ms_line_side_dst(src_m) = 0;

                t = t2b;
            else
                % 机器上记录的 current_job 已经不是本工件了（可能早前被搬走但
                % js_location 没同步更新）——这种情况属于状态不一致，强制同步。
                % 正常流程下不应触及此分支。
                js_location(job_id)    = LOC_LOAD;
                js_location_id(job_id) = 1;
            end
        end

        % =========================================================
        % 步骤2.2：若所需夹具被别的工件占用，先释放
        % =========================================================
        if fixture_id > 0 && fs_attached_job(fixture_id) > 0 && ...
           fs_attached_job(fixture_id) ~= job_id

            bound_job    = fs_attached_job(fixture_id);
            fix_location = fs_location(fixture_id);
            fix_loc_id   = fs_location_id(fixture_id);

            if fix_location == LOC_MACH
                % 情况B：夹具在某台机器上
                fixture_machine_id = fix_loc_id;

                if ms_busy_until(fixture_machine_id) > t, t = ms_busy_until(fixture_machine_id); end
                if rgv_avail > t, t = rgv_avail; end

                bound_op_num    = ms_current_op(fixture_machine_id);
                bound_total_ops = job_operation_num(bound_job);
                bound_dest_ls   = ms_line_side_dst(fixture_machine_id);

                if bound_op_num >= bound_total_ops
                    move_to_type = LOC_LOAD;
                    move_to_id   = 1;
                else
                    move_to_type = LOC_LS;
                    move_to_id   = bound_dest_ls;
                end

                d1 = dist_table(rgv_loc_type, rgv_loc_id, LOC_MACH, fixture_machine_id);
                t1 = t + d1 / rgv_speed;
                d2 = dist_table(LOC_MACH, fixture_machine_id, move_to_type, move_to_id);
                t_dest_done = t1 + d2 / rgv_speed;

                rgv_avail    = t_dest_done;
                rgv_loc_type = move_to_type;
                rgv_loc_id   = move_to_id;

                if move_to_type == LOC_LOAD
                    js_location(bound_job)    = LOC_LOAD;
                    js_location_id(bound_job) = 1;
                    js_ready_time(bound_job)  = t_dest_done;
                    js_completed(bound_job)   = true;
                    js_current_fix(bound_job) = 0;
                    fs_busy_until(fixture_id)   = t_dest_done;
                    fs_location(fixture_id)     = LOC_LOAD;
                    fs_location_id(fixture_id)  = 1;
                    fs_attached_job(fixture_id) = 0;
                else
                    js_location(bound_job)    = LOC_LS;
                    js_location_id(bound_job) = move_to_id;
                    js_ready_time(bound_job)  = t_dest_done;
                    fs_busy_until(fixture_id)  = t_dest_done;
                    fs_location(fixture_id)    = LOC_LS;
                    fs_location_id(fixture_id) = move_to_id;
                    line_side_status(move_to_id)    = bound_job;
                    line_side_available(move_to_id) = t_dest_done;
                    line_side_fixture(move_to_id)   = fixture_id;

                    % 把夹具从线边库运回装载站释放
                    t2x = t_dest_done;
                    if rgv_avail > t2x, t2x = rgv_avail; end
                    d3 = dist_table(rgv_loc_type, rgv_loc_id, LOC_LS, move_to_id);
                    t3 = t2x + d3 / rgv_speed;
                    d4 = dist_table(LOC_LS, move_to_id, LOC_LOAD, 1);
                    t_back_done = t3 + d4 / rgv_speed;

                    rgv_avail    = t_back_done;
                    rgv_loc_type = LOC_LOAD;
                    rgv_loc_id   = 1;

                    fs_busy_until(fixture_id)   = t_back_done;
                    fs_location(fixture_id)     = LOC_LOAD;
                    fs_location_id(fixture_id)  = 1;
                    fs_attached_job(fixture_id) = 0;
                    js_current_fix(bound_job)   = 0;
                    line_side_fixture(move_to_id) = 0;

                    t_dest_done = t_back_done;
                end

                ms_current_job(fixture_machine_id)   = 0;
                ms_current_op(fixture_machine_id)    = 0;
                ms_current_fix(fixture_machine_id)   = 0;
                ms_line_side_dst(fixture_machine_id) = 0;

                t = t_dest_done;

            else
                % 情况A：夹具在线边库（或装载站）上绑着别的工件
                if fs_busy_until(fixture_id) > t, t = fs_busy_until(fixture_id); end
                if rgv_avail > t, t = rgv_avail; end

                d1 = dist_table(rgv_loc_type, rgv_loc_id, fix_location, fix_loc_id);
                t1 = t + d1 / rgv_speed;
                d2 = dist_table(fix_location, fix_loc_id, LOC_LOAD, 1);
                t_back_done = t1 + d2 / rgv_speed;

                rgv_avail    = t_back_done;
                rgv_loc_type = LOC_LOAD;
                rgv_loc_id   = 1;

                fs_busy_until(fixture_id)   = t_back_done;
                fs_location(fixture_id)     = LOC_LOAD;
                fs_location_id(fixture_id)  = 1;
                fs_attached_job(fixture_id) = 0;

                js_location(bound_job)    = LOC_LOAD;
                js_location_id(bound_job) = 1;
                js_ready_time(bound_job)  = t_back_done;
                js_current_fix(bound_job) = 0;

                if fix_location == LOC_LS
                    line_side_status(fix_loc_id)    = 0;
                    line_side_available(fix_loc_id) = t_back_done;
                    line_side_fixture(fix_loc_id)   = 0;
                end

                t = t_back_done;
            end
        end

        % =========================================================
        % 步骤2.2b：夹具就位检查
        % =========================================================
        if fixture_id > 0
            jl_code = js_location(job_id);
            jl_id   = js_location_id(job_id);
            fl_code = fs_location(fixture_id);
            fl_id   = fs_location_id(fixture_id);
            if jl_code == LOC_LOAD, jl_id = 1; end
            if fl_code == LOC_LOAD, fl_id = 1; end

            if jl_code ~= fl_code || jl_id ~= fl_id
                if fs_busy_until(fixture_id) > t, t = fs_busy_until(fixture_id); end
                if rgv_avail > t, t = rgv_avail; end

                dA = dist_table(rgv_loc_type, rgv_loc_id, fl_code, fl_id);
                tA = t + dA / rgv_speed;
                dB = dist_table(fl_code, fl_id, jl_code, jl_id);
                tB = tA + dB / rgv_speed;

                rgv_avail    = tB;
                rgv_loc_type = jl_code;
                rgv_loc_id   = jl_id;

                if fl_code == LOC_LS && line_side_fixture(fl_id) == fixture_id
                    line_side_fixture(fl_id) = 0;
                end

                fs_location(fixture_id)    = jl_code;
                fs_location_id(fixture_id) = jl_id;
                fs_busy_until(fixture_id)  = tB;
                if jl_code == LOC_LS
                    line_side_fixture(jl_id) = fixture_id;
                end

                t = tB;
            end
        end

        % =========================================================
        % 步骤2.3：运输工件+夹具到机器
        % =========================================================
        if rgv_avail > t, t = rgv_avail; end

        job_loc    = js_location(job_id);
        job_loc_id = js_location_id(job_id);

        if job_loc == LOC_LS
            from_type = LOC_LS;
            from_id   = job_loc_id;
        else
            from_type = LOC_LOAD;
            from_id   = 1;
        end

        d1 = dist_table(rgv_loc_type, rgv_loc_id, from_type, from_id);
        time1 = d1 / rgv_speed;
        t_rgv_at_from = t + time1;

        d2 = dist_table(from_type, from_id, LOC_MACH, machine_id);
        time2 = d2 / rgv_speed;
        t_arrive_machine = t_rgv_at_from + time2;

        total_transport_time = time1 + time2;

        rgv_avail    = t_arrive_machine;
        rgv_loc_type = LOC_MACH;
        rgv_loc_id   = machine_id;

        if job_loc == LOC_LS
            line_side_status(job_loc_id)  = 0;
            line_side_fixture(job_loc_id) = 0;
        end

        if fixture_id > 0
            fs_attached_job(fixture_id) = job_id;
            fs_location(fixture_id)     = LOC_MACH;
            fs_location_id(fixture_id)  = machine_id;
        end
        js_current_fix(job_id) = fixture_id;

        % --- 加工 ---
        start_time = t_arrive_machine;
        end_time   = start_time + processing_time;
        wait_time  = start_time - js_ready_time(job_id);
        if wait_time < 0, wait_time = 0; end

        out_JobID(seq)         = job_id;
        out_Operation(seq)     = op_num;
        out_Machine(seq)       = machine_id;
        out_Fixture(seq)       = fixture_id;
        out_LineSide(seq)      = line_side_id;
        out_StartTime(seq)     = start_time;
        out_EndTime(seq)       = end_time;
        out_WaitTime(seq)      = wait_time;
        out_TransportTime(seq) = total_transport_time;

        ms_busy_until(machine_id)    = end_time;
        ms_current_job(machine_id)   = job_id;
        ms_current_op(machine_id)    = op_num;
        ms_current_fix(machine_id)   = fixture_id;
        ms_line_side_dst(machine_id) = line_side_id;

        js_current_op(job_id)  = op_num; 
        js_location(job_id)    = LOC_MACH;
        js_location_id(job_id) = machine_id;
        js_ready_time(job_id)  = end_time;

        if fixture_id > 0
            fs_busy_until(fixture_id) = end_time;
        end
    end

    %% 6. 收尾
    final_time = max(out_EndTime);

    for m = 1:num_machines
        if ms_current_job(m) > 0
            old_job_id     = ms_current_job(m);
            old_fixture_id = ms_current_fix(m);
            old_op_num     = ms_current_op(m);
            dest_ls        = ms_line_side_dst(m);

            t_final = ms_busy_until(m);
            if rgv_avail > t_final, t_final = rgv_avail; end

            total_job_ops = job_operation_num(old_job_id);
            if old_op_num >= total_job_ops
                move_to_type = LOC_LOAD;
                move_to_id   = 1;
            else
                move_to_type = LOC_LS;
                move_to_id   = dest_ls;
            end

            d1 = dist_table(rgv_loc_type, rgv_loc_id, LOC_MACH, m);
            t1 = t_final + d1 / rgv_speed;
            d2 = dist_table(LOC_MACH, m, move_to_type, move_to_id);
            t_done = t1 + d2 / rgv_speed;

            rgv_avail    = t_done;
            rgv_loc_type = move_to_type;
            rgv_loc_id   = move_to_id;

            if move_to_type == LOC_LOAD
                js_completed(old_job_id) = true; 
                if old_fixture_id > 0
                    fs_location(old_fixture_id)     = LOC_LOAD;
                    fs_location_id(old_fixture_id)  = 1;
                    fs_attached_job(old_fixture_id) = 0;
                end
            else
                js_location(old_job_id)    = LOC_LS;
                js_location_id(old_job_id) = move_to_id;
                if old_fixture_id > 0
                    fs_location(old_fixture_id)    = LOC_LS;
                    fs_location_id(old_fixture_id) = move_to_id;
                end
                line_side_status(move_to_id)  = old_job_id;
                line_side_fixture(move_to_id) = old_fixture_id;
            end

            ms_current_job(m) = 0;
            ms_current_op(m)  = 0;
            ms_current_fix(m) = 0;

            if t_done > final_time, final_time = t_done; end
        end
    end

    %% 7. 输出
    makespan = final_time;
    schedule = table( ...
        (1:total_ops)', out_JobID, out_Operation, out_Machine, out_Fixture, ...
        out_LineSide, out_StartTime, out_EndTime, out_WaitTime, out_TransportTime, ...
        'VariableNames', {'OperationID','JobID','Operation','Machine','Fixture', ...
                          'LineSide','StartTime','EndTime','WaitTime','TransportTime'});
end

%% ========================================================================
function d = dist_table(from_type_code, from_id, to_type_code, to_id)
    persistent type_strs
    if isempty(type_strs)
        type_strs = {'loading', 'machine', 'line_side'};
    end
    d = layout.get_distance({type_strs{from_type_code}, from_id}, ...
                            {type_strs{to_type_code},   to_id});
end
