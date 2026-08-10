class_name FoundationTechRollState
extends FoundationState
## 软倒地受身翻滚状态；由 Fray 防御输入在受身窗口内触发。

var _elapsed_frames: int = 0
var _world_direction: int = 1


## 进入受身时按当前方向翻滚；无方向时默认朝后方脱离。
func _enter_impl(_args: Dictionary) -> void:
	_elapsed_frames = 0
	var axis := signf(controller.get_axis(input_name("left"), input_name("right")))
	_world_direction = int(axis) if not is_zero_approx(axis) else -fighter.facing_direction
	movement.start_tech_roll(_world_direction)


## 推进受身位移和地面处理。
func _physics_process_impl(delta: float) -> void:
	_elapsed_frames += 1
	movement.step_tech_roll(_world_direction, _elapsed_frames, delta)


## 达到环境配置的受身持续帧后结束。
func _is_done_processing_impl() -> bool:
	return _elapsed_frames >= environment.tech_roll_duration_frames
