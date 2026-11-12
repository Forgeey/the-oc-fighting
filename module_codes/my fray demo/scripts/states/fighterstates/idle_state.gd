class_name IdleState
extends FighterState
## 处理角色待机时的动画和移动。

## 保持地面移动并逐步停止水平速度。
func _physics_process_impl(delta: float) -> void:
	movement.step_grounded(0.0, delta)
