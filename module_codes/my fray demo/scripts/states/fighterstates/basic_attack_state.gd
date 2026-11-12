class_name BasicAttackState
extends FighterState
## 从 context Manager 的本状态姿态读取攻击 Attribute，不依赖 Move 或进入参数。

enum Phase { STARTUP, ACTIVE, RECOVERY, DONE }
var elapsed_frames: int = 0
var attack_attributes: Dictionary[int, FighterHitboxAttribute] = {}
var _pose: FrayHitState2D
var _base_mask: int


func _enter_impl(args: Dictionary) -> void:
	super(args)  # 先选中本状态姿态，不能读取上一个状态的 current pose。
	_pose = hit_state_manager.get_current_state_obj()
	attack_attributes.clear()
	_base_mask = state_definition.hit_state_definition.default_active_hitboxes
	var boxes := _pose.get_hitboxes()
	for index in boxes.size():
		if boxes[index].attribute is FighterHitboxAttribute and boxes[index].attribute.kind == FighterHitboxAttribute.Kind.ATTACK:
			attack_attributes[index] = boxes[index].attribute
			_base_mask &= ~(1 << index)
	elapsed_frames = 0
	_apply_attack_windows()
	movement.stop_horizontal()


func _physics_process_impl(delta: float) -> void:
	elapsed_frames += 1
	_apply_attack_windows()
	movement.step_grounded(0.0, delta)


## 多框时动作等待所有窗口及其恢复完成，不按“第一个框关闭”结束。
func total_frames() -> int:
	var duration := 0
	for attribute in attack_attributes.values():
		duration = maxi(duration, attribute.total_frames())
	return duration


func get_phase() -> Phase:
	if elapsed_frames >= total_frames():
		return Phase.DONE
	var first_active := total_frames()
	for attribute in attack_attributes.values():
		first_active = mini(first_active, attribute.startup_frames)
		if attribute.is_active_at(elapsed_frames):
			return Phase.ACTIVE
	return Phase.STARTUP if elapsed_frames < first_active else Phase.RECOVERY


func _apply_attack_windows() -> void:
	var mask := _base_mask
	for index in attack_attributes:
		if attack_attributes[index].is_active_at(elapsed_frames):
			mask |= 1 << index
	# 不重复设置掩码，以免每帧重新 activate。Hurt／Push 保持默认启用。
	if mask != _pose.active_hitboxes:
		_pose.active_hitboxes = mask


func _is_done_processing_impl() -> bool:
	return elapsed_frames >= total_frames()


func can_update_facing() -> bool:
	return is_done_processing()
