class_name FighterLoadout
extends Resource
## 角色从公共状态库中选择状态；转换由构建器根据端点可用性自动选入。

@export var state_library: FighterStateLibrary
@export var transition_library: FighterTransitionLibrary
## 完整行为路径，例如 neutral/idle、action/basic_attack/punch。不要重复选择。
@export var selected_state_paths: Array[StringName] = []
@export var entry_path: StringName = &"neutral/idle"
## 固定分组路径 -> 默认直接子状态名。未指定时选第一个可进入的子状态。
@export var group_start_states: Dictionary[StringName, StringName] = {}

## 招式资源内固定 command；角色清单不提供改指令字段。
@export var selected_moves: Array[FighterMoveDefinition] = []
