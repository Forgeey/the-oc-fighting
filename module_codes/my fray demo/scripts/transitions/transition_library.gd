class_name FighterTransitionLibrary
extends Resource
## 公共候选转换库。构建器根据角色选中的状态及可进入的分组筛选规则。

## 条件名称 -> Fighter 的无参数 bool 方法名。只绑定实际选入规则的条件。
@export var condition_methods: Dictionary[StringName, StringName] = {}
## 入选规则保持数组顺序，允许相同端点具有不同条件的多条规则。
@export var transitions: Array[FighterTransitionDefinition] = []
