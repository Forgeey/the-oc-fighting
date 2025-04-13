extends Control


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	visible = false


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_title_fade_in_completed() -> void:
	visible = true
	get_tree().create_timer(3).timeout.connect(_on_loading_finished)
	
func _on_loading_finished() -> void:
	get_tree().change_scene_to_file("res://core/screen/arena.tscn")
	
