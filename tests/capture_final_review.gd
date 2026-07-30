extends SceneTree

const WATCHTOWER_PATH := "/tmp/link24_final_watchtower.png"
const SETTINGS_PATH := "/tmp/link24_final_settings.png"
const HOME_PATH := "/tmp/link24_final_home.png"
const ENGLISH_PATH := "/tmp/link24_final_english.png"


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame

	scene.progress.unlocked_levels["chapter_2"] = 10
	scene._set_current_chapter(1)
	scene._load_level(0)
	scene.map_view.debug_apply_next_intended_path()
	scene.map_view.debug_apply_next_intended_path()
	scene.map_view.recenter_on_cell(Vector2i(3, 8))
	await process_frame
	await process_frame
	if _save_viewport(WATCHTOWER_PATH) != OK:
		await _finish(scene, 1)
		return

	scene._show_settings()
	await process_frame
	if _save_viewport(SETTINGS_PATH) != OK:
		await _finish(scene, 1)
		return

	scene._close_settings()
	var chapter: Dictionary = scene.chapters[1]
	for level in chapter["levels"]:
		var level_id := str(level["id"])
		scene.progress.completed_levels[level_id] = true
		scene.progress.best_days[level_id] = int(level["optimal_days"])
		scene.progress.rescued_partners[level_id] = level.get("partner_cells", []).size()
		scene.progress.explored_watchtowers[level_id] = level.get("watchtower_cells", []).size()
	scene.progress.selected_decorations["chapter_2"] = "festival_flags"
	scene.current_level_index = 9
	scene._show_chapter_map()
	scene.chapter_map_view.home_visible = true
	await process_frame
	await process_frame
	if _save_viewport(HOME_PATH) != OK:
		await _finish(scene, 1)
		return

	scene.chapter_map_view.home_visible = false
	scene._load_level(0)
	scene.settings.language = "en"
	scene._apply_feedback_settings()
	scene._show_settings()
	await process_frame
	await process_frame
	if _save_viewport(ENGLISH_PATH) != OK:
		await _finish(scene, 1)
		return

	print("CAPTURED: %s" % WATCHTOWER_PATH)
	print("CAPTURED: %s" % SETTINGS_PATH)
	print("CAPTURED: %s" % HOME_PATH)
	print("CAPTURED: %s" % ENGLISH_PATH)
	await _finish(scene, 0)


func _save_viewport(path: String) -> Error:
	var texture := root.get_viewport().get_texture()
	if texture == null:
		return ERR_UNAVAILABLE
	var image := texture.get_image()
	if image == null:
		return ERR_UNAVAILABLE
	return image.save_png(path)


func _finish(scene, exit_code: int) -> void:
	scene.queue_free()
	await process_frame
	quit(exit_code)
