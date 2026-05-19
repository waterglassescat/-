function plot_gantt_with_rgv(schedule, rgv_log, makespan, num_machines, job_operation_num)
% 绘制调度甘特图（含RGV运输）
% 输入：
%   schedule          - decode_makespan2 返回的调度结果表(table)
%   rgv_log           - decode_makespan2 返回的RGV运输日志表(table)
%   makespan          - 总完工时间
%   num_machines      - 机器数量
%   job_operation_num - 各工件工序数
%
% 绘制规则：
%   机器行：彩色块=加工（同工件同色），灰色块=RGV运输（起点或终点涉及该机器）
%   RGV行：灰色块=载货运输，浅灰虚线=空跑
%   不涉及机器的运输只画在RGV行

total_jobs = length(job_operation_num);

% RGV行的y坐标放在最下方（y=0），机器行在上方（y=1~num_machines）
% 纵轴编号：RGV=0, M1=1, M2=2, ... Mn=n
rgv_row = 0;
max_row = num_machines;  % 最上方的行号

figure('Position', [100, 100, 1200, 600]);
hold on;

%% 1. 颜色定义
% 工件颜色：用 HSV 空间均匀采样，保证任意工件数都互不相同
colors = generate_distinct_colors(total_jobs);

% RGV运输颜色
rgv_carry_color = [0.75 0.75 0.75];    % 载货：中灰色
rgv_idle_color  = [0.90 0.90 0.90];    % 空跑：浅灰色

bar_half = 0.3;  % 条形半高

%% 2. 绘制机器加工块（彩色）
for i = 1:height(schedule)
    job_id     = schedule.JobID(i);
    op_num     = schedule.Operation(i);
    fixture_id = schedule.Fixture(i);
    machine_id = schedule.Machine(i);
    t_start    = schedule.StartTime(i);
    t_end      = schedule.EndTime(i);
    
    if job_id == 0 || machine_id == 0, continue; end
    duration = t_end - t_start;
    if duration <= 0, continue; end
    
    y = machine_id;  % 机器号直接作为y坐标
    color = colors(job_id, :);
    
    % 用fill绘制彩色条形（与原版风格一致）
    fill([t_start, t_start, t_end, t_end], ...
         [y - bar_half, y + bar_half, y + bar_half, y - bar_half], ...
         color, 'FaceAlpha', 0.8, 'EdgeColor', 'black', 'LineWidth', 1);
    
    % 标注：J工件号-F夹具号
    if duration > 0
        label = sprintf('J%d-F%d', job_id, fixture_id);
        text_x = t_start + duration / 2;
        
        if duration >= makespan * 0.05
            fs = 9;
        elseif duration >= makespan * 0.02
            fs = 7;
        else
            fs = 5;
        end
        
        text(text_x, y, label, ...
             'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
             'FontSize', fs, 'FontWeight', 'bold', 'Color', 'white');
    end
end

%% 3. 绘制RGV运输块（灰色）
for i = 1:height(rgv_log)
    t_start    = rgv_log.StartTime(i);
    t_end      = rgv_log.EndTime(i);
    phase      = rgv_log.Phase{i};
    job_id     = rgv_log.JobID(i);
    fixture_id = rgv_log.FixtureID(i);
    from_type  = rgv_log.FromType{i};
    from_id    = rgv_log.FromID(i);
    to_type    = rgv_log.ToType{i};
    to_id      = rgv_log.ToID(i);
    
    duration = t_end - t_start;
    if duration < 1e-6, continue; end
    
    from_is_machine = strcmp(from_type, 'machine');
    to_is_machine   = strcmp(to_type, 'machine');
    
    if strcmp(phase, 'travel_to_pickup')
        % ======== 空跑阶段：浅灰色 + 虚线边框 ========
        
        % RGV行
        fill([t_start, t_start, t_end, t_end], ...
             [rgv_row - bar_half, rgv_row + bar_half, rgv_row + bar_half, rgv_row - bar_half], ...
             rgv_idle_color, 'FaceAlpha', 0.6, 'EdgeColor', [0.5 0.5 0.5], ...
             'LineStyle', '--', 'LineWidth', 0.5);
        
        % 如果空跑终点是机器，也在该机器行画
        if to_is_machine
            my = to_id;
            fill([t_start, t_start, t_end, t_end], ...
                 [my - bar_half, my + bar_half, my + bar_half, my - bar_half], ...
                 rgv_idle_color, 'FaceAlpha', 0.5, 'EdgeColor', [0.5 0.5 0.5], ...
                 'LineStyle', '--', 'LineWidth', 0.5);
        end
        
    else
        % ======== 载货阶段：中灰色 + 实线边框 ========
        
        % 准备标注文字
        if job_id > 0 && fixture_id > 0
            label = sprintf('J%d-F%d', job_id, fixture_id);
        elseif job_id > 0
            label = sprintf('J%d', job_id);
        else
            label = '';
        end
        
        if duration >= makespan * 0.04
            fs = 8;
        elseif duration >= makespan * 0.02
            fs = 6;
        else
            fs = 5;
        end
        
        % --- 始终画在RGV行 ---
        fill([t_start, t_start, t_end, t_end], ...
             [rgv_row - bar_half, rgv_row + bar_half, rgv_row + bar_half, rgv_row - bar_half], ...
             rgv_carry_color, 'FaceAlpha', 0.8, 'EdgeColor', 'black', 'LineWidth', 0.8);
        if duration > makespan * 0.015 && ~isempty(label)
            text(t_start + duration/2, rgv_row, label, ...
                 'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
                 'FontSize', fs, 'FontWeight', 'bold', 'Color', 'k');
        end
        
        % --- 起点是机器 → 在该机器行也画灰色块 ---
        if from_is_machine
            my = from_id;
            fill([t_start, t_start, t_end, t_end], ...
                 [my - bar_half, my + bar_half, my + bar_half, my - bar_half], ...
                 rgv_carry_color, 'FaceAlpha', 0.7, 'EdgeColor', 'black', 'LineWidth', 0.8);
            if duration > makespan * 0.02 && ~isempty(label)
                text(t_start + duration/2, my, label, ...
                     'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
                     'FontSize', fs, 'Color', [0.2 0.2 0.2]);
            end
        end
        
        % --- 终点是机器 → 在该机器行也画灰色块 ---
        if to_is_machine
            my = to_id;
            fill([t_start, t_start, t_end, t_end], ...
                 [my - bar_half, my + bar_half, my + bar_half, my - bar_half], ...
                 rgv_carry_color, 'FaceAlpha', 0.7, 'EdgeColor', 'black', 'LineWidth', 0.8);
            if duration > makespan * 0.02 && ~isempty(label)
                text(t_start + duration/2, my, label, ...
                     'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
                     'FontSize', fs, 'Color', [0.2 0.2 0.2]);
            end
        end
    end
end

%% 4. 坐标轴设置
xlabel('时间', 'FontSize', 12, 'FontWeight', 'bold');
ylabel('资源', 'FontSize', 12, 'FontWeight', 'bold');
title(sprintf('调度甘特图（Makespan = %.2f）', makespan), ...
      'FontSize', 14, 'FontWeight', 'bold');

ylim([rgv_row - 0.5, max_row + 0.5]);
xlim([0, makespan * 1.05]);

% 纵轴刻度：RGV在最下方，M1~Mn在上方
ytick_vals   = [rgv_row, 1:num_machines];
ytick_labels = ['RGV', arrayfun(@(x) sprintf('M%d', x), 1:num_machines, 'UniformOutput', false)];
yticks(ytick_vals);
yticklabels(ytick_labels);

set(gca, 'YGrid', 'on', 'GridAlpha', 0.3, 'GridLineStyle', '-');

%% 5. 图例
legend_handles = [];
legend_labels  = {};

% 每个出现的工件
appeared_jobs = unique(schedule.JobID(schedule.JobID > 0));
for j = 1:length(appeared_jobs)
    jid = appeared_jobs(j);
    h = fill(NaN, NaN, colors(jid, :), 'FaceAlpha', 0.8, 'EdgeColor', 'black');
    legend_handles = [legend_handles, h];
    legend_labels{end+1} = sprintf('工件 %d', jid);
end

% RGV载货
h1 = fill(NaN, NaN, rgv_carry_color, 'FaceAlpha', 0.8, 'EdgeColor', 'black');
legend_handles = [legend_handles, h1];
legend_labels{end+1} = 'RGV 载货';

% RGV空跑
h2 = fill(NaN, NaN, rgv_idle_color, 'FaceAlpha', 0.6, 'EdgeColor', [0.5 0.5 0.5], 'LineStyle', '--');
legend_handles = [legend_handles, h2];
legend_labels{end+1} = 'RGV 空跑';

legend(legend_handles, legend_labels, 'Location', 'eastoutside', 'FontSize', 10);

%% 6. 底部RGV统计
carry_mask = strcmp(rgv_log.Phase, 'carry_to_dest');
idle_mask  = strcmp(rgv_log.Phase, 'travel_to_pickup');
t_carry = sum(rgv_log.Duration(carry_mask));
t_idle  = sum(rgv_log.Duration(idle_mask));
t_free  = max(0, makespan - t_carry - t_idle);

stats = sprintf('RGV统计 | 载货: %.1f (%.0f%%)  空跑: %.1f (%.0f%%)  空闲: %.1f (%.0f%%)  运输次数: %d', ...
    t_carry, t_carry/makespan*100, t_idle, t_idle/makespan*100, ...
    t_free, t_free/makespan*100, sum(carry_mask));

% 在图形底部添加文本
annotation('textbox', [0.1, 0.01, 0.75, 0.04], 'String', stats, ...
           'HorizontalAlignment', 'center', 'FontSize', 9, ...
           'EdgeColor', 'none', 'FitBoxToText', 'off');

box on;
hold off;
end
%% =============== 工件颜色生成（保证互不相同）===============
function colors = generate_distinct_colors(N)
    % 用 HSV 空间均匀采样色相，再用不同的饱和度/亮度组合避免相邻颜色过近
    if N <= 0
        colors = [];
        return;
    end
    
    % 黄金角分布在 [0,1) 上分配色相，避免均匀网格的视觉重复
    golden = 0.61803398875;
    hues = mod((0:N-1) * golden + 0.1, 1);
    
    % 饱和度和亮度循环变化，进一步增加区分度
    sats = 0.65 + 0.25 * mod(0:N-1, 3) / 2;        % 0.65, 0.775, 0.9 循环
    vals = 0.95 - 0.20 * mod(floor((0:N-1)/3), 2); % 0.95 / 0.75 交替
    
    hsv_mat = [hues(:), sats(:), vals(:)];
    colors = hsv2rgb(hsv_mat);
end
