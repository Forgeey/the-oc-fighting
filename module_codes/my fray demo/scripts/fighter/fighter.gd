class_name Fighter
extends CharacterBody2D
## 装配角色组件，推进状态，并同步朝向、动画和判定。

@export var move_env: FighterMoveEnv
@export var loadout: FighterLoadout
var _movement := FighterMovement.new()
var _standing_body_size: Vector2
var _standing_body_pos: Vector2
## 保存本角色全部已选转换，同组普通规则交给 Fray 推进。
var _selected_transitions: Array[FighterTransitionDefinition] = []

## 由判定 Builder 离树组装后整体挂载，不预置在 Fighter 场景中。
var hit_state_manager: FrayHitStateManager2D
var hit_states: Dictionary[FighterHitStateDefinition, FrayHitState2D] = {}
var _current_hit_state: FrayHitState2D
var _requested_facing: int = 1
var _last_transition_frame: int = -1

@onready var body_shape: CollisionShape2D = $CollisionShape2D

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var controller: FrayController = $FrayController
@onready var fighter_input: FighterInput = $FighterInput
@onready var state_machine: FrayStateMachine = $FrayStateMachine
@onready var advancer: FrayBufferedInputAdvancer = $FrayStateMachine/FrayBufferedInputAdvancer


#region 角色初始化

## 节点就绪后装配角色组件。
func _ready() -> void:
	_init_fighter()


## 设置更新顺序，初始化运动、判定和状态机。
func _init_fighter() -> void:
	# Fray 原始采样先于每角色方向清洗；不修改插件源码。
	FrayInput.process_physics_priority = -100
	process_physics_priority = 50
	# 场景通过 resource_local_to_scene 保证碰撞形状按角色独立持有。
	_standing_body_size = body_shape.shape.size
	_standing_body_pos = body_shape.position
	# 运动模块初始化。
	_movement.init_movement(move_env, self)
	# 每个角色在战前仅解析一次当前选择，三套系统共用同一结果。
	var selection := loadout.resolve_selection()
	# 判定系统初始化。
	var hit_builder := FighterHitStateBuilder.new()
	hit_state_manager = hit_builder.build(selection.states)
	hit_states = hit_builder.hit_states
	add_child(hit_state_manager)
	hit_state_manager.source = self
	# 初始朝向先存请求；输入与状态就绪后统一发布。
	_requested_facing = 1
	# 推进器和状态机初始化。
	advancer.paused = true
	_initialize_state_machine(loadout.entry_state, selection)


## 配置输入与状态树，并启用原生状态机和缓冲推进器。
func _initialize_state_machine(target_path: StringName, selection: Dictionary) -> void:
	var builder := FighterSMBuilder.new()
	var root := builder.build(self, loadout, selection)
	_selected_transitions = builder.selected_transitions
	# 在角色构建时配置一棵序列树和唯一 Matcher；普通转向不重配。
	fighter_input.configure(controller, selection.moves, advancer)
	state_machine.initialize({
		"fighter": self,
		"controller": controller,
		"fighter_input": fighter_input,
		"movement": _movement,
		"hit_state_manager": hit_state_manager,
	}, root, target_path)
	state_machine.get_root().transitioned.connect(_on_transitioned)
	state_machine.advance_mode = FrayStateMachine.AdvanceMode.MANUAL
	state_machine.active = true
	advancer.process_physics_priority = 25
	advancer.advance_mode = FrayBufferedInputAdvancer.AdvanceMode.PHYSICS
	publish_input_context()
	advancer.paused = false


#endregion


#region 状态推进与查询

## 尝试普通状态推进，并在帧末发布输入上下文。
func _physics_process(_delta: float) -> void:
	advance_commands()
	publish_input_context()


## 本帧尚未转换时，尝试推进当前状态。
func advance_commands() -> bool:
	if _last_transition_frame == Engine.get_physics_frames():
		return false
	return state_machine.advance()


## 记录转换帧，避免同帧再次推进。
func _on_transitioned(_from: StringName, _to: StringName) -> void:
	_last_transition_frame = Engine.get_physics_frames()


## 沿当前状态分支找到实际执行动作的叶子。
func get_active_leaf() -> FighterState:
	var state := state_machine.get_root().get_current_state()
	while state is FrayCompoundState:
		state = state.get_current_state()
	return state as FighterState


#endregion


#region 朝向与输入上下文

## 记录转向请求，留到帧末按状态权限提交。
func set_facing(direction: int) -> void:
	_requested_facing = direction


## 按当前动作的转向权限，同步输入、运动、画面和判定朝向。
func publish_input_context() -> void:
	var state := get_active_leaf()
	var direction := _requested_facing if state.can_update_facing() else fighter_input.facing_dir
	fighter_input.publish_context(direction)
	_movement.set_facing(direction)
	sprite.flip_h = direction == 1
	hit_state_manager.scale.x = float(direction)


#endregion


#region 地面与实体碰撞

## 返回角色是否接触地面。
func grounded() -> bool:
	return is_on_floor()


## 切换实体碰撞体高度，并保持脚底位置。
func set_crouching(crouching: bool) -> void:
	var height := _standing_body_size.y * (0.5 if crouching else 1.0)
	body_shape.shape.size = Vector2(_standing_body_size.x, height)
	body_shape.position = _standing_body_pos + Vector2(0.0, (_standing_body_size.y - height) * 0.5)


#endregion


#region 动画播放

## 解析动画语义并播放对应动画。
func play_animation(animation_key: StringName) -> void:
	sprite.play(_resolve_animation_key(animation_key))


## 预留外观动画映射入口，目前原样返回动画键。
func _resolve_animation_key(animation_key: StringName) -> StringName:
	return animation_key


#endregion


#region 判定姿态管理

## 选择本状态的判定姿态，并应用默认启用掩码。
func select_hit_state(definition: FighterHitStateDefinition) -> void:
	_current_hit_state = hit_states[definition]
	set_hit_state_mask(definition.default_active_hitboxes)


## 更新当前姿态中启用的判定框。
func set_hit_state_mask(mask: int) -> void:
	_current_hit_state.active_hitboxes = mask


## 关闭并停用当前姿态，避免退出状态后残留判定。
func clear_hit_state() -> void:
	var pose := _current_hit_state
	_current_hit_state = null
	var blocked := pose.is_blocking_signals()
	pose.set_block_signals(true)
	pose.active_hitboxes = 0
	pose.deactivate()
	pose.set_block_signals(blocked)


#endregion
