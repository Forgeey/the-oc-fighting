class_name FWalkState
extends FighterState
## 处理角色相对朝向前进时的动画和移动。

## 进入前进时播放前进动画。
func _enter_impl(_args: Dictionary) -> void:
	play_state_animation()


## 按前进输入更新地面移动。
func _physics_process_impl(delta: float) -> void:
	movement.step_grounded(fighter.get_forward_axis(), delta)
