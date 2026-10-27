class_name FighterInputBindings
extends RefCounted
## 将游戏输入动作接入 Fray 输入映射。

const ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"move_up", &"move_down",
	&"jump", &"crouch",
	&"light_attack", &"medium_attack", &"heavy_attack", &"guard",
]


## 将项目输入动作注册到 Fray 输入映射。
static func register_actions(input_map: _FrayInputMap) -> void:
	for input_action in ACTIONS:
		if not input_map.has_input(input_action):
			input_map.add_bind_action(input_action, input_action)
