@tool
class_name DemoMoveLoadoutEntry
extends Resource

## 固定招式配置条目，保存启用状态和对应的 Fray 指令。
@export var enabled := true
@export var move: DemoMoveDefinition
@export var command: DemoMoveCommand
