class_name FighterTransitionDefinition
extends Resource
## 保存普通转换或招式转换的规则。

## 标识转换在全局库中的唯一身份。
@export var transition_id: StringName
## 接受的逻辑命令；留空为普通条件转换。同一命令可以连接多条边。
@export var command: StringName

## 所属组的直接源状态名称。
@export var from_state: StringName
## 所属组的直接目标状态名称。
@export var to_state: StringName

## 声明转换必须满足的前置条件。
@export var prereqs: PackedStringArray
## 声明普通自动推进或招式发动时检查的条件。
@export var advance_conditions: PackedStringArray
## 决定普通转换是否检查推进条件。
@export var auto_advance: bool = true
## 决定转换是否等待源状态完成。
@export var switch_mode: FrayStateMachineTransition.SwitchMode = FrayStateMachineTransition.SwitchMode.AT_END
## 保存传给 Fray 普通转换的优先级数值。
@export var priority: int = 0
