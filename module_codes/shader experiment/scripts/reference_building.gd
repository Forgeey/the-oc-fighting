extends "res://scripts/building.gd"

## wall2 中的面边界，像素坐标；顺序：近端顶、远端顶、远端底、近端底。
## 使用像素边界坐标，允许最右/底坐标等于图像尺寸。
@export var side_reference_corners := PackedVector2Array([
	Vector2(0, 4), Vector2(113, 41), Vector2(113, 256), Vector2(0, 256)
])


func update_projection(camera: Node, screen_width: float) -> void:
	super.update_projection(camera, screen_width)
	var texture_size: Vector2 = material.get_shader_parameter("side_texture").get_size()
	var p := PackedVector2Array()
	for corner in side_reference_corners:
		p.append(corner / texture_size)
	material.set_shader_parameter("side_reference_map", square_to_quad(p))


## 局部单位矩形 → 素材中的参考四边形（单应矩阵，列向量）。
func square_to_quad(p: PackedVector2Array) -> Basis:
	var d1 := p[1] - p[2]
	var d2 := p[3] - p[2]
	var d3 := p[0] - p[1] + p[2] - p[3]
	var divisor := d1.cross(d2)
	var g := d3.cross(d2) / divisor
	var h := d1.cross(d3) / divisor
	var a := p[1] - p[0] + g * p[1]
	var b := p[3] - p[0] + h * p[3]
	return Basis(Vector3(a.x, a.y, g), Vector3(b.x, b.y, h), Vector3(p[0].x, p[0].y, 1.0))