class_name DemoStage
extends Node2D

## 使用项目固定操作和默认招式配置的 Demo 舞台协调器。
const FIGHTER_SCENE = preload("res://scenes/fighters/demo_fighter.tscn")
const DEFAULT_ENVIRONMENT = preload("res://resources/environment/default_fighter_environment.tres")
const DEFAULT_LOADOUT = preload("res://resources/fighters/default_fighter_loadout.tres")

@export var environment: DemoFighterEnvironment = DEFAULT_ENVIRONMENT

var player: DemoFighter
var opponent: DemoFighter
var hud: DemoHUD

@onready var fighter_root: Node2D = $TrainingStage/Fighters
@onready var camera: Camera2D = $TrainingStage/Camera2D
@onready var player_spawn: Marker2D = $TrainingStage/PlayerSpawn
@onready var opponent_spawn: Marker2D = $TrainingStage/OpponentSpawn


## 节点就绪时完成运行时初始化。
func _ready() -> void:
	_setup_fighters()
	_setup_hud()
	camera.make_current()
	_refresh_fighter_hitboxes()
	await get_tree().physics_frame
	_refresh_fighter_hitboxes()


## 每个物理帧更新角色逻辑。
func _physics_process(_delta: float) -> void:
	if FrayInput.is_just_pressed(&"restart_demo"):
		get_tree().reload_current_scene()
		return

	camera.global_position = Vector2(
		(player.global_position.x + opponent.global_position.x) * 0.5,
		270.0
	)


## 配置角色。
func _setup_fighters() -> void:
	player = FIGHTER_SCENE.instantiate() as DemoFighter
	player.name = "Player"
	player.fighter_name = "Player"
	player.input_prefix = "p1"
	player.is_player = true
	player.ai_enabled = false
	player.body_color = Color(0.25, 0.55, 1.0)
	player.sprite_modulate = Color.WHITE
	player.environment = environment
	player.move_loadout = DEFAULT_LOADOUT

	opponent = FIGHTER_SCENE.instantiate() as DemoFighter
	opponent.name = "CPU"
	opponent.fighter_name = "CPU"
	opponent.input_prefix = "cpu"
	opponent.is_player = false
	opponent.ai_enabled = false
	opponent.body_color = Color(1.0, 0.38, 0.28)
	opponent.sprite_modulate = Color(1.0, 0.82, 0.82)
	opponent.environment = environment
	opponent.move_loadout = DEFAULT_LOADOUT

	player.opponent = opponent
	opponent.opponent = player

	fighter_root.add_child(player)
	fighter_root.add_child(opponent)
	player.global_position = player_spawn.global_position
	opponent.global_position = opponent_spawn.global_position
	_refresh_fighter_hitboxes()


## 刷新角色命中框。
func _refresh_fighter_hitboxes() -> void:
	player.refresh_battle_hitboxes()
	opponent.refresh_battle_hitboxes()


## 获取 HUD 节点并绑定双方角色。
func _setup_hud() -> void:
	hud = $HUD as DemoHUD
	hud.setup(player, opponent)
