class_name FighterStateDefinition
extends Resource
## 一个行为叶子的静态定义，完整标识为 group_path/state_name。

@export var state_name: StringName
@export var group_path: StringName = &"neutral"
## 继承 FrayState（暂时不能是 FrayCompoundState），须支持无参构造。
@export var state_script: Script
