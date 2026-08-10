@tool
@icon("res://addons/fray/assets/icons/buffered_input_advancer.svg")
class_name FrayBufferedInputAdvancer
extends Node
## A node designed to advance a specified state machine using buffered inputs.
##
## This node automatically feeds buffered inputs to the designated state machine to trigger state transitions.
## When an input is accepted by the state machine, the advancer stops processing new inputs for the current frame.
## Input feeding and buffer aging can be paused independently. Inputs are still collected while either pause is active.
## This allows gameplay pauses such as hitstop to freeze buffer age without changing when state transitions may consume inputs.

enum AdvanceMode {
	IDLE,  ## Advance during the idle process
	PHYSICS,  ## Advance during the physics process
}

## If [code]true[/code], the buffer does not attempt to advance by feeding inputs to the state machine.
## Enabling or disabling this property allows control over when buffered inputs are consumed.
## This can be useful for managing when a player can 'cancel' an attack using their buffered inputs.
@export var paused: bool = false

## If [code]true[/code], the gameplay clock used for buffer age does not advance.
## Inputs can still be buffered with the current frozen timestamp. Use this for hitstop or other gameplay pauses.
@export var buffer_clock_paused: bool = false

## The max gameplay time an input can exist in the buffer before it is ignored, in seconds.
@export_range(0.0, 5.0, 0.01, "suffix:sec") var max_buffer_time: float = 1.0

## Determines the process during which the advancer machine can advance the state machine and its buffer clock.
@export var advance_mode: AdvanceMode

## If [code]true[/code], component presses masked by a higher-priority Fray
## composite input are not buffered as standalone presses. This keeps raw attack
## buttons from consuming a transition before their combination/sequence event.
@export var ignore_indistinct_presses: bool = true

## Controller whose Fray input events should be buffered automatically.
var input_controller: FrayController = null

## Optional prefix used to ignore unrelated Fray inputs.
var input_filter_prefix := ""

## Optional sequence tree used to detect motion inputs before buffering them.
var sequence_tree: FraySequenceTree = null

var _state_machine: FrayStateMachine
var _input_buffer: Array[BufferedInput]
var _accepted_input_time_stamp := 0
var _has_accepted_input := false
var _buffer_clock_msec := 0.0
var _fray_input = null
var _sequence_matcher := FraySequenceMatcher.new()
var _sequence_matcher_enabled := false


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	_state_machine = get_state_machine()
	_configure_sequence_matcher()
	_connect_fray_input_listener()


func _exit_tree() -> void:
	stop_listening_to_fray_input()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	if advance_mode == AdvanceMode.IDLE:
		_tick_buffer_clock(delta)
		_advance()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	if advance_mode == AdvanceMode.PHYSICS:
		_tick_buffer_clock(delta)
		_advance()


func _get_configuration_warnings() -> PackedStringArray:
	if get_state_machine() == null:
		return ["This node is expected to be the the child of a FrayStateMachine."]
	return []


## Buffers an input press to be processed by the state machine
##
## [kbd]input[/kbd] is the name of the input.
## This is just an identifier used in input transitions.
## It is not default associated with any actions in godot or inputs in fray.
##
## If [kbd]is_presse[/kbd] is true then a pressed input is buffered, else a released input is buffered.
func buffer_press(input: StringName, is_pressed: bool = true) -> void:
	_input_buffer.append(BufferedInputPress.new(get_buffer_clock_msec(), input, is_pressed))


## Buffers an input sequence to be processed by the state machine
#
## [kbd]sequence_name[/kbd] is the name of the sequence.
## This is just an identifier used in input transitions.
## It is not default associated with any actions in godot or inputs in fray.
func buffer_sequence(sequence_name: StringName) -> void:
	_input_buffer.append(BufferedInputSequence.new(get_buffer_clock_msec(), sequence_name))


## Clears the input buffer
func clear_buffer() -> void:
	_input_buffer.clear()


## Discards the matched input and every older buffered input.
##
## The input may come from [method get_buffer], which returns the same
## RefCounted input objects in a shallow copy. Newer inputs remain available for
## follow-up cancels and dial-a-kombo strings.
func discard_buffer_through(buffered_input: BufferedInput) -> bool:
	if buffered_input == null:
		return false
	var matched_index := _input_buffer.find(buffered_input)
	if matched_index < 0:
		return false
	for _index in range(matched_index + 1):
		_input_buffer.pop_front()
	return true


## Returns a shallow copy of the current buffer.
func get_buffer() -> Array[BufferedInput]:
	return _input_buffer.duplicate()


## Returns the pause-aware gameplay clock used to timestamp and age buffered inputs.
func get_buffer_clock_msec() -> int:
	return int(_buffer_clock_msec)


## Returns the state machine this component belongs to if it exists.
func get_state_machine() -> FrayStateMachine:
	return get_parent() as FrayStateMachine


## Listens to Fray input events from the given controller and buffers matching presses.
func listen_to_fray_input(
	controller: FrayController,
	filter_prefix: String = "",
	sequences: FraySequenceTree = null
) -> void:
	input_controller = controller
	input_filter_prefix = filter_prefix
	sequence_tree = sequences
	_configure_sequence_matcher()
	_connect_fray_input_listener()


## Stops listening to Fray input events.
func stop_listening_to_fray_input() -> void:
	if _fray_input == null:
		_fray_input = get_node_or_null("/root/FrayInput")
	if _fray_input == null:
		return

	var input_callback := Callable(self, "_on_fray_input_detected")
	if _fray_input.input_detected.is_connected(input_callback):
		_fray_input.input_detected.disconnect(input_callback)


func _tick_buffer_clock(delta: float) -> void:
	if not buffer_clock_paused:
		_buffer_clock_msec += maxf(delta, 0.0) * 1000.0


func _advance() -> void:
	var current_time_stamp := get_buffer_clock_msec()
	while not _input_buffer.is_empty() and not paused:
		var buffered_input: BufferedInput = _input_buffer.pop_front()
		var is_input_within_buffer := (
			buffered_input.calc_elapsed_time_msec(current_time_stamp) <= Fray.sec_to_msec(max_buffer_time)
		)
		var accepted_input_age_sec := INF
		if _has_accepted_input:
			accepted_input_age_sec = Fray.msec_to_sec(
				current_time_stamp - _accepted_input_time_stamp
			)
		var state_machine_input := _create_state_machine_input(
			buffered_input, accepted_input_age_sec, current_time_stamp
		)

		if is_input_within_buffer and _state_machine.advance(state_machine_input):
			_accepted_input_time_stamp = current_time_stamp
			_has_accepted_input = true
			break


func _create_state_machine_input(
	buffered_input: BufferedInput,
	time_since_last_input: float,
	current_time_stamp: int
) -> Dictionary:
	if buffered_input is BufferedInputPress:
		return {
			input = buffered_input.input,
			is_pressed = buffered_input.is_pressed,
			time_since_last_input = time_since_last_input,
			time_held = buffered_input.calc_elapsed_time_msec(current_time_stamp)
		}
	elif buffered_input is BufferedInputSequence:
		return {
			sequence = buffered_input.sequence_name,
			time_since_last_input = time_since_last_input,
		}
	return {}


func _configure_sequence_matcher() -> void:
	_sequence_matcher_enabled = sequence_tree != null and not sequence_tree.get_sequence_names().is_empty()
	if not _sequence_matcher_enabled:
		return

	_sequence_matcher.initialize(sequence_tree)
	var sequence_callback := Callable(self, "_on_sequence_match_found")
	if not _sequence_matcher.match_found.is_connected(sequence_callback):
		_sequence_matcher.match_found.connect(sequence_callback)


func _connect_fray_input_listener() -> void:
	if Engine.is_editor_hint() or input_controller == null:
		return

	if _fray_input == null:
		_fray_input = get_node_or_null("/root/FrayInput")
	if _fray_input == null:
		push_error("Failed to access FrayInput singleton. Fray plugin may not be enabled.")
		return

	var input_callback := Callable(self, "_on_fray_input_detected")
	if not _fray_input.input_detected.is_connected(input_callback):
		_fray_input.input_detected.connect(input_callback)


func _on_fray_input_detected(input_event: FrayInputEvent) -> void:
	if not _accepts_fray_input_event(input_event):
		return

	if _sequence_matcher_enabled:
		_sequence_matcher.read(input_event)

	if (
		input_event.is_just_pressed()
		and (not ignore_indistinct_presses or input_event.is_distinct())
	):
		buffer_press(input_event.input, input_event.is_pressed())


func _accepts_fray_input_event(input_event: FrayInputEvent) -> bool:
	return (
		input_controller != null
		and not input_controller.disabled
		and input_event.device == input_controller.device
		and (
			input_filter_prefix.is_empty()
			or String(input_event.input).begins_with(input_filter_prefix)
		)
	)


func _on_sequence_match_found(sequence_name: StringName) -> void:
	buffer_sequence(sequence_name)


class BufferedInput:
	extends RefCounted

	var time_stamp: int

	func _init(input_time_stamp: int = 0) -> void:
		time_stamp = input_time_stamp

	func calc_elapsed_time_msec(current_time_stamp: int) -> int:
		return maxi(current_time_stamp - time_stamp, 0)


class BufferedInputPress:
	extends BufferedInput

	var input: StringName
	var is_pressed: bool

	func _init(
		input_time_stamp: int = 0, input_name: StringName = "", input_is_pressed: bool = true
	) -> void:
		super(input_time_stamp)
		input = input_name
		is_pressed = input_is_pressed


class BufferedInputSequence:
	extends BufferedInput

	var sequence_name: StringName

	func _init(input_time_stamp: int = 0, input_sequence_name: StringName = "") -> void:
		super(input_time_stamp)
		sequence_name = input_sequence_name
