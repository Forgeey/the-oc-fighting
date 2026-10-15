class_name FoundationBlockstunState
extends FoundationState
## 格挡硬直状态；持续时间与推退只读取 FrayAttackAttribute。

var _elapsed_frames: int = 0
var _duration_frames: int = 1


## 进入状态时读取攻击资源并启动较轻的格挡推退。
func _enter_impl(args: Dictionary) -> void:
	_elapsed_frames = 0
	var attribute: FrayAttackAttribute = fighter.resolve_reaction_attribute(args.get("attribute"))
	_duration_frames = maxi(attribute.blockstun_frames, 1)
	movement.start_block_reaction(attribute)


## 格挡硬直期间应用地面推退与摩擦。
func _physics_process_impl(delta: float) -> void:
	_elapsed_frames += 1
	movement.step_reaction(delta)


## 达到攻击资源指定的 blockstun 帧数后结束。
func _is_done_processing_impl() -> bool:
	return _elapsed_frames >= _duration_frames
