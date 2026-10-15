class_name FoundationDoubleJumpState
extends FoundationState
## 空中二段跳状态；通过 Fray 的上方向输入转移进入，并只消耗一次空中跳跃次数。


## 进入状态时按当前方向刷新垂直速度和水平轨迹。
func _enter_impl(_args: Dictionary) -> void:
	movement.launch_double_jump(controller.get_axis(&"p1_left", &"p1_right"))


## 每个物理帧保持二段跳轨迹并应用空中重力。
func _physics_process_impl(delta: float) -> void:
	movement.step_airborne(delta)
