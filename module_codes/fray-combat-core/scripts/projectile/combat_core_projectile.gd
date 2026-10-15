class_name CombatCoreProjectile
extends Node2D
## 使用 FrayHitState2D/FrayHitbox2D 的单次命中测试投射物。
##
## 攻击数值只来自子 FrayHitbox2D.attribute；脚本只负责 owner、移动、生命周期和去重 token。

signal combat_contact_requested(defender, hurt_hitbox: FrayHitbox2D, strike_hitbox: FrayHitbox2D)

@onready var _hit_state: FrayHitState2D = $HitState

var _owner_fighter: CombatCoreFighter
var _configured_attribute: FrayAttackAttribute
var _direction: int = 1
var _elapsed_frames: int = 0
var _consumed: bool = false
var _attack_token: StringName = &"uninitialized"


## 在加入场景前缓存 owner、方向与实际攻击资源，确保 _ready 可直接配置 Fray strike。
func setup(owner_fighter: CombatCoreFighter, direction: int, attribute: FrayAttackAttribute) -> void:
	_owner_fighter = owner_fighter
	_configured_attribute = attribute
	_direction = 1 if direction >= 0 else -1
	if _owner_fighter != null:
		_attack_token = StringName("projectile:%s:%d" % [_owner_fighter.fighter_id, get_instance_id()])


## 激活唯一 strike，并将 source 设为 projectile 自身供协调器回溯 owner。
func _ready() -> void:
	if _owner_fighter == null or _configured_attribute == null or not _configured_attribute.is_projectile:
		push_error("CombatCoreProjectile 必须在 add_child() 前调用 setup(owner, direction, attribute)。")
		queue_free()
		return
	_hit_state.set_hitbox_source(self)
	var contact_callback := Callable(self, "_on_strike_hitbox_intersected")
	if not _hit_state.hitbox_intersected.is_connected(contact_callback):
		_hit_state.hitbox_intersected.connect(contact_callback)
	for hitbox in _hit_state.get_hitboxes():
		hitbox.attribute = _configured_attribute
		hitbox.set_meta("combat_attack_token", _attack_token)
	_hit_state.activate()
	_hit_state.active_hitboxes = 1


## 在固定物理 tick 移动；owner hitstop 时同步冻结投射物。
func _physics_process(delta: float) -> void:
	if _consumed or _owner_fighter == null:
		return
	if _owner_fighter.is_in_hitstop():
		return
	_elapsed_frames += 1
	var attribute := get_attack_attribute()
	if attribute == null:
		consume_after_contact()
		return
	position.x += attribute.projectile_speed * float(_direction) * delta
	if _elapsed_frames >= maxi(attribute.duration_frames, 1):
		consume_after_contact()


## 将投射物 strike 主动检测到的对手 hurtbox 上报战斗协调器。
func _on_strike_hitbox_intersected(strike_hitbox: FrayHitbox2D, hurt_hitbox: FrayHitbox2D) -> void:
	if _consumed or strike_hitbox == null or hurt_hitbox == null:
		return
	if not (strike_hitbox.attribute is FrayAttackAttribute):
		push_error("CombatCoreProjectile 的 strike 缺少 FrayAttackAttribute。")
		return
	var defender := hurt_hitbox.source as CombatCoreFighter
	if defender == null or defender == _owner_fighter:
		return
	combat_contact_requested.emit(defender, hurt_hitbox, strike_hitbox)


## 返回实际 strike 上的唯一投射物攻击资源。
func get_attack_attribute() -> FrayAttackAttribute:
	if _hit_state == null:
		return null
	var hitboxes := _hit_state.get_hitboxes()
	if hitboxes.is_empty():
		return null
	return hitboxes[0].attribute as FrayAttackAttribute


## 返回批量命中协调器需要的实际 fighter owner。
func get_combat_owner() -> CombatCoreFighter:
	return _owner_fighter


## 返回投射物的固定飞行方向，避免 owner 转向改变本次击退方向。
func get_combat_attack_direction() -> int:
	return _direction


## 返回投射物实例级 token，保证持续重叠不会重复结算。
func get_combat_attack_token(_strike_hitbox: FrayHitbox2D) -> StringName:
	return _attack_token


## 首次合资格接触后立即关闭 Fray strike，并在安全时机释放节点。
func consume_after_contact() -> void:
	if _consumed:
		return
	_consumed = true
	_hit_state.active_hitboxes = 0
	_hit_state.deactivate()
	queue_free()
