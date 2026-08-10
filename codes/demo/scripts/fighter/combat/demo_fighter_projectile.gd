class_name DemoFighterProjectile
extends Node2D

## Demo 波动攻击使用的简单 FrayHitbox2D 投射物；节点结构由场景提供，受击数据只读取命中框上的 FrayAttackAttribute。

var owner_fighter: DemoFighter
var attack: DemoProjectileAttackAttribute
var direction := 1
var lifetime := 1.0
var hit_targets: Dictionary = {}

@onready var projectile_sprite: Sprite2D = $GodotIconWave
@onready var hitbox: FrayHitbox2D = $WaveHitbox
@onready var collision_shape: CollisionShape2D = $WaveHitbox/CollisionShape2D


## 保存运行所需依赖；调用方应在节点加入场景树前完成设置。
func setup(p_owner: DemoFighter, p_attack: DemoProjectileAttackAttribute, p_direction: int) -> void:
	owner_fighter = p_owner
	attack = p_attack
	direction = 1 if p_direction >= 0 else -1
	lifetime = attack.projectile_lifetime


## 节点就绪时把攻击资源应用到场景中已有的视觉和 Fray 命中框。
func _ready() -> void:
	projectile_sprite.scale = attack.projectile_scale
	hitbox.attribute = attack
	hitbox.source = owner_fighter

	var rectangle := collision_shape.shape as RectangleShape2D
	if rectangle != null:
		rectangle.size = attack.projectile_size
	collision_shape.debug_color = attack.get_color()
	hitbox.activate()


## 每个物理帧推进投射物、处理已有重叠并在寿命结束时销毁。
func _physics_process(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()
		return

	global_position.x += float(direction) * attack.projectile_speed * delta
	_resolve_existing_overlaps()


## 解析并处理已有重叠。
func _resolve_existing_overlaps() -> void:
	for detected in hitbox.get_overlapping_hitboxes():
		_on_hitbox_entered(detected)
		if is_queued_for_deletion():
			return


## 处理投射物命中框进入事件。
func _on_hitbox_entered(detected_hitbox: FrayHitbox2D) -> void:
	if is_queued_for_deletion():
		return
	if owner_fighter.attack_module.try_resolve_contact(
		hitbox,
		detected_hitbox,
		hit_targets
	):
		queue_free()
