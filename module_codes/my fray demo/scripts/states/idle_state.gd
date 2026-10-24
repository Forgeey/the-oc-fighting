class_name IdleState
extends FighterState


func _enter_impl(_args: Dictionary) -> void:
	fighter.play_animation(&"idle")


func _physics_process_impl(delta: float) -> void:
	movement.step_grounded(0.0, delta)
