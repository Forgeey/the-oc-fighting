class_name FighterInput
extends Node
## 每角色输入适配：复用 Fray 的采样与序列匹配。
## priority -50：位于 FrayInput(-100) 之后、状态物理更新(0)之前。

var controller: FrayController
var facing_dir: int = 1
var _moves: Array[FighterMoveDefinition] = []
var _matchers: Dictionary = {}
var _combination_names: Dictionary = {}
var _combination_active: Dictionary = {}
var _events: Array[FrayInputEvent] = []
var _candidates: Array[Dictionary] = []
var _press_frames: Dictionary = {}
var _press_ids: Dictionary = {}
var _consumed_ids: Dictionary = {}
## 已确认特殊指令的按键周期；候选过期或暂不能执行也不回退普通攻击。
var _special_ids: Dictionary = {}
var _event_id := 0
var _direction := 5
var _direction_pressed_ms := 0
var _facing_at_sample := 1
var _horizontal_axis := 0.0
var _crouch_pressed := false
var _active_source_ids: Array[int] = []
var _device := 0
var _suspended := false


func _ready() -> void:
	process_physics_priority = -50
	FrayInput.input_detected.connect(_on_fray_input_input_detected)


func configure(input_controller: FrayController, moves: Array[FighterMoveDefinition]) -> void:
	controller = input_controller
	_device = controller.device
	_moves.assign(moves)
	_combination_names.clear()
	for move in _moves:
		if move.command.input_kind != FighterCommandDefinition.InputKind.COMBINATION:
			continue
		var buttons := move.command.buttons.duplicate()
		buttons.sort()
		var name := StringName("game_combo_" + "_".join(buttons))
		if not FrayInputMap.has_input(name):
			var combination := FrayCombinationInput.builder().mode_async()
			for button in buttons:
				combination.add_component_simple(button)
			FrayInputMap.add_composite_input(name, combination.build())
		_combination_names[move.move_id] = name
	clear_history()


func _physics_process(_delta: float) -> void:
	sample()


## 仅由本节点 _physics_process 调用一次；controller 由 Fighter 初始化时配置。
func sample() -> void:
	var frame := Engine.get_physics_frames()
	if _device != controller.device:
		_device = controller.device
		clear_history()
	if _suspended or controller.disabled or not controller.is_device_connected():
		clear_history()
		return

	var axis := controller.get_axis(&"move_left", &"move_right")
	var vertical := controller.get_axis(&"move_down", &"move_up")
	_horizontal_axis = axis
	# 行为意图只读取 crouch；与默认同键的 move_down 方向保持解耦。
	_crouch_pressed = controller.is_pressed(&"crouch")
	var horizontal_dir := int(signf(axis)) * facing_dir
	var vertical_dir := int(signf(vertical))
	var direction := 5 + horizontal_dir + vertical_dir * 3
	if _facing_at_sample != facing_dir:
		# 换面向不凭空制造动作，也不保留跨朝向的半条指令。
		_reset_matchers()
		_direction = direction
		_direction_pressed_ms = Time.get_ticks_msec()
		_facing_at_sample = facing_dir
	elif direction != _direction:
		_feed_direction(_direction, false)
		_direction = direction
		_direction_pressed_ms = Time.get_ticks_msec()
		_feed_direction(_direction, true)

	for event in _events:
		var ids: Array[int] = []
		if event.is_pressed():
			_event_id += 1
			_press_ids[event.input] = _event_id
			_press_frames[event.input] = frame
		if _press_ids.has(event.input):
			ids.append(_press_ids[event.input])
		# 先让序列确认特殊指令；命中后，同源普通单键不会生成候选。
		_feed_sequences(event, ids)
		for move in _moves:
			var command := move.command
			if command.input_kind == FighterCommandDefinition.InputKind.SINGLE:
				var pressed := command.trigger == FighterCommandDefinition.Trigger.PRESS
				if event.input == command.buttons[0] and event.is_pressed() == pressed:
					_add_candidate(move.move_id, ids)
	_events.clear()
	_sample_combinations()
	_candidates = _candidates.filter(func(candidate: Dictionary) -> bool:
		return frame <= candidate.expires_frame)
	# 只保留仍与当前按键周期关联的消费标识，避免运行越久字典越大。
	var retained: Dictionary = {}
	var retained_special: Dictionary = {}
	for id in _press_ids.values():
		if _consumed_ids.has(id):
			retained[id] = true
		if _special_ids.has(id):
			retained_special[id] = true
	_consumed_ids = retained
	_special_ids = retained_special


func get_horizontal_axis() -> float:
	return _horizontal_axis


func inputed_fwalk() -> bool:
	return not inputed_crouch() and _horizontal_axis * facing_dir > 0.1


func inputed_bwalk() -> bool:
	return not inputed_crouch() and _horizontal_axis * facing_dir < -0.1


func inputed_crouch() -> bool:
	return _crouch_pressed


func get_direction() -> int:
	return _direction


## 只过滤尚在组合键等待窗口内的普通单键；候选保持生成顺序，不做评分排序。
func get_candidates() -> Array[Dictionary]:
	var frame := Engine.get_physics_frames()
	var result: Array[Dictionary] = []
	for candidate in _candidates:
		if frame < candidate.ready_frame:
			continue
		result.append(candidate)
	return result


func consume(candidate: Dictionary) -> void:
	var ids: Array = candidate.source_ids
	for id in ids:
		_consumed_ids[id] = true
	_candidates = _candidates.filter(func(other: Dictionary) -> bool:
		return not _overlaps(other.source_ids, ids))
	_reset_matchers()


## 窗口允许的最低输入帧由阶段状态查询 candidate.created_frame，不自动重用旧按键。
func clear_history() -> void:
	_events.clear()
	_candidates.clear()
	_press_frames.clear()
	_press_ids.clear()
	_consumed_ids.clear()
	_special_ids.clear()
	_combination_active.clear()
	_horizontal_axis = 0.0
	_crouch_pressed = false
	_direction = 5
	_direction_pressed_ms = Time.get_ticks_msec()
	_facing_at_sample = facing_dir
	_reset_matchers()


func _reset_matchers() -> void:
	_matchers.clear()
	for move in _moves:
		if move.command.input_kind == FighterCommandDefinition.InputKind.SEQUENCE:
			var matcher := FraySequenceMatcher.new()
			# 游戏侧分流方向与按钮，特殊指令确认后才允许普通单键回退。
			matcher.can_ignore_indistinct_inputs = false
			matcher.initialize(move.command.create_sequence(move.move_id))
			matcher.match_found.connect(_on_sequence_match_found)
			_matchers[move.move_id] = matcher


func _on_fray_input_input_detected(event: FrayInputEvent) -> void:
	if _suspended or controller.disabled:
		return
	if event.device != controller.device or event.is_echo():
		return
	# 方向从同帧轴快照产生；别名 jump/crouch 不送入方向序列。
	if event.input in FighterCommandDefinition.BUTTONS:
		_events.append(event)


func _feed_direction(direction: int, pressed: bool) -> void:
	var event := FrayInputEvent.new()
	event.input = StringName("dir_%d" % direction)
	event.device = _device
	event.physics_frame = Engine.get_physics_frames()
	event.time_pressed = _direction_pressed_ms
	event.time_detected = Time.get_ticks_msec()
	event._is_pressed = pressed
	event._is_distinct = true
	_feed_sequences(event, [])


func _feed_sequences(event: FrayInputEvent, ids: Array[int]) -> void:
	_active_source_ids = ids
	for move in _moves:
		if move.command.input_kind != FighterCommandDefinition.InputKind.SEQUENCE:
			continue
		# jump/crouch 默认是方向别名；只有指令作者显式写入才发送。
		if event.input in [&"jump", &"crouch"] and not event.input in move.command.steps:
			continue
		_matchers[move.move_id].read(event)
	_active_source_ids = []


func _on_sequence_match_found(move_id: StringName) -> void:
	_add_candidate(move_id, _active_source_ids)


func _sample_combinations() -> void:
	var frame := Engine.get_physics_frames()
	for move in _moves:
		if move.command.input_kind != FighterCommandDefinition.InputKind.COMBINATION:
			continue
		var held := controller.is_pressed(_combination_names[move.move_id])
		if held and not _combination_active.get(move.move_id, false):
			var earliest := frame
			var latest := -1
			var ids: Array[int] = []
			for button in move.command.buttons:
				if not _press_frames.has(button):
					ids.clear()
					break
				earliest = mini(earliest, _press_frames[button])
				latest = maxi(latest, _press_frames[button])
				ids.append(_press_ids[button])
			if ids.size() == move.command.buttons.size() and latest - earliest <= move.command.combination_window_frames:
				_add_candidate(move.move_id, ids)
		_combination_active[move.move_id] = held


func _add_candidate(move_id: StringName, ids: Array[int]) -> void:
	if ids.is_empty():
		return
	for id in ids:
		if _consumed_ids.has(id) or _special_ids.has(id):
			return
	for candidate in _candidates:
		if candidate.move.move_id == move_id and candidate.source_ids == ids:
			return
	var move: FighterMoveDefinition
	for selected in _moves:
		if selected.move_id == move_id:
			move = selected
			break
	var frame := Engine.get_physics_frames()
	var ready_frame := frame
	if move.command.input_kind == FighterCommandDefinition.InputKind.SINGLE:
		ready_frame += move.command.resolve_delay_frames
	else:
		# 特殊指令确定归属后，撤销仍在缓冲中的同源普通单键。
		# 组合键可以在普通单键的等待窗口内接管首次按下的按钮。
		for id in ids:
			_special_ids[id] = true
		_candidates = _candidates.filter(func(candidate: Dictionary) -> bool:
			return not _overlaps(candidate.source_ids, ids))
	_candidates.append({move = move, source_ids = ids.duplicate(), created_frame = frame,
		ready_frame = ready_frame, expires_frame = frame + move.command.buffer_frames})


func _overlaps(first: Array, second: Array) -> bool:
	for id in first:
		if id in second:
			return true
	return false


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_suspended = true
		clear_history()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_suspended = false
		clear_history()
