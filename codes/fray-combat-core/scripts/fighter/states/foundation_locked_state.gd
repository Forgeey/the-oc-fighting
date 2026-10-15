class_name FoundationLockedState
extends FoundationState
## 集中控制锁定状态。


## 每个物理帧停止水平移动并保留正常重力/地面处理。
func _physics_process_impl(delta: float) -> void:
	movement.step_grounded(0.0, delta)
