function rgv_summary = analyze_rgv(rgv_log, makespan)
% ANALYZE_RGV  Analyze rgv_log from decode_makespan2
%
% Usage:
%   [schedule, makespan, rgv_log] = decode_makespan2(...);
%   rgv_summary = analyze_rgv(rgv_log, makespan);
%
% Output:
%   rgv_summary.overview     : overall summary table
%   rgv_summary.by_task_type : statistics grouped by task type
%   rgv_summary.by_phase     : statistics grouped by phase (travel/carry)
%
% Also prints a console report and draws three pie charts.

    %% ====================================================================
    %  Part 1 : Overall summary
    %  ====================================================================
    total_tasks    = height(rgv_log);
    total_time     = sum(rgv_log.Duration);
    total_distance = sum(rgv_log.Distance);

    is_travel = strcmp(rgv_log.Phase, 'travel_to_pickup');
    is_carry  = strcmp(rgv_log.Phase, 'carry_to_dest');

    travel_time = sum(rgv_log.Duration(is_travel));
    carry_time  = sum(rgv_log.Duration(is_carry));
    travel_dist = sum(rgv_log.Distance(is_travel));
    carry_dist  = sum(rgv_log.Distance(is_carry));

    idle_time = makespan - total_time;
    if idle_time < 0, idle_time = 0; end

    utilization = total_time / makespan * 100;

    overview_metric = {
        'TotalSegments';
        'TotalTransportTime';
        'TotalTransportDist';
        'TravelTime';
        'TravelDist';
        'CarryTime';
        'CarryDist';
        'IdleTime';
        'Utilization_pct';
        'Makespan'
    };
    overview_value = [
        total_tasks;
        total_time;
        total_distance;
        travel_time;
        travel_dist;
        carry_time;
        carry_dist;
        idle_time;
        utilization;
        makespan
    ];
    overview = table(overview_metric, overview_value, ...
        'VariableNames', {'Metric', 'Value'});

    %% ====================================================================
    %  Part 2 : By task type
    %  ====================================================================
    task_types = unique(rgv_log.TaskType);
    n_types = length(task_types);

    % English label map
    en_map = {
        'clear_machine',               'Clear target machine';
        'evacuate_source_machine',      'Evacuate source machine';
        'release_fixture_from_machine', 'Release fixture (machine)';
        'release_fixture_return',       'Return fixture to loading';
        'release_fixture',              'Release fixture (lineside)';
        'reposition_fixture',           'Reposition fixture';
        'deliver_to_machine',           'Deliver job to machine';
        'final_cleanup',                'Final cleanup'
    };
    % Chinese label map (via char codes to avoid encoding issues)
    zh_map = {
        'clear_machine',               char([28165 29702 30446 26631 26426 22120]);
        'evacuate_source_machine',      char([25644 31163 28304 26426 22120 24037 20214]);
        'release_fixture_from_machine', char([37322 25918 26426 22120 19978 22841 20855]);
        'release_fixture_return',       char([22841 20855 36865 22238 35013 36733 31449]);
        'release_fixture',              char([37322 25918 32447 36793 24211 22841 20855]);
        'reposition_fixture',           char([22841 20855 23601 20301 35843 24230]);
        'deliver_to_machine',           char([36865 24037 20214 21040 26426 22120]);
        'final_cleanup',                char([25910 23614 28165 29702])
    };

    type_label    = cell(n_types, 1);
    type_label_zh = cell(n_types, 1);
    for i = 1:n_types
        idx = find(strcmp(en_map(:,1), task_types{i}), 1);
        if ~isempty(idx)
            type_label{i} = en_map{idx, 2};
        else
            type_label{i} = task_types{i};
        end
        idx2 = find(strcmp(zh_map(:,1), task_types{i}), 1);
        if ~isempty(idx2)
            type_label_zh{i} = zh_map{idx2, 2};
        else
            type_label_zh{i} = task_types{i};
        end
    end

    type_count    = zeros(n_types, 1);
    type_time     = zeros(n_types, 1);
    type_dist     = zeros(n_types, 1);
    type_time_pct = zeros(n_types, 1);

    for i = 1:n_types
        mask = strcmp(rgv_log.TaskType, task_types{i});
        type_count(i) = sum(mask);
        type_time(i)  = sum(rgv_log.Duration(mask));
        type_dist(i)  = sum(rgv_log.Distance(mask));
    end
    if total_time > 0
        type_time_pct = type_time / total_time * 100;
    end

    by_task_type = table(type_label, type_label_zh, task_types, ...
        type_count, type_time, type_dist, type_time_pct, ...
        'VariableNames', {'Label', 'LabelZH', 'TaskType', ...
                          'Segments', 'TotalTime', 'TotalDist', 'TimePct'});
    [~, sort_idx] = sort(type_time, 'descend');
    by_task_type = by_task_type(sort_idx, :);

    %% ====================================================================
    %  Part 3 : By phase
    %  ====================================================================
    phase_names  = {'travel_to_pickup'; 'carry_to_dest'};
    phase_label  = {'Travel (empty)'; 'Carry (loaded)'};
    phase_count  = [sum(is_travel); sum(is_carry)];
    phase_time_v = [travel_time; carry_time];
    phase_dist_v = [travel_dist; carry_dist];
    phase_pct    = phase_time_v / max(total_time, eps) * 100;

    by_phase = table(phase_label, phase_names, phase_count, ...
        phase_time_v, phase_dist_v, phase_pct, ...
        'VariableNames', {'Label', 'Phase', 'Segments', ...
                          'TotalTime', 'TotalDist', 'TimePct'});

    %% ====================================================================
    %  Output struct
    %  ====================================================================
    rgv_summary.overview     = overview;
    rgv_summary.by_task_type = by_task_type;
    rgv_summary.by_phase     = by_phase;

    %% ====================================================================
    %  Console report
    %  ====================================================================
    print_report(makespan, total_time, utilization, idle_time, ...
                 total_tasks, total_distance, ...
                 travel_time, carry_time, travel_dist, carry_dist, ...
                 by_task_type, by_phase);

    %% ====================================================================
    %  Part 4 : Pie charts
    %  ====================================================================
    plot_rgv_pie(by_task_type, idle_time, makespan, travel_time, carry_time);

end


%% ========================================================================
%  Console report (all Chinese strings built via char() at runtime)
%% ========================================================================
function print_report(makespan, total_time, utilization, idle_time, ...
                      total_tasks, total_distance, ...
                      travel_time, carry_time, travel_dist, carry_dist, ...
                      by_task_type, by_phase)

    fprintf('\n');
    fprintf('============================================================\n');
    fprintf('                    RGV %s\n', ...
        char([36816 36755 20998 26512 25253 21578]));  % "transport analysis report"
    fprintf('============================================================\n');

    % Section 1: Summary
    fprintf('\n-- %s --\n', ...
        char([19968 12289 24635 20307 27719 24635]));  % "1. Overall summary"
    fprintf('  Makespan               : %.2f\n', makespan);
    fprintf('  RGV %s       : %.2f (%s %.1f%%)\n', ...
        char([24635 36816 36755 26102 38388]), total_time, ...  % "total transport time"
        char([21033 29992 29575]), utilization);                % "utilization"
    fprintf('  RGV %s           : %.2f\n', ...
        char([31354 38386 26102 38388]), idle_time);            % "idle time"
    fprintf('  %s             : %d\n', ...
        char([24635 36816 36755 27573 25968]), total_tasks);    % "total segments"
    fprintf('  %s             : %.2f\n', ...
        char([24635 36816 36755 36317 31163]), total_distance); % "total distance"
    fprintf('  %s / %s    : %.2f / %.2f\n', ...
        char([31354 36305 26102 38388]), ...                    % "travel time"
        char([36733 36135 26102 38388]), ...                    % "carry time"
        travel_time, carry_time);
    fprintf('  %s / %s    : %.2f / %.2f\n', ...
        char([31354 36305 36317 31163]), ...                    % "travel dist"
        char([36733 36135 36317 31163]), ...                    % "carry dist"
        travel_dist, carry_dist);

    % Section 2: By task type
    fprintf('\n-- %s --\n', ...
        char([20108 12289 25353 20219 21153 31867 22411 20998 31867]));  % "2. By task type"
    hdr_type = char([31867 22411]);       % "type"
    hdr_seg  = char([27573 25968]);       % "segments"
    hdr_time = char([32791 26102]);       % "duration"
    hdr_dist = char([36317 31163]);       % "distance"
    hdr_pct  = char([21344 27604 37327]); % "ratio(%)"
    fprintf('  %-24s %6s %10s %10s %8s\n', hdr_type, hdr_seg, hdr_time, hdr_dist, hdr_pct);
    fprintf('  %s\n', repmat('-', 1, 62));
    for i = 1:height(by_task_type)
        fprintf('  %-24s %6d %10.2f %10.2f %8.1f\n', ...
            by_task_type.LabelZH{i}, ...
            by_task_type.Segments(i), ...
            by_task_type.TotalTime(i), ...
            by_task_type.TotalDist(i), ...
            by_task_type.TimePct(i));
    end

    % Section 3: By phase
    fprintf('\n-- %s --\n', ...
        char([19977 12289 25353 36816 36755 38454 27573 20998 31867]));  % "3. By phase"
    hdr_phase = char([38454 27573]);  % "phase"
    fprintf('  %-24s %6s %10s %10s %8s\n', hdr_phase, hdr_seg, hdr_time, hdr_dist, hdr_pct);
    fprintf('  %s\n', repmat('-', 1, 62));
    phase_zh = { ...
        char([31354 36305 65288 21435 21462 20214 65289]); ...  % "travel (to pickup)"
        char([36733 36135 65288 36865 36798 65289])};           % "carry (deliver)"
    for i = 1:height(by_phase)
        fprintf('  %-24s %6d %10.2f %10.2f %8.1f\n', ...
            phase_zh{i}, ...
            by_phase.Segments(i), ...
            by_phase.TotalTime(i), ...
            by_phase.TotalDist(i), ...
            by_phase.TimePct(i));
    end
    fprintf('\n');
end


%% ========================================================================
%  Pie chart plotting
%% ========================================================================
function plot_rgv_pie(by_task_type, idle_time, makespan, travel_time, carry_time)

    figure('Name', 'RGV Time Analysis', 'NumberTitle', 'off', ...
           'Color', 'w', 'Position', [100, 100, 1200, 500]);

    colors_pool = [
        0.267, 0.667, 0.600;
        0.886, 0.529, 0.275;
        0.400, 0.467, 0.800;
        0.867, 0.467, 0.533;
        0.533, 0.733, 0.400;
        0.800, 0.733, 0.267;
        0.600, 0.400, 0.667;
        0.467, 0.667, 0.800;
        0.850, 0.850, 0.850;
    ];

    str_idle = char([31354 38386]);           % "idle"
    str_travel = char([31354 36305]);         % "travel"
    str_carry  = char([36733 36135]);         % "carry"
    str_effective = char([26377 25928 36816 36755]);  % "effective transport"
    str_overhead  = char([36741 21161 36816 36755]);  % "auxiliary transport"

    % ---- Pie 1 : by task type + idle ----
    ax1 = subplot(1, 3, 1);

    pie_labels = by_task_type.LabelZH;
    pie_values = by_task_type.TotalTime;

    valid = pie_values > 0;
    pie_labels = pie_labels(valid);
    pie_values = pie_values(valid);

    if idle_time > 0
        pie_labels{end+1} = str_idle;
        pie_values(end+1) = idle_time;
    end

    pct = pie_values / sum(pie_values) * 100;
    disp_labels = cell(size(pie_labels));
    for i = 1:length(pie_labels)
        disp_labels{i} = sprintf('%s\n%.1f%%', pie_labels{i}, pct(i));
    end

    n = length(pie_values);
    cmap1 = colors_pool(1:min(n, size(colors_pool,1)), :);
    if n > size(cmap1, 1)
        cmap1 = [cmap1; rand(n - size(cmap1,1), 3)*0.5 + 0.3];
    end

    p1 = pie(ax1, pie_values, disp_labels);
    colormap(ax1, cmap1);
    title(ax1, char([25353 20219 21153 31867 22411]), ...  % "by task type"
          'FontSize', 13, 'FontWeight', 'bold');
    set_pie_fontsize(p1, 8);

    % ---- Pie 2 : travel vs carry vs idle ----
    ax2 = subplot(1, 3, 2);

    pv2 = []; pl2 = {}; pc2 = [];
    if travel_time > 0
        pv2(end+1) = travel_time;
        pl2{end+1} = sprintf('%s\n%.1f%%', str_travel, travel_time/makespan*100);
        pc2(end+1,:) = [0.886, 0.529, 0.275];
    end
    if carry_time > 0
        pv2(end+1) = carry_time;
        pl2{end+1} = sprintf('%s\n%.1f%%', str_carry, carry_time/makespan*100);
        pc2(end+1,:) = [0.267, 0.667, 0.600];
    end
    if idle_time > 0
        pv2(end+1) = idle_time;
        pl2{end+1} = sprintf('%s\n%.1f%%', str_idle, idle_time/makespan*100);
        pc2(end+1,:) = [0.850, 0.850, 0.850];
    end

    p2 = pie(ax2, pv2, pl2);
    colormap(ax2, pc2);
    title(ax2, sprintf('%s vs %s vs %s', str_travel, str_carry, str_idle), ...
          'FontSize', 13, 'FontWeight', 'bold');
    set_pie_fontsize(p2, 10);

    % ---- Pie 3 : effective vs overhead vs idle ----
    ax3 = subplot(1, 3, 3);

    deliver_mask = strcmp(by_task_type.TaskType, 'deliver_to_machine');
    effective_time = 0;
    if any(deliver_mask)
        effective_time = by_task_type.TotalTime(deliver_mask);
    end
    overhead_time = (travel_time + carry_time) - effective_time;
    if overhead_time < 0, overhead_time = 0; end

    pv3 = []; pl3 = {}; pc3 = [];
    if effective_time > 0
        pv3(end+1) = effective_time;
        pl3{end+1} = sprintf('%s\n%.1f%%', str_effective, effective_time/makespan*100);
        pc3(end+1,:) = [0.267, 0.667, 0.600];
    end
    if overhead_time > 0
        pv3(end+1) = overhead_time;
        pl3{end+1} = sprintf('%s\n%.1f%%', str_overhead, overhead_time/makespan*100);
        pc3(end+1,:) = [0.886, 0.529, 0.275];
    end
    if idle_time > 0
        pv3(end+1) = idle_time;
        pl3{end+1} = sprintf('%s\n%.1f%%', str_idle, idle_time/makespan*100);
        pc3(end+1,:) = [0.850, 0.850, 0.850];
    end

    p3 = pie(ax3, pv3, pl3);
    colormap(ax3, pc3);
    title(ax3, sprintf('%s vs %s vs %s', str_effective, str_overhead, str_idle), ...
          'FontSize', 13, 'FontWeight', 'bold');
    set_pie_fontsize(p3, 10);

    sgtitle(sprintf('RGV %s', char([26102 38388 21033 29992 20998 26512])), ...
            'FontSize', 16, 'FontWeight', 'bold');  % "time utilization analysis"
end


%% ========================================================================
function set_pie_fontsize(p, sz)
    for i = 1:length(p)
        if isa(p(i), 'matlab.graphics.primitive.Text')
            set(p(i), 'FontSize', sz);
        end
    end
end