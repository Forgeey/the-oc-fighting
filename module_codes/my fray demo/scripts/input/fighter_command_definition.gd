class_name FighterCommandDefinition
extends Resource
## 作者固定的输入模式，内嵌于招式资源；运行时只读，假设配置有效。

enum InputKind { SINGLE, COMBINATION, SEQUENCE }
enum Trigger { PRESS, RELEASE }

const BUTTONS: Array[StringName] = [
	&"light_attack", &"medium_attack", &"heavy_attack", &"guard", &"jump", &"crouch",
]

@export var input_kind: InputKind = InputKind.SINGLE
## SINGLE/COMBINATION 用 buttons；SEQUENCE 用 steps（方向和最终按钮）。
@export var buttons: Array[StringName] = [&"light_attack"]
@export var steps: Array[StringName] = []
@export var trigger: Trigger = Trigger.PRESS
@export_range(1, 2000) var max_step_delay_ms: int = 200
@export_range(0, 2000) var min_charge_ms: int = 0
@export var negative_edge := false
@export_range(0, 10) var combination_window_frames: int = 2
## 普通单键等待组合键的帧数；序列和组合命中后不等待。
@export_range(0, 10) var resolve_delay_frames: int = 2
@export_range(0, 60) var buffer_frames: int = 6


func create_sequence(move_id: StringName) -> FraySequenceTree:
	var tree := FraySequenceTree.new()
	var branch := FraySequenceBranch.builder()
	for i in steps.size():
		branch.then(steps[i], max_step_delay_ms, min_charge_ms if i == 0 else 0)
	if negative_edge:
		branch.enable_negative_edge()
	tree.add(move_id, branch.build())
	return tree
