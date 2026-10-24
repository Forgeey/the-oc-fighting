class_name Fighter
extends CharacterBody2D
## 输入采样(-50) → 状态物理更新(0) → 本节点普通推进(50)。

@export var move_env: FighterMoveEnv
@export var loadout: FighterLoadout
var _movement := FighterMovement.new()
var _standing_body_size: Vector2
var _standing_body_pos: Vector2

@onready var body_shape: CollisionShape2D = $CollisionShape2D

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var controller: FrayController = $FrayController
@onready var fighter_input: FighterInput = $FighterInput
@onready var hit_state_manager: FrayHitStateManager2D = $FrayHitStateManager2D
@onready var state_machine: FrayStateMachine = $FrayStateMachine
@onready var advancer: FrayBufferedInputAdvancer = $FrayStateMachine/FrayBufferedInputAdvancer


func _ready() -> void:
	_init_fighter()


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
	set_facing(1)
	advancer.paused = true
	hit_state_manager.source = self
	_initialize_state_machine(loadout.entry_path)


func _initialize_state_machine(target_path: StringName) -> void:
	var root := FighterSMBuilder.new().build(self, loadout)
	fighter_input.configure(controller, loadout.selected_moves)
	state_machine.initialize({
		"fighter": self,
		"controller": controller,
		"fighter_input": fighter_input,
		"movement": _movement,
		"hit_state_manager": hit_state_manager,
	}, root, target_path)
	state_machine.advance_mode = FrayStateMachine.AdvanceMode.MANUAL
	state_machine.active = true


# 根据指令推进状态机
func _physics_process(_delta: float) -> void:
	advance_commands()


## 根据候选指令进行推进，无法推进则进行状态机自动推进。
func advance_commands() -> bool:
	for candidate in fighter_input.get_candidates():
		if _try_move(candidate):
			fighter_input.consume(candidate)
			return true
	return state_machine.advance()


## 固定招式规则通过源状态、前置条件和完成条件后，才执行 external 转换。
## Fray 公开 add_transition 仅支持直接子节点；跨层入口桥接集中在此处。
func _try_move(candidate: Dictionary) -> bool:
	var move: FighterMoveDefinition = candidate.move
	var root := state_machine.get_root()
	var active_info := root.get_active_states_info()
	var active_states: Array[FrayState] = active_info.states
	var source: FrayState
	for state in active_states:
		for path in move.allowed_from_paths:
			if root.get_state_or_null(path) == state:
				source = state
	if source == null:
		return false
	for expression in move.prereqs:
		if not root.is_condition_true(expression):
			return false
	if move.switch_mode == FrayStateMachineTransition.SwitchMode.AT_END:
		if not source.is_done_processing() or not active_states.back().is_done_processing():
			return false
	# 不是无条件 goto；使用修复后的 external 执行器，保留自转移和进退顺序。
	return root._transition_to(move.entry_path, {
		"move_id": move.move_id,
		"input_frame": candidate.created_frame,
	}, source)


func set_facing(direction: int) -> void:
	fighter_input.facing_dir = direction
	_movement.set_facing(direction)
	# 原图朝左，面向右时仅翻转表现节点。
	sprite.flip_h = direction == 1


func get_forward_axis() -> float:
	return fighter_input.get_horizontal_axis() if inputed_fwalk() else 0.0


func inputed_fwalk() -> bool:
	return fighter_input.inputed_fwalk()


func get_backward_axis() -> float:
	return fighter_input.get_horizontal_axis() if inputed_bwalk() else 0.0


func inputed_bwalk() -> bool:
	return fighter_input.inputed_bwalk()


func inputed_crouch() -> bool:
	return fighter_input.inputed_crouch()


## 只调整实体碰撞体，保持脚底高度；不代替战斗 hurtbox / 防御判定。
func set_crouching(crouching: bool) -> void:
	var height := _standing_body_size.y * (0.5 if crouching else 1.0)
	body_shape.shape.size = Vector2(_standing_body_size.x, height)
	body_shape.position = _standing_body_pos + Vector2(0.0, (_standing_body_size.y - height) * 0.5)


func play_animation(animation_key: StringName) -> void:
	sprite.play(animation_key)
