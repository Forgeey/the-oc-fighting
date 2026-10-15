class_name DemoFighterComboInput
extends RefCounted

## 管理 Demo 特有的取消输入缓冲，并读取已安装目标招式配置的按键或序列指令。
var fighter: DemoFighter
var input_advancer: FrayBufferedInputAdvancer
var input_window_open := false
var input_window_started_at_msec := 0
var cancel_window_open := false
var source_move_id: StringName = &""
var matched_cancel_inputs: Dictionary = {}


## 保存运行所需依赖并完成初始化。
func setup(p_fighter: DemoFighter, p_input_advancer: FrayBufferedInputAdvancer) -> void:
	fighter = p_fighter
	input_advancer = p_input_advancer


## 打开取消窗口。
func open_cancel_window(p_source_move_id: StringName) -> void:
	input_window_open = true
	input_window_started_at_msec = (
		input_advancer.get_buffer_clock_msec()
	)
	cancel_window_open = false
	source_move_id = p_source_move_id


## 更新取消窗口。
func update_cancel_window(attack: FrayAttackAttribute, attack_frame: int) -> void:
	cancel_window_open = input_window_open and attack.is_cancel_frame(attack_frame)


## 关闭窗口。
func close_window(clear_buffer := false) -> void:
	input_window_open = false
	cancel_window_open = false
	input_window_started_at_msec = 0
	source_move_id = &""
	if clear_buffer:
		input_advancer.clear_buffer()
		matched_cancel_inputs.clear()


## 仅消费触发本次 Fray 取消转移的输入，保留之后录入的连续技指令。
## 消费触发取消转移的输入缓冲。
func consume_buffer(target_move_id: StringName) -> void:
	var matched_input: FrayBufferedInputAdvancer.BufferedInput = (
		matched_cancel_inputs.get(target_move_id) as FrayBufferedInputAdvancer.BufferedInput
	)
	if matched_input == null or not input_advancer.discard_buffer_through(matched_input):
		input_advancer.clear_buffer()
	elif input_window_open:
		input_window_started_at_msec = matched_input.time_stamp
	matched_cancel_inputs.clear()


## 非取消转移会清除匹配缓存；取消转移由 consume_buffer 消费对应输入。
## 清除已经匹配的取消输入缓存。
func clear_matched_cancel_inputs() -> void:
	matched_cancel_inputs.clear()


## 判断当前攻击帧是否允许执行取消。
func can_cancel_now() -> bool:
	return cancel_window_open


## 判断缓冲中是否存在指定取消目标的输入。
func has_buffered_cancel_to(target_move_id: StringName) -> bool:
	if not input_window_open or not fighter.move_loadout.can_cancel_to_move(source_move_id, target_move_id):
		return false
	var command := fighter.move_loadout.get_command(target_move_id)
	var expected_press := fighter.fray_input(command.get_simple_input()) if command.is_simple_press() else &""
	var expected_sequence := fighter.fray_input(DemoFighterLoadout.get_sequence_input_name(target_move_id))
	for buffered_input in input_advancer.get_buffer():
		if buffered_input.time_stamp < input_window_started_at_msec:
			continue
		if buffered_input is FrayBufferedInputAdvancer.BufferedInputPress:
			if expected_press != &"" and buffered_input.input == expected_press and buffered_input.is_pressed:
				matched_cancel_inputs[target_move_id] = buffered_input
				return true
		elif buffered_input is FrayBufferedInputAdvancer.BufferedInputSequence:
			if not command.is_simple_press() and buffered_input.sequence_name == expected_sequence:
				matched_cancel_inputs[target_move_id] = buffered_input
				return true
	return false
