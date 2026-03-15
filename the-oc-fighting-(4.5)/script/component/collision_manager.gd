extends Node
class_name CollisionManager

# 格斗游戏碰撞箱类型
enum CollisionType {
	PUSHBOX,    # 推挤箱 - 防止角色重叠
	HURTBOX,    # 受击箱 - 角色可以被攻击的区域
	HITBOX      # 攻击箱 - 角色攻击时产生伤害的区域
}

# 信号定义
signal character_hit(hitter: Node, victim: Node, damage: int)
signal characters_pushing(character1: Node, character2: Node)

# 碰撞数据结构
class CollisionData:
	var type: CollisionType
	var damage: int = 0
	var knockback_force: Vector2 = Vector2.ZERO
	var hitstun_frames: int = 0
	var blockstun_frames: int = 0
	var owner_character: Node = null
	
	func _init(collision_type: CollisionType, character_owner: Node = null):
		type = collision_type
		owner_character = character_owner

# 活跃的碰撞箱注册表
var active_hitboxes: Array[Area2D] = []
var active_hurtboxes: Array[Area2D] = []
var active_pushboxes: Array[Area2D] = []

func _ready():
	# 确保这是单例
	set_process(true)

func register_collision_box(area: Area2D, collision_data: CollisionData):
	"""注册碰撞箱到管理器"""
	area.set_meta("collision_data", collision_data)
	
	match collision_data.type:
		CollisionType.HITBOX:
			if area not in active_hitboxes:
				active_hitboxes.append(area)
				area.area_entered.connect(_on_hitbox_entered)
		CollisionType.HURTBOX:
			if area not in active_hurtboxes:
				active_hurtboxes.append(area)
		CollisionType.PUSHBOX:
			if area not in active_pushboxes:
				active_pushboxes.append(area)
				area.area_entered.connect(_on_pushbox_entered)

func unregister_collision_box(area: Area2D):
	"""从管理器注销碰撞箱"""
	if area in active_hitboxes:
		active_hitboxes.erase(area)
		area.area_entered.disconnect(_on_hitbox_entered)
	elif area in active_hurtboxes:
		active_hurtboxes.erase(area)
	elif area in active_pushboxes:
		active_pushboxes.erase(area)
		area.area_entered.disconnect(_on_pushbox_entered)

func _on_hitbox_entered(hurtbox: Area2D):
	"""处理攻击箱与受击箱的碰撞"""
	var hitbox = null
	for h in active_hitboxes:
		if h.has_overlapping_areas():
			for area in h.get_overlapping_areas():
				if area == hurtbox:
					hitbox = h
					break
	
	if not hitbox:
		return
		
	var hitbox_data = hitbox.get_meta("collision_data") as CollisionData
	var hurtbox_data = hurtbox.get_meta("collision_data") as CollisionData
	
	# 检查是否是有效攻击（不能自己打自己）
	if hitbox_data.owner_character == hurtbox_data.owner_character:
		return
	
	# 检查受击箱是否在活跃列表中
	if hurtbox not in active_hurtboxes:
		return
	
	# 发送攻击信号
	character_hit.emit(
		hitbox_data.owner_character,
		hurtbox_data.owner_character,
		hitbox_data.damage
	)
	
	# 应用击退效果
	if hurtbox_data.owner_character.has_method("apply_knockback"):
		hurtbox_data.owner_character.apply_knockback(hitbox_data.knockback_force)

func _on_pushbox_entered(other_pushbox: Area2D):
	"""处理推挤箱之间的碰撞"""
	var pushbox1 = null
	for p in active_pushboxes:
		if p.has_overlapping_areas():
			for area in p.get_overlapping_areas():
				if area == other_pushbox:
					pushbox1 = p
					break
	
	if not pushbox1:
		return
	
	var data1 = pushbox1.get_meta("collision_data") as CollisionData
	var data2 = other_pushbox.get_meta("collision_data") as CollisionData
	
	# 检查是否是不同角色的推挤箱
	if data1.owner_character != data2.owner_character:
		characters_pushing.emit(data1.owner_character, data2.owner_character)

func create_collision_data(type: CollisionType, owner: Node = null) -> CollisionData:
	"""创建碰撞数据的便捷方法"""
	return CollisionData.new(type, owner)

func set_hitbox_properties(collision_data: CollisionData, damage: int, knockback: Vector2, hitstun: int = 10):
	"""设置攻击箱属性"""
	collision_data.damage = damage
	collision_data.knockback_force = knockback
	collision_data.hitstun_frames = hitstun

func activate_hitbox(area: Area2D, duration: float = 0.1):
	"""临时激活攻击箱"""
	if area in active_hitboxes:
		return
		
	register_collision_box(area, area.get_meta("collision_data"))
	
	if duration > 0:
		await get_tree().create_timer(duration).timeout
		deactivate_hitbox(area)

func deactivate_hitbox(area: Area2D):
	"""停用攻击箱"""
	unregister_collision_box(area)

func _process(_delta):
	# 清理已被删除的碰撞箱
	active_hitboxes = active_hitboxes.filter(func(area): return is_instance_valid(area))
	active_hurtboxes = active_hurtboxes.filter(func(area): return is_instance_valid(area))
	active_pushboxes = active_pushboxes.filter(func(area): return is_instance_valid(area)) 
