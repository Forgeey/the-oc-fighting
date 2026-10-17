class_name Fighter
extends Node2D

@export var _environment = MoveEnvironment.new()
var _movement = Movement.new()

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_init_fighter()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _physics_process(delta: float) -> void:
	pass

func _init_fighter() -> void:
	_movement.init_movement(_environment)
