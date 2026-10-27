class_name IdleState
extends FighterState
## 处理角色待机时的动画和移动。

## 进入待机时播放待机动画。
func _enter_impl(_args: Dictionary) -> void:
	super(_args)
	play_state_animation()


## 保持地面移动并逐步停止水平速度。
func _physics_process_impl(delta: float) -> void:
	movement.step_grounded(0.0, delta)
