extends SceneTree

const BoardModel = preload("res://src/model/board_model.gd")
const LevelCatalog = preload("res://src/model/level_catalog.gd")

var failures: Array[String] = []
var assertions := 0


func _initialize() -> void:
	var levels := LevelCatalog.all_levels()
	var playable := LevelCatalog.playable_levels()
	_expect(levels.size() == 11, "catalog contains ten chapter levels and one internal map")
	_expect(playable.size() == 10, "player catalog contains the complete first chapter")
	for index in playable.size():
		var level := playable[index]
		var label := "chapter level %d" % (index + 1)
		_expect(int(level["chapter"]) == 1, "%s belongs to chapter one" % label)
		_expect(int(level["level_index"]) == index + 1, "%s has a stable sequential index" % label)
		_expect(not str(level["lesson"]).is_empty(), "%s has a teaching purpose" % label)
		_expect(
			int(level["recommended_days"]) == level["intended_paths"].size(),
			"%s recommendation matches its authored main route" % label
		)
		_test_main_routes(level, label)
		if not level["branch_paths"].is_empty():
			_test_branch_return(level, label)
	_test_stuck_map(levels.back())
	_test_invalid_start(playable[0])
	_test_checkpoint_order(playable[8])

	if failures.is_empty():
		print("PASS: %d graybox assertions" % assertions)
		quit(0)
	else:
		for failure in failures:
			push_error("FAIL: %s" % failure)
		print("FAILED: %d of %d assertions" % [failures.size(), assertions])
		quit(1)


func _test_main_routes(level: Dictionary, label: String) -> void:
	var board := BoardModel.new()
	board.load_level(level)
	_expect(board.goal_is_outside_board(), "%s destination oasis is outside the board" % label)
	_expect(board.goal_entry_cells().size() == 1, "%s destination has exactly one board exit" % label)
	_expect(not board.goal_is_connected(), "%s starts disconnected" % label)
	if board.total_checkpoints() > 0:
		_expect(
			not board.checkpoint_requirements_met(),
			"%s starts before its required water stop" % label
		)
	var expected_days := 0
	for raw_path in level["intended_paths"]:
		var path := _typed_path(raw_path)
		expected_days += 1
		_expect(board.is_frontier(path[0]), "%s path %d starts at frontier" % [label, expected_days])
		_expect(board.path_sum(path) == 24, "%s path %d sums to 24" % [label, expected_days])
		_expect(board.path_is_valid(path), "%s path %d passes rule validation" % [label, expected_days])
		var road_route := board.road_route_to_frontier(path[0])
		_expect(not road_route.is_empty(), "%s animals can reach path %d" % [label, expected_days])
		_expect(board.apply_path(path), "%s path %d applies" % [label, expected_days])
	_expect(board.days == expected_days, "%s migration days match applied paths" % label)
	_expect(board.goal_is_connected(), "%s reaches destination" % label)
	_expect(board.level_is_complete(), "%s satisfies every required objective" % label)
	_expect(
		board.checkpoint_requirements_met(),
		"%s completes all authored water stops" % label
	)


func _test_branch_return(level: Dictionary, label: String) -> void:
	var board := BoardModel.new()
	board.load_level(level)
	var intended: Array = level["intended_paths"]
	var branch := _typed_path(level["branch_path"])
	_expect(board.path_sum(branch) == 24, "%s branch path sums to 24" % label)
	var branch_applied := false
	for index in intended.size():
		if not branch_applied and board.path_is_valid(branch):
			_expect(board.apply_path(branch), "%s optional branch applies" % label)
			branch_applied = true
		var path := _typed_path(intended[index])
		_expect(
			board.path_is_valid(path),
			"%s main route remains valid after branch at segment %d" % [label, index + 1]
		)
		_expect(
			board.apply_path(path),
			"%s main route segment %d applies after branch" % [label, index + 1]
		)
	if not branch_applied and board.path_is_valid(branch):
		_expect(board.apply_path(branch), "%s late optional branch applies" % label)
		branch_applied = true
	_expect(branch_applied, "%s branch becomes available from the connected road" % label)
	if board.total_partners() > 0:
		_expect(
			board.rescued_partners() == board.total_partners(),
			"%s optional branch rescues every authored partner" % label
		)
	_expect(board.goal_is_connected(), "%s returns from branch and reaches goal" % label)
	_expect(board.days == intended.size() + 1, "%s detour costs one migration day" % label)


func _test_stuck_map(level: Dictionary) -> void:
	var board := BoardModel.new()
	board.load_level(level)
	_expect(board.goal_is_outside_board(), "stuck map destination is outside the board")
	_expect(board.goal_entry_cells().size() == 1, "stuck map keeps one destination exit")
	_expect(board.find_valid_path().is_empty(), "stuck map has no valid frontier path")
	_expect(not board.has_valid_path(), "stuck map reports no available move")
	_expect(not board.goal_is_connected(), "stuck map does not falsely connect goal")
	_expect(board.reshuffle_frontier_for_valid_path(), "stuck map frontier can be safely reshuffled")
	var recovered_path := board.find_valid_path()
	_expect(not recovered_path.is_empty(), "reshuffle creates a valid frontier path")
	_expect(board.path_sum(recovered_path) == 24, "reshuffled frontier path sums to 24")
	_expect(board.path_is_valid(recovered_path), "reshuffled frontier path passes validation")


func _test_invalid_start(level: Dictionary) -> void:
	var board := BoardModel.new()
	board.load_level(level)
	var late_path := _typed_path(level["intended_paths"][5])
	_expect(board.path_sum(late_path) == 24, "late segment still sums to 24")
	_expect(not board.path_is_valid(late_path), "sum-24 path away from road cannot start")


func _test_checkpoint_order(level: Dictionary) -> void:
	var board := BoardModel.new()
	board.load_level(level)
	_expect(board.total_checkpoints() == 1, "level nine contains one required water stop")
	var exit_path := _typed_path(level["intended_paths"].back())
	_expect(
		board.path_violates_checkpoint_order(exit_path),
		"level-nine exit remains locked before the water stop"
	)
	var intended: Array = level["intended_paths"]
	for index in 4:
		var path := _typed_path(intended[index])
		_expect(board.apply_path(path), "level-nine approach segment %d applies" % (index + 1))
	_expect(board.visited_checkpoints() == 1, "opening the pond segment records the water stop")
	_expect(board.checkpoint_requirements_met(), "the water stop unlocks the destination gate")
	_expect(
		not board.path_violates_checkpoint_order(exit_path),
		"the exit path becomes eligible after the water stop"
	)
	var snapshot := board.duplicate_state()
	_expect(snapshot.visited_checkpoints() == 1, "undo snapshots preserve water-stop progress")


func _typed_path(raw_path: Array) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in raw_path:
		result.append(cell)
	return result


func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
