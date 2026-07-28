extends SceneTree

const MapViewScene = preload("res://src/ui/map_view.gd")
const LevelCatalog = preload("res://src/model/level_catalog.gd")
const BoardModel = preload("res://src/model/board_model.gd")

var failures: Array[String] = []
var assertions := 0


func _initialize() -> void:
	var map_view: MigrationMapView = MapViewScene.new()
	map_view.size = Vector2(1000, 1180)
	root.add_child(map_view)

	var playable := LevelCatalog.playable_levels()
	map_view.load_level(playable[0])
	_expect(not map_view.dead_end, "playable map does not start in a dead end")
	_expect(map_view.tutorial_step == 0, "first playable map starts the inline tutorial")
	_expect(map_view.board.days == 0, "playable map starts at day zero")
	var desert_rects := map_view._desert_background_rects()
	_expect(desert_rects.size() == 3, "desert art extends above and below the board")
	_expect(desert_rects[0].end.y == desert_rects[1].position.y, "upper desert art meets the board")
	_expect(desert_rects[1].end.y == desert_rects[2].position.y, "lower desert art meets the board")
	_expect(
		desert_rects[0].position.y <= map_view._world_bounds().position.y
		and desert_rects[2].end.y >= map_view._world_bounds().end.y,
		"desert art covers the complete pan range including both oases"
	)
	map_view.debug_apply_next_intended_path()
	_expect(map_view.board.days == 1, "opening a path advances one day")
	_expect(map_view.tutorial_step == 2, "tutorial advances after the first opened road")
	_expect(map_view.previous_board != null, "opening a path stores one undo snapshot")
	_expect(map_view.recent_open_path.size() == 3, "opening keeps the three changed cells for animation")
	_expect(
		map_view.recent_open_values.size() == map_view.recent_open_path.size(),
		"opening animation keeps one original value for every changed cell"
	)
	var animated_value_total := 0
	for value in map_view.recent_open_values:
		animated_value_total += value
	_expect(animated_value_total == 24, "opening animation preserves the solved 24 values")
	map_view._process(0.1)
	_expect(map_view.road_bloom_progress > 0.0, "opening transition advances over time")
	_expect(not map_view.recent_open_path.is_empty(), "opening transition remains visible mid-animation")
	map_view._process(0.05)
	map_view._process(0.05)
	_expect(map_view.animal_animation_frame == 1, "moving animals advance into the left-step frame")
	_expect(
		map_view._animal_texture_for_frame(1) == map_view.TEXTURE_ANIMALS_WALK_LEFT,
		"left-step animation frame uses the generated left gait"
	)
	_expect(
		map_view._animal_texture_for_frame(3) == map_view.TEXTURE_ANIMALS_WALK_RIGHT,
		"right-step animation frame uses the generated right gait"
	)
	map_view.undo_last_opening()
	_expect(map_view.board.days == 0, "undo restores the previous day count")
	_expect(map_view.tutorial_step == 0, "undo restores the matching tutorial step")
	_expect(map_view.previous_board == null, "undo consumes the stored snapshot")
	_expect(map_view.board.has_valid_path(), "undo restores a playable frontier")
	_expect(map_view.recent_open_path.is_empty(), "undo clears the opening transition cells")
	_expect(map_view.recent_open_values.is_empty(), "undo clears the opening transition values")
	_expect(map_view.animal_animation_frame == 0, "undo returns the party to its stable standing frame")
	for index in 6:
		map_view.debug_apply_next_intended_path()
	_expect(map_view.tutorial_step == -1, "tutorial retires after the second opened road")
	_expect(map_view.completed, "final path locks gameplay while animals migrate")
	_expect(not map_view.completion_overlay_visible, "completion overlay waits for animal arrival")
	map_view._process(10.0)
	_expect(map_view.completion_overlay_visible, "completion overlay appears after animal arrival")
	_expect(map_view.animal_animation_frame == 0, "arrival returns the party to its standing frame")
	_expect(map_view.celebration_time > 0.0, "arrival starts the completion celebration")
	_expect(map_view.oasis_recovery_progress == 1.0, "arrival fully advances the oasis recovery state")
	var goal_view := map_view._cell_center(map_view.board.goal_cell) + map_view.pan_offset
	_expect(
		goal_view.y > 0.0 and goal_view.y < map_view.size.y,
		"completion camera reveals the outside-board destination"
	)
	var next_requests := [0]
	map_view.next_level_requested.connect(func() -> void: next_requests[0] += 1)
	var next_click := InputEventMouseButton.new()
	next_click.button_index = MOUSE_BUTTON_LEFT
	next_click.pressed = true
	next_click.position = map_view.completion_next_rect.get_center()
	map_view._gui_input(next_click)
	_expect(next_requests[0] == 1, "completion panel requests the next level")

	map_view.load_level(LevelCatalog.stuck_test_level())
	_expect(map_view.dead_end, "internal stuck map is detected immediately on load")
	map_view.reshuffle_dead_end_frontier()
	_expect(not map_view.dead_end, "frontier reshuffle clears the dead-end state")
	_expect(map_view.board.has_valid_path(), "frontier reshuffle creates a playable move")

	map_view.load_level(playable[7])
	_expect(map_view.board.total_partners() == 1, "level eight contains one optional partner")
	_expect(int(map_view.level_data["fog_radius"]) == 2, "level eight introduces thin exploration fog")
	_expect(
		map_view._cell_is_revealed(map_view.board.start_cell),
		"the start remains visible through exploration fog"
	)
	_expect(
		map_view._cell_is_revealed(map_view.board.find_valid_path()[0]),
		"every currently playable frontier remains visible"
	)
	_expect(
		not map_view._cell_is_revealed(Vector2i(7, 0)),
		"distant numbers begin hidden by exploration fog"
	)
	var hidden_before_opening := map_view._hidden_cells().size()
	map_view.debug_apply_next_intended_path()
	_expect(
		not map_view.recently_revealed_cells.is_empty(),
		"opening a fog level records the newly revealed cells"
	)
	_expect(
		map_view._hidden_cells().size() < hidden_before_opening,
		"opening a road expands the revealed map area"
	)
	for revealed_cell in map_view.recently_revealed_cells:
		_expect(
			map_view._cell_is_revealed(revealed_cell),
			"every fading fog cell is now part of the revealed area"
		)
	map_view._process(0.25)
	_expect(map_view.fog_reveal_progress > 0.0, "fog reveal transition advances over time")
	map_view._process(2.0)
	_expect(map_view.recently_revealed_cells.is_empty(), "fog reveal transition clears after fading")
	map_view.debug_apply_branch_path()
	_expect(map_view.board.rescued_partners() == 1, "opening the optional branch rescues the partner")
	map_view.undo_last_opening()
	_expect(map_view.board.rescued_partners() == 0, "undo restores the unrescued partner state")
	_expect(map_view.recently_revealed_cells.is_empty(), "undo clears any active fog reveal transition")

	var checkpoint_updates: Array[Vector2i] = []
	map_view.checkpoints_changed.connect(
		func(visited: int, total: int) -> void:
			checkpoint_updates.append(Vector2i(visited, total))
	)
	map_view.load_level(playable[8])
	_expect(map_view.board.total_checkpoints() == 1, "level nine shows one water-stop objective")
	_expect(
		not map_view.board.checkpoint_requirements_met(),
		"the destination gate begins locked behind the water-stop objective"
	)
	for index in 3:
		map_view.debug_apply_next_intended_path()
	_expect(map_view.board.visited_checkpoints() == 0, "the water stop remains pending on approach")
	map_view.debug_apply_next_intended_path()
	_expect(map_view.board.visited_checkpoints() == 1, "opening the pond segment completes the stop")
	_expect(
		checkpoint_updates.back() == Vector2i(1, 1),
		"the HUD receives completed water-stop progress"
	)
	map_view.undo_last_opening()
	_expect(map_view.board.visited_checkpoints() == 0, "undo restores the pending water stop")
	_expect(
		checkpoint_updates.back() == Vector2i(0, 1),
		"the HUD receives restored water-stop progress after undo"
	)

	var seen_obstacle_variants := {}
	var sampled_obstacle := Vector2i(-1, -1)
	var sampled_variant := -1
	var sampled_level: Dictionary = {}
	for level in playable:
		map_view.load_level(level)
		for y in map_view.board.height:
			for x in map_view.board.width:
				var cell := Vector2i(x, y)
				if map_view.board.terrain_at(cell) != BoardModel.Terrain.BLOCKED:
					continue
				var variant := map_view._obstacle_variant(cell)
				seen_obstacle_variants[variant] = true
				if sampled_obstacle == Vector2i(-1, -1):
					sampled_obstacle = cell
					sampled_variant = variant
					sampled_level = level
	_expect(seen_obstacle_variants.size() == 3, "playable levels use all three obstacle art variants")
	map_view.load_level(sampled_level)
	_expect(
		map_view._obstacle_variant(sampled_obstacle) == sampled_variant,
		"an obstacle keeps the same visual variant within a loaded level"
	)

	if failures.is_empty():
		print("PASS: %d map-view flow assertions" % assertions)
		quit(0)
	else:
		for failure in failures:
			push_error("FAIL: %s" % failure)
		print("FAILED: %d of %d assertions" % [failures.size(), assertions])
		quit(1)


func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
