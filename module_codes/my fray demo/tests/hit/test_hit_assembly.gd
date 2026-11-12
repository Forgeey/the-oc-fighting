extends Node
## 验证实际资源动态装配、生命周期和物理接触，不补写转换条件或实现战斗结果。

const ATTACK := &"light_attack"
const BASE_STATES: Array[StringName] = [&"idle", &"fwalk", &"bwalk", &"crouch"]
var checks := 0
var failures := 0


func _enter_tree() -> void:
	# 本套件直接测试姿态，真实输入与自动转换仍由独立 movement 套件验证。
	FrayInput.set_physics_process(false)


func _ready() -> void:
	_run.call_deferred()


func _check(value: bool, label: String) -> void:
	checks += 1
	if value:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


## 提供一份独立选择，定义库仍按只读共享使用。
func _loadout(paths: Array[StringName], moves: Array[StringName] = []) -> FighterLoadout:
	var result := load("res://resource/characters/demo_loadout.tres").duplicate() as FighterLoadout
	result.selected_state_names = paths
	result.selected_move_ids = moves
	return result


## 在不进入场景树的 Fighter 模板上验证 Manager 不再预置。
func _spawn(loadout: FighterLoadout = null, audit: Dictionary = {}) -> Fighter:
	var actor: Fighter = load("res://scenes/Fighter.tscn").instantiate()
	_check(not actor.has_node("FrayHitStateManager2D"), "Fighter template contains no static manager")
	if loadout != null:
		actor.loadout = loadout
	actor.child_entered_tree.connect(func(child: Node) -> void:
		if child is FrayHitStateManager2D:
			audit["complete_before_ready"] = child.get_child_count() == actor.hit_states.size()
			child.ready.connect(func() -> void:
				audit["ready_all_disabled"] = _all_disabled(child)
				audit["ready_connected"] = _connected(child))
	)
	add_child(actor)
	actor.set_physics_process(false)
	actor.state_machine.set_physics_process(false)
	actor.fighter_input.set_physics_process(false)
	return actor


## 按完整状态路径定位本角色的静态判定定义。
func _definition(actor: Fighter, path: StringName) -> FighterHitStateDefinition:
	return (actor.state_machine.get_root().get_state(path) as FighterState).state_definition.hit_state_definition


## 检查包括标志、掩码、可见性和区域监测的完整停用状态。
func _all_disabled(manager: FrayHitStateManager2D) -> bool:
	for pose: FrayHitState2D in manager.get_children():
		if pose.is_active() or pose.active_hitboxes != 0 or pose.visible:
			return false
		for box in pose.get_hitboxes():
			if box.monitoring or box.monitorable or box.visible:
				return false
	return true


## 检查原生 ready 只为每个姿态和框连接一次。
func _connected(manager: FrayHitStateManager2D) -> bool:
	for pose: FrayHitState2D in manager.get_children():
		if not pose.is_node_ready() or pose.active_hitboxes_changed.get_connections().size() != 1:
			return false
		if pose.hitbox_intersected.get_connections().size() != 1 or pose.hitbox_separated.get_connections().size() != 1:
			return false
		for box in pose.get_hitboxes():
			if box.hitbox_entered.get_connections().size() != 1 or box.hitbox_exited.get_connections().size() != 1:
				return false
	return true


## 对活动姿态逐框验证掩码和其余姿态的完整关闭。
func _expect_pose(actor: Fighter, definition: FighterHitStateDefinition, label: String) -> void:
	var expected := actor.hit_states[definition]
	_check(actor._current_hit_state == expected and actor.hit_state_manager.get_current_state_obj() == expected, label + " selects mapped pose")
	for pose: FrayHitState2D in actor.hit_state_manager.get_children():
		if pose == expected:
			_check(pose.is_active() and pose.active_hitboxes == definition.default_active_hitboxes and pose.visible, label + " applies default mask")
		else:
			_check(not pose.is_active() and pose.active_hitboxes == 0 and not pose.visible, label + " completely deactivates other pose")
		for i in pose.get_hitboxes().size():
			var box := pose.get_hitboxes()[i]
			var enabled := pose == expected and (definition.default_active_hitboxes & (1 << i)) != 0
			_check(box.monitoring == enabled and box.monitorable == enabled and box.visible == enabled, label + " toggles actual box flags")


func _run() -> void:
	_test_builder_selections()
	_test_mount_and_lifecycle()
	_test_independence_and_scene_contracts()
	await _test_contact_and_mirroring()
	print("HIT ASSEMBLY TESTS: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)


## 选择只解析一次；两套 Builder 共用结果，判定 Builder 不读取装备或转换库。
func _test_builder_selections() -> void:
	for loadout in [
		_loadout([&"idle"]),
		_loadout(BASE_STATES.duplicate()),
		_loadout([&"idle"], [&"01010001"]),
		_loadout(BASE_STATES.duplicate(), [&"01010001"]),
		_loadout([&"idle", ATTACK]),
	]:
		var hit_builder := FighterHitStateBuilder.new()
		var without_transitions := loadout.duplicate() as FighterLoadout
		without_transitions.transition_library = null
		var selection := without_transitions.resolve_selection()
		var manager := hit_builder.build(selection.states)
		_check(not manager.is_inside_tree() and not manager.is_node_ready(), "builder returns off-tree manager")
		_check(_all_disabled(manager), "all constructed poses and boxes start fully disabled")
		var fighter := Fighter.new()
		# ????????????????????????? ready?
		fighter.fighter_input = FighterInput.new()
		fighter.add_child(fighter.fighter_input)
		var root := FighterSMBuilder.new().build(fighter, loadout, selection)
		var expected: Dictionary = {}
		for state in loadout.state_library.states:
			var path: StringName = state.state_name
			if root.has_state(path):
				expected[state.hit_state_definition] = true
		_check(manager.get_child_count() == expected.size() and hit_builder.hit_states.size() == expected.size(), "hit selection equals actual assembled leaf dependencies")
		for definition in expected:
			_check(hit_builder.hit_states.has(definition), "every assembled state dependency has its pose")
		manager.free()
		fighter.free()

	var duplicated := _loadout([&"idle", &"idle"], [&"01010001", &"01010002"])
	duplicated.move_library = duplicated.move_library.duplicate()
	duplicated.move_library.moves = duplicated.move_library.moves.duplicate()
	var other := duplicated.move_library.moves[0].duplicate() as FighterMoveDefinition
	other.move_id = &"01010002"
	other.state = duplicated.move_library.moves[0].state
	duplicated.move_library.moves.append(other)
	var builder := FighterHitStateBuilder.new()
	var selection := duplicated.resolve_selection()
	_check(selection.states.size() == 2 and selection.moves.size() == 2, "one resolver deduplicates shared execution states and preserves selected moves")
	_check(duplicated.selected_state_names == [&"idle", &"idle"], "resolving does not mutate authored selection arrays")
	var only_other := duplicated.duplicate() as FighterLoadout
	only_other.selected_move_ids = [&"01010002"]
	var only_other_selection := only_other.resolve_selection()
	_check(only_other_selection.moves.size() == 1 and only_other_selection.moves[0] == other, "execution state dependencies never auto-equip an unselected move")
	var manager := builder.build(selection.states)
	_check(manager.get_child_count() == 2, "repeated paths and multiple moves sharing states do not duplicate poses")
	manager.free()

	var same_name := _loadout([&"idle", &"reaction_idle", &"root_leaf"])
	same_name.state_library = same_name.state_library.duplicate()
	same_name.state_library.states = same_name.state_library.states.duplicate()
	var state := same_name.state_library.states[0].duplicate() as FighterStateDefinition
	state.state_id = &"0002000100"

	state.state_name = &"reaction_idle"
	state.hit_state_definition = state.hit_state_definition.duplicate()
	same_name.state_library.states.append(state)
	var root_state := state.duplicate() as FighterStateDefinition
	root_state.state_id = &"0003000100"

	root_state.state_name = &"root_leaf"
	root_state.hit_state_definition = state.hit_state_definition.duplicate()
	same_name.state_library.states.append(root_state)
	manager = builder.build(same_name.resolve_selection().states)
	_check(manager.get_child_count() == 3, "globally unique state names distinguish independent definitions without runtime groups")
	_check(builder.hit_states.size() == 3, "different definitions sharing one scene are not merged")
	var shape_a := (manager.get_child(0).get_child(0).get_child(0) as CollisionShape2D).shape
	var shape_b := (manager.get_child(1).get_child(0).get_child(0) as CollisionShape2D).shape
	_check(shape_a != shape_b, "same PackedScene instances have independent mutable geometry")
	manager.free()




## 验证真正动态挂载、默认姿态和各种进入/退出路径。
func _test_mount_and_lifecycle() -> void:
	var audit: Dictionary = {}
	var actor := _spawn(null, audit)
	_check(audit.get("complete_before_ready", false), "all three poses were installed before manager entered the tree")
	_check(audit.get("ready_all_disabled", false), "nothing enabled during native ready wiring")
	_check(audit.get("ready_connected", false) and _connected(actor.hit_state_manager), "native signals connected once without manual hot registration")
	_check(actor.get_children().filter(func(node: Node) -> bool: return node is FrayHitStateManager2D).size() == 1, "fighter owns exactly one manager")
	_check(actor.hit_state_manager.get_child_count() == 3 and actor.hit_states.size() == 3, "default loadout assembles only three unique poses")
	for pose: FrayHitState2D in actor.hit_state_manager.get_children():
		for box in pose.get_hitboxes():
			_check(box.source == actor, "post-mount source propagates to every box")
			_check((box.get_child(0) as CollisionShape2D).debug_color == box.attribute.get_color(), "authored scene debug color matches hitbox attribute")
	var root := actor.state_machine.get_root()
	var standing := _definition(actor, &"idle")
	_expect_pose(actor, standing, "initial idle")
	for path in BASE_STATES:
		root.goto(path)
		_expect_pose(actor, _definition(actor, path), "enter " + String(path))
	_check(_definition(actor, &"fwalk") == standing and _definition(actor, &"bwalk") == standing, "three movement behaviors share one standing definition")
	root.goto(&"idle")
	_check(is_equal_approx(actor.body_shape.shape.size.y, 108.0), "crouch exit still restores world body height")
	var move := actor.loadout.move_library.moves[0]
	var attack_definition := _definition(actor, ATTACK)
	root.goto(ATTACK, {"move": move})
	_expect_pose(actor, attack_definition, "attack entry")
	var attack_box := actor._current_hit_state.get_node("Attackbox") as FrayHitbox2D
	_check(not attack_box.monitoring, "attack starts with Hurt/Push only")
	actor.set_hit_state_mask(7)
	_check(attack_box.monitoring and attack_box.monitorable, "explicit mask API can enable attack bit without replacing Hurt/Push")
	root._transition_to(ATTACK, {"move": move}, root.get_state(ATTACK))
	_check(not attack_box.monitoring and actor._current_hit_state.active_hitboxes == 3, "external self re-entry clears transient attack mask and restores defaults")
	var attack := root.get_state(ATTACK) as BasicAttackState
	for i in attack.total_frames():
		attack._physics_process_impl(1.0 / 60.0)
	_check(not attack_box.monitoring, "Attackbox closes automatically after active frames and remains closed at action end")
	root.goto(&"idle")
	_expect_pose(actor, standing, "interrupted attack returns to standing")
	actor.clear_hit_state()
	_check(actor._current_hit_state == null and _all_disabled(actor.hit_state_manager), "clear zeroes masks and truly stops every pose")
	actor.select_hit_state(standing)
	actor.set_hit_state_mask(1)
	_check(actor._current_hit_state.active_hitboxes == 1, "nonzero mask updates the selected pose")
	actor.clear_hit_state()
	_check(actor._current_hit_state == null and _all_disabled(actor.hit_state_manager), "explicit clear is the complete shutdown API")
	actor.select_hit_state(standing)
	_check(actor._current_hit_state.is_active(), "same previously selected manager name can be reactivated after cleanup")
	actor._current_hit_state.set_block_signals(true)
	actor.clear_hit_state()
	_check(actor.hit_states[standing].is_blocking_signals(), "cleanup preserves an existing signal-block state")
	actor.hit_states[standing].set_block_signals(false)
	actor.select_hit_state(standing)
	_expect_pose(actor, standing, "explicit reselection after cleanup")
	actor.free()


## 验证必填判定配置、场景本地几何和跨角色独立性，不再测试非法空定义。
func _test_independence_and_scene_contracts() -> void:
	var a := _spawn()
	var b := _spawn()
	var definition := _definition(a, &"idle")
	_check(definition == _definition(b, &"idle"), "fighters share immutable hit definitions")
	_check(a.hit_state_manager != b.hit_state_manager and a._current_hit_state != b._current_hit_state, "fighters own separate manager and pose nodes")
	var body_b_size: Vector2 = b.body_shape.shape.size
	a.set_crouching(true)
	_check(a.body_shape.shape != b.body_shape.shape and b.body_shape.shape.size == body_b_size, "scene-local world body shapes isolate crouching between fighters")
	var shape_a := (a._current_hit_state.get_node("Hurtbox/CollisionShape2D") as CollisionShape2D).shape as RectangleShape2D
	var shape_b := (b._current_hit_state.get_node("Hurtbox/CollisionShape2D") as CollisionShape2D).shape as RectangleShape2D
	var size_b := shape_b.size
	shape_a.size = Vector2(1, 2)
	_check(shape_a != shape_b and shape_b.size == size_b, "changing one fighter's geometry cannot affect another")
	a.clear_hit_state()
	_check(b._current_hit_state != null and b._current_hit_state.active_hitboxes == 3, "one fighter clearing pose cannot clear another")
	a.free()
	b.free()
	var minimal := _spawn(_loadout([&"idle"]))
	_check(minimal.hit_state_manager.get_child_count() == 1, "idle-only fighter only has standing pose")
	minimal.free()
	var movement := _spawn(_loadout(BASE_STATES.duplicate()))
	_check(movement.hit_state_manager.get_child_count() == 2, "unequipped attack has no attack pose")
	movement.free()
	var from_move := _spawn(_loadout([&"idle"], [&"01010001"]))
	_check(from_move.hit_state_manager.get_child_count() == 2 and from_move.hit_states.has(_definition(from_move, ATTACK)), "move-only state dependency assembles attack pose")
	from_move.free()
	var loadout := load("res://resource/characters/demo_loadout.tres") as FighterLoadout
	for state in loadout.state_library.states:
		var hit := state.hit_state_definition
		_check(hit != null and hit.default_active_hitboxes > 0, "authored state declares a mandatory nonzero pose: " + String(state.state_name))
		var first := hit.hit_state_scene.instantiate() as FrayHitState2D
		var second := hit.hit_state_scene.instantiate() as FrayHitState2D
		var first_boxes: Array = first.get_hitboxes()
		var second_boxes: Array = second.get_hitboxes()
		for i in first_boxes.size():
			var first_shape := first_boxes[i].get_node("CollisionShape2D") as CollisionShape2D
			var second_shape := second_boxes[i].get_node("CollisionShape2D") as CollisionShape2D
			_check(first_shape.shape.resource_local_to_scene and first_shape.shape != second_shape.shape, "authored hit scene isolates geometry without builder duplication")
			_check(first_boxes[i].attribute != null and first_shape.debug_color == first_boxes[i].attribute.get_color(), "authored hit scene provides attributes and debug colors")
		first.free()
		second.free()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame


## 使用两个模板实例验证真实区域接触，只观察信号，不结算伤害或推挤。
func _test_contact_and_mirroring() -> void:
	var attacker := _spawn()
	var target := _spawn()
	attacker.position = Vector2(400, 100)
	target.position = Vector2(500, 100)
	var root := attacker.state_machine.get_root()
	root.goto(ATTACK, {"move": attacker.loadout.move_library.moves[0]})
	var attack := attacker._current_hit_state.get_node("Attackbox") as FrayHitbox2D
	var hurt := target._current_hit_state.get_node("Hurtbox") as FrayHitbox2D
	var own_hurt := attacker._current_hit_state.get_node("Hurtbox") as FrayHitbox2D
	var push := attacker._current_hit_state.get_node("Pushbox") as FrayHitbox2D
	var target_push := target._current_hit_state.get_node("Pushbox") as FrayHitbox2D
	_check(attack.can_detect(hurt) and not attack.can_detect(own_hurt), "attack detects other source Hurt but rejects self source")
	_check(not attack.can_detect(push) and not hurt.can_detect(attack), "attribute relations reject Attack/Push and Hurt detection")
	_check(push.can_detect(target_push), "Push attribute allows other Push contact without resolution")
	var entered: Array = []
	var separated: Array = []
	attacker.hit_state_manager.hitbox_intersected.connect(func(detector: FrayHitbox2D, detected: FrayHitbox2D) -> void:
		if detector == attack:
			entered.append(detected))
	attacker.hit_state_manager.hitbox_separated.connect(func(detector: FrayHitbox2D, detected: FrayHitbox2D) -> void:
		if detector == attack:
			separated.append(detected))
	await _frames(3)
	_check(entered.is_empty(), "assembled attack pose does not detect targets while Attackbox is disabled")
	attacker.set_hit_state_mask(7)
	await _frames(3)
	_check(hurt in entered and not own_hurt in entered, "real physics contact reaches Manager through native signals without self-hit")
	_check(hurt in attack.get_overlapping_hitboxes(), "physical overlap query agrees with forwarded attack contact")
	var offset := attack.global_position.x - attacker.global_position.x
	var local_position := attack.position
	var body_scale := attacker.body_shape.scale
	# 新语义：普通攻击未完成时锁向，几何镜像测试先明确完成此动作。
	var finished_attack := root.get_state(ATTACK) as BasicAttackState
	finished_attack.elapsed_frames = finished_attack.total_frames()
	attacker.set_facing(-1)
	attacker.publish_input_context()
	_check(is_equal_approx(attack.global_position.x - attacker.global_position.x, -offset), "Manager mirror reverses biased attack position")
	_check(attack.position == local_position and attacker.body_shape.scale == body_scale, "child boxes and world collision are not mirrored twice")
	_check(not attacker.sprite.flip_h and attacker.hit_state_manager.scale.x == -1, "sprite and hit subtree share left-facing intent")
	await _frames(3)
	_check(hurt in separated, "real separation is forwarded from box through pose to Manager")
	attacker.set_facing(1)
	attacker.publish_input_context()
	_check(is_equal_approx(attack.global_position.x - attacker.global_position.x, offset), "double facing change returns geometry without cumulative mirror")
	attacker.clear_hit_state()
	await _frames(2)
	_check(_all_disabled(attacker.hit_state_manager), "physical contact test leaves no active boxes after explicit clear")
	attacker.free()
	target.free()
