extends Sprite2D
var 当前选择框:Node

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

var 按钮1
var 按钮2
var 按钮3
var 按钮4
var 按钮5
var 按钮6
var 按钮7

var 按钮1尺寸
var 按钮2尺寸
var 按钮3尺寸
var 按钮4尺寸
var 按钮5尺寸
var 按钮6尺寸
var 按钮7尺寸

var 按钮1位置
var 按钮2位置
var 按钮3位置
var 按钮4位置
var 按钮5位置
var 按钮6位置
var 按钮7位置

var 按钮1可见性
var 按钮2可见性
var 按钮3可见性
var 按钮4可见性
var 按钮5可见性
var 按钮6可见性
var 按钮7可见性

var 按钮1计数器:int = 0
var 按钮2计数器:int = 1
var 按钮3计数器:int = 2
var 按钮4计数器:int = 3
var 按钮5计数器:int = 4
var 按钮6计数器:int = 5
var 按钮7计数器:int = 6

var 动画速率:float = 4

func _ready() -> void:
	
	按钮1 = get_child(0)
	按钮2 = get_child(1)
	按钮3 = get_child(2)
	按钮4 = get_child(3)
	按钮5 = get_child(4)
	按钮6 = get_child(5)
	按钮7 = get_child(6)
	
	按钮1尺寸 = 尺寸列表[0]
	按钮2尺寸 = 尺寸列表[1]
	按钮3尺寸 = 尺寸列表[2]
	按钮4尺寸 = 尺寸列表[3]
	按钮5尺寸 = 尺寸列表[4]
	按钮6尺寸 = 尺寸列表[5]
	按钮7尺寸 = 尺寸列表[6]
	
	按钮1位置 = 位置列表[0]
	按钮2位置 = 位置列表[1]
	按钮3位置 = 位置列表[2]
	按钮4位置 = 位置列表[3]
	按钮5位置 = 位置列表[4]
	按钮6位置 = 位置列表[5]
	按钮7位置 = 位置列表[6]
	
func _process(_delta: float) -> void:
	
	_change_size()
	
	_change_position()
	
	_计数器 ()
	
	_Animation()
	
	_change_visible()
	
	当前选项框方法()
	
func _计数器 ():
	if Input.is_action_just_pressed("1p_jump") or Input.is_action_just_pressed("2p_jump"):
		if 按钮1计数器 != 6 :
			按钮1计数器 = 按钮1计数器 + 1
		else:
			按钮1计数器 = 0
			
			
		if 按钮2计数器 != 6 :
			按钮2计数器 = 按钮2计数器 + 1
		else:
			按钮2计数器 = 0
			
			
		if 按钮3计数器 != 6 :
			按钮3计数器 = 按钮3计数器 + 1
		else:
			按钮3计数器 = 0
			
			
		if 按钮4计数器 != 6 :
			按钮4计数器 = 按钮4计数器 + 1
		else:
			按钮4计数器 = 0
			
			
		if 按钮5计数器 != 6 :
			按钮5计数器 = 按钮5计数器 + 1
		else:
			按钮5计数器 = 0
			
			
		if 按钮6计数器 != 6 :
			按钮6计数器 = 按钮6计数器 + 1
		else:
			按钮6计数器 = 0
			
			
		if 按钮7计数器 != 6 :
			按钮7计数器 = 按钮7计数器 + 1
		else:
			按钮7计数器 = 0
		pass
	if Input.is_action_just_pressed("1p_dodge") or Input.is_action_just_pressed("2p_dodge"):
		if 按钮1计数器 != 0 :
			按钮1计数器 = 按钮1计数器 - 1
		else:
			按钮1计数器 = 6
			
			
		if 按钮2计数器 != 0 :
			按钮2计数器 = 按钮2计数器 - 1
		else:
			按钮2计数器 = 6
			
			
		if 按钮3计数器 != 0 :
			按钮3计数器 = 按钮3计数器 - 1
		else:
			按钮3计数器 = 6
			
			
		if 按钮4计数器 != 0 :
			按钮4计数器 = 按钮4计数器 - 1
		else:
			按钮4计数器 = 6
			
			
		if 按钮5计数器 != 0 :
			按钮5计数器 = 按钮5计数器 - 1
		else:
			按钮5计数器 = 6
			
			
		if 按钮6计数器 != 0 :
			按钮6计数器 = 按钮6计数器 - 1
		else:
			按钮6计数器 = 6
			
			
		if 按钮7计数器 != 0 :
			按钮7计数器 = 按钮7计数器 - 1
		else:
			按钮7计数器 = 6
		pass
	pass
	
func _Animation ():
	按钮1.size.x = move_toward( 按钮1.size.x , 按钮1尺寸.x , 动画速率 )
	按钮1.size.y = move_toward( 按钮1.size.y , 按钮1尺寸.y , 动画速率 )
	
	按钮2.size.x = move_toward( 按钮2.size.x , 按钮2尺寸.x , 动画速率 )
	按钮2.size.y = move_toward( 按钮2.size.y , 按钮2尺寸.y , 动画速率 )
	
	按钮3.size.x = move_toward( 按钮3.size.x , 按钮3尺寸.x , 动画速率 )
	按钮3.size.y = move_toward( 按钮3.size.y , 按钮3尺寸.y , 动画速率 )
	
	按钮4.size.x = move_toward( 按钮4.size.x , 按钮4尺寸.x , 动画速率 )
	按钮4.size.y = move_toward( 按钮4.size.y , 按钮4尺寸.y , 动画速率 )
	
	按钮5.size.x = move_toward( 按钮5.size.x , 按钮5尺寸.x , 动画速率 )
	按钮5.size.y = move_toward( 按钮5.size.y , 按钮5尺寸.y , 动画速率 )
	
	按钮6.size.x = move_toward( 按钮6.size.x , 按钮6尺寸.x , 动画速率 )
	按钮6.size.y = move_toward( 按钮6.size.y , 按钮6尺寸.y , 动画速率 )
	
	按钮7.size.x = move_toward( 按钮7.size.x , 按钮7尺寸.x , 动画速率 )
	按钮7.size.y = move_toward( 按钮7.size.y , 按钮7尺寸.y , 动画速率 )
	
	
	按钮1.position.x = move_toward( 按钮1.position.x , 按钮1位置.x , 动画速率 )
	按钮1.position.y = move_toward( 按钮1.position.y , 按钮1位置.y , 动画速率 )
	
	按钮2.position.x = move_toward( 按钮2.position.x , 按钮2位置.x , 动画速率 )
	按钮2.position.y = move_toward( 按钮2.position.y , 按钮2位置.y , 动画速率 )
	
	按钮3.position.x = move_toward( 按钮3.position.x , 按钮3位置.x , 动画速率 )
	按钮3.position.y = move_toward( 按钮3.position.y , 按钮3位置.y , 动画速率 )
	
	按钮4.position.x = move_toward( 按钮4.position.x , 按钮4位置.x , 动画速率 )
	按钮4.position.y = move_toward( 按钮4.position.y , 按钮4位置.y , 动画速率 )
	
	按钮5.position.x = move_toward( 按钮5.position.x , 按钮5位置.x , 动画速率 )
	按钮5.position.y = move_toward( 按钮5.position.y , 按钮5位置.y , 动画速率 )
	
	按钮6.position.x = move_toward( 按钮6.position.x , 按钮6位置.x , 动画速率 )
	按钮6.position.y = move_toward( 按钮6.position.y , 按钮6位置.y , 动画速率 )
	
	按钮7.position.x = move_toward( 按钮7.position.x , 按钮7位置.x , 动画速率 )
	按钮7.position.y = move_toward( 按钮7.position.y , 按钮7位置.y , 动画速率 )
	
func _change_size():
	按钮1尺寸 = 尺寸列表[按钮1计数器]
	按钮2尺寸 = 尺寸列表[按钮2计数器]
	按钮3尺寸 = 尺寸列表[按钮3计数器]
	按钮4尺寸 = 尺寸列表[按钮4计数器]
	按钮5尺寸 = 尺寸列表[按钮5计数器]
	按钮6尺寸 = 尺寸列表[按钮6计数器]
	按钮7尺寸 = 尺寸列表[按钮7计数器]
	pass
	
func _change_position():
	按钮1位置 = 位置列表[按钮1计数器]
	按钮2位置 = 位置列表[按钮2计数器]
	按钮3位置 = 位置列表[按钮3计数器]
	按钮4位置 = 位置列表[按钮4计数器]
	按钮5位置 = 位置列表[按钮5计数器]
	按钮6位置 = 位置列表[按钮6计数器]
	按钮7位置 = 位置列表[按钮7计数器]
	pass
	
func _change_visible():
	按钮1.self_modulate = 透明度列表[按钮1计数器]
	按钮2.self_modulate = 透明度列表[按钮2计数器]
	按钮3.self_modulate = 透明度列表[按钮3计数器]
	按钮4.self_modulate = 透明度列表[按钮4计数器]
	按钮5.self_modulate = 透明度列表[按钮5计数器]
	按钮6.self_modulate = 透明度列表[按钮6计数器]
	按钮7.self_modulate = 透明度列表[按钮7计数器]
	pass
	
func 当前选项框方法():
	var 计数器列表 = [
		按钮1计数器,
		按钮2计数器,
		按钮3计数器,
		按钮4计数器,
		按钮5计数器,
		按钮6计数器,
		按钮7计数器,
	]
	for i in 计数器列表:
		var 其他选项框 = get("按钮"+str(i+1))
		if 计数器列表[i] == 3:
			当前选择框 = get("按钮"+str(i+1))
		if 其他选项框 != 当前选择框:
			其他选项框.add_theme_color_override("font_color", Color(0,0,0,0.62))
			其他选项框.icon = load("res://asset/screen/Sprite-0003.png")
			pass
	当前选择框.add_theme_color_override("font_color", Color(1,1,1,0.62))
	当前选择框.icon = load("res://asset/screen/Sprite-0004.png")
	pass
