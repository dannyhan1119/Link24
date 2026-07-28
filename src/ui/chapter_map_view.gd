extends Control
class_name MigrationChapterMapView

signal level_selected(level_index: int)
signal status_message(message: String)

const TEXTURE_OASIS: Texture2D = preload("res://art/destination/destination_oasis_v3.png")
const TEXTURE_START_OASIS: Texture2D = preload("res://art/start/start_oasis_v1.png")
const TEXTURE_ANIMALS: Texture2D = preload("res://art/characters/migration_party_v1.png")
const TEXTURE_DESERT: Texture2D = preload("res://art/environment/desert_map_base_v1.png")
const TEXTURE_ROCKS: Texture2D = preload("res://art/obstacles/rock_cluster_low_v1.png")
const TEXTURE_CACTUS: Texture2D = preload("res://art/obstacles/cactus_cluster_v1.png")

const COLOR_SKY := Color("#EAF9FC")
const COLOR_TEXT := Color("#173954")
const COLOR_SUBTEXT := Color("#55758A")
const COLOR_CYAN := Color("#37BFE4")
const COLOR_GREEN := Color("#58C978")
const COLOR_GOLD := Color("#F2B94E")
const COLOR_LOCKED := Color("#B9C9CF")

var levels: Array[Dictionary] = []
var progress
var current_level_index := 0
var node_rects: Array[Rect2] = []
var footer_message := "点击已解锁的关卡继续迁徙"
var map_time := 0.0
var redraw_accumulator := 0.0

var node_positions: Array[Vector2] = [
	Vector2(220, 1570),
	Vector2(470, 1450),
	Vector2(760, 1530),
	Vector2(850, 1300),
	Vector2(610, 1160),
	Vector2(300, 1090),
	Vector2(205, 850),
	Vector2(490, 735),
	Vector2(790, 835),
	Vector2(760, 560),
]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_update_node_rects()
	set_process(true)


func configure(chapter_levels: Array[Dictionary], progress_store, selected_index: int) -> void:
	levels = chapter_levels
	progress = progress_store
	current_level_index = clampi(selected_index, 0, maxi(0, levels.size() - 1))
	footer_message = "点击已解锁的关卡继续迁徙"
	map_time = 0.0
	redraw_accumulator = 0.0
	_update_node_rects()
	queue_redraw()


func _process(delta: float) -> void:
	map_time += delta
	redraw_accumulator += delta
	if redraw_accumulator >= 0.08:
		redraw_accumulator = 0.0
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var position := Vector2.ZERO
	var pressed := false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		position = event.position
		pressed = event.pressed
	elif event is InputEventScreenTouch:
		position = event.position
		pressed = event.pressed
	if not pressed:
		return
	_update_node_rects()
	for index in node_rects.size():
		if not node_rects[index].has_point(position):
			continue
		if progress != null and progress.is_unlocked(index + 1):
			level_selected.emit(index)
		else:
			footer_message = "先完成前一关，迁徙路线就会继续展开"
			status_message.emit(footer_message)
			queue_redraw()
		accept_event()
		return


func _update_node_rects() -> void:
	node_rects.clear()
	for position in node_positions:
		node_rects.append(Rect2(position - Vector2.ONE * 66.0, Vector2.ONE * 132.0))


func _draw() -> void:
	_draw_sky_gradient()
	_draw_desert_landscape()
	_draw_background_clouds()
	_draw_header()
	_draw_map_decorations()
	_draw_route()
	_draw_start_landmark()
	_draw_destination_landmark()
	_draw_nodes()
	_draw_footer()


func _draw_sky_gradient() -> void:
	var band_height := size.y / 16.0
	for index in 16:
		var amount := float(index) / 15.0
		var color := Color("#75D4EE").lerp(COLOR_SKY, amount)
		draw_rect(
			Rect2(Vector2(0.0, float(index) * band_height), Vector2(size.x, band_height + 1.0)),
			color,
			true
		)


func _draw_desert_landscape() -> void:
	var landscape_rect := Rect2(0.0, 220.0, 1080.0, 1660.0)
	draw_texture_rect(TEXTURE_DESERT, landscape_rect, false, Color("#FFF9E8F2"))
	draw_rect(Rect2(0.0, 220.0, 1080.0, 95.0), Color("#EAF9FCAA"))
	draw_rect(Rect2(0.0, 1740.0, 1080.0, 140.0), Color("#FFF5DE82"))


func _draw_background_clouds() -> void:
	for index in 11:
		var center := Vector2(
			90.0 + fposmod(float(index) * 337.0, 900.0),
			250.0 + float(index) * 154.0
		)
		if index % 2 == 1:
			center.x = 990.0 - center.x * 0.75
		var cloud_color := Color("#FFFFFF8A")
		draw_circle(center, 51.0, cloud_color)
		draw_circle(center + Vector2(56.0, 9.0), 40.0, cloud_color)
		draw_circle(center + Vector2(-52.0, 14.0), 35.0, cloud_color)


func _draw_header() -> void:
	_draw_rounded_rect(Rect2(70, 66, 940, 190), Color("#31515E32"), 54.0)
	_draw_rounded_rect(Rect2(70, 54, 940, 190), Color("#FFF9ECF6"), 54.0, Color.WHITE, 5.0)
	_draw_centered_text("第一章 · 绿洲边缘", Vector2(540, 132), 48, COLOR_TEXT)
	var completed_count := _completed_count()
	var unlocked: int = 1 if progress == null else int(progress.unlocked_level)
	_draw_centered_text(
		"已完成 %d / %d　·　已解锁 %d / %d" % [
			completed_count,
			levels.size(),
			unlocked,
			levels.size(),
		],
		Vector2(540, 190),
		27,
		COLOR_SUBTEXT
	)
	var progress_track := Rect2(280.0, 211.0, 520.0, 14.0)
	_draw_rounded_rect(progress_track, Color("#DCECEF"), 7.0)
	if not levels.is_empty():
		var fill_width := progress_track.size.x * float(completed_count) / float(levels.size())
		if fill_width > 0.0:
			_draw_rounded_rect(
				Rect2(progress_track.position, Vector2(fill_width, progress_track.size.y)),
				COLOR_GREEN,
				7.0
			)


func _completed_count() -> int:
	var completed_count := 0
	if progress == null:
		return completed_count
	for level_index in range(1, levels.size() + 1):
		if progress.is_completed(level_index):
			completed_count += 1
	return completed_count


func _draw_map_decorations() -> void:
	var cactus_positions := [
		Vector2(125.0, 405.0),
		Vector2(925.0, 1010.0),
		Vector2(175.0, 1260.0),
	]
	for position in cactus_positions:
		draw_texture_rect(
			TEXTURE_CACTUS,
			Rect2(position - Vector2(64.0, 64.0), Vector2(128.0, 128.0)),
			false,
			Color("#FFFFFFD8")
		)
	var rock_positions := [
		Vector2(820.0, 1110.0),
		Vector2(385.0, 930.0),
		Vector2(910.0, 1515.0),
	]
	for position in rock_positions:
		draw_texture_rect(
			TEXTURE_ROCKS,
			Rect2(position - Vector2(63.0, 55.0), Vector2(126.0, 110.0)),
			false,
			Color("#FFFFFFDB")
		)


func _draw_route() -> void:
	for index in range(1, node_positions.size()):
		var from: Vector2 = node_positions[index - 1]
		var to: Vector2 = node_positions[index]
		var unlocked := _route_segment_unlocked(index - 1)
		if unlocked:
			draw_line(from, to, Color("#4B9F42"), 54.0, true)
			draw_line(from, to, Color("#7BCA50"), 42.0, true)
			var middle := from.lerp(to, 0.52)
			var flower_color := Color("#FFF4B5") if index % 2 == 0 else Color("#F4A6C0")
			draw_circle(middle + Vector2(-5.0, 0.0), 5.0, flower_color)
			draw_circle(middle + Vector2(5.0, 0.0), 5.0, flower_color)
			draw_circle(middle, 3.5, Color("#FFD65A"))
			var flow_phase := fposmod(map_time * 0.34 + float(index) * 0.17, 1.0)
			var glow_point := from.lerp(to, flow_phase)
			draw_circle(glow_point, 15.0, Color("#F4FFD88A"))
			draw_circle(glow_point, 6.0, Color.WHITE)
		else:
			draw_dashed_line(from, to, Color("#FFFFFFD4"), 20.0, 28.0, true)
			draw_dashed_line(from, to, Color("#BFC8BF"), 9.0, 28.0, true)


func _route_segment_unlocked(segment_index: int) -> bool:
	return progress == null or bool(progress.is_unlocked(segment_index + 2))


func _draw_start_landmark() -> void:
	var start_rect := Rect2(55, 1580, 360, 330)
	var start_source := Rect2(115.0, 190.0, 1020.0, 930.0)
	draw_texture_rect_region(TEXTURE_START_OASIS, start_rect, start_source)
	var party_rect := Rect2(160, 1525 + sin(map_time * 2.0) * 4.0, 165, 205)
	var party_source := Rect2(35.0, 275.0, 870.0, 1035.0)
	draw_texture_rect_region(TEXTURE_ANIMALS, party_rect, party_source)


func _draw_destination_landmark() -> void:
	var oasis_rect := Rect2(545, 245 + sin(map_time * 1.25) * 3.0, 430, 430)
	var oasis_source := Rect2(22.0, 55.0, 1155.0, 1215.0)
	draw_texture_rect_region(TEXTURE_OASIS, oasis_rect, oasis_source)
	_draw_centered_text("新的绿洲", Vector2(760, 430), 29, Color("#318D5D"))


func _draw_nodes() -> void:
	for index in mini(levels.size(), node_positions.size()):
		var level_number: int = index + 1
		var center: Vector2 = node_positions[index]
		var state := _node_visual_state(index)
		var unlocked := state != "locked"
		var completed := state == "completed"
		var selected := state == "selected"
		var fill: Color = COLOR_LOCKED
		if completed:
			fill = COLOR_GREEN
		elif unlocked:
			fill = COLOR_GOLD if selected else COLOR_CYAN

		var pulse := (sin(map_time * 3.2) + 1.0) * 0.5 if selected else 0.0
		var radius: float = 59.0 + pulse * 3.0 if selected and unlocked else 52.0
		if selected and unlocked:
			var pulse_color := Color("#FFF1A5")
			pulse_color.a = 0.22 + pulse * 0.28
			draw_circle(center, radius + 22.0 + pulse * 7.0, pulse_color)
		draw_circle(center + Vector2(0, 8), radius + 6.0, Color("#31515E35"))
		draw_circle(center, radius + 6.0, Color.WHITE)
		draw_circle(center, radius, fill)
		draw_circle(center, radius - 8.0, fill.lightened(0.12))
		_draw_centered_text(
			"✓" if completed else ("锁" if not unlocked else str(level_number)),
			center + Vector2(0, 17),
			38 if completed else 34,
			Color.WHITE
		)

		if unlocked and progress != null:
			var best: int = int(progress.best_days_for(level_number))
			if best > 0:
				_draw_rounded_rect(
					Rect2(center + Vector2(-59, 62), Vector2(118, 38)),
					Color("#FFFFFFE8"),
					18.0
				)
				_draw_centered_text("%d 天" % best, center + Vector2(0, 89), 19, COLOR_SUBTEXT)
			if progress.partners_for(level_number) > 0:
				draw_circle(center + Vector2(53, -47), 18.0, Color("#FFF4D8"))
				_draw_centered_text("♥", center + Vector2(53, -40), 19, Color("#F39A62"))


func _node_visual_state(index: int) -> String:
	var level_number := index + 1
	if progress != null and bool(progress.is_completed(level_number)):
		return "completed"
	if progress != null and not bool(progress.is_unlocked(level_number)):
		return "locked"
	if index == current_level_index:
		return "selected"
	return "unlocked"


func _draw_footer() -> void:
	_draw_rounded_rect(Rect2(120, 1788, 840, 86), Color("#31515E35"), 36.0)
	_draw_rounded_rect(Rect2(120, 1780, 840, 86), Color("#FFF9ECF2"), 36.0, Color.WHITE, 4.0)
	_draw_centered_text(footer_message, Vector2(540, 1834), 27, COLOR_SUBTEXT)


func _draw_rounded_rect(
	rect: Rect2,
	fill: Color,
	radius: float,
	border := Color.TRANSPARENT,
	border_width := 0.0
) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(int(radius))
	if border_width > 0.0:
		style.border_color = border
		style.set_border_width_all(int(border_width))
	draw_style_box(style, rect)


func _draw_centered_text(text: String, center: Vector2, font_size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(
		font,
		Vector2(center.x - width * 0.5, center.y),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		color
	)
