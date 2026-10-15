class_name DemoFighter
extends CharacterBody2D

## Demo 角色的组合根节点；Fray 负责输入、状态机和命中框机制，Demo 组件仅负责组装与表现。
signal health_changed(fighter: DemoFighter, health: int, max_health: int)
signal knocked_out(fighter: DemoFighter)
signal attack_connected(attacker: DemoFighter, defender: DemoFighter, attack: FrayAttackAttribute, blocked: bool)
signal combo_changed(attacker: DemoFighter, defender: DemoFighter, hits: int, total_damage: int)
signal combo_ended(attacker: DemoFighter, defender: DemoFighter, hits: int, total_damage: int)
## 为未来投技与拆投流程保留的接口；当前招式不使用投技类型。
signal throw_contact_requested(attacker: DemoFighter, defender: DemoFighter, attack: FrayAttackAttribute)

@export var fighter_name := "Fighter"
@export var input_prefix := "p1"
@export var is_player := true
@export var ai_enabled := true
@export var body_color: Color = Color(0.25, 0.55, 1.0)
@export var sprite_modulate: Color = Color.WHITE
@export var environment: DemoFighterEnvironment = preload("res://resources/environment/default_fighter_environment.tres")
@export var move_loadout: DemoFighterLoadout = preload("res://resources/fighters/default_fighter_loadout.tres")
## 由角色场景直接配置的投射物场景，避免在角色脚本中硬编码场景预加载。
@export var projectile_scene: PackedScene

const STATE_TAG_ATTACK := &"attack"
const STATE_TAG_NEUTRAL := &"neutral"
const STATE_TAG_KO := &"ko"

var max_health := 100
var health := 100
var opponent: DemoFighter
var facing := 1


var state_machine: FrayStateMachine
var input_advancer: FrayBufferedInputAdvancer
var controller: FrayController
var animation_player: AnimationPlayer
var facing_root: Node2D
var sprite: Sprite2D
var hurt_manager: FrayHitStateManager2D
var attack_manager: FrayHitStateManager2D
var pushbox: DemoFighterPushbox
var attack_module: DemoFighterAttackModule
var movement: DemoFighterMovement
var virtual_ai: DemoFighterVirtualAI
var hitstop_remaining_frames := 0

var input_setup: DemoFighterInputSetup
var combat_resolver: DemoFighterCombatResolver
var combo_input: DemoFighterComboInput
var pending_knockdown: Dictionary = {}
var knockdown_tech_available := false
var knockdown_is_hard := false


## 节点就绪时完成运行时初始化。
func _ready() -> void:
	health = max_health
	add_to_group("fighters")
	_setup_scene_nodes()

	attack_module = DemoFighterAttackModule.new()
	attack_module.setup(self, hurt_manager, attack_manager, move_loadout)

	input_setup = DemoFighterInputSetup.new()
	input_setup.setup(self)
	input_setup.setup_inputs()
	_setup_components()

	combat_resolver = DemoFighterCombatResolver.new()
	combat_resolver.setup(self)
	combo_input = DemoFighterComboInput.new()
	combo_input.setup(self, input_advancer)

	DemoFighterStateMachineBuilder.configure(self, state_machine, attack_module, move_loadout)
	_sync_input_advancer_pause()
	health_changed.emit(self, health, max_health)


## 节点退出场景树时释放运行时资源。
func _exit_tree() -> void:
	if not is_player:
		virtual_ai.dispose()


## 每个物理帧更新角色逻辑。
func _physics_process(delta: float) -> void:
	if _is_hitstop_active():
		_sync_hitstop_pause()
		_advance_hitstop()
		return
	_sync_hitstop_pause()
	if not is_player:
		virtual_ai.update(delta)
	_update_facing()
	_sync_input_advancer_pause()


## 接收并处理命中。
func receive_hit(attacker: DemoFighter, attack: FrayAttackAttribute) -> bool:
	return combat_resolver.receive_hit(attacker, attack)


## 应用停帧并立即同步 Fray 状态机和输入缓冲的暂停状态。
func apply_hitstop(frames: int) -> void:
	hitstop_remaining_frames = maxi(hitstop_remaining_frames, maxi(0, frames))
	_sync_hitstop_pause()


## 判断角色当前是否处于停帧。
func _is_hitstop_active() -> bool:
	return hitstop_remaining_frames > 0


## 推进一帧角色自身的停帧计数。
func _advance_hitstop() -> void:
	hitstop_remaining_frames = maxi(0, hitstop_remaining_frames - 1)


## 根据停帧计数同步 Fray 状态机和输入缓冲的暂停状态。
func _sync_hitstop_pause() -> void:
	state_machine.active = not _is_hitstop_active()
	_sync_input_advancer_pause()


## 判断是否位于右侧一侧。
func is_on_right_side(_device: int = 0) -> bool:
	return global_position.x > opponent.global_position.x


## 判断是否处于中立状态。
func is_in_neutral_state() -> bool:
	return has_current_state_tag(STATE_TAG_NEUTRAL)


## 返回 Fray 状态机的当前状态。
func get_current_state() -> StringName:
	return state_machine.get_current_state_name()


## 返回当前正在执行的攻击标识。
func get_current_attack() -> StringName:
	var state := get_current_state()
	return state if has_current_state_tag(STATE_TAG_ATTACK) and attack_module.has_move(state) else &""


## 判断是否存在招式取消目标。
func has_move_cancel_targets(move_id: StringName) -> bool:
	return not move_loadout.get_cancel_target_ids(move_id).is_empty()


## 判断当前 Fray 状态是否包含指定标签。
func has_current_state_tag(tag: StringName) -> bool:
	var state := get_current_state()
	return state != &"" and state_machine.get_root().get_state_tags(state).has(String(tag))


## 激活指定姿态对应的受击框。
func set_hurt_state(state_name: StringName = &"Stand") -> void:
	attack_module.set_hurt_state(state_name)
	pushbox.set_pose_profile(state_name)


## 清空已命中目标并关闭全部攻击框。
func clear_attack_state() -> void:
	attack_module.clear_attack_state()


## 清空当前攻击窗口已命中的目标。
func reset_attack_targets() -> void:
	attack_module.reset_attack_targets()


## 根据攻击帧启用或关闭攻击框。
func update_attack_hitbox_window(attack: FrayAttackAttribute, attack_frame: int) -> void:
	attack_module.update_attack_hitbox_window(attack, attack_frame)


## 切换指定攻击状态的命中框并处理即时重叠。
func set_attack_hitbox(state_name: StringName, active: bool) -> void:
	attack_module.set_attack_hitbox(state_name, active)


## 关闭攻击管理器中的全部命中框。
func clear_attack_hitboxes() -> void:
	attack_module.clear_attack_hitboxes()


## 打开招式取消窗口。
func open_move_cancel_window(source_move_id: StringName) -> void:
	combo_input.open_cancel_window(source_move_id)


## 更新招式取消窗口。
func update_move_cancel_window(attack: FrayAttackAttribute, attack_frame: int) -> void:
	combo_input.update_cancel_window(attack, attack_frame)


## 关闭连段输入窗口。
func close_combo_input_window(clear_buffer := false) -> void:
	combo_input.close_window(clear_buffer)


## 消费招式取消缓冲。
func consume_move_cancel_buffer(target_move_id: StringName) -> void:
	combo_input.consume_buffer(target_move_id)


## 判断当前攻击帧是否处于允许取消的窗口。
func can_cancel_move_now() -> bool:
	return combo_input.can_cancel_now()


## 判断缓冲中是否存在指定取消目标的输入。
func has_buffered_cancel_to(target_move_id: StringName) -> bool:
	return combo_input.has_buffered_cancel_to(target_move_id)


## 返回带角色前缀的 Fray 输入名称。
func fray_input(action: StringName) -> StringName:
	return StringName("%s_%s" % [input_prefix, action])


## 按照当前姿态刷新战斗框。
func refresh_battle_hitboxes() -> void:
	_update_facing()
	clear_attack_state()
	set_hurt_state(_get_hurt_state_for_current_pose())


## 返回推挤框结算器。
func get_pushbox_resolver() -> DemoFighterPushbox:
	return pushbox


## 记录倒地。
func queue_knockdown(attack: FrayAttackAttribute) -> void:
	if not attack.causes_knockdown():
		return
	pending_knockdown = {
		"duration": attack.get_knockdown_seconds(),
		"untechable_time": attack.get_untechable_seconds(),
		"hard": attack.is_hard_knockdown(),
		"type": attack.knockdown_type,
	}


## 判断是否存在待处理倒地。
func has_pending_knockdown() -> bool:
	return not pending_knockdown.is_empty()


## 消费待处理倒地。
func consume_pending_knockdown() -> Dictionary:
	var result := pending_knockdown.duplicate()
	pending_knockdown.clear()
	return result


## 清除待处理倒地。
func clear_pending_knockdown() -> void:
	pending_knockdown.clear()


## 设置倒地受身可用性。
func set_knockdown_tech_available(available: bool, hard := false) -> void:
	knockdown_tech_available = available
	knockdown_is_hard = hard


## 判断当前是否可以受身翻滚。
func can_tech_roll() -> bool:
	return (
		get_current_state() == &"knockdown"
		and knockdown_tech_available
		and not knockdown_is_hard
		and absf(get_move_axis()) > 0.1
	)


## 返回受身翻滚方向。
func get_tech_roll_direction() -> int:
	var axis := signf(get_move_axis())
	return int(axis) if axis != 0.0 else -facing

## 缓存场景中固定节点的引用。
func _setup_scene_nodes() -> void:
	controller = $FrayController as FrayController
	controller.disabled = false
	process_priority = -200
	animation_player = $AnimationPlayer as AnimationPlayer
	animation_player.root_node = NodePath("..")
	state_machine = $FrayStateMachine as FrayStateMachine
	state_machine.advance_mode = FrayStateMachine.AdvanceMode.PHYSICS
	state_machine.process_priority = -100
	state_machine.state_changed.connect(_on_state_machine_state_changed)
	input_advancer = $FrayStateMachine/BufferedInputAdvancer as FrayBufferedInputAdvancer
	input_advancer.advance_mode = FrayBufferedInputAdvancer.AdvanceMode.PHYSICS
	input_advancer.process_priority = -90
	hurt_manager = $FacingRoot/HurtStateManager2D as FrayHitStateManager2D
	attack_manager = $FacingRoot/AttackStateManager2D as FrayHitStateManager2D
	facing_root = $FacingRoot as Node2D
	sprite = $FacingRoot/CharacterSprite as Sprite2D
	sprite.modulate = sprite_modulate
	sprite.centered = true


## 配置组件。
func _setup_components() -> void:
	pushbox = $Pushbox as DemoFighterPushbox
	pushbox.setup(self, environment.arena_left, environment.arena_right)
	movement = DemoFighterMovement.new()
	movement.setup(self, pushbox, environment)
	if is_player:
		controller.device = _FrayInput.DEVICE_KBM_JOY1
	else:
		virtual_ai = DemoFighterVirtualAI.new()
		virtual_ai.setup(self, controller)
	input_setup.setup_buffering(controller, input_advancer, move_loadout)


## 根据停帧和角色状态同步输入缓冲推进器的暂停状态。
func _sync_input_advancer_pause() -> void:
	input_advancer.buffer_clock_paused = _is_hitstop_active()
	input_advancer.paused = _is_hitstop_active() or not (
		is_in_neutral_state()
		or has_current_state_tag(&"airborne")
		or has_current_state_tag(&"knockdown")
	)


## 状态机切换时处理取消缓冲、连段重置和输入暂停。
func _on_state_machine_state_changed(from_state: StringName, to_state: StringName) -> void:
	if move_loadout.can_cancel_to_move(from_state, to_state):
		consume_move_cancel_buffer(to_state)
	else:
		combo_input.clear_matched_cancel_inputs()
	if combat_resolver.is_combo_active() and to_state in [&"idle", &"walk", &"crouch"]:
		combat_resolver.reset_combo()
	_sync_input_advancer_pause()


## 更新朝向。
func _update_facing() -> void:
	# Mortal Kombat-style side switches: crossing over changes facing automatically,
	# while the dedicated block input remains side-independent.
	facing = 1 if opponent.global_position.x >= global_position.x else -1
	facing_root.scale.x = facing


## 返回受击状态对应当前姿态。
func _get_hurt_state_for_current_pose() -> StringName:
	if get_current_state() == &"crouch":
		return &"Crouch"
	return &"Air" if has_current_state_tag(&"airborne") else &"Stand"


## 判断是否着地。
func is_grounded() -> bool:
	return movement.is_floor_contact()


## 判断角色是否希望下蹲。
func wants_crouch() -> bool:
	return is_grounded() and controller.is_pressed(fray_input(&"down"))


## 判断角色是否希望行走。
func wants_walk() -> bool:
	return is_grounded() and absf(get_move_axis()) > 0.1 and not wants_crouch()


## 判断角色是否希望待机。
func wants_idle() -> bool:
	return is_grounded() and absf(get_move_axis()) <= 0.1 and not wants_crouch()


## 判断当前是否可以跳跃。
func can_jump() -> bool:
	return is_grounded() and not wants_crouch()


## 判断当前是否可以二段跳跃。
func can_double_jump() -> bool:
	return has_current_state_tag(&"airborne") and movement.can_double_jump()


## 判断当前是否可以地面冲刺。
func can_ground_dash() -> bool:
	return is_grounded() and is_in_neutral_state() and not wants_crouch()


## 返回冲刺持续时间。
func get_dash_duration(state_name: StringName) -> float:
	return environment.dash_back_duration if state_name == &"dash_back" else environment.dash_forward_duration


## 返回指定冲刺状态的移动速度。
func get_dash_speed(state_name: StringName) -> float:
	return environment.dash_back_speed if state_name == &"dash_back" else environment.dash_forward_speed


## 判断是否空中。
func is_airborne() -> bool:
	return not is_grounded()

## 判断是否格挡。
func is_blocking() -> bool:
	return combat_resolver.is_blocking()


## 生成投射物攻击。
func spawn_projectile_attack(attack: DemoProjectileAttackAttribute) -> void:
	if projectile_scene == null:
		push_error("DemoFighter requires a projectile_scene")
		return
	var projectile := projectile_scene.instantiate() as DemoFighterProjectile
	if projectile == null:
		push_error("projectile_scene must instantiate DemoFighterProjectile")
		return
	projectile.setup(self, attack, facing)
	var spawn_offset := attack.projectile_spawn_offset
	get_parent().add_child(projectile)
	projectile.global_position = global_position + Vector2(spawn_offset.x * float(facing), spawn_offset.y)


## 返回角色当前的水平移动输入轴值。
func get_move_axis() -> float:
	return controller.get_axis(fray_input(&"left"), fray_input(&"right"))
