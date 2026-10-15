class_name FoundationFighter
extends CharacterBody2D
## Fray fighter foundation 角色入口。
##
## 本脚本只负责依赖装配、集中外部战斗事件、回合生命周期与调试投影；
## 状态拓扑由 FighterStateMachineBuilder 独占，攻击帧数据由 FrayAttackAttribute 独占。

signal foundation_ready(success: bool)
signal debug_snapshot_changed(snapshot: Dictionary)
## 朝向发生变化时发出；表现层可据此播放独立的转身动画，无需占用战斗状态。
signal facing_changed(from_direction: int, to_direction: int)

const DEBUG_INPUT_HISTORY_LIMIT: int = 18
const DEBUG_STATE_HISTORY_LIMIT: int = 12
const DEBUG_MOVE_HISTORY_LIMIT: int = 10
const AUTO_FACING_STATES := [&"idle", &"walk_forward", &"walk_back", &"crouch", &"stand_guard", &"crouch_guard"]
const ACTION_DISPLAY_NAMES := {
	&"idle": "站立待机",
	&"walk_forward": "前进行走",
	&"walk_back": "后退行走",
	&"crouch": "下蹲",
	&"stand_guard": "站立防御",
	&"crouch_guard": "下蹲防御",
	&"jump_start": "起跳准备",
	&"jump": "空中上升",
	&"double_jump": "二段跳",
	&"fall": "下落",
	&"land": "落地恢复",
	&"dash_forward": "前冲",
	&"dash_back": "后撤",
	&"stand_light": "站立轻攻击",
	&"stand_heavy": "站立重攻击",
	&"crouch_light": "下蹲轻攻击",
	&"crouch_heavy": "下蹲重攻击",
	&"air_light": "空中轻攻击",
	&"air_heavy": "空中重攻击",
	&"hitstun": "地面受击硬直",
	&"air_hitstun": "空中受击硬直",
	&"blockstun": "格挡硬直",
	&"knockdown": "倒地",
	&"tech_roll": "受身翻滚",
	&"wakeup": "起身恢复",
	&"ko": "KO",
	&"locked": "控制锁定",
}
const MOVE_DEFINITIONS := {
	&"jump_start": {"name": "跳跃", "command": "8 / W"},
	&"double_jump": {"name": "二段跳", "command": "空中 8 / W"},
	&"dash_forward": {"name": "前冲", "command": "66"},
	&"dash_back": {"name": "后撤", "command": "44"},
	&"stand_light": {"name": "站立轻攻击", "command": "J"},
	&"stand_heavy": {"name": "站立重攻击", "command": "K"},
	&"crouch_light": {"name": "下蹲轻攻击", "command": "2J"},
	&"crouch_heavy": {"name": "下蹲重攻击", "command": "2K"},
	&"air_light": {"name": "空中轻攻击", "command": "空中 J"},
	&"air_heavy": {"name": "空中重攻击", "command": "空中 K"},
	&"tech_roll": {"name": "受身", "command": "软倒地窗口 Q"},
}
const STATE_COLORS := {
	&"neutral": Color(0.2, 0.65, 1.0, 1.0),
	&"movement": Color(0.3, 0.8, 1.0, 1.0),
	&"defense": Color(0.2, 0.9, 0.75, 1.0),
	&"attack": Color(1.0, 0.45, 0.18, 1.0),
	&"reaction": Color(0.9, 0.25, 0.55, 1.0),
	&"downed": Color(0.55, 0.55, 0.65, 1.0),
	&"ko": Color(0.22, 0.22, 0.28, 1.0),
	&"locked": Color(0.45, 0.45, 0.5, 1.0),
}

## 舞台边界与角色运动物理的唯一环境资源。
@export var environment: FoundationFighterEnvironment

## 角色当前世界朝向；1 表示向右，-1 表示向左。
@export_enum("Left:-1", "Right:1") var facing_direction: int = 1

## 调试受击按键使用的 FrayAttackAttribute；正式战斗应传入实际 strike attribute。
@export var debug_reaction_attribute: FrayAttackAttribute

## 调试倒地按键使用的软倒地 FrayAttackAttribute。
@export var debug_knockdown_attribute: FrayAttackAttribute

## 演示用对手标记路径；正式对手解析属于后续项目。
@export_node_path("Node2D") var opponent_marker_path: NodePath

@onready var controller: FrayController = $FrayController
@onready var state_machine: FrayStateMachine = $FrayStateMachine
@onready var input_advancer: FrayBufferedInputAdvancer = $FrayStateMachine/FrayBufferedInputAdvancer
@onready var _visual: Polygon2D = $Visual
@onready var _facing_indicator: Polygon2D = $FacingIndicator
@onready var _attack_hit_state_manager: FrayHitStateManager2D = $AttackHitStateManager
@onready var _hurt_hit_state: FrayHitState2D = $HurtState

var _movement := FoundationMovement.new()
var _input_setup := FoundationInputSetup.new()
var _opponent_marker: Node2D
var _fray_input: _FrayInput
var _initialized: bool = false
var _control_locked: bool = false
var _simulation_paused: bool = false
var _tech_roll_available: bool = false
var _pending_reaction_attribute: FrayAttackAttribute
var _attack_hit_states: Dictionary = {}
var _attack_attributes: Dictionary = {}
var _last_transition_from: StringName = &""
var _last_transition_to: StringName = &""
var _last_lock_reason: StringName = &""
var _last_move: Dictionary = {}
var _input_history: Array[Dictionary] = []
var _state_history: Array[Dictionary] = []
var _move_history: Array[Dictionary] = []


## 初始化输入、移动、Fray hit states 和 Fray 状态机；失败时禁用角色处理。
func _ready() -> void:
	var success := initialize_fighter()
	foundation_ready.emit(success)
	if not success:
		set_physics_process(false)


## 在子节点状态机处理前刷新 grounded 快照和朝向显示。
func _physics_process(_delta: float) -> void:
	if _simulation_paused:
		return
	_movement.refresh_snapshot()
	_update_facing_toward_opponent()
	_sync_facing_visual()
	debug_snapshot_changed.emit(get_debug_snapshot())


## 场景退出时停止 Fray singleton 监听，避免重复回调。
func _exit_tree() -> void:
	_input_setup.shutdown_input()
	if not _initialized:
		return
	_disconnect_debug_input_listener()
	state_machine.state_changed.disconnect(Callable(self, "_on_state_changed"))


## 创建只读 context、Root，连接信号并启动 fighter。
func initialize_fighter() -> bool:
	if _initialized:
		return true
	var fray_input := get_node_or_null("/root/FrayInput") as _FrayInput
	if get_node_or_null("/root/FrayInputMap") == null or fray_input == null:
		push_error("Fray autoload 缺失：请启用 res://addons/fray/plugin.cfg 并重新打开项目。")
		return false
	if environment == null:
		push_error("FoundationFighter 缺少 environment。")
		return false
	if debug_reaction_attribute == null:
		push_error("FoundationFighter 缺少 debug_reaction_attribute。")
		return false
	if debug_knockdown_attribute == null:
		push_error("FoundationFighter 缺少 debug_knockdown_attribute。")
		return false
	var config_errors := environment.validate()
	if not config_errors.is_empty():
		for message in config_errors:
			push_error("FighterEnvironment：%s" % message)
		return false

	_opponent_marker = get_node_or_null(opponent_marker_path) as Node2D
	_movement.setup(self, environment)
	if not _collect_attack_hit_states():
		return false
	_hurt_hit_state.set_hitbox_source(self)
	_hurt_hit_state.activate()
	_hurt_hit_state.active_hitboxes = 1
	_sync_facing_visual()
	if not _input_setup.configure_input_map(&"p1_", self):
		return false
	var sequence_tree := _input_setup.create_dash_sequences(&"p1_")

	var context := {
		"fighter": self,
		"movement": _movement,
		"environment": environment,
		"controller": controller,
	}
	var root := FighterStateMachineBuilder.new().build_root(context)
	if root == null:
		return false
	var callback := Callable(self, "_on_state_changed")
	if not state_machine.state_changed.is_connected(callback):
		state_machine.state_changed.connect(callback)
	state_machine.initialize(context, root)
	state_machine.active = true
	if not _input_setup.bind_advancer(controller, input_advancer, sequence_tree):
		state_machine.active = false
		return false
	_connect_debug_input_listener(fray_input)
	_initialized = true
	_sync_state_visual(state_machine.get_current_state_name())
	return true


## 集中进入或退出 locked；重复值幂等。
func set_control_locked(locked: bool, reason: StringName = &"external") -> void:
	if not _initialized or _control_locked == locked:
		return
	_control_locked = locked
	_last_lock_reason = reason
	controller.disabled = locked
	input_advancer.clear_buffer()
	if locked:
		_movement.stop()
		state_machine.goto(&"locked", {"reason": reason})
	else:
		state_machine.goto_start({"reason": reason})


## 返回当前集中控制锁定值，供 Fray condition 只读查询。
func is_control_locked() -> bool:
	return _control_locked



## 在允许自动改向的地面状态中同步对手方向；转身动画由表现层监听 facing_changed 播放。
func _update_facing_toward_opponent() -> void:
	if _opponent_marker == null or not _movement.is_grounded():
		return
	if state_machine.get_current_state_name() not in AUTO_FACING_STATES:
		return
	var horizontal_delta := _opponent_marker.global_position.x - global_position.x
	if is_zero_approx(horizontal_delta):
		return
	var next_direction := 1 if horizontal_delta > 0.0 else -1
	if next_direction == facing_direction:
		return
	var previous_direction := facing_direction
	facing_direction = next_direction
	_sync_facing_visual()
	facing_changed.emit(previous_direction, facing_direction)



## 返回 Fray builder 的下落 condition。
func is_falling_for_transition() -> bool:
	return not _movement.is_grounded() and _movement.get_velocity().y >= 0.0



## 返回软倒地受身窗口是否已经开放。
func can_tech_roll() -> bool:
	return _tech_roll_available


## 由倒地状态集中更新受身窗口。
func set_tech_roll_available(available: bool) -> void:
	_tech_roll_available = available


## 返回当前缓存攻击是否要求倒地反应。
func should_knockdown() -> bool:
	return _pending_reaction_attribute != null and _pending_reaction_attribute.causes_knockdown()


## 返回指定攻击状态对应、由 FrayHitStateManager2D 管理的 FrayHitState2D。
func get_attack_hit_state(state_id: StringName) -> FrayHitState2D:
	return _attack_hit_states.get(state_id) as FrayHitState2D


## 返回从指定 FrayHitState2D 子 FrayHitbox2D.attribute 中缓存的唯一攻击属性。
func get_attack_attribute(state_id: StringName) -> FrayAttackAttribute:
	return _attack_attributes.get(state_id) as FrayAttackAttribute


## 集中解析受击来源并缓存 FrayAttackAttribute；空值回退到调试资源。
func resolve_reaction_attribute(value = null) -> FrayAttackAttribute:
	var attribute: FrayAttackAttribute = value as FrayAttackAttribute
	if attribute == null:
		attribute = _pending_reaction_attribute
	if attribute == null:
		attribute = debug_reaction_attribute
	_pending_reaction_attribute = attribute
	return attribute


## 清缓冲、速度、诊断历史和临时窗口，并从 Fray start state 重启回合。
func reset_for_round(spawn: Transform2D, facing: int = 1) -> void:
	if not _initialized:
		push_error("reset_for_round() 在 fighter 初始化前被调用。")
		return
	_input_setup.reset_input_runtime(false)
	_simulation_paused = false
	state_machine.active = true
	_input_setup.set_input_pause(false, false)
	_control_locked = false
	_tech_roll_available = false
	_pending_reaction_attribute = null
	controller.disabled = false
	global_transform = spawn
	_movement.stop()
	facing_direction = 1 if facing >= 0 else -1
	_movement.refresh_snapshot()
	_deactivate_all_attack_hit_states()
	_sync_facing_visual()
	state_machine.goto_start({"reason": &"round_reset"})
	_clear_debug_history()


## 同步状态机处理与 Fray 输入缓冲的暂停语义。
func set_simulation_paused(paused: bool, freeze_buffer_clock: bool) -> void:
	if not _initialized:
		return
	_simulation_paused = paused
	state_machine.active = not paused
	_input_setup.set_input_pause(paused, freeze_buffer_clock)


## 集中接收 hitstun、blockstun、knockdown、wakeup、KO、locked 与 reset 等外部战斗事件。
func request_external_state(kind: StringName, args: Dictionary = {}) -> bool:
	if not _initialized:
		return false
	var reaction_attribute: FrayAttackAttribute
	match kind:
		&"hitstun":
			reaction_attribute = resolve_reaction_attribute(args.get("attribute", debug_reaction_attribute))
			var target := &"air_hitstun" if not _movement.is_grounded() or bool(args.get("airborne", false)) else &"hitstun"
			state_machine.goto(target, {"attribute": reaction_attribute})
			return true
		&"blockstun":
			reaction_attribute = resolve_reaction_attribute(args.get("attribute", debug_reaction_attribute))
			state_machine.goto(&"blockstun", {"attribute": reaction_attribute})
			return true
		&"knockdown":
			reaction_attribute = resolve_reaction_attribute(args.get("attribute", debug_knockdown_attribute))
			state_machine.goto(&"knockdown", {"attribute": reaction_attribute})
			return true
		&"wakeup":
			state_machine.goto(&"wakeup", args)
			return true
		&"ko":
			resolve_reaction_attribute(args.get("attribute", debug_reaction_attribute))
			state_machine.goto(&"ko", args)
			return true
		&"locked":
			set_control_locked(bool(args.get("locked", true)), StringName(args.get("reason", "external")))
			return true
		&"reset":
			reset_for_round(args.get("spawn", global_transform), int(args.get("facing", facing_direction)))
			return true
		_:
			push_warning("不支持外部状态 kind：%s" % kind)
			return false


## 返回状态、招式、运动与输入缓冲的只读调试快照。
func get_debug_snapshot() -> Dictionary:
	if not _initialized:
		return {"valid": false, "reason": "fighter 尚未初始化"}
	var root := state_machine.get_root()
	var state_name := state_machine.get_current_state_name()
	var active_info := root.get_active_states_info()
	return {
		"valid": true,
		"physics_frame": Engine.get_physics_frames(),
		"state": state_name,
		"action": ACTION_DISPLAY_NAMES.get(state_name, String(state_name)),
		"path": active_info.get("path", ""),
		"tags": root.get_state_tags(state_name),
		"velocity": velocity,
		"grounded": _movement.is_grounded(),
		"facing": facing_direction,
		"control_locked": _control_locked,
		"simulation_paused": _simulation_paused,
		"buffer_clock_paused": input_advancer.buffer_clock_paused,
		"lock_reason": _last_lock_reason,
		"device": controller.device,
		"device_connected": controller.is_device_connected(),
		"last_transition": "%s → %s" % [_last_transition_from, _last_transition_to],
		"buffer_clock_msec": input_advancer.get_buffer_clock_msec(),
		"buffer": input_advancer.get_buffer(),
		"input_history": _input_history.duplicate(true),
		"state_history": _state_history.duplicate(true),
		"move_history": _move_history.duplicate(true),
		"last_move": _last_move.duplicate(true),
		"available_moves": _get_available_moves(),
	}


## 从 FrayHitStateManager2D 收集攻击状态，并校验每个状态的 FrayHitbox2D.attribute。
func _collect_attack_hit_states() -> bool:
	_attack_hit_states.clear()
	_attack_attributes.clear()
	_attack_hit_state_manager.source = self
	for child in _attack_hit_state_manager.get_children():
		var hit_state := child as FrayHitState2D
		if hit_state == null:
			push_error("攻击管理器子节点 %s 不是 FrayHitState2D。" % child.name)
			return false

		var state_id := StringName(hit_state.name)
		var attack := _validate_attack_hit_state(state_id, hit_state)
		if attack == null:
			return false
		_attack_hit_states[state_id] = hit_state
		_attack_attributes[state_id] = attack
		hit_state.active_hitboxes = 0
		hit_state.deactivate()

	if _attack_hit_states.is_empty():
		push_error("FrayHitStateManager2D 下没有可用的攻击 FrayHitState2D。")
		return false
	return true


## 校验 FrayHitState2D 直接包含 FrayHitbox2D，且所有 hitbox 共用匹配状态 ID 的攻击资源。
func _validate_attack_hit_state(
	state_id: StringName,
	hit_state: FrayHitState2D
) -> FrayAttackAttribute:
	var hitboxes := hit_state.get_hitboxes()
	if hitboxes.is_empty():
		push_error("攻击状态 %s 下没有 FrayHitbox2D。" % state_id)
		return null

	var result: FrayAttackAttribute
	for hitbox in hitboxes:
		var attack := hitbox.attribute as FrayAttackAttribute
		if attack == null:
			push_error("攻击状态 %s 的 FrayHitbox2D.attribute 必须是 FrayAttackAttribute。" % state_id)
			return null
		if attack.id != state_id:
			push_error("攻击状态 %s 的 attribute.id 必须与状态名一致，当前为 %s。" % [state_id, attack.id])
			return null
		if result != null and result != attack:
			push_error("攻击状态 %s 的所有 FrayHitbox2D 必须引用同一个 FrayAttackAttribute。" % state_id)
			return null
		result = attack
	return result


## 关闭攻击管理器下全部 FrayHitState2D 的 FrayHitbox2D，供 reset 与异常恢复使用。
func _deactivate_all_attack_hit_states() -> void:
	for value in _attack_hit_states.values():
		var hit_state := value as FrayHitState2D
		hit_state.active_hitboxes = 0
		hit_state.deactivate()


## 监听已在初始化入口校验的 FrayInput，仅用于生成只读历史，不参与状态转移。
func _connect_debug_input_listener(fray_input: _FrayInput) -> void:
	_fray_input = fray_input
	_fray_input.input_detected.connect(Callable(self, "_on_fray_input_detected"))


## 断开初始化阶段建立的只读调试输入监听。
func _disconnect_debug_input_listener() -> void:
	_fray_input.input_detected.disconnect(Callable(self, "_on_fray_input_detected"))
	_fray_input = null


## 记录本 fighter 设备的 Fray 输入按下/松开历史；忽略逐帧 echo。
func _on_fray_input_detected(fray_event: FrayInputEvent) -> void:
	if fray_event.device != controller.device or fray_event.is_echo():
		return
	if not String(fray_event.input).begins_with(_input_setup.get_prefix()):
		return
	_input_history.append({
		"frame": fray_event.physics_frame,
		"input": fray_event.input,
		"pressed": fray_event.is_pressed(),
		"distinct": fray_event.is_distinct(),
		"virtual": fray_event.is_virtually_pressed(),
		"time_msec": fray_event.time_detected,
	})
	while _input_history.size() > DEBUG_INPUT_HISTORY_LIMIT:
		_input_history.pop_front()


## 记录 Fray state_changed，并把命令成功进入的状态投影为招式输出历史。
func _on_state_changed(from: StringName, to: StringName) -> void:
	_last_transition_from = from
	_last_transition_to = to
	_sync_state_visual(to)
	var frame := Engine.get_physics_frames()
	_state_history.append({"frame": frame, "from": from, "to": to})
	while _state_history.size() > DEBUG_STATE_HISTORY_LIMIT:
		_state_history.pop_front()
	if not MOVE_DEFINITIONS.has(to):
		return
	var definition: Dictionary = MOVE_DEFINITIONS[to]
	_last_move = {
		"frame": frame,
		"state": to,
		"name": definition.get("name", String(to)),
		"command": definition.get("command", ""),
	}
	_move_history.append(_last_move.duplicate(true))
	while _move_history.size() > DEBUG_MOVE_HISTORY_LIMIT:
		_move_history.pop_front()


## 清空仅用于观察的历史数据，不改变 Fray 输入和状态语义。
func _clear_debug_history() -> void:
	_input_history.clear()
	_state_history.clear()
	_move_history.clear()
	_last_move.clear()
	_last_transition_from = &""
	_last_transition_to = &""


## 返回 HUD 使用的招式清单；招式识别仍以 Fray transition 成功为准。
func _get_available_moves() -> Array[Dictionary]:
	var moves: Array[Dictionary] = []
	for state_name in MOVE_DEFINITIONS:
		var definition: Dictionary = MOVE_DEFINITIONS[state_name]
		moves.append({
			"state": state_name,
			"name": definition.get("name", String(state_name)),
			"command": definition.get("command", ""),
		})
	return moves


## 将方块角色的朝向箭头同步到角色 facing_direction 属性。
func _sync_facing_visual() -> void:
	_facing_indicator.scale.x = float(facing_direction)


## 用颜色区分中立、移动、防御、攻击、受击、倒地、KO 和锁定状态。
func _sync_state_visual(state_name: StringName) -> void:
	var color_key := &"neutral"
	if state_name in [&"jump_start", &"jump", &"double_jump", &"fall", &"land", &"dash_forward", &"dash_back"]:
		color_key = &"movement"
	elif state_name in [&"stand_guard", &"crouch_guard", &"blockstun"]:
		color_key = &"defense"
	elif state_name in [&"stand_light", &"stand_heavy", &"crouch_light", &"crouch_heavy", &"air_light", &"air_heavy"]:
		color_key = &"attack"
	elif state_name in [&"hitstun", &"air_hitstun"]:
		color_key = &"reaction"
	elif state_name in [&"knockdown", &"tech_roll", &"wakeup"]:
		color_key = &"downed"
	elif state_name == &"ko":
		color_key = &"ko"
	elif state_name == &"locked":
		color_key = &"locked"
	_visual.color = STATE_COLORS[color_key]
