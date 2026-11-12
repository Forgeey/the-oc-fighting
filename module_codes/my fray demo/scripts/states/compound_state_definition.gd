class_name FighterCompoundStateDefinition
extends Resource
## 根下的局部流程组配置；运行时仍创建原生 FrayCompoundState，不是 Node 或组子类。

## 根下唯一的组名，不与根的动作重名。
@export var state_name: StringName
## 本组直接子动作的默认入口。
@export var start_state: StringName


## 本组直接子状态的静态引用；装配时按 state_id 解析到角色状态库，运行实例独立。
@export var states: Array[FighterStateDefinition] = []

## 仅属于本组的内部转换；from/to 是本组直接孩子，条件也只注册在本组。
@export var transitions: Array[FighterTransitionDefinition] = []
