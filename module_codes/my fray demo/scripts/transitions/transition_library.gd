class_name FighterTransitionLibrary
extends Resource
## 保存全游戏转换规则和条件方法映射。

## 保存所有的状态之间的普通转换或招式转换。
@export var transitions: Array[FighterTransitionDefinition] = []

## 将条件名映射到 Fighter 的无参布尔方法。
@export var condition_methods: Dictionary[StringName, StringName] = {}
