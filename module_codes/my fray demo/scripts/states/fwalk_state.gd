class_name FWalkState
extends FighterState
## 按相对面向前进；输入条件由普通转换资源解释。


func _enter_impl(_args: Dictionary) -> void:
	fighter.play_animation(&"fwalk")


func _physics_process_impl(delta: float) -> void:
	movement.step_grounded(fighter.get_forward_axis(), delta)
