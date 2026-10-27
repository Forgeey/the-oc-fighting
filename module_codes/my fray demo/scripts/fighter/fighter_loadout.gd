class_name FighterLoadout
extends Resource
## 从公共库选择角色的基础状态和招式。

## 提供全游戏状态定义。
@export var state_library: FighterStateLibrary
## 提供全游戏招式定义。
@export var move_library: FighterMoveLibrary
## 提供全游戏转换规则。
@export var transition_library: FighterTransitionLibrary

## 选择本角色需要的基础状态路径。
@export var selected_state_paths: Array[StringName] = []
## 选择本角色装备的招式 ID。
@export var selected_move_ids: Array[StringName] = []

## 指定角色生成时进入的完整状态路径。
@export var entry_path: StringName = &"neutral/idle"
## 指定各分组默认进入的直接子状态。
@export var group_start_states: Dictionary[StringName, StringName] = {}
