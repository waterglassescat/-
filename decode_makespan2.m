function [schedule, makespan, rgv_log] = decode_makespan2(pop, num_machines, machine_data, fixture_data, job_operation_num, num_fixture_types)
    % 解码遗传算法个体（详细版），在解码的同时记录RGV每一次转移的完整信息
    % 输入：（与decode_makespan相同）
    % 输出：
    %   schedule: 调度结果表格
    %   makespan: 总完工时间
    %   rgv_log:  RGV运输日志表格

    %% 1. 获取布局信息（与 decode_makespan 保持一致的动态 RGV 速度）
    cur_factor = get_rgv_speed_factor();
    all_times = [];
    for jj = 1:length(machine_data)
        for oo = 1:length(machine_data{jj})
            all_times = [all_times; machine_data{jj}{oo}(:, end)]; %#ok<AGROW>
        end
    end
    rgv_speed_dynamic = mean(all_times) * cur_factor;
    if rgv_speed_dynamic <= 0, rgv_speed_dynamic = 20; end
    layout = create_layout_info(num_machines, rgv_speed_dynamic);

    %% 2. 解析编码
    total_ops = length(pop) / 4;
    machine_code   = pop(1:total_ops);
    fixture_code   = pop(total_ops+1:2*total_ops);
    line_side_code = pop(2*total_ops+1:3*total_ops);
    schedule_code  = pop(3*total_ops+1:4*total_ops);

    %% 3. 工序信息
    [job_info, op_map] = get_job_operation_info(total_ops, schedule_code, job_operation_num);

    %% 4. 初始化数据结构
    machine_status = struct();
    for m = 1:num_machines
        machine_status(m).busy_until = 0;
        machine_status(m).current_job = 0;
        machine_status(m).current_op = 0;
        machine_status(m).current_fixture = 0;
        machine_status(m).completed_code_idx = 0;
        machine_status(m).line_side_dest = 0;
    end

    % 注意：num_fixture_types 由 read_production_data 直接提供
    num_fixtures = num_fixture_types;
    fixture_status = struct();
    for f = 1:num_fixtures
        fixture_status(f).busy_until = 0;
        fixture_status(f).location = 1;
        fixture_status(f).location_id = 1;
        fixture_status(f).attached_job = 0;
    end

    line_side_status = zeros(layout.num_Line_side, 1);
    line_side_available = zeros(layout.num_Line_side, 1);
    line_side_fixture = zeros(layout.num_Line_side, 1);

    max_jobs = length(job_operation_num);
    job_status = struct();
    for j = 1:max_jobs
        job_status(j).current_op = 0;
        job_status(j).current_location = 1;
        job_status(j).location_id = 1;
        job_status(j).current_fixture = 0;
        job_status(j).ready_time = 0;
        job_status(j).completed = false;
    end

    rgv_status = struct();
    rgv_status.current_location = 1;
    rgv_status.current_location_type = 'loading';
    rgv_status.available_time = 0;

    %% 5. 调度结果表
    schedule = table();
    schedule.OperationID   = (1:total_ops)';
    schedule.JobID         = zeros(total_ops, 1);
    schedule.Operation     = zeros(total_ops, 1);
    schedule.Machine       = zeros(total_ops, 1);
    schedule.Fixture       = zeros(total_ops, 1);
    schedule.LineSide      = zeros(total_ops, 1);
    schedule.StartTime     = zeros(total_ops, 1);
    schedule.EndTime       = zeros(total_ops, 1);
    schedule.WaitTime      = zeros(total_ops, 1);
    schedule.TransportTime = zeros(total_ops, 1);

    %% 7. RGV日志预分配（增大以容纳新增的 reposition_fixture 任务）
    max_log_entries = total_ops * 10;
    log_TaskID       = zeros(max_log_entries, 1);
    log_TaskType     = cell(max_log_entries, 1);
    log_Phase        = cell(max_log_entries, 1);
    log_JobID        = zeros(max_log_entries, 1);
    log_FixtureID    = zeros(max_log_entries, 1);
    log_FromType     = cell(max_log_entries, 1);
    log_FromID       = zeros(max_log_entries, 1);
    log_ToType       = cell(max_log_entries, 1);
    log_ToID         = zeros(max_log_entries, 1);
    log_StartTime    = zeros(max_log_entries, 1);
    log_EndTime      = zeros(max_log_entries, 1);
    log_Duration     = zeros(max_log_entries, 1);
    log_Distance     = zeros(max_log_entries, 1);
    log_TriggerOpIdx = zeros(max_log_entries, 1);
    log_count = 0;

    %% 8. 主循环
    for seq = 1:total_ops
        job_id   = job_info.job_ids(seq);
        op_num   = job_info.op_nums(seq);
        code_idx = op_map(seq);

        [~, ~, ~, ~, line_side_id, machine_id, processing_time, fixture_id] = ...
            get_operation_info(seq, code_idx, machine_code, fixture_code, line_side_code, ...
                              job_info, machine_data, fixture_data);

        t = max(job_status(job_id).ready_time, rgv_status.available_time);

        % --- 步骤1：等待机器空闲 ---
        if machine_status(machine_id).busy_until > t
            t = machine_status(machine_id).busy_until;
        end

        % =====================================================================
        % 步骤2.1：搬走机器上残留的旧工件
        % =====================================================================
        if machine_status(machine_id).current_job > 0
            old_job_id       = machine_status(machine_id).current_job;
            old_fixture_id   = machine_status(machine_id).current_fixture;
            dest_ls          = machine_status(machine_id).line_side_dest;

            t = max(t, rgv_status.available_time);

            old_op_num    = machine_status(machine_id).current_op;
            total_job_ops = job_operation_num(old_job_id);

            if old_op_num >= total_job_ops
                move_to_type = 'loading';
                move_to_id   = 1;
            else
                move_to_type = 'line_side';
                move_to_id   = dest_ls;
            end

            % --- RGV第一段：空跑到机器 ---
            rgv_from_type = rgv_status.current_location_type;
            rgv_from_id   = rgv_status.current_location;
            dist1 = layout.get_distance({rgv_from_type, rgv_from_id}, {'machine', machine_id});
            time1 = dist1 / layout.RGV_speed;
            t_rgv_at_machine = t + time1;

            log_count = log_count + 1;
            log_TaskID(log_count)       = log_count;
            log_TaskType{log_count}     = 'clear_machine';
            log_Phase{log_count}        = 'travel_to_pickup';
            log_JobID(log_count)        = 0;
            log_FixtureID(log_count)    = 0;
            log_FromType{log_count}     = rgv_from_type;
            log_FromID(log_count)       = rgv_from_id;
            log_ToType{log_count}       = 'machine';
            log_ToID(log_count)         = machine_id;
            log_StartTime(log_count)    = t;
            log_EndTime(log_count)      = t_rgv_at_machine;
            log_Duration(log_count)     = time1;
            log_Distance(log_count)     = dist1;
            log_TriggerOpIdx(log_count) = code_idx;

            % --- RGV第二段：载货到目的地 ---
            dist2 = layout.get_distance({'machine', machine_id}, {move_to_type, move_to_id});
            time2 = dist2 / layout.RGV_speed;
            t_transport_done = t_rgv_at_machine + time2;

            log_count = log_count + 1;
            log_TaskID(log_count)       = log_count;
            log_TaskType{log_count}     = 'clear_machine';
            log_Phase{log_count}        = 'carry_to_dest';
            log_JobID(log_count)        = old_job_id;
            log_FixtureID(log_count)    = old_fixture_id;
            log_FromType{log_count}     = 'machine';
            log_FromID(log_count)       = machine_id;
            log_ToType{log_count}       = move_to_type;
            log_ToID(log_count)         = move_to_id;
            log_StartTime(log_count)    = t_rgv_at_machine;
            log_EndTime(log_count)      = t_transport_done;
            log_Duration(log_count)     = time2;
            log_Distance(log_count)     = dist2;
            log_TriggerOpIdx(log_count) = code_idx;

            % 更新RGV
            rgv_status.available_time = t_transport_done;
            rgv_status.current_location_type = move_to_type;
            rgv_status.current_location = move_to_id;

            % 更新旧工件
            if strcmp(move_to_type, 'loading')
                job_status(old_job_id).current_location = 1;
                job_status(old_job_id).location_id = 1;
                job_status(old_job_id).ready_time = t_transport_done;
                job_status(old_job_id).completed = true;
                if old_fixture_id > 0
                    fixture_status(old_fixture_id).busy_until = t_transport_done;
                    fixture_status(old_fixture_id).location = 1;
                    fixture_status(old_fixture_id).location_id = 1;
                    fixture_status(old_fixture_id).attached_job = 0;
                end
            else
                job_status(old_job_id).current_location = 3;
                job_status(old_job_id).location_id = move_to_id;
                job_status(old_job_id).ready_time = t_transport_done;
                if old_fixture_id > 0
                    fixture_status(old_fixture_id).busy_until = t_transport_done;
                    fixture_status(old_fixture_id).location = 3;
                    fixture_status(old_fixture_id).location_id = move_to_id;
                end
                line_side_status(move_to_id) = old_job_id;
                line_side_available(move_to_id) = t_transport_done;
                line_side_fixture(move_to_id) = old_fixture_id;
            end

            machine_status(machine_id).current_job = 0;
            machine_status(machine_id).current_op = 0;
            machine_status(machine_id).current_fixture = 0;
            machine_status(machine_id).completed_code_idx = 0;
            machine_status(machine_id).line_side_dest = 0;

            t = t_transport_done;
        end

        % =====================================================================
        % 步骤2.1b：【新增】若当前工件仍滞留在上一台机器上，先搬离
        % 修复"前一道工序未完成，下一道已在另一台机器开始"的Bug。
        % 这是步骤2.1的对偶：2.1从"目标机器"视角腾位子，2.1b从"工件"视角让
        % 它离开原机器。前提：工件当前位置是机器，且不是当前目标机器本身。
        % =====================================================================
        if job_status(job_id).current_location == 2 && ...
           job_status(job_id).location_id ~= machine_id
            src_m = job_status(job_id).location_id;
            if machine_status(src_m).current_job == job_id
                src_fixture_id = machine_status(src_m).current_fixture;
                src_dest_ls    = machine_status(src_m).line_side_dest;
                src_op_num     = machine_status(src_m).current_op;
                src_total_ops  = job_operation_num(job_id);

                % 必须等上一道工序加工完成
                t = max(t, machine_status(src_m).busy_until);
                t = max(t, rgv_status.available_time);

                if src_op_num >= src_total_ops
                    src_move_to_type = 'loading';
                    src_move_to_id   = 1;
                else
                    src_move_to_type = 'line_side';
                    src_move_to_id   = src_dest_ls;
                end

                % --- RGV第一段：空跑到源机器 ---
                rgv_from_type = rgv_status.current_location_type;
                rgv_from_id   = rgv_status.current_location;
                dist1 = layout.get_distance({rgv_from_type, rgv_from_id}, {'machine', src_m});
                time1 = dist1 / layout.RGV_speed;
                t_rgv_at_src = t + time1;

                log_count = log_count + 1;
                log_TaskID(log_count)       = log_count;
                log_TaskType{log_count}     = 'evacuate_source_machine';
                log_Phase{log_count}        = 'travel_to_pickup';
                log_JobID(log_count)        = 0;
                log_FixtureID(log_count)    = 0;
                log_FromType{log_count}     = rgv_from_type;
                log_FromID(log_count)       = rgv_from_id;
                log_ToType{log_count}       = 'machine';
                log_ToID(log_count)         = src_m;
                log_StartTime(log_count)    = t;
                log_EndTime(log_count)      = t_rgv_at_src;
                log_Duration(log_count)     = time1;
                log_Distance(log_count)     = dist1;
                log_TriggerOpIdx(log_count) = code_idx;

                % --- RGV第二段：载货到目的地 ---
                dist2 = layout.get_distance({'machine', src_m}, {src_move_to_type, src_move_to_id});
                time2 = dist2 / layout.RGV_speed;
                t_src_done = t_rgv_at_src + time2;

                log_count = log_count + 1;
                log_TaskID(log_count)       = log_count;
                log_TaskType{log_count}     = 'evacuate_source_machine';
                log_Phase{log_count}        = 'carry_to_dest';
                log_JobID(log_count)        = job_id;
                log_FixtureID(log_count)    = src_fixture_id;
                log_FromType{log_count}     = 'machine';
                log_FromID(log_count)       = src_m;
                log_ToType{log_count}       = src_move_to_type;
                log_ToID(log_count)         = src_move_to_id;
                log_StartTime(log_count)    = t_rgv_at_src;
                log_EndTime(log_count)      = t_src_done;
                log_Duration(log_count)     = time2;
                log_Distance(log_count)     = dist2;
                log_TriggerOpIdx(log_count) = code_idx;

                % 更新 RGV
                rgv_status.available_time = t_src_done;
                rgv_status.current_location_type = src_move_to_type;
                rgv_status.current_location = src_move_to_id;

                % 更新工件与夹具状态
                if strcmp(src_move_to_type, 'loading')
                    job_status(job_id).current_location = 1;
                    job_status(job_id).location_id = 1;
                    job_status(job_id).ready_time = t_src_done;
                    job_status(job_id).completed = true;
                    if src_fixture_id > 0
                        fixture_status(src_fixture_id).busy_until = t_src_done;
                        fixture_status(src_fixture_id).location = 1;
                        fixture_status(src_fixture_id).location_id = 1;
                        fixture_status(src_fixture_id).attached_job = 0;
                    end
                else
                    job_status(job_id).current_location = 3;
                    job_status(job_id).location_id = src_move_to_id;
                    job_status(job_id).ready_time = t_src_done;
                    if src_fixture_id > 0
                        fixture_status(src_fixture_id).busy_until = t_src_done;
                        fixture_status(src_fixture_id).location = 3;
                        fixture_status(src_fixture_id).location_id = src_move_to_id;
                    end
                    line_side_status(src_move_to_id) = job_id;
                    line_side_available(src_move_to_id) = t_src_done;
                    line_side_fixture(src_move_to_id) = src_fixture_id;
                end

                % 清空源机器
                machine_status(src_m).current_job = 0;
                machine_status(src_m).current_op = 0;
                machine_status(src_m).current_fixture = 0;
                machine_status(src_m).completed_code_idx = 0;
                machine_status(src_m).line_side_dest = 0;

                t = t_src_done;
            else
                % 状态不一致的兜底（正常流程不会到这里）
                job_status(job_id).current_location = 1;
                job_status(job_id).location_id = 1;
            end
        end

        % =====================================================================
        % 步骤2.2：若所需夹具被别的工件占用，需要先释放
        % =====================================================================
        if fixture_id > 0 && fixture_status(fixture_id).attached_job > 0 && ...
           fixture_status(fixture_id).attached_job ~= job_id

            bound_job = fixture_status(fixture_id).attached_job;
            fix_location = fixture_status(fixture_id).location;
            fix_loc_id   = fixture_status(fixture_id).location_id;

            if fix_location == 2
                % ---- 情况B：夹具在某台机器上 ----
                fixture_machine_id = fix_loc_id;

                t = max(t, machine_status(fixture_machine_id).busy_until);
                t = max(t, rgv_status.available_time);

                bound_op_num    = machine_status(fixture_machine_id).current_op;
                bound_total_ops = job_operation_num(bound_job);
                bound_dest_ls   = machine_status(fixture_machine_id).line_side_dest;

                if bound_op_num >= bound_total_ops
                    move_to_type = 'loading';
                    move_to_id   = 1;
                else
                    move_to_type = 'line_side';
                    move_to_id   = bound_dest_ls;
                end

                % --- RGV第一段：空跑到夹具所在的机器 ---
                rgv_from_type = rgv_status.current_location_type;
                rgv_from_id   = rgv_status.current_location;
                dist1 = layout.get_distance({rgv_from_type, rgv_from_id}, {'machine', fixture_machine_id});
                time1 = dist1 / layout.RGV_speed;
                t_rgv_at_fix = t + time1;

                log_count = log_count + 1;
                log_TaskID(log_count)       = log_count;
                log_TaskType{log_count}     = 'release_fixture_from_machine';
                log_Phase{log_count}        = 'travel_to_pickup';
                log_JobID(log_count)        = 0;
                log_FixtureID(log_count)    = 0;
                log_FromType{log_count}     = rgv_from_type;
                log_FromID(log_count)       = rgv_from_id;
                log_ToType{log_count}       = 'machine';
                log_ToID(log_count)         = fixture_machine_id;
                log_StartTime(log_count)    = t;
                log_EndTime(log_count)      = t_rgv_at_fix;
                log_Duration(log_count)     = time1;
                log_Distance(log_count)     = dist1;
                log_TriggerOpIdx(log_count) = code_idx;

                % --- RGV第二段：载着工件+夹具到目的地 ---
                dist2 = layout.get_distance({'machine', fixture_machine_id}, {move_to_type, move_to_id});
                time2 = dist2 / layout.RGV_speed;
                t_dest_done = t_rgv_at_fix + time2;

                log_count = log_count + 1;
                log_TaskID(log_count)       = log_count;
                log_TaskType{log_count}     = 'release_fixture_from_machine';
                log_Phase{log_count}        = 'carry_to_dest';
                log_JobID(log_count)        = bound_job;
                log_FixtureID(log_count)    = fixture_id;
                log_FromType{log_count}     = 'machine';
                log_FromID(log_count)       = fixture_machine_id;
                log_ToType{log_count}       = move_to_type;
                log_ToID(log_count)         = move_to_id;
                log_StartTime(log_count)    = t_rgv_at_fix;
                log_EndTime(log_count)      = t_dest_done;
                log_Duration(log_count)     = time2;
                log_Distance(log_count)     = dist2;
                log_TriggerOpIdx(log_count) = code_idx;

                rgv_status.available_time = t_dest_done;
                rgv_status.current_location_type = move_to_type;
                rgv_status.current_location = move_to_id;

                if strcmp(move_to_type, 'loading')
                    job_status(bound_job).current_location = 1;
                    job_status(bound_job).location_id = 1;
                    job_status(bound_job).ready_time = t_dest_done;
                    job_status(bound_job).completed = true;
                    job_status(bound_job).current_fixture = 0;
                    fixture_status(fixture_id).busy_until = t_dest_done;
                    fixture_status(fixture_id).location = 1;
                    fixture_status(fixture_id).location_id = 1;
                    fixture_status(fixture_id).attached_job = 0;
                else
                    job_status(bound_job).current_location = 3;
                    job_status(bound_job).location_id = move_to_id;
                    job_status(bound_job).ready_time = t_dest_done;
                    fixture_status(fixture_id).busy_until = t_dest_done;
                    fixture_status(fixture_id).location = 3;
                    fixture_status(fixture_id).location_id = move_to_id;
                    line_side_status(move_to_id) = bound_job;
                    line_side_available(move_to_id) = t_dest_done;
                    line_side_fixture(move_to_id) = fixture_id;

                    % 还需要把夹具从线边库运回装载站释放
                    t2 = max(t_dest_done, rgv_status.available_time);

                    % --- RGV第三段：去线边库取夹具 ---
                    dist3 = layout.get_distance({rgv_status.current_location_type, rgv_status.current_location}, ...
                        {'line_side', move_to_id});
                    time3 = dist3 / layout.RGV_speed;
                    t_rgv_at_ls = t2 + time3;

                    log_count = log_count + 1;
                    log_TaskID(log_count)       = log_count;
                    log_TaskType{log_count}     = 'release_fixture_return';
                    log_Phase{log_count}        = 'travel_to_pickup';
                    log_JobID(log_count)        = 0;
                    log_FixtureID(log_count)    = 0;
                    log_FromType{log_count}     = rgv_status.current_location_type;
                    log_FromID(log_count)       = rgv_status.current_location;
                    log_ToType{log_count}       = 'line_side';
                    log_ToID(log_count)         = move_to_id;
                    log_StartTime(log_count)    = t2;
                    log_EndTime(log_count)      = t_rgv_at_ls;
                    log_Duration(log_count)     = time3;
                    log_Distance(log_count)     = dist3;
                    log_TriggerOpIdx(log_count) = code_idx;

                    % --- RGV第四段：载着夹具回装载站 ---
                    dist4 = layout.get_distance({'line_side', move_to_id}, {'loading', 1});
                    time4 = dist4 / layout.RGV_speed;
                    t_back_done = t_rgv_at_ls + time4;

                    log_count = log_count + 1;
                    log_TaskID(log_count)       = log_count;
                    log_TaskType{log_count}     = 'release_fixture_return';
                    log_Phase{log_count}        = 'carry_to_dest';
                    log_JobID(log_count)        = 0;
                    log_FixtureID(log_count)    = fixture_id;
                    log_FromType{log_count}     = 'line_side';
                    log_FromID(log_count)       = move_to_id;
                    log_ToType{log_count}       = 'loading';
                    log_ToID(log_count)         = 1;
                    log_StartTime(log_count)    = t_rgv_at_ls;
                    log_EndTime(log_count)      = t_back_done;
                    log_Duration(log_count)     = time4;
                    log_Distance(log_count)     = dist4;
                    log_TriggerOpIdx(log_count) = code_idx;

                    rgv_status.available_time = t_back_done;
                    rgv_status.current_location_type = 'loading';
                    rgv_status.current_location = 1;

                    fixture_status(fixture_id).busy_until = t_back_done;
                    fixture_status(fixture_id).location = 1;
                    fixture_status(fixture_id).location_id = 1;
                    fixture_status(fixture_id).attached_job = 0;
                    job_status(bound_job).current_fixture = 0;
                    line_side_fixture(move_to_id) = 0;

                    t_dest_done = t_back_done;
                end

                machine_status(fixture_machine_id).current_job = 0;
                machine_status(fixture_machine_id).current_op = 0;
                machine_status(fixture_machine_id).current_fixture = 0;
                machine_status(fixture_machine_id).completed_code_idx = 0;
                machine_status(fixture_machine_id).line_side_dest = 0;

                t = t_dest_done;

            else
                % ---- 情况A：夹具在线边库（或装载站）上绑着别的工件 ----
                t = max(t, fixture_status(fixture_id).busy_until);
                t = max(t, rgv_status.available_time);

                fix_loc_type = get_location_type_str(fix_location);

                % --- RGV第一段：空跑到夹具所在位置 ---
                rgv_from_type = rgv_status.current_location_type;
                rgv_from_id   = rgv_status.current_location;
                dist1 = layout.get_distance({rgv_from_type, rgv_from_id}, {fix_loc_type, fix_loc_id});
                time1 = dist1 / layout.RGV_speed;
                t_rgv_at_fix = t + time1;

                log_count = log_count + 1;
                log_TaskID(log_count)       = log_count;
                log_TaskType{log_count}     = 'release_fixture';
                log_Phase{log_count}        = 'travel_to_pickup';
                log_JobID(log_count)        = 0;
                log_FixtureID(log_count)    = 0;
                log_FromType{log_count}     = rgv_from_type;
                log_FromID(log_count)       = rgv_from_id;
                log_ToType{log_count}       = fix_loc_type;
                log_ToID(log_count)         = fix_loc_id;
                log_StartTime(log_count)    = t;
                log_EndTime(log_count)      = t_rgv_at_fix;
                log_Duration(log_count)     = time1;
                log_Distance(log_count)     = dist1;
                log_TriggerOpIdx(log_count) = code_idx;

                % --- RGV第二段：载着夹具+工件运回装载站 ---
                dist2 = layout.get_distance({fix_loc_type, fix_loc_id}, {'loading', 1});
                time2 = dist2 / layout.RGV_speed;
                t_back_done = t_rgv_at_fix + time2;

                log_count = log_count + 1;
                log_TaskID(log_count)       = log_count;
                log_TaskType{log_count}     = 'release_fixture';
                log_Phase{log_count}        = 'carry_to_dest';
                log_JobID(log_count)        = bound_job;
                log_FixtureID(log_count)    = fixture_id;
                log_FromType{log_count}     = fix_loc_type;
                log_FromID(log_count)       = fix_loc_id;
                log_ToType{log_count}       = 'loading';
                log_ToID(log_count)         = 1;
                log_StartTime(log_count)    = t_rgv_at_fix;
                log_EndTime(log_count)      = t_back_done;
                log_Duration(log_count)     = time2;
                log_Distance(log_count)     = dist2;
                log_TriggerOpIdx(log_count) = code_idx;

                rgv_status.available_time = t_back_done;
                rgv_status.current_location_type = 'loading';
                rgv_status.current_location = 1;

                fixture_status(fixture_id).busy_until = t_back_done;
                fixture_status(fixture_id).location = 1;
                fixture_status(fixture_id).location_id = 1;
                fixture_status(fixture_id).attached_job = 0;

                job_status(bound_job).current_location = 1;
                job_status(bound_job).location_id = 1;
                job_status(bound_job).ready_time = t_back_done;
                job_status(bound_job).current_fixture = 0;

                if fix_location == 3
                    line_side_status(fix_loc_id) = 0;
                    line_side_available(fix_loc_id) = t_back_done;
                    line_side_fixture(fix_loc_id) = 0;
                end

                t = t_back_done;
            end
        end

        % =====================================================================
        % 步骤2.2b：【新增】夹具就位检查
        % 不依赖 attached_job，直接基于物理位置判断；若不在工件处，由 RGV 把
        % 夹具运到工件所在位置。完整记录到 rgv_log。
        % =====================================================================
        if fixture_id > 0
            jl_code = job_status(job_id).current_location;
            jl_id   = job_status(job_id).location_id;
            fl_code = fixture_status(fixture_id).location;
            fl_id   = fixture_status(fixture_id).location_id;

            if jl_code == 1, jl_id = 1; end
            if fl_code == 1, fl_id = 1; end

            same_place = (jl_code == fl_code) && (jl_id == fl_id);

            if ~same_place
                t = max(t, fixture_status(fixture_id).busy_until);
                t = max(t, rgv_status.available_time);

                fl_type = get_location_type_str(fl_code);
                jl_type = get_location_type_str(jl_code);

                % --- RGV第一段：空跑到夹具位置 ---
                rgv_from_type = rgv_status.current_location_type;
                rgv_from_id   = rgv_status.current_location;
                distA = layout.get_distance({rgv_from_type, rgv_from_id}, {fl_type, fl_id});
                timeA = distA / layout.RGV_speed;
                t_rgv_at_fix = t + timeA;

                log_count = log_count + 1;
                log_TaskID(log_count)       = log_count;
                log_TaskType{log_count}     = 'reposition_fixture';
                log_Phase{log_count}        = 'travel_to_pickup';
                log_JobID(log_count)        = 0;
                log_FixtureID(log_count)    = 0;
                log_FromType{log_count}     = rgv_from_type;
                log_FromID(log_count)       = rgv_from_id;
                log_ToType{log_count}       = fl_type;
                log_ToID(log_count)         = fl_id;
                log_StartTime(log_count)    = t;
                log_EndTime(log_count)      = t_rgv_at_fix;
                log_Duration(log_count)     = timeA;
                log_Distance(log_count)     = distA;
                log_TriggerOpIdx(log_count) = code_idx;

                % --- RGV第二段：载夹具到工件位置 ---
                distB = layout.get_distance({fl_type, fl_id}, {jl_type, jl_id});
                timeB = distB / layout.RGV_speed;
                t_fix_at_job = t_rgv_at_fix + timeB;

                log_count = log_count + 1;
                log_TaskID(log_count)       = log_count;
                log_TaskType{log_count}     = 'reposition_fixture';
                log_Phase{log_count}        = 'carry_to_dest';
                log_JobID(log_count)        = 0;
                log_FixtureID(log_count)    = fixture_id;
                log_FromType{log_count}     = fl_type;
                log_FromID(log_count)       = fl_id;
                log_ToType{log_count}       = jl_type;
                log_ToID(log_count)         = jl_id;
                log_StartTime(log_count)    = t_rgv_at_fix;
                log_EndTime(log_count)      = t_fix_at_job;
                log_Duration(log_count)     = timeB;
                log_Distance(log_count)     = distB;
                log_TriggerOpIdx(log_count) = code_idx;

                % 更新RGV
                rgv_status.available_time = t_fix_at_job;
                rgv_status.current_location_type = jl_type;
                rgv_status.current_location = jl_id;

                % 清空夹具原线边库槽
                if fl_code == 3
                    if line_side_fixture(fl_id) == fixture_id
                        line_side_fixture(fl_id) = 0;
                    end
                end

                % 更新夹具物理位置
                fixture_status(fixture_id).location = jl_code;
                fixture_status(fixture_id).location_id = jl_id;
                fixture_status(fixture_id).busy_until = t_fix_at_job;
                if jl_code == 3
                    line_side_fixture(jl_id) = fixture_id;
                end

                t = t_fix_at_job;
            end
        end

        % =====================================================================
        % 步骤2.3：运输当前工件+夹具到机器
        % =====================================================================
        t = max(t, rgv_status.available_time);

        job_loc = job_status(job_id).current_location;
        job_loc_id = job_status(job_id).location_id;

        if job_loc == 3
            from_type = 'line_side';
            from_id   = job_loc_id;
        else
            from_type = 'loading';
            from_id   = 1;
        end

        % --- RGV第一段：空跑到工件位置 ---
        rgv_from_type = rgv_status.current_location_type;
        rgv_from_id   = rgv_status.current_location;
        dist1 = layout.get_distance({rgv_from_type, rgv_from_id}, {from_type, from_id});
        time1 = dist1 / layout.RGV_speed;
        t_rgv_at_from = t + time1;

        log_count = log_count + 1;
        log_TaskID(log_count)       = log_count;
        log_TaskType{log_count}     = 'deliver_to_machine';
        log_Phase{log_count}        = 'travel_to_pickup';
        log_JobID(log_count)        = 0;
        log_FixtureID(log_count)    = 0;
        log_FromType{log_count}     = rgv_from_type;
        log_FromID(log_count)       = rgv_from_id;
        log_ToType{log_count}       = from_type;
        log_ToID(log_count)         = from_id;
        log_StartTime(log_count)    = t;
        log_EndTime(log_count)      = t_rgv_at_from;
        log_Duration(log_count)     = time1;
        log_Distance(log_count)     = dist1;
        log_TriggerOpIdx(log_count) = code_idx;

        % --- RGV第二段：载着工件+夹具送到机器 ---
        dist2 = layout.get_distance({from_type, from_id}, {'machine', machine_id});
        time2 = dist2 / layout.RGV_speed;
        t_arrive_machine = t_rgv_at_from + time2;

        log_count = log_count + 1;
        log_TaskID(log_count)       = log_count;
        log_TaskType{log_count}     = 'deliver_to_machine';
        log_Phase{log_count}        = 'carry_to_dest';
        log_JobID(log_count)        = job_id;
        log_FixtureID(log_count)    = fixture_id;
        log_FromType{log_count}     = from_type;
        log_FromID(log_count)       = from_id;
        log_ToType{log_count}       = 'machine';
        log_ToID(log_count)         = machine_id;
        log_StartTime(log_count)    = t_rgv_at_from;
        log_EndTime(log_count)      = t_arrive_machine;
        log_Duration(log_count)     = time2;
        log_Distance(log_count)     = dist2;
        log_TriggerOpIdx(log_count) = code_idx;

        total_transport_time = time1 + time2;

        rgv_status.available_time = t_arrive_machine;
        rgv_status.current_location_type = 'machine';
        rgv_status.current_location = machine_id;

        if job_loc == 3
            line_side_status(job_loc_id) = 0;
            line_side_fixture(job_loc_id) = 0;
        end

        if fixture_id > 0
            fixture_status(fixture_id).attached_job = job_id;
            fixture_status(fixture_id).location = 2;
            fixture_status(fixture_id).location_id = machine_id;
        end
        job_status(job_id).current_fixture = fixture_id;

        % --- 开始加工 ---
        start_time = t_arrive_machine;
        end_time   = start_time + processing_time;
        wait_time = max(0, start_time - job_status(job_id).ready_time);

        schedule.JobID(seq)         = job_id;
        schedule.Operation(seq)     = op_num;
        schedule.Machine(seq)       = machine_id;
        schedule.Fixture(seq)       = fixture_id;
        schedule.LineSide(seq)      = line_side_id;
        schedule.StartTime(seq)     = start_time;
        schedule.EndTime(seq)       = end_time;
        schedule.WaitTime(seq)      = wait_time;
        schedule.TransportTime(seq) = total_transport_time;

        machine_status(machine_id).busy_until       = end_time;
        machine_status(machine_id).current_job      = job_id;
        machine_status(machine_id).current_op       = op_num;
        machine_status(machine_id).current_fixture  = fixture_id;
        machine_status(machine_id).completed_code_idx = code_idx;
        machine_status(machine_id).line_side_dest   = line_side_id;

        job_status(job_id).current_op       = op_num;
        job_status(job_id).current_location = 2;
        job_status(job_id).location_id      = machine_id;
        job_status(job_id).ready_time       = end_time;

        if fixture_id > 0
            fixture_status(fixture_id).busy_until = end_time;
        end
    end

    %% 9. 收尾：处理机器上残留工件
    final_time = max(schedule.EndTime);

    for m = 1:num_machines
        if machine_status(m).current_job > 0
            old_job_id     = machine_status(m).current_job;
            old_fixture_id = machine_status(m).current_fixture;
            old_op_num     = machine_status(m).current_op;
            dest_ls        = machine_status(m).line_side_dest;

            t_final = max(machine_status(m).busy_until, rgv_status.available_time);

            total_job_ops = job_operation_num(old_job_id);
            if old_op_num >= total_job_ops
                move_to_type = 'loading';
                move_to_id   = 1;
            else
                move_to_type = 'line_side';
                move_to_id   = dest_ls;
            end

            rgv_from_type = rgv_status.current_location_type;
            rgv_from_id   = rgv_status.current_location;
            dist1 = layout.get_distance({rgv_from_type, rgv_from_id}, {'machine', m});
            time1 = dist1 / layout.RGV_speed;
            t_rgv_at_m = t_final + time1;

            log_count = log_count + 1;
            log_TaskID(log_count)       = log_count;
            log_TaskType{log_count}     = 'final_cleanup';
            log_Phase{log_count}        = 'travel_to_pickup';
            log_JobID(log_count)        = 0;
            log_FixtureID(log_count)    = 0;
            log_FromType{log_count}     = rgv_from_type;
            log_FromID(log_count)       = rgv_from_id;
            log_ToType{log_count}       = 'machine';
            log_ToID(log_count)         = m;
            log_StartTime(log_count)    = t_final;
            log_EndTime(log_count)      = t_rgv_at_m;
            log_Duration(log_count)     = time1;
            log_Distance(log_count)     = dist1;
            log_TriggerOpIdx(log_count) = 0;

            dist2 = layout.get_distance({'machine', m}, {move_to_type, move_to_id});
            time2 = dist2 / layout.RGV_speed;
            t_done = t_rgv_at_m + time2;

            log_count = log_count + 1;
            log_TaskID(log_count)       = log_count;
            log_TaskType{log_count}     = 'final_cleanup';
            log_Phase{log_count}        = 'carry_to_dest';
            log_JobID(log_count)        = old_job_id;
            log_FixtureID(log_count)    = old_fixture_id;
            log_FromType{log_count}     = 'machine';
            log_FromID(log_count)       = m;
            log_ToType{log_count}       = move_to_type;
            log_ToID(log_count)         = move_to_id;
            log_StartTime(log_count)    = t_rgv_at_m;
            log_EndTime(log_count)      = t_done;
            log_Duration(log_count)     = time2;
            log_Distance(log_count)     = dist2;
            log_TriggerOpIdx(log_count) = 0;

            rgv_status.available_time = t_done;
            rgv_status.current_location_type = move_to_type;
            rgv_status.current_location = move_to_id;

            if strcmp(move_to_type, 'loading')
                job_status(old_job_id).completed = true;
                if old_fixture_id > 0
                    fixture_status(old_fixture_id).location = 1;
                    fixture_status(old_fixture_id).location_id = 1;
                    fixture_status(old_fixture_id).attached_job = 0;
                end
            else
                job_status(old_job_id).current_location = 3;
                job_status(old_job_id).location_id = move_to_id;
                if old_fixture_id > 0
                    fixture_status(old_fixture_id).location = 3;
                    fixture_status(old_fixture_id).location_id = move_to_id;
                end
                line_side_status(move_to_id) = old_job_id;
                line_side_fixture(move_to_id) = old_fixture_id;
            end

            machine_status(m).current_job = 0;
            machine_status(m).current_op = 0;
            machine_status(m).current_fixture = 0;

            final_time = max(final_time, t_done);
        end
    end

    %% 10. makespan
    makespan = final_time;

    %% 11. 组装RGV日志
    rgv_log = table();
    rgv_log.TaskID       = log_TaskID(1:log_count);
    rgv_log.TaskType     = log_TaskType(1:log_count);
    rgv_log.Phase        = log_Phase(1:log_count);
    rgv_log.JobID        = log_JobID(1:log_count);
    rgv_log.FixtureID    = log_FixtureID(1:log_count);
    rgv_log.FromType     = log_FromType(1:log_count);
    rgv_log.FromID       = log_FromID(1:log_count);
    rgv_log.ToType       = log_ToType(1:log_count);
    rgv_log.ToID         = log_ToID(1:log_count);
    rgv_log.StartTime    = log_StartTime(1:log_count);
    rgv_log.EndTime      = log_EndTime(1:log_count);
    rgv_log.Duration     = log_Duration(1:log_count);
    rgv_log.Distance     = log_Distance(1:log_count);
    rgv_log.TriggerOpIdx = log_TriggerOpIdx(1:log_count);

end

%% ========================================================================
%  辅助函数
%% ========================================================================



function loc_str = get_location_type_str(loc_code)
    switch loc_code
        case 1
            loc_str = 'loading';
        case 2
            loc_str = 'machine';
        case 3
            loc_str = 'line_side';
        otherwise
            loc_str = 'loading';
    end
end