class_name InitStateMachine
extends RefCounted

var states = {
	"idle": IdleState.new()
}
var conditions = {}
var transitions = {}
var state_tags = {}

func build_sm():
	var builder = FrayCompoundState.builder()
	
	
	

func _add_states():
	pass

func _add_transitions():
	pass
