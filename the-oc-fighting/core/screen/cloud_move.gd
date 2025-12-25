extends Parallax2D

# 云的纹理（可在编辑器中拖入多个纹理实现随机样式）
@export var cloud_textures: Array[Texture2D]
# 云的移动速度范围（像素/秒）
@export var speed_range: Vector2 = Vector2(30, 100)
# 云的生成间隔范围（秒）
@export var spawn_interval_range: Vector2 = Vector2(3, 5)
# 云的Y轴位置范围（相对于屏幕顶部）
@export var y_position_range: Vector2 = Vector2(200, 400)
# 缩放范围（例如 0.5~1.5 倍）
@export var scale_range: Vector2 = Vector2(0.5, 1.5)


var timer: Timer = Timer.new()

func _ready():
	# 初始化计时器，用于随机生成云
	add_child(timer)
	timer.wait_time = randf_range(spawn_interval_range.x, spawn_interval_range.y)
	timer.timeout.connect(_spawn_cloud)
	timer.start()

func _spawn_cloud():
	# 随机选择云纹理
	if cloud_textures.is_empty():
		return
	var cloud_texture = cloud_textures[randi() % cloud_textures.size()]
	
	# 创建云Sprite2D
	var cloud = Sprite2D.new()
	cloud.texture = cloud_texture
	cloud.position = Vector2(
		get_viewport_rect().size.x + cloud.texture.get_size().x/2,  # 从屏幕右侧外生成
		randf_range(y_position_range.x, y_position_range.y)  # 随机Y轴位置
	)
	add_child(cloud)
	
	# 随机速度（X轴向左移动，Y轴微小浮动）
	var speed = randf_range(speed_range.x, speed_range.y)
	cloud.set_meta("speed", speed)
	
	# 随机缩放、翻转
	var random_scale = randf_range(scale_range.x, scale_range.y)
	cloud.scale = Vector2(random_scale, random_scale)
	
	# 50%概率随机水平翻转
	if randf() < 0.5:
		cloud.flip_h = true
	
	# 重置计时器，下次生成云
	timer.wait_time = randf_range(spawn_interval_range.x, spawn_interval_range.y)
	timer.start()

func _process(delta):
	# 遍历所有云子节点
	for cloud in get_children():
		if cloud is Sprite2D:
			# 向左移动（X轴速度为负）
			cloud.position.x -= cloud.get_meta("speed") * delta
			
			# 当云完全移出屏幕左侧时销毁
			if cloud.position.x < -cloud.texture.get_size().x/2:
				cloud.queue_free()
