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

	var progress = ProgressStore.new()
	var playable: Array[Dictionary] = LevelCatalog.playable_levels()
	chapter_map.configure(playable, progress, 0)
	_expect(chapter_map.node_rects.size() == 10, "chapter map creates ten tappable level nodes")
	_expect(chapter_map._node_visual_state(0) == "selected", "first node begins as the current selection")
	_expect(chapter_map._node_visual_state(1) == "locked", "second node begins visually locked")
	_expect(not chapter_map._route_segment_unlocked(0), "route to a locked node begins closed")
	chapter_map._process(0.16)
	_expect(chapter_map.map_time > 0.0, "chapter-map ambient animation advances over time")

	var selected_levels: Array[int] = []
	var status_messages: Array[String] = []
	chapter_map.level_selected.connect(
		func(level_index: int) -> void: selected_levels.append(level_index)
	)
	chapter_map.status_message.connect(
		func(message: String) -> void: status_messages.append(message)
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

	progress.unlocked_level = 2
	chapter_map.configure(playable, progress, 1)
	_expect(chapter_map._node_visual_state(1) == "selected", "newly selected unlocked node is highlighted")
	_expect(chapter_map._route_segment_unlocked(0), "route opens when its destination node unlocks")
	_tap(chapter_map, chapter_map.node_positions[1])
	_expect(selected_levels == [0, 1], "an unlocked second node enters level two")

	progress.completed_levels[1] = true
	progress.best_days[1] = 5
	progress.rescued_partners[8] = 1
	chapter_map.configure(playable, progress, 1)
	_expect(progress.is_completed(1), "completed-node state is available to the chapter map")
	_expect(chapter_map._node_visual_state(0) == "completed", "completed node takes priority visually")
	_expect(chapter_map._completed_count() == 1, "chapter header counts completed nodes")
	_expect(progress.best_days_for(1) == 5, "best-day badge data is available")
	_expect(progress.partners_for(8) == 1, "partner badge data is available")

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
