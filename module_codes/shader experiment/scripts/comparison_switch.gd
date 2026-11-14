extends Button

@export_file("*.tscn") var target_scene: String

# 只保留比较用的相机状态；两个场景共用此脚本。
static var camera_state: Dictionary = {}

@onready var map: Node = get_parent().get_parent()


func _ready() -> void:
	pressed.connect(_switch_scene)
	map.ready.connect(_restore_camera)


func _switch_scene() -> void:
	var camera = map.get_node("MapCamera")
	camera_state = {
		"ground_position": camera.ground_position,
		"height": camera.height,
		"focal_length": camera.focal_length,
		"horizon": camera.horizon,
		"speed": camera.speed,
	}
	get_tree().change_scene_to_file(target_scene)


func _restore_camera() -> void:
	if camera_state.is_empty():
		return
	var camera = map.get_node("MapCamera")
	for property in camera_state:
		camera.set(property, camera_state[property])
	map.update_projection()