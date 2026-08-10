class_name FoundationLandState
extends FoundationState
## 落地恢复状态，以固定物理帧计时。

var _elapsed_frames: int = 0


## 进入状态时重置落地恢复计时。
func _enter_impl(_args: Dictionary) -> void:
	_elapsed_frames = 0


## 在恢复窗口中通过地面摩擦停止水平惯性并推进固定帧计时。
func _physics_process_impl(delta: float) -> void:
	movement.step_grounded(0.0, delta)
	_elapsed_frames += 1


## 达到环境配置帧数后允许 AT_END transition 返回 idle。
func _is_done_processing_impl() -> bool:
	return _elapsed_frames >= environment.land_duration_frames