extends Node2D

@onready var camera = $MapCamera
@onready var floor_rect: ColorRect = $Floor
@onready var buildings: Node2D = $Buildings
@onready var players: Node2D = $Players


func _ready() -> void:
	update_projection()


func _process(delta: float) -> void:
	camera.move(delta)
	update_projection()


func update_projection() -> void:
	var screen_size := get_viewport_rect().size
	floor_rect.size = screen_size
	for player in players.get_children():
		player.update_projection(camera, screen_size.x)
	for building in buildings.get_children():
		building.update_projection(camera, screen_size.x)
	for surface in [floor_rect] + buildings.get_children():
		camera.sync_shader_parameters(surface.material, screen_size)
