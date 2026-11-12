class_name FighterStateDefinition
extends Resource
## 保存角色状态的静态定义。

## 状态库内唯一的十位数字字符串；招式状态为八位 move_id 加两位序号。
@export var state_id: StringName
## 状态库内全局唯一的运行名称，不包含层级路径；selected_state_names 仍按此名称选择。
@export var state_name: StringName

## 状态挂载的可无参创建的 FighterState 执行脚本。
@export var state_script: Script

## 必填的状态动画语义；每次进入状态都播放，未制作时配置有效占位动画。
@export var animation_key: StringName

## 本状态必填的完整判定姿态；默认启用掩码必须非零。
@export var hit_state_definition: FighterHitStateDefinition
