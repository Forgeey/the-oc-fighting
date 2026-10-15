class_name CombatDebugOverlay
extends Control
## 只读战斗诊断覆盖层，显示生命、气条、Fray 状态、连段缩放、去重和最近交互。

## 战斗协调器路径。
@export_node_path("CombatCoreMatch") var combat_match_path: NodePath

var _combat_match: CombatCoreMatch
var _snapshot: Dictionary = {}


## 连接 CombatSnapshot 信号；覆盖层不持有任何写接口。
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_combat_match = get_node_or_null(combat_match_path) as CombatCoreMatch
	if _combat_match == null:
		push_error("CombatDebugOverlay 缺少 CombatCoreMatch。")
		return
	_combat_match.combat_snapshot_ready.connect(_on_combat_snapshot_ready)
	_snapshot = _combat_match.get_combat_snapshot()
	queue_redraw()


## 接收只读快照并请求重绘。
func _on_combat_snapshot_ready(snapshot: Dictionary) -> void:
	_snapshot = snapshot
	queue_redraw()


## 绘制双方状态、连段和操作说明。
func _draw() -> void:
	if _snapshot.is_empty():
		return
	var p1: Dictionary = _snapshot.get("fighter_one", {})
	var p2: Dictionary = _snapshot.get("fighter_two", {})
	_draw_fighter_panel(p1, Vector2(24, 20), Color(0.2, 0.65, 1.0, 1.0), false)
	_draw_fighter_panel(p2, Vector2(size.x - 444, 20), Color(1.0, 0.34, 0.35, 1.0), true)
	_draw_center_info()
	_draw_event_log()
	_draw_controls()


## 绘制单侧生命、气条、状态和 hitstop。
func _draw_fighter_panel(snapshot: Dictionary, origin: Vector2, accent: Color, align_right: bool) -> void:
	if snapshot.is_empty():
		return
	var panel := Rect2(origin, Vector2(420, 104))
	draw_rect(panel, Color(0.025, 0.035, 0.055, 0.88), true)
	draw_rect(panel, accent.darkened(0.25), false, 2.0)
	var health_ratio := float(snapshot.health) / maxf(float(snapshot.max_health), 1.0)
	var meter_ratio := float(snapshot.meter) / maxf(float(snapshot.max_meter), 1.0)
	var health_rect := Rect2(origin + Vector2(12, 30), Vector2(396, 22))
	var meter_rect := Rect2(origin + Vector2(12, 60), Vector2(396, 12))
	draw_rect(health_rect, Color(0.13, 0.14, 0.18, 1.0), true)
	draw_rect(Rect2(health_rect.position, Vector2(health_rect.size.x * health_ratio, health_rect.size.y)), Color(0.2, 0.9, 0.42, 1.0), true)
	draw_rect(meter_rect, Color(0.13, 0.14, 0.18, 1.0), true)
	draw_rect(Rect2(meter_rect.position, Vector2(meter_rect.size.x * meter_ratio, meter_rect.size.y)), Color(1.0, 0.72, 0.18, 1.0), true)
	var header := "%s  HP %d/%d" % [snapshot.display_name, snapshot.health, snapshot.max_health]
	var state_line := "Fray: %s | %s | 气 %d | hitstop %dF" % [snapshot.state, snapshot.action, snapshot.meter, snapshot.hitstop_frames]
	var header_width := ThemeDB.fallback_font.get_string_size(header, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	var x := origin.x + 12
	if align_right:
		x = origin.x + panel.size.x - 12 - header_width
	draw_string(ThemeDB.fallback_font, Vector2(x, origin.y + 21), header, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
	draw_string(ThemeDB.fallback_font, origin + Vector2(12, 94), state_line, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, accent.lightened(0.25))


## 绘制当前连段数、缩放、juggle 与去重计数。
func _draw_center_info() -> void:
	var combos: Dictionary = _snapshot.get("combos", {})
	var lines := PackedStringArray(["COMBAT CORE / 60 Hz"])
	for key in combos:
		var combo: Dictionary = combos[key]
		lines.append("%s→%s  %d HIT  %d DMG  %.0f%%  J%d" % [combo.attacker_id, combo.defender_id, combo.hits, combo.damage, float(combo.scale) * 100.0, combo.juggle])
	if combos.is_empty():
		lines.append("等待连段")
	lines.append("pending %d | dedupe %d" % [_snapshot.pending_contacts, _snapshot.dedupe_entries])
	var y := 28.0
	for line in lines:
		var width := ThemeDB.fallback_font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		draw_string(ThemeDB.fallback_font, Vector2((size.x - width) * 0.5, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.9, 0.94, 1.0))
		y += 20.0


## 绘制最近命中、格挡、重复过滤、juggle 拒绝和 KO 日志。
func _draw_event_log() -> void:
	var events: Array = _snapshot.get("recent_events", [])
	var origin := Vector2(24, 156)
	draw_rect(Rect2(origin - Vector2(8, 22), Vector2(470, 246)), Color(0.025, 0.035, 0.055, 0.78), true)
	draw_string(ThemeDB.fallback_font, origin, "命中日志（attribute 唯一来源）", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.75, 0.85, 1.0))
	var y := origin.y + 22.0
	for event in events:
		var line := "F%-5d %-18s %s>%s  %s" % [event.get("frame", 0), event.get("event", ""), event.get("attacker", "?"), event.get("defender", "?"), event.get("attribute_id", "missing")]
		if event.has("damage"):
			line += "  dmg=%d scale=%.0f%%" % [event.damage, float(event.get("scale", 1.0)) * 100.0]
		draw_string(ThemeDB.fallback_font, Vector2(origin.x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.82, 0.86, 0.92))
		y += 16.0


## 绘制双人按键、投射物、重置和 hitbox 开关说明。
func _draw_controls() -> void:
	var lines := [
		"P1: A/D 移动  W 跳  S 蹲  J 轻  K 中  L 重  ; 防御  后→前→J 普通波",
		"强化波: 后→前→J 后在启动 0～11F 按 ;（消耗 1 格气）；J→K→L 可拨号    P2: 训练木偶",
		"R 重置回合    Z 判定框    HUD 可观察连段缩放、juggle 与去重",
	]
	var y := size.y - 66.0
	for line in lines:
		draw_string(ThemeDB.fallback_font, Vector2(24, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.88, 0.9, 0.96))
		y += 20.0