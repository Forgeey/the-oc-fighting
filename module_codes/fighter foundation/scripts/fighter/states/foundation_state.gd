class_name FoundationState
extends FrayState
## Fighter foundation 状态的共享基类。
##
## 只缓存 Fray initialize() 提供的只读 context，不维护状态分发或转移拓扑。

# 保持动态类型，避免新状态解析时沿 FoundationState 循环解析 FoundationFighter。
# movement为角色移动参数，为RefCounted
# environment为环境资源参数，为Resource
var fighter
var movement: FoundationMovement
var environment: FoundationFighterEnvironment
var controller: FrayController


## 从 Fray 只读 context 缓存当前状态需要的依赖。
func _ready_impl(context: Dictionary) -> void:
	fighter = context.get("fighter")
	movement = context.get("movement")
	environment = context.get("environment")
	controller = context.get("controller")
