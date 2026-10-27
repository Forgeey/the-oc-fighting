extends Node
## 验证实际资源动态装配、生命周期和物理接触，不补写转换条件或实现战斗结果。

const ATTACK := &"action/basic_attack/light_attack"
const NEUTRAL: Array[StringName] = [&"neutral/idle", &"neutral/fwalk", &"neutral/bwalk", &"neutral/crouch"]
var checks := 0
var failures := 0


func _enter_tree() -> void:
	# 本套件直接测试姿态，真实输入与自动转换仍由独立 neutral 套件验证。
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
	result.selected_state_paths = paths
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
			audit["complete_before_ready"] = child.get_child_count() == actor._hit_state_by_definition.size()
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
	var expected := actor._hit_state_by_definition[definition]
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
	_test_independence_and_nullable()
	await _test_contact_and_mirroring()
	print("HIT ASSEMBLY TESTS: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)


## 独立 Builder 不读取转换库，依赖范围与状态机的实际叶子一致。
func _test_builder_selections() -> void:
	for loadout in [
		_loadout([&"neutral/idle"]),
		_loadout(NEUTRAL.duplicate()),
		_loadout([&"neutral/idle"], [&"01010001"]),
		_loadout(NEUTRAL.duplicate(), [&"01010001"]),
		_loadout([&"neutral/idle", ATTACK]),
	]:
		var hit_builder := FighterHitStateBuilder.new()
		var without_transitions := loadout.duplicate() as FighterLoadout
		without_transitions.transition_library = null
		var manager := hit_builder.build(without_transitions)
		_check(not manager.is_inside_tree() and not manager.is_node_ready(), "builder returns off-tree manager")
		_check(_all_disabled(manager), "all constructed poses and boxes start fully disabled")
		var fighter := Fighter.new()
		var root := FighterSMBuilder.new().build(fighter, loadout)
		var expected: Dictionary = {}
		for state in loadout.state_library.states:
			var path := StringName(String(state.group_path) + "/" + String(state.state_name))
			if root.has_state(path) and state.hit_state_definition != null:
				expected[state.hit_state_definition] = true
		_check(manager.get_child_count() == expected.size() and hit_builder.hit_state_by_definition.size() == expected.size(), "hit selection equals actual assembled leaf dependencies")
		for definition in expected:
			_check(hit_builder.hit_state_by_definition.has(definition), "every assembled state dependency has its pose")
		manager.free()
		fighter.free()

	var duplicated := _loadout([&"neutral/idle", &"neutral/idle"], [&"01010001", &"01010002"])
	duplicated.move_library = duplicated.move_library.duplicate()
	duplicated.move_library.moves = duplicated.move_library.moves.duplicate()
	var other := duplicated.move_library.moves[0].duplicate() as FighterMoveDefinition
	other.move_id = &"01010002"
	other.required_state_paths = [ATTACK, ATTACK, &"neutral/idle"]
	duplicated.move_library.moves.append(other)
	var builder := FighterHitStateBuilder.new()
	var manager := builder.build(duplicated)
	_check(manager.get_child_count() == 2, "repeated paths and multiple moves sharing states do not duplicate poses")
	manager.free()

	var same_name := _loadout([&"neutral/idle", &"reaction/idle", &"root_leaf"])
	same_name.state_library = same_name.state_library.duplicate()
	same_name.state_library.states = same_name.state_library.states.duplicate()
	var state := same_name.state_library.states[0].duplicate() as FighterStateDefinition
	state.group_path = &"reaction"
	state.hit_state_definition = state.hit_state_definition.duplicate()
	same_name.state_library.states.append(state)
	var root_state := state.duplicate() as FighterStateDefinition
	root_state.group_path = &""
	root_state.state_name = &"root_leaf"
	root_state.hit_state_definition = state.hit_state_definition.duplicate()
	same_name.state_library.states.append(root_state)
	manager = builder.build(same_name)
	_check(manager.get_child_count() == 3, "full paths distinguish same local names and root-level states")
	_check(builder.hit_state_by_definition.size() == 3, "different definitions sharing one scene are not merged")
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
	_check(actor.hit_state_manager.get_child_count() == 3 and actor._hit_state_by_definition.size() == 3, "default loadout assembles only three unique poses")
	for pose: FrayHitState2D in actor.hit_state_manager.get_children():
		for box in pose.get_hitboxes():
			_check(box.source == actor, "post-mount source propagates to every box")
			_check((box.get_child(0) as CollisionShape2D).debug_color == box.attribute.get_color(), "runtime debug color follows hitbox attribute")
	var root := actor.state_machine.get_root()
	var standing := _definition(actor, &"neutral/idle")
	_expect_pose(actor, standing, "initial idle")
	for path in NEUTRAL:
		root.goto(path)
		_expect_pose(actor, _definition(actor, path), "enter " + String(path))
	_check(_definition(actor, &"neutral/fwalk") == standing and _definition(actor, &"neutral/bwalk") == standing, "three neutral behaviors share one standing definition")
	root.goto(&"neutral/idle")
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
	for i in move.total_frames():
		attack._physics_process_impl(1.0 / 60.0)
	_check(not attack_box.monitoring, "basic attack does not automatically open Attackbox at any phase in this scope")
	root.goto(&"neutral/idle")
	_expect_pose(actor, standing, "interrupted attack returns to standing")
	actor.clear_hit_state()
	_check(actor._current_hit_state == null and _all_disabled(actor.hit_state_manager), "clear zeroes masks and truly stops every pose")
	actor.clear_hit_state()
	_check(_all_disabled(actor.hit_state_manager), "clear is safe when already empty")
	actor.select_hit_state(standing)
	actor.set_hit_state_mask(0)
	_check(actor._current_hit_state == null and _all_disabled(actor.hit_state_manager), "zero mask uses complete cleanup path")
	actor.select_hit_state(standing)
	_check(actor._current_hit_state.is_active(), "same previously selected manager name can be reactivated after cleanup")
	actor._current_hit_state.set_block_signals(true)
	actor.clear_hit_state()
	_check(actor._hit_state_by_definition[standing].is_blocking_signals(), "cleanup preserves an existing signal-block state")
	actor._hit_state_by_definition[standing].set_block_signals(false)
	actor.select_hit_state(null)
	_check(_all_disabled(actor.hit_state_manager), "null selection leaves no stale pose")
	actor.free()


## 验证单角色选择范围、跨角色形状独立，以及空引用和零默认掩码。
func _test_independence_and_nullable() -> void:
	var a := _spawn()
	var b := _spawn()
	var definition := _definition(a, &"neutral/idle")
	_check(definition == _definition(b, &"neutral/idle"), "fighters share immutable hit definitions")
	_check(a.hit_state_manager != b.hit_state_manager and a._current_hit_state != b._current_hit_state, "fighters own separate manager and pose nodes")
	var shape_a := (a._current_hit_state.get_node("Hurtbox/CollisionShape2D") as CollisionShape2D).shape as RectangleShape2D
	var shape_b := (b._current_hit_state.get_node("Hurtbox/CollisionShape2D") as CollisionShape2D).shape as RectangleShape2D
	var size_b := shape_b.size
	shape_a.size = Vector2(1, 2)
	_check(shape_a != shape_b and shape_b.size == size_b, "changing one fighter's geometry cannot affect another")
	a.clear_hit_state()
	_check(b._current_hit_state != null and b._current_hit_state.active_hitboxes == 3, "one fighter clearing pose cannot clear another")
	a.free()
	b.free()
	var minimal := _spawn(_loadout([&"neutral/idle"]))
	_check(minimal.hit_state_manager.get_child_count() == 1, "idle-only fighter only has standing pose")
	minimal.free()
	var neutral := _spawn(_loadout(NEUTRAL.duplicate()))
	_check(neutral.hit_state_manager.get_child_count() == 2, "unequipped attack has no attack pose")
	neutral.free()
	var from_move := _spawn(_loadout([&"neutral/idle"], [&"01010001"]))
	_check(from_move.hit_state_manager.get_child_count() == 2 and from_move._hit_state_by_definition.has(_definition(from_move, ATTACK)), "move-only state dependency assembles attack pose")
	from_move.free()
	var optional := _loadout(NEUTRAL.duplicate())
	optional.state_library = optional.state_library.duplicate()
	optional.state_library.states = optional.state_library.states.duplicate()
	for i in optional.state_library.states.size():
		var state := optional.state_library.states[i].duplicate() as FighterStateDefinition
		optional.state_library.states[i] = state
		if state.state_name == &"fwalk":
			state.hit_state_definition = null
		elif state.state_name == &"crouch":
			state.hit_state_definition = state.hit_state_definition.duplicate()
			state.hit_state_definition.default_active_hitboxes = 0
	var actor := _spawn(optional)
	var root := actor.state_machine.get_root()
	root.goto(&"neutral/fwalk")
	_check(actor._current_hit_state == null and _all_disabled(actor.hit_state_manager), "entering state with no hit definition clears previous pose")
	root.goto(&"neutral/idle")
	root.goto(&"neutral/crouch")
	_check(actor._current_hit_state == null and _all_disabled(actor.hit_state_manager), "zero default mask is fully inactive rather than visually-only disabled")
	actor.free()

	var no_pose := _loadout([&"neutral/idle"])
	no_pose.state_library = no_pose.state_library.duplicate()
	no_pose.state_library.states = no_pose.state_library.states.duplicate()
	no_pose.state_library.states[0] = no_pose.state_library.states[0].duplicate() as FighterStateDefinition
	no_pose.state_library.states[0].hit_state_definition = null
	actor = _spawn(no_pose)
	_check(actor.hit_state_manager.is_node_ready() and actor.hit_state_manager.get_child_count() == 0, "empty optional pose set still mounts a ready manager")
	_check(actor._current_hit_state == null and _all_disabled(actor.hit_state_manager), "initial state without a pose has no phantom activation")
	actor.free()


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
	attacker.set_facing(-1)
	_check(is_equal_approx(attack.global_position.x - attacker.global_position.x, -offset), "Manager mirror reverses biased attack position")
	_check(attack.position == local_position and attacker.body_shape.scale == body_scale, "child boxes and world collision are not mirrored twice")
	_check(not attacker.sprite.flip_h and attacker.hit_state_manager.scale.x == -1, "sprite and hit subtree share left-facing intent")
	await _frames(3)
	_check(hurt in separated, "real separation is forwarded from box through pose to Manager")
	attacker.set_facing(1)
	_check(is_equal_approx(attack.global_position.x - attacker.global_position.x, offset), "double facing change returns geometry without cumulative mirror")
	attacker.clear_hit_state()
	await _frames(2)
	_check(_all_disabled(attacker.hit_state_manager), "physical contact test leaves no active boxes after explicit clear")
	attacker.free()
	target.free()
