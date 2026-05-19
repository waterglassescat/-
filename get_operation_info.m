function [job_id, op_num, machine_idx, fixture_idx, line_side_id, actual_machine, processing_time, actual_fixture] = ...
    get_operation_info(seq_idx, code_idx, machine_code, fixture_code, line_side_code, job_info, machine_data, fixture_data)

machine_idx  = machine_code(code_idx);
fixture_idx  = fixture_code(code_idx);
line_side_id = line_side_code(code_idx);

job_id = job_info.job_ids(seq_idx);
op_num = job_info.op_nums(seq_idx);

op_machine_options = machine_data{job_id}{op_num};
nM = size(op_machine_options, 1);
if machine_idx > nM, machine_idx = nM; end

actual_machine  = op_machine_options(machine_idx, 1) + 1;
processing_time = op_machine_options(machine_idx, 2);

op_fixture_options = fixture_data{job_id}{op_num};
nF = size(op_fixture_options, 1);
if fixture_idx > nF, fixture_idx = nF; end

actual_fixture = op_fixture_options(fixture_idx, 1) + 1;
end
