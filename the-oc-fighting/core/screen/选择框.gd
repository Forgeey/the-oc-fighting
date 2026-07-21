extends Sprite2D

var 当前选择框: Node

var 尺寸列表 = [
	Vector2(200,68),
	Vector2(235,68),
	Vector2(260,68),
	Vector2(285,68),
	Vector2(260,68),
	Vector2(235,68),
	Vector2(200,68)
]

var 位置列表 = [
	Vector2(940,195),
	Vector2(910,245),
	Vector2(885,300),
	Vector2(860,360),
	Vector2(885,422),
	Vector2(910,478),
	Vector2(940,526)
]

var 透明度列表 = [
	"ffffff00",
	"ffffffaa",
	"ffffffc8",
	"ffffff",
	"ffffffc8",
	"ffffffaa",
	"ffffff00"
]

var 按钮列表: Array      # 7个按钮节点
var 计数器列表: Array    # 每个按钮的槽位索引 (0-6)

var 动画时长: float = 0.2  # 所有按钮统一动画时长（秒）
var _tween: Tween        # 当前运行的动画


func _ready() -> void:
	# 收集按钮节点
	按钮列表 = []
	for i in range(7):
		按钮列表.append(get_child(i))
	
	# 初始槽位: 按钮0→槽0, 按钮1→槽1, ...
	计数器列表 = [0, 1, 2, 3, 4, 5, 6]
	
	# 设置初始状态
	_apply_instant()
	
	# 入场动画：按钮从右侧依次划入淡入
	_play_entrance()


func _input(event):
	var direction = 0
	if event.is_action_pressed("1p_jump") or event.is_action_pressed("2p_jump"):
		direction = 1
	elif event.is_action_pressed("1p_dodge") or event.is_action_pressed("2p_dodge"):
		direction = -1
	
	if direction != 0:
		_shift(direction)


# 整体循环移动一个方向
func _shift(direction: int):
	# 更新计数器（循环移位）
	for i in range(7):
		计数器列表[i] = (计数器列表[i] + direction + 7) % 7
	
	# 启动Tween —— 所有按钮同时到达目标，消除"末尾按钮缓慢漂移"
	_animate_all()
	_更新当前选择框()


# 用 Tween 统一时长驱动所有按钮的动画
func _animate_all():
	if _tween and _tween.is_valid():
		_tween.kill()
	
	_tween = create_tween()
	_tween.set_parallel(true)
	
	for i in range(7):
		var btn = 按钮列表[i]
		var slot = 计数器列表[i]
		
		_tween.tween_property(btn, "position",   位置列表[slot],    动画时长).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		_tween.tween_property(btn, "size",       尺寸列表[slot],    动画时长).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		_tween.tween_property(btn, "self_modulate", Color(透明度列表[slot]), 动画时长).set_ease(Tween.EASE_OUT)


# 立刻设置所有按钮的最终状态（无动画，用于初始化）
func _apply_instant():
	for i in range(7):
		var btn = 按钮列表[i]
		var slot = 计数器列表[i]
		btn.position = 位置列表[slot]
		btn.size = 尺寸列表[slot]
		btn.self_modulate = Color(透明度列表[slot])
	
	_更新当前选择框()


# 入场动画：所有按钮从右侧依次划入淡入
func _play_entrance():
	# 先把按钮移到右侧并透明（覆盖 _apply_instant 的位置）
	for i in range(7):
		var btn = 按钮列表[i]
		var slot = 计数器列表[i]
		btn.modulate = Color(1, 1, 1, 0)
		btn.position = 位置列表[slot] + Vector2(300, 0)
	
	# 用单个Tween + PropertyTweener.set_delay 实现依次划入
	var tween = create_tween()
	tween.set_parallel(true)
	for i in range(7):
		var btn = 按钮列表[i]
		var slot = 计数器列表[i]
		tween.tween_property(btn, "position", 位置列表[slot], 0.25).set_delay(i * 0.06).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(btn, "modulate", Color(1, 1, 1, 1), 0.25).set_delay(i * 0.06).set_ease(Tween.EASE_OUT)


# 从设置页返回时：恢复按钮到正确状态并播放入场动画
func restore_and_play_entrance():
	_apply_instant()
	_play_entrance()


# 找出焦点槽位（计数器=3）的按钮，更新图标和文字颜色
func _更新当前选择框():
	for i in range(7):
		var btn = 按钮列表[i]
		if 计数器列表[i] == 3:
			当前选择框 = btn
			btn.add_theme_color_override("font_color", Color(1,1,1,0.62))
			btn.icon = load("res://asset/screen/Sprite-0004.png")
		else:
			btn.add_theme_color_override("font_color", Color(0,0,0,0.62))
			btn.icon = load("res://asset/screen/Sprite-0003.png")
