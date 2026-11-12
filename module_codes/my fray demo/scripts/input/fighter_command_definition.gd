class_name FighterCommandDefinition
extends Resource
## 保存单个招式的固定输入指令。

enum InputKind { SINGLE, COMBINATION, SEQUENCE }
enum Trigger { PRESS, RELEASE }

const BUTTONS: Array[StringName] = [
	&"light_attack", &"medium_attack", &"heavy_attack", &"guard", &"jump", &"crouch",
]

## 独立逻辑命令名；可被多个状态转换接受，不是 move_id。
@export var command_id: StringName = &"light_attack"

## 选择单键、组合键或序列指令。
@export var input_kind: InputKind = InputKind.SINGLE
## 指定单键由按下还是松开发动。
@export var trigger: Trigger = Trigger.PRESS

## 指定单键或组合键使用的逻辑按钮。
@export var buttons: Array[StringName] = [&"light_attack"]
## 按钮触发时要求的相对九宫格方向；0 表示不限。非序列指令使用。
@export_range(0, 9) var required_direction: int = 0
## 设置组合键允许的按下间隔帧数。
@export_range(0, 10) var combination_window_frames: int = 2

## 按顺序保存序列指令的方向和按钮。
@export var steps: Array[StringName] = []
## 设置序列相邻步骤的最大间隔毫秒数。
@export_range(1, 2000) var max_step_delay_ms: int = 200
## 设置序列首步的最短蓄力毫秒数。
@export_range(0, 2000) var min_charge_ms: int = 0
## 决定序列是否启用松键识别。
@export var negative_edge := false

## 设置单键为等待组合输入保留的逻辑帧数。
@export_range(0, 10) var resolve_delay_frames: int = 2


## 配置角色时调用一次：相对步骤→世界步骤→原生分支；转向不重新编译。
## 不注册 InputMap，不创建 Matcher。两个朝向的路径放进同一棵树。
func create_branch(facing: int) -> FraySequenceBranch:
	var branch := FraySequenceBranch.builder()
	for index in steps.size():
		var input := steps[index]
		if String(input).begins_with("dir_"):
			var direction := int(String(input).trim_prefix("dir_"))
			if facing < 0:
				direction += 2 - 2 * ((direction - 1) % 3)
			input = StringName("world_%d" % direction)
		branch.then(input, max_step_delay_ms, min_charge_ms if index == 0 else 0)
	if negative_edge:
		branch.enable_negative_edge()
	return branch.build()
