extends Node
## 使用实际默认转换资源，仅注入采样后的输入意图，不补写规则或条件。

const ATTACK := &"action/basic_attack/light_attack"
const NEUTRAL_PATHS: Array[StringName] = [
	&"neutral/idle", &"neutral/fwalk", &"neutral/bwalk", &"neutral/crouch",
]
var checks := 0
var failures := 0
var grounded_flag := true


func _enter_tree() -> void:
	# 专项测试注入采样后的意图；完整输入链另由 neutral 套件验证。
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


## 多次推进确认没有无意义退出重入，也没有无输入自动发动招式。
func _stays(actor: Fighter, expected: StringName, steps: int = 120) -> bool:
	var stable := true
	for i in steps:
		if actor.advance_commands():
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
	var root := actor.state_machine.get_root()
	_check(actor._selected_transitions.size() == 16, "default loadout selects all configured rules")
	for rule in actor._selected_transitions:
		_check(rule in actor.loadout.transition_library.transitions, "selected rule is an actual library resource: %s" % rule.transition_id)
		if not rule.move_id.is_empty():
			_check("grounded" in rule.prereqs, "default launch resource retains grounded prerequisite: %s" % rule.transition_id)
		elif rule.from_state == &"action":
			_check("active_leaf_done" in rule.prereqs, "default group return retains leaf-completion prerequisite")
		else:
			_check(rule.auto_advance and not rule.advance_conditions.is_empty(), "default neutral resource explicitly gates automatic advance: %s" % rule.transition_id)
	_intent(actor, 0.0)
	_check(_stays(actor, &"neutral/idle"), "no input keeps idle for 120 advances")

	var axes := [0.0, 1.0, -1.0, 0.0]
	for source in NEUTRAL_PATHS:
		for i in NEUTRAL_PATHS.size():
			var target := NEUTRAL_PATHS[i]
			root.goto(source)
			_intent(actor, axes[i], target == &"neutral/crouch")
			var advanced := actor.advance_commands()
			_check(root.get_active_states_info().path == target and advanced == (source != target), "actual resource selects %s -> %s" % [source, target])
			_check(_stays(actor, target), "held intent keeps %s without re-entry" % target)

	# 同时持有下蹲和水平方向时，不能在行走和下蹲之间抖动。
	for axis in [-1.0, 1.0]:
		root.goto(&"neutral/idle")
		_intent(actor, axis, true)
		_check(actor.advance_commands() and root.get_active_states_info().path == &"neutral/crouch", "crouch overrides horizontal intent %s" % axis)
		_check(_stays(actor, &"neutral/crouch"), "diagonal crouch remains stable")
		_intent(actor, axis)
		var target: StringName = &"neutral/fwalk" if axis > 0 else &"neutral/bwalk"
		_check(actor.advance_commands() and root.get_active_states_info().path == target, "releasing crouch resumes held horizontal direction")
		_intent(actor, 0.0)
		_check(actor.advance_commands() and _stays(actor, &"neutral/idle"), "releasing all input returns to stable idle")

	actor.set_facing(-1)
	_intent(actor, 1.0)
	_check(actor.advance_commands() and root.get_active_states_info().path == &"neutral/bwalk", "movement conditions remain relative to facing")
	_check(_stays(actor, &"neutral/bwalk"), "backwalk with reversed facing stays stable")
	actor.set_facing(1)
	_intent(actor, 0.0)
	_check(actor.advance_commands() and _stays(actor, &"neutral/idle"), "released reversed-facing input settles at idle")

	# 只控制物理接地结果，使用资源里真实的 grounded 前置条件。
	root.set_condition(&"grounded", func() -> bool: return grounded_flag)
	var move := actor.loadout.move_library.moves[0]
	var candidate := {"move": move, "created_frame": 0}
	for source in [ &"neutral/idle", &"neutral/fwalk", &"neutral/bwalk" ]:
		root.goto(source)
		grounded_flag = false
		_check(not actor._try_move(candidate) and root.get_active_states_info().path == source, "actual launch rule rejects airborne source %s" % source)
		grounded_flag = true
		_check(actor._try_move(candidate) and root.get_active_states_info().path == ATTACK, "actual launch rule accepts grounded source %s" % source)
		var attack := root.get_state(ATTACK) as BasicAttackState
		_check(not actor.advance_commands(), "actual return rule waits at attack startup")
		var waited := true
		for frame in move.total_frames() - 1:
			attack._physics_process_impl(1.0 / 60.0)
			if actor.advance_commands():
				waited = false
		_check(waited and root.get_active_states_info().path == ATTACK, "actual return rule waits through unfinished attack")
		attack._physics_process_impl(1.0 / 60.0)
		_check(actor.advance_commands() and root.get_active_states_info().path == &"neutral/idle", "actual group return executes after attack completion")
		_check(_stays(actor, &"neutral/idle"), "completed attack returns to stable idle without auto-repeat")
	root.goto(&"neutral/crouch")
	_check(not actor._try_move(candidate), "missing crouch launch edge remains forbidden")
	actor.free()
	_test_minimal_loadouts()
	_test_move_identity()
	_test_state_animation_config()
	print("TRANSITION RESOURCE TESTS: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)


## 未装配目标动作时，源意图结束仍须退回 idle，不能困在旧状态。
func _test_minimal_loadouts() -> void:
	var axes := [0.0, 1.0, -1.0, 0.0]
	for source in [&"neutral/fwalk", &"neutral/bwalk", &"neutral/crouch"]:
		var actor: Fighter = load("res://scenes/Fighter.tscn").instantiate()
		actor.loadout = actor.loadout.duplicate()
		actor.loadout.selected_state_paths = [&"neutral/idle", source]
		actor.loadout.selected_move_ids = []
		add_child(actor)
		actor.set_physics_process(false)
		actor.state_machine.set_physics_process(false)
		actor.fighter_input.set_physics_process(false)
		var root := actor.state_machine.get_root()
		for i in NEUTRAL_PATHS.size():
			var requested := NEUTRAL_PATHS[i]
			if requested == source:
				continue
			root.goto(source)
			_intent(actor, axes[i], requested == &"neutral/crouch")
			_check(actor.advance_commands() and root.get_active_states_info().path == &"neutral/idle", "minimal %s loadout falls back to idle for %s intent" % [source, requested])
			_check(_stays(actor, &"neutral/idle"), "minimal loadout fallback does not cycle")
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
	var root := actor.state_machine.get_root()
	root.set_condition(&"grounded", func() -> bool: return true)
	_check(actor.fighter_input._moves[0] == renamed, "loadout and input use numeric ID regardless of display rename")
	_check(actor._try_move({"move": renamed, "created_frame": 0}), "renaming move does not break actual numeric-ID launch rules")
	_check(root.get_active_states_info().path == ATTACK, "numeric ID does not replace the semantic state path")
	_check(renamed.command.buttons[0] == &"light_attack" and (root.get_state(ATTACK) as FighterState).state_definition.animation_key == &"light_attack", "input action and animation keys stay semantic rather than becoming IDs")
	actor.fighter_input.clear_history()
	actor.fighter_input._add_candidate(&"01010001", [1])
	_check(actor.fighter_input._candidates.size() == 1 and actor.fighter_input._candidates[0].move == renamed, "numeric StringName works as input candidate lookup key")

	var other := renamed.duplicate() as FighterMoveDefinition
	other.move_id = &"01010002"
	actor.loadout.move_library.moves.append(other)
	actor.loadout.selected_move_ids = [&"01010002"]
	var builder := FighterSMBuilder.new()
	var other_root := builder.build(actor, actor.loadout)
	_check(builder.selected_moves.size() == 1 and builder.selected_moves[0] == other, "same display name does not merge distinct numeric IDs")
	_check(other_root.has_state(ATTACK), "same-name move still resolves explicitly configured state dependency")
	var launch_count := 0
	for rule in builder.selected_transitions:
		if not rule.move_id.is_empty():
			launch_count += 1
	_check(launch_count == 0, "different numeric ID cannot reuse another move's launch permission merely by name")
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
			definition.state_script = load("res://scripts/states/fighterstates/neutral/idle_state.gd")
	add_child(actor)
	actor.set_physics_process(false)
	actor.state_machine.set_physics_process(false)
	actor.fighter_input.set_physics_process(false)
	return actor


## 覆盖初始化、普通转换、external 攻击、重入及空动画键，不实现动画映射系统。
func _test_state_animation_config() -> void:
	var actor := _animation_actor()
	var root := actor.state_machine.get_root()
	_check(actor.sprite.animation == &"configured_idle", "initial entry reads animation from bound state definition")
	_check(actor._resolve_animation_key(&"idle") == &"idle", "reserved custom animation resolver is identity-only")
	for definition in actor.loadout.state_library.states:
		var path := StringName(String(definition.group_path) + "/" + String(definition.state_name))
		var state := root.get_state(path) as FighterState
		_check(state.state_definition == definition, "builder binds exact state definition: %s" % path)
	var axes := [0.0, 1.0, -1.0, 0.0]
	for i in NEUTRAL_PATHS.size():
		var target := NEUTRAL_PATHS[i]
		_intent(actor, axes[i], target == &"neutral/crouch")
		actor.advance_commands()
		_check(root.get_active_states_info().path == target and actor.sprite.animation == StringName("configured_" + String(target).get_file()), "neutral state uses configured animation rather than script literal: %s" % target)
		_check(_stays(actor, target), "configurable animation does not change stable neutral behavior")
	root.goto(&"neutral/idle")
	_intent(actor, 0.0)
	root.set_condition(&"grounded", func() -> bool: return true)
	var move := actor.loadout.move_library.moves[0]
	var has_move_animation := false
	for property in move.get_property_list():
		if property.name == "animation_key":
			has_move_animation = true
	_check(not has_move_animation, "move definition no longer duplicates state animation configuration")
	_check(actor._try_move({"move": move, "created_frame": 0}) and actor.sprite.animation == &"configured_light_attack", "external attack entry uses state animation while retaining move timing data")
	var attack := root.get_state(ATTACK) as BasicAttackState
	_check(attack.move == move and attack.elapsed_frames == 0, "animation migration preserves per-execution move and frame counter")
	root.goto(&"neutral/idle")
	_check(actor.sprite.animation == &"configured_idle", "return entry restores configured neutral animation")
	_check(actor._try_move({"move": move, "created_frame": 0}) and actor.sprite.animation == &"configured_light_attack", "repeated attack entry keeps configured state animation")
	var idle := root.get_state(&"neutral/idle") as FighterState
	# 运行期不改共享定义；下面替换本测试角色的私有副本，只用于验证播放协议。
	idle.state_definition.animation_key = &""
	root.goto(&"neutral/idle")
	_check(actor.sprite.animation == &"configured_light_attack", "empty animation key skips playback instead of sending invalid animation")
	var loadout := load("res://resource/characters/demo_loadout.tres") as FighterLoadout
	_check(loadout.state_library.states[0].animation_key == &"idle", "per-role test configuration never mutates shared state library")
	actor.free()

	var reused := _animation_actor(true)
	var reused_root := reused.state_machine.get_root()
	var reused_idle := reused_root.get_state(&"neutral/idle") as FighterState
	var reused_walk := reused_root.get_state(&"neutral/fwalk") as FighterState
	_check(reused_idle.get_script() == reused_walk.get_script(), "different states can reuse the same execution script")
	_check(reused_idle != reused_walk and reused_idle.state_definition != reused_walk.state_definition, "shared script retains separate instances and bound definitions")
	_check(reused.sprite.animation == &"configured_idle", "shared script initially uses idle definition animation")
	reused_root.goto(&"neutral/fwalk")
	_check(reused.sprite.animation == &"configured_fwalk", "shared script changes animation according to destination definition")
	reused.free()
