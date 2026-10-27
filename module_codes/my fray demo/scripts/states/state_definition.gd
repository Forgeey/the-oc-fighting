class_name FighterStateDefinition
extends Resource
## 保存角色状态的静态定义。

## 状态所属分组的完整路径。
@export var group_path: StringName = &"neutral"
## 状态的名称。
@export var state_name: StringName
## 状态挂载的可无参创建的 FighterState 执行脚本。
@export var state_script: Script

## 指定本状态播放的动画语义；留空表示不请求播放动画。
@export var animation_key: StringName

## 本状态使用的完整判定姿态，留空时进入后不启用任何姿态。
@export var hit_state_definition: FighterHitStateDefinition
