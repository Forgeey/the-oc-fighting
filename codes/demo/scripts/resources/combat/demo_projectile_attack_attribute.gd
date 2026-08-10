@tool
class_name DemoProjectileAttackAttribute
extends FrayAttackAttribute

## 与 Fray 兼容的投射物攻击数据；伤害与受击反应仍来自 FrayAttackAttribute，此处只描述投射物运动。
@export var projectile_speed := 520.0
@export var projectile_lifetime := 1.25
@export var projectile_spawn_offset := Vector2(72.0, -42.0)
@export var projectile_size := Vector2(72.0, 34.0)
@export var projectile_scale := Vector2(0.42, 0.42)
