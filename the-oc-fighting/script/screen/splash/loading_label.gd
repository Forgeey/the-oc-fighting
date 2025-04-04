extends Label

@export var ani_loop_duration: float = 3.0
@export var min_transparency: float = 0.3


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	visible = false


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_title_fade_in_completed() -> void:
	visible = true
	var tween = get_tree().create_tween()
	tween.tween_property(self, "self_modulate:a", 1.0, ani_loop_duration / 2)
	tween.tween_property(self, "self_modulate:a", min_transparency, ani_loop_duration / 2)
	tween.set_loops(1)  # FIXME: For development
	# tween.set_loops()
	tween.connect("finished", _on_loading_finished)
	
func _on_loading_finished() -> void:
	get_tree().change_scene_to_file("res://core/screen/arena.tscn")
	
