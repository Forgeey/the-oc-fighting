extends TextureRect

@export var fade_in_time: float = 1

signal fade_in_completed


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	self_modulate.a = 0
	var tween = get_tree().create_tween()
	tween.tween_property(self, "self_modulate:a", 1.0, fade_in_time)
	tween.connect("finished", _emit_fade_complete)
	
func _emit_fade_complete():
	emit_signal("fade_in_completed")

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
