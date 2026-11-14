extends AnimatedSprite2D

## 地面脚点的世界 X/Z；高度单独保留，不拿跳跃改变 Z。
@export var ground_position := Vector2.ZERO
@export var jump_height := 0.0
## 素材的世界体量标尺，不用于决定屏幕分辨率。当前每源像素投影约 2 渲染像素。
@export var world_units_per_texel := 3.0


func update_projection(camera: Node, screen_width: float) -> void:
	var foot := Vector3(ground_position.x, jump_height, ground_position.y)
	position = camera.project(foot, screen_width).round()
	scale = Vector2.ONE * world_units_per_texel * camera.scale_at(ground_position.y)
	z_index = -int(ground_position.y)
