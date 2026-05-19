function [job_info, op_map] = get_job_operation_info(total_ops, schedule_code, job_operation_num)
% 优化版：用前缀和数组替代循环 sum，避免 O(num_jobs) 的反复累加

% 前缀和（cached）：prefix(j) = sum(job_operation_num(1:j-1))
persistent cached_jon cached_prefix
if isempty(cached_jon) || ~isequal(cached_jon, job_operation_num)
    cached_jon = job_operation_num;
    cached_prefix = [0; cumsum(job_operation_num(:))];
end
prefix = cached_prefix;

num_jobs = length(job_operation_num);
job_counter = zeros(1, num_jobs);

job_ids = zeros(total_ops, 1);
op_nums = zeros(total_ops, 1);
op_map  = zeros(total_ops, 1);

for i = 1:total_ops
    job_id = schedule_code(i);
    job_counter(job_id) = job_counter(job_id) + 1;
    job_ids(i) = job_id;
    op_nums(i) = job_counter(job_id);
    op_map(i)  = prefix(job_id) + job_counter(job_id);
end

if sum(job_counter) ~= total_ops
    warning('工序总数与job_operation_num不匹配！');
end

job_info = struct();
job_info.job_ids          = job_ids;
job_info.op_nums          = op_nums;
job_info.job_counter      = job_counter;
job_info.job_operation_num = job_operation_num;
end
