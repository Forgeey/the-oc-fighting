extends Node
const InputTest = preload("res://tests/input/input_test_support.gd")
## 使用实际默认转换资源，仅注入采样后的输入意图，不补写规则或条件。

const ATTACK := &"light_attack"
const NEUTRAL_PATHS: Array[StringName] = [
	&"idle", &"fwalk", &"bwalk", &"crouch",
]
var checks := 0
var failures := 0
var grounded_flag := true


func _enter_tree() -> void:
	# 专项测试注入采样后的意图；完整输入链另由 movement 套件验证。
	FrayInput.set_physics_process(false)


func _ready() -> void:
	_run.call_deferred()


func _check(value: bool, message: String) -> void:
	checks += 1
	if value:
		print("PASS: ", message)
	else:
		failures += 1
		print("FAIL: ", message)


## 注入已采样意图，继续通过真实 FighterInput 条件方法判断转换。
func _intent(actor: Fighter, axis: float, crouch: bool = false) -> void:
	actor.fighter_input._horizontal_axis = axis
	actor.fighter_input._crouch_pressed = crouch
	actor.fighter_input._forward_pressed = axis * actor.fighter_input.facing_dir > 0.1
	actor.fighter_input._backward_pressed = axis * actor.fighter_input.facing_dir < -0.1


## 多次推进确认没有无意义退出重入，也没有无输入自动发动招式。
func _stays(actor: Fighter, expected: StringName, steps: int = 120) -> bool:
	var stable := true
	for i in steps:
		if InputTest.ordinary(actor):
			stable = false
		if actor.state_machine.get_root().get_active_states_info().path != expected:
			stable = false
	return stable


func _run() -> void:
	var actor: Fighter = load("res://scenes/Fighter.tscn").instantiate()
	# 不复制或改写 Loadout / TransitionLibrary，也不覆盖移动条件绑定。
	add_child(actor)
	actor.set_physics_process(false)
	actor.state_machine.set_physics_process(false)
	actor.fighter_input.set_physics_process(false)
	actor.advancer.set_physics_process(false)
	var root := actor.state_machine.get_root()
	_check(actor._selected_transitions.size() == 16, "default loadout selects all configured rules")
	for rule in actor._selected_transitions:
		_check(rule in actor.loadout.transition_library.transitions, "selected rule is an actual library resource: %s" % rule.transition_id)
		if not rule.command.is_empty():
			_check("grounded" in rule.prereqs, "default launch resource retains grounded prerequisite: %s" % rule.transition_id)
		elif rule.from_state == ATTACK:
			_check(rule.prereqs.is_empty() and rule.switch_mode == FrayStateMachineTransition.SwitchMode.AT_END, "natural return delegates completion to plugin AT_END without duplicate condition")
		else:
			_check(rule.auto_advance and not rule.advance_conditions.is_empty(), "default movement resource explicitly gates automatic advance: %s" % rule.transition_id)
	_intent(actor, 0.0)
	_check(_stays(actor, &"idle"), "no input keeps idle for 120 advances")

	var axes := [0.0, 1.0, -1.0, 0.0]
	for source in NEUTRAL_PATHS:
		for i in NEUTRAL_PATHS.size():
			var target := NEUTRAL_PATHS[i]
			root.goto(source)
			_intent(actor, axes[i], target == &"crouch")
			var advanced := InputTest.ordinary(actor)
			_check(root.get_active_states_info().path == target and advanced == (source != target), "actual resource selects %s -> %s" % [source, target])
			_check(_stays(actor, target), "held intent keeps %s without re-entry" % target)

	# 同时持有下蹲和水平方向时，不能在行走和下蹲之间抖动。
	for axis in [-1.0, 1.0]:
		root.goto(&"idle")
		_intent(actor, axis, true)
		_check(InputTest.ordinary(actor) and root.get_active_states_info().path == &"crouch", "crouch overrides horizontal intent %s" % axis)
		_check(_stays(actor, &"crouch"), "diagonal crouch remains stable")
		_intent(actor, axis)
		var target: StringName = &"fwalk" if axis > 0 else &"bwalk"
		_check(InputTest.ordinary(actor) and root.get_active_states_info().path == target, "releasing crouch resumes held horizontal direction")
		_intent(actor, 0.0)
		_check(InputTest.ordinary(actor) and _stays(actor, &"idle"), "releasing all input returns to stable idle")

	InputTest.turn(actor, -1)
	_intent(actor, 1.0)
	_check(InputTest.ordinary(actor) and root.get_active_states_info().path == &"bwalk", "movement conditions remain relative to facing")
	_check(_stays(actor, &"bwalk"), "backwalk with reversed facing stays stable")
	InputTest.turn(actor, 1)
	_intent(actor, 0.0)
	_check(InputTest.ordinary(actor) and _stays(actor, &"idle"), "released reversed-facing input settles at idle")

	# 只控制物理接地结果，使用资源里真实的 grounded 前置条件。
	root.set_condition(&"grounded", func() -> bool: return grounded_flag)
	var move := actor.loadout.move_library.moves[0]
	var candidate := move
	for source in [ &"idle", &"fwalk", &"bwalk" ]:
		root.goto(source)
		grounded_flag = false
		_check(not InputTest.try_move(actor, candidate) and root.get_active_states_info().path == source, "actual launch rule rejects airborne source %s" % source)
		grounded_flag = true
		_check(InputTest.try_move(actor, candidate) and root.get_active_states_info().path == ATTACK, "actual launch rule accepts grounded source %s" % source)
		var attack := root.get_state(ATTACK) as BasicAttackState
		_check(not InputTest.ordinary(actor), "actual return rule waits at attack startup")
		var waited := true
		for frame in attack.total_frames() - 1:
			attack._physics_process_impl(1.0 / 60.0)
			if InputTest.ordinary(actor):
				waited = false
		_check(waited and root.get_active_states_info().path == ATTACK, "actual return rule waits through unfinished attack")
		attack._physics_process_impl(1.0 / 60.0)
		_check(InputTest.ordinary(actor) and root.get_active_states_info().path == &"idle", "actual group return executes after attack completion")
		_check(_stays(actor, &"idle"), "completed attack returns to stable idle without auto-repeat")
	root.goto(&"crouch")
	_check(not InputTest.try_move(actor, candidate), "missing crouch launch edge remains forbidden")
	actor.free()
	_test_minimal_loadouts()
	_test_move_identity()
	_test_generic_input_conditions()
	_test_state_animation_config()
	print("TRANSITION RESOURCE TESTS: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)


## 未装配目标动作时，源意图结束仍须退回 idle，不能困在旧状态。
func _test_minimal_loadouts() -> void:
	var axes := [0.0, 1.0, -1.0, 0.0]
	for source in [&"fwalk", &"bwalk", &"crouch"]:
		var actor: Fighter = load("res://scenes/Fighter.tscn").instantiate()
		actor.loadout = actor.loadout.duplicate()
		actor.loadout.selected_state_names = [&"idle", source]
		actor.loadout.selected_move_ids = []
		add_child(actor)
		actor.set_physics_process(false)
		actor.state_machine.set_physics_process(false)
		actor.fighter_input.set_physics_process(false)
		actor.advancer.set_physics_process(false)
		var root := actor.state_machine.get_root()
		for i in NEUTRAL_PATHS.size():
			var requested := NEUTRAL_PATHS[i]
			if requested == source:
				continue
			root.goto(source)
			_intent(actor, axes[i], requested == &"crouch")
			_check(InputTest.ordinary(actor) and root.get_active_states_info().path == &"idle", "minimal %s loadout falls back to idle for %s intent" % [source, requested])
			_check(_stays(actor, &"idle"), "minimal loadout fallback does not cycle")
		actor.free()


## 验证数字身份与显示名称分离，不因改名或同名招式误选发动规则。
func _test_move_identity() -> void:
	var actor: Fighter = load("res://scenes/Fighter.tscn").instantiate()
	actor.loadout = actor.loadout.duplicate()
	actor.loadout.move_library = actor.loadout.move_library.duplicate()
	actor.loadout.move_library.moves = actor.loadout.move_library.moves.duplicate()
	var original := actor.loadout.move_library.moves[0]
	_check(original.move_id == &"01010001" and original.move_name == "轻攻击", "default move has numeric ID and separate readable name")
	_check(String(original.move_id).length() == 8 and String(original.move_id).is_valid_int(), "numeric ID retains eight digits including leading zero")
	var renamed := original.duplicate() as FighterMoveDefinition
	renamed.move_name = "改名后的轻攻击"
	actor.loadout.move_library.moves[0] = renamed
	add_child(actor)
	actor.set_physics_process(false)
	actor.state_machine.set_physics_process(false)
	actor.fighter_input.set_physics_process(false)
	actor.advancer.set_physics_process(false)
	var root := actor.state_machine.get_root()
	root.set_condition(&"grounded", func() -> bool: return true)
	_check(actor.fighter_input._commands.has(renamed.command), "loadout and input use numeric ID regardless of display rename")
	_check(InputTest.try_move(actor, renamed), "renaming move does not break actual numeric-ID launch rules")
	_check(root.get_active_states_info().path == ATTACK, "numeric ID does not replace the semantic state path")
	_check(renamed.command.buttons[0] == &"light_attack" and (root.get_state(ATTACK) as FighterState).state_definition.animation_key == &"light_attack", "input action and animation keys stay semantic rather than becoming IDs")
	actor.fighter_input.clear_history()
	actor.fighter_input._enqueue(renamed.command, [1])
	_check(actor.advancer.get_buffer().size() == 1 and actor.advancer.get_buffer()[0].sequence_name == renamed.command.command_id, "numeric StringName works as native buffered command lookup key")

	var other := renamed.duplicate() as FighterMoveDefinition
	other.move_id = &"01010002"
	actor.loadout.move_library.moves.append(other)
	actor.loadout.selected_move_ids = [&"01010002"]
	var builder := FighterSMBuilder.new()
	var selection := actor.loadout.resolve_selection()
	var other_root := builder.build(actor, actor.loadout, selection)
	_check(selection.moves.size() == 1 and selection.moves[0] == other, "same display name does not merge distinct numeric IDs")
	_check(other_root.has_state(ATTACK), "same-name move still resolves explicitly configured state dependency")
	var launch_count := 0
	for rule in builder.selected_transitions:
		if not rule.command.is_empty():
			launch_count += 1
	_check(launch_count == 3, "same logical command retains state-driven launch edges regardless of move identity")
	actor.free()


## 通用条件名绑定，不需要 Fighter/FighterInput 为每种意图提供同名方法。
func _test_generic_input_conditions() -> void:
	var actor: Fighter = load("res://scenes/Fighter.tscn").instantiate()
	add_child(actor)
	actor.set_physics_process(false)
	actor.state_machine.set_physics_process(false)
	actor.fighter_input.set_physics_process(false)
	actor.advancer.set_physics_process(false)
	var root := actor.state_machine.get_root()
	FighterSMBuilder.new()._bind_conditions(root,
		PackedStringArray(["inputed_idle", "inputed_fwalk", "inputed_bwalk", "inputed_crouch"]),
		actor.loadout.transition_library, actor)
	_check(not actor.has_method("inputed_fwalk") and not actor.fighter_input.has_method("inputed_fwalk"), "per-action condition functions are no longer required")
	_check(not actor.loadout.transition_library.condition_methods.has(&"inputed_idle"), "new intent conditions require no per-action method mapping")
	_intent(actor, 0.0)
	_check(root.is_condition_true("inputed_idle"), "inputed_idle binds the generic query without a dedicated method")
	_intent(actor, 1.0)
	_check(root.is_condition_true("inputed_fwalk") and root.is_condition_true("!inputed_bwalk"), "generic conditions preserve direction and negation semantics")
	InputTest.turn(actor, -1)
	_intent(actor, 1.0)
	_check(root.is_condition_true("inputed_bwalk") and not root.is_condition_true("inputed_fwalk"), "generic direction is relative to current facing")
	_check(actor.fighter_input.get_movement_axis(&"bwalk") == 1.0, "generic axis keeps world-space sign")
	_intent(actor, 1.0, true)
	_check(root.is_condition_true("inputed_crouch") and not root.is_condition_true("inputed_bwalk"), "crouch remains higher priority than walking")
	_check(actor.fighter_input.get_movement_axis(&"crouch") == 0.0, "crouch does not submit a horizontal movement axis")
	actor.free()


## 只在测试角色复制定义和帧资源，确认动画配置无需改状态脚本。
func _animation_actor(reuse_idle_script: bool = false) -> Fighter:
	var actor: Fighter = load("res://scenes/Fighter.tscn").instantiate()
	actor.loadout = actor.loadout.duplicate()
	actor.loadout.state_library = actor.loadout.state_library.duplicate()
	actor.loadout.state_library.states = actor.loadout.state_library.states.duplicate()
	var sprite := actor.get_node("AnimatedSprite2D") as AnimatedSprite2D
	sprite.sprite_frames = sprite.sprite_frames.duplicate()
	for i in actor.loadout.state_library.states.size():
		var definition := actor.loadout.state_library.states[i].duplicate() as FighterStateDefinition
		actor.loadout.state_library.states[i] = definition
		var original := definition.animation_key
		var alias := StringName("configured_" + String(original))
		sprite.sprite_frames.add_animation(alias)
		sprite.sprite_frames.set_animation_speed(alias, sprite.sprite_frames.get_animation_speed(original))
		sprite.sprite_frames.set_animation_loop(alias, sprite.sprite_frames.get_animation_loop(original))
		for frame in sprite.sprite_frames.get_frame_count(original):
			sprite.sprite_frames.add_frame(alias, sprite.sprite_frames.get_frame_texture(original, frame), sprite.sprite_frames.get_frame_duration(original, frame))
		definition.animation_key = alias
		if reuse_idle_script and definition.state_name == &"fwalk":
			definition.state_script = load("res://scripts/states/fighterstates/idle_state.gd")
	# 招式仅保存 ID，自动解析到该角色状态库的私有定义，无需重绑资源引用。
	add_child(actor)
	actor.set_physics_process(false)
	actor.state_machine.set_physics_process(false)
	actor.fighter_input.set_physics_process(false)
	actor.advancer.set_physics_process(false)
	return actor


## 覆盖初始进入、普通转换、攻击和重入时基类统一播放状态动画。
func _test_state_animation_config() -> void:
	var actor := _animation_actor()
	var root := actor.state_machine.get_root()
	_check(actor.sprite.animation == &"configured_idle", "initial entry reads animation from bound state definition")
	_check(actor._resolve_animation_key(&"idle") == &"idle", "reserved custom animation resolver is identity-only")
	for definition in actor.loadout.state_library.states:
		var path := definition.state_name
		var state := root.get_state(path) as FighterState
		_check(state.state_definition == definition, "builder binds exact state definition: %s" % path)
	var axes := [0.0, 1.0, -1.0, 0.0]
	for i in NEUTRAL_PATHS.size():
		var target := NEUTRAL_PATHS[i]
		_intent(actor, axes[i], target == &"crouch")
		InputTest.ordinary(actor)
		_check(root.get_active_states_info().path == target and actor.sprite.animation == StringName("configured_" + String(target).get_file()), "movement state uses configured animation rather than script literal: %s" % target)
		_check(_stays(actor, target), "configurable animation does not change stable movement behavior")
	root.goto(&"idle")
	_intent(actor, 0.0)
	root.set_condition(&"grounded", func() -> bool: return true)
	var move := actor.loadout.move_library.moves[0]
	var has_move_animation := false
	for property in move.get_property_list():
		if property.name == "animation_key":
			has_move_animation = true
	_check(not has_move_animation, "move definition no longer duplicates state animation configuration")
	_check(InputTest.try_move(actor, move) and actor.sprite.animation == &"configured_light_attack", "external attack entry uses state animation while retaining move timing data")
	var attack := root.get_state(ATTACK) as BasicAttackState
	_check(not attack.attack_attributes.is_empty() and attack.elapsed_frames == 0, "animation migration preserves Attribute timing and per-execution frame counter")
	root.goto(&"idle")
	_check(actor.sprite.animation == &"configured_idle", "return entry restores configured movement animation")
	_check(InputTest.try_move(actor, move) and actor.sprite.animation == &"configured_light_attack", "repeated attack entry keeps configured state animation")
	var idle := root.get_state(&"idle") as FighterState
	# 运行期不改共享定义；下面替换本测试角色的私有副本，只用于验证播放协议。
	idle.state_definition.animation_key = &"configured_bwalk"
	root.goto(&"idle")
	_check(actor.sprite.animation == &"configured_bwalk", "every entry directly plays the configured state animation")
	var loadout := load("res://resource/characters/demo_loadout.tres") as FighterLoadout
	_check(loadout.state_library.states[0].animation_key == &"idle", "per-role test configuration never mutates shared state library")
	actor.free()

	var reused := _animation_actor(true)
	var reused_root := reused.state_machine.get_root()
	var reused_idle := reused_root.get_state(&"idle") as FighterState
	var reused_walk := reused_root.get_state(&"fwalk") as FighterState
	_check(reused_idle.get_script() == reused_walk.get_script(), "different states can reuse the same execution script")
	_check(reused_idle != reused_walk and reused_idle.state_definition != reused_walk.state_definition, "shared script retains separate instances and bound definitions")
	_check(reused.sprite.animation == &"configured_idle", "shared script initially uses idle definition animation")
	reused_root.goto(&"fwalk")
	_check(reused.sprite.animation == &"configured_fwalk", "shared script changes animation according to destination definition")
	reused.free()
