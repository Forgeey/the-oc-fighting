class_name FighterMoveDefinition
extends Resource
## 保存招式配置与依赖，不保存本次执行进度。

## 用八位数字字符串标识招式：两位大类、两位小类、四位流水号。
@export var move_id: StringName
## 保存面向玩家的招式名称，不参与装备、输入匹配或转换判断。
@export var move_name: String = ""
## 定义发动本招的输入指令。
@export var command: FighterCommandDefinition

## 指定本招发动时进入的完整状态路径。
@export var entry_path: StringName
## 列出装备本招需要装配的状态路径。
@export var required_state_paths: Array[StringName] = []
## 声明本招发动时检查的公共条件。
@export var prereqs: PackedStringArray = []

## 设置本招起手阶段的逻辑帧数。
@export var startup_frames: int = 10
## 设置本招有效阶段的逻辑帧数。
@export var active_frames: int = 4
## 设置本招恢复阶段的逻辑帧数。
@export var recovery_frames: int = 10


## 返回起手、有效和恢复阶段的总逻辑帧数。
func total_frames() -> int:
	return startup_frames + active_frames + recovery_frames
