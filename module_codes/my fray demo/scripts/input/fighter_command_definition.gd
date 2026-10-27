class_name FighterCommandDefinition
extends Resource
## 保存单个招式的固定输入指令。

enum InputKind { SINGLE, COMBINATION, SEQUENCE }
enum Trigger { PRESS, RELEASE }

const BUTTONS: Array[StringName] = [
	&"light_attack", &"medium_attack", &"heavy_attack", &"guard", &"jump", &"crouch",
]

## 选择单键、组合键或序列指令。
@export var input_kind: InputKind = InputKind.SINGLE
## 指定单键由按下还是松开发动。
@export var trigger: Trigger = Trigger.PRESS

## 指定单键或组合键使用的逻辑按钮。
@export var buttons: Array[StringName] = [&"light_attack"]
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
## 设置输入候选可保留的逻辑帧数。
@export_range(0, 60) var buffer_frames: int = 6


## 按指令步骤构建指定招式的序列匹配树。
func create_sequence(move_id: StringName) -> FraySequenceTree:
	var tree := FraySequenceTree.new()
	var branch := FraySequenceBranch.builder()
	for i in steps.size():
		branch.then(steps[i], max_step_delay_ms, min_charge_ms if i == 0 else 0)
	if negative_edge:
		branch.enable_negative_edge()
	tree.add(move_id, branch.build())
	return tree
