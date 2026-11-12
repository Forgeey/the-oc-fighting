class_name FighterStateLibrary
extends Resource
## 状态定义的权威装配来源；Move.state 引用叶子或显式组的静态定义。

## 内容作者保证 ID 非空且 ID/运行名称唯一；当前不做定义预检，资源按只读使用。
@export var states: Array[FighterStateDefinition] = []

## 显式声明根下的组合技／投掷等局部组；只有招式直接引用的组才装配；成员与内部边存于组定义。
@export var compound_states: Array[FighterCompoundStateDefinition] = []
