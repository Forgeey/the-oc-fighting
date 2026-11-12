class_name FighterInputBindings
extends RefCounted
## selection 解析后统一注册；全局复合定义不捕获某个 Fighter。

const ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"move_up", &"move_down",
	&"jump", &"crouch", &"light_attack", &"medium_attack", &"heavy_attack", &"guard",
]
const FORWARD := &"game_forward"
const BACKWARD := &"game_backward"
## device ID → FighterInput 的弱引用；负责设备归属，不保存序列历史或组合技进度。
static var _device_bindings: Dictionary = {}


static func register_actions(input_map: _FrayInputMap) -> void:
	for action in ACTIONS:
		if not input_map.has_input(action):
			input_map.add_bind_action(action, action)


## 基础 bind → 相对移动输入 → 当前装备的多按钮组合定义。
static func register_inputs(input_map: _FrayInputMap, commands: Array[FighterCommandDefinition]) -> Dictionary:
	# 基础移动、基础攻击的输入注册
	register_actions(input_map)
	# 前后注册为条件输入，实现镜像
	for name in [FORWARD, BACKWARD]:
		if not input_map.has_input(name):
			var normal := &"move_right" if name == FORWARD else &"move_left"
			var mirrored := &"move_left" if name == FORWARD else &"move_right"
			var conditional := FrayConditionalInput.builder()
			conditional.add_component_simple(normal)
			conditional.add_component_simple(mirrored)
			conditional.use_condition(_faces_left)
			input_map.add_composite_input(name, conditional.build())
	# 注册指令组合输入，未来可能设计多攻击键组合输入的招式
	var combinations := {}
	for command in commands:
		if command.input_kind != FighterCommandDefinition.InputKind.COMBINATION:
			continue
		var buttons := command.buttons.duplicate()
		buttons.sort()
		# ASYNC 定义仅由按钮决定；帧容错仍由各 command 在游戏薄层检查。
		var name := StringName("game_combo_" + "_".join(buttons))
		if not input_map.has_input(name):
			var combination := FrayCombinationInput.builder().mode_async()
			for button in buttons:
				combination.add_component_simple(button)
			input_map.add_composite_input(name, combination.build())
		combinations[command.command_id] = name
	return combinations

## 将输入设备绑定到角色 FighterInput，并检查活动设备占用。
static func bind_device(device: int, fighter_input: Node) -> bool:
	var current: Node = get_device_input(device)
	# 已停止采样或已禁用的角色输入可让出设备；同时采样的两个角色必须用不同 device。
	if current != null and current != fighter_input and current.is_physics_processing() and not current.controller.disabled:
		push_error("Input device %d already belongs to an active FighterInput." % device)
		return false
	_device_bindings[device] = weakref(fighter_input)
	return true


## 仅解除当前角色仍然拥有的设备绑定。
static func unbind_device(device: int, fighter_input: Node) -> void:
	if get_device_input(device) == fighter_input:
		_device_bindings.erase(device)


## 获取该设备当前绑定的 FighterInput。
static func get_device_input(device: int) -> Node:
	var reference: WeakRef = _device_bindings.get(device)
	return reference.get_ref() if reference != null else null


## 通过设备映射查询角色朝向
static func _faces_left(device: int) -> bool:
	var fighter_input: Node = get_device_input(device)
	return fighter_input != null and fighter_input.facing_dir < 0
