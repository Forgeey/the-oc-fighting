class_name FighterInput
extends Node
## 将设备输入解释为移动意图和逻辑命令，交给 Fray 推进状态机。

@export_range(0, 60) var buffer_frames: int = 6
var controller: FrayController
var advancer: FrayBufferedInputAdvancer
## 由 Fighter 在帧末发布，采样期间保持不变。
var facing_dir: int = 1
var _device := 0
var _suspended := false
var _commands: Array[FighterCommandDefinition] = []
var _combination_names: Dictionary = {}
var _combination_active: Dictionary = {}
## 每个角色共用一个 Matcher，清历史时不重建。
var matcher := FraySequenceMatcher.new()
var _sequence_tree: FraySequenceTree
var _routes: Dictionary = {}
var _sequence_aliases: Array[StringName] = []
var _events: Array[FrayInputEvent] = []
var _held: Dictionary = {}
var _press_ids: Dictionary = {}
var _press_frames: Dictionary = {}
var _claimed_ids: Dictionary = {}
var _event_sources: Dictionary = {}
var _event_serial := 0
## 暂存等待组合判定的单键，不保存失败重试命令。
var _pending_singles: Array[Dictionary] = []
var _horizontal_axis := 0.0
var _crouch_pressed := false
var _forward_pressed := false
var _backward_pressed := false
var _direction := 5
var _direction_pressed_ms := 0
var _direction_sources: Array[int] = []
var _vertical_input: StringName = &""


#region 初始化与设备绑定

## 设置采样顺序，并连接输入和匹配信号。
func _ready() -> void:
	process_physics_priority = -50
	FrayInput.input_detected.connect(_collect_input_event)
	matcher.match_found.connect(_on_world_route_match)


## 绑定设备和依赖，并按已选招式编译输入指令。
func configure(input_controller: FrayController, moves: Array[FighterMoveDefinition], input_advancer: FrayBufferedInputAdvancer) -> void:
	FighterInputBindings.unbind_device(_device, self)
	controller = input_controller
	advancer = input_advancer
	_device = controller.device
	_commands.clear()
	var command_ids := {}
	for move in moves:
		var command := move.command
		if not command_ids.has(command.command_id):
			command_ids[command.command_id] = true
			_commands.append(command)
	_combination_names = FighterInputBindings.register_inputs(FrayInputMap, _commands)
	_compile_sequences()
	matcher.can_ignore_indistinct_inputs = false
	matcher.initialize(_sequence_tree)
	advancer.max_buffer_time = frames_to_seconds(buffer_frames)
	clear_history()
	set_physics_process(FighterInputBindings.bind_device(_device, self))


## 发布合法朝向，设备变化时换绑并清理历史。
func publish_context(direction: int) -> void:
	facing_dir = direction
	if _device != controller.device:
		FighterInputBindings.unbind_device(_device, self)
		_device = controller.device
		set_physics_process(FighterInputBindings.bind_device(_device, self))
		clear_history()


## 检查焦点、设备连接和当前角色的输入权限。
func _can_receive_input() -> bool:
	return not _suspended and not controller.disabled \
		and _device == controller.device and controller.is_device_connected() \
		and FighterInputBindings.get_device_input(_device) == self


## 将物理帧数换算为小数秒。
static func frames_to_seconds(frames: int) -> float:
	# Fray.frame_to_sec 当前返回整数，短窗口不能直接用它。
	return float(frames) / Engine.physics_ticks_per_second


#endregion


#region 输入采样

## 每个物理帧采样一次角色输入。
func _physics_process(_delta: float) -> void:
	sample()


## 收集本设备的有效输入事件，留到采样时统一处理。
func _collect_input_event(event: FrayInputEvent) -> void:
	if not _can_receive_input():
		return
	if event.device == _device and not event.is_echo() and event.input in FighterInputBindings.ACTIONS:
		_events.append(event)


## 整理本帧事件，按序列、组合键、单键顺序识别并提交命令。
func sample() -> void:
	if not _can_receive_input():
		clear_history()
		return
	_horizontal_axis = controller.get_axis(&"move_left", &"move_right")
	_crouch_pressed = controller.is_pressed(&"crouch")
	_forward_pressed = controller.is_pressed(FighterInputBindings.FORWARD)
	_backward_pressed = controller.is_pressed(FighterInputBindings.BACKWARD)
	var events: Array[FrayInputEvent] = []
	for event in _events:
		if bool(_held.get(event.input, false)) == event.is_pressed():
			continue
		_held[event.input] = event.is_pressed()
		if event.is_pressed():
			_event_serial += 1
			_press_ids[event.input] = _event_serial
			_press_frames[event.input] = Engine.get_physics_frames()
		var ids: Array[int] = []
		if _press_ids.has(event.input):
			ids.append(_press_ids[event.input])
		_remember_sources(event, ids)
		events.append(event)
	_events.clear()

	# 全部序列使用同一规范方向流：斜方向一个步骤，上下重叠按新按下方向。
	_sample_direction(events)
	for event in events:
		if not event.input in FighterCommandDefinition.BUTTONS:
			continue
		# 全角色统一规则：未在任何序列显式声明的方向行为别名不送 Matcher。
		if event.input in [&"jump", &"crouch"] and not event.input in _sequence_aliases:
			continue
		matcher.read(event)

	# 所有特殊序列先确认，再处理同时键和普通单键，入队后不再撤回。
	_sample_combinations()
	for event in events:
		for command in _commands:
			if command.input_kind != FighterCommandDefinition.InputKind.SINGLE:
				continue
			var pressed := command.trigger == FighterCommandDefinition.Trigger.PRESS
			if event.input == command.buttons[0] and event.is_pressed() == pressed and _matches_direction(command):
				var ids := _sources(event)
				if not ids.is_empty() and not _is_claimed(ids):
					_pending_singles.append({command = command, ids = ids,
						ready = Engine.get_physics_frames() + command.resolve_delay_frames})
	var waiting: Array[Dictionary] = []
	for pending in _pending_singles:
		if _is_claimed(pending.ids):
			continue
		if Engine.get_physics_frames() < pending.ready:
			waiting.append(pending)
		else:
			_enqueue(pending.command, pending.ids)
	_pending_singles = waiting
	_prune_sources()


#endregion


#region 持续移动意图

## 按蹲下优先、左右抵消的规则返回移动意图。
func get_movement_intent() -> StringName:
	if _crouch_pressed:
		return &"crouch"
	if _forward_pressed and not _backward_pressed:
		return &"fwalk"
	if _backward_pressed and not _forward_pressed:
		return &"bwalk"
	return &"idle"


## 判断当前移动意图是否符合指定名称。
func has_intent(intent: StringName) -> bool:
	return get_movement_intent() == intent


## 返回指定移动意图对应的水平输入量。
func get_movement_axis(intent: StringName) -> float:
	return _horizontal_axis if not _crouch_pressed and has_intent(intent) else 0.0


#endregion


#region 方向规范化

## 合成统一方向，同帧上下输入按“下→上”处理。
func _sample_direction(events: Array[FrayInputEvent]) -> void:
	var horizontal := int(signf(_horizontal_axis))
	var vertical_presses: Array[FrayInputEvent] = []
	for event in events:
		if event.is_pressed() and event.input in [&"move_down", &"move_up"]:
			vertical_presses.append(event)
	vertical_presses.sort_custom(func(a: FrayInputEvent, b: FrayInputEvent) -> bool:
		if a.physics_frame != b.physics_frame:
			return a.physics_frame < b.physics_frame
		return a.input == &"move_down" and b.input == &"move_up")
	for event in vertical_presses:
		_vertical_input = event.input
		var vertical := -1 if event.input == &"move_down" else 1
		_change_direction(5 + horizontal + vertical * 3)
	# 松开当前垂直方向后，回到仍按住的一侧；这不会新建物理来源周期。
	if not _held.get(_vertical_input, false):
		_vertical_input = &""
		for input in [&"move_down", &"move_up"]:
			if _held.get(input, false):
				_vertical_input = input
	var vertical := 0
	if _vertical_input == &"move_down": vertical = -1
	elif _vertical_input == &"move_up": vertical = 1
	_change_direction(5 + horizontal + vertical * 3)


## 方向变化时结束旧方向，并记录新方向及其按键来源。
func _change_direction(direction: int) -> void:
	if direction == _direction:
		return
	_feed_motion(_direction, false)
	_direction = direction
	_direction_pressed_ms = Time.get_ticks_msec()
	_direction_sources.clear()
	var horizontal := (direction - 1) % 3 - 1
	var vertical := int((direction - 1) / 3.0) - 1
	var components: Array[StringName] = []
	if horizontal != 0: components.append(&"move_left" if horizontal < 0 else &"move_right")
	if vertical != 0: components.append(&"move_down" if vertical < 0 else &"move_up")
	for input in components:
		if _press_ids.has(input): _direction_sources.append(_press_ids[input])
	_feed_motion(_direction, true)


## 生成世界方向事件并交给序列匹配器。
func _feed_motion(direction: int, pressed: bool) -> void:
	if direction == 5:
		return
	var event := FrayInputEvent.new()
	event.input = StringName("world_%d" % direction)
	event.device = _device
	event.physics_frame = Engine.get_physics_frames()
	event.time_pressed = _direction_pressed_ms
	event.time_detected = Time.get_ticks_msec()
	event._is_pressed = pressed
	event._is_distinct = true
	_remember_sources(event, _direction_sources)
	matcher.read(event)


#endregion


#region 指令识别

## 将左右序列合入一棵树，共享路径保留各指令的精确条件。
func _compile_sequences() -> void:
	_sequence_tree = FraySequenceTree.new()
	_routes.clear()
	_sequence_aliases.clear()
	var routes_by_path := {}
	for command in _commands:
		if command.input_kind != FighterCommandDefinition.InputKind.SEQUENCE:
			continue
		for alias in [&"jump", &"crouch"]:
			if alias in command.steps and not alias in _sequence_aliases:
				_sequence_aliases.append(alias)
		for facing in [1, -1]:
			# 相同路径在原生树只注册一次；精确分支与共享包络独立持有。
			var branch := command.create_branch(facing)
			var path: Array[String] = []
			for requirement in branch.input_requirements:
				path.append("%s:%s" % [requirement.input, requirement.is_charge_input()])
			var key := ",".join(path)
			if not routes_by_path.has(key):
				var route := StringName("route_%d" % routes_by_path.size())
				routes_by_path[key] = route
				var shared := command.create_branch(facing)  # 独立包络，不能修改精确校验分支。
				_routes[route] = {branch = shared, entries = []}
				_sequence_tree.add(route, shared)
			var metadata: Dictionary = _routes[routes_by_path[key]]
			# 同一原生终点只注册一次：识别用宽包络，命中后用原生 is_match
			# 复核各命令的真实时限／蓄力，不因时间参数不同而创建第二 Matcher。
			for index in branch.input_requirements.size():
				var shared: FrayInputRequirement = metadata.branch.input_requirements[index]
				var exact: FrayInputRequirement = branch.input_requirements[index]
				shared.max_delay = maxi(shared.max_delay, exact.max_delay)
				shared.min_time_held = mini(shared.min_time_held, exact.min_time_held)
			metadata.branch.is_negative_edge_enabled = metadata.branch.is_negative_edge_enabled or branch.is_negative_edge_enabled
			metadata.entries.append({command = command, facing = facing, branch = branch})


## 按当前朝向和精确时限复核序列命中，再提交对应命令。
func _on_world_route_match(route: StringName) -> void:
	var events := matcher.get_match_branch().duplicate()
	var ids: Array[int] = []
	for event in events:
		for id in _sources(event):
			if not id in ids:
				ids.append(id)
	for entry in _routes[route].entries:
		if entry.facing != facing_dir:
			continue
		if not events.back().is_pressed() and not entry.branch.is_negative_edge_enabled and not entry.branch.input_requirements.back().is_charge_input():
			continue
		if FraySequenceMatcher.is_match(events, entry.branch.input_requirements):
			_enqueue(entry.command, ids)
			return


## 检查多按钮组合的新触发、按下间隔和方向限制。
func _sample_combinations() -> void:
	for command in _commands:
		if command.input_kind != FighterCommandDefinition.InputKind.COMBINATION:
			continue
		var held := controller.is_pressed(_combination_names[command.command_id])
		if held and not _combination_active.get(command.command_id, false) and _matches_direction(command):
			var earliest := Engine.get_physics_frames()
			var latest := -1
			var ids: Array[int] = []
			for button in command.buttons:
				if not _press_frames.has(button): break
				earliest = mini(earliest, _press_frames[button])
				latest = maxi(latest, _press_frames[button])
				ids.append(_press_ids[button])
			if ids.size() == command.buttons.size() and latest - earliest <= command.combination_window_frames:
				_enqueue(command, ids)
		_combination_active[command.command_id] = held


## 检查按钮触发时的相对方向是否符合指令。
func _matches_direction(command: FighterCommandDefinition) -> bool:
	if command.required_direction == 0:
		return true
	var relative := _direction
	if facing_dir < 0:
		relative += 2 - 2 * ((relative - 1) % 3)
	return relative == command.required_direction


#endregion


#region 按键来源与命令提交

## 记录输入事件对应的物理按键来源。
func _remember_sources(event: FrayInputEvent, ids: Array[int]) -> void:
	_event_sources[event.get_instance_id()] = {event = weakref(event), ids = ids.duplicate()}


## 读取输入事件已登记的按键来源。
func _sources(event: FrayInputEvent) -> Array[int]:
	var result: Array[int] = []
	result.assign(_event_sources[event.get_instance_id()].ids)
	return result


## 检查来源中是否有按键已被其他命令消费。
func _is_claimed(ids: Array) -> bool:
	for id in ids:
		if _claimed_ids.has(id): return true
	return false


## 认领未消费的按键，并将逻辑命令交给 Fray 推进器。
func _enqueue(command: FighterCommandDefinition, ids: Array) -> void:
	if ids.is_empty() or _is_claimed(ids):
		return
	for id in ids:
		_claimed_ids[id] = true
	advancer.buffer_sequence(command.command_id)


## 回收失效事件及不再使用的按键认领记录。
func _prune_sources() -> void:
	var live_ids := {}
	for id in _press_ids.values(): live_ids[id] = true
	for key in _event_sources.keys():
		var entry: Dictionary = _event_sources[key]
		if entry.event.get_ref() == null:
			_event_sources.erase(key)
		else:
			for id in entry.ids: live_ids[id] = true
	for id in _claimed_ids.keys():
		if not live_ids.has(id): _claimed_ids.erase(id)


#endregion


#region 历史清理与生命周期

## 清空输入与缓冲记录，保留现有 Matcher 和匹配树。
func clear_history() -> void:
	_events.clear()
	_pending_singles.clear()
	_held.clear()
	_press_ids.clear()
	_press_frames.clear()
	_claimed_ids.clear()
	_event_sources.clear()
	_combination_active.clear()
	_horizontal_axis = 0.0
	_forward_pressed = false
	_backward_pressed = false
	_crouch_pressed = false
	_direction = 5
	_direction_pressed_ms = Time.get_ticks_msec()
	_direction_sources.clear()
	_vertical_input = &""
	matcher.clear_history()
	advancer.clear_buffer()


## 失焦时暂停收集输入，焦点变化时清理历史。
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_suspended = true
		clear_history()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_suspended = false
		clear_history()


## 离场时解除设备绑定并清理输入历史。
func _exit_tree() -> void:
	FighterInputBindings.unbind_device(_device, self)
	clear_history()


#endregion
