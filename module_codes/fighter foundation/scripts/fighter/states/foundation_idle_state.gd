class_name FoundationIdleState
extends FoundationState
## 站立待机状态。


## 每个物理帧停止水平移动并保持地面接触。
func _physics_process_impl(delta: float) -> void:
	movement.step_grounded(0.0, delta)
