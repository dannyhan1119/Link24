extends SceneTree

const OUTPUT_PATH := "/tmp/link24_chapter_two_map.png"


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.progress.unlocked_levels["chapter_2"] = 10
	scene._set_current_chapter(1)
	scene.current_level_index = 0
	scene._show_chapter_map()
	await process_frame
	await process_frame
	var viewport_texture := root.get_viewport().get_texture()
	if viewport_texture == null:
		push_error("Visual capture requires a real rendering driver")
		scene.queue_free()
		await process_frame
		quit(1)
		return
	var image := viewport_texture.get_image()
	if image == null:
		push_error("Visual capture did not receive a viewport image")
		scene.queue_free()
		await process_frame
		quit(1)
		return
	var result := image.save_png(OUTPUT_PATH)
	if result == OK:
		print("CAPTURED: %s" % OUTPUT_PATH)
		scene.queue_free()
		await process_frame
		quit(0)
	else:
		push_error("Unable to save visual capture: %s" % error_string(result))
		scene.queue_free()
		await process_frame
		quit(1)
