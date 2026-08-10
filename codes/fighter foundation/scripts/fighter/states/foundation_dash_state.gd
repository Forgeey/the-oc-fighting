class_name FoundationDashState
extends FoundationState
## 固定时长的相对方向冲刺状态；前冲与后撤使用不同速度和持续时间。

var _relative_direction: int = 1
var _world_direction: int = 1
var _elapsed_frames: int = 0
var _duration_frames: int = 1
var _speed: float = 0.0


## 创建向前（1）或向后（-1）的冲刺状态实例。
func _init(relative_direction: int = 1) -> void:
	_relative_direction = 1 if relative_direction >= 0 else -1


## 进入状态时锁定世界方向，并从环境读取对应的前冲或后撤参数。
func _enter_impl(_args: Dictionary) -> void:
	_world_direction = fighter.facing_direction * _relative_direction
	_elapsed_frames = 0
	if _relative_direction > 0:
		_duration_frames = environment.dash_forward_duration_frames
		_speed = environment.dash_forward_speed
	else:
		_duration_frames = environment.dash_back_duration_frames
		_speed = environment.dash_back_speed
	movement.start_ground_dash(_world_direction, _speed)


## 每个物理帧推进冲刺阶段，先加速并在收尾主动制动。
func _physics_process_impl(delta: float) -> void:
	_elapsed_frames += 1
	movement.step_dash_world(
		_world_direction,
		_speed,
		_elapsed_frames,
		_duration_frames,
		delta
	)


## 达到对应前冲或后撤帧数后允许 AT_END transition 返回 idle。
func _is_done_processing_impl() -> bool:
	return _elapsed_frames >= _duration_frames
