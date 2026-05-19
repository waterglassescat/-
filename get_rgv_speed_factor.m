function val = get_rgv_speed_factor(new_val)
% RGV 速度倍率的全局设置/读取
%
% 用法：
%   get_rgv_speed_factor(20)       % 设置倍率为 5
%   v = get_rgv_speed_factor()      % 读取当前倍率
%   get_rgv_speed_factor([])        % 重置为默认值
%
% 含义：
%   RGV_speed = avg_processing_time × rgv_speed_factor
%   这样 RGV 的运输时间在不同算例的 makespan 里占比相近。
%
% 默认值：5
%
% 注意：修改此值后会清空 decode_makespan 的 layout 缓存，下次调用时
% 会按新值重建 layout。

persistent factor
if isempty(factor)
    factor = 5;
end

if nargin >= 1
    if isempty(new_val)
        factor = 5;
    else
        factor = new_val;
    end
    % 清空 decode_makespan 的 persistent 缓存
    clear decode_makespan
end

val = factor;
end
