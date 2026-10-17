class_name IdleState
extends State

func _physics_process_impl(delta: float) -> void:
	movement.step_grounded(0.0, delta)
