class_name FighterHitStateBuilder
extends RefCounted
## 直接按 Loadout 选择离树装配完整判定子树，不读取状态机或转换库。

## 保存本次构建的判定定义到角色节点绑定。
var hit_state_by_definition: Dictionary[FighterHitStateDefinition, FrayHitState2D] = {}


## 合并显式状态与所选招式依赖，返回全部判定仍关闭的离树 Manager。
func build(loadout: FighterLoadout) -> FrayHitStateManager2D:
	hit_state_by_definition.clear()
	var definitions: Dictionary[StringName, FighterStateDefinition] = {}
	for definition in loadout.state_library.states:
		var path := _state_path(definition.group_path, definition.state_name)
		definitions[path] = definition
	var moves: Dictionary[StringName, FighterMoveDefinition] = {}
	for move in loadout.move_library.moves:
		moves[move.move_id] = move
	var selected_state_paths: Array[StringName] = []
	for path in loadout.selected_state_paths:
		if not path in selected_state_paths:
			selected_state_paths.append(path)
	for move_id in loadout.selected_move_ids:
		for path in moves[move_id].required_state_paths:
			if not path in selected_state_paths:
				selected_state_paths.append(path)

	var manager := FrayHitStateManager2D.new()
	manager.name = &"FrayHitStateManager2D"
	for path in selected_state_paths:
		var definition := definitions[path].hit_state_definition
		if definition == null or hit_state_by_definition.has(definition):
			continue
		var pose := definition.hit_state_scene.instantiate() as FrayHitState2D
		pose.name = "%s_%d" % [pose.name, hit_state_by_definition.size()]
		# 每个角色拥有独立的可变碰撞几何。
		for box in pose.get_hitboxes():
			for child in box.get_children():
				if child is CollisionShape2D:
					child.shape = child.shape.duplicate()
					if box.attribute != null:
						child.debug_color = box.attribute.get_color()
		pose.active_hitboxes = 0
		pose.deactivate()
		manager.add_child(pose)
		hit_state_by_definition[definition] = pose
	return manager


## 拼接状态定义的完整状态路径。
func _state_path(group_path: StringName, state_name: StringName) -> StringName:
	return StringName(String(state_name) if group_path.is_empty()
		else String(group_path) + "/" + String(state_name))
