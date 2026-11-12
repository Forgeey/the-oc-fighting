class_name FighterTransitionLibrary
extends Resource
## 保存根层转换规则和各层共用的条件方法映射。

## 保存根的直接子状态之间的普通转换或命令转换；局部边由复合定义持有。
@export var transitions: Array[FighterTransitionDefinition] = []

## 将非 inputed_ 条件映射到 Fighter 的无参布尔方法；inputed_<意图> 由 Builder 通用绑定。
@export var condition_methods: Dictionary[StringName, StringName] = {}
