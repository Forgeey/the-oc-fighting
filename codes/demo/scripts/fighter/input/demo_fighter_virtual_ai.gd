class_name DemoFighterVirtualAI
extends RefCounted

## 使用 FrayVirtualDevice 驱动移动并逐步执行招式指令，不绕过 Fray 输入和状态机流程。

const HELD_ACTIONS := [&"left", &"right", &"down", &"up", &"block"]

var fighter: DemoFighter
var virtual_device: FrayVirtualDevice
var pressed_inputs: Dictionary = {}

var _attack_cooldown := 0.7
var _rng := RandomNumberGenerator.new()
var _command_steps: Array = []
var _command_step_index := 0
var _command_phase := 0
var _active_command_inputs: Array[StringName] = []


## 保存运行所需依赖并完成初始化。
func setup(p_fighter: DemoFighter, controller: FrayController) -> void:
	fighter = p_fighter
	virtual_device = FrayInput.create_virtual_device()
	controller.device = virtual_device.get_id()
	_rng.randomize()


## 更新虚拟 AI 的输入决策。
func update(delta: float) -> void:
	if not fighter.ai_enabled:
		release_all()
		return

	if _advance_command():
		return

	_attack_cooldown -= delta
	_set_axis(0.0)
	_set_action(&"down", false)
	_set_action(&"block", false)

	if not fighter.is_in_neutral_state():
		return

	var distance := absf(fighter.opponent.global_position.x - fighter.global_position.x)
	var dir := signf(fighter.opponent.global_position.x - fighter.global_position.x)

	if fighter.opponent.get_current_attack() != &"" and distance < 145.0 and _rng.randf() < 0.55:
		_set_action(&"block", true)
		return

	if distance > 92.0:
		_set_axis(dir)
	elif _attack_cooldown <= 0.0:
		var entry := _pick_ground_attack()
		if entry != null:
			_start_command(entry.command)
			_advance_command()
		_attack_cooldown = _rng.randf_range(0.45, 0.9)


## 释放虚拟设备及相关运行时资源。
func dispose() -> void:
	release_all()
	virtual_device.unplug()
	virtual_device = null


## 释放虚拟设备上当前保持的全部输入。
func release_all() -> void:
	_command_steps.clear()
	_command_step_index = 0
	_command_phase = 0
	_release_active_command_inputs()
	for action in HELD_ACTIONS:
		_set_action(action, false)


## 选择地面攻击。
func _pick_ground_attack() -> DemoMoveLoadoutEntry:
	var candidates: Array[DemoMoveLoadoutEntry] = []
	for entry in fighter.move_loadout.get_installed_entries():
		if (
			entry.move.neutral_available
			and entry.move.activation_context == DemoMoveDefinition.CONTEXT_GROUND
		):
			candidates.append(entry)
	if candidates.is_empty():
		return null
	return candidates[_rng.randi_range(0, candidates.size() - 1)]


## 开始指令。
func _start_command(command: DemoMoveCommand) -> void:
	_command_steps.clear()
	_command_step_index = 0
	_command_phase = 0
	for step in command.steps:
		_command_steps.append(step.inputs.duplicate())


## 推进当前虚拟 AI 指令的一步输入。
func _advance_command() -> bool:
	if _command_steps.is_empty():
		return false
	if _command_phase == 1:
		_release_active_command_inputs()
		_command_phase = 2
		return true
	if _command_phase == 2:
		_command_phase = 0
		if _command_step_index >= _command_steps.size():
			_command_steps.clear()
			_command_step_index = 0
			return false
	if _command_step_index >= _command_steps.size():
		_command_steps.clear()
		return false
	var step_inputs: PackedStringArray = _command_steps[_command_step_index]
	_command_step_index += 1
	for input_name in step_inputs:
		var resolved := _resolve_direction_input(StringName(input_name))
		var fray_name := fighter.fray_input(resolved)
		_set_input(fray_name, true)
		_active_command_inputs.append(fray_name)
	_command_phase = 1
	return true


## 释放激活指令输入。
func _release_active_command_inputs() -> void:
	for input_name in _active_command_inputs:
		_set_input(input_name, false)
	_active_command_inputs.clear()


## 根据角色朝向把前后方向转换为左右输入。
func _resolve_direction_input(input_name: StringName) -> StringName:
	match input_name:
		&"forward":
			return &"right" if fighter.facing >= 0 else &"left"
		&"back":
			return &"left" if fighter.facing >= 0 else &"right"
		_:
			return input_name


## 将水平轴值转换为左右方向按键状态。
func _set_axis(axis: float) -> void:
	var direction := signf(axis)
	_set_action(&"left", direction < 0.0)
	_set_action(&"right", direction > 0.0)


## 设置一个语义动作的按下或释放状态。
func _set_action(action: StringName, pressed: bool) -> void:
	_set_input(fighter.fray_input(action), pressed)


## 向 Fray 虚拟设备提交输入状态变化。
func _set_input(input: StringName, pressed: bool) -> void:
	var is_pressed := pressed_inputs.has(input)
	if is_pressed == pressed:
		return

	if pressed:
		virtual_device.press(input)
		pressed_inputs[input] = true
	else:
		virtual_device.unpress(input)
		pressed_inputs.erase(input)
