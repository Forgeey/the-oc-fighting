class_name FoundationFallState
extends FoundationState
## 下落状态。


## 每个物理帧保持空中惯性并应用更强的下落重力，落地由 builder condition 转入 land。
func _physics_process_impl(delta: float) -> void:
	movement.step_airborne(delta)