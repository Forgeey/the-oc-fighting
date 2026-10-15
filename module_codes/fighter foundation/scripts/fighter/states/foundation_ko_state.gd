class_name FoundationKOState
extends FoundationState
## KO 终止状态；不会自动返回中立，只能由回合重置或外部流程离开。


## 进入 KO 时关闭水平移动并保留自然落地。
func _enter_impl(_args: Dictionary) -> void:
	movement.stop_horizontal()


## KO 状态继续应用重力，避免角色悬空冻结。
func _physics_process_impl(delta: float) -> void:
	movement.step_reaction(delta)


## KO 是非完成状态。
func _is_done_processing_impl() -> bool:
	return false
