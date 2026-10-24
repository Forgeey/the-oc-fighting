class_name FighterStateLibrary
extends Resource
## 公共可选状态库。状态用 group_path/state_name 完整路径标识。
## 只保存静态定义；每个 Fighter 只实例化自己选中的状态。

@export var states: Array[FighterStateDefinition] = []
