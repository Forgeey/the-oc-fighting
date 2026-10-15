class_name CombatHitboxDebugDraw
extends Node2D
## 训练场判定框覆盖层。
##
## 绿色绘制 fighter pushbox，蓝色绘制活动 hurtbox，红色绘制活动 strike；命中数据直接读取 FrayHitbox2D 与其 attribute。

## 是否显示判定框。
@export var enabled: bool = true


## 每帧重绘活动 Fray hitbox，便于逐帧观察 startup/active/recovery。
func _process(_delta: float) -> void:
	queue_redraw()


## 使用 Z 对应的 debug_hitboxes action 切换覆盖层。
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_hitboxes"):
		enabled = not enabled
		queue_redraw()


## 遍历当前场景中的 fighter pushbox 与 FrayHitbox2D，并绘制 RectangleShape2D。
func _draw() -> void:
	if not enabled or get_tree().current_scene == null:
		return
	var pushboxes: Array[CollisionShape2D] = []
	_collect_pushboxes(get_tree().current_scene, pushboxes)
	for pushbox in pushboxes:
		var push_rectangle := pushbox.shape as RectangleShape2D
		if push_rectangle != null and not pushbox.disabled:
			_draw_pushbox(pushbox, push_rectangle)
	var hitboxes: Array[FrayHitbox2D] = []
	_collect_hitboxes(get_tree().current_scene, hitboxes)
	for hitbox in hitboxes:
		if not hitbox.is_visible_in_tree() or not hitbox.monitorable:
			continue
		for child in hitbox.get_children():
			var collision_shape := child as CollisionShape2D
			if collision_shape == null or collision_shape.disabled:
				continue
			var rectangle := collision_shape.shape as RectangleShape2D
			if rectangle == null:
				continue
			_draw_rectangle_hitbox(hitbox, collision_shape, rectangle)


## 递归收集 CombatCoreFighter 的 CharacterBody2D 碰撞形状作为 pushbox。
func _collect_pushboxes(node: Node, output: Array[CollisionShape2D]) -> void:
	var collision_shape := node as CollisionShape2D
	if collision_shape != null and collision_shape.get_parent() is CombatCoreFighter:
		output.append(collision_shape)
	for child in node.get_children():
		_collect_pushboxes(child, output)


## 递归收集 FrayHitbox2D，不修改任何判定节点。
func _collect_hitboxes(node: Node, output: Array[FrayHitbox2D]) -> void:
	if node is FrayHitbox2D:
		output.append(node)
	for child in node.get_children():
		_collect_hitboxes(child, output)


## 将 fighter pushbox 变换到覆盖层坐标并以绿色绘制。
func _draw_pushbox(collision_shape: CollisionShape2D, rectangle: RectangleShape2D) -> void:
	var half := rectangle.size * 0.5
	var local_points := PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y),
	])
	var points := PackedVector2Array()
	for point in local_points:
		points.append(to_local(collision_shape.global_transform * point))
	draw_colored_polygon(points, Color(0.2, 1.0, 0.4, 0.10))
	var closed := PackedVector2Array(points)
	closed.append(points[0])
	draw_polyline(closed, Color(0.35, 1.0, 0.5, 0.9), 2.0, true)
	draw_string(ThemeDB.fallback_font, points[0] + Vector2(0, -4), "push", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.35, 1.0, 0.5, 0.9))


## 将碰撞矩形变换到覆盖层坐标并绘制 attribute ID。
func _draw_rectangle_hitbox(hitbox: FrayHitbox2D, collision_shape: CollisionShape2D, rectangle: RectangleShape2D) -> void:
	var half := rectangle.size * 0.5
	var local_points := PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y),
	])
	var points := PackedVector2Array()
	for point in local_points:
		var world_point := collision_shape.global_transform * point
		points.append(to_local(world_point))
	var is_strike := hitbox.attribute is FrayAttackAttribute
	var fill := Color(1.0, 0.12, 0.08, 0.22) if is_strike else Color(0.1, 0.55, 1.0, 0.16)
	var outline := Color(1.0, 0.25, 0.18, 0.95) if is_strike else Color(0.2, 0.7, 1.0, 0.9)
	draw_colored_polygon(points, fill)
	var closed := PackedVector2Array(points)
	closed.append(points[0])
	draw_polyline(closed, outline, 2.0, true)
	var label := String(hitbox.attribute.id) if is_strike else "hurt"
	draw_string(ThemeDB.fallback_font, points[0] + Vector2(0, -4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, outline)