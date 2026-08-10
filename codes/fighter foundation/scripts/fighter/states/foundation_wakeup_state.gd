class_name FoundationWakeupState
extends FoundationState
## 倒地结束后的明确起身恢复状态。

var _elapsed_frames: int = 0


## 进入状态时重置起身恢复计时并停止残余速度。
func _enter_impl(_args: Dictionary) -> void:
	_elapsed_frames = 0
	movement.stop_horizontal()


## 起身期间保持地面接触并推进恢复帧。
func _physics_process_impl(delta: float) -> void:
	_elapsed_frames += 1
	movement.step_grounded(0.0, delta)


## 达到环境配置的起身恢复帧后结束。
func _is_done_processing_impl() -> bool:
	return _elapsed_frames >= environment.wakeup_duration_frames
