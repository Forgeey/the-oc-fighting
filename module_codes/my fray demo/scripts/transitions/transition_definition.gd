class_name FighterTransitionDefinition
extends Resource
## 普通转换。端点均为所属复合状态的直接子状态名。
## 两端均为已选叶子或可进入的分组时，构建器才会注册本规则。

## 根层用空字符串；例如根层 neutral -> action。
@export var group_path: StringName = &"neutral"
@export var from_state: StringName
@export var to_state: StringName
@export var advance_conditions: PackedStringArray = []
@export var prereqs: PackedStringArray = []
@export var auto_advance: bool = true
@export var switch_mode: FrayStateMachineTransition.SwitchMode = FrayStateMachineTransition.SwitchMode.AT_END
@export var priority: int = 0
