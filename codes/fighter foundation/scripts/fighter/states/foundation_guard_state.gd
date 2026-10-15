class_name FoundationGuardState
extends FoundationState
## 站立或下蹲防御保持状态；姿态选择与退出条件由 Fray builder 负责。

var _crouching: bool = false


## 创建站立防御或下蹲防御状态。
func _init(crouching: bool = false) -> void:
	_crouching = crouching


## 防御期间停止主动移动并保持地面接触。
func _physics_process_impl(delta: float) -> void:
	movement.step_grounded(0.0, delta)


## 返回当前防御姿态是否为下蹲防御，供调试或后续格挡结算使用。
func is_crouching_guard() -> bool:
	return _crouching
