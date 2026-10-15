class_name CombatCoreMatch
extends Node
## 固定 60 Hz 的第 2 组战斗 Tick 协调器。
##
## FrayHitState2D 只负责空间接触；本节点完整缓存同一物理帧的接触，按稳定键排序、去重，
## 再统一提交防御、伤害、气条、hitstop、反应、连段与 KO，避免节点遍历顺序决定结果。

signal interaction_resolved(result: Dictionary)
signal combo_started(context: Dictionary)
signal combo_changed(context: Dictionary)
signal combo_ended(context: Dictionary)
signal combat_snapshot_ready(snapshot: Dictionary)
signal double_ko_detected(fighters: Array, physics_frame: int)

const PUSHBOX_SEPARATION_MARGIN: float = 0.05
const CORNER_CROSSUP_MIN_SPEED: float = 1.0
const CORNER_CROSSUP_POSITION_EPSILON: float = 0.5

## 本场景共享规则资源。
@export var rules: CombatRuleSet

## 左侧 fighter 节点路径。
@export_node_path("CombatCoreFighter") var fighter_one_path: NodePath

## 右侧 fighter 节点路径。
@export_node_path("CombatCoreFighter") var fighter_two_path: NodePath

## 投射物容器路径。
@export_node_path("Node2D") var projectiles_root_path: NodePath

## 调试投射物场景；其 strike FrayHitbox2D.attribute 直接持有攻击资源。
@export var projectile_scene: PackedScene

var fighter_one: CombatCoreFighter
var fighter_two: CombatCoreFighter
var _projectiles_root: Node2D
var _pending_contacts: Array[Dictionary] = []
var _contact_ledger: Dictionary = {}
var _combo_by_defender: Dictionary = {}
var _recent_events: Array[Dictionary] = []
var _spawn_transforms: Dictionary = {}


## 校验规则、注册两名 fighter，并连接 hurtbox 接触信号。
func _ready() -> void:
	fighter_one = get_node_or_null(fighter_one_path) as CombatCoreFighter
	fighter_two = get_node_or_null(fighter_two_path) as CombatCoreFighter
	_projectiles_root = get_node_or_null(projectiles_root_path) as Node2D
	if rules == null or fighter_one == null or fighter_two == null or _projectiles_root == null:
		push_error("CombatCoreMatch 缺少 rules、fighter 或 projectiles root。")
		set_physics_process(false)
		return
	var errors := rules.validate()
	var configured_fps := int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 60))
	if configured_fps != rules.gameplay_fps:
		errors.append("project.godot 物理频率 %d 与 gameplay_fps %d 不一致。" % [configured_fps, rules.gameplay_fps])
	if not errors.is_empty():
		for message in errors:
			push_error("CombatRuleSet：%s" % message)
		set_physics_process(false)
		return
	_spawn_transforms[fighter_one.fighter_id] = fighter_one.global_transform
	_spawn_transforms[fighter_two.fighter_id] = fighter_two.global_transform
	fighter_one.set_combat_opponent(fighter_two)
	fighter_two.set_combat_opponent(fighter_one)
	fighter_one.combat_contact_requested.connect(_on_contact_requested)
	fighter_two.combat_contact_requested.connect(_on_contact_requested)
	fighter_one.projectile_requested.connect(_on_projectile_requested)
	fighter_two.projectile_requested.connect(_on_projectile_requested)
	fighter_one.knocked_out.connect(_on_fighter_knocked_out)
	fighter_two.knocked_out.connect(_on_fighter_knocked_out)


## 每个固定 tick 先分离双方 pushbox，再提交上一物理步缓存的接触批次并维护诊断快照。
func _physics_process(delta: float) -> void:
	_resolve_fighter_pushboxes(delta)
	if not _pending_contacts.is_empty():
		_submit_interaction_batch()
	_expire_combo_contexts()
	_prune_contact_ledger()
	combat_snapshot_ready.emit(get_combat_snapshot())


## 检测双方 pushbox 的矩形重叠；主动上升穿越可跳过分离，下落后再恢复墙角或普通推挤。
func _resolve_fighter_pushboxes(delta: float) -> void:
	if fighter_one == null or fighter_two == null:
		return
	var fighter_one_rect := fighter_one.get_pushbox_rect()
	var fighter_two_rect := fighter_two.get_pushbox_rect()
	if not fighter_one_rect.has_area() or not fighter_two_rect.has_area():
		return
	var overlap := fighter_one_rect.intersection(fighter_two_rect)
	if not overlap.has_area():
		return
	if not fighter_one.should_resolve_pushbox_with(fighter_two):
		return
	if not fighter_two.should_resolve_pushbox_with(fighter_one):
		return
	if _try_resolve_corner_air_crossup(fighter_one, fighter_two, fighter_one_rect, fighter_two_rect, delta):
		return
	if _try_resolve_corner_air_crossup(fighter_two, fighter_one, fighter_two_rect, fighter_one_rect, delta):
		return

	var fighter_one_direction := signf(fighter_one.global_position.x - fighter_two.global_position.x)
	if is_zero_approx(fighter_one_direction):
		fighter_one_direction = -1.0 if String(fighter_one.fighter_id) < String(fighter_two.fighter_id) else 1.0
	_separate_pushboxes(fighter_one, fighter_one_direction, fighter_two, -fighter_one_direction, overlap.size.x)


## 墙角外侧角色处于主动跳跃且继续朝墙移动时，让空中角色向墙侧、地面角色向中央分离。
## 该方向在双方中心点交叉前不按旧左右顺序反转，因此可实现真人快打式角落跳入换边。
func _try_resolve_corner_air_crossup(
	airborne: CombatCoreFighter,
	grounded: CombatCoreFighter,
	airborne_rect: Rect2,
	grounded_rect: Rect2,
	delta: float
) -> bool:
	if not airborne.can_air_crossup_pushbox() or grounded.is_airborne_for_combat():
		return false
	if airborne.environment == null or grounded.environment == null:
		return false

	var corner_window := grounded_rect.size.x + airborne_rect.size.x * 0.5
	var right_corner_distance := grounded.environment.arena_right - grounded.global_position.x
	var entering_right_corner := (
		right_corner_distance >= -CORNER_CROSSUP_POSITION_EPSILON
		and right_corner_distance <= corner_window
		and airborne.velocity.x > CORNER_CROSSUP_MIN_SPEED
	)
	if entering_right_corner:
		_move_pushboxes_in_directions(
			airborne,
			1.0,
			grounded,
			-1.0,
			maxf(absf(airborne.velocity.x) * delta, PUSHBOX_SEPARATION_MARGIN)
		)
		return true

	var left_corner_distance := grounded.global_position.x - grounded.environment.arena_left
	var entering_left_corner := (
		left_corner_distance >= -CORNER_CROSSUP_POSITION_EPSILON
		and left_corner_distance <= corner_window
		and airborne.velocity.x < -CORNER_CROSSUP_MIN_SPEED
	)
	if entering_left_corner:
		_move_pushboxes_in_directions(
			airborne,
			-1.0,
			grounded,
			1.0,
			maxf(absf(airborne.velocity.x) * delta, PUSHBOX_SEPARATION_MARGIN)
		)
		return true
	return false


## 按指定方向平分水平重叠；一方受场地边界限制时，把未完成位移交给另一方。
func _separate_pushboxes(
	first: CombatCoreFighter,
	first_direction: float,
	second: CombatCoreFighter,
	second_direction: float,
	overlap_width: float
) -> void:
	_move_pushboxes_in_directions(
		first,
		first_direction,
		second,
		second_direction,
		overlap_width + PUSHBOX_SEPARATION_MARGIN
	)


## 按给定总距离移动双方；墙角空中换边用小步连续穿越，普通分离则传入完整重叠宽度。
func _move_pushboxes_in_directions(
	first: CombatCoreFighter,
	first_direction: float,
	second: CombatCoreFighter,
	second_direction: float,
	distance: float
) -> void:
	var half_distance := distance * 0.5
	var remaining := distance
	remaining -= absf(first.move_horizontally_for_pushbox(first_direction * half_distance))
	remaining -= absf(second.move_horizontally_for_pushbox(second_direction * half_distance))
	if remaining > 0.0:
		remaining -= absf(first.move_horizontally_for_pushbox(first_direction * remaining))
	if remaining > 0.0:
		second.move_horizontally_for_pushbox(second_direction * remaining)


## 接收回合重置；攻击和波动指令全部由 fighter 的 Fray 输入与状态机处理。
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("combat_reset"):
		reset_round()


## 接收投射物施放 FrayState 的生成请求，并把实际攻击资源交给统一生成入口校验。
func _on_projectile_requested(fighter, attribute: FrayAttackAttribute) -> void:
	spawn_projectile(fighter as CombatCoreFighter, attribute)


## 缓存 hurtbox/strike 接触；本回调不直接改变生命和状态。
func _on_contact_requested(defender, _detector_hitbox: FrayHitbox2D, strike_hitbox: FrayHitbox2D) -> void:
	var typed_defender := defender as CombatCoreFighter
	if typed_defender == null or strike_hitbox == null:
		return
	var attribute := strike_hitbox.attribute as FrayAttackAttribute
	if attribute == null:
		push_error("命中接触缺少 FrayAttackAttribute，已阻止结算。")
		return
	var source := strike_hitbox.source
	var attacker: CombatCoreFighter
	if source is CombatCoreFighter:
		attacker = source
	elif source != null and source.has_method("get_combat_owner"):
		attacker = source.get_combat_owner() as CombatCoreFighter
	if attacker == null or attacker == typed_defender:
		return
	if not typed_defender.can_be_hit_by(attribute):
		return
	var token := StringName("missing")
	if source != null and source.has_method("get_combat_attack_token"):
		token = source.get_combat_attack_token(strike_hitbox)
	else:
		token = attacker.get_combat_attack_token(strike_hitbox)
	var attack_direction := attacker.facing_direction
	if source != null and source.has_method("get_combat_attack_direction"):
		attack_direction = int(source.get_combat_attack_direction())
	var hit_id := StringName("%s/%s" % [attribute.id, strike_hitbox.name])
	var key := "%s>%s:%s:%s" % [attacker.fighter_id, typed_defender.fighter_id, token, hit_id]
	if _contact_ledger.has(key):
		_record_event(&"duplicate_ignored", attacker, typed_defender, attribute, {"token": token, "hit_id": hit_id})
		return
	_contact_ledger[key] = Engine.get_physics_frames()
	_pending_contacts.append({
		"frame": Engine.get_physics_frames(),
		"key": key,
		"attacker": attacker,
		"defender": typed_defender,
		"source": source,
		"strike_hitbox": strike_hitbox,
		"attribute": attribute,
		"attack_direction": 1 if attack_direction >= 0 else -1,
		"token": token,
		"hit_id": hit_id,
	})


## 按稳定键排序完整批次，先计算全部结果，再分阶段提交伤害、资源和反应。
func _submit_interaction_batch() -> void:
	var batch := _pending_contacts.duplicate()
	_pending_contacts.clear()
	batch.sort_custom(_contact_less)
	var results: Array[Dictionary] = []
	for contact in batch:
		var result := _resolve_contact(contact)
		if not result.is_empty():
			results.append(result)
	if results.is_empty():
		return

	for result in results:
		var defender: CombatCoreFighter = result.defender
		defender.apply_health_delta(-int(result.damage), result.outcome, result.attribute)
	for result in results:
		_apply_meter_result(result)

	var reactions: Dictionary = {}
	for result in results:
		var attacker: CombatCoreFighter = result.attacker
		var defender: CombatCoreFighter = result.defender
		var attribute: FrayAttackAttribute = result.attribute
		var blocked := bool(result.blocked)
		var current: Dictionary = reactions.get(defender, {})
		var priority := _reaction_priority(result)
		var duration := attribute.blockstun_frames if blocked else attribute.hitstun_frames
		var current_priority := -1
		var current_duration := -1
		if not current.is_empty():
			var current_attribute: FrayAttackAttribute = current.attribute
			current_priority = _reaction_priority(current)
			current_duration = current_attribute.blockstun_frames if current.blocked else current_attribute.hitstun_frames
		if current.is_empty() or priority > current_priority or (priority == current_priority and duration > current_duration):
			reactions[defender] = result
		attacker.confirm_current_attack_contact(result.token, attribute, blocked)
		attacker.begin_hitstop(attribute.get_attacker_hitstop_frames(blocked))
		defender.begin_hitstop(attribute.get_defender_hitstop_frames(blocked))
		_consume_contact_source(result.source)
		interaction_resolved.emit(result.duplicate(true))

	for defender_key in reactions:
		var defender := defender_key as CombatCoreFighter
		if defender == null:
			continue
		var result: Dictionary = reactions[defender_key]
		defender.commit_combat_reaction(
			result.attribute,
			result.blocked,
			int(result.attack_direction),
			result.combo,
			bool(result.defender_was_airborne)
		)

	var knocked_out: Array = []
	for fighter in [fighter_one, fighter_two]:
		if fighter.health <= 0:
			knocked_out.append(fighter)
	if knocked_out.size() == 2:
		double_ko_detected.emit(knocked_out, Engine.get_physics_frames())


## 返回同帧多次交互的反应优先级：倒地高于浮空，浮空高于普通命中，命中高于格挡。
func _reaction_priority(result: Dictionary) -> int:
	if bool(result.blocked):
		return 0
	var attribute: FrayAttackAttribute = result.attribute
	if attribute.causes_knockdown():
		return 3
	if not is_zero_approx(attribute.get_launch_y_velocity(bool(result.defender_was_airborne))):
		return 2
	return 1


## 对单个已排序接触执行防御、juggle 与连段缩放裁决，不立即产生副作用。
func _resolve_contact(contact: Dictionary) -> Dictionary:
	var attacker: CombatCoreFighter = contact.attacker
	var defender: CombatCoreFighter = contact.defender
	var attribute: FrayAttackAttribute = contact.attribute
	if attacker.health <= 0 or defender.health <= 0:
		return {}
	var defender_was_airborne := defender.is_airborne_for_combat()
	var blocked := defender.is_guarding_against(attribute)
	var damage := attribute.block_damage if blocked else attribute.damage
	var scale := 1.0
	var combo_context: Dictionary = {}
	if not blocked:
		combo_context = _advance_combo(attacker, defender, attribute)
		if combo_context.get("rejected", false):
			_record_event(&"juggle_rejected", attacker, defender, attribute, combo_context)
			return {}
		scale = float(combo_context.scale)
		damage = int(floor(float(attribute.damage) * scale))
		if attribute.damage > 0:
			damage = maxi(damage, 1)
	var outcome := &"block" if blocked else &"hit"
	var result := {
		"physics_frame": Engine.get_physics_frames(),
		"attacker": attacker,
		"defender": defender,
		"source": contact.source,
		"attribute": attribute,
		"attribute_id": attribute.id,
		"attack_direction": int(contact.attack_direction),
		"token": contact.token,
		"hit_id": contact.hit_id,
		"blocked": blocked,
		"defender_was_airborne": defender_was_airborne,
		"outcome": outcome,
		"damage": damage,
		"scale": scale,
		"combo": combo_context.duplicate(true),
	}
	_record_event(outcome, attacker, defender, attribute, {"damage": damage, "scale": scale, "token": contact.token})
	return result


## 创建或续接 ComboContext，并应用逐击、起手、重复招式与 juggle 规则。
func _advance_combo(attacker: CombatCoreFighter, defender: CombatCoreFighter, attribute: FrayAttackAttribute) -> Dictionary:
	var frame: int = Engine.get_physics_frames()
	var key: StringName = defender.fighter_id
	var context: Dictionary = _combo_by_defender.get(key, {})
	var continuing: bool = (
		not context.is_empty()
		and StringName(context.get("attacker_id", &"")) == attacker.fighter_id
		and frame - int(context.get("last_hit_frame", -999999)) <= rules.combo_timeout_frames
	)
	if not continuing:
		if not context.is_empty():
			_end_combo(key, &"replaced")
		context = {
			"attacker_id": attacker.fighter_id,
			"defender_id": defender.fighter_id,
			"hits": 0,
			"damage": 0,
			"juggle": 0,
			"air_hits": 0,
			"scale": attribute.combo_initial_scale,
			"last_move": &"",
			"last_hit_frame": frame,
			"move_chain": [],
		}
	var next_juggle := int(context.juggle)
	var defender_was_airborne := defender.is_airborne_for_combat()
	if defender_was_airborne:
		next_juggle += attribute.juggle_increment
		if next_juggle > attribute.juggle_limit:
			return {"rejected": true, "reason": &"juggle_limit", "juggle": next_juggle, "limit": attribute.juggle_limit}
	elif attribute.launch_y_velocity < 0.0:
		next_juggle = attribute.juggle_start
	var hit_index := int(context.hits)
	var scale := attribute.combo_initial_scale * pow(rules.combo_decay, hit_index)
	if StringName(context.last_move) == attribute.id:
		scale *= rules.repeated_move_scale
	scale = maxf(scale, rules.minimum_damage_scale)
	var scaled_damage := int(floor(float(attribute.damage) * scale))
	if attribute.damage > 0:
		scaled_damage = maxi(scaled_damage, 1)
	context.hits = hit_index + 1
	context.damage = int(context.damage) + scaled_damage
	context.juggle = next_juggle
	if defender_was_airborne:
		context.air_hits = int(context.get("air_hits", 0)) + 1
	else:
		context.air_hits = 0
	context.scale = scale
	context.last_move = attribute.id
	context.last_hit_frame = frame
	var chain: Array = context.move_chain
	chain.append(attribute.id)
	context.move_chain = chain
	_combo_by_defender[key] = context
	if int(context.hits) == 1:
		combo_started.emit(context.duplicate(true))
	else:
		combo_changed.emit(context.duplicate(true))
	return context


## 根据唯一 FrayAttackAttribute 上的气条收益字段提交双方资源变化。
func _apply_meter_result(result: Dictionary) -> void:
	var attacker: CombatCoreFighter = result.attacker
	var defender: CombatCoreFighter = result.defender
	var attribute: FrayAttackAttribute = result.attribute
	if result.blocked:
		attacker.add_meter(attribute.attacker_meter_gain_block, &"attack_blocked", attribute)
		defender.add_meter(attribute.defender_meter_gain_block, &"guard_success", attribute)
	else:
		attacker.add_meter(attribute.attacker_meter_gain_hit, &"attack_hit", attribute)
		defender.add_meter(attribute.defender_meter_gain_hit, &"damage_taken", attribute)


## 在连段超时后发出结束快照并释放上下文。
func _expire_combo_contexts() -> void:
	var frame := Engine.get_physics_frames()
	for key in _combo_by_defender.keys():
		var context: Dictionary = _combo_by_defender[key]
		if frame - int(context.last_hit_frame) > rules.combo_timeout_frames:
			_end_combo(key, &"timeout")


## 结束指定 defender 的连段并发出只读快照。
func _end_combo(key: StringName, reason: StringName) -> void:
	if not _combo_by_defender.has(key):
		return
	var context: Dictionary = _combo_by_defender[key]
	context.end_reason = reason
	combo_ended.emit(context.duplicate(true))
	_combo_by_defender.erase(key)


## 移除过旧的去重键，避免长时间训练时 ledger 无界增长。
func _prune_contact_ledger() -> void:
	var cutoff := Engine.get_physics_frames() - 600
	for key in _contact_ledger.keys():
		if int(_contact_ledger[key]) < cutoff:
			_contact_ledger.erase(key)


## 命中或格挡后通知投射物关闭 strike；近战 source 不需要额外处理。
func _consume_contact_source(source) -> void:
	if source != null and is_instance_valid(source) and source.has_method("consume_after_contact"):
		source.consume_after_contact()


## 生成一枚使用 FrayHitState2D/FrayHitbox2D 的投射物，并校验其 strike 使用施放状态传入的同一资源。
func spawn_projectile(attacker: CombatCoreFighter, expected_attribute: FrayAttackAttribute) -> void:
	if projectile_scene == null or attacker == null or attacker.health <= 0 or attacker.training_dummy:
		return
	var projectile = projectile_scene.instantiate()
	if projectile == null or not projectile.has_method("setup"):
		push_error("projectile_scene 必须实现 setup(owner, direction, attribute)。")
		return
	if not projectile.has_signal("combat_contact_requested"):
		push_error("projectile_scene 必须提供 combat_contact_requested 信号。")
		projectile.queue_free()
		return
	projectile.setup(attacker, attacker.facing_direction, expected_attribute)
	projectile.connect(&"combat_contact_requested", Callable(self, "_on_contact_requested"))
	# add_child() 会触发 projectile._ready() 激活 strike，因此先写入最终出生位置。
	var spawn_global_position := attacker.global_position + Vector2(72.0 * attacker.facing_direction, -32.0)
	projectile.position = _projectiles_root.to_local(spawn_global_position)
	_projectiles_root.add_child(projectile)
	if expected_attribute != null and projectile.has_method("get_attack_attribute"):
		var actual_attribute := projectile.get_attack_attribute() as FrayAttackAttribute
		if actual_attribute != expected_attribute:
			push_error("projectile_scene 的 strike 未使用 fighter 施放状态传入的同一 FrayAttackAttribute。")
			projectile.queue_free()
			return


## 清理接触、连段和投射物，并重置双方到初始位置。
func reset_round() -> void:
	_pending_contacts.clear()
	_contact_ledger.clear()
	for key in _combo_by_defender.keys():
		_end_combo(key, &"round_reset")
	for child in _projectiles_root.get_children():
		if child.has_method("consume_after_contact"):
			child.consume_after_contact()
		else:
			child.queue_free()
	fighter_one.reset_combat(_spawn_transforms[fighter_one.fighter_id], 1)
	fighter_two.reset_combat(_spawn_transforms[fighter_two.fighter_id], -1)
	_recent_events.clear()


## 返回 HUD 与测试工具使用的只读 CombatSnapshot。
func get_combat_snapshot() -> Dictionary:
	return {
		"physics_frame": Engine.get_physics_frames(),
		"fighter_one": fighter_one.get_combat_snapshot() if fighter_one != null else {},
		"fighter_two": fighter_two.get_combat_snapshot() if fighter_two != null else {},
		"combos": _combo_by_defender.duplicate(true),
		"pending_contacts": _pending_contacts.size(),
		"dedupe_entries": _contact_ledger.size(),
		"recent_events": _recent_events.duplicate(true),
	}


## 用 fighter、token、hit id 构造稳定批次顺序。
func _contact_less(a: Dictionary, b: Dictionary) -> bool:
	return String(a.key) < String(b.key)


## 保存有界战斗事件日志，字段均可追踪到 attribute.id。
func _record_event(event_name: StringName, attacker: CombatCoreFighter, defender: CombatCoreFighter, attribute: FrayAttackAttribute, extra: Dictionary = {}) -> void:
	var event := {
		"frame": Engine.get_physics_frames(),
		"event": event_name,
		"attacker": attacker.fighter_id,
		"defender": defender.fighter_id,
		"attribute_id": attribute.id,
	}
	event.merge(extra, true)
	_recent_events.append(event)
	while _recent_events.size() > 14:
		_recent_events.pop_front()


## KO 信号仅用于补充日志；真正 KO 状态在批次反应提交阶段进入。
func _on_fighter_knocked_out(fighter, attribute: FrayAttackAttribute) -> void:
	var typed_fighter := fighter as CombatCoreFighter
	if typed_fighter == null:
		return
	var opponent := fighter_two if typed_fighter == fighter_one else fighter_one
	_record_event(&"ko", opponent, typed_fighter, attribute)
