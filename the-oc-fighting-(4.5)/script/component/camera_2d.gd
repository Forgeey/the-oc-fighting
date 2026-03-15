extends Camera2D
var 角色相对位置:Vector2
var 角色相对距离:Vector2
var mob1
var mob2
var X :float
var 镜头缩放系数:float
var target_bottom_y: float = 700 #摄像机画面最底部恒定的目标y值
var screen_height: float
#var Y :float
func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	mob1 = get_parent().get_node("Player1/CharacterBody2D")
	mob2 = get_parent().get_node("Player2/CharacterBody2D")
	screen_height = get_viewport().get_visible_rect().size.y
	pass
@warning_ignore("unused_parameter")
func _physics_process(delta:float):
	角色相对位置.x = (mob1.global_position.x + mob2.global_position.x)/2
	角色相对位置.y = mob1.global_position.y/1.5
	角色相对距离.x = abs(mob1.global_position.x - mob2.global_position.x)
	X = abs(self.position.x - 角色相对位置.x)/8
	#Y = abs(self.position.y - mob.position.y)/8
	self.position.x = move_toward( self.position.x , 角色相对位置.x , X )
	if 角色相对距离.x >= 400:
		镜头缩放系数 = 1.5/(2-1/(角色相对距离.x/400))
		self.zoom = Vector2(镜头缩放系数,镜头缩放系数)
		var viewport_height_world = screen_height / 镜头缩放系数
		self.position.y = target_bottom_y - (viewport_height_world / 2.0)
	#print(self.zoom)
	pass
