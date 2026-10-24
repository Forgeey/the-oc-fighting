class_name FighterInputBindings
extends RefCounted
## 游戏输入动作的统一 Fray 注册入口。物理键位只在项目 Input Map 中配置。
## 仅注册基础动作，不识别招式、不推进状态机，也不覆盖已经注册的输入。

const ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"move_up", &"move_down",
	&"jump", &"crouch",
	&"light_attack", &"medium_attack", &"heavy_attack", &"guard",
]


## 将Godot项目层面的action绑定到FrayInputMap中。InputMap -> FrayInputMap。
static func register_actions(input_map: _FrayInputMap) -> void:
	for input_action in ACTIONS:
		if not input_map.has_input(input_action):
			input_map.add_bind_action(input_action, input_action)
