class_name BWalkState
extends FighterState
## 处理角色相对朝向后退时的动画和移动。

## 按后退输入更新地面移动。
func _physics_process_impl(delta: float) -> void:
	movement.step_grounded(fighter_input.get_movement_axis(&"bwalk"), delta)
