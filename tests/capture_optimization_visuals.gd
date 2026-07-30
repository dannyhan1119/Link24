extends SceneTree

const GAMEPLAY_PATH := "/tmp/link24_optimized_gameplay.png"
const COMPLETION_PATH := "/tmp/link24_optimized_completion.png"
const GROWTH_PATH := "/tmp/link24_optimized_growth.png"


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene._set_current_chapter(0)
	scene._load_level(0)
	scene.map_view.show_hint()
	scene.map_view.show_hint()
	scene.map_view.debug_apply_next_intended_path()
	scene.map_view.debug_apply_next_intended_path()
	await process_frame
	await process_frame
	if _save_viewport(GAMEPLAY_PATH) != OK:
		await _finish(scene, 1)
		return

	while not scene.map_view.completed:
		scene.map_view.debug_apply_next_intended_path()
	scene.map_view._process(10.0)
	await process_frame
	await process_frame
	if _save_viewport(COMPLETION_PATH) != OK:
		await _finish(scene, 1)
		return

	var chapter: Dictionary = scene.chapters[0]
	for level in chapter["levels"]:
		var level_id := str(level["id"])
		scene.progress.completed_levels[level_id] = true
		scene.progress.best_days[level_id] = int(level["optimal_days"])
		scene.progress.rescued_partners[level_id] = level.get("partner_cells", []).size()
	scene.current_level_index = 9
	scene._show_chapter_map()
	await process_frame
	await process_frame
	if _save_viewport(GROWTH_PATH) != OK:
		await _finish(scene, 1)
		return

	print("CAPTURED: %s" % GAMEPLAY_PATH)
	print("CAPTURED: %s" % COMPLETION_PATH)
	print("CAPTURED: %s" % GROWTH_PATH)
	await _finish(scene, 0)


func _save_viewport(path: String) -> Error:
	var viewport_texture := root.get_viewport().get_texture()
	if viewport_texture == null:
		push_error("Visual capture requires a real rendering driver")
		return ERR_UNAVAILABLE
	var image := viewport_texture.get_image()
	if image == null:
		push_error("Visual capture did not receive a viewport image")
		return ERR_UNAVAILABLE
	return image.save_png(path)


func _finish(scene, exit_code: int) -> void:
	scene.queue_free()
	await process_frame
	quit(exit_code)
