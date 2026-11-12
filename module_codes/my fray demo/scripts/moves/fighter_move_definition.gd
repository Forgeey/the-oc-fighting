class_name FighterMoveDefinition
extends Resource
## 保存招式配置与单一执行入口，不保存本次执行进度。

## 用八位数字字符串标识招式：两位大类、两位小类、四位流水号。
@export var move_id: StringName
## 保存面向玩家的招式名称，不参与装备、输入匹配或转换判断。
@export var move_name: String = ""
## 定义发动本招的输入指令。
@export var command: FighterCommandDefinition

## 单段引用 FighterStateDefinition，多段引用 FighterCompoundStateDefinition。
## 这里只引用静态定义；运行对象由 Builder 创建，组定义直接持有成员与内部转换。
@export_custom(PROPERTY_HINT_RESOURCE_TYPE, "FighterStateDefinition,FighterCompoundStateDefinition")
var state: Resource
## 声明战斗中发动本招时检查的公共条件，不用于解锁或递归装配。
@export var prereqs: PackedStringArray
