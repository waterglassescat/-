function [job_data, machine_data, fixture_data, fixture_times, num_jobs, num_machines, num_fixture_types, total_operations] = read_production_data(filename)
    % 读取生产数据文件
    % 输入参数:
    %   filename - 数据文件名
    % 输出参数:
    %   job_data - 工件加工信息
    %   machine_data - 工件在机器上的加工时间信息
    %   fixture_data - 工件各工序可用夹具信息
    %   fixture_times - 夹具装卸时间
    %   num_jobs - 工件数量
    %   num_machines - 机器总数
    %   num_fixture_types - 夹具类型数
    %   total_operations - 总工序数
    
    % 打开文件
    fid = fopen(filename, 'r');
    if fid == -1
        error('无法打开文件: %s', filename);
    end
    
    % 读取第一行的基本信息
    header_line = fgetl(fid);
    header_nums = sscanf(header_line, '%d');
    num_jobs = header_nums(1);
    num_machines = header_nums(2);
    num_fixture_types = header_nums(3);
    
    % 初始化数据结构
    job_data = cell(num_jobs, 1);
    machine_data = cell(num_jobs, 1);
    fixture_data = cell(num_jobs, 1);
    fixture_times = zeros(num_fixture_types, 1);
    
    % 初始化总工序数
    total_operations = 0;
    
    % 读取machine数据
    for job_id = 1:num_jobs
        line = fgetl(fid);
        if isempty(line) || ~strncmp(line, '#machine', 8)
            error('文件格式错误: 期望 #machine 行');
        end
        
        % 移除标签并转换为数字
        numbers = sscanf(line(9:end), '%d');
        
        % 解析工件工序数
        num_operations = numbers(1);
        job_data{job_id}.num_operations = num_operations;
        
        % 累加到总工序数
        total_operations = total_operations + num_operations;
        
        % 初始化机器选择数据结构
        machine_data{job_id} = cell(num_operations, 1);
        
        idx = 2; % 从第二个数字开始解析
        for op = 1:num_operations
            % 获取可选机器数量
            num_machine_options = numbers(idx);
            idx = idx + 1;
            
            % 初始化当前工序的机器选择矩阵
            % 每行: [机器编号, 加工时间]
            machine_options = zeros(num_machine_options, 2);
            
            for opt = 1:num_machine_options
                machine_options(opt, 1) = numbers(idx);     % 机器编号
                machine_options(opt, 2) = numbers(idx + 1); % 加工时间
                idx = idx + 2;
            end
            
            % 存储当前工序的机器选择
            machine_data{job_id}{op} = machine_options;
        end
    end
    
    % 读取fixture数据
    for job_id = 1:num_jobs
        line = fgetl(fid);
        if isempty(line) || ~strncmp(line, '#fixture', 8)
            error('文件格式错误: 期望 #fixture 行');
        end
        
        % 移除标签并转换为数字
        numbers = sscanf(line(9:end), '%d');
        
        % 验证工序数是否匹配
        if numbers(1) ~= job_data{job_id}.num_operations
            error('工件 %d 的工序数不匹配', job_id);
        end
        
        % 初始化夹具选择数据结构
        fixture_data{job_id} = cell(job_data{job_id}.num_operations, 1);
        
        idx = 2; % 从第二个数字开始解析
        for op = 1:job_data{job_id}.num_operations
            % 获取可选夹具数量
            num_fixture_options = numbers(idx);
            idx = idx + 1;
            
            % 初始化当前工序的夹具选择数组
            fixture_options = zeros(num_fixture_options, 1);
            
            for opt = 1:num_fixture_options
                fixture_options(opt) = numbers(idx);
                idx = idx + 1;
            end
            
            % 存储当前工序的夹具选择
            fixture_data{job_id}{op} = fixture_options;
        end
    end
    
    % 读取fixtureTime数据
    for i = 1:num_fixture_types
        line = fgetl(fid);
        if isempty(line) || ~strncmp(line, '#fixtureTime', 12)
            error('文件格式错误: 期望 #fixtureTime 行');
        end
        
        % 移除标签并转换为数字
        numbers = sscanf(line(13:end), '%d');
        
        fixture_id = numbers(1);
        setup_time = numbers(2);
        
        % 验证夹具编号是否有效
        if fixture_id < 0 || fixture_id >= num_fixture_types
            error('夹具编号 %d 超出范围', fixture_id);
        end
        
        % 存储夹具装卸时间 (MATLAB索引从1开始，所以需要+1)
        fixture_times(fixture_id + 1) = setup_time;
    end
    
    % 关闭文件
    fclose(fid);
    
    % 显示读取结果摘要

    % fprintf('工件数量: %d\n', num_jobs);
    % fprintf('机器总数: %d\n', num_machines);
    % fprintf('夹具类型数: %d\n', num_fixture_types);
    % fprintf('总工序数: %d\n', total_operations);
    % fprintf('\n');
    
    
end
