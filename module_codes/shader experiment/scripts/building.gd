extends ColorRect

## 正面底边中心的 X/Z 位置，深度沿 +Z 延伸。
@export var ground_position := Vector2.ZERO
## 世界尺寸：宽、高、深。
@export var world_size := Vector3(240.0, 400.0, 320.0)


func update_projection(camera: Node, screen_width: float) -> void:
	# 几何与屏幕范围一起更新，运行中改建筑参数也不会留下旧材质数据。
	var box_min := Vector3(ground_position.x - world_size.x * 0.5, 0.0, ground_position.y)
	material.set_shader_parameter("box_min", box_min)
	material.set_shader_parameter("box_size", world_size)
	z_index = -int(ground_position.y)

	# ColorRect 只承载八个角点的屏幕包围框，实际墙面由 shader 绘制。
	var bounds := Rect2(camera.project(Vector3(ground_position.x, 0.0, ground_position.y), screen_width), Vector2.ZERO)
	for x in [-0.5, 0.5]:
		for y in [0.0, 1.0]:
			for z in [0.0, 1.0]:
				var corner := box_min + world_size * Vector3(x + 0.5, y, z)
				bounds = bounds.expand(camera.project(corner, screen_width))
	position = bounds.position
	size = bounds.size
