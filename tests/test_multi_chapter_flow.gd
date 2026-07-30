extends SceneTree

const MainScene = preload("res://src/main.gd")
const MapViewScene = preload("res://src/ui/map_view.gd")
const ChapterMapViewScene = preload("res://src/ui/chapter_map_view.gd")
const LevelCatalog = preload("res://src/model/level_catalog.gd")

var failures: Array[String] = []
var assertions := 0


func _initialize() -> void:
	var chapters := LevelCatalog.chapter_definitions()
	var main = _make_main_shell(chapters, "normal")
	main.size = Vector2(1200, 1920)
	main._update_safe_layout()
	_expect(main.layout_origin == Vector2(60, 0), "wide screens center the 9:16 design safely")
	_expect(main.layout_scale == 1.0, "wide screens preserve design scale when height is exact")
	_expect(
		main._to_design_position(main.layout_origin + main.pause_rect.get_center())
			== main.pause_rect.get_center(),
		"safe-layout input maps back to design coordinates"
	)
	_expect(
		main.map_view.position == Vector2(100, 370),
		"game board follows the centered safe-layout origin"
	)
	_expect(main.current_chapter_index == 0, "main flow begins in chapter one")
	_expect(main.levels.size() == 10, "main flow exposes one chapter at a time")
	main.map_view.load_level(chapters[0]["levels"][0])
	_expect(
		main._handle_game_hud_pointer(main.pause_rect.get_center()),
		"touch pause control handles the pointer"
	)
	_expect(main.settings_visible, "touch pause control opens the real settings panel")
	_expect(not main.map_view.visible, "pause panel covers and suspends the gameplay map")
	main._handle_settings_pointer(main.settings_sound_rect.get_center())
	_expect(not main.settings.sound_enabled, "settings panel toggles sound")
	_expect(not main.map_view.sound_enabled, "sound preference reaches gameplay feedback")
	main._handle_settings_pointer(main.settings_motion_rect.get_center())
	_expect(main.map_view.reduced_motion, "reduced-motion preference reaches gameplay")
	main._handle_settings_pointer(main.settings_map_rect.get_center())
	_expect(main.chapter_map_visible, "settings panel can return to the chapter map")
	_expect(not main.settings_visible, "leaving settings closes the pause panel")
	main.chapter_map_visible = false
	main.map_view.visible = true

	for level in chapters[0]["levels"]:
		main.progress.complete_level(
			str(level["id"]),
			int(level["recommended_days"]),
			0
		)
	_expect(main.progress.is_chapter_unlocked("chapter_2"), "chapter-one completion unlocks chapter two")

	main.current_chapter_index = 0
	main.current_level_index = 9
	main.chapter_complete_visible = true
	main._continue_after_chapter_complete()
	_expect(main.current_chapter_index == 1, "chapter completion advances to the next chapter")
	_expect(str(main.levels[0]["id"]) == "c2_l01", "chapter transition loads chapter-two levels")
	_expect(main.chapter_map_visible, "chapter transition opens the next chapter map")
	_expect(
		str(main.chapter_map_view.chapter["id"]) == "chapter_2",
		"chapter map receives the active chapter definition"
	)

	var preview = _make_main_shell(chapters, "preview")
	preview._set_current_chapter(1)
	preview.current_level_index = 0
	preview.preview_mode_active = true
	preview._on_level_completed(5)
	_expect(
		not preview.progress.is_completed("c2_l01"),
		"locked direct preview does not write chapter-two completion"
	)
	_free_main_shell(main)
	_free_main_shell(preview)

	if failures.is_empty():
		print("PASS: %d multi-chapter main-flow assertions" % assertions)
		quit(0)
	else:
		for failure in failures:
			push_error("FAIL: %s" % failure)
		print("FAILED: %d of %d assertions" % [failures.size(), assertions])
		quit(1)


func _make_main_shell(chapters: Array[Dictionary], suffix: String):
	var main = MainScene.new()
	main.chapters = chapters
	main.progress.configure_chapters(chapters)
	main.progress.load_progress(
		"/tmp/link24_main_flow_%s_%d.cfg" % [suffix, Time.get_ticks_usec()]
	)
	main.settings.load_settings(
		"/tmp/link24_main_settings_%s_%d.cfg" % [suffix, Time.get_ticks_usec()]
	)
	main._set_current_chapter(0)
	main.map_view = MapViewScene.new()
	main.chapter_map_view = ChapterMapViewScene.new()
	return main


func _free_main_shell(main) -> void:
	main.map_view.free()
	main.chapter_map_view.free()
	main.free()


func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
