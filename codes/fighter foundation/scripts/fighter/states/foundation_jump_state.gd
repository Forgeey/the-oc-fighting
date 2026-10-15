class_name FoundationJumpState
extends FoundationState
## 上升跳跃状态。


## 进入状态时按起跳准备阶段缓存的方向生成垂直、前跳或后跳速度。
func _enter_impl(_args: Dictionary) -> void:
	movement.launch_fighting_game_jump()


## 每个物理帧保持起跳水平惯性，并应用上升/顶点重力。
func _physics_process_impl(delta: float) -> void:
	movement.step_airborne(delta)