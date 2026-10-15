class_name DemoFighterAttackModule
extends RefCounted

## 角色攻击模块：发现场景中的 Fray 命中状态、缓存真实攻击属性并负责攻击框开关与接触结算。
## 固定招式的数值只从 strike `FrayHitbox2D.attribute` 读取；投射物则直接使用招式上的属性。

var fighter: DemoFighter
var hurt_manager: FrayHitStateManager2D
var attack_manager: FrayHitStateManager2D
var move_cache: Dictionary = {}
var hit_targets: Dictionary = {}
var active_attack_state: StringName = &""


## 连接 Fray 命中管理器，并从场景中缓存 Loadout 使用的固定攻击。
func setup(
	p_fighter: DemoFighter,
	p_hurt_manager: FrayHitStateManager2D,
	p_attack_manager: FrayHitStateManager2D,
	loadout: DemoFighterLoadout
) -> void:
	fighter = p_fighter
	hurt_manager = p_hurt_manager
	attack_manager = p_attack_manager
	move_cache.clear()

	for entry in loadout.get_installed_entries():
		var move := entry.move
		if move.uses_projectile_attack():
			_cache_move(move, move.attack_attribute, null)
			continue
		_cache_fixed_move(move)

	hurt_manager.source = fighter
	attack_manager.source = fighter
	_deactivate_hit_states(hurt_manager)
	clear_attack_hitboxes()
	if not attack_manager.hitbox_intersected.is_connected(_on_attack_hitbox_intersected):
		attack_manager.hitbox_intersected.connect(_on_attack_hitbox_intersected)


## 返回已成功缓存的招式标识。
func get_move_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for move_id in move_cache.keys():
		result.append(StringName(move_id))
	return result


## 判断攻击模块是否包含指定招式。
func has_move(move_id: StringName) -> bool:
	return move_cache.has(move_id)


## 返回指定招式定义。
func get_move(move_id: StringName) -> DemoMoveDefinition:
	return _get_move_cache_value(move_id, &"move") as DemoMoveDefinition


## 返回命中框实际引用的攻击属性。
func get_attack(move_id: StringName) -> FrayAttackAttribute:
	return _get_move_cache_value(move_id, &"attack") as FrayAttackAttribute


## 激活指定姿态对应的受击框。
func set_hurt_state(state_name: StringName) -> void:
	var state := hurt_manager.get_node_or_null(NodePath(state_name)) as FrayHitState2D
	if state != null:
		state.active_hitboxes = _all_hitbox_bits(state)


## 清空已命中目标并关闭全部攻击框。
func clear_attack_state() -> void:
	hit_targets.clear()
	clear_attack_hitboxes()


## 清空当前攻击窗口已命中的目标。
func reset_attack_targets() -> void:
	hit_targets.clear()


## 统一解析 melee 或 projectile 的 Fray 命中接触，只缓存成功结算的目标。
func try_resolve_contact(
	detector_hitbox: FrayHitbox2D,
	detected_hitbox: FrayHitbox2D,
	target_cache: Dictionary
) -> bool:
	if detected_hitbox.source == fighter or not (detected_hitbox.source is DemoFighter):
		return false

	var target := detected_hitbox.source as DemoFighter
	if target_cache.has(target):
		return false

	var attack := detector_hitbox.attribute as FrayAttackAttribute
	if attack == null or not target.receive_hit(fighter, attack):
		return false

	target_cache[target] = true
	return true


## 根据攻击帧启用或关闭固定攻击框；投射物招式没有角色攻击框，因此直接跳过。
func update_attack_hitbox_window(attack: FrayAttackAttribute, attack_frame: int) -> void:
	if _get_hit_state(attack.id) == null:
		return
	var active_start := attack.startup_frames
	var active_end := active_start + attack.active_frames
	set_attack_hitbox(attack.id, attack_frame >= active_start and attack_frame < active_end)


## 切换指定攻击状态的命中框并处理即时重叠。
func set_attack_hitbox(state_name: StringName, active: bool) -> void:
	var state := _get_hit_state(state_name)
	if state == null:
		return
	if not active:
		clear_attack_hitboxes()
		return

	var is_new_active_window := active_attack_state != state_name
	var hitbox_bits := _all_hitbox_bits(state)
	active_attack_state = state_name
	if state.active_hitboxes != hitbox_bits:
		state.active_hitboxes = hitbox_bits
	if is_new_active_window:
		_resolve_active_attack_overlaps(state)


## 关闭攻击管理器中的全部命中框。
func clear_attack_hitboxes() -> void:
	if attack_manager == null:
		return
	_deactivate_hit_states(attack_manager)
	active_attack_state = &""


## 从攻击管理器中缓存一个固定 FrayHitState2D，并从其 strike 读取攻击属性。
func _cache_fixed_move(move: DemoMoveDefinition) -> void:
	var hit_state := attack_manager.get_node_or_null(NodePath(move.id)) as FrayHitState2D
	if hit_state == null:
		push_warning("Move %s has no matching FrayHitState2D in the fighter scene" % move.id)
		return

	var attack := _get_hit_state_attack(move, hit_state)
	if attack == null:
		return

	hit_state.set_hitbox_source(fighter)
	hit_state.active_hitboxes = 0
	hit_state.deactivate()
	_cache_move(move, attack, hit_state)

## 校验固定命中状态，并返回其唯一攻击属性。
func _get_hit_state_attack(move: DemoMoveDefinition, hit_state: FrayHitState2D) -> FrayAttackAttribute:
	if StringName(hit_state.name) != move.id:
		push_warning("Move %s hit-state root name must match its ID" % move.id)
		return null
	var hitboxes := hit_state.get_hitboxes()
	if hitboxes.is_empty():
		push_warning("Move %s FrayHitState2D has no hitboxes" % move.id)
		return null

	var result: FrayAttackAttribute
	for hitbox in hitboxes:
		var attack := hitbox.attribute as FrayAttackAttribute
		if attack == null or attack.id != move.id:
			push_warning("Move %s hitbox must reference a matching FrayAttackAttribute" % move.id)
			return null
		if result != null and result != attack:
			push_warning("Move %s hitboxes must share one FrayAttackAttribute" % move.id)
			return null
		result = attack
	return result


## 缓存一个已验证招式的直接场景引用。
func _cache_move(
	move: DemoMoveDefinition,
	attack: FrayAttackAttribute,
	hit_state: FrayHitState2D
) -> void:
	if attack == null or attack.id != move.id:
		push_warning("Move %s has no matching FrayAttackAttribute" % move.id)
		return
	move_cache[move.id] = {
		&"move": move,
		&"attack": attack,
		&"hit_state": hit_state,
	}


## 返回指定招式的一项缓存引用。
func _get_move_cache_value(move_id: StringName, key: StringName) -> Variant:
	var data: Dictionary = move_cache.get(move_id, {})
	return data.get(key)


## 返回固定招式的 FrayHitState2D；投射物招式返回空。
func _get_hit_state(move_id: StringName) -> FrayHitState2D:
	return _get_move_cache_value(move_id, &"hit_state") as FrayHitState2D


## 停用指定管理器中的全部 Fray 命中状态。
func _deactivate_hit_states(manager: FrayHitStateManager2D) -> void:
	for child in manager.get_children():
		var state := child as FrayHitState2D
		if state == null:
			continue
		state.active_hitboxes = 0
		state.deactivate()


## 计算命中状态中全部命中框的激活位掩码。
func _all_hitbox_bits(state: FrayHitState2D) -> int:
	var hitbox_count := state.get_hitboxes().size()
	return (1 << hitbox_count) - 1 if hitbox_count > 0 else 0


## 攻击框激活时立即处理已经存在的重叠目标。
func _resolve_active_attack_overlaps(state: FrayHitState2D) -> void:
	var hitboxes := state.get_hitboxes()
	for i in hitboxes.size():
		var detector := hitboxes[i]
		if not state.is_hitbox_active(i) or not detector.monitoring:
			continue
		for detected in _query_overlapping_hitboxes_immediate(detector):
			_on_attack_hitbox_intersected(detector, detected)


## 立即查询当前攻击框重叠的 Fray 命中框。
func _query_overlapping_hitboxes_immediate(detector: FrayHitbox2D) -> Array[FrayHitbox2D]:
	var overlaps: Array[FrayHitbox2D] = []
	var seen := {}
	var space_state := detector.get_world_2d().direct_space_state
	for child in detector.get_children():
		var shape_node := child as CollisionShape2D
		if shape_node == null or shape_node.disabled or shape_node.shape == null:
			continue

		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = shape_node.shape
		query.transform = shape_node.global_transform
		query.collision_mask = detector.collision_mask
		query.collide_with_areas = true
		query.collide_with_bodies = false
		query.exclude = [detector.get_rid()]

		for result in space_state.intersect_shape(query, 32):
			var candidate := result.get("collider") as FrayHitbox2D
			if candidate == null or candidate == detector or not candidate.monitorable:
				continue
			if seen.has(candidate.get_instance_id()) or not detector.can_detect(candidate):
				continue
			seen[candidate.get_instance_id()] = true
			overlaps.append(candidate)
	return overlaps


## 将攻击框相交事件交给统一接触解析器处理。
func _on_attack_hitbox_intersected(
	detector_hitbox: FrayHitbox2D,
	detected_hitbox: FrayHitbox2D
) -> void:
	if fighter.get_current_attack() == &"":
		return
	try_resolve_contact(detector_hitbox, detected_hitbox, hit_targets)
