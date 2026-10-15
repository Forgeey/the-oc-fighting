class_name FoundationInputSetup
extends RefCounted
## 第 1 组学习项目的 Fray 输入装配器。
##
## 本类只注册项目语义输入、组合输入与序列树；输入状态、事件、序列匹配和缓冲均由 Fray 提供。

## 冲刺双方向输入允许的最大间隔。
const DASH_SEQUENCE_DELAY_MSEC: int = 220
## “后、前”方向部分允许的最大间隔。
const PROJECTILE_DIRECTION_DELAY_MSEC: int = 260
## “前、轻攻击”收尾允许的最大间隔。
const PROJECTILE_BUTTON_DELAY_MSEC: int = 180
var _prefix: String = "p1_"
var _fighter
var _controller: FrayController
var _advancer: FrayBufferedInputAdvancer
var _sequence_tree: FraySequenceTree
var _configured: bool = false


## 将项目在Godot InputMap中配置的绝对物理action，注册为Fray基础bind，并制作前后方向。
## 幂等重建物理 bind、相对方向 composite 与斜向 composite。
## fighter 提供 facing_direction 属性，作为相对前后方向的唯一朝向来源。
func configure_input_map(prefix: StringName, fighter) -> bool:
	var input_map := _get_fray_input_map()
	_prefix = String(prefix)
	_fighter = fighter
	if not _validate_godot_actions():
		return false

	# FrayInputMap 是进程级 singleton。重载场景时必须重建本角色前缀，
	# 避免 composite 保留指向已释放 fighter 的朝向对象。
	_clear_prefix_inputs(input_map)
	for suffix in ["left", "right", "down", "up", "light", "medium", "heavy", "guard"]:
		_register_bind(input_map, _name(suffix), _name(suffix))
	_register_relative_directions(input_map)
	_register_relative_diagonals(input_map)
	_configured = true
	return true


## 创建冲刺与后前轻攻击普通波共用的 FraySequenceTree；强化键由施法状态内的 Fray press transition 处理。
func create_combat_sequences(prefix: StringName) -> FraySequenceTree:
	if String(prefix) != _prefix:
		push_error("Dash sequence prefix 与已配置输入前缀不一致。")
		return null
	var tree := FraySequenceTree.new()
	
	var forward_builder := (FraySequenceBranch.builder()
		.first(_name("forward"))
		.then(_name("forward"), DASH_SEQUENCE_DELAY_MSEC)
		.build())
	tree.add(_name("dash_forward"), forward_builder)

	var back_builder := (FraySequenceBranch.builder()
		.first(_name("back"))
		.then(_name("back"), DASH_SEQUENCE_DELAY_MSEC)
		.build())
	tree.add(_name("dash_back"), back_builder)

	var projectile_builder := (FraySequenceBranch.builder()
		.first(_name("back"))
		.then(_name("forward"), PROJECTILE_DIRECTION_DELAY_MSEC)
		.then(_name("light"), PROJECTILE_BUTTON_DELAY_MSEC)
		.build())
	tree.add(_name("back_forward_light"), projectile_builder)


	_sequence_tree = tree
	return tree


## 校验节点关系并让 FrayBufferedInputAdvancer 监听当前 controller。
func bind_advancer(
	controller: FrayController,
	advancer: FrayBufferedInputAdvancer,
	tree: FraySequenceTree
) -> bool:
	if not _configured:
		push_error("必须先调用 configure_input_map()。")
		return false
	if controller == null or advancer == null or tree == null:
		push_error("bind_advancer() 收到空 controller、advancer 或 sequence tree。")
		return false
	if not (advancer.get_parent() is FrayStateMachine):
		push_error("FrayBufferedInputAdvancer 必须是 FrayStateMachine 的直接子节点。")
		return false
	_controller = controller
	_advancer = advancer
	_sequence_tree = tree
	_advancer.listen_to_fray_input(_controller, _prefix, _sequence_tree)
	return true


## 同步输入消费暂停与缓冲时钟暂停语义；仅在 bind_advancer() 成功后调用。
# paused控制advancer对输入的消费。
# freeze_clock控制缓冲区的游戏时间是否继续前进。
func set_input_pause(paused: bool, freeze_clock: bool) -> void:
	_advancer.paused = paused
	_advancer.buffer_clock_paused = freeze_clock


## 清理缓冲；仅在 bind_advancer() 成功后调用，relisten 为 true 时重建 Fray singleton 监听。
# 上一回合结束前玩家按了攻击，如果不清理缓冲，新回合开始时这个攻击可能被状态机消费。
func reset_input_runtime(relisten: bool = false) -> void:
	_advancer.clear_buffer()
	if relisten:
		_advancer.stop_listening_to_fray_input()
		_advancer.listen_to_fray_input(_controller, _prefix, _sequence_tree)


## 停止 singleton 监听并清空缓冲；重复调用安全。
# 彻底结束当前fighter的输入运行时。
func shutdown_input() -> void:
	if _advancer == null:
		return
	_advancer.stop_listening_to_fray_input()
	_advancer.clear_buffer()
	_advancer = null
	_controller = null
	_sequence_tree = null
	_fighter = null


## 返回当前配置的输入前缀。
func get_prefix() -> String:
	return _prefix


## 从 SceneTree 获取 FrayInputMap singleton。
func _get_fray_input_map() -> _FrayInputMap:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("FrayInputMap") as _FrayInputMap


## 校验 project.godot 中移动与攻防所需的 Godot InputMap action。
func _validate_godot_actions() -> bool:
	var valid := true
	for suffix in ["left", "right", "down", "up", "light", "medium", "heavy", "guard"]:
		var action := _name(suffix)
		if not InputMap.has_action(action):
			push_error("缺少 Godot InputMap action：%s" % action)
			valid = false
	return valid


## 删除当前角色前缀下的旧 Fray bind/composite，保证场景重载后 Callable 有效。
func _clear_prefix_inputs(input_map: _FrayInputMap) -> void:
	for input_name in input_map.get_bind_names():
		if String(input_name).begins_with(_prefix):
			input_map.remove_input(input_name)
	var composite_names: Array[StringName] = []
	composite_names.assign(input_map.get_composite_input_names())
	for input_name in composite_names:
		if String(input_name).begins_with(_prefix):
			input_map.remove_input(input_name)


## 若 bind 尚不存在，则将 Fray 语义名绑定到同名 Godot action。
func _register_bind(input_map: _FrayInputMap, input_name: StringName, action: StringName) -> void:
	if input_map.has_input(input_name):
		if not input_map.has_bind(input_name):
			push_error("Fray 输入名 %s 已被 composite 占用。" % input_name)
		return
	input_map.add_bind_action(input_name, action)




## 注册随 fighter facing 改变的 forward/back 语义输入。
## FrayConditionalInput 的第一个组件是面向左时的默认项，第二个组件在面向右时启用。
func _register_relative_directions(input_map: _FrayInputMap) -> void:
	_register_relative_direction(input_map, "forward", "left", "right")
	_register_relative_direction(input_map, "back", "right", "left")


## 注册单个相对方向，确保 forward 与 back 在任一朝向下都映射到相反的物理方向。
func _register_relative_direction(
	input_map: _FrayInputMap,
	direction_suffix: String,
	facing_negative_bind_suffix: String,
	facing_positive_bind_suffix: String
) -> void:
	var direction_name := _name(direction_suffix)
	if input_map.has_input(direction_name):
		return

	var direction_builder := FrayConditionalInput.builder()
	direction_builder.add_component_simple(_name(facing_negative_bind_suffix))
	direction_builder.add_component_simple(_name(facing_positive_bind_suffix))
	direction_builder.use_condition(Callable(self, "_is_facing_positive"))
	direction_builder.priority(20)
	input_map.add_composite_input(direction_name, direction_builder.build())


## 注册角色相对斜方向；下前与下后共享底层方向 bind。
func _register_relative_diagonals(input_map: _FrayInputMap) -> void:
	_register_down_forward(input_map)
	_register_down_back(input_map)


## 注册 down+forward；直接组合底层方向 bind，避免建立项目私有输入系统。
func _register_down_forward(input_map: _FrayInputMap) -> void:
	var diagonal_name := _name("down_forward")
	if input_map.has_input(diagonal_name):
		return

	var down_left_builder := FrayCombinationInput.builder()
	down_left_builder.add_component_simple(_name("down"))
	down_left_builder.add_component_simple(_name("left"))
	down_left_builder.mode_async()

	var down_right_builder := FrayCombinationInput.builder()
	down_right_builder.add_component_simple(_name("down"))
	down_right_builder.add_component_simple(_name("right"))
	down_right_builder.mode_async()

	var diagonal_builder := FrayConditionalInput.builder()
	diagonal_builder.add_component(down_left_builder.build())
	diagonal_builder.add_component(down_right_builder.build())
	diagonal_builder.use_condition(Callable(self, "_is_facing_positive"))
	diagonal_builder.is_virtual()
	diagonal_builder.priority(30)
	input_map.add_composite_input(diagonal_name, diagonal_builder.build())


## 注册 down+back；根据 fighter 当前朝向选择绝对的 down+left 或 down+right。
func _register_down_back(input_map: _FrayInputMap) -> void:
	var diagonal_name := _name("down_back")
	if input_map.has_input(diagonal_name):
		return

	var down_right_builder := FrayCombinationInput.builder()
	down_right_builder.add_component_simple(_name("down"))
	down_right_builder.add_component_simple(_name("right"))
	down_right_builder.mode_async()

	var down_left_builder := FrayCombinationInput.builder()
	down_left_builder.add_component_simple(_name("down"))
	down_left_builder.add_component_simple(_name("left"))
	down_left_builder.mode_async()

	var diagonal_builder := FrayConditionalInput.builder()
	diagonal_builder.add_component(down_right_builder.build())
	diagonal_builder.add_component(down_left_builder.build())
	diagonal_builder.use_condition(Callable(self, "_is_facing_positive"))
	diagonal_builder.is_virtual()
	diagonal_builder.priority(30)
	input_map.add_composite_input(diagonal_name, diagonal_builder.build())


## 为 FrayConditionalInput 返回角色当前是否面向右侧。
func _is_facing_positive(_device: int) -> bool:
	if _fighter != null:
		return int(_fighter.facing_direction) > 0
	return true


## 根据当前前缀构造稳定 StringName。
func _name(suffix: String) -> StringName:
	return StringName(_prefix + suffix)
