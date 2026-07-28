extends Control

const MapViewScene = preload("res://src/ui/map_view.gd")
const ChapterMapViewScene = preload("res://src/ui/chapter_map_view.gd")
const LevelCatalog = preload("res://src/model/level_catalog.gd")
const ProgressStore = preload("res://src/model/progress_store.gd")
const TEXTURE_OASIS: Texture2D = preload("res://art/destination/destination_oasis_v3.png")
const BUTTON_RESET: Texture2D = preload("res://art/ui/button_reset_v1.png")
const BUTTON_COMPASS: Texture2D = preload("res://art/ui/button_compass_v1.png")
const BUTTON_PARTY: Texture2D = preload("res://art/ui/button_party_v1.png")

const COLOR_BACKGROUND := Color("#EDF9FC")
const COLOR_PANEL := Color("#FFFFFF")
const COLOR_BORDER := Color("#83CDE8")
const COLOR_TEXT := Color("#173954")
const COLOR_SUBTEXT := Color("#4E7087")
const COLOR_CYAN := Color("#27C9DF")
const COLOR_CREAM := Color("#FFF7E7")
const COLOR_GOLD := Color("#F4B84E")

var levels: Array[Dictionary] = []
var current_level_index := 0
var debug_level_active := false
var chapter_complete_visible := false
var chapter_map_visible := false
var map_view: MigrationMapView
var chapter_map_view
var progress := ProgressStore.new()

var current_level_name := ""
var current_days := 0
var current_recommended_days := 0
var current_rescued_partners := 0
var current_total_partners := 0
var current_visited_checkpoints := 0
var current_total_checkpoints := 0
var current_sum := 0
var current_sum_label := "从道路边缘开始"
var current_accent := COLOR_CYAN
var current_message := ""
var target_pulse_time := 0.0
var action_feedback_id := ""
var action_feedback_time := 0.0

var restart_rect := Rect2(165, 1708, 210, 145)
var hint_rect := Rect2(435, 1708, 210, 145)
var recenter_rect := Rect2(705, 1708, 210, 145)
var level_switch_rect := Rect2(32, 28, 390, 82)
var chapter_replay_rect := Rect2(330, 1325, 420, 105)
var minimap_rect := Rect2(780, 138, 260, 220)


func _ready() -> void:
	levels = LevelCatalog.playable_levels()
	progress.load_progress()
	map_view = MapViewScene.new()
	map_view.position = Vector2(40, 370)
	map_view.size = Vector2(1000, 1180)
	map_view.status_changed.connect(_on_status_changed)
	map_view.session_changed.connect(_on_session_changed)
	map_view.objectives_changed.connect(_on_objectives_changed)
	map_view.checkpoints_changed.connect(_on_checkpoints_changed)
	map_view.level_completed.connect(_on_level_completed)
	map_view.next_level_requested.connect(_on_next_level_requested)
	add_child(map_view)
	chapter_map_view = ChapterMapViewScene.new()
	chapter_map_view.position = Vector2.ZERO
	chapter_map_view.size = Vector2(1080, 1920)
	chapter_map_view.level_selected.connect(_on_chapter_level_selected)
	chapter_map_view.status_message.connect(_on_chapter_status_message)
	chapter_map_view.visible = false
	add_child(chapter_map_view)
	var arguments := OS.get_cmdline_user_args()
	if "--debug-stuck" in arguments:
		_load_debug_stuck_level()
	elif "--play" in arguments or _has_auto_argument(arguments):
		_load_level(0)
	else:
		_load_level(clampi(progress.unlocked_level - 1, 0, levels.size() - 1))
		_show_chapter_map()
	for argument in arguments:
		if argument.begins_with("--auto="):
			var count := int(argument.trim_prefix("--auto="))
			for index in count:
				map_view.debug_apply_next_intended_path()
	queue_redraw()


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
	current_message = "该地图仅用于验证自动死局检测和恢复操作"
	queue_redraw()


func _input(event: InputEvent) -> void:
	if chapter_complete_visible:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE or event.keycode == KEY_R:
				_show_chapter_map()
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if chapter_replay_rect.has_point(event.position):
				_show_chapter_map()
			get_viewport().set_input_as_handled()
		elif event is InputEventScreenTouch and event.pressed:
			if chapter_replay_rect.has_point(event.position):
				_show_chapter_map()
			get_viewport().set_input_as_handled()
		return
	if chapter_map_visible:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode >= KEY_1 and event.keycode <= KEY_9:
				_load_level(int(event.keycode - KEY_1))
			elif event.keycode == KEY_0:
				_load_level(9)
			elif event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
				_load_level(clampi(progress.unlocked_level - 1, 0, levels.size() - 1))
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
		var position: Vector2 = mouse_event.position
		if _handle_game_hud_pointer(position):
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch and event.pressed:
		if _handle_game_hud_pointer(event.position):
			get_viewport().set_input_as_handled()


func _handle_game_hud_pointer(position: Vector2) -> bool:
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
	Input.vibrate_handheld(18)
	queue_redraw()


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


func _on_level_completed(days: int) -> void:
	current_days = days
	if not debug_level_active:
		progress.complete_level(
			current_level_index + 1,
			days,
			current_rescued_partners
		)
	current_message = "迁徙完成：动物队伍已经安全抵达新绿洲"
	queue_redraw()


func _on_next_level_requested() -> void:
	if not debug_level_active and current_level_index == levels.size() - 1:
		chapter_complete_visible = true
		map_view.visible = false
		current_message = "第一章完成：新的绿洲已经恢复"
		queue_redraw()
	else:
		_load_level(current_level_index + 1)


func _show_chapter_map() -> void:
	debug_level_active = false
	chapter_complete_visible = false
	chapter_map_visible = true
	map_view.visible = false
	chapter_map_view.visible = true
	chapter_map_view.configure(levels, progress, current_level_index)
	queue_redraw()


func _on_chapter_level_selected(level_index: int) -> void:
	_load_level(level_index)


func _on_chapter_status_message(_message: String) -> void:
	queue_redraw()


func _draw() -> void:
	_draw_game_background()

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
	var objective_label := ""
	if current_total_partners > 0:
		objective_label = "伙伴 %d / %d" % [
			current_rescued_partners,
			current_total_partners,
		]
	elif current_total_checkpoints > 0:
		objective_label = "水塘补给 %d / %d" % [
			current_visited_checkpoints,
			current_total_checkpoints,
		]
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
			19,
			Color("#2FAE91")
		)
	else:
		_draw_centered_text(
			recommendation_label,
			recommendation_rect.get_center() + Vector2(0, 11),
			27,
			Color("#8C651F")
		)

	var pause_rect := Rect2(948, 30, 82, 78)
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

	_draw_panel(Rect2(135, 1672, 810, 188), Color("#FFF5E5F2"), Color("#FFFFFF"), 78.0, 5.0)
	_draw_action_button(restart_rect, BUTTON_RESET, "重置", "reset", 180.0)
	_draw_action_button(hint_rect, BUTTON_COMPASS, "提示", "hint", 210.0)
	_draw_action_button(recenter_rect, BUTTON_PARTY, "回到队伍", "party", 195.0)

	_draw_centered_text(
		"键盘：1–9/0 第一章　F3 死局测试　R 重置　U 撤回　G 看绿洲　A 主路　B 支路",
		Vector2(540, 1900),
		21,
		Color("#6A8798")
	)
	if chapter_complete_visible:
		_draw_chapter_complete()


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
	draw_rect(Rect2(Vector2.ZERO, size), Color("#EAF9FC"), true)
	for index in 20:
		var x := 55.0 + fposmod(float(index) * 197.0, 970.0)
		var y := 110.0 + fposmod(float(index * index) * 73.0, 1540.0)
		var colors := [Color("#6EDB94"), Color("#57C9E9"), Color("#FFD76A"), Color("#FF9DA6")]
		draw_circle(Vector2(x, y), 7.0 + float(index % 3) * 2.0, colors[index % colors.size()])

	_draw_panel(Rect2(120, 135, 840, 1480), Color("#FFF9EBF8"), Color("#70D58D"), 70.0, 7.0)
	_draw_centered_text("第一章完成", Vector2(540, 275), 66, COLOR_TEXT)
	_draw_centered_text("绿洲边缘 · 10 / 10", Vector2(540, 340), 31, Color("#3AAE68"))

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
	_draw_centered_text("返回章节地图", chapter_replay_rect.get_center() + Vector2(0, 12), 34, Color.WHITE)
	_draw_centered_text("第二章 · 明亮沙丘正在准备中", Vector2(540, 1510), 26, Color("#6A8798"))


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
	var font := ThemeDB.fallback_font
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
