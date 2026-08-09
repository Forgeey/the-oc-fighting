extends Control

signal confirmed
signal cancelled

const ENTER_SCALE := Vector2(0.9, 0.9)
const ANIM_IN := 0.2
const ANIM_ENTER_SCALE := 0.25
const ANIM_OUT := 0.12

@export var title_text: String = "提示":
	set(v):
		title_text = v
		_apply_texts()
@export var message_text: String = "":
	set(v):
		message_text = v
		_apply_texts()
@export var confirm_text: String = "确认":
	set(v):
		confirm_text = v
		_apply_texts()
@export var cancel_text: String = "取消":
	set(v):
		cancel_text = v
		_apply_texts()

@onready var dim: ColorRect = %Dim
@onready var panel: PanelContainer = %Panel
@onready var title_label: Label = %Title
@onready var message_label: Label = %Message
@onready var confirm_btn: Button = %ConfirmBtn
@onready var cancel_btn: Button = %CancelBtn

var _focus: int = 0
var _dismissing: bool = false


func _ready():
	panel.resized.connect(func(): panel.pivot_offset = panel.size * 0.5)
	confirm_btn.pressed.connect(func(): _dismiss(true))
	cancel_btn.pressed.connect(func(): _dismiss(false))
	_apply_texts()
	_refresh_focus()
	_play_enter.call_deferred()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		_dismiss(false)
	elif event.is_action_pressed("1p_left") or event.is_action_pressed("2p_left") \
			or event.is_action_pressed("1p_right") or event.is_action_pressed("2p_right"):
		accept_event()
		_focus = 1 - _focus
		_refresh_focus()
	elif event.is_action_pressed("ui_accept"):
		accept_event()
		_dismiss(_focus == 0)


func _apply_texts() -> void:
	if not is_node_ready():
		return
	title_label.text = title_text
	message_label.text = message_text
	confirm_btn.text = confirm_text
	cancel_btn.text = cancel_text


func _refresh_focus() -> void:
	confirm_btn.modulate = Color(1, 1, 1, 1) if _focus == 0 else Color(1, 1, 1, 0.55)
	cancel_btn.modulate = Color(1, 1, 1, 1) if _focus == 1 else Color(1, 1, 1, 0.55)


func _play_enter() -> void:
	panel.pivot_offset = panel.size * 0.5
	dim.modulate = Color(1, 1, 1, 0)
	panel.modulate = Color(1, 1, 1, 0)
	panel.scale = ENTER_SCALE
	var tween = create_tween().set_parallel(true)
	tween.tween_property(dim, "modulate:a", 1.0, ANIM_IN).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "modulate:a", 1.0, ANIM_IN).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "scale", Vector2.ONE, ANIM_ENTER_SCALE).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _dismiss(result: bool) -> void:
	if _dismissing:
		return
	_dismissing = true
	set_process_input(false)
	var tween = create_tween().set_parallel(true)
	tween.tween_property(dim, "modulate:a", 0.0, ANIM_OUT).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(panel, "modulate:a", 0.0, ANIM_OUT).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(panel, "scale", ENTER_SCALE, ANIM_OUT).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tween.finished
	if result:
		confirmed.emit()
	else:
		cancelled.emit()
	queue_free()
