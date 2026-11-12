extends Node
## 直接验证两类问题：递归完成与退出旧活动分支，不依赖 Fighter 条件包装。
var checks := 0
var failures := 0
var events: Array[String] = []

class Leaf extends FrayState:
	var label: String
	var events: Array[String]
	var done := false
	func _init(name: String, trace: Array[String]) -> void:
		label = name
		events = trace
	func _enter_impl(_args: Dictionary) -> void:
		events.append(label + ".enter")
		done = false
	func _exit_impl() -> void:
		events.append(label + ".exit")
	func _is_done_processing_impl() -> bool:
		return done

class Group extends FrayCompoundState:
	var label: String
	var events: Array[String]
	func _init(name: String, trace: Array[String]) -> void:
		label = name
		events = trace
	func _enter_impl(args: Dictionary) -> void:
		super(args)
		events.append(label + ".enter")
	func _exit_impl() -> void:
		events.append(label + ".exit")
		super()

func _ready() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
	print("PASS: " if value else "FAIL: ", label)

func edge(mode: FrayStateMachineTransition.SwitchMode = FrayStateMachineTransition.SwitchMode.AT_END) -> FrayStateMachineTransition:
	var result := FrayStateMachineTransition.new()
	result.switch_mode = mode
	result.auto_advance = true
	return result

func _run() -> void:
	FrayInput.set_physics_process(false)
	var empty := FrayCompoundState.new()
	check(not empty.is_done_processing(), "inactive empty compound is not finished")
	var root := FrayCompoundState.new()
	var idle := Leaf.new("idle", events)
	var combo := Group.new("combo", events)
	var b := Leaf.new("B", events)
	var c := Leaf.new("C", events)
	combo.add_state(&"B", b)
	combo.add_state(&"C", c)
	combo.start_state = &"B"
	root.add_state(&"idle", idle)
	root.add_state(&"combo", combo)
	root.start_state = &"idle"
	root.add_transition(&"combo", &"idle", edge())
	combo.add_transition(&"B", &"C", edge())
	var sm := FrayStateMachine.new()
	sm.advance_mode = FrayStateMachine.AdvanceMode.MANUAL
	add_child(sm)
	sm.initialize({}, root)
	check(events == ["idle.enter"], "initialize enters actual default leaf exactly once")
	events.clear()
	root.goto(&"combo")
	check(events == ["idle.exit", "combo.enter", "B.enter"], "goto exits CURRENT idle, then enters TARGET compound and its start leaf")
	check(not combo.is_done_processing() and not root.is_done_processing(), "empty end_state recursively waits for B")
	check(not root.advance(), "parent AT_END and child AT_END both wait, without game prerequisites")
	check(root._can_switch(edge(FrayStateMachineTransition.SwitchMode.IMMEDIATE)), "IMMEDIATE still permits an authorized interrupt of unfinished group")
	b.done = true
	check(combo.is_done_processing() and root.is_done_processing(), "finished B propagates completion through all active ancestors")
	events.clear()
	check(root.advance() and root.get_active_states_info().path == "combo/C", "child AT_END continuation wins over simultaneous parent natural exit")
	check(events == ["B.exit", "C.enter"], "internal transition exits only old B, never C or retained combo")
	check(not combo.is_done_processing(), "entering unfinished C resets group completion")
	c.done = true
	root.set_condition("allowed_exit", func() -> bool: return false)
	var parent_exit := root.get_transition(&"combo", &"idle")
	parent_exit.prereqs = PackedStringArray(["allowed_exit"])
	check(combo.is_done_processing() and not root.advance(), "recursive completion does not bypass explicit parent prerequisites")
	root.set_condition("allowed_exit", func() -> bool: return true)
	parent_exit.prereqs = PackedStringArray()
	events.clear()
	check(root.advance() and root.get_current_state_name() == &"idle", "parent unconditional AT_END waits until actual C completion")
	check(events == ["C.exit", "combo.exit", "idle.enter"], "leaving compound exits leaf and group before target enter")
	check(not combo.is_done_processing(), "inactive nonpersistent compound does not report completion")
	events.clear()
	root.goto(&"combo/C")
	check(events == ["idle.exit", "combo.enter", "C.enter"], "explicit descendant path enters C, not default B")
	events.clear()
	root.goto(&"combo/C")
	check(events.is_empty(), "goto current leaf is navigation, not external reentry")
	combo.add_transition(&"C", &"C", edge(FrayStateMachineTransition.SwitchMode.IMMEDIATE))
	check(root.advance() and events == ["C.exit", "C.enter"], "external self transition correctly exits and reenters CURRENT leaf")
	combo.remove_transition(&"C", &"C")
	combo.end_state = &"C"
	check(not combo.is_done_processing(), "marked end C must itself finish, not just be entered")
	c.done = true
	check(combo.is_done_processing(), "marked end C completes only after C done")
	root.goto(&"idle")
	root.goto(&"combo/B")
	b.done = true
	check(not combo.is_done_processing(), "finished non-end B cannot complete group configured with end C")
	check(root.advance() and root.get_active_states_info().path == "combo/C", "end marker does not prevent internal progression toward C")
	check(not root.advance(), "entering configured end C still waits for its own completion")
	c.done = true
	check(root.advance() and root.get_current_state_name() == &"idle", "configured end C finishes then takes parent edge")
	# 真实嵌套组：递归完成，但不改游戏 Builder 仅支持一层组的配置边界。
	var outer := Group.new("outer", events)
	var inner := Group.new("inner", events)
	var leaf := Leaf.new("nested", events)
	inner.add_state(&"leaf", leaf)
	inner.start_state = &"leaf"
	outer.add_state(&"inner", inner)
	outer.start_state = &"inner"
	root.add_state(&"outer", outer)
	root.add_transition(&"outer", &"idle", edge())
	root.goto(&"outer")
	check(not inner.is_done_processing() and not outer.is_done_processing() and not root.is_done_processing(), "nested groups recursively block unfinished leaf")
	check(not root.advance(), "nested unfinished branch cannot exit through parent AT_END")
	leaf.done = true
	check(inner.is_done_processing() and outer.is_done_processing() and root.is_done_processing(), "nested leaf completion propagates recursively")
	events.clear()
	check(root.advance() and events == ["nested.exit", "inner.exit", "outer.exit", "idle.enter"], "nested exit order is deepest CURRENT leaf to group ancestors, then target")
	# travel 使用同一完成查询，不能绕过递归完成。
	root.goto(&"outer")
	root.travel(&"idle")
	check(not root.advance() and root.get_current_state_name() == &"outer", "travel also waits for nested child completion")
	leaf.done = true
	check(root.advance() and root.get_current_state_name() == &"idle", "travel proceeds after recursive completion")
	outer.is_persistent = true
	inner.is_persistent = true
	root.goto(&"outer")
	leaf.done = true
	root.goto(&"idle")
	check(outer.is_done_processing(), "persistent compound queries its retained child's completion")
	events.clear()
	root.goto(&"outer")
	check(events == ["idle.exit", "outer.enter", "inner.enter", "nested.enter"] and not outer.is_done_processing(), "persistent entry still reenters retained path and leaf resets progress")
	sm.free()
	print("FRAY COMPOUND LIFECYCLE TESTS: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
