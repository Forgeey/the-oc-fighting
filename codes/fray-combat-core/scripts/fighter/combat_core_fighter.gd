class_name CombatCoreFighter
extends FoundationFighter
## 第 2 组战斗核心 fighter 薄层。
##
## 角色流程继续由 FoundationFighter 内的 FrayStateMachine 表达；本类只增加生命、气条、
## Fray strike 接触上报、集中反应入口、hitstop 与 FrayAnimationObserver 的只读表现事件。

signal combat_contact_requested(defender, hurt_hitbox: FrayHitbox2D, strike_hitbox: FrayHitbox2D)
signal health_changed(fighter, old_value: int, new_value: int, reason: StringName, attribute_id: StringName)
signal meter_changed(fighter, old_value: int, new_value: int, reason: StringName, attribute_id: StringName)
signal knocked_out(fighter, attribute: FrayAttackAttribute)
signal animation_event(fighter, event_name: StringName, animation_name: StringName, play_position: float)
signal projectile_requested(fighter, attribute: FrayAttackAttribute)

const ATTACK_STATES := [&"stand_light", &"stand_medium", &"stand_heavy", &"stand_combo_medium", &"crouch_light", &"crouch_medium", &"crouch_heavy", &"air_light", &"air_medium", &"air_heavy"]
const AIR_STATES := [&"jump", &"double_jump", &"fall", &"air_light", &"air_medium", &"air_heavy", &"air_hitstun"]
const CORNER_CROSSUP_AIR_STATES := [&"jump", &"double_jump", &"fall", &"air_light", &"air_medium", &"air_heavy"]
const CROUCH_PUSHBOX_STATES := [&"crouch", &"crouch_guard", &"crouch_light", &"crouch_medium", &"crouch_heavy", &"knockdown", &"tech_roll", &"ko"]
const PUSHBOX_RISE_VELOCITY_EPSILON: float = 1.0
const TAG_PUSHBOX_RISING_PASS: StringName = &"pushbox_rising_pass"
const TURN_ANIMATION: StringName = &"turn"
## 每次进入项目或重置回合时使用的初始气条值。
const INITIAL_METER: int = 1000

## 稳定 fighter 标识，用于确定性排序和调试日志。
@export var fighter_id: StringName = &"p1"

## HUD 显示名称。
@export var display_name: String = "Player 1"

## 本角色使用的共享战斗规则。
@export var combat_rules: CombatRuleSet

## 普通波施放状态和投射物 strike 共用的唯一 FrayAttackAttribute。
@export var projectile_attack_attribute: FrayAttackAttribute

## 强化波施放状态和投射物 strike 共用的唯一 FrayAttackAttribute。
@export var enhanced_projectile_attack_attribute: FrayAttackAttribute

## 为 true 时只禁用 Fray 玩家输入；中立、受击、击退、倒地、起身与 KO 状态仍正常运行。
@export var training_dummy: bool = false

@export_group("Pushbox Profiles")
## 蹲姿推挤框尺寸；与 demo 的 DemoFighterPushbox 保持一致。
@export var crouch_pushbox_size := Vector2(88.0, 58.0)

## 蹲姿推挤框相对脚底原点的偏移。
@export var crouch_pushbox_offset := Vector2(0.0, -29.0)

## 空中推挤框尺寸；较窄的宽度允许跳跃角色从墙角对手上方完成换边。
@export var air_pushbox_size := Vector2(72.0, 80.0)

## 空中推挤框相对脚底原点的偏移。
@export var air_pushbox_offset := Vector2(0.0, -40.0)

## 主动空中状态上升时是否忽略地面角色 pushbox；下落、空中受击和空对空仍正常推挤。
@export var air_pushbox_ignores_grounded_while_rising: bool = true

@onready var _animation_player: AnimationPlayer = get_node_or_null("AnimationPlayer") as AnimationPlayer
@onready var _animation_observer: FrayAnimationObserver = get_node_or_null("FrayAnimationObserver") as FrayAnimationObserver
@onready var _facing_root: Node2D = get_node_or_null("FacingRoot") as Node2D
@onready var _pushbox: CollisionShape2D = get_node_or_null("Pushbox") as CollisionShape2D

enum AttackContactResult {
	NONE,
	BLOCK,
	HIT,
}

var health: int = 1
var meter: int = INITIAL_METER
var _attack_generation: int = 0
var _current_attack_token: StringName = &""
var _current_attack_contact: int = AttackContactResult.NONE
var _hitstop_frames_remaining: int = 0
var _hitstop_resume_queued: bool = false
var _animation_speed_before_hitstop: float = 1.0
var _last_guard_posture: StringName = &"stand"
var _pushbox_rectangle: RectangleShape2D
var _stand_pushbox_size := Vector2.ZERO
var _stand_pushbox_offset := Vector2.ZERO
var _turn_animation_active: bool = false


## 先完成基础 Fray fighter 初始化，再连接战斗接触与动画观察信号。
func _ready() -> void:
	super()
	if not _initialized:
		return
	if not _initialize_pushbox_profiles():
		return
	if combat_rules == null:
		push_error("CombatCoreFighter %s 缺少 combat_rules。" % fighter_id)
		return
	if not _validate_projectile_attribute(&"projectile", projectile_attack_attribute):
		return
	if not _validate_projectile_attribute(&"enhanced_projectile", enhanced_projectile_attack_attribute):
		return
	if not _validate_projectile_amplify():
		return
	health = combat_rules.max_health
	meter = clampi(INITIAL_METER, 0, combat_rules.max_meter)
	var contact_callback := Callable(self, "_on_attack_hitbox_intersected")
	if not _attack_hit_state_manager.hitbox_intersected.is_connected(contact_callback):
		_attack_hit_state_manager.hitbox_intersected.connect(contact_callback)
	var state_callback := Callable(self, "_on_combat_state_changed")
	if not state_machine.state_changed.is_connected(state_callback):
		state_machine.state_changed.connect(state_callback)
	_connect_animation_observer()
	var facing_callback := Callable(self, "_on_facing_changed")
	if not facing_changed.is_connected(facing_callback):
		facing_changed.connect(facing_callback)
	_apply_training_dummy_mode()
	_play_state_animation(state_machine.get_current_state_name())


## 保留基础 fighter 的物理快照刷新，并独立推进 hitstop 计数。
func _physics_process(delta: float) -> void:
	super(delta)
	if _hitstop_frames_remaining <= 0:
		return
	if _hitstop_frames_remaining > 1:
		_hitstop_frames_remaining -= 1
	elif not _hitstop_resume_queued:
		_hitstop_resume_queued = true
		call_deferred("_finish_hitstop")


## 设置用于自动转向的真实对手节点。
func set_combat_opponent(opponent: Node2D) -> void:
	_opponent_marker = opponent


## 按唯一 facing_direction 同步图片角色根节点与 Fray 攻击判定管理器。
## 攻击管理器只在父级镜像一次，避免子 HitState 再次翻转后抵消方向。
func _sync_facing_visual() -> void:
	if _facing_root != null:
		_facing_root.scale.x = float(facing_direction)
	if _attack_hit_state_manager != null:
		_attack_hit_state_manager.scale.x = float(facing_direction)


## 返回当前 pushbox 的世界坐标矩形，供 CombatCoreMatch 做双方分离。
func get_pushbox_rect() -> Rect2:
	if _pushbox == null or _pushbox.disabled or _pushbox_rectangle == null:
		return Rect2()
	return Rect2(_pushbox.global_position - _pushbox_rectangle.size * 0.5, _pushbox_rectangle.size)


## 为 pushbox 分离直接移动角色，并返回场地边界限制后的实际水平位移。
func move_horizontally_for_pushbox(delta_x: float) -> float:
	if environment == null or is_zero_approx(delta_x):
		return 0.0
	var previous_x := global_position.x
	global_position.x = clampf(previous_x + delta_x, environment.arena_left, environment.arena_right)
	return global_position.x - previous_x


## 返回角色是否正处于允许主动跳过墙角对手的空中 Fray 状态。
## 空中受击不参与主动换边，避免击飞轨迹改变双方站位规则。
func can_air_crossup_pushbox() -> bool:
	return get_combat_state() in CORNER_CROSSUP_AIR_STATES


## 返回当前角色是否应与指定对手执行 pushbox 分离。
## 只有带 Fray 穿越 tag 的主动空中状态在上升时可忽略地面对手；下落、受击和空对空均返回 true。
func should_resolve_pushbox_with(opponent: CombatCoreFighter) -> bool:
	if opponent == null:
		return false
	if not air_pushbox_ignores_grounded_while_rising:
		return true
	if opponent.is_airborne_for_combat():
		return true
	if velocity.y >= -PUSHBOX_RISE_VELOCITY_EPSILON:
		return true
	return not _has_current_state_tag(TAG_PUSHBOX_RISING_PASS)


## 返回当前 Fray 状态是否具有指定 tag；状态机尚未初始化时按无 tag 处理。
func _has_current_state_tag(tag_name: StringName) -> bool:
	if state_machine == null:
		return false
	var root := state_machine.get_root()
	if root == null:
		return false
	return tag_name in root.get_state_tags(get_combat_state())


## 复制场景中的 RectangleShape2D 并缓存站姿配置，避免两个实例共享 Shape 资源。
func _initialize_pushbox_profiles() -> bool:
	if _pushbox == null:
		push_error("%s 缺少 Pushbox 节点。" % fighter_id)
		return false
	var configured_rectangle := _pushbox.shape as RectangleShape2D
	if configured_rectangle == null:
		push_error("%s 的 Pushbox 必须使用 RectangleShape2D。" % fighter_id)
		return false
	_pushbox_rectangle = configured_rectangle.duplicate() as RectangleShape2D
	_pushbox.shape = _pushbox_rectangle
	_stand_pushbox_size = _pushbox_rectangle.size
	_stand_pushbox_offset = _pushbox.position
	_apply_pushbox_pose(state_machine.get_current_state_name())
	return true


## 根据当前 Fray 状态切换站立、蹲伏或空中推挤框，不建立额外姿态状态机。
func _apply_pushbox_pose(state_name: StringName) -> void:
	if _pushbox == null or _pushbox_rectangle == null:
		return
	if state_name in AIR_STATES:
		_pushbox_rectangle.size = air_pushbox_size
		_pushbox.position = air_pushbox_offset
	elif state_name in CROUCH_PUSHBOX_STATES or (state_name == &"blockstun" and _last_guard_posture == &"crouch"):
		_pushbox_rectangle.size = crouch_pushbox_size
		_pushbox.position = crouch_pushbox_offset
	else:
		_pushbox_rectangle.size = _stand_pushbox_size
		_pushbox.position = _stand_pushbox_offset


## 校验场景装配的普通波或强化波资源；速度也必须由同一攻击属性提供。
func _validate_projectile_attribute(state_id: StringName, attribute: FrayAttackAttribute) -> bool:
	if attribute == null or not attribute.is_projectile:
		push_error("CombatCoreFighter %s 的 %s 缺少有效投射物 FrayAttackAttribute。" % [fighter_id, state_id])
		return false
	if attribute.projectile_spawn_frame > attribute.projectile_cast_duration_frames:
		push_error("CombatCoreFighter %s 的 %s 生成帧晚于施放动作结束帧。" % [fighter_id, state_id])
		return false
	if attribute.projectile_speed <= 0.0:
		push_error("CombatCoreFighter %s 的 %s projectile_speed 必须大于 0。" % [fighter_id, state_id])
		return false
	return true


## 校验普通波声明的 Amplify 窗口、目标、资源消耗与共享施法时间轴。
func _validate_projectile_amplify() -> bool:
	var source := projectile_attack_attribute
	var target := enhanced_projectile_attack_attribute
	if not source.has_amplify_window():
		push_error("CombatCoreFighter %s 的普通波必须声明 Amplify 窗口。" % fighter_id)
		return false
	if source.amplify_target_state != &"enhanced_projectile":
		push_error("CombatCoreFighter %s 的普通波 Amplify 目标必须是 enhanced_projectile。" % fighter_id)
		return false
	if source.amplify_meter_cost <= 0:
		push_error("CombatCoreFighter %s 的普通波 amplify_meter_cost 必须大于 0。" % fighter_id)
		return false
	var amplify_end_frame := (
		source.amplify_end_frame
		if source.amplify_end_frame >= 0
		else source.projectile_spawn_frame - 1
	)
	if amplify_end_frame < source.amplify_start_frame:
		push_error("CombatCoreFighter %s 的普通波 Amplify 结束帧不能早于开始帧。" % fighter_id)
		return false
	if amplify_end_frame >= source.projectile_spawn_frame:
		push_error("CombatCoreFighter %s 的普通波 Amplify 窗口必须在投射物生成前结束。" % fighter_id)
		return false
	if (
		target.projectile_cast_duration_frames != source.projectile_cast_duration_frames
		or target.projectile_spawn_frame != source.projectile_spawn_frame
	):
		push_error("CombatCoreFighter %s 的普通波与强化波必须共享施法总帧和生成帧。" % fighter_id)
		return false
	return true


## 返回攻击资源是否为 fighter 场景实际装配的普通波或强化波资源。
func _is_configured_projectile_attribute(attribute: FrayAttackAttribute) -> bool:
	return (
		attribute != null
		and attribute.is_projectile
		and attribute in [projectile_attack_attribute, enhanced_projectile_attack_attribute]
	)


## 返回命中协调器使用的稳定标识。
func get_combat_id() -> StringName:
	return fighter_id


## 按施放状态返回普通波或强化波与投射物 strike 共用的唯一攻击资源。
func get_projectile_attack_attribute(state_id: StringName = &"projectile") -> FrayAttackAttribute:
	match state_id:
		&"projectile":
			return projectile_attack_attribute
		&"enhanced_projectile":
			return enhanced_projectile_attack_attribute
		_:
			return null


## 由 Fray 投射物施放状态请求 Match 生成投射物，不直接实例化场景。
func request_projectile_spawn(attribute: FrayAttackAttribute) -> void:
	if not _is_configured_projectile_attribute(attribute):
		push_error("%s 拒绝了与场景装配不一致的投射物攻击资源。" % fighter_id)
		return
	projectile_requested.emit(self, attribute)


## 返回投射物和近战 hitbox 解析到的战斗所有者。
func get_combat_owner() -> CombatCoreFighter:
	return self


## 返回当前近战攻击的世界方向，供统一结算确定击退方向。
func get_combat_attack_direction() -> int:
	return facing_direction


## 返回指定 strike 的攻击实例 token；同一实例对同一目标只结算一次。
func get_combat_attack_token(strike_hitbox: FrayHitbox2D) -> StringName:
	if strike_hitbox != null and strike_hitbox.has_meta("combat_attack_token"):
		return StringName(strike_hitbox.get_meta("combat_attack_token"))
	return StringName("%s:%d:%s" % [fighter_id, _attack_generation, strike_hitbox.name if strike_hitbox != null else "unknown"])


## 记录当前近战攻击实例的实际命中或格挡结果；旧 token、投射物和错误 attribute 均会被拒绝。
func confirm_current_attack_contact(token: StringName, attribute: FrayAttackAttribute, blocked: bool) -> bool:
	if token.is_empty() or token != _current_attack_token or attribute == null:
		return false
	if attribute.id != get_combat_state():
		return false
	var next_result := AttackContactResult.BLOCK if blocked else AttackContactResult.HIT
	_current_attack_contact = maxi(_current_attack_contact, next_result)
	return true


## 兼容只关心 clean hit 的调用方，并转交统一攻击接触记录。
func confirm_current_attack_hit(token: StringName, attribute: FrayAttackAttribute) -> bool:
	return confirm_current_attack_contact(token, attribute, false)


## 返回当前近战攻击实例是否已实际命中且未被格挡。
func has_confirmed_current_attack_hit() -> bool:
	return not _current_attack_token.is_empty() and _current_attack_contact == AttackContactResult.HIT


## 返回当前攻击接触结果是否满足指定攻击资源的数据化取消条件。
func is_current_attack_cancel_contact_allowed(attribute: FrayAttackAttribute = null) -> bool:
	var current_attribute := attribute
	if current_attribute == null:
		current_attribute = get_attack_attribute(get_combat_state())
	if current_attribute == null or _current_attack_token.is_empty():
		return false
	var connected := _current_attack_contact != AttackContactResult.NONE
	var blocked := _current_attack_contact == AttackContactResult.BLOCK
	return current_attribute.is_cancel_contact_allowed(connected, blocked)


## 返回当前攻击是否可按资源规则取消到目标状态，供 Fray transition condition 使用。
func can_cancel_current_attack_to(target_state: StringName) -> bool:
	var attribute := get_attack_attribute(get_combat_state())
	return (
		attribute != null
		and attribute.can_cancel_to(target_state)
		and is_current_attack_cancel_contact_allowed(attribute)
	)


## 返回当前 Fray 状态名。
func get_combat_state() -> StringName:
	return state_machine.get_current_state_name()


## 返回当前是否处于空中流程。
func is_airborne_for_combat() -> bool:
	return get_combat_state() in AIR_STATES or not is_on_floor()


## 返回攻击属性是否能接触当前姿态；高段攻击会被主动下蹲姿态闪避。
func can_be_hit_by(attribute: FrayAttackAttribute) -> bool:
	if attribute == null:
		return false
	if attribute.guard_type != FrayAttackAttribute.GuardType.HIGH or is_airborne_for_combat():
		return true
	var state_name := get_combat_state()
	return not (
		state_name in [&"crouch", &"crouch_guard", &"crouch_light", &"crouch_medium", &"crouch_heavy"]
		or (state_name == &"blockstun" and _last_guard_posture == &"crouch")
	)


## 根据 Fray 防御状态与 attribute.guard_type 判断本次攻击是否被挡住。
func is_guarding_against(attribute: FrayAttackAttribute) -> bool:
	if attribute == null:
		return false
	var state_name := get_combat_state()
	var guarding := state_name in [&"stand_guard", &"crouch_guard", &"blockstun"]
	if not guarding:
		return false
	if is_airborne_for_combat() and not attribute.can_air_block:
		return false
	match attribute.guard_type:
		FrayAttackAttribute.GuardType.HIGH:
			return _last_guard_posture == &"stand"
		FrayAttackAttribute.GuardType.MID:
			return true
		FrayAttackAttribute.GuardType.LOW:
			return _last_guard_posture == &"crouch"
		FrayAttackAttribute.GuardType.OVERHEAD:
			return _last_guard_posture == &"stand"
		FrayAttackAttribute.GuardType.THROW, FrayAttackAttribute.GuardType.UNBLOCKABLE:
			return false
		_:
			return false


## 原子修改生命并发出只读事件；KO 状态由协调器统一提交。
func apply_health_delta(amount: int, reason: StringName, attribute: FrayAttackAttribute) -> void:
	var old_value := health
	health = clampi(health + amount, 0, combat_rules.max_health)
	if old_value != health:
		health_changed.emit(self, old_value, health, reason, attribute.id if attribute != null else &"missing")


## 返回当前气条是否足以支付给定的非负资源数量。
func can_spend_meter(amount: int) -> bool:
	return amount >= 0 and meter >= amount


## 原子检查并支付气条；失败时不修改资源也不发出事件。
func try_spend_meter(
	amount: int,
	reason: StringName,
	attribute: FrayAttackAttribute
) -> bool:
	if amount <= 0 or not can_spend_meter(amount):
		return false
	add_meter(-amount, reason, attribute)
	return true


## 修改统一气条并限制在 0 到规则上限。
func add_meter(amount: int, reason: StringName, attribute: FrayAttackAttribute) -> void:
	var old_value := meter
	meter = clampi(meter + amount, 0, combat_rules.max_meter)
	if old_value != meter:
		meter_changed.emit(self, old_value, meter, reason, attribute.id if attribute != null else &"missing")


## 在完整交互批次提交后集中请求 blockstun、hitstun、air hitstun、knockdown 或 KO。
func commit_combat_reaction(
	attribute: FrayAttackAttribute,
	blocked: bool,
	attacker_direction: int,
	combo_context: Dictionary = {},
	defender_was_airborne: bool = false
) -> void:
	if attribute == null:
		push_error("%s 收到缺少 FrayAttackAttribute 的反应请求。" % fighter_id)
		return
	facing_direction = -1 if attacker_direction > 0 else 1
	_sync_facing_visual()
	if health <= 0:
		request_external_state(&"ko", {"attribute": attribute})
		knocked_out.emit(self, attribute)
		return
	if blocked:
		request_external_state(&"blockstun", {"attribute": attribute})
		return
	var reaction_args := {
		"attribute": attribute,
		"combo_air_hits": int(combo_context.get("air_hits", 0)),
		"defender_was_airborne": defender_was_airborne,
	}
	if attribute.causes_knockdown():
		request_external_state(&"knockdown", reaction_args)
		return
	var launch_velocity := attribute.get_launch_y_velocity(defender_was_airborne)
	reaction_args.airborne = defender_was_airborne or launch_velocity < 0.0
	request_external_state(&"hitstun", reaction_args)


## 以固定物理帧暂停状态机、运动与输入缓冲年龄；多次请求取较长者。
func begin_hitstop(frames: int) -> void:
	if frames <= 0:
		return
	_hitstop_frames_remaining = maxi(_hitstop_frames_remaining, frames)
	set_simulation_paused(true, true)
	_set_animation_hitstop_paused(true)


## 在当前物理帧全部 Fray 节点处理完后恢复模拟，确保最后一帧 hitstop 不被父节点提前解除。
func _finish_hitstop() -> void:
	_hitstop_resume_queued = false
	if _hitstop_frames_remaining > 1:
		return
	_hitstop_frames_remaining = 0
	set_simulation_paused(false, false)
	_set_animation_hitstop_paused(false)


## 返回角色是否正处于战斗 hitstop。
func is_in_hitstop() -> bool:
	return _hitstop_frames_remaining > 0


## 重置回合生命、气条、hitstop、攻击 generation 与 Fray 状态。
func reset_combat(spawn: Transform2D, facing: int) -> void:
	var old_health := health
	var old_meter := meter
	_hitstop_frames_remaining = 0
	_hitstop_resume_queued = false
	_attack_generation = 0
	_current_attack_token = &""
	_current_attack_contact = AttackContactResult.NONE
	_turn_animation_active = false
	_set_animation_hitstop_paused(false)
	health = combat_rules.max_health
	meter = clampi(INITIAL_METER, 0, combat_rules.max_meter)
	reset_for_round(spawn, facing)
	_apply_training_dummy_mode()
	if old_health != health:
		health_changed.emit(self, old_health, health, &"round_reset", &"reset")
	if old_meter != meter:
		meter_changed.emit(self, old_meter, meter, &"round_reset", &"reset")


## 扩展基础调试快照，但不允许 HUD 反向修改 fighter。
func get_combat_snapshot() -> Dictionary:
	var snapshot := get_debug_snapshot()
	snapshot.merge({
		"fighter_id": fighter_id,
		"display_name": display_name,
		"health": health,
		"max_health": combat_rules.max_health if combat_rules != null else 0,
		"meter": meter,
		"max_meter": combat_rules.max_meter if combat_rules != null else 0,
		"attack_generation": _attack_generation,
		"hitstop_frames": _hitstop_frames_remaining,
		"training_dummy": training_dummy,
	}, true)
	return snapshot


## 让攻击方 strike 主动检测对手 hurtbox，并上报统一批量结算器。
func _on_attack_hitbox_intersected(strike_hitbox: FrayHitbox2D, hurt_hitbox: FrayHitbox2D) -> void:
	if strike_hitbox == null or hurt_hitbox == null:
		return
	if not (strike_hitbox.attribute is FrayAttackAttribute):
		push_error("%s 的 strike 缺少 FrayAttackAttribute。" % fighter_id)
		return
	var defender := hurt_hitbox.source as CombatCoreFighter
	if defender == null or defender == self:
		return
	combat_contact_requested.emit(defender, hurt_hitbox, strike_hitbox)


## 只关闭训练木偶的 Fray 输入，不进入 locked 状态，确保外部受击状态仍可正常 goto。
func _apply_training_dummy_mode() -> void:
	if controller == null or input_advancer == null:
		return
	controller.disabled = training_dummy
	if training_dummy:
		input_advancer.clear_buffer()


## 为每次进入攻击 FrayState 生成稳定 token，并把 token 写到实际 FrayHitbox2D。
func _on_combat_state_changed(from: StringName, to: StringName) -> void:
	if to == &"crouch_guard":
		_last_guard_posture = &"crouch"
	elif to == &"stand_guard":
		_last_guard_posture = &"stand"
	_apply_pushbox_pose(to)
	if _turn_animation_active and to not in AUTO_FACING_STATES:
		_turn_animation_active = false
	if to in ATTACK_STATES:
		_attack_generation += 1
		_current_attack_token = StringName("%s:%d:%s" % [fighter_id, _attack_generation, to])
		_current_attack_contact = AttackContactResult.NONE
		var hit_state := get_attack_hit_state(to)
		if hit_state != null:
			for hitbox in hit_state.get_hitboxes():
				hitbox.set_meta("combat_attack_token", _current_attack_token)
	else:
		_current_attack_token = &""
		_current_attack_contact = AttackContactResult.NONE
	# Amplify 只替换尚未生成的攻击资源，不重播同一施法动画。
	if not (from == &"projectile" and to == &"enhanced_projectile"):
		_play_state_animation(to)


## 连接 FrayAnimationObserver tracker 的开始、更新和结束事件，仅用于表现与诊断。
func _connect_animation_observer() -> void:
	if _animation_observer == null or _animation_observer.tracker == null:
		push_warning("%s 未装配 FrayAnimationObserver；战斗逻辑仍按固定帧运行。" % fighter_id)
		return
	_animation_observer.tracker.animation_started.connect(_on_animation_started)
	_animation_observer.tracker.animation_updated.connect(_on_animation_updated)
	_animation_observer.tracker.animation_finished.connect(_on_animation_finished)


## 同步暂停 AnimationPlayer 与 Fray tracker，避免 hitstop 期间表现事件重复推进。
func _set_animation_hitstop_paused(paused: bool) -> void:
	if _animation_player != null:
		if paused:
			if not is_zero_approx(_animation_player.speed_scale):
				_animation_speed_before_hitstop = _animation_player.speed_scale
			_animation_player.speed_scale = 0.0
		else:
			_animation_player.speed_scale = _animation_speed_before_hitstop
	if _animation_observer != null:
		_animation_observer.set_process(not paused)
		_animation_observer.set_physics_process(not paused)


## 根据 Fray 状态选择图片序列动画；这些轨道只负责表现，不控制 hitbox 生命周期或战斗帧。
func _play_state_animation(state_name: StringName) -> void:
	if _animation_player == null or _turn_animation_active:
		return
	var animation_name: StringName = &"idle"
	if state_name in [&"stand_light", &"crouch_light", &"air_light"]:
		animation_name = &"attack"
	elif state_name in [&"stand_medium", &"stand_heavy", &"stand_combo_medium", &"crouch_medium", &"crouch_heavy", &"air_medium", &"air_heavy", &"projectile", &"enhanced_projectile"]:
		animation_name = &"attack_heavy"
	elif state_name == &"walk_forward":
		animation_name = &"walk_forward"
	elif state_name == &"walk_back":
		animation_name = &"walk_back"
	elif state_name == &"jump_start":
		animation_name = &"jump_start"
	elif state_name == &"jump":
		animation_name = &"jump"
	elif state_name == &"double_jump":
		animation_name = &"double_jump"
	elif state_name == &"fall":
		animation_name = &"fall"
	elif state_name == &"land":
		animation_name = &"land"
	elif state_name == &"dash_forward":
		animation_name = &"dash_forward"
	elif state_name == &"dash_back":
		animation_name = &"dash_back"
	elif state_name in [&"crouch", &"stand_guard", &"crouch_guard", &"blockstun", &"tech_roll"]:
		animation_name = &"guard"
	elif state_name in [&"hitstun", &"air_hitstun", &"knockdown", &"wakeup"]:
		animation_name = &"hurt"
	elif state_name == &"ko":
		animation_name = &"ko"
	if _animation_player.has_animation(animation_name):
		_animation_player.play(animation_name)


## 朝向改变时播放独立转身表现；复用下蹲所用的图片序列，不改变 Fray 战斗状态。
func _on_facing_changed(_from_direction: int, _to_direction: int) -> void:
	if _animation_player == null or not _animation_player.has_animation(TURN_ANIMATION):
		return
	_turn_animation_active = true
	_animation_player.play(TURN_ANIMATION)


## 转发 tracker 的动画开始事件。
func _on_animation_started(animation_name: StringName) -> void:
	animation_event.emit(self, &"started", animation_name, 0.0)


## 转发 tracker 的动画进度事件。
func _on_animation_updated(animation_name: StringName, play_position: float) -> void:
	animation_event.emit(self, &"updated", animation_name, play_position)


## 转发 tracker 的动画结束事件；转身结束后恢复当前 Fray 状态对应的表现动画。
func _on_animation_finished(animation_name: StringName) -> void:
	animation_event.emit(self, &"finished", animation_name, 1.0)
	if animation_name != TURN_ANIMATION or not _turn_animation_active:
		return
	_turn_animation_active = false
	_play_state_animation(state_machine.get_current_state_name())
