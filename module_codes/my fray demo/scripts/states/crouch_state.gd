class_name CrouchState
extends FighterState
## 原地下蹲；斜下输入不产生水平移动，不包含蹲防/蹲走逻辑。


func _enter_impl(_args: Dictionary) -> void:
	movement.stop_horizontal()
	fighter.set_crouching(true)
	fighter.play_animation(&"crouch")


func _exit_impl() -> void:
	fighter.set_crouching(false)


func _physics_process_impl(delta: float) -> void:
	movement.step_grounded(0.0, delta)
