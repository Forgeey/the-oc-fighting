extends Node

# 场景字典
const SCENES = {
	"main": "res://core/screen/main.tscn",
	"setting": "res://core/screen/setting.tscn",
	"arena": "res://core/screen/arena.tscn",
	"sky": "res://core/screen/sky.tscn"
}

# 信号
signal scene_changed(scene_name: String)

func change_scene(scene_name: String):
	if scene_name in SCENES:
		get_tree().change_scene_to_file(SCENES[scene_name])
		scene_changed.emit(scene_name)
		print("场景切换到: ", scene_name)
	else:
		push_error("场景不存在: " + scene_name)

func change_scene_with_loading(scene_name: String):
	if scene_name in SCENES:
		# 异步加载场景
		var scene_path = SCENES[scene_name]
		ResourceLoader.load_threaded_request(scene_path)
		
		# 等待加载完成
		_wait_for_loading(scene_path)

func _wait_for_loading(scene_path: String):
	while true:
		var progress = ResourceLoader.load_threaded_get_status(scene_path)
		
		if progress == ResourceLoader.THREAD_LOAD_LOADED:
			var scene = ResourceLoader.load_threaded_get(scene_path)
			get_tree().change_scene_to_packed(scene)
			break
		elif progress == ResourceLoader.THREAD_LOAD_FAILED:
			push_error("场景加载失败: " + scene_path)
			break
		
		await get_tree().process_frame
