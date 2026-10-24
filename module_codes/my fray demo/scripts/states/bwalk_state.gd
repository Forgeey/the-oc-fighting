class_name BWalkState
extends FighterState
## 按相对面向后退，使用独立后退动画和后退运动参数。


func _enter_impl(_args: Dictionary) -> void:
	fighter.play_animation(&"bwalk")


func _physics_process_impl(delta: float) -> void:
	movement.step_grounded(fighter.get_backward_axis(), delta)
