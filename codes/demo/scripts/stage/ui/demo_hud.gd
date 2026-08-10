class_name DemoHUD
extends CanvasLayer

## Demo HUD：显示生命值、当前 Fray 状态、连段数据、固定操作和从招式配置生成的招式表。
const INSTRUCTIONS := "WASD move    J light    K heavy    L special    ; block    M move list    R restart"

var player: DemoFighter
var opponent: DemoFighter

@onready var player_bar: ProgressBar = $PlayerHealthBar
@onready var opponent_bar: ProgressBar = $OpponentHealthBar
@onready var player_name_label: Label = $PlayerName
@onready var opponent_name_label: Label = $OpponentName
@onready var player_state_label: Label = $PlayerState
@onready var opponent_state_label: Label = $OpponentState
@onready var player_combo_label: Label = $PlayerCombo
@onready var opponent_combo_label: Label = $OpponentCombo
@onready var round_label: Label = $RoundLabel
@onready var move_list_panel: PanelContainer = $MoveListPanel
@onready var move_list_text: RichTextLabel = $MoveListPanel/MarginContainer/MoveListText


## 节点就绪时完成运行时初始化。
func _ready() -> void:
	player_bar.fill_mode = ProgressBar.FILL_BEGIN_TO_END
	opponent_bar.fill_mode = ProgressBar.FILL_END_TO_BEGIN
	_style_label(player_name_label, HORIZONTAL_ALIGNMENT_LEFT)
	_style_label(opponent_name_label, HORIZONTAL_ALIGNMENT_RIGHT)
	_style_label(player_state_label, HORIZONTAL_ALIGNMENT_LEFT)
	_style_label(opponent_state_label, HORIZONTAL_ALIGNMENT_RIGHT)
	_style_label(player_combo_label, HORIZONTAL_ALIGNMENT_LEFT)
	_style_label(opponent_combo_label, HORIZONTAL_ALIGNMENT_RIGHT)
	player_combo_label.add_theme_font_size_override("font_size", 22)
	opponent_combo_label.add_theme_font_size_override("font_size", 22)
	_style_label(round_label, HORIZONTAL_ALIGNMENT_CENTER)
	move_list_panel.visible = false


## 每帧更新界面和非物理逻辑。
func _process(_delta: float) -> void:
	if FrayInput.is_just_pressed(&"move_list"):
		move_list_panel.visible = not move_list_panel.visible
		if move_list_panel.visible:
			move_list_text.scroll_to_line(0)


## 保存运行所需依赖并完成初始化。
func setup(p_player: DemoFighter, p_opponent: DemoFighter) -> void:
	player = p_player
	opponent = p_opponent

	player_name_label.text = player.fighter_name.to_upper()
	opponent_name_label.text = opponent.fighter_name.to_upper()
	round_label.text = INSTRUCTIONS
	move_list_text.text = DemoMoveListFormatter.build_bbcode(player.move_loadout)

	player.health_changed.connect(_on_fighter_health_changed)
	opponent.health_changed.connect(_on_fighter_health_changed)
	player.state_machine.state_changed.connect(_on_fighter_state_machine_changed.bind(player))
	opponent.state_machine.state_changed.connect(_on_fighter_state_machine_changed.bind(opponent))
	player.knocked_out.connect(_on_fighter_knocked_out)
	opponent.knocked_out.connect(_on_fighter_knocked_out)
	player.combo_changed.connect(_on_combo_changed)
	opponent.combo_changed.connect(_on_combo_changed)
	player.combo_ended.connect(_on_combo_ended)
	opponent.combo_ended.connect(_on_combo_ended)

	player_combo_label.text = ""
	opponent_combo_label.text = ""
	_on_fighter_health_changed(player, player.health, player.max_health)
	_on_fighter_health_changed(opponent, opponent.health, opponent.max_health)
	_on_fighter_state_changed(player, player.get_current_state())
	_on_fighter_state_changed(opponent, opponent.get_current_state())


## 设置标签样式。
func _style_label(label: Label, alignment: int) -> void:
	label.horizontal_alignment = alignment
	label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.86))
	label.add_theme_font_size_override("font_size", 16)


## 角色生命值变化时刷新对应生命条。
func _on_fighter_health_changed(fighter: DemoFighter, health: int, max_health: int) -> void:
	var bar: ProgressBar = player_bar if fighter == player else opponent_bar
	bar.max_value = max_health
	bar.value = health


## 角色状态变化时刷新状态文本。
func _on_fighter_state_changed(fighter: DemoFighter, state_name: StringName) -> void:
	var label: Label = player_state_label if fighter == player else opponent_state_label
	label.text = String(state_name)


## 状态机切换时记录最近一次状态变化。
func _on_fighter_state_machine_changed(
	_from: StringName,
	to: StringName,
	fighter: DemoFighter
) -> void:
	_on_fighter_state_changed(fighter, to)


## 连段数据变化时刷新连段显示。
func _on_combo_changed(
	attacker: DemoFighter,
	_defender: DemoFighter,
	hits: int,
	total_damage: int
) -> void:
	var label := player_combo_label if attacker == player else opponent_combo_label
	label.text = "%d HITS  %d DAMAGE" % [hits, total_damage]


## 处理连段结束事件。
func _on_combo_ended(
	attacker: DemoFighter,
	_defender: DemoFighter,
	_hits: int,
	_total_damage: int
) -> void:
	var label := player_combo_label if attacker == player else opponent_combo_label
	label.text = ""


## 角色被击倒时显示胜负结果。
func _on_fighter_knocked_out(fighter: DemoFighter) -> void:
	var winner: DemoFighter = opponent if fighter == player else player
	round_label.text = "%s wins - press R to restart" % winner.fighter_name
