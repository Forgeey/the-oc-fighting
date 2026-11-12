class_name FighterLoadout
extends Resource
## 从公共库选择角色的基础状态和招式。

## 提供全游戏状态定义。
@export var state_library: FighterStateLibrary
## 提供全游戏招式定义。
@export var move_library: FighterMoveLibrary
## 提供全游戏转换规则。
@export var transition_library: FighterTransitionLibrary

## 选择直接装配到根的基础叶子状态名称。
@export var selected_state_names: Array[StringName] = []
## 选择本角色装备的招式 ID。
@export var selected_move_ids: Array[StringName] = []

## 根的唯一初始状态；必须是已装配的根动作或局部组。
@export var entry_state: StringName = &"idle"


## 战前将招式静态入口解析到本库；叶子按 state_id、组按 state_name 解析，不处理解锁或指令冲突。
## 失败返回空结果，调用方必须停止装配；成功结果由三套系统共用。
func resolve_selection() -> Dictionary:
	# 当前直接信任内容作者的 ID 非空、唯一及运行名称全局唯一约定，不做定义预检。
	var state_by_id: Dictionary[StringName, FighterStateDefinition] = {}
	var state_by_name: Dictionary[StringName, FighterStateDefinition] = {}
	for state in state_library.states:
		state_by_id[state.state_id] = state
		state_by_name[state.state_name] = state
	var compounds_by_name: Dictionary[StringName, FighterCompoundStateDefinition] = {}
	for definition in state_library.compound_states:
		compounds_by_name[definition.state_name] = definition
	var selected_compounds: Dictionary[StringName, FighterCompoundStateDefinition] = {}
	var move_by_id: Dictionary[StringName, FighterMoveDefinition] = {}
	for move in move_library.moves:
		move_by_id[move.move_id] = move
	var moves: Array[FighterMoveDefinition] = []
	var selected_states: Dictionary[StringName, FighterStateDefinition] = {}
	for name in selected_state_names:
		if not state_by_name.has(name):
			push_error("State selection rejected: unknown selected state name '%s'." % name)
			return {}
		var state: FighterStateDefinition = state_by_name[name]
		selected_states[state.state_id] = state
	for id in selected_move_ids:
		if not move_by_id.has(id):
			push_error("State selection rejected: unknown selected move ID '%s'." % id)
			return {}
		var move: FighterMoveDefinition = move_by_id[id]
		if move.state == null:
			push_error("State selection rejected: move '%s' has no execution state." % id)
			return {}
		moves.append(move)
		if move.state is FighterStateDefinition:
			var definition := move.state as FighterStateDefinition
			if not state_by_id.has(definition.state_id):
				push_error("State selection rejected: unknown state ID '%s' in move '%s'." % [definition.state_id, id])
				return {}
			selected_states[definition.state_id] = state_by_id[definition.state_id]
		else:
			var definition := move.state as FighterCompoundStateDefinition
			selected_compounds[definition.state_name] = compounds_by_name[definition.state_name]
	# 独立选择的叶子属于根；组不反向污染叶子，也不按叶子身份猜测父组。
	var root_states: Array[FighterStateDefinition] = []
	root_states.assign(selected_states.values())
	for group: FighterCompoundStateDefinition in selected_compounds.values():
		for reference in group.states:
			selected_states[reference.state_id] = state_by_id[reference.state_id]
	var states: Array[FighterStateDefinition] = []
	for state in selected_states.values():
		states.append(state)
	var compound_states: Array[FighterCompoundStateDefinition] = []
	compound_states.assign(selected_compounds.values())
	return {moves = moves, root_states = root_states, states = states, compound_states = compound_states}
