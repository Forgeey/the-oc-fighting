class_name FoundationJumpStartState
extends FoundationState
## 起跳准备状态，以固定物理帧计时并缓存起跳方向。

var _elapsed_frames: int = 0


## 进入状态时缓存世界方向和朝向，保证随后生成固定的格斗游戏跳跃轨迹。
func _enter_impl(_args: Dictionary) -> void:
	_elapsed_frames = 0
	movement.queue_fighting_game_jump(controller.get_axis(&"p1_left", &"p1_right"))


## 在准备帧中应用地面摩擦，不再改变已缓存的起跳方向。
func _physics_process_impl(delta: float) -> void:
	movement.step_jump_start(delta)
	_elapsed_frames += 1


## 达到环境配置帧数后允许 AT_END transition 进入 jump。
func _is_done_processing_impl() -> bool:
	return _elapsed_frames >= environment.jump_start_duration_frames