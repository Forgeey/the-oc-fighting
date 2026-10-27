class_name Fighter
extends CharacterBody2D
## 管理角色组件、输入请求和状态机初始化。

@export var move_env: FighterMoveEnv
@export var loadout: FighterLoadout
var _movement := FighterMovement.new()
var _standing_body_size: Vector2
var _standing_body_pos: Vector2
## 保存本角色全部已选转换，同组普通规则交给 Fray 推进。
var _selected_transitions: Array[FighterTransitionDefinition] = []

## 由判定 Builder 离树组装后整体挂载，不预置在 Fighter 场景中。
var hit_state_manager: FrayHitStateManager2D
var _hit_state_by_definition: Dictionary[FighterHitStateDefinition, FrayHitState2D] = {}
var _current_hit_state: FrayHitState2D

@onready var body_shape: CollisionShape2D = $CollisionShape2D

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var controller: FrayController = $FrayController
@onready var fighter_input: FighterInput = $FighterInput
@onready var state_machine: FrayStateMachine = $FrayStateMachine
@onready var advancer: FrayBufferedInputAdvancer = $FrayStateMachine/FrayBufferedInputAdvancer


## 节点就绪后初始化角色。
func _ready() -> void:
	_init_fighter()


## 初始化角色组件和物理更新顺序。
func _init_fighter() -> void:
	FighterInputBindings.register_actions(FrayInputMap)
	# Fray 原始采样先于每角色方向清洗；不修改插件源码。
	FrayInput.process_physics_priority = -100
	process_physics_priority = 50
	# 碰撞形状按角色独立持有；蹲下不能修改其他角色的共享资源。
	body_shape.shape = body_shape.shape.duplicate()
	_standing_body_size = body_shape.shape.size
	_standing_body_pos = body_shape.position
	_movement.init_movement(move_env, self)
	var hit_builder := FighterHitStateBuilder.new()
	hit_state_manager = hit_builder.build(loadout)
	_hit_state_by_definition = hit_builder.hit_state_by_definition
	add_child(hit_state_manager)
	hit_state_manager.source = self
	set_facing(1)
	advancer.paused = true
	_initialize_state_machine(loadout.entry_path)


## 按装备的招式构建状态机并配置输入。
func _initialize_state_machine(target_path: StringName) -> void:
	var builder := FighterSMBuilder.new()
	var root := builder.build(self, loadout)
	_selected_transitions = builder.selected_transitions
	fighter_input.configure(controller, builder.selected_moves)
	state_machine.initialize({
		"fighter": self,
		"controller": controller,
		"fighter_input": fighter_input,
		"movement": _movement,
		"hit_state_manager": hit_state_manager,
	}, root, target_path)
	state_machine.advance_mode = FrayStateMachine.AdvanceMode.MANUAL
	state_machine.active = true


## 每个物理帧处理输入候选和普通转换。
func _physics_process(_delta: float) -> void:
	advance_commands()


## 依次尝试招式候选、跨组普通转换和同组普通转换。
func advance_commands() -> bool:
	for candidate in fighter_input.get_candidates():
		if _try_move(candidate):
			fighter_input.consume(candidate)
			return true
	for rule in _selected_transitions:
		if not rule.move_id.is_empty():
			continue
		if String(rule.from_state).get_base_dir() == String(rule.to_state).get_base_dir():
			continue
		if _try_transition(rule):
			return true
	return state_machine.advance()


## 按已装配的转换规则检查并发动候选招式。
func _try_move(candidate: Dictionary) -> bool:
	var move: FighterMoveDefinition = candidate.move
	var root := state_machine.get_root()
	for expression in move.prereqs:
		if not root.is_condition_true(expression):
			return false
	for rule in _selected_transitions:
		if rule.move_id != move.move_id or rule.to_state != move.entry_path:
			continue
		if _try_transition(rule, {
			"move": move,
			"move_id": move.move_id,
			"input_frame": candidate.created_frame,
		}):
			return true
	return false


## 检查活动源和规则条件后按完整路径执行转换。
func _try_transition(rule: FighterTransitionDefinition, args: Dictionary = {}) -> bool:
	var root := state_machine.get_root()
	var active_states: Array[FrayState] = root.get_active_states_info().states
	var source := root.get_state_or_null(rule.from_state)
	if not source in active_states:
		return false
	for expression in rule.prereqs:
		if not root.is_condition_true(expression):
			return false
	# 普通转换沿用 Fray 的条件语义，招式转换始终检查推进条件。
	if rule.auto_advance or not rule.move_id.is_empty():
		for expression in rule.advance_conditions:
			if not root.is_condition_true(expression):
				return false
	if rule.switch_mode == FrayStateMachineTransition.SwitchMode.AT_END:
		if not source.is_done_processing() or not active_states.back().is_done_processing():
			return false
	return root._transition_to(rule.to_state, args, source)


## 同步角色移动朝向和精灵翻转。
func set_facing(direction: int) -> void:
	fighter_input.facing_dir = direction
	_movement.set_facing(direction)
	# 原图朝左，面向右时仅翻转表现节点。
	sprite.flip_h = direction == 1
	# 判定场景面向右，只在 Manager 上镜像一次，不翻转世界碰撞体。
	hit_state_manager.scale.x = float(direction)


## 返回前进时使用的水平输入轴。
func get_forward_axis() -> float:
	return fighter_input.get_horizontal_axis() if inputed_fwalk() else 0.0


## 判断当前输入是否要求前进。
func inputed_fwalk() -> bool:
	return fighter_input.inputed_fwalk()


## 返回后退时使用的水平输入轴。
func get_backward_axis() -> float:
	return fighter_input.get_horizontal_axis() if inputed_bwalk() else 0.0


## 判断当前输入是否要求后退。
func inputed_bwalk() -> bool:
	return fighter_input.inputed_bwalk()


## 判断当前输入是否要求下蹲。
func inputed_crouch() -> bool:
	return fighter_input.inputed_crouch()


## 判断角色是否接触地面。
func grounded() -> bool:
	return is_on_floor()


## 切换实体碰撞体高度并保持脚底位置。
func set_crouching(crouching: bool) -> void:
	var height := _standing_body_size.y * (0.5 if crouching else 1.0)
	body_shape.shape.size = Vector2(_standing_body_size.x, height)
	body_shape.position = _standing_body_pos + Vector2(0.0, (_standing_body_size.y - height) * 0.5)


## 解析状态动画语义并播放角色当前表现中的动画。
func play_animation(animation_key: StringName) -> void:
	sprite.play(_resolve_animation_key(animation_key))


## 预留角色自定义动画映射入口，当前仅原样返回动画语义。
func _resolve_animation_key(animation_key: StringName) -> StringName:
	return animation_key


## 清理旧姿态后，选择本角色已装配的定义并应用默认掩码。
func select_hit_state(definition: FighterHitStateDefinition) -> void:
	clear_hit_state()
	if definition == null or definition.default_active_hitboxes == 0:
		return
	_current_hit_state = _hit_state_by_definition[definition]
	set_hit_state_mask(definition.default_active_hitboxes)


## 完全关闭当前姿态，避免 Manager 对零掩码通知再次 activate。
func clear_hit_state() -> void:
	if _current_hit_state == null:
		return
	var pose := _current_hit_state
	_current_hit_state = null
	var blocked := pose.is_blocking_signals()
	pose.set_block_signals(true)
	pose.active_hitboxes = 0
	pose.deactivate()
	pose.set_block_signals(blocked)


## 统一设置当前姿态的启用位，零掩码表示完全清理且需重新选择。
func set_hit_state_mask(mask: int) -> void:
	if mask == 0:
		clear_hit_state()
	elif _current_hit_state != null:
		_current_hit_state.active_hitboxes = mask


## 判断当前最深活动状态是否完成。
func active_leaf_done() -> bool:
	var states: Array[FrayState] = state_machine.get_root().get_active_states_info().states
	return not states.is_empty() and states.back().is_done_processing()
