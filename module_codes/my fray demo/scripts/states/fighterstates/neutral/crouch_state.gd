class_name CrouchState
extends FighterState
## 处理角色原地下蹲时的动画和实体碰撞体。

## 停止水平移动并切换下蹲碰撞体和动画。
func _enter_impl(_args: Dictionary) -> void:
	super(_args)
	movement.stop_horizontal()
	fighter.set_crouching(true)
	play_state_animation()


## 离开下蹲时恢复站立碰撞体。
func _exit_impl() -> void:
	super()
	fighter.set_crouching(false)


## 保持原地下蹲时的重力和地面碰撞。
func _physics_process_impl(delta: float) -> void:
	movement.step_grounded(0.0, delta)
