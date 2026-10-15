class_name FoundationKnockdownState
extends FoundationState
## 倒地状态；倒地与不可受身帧数来自 FrayAttackAttribute。

var _elapsed_frames: int = 0
var _duration_frames: int = 1
var _untechable_frames: int = 0
var _hard_knockdown: bool = false


## 进入倒地时读取集中缓存的攻击资源，并重置受身窗口。
func _enter_impl(args: Dictionary) -> void:
	_elapsed_frames = 0
	var attribute: FrayAttackAttribute = fighter.resolve_reaction_attribute(args.get("attribute"))
	_duration_frames = attribute.knockdown_frames
	if _duration_frames <= 0:
		_duration_frames = environment.default_knockdown_duration_frames
	_untechable_frames = clampi(attribute.untechable_frames, 0, _duration_frames)
	_hard_knockdown = attribute.is_hard_knockdown()
	fighter.set_tech_roll_available(false)
	movement.start_knockdown(attribute)


## 离开倒地状态时关闭受身许可。
func _exit_impl() -> void:
	fighter.set_tech_roll_available(false)


## 推进倒地摩擦，并在软倒地不可受身窗口结束后开放受身。
func _physics_process_impl(delta: float) -> void:
	_elapsed_frames += 1
	fighter.set_tech_roll_available(not _hard_knockdown and _elapsed_frames >= _untechable_frames)
	movement.step_knockdown(delta)


## 达到倒地持续帧数后进入起身流程。
func _is_done_processing_impl() -> bool:
	return _elapsed_frames >= _duration_frames
