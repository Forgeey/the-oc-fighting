class_name FighterHitStateBuilder
extends RefCounted
## 只按已解析的状态集合离树装配判定子树，不读取装备、招式或转换库。

## 保存本次构建的判定定义到角色节点绑定。
var hit_states: Dictionary[FighterHitStateDefinition, FrayHitState2D] = {}


## 使用与状态机相同的状态定义集合，返回全部判定仍关闭的离树 Manager。
func build(states: Array[FighterStateDefinition]) -> FrayHitStateManager2D:
	hit_states.clear()
	var manager := FrayHitStateManager2D.new()
	manager.name = &"FrayHitStateManager2D"
	for state in states:
		var definition := state.hit_state_definition
		if hit_states.has(definition):
			continue
		var pose := definition.hit_state_scene.instantiate() as FrayHitState2D
		pose.name = "%s_%d" % [pose.name, hit_states.size()]
		# 碰撞形状的实例隔离和调试颜色由判定场景配置。
		pose.active_hitboxes = 0
		pose.deactivate()
		manager.add_child(pose)
		hit_states[definition] = pose
	return manager
