extends SceneTree

const BoardModel = preload("res://src/model/board_model.gd")
const LevelCatalog = preload("res://src/model/level_catalog.gd")

var failures: Array[String] = []
var assertions := 0


func _initialize() -> void:
	var chapters := LevelCatalog.chapter_definitions()
	var levels := LevelCatalog.all_levels()
	var playable := LevelCatalog.playable_levels()
	_expect(chapters.size() == 2, "catalog exposes two playable chapters")
	_expect(levels.size() == 21, "catalog contains twenty story levels and one internal map")
	_expect(playable.size() == 20, "player catalog flattens both complete chapters")
	var seen_ids := {}
	for chapter_index in chapters.size():
		var chapter: Dictionary = chapters[chapter_index]
		var chapter_levels: Array = chapter["levels"]
		_expect(chapter_levels.size() == 10, "chapter %d contains ten levels" % (chapter_index + 1))
		_expect(
			int(chapter["catalog_index"]) == chapter_index,
			"chapter %d has a stable catalog index" % (chapter_index + 1)
		)
		for level_index in chapter_levels.size():
			var level: Dictionary = chapter_levels[level_index]
			var label := "chapter %d level %d" % [chapter_index + 1, level_index + 1]
			var level_id := str(level["id"])
			_expect(not seen_ids.has(level_id), "%s has a globally unique ID" % label)
			seen_ids[level_id] = true
			_expect(int(level["chapter"]) == chapter_index + 1, "%s belongs to its chapter" % label)
			_expect(
				str(level["chapter_id"]) == str(chapter["id"]),
				"%s references its stable chapter ID" % label
			)
			_expect(
				int(level["level_index"]) == level_index + 1,
				"%s has a stable local index" % label
			)
			_expect(
				int(level["global_index"]) == chapter_index * 10 + level_index + 1,
				"%s has a stable global index" % label
			)
			_expect(
				bool(level["is_chapter_final"]) == (level_index == chapter_levels.size() - 1),
				"%s records whether it closes the chapter" % label
			)
			_expect(not str(level["lesson"]).is_empty(), "%s has a teaching purpose" % label)
			_expect(
				int(level["optimal_days"]) > 0
				and int(level["recommended_days"]) == int(level["optimal_days"]) + 1,
				"%s separates exact mastery from the one-day story allowance" % label
			)
			_test_main_routes(level, label)
			if not level["branch_paths"].is_empty():
				_test_branch_return(level, label)
			if chapter_index == 1:
				_expect(
					not level.get("watchtower_cells", []).is_empty(),
					"%s includes the chapter-two watchtower rule" % label
				)
	_test_second_chapter_layouts_are_independent(chapters)
	_test_stuck_map(levels.back())
	_test_invalid_start(playable[0])
	_test_checkpoint_order(chapters[0]["levels"][8])

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
	var pending_branches: Array = []
	for raw_branch in level["branch_paths"]:
		var branch := _typed_path(raw_branch)
		_expect(board.path_sum(branch) == 24, "%s branch path sums to 24" % label)
		pending_branches.append(branch)
	var applied_branches := 0
	for index in intended.size():
		for branch_index in range(pending_branches.size() - 1, -1, -1):
			var branch: Array[Vector2i] = pending_branches[branch_index]
			if board.path_is_valid(branch):
				_expect(board.apply_path(branch), "%s optional branch applies" % label)
				pending_branches.remove_at(branch_index)
				applied_branches += 1
		var path := _typed_path(intended[index])
		_expect(
			board.path_is_valid(path),
			"%s main route remains valid after branch at segment %d" % [label, index + 1]
		)
		_expect(
			board.apply_path(path),
			"%s main route segment %d applies after branch" % [label, index + 1]
		)
	for branch_index in range(pending_branches.size() - 1, -1, -1):
		var branch: Array[Vector2i] = pending_branches[branch_index]
		if board.path_is_valid(branch):
			_expect(board.apply_path(branch), "%s late optional branch applies" % label)
			pending_branches.remove_at(branch_index)
			applied_branches += 1
	_expect(pending_branches.is_empty(), "%s every optional branch becomes reachable" % label)
	if board.total_partners() > 0:
		_expect(
			board.rescued_partners() == board.total_partners(),
			"%s optional branch rescues every authored partner" % label
		)
	if board.total_watchtowers() > 0:
		_expect(
			board.visited_watchtowers() == board.total_watchtowers(),
			"%s optional branch visits every authored watchtower" % label
		)
	_expect(board.goal_is_connected(), "%s returns from branch and reaches goal" % label)
	_expect(
		board.days == intended.size() + applied_branches,
		"%s each optional detour costs one migration day" % label
	)


func _test_stuck_map(level: Dictionary) -> void:
	var board := BoardModel.new()
	board.load_level(level)
	var numbers_before := board.numbers.duplicate()
	var terrain_before := board.terrain.duplicate()
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
	var recovered_values: Array[int] = []
	var changed_cells := 0
	for index in board.numbers.size():
		if board.numbers[index] != numbers_before[index]:
			changed_cells += 1
	for cell in recovered_path:
		recovered_values.append(board.value_at(cell))
	recovered_values.sort()
	_expect(
		recovered_values != [7, 8, 9],
		"frontier recovery no longer stamps the old fixed 7/8/9 placeholder"
	)
	_expect(
		changed_cells == recovered_path.size(),
		"frontier recovery changes only the selected unexplored chain"
	)
	_expect(board.terrain == terrain_before, "frontier recovery preserves all terrain state")


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


func _test_second_chapter_layouts_are_independent(chapters: Array[Dictionary]) -> void:
	var first_signatures := {}
	for level in chapters[0]["levels"]:
		first_signatures[_route_signature(level["intended_paths"])] = true
		first_signatures[_mirrored_route_signature(level["intended_paths"], int(level["width"]))] = true
	for level in chapters[1]["levels"]:
		_expect(
			not first_signatures.has(_route_signature(level["intended_paths"])),
			"%s is not copied or mirrored from chapter one" % str(level["id"])
		)


func _route_signature(paths: Array) -> String:
	var parts := PackedStringArray()
	for raw_path in paths:
		var cells := PackedStringArray()
		for cell in raw_path:
			cells.append("%d,%d" % [cell.x, cell.y])
		parts.append(";".join(cells))
	return "|".join(parts)


func _mirrored_route_signature(paths: Array, width: int) -> String:
	var mirrored: Array = []
	for raw_path in paths:
		var path: Array[Vector2i] = []
		for cell in raw_path:
			path.append(Vector2i(width - 1 - cell.x, cell.y))
		mirrored.append(path)
	return _route_signature(mirrored)


func _typed_path(raw_path: Array) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in raw_path:
		result.append(cell)
	return result


func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
