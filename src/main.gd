extends Control

const MapViewScene = preload("res://src/ui/map_view.gd")
const ChapterMapViewScene = preload("res://src/ui/chapter_map_view.gd")
const LevelCatalog = preload("res://src/model/level_catalog.gd")
const ProgressStore = preload("res://src/model/progress_store.gd")
const SettingsStore = preload("res://src/model/settings_store.gd")
const Localization = preload("res://src/model/localization.gd")
const TEXTURE_OASIS: Texture2D = preload("res://art/destination/destination_oasis_v3.png")
const BUTTON_RESET: Texture2D = preload("res://art/ui/button_reset_v1.png")
const BUTTON_COMPASS: Texture2D = preload("res://art/ui/button_compass_v1.png")
const BUTTON_PARTY: Texture2D = preload("res://art/ui/button_party_v1.png")
const UI_FONT: Font = preload("res://fonts/NotoSansCJKsc-Regular.otf")

const COLOR_BACKGROUND := Color("#EDF9FC")
const COLOR_PANEL := Color("#FFFFFF")
const COLOR_BORDER := Color("#83CDE8")
const COLOR_TEXT := Color("#173954")
const COLOR_SUBTEXT := Color("#4E7087")
const COLOR_CYAN := Color("#27C9DF")
const COLOR_CREAM := Color("#FFF7E7")
const COLOR_GOLD := Color("#F4B84E")
const DESIGN_SIZE := Vector2(1080, 1920)

var chapters: Array[Dictionary] = []
var levels: Array[Dictionary] = []
var current_chapter_index := 0
var current_level_index := 0
var debug_level_active := false
var preview_mode_active := false
var chapter_complete_visible := false
var chapter_map_visible := false
var map_view: MigrationMapView
var chapter_map_view
var progress := ProgressStore.new()
var settings := SettingsStore.new()
var settings_visible := false

var current_level_name := ""
var current_days := 0
var current_recommended_days := 0
var current_rescued_partners := 0
var current_total_partners := 0
var current_visited_checkpoints := 0
var current_total_checkpoints := 0
var current_visited_watchtowers := 0
var current_total_watchtowers := 0
var current_sum := 0
var current_sum_label := "从道路边缘开始"
var current_accent := COLOR_CYAN
var current_message := ""
var target_pulse_time := 0.0
var action_feedback_id := ""
var action_feedback_time := 0.0

var restart_rect := Rect2(105, 1708, 180, 145)
var undo_rect := Rect2(315, 1708, 180, 145)
var hint_rect := Rect2(525, 1708, 180, 145)
var recenter_rect := Rect2(735, 1708, 180, 145)
var level_switch_rect := Rect2(32, 28, 390, 82)
var pause_rect := Rect2(948, 30, 82, 78)
var chapter_replay_rect := Rect2(330, 1325, 420, 105)
var minimap_rect := Rect2(780, 138, 260, 220)
var settings_resume_rect := Rect2(300, 680, 480, 92)
var settings_sound_rect := Rect2(220, 820, 640, 92)
var settings_vibration_rect := Rect2(220, 930, 640, 92)
var settings_motion_rect := Rect2(220, 1040, 640, 92)
var settings_language_rect := Rect2(220, 1150, 640, 92)
var settings_map_rect := Rect2(300, 1280, 480, 92)
var layout_origin := Vector2.ZERO
var layout_scale := 1.0


func _ready() -> void:
	chapters = LevelCatalog.chapter_definitions()
	progress.configure_chapters(chapters)
	progress.load_progress()
	settings.load_settings()
	current_chapter_index = progress.latest_unlocked_chapter_index()
	_set_current_chapter(current_chapter_index)
	map_view = MapViewScene.new()
	map_view.position = Vector2(40, 370)
	map_view.size = Vector2(1000, 1180)
	map_view.status_changed.connect(_on_status_changed)
	map_view.session_changed.connect(_on_session_changed)
	map_view.objectives_changed.connect(_on_objectives_changed)
	map_view.checkpoints_changed.connect(_on_checkpoints_changed)
	map_view.watchtowers_changed.connect(_on_watchtowers_changed)
	map_view.level_completed.connect(_on_level_completed)
	map_view.next_level_requested.connect(_on_next_level_requested)
	add_child(map_view)
	_apply_feedback_settings()
	chapter_map_view = ChapterMapViewScene.new()
	chapter_map_view.position = Vector2.ZERO
	chapter_map_view.size = Vector2(1080, 1920)
	chapter_map_view.level_selected.connect(_on_chapter_level_selected)
	chapter_map_view.chapter_requested.connect(_on_chapter_requested)
	chapter_map_view.status_message.connect(_on_chapter_status_message)
	chapter_map_view.visible = false
	add_child(chapter_map_view)
	resized.connect(_update_safe_layout)
	_update_safe_layout()
	var arguments := OS.get_cmdline_user_args()
	var requested_chapter := _requested_chapter_index(arguments)
	if requested_chapter >= 0:
		_set_current_chapter(requested_chapter)
		var requested_id := str(chapters[requested_chapter]["id"])
		preview_mode_active = not progress.is_chapter_unlocked(requested_id)
	if "--debug-stuck" in arguments:
		_load_debug_stuck_level()
	elif "--play" in arguments or _has_auto_argument(arguments):
		_load_level(0)
	else:
		var chapter_id := str(chapters[current_chapter_index]["id"])
		_load_level(progress.latest_unlocked_level_index(chapter_id))
		_show_chapter_map()
	for argument in arguments:
		if argument.begins_with("--auto="):
			var count := int(argument.trim_prefix("--auto="))
			for index in count:
				map_view.debug_apply_next_intended_path()
	queue_redraw()


func _requested_chapter_index(arguments: PackedStringArray) -> int:
	for argument in arguments:
		if argument.begins_with("--chapter="):
			return clampi(
				int(argument.trim_prefix("--chapter=")) - 1,
				0,
				maxi(0, chapters.size() - 1)
			)
	return -1


func _set_current_chapter(chapter_index: int) -> void:
	current_chapter_index = clampi(chapter_index, 0, maxi(0, chapters.size() - 1))
	levels = chapters[current_chapter_index]["levels"]
	current_level_index = clampi(current_level_index, 0, maxi(0, levels.size() - 1))


func _has_auto_argument(arguments: PackedStringArray) -> bool:
	for argument in arguments:
		if argument.begins_with("--auto="):
			return true
	return false


func _process(delta: float) -> void:
	if current_sum == 24 and not chapter_map_visible and not chapter_complete_visible:
		target_pulse_time += delta
		queue_redraw()
	if action_feedback_time > 0.0:
		action_feedback_time = maxf(0.0, action_feedback_time - delta)
		if action_feedback_time == 0.0:
			action_feedback_id = ""
		queue_redraw()


func _load_level(index: int) -> void:
	debug_level_active = false
	chapter_complete_visible = false
	chapter_map_visible = false
	map_view.visible = true
	if chapter_map_view != null:
		chapter_map_view.visible = false
	current_level_index = posmod(index, levels.size())
	var level := levels[current_level_index]
	map_view.load_level(level)
	current_level_name = str(level["name"])
	current_days = 0
	current_recommended_days = int(level.get("recommended_days", 0))
	current_rescued_partners = 0
	current_total_partners = level.get("partner_cells", []).size()
	current_visited_checkpoints = 0
	current_total_checkpoints = level.get("checkpoint_cells", []).size()
	current_visited_watchtowers = 0
	current_total_watchtowers = level.get("watchtower_cells", []).size()
	current_message = str(level.get("lesson", "按住道路前沿的数字开始连线"))
	queue_redraw()


func _load_debug_stuck_level() -> void:
	debug_level_active = true
	chapter_complete_visible = false
	chapter_map_visible = false
	map_view.visible = true
	if chapter_map_view != null:
		chapter_map_view.visible = false
	map_view.load_level(LevelCatalog.stuck_test_level())
	current_level_name = "内部测试 · 无路恢复"
	current_days = 0
	current_recommended_days = 0
	current_rescued_partners = 0
	current_total_partners = 0
	current_visited_checkpoints = 0
	current_total_checkpoints = 0
	current_visited_watchtowers = 0
	current_total_watchtowers = 0
	current_message = "该地图仅用于验证自动死局检测和恢复操作"
	queue_redraw()


func _input(event: InputEvent) -> void:
	if settings_visible:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_ESCAPE or event.keycode == KEY_ENTER:
				_close_settings()
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_handle_settings_pointer(_to_design_position(event.position))
			get_viewport().set_input_as_handled()
		elif event is InputEventScreenTouch and event.pressed:
			_handle_settings_pointer(_to_design_position(event.position))
			get_viewport().set_input_as_handled()
		return
	if chapter_complete_visible:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE or event.keycode == KEY_R:
				_continue_after_chapter_complete()
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if chapter_replay_rect.has_point(_to_design_position(event.position)):
				_continue_after_chapter_complete()
			get_viewport().set_input_as_handled()
		elif event is InputEventScreenTouch and event.pressed:
			if chapter_replay_rect.has_point(_to_design_position(event.position)):
				_continue_after_chapter_complete()
			get_viewport().set_input_as_handled()
		return
	if chapter_map_visible:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode >= KEY_1 and event.keycode <= KEY_9:
				_load_level(int(event.keycode - KEY_1))
			elif event.keycode == KEY_0:
				_load_level(9)
			elif event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
				var chapter_id := str(chapters[current_chapter_index]["id"])
				_load_level(progress.latest_unlocked_level_index(chapter_id))
			elif event.keycode == KEY_F3:
				_load_debug_stuck_level()
		return
	if (
		map_view != null
		and map_view.completed
		and map_view.completion_overlay_visible
		and event is InputEventKey
		and event.pressed
		and not event.echo
		and (event.keycode == KEY_ENTER or event.keycode == KEY_SPACE)
	):
		_on_next_level_requested()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_1 and event.keycode <= KEY_9:
			_load_level(int(event.keycode - KEY_1))
		elif event.keycode == KEY_0:
			_load_level(9)
		else:
			match event.keycode:
				KEY_F3:
					_load_debug_stuck_level()
				KEY_R:
					_trigger_action_feedback("reset")
					map_view.reset_level()
				KEY_H:
					_trigger_action_feedback("hint")
					map_view.show_hint()
				KEY_C:
					_trigger_action_feedback("party")
					map_view.recenter_on_animals()
				KEY_G:
					map_view.recenter_on_goal()
				KEY_U:
					map_view.undo_last_opening()
				KEY_A:
					map_view.debug_apply_next_intended_path()
				KEY_B:
					map_view.debug_apply_branch_path()
				KEY_M, KEY_ESCAPE:
					_show_chapter_map()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var mouse_event := event as InputEventMouseButton
		var position: Vector2 = _to_design_position(mouse_event.position)
		if _handle_game_hud_pointer(position):
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch and event.pressed:
		if _handle_game_hud_pointer(_to_design_position(event.position)):
			get_viewport().set_input_as_handled()


func _to_design_position(position: Vector2) -> Vector2:
	return (position - layout_origin) / maxf(layout_scale, 0.001)


func _update_safe_layout() -> void:
	var safe_rect := Rect2(Vector2.ZERO, size)
	if OS.has_feature("mobile"):
		var window_size := Vector2(DisplayServer.window_get_size())
		var safe_pixels := DisplayServer.get_display_safe_area()
		if window_size.x > 0.0 and window_size.y > 0.0 and safe_pixels.size != Vector2i.ZERO:
			var to_local := Vector2(size.x / window_size.x, size.y / window_size.y)
			safe_rect = Rect2(
				Vector2(safe_pixels.position) * to_local,
				Vector2(safe_pixels.size) * to_local
			)
	layout_scale = minf(
		safe_rect.size.x / DESIGN_SIZE.x,
		safe_rect.size.y / DESIGN_SIZE.y
	)
	if layout_scale <= 0.0:
		layout_scale = 1.0
	layout_origin = safe_rect.position + (safe_rect.size - DESIGN_SIZE * layout_scale) * 0.5
	if map_view != null:
		map_view.position = layout_origin + Vector2(40, 370) * layout_scale
		map_view.scale = Vector2.ONE * layout_scale
		map_view.size = Vector2(1000, 1180)
	if chapter_map_view != null:
		chapter_map_view.position = layout_origin
		chapter_map_view.scale = Vector2.ONE * layout_scale
		chapter_map_view.size = DESIGN_SIZE
	queue_redraw()


func _handle_game_hud_pointer(position: Vector2) -> bool:
	if pause_rect.has_point(position):
		_show_settings()
		return true
	if minimap_rect.has_point(position):
		if map_view.board.checkpoint_requirements_met():
			map_view.recenter_on_goal()
			_on_session_changed(current_level_name, current_days, "小地图已将镜头带到目标绿洲")
		else:
			map_view.recenter_on_checkpoint()
			_on_session_changed(current_level_name, current_days, "小地图已将镜头带到途中补给水塘")
		return true
	if restart_rect.has_point(position):
		_trigger_action_feedback("reset")
		map_view.reset_level()
		return true
	if undo_rect.has_point(position):
		_trigger_action_feedback("undo")
		map_view.undo_last_opening()
		return true
	if hint_rect.has_point(position):
		_trigger_action_feedback("hint")
		map_view.show_hint()
		return true
	if recenter_rect.has_point(position):
		_trigger_action_feedback("party")
		map_view.recenter_on_animals()
		return true
	if level_switch_rect.has_point(position):
		_show_chapter_map()
		return true
	return false


func _trigger_action_feedback(action_id: String) -> void:
	action_feedback_id = action_id
	action_feedback_time = 0.22
	if settings.vibration_enabled:
		Input.vibrate_handheld(18)
	queue_redraw()


func _show_settings() -> void:
	settings_visible = true
	map_view.set_process(false)
	map_view.visible = false
	queue_redraw()


func _close_settings() -> void:
	settings_visible = false
	map_view.set_process(true)
	map_view.visible = true
	queue_redraw()


func _handle_settings_pointer(position: Vector2) -> void:
	if settings_resume_rect.has_point(position):
		_close_settings()
	elif settings_sound_rect.has_point(position):
		settings.set_sound_enabled(not settings.sound_enabled)
		_apply_feedback_settings()
	elif settings_vibration_rect.has_point(position):
		settings.set_vibration_enabled(not settings.vibration_enabled)
		_apply_feedback_settings()
	elif settings_motion_rect.has_point(position):
		settings.set_reduced_motion(not settings.reduced_motion)
		_apply_feedback_settings()
	elif settings_language_rect.has_point(position):
		settings.set_language("en" if settings.language == "zh" else "zh")
		_apply_feedback_settings()
	elif settings_map_rect.has_point(position):
		settings_visible = false
		map_view.set_process(true)
		map_view.visible = true
		_show_chapter_map()
	queue_redraw()


func _apply_feedback_settings() -> void:
	Localization.set_language(settings.language)
	if map_view != null:
		map_view.configure_feedback(
			settings.sound_enabled,
			settings.vibration_enabled,
			settings.reduced_motion
		)


func _on_status_changed(total: int, label: String, accent: Color) -> void:
	current_sum = total
	current_sum_label = label
	current_accent = accent
	if current_sum != 24:
		target_pulse_time = 0.0
	queue_redraw()


func _on_session_changed(level_name: String, days: int, message: String) -> void:
	current_level_name = level_name
	current_days = days
	current_message = message
	queue_redraw()


func _on_objectives_changed(rescued_partners: int, total_partners: int) -> void:
	current_rescued_partners = rescued_partners
	current_total_partners = total_partners
	queue_redraw()


func _on_checkpoints_changed(visited: int, total: int) -> void:
	current_visited_checkpoints = visited
	current_total_checkpoints = total
	queue_redraw()


func _on_watchtowers_changed(visited: int, total: int) -> void:
	current_visited_watchtowers = visited
	current_total_watchtowers = total
	queue_redraw()


func _on_level_completed(days: int) -> void:
	current_days = days
	if not debug_level_active and not preview_mode_active:
		var level_id := str(levels[current_level_index]["id"])
		progress.complete_level(
			level_id,
			days,
			current_rescued_partners,
			current_visited_watchtowers
		)
	current_message = "迁徙完成：动物队伍已经安全抵达新绿洲"
	queue_redraw()


func _on_next_level_requested() -> void:
	if not debug_level_active and current_level_index == levels.size() - 1:
		chapter_complete_visible = true
		map_view.visible = false
		current_message = "%s完成：新的绿洲已经恢复" % _current_chapter_label()
		queue_redraw()
	else:
		_load_level(current_level_index + 1)


func _show_chapter_map() -> void:
	debug_level_active = false
	chapter_complete_visible = false
	chapter_map_visible = true
	map_view.visible = false
	chapter_map_view.visible = true
	chapter_map_view.configure(chapters[current_chapter_index], progress, current_level_index)
	queue_redraw()


func _continue_after_chapter_complete() -> void:
	preview_mode_active = false
	if current_chapter_index + 1 < chapters.size():
		var next_chapter_id := str(chapters[current_chapter_index + 1]["id"])
		if progress.is_chapter_unlocked(next_chapter_id):
			_set_current_chapter(current_chapter_index + 1)
			current_level_index = progress.latest_unlocked_level_index(next_chapter_id)
	_show_chapter_map()


func _on_chapter_level_selected(level_index: int) -> void:
	_load_level(level_index)


func _on_chapter_requested(chapter_index: int) -> void:
	var chapter_id := str(chapters[chapter_index]["id"])
	if not progress.is_chapter_unlocked(chapter_id):
		return
	preview_mode_active = false
	_set_current_chapter(chapter_index)
	current_level_index = progress.latest_unlocked_level_index(chapter_id)
	_show_chapter_map()


func _on_chapter_status_message(_message: String) -> void:
	queue_redraw()


func _current_chapter_label() -> String:
	return "第%s章" % _chinese_chapter_number(current_chapter_index + 1)


func _chinese_chapter_number(number: int) -> String:
	var labels := ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]
	if number >= 1 and number <= labels.size():
		return labels[number - 1]
	return str(number)


func _draw() -> void:
	_draw_game_background()
	draw_set_transform(layout_origin, 0.0, Vector2.ONE * layout_scale)

	_draw_panel(
		Rect2(level_switch_rect.position + Vector2(0, 8), level_switch_rect.size),
		Color("#31515E2E"),
		Color.TRANSPARENT,
		36.0,
		0.0
	)
	_draw_panel(level_switch_rect, Color("#FFF8E9"), Color.WHITE, 36.0, 5.0)
	var level_position := "内部" if debug_level_active else "%d/%d" % [current_level_index + 1, levels.size()]
	_draw_centered_text(
		"%s  (%s)" % [current_level_name, level_position],
		level_switch_rect.get_center() + Vector2(0, 12),
		24,
		COLOR_TEXT
	)

	var day_rect := Rect2(440, 28, 180, 82)
	_draw_panel(
		Rect2(day_rect.position + Vector2(0, 8), day_rect.size),
		Color("#31515E2E"),
		Color.TRANSPARENT,
		36.0,
		0.0
	)
	_draw_panel(day_rect, Color("#FFF8E9"), Color.WHITE, 36.0, 5.0)
	_draw_centered_text("第 %d 天" % current_days, day_rect.get_center() + Vector2(0, 11), 29, COLOR_TEXT)

	var recommendation_rect := Rect2(638, 28, 265, 82)
	_draw_panel(
		Rect2(recommendation_rect.position + Vector2(0, 8), recommendation_rect.size),
		Color("#9B6A2430"),
		Color.TRANSPARENT,
		36.0,
		0.0
	)
	_draw_panel(recommendation_rect, Color("#FFF5D9"), Color.WHITE, 36.0, 5.0)
	var recommendation_label := "内部验证"
	if current_recommended_days > 0:
		recommendation_label = "推荐 ≤ %d 天" % current_recommended_days
	var objective_parts := PackedStringArray()
	if current_total_partners > 0:
		objective_parts.append("伙伴 %d/%d" % [
			current_rescued_partners,
			current_total_partners,
		])
	if current_total_checkpoints > 0:
		objective_parts.append("水塘 %d/%d" % [
			current_visited_checkpoints,
			current_total_checkpoints,
		])
	if current_total_watchtowers > 0:
		objective_parts.append("瞭望 %d/%d" % [
			current_visited_watchtowers,
			current_total_watchtowers,
		])
	var objective_label := " · ".join(objective_parts)
	if not objective_label.is_empty():
		_draw_centered_text(
			recommendation_label,
			recommendation_rect.get_center() + Vector2(0, -2),
			23,
			Color("#8C651F")
		)
		_draw_centered_text(
			objective_label,
			recommendation_rect.get_center() + Vector2(0, 27),
			17 if objective_parts.size() > 1 else 19,
			Color("#2FAE91")
		)
	else:
		_draw_centered_text(
			recommendation_label,
			recommendation_rect.get_center() + Vector2(0, 11),
			27,
			Color("#8C651F")
		)

	_draw_panel(
		Rect2(pause_rect.position + Vector2(0, 8), pause_rect.size),
		Color("#31515E2E"),
		Color.TRANSPARENT,
		36.0,
		0.0
	)
	_draw_panel(pause_rect, Color("#FFF8E9"), Color.WHITE, 36.0, 5.0)
	_draw_centered_text("Ⅱ", pause_rect.get_center() + Vector2(0, 14), 35, COLOR_TEXT)

	if map_view != null and map_view.visible and not chapter_complete_visible:
		_draw_minimap()

	var target_center := Vector2(540, 238)
	var target_ring := COLOR_GOLD if current_sum == 0 else current_accent
	var target_pulse := 0.0
	if current_sum == 24:
		target_pulse = (sin(target_pulse_time * 7.0) + 1.0) * 4.0
		draw_circle(
			target_center,
			132.0 + target_pulse,
			Color(0.45, 0.96, 1.0, 0.17),
			false,
			10.0,
			true
		)
	draw_circle(target_center + Vector2(0, 10), 120.0 + target_pulse, Color("#7A55252C"))
	draw_circle(target_center, 120.0 + target_pulse, Color.WHITE)
	draw_circle(target_center, 108.0 + target_pulse, target_ring)
	draw_circle(target_center, 96.0 + target_pulse * 0.65, COLOR_CREAM)
	_draw_centered_text("%d / 24" % current_sum, target_center + Vector2(0, 1), 48, COLOR_TEXT)
	_draw_centered_text(current_sum_label, target_center + Vector2(0, 50), 23, current_accent)

	var instruction_rect := Rect2(90, 1570, 900, 76)
	_draw_panel(instruction_rect, COLOR_PANEL, COLOR_BORDER, 30.0)
	_draw_centered_text(current_message, instruction_rect.get_center() + Vector2(0, 9), 26, COLOR_SUBTEXT)

	_draw_panel(Rect2(55, 1672, 970, 188), Color("#FFF5E5F2"), Color("#FFFFFF"), 78.0, 5.0)
	_draw_action_button(restart_rect, BUTTON_RESET, "重置", "reset", 158.0)
	_draw_undo_action_button()
	_draw_action_button(hint_rect, BUTTON_COMPASS, "分级提示", "hint", 172.0)
	_draw_action_button(recenter_rect, BUTTON_PARTY, "回到队伍", "party", 164.0)

	_draw_centered_text(
		"键盘：1–9/0 当前章节　F3 死局测试　R 重置　U 撤回　G 看绿洲　A 主路　B 支路",
		Vector2(540, 1900),
		21,
		Color("#6A8798")
	)
	if chapter_complete_visible:
		_draw_chapter_complete()
	if settings_visible:
		_draw_settings_overlay()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_settings_overlay() -> void:
	draw_rect(Rect2(Vector2.ZERO, DESIGN_SIZE), Color("#17395478"), true)
	var panel := Rect2(150, 500, 780, 900)
	_draw_panel(
		Rect2(panel.position + Vector2(0, 12), panel.size),
		Color("#24485A4A"),
		Color.TRANSPARENT,
		62.0,
		0.0
	)
	_draw_panel(panel, Color("#FFF9ECFA"), Color("#70D58D"), 62.0, 6.0)
	_draw_centered_text("暂停与设置", Vector2(540, 610), 52, COLOR_TEXT)
	_draw_settings_button(settings_resume_rect, "继续迁徙", true, true)
	_draw_settings_button(
		settings_sound_rect,
		"声音",
		settings.sound_enabled,
		settings.sound_enabled
	)
	_draw_settings_button(
		settings_vibration_rect,
		"震动",
		settings.vibration_enabled,
		settings.vibration_enabled
	)
	_draw_settings_button(
		settings_motion_rect,
		"减少动态",
		settings.reduced_motion,
		settings.reduced_motion
	)
	_draw_settings_button(
		settings_language_rect,
		"语言：%s" % ("中文" if settings.language == "zh" else "英文"),
		true,
		true
	)
	_draw_settings_button(settings_map_rect, "返回章节地图", true, true)


func _draw_settings_button(rect: Rect2, label: String, enabled: bool, active: bool) -> void:
	var fill := Color("#55BEE6") if active else Color("#E1E9E8")
	var text_color := Color.WHITE if active else Color("#657E82")
	_draw_panel(rect, fill, Color.WHITE, 38.0, 4.0)
	var state_label := ""
	if label in ["声音", "震动", "减少动态"]:
		state_label = "开启" if enabled else "关闭"
	_draw_centered_text(
		"%s%s" % [label, "　%s" % state_label if not state_label.is_empty() else ""],
		rect.get_center() + Vector2(0, 11),
		29,
		text_color
	)


func _draw_game_background() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#FFF7E7"), true)
	var sky_top := Color("#58C9F0")
	var sky_bottom := Color("#EDF9FC")
	var strip_height := 10.5
	for index in 40:
		var amount := float(index) / 39.0
		draw_rect(
			Rect2(0.0, float(index) * strip_height, size.x, strip_height + 1.0),
			sky_top.lerp(sky_bottom, amount),
			true
		)
	for center in [Vector2(75, 318), Vector2(975, 300)]:
		draw_circle(center + Vector2(-55, 12), 55.0, Color("#FFFFFFB8"))
		draw_circle(center + Vector2(0, -16), 73.0, Color("#FFFFFFD0"))
		draw_circle(center + Vector2(64, 14), 52.0, Color("#FFFFFFB8"))


func _draw_minimap() -> void:
	_draw_panel(
		Rect2(minimap_rect.position + Vector2(0, 9), minimap_rect.size),
		Color("#31515E35"),
		Color.TRANSPARENT,
		34.0,
		0.0
	)
	_draw_panel(minimap_rect, Color("#FFF9EAF2"), Color("#FFFFFF"), 34.0, 5.0)
	_draw_centered_text(
		"迁徙路线",
		Vector2(minimap_rect.get_center().x, minimap_rect.position.y + 35.0),
		20,
		COLOR_SUBTEXT
	)
	var plot := Rect2(
		minimap_rect.position + Vector2(25.0, 52.0),
		minimap_rect.size - Vector2(50.0, 72.0)
	)
	_draw_panel(plot, Color("#F5E5B2B5"), Color("#E8CC8F"), 24.0, 2.0)

	var authored_route: Array[Vector2] = []
	authored_route.append(_minimap_cell_point(map_view.board.start_cell, plot))
	for raw_path in map_view.board.intended_paths:
		for cell in raw_path:
			authored_route.append(_minimap_cell_point(cell, plot))
	authored_route.append(_minimap_cell_point(map_view.board.goal_cell, plot))
	for index in range(1, authored_route.size()):
		draw_dashed_line(
			authored_route[index - 1],
			authored_route[index],
			Color("#FFFFFFC7"),
			8.0,
			11.0,
			true
		)

	for y in map_view.board.height:
		for x in map_view.board.width:
			var cell := Vector2i(x, y)
			if not map_view.board.is_road_cell(cell):
				continue
			var center := _minimap_cell_point(cell, plot)
			for direction in [Vector2i.RIGHT, Vector2i.DOWN]:
				var neighbor: Vector2i = cell + direction
				if map_view.board.is_road_cell(neighbor):
					draw_line(
						center,
						_minimap_cell_point(neighbor, plot),
						Color("#63C85D"),
						11.0,
						true
					)
			draw_circle(center, 6.0, Color("#63C85D"))

	var start_position := _minimap_cell_point(map_view.board.start_cell, plot)
	draw_circle(start_position, 11.0, Color.WHITE)
	draw_circle(start_position, 8.0, Color("#45CBE4"))
	var animal_position := _minimap_cell_point(map_view.board.animal_cell, plot)
	draw_circle(animal_position, 10.0, Color.WHITE)
	draw_circle(animal_position, 7.0, Color("#F3AC47"))

	var goal_position := _minimap_cell_point(map_view.board.goal_cell, plot)
	var oasis_rect := Rect2(goal_position - Vector2(18.0, 19.0), Vector2(36.0, 38.0))
	var oasis_source := Rect2(22.0, 55.0, 1155.0, 1215.0)
	draw_texture_rect_region(TEXTURE_OASIS, oasis_rect, oasis_source)


func _minimap_cell_point(cell: Vector2i, plot: Rect2) -> Vector2:
	var normalized_x := (float(cell.x) + 0.5) / float(map_view.board.width)
	var normalized_y := (float(cell.y) + 1.25) / float(map_view.board.height + 1)
	return Vector2(
		lerpf(plot.position.x, plot.end.x, normalized_x),
		lerpf(plot.position.y, plot.end.y, normalized_y)
	)


func _draw_chapter_complete() -> void:
	draw_rect(Rect2(Vector2.ZERO, DESIGN_SIZE), Color("#EAF9FC"), true)
	for index in 20:
		var x := 55.0 + fposmod(float(index) * 197.0, 970.0)
		var y := 110.0 + fposmod(float(index * index) * 73.0, 1540.0)
		var colors := [Color("#6EDB94"), Color("#57C9E9"), Color("#FFD76A"), Color("#FF9DA6")]
		draw_circle(Vector2(x, y), 7.0 + float(index % 3) * 2.0, colors[index % colors.size()])

	_draw_panel(Rect2(120, 135, 840, 1480), Color("#FFF9EBF8"), Color("#70D58D"), 70.0, 7.0)
	var chapter: Dictionary = chapters[current_chapter_index]
	_draw_centered_text("%s完成" % _current_chapter_label(), Vector2(540, 275), 66, COLOR_TEXT)
	_draw_centered_text(
		"%s · %d / %d" % [
			str(chapter["title"]).get_slice(" · ", 1),
			levels.size(),
			levels.size(),
		],
		Vector2(540, 340),
		31,
		Color("#3AAE68")
	)

	var oasis_rect := Rect2(270, 390, 540, 550)
	var oasis_source := Rect2(22.0, 55.0, 1155.0, 1215.0)
	draw_texture_rect_region(TEXTURE_OASIS, oasis_rect, oasis_source)

	_draw_panel(Rect2(220, 980, 640, 190), Color("#F0FFF3"), Color("#9BE2AD"), 44.0)
	_draw_centered_text("新绿洲已经恢复", Vector2(540, 1055), 40, COLOR_TEXT)
	_draw_centered_text("动物队伍获得了新的家园", Vector2(540, 1112), 28, COLOR_SUBTEXT)

	_draw_panel(
		Rect2(chapter_replay_rect.position + Vector2(0, 8), chapter_replay_rect.size),
		Color("#31515E38"),
		Color.TRANSPARENT,
		48.0,
		0.0
	)
	_draw_panel(chapter_replay_rect, Color("#39BDE4"), Color.WHITE, 48.0, 5.0)
	var action_label := "返回章节地图"
	var next_hint := "所有现有章节已经完成"
	if current_chapter_index + 1 < chapters.size():
		action_label = "进入下一章"
		next_hint = str(chapters[current_chapter_index + 1]["title"])
	_draw_centered_text(action_label, chapter_replay_rect.get_center() + Vector2(0, 12), 34, Color.WHITE)
	_draw_centered_text(next_hint, Vector2(540, 1510), 26, Color("#6A8798"))


func _draw_action_button(
	rect: Rect2,
	texture: Texture2D,
	label: String,
	action_id: String,
	icon_size: float
) -> void:
	var center := Vector2(rect.get_center().x, rect.position.y + 55)
	var press_amount := 0.0
	if action_feedback_id == action_id and action_feedback_time > 0.0:
		var progress := 1.0 - action_feedback_time / 0.22
		press_amount = sin(progress * PI)
	var draw_size := icon_size * (1.0 - press_amount * 0.075)
	var draw_center := center + Vector2(0.0, press_amount * 7.0)
	var shadow_radius := minf(76.0, draw_size * 0.4)
	draw_circle(draw_center + Vector2(0, 8), shadow_radius, Color("#4D78902B"))
	draw_texture_rect(
		texture,
		Rect2(draw_center - Vector2.ONE * draw_size * 0.5, Vector2.ONE * draw_size),
		false
	)
	_draw_centered_text(label, Vector2(center.x, rect.position.y + 139), 23, COLOR_SUBTEXT)


func _draw_undo_action_button() -> void:
	var center := Vector2(undo_rect.get_center().x, undo_rect.position.y + 55)
	var enabled := map_view != null and not map_view.undo_stack.is_empty()
	var press_amount := 0.0
	if action_feedback_id == "undo" and action_feedback_time > 0.0:
		var feedback_progress := 1.0 - action_feedback_time / 0.22
		press_amount = sin(feedback_progress * PI)
	var draw_center := center + Vector2(0.0, press_amount * 7.0)
	var outer := Color("#55BEE6") if enabled else Color("#B7C9CF")
	draw_circle(draw_center + Vector2(0, 8), 68.0, Color("#4D78902B"))
	draw_circle(draw_center, 68.0 * (1.0 - press_amount * 0.075), outer)
	draw_circle(draw_center, 57.0 * (1.0 - press_amount * 0.075), Color("#F7FFFE"))
	_draw_centered_text(
		"↶",
		draw_center + Vector2(0, 19),
		55,
		Color("#248DB6") if enabled else Color("#83999F")
	)
	_draw_centered_text(
		"撤回 %d" % map_view.undo_stack.size() if enabled else "撤回",
		Vector2(center.x, undo_rect.position.y + 139),
		23,
		COLOR_SUBTEXT if enabled else Color("#91A4AA")
	)


func _draw_panel(
	rect: Rect2,
	fill: Color,
	border: Color,
	radius: float,
	border_width := 4.0
) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(int(border_width))
	style.set_corner_radius_all(int(radius))
	draw_style_box(style, rect)


func _draw_centered_text(text: String, center: Vector2, font_size: int, color: Color) -> void:
	text = Localization.text(text)
	var font := UI_FONT
	var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(
		font,
		Vector2(center.x - text_width * 0.5, center.y),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		color
	)
