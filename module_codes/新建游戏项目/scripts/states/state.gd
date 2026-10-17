class_name State
extends FrayState

var fighter
var controller: FrayController
var movement: Movement

## 从 Fray 只读 context 缓存当前状态需要的依赖。
func _ready_impl(context: Dictionary) -> void:
	fighter = context.get("fighter")
	controller = context.get("controller")
	movement = context.get("movement")
