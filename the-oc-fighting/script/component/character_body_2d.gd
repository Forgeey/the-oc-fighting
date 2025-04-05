extends CharacterBody2D

@export var SPEED = 300.0
@export var JUMP_VELOCITY = -400.0

enum STATE{
	IDLE,
	MOVING,
	DODGING,
	PARRYING,
}

var state := STATE.IDLE

func _ready() -> void:
	pass

func _physics_process(delta: float) -> void:
	# 重力处理
	if not is_on_floor():
		velocity += get_gravity() * delta
	
	handle_combat_actions()
	
	# 只在非防御/闪避状态允许跳跃和移动
	if state == STATE.IDLE or state == STATE.MOVING:
		handle_jump()
		handle_movement(delta)
	
	
	update_animation_state()
	
	move_and_slide()

func handle_jump():
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

func handle_movement(delta):
	var direction := Input.get_axis("ui_left", "ui_right")
	if direction:
		velocity.x = direction * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
	
	# 更新角色朝向
	if velocity.x > 0:
		$AnimatedSprite2D.flip_h = true
	elif velocity.x < 0:
		$AnimatedSprite2D.flip_h = false
		
	state = STATE.IDLE if velocity.x == 0 else STATE.MOVING 

func handle_combat_actions():
	if Input.is_action_just_pressed("dodge") and is_on_floor():
		velocity.x = 0
		state = STATE.DODGING
		$AnimatedSprite2D.play("dodge")
			
	if Input.is_action_just_released("dodge"):
		state = STATE.IDLE
	
	var direction := Input.get_axis("ui_left", "ui_right")
	if state == STATE.DODGING and (
		direction > 0 and not $AnimatedSprite2D.flip_h or 
		direction < 0 and $AnimatedSprite2D.flip_h):
			state = STATE.PARRYING
			$AnimatedSprite2D.play("parry")
	if state == STATE.PARRYING and direction == 0:
		state = STATE.DODGING
		$AnimatedSprite2D.set_animation("dodge")
		$AnimatedSprite2D.set_frame($AnimatedSprite2D.get_spirit_frames().get_frame_count("dodge")-1)

func update_animation_state():
	# 优先处理战斗动作动画
	if not (state == STATE.IDLE or state == STATE.MOVING):
		return
	
	# 常规动画状态
	if abs(velocity.x) > 0:
		$AnimatedSprite2D.play("move")
	else:
		$AnimatedSprite2D.play("idle")
