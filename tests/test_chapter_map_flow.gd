extends SceneTree

const ChapterMapViewScene = preload("res://src/ui/chapter_map_view.gd")
const LevelCatalog = preload("res://src/model/level_catalog.gd")
const ProgressStore = preload("res://src/model/progress_store.gd")

var failures: Array[String] = []
var assertions := 0


func _initialize() -> void:
	var chapter_map = ChapterMapViewScene.new()
	chapter_map.size = Vector2(1080, 1920)
	root.add_child(chapter_map)

	var chapters := LevelCatalog.chapter_definitions()
	var progress = ProgressStore.new()
	progress.configure_chapters(chapters)
	progress.load_progress("/tmp/link24_chapter_map_missing_%d.cfg" % Time.get_ticks_usec())
	var chapter_one: Dictionary = chapters[0]
	var first_level_id := str(chapter_one["levels"][0]["id"])
	var eighth_level_id := str(chapter_one["levels"][7]["id"])
	chapter_map.configure(chapter_one, progress, 0)
	_expect(chapter_map.node_rects.size() == 10, "chapter map creates ten tappable level nodes")
	_expect(chapter_map._node_visual_state(0) == "selected", "first node begins as the current selection")
	_expect(chapter_map._node_visual_state(1) == "locked", "second node begins visually locked")
	_expect(not chapter_map._route_segment_unlocked(0), "route to a locked node begins closed")
	chapter_map._process(0.16)
	_expect(chapter_map.map_time > 0.0, "chapter-map ambient animation advances over time")

	var selected_levels: Array[int] = []
	var selected_chapters: Array[int] = []
	var status_messages: Array[String] = []
	chapter_map.level_selected.connect(
		func(level_index: int) -> void: selected_levels.append(level_index)
	)
	chapter_map.status_message.connect(
		func(message: String) -> void: status_messages.append(message)
	)
	chapter_map.chapter_requested.connect(
		func(chapter_index: int) -> void: selected_chapters.append(chapter_index)
	)

	_tap(chapter_map, chapter_map.node_positions[0])
	_expect(selected_levels == [0], "the first unlocked node enters level one")

	_tap(chapter_map, chapter_map.node_positions[1])
	_expect(selected_levels == [0], "a locked node cannot enter gameplay")
	_expect(status_messages.size() == 1, "a locked node explains how to unlock it")
	_expect(
		chapter_map.footer_message.contains("完成前一关"),
		"the footer keeps the locked-node guidance visible"
	)

	progress.unlocked_levels["chapter_1"] = 2
	chapter_map.configure(chapter_one, progress, 1)
	_expect(chapter_map._node_visual_state(1) == "selected", "newly selected unlocked node is highlighted")
	_expect(chapter_map._route_segment_unlocked(0), "route opens when its destination node unlocks")
	_tap(chapter_map, chapter_map.node_positions[1])
	_expect(selected_levels == [0, 1], "an unlocked second node enters level two")

	progress.completed_levels[first_level_id] = true
	progress.best_days[first_level_id] = 5
	progress.rescued_partners[eighth_level_id] = 1
	chapter_map.configure(chapter_one, progress, 1)
	_expect(progress.is_completed(first_level_id), "completed-node state is available to the chapter map")
	_expect(chapter_map._node_visual_state(0) == "completed", "completed node takes priority visually")
	_expect(chapter_map._completed_count() == 1, "chapter header counts completed nodes")
	_expect(progress.best_days_for(first_level_id) == 5, "best-day badge data is available")
	_expect(progress.partners_for(eighth_level_id) == 1, "partner badge data is available")
	_expect(progress.level_badge_count(first_level_id) == 3, "chapter node exposes all earned badge states")
	_expect(progress.chapter_badge_count("chapter_1") == 3, "chapter vitality totals completed achievements")
	_expect(progress.chapter_badge_total("chapter_1") == 30, "chapter map has a thirty-point growth target")
	_expect(progress.chapter_growth_stage("chapter_1") == 0, "early progress keeps the oasis at its waiting stage")
	_tap(chapter_map, chapter_map.home_button_rect.get_center())
	_expect(chapter_map.home_visible, "chapter map opens the interactive oasis home")
	_tap(chapter_map, chapter_map.home_close_rect.get_center())
	_expect(not chapter_map.home_visible, "oasis home closes back to the chapter route")

	_tap(chapter_map, chapter_map.next_chapter_rect.get_center())
	_expect(selected_chapters.is_empty(), "locked chapter navigation cannot leave chapter one")
	_expect(status_messages.size() == 2, "locked chapter navigation explains its requirement")
	progress.unlocked_levels["chapter_2"] = 1
	_tap(chapter_map, chapter_map.next_chapter_rect.get_center())
	_expect(selected_chapters == [1], "unlocked chapter navigation requests chapter two")

	var chapter_two: Dictionary = chapters[1]
	chapter_map.configure(chapter_two, progress, 0)
	_expect(chapter_map.current_chapter_index == 1, "chapter map accepts a second definition")
	_expect(
		int(chapter_map.levels[0]["global_index"]) == 11,
		"chapter two displays globally numbered levels"
	)
	_expect(chapter_map._node_visual_state(0) == "selected", "chapter two begins at its unlocked first node")

	if failures.is_empty():
		print("PASS: %d chapter-map flow assertions" % assertions)
		quit(0)
	else:
		for failure in failures:
			push_error("FAIL: %s" % failure)
		print("FAILED: %d of %d assertions" % [failures.size(), assertions])
		quit(1)


func _tap(chapter_map, position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = position
	chapter_map._gui_input(event)


func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
