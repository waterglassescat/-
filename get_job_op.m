function [job, op] = get_job_op(k, job_operation_num)
% 根据全局工序索引 k，确定对应的工件号和工序号
% 优化：用 persistent 缓存前缀和与查找表，O(1) 查询

persistent cached_jon cached_pos2job cached_pos2op
if isempty(cached_jon) || ~isequal(cached_jon, job_operation_num)
    cached_jon = job_operation_num;
    total_ops = sum(job_operation_num);
    cached_pos2job = zeros(total_ops, 1);
    cached_pos2op  = zeros(total_ops, 1);
    idx = 0;
    for j = 1:length(job_operation_num)
        for o = 1:job_operation_num(j)
            idx = idx + 1;
            cached_pos2job(idx) = j;
            cached_pos2op(idx)  = o;
        end
    end
end

job = cached_pos2job(k);
op  = cached_pos2op(k);
end
