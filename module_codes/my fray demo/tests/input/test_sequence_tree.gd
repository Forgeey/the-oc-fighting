extends Node
## 仅验证 Fray 分支索引的最小修复；八次越界应保留原有错误提示。

var checks := 0
var failures := 0


func _check(value: bool, label: String) -> void:
	checks += 1
	if value:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _ready() -> void:
	var tree := FraySequenceTree.new()
	var first := FraySequenceBranch.new()
	var middle := FraySequenceBranch.new()
	var last := FraySequenceBranch.new()
	tree.add(&"test", first)
	tree.add(&"test", middle)
	tree.add(&"test", last)
	_check(tree.get_sequence_branch(&"test") == first, "default index returns first branch")
	_check(tree.get_sequence_branch(&"test", 1) == middle, "middle index returns middle branch")
	_check(tree.get_sequence_branch(&"test", 2) == last, "last valid index returns last branch")
	for index in [-1, 3, 4]:
		_check(tree.get_sequence_branch(&"test", index) == null, "invalid getter index is rejected: %d" % index)
	for index in [-1, 3, 4]:
		tree.remove_sequence_branch(&"test", index)
		_check(tree.get_sequence_branchs(&"test").size() == 3, "invalid removal preserves branches: %d" % index)
	tree.remove_sequence_branch(&"test", 0)
	_check(tree.get_sequence_branchs(&"test").size() == 2, "first valid removal reduces branch count")
	_check(tree.get_sequence_branch(&"test", 0) == middle, "first removal shifts remaining branch")
	tree.remove_sequence_branch(&"test", 1)
	_check(tree.get_sequence_branchs(&"test").size() == 1 and tree.get_sequence_branch(&"test") == middle, "last valid removal preserves first remaining branch")
	tree.remove_sequence_branch(&"test", 0)
	_check(tree.get_sequence_branchs(&"test").is_empty(), "final valid removal empties branch array")
	_check(tree.get_sequence_branch(&"test", 0) == null, "empty-array getter rejects index zero")
	tree.remove_sequence_branch(&"test", 0)
	_check(tree.get_sequence_branchs(&"test").is_empty(), "empty-array removal is rejected without mutation")
	_check(tree.get_sequence_branch(&"missing") == null, "unknown sequence still returns null")
	tree.remove_sequence_branch(&"missing", 0)
	_check(tree.get_sequence_branchs(&"missing").is_empty(), "unknown-sequence removal remains a no-op")
	print("SEQUENCE TREE TESTS: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
