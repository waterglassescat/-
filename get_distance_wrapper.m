function distance = get_distance_wrapper(layout_info, from, to)
% 距离访问包装函数（兼容旧接口）
%
% 推荐用法：直接索引 layout_info.dist_table(t1, i, t2, j)，速度更快。
% 此函数仅为兼容旧代码保留。

if iscell(from)
    from_type = from{1};  from_id = from{2};
    to_type   = to{1};    to_id   = to{2};
else
    from_type = from.type;  from_id = from.id;
    to_type   = to.type;    to_id   = to.id;
end

% 字符串 -> 整数代码
t1 = type_to_code(from_type);
t2 = type_to_code(to_type);
if t1 == 1, from_id = 1; end
if t2 == 1, to_id   = 1; end

distance = layout_info.dist_table(t1, from_id, t2, to_id);
end

function c = type_to_code(s)
switch s
    case 'loading',   c = 1;
    case 'machine',   c = 2;
    case 'line_side', c = 3;
    otherwise, error('未知位置类型: %s', s);
end
end
