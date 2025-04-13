extends CharacterBody2D

@export var SPEED = 300.0
@export var JUMP_VELOCITY = -600.0
@export var DODGE_DURATION = 0.5
@export var KNOCKBACK_FORCE = 500.0
@export var FRACTION = 0.95
@export var MINIMUM_SPEED = 0.05

@export var IS_1P: bool = true

enum STATE {
	IDLE,
	MOVING,
	JUMPING,
	DODGING,
	PARRYING,
	KNOCKBACK,
	LANDING
}

var state := STATE.IDLE
var knockback_direction := Vector2.ZERO
var dodge_timer := 0.0

@onready var animated_sprite := $AnimatedSprite2D

func _ready() -> void:
	animated_sprite.animation_finished.connect(_on_animation_finished)

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += get_gravity().y * delta
	
	match state:
		STATE.KNOCKBACK:
			handle_knockback(delta)
		STATE.PARRYING:
			handle_parrying_finish()
		STATE.DODGING:
			handle_dodge_finish()
		_:
			handle_landing()
			handle_movement_input()
			handle_jump_input()
			handle_combat_input()
	
	update_animation_state()
	if state != STATE.IDLE:
		print(state)
	move_and_slide()

func handle_landing() -> void:
	if state == STATE.JUMPING and is_on_floor():
		animated_sprite.play("land")
		state = STATE.LANDING

func handle_movement_input() -> void:
	var direction = Input.get_axis("ui_left" if IS_1P else "2p_left", "ui_right" if IS_1P else "2p_right")
		
	if state == STATE.LANDING:
		var v = velocity.x * FRACTION
		velocity.x = v
	elif direction:
		velocity.x = direction * SPEED
		animated_sprite.flip_h = direction > 0
	else:
		if is_on_floor():
			velocity.x = move_toward(velocity.x, 0, SPEED)
		else:
			velocity.x *= FRACTION
	
	if state not in [STATE.JUMPING, STATE.LANDING]:
		state = STATE.MOVING if direction != 0 else STATE.IDLE

func handle_jump_input() -> void:
	if Input.is_action_just_pressed("jump" if IS_1P else "2p_jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
		var is_backjump = (Input.get_axis("ui_left" if IS_1P else "2p_left", "ui_right" if IS_1P else "2p_right") != 0) and \
						((velocity.x > 0 and not animated_sprite.flip_h) or \
						(velocity.x < 0 and animated_sprite.flip_h))
		animated_sprite.play("backjump" if is_backjump else "jump")
		state = STATE.JUMPING

func handle_combat_input() -> void:
	if Input.is_action_just_pressed("dodge" if IS_1P else "2p_dodge") and is_on_floor():
		start_dodge()
	if state == STATE.DODGING:
		handle_parry()

func start_dodge() -> void:
	state = STATE.DODGING
	velocity = Vector2.ZERO
	animated_sprite.play("dodge")

func handle_parry() -> void:
	var reverse_direction: StringName
	if IS_1P:
		reverse_direction = "ui_left" if animated_sprite.flip_h else "ui_right"
	else:
		reverse_direction = "2p_left" if animated_sprite.flip_h else "2p_right"
	print(reverse_direction)
	if Input.is_action_just_pressed(reverse_direction):
		animated_sprite.play("parry")
		state = STATE.PARRYING
	elif Input.is_action_just_released(reverse_direction):
		state = STATE.DODGING
	

func handle_parrying_finish() -> void:
	if Input.get_axis("ui_left" if IS_1P else "2p_left", "ui_right" if IS_1P else "2p_right") == 0:
		state = STATE.DODGING

func handle_dodge_finish() -> void:
	if Input.is_action_just_released("dodge" if IS_1P else "2p_dodge"):
		state = STATE.IDLE

func handle_knockback(delta: float) -> void:
	velocity = knockback_direction * KNOCKBACK_FORCE
	velocity.y += get_gravity().y * delta

func apply_knockback(direction: Vector2) -> void:
	if state != STATE.KNOCKBACK:
		state = STATE.KNOCKBACK
		knockback_direction = direction.normalized()
		animated_sprite.play("backward")

func update_animation_state() -> void:
	if state in [STATE.DODGING, STATE.PARRYING, STATE.KNOCKBACK, STATE.JUMPING, STATE.LANDING]:
		return
	
	if not is_on_floor():
		if animated_sprite.animation != "floating":
			animated_sprite.play("floating")
	else:
		if velocity.x == 0:
			animated_sprite.play("idle")
		else:
			animated_sprite.play("forward")

func _on_animation_finished() -> void:
	match animated_sprite.animation:
		"jump", "backjump":
			if not is_on_floor():
				animated_sprite.play("floating")
		"dodge":
			animated_sprite.pause()
		"backward":  # TODO
			if is_on_floor():
				state = STATE.IDLE
		"land":
			if Input.is_action_pressed("dodge" if IS_1P else "2p_dodge"):
				start_dodge()
			else:
				state = STATE.IDLE
