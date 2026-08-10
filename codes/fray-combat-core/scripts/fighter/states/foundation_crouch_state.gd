class_name FoundationCrouchState
extends FoundationState
## 下蹲保持状态。


## 每个物理帧停止水平移动；下蹲的正式碰撞变化不在本学习组范围内。
func _physics_process_impl(delta: float) -> void:
	movement.step_grounded(0.0, delta)
