extends Node

## 相机地面 X/Z；WASD 不改变 Z，以保持角色显示尺度。
@export var ground_position := Vector2(0.0, -1400.0)
@export_range(1.0, 2000.0, 1.0, "or_greater") var height := 210.0
## 1280×720 渲染像素；从旧画布同比例换算，保持视野与构图。
@export var focal_length := 933.3333333334
@export var horizon := 460.0
@export var speed := 320.0

var initial_ground_position: Vector2
var initial_height: float


func _ready() -> void:
	initial_ground_position = ground_position
	initial_height = height


func move(delta: float) -> void:
	var direction := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_S))
	).normalized()
	ground_position.x = clampf(ground_position.x + direction.x * speed * delta, -700.0, 700.0)
	height = clampf(height + direction.y * speed * delta, 80.0, 420.0)
	if Input.is_physical_key_pressed(KEY_R):
		ground_position = initial_ground_position
		height = initial_height


## CameraRuntime 是脚本输出；请在相机节点调整，而不是在材质中修改。
func sync_shader_parameters(material: ShaderMaterial, screen_size: Vector2) -> void:
	material.set_shader_parameter("screen_size", screen_size)
	material.set_shader_parameter("camera_ground", ground_position)
	material.set_shader_parameter("camera_height", height)
	material.set_shader_parameter("focal_length", focal_length)
	material.set_shader_parameter("horizon", horizon)


func scale_at(world_z: float) -> float:
	return focal_length / (world_z - ground_position.y)


func project(point: Vector3, screen_width: float) -> Vector2:
	var perspective := scale_at(point.z)
	return Vector2(
		screen_width * 0.5 + (point.x - ground_position.x) * perspective,
		horizon + (height - point.y) * perspective
	)
