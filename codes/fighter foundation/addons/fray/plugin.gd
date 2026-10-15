@tool
extends EditorPlugin
## Fray 编辑器插件入口。
##
## Autoload 仅随插件启用/禁用而增删，不在编辑器整体退出的 `_exit_tree()` 阶段修改
## ProjectSettings，避免关闭流程中的保存窗口与插件清理发生竞态。

const AUTOLOADS := {
	"FrayInputMap": "res://addons/fray/src/input/autoloads/fray_input_map.gd",
	"FrayInput": "res://addons/fray/src/input/autoloads/fray_input.gd",
}


## 插件启用时补齐 Fray Autoload；已有配置保持不变，避免重复注册。
func _enable_plugin() -> void:
	for singleton_name in AUTOLOADS:
		var setting_name := "autoload/%s" % singleton_name
		if ProjectSettings.has_setting(setting_name):
			continue
		add_autoload_singleton(String(singleton_name), String(AUTOLOADS[singleton_name]))


## 插件被用户禁用时移除 Fray Autoload；编辑器普通退出不会调用此清理路径。
func _disable_plugin() -> void:
	for singleton_name in AUTOLOADS:
		var setting_name := "autoload/%s" % singleton_name
		if not ProjectSettings.has_setting(setting_name):
			continue
		remove_autoload_singleton(String(singleton_name))