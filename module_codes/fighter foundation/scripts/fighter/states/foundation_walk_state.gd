class_name FoundationWalkState
extends FoundationState
## 地面行走状态。


## 每个物理帧读取 FrayController 语义轴，由移动层加速趋近最大行走速度。
func _physics_process_impl(delta: float) -> void:
	movement.step_grounded(controller.get_axis("p1_left", "p1_right"), delta)
