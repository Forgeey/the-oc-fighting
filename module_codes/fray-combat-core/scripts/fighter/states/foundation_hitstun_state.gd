class_name FoundationHitstunState
extends FoundationState
## 地面或空中受击硬直状态；反应帧数与击退只读取 FrayAttackAttribute。

var _airborne: bool = false
var _elapsed_frames: int = 0
var _duration_frames: int = 1


## 创建地面或空中受击硬直状态。
func _init(airborne: bool = false) -> void:
	_airborne = airborne


## 进入状态时读取 fighter 集中缓存的 FrayAttackAttribute 并启动击退。
func _enter_impl(args: Dictionary) -> void:
	_elapsed_frames = 0
	var attribute: FrayAttackAttribute = fighter.resolve_reaction_attribute(args.get("attribute"))
	var airborne_hit_count := maxi(int(args.get("combo_air_hits", 0)), 0)
	var duration_scale := 1.0
	if _airborne:
		duration_scale = pow(attribute.air_hitstun_decay, maxi(airborne_hit_count - 1, 0))
	_duration_frames = maxi(int(round(float(attribute.hitstun_frames) * duration_scale)), 1)
	movement.start_hit_reaction(
		attribute,
		bool(args.get("defender_was_airborne", false)),
		airborne_hit_count
	)


## 受击期间应用重力和击退摩擦；转移由 builder 集中处理。
func _physics_process_impl(delta: float) -> void:
	_elapsed_frames += 1
	movement.step_reaction(delta)


## 达到攻击资源指定的 hitstun 帧数后结束。
func _is_done_processing_impl() -> bool:
	return _elapsed_frames >= _duration_frames
