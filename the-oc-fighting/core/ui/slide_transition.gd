class_name SlideTransition
extends RefCounted

## Shared position-only transitions for Controls. Direction is the direction of travel.
enum Direction {
	UP,
	DOWN,
	LEFT,
	RIGHT,
}

# Negative distance automatically moves the element beyond the viewport edge.
const DEFAULT_DISTANCE := -1.0
const DEFAULT_DURATION := 0.3
const OFFSCREEN_MARGIN := 8.0
const _REST_LAYOUT_META := &"slide_transition_rest_layout"
const _ACTIVE_TWEEN_META := &"slide_transition_active_tween"


static func slide_in(
	element: Control,
	direction: int,
	delay: float = 0.0,
	duration: float = DEFAULT_DURATION,
	distance: float = DEFAULT_DISTANCE
) -> Tween:
	var rest_position := _get_rest_position(element)
	_kill_active_tween(element)
	var start_direction := -_direction_vector(direction)
	var resolved_distance := _resolve_distance(element, rest_position, start_direction, distance)
	element.global_position = rest_position + start_direction * resolved_distance
	return _tween_to(element, rest_position, delay, duration, Tween.EASE_OUT)


static func slide_out(
	element: Control,
	direction: int,
	delay: float = 0.0,
	duration: float = DEFAULT_DURATION,
	distance: float = DEFAULT_DISTANCE
) -> Tween:
	var rest_position := _get_rest_position(element)
	_kill_active_tween(element)
	var resolved_distance := _resolve_distance(element, rest_position, _direction_vector(direction), distance)
	return _tween_to(
		element,
		rest_position + _direction_vector(direction) * resolved_distance,
		delay,
		duration,
		Tween.EASE_IN
	)


static func _get_rest_position(element: Control) -> Vector2:
	if not element.has_meta(_REST_LAYOUT_META):
		element.set_meta(_REST_LAYOUT_META, _capture_layout(element))

	var layout: Dictionary = element.get_meta(_REST_LAYOUT_META)
	var rest_position := _position_from_layout(element, layout)
	var last_target: Vector2 = layout["last_target"]
	var active_tween: Variant = element.get_meta(_ACTIVE_TWEEN_META, null)
	var tween_is_running: bool = active_tween is Tween and active_tween.is_running()
	if not tween_is_running \
			and not _positions_match(element.global_position, rest_position) \
			and not _positions_match(element.global_position, last_target):
		layout = _capture_layout(element)
		layout["last_target"] = element.global_position
		element.set_meta(_REST_LAYOUT_META, layout)
		rest_position = _position_from_layout(element, layout)
	return rest_position


static func _capture_layout(element: Control) -> Dictionary:
	return {
		"anchor_left": element.anchor_left,
		"anchor_top": element.anchor_top,
		"offset_left": element.offset_left,
		"offset_top": element.offset_top,
		"global_position": element.global_position,
		"last_target": element.global_position,
	}


static func _position_from_layout(element: Control, layout: Dictionary) -> Vector2:
	var parent := element.get_parent() as Control
	if parent == null:
		var global_position: Vector2 = layout["global_position"]
		return global_position
	var rest_local_position := Vector2(
		parent.size.x * float(layout["anchor_left"]) + float(layout["offset_left"]),
		parent.size.y * float(layout["anchor_top"]) + float(layout["offset_top"])
	)
	return parent.get_global_transform() * rest_local_position


static func _positions_match(first: Vector2, second: Vector2) -> bool:
	return first.distance_squared_to(second) <= 0.25


static func _resolve_distance(
	element: Control,
	origin_position: Vector2,
	direction: Vector2,
	requested_distance: float
) -> float:
	if requested_distance >= 0.0:
		return requested_distance

	var rect := Rect2(origin_position, element.size)
	var viewport_rect := element.get_viewport().get_visible_rect()
	var distance := 0.0
	if direction.x < 0.0:
		distance = rect.end.x - viewport_rect.position.x
	elif direction.x > 0.0:
		distance = viewport_rect.end.x - rect.position.x
	elif direction.y < 0.0:
		distance = rect.end.y - viewport_rect.position.y
	elif direction.y > 0.0:
		distance = viewport_rect.end.y - rect.position.y
	return maxf(distance + OFFSCREEN_MARGIN, OFFSCREEN_MARGIN)


static func _tween_to(
	element: Control,
	target_position: Vector2,
	delay: float,
	duration: float,
	ease_type: int
) -> Tween:
	var tween := element.create_tween()
	element.set_meta(_ACTIVE_TWEEN_META, tween)
	var layout: Dictionary = element.get_meta(_REST_LAYOUT_META)
	layout["last_target"] = target_position
	element.set_meta(_REST_LAYOUT_META, layout)
	tween.tween_property(element, "global_position", target_position, duration) \
		.set_delay(maxf(delay, 0.0)).set_ease(ease_type).set_trans(Tween.TRANS_CUBIC)
	return tween


static func _kill_active_tween(element: Control) -> void:
	if not element.has_meta(_ACTIVE_TWEEN_META):
		return

	var active_tween: Variant = element.get_meta(_ACTIVE_TWEEN_META)
	if active_tween is Tween and active_tween.is_running():
		active_tween.kill()


static func _direction_vector(direction: int) -> Vector2:
	match direction:
		Direction.UP:
			return Vector2.UP
		Direction.DOWN:
			return Vector2.DOWN
		Direction.LEFT:
			return Vector2.LEFT
		Direction.RIGHT:
			return Vector2.RIGHT
	return Vector2.ZERO
