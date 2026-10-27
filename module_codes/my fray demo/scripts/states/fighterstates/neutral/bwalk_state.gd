class_name BWalkState
extends FighterState
## 处理角色相对朝向后退时的动画和移动。

## 进入后退时播放后退动画。
func _enter_impl(_args: Dictionary) -> void:
	play_state_animation()


## 按后退输入更新地面移动。
func _physics_process_impl(delta: float) -> void:
	movement.step_grounded(fighter.get_backward_axis(), delta)
