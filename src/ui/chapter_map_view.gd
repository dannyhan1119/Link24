extends Control
class_name MigrationChapterMapView

const Localization = preload("res://src/model/localization.gd")

signal level_selected(level_index: int)
signal chapter_requested(chapter_index: int)
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
var chapter: Dictionary = {}
var progress
var current_level_index := 0
var current_chapter_index := 0
var chapter_count := 1
var node_rects: Array[Rect2] = []
var footer_message := "点击已解锁的关卡继续迁徙"
var map_time := 0.0
var redraw_accumulator := 0.0
var node_positions: Array[Vector2] = []
var previous_chapter_rect := Rect2(86, 112, 84, 84)
var next_chapter_rect := Rect2(910, 112, 84, 84)
var home_visible := false
var home_button_rect := Rect2(74, 270, 190, 70)
var home_close_rect := Rect2(832, 292, 104, 66)
var decoration_rects: Array[Rect2] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_update_node_rects()
	set_process(true)


func configure(chapter_definition: Dictionary, progress_store, selected_index: int) -> void:
	chapter = chapter_definition
	levels = chapter.get("levels", [])
	progress = progress_store
	current_chapter_index = int(chapter.get("catalog_index", 0))
	chapter_count = int(chapter.get("chapter_count", 1))
	current_level_index = clampi(selected_index, 0, maxi(0, levels.size() - 1))
	home_visible = false
	node_positions.clear()
	for position in chapter.get("node_positions", []):
		node_positions.append(position)
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
	if home_visible:
		if home_close_rect.has_point(position):
			home_visible = false
			queue_redraw()
			accept_event()
			return
		var tiers: Array[Dictionary] = [] if progress == null else progress.decoration_tiers()
		for index in mini(decoration_rects.size(), tiers.size()):
			if not decoration_rects[index].has_point(position):
				continue
			var chapter_id := str(chapter.get("id", ""))
			var result: Error = progress.select_decoration(chapter_id, str(tiers[index]["id"]))
			footer_message = (
				"家园装饰已更换为「%s」" % str(tiers[index]["label"])
				if result == OK
				else "继续收集成果，达到 %d 点生机即可解锁" % int(tiers[index]["points"])
			)
			status_message.emit(footer_message)
			queue_redraw()
			accept_event()
			return
		accept_event()
		return
	if home_button_rect.has_point(position):
		home_visible = true
		queue_redraw()
		accept_event()
		return
	if previous_chapter_rect.has_point(position) and current_chapter_index > 0:
		chapter_requested.emit(current_chapter_index - 1)
		accept_event()
		return
	if next_chapter_rect.has_point(position) and current_chapter_index + 1 < chapter_count:
		var next_chapter_id := ""
		if progress != null and current_chapter_index + 1 < progress.chapter_order.size():
			next_chapter_id = str(progress.chapter_order[current_chapter_index + 1])
		if progress != null and progress.is_chapter_unlocked(next_chapter_id):
			chapter_requested.emit(current_chapter_index + 1)
		else:
			footer_message = "完成本章最后一关后，明亮的迁徙路线会继续展开"
			status_message.emit(footer_message)
			queue_redraw()
		accept_event()
		return
	_update_node_rects()
	for index in node_rects.size():
		if not node_rects[index].has_point(position):
			continue
		var level_id := str(levels[index]["id"])
		if progress != null and progress.is_level_unlocked(level_id):
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
	_draw_growth_status()
	_draw_footer()
	_draw_home_button()
	if home_visible:
		_draw_home_overlay()


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
	var landscape_tint: Color = chapter.get("landscape_tint", Color("#FFF9E8"))
	landscape_tint.a = 0.95
	draw_texture_rect(TEXTURE_DESERT, landscape_rect, false, landscape_tint)
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
	_draw_centered_text(str(chapter.get("title", "迁徙章节")), Vector2(540, 132), 48, COLOR_TEXT)
	var completed_count := _completed_count()
	var chapter_id := str(chapter.get("id", ""))
	var badge_count: int = 0 if progress == null else progress.chapter_badge_count(chapter_id)
	var badge_total: int = levels.size() * 3 if progress == null else progress.chapter_badge_total(chapter_id)
	_draw_centered_text(
		"已完成 %d / %d　·　绿洲生机 %d / %d" % [
			completed_count,
			levels.size(),
			badge_count,
			badge_total,
		],
		Vector2(540, 190),
		27,
		COLOR_SUBTEXT
	)
	var progress_track := Rect2(280.0, 211.0, 520.0, 14.0)
	_draw_rounded_rect(progress_track, Color("#DCECEF"), 7.0)
	if badge_total > 0:
		var fill_width := progress_track.size.x * float(badge_count) / float(badge_total)
		if fill_width > 0.0:
			_draw_rounded_rect(
				Rect2(progress_track.position, Vector2(fill_width, progress_track.size.y)),
				COLOR_GREEN,
				7.0
			)
	_draw_chapter_navigation()


func _draw_chapter_navigation() -> void:
	if current_chapter_index > 0:
		_draw_rounded_rect(previous_chapter_rect, Color("#FFFFFFD9"), 36.0, Color.WHITE, 3.0)
		_draw_centered_text("‹", previous_chapter_rect.get_center() + Vector2(0, 16), 48, COLOR_SUBTEXT)
	if current_chapter_index + 1 < chapter_count:
		var next_unlocked := false
		if progress != null and current_chapter_index + 1 < progress.chapter_order.size():
			next_unlocked = progress.is_chapter_unlocked(
				str(progress.chapter_order[current_chapter_index + 1])
			)
		var fill := Color("#FFFFFFD9") if next_unlocked else Color("#D8E1E2D9")
		_draw_rounded_rect(next_chapter_rect, fill, 36.0, Color.WHITE, 3.0)
		_draw_centered_text(
			"›" if next_unlocked else "锁",
			next_chapter_rect.get_center() + Vector2(0, 15),
			48 if next_unlocked else 28,
			COLOR_SUBTEXT
		)


func _completed_count() -> int:
	var completed_count := 0
	if progress == null:
		return completed_count
	for level in levels:
		if progress.is_completed(str(level["id"])):
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
	if progress == null or segment_index + 1 >= levels.size():
		return progress == null
	return bool(progress.is_level_unlocked(str(levels[segment_index + 1]["id"])))


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
	var chapter_id := str(chapter.get("id", ""))
	var stage: int = 0 if progress == null else progress.chapter_growth_stage(chapter_id)
	var oasis_tint := Color("#AFA58E") if stage == 0 else Color.WHITE
	if stage == 1:
		oasis_tint = Color("#C4CBAA")
	elif stage == 2:
		oasis_tint = Color("#E0E8CA")
	draw_texture_rect_region(TEXTURE_OASIS, oasis_rect, oasis_source, oasis_tint)
	_draw_growth_decorations(stage, oasis_rect)
	if progress != null:
		_draw_selected_home_decoration(
			progress.selected_decoration_for(chapter_id),
			oasis_rect
		)


func _draw_growth_status() -> void:
	var chapter_id := str(chapter.get("id", ""))
	var stage: int = 0 if progress == null else progress.chapter_growth_stage(chapter_id)
	var status_rect := Rect2(610, 300, 300, 58)
	_draw_rounded_rect(status_rect, Color("#FFF9ECED"), 27.0, Color("#FFFFFF"), 3.0)
	_draw_centered_text(
		_growth_stage_label(stage),
		status_rect.get_center() + Vector2(0, 9),
		23,
		Color("#318D5D") if stage > 0 else Color("#7D796C")
	)


func _growth_stage_label(stage: int) -> String:
	match stage:
		1:
			return "水源重新涌动"
		2:
			return "草木正在生长"
		3:
			return "伙伴们的新家"
		4:
			return "完全复苏的绿洲"
		_:
			return "等待复苏的绿洲"


func _draw_growth_decorations(stage: int, oasis_rect: Rect2) -> void:
	if stage >= 1:
		var water_center := oasis_rect.get_center() + Vector2(2.0, 66.0)
		var pulse := (sin(map_time * 2.4) + 1.0) * 0.5
		draw_circle(water_center, 52.0 + pulse * 5.0, Color("#73DDF05C"))
		draw_circle(water_center, 34.0, Color("#A5F1F4A8"))
	if stage >= 2:
		for offset in [
			Vector2(-122, 108), Vector2(-92, 134), Vector2(108, 115),
			Vector2(138, 82), Vector2(-145, 62), Vector2(84, 145),
		]:
			var flower: Vector2 = oasis_rect.get_center() + offset
			draw_circle(flower + Vector2(-5, 0), 6.0, Color("#FFF0A8"))
			draw_circle(flower + Vector2(5, 0), 6.0, Color("#F5AFC5"))
			draw_circle(flower, 3.5, Color("#FFD45B"))
	if stage >= 3:
		var party_rect := Rect2(oasis_rect.position + Vector2(120, 235), Vector2(150, 175))
		var party_source := Rect2(35.0, 275.0, 870.0, 1035.0)
		draw_texture_rect_region(TEXTURE_ANIMALS, party_rect, party_source)
	if stage >= 4:
		for index in 8:
			var angle := map_time * 0.35 + TAU * float(index) / 8.0
			var sparkle := oasis_rect.get_center() + Vector2(cos(angle), sin(angle)) * 185.0
			draw_circle(sparkle, 6.0, Color("#FFF7A5C8"))
			draw_circle(sparkle, 2.5, Color.WHITE)


func _draw_selected_home_decoration(decoration_id: String, oasis_rect: Rect2) -> void:
	var center := oasis_rect.get_center()
	match decoration_id:
		"wind_chimes":
			draw_line(center + Vector2(112, -96), center + Vector2(112, -28), Color("#8B6637"), 5.0)
			for offset in [-18.0, 0.0, 18.0]:
				draw_line(
					center + Vector2(112 + offset, -62),
					center + Vector2(112 + offset, -28),
					Color("#F1C44F"),
					4.0
				)
				draw_circle(center + Vector2(112 + offset, -22), 6.0, Color("#FFF0A0"))
		"flower_garden":
			for offset in [
				Vector2(-155, 105), Vector2(-130, 126), Vector2(138, 116),
				Vector2(160, 92), Vector2(-112, 145), Vector2(112, 148),
			]:
				draw_circle(center + offset, 12.0, Color("#F49ABC"))
				draw_circle(center + offset, 5.0, Color("#FFD55B"))
		"shade_tent":
			draw_colored_polygon(
				PackedVector2Array([
					center + Vector2(-96, 117),
					center + Vector2(-28, 34),
					center + Vector2(38, 117),
				]),
				Color("#F2B75A")
			)
			draw_line(center + Vector2(-28, 34), center + Vector2(-28, 128), Color("#8B6337"), 5.0)
		"star_lanterns":
			draw_line(center + Vector2(-150, -40), center + Vector2(150, -10), Color("#7E6440"), 4.0)
			for index in 7:
				var lamp := center + Vector2(-145 + index * 48.0, -38 + index * 5.0)
				draw_circle(lamp, 9.0, Color("#FFF19A88"))
				draw_circle(lamp, 4.0, Color("#FFF7C8"))
		"festival_flags":
			draw_line(center + Vector2(-155, -42), center + Vector2(155, -18), Color("#7E6440"), 4.0)
			var colors := [Color("#F48DA8"), Color("#59CBE8"), Color("#FFD15A"), Color("#68CF88")]
			for index in 8:
				var anchor := center + Vector2(-145 + index * 41.0, -41 + index * 3.2)
				draw_colored_polygon(
					PackedVector2Array([
						anchor,
						anchor + Vector2(26, 2),
						anchor + Vector2(13, 28),
					]),
					colors[index % colors.size()]
				)


func _draw_home_button() -> void:
	_draw_rounded_rect(
		Rect2(home_button_rect.position + Vector2(0, 6), home_button_rect.size),
		Color("#31515E35"),
		28.0
	)
	_draw_rounded_rect(home_button_rect, Color("#FFF9ECF2"), 28.0, Color.WHITE, 4.0)
	_draw_centered_text("绿洲家园", home_button_rect.get_center() + Vector2(0, 10), 25, Color("#318D5D"))


func _draw_home_overlay() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#17395466"), true)
	var panel := Rect2(70, 260, 940, 1420)
	_draw_rounded_rect(
		Rect2(panel.position + Vector2(0, 12), panel.size),
		Color("#24485A4A"),
		58.0
	)
	_draw_rounded_rect(panel, Color("#FFF9ECFA"), 58.0, Color("#70D58D"), 6.0)
	_draw_centered_text("绿洲家园", Vector2(540, 350), 52, COLOR_TEXT)
	var chapter_id := str(chapter.get("id", ""))
	var resident_count: int = 0 if progress == null else progress.chapter_resident_count(chapter_id)
	var resident_total: int = 0 if progress == null else progress.chapter_resident_total(chapter_id)
	_draw_centered_text(
		"获救居民 %d / %d　·　成果会解锁新的家园装饰" % [resident_count, resident_total],
		Vector2(540, 405),
		25,
		COLOR_SUBTEXT
	)
	_draw_rounded_rect(home_close_rect, Color("#E8F1EF"), 26.0)
	_draw_centered_text("关闭窗口", home_close_rect.get_center() + Vector2(0, 9), 22, COLOR_SUBTEXT)

	var residents: Array[Dictionary] = [] if progress == null else progress.chapter_residents(chapter_id)
	_draw_centered_text("迁入居民", Vector2(220, 492), 30, COLOR_TEXT)
	if residents.is_empty():
		_draw_centered_text("本章没有额外救援目标", Vector2(540, 600), 26, COLOR_SUBTEXT)
	else:
		for index in residents.size():
			var resident: Dictionary = residents[index]
			var center := Vector2(190 + float(index % 4) * 225.0, 595 + float(index / 4) * 150.0)
			var rescued := bool(resident["rescued"])
			draw_circle(center + Vector2(0, 6), 54.0, Color("#31515E28"))
			draw_circle(center, 54.0, Color("#79D58F") if rescued else Color("#CBD6D3"))
			draw_circle(center, 44.0, Color("#F3FFF5") if rescued else Color("#EEF1F0"))
			_draw_centered_text("♥" if rescued else "?", center + Vector2(0, 15), 36, Color("#3BA968") if rescued else Color("#899A98"))
			_draw_centered_text(
				str(resident["name"]) if rescued else "等待救援",
				center + Vector2(0, 82),
				20,
				COLOR_SUBTEXT
			)

	_draw_centered_text("家园装饰", Vector2(220, 890), 30, COLOR_TEXT)
	decoration_rects.clear()
	var tiers: Array[Dictionary] = [] if progress == null else progress.decoration_tiers()
	var selected: String = "natural" if progress == null else progress.selected_decoration_for(chapter_id)
	var vitality: int = 0 if progress == null else progress.chapter_badge_count(chapter_id)
	for index in tiers.size():
		var column := index % 2
		var row := index / 2
		var rect := Rect2(135 + column * 420.0, 935 + row * 175.0, 390, 132)
		decoration_rects.append(rect)
		var tier: Dictionary = tiers[index]
		var unlocked: bool = vitality >= int(tier["points"])
		var is_selected: bool = selected == str(tier["id"])
		var fill := Color("#F1FFF3") if unlocked else Color("#E7ECEB")
		var border := Color("#62C97E") if is_selected else Color("#D2E0DD")
		_draw_rounded_rect(rect, fill, 30.0, border, 5.0 if is_selected else 3.0)
		_draw_centered_text(
			str(tier["label"]) if unlocked else "%d 生机解锁" % int(tier["points"]),
			Vector2(rect.get_center().x, rect.position.y + 56),
			23,
			Color("#328D5D") if unlocked else Color("#869694")
		)
		_draw_centered_text(
			"使用中" if is_selected else "点击更换" if unlocked else "尚未解锁",
			Vector2(rect.get_center().x, rect.position.y + 96),
			19,
			Color("#55A96D") if unlocked else Color("#9BA8A6")
		)


func _draw_nodes() -> void:
	for index in mini(levels.size(), node_positions.size()):
		var level_number := int(levels[index].get("global_index", index + 1))
		var level_id := str(levels[index]["id"])
		var center: Vector2 = node_positions[index]
		var state := _node_visual_state(index)
		var unlocked := state != "locked"
		var completed := state == "completed"
		var selected := state == "selected"
		var fill: Color = COLOR_LOCKED
		if completed:
			fill = COLOR_GREEN
		elif unlocked:
			var chapter_accent: Color = chapter.get("accent_color", COLOR_CYAN)
			fill = COLOR_GOLD if selected else chapter_accent

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
			var badge_states: Dictionary = progress.badge_states_for(level_id)
			for badge_index in 3:
				var badge_key: String = ["arrival", "efficient", "mastery"][badge_index]
				var badge_center := center + Vector2(float(badge_index - 1) * 22.0, -70.0)
				draw_circle(badge_center, 9.0, Color("#FFFFFFE8"))
				draw_circle(
					badge_center,
					6.0,
					Color("#F4B84E") if bool(badge_states[badge_key]) else Color("#C8D5D7")
				)
			var best: int = int(progress.best_days_for(level_id))
			if best > 0:
				_draw_rounded_rect(
					Rect2(center + Vector2(-59, 62), Vector2(118, 38)),
					Color("#FFFFFFE8"),
					18.0
				)
				_draw_centered_text("%d 天" % best, center + Vector2(0, 89), 19, COLOR_SUBTEXT)
			if progress.partners_for(level_id) > 0:
				draw_circle(center + Vector2(53, -47), 18.0, Color("#FFF4D8"))
				_draw_centered_text("♥", center + Vector2(53, -40), 19, Color("#F39A62"))
			if progress.watchtowers_for(level_id) > 0:
				draw_circle(center + Vector2(-53, -47), 18.0, Color("#FFF4D8"))
				_draw_centered_text("▲", center + Vector2(-53, -41), 17, Color("#C48A2C"))


func _node_visual_state(index: int) -> String:
	var level_id := str(levels[index]["id"])
	if progress != null and bool(progress.is_completed(level_id)):
		return "completed"
	if progress != null and not bool(progress.is_level_unlocked(level_id)):
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
	text = Localization.text(text)
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
