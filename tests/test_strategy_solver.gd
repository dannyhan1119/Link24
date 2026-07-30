extends SceneTree

const BoardModel = preload("res://src/model/board_model.gd")
const LevelCatalog = preload("res://src/model/level_catalog.gd")
const StrategySolver = preload("res://src/model/strategy_solver.gd")

var failures: Array[String] = []
var assertions := 0


func _initialize() -> void:
	var levels := LevelCatalog.playable_levels()
	for level in levels:
		_test_level_solution(level)
	_test_safe_move_avoids_a_locally_valid_trap(levels[4])
	_test_recovery_has_a_complete_solution()

	if failures.is_empty():
		print("PASS: %d strategy-solver assertions" % assertions)
		quit(0)
	else:
		for failure in failures:
			push_error("FAIL: %s" % failure)
		print("FAILED: %d of %d assertions" % [failures.size(), assertions])
		quit(1)


func _test_level_solution(level: Dictionary) -> void:
	var board := BoardModel.new()
	board.load_level(level)
	var result := StrategySolver.find_solution(board)
	var label := str(level["id"])
	_expect(bool(result["solved"]), "%s has a globally verified solution" % label)
	_expect(bool(result["exact"]), "%s solution search does not truncate move enumeration" % label)
	var sequence: Array = result["sequence"]
	_expect(
		sequence.size() == int(level["optimal_days"]),
		"%s global solution matches exact optimal days" % label
	)
	for raw_path in sequence:
		var path := _typed_path(raw_path)
		_expect(board.path_is_valid(path), "%s safe sequence keeps every move legal" % label)
		_expect(board.apply_path(path), "%s safe sequence applies every move" % label)
	_expect(board.level_is_complete(), "%s safe sequence reaches the oasis" % label)


func _test_safe_move_avoids_a_locally_valid_trap(level: Dictionary) -> void:
	var board := BoardModel.new()
	board.load_level(level)
	var enumeration := StrategySolver.enumerate_valid_paths(board)
	var safe_paths: Array = []
	var fatal_paths: Array = []
	for raw_path in enumeration["paths"]:
		var path := _typed_path(raw_path)
		var next := board.duplicate_state()
		_expect(next.apply_path(path), "every enumerated fork move applies")
		var continuation := StrategySolver.find_solution(next)
		if bool(continuation["solved"]):
			safe_paths.append(path)
		elif bool(continuation["exhausted"]) and bool(continuation["exact"]):
			fatal_paths.append(path)
	_expect(not safe_paths.is_empty(), "trap fixture contains a globally safe move")
	_expect(not fatal_paths.is_empty(), "trap fixture contains a locally legal but fatal move")
	var advised := StrategySolver.find_winning_path(board)
	_expect(not advised.is_empty(), "strategy solver advises a move at the fork")
	_expect(_path_key(advised) in _path_keys(safe_paths), "advice chooses a globally safe move")
	_expect(_path_key(advised) not in _path_keys(fatal_paths), "advice rejects the fatal legal move")


func _test_recovery_has_a_complete_solution() -> void:
	var board := BoardModel.new()
	board.load_level(LevelCatalog.stuck_test_level())
	_expect(not board.has_valid_path(), "recovery fixture starts without a legal move")
	_expect(board.reshuffle_frontier_for_valid_path(), "recovery rewrites a real frontier chain")
	var result := StrategySolver.find_solution(board)
	_expect(bool(result["solved"]), "recovery state has a complete route to the oasis")
	for raw_path in result["sequence"]:
		_expect(board.apply_path(_typed_path(raw_path)), "verified recovery sequence applies")
	_expect(board.level_is_complete(), "verified recovery sequence reaches the oasis")


func _typed_path(raw_path) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	for cell in raw_path:
		path.append(cell)
	return path


func _path_key(path: Array[Vector2i]) -> String:
	var cells := PackedStringArray()
	for cell in path:
		cells.append("%d,%d" % [cell.x, cell.y])
	return "|".join(cells)


func _path_keys(paths: Array) -> PackedStringArray:
	var keys := PackedStringArray()
	for raw_path in paths:
		keys.append(_path_key(_typed_path(raw_path)))
	return keys


func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
