class_name FoundationAttackState
extends FoundationState
## 由 FrayHitbox2D.attribute 中的 FrayAttackAttribute 驱动的基础攻击状态。
##
## 状态只保存攻击状态 ID；帧数、位移和 strike 激活窗口统一读取实际 hitbox attribute。

var _attack: FrayAttackAttribute
var _state_id: StringName
var _airborne: bool = false
var _elapsed_frames: int = 0
var _hit_state: FrayHitState2D
var _active_hitbox_mask: int = 0
var _manages_cancel_buffer: bool = false
var _contact_failure_discard_sequences: PackedStringArray = PackedStringArray()


## 创建一个按状态 ID 查找 Fray hit state 的攻击状态，并接收由取消目标推导出的序列清理列表。
func _init(
	state_id: StringName,
	airborne: bool = false,
	contact_failure_discard_sequences: PackedStringArray = PackedStringArray()
) -> void:
	_state_id = state_id
	_airborne = airborne
	_contact_failure_discard_sequences = contact_failure_discard_sequences


## 进入状态时取得对应 FrayHitState2D，并从其 FrayHitbox2D 读取唯一攻击属性。
func _enter_impl(_args: Dictionary) -> void:
	_elapsed_frames = 0
	_hit_state = fighter.get_attack_hit_state(_state_id)
	_attack = fighter.get_attack_attribute(_state_id)
	_active_hitbox_mask = 0
	_manages_cancel_buffer = _attack != null and _attack.has_cancel_window()
	if _manages_cancel_buffer:
		_set_cancel_buffer_open(_is_cancel_buffer_open(0))
	if _hit_state == null or _attack == null:
		push_error("攻击状态 %s 缺少已校验的 Fray hit state 或 attack attribute。" % _state_id)
		return

	# 世界朝向统一由父级 FrayHitStateManager2D 镜像；子状态保持正缩放以避免双重翻转。
	_hit_state.scale.x = 1.0
	_hit_state.active_hitboxes = 0
	_hit_state.activate()
	_active_hitbox_mask = _all_hitbox_bits(_hit_state)


## 退出攻击状态时关闭该 Fray hit state，并恢复 Fray 输入缓冲的正常消费与时钟。
## 接触条件失败时会丢弃由资源取消目标推导出的 sequence；外部 hitstop 暂停权仍由 fighter 集中管理。
func _exit_impl() -> void:
	if (
		_attack != null
		and _attack.cancel_requires_contact()
		and not fighter.is_current_attack_cancel_contact_allowed(_attack)
		and fighter.input_advancer != null
	):
		for sequence_name in _contact_failure_discard_sequences:
			fighter.input_advancer.discard_sequence(StringName(sequence_name))
	if _manages_cancel_buffer and not fighter.is_simulation_paused():
		_set_cancel_buffer_open(true)
	if _hit_state != null:
		_hit_state.active_hitboxes = 0
		_hit_state.deactivate()
	_hit_state = null
	_attack = null
	_active_hitbox_mask = 0
	_manages_cancel_buffer = false


## 按 hitbox attribute 的 startup、active、duration 推进攻击帧和移动。
func _physics_process_impl(delta: float) -> void:
	if _attack == null:
		return

	_elapsed_frames += 1
	if _manages_cancel_buffer:
		_set_cancel_buffer_open(_is_cancel_buffer_open(_elapsed_frames))
	var first_active_frame := _attack.startup_frames + 1
	var last_active_frame := _attack.startup_frames + _attack.active_frames
	if _hit_state != null:
		var hitboxes_active := _elapsed_frames >= first_active_frame and _elapsed_frames <= last_active_frame
		_hit_state.active_hitboxes = _active_hitbox_mask if hitboxes_active else 0
	if _airborne:
		movement.step_airborne(delta)
	else:
		movement.step_ground_attack(_attack, _elapsed_frames, delta)


## 攻击总时长完全读取 FrayHitbox2D.attribute 中的 duration_frames。
func _is_done_processing_impl() -> bool:
	return _attack == null or _elapsed_frames >= maxi(_attack.duration_frames, 1)


## 返回 hit state 下所有 FrayHitbox2D 对应的激活位掩码。
func _all_hitbox_bits(hit_state: FrayHitState2D) -> int:
	var hitbox_count := hit_state.get_hitboxes().size()
	return (1 << hitbox_count) - 1 if hitbox_count > 0 else 0


## 返回当前帧是否满足 attribute 取消窗及其命中、格挡或接触条件。
func _is_cancel_buffer_open(frame: int) -> bool:
	if _attack == null or not _attack.is_cancel_frame(frame):
		return false
	return fighter.is_current_attack_cancel_contact_allowed(_attack)


## 在取消条件未满足时保留预输入，在窗口开放后交回 FrayBufferedInputAdvancer 消费。
## ALWAYS 规则冻结缓冲时钟以支持提前拨号；接触型取消保持时钟推进，让挥空输入正常过期。
func _set_cancel_buffer_open(open: bool) -> void:
	if fighter == null or fighter.input_advancer == null or fighter.is_simulation_paused():
		return
	fighter.input_advancer.paused = not open
	fighter.input_advancer.buffer_clock_paused = (
		not open and (_attack == null or not _attack.cancel_requires_contact())
	)