function layout_info = create_layout_info(num_machines, rgv_speed_override)
% 创建布局信息
%
% 输入：
%   num_machines        - 机器数量
%   rgv_speed_override  - （可选）显式指定 RGV 速度。
%                         若不传或为空，则使用默认值 20。
%                         推荐通过 create_layout_info_dynamic 计算动态速度。
%
% 输出 layout_info 结构体新增字段：
%   .dist_table - (3 x max_id x 3 x max_id) 数值矩阵
%                 dist_table(t1, i, t2, j) 直接给出位置(t1,i)到(t2,j)的距离
%                 类型编码：1=loading, 2=machine, 3=line_side
%                 loading 的 id 固定为 1
%   .max_id     - dist_table 的第二/四维大小（= max(num_machines, num_LS, 1)）

if nargin < 2 || isempty(rgv_speed_override)
    rgv_speed_override = 20;
end

%% 基本参数
distance_Line_side = 0.6;
num_Line_side = 5*num_machines + 11;
machine_left = (6-1) * distance_Line_side;
distance_machine = 5 * distance_Line_side;
loading_position = 0;

layout_info = struct();
layout_info.num_machines       = num_machines;
layout_info.num_Line_side      = num_Line_side;
layout_info.distance_Line_side = distance_Line_side;
layout_info.distance_machine   = distance_machine;
layout_info.RGV_speed          = rgv_speed_override;

%% 位置数组（向量化）
layout_info.positions.loading   = loading_position;
layout_info.positions.machines  = machine_left + (0:num_machines-1)' * distance_machine;
layout_info.positions.line_side = (0:num_Line_side-1)' * distance_Line_side;

%% 距离矩阵（向量化）
mp = layout_info.positions.machines;
lp = layout_info.positions.line_side;
lo = layout_info.positions.loading;

layout_info.distances.machine_to_machine     = abs(mp - mp');
layout_info.distances.line_side_to_line_side = abs(lp - lp');
layout_info.distances.machine_to_line_side   = abs(mp - lp');
layout_info.distances.loading_to_machines    = abs(lo - mp);
layout_info.distances.loading_to_line_side   = abs(lo - lp);

%% 【新增】构建大距离查找表 dist_table
% 类型编码：1=loading, 2=machine, 3=line_side
% loading 的 id 固定为 1
max_id = max([1, num_machines, num_Line_side]);
dist_table = zeros(3, max_id, 3, max_id);

% loading->loading
dist_table(1, 1, 1, 1) = 0;
% loading->machine
for j = 1:num_machines
    d = layout_info.distances.loading_to_machines(j);
    dist_table(1, 1, 2, j) = d;
    dist_table(2, j, 1, 1) = d;
end
% loading->line_side
for j = 1:num_Line_side
    d = layout_info.distances.loading_to_line_side(j);
    dist_table(1, 1, 3, j) = d;
    dist_table(3, j, 1, 1) = d;
end
% machine->machine
for i = 1:num_machines
    for j = 1:num_machines
        dist_table(2, i, 2, j) = layout_info.distances.machine_to_machine(i, j);
    end
end
% line_side->line_side
for i = 1:num_Line_side
    for j = 1:num_Line_side
        dist_table(3, i, 3, j) = layout_info.distances.line_side_to_line_side(i, j);
    end
end
% machine<->line_side
for i = 1:num_machines
    for j = 1:num_Line_side
        d = layout_info.distances.machine_to_line_side(i, j);
        dist_table(2, i, 3, j) = d;
        dist_table(3, j, 2, i) = d;
    end
end

layout_info.dist_table = dist_table;
layout_info.max_id     = max_id;

%% 兼容旧接口：get_distance 包装函数（仍可用，但新代码应直接索引 dist_table）
layout_info.get_distance = @(from, to) get_distance_wrapper(layout_info, from, to);

end
