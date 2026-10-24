class_name FighterMoveDefinition
extends Resource
## 完整招式及其固定输入；假设作者配置有效，不保存运行状态。

@export var move_id: StringName
@export var command: FighterCommandDefinition
@export var entry_path: StringName
@export var states: Array[FighterStateDefinition] = []
@export var transitions: Array[FighterTransitionDefinition] = []
## 可执行本招的源状态/父组完整路径；空数组表示不可由玩家输入发动。
@export var allowed_from_paths: Array[StringName] = [&"neutral"]
## 条件键通过现有 transition_library.condition_methods 绑定到 Fighter。
@export var prereqs: PackedStringArray = []
@export var switch_mode: FrayStateMachineTransition.SwitchMode = FrayStateMachineTransition.SwitchMode.AT_END
