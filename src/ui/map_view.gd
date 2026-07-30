extends Control
class_name MigrationMapView

signal status_changed(total: int, label: String, accent: Color)
signal session_changed(level_name: String, days: int, message: String)
signal objectives_changed(rescued_partners: int, total_partners: int)
signal checkpoints_changed(visited: int, total: int)
signal watchtowers_changed(visited: int, total: int)
signal level_completed(days: int)
signal next_level_requested

const BoardModel = preload("res://src/model/board_model.gd")
const StrategySolver = preload("res://src/model/strategy_solver.gd")
const Localization = preload("res://src/model/localization.gd")
const TEXTURE_DESERT: Texture2D = preload("res://art/environment/desert_map_base_v1.png")
const TEXTURE_ANIMALS: Texture2D = preload("res://art/characters/migration_party_v1.png")
const TEXTURE_ANIMALS_WALK_LEFT: Texture2D = preload(
	"res://art/characters/migration_party_walk_left_v1.png"
)
const TEXTURE_ANIMALS_WALK_RIGHT: Texture2D = preload(
	"res://art/characters/migration_party_walk_right_v1.png"
)
const TEXTURE_OASIS: Texture2D = preload("res://art/destination/destination_oasis_v3.png")
const TEXTURE_START_OASIS: Texture2D = preload("res://art/start/start_oasis_v1.png")
const TEXTURE_ROCKS: Texture2D = preload("res://art/obstacles/rock_cluster_v1.png")
const TEXTURE_ROCKS_LOW: Texture2D = preload("res://art/obstacles/rock_cluster_low_v1.png")
const TEXTURE_CACTUS: Texture2D = preload("res://art/obstacles/cactus_cluster_v1.png")
const TEXTURE_LOST_PARTNER: Texture2D = preload("res://art/characters/lost_fennec_v2.png")
const TEXTURE_SANDSTONE_TILE: Texture2D = preload("res://art/tiles/sandstone_tile_v1.png")
const TEXTURE_GRASS_TILE: Texture2D = preload("res://art/tiles/grass_tile_v1.png")
const SFX_OPEN_PATH: AudioStream = preload("res://audio/sfx/open_path.wav")
const SFX_INVALID_PATH: AudioStream = preload("res://audio/sfx/invalid_path.wav")
const SFX_ARRIVAL: AudioStream = preload("res://audio/sfx/arrival.wav")
const CELL_SIZE := 132.0
const CELL_INSET := 8.0
const EDGE_SCROLL_MARGIN := 54.0
const EDGE_SCROLL_SPEED := 360.0
const OASIS_WORLD_MARGIN := 3.4
const START_WORLD_MARGIN := 1.4
const GOAL_SAFE_INSET := 58.0
const GOAL_INDICATOR_RADIUS := 42.0
const ANIMAL_SOURCE_RECT := Rect2(25.0, 270.0, 900.0, 1050.0)
const MAX_UNDO_STEPS := 20
const HINT_STATE_CAP := 12000

const COLOR_SAND := Color("#F9E7BD")
const COLOR_TILE := Color("#FFFAF0")
const COLOR_TILE_BORDER := Color("#E8C987")
const COLOR_NUMBER := Color("#173954")
const COLOR_ROAD := Color("#8CDC58")
const COLOR_ROAD_BORDER := Color("#55B654")
const COLOR_SELECTED := Color("#A9EC59")
const COLOR_CYAN := Color("#27C9DF")
const COLOR_SUCCESS := Color("#45CE84")
const COLOR_ERROR := Color("#FF716B")
const COLOR_BLOCKED := Color("#B39E7D")
const COLOR_START := Color("#50C7E7")
const COLOR_GOAL := Color("#6FD18A")

var board := MigrationBoardModel.new()
var level_data: Dictionary = {}
var pan_offset := Vector2.ZERO
var selected_path: Array[Vector2i] = []
var selected_sum := 0
var hint_path: Array[Vector2i] = []
var safe_hint_path: Array[Vector2i] = []
var hint_stage := 0

var selecting := false
var panning := false
var last_pointer := Vector2.ZERO
var completed := false
var completion_overlay_visible := false
var celebration_time := 0.0
var dead_end := false
var previous_board: MigrationBoardModel = null
var undo_stack: Array[MigrationBoardModel] = []

var animal_visual_cell := Vector2.ZERO
var animal_route: Array[Vector2i] = []
var animal_route_progress := 0.0
var animal_animation_frame := 0
var recent_open_path: Array[Vector2i] = []
var recent_open_values := PackedInt32Array()
var road_bloom_progress := 0.0
var goal_indicator_rect := Rect2()
var checkpoint_indicator_rect := Rect2()
var dead_undo_rect := Rect2()
var dead_reshuffle_rect := Rect2()
var dead_reset_rect := Rect2()
var completion_next_rect := Rect2()
var tutorial_step := -1
var tutorial_time := 0.0
var fog_time := 0.0
var fog_redraw_accumulator := 0.0
var recently_revealed_cells: Array[Vector2i] = []
var fog_reveal_progress := 0.0
var ambient_time := 0.0
var ambient_redraw_accumulator := 0.0
var oasis_recovery_progress := 0.0
var feedback_audio: AudioStreamPlayer
var arrival_audio: AudioStreamPlayer
var sound_enabled := true
var vibration_enabled := true
var reduced_motion := false


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	feedback_audio = AudioStreamPlayer.new()
	feedback_audio.volume_db = -3.0
	add_child(feedback_audio)
	arrival_audio = AudioStreamPlayer.new()
	arrival_audio.volume_db = -1.5
	add_child(arrival_audio)
	set_process(true)


func load_level(data: Dictionary) -> void:
	level_data = data.duplicate(true)
	board.load_level(level_data)
	selected_path.clear()
	selected_sum = 0
	hint_path.clear()
	safe_hint_path.clear()
	hint_stage = 0
	selecting = false
	panning = false
	completed = false
	completion_overlay_visible = false
	celebration_time = 0.0
	completion_next_rect = Rect2()
	dead_end = false
	previous_board = null
	undo_stack.clear()
	animal_route.clear()
	animal_route_progress = 0.0
	animal_animation_frame = 0
	recent_open_path.clear()
	recent_open_values.clear()
	road_bloom_progress = 0.0
	tutorial_time = 0.0
	fog_time = 0.0
	fog_redraw_accumulator = 0.0
	recently_revealed_cells.clear()
	fog_reveal_progress = 0.0
	ambient_time = 0.0
	ambient_redraw_accumulator = 0.0
	oasis_recovery_progress = 0.0
	if feedback_audio != null:
		feedback_audio.stop()
	if arrival_audio != null:
		arrival_audio.stop()
	animal_visual_cell = Vector2(board.animal_cell.x, board.animal_cell.y)
	_sync_tutorial_step()
	recenter_on_cell(board.start_cell)
	_emit_status()
	_emit_objectives()
	_emit_checkpoints()
	_emit_watchtowers()
	_refresh_dead_end_state()
	if dead_end:
		_emit_session("开局没有可用路径，已自动暂停并提供恢复操作")
	elif board.total_checkpoints() > 0:
		_emit_session("先沿蓝色水滴指引找到水塘，补给后出口才会开启")
	else:
		_emit_session("从起点边缘连接数字，凑成 24")
	queue_redraw()


func reset_level() -> void:
	load_level(level_data)


func configure_feedback(sound_on: bool, vibration_on: bool, reduce_motion: bool) -> void:
	sound_enabled = sound_on
	vibration_enabled = vibration_on
	reduced_motion = reduce_motion
	if not sound_enabled:
		if feedback_audio != null:
			feedback_audio.stop()
		if arrival_audio != null:
			arrival_audio.stop()
	queue_redraw()


func show_hint() -> void:
	if safe_hint_path.is_empty():
		var solution := StrategySolver.find_solution(board, HINT_STATE_CAP)
		if bool(solution["solved"]):
			safe_hint_path = _typed_path(solution["first_path"])
		elif bool(solution["exhausted"]) and bool(solution["exact"]):
			dead_end = true
			_emit_session("向导确认这条迁徙线无法抵达绿洲，请撤回或请求重整")
			queue_redraw()
			return
		else:
			_emit_session("向导暂时无法确认安全路线，请先撤回一步再观察")
			queue_redraw()
			return
	if safe_hint_path.is_empty():
		return
	hint_stage = mini(hint_stage + 1, 3)
	_set_hint_path_for_stage(safe_hint_path)
	recenter_on_cell(hint_path[0])
	match hint_stage:
		1:
			_emit_session("罗盘提示：从高亮的道路前沿开始观察")
		2:
			_emit_session("方向提示：前两个数字已经标出，继续凑成 24")
		_:
			_emit_session("完整提示：这条路径已确认可以继续抵达绿洲")
	queue_redraw()


func _set_hint_path_for_stage(valid_path: Array[Vector2i]) -> void:
	hint_path.clear()
	var visible_count := valid_path.size()
	if hint_stage == 1:
		visible_count = 1
	elif hint_stage == 2:
		visible_count = mini(2, valid_path.size())
	for index in visible_count:
		hint_path.append(valid_path[index])


func _typed_path(raw_path) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	for cell in raw_path:
		path.append(cell)
	return path


func recenter_on_animals() -> void:
	recenter_on_cell(board.animal_cell)


func recenter_on_goal() -> void:
	recenter_on_cell(board.goal_cell)


func recenter_on_checkpoint() -> void:
	for cell in board.checkpoint_cells:
		if not board.checkpoint_is_visited(cell):
			recenter_on_cell(cell)
			return


func undo_last_opening() -> void:
	if undo_stack.is_empty():
		_emit_session("当前没有可以撤回的开路步骤")
		return
	board = undo_stack.pop_back()
	previous_board = undo_stack.back() if not undo_stack.is_empty() else null
	selected_path.clear()
	selected_sum = 0
	hint_path.clear()
	safe_hint_path.clear()
	hint_stage = 0
	animal_route.clear()
	animal_route_progress = 0.0
	animal_animation_frame = 0
	recent_open_path.clear()
	recent_open_values.clear()
	road_bloom_progress = 0.0
	recently_revealed_cells.clear()
	fog_reveal_progress = 0.0
	animal_visual_cell = Vector2(board.animal_cell.x, board.animal_cell.y)
	completed = false
	completion_overlay_visible = false
	celebration_time = 0.0
	oasis_recovery_progress = 0.0
	completion_next_rect = Rect2()
	_sync_tutorial_step()
	_refresh_dead_end_state()
	recenter_on_animals()
	_emit_status()
	_emit_objectives()
	_emit_checkpoints()
	_emit_watchtowers()
	_emit_session(
		"已撤回上一次开路，还可撤回 %d 步" % undo_stack.size()
		if not undo_stack.is_empty()
		else "已撤回上一次开路，可以重新选择方向"
	)
	queue_redraw()


func reshuffle_dead_end_frontier() -> void:
	if board.reshuffle_frontier_for_valid_path():
		dead_end = false
		safe_hint_path = StrategySolver.find_winning_path(board, HINT_STATE_CAP)
		hint_stage = 1
		_set_hint_path_for_stage(safe_hint_path)
		_emit_session("向导重新整理了路标，这条新路线已经确认能够抵达绿洲")
	else:
		_emit_session("向导无法安全重整当前路线，请撤回上步或重置地图")
	queue_redraw()


func debug_apply_next_intended_path() -> void:
	if completed:
		return
	for raw_path in board.intended_paths:
		var path: Array[Vector2i] = []
		for cell in raw_path:
			path.append(cell)
		if board.path_is_valid(path):
			_commit_valid_path(path)
			selected_path.clear()
			selected_sum = 0
			_emit_status()
			queue_redraw()
			return
	_emit_session("当前没有下一段预设路径")


func debug_apply_branch_path() -> void:
	if completed or board.branch_path.is_empty():
		return
	if board.path_is_valid(board.branch_path):
		_commit_valid_path(board.branch_path)
		selected_path.clear()
		selected_sum = 0
		_emit_status()
		queue_redraw()
	else:
		_emit_session("当前支路尚未与道路前沿连通")


func recenter_on_cell(cell: Vector2i) -> void:
	var center := _cell_center(cell)
	pan_offset = size * 0.5 - center
	_clamp_pan()
	queue_redraw()


func _process(delta: float) -> void:
	var needs_redraw := false
	var transition_delta := delta * (12.0 if reduced_motion else 1.0)
	if selecting:
		var scroll_direction := Vector2.ZERO
		if last_pointer.x < EDGE_SCROLL_MARGIN:
			scroll_direction.x = 1.0
		elif last_pointer.x > size.x - EDGE_SCROLL_MARGIN:
			scroll_direction.x = -1.0
		if last_pointer.y < EDGE_SCROLL_MARGIN:
			scroll_direction.y = 1.0
		elif last_pointer.y > size.y - EDGE_SCROLL_MARGIN:
			scroll_direction.y = -1.0
		if scroll_direction != Vector2.ZERO:
			pan_offset += scroll_direction.normalized() * EDGE_SCROLL_SPEED * delta
			_clamp_pan()
			_update_selection_at(last_pointer)
			needs_redraw = true

	if animal_route.size() >= 2:
		animal_route_progress += transition_delta * 5.0
		var last_index := animal_route.size() - 1
		if animal_route_progress >= last_index:
			animal_visual_cell = Vector2(animal_route[last_index].x, animal_route[last_index].y)
			animal_route.clear()
			animal_route_progress = 0.0
			animal_animation_frame = 0
			if completed and not completion_overlay_visible:
				recenter_on_goal()
				completion_overlay_visible = true
				celebration_time = 0.0
				oasis_recovery_progress = 0.0
				_update_completion_next_rect()
				_play_arrival_sound()
				_emit_session("动物队伍已经抵达新的绿洲！")
				level_completed.emit(board.days)
		else:
			animal_animation_frame = int(floor(ambient_time * 8.0)) % 4
			var from_index := int(floor(animal_route_progress))
			var to_index: int = mini(from_index + 1, last_index)
			var amount := animal_route_progress - from_index
			var from_cell := Vector2(animal_route[from_index].x, animal_route[from_index].y)
			var to_cell := Vector2(animal_route[to_index].x, animal_route[to_index].y)
			animal_visual_cell = from_cell.lerp(to_cell, amount)
			if completed:
				var animal_world := Vector2(
					animal_visual_cell.x + 0.5,
					animal_visual_cell.y + 0.5
				) * CELL_SIZE
				var follow_target := Vector2(size.x * 0.5, size.y * 0.56) - animal_world
				pan_offset = pan_offset.lerp(follow_target, minf(1.0, delta * 4.5))
				_clamp_pan()
		needs_redraw = true

	if not recent_open_path.is_empty():
		road_bloom_progress += transition_delta * 3.6
		var bloom_duration := 1.0 + float(recent_open_path.size() - 1) * 0.12
		if road_bloom_progress >= bloom_duration:
			recent_open_path.clear()
			recent_open_values.clear()
			road_bloom_progress = 0.0
		needs_redraw = true

	if tutorial_step >= 0:
		tutorial_time += delta
		needs_redraw = true

	if int(level_data.get("fog_radius", 0)) > 0:
		if not completed:
			fog_time += 0.0 if reduced_motion else delta
			fog_redraw_accumulator += delta
			if fog_redraw_accumulator >= 0.08:
				fog_redraw_accumulator = 0.0
				needs_redraw = true
		if not recently_revealed_cells.is_empty():
			fog_reveal_progress += transition_delta * 1.15
			if fog_reveal_progress >= 1.18:
				recently_revealed_cells.clear()
				fog_reveal_progress = 0.0
			needs_redraw = true

	ambient_time += 0.0 if reduced_motion else delta
	ambient_redraw_accumulator += delta
	if ambient_redraw_accumulator >= 0.1:
		ambient_redraw_accumulator = 0.0
		needs_redraw = true

	if completion_overlay_visible:
		celebration_time += 0.0 if reduced_motion else delta
		oasis_recovery_progress = minf(
			1.0,
			oasis_recovery_progress + transition_delta / 1.35
		)
		needs_redraw = true

	if needs_redraw:
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if completed:
		if completion_overlay_visible:
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				if completion_next_rect.has_point(event.position):
					next_level_requested.emit()
			elif event is InputEventScreenTouch and event.pressed:
				if completion_next_rect.has_point(event.position):
					next_level_requested.emit()
			accept_event()
		return
	if dead_end:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_handle_dead_end_pointer(event.position)
		elif event is InputEventScreenTouch and event.pressed:
			_handle_dead_end_pointer(event.position)
		accept_event()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_pointer(event.position)
		else:
			_finish_pointer()
		accept_event()
	elif event is InputEventMouseMotion and (selecting or panning):
		_move_pointer(event.position, event.relative)
		accept_event()
	elif event is InputEventScreenTouch:
		if event.pressed:
			_begin_pointer(event.position)
		else:
			_finish_pointer()
		accept_event()
	elif event is InputEventScreenDrag and (selecting or panning):
		_move_pointer(event.position, event.relative)
		accept_event()


func _handle_dead_end_pointer(position: Vector2) -> void:
	_update_dead_end_rects()
	if dead_undo_rect.has_point(position) and previous_board != null:
		undo_last_opening()
	elif dead_reshuffle_rect.has_point(position):
		reshuffle_dead_end_frontier()
	elif dead_reset_rect.has_point(position):
		reset_level()


func _begin_pointer(position: Vector2) -> void:
	last_pointer = position
	if (
		checkpoint_indicator_rect.size != Vector2.ZERO
		and checkpoint_indicator_rect.has_point(position)
	):
		recenter_on_checkpoint()
		_emit_session("先把绿色道路连接到蓝色水塘，完成途中补给")
		return
	if goal_indicator_rect.size != Vector2.ZERO and goal_indicator_rect.has_point(position):
		recenter_on_goal()
		_emit_session("目标绿洲位于唯一出口之外")
		return
	var cell := _cell_at_view_position(position)
	if board.is_frontier(cell):
		selecting = true
		panning = false
		selected_path = [cell]
		selected_sum = board.value_at(cell)
		if tutorial_step == 0:
			tutorial_step = 1
		hint_path.clear()
		_emit_status()
		queue_redraw()
	else:
		selecting = false
		panning = true


func _move_pointer(position: Vector2, relative: Vector2) -> void:
	last_pointer = position
	if panning:
		pan_offset += relative
		_clamp_pan()
		queue_redraw()
	elif selecting:
		_update_selection_at(position)


func _update_selection_at(position: Vector2) -> void:
	var cell := _cell_at_view_position(position)
	if not board.is_in_bounds(cell) or selected_path.is_empty():
		return
	if cell == selected_path.back():
		return
	if selected_path.size() >= 2 and cell == selected_path[selected_path.size() - 2]:
		selected_path.pop_back()
		selected_sum = board.path_sum(selected_path)
		_emit_status()
		queue_redraw()
		return
	if cell in selected_path or not board.is_number_cell(cell):
		return
	var delta: Vector2i = cell - selected_path.back()
	if abs(delta.x) + abs(delta.y) != 1:
		return
	if selected_sum > BoardModel.TARGET_SUM:
		return
	selected_path.append(cell)
	selected_sum += board.value_at(cell)
	_emit_status()
	queue_redraw()


func _finish_pointer() -> void:
	if panning:
		panning = false
		return
	if not selecting:
		return
	selecting = false
	if selected_sum == BoardModel.TARGET_SUM and board.path_is_valid(selected_path):
		_commit_valid_path(selected_path)
	else:
		_play_feedback_sound(SFX_INVALID_PATH)
		if (
			selected_sum == BoardModel.TARGET_SUM
			and board.path_violates_checkpoint_order(selected_path)
		):
			_emit_session("出口尚未开启：请先连接蓝色水塘完成补给")
		else:
			_emit_session("路径未达到 24，已取消")
		_sync_tutorial_step()
	selected_path.clear()
	selected_sum = 0
	_emit_status()
	queue_redraw()


func _commit_valid_path(path: Array[Vector2i]) -> void:
	var movement_route := board.road_route_to_frontier(path[0])
	movement_route.append_array(path)
	var snapshot := board.duplicate_state()
	var hidden_before := _hidden_cells()
	var opening_values := PackedInt32Array()
	for cell in path:
		opening_values.append(board.value_at(cell))
	var rescued_before := board.rescued_partners()
	var checkpoints_before := board.visited_checkpoints()
	var watchtowers_before := board.visited_watchtowers()
	var applied := board.apply_path(path)
	if not applied:
		_emit_session("开发错误：合法路径未能应用")
		return
	_play_feedback_sound(SFX_OPEN_PATH)
	if vibration_enabled:
		Input.vibrate_handheld(28)
	var rescued_now := board.rescued_partners() > rescued_before
	var checkpoint_reached := board.visited_checkpoints() > checkpoints_before
	var watchtower_reached := board.visited_watchtowers() > watchtowers_before
	_emit_objectives()
	_emit_checkpoints()
	_emit_watchtowers()
	_capture_newly_revealed_cells(hidden_before)
	undo_stack.append(snapshot)
	if undo_stack.size() > MAX_UNDO_STEPS:
		undo_stack.pop_front()
	previous_board = undo_stack.back()
	_sync_tutorial_step()
	if board.level_is_complete():
		movement_route.append(board.goal_cell)
	_start_animal_route(movement_route)
	recent_open_path = path.duplicate()
	recent_open_values = opening_values
	road_bloom_progress = 0.0
	hint_path.clear()
	safe_hint_path.clear()
	hint_stage = 0
	if board.level_is_complete():
		completed = true
		dead_end = false
		_emit_session("出口已经打通，动物队伍正在前往绿洲")
	else:
		_refresh_dead_end_state()
	if dead_end:
		_emit_session("道路前沿没有可用路径，已打开恢复面板")
	elif rescued_now and not completed:
		_emit_session("找到了迷路的耳廓狐！它已经加入迁徙队伍")
	elif checkpoint_reached and not completed:
		_emit_session("水塘补给完成！通往目标绿洲的出口已经开启")
	elif watchtower_reached and not completed:
		_emit_session("瞭望点已点亮！高处视野驱散了周围大片薄雾")
	elif not completed:
		_emit_session("开路成功，继续从绿色道路边缘出发")


func _hidden_cells() -> Dictionary:
	var hidden := {}
	var fog_radius := int(level_data.get("fog_radius", 0))
	if fog_radius <= 0:
		return hidden
	for y in board.height:
		for x in board.width:
			var cell := Vector2i(x, y)
			if not _cell_is_revealed(cell, fog_radius):
				hidden[cell] = true
	return hidden


func _capture_newly_revealed_cells(hidden_before: Dictionary) -> void:
	recently_revealed_cells.clear()
	fog_reveal_progress = 0.0
	if hidden_before.is_empty():
		return
	var fog_radius := int(level_data.get("fog_radius", 0))
	for cell_variant in hidden_before.keys():
		var cell: Vector2i = cell_variant
		if _cell_is_revealed(cell, fog_radius):
			recently_revealed_cells.append(cell)
	recently_revealed_cells.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			var a_distance: int = absi(a.x - board.animal_cell.x) + absi(a.y - board.animal_cell.y)
			var b_distance: int = absi(b.x - board.animal_cell.x) + absi(b.y - board.animal_cell.y)
			return a_distance < b_distance
	)


func _start_animal_route(route: Array[Vector2i]) -> void:
	if route.is_empty():
		animal_visual_cell = Vector2(board.animal_cell.x, board.animal_cell.y)
		animal_animation_frame = 0
		return
	animal_route = route.duplicate()
	animal_route_progress = 0.0
	animal_animation_frame = 0
	animal_visual_cell = Vector2(route[0].x, route[0].y)


func _play_feedback_sound(stream: AudioStream) -> void:
	if feedback_audio == null or not sound_enabled:
		return
	feedback_audio.stream = stream
	feedback_audio.play()


func _play_arrival_sound() -> void:
	if arrival_audio == null or not sound_enabled:
		return
	arrival_audio.stream = SFX_ARRIVAL
	arrival_audio.play()


func _clamp_pan() -> void:
	var bounds := _world_bounds()
	var minimum := Vector2(size.x - bounds.end.x, size.y - bounds.end.y)
	var maximum := -bounds.position
	pan_offset.x = clampf(pan_offset.x, minf(minimum.x, maximum.x), maxf(minimum.x, maximum.x))
	pan_offset.y = clampf(pan_offset.y, minf(minimum.y, maximum.y), maxf(minimum.y, maximum.y))


func _world_bounds() -> Rect2:
	return Rect2(
		Vector2(0.0, -CELL_SIZE * OASIS_WORLD_MARGIN),
		Vector2(
			board.width * CELL_SIZE,
			board.height * CELL_SIZE + CELL_SIZE * (OASIS_WORLD_MARGIN + START_WORLD_MARGIN)
		)
	)


func _cell_at_view_position(position: Vector2) -> Vector2i:
	var world_position := position - pan_offset
	return Vector2i(
		int(floor(world_position.x / CELL_SIZE)),
		int(floor(world_position.y / CELL_SIZE))
	)


func _cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(
		Vector2(cell.x, cell.y) * CELL_SIZE + Vector2.ONE * CELL_INSET,
		Vector2.ONE * (CELL_SIZE - CELL_INSET * 2.0)
	)


func _cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell.x + 0.5, cell.y + 0.5) * CELL_SIZE


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_SAND, true)
	draw_set_transform(pan_offset)

	_draw_desert_world()
	_draw_destination_oasis()
	_draw_start_oasis()
	_draw_road_network()

	for y in board.height:
		for x in board.width:
			_draw_cell(Vector2i(x, y))

	_draw_exploration_fog()
	_draw_water_checkpoints()
	_draw_watchtowers()
	_draw_waiting_partners()
	_draw_destination_gate()
	_draw_hint_path()
	_draw_selected_path()
	_draw_road_bloom()
	_draw_migration_flow()
	_draw_tutorial_world_highlight()
	_draw_animals()

	draw_set_transform(Vector2.ZERO)
	_draw_checkpoint_indicator()
	_draw_goal_indicator()
	_draw_tutorial_callout()
	draw_rect(Rect2(Vector2.ZERO, size), Color("#8ACFE8"), false, 5.0)
	if dead_end:
		_draw_dead_end_overlay()
	if completion_overlay_visible:
		_draw_completion_overlay()


func _draw_completion_overlay() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#17395438"), true)
	_draw_celebration_particles()
	var panel := Rect2(size.x * 0.10, size.y * 0.29, size.x * 0.80, 470.0)
	_draw_rounded_rect(
		Rect2(panel.position + Vector2(0, 12), panel.size),
		Color("#24485A4A"),
		50.0
	)
	_draw_rounded_rect(panel, Color("#FFF9ECF8"), 50.0, Color("#70D58D"), 6.0)
	var badge_center := Vector2(panel.get_center().x, panel.position.y + 22.0)
	draw_circle(badge_center + Vector2(0, 7), 56.0, Color("#31515E35"))
	draw_circle(badge_center, 56.0, Color("#66D489"))
	draw_circle(badge_center, 47.0, Color("#EFFFF1"))
	_draw_centered_text("✓", badge_center + Vector2(0, 18), 47, Color("#3BB96A"))
	_draw_centered_text(
		"迁徙路线已打通",
		Vector2(panel.get_center().x, panel.position.y + 116.0),
		46,
		COLOR_NUMBER
	)
	_draw_centered_text(
		"动物队伍安全抵达新绿洲",
		Vector2(panel.get_center().x, panel.position.y + 162.0),
		27,
		Color("#4E7087")
	)
	_draw_completion_badges(panel)
	_draw_centered_text(
		_completion_days_label(),
		Vector2(panel.get_center().x, panel.position.y + 322.0),
		24,
		Color("#3DAF68")
	)
	_update_completion_next_rect()
	_draw_rounded_rect(
		Rect2(completion_next_rect.position + Vector2(0, 6), completion_next_rect.size),
		Color("#31515E38"),
		31.0
	)
	_draw_rounded_rect(completion_next_rect, Color("#38BCE4"), 31.0, Color.WHITE, 4.0)
	var next_label := "继续下一关  ›"
	if bool(level_data.get("is_chapter_final", false)):
		next_label = "完成本章  ›"
	_draw_centered_text(next_label, completion_next_rect.get_center() + Vector2(0, 10), 28, Color.WHITE)


func completion_badge_states() -> Dictionary:
	var recommended := int(level_data.get("recommended_days", 0))
	var optimal := int(level_data.get("optimal_days", recommended))
	var has_partners := board.total_partners() > 0
	var has_watchtowers := board.total_watchtowers() > 0
	var mastery := (
		(
			board.rescued_partners() >= board.total_partners()
			and board.visited_watchtowers() >= board.total_watchtowers()
		)
		if has_partners or has_watchtowers
		else optimal > 0 and board.days <= optimal
	)
	return {
		"arrival": true,
		"efficient": recommended > 0 and board.days <= recommended,
		"mastery": mastery,
	}


func _draw_completion_badges(panel: Rect2) -> void:
	var states := completion_badge_states()
	var labels := [
		["抵达", bool(states["arrival"])],
		["远行家", bool(states["efficient"])],
		[
			"探索"
			if board.total_watchtowers() > 0
			else "伙伴"
			if board.total_partners() > 0
			else "先锋",
			bool(states["mastery"]),
		],
	]
	var spacing := 178.0
	var start_x := panel.get_center().x - spacing
	for index in labels.size():
		var center := Vector2(start_x + float(index) * spacing, panel.position.y + 238.0)
		var achieved := bool(labels[index][1])
		var fill := Color("#65CF87") if achieved else Color("#D9E3E3")
		var text_color := Color("#2C9257") if achieved else Color("#84999E")
		draw_circle(center + Vector2(0, 5), 34.0, Color("#31515E2A"))
		draw_circle(center, 34.0, fill)
		draw_circle(center, 27.0, Color("#F7FFF7") if achieved else Color("#F1F4F3"))
		_draw_centered_text("✓" if achieved else "·", center + Vector2(0, 11), 29, text_color)
		_draw_centered_text(str(labels[index][0]), center + Vector2(0, 61), 21, text_color)


func _completion_days_label() -> String:
	var recommended := int(level_data.get("recommended_days", 0))
	var partner_suffix := ""
	if board.total_partners() > 0:
		partner_suffix = " · 伙伴 %d/%d" % [board.rescued_partners(), board.total_partners()]
	if board.total_watchtowers() > 0:
		partner_suffix += " · 瞭望 %d/%d" % [
			board.visited_watchtowers(),
			board.total_watchtowers(),
		]
	if recommended <= 0:
		return "用了 %d 个迁徙日%s" % [board.days, partner_suffix]
	if board.days <= recommended:
		return "用了 %d 天 · 达成推荐%s" % [board.days, partner_suffix]
	return "用了 %d 天 · 推荐 %d 天%s" % [board.days, recommended, partner_suffix]


func _update_completion_next_rect() -> void:
	var panel := Rect2(size.x * 0.10, size.y * 0.29, size.x * 0.80, 470.0)
	completion_next_rect = Rect2(
		panel.position.x + 170.0,
		panel.position.y + 365.0,
		panel.size.x - 340.0,
		76.0
	)


func _draw_celebration_particles() -> void:
	var center := Vector2(size.x * 0.5, size.y * 0.41)
	var ring_phase := fposmod(celebration_time, 1.4) / 1.4
	var ring_color := Color("#E9FF8C")
	ring_color.a = (1.0 - ring_phase) * 0.62
	draw_circle(center, 80.0 + ring_phase * 210.0, ring_color, false, 9.0, true)
	var colors := [
		Color("#FFF284"),
		Color("#65DA91"),
		Color("#57CBE8"),
		Color("#FF9FA4"),
		Color("#FFFFFF"),
	]
	for index in 18:
		var lane := float(index % 6)
		var cycle := fposmod(
			celebration_time * (0.42 + lane * 0.035) + float(index) * 0.087,
			1.0
		)
		var x := 55.0 + fposmod(float(index) * 173.0, size.x - 110.0)
		x += sin(celebration_time * 2.2 + float(index)) * 24.0
		var y := -30.0 + cycle * (size.y + 80.0)
		var particle_color: Color = colors[index % colors.size()]
		var radius := 5.0 + float(index % 3) * 2.0
		draw_circle(Vector2(x, y), radius, particle_color)
		if index % 2 == 0:
			draw_line(
				Vector2(x - radius * 1.6, y),
				Vector2(x + radius * 1.6, y),
				particle_color,
				4.0,
				true
			)


func _draw_dead_end_overlay() -> void:
	_update_dead_end_rects()
	draw_rect(Rect2(Vector2.ZERO, size), Color("#17395455"), true)
	var panel := Rect2(size.x * 0.08, size.y * 0.32, size.x * 0.84, 360.0)
	_draw_rounded_rect(
		Rect2(panel.position + Vector2(0, 10), panel.size),
		Color("#24485A52"),
		44.0
	)
	_draw_rounded_rect(panel, Color("#FFF9ECFA"), 44.0, Color("#F2C66B"), 6.0)
	_draw_centered_text(
		"队伍在沙丘中迷路了",
		Vector2(panel.get_center().x, panel.position.y + 82),
		43,
		COLOR_NUMBER
	)
	var detail := "迁徙向导会保留已有道路，选择一种方式重新找路"
	if previous_board == null:
		detail = "向导可以重整路标，或带队伍从营地重新出发"
	_draw_centered_text(detail, Vector2(panel.get_center().x, panel.position.y + 132), 24, Color("#557187"))
	_draw_recovery_button(dead_undo_rect, "沿路返回", previous_board != null, Color("#55BEE6"))
	_draw_recovery_button(dead_reshuffle_rect, "请向导重整", true, Color("#68C96A"))
	_draw_recovery_button(dead_reset_rect, "返回营地", true, Color("#F0A952"))


func _update_dead_end_rects() -> void:
	var panel := Rect2(size.x * 0.08, size.y * 0.32, size.x * 0.84, 360.0)
	var button_width := 220.0
	var button_gap := 24.0
	var group_width := button_width * 3.0 + button_gap * 2.0
	var start_x := panel.get_center().x - group_width * 0.5
	var button_y := panel.position.y + 215.0
	dead_undo_rect = Rect2(start_x, button_y, button_width, 86.0)
	dead_reshuffle_rect = Rect2(start_x + button_width + button_gap, button_y, button_width, 86.0)
	dead_reset_rect = Rect2(start_x + (button_width + button_gap) * 2.0, button_y, button_width, 86.0)


func _draw_recovery_button(rect: Rect2, label: String, enabled: bool, accent: Color) -> void:
	var fill := accent if enabled else Color("#C7D0D3")
	var text_color := Color.WHITE if enabled else Color("#7B8D95")
	_draw_rounded_rect(Rect2(rect.position + Vector2(0, 6), rect.size), Color("#31515E3D"), 30.0)
	_draw_rounded_rect(rect, fill, 30.0, Color.WHITE, 4.0)
	_draw_centered_text(label, rect.get_center() + Vector2(0, 10), 25, text_color)


func _draw_destination_oasis() -> void:
	var center := _cell_center(board.goal_cell)
	var oasis_rect := Rect2(center.x - 230.0, -430.0, 460.0, 460.0)
	var oasis_source := Rect2(22.0, 55.0, 1155.0, 1215.0)
	var water_center := Vector2(center.x, -205.0)
	if oasis_recovery_progress > 0.0:
		_draw_oasis_recovery_glow(water_center)
	draw_texture_rect_region(TEXTURE_OASIS, oasis_rect, oasis_source)
	var ripple := (sin(ambient_time * 1.8) + 1.0) * 0.5
	var ripple_color := Color(0.75, 1.0, 1.0, 0.28 * (1.0 - ripple))
	draw_arc(
		water_center,
		43.0 + ripple * 24.0,
		0.0,
		TAU,
		32,
		ripple_color,
		3.0,
		true
	)
	draw_circle(
		water_center + Vector2(-24.0, -18.0),
		3.0 + ripple * 2.0,
		Color("#FFFFFFB8")
	)
	if oasis_recovery_progress > 0.0:
		_draw_oasis_recovery_particles(water_center)


func _draw_oasis_recovery_glow(center: Vector2) -> void:
	var progress := ease(oasis_recovery_progress, 0.35)
	var burst := sin(minf(1.0, oasis_recovery_progress * 1.35) * PI)
	var glow_color := Color("#F5FF9B")
	glow_color.a = 0.10 + burst * 0.18
	draw_circle(center, 105.0 + progress * 82.0, glow_color)
	for ring_index in 2:
		var ring_phase := clampf(
			oasis_recovery_progress * 1.45 - float(ring_index) * 0.22,
			0.0,
			1.0
		)
		if ring_phase <= 0.0 or ring_phase >= 1.0:
			continue
		var ring_color := Color("#F2FFB5")
		ring_color.a = sin(ring_phase * PI) * 0.58
		draw_circle(
			center,
			62.0 + ring_phase * 150.0,
			ring_color,
			false,
			7.0,
			true
		)


func _draw_oasis_recovery_particles(center: Vector2) -> void:
	for particle_index in 14:
		var phase := clampf(
			oasis_recovery_progress * 1.65 - float(particle_index) * 0.035,
			0.0,
			1.0
		)
		if phase <= 0.0 or phase >= 1.0:
			continue
		var angle := float(particle_index) * 2.39996 + phase * 0.45
		var distance := 38.0 + phase * (112.0 + float(particle_index % 3) * 18.0)
		var position := center + Vector2(cos(angle), sin(angle) * 0.68) * distance
		var strength := sin(phase * PI)
		var leaf_color := Color("#B9F36B") if particle_index % 2 == 0 else Color("#FFF089")
		leaf_color.a = strength * 0.92
		var leaf_direction := Vector2(cos(angle + 0.8), sin(angle + 0.8))
		draw_line(
			position - leaf_direction * 5.0,
			position + leaf_direction * 5.0,
			leaf_color,
			4.0 + strength * 2.0,
			true
		)
		if particle_index % 3 == 0:
			var sparkle := Color.WHITE
			sparkle.a = strength * 0.88
			draw_circle(position, 3.0 + strength * 2.0, sparkle)


func _desert_background_rects() -> Array[Rect2]:
	var board_size := Vector2(board.width, board.height) * CELL_SIZE
	var rects: Array[Rect2] = []
	for vertical_index in range(-1, 2):
		rects.append(Rect2(Vector2(0.0, board_size.y * vertical_index), board_size))
	return rects


func _draw_desert_world() -> void:
	var rects := _desert_background_rects()
	for index in rects.size():
		var tint := Color.WHITE
		if index != 1:
			tint = Color("#FFF6DB")
		draw_texture_rect(TEXTURE_DESERT, rects[index], false, tint)
	var board_height := float(board.height) * CELL_SIZE
	_draw_desert_seam_blend(0.0)
	_draw_desert_seam_blend(board_height)


func _draw_desert_seam_blend(seam_y: float) -> void:
	var world_width := float(board.width) * CELL_SIZE
	draw_rect(
		Rect2(Vector2(0.0, seam_y - 13.0), Vector2(world_width, 26.0)),
		Color("#F1C77770")
	)
	draw_rect(
		Rect2(Vector2(0.0, seam_y - 3.0), Vector2(world_width, 6.0)),
		Color("#F2C979")
	)
	var patch_count := int(ceil(world_width / 110.0)) + 1
	for patch_index in patch_count:
		var patch_x := float(patch_index) * 110.0 - 30.0
		var patch_y := seam_y + sin(float(patch_index) * 1.73) * 10.0
		var patch_color := Color("#F4CF83")
		patch_color.a = 0.14 + float(patch_index % 3) * 0.025
		draw_circle(
			Vector2(patch_x, patch_y),
			48.0 + float(patch_index % 2) * 12.0,
			patch_color
		)


func _draw_start_oasis() -> void:
	var center := _cell_center(board.start_cell)
	var oasis_rect := Rect2(center.x - 170.0, center.y - 60.0, 340.0, 310.0)
	var oasis_source := Rect2(115.0, 190.0, 1020.0, 930.0)
	draw_texture_rect_region(TEXTURE_START_OASIS, oasis_rect, oasis_source)
	var water_center := center + Vector2(0.0, 78.0)
	var ripple := (sin(ambient_time * 2.0 + 1.7) + 1.0) * 0.5
	var ripple_color := Color(0.78, 1.0, 1.0, 0.25 * (1.0 - ripple))
	draw_arc(
		water_center,
		36.0 + ripple * 19.0,
		0.0,
		TAU,
		28,
		ripple_color,
		3.0,
		true
	)


func _draw_road_network() -> void:
	var outer := Color("#5BAE4A")
	var inner := Color("#79C94F")
	_draw_road_layer(outer, 100.0, 54.0, 12.0)
	_draw_road_layer(inner, 94.0, 50.0, 9.0)

	for y in board.height:
		for x in board.width:
			var cell := Vector2i(x, y)
			if not board.is_road_cell(cell):
				continue
			var center := _cell_center(cell)
			if board.terrain_at(cell) == BoardModel.Terrain.START:
				continue
			draw_texture_rect(
				TEXTURE_GRASS_TILE,
				Rect2(center - Vector2.ONE * 52.0, Vector2.ONE * 104.0),
				false,
				Color(1.0, 1.0, 1.0, 0.18)
			)
			var edge_offsets := [
				Vector2(-43.0, -7.0),
				Vector2(40.0, 13.0),
				Vector2(-7.0, 42.0),
			]
			for edge_index in edge_offsets.size():
				var wobble := Vector2(
					sin(float(cell.x * 7 + cell.y * 3 + edge_index)) * 3.0,
					cos(float(cell.x * 2 + cell.y * 5 + edge_index)) * 3.0
				)
				draw_circle(
					center + edge_offsets[edge_index] + wobble,
					8.0 + float(edge_index % 2) * 2.0,
					inner
				)


func _draw_road_layer(
	color: Color,
	connection_width: float,
	cell_radius: float,
	lobe_radius: float
) -> void:
	for y in board.height:
		for x in board.width:
			var cell := Vector2i(x, y)
			if not board.is_road_cell(cell):
				continue
			var center := _cell_center(cell)
			for direction in [Vector2i.RIGHT, Vector2i.DOWN]:
				var neighbor: Vector2i = cell + direction
				if not board.is_road_cell(neighbor):
					continue
				var neighbor_center := _cell_center(neighbor)
				draw_line(center, neighbor_center, color, connection_width, true)
				var tangent := (neighbor_center - center).normalized()
				var normal := Vector2(-tangent.y, tangent.x)
				var side := -1.0 if (cell.x + cell.y) % 2 == 0 else 1.0
				var lobe_center := (
					center.lerp(neighbor_center, 0.48)
					+ normal * side * 47.0
				)
				draw_circle(lobe_center, lobe_radius, color)
			var organic_shift := Vector2(
				sin(float(cell.x * 5 + cell.y * 3)) * 3.0,
				cos(float(cell.x * 2 - cell.y * 7)) * 3.0
			)
			draw_circle(center + organic_shift, cell_radius, color)


func _draw_destination_gate() -> void:
	var entry_cells := board.goal_entry_cells()
	if entry_cells.size() != 1:
		return
	var entry := entry_cells[0]
	var gate_center := Vector2(_cell_center(entry).x, 0.0)
	var gate_color := COLOR_GOAL if board.checkpoint_requirements_met() else Color("#96A8AE")
	draw_line(gate_center + Vector2(-38, 0), gate_center + Vector2(38, 0), gate_color, 18.0, true)
	draw_circle(gate_center, 12.0, Color.WHITE)
	if board.checkpoint_requirements_met():
		_draw_centered_text("出口", gate_center + Vector2(0, -18), 20, Color("#317B59"))
	else:
		_draw_centered_text("补给后开启", gate_center + Vector2(0, -18), 18, Color("#657980"))


func _draw_exploration_fog() -> void:
	var fog_radius := int(level_data.get("fog_radius", 0))
	if fog_radius <= 0:
		return
	for y in board.height:
		for x in board.width:
			var cell := Vector2i(x, y)
			if _cell_is_revealed(cell, fog_radius):
				continue
			draw_rect(_cell_rect(cell).grow(3.0), Color("#FFF9E9E8"), true)
	for y in board.height:
		for x in board.width:
			var cell := Vector2i(x, y)
			if _cell_is_revealed(cell, fog_radius) or posmod(x + y * 2, 3) != 0:
				continue
			_draw_fog_cloud_cluster(cell, 1.0, 0.0)

	for index in recently_revealed_cells.size():
		var phase := clampf(fog_reveal_progress - float(index) * 0.035, 0.0, 1.0)
		var opacity := pow(1.0 - phase, 1.7)
		if opacity <= 0.01:
			continue
		var cell := recently_revealed_cells[index]
		var fading_rect := _cell_rect(cell).grow(3.0 - phase * 13.0)
		var veil_color := Color("#FFF9E9")
		veil_color.a = opacity * 0.91
		draw_rect(fading_rect, veil_color, true)
		_draw_fog_cloud_cluster(cell, opacity, phase)


func _draw_fog_cloud_cluster(cell: Vector2i, opacity: float, dispersal: float) -> void:
	var center := _cell_center(cell)
	var drift := sin(float(cell.x * 5 + cell.y * 3) + fog_time * 0.32) * 22.0
	var lift := cos(float(cell.x * 3 - cell.y * 4) + fog_time * 0.24) * 17.0
	var scatter_angle := float(cell.x * 7 + cell.y * 11) * 0.73
	var scatter := Vector2(cos(scatter_angle), sin(scatter_angle) * 0.65) * dispersal * 92.0
	var radius_scale := 1.0 - dispersal * 0.28
	var cloud_core := Color("#FFFFF8")
	var cloud_edge := Color("#FFFFFF")
	var cloud_low := Color("#FFF8E9")
	cloud_core.a = 0.96 * opacity
	cloud_edge.a = 0.91 * opacity
	cloud_low.a = 0.93 * opacity
	draw_circle(
		center + Vector2(-70.0 + drift, 20.0 + lift) + scatter,
		77.0 * radius_scale,
		cloud_edge
	)
	draw_circle(
		center + Vector2(-5.0 + drift, -28.0 + lift) + scatter * 0.72,
		94.0 * radius_scale,
		cloud_core
	)
	draw_circle(
		center + Vector2(72.0 + drift, 13.0 + lift) + scatter * 1.08,
		82.0 * radius_scale,
		cloud_edge
	)
	draw_circle(
		center + Vector2(12.0 + drift, 55.0 + lift) + scatter * 0.88,
		86.0 * radius_scale,
		cloud_low
	)


func _cell_is_revealed(cell: Vector2i, fog_radius := -1) -> bool:
	if fog_radius < 0:
		fog_radius = int(level_data.get("fog_radius", 0))
	if fog_radius <= 0:
		return true
	for y in board.height:
		for x in board.width:
			var road_cell := Vector2i(x, y)
			if not board.is_road_cell(road_cell):
				continue
			if abs(cell.x - road_cell.x) + abs(cell.y - road_cell.y) <= fog_radius:
				return true
	var tower_radius := int(level_data.get("watchtower_reveal_radius", 5))
	for tower in board.visited_watchtower_cells:
		if abs(cell.x - tower.x) + abs(cell.y - tower.y) <= tower_radius:
			return true
	return false


func _draw_watchtowers() -> void:
	for cell in board.watchtower_cells:
		var center := _cell_center(cell)
		var visited := board.watchtower_is_visited(cell)
		var glow := Color("#FFE78455") if visited else Color("#FFFFFFB8")
		draw_circle(center, 52.0, glow)
		draw_circle(
			center,
			48.0,
			Color("#F5C95A") if visited else Color("#E8D6A8"),
			false,
			5.0,
			true
		)
		var tower_color := Color("#9B6A32") if visited else Color("#7D776A")
		draw_polygon(
			PackedVector2Array([
				center + Vector2(-20, 30),
				center + Vector2(-10, -19),
				center + Vector2(10, -19),
				center + Vector2(20, 30),
			]),
			PackedColorArray([tower_color])
		)
		draw_line(center + Vector2(0, -18), center + Vector2(0, -48), tower_color, 5.0)
		draw_colored_polygon(
			PackedVector2Array([
				center + Vector2(2, -47),
				center + Vector2(30, -37),
				center + Vector2(2, -27),
			]),
			Color("#62CE83") if visited else Color("#F0B74C")
		)
		if visited:
			_draw_centered_text("✓", center + Vector2(0, 14), 25, Color.WHITE)


func _draw_water_checkpoints() -> void:
	for cell in board.checkpoint_cells:
		var center := _cell_center(cell)
		var visited := board.checkpoint_is_visited(cell)
		if visited:
			draw_circle(center + Vector2(0, 7), 49.0, Color("#31515E30"))
			draw_circle(center, 47.0, Color("#79D9EF"))
			draw_circle(center + Vector2(-10, -10), 29.0, Color("#A9F0FA"))
			draw_circle(center, 47.0, Color.WHITE, false, 5.0, true)
			_draw_centered_text("✓", center + Vector2(0, 13), 29, Color("#218DAE"))
			continue
		var rect := _cell_rect(cell).grow(-2.0)
		draw_style_box(_make_style(Color.TRANSPARENT, Color("#27BDE0"), 6.0, 27.0), rect)
		var badge_center := center + Vector2(38.0, -38.0)
		draw_circle(badge_center + Vector2(0, 5), 35.0, Color("#31515E35"))
		draw_circle(badge_center, 34.0, Color("#E9FCFF"))
		draw_circle(badge_center, 34.0, Color("#28BFE1"), false, 5.0, true)
		_draw_centered_text("水", badge_center + Vector2(0, 10), 24, Color("#178BAB"))


func _draw_checkpoint_indicator() -> void:
	checkpoint_indicator_rect = Rect2()
	if completed or board.checkpoint_requirements_met():
		return
	var checkpoint := Vector2i(-1, -1)
	for cell in board.checkpoint_cells:
		if not board.checkpoint_is_visited(cell):
			checkpoint = cell
			break
	if checkpoint.x < 0:
		return
	var checkpoint_view_position := _cell_center(checkpoint) + pan_offset
	var safe_rect := Rect2(
		Vector2.ONE * GOAL_SAFE_INSET,
		size - Vector2.ONE * GOAL_SAFE_INSET * 2.0
	)
	if safe_rect.has_point(checkpoint_view_position):
		return
	var screen_center := size * 0.5
	var direction := checkpoint_view_position - screen_center
	if direction.length_squared() < 0.01:
		return
	var marker_position := _ray_rect_intersection(screen_center, direction, safe_rect)
	checkpoint_indicator_rect = Rect2(
		marker_position - Vector2.ONE * GOAL_INDICATOR_RADIUS,
		Vector2.ONE * GOAL_INDICATOR_RADIUS * 2.0
	)
	var inward := (screen_center - marker_position).normalized()
	draw_dashed_line(
		marker_position + inward * (GOAL_INDICATOR_RADIUS + 5.0),
		marker_position + inward * (GOAL_INDICATOR_RADIUS + 42.0),
		Color("#28BFE1"),
		5.0,
		9.0
	)
	draw_circle(marker_position + Vector2(0, 5), GOAL_INDICATOR_RADIUS + 5.0, Color("#37556A40"))
	draw_circle(marker_position, GOAL_INDICATOR_RADIUS, Color("#FFFFFFF2"))
	draw_circle(marker_position, GOAL_INDICATOR_RADIUS, Color("#28BFE1"), false, 5.0)
	_draw_centered_text("水", marker_position + Vector2(0, 12), 28, Color("#178BAB"))


func _draw_goal_indicator() -> void:
	goal_indicator_rect = Rect2()
	if completed or not board.checkpoint_requirements_met():
		return

	var goal_view_position := _cell_center(board.goal_cell) + pan_offset
	var safe_rect := Rect2(
		Vector2.ONE * GOAL_SAFE_INSET,
		size - Vector2.ONE * GOAL_SAFE_INSET * 2.0
	)
	if safe_rect.has_point(goal_view_position):
		return

	var screen_center := size * 0.5
	var direction := goal_view_position - screen_center
	if direction.length_squared() < 0.01:
		return
	var marker_position := _ray_rect_intersection(screen_center, direction, safe_rect)
	goal_indicator_rect = Rect2(
		marker_position - Vector2.ONE * GOAL_INDICATOR_RADIUS,
		Vector2.ONE * GOAL_INDICATOR_RADIUS * 2.0
	)

	var inward := (screen_center - marker_position).normalized()
	draw_dashed_line(
		marker_position + inward * (GOAL_INDICATOR_RADIUS + 5.0),
		marker_position + inward * (GOAL_INDICATOR_RADIUS + 42.0),
		Color("#49A970"),
		5.0,
		9.0
	)
	draw_circle(marker_position + Vector2(0, 5), GOAL_INDICATOR_RADIUS + 5.0, Color("#37556A40"))
	draw_circle(marker_position, GOAL_INDICATOR_RADIUS, Color("#FFFFFFF2"))
	draw_circle(marker_position, GOAL_INDICATOR_RADIUS, COLOR_GOAL, false, 5.0)
	var icon_rect := Rect2(marker_position - Vector2(31, 33), Vector2(62, 66))
	var oasis_source := Rect2(22.0, 55.0, 1155.0, 1215.0)
	draw_texture_rect_region(TEXTURE_OASIS, icon_rect, oasis_source)


func _ray_rect_intersection(origin: Vector2, direction: Vector2, rect: Rect2) -> Vector2:
	var horizontal_t := INF
	var vertical_t := INF
	if direction.x > 0.0:
		horizontal_t = (rect.end.x - origin.x) / direction.x
	elif direction.x < 0.0:
		horizontal_t = (rect.position.x - origin.x) / direction.x
	if direction.y > 0.0:
		vertical_t = (rect.end.y - origin.y) / direction.y
	elif direction.y < 0.0:
		vertical_t = (rect.position.y - origin.y) / direction.y
	var amount := minf(horizontal_t, vertical_t)
	return origin + direction * amount


func _draw_cell(cell: Vector2i) -> void:
	var kind := board.terrain_at(cell)
	var rect := _cell_rect(cell)
	var center := _cell_center(cell)
	match kind:
		BoardModel.Terrain.NUMBER:
			draw_texture_rect(TEXTURE_SANDSTONE_TILE, rect.grow(10.0), false)
			_draw_centered_text(str(board.value_at(cell)), center + Vector2(0, 17), 50, Color("#49331F"))
			if board.is_frontier(cell):
				var marker := rect.position + Vector2(rect.size.x - 15, 17)
				draw_circle(marker + Vector2(0, 3), 10.0, Color("#31515E36"))
				draw_circle(marker, 8.0, COLOR_CYAN)
				draw_circle(marker + Vector2(-2, -2), 3.0, Color.WHITE)
		BoardModel.Terrain.ROAD:
			_draw_road_surface_details(cell, center)
		BoardModel.Terrain.BLOCKED:
			_draw_blocked_cell(cell, center)
		BoardModel.Terrain.START:
			pass
		BoardModel.Terrain.GOAL:
			draw_circle(center, 52.0, COLOR_GOAL)
			draw_circle(center, 52.0, Color.WHITE, false, 7.0)
			_draw_centered_text("终", center + Vector2(0, 11), 29, COLOR_NUMBER)


func _obstacle_variant(cell: Vector2i) -> int:
	var level_index := int(level_data.get("level_index", 1))
	return posmod(cell.x * 17 + cell.y * 31 + level_index * 13, 3)


func _draw_blocked_cell(cell: Vector2i, center: Vector2) -> void:
	var variant := _obstacle_variant(cell)
	var shadow_rect := Rect2(center + Vector2(-42.0, 30.0), Vector2(84.0, 22.0))
	if variant == 1:
		shadow_rect = Rect2(center + Vector2(-48.0, 25.0), Vector2(96.0, 21.0))
	elif variant == 2:
		shadow_rect = Rect2(center + Vector2(-39.0, 33.0), Vector2(78.0, 21.0))
	_draw_rounded_rect(shadow_rect, Color("#624A2D2B"), 11.0)

	match variant:
		1:
			var low_rect := Rect2(center - Vector2(63.0, 48.0), Vector2(126.0, 100.0))
			var low_source := Rect2(100.0, 190.0, 1050.0, 850.0)
			draw_texture_rect_region(TEXTURE_ROCKS_LOW, low_rect, low_source)
		2:
			var cactus_rect := Rect2(center - Vector2(56.0, 68.0), Vector2(112.0, 126.0))
			var cactus_source := Rect2(160.0, 100.0, 930.0, 1050.0)
			draw_texture_rect_region(TEXTURE_CACTUS, cactus_rect, cactus_source)
		_:
			var rock_rect := Rect2(center - Vector2(59.0, 56.0), Vector2(118.0, 112.0))
			var rock_source := Rect2(145.0, 185.0, 970.0, 830.0)
			draw_texture_rect_region(TEXTURE_ROCKS, rock_rect, rock_source)


func _draw_road_surface_details(cell: Vector2i, center: Vector2) -> void:
	var seed := absi(cell.x * 92821 + cell.y * 68917)
	var blade_anchor := center + Vector2(
		-30.0 + float(seed % 19),
		-15.0 + float((seed / 19) % 25)
	)
	draw_line(blade_anchor, blade_anchor + Vector2(-4.0, -14.0), Color("#4EA944"), 3.0, true)
	draw_line(blade_anchor, blade_anchor + Vector2(5.0, -11.0), Color("#63B849"), 3.0, true)

	var flower_anchor := center + Vector2(
		12.0 + float((seed / 31) % 23),
		12.0 + float((seed / 71) % 19)
	)
	var petal_color := Color("#FFF7CE")
	if seed % 3 == 1:
		petal_color = Color("#F7A6BE")
	elif seed % 3 == 2:
		petal_color = Color("#D8B7FF")
	for petal_index in 4:
		var angle := float(petal_index) * PI * 0.5
		draw_circle(
			flower_anchor + Vector2(cos(angle), sin(angle)) * 4.5,
			3.4,
			petal_color
		)
	draw_circle(flower_anchor, 2.6, Color("#FFD65A"))

	if seed % 2 == 0:
		var tiny_flower := center + Vector2(
			-20.0 + float((seed / 101) % 15),
			24.0 - float((seed / 211) % 13)
		)
		draw_circle(tiny_flower + Vector2(-2.5, 0.0), 2.5, Color.WHITE)
		draw_circle(tiny_flower + Vector2(2.5, 0.0), 2.5, Color.WHITE)
		draw_circle(tiny_flower, 1.8, Color("#FFD65A"))


func _draw_hint_path() -> void:
	if hint_path.is_empty():
		return
	for index in hint_path.size():
		var rect := _cell_rect(hint_path[index]).grow(-4.0)
		draw_style_box(_make_style(Color.TRANSPARENT, COLOR_CYAN, 5.0, 23.0), rect)
		if index > 0:
			draw_dashed_line(
				_cell_center(hint_path[index - 1]),
				_cell_center(hint_path[index]),
				COLOR_CYAN,
				6.0,
				12.0
			)


func _draw_selected_path() -> void:
	if selected_path.is_empty():
		return
	var accent := COLOR_CYAN
	if selected_sum == BoardModel.TARGET_SUM:
		accent = COLOR_SUCCESS
	elif selected_sum > BoardModel.TARGET_SUM:
		accent = COLOR_ERROR
	for index in selected_path.size():
		if index > 0:
			draw_line(
				_cell_center(selected_path[index - 1]),
				_cell_center(selected_path[index]),
				accent,
				18.0,
				true
			)
	for cell in selected_path:
		var rect := _cell_rect(cell)
		draw_circle(_cell_center(cell), 67.0, Color("#76F4FF4A"))
		draw_texture_rect(TEXTURE_GRASS_TILE, rect.grow(11.0), false)
		draw_style_box(_make_style(Color.TRANSPARENT, accent, 6.0, 28.0), rect.grow(1.0))
		_draw_centered_text(
			str(board.value_at(cell)),
			_cell_center(cell) + Vector2(0, 17),
			50,
			Color("#17573F")
		)


func _draw_road_bloom() -> void:
	if recent_open_path.is_empty():
		return
	for index in recent_open_path.size():
		var phase := road_bloom_progress - float(index) * 0.12
		if phase < 0.0 or phase > 1.0:
			continue
		var cell := recent_open_path[index]
		var rect := _cell_rect(cell)
		var center := _cell_center(cell)
		var grass_phase := clampf((phase - 0.10) / 0.58, 0.0, 1.0)
		var stone_phase := clampf(phase / 0.52, 0.0, 1.0)

		if grass_phase > 0.0:
			var grow := sin(grass_phase * PI * 0.5)
			var grass_size := (rect.size + Vector2.ONE * 22.0) * grow
			var grass_rect := Rect2(center - grass_size * 0.5, grass_size)
			var grass_color := Color.WHITE
			grass_color.a = 0.72 + grass_phase * 0.28
			draw_texture_rect(TEXTURE_GRASS_TILE, grass_rect, false, grass_color)

		if stone_phase < 1.0 and index < recent_open_values.size():
			var flip_height := maxf(
				3.0,
				(rect.size.y + 20.0) * absf(cos(stone_phase * PI * 0.5))
			)
			var stone_rect := Rect2(
				Vector2(rect.position.x - 10.0, center.y - flip_height * 0.5 + stone_phase * 7.0),
				Vector2(rect.size.x + 20.0, flip_height)
			)
			var stone_color := Color.WHITE
			stone_color.a = 1.0 - stone_phase * 0.12
			draw_texture_rect(TEXTURE_SANDSTONE_TILE, stone_rect, false, stone_color)
			var number_color := Color("#49331F")
			number_color.a = pow(1.0 - stone_phase, 0.65)
			_draw_centered_text(
				str(recent_open_values[index]),
				center + Vector2(0.0, 17.0 + stone_phase * 7.0),
				50,
				number_color
			)

		var strength := sin(phase * PI)
		var ring_color := Color("#D9FF85")
		ring_color.a = strength * 0.9
		draw_circle(center, 18.0 + phase * 43.0, ring_color, false, 8.0, true)
		var dust_phase := clampf((phase - 0.26) / 0.64, 0.0, 1.0)
		var dust_strength := sin(dust_phase * PI)
		for dust_index in 6:
			var dust_angle := (
				float(dust_index) * TAU / 6.0
				+ float(index) * 0.73
				+ dust_phase * 0.35
			)
			var dust_distance := 20.0 + dust_phase * (35.0 + float(dust_index % 2) * 10.0)
			var dust_position := center + Vector2(cos(dust_angle), sin(dust_angle)) * dust_distance
			var dust_color := Color("#E9BE72")
			dust_color.a = dust_strength * 0.72
			draw_circle(
				dust_position,
				2.5 + dust_strength * (3.5 + float(dust_index % 3)),
				dust_color
			)
		for spark_index in 4:
			var angle := float(spark_index) * PI * 0.5 + float(index) * 0.7
			var distance := 25.0 + phase * 36.0
			var spark := center + Vector2(cos(angle), sin(angle)) * distance
			var spark_color := Color.WHITE
			spark_color.a = strength * 0.85
			draw_circle(spark, 3.0 + strength * 3.0, spark_color)


func _draw_migration_flow() -> void:
	if not completed or animal_route.size() < 2:
		return
	for index in animal_route.size() - 1:
		var from := _cell_center(animal_route[index])
		var to := _cell_center(animal_route[index + 1])
		draw_line(from, to, Color("#ECFFC6A0"), 7.0, true)
		var travel_phase := fposmod(ambient_time * 1.8 - float(index) * 0.17, 1.0)
		if travel_phase >= 0.32:
			continue
		var amount := travel_phase / 0.32
		var glow_strength := sin(amount * PI)
		var glow_point := from.lerp(to, amount)
		var glow_color := Color("#F8FFD9")
		glow_color.a = glow_strength * 0.62
		draw_circle(glow_point, 13.0 + glow_strength * 4.0, glow_color)
		var core_color := Color.WHITE
		core_color.a = glow_strength * 0.92
		draw_circle(glow_point, 4.0 + glow_strength * 2.0, core_color)


func _draw_tutorial_world_highlight() -> void:
	if tutorial_step < 0 or dead_end or completed:
		return
	var focus_cell := _tutorial_focus_cell()
	if not board.is_in_bounds(focus_cell):
		return
	var center := _cell_center(focus_cell)
	var pulse := (sin(tutorial_time * 4.0) + 1.0) * 0.5
	var color := Color("#31D4E8")
	color.a = 0.55 + pulse * 0.35
	draw_circle(center, 62.0 + pulse * 8.0, color, false, 7.0, true)
	draw_circle(center, 72.0 + pulse * 10.0, Color(1.0, 1.0, 1.0, 0.22), false, 4.0, true)


func _draw_tutorial_callout() -> void:
	if tutorial_step < 0 or dead_end or completed:
		return
	var focus_cell := _tutorial_focus_cell()
	if not board.is_in_bounds(focus_cell):
		return
	var focus := _cell_center(focus_cell) + pan_offset
	var bubble_size := Vector2(560.0, 104.0)
	var bubble_x := clampf(focus.x - bubble_size.x * 0.5, 24.0, size.x - bubble_size.x - 24.0)
	var place_above := focus.y >= 165.0
	var bubble_y := focus.y - 142.0 if place_above else focus.y + 52.0
	bubble_y = clampf(bubble_y, 22.0, size.y - bubble_size.y - 22.0)
	var bubble := Rect2(Vector2(bubble_x, bubble_y), bubble_size)
	var pointer_x := clampf(focus.x, bubble.position.x + 45.0, bubble.end.x - 45.0)
	var pointer := PackedVector2Array()
	if place_above:
		pointer = PackedVector2Array([
			Vector2(pointer_x - 18.0, bubble.end.y - 2.0),
			Vector2(pointer_x + 18.0, bubble.end.y - 2.0),
			Vector2(focus.x, minf(focus.y - 8.0, bubble.end.y + 34.0)),
		])
	else:
		pointer = PackedVector2Array([
			Vector2(pointer_x - 18.0, bubble.position.y + 2.0),
			Vector2(pointer_x + 18.0, bubble.position.y + 2.0),
			Vector2(focus.x, maxf(focus.y + 8.0, bubble.position.y - 34.0)),
		])
	draw_colored_polygon(pointer, Color("#FFF9EAF5"))
	_draw_rounded_rect(Rect2(bubble.position + Vector2(0, 7), bubble.size), Color("#31515E35"), 32.0)
	_draw_rounded_rect(bubble, Color("#FFF9EAF7"), 32.0, Color("#50CBE1"), 5.0)
	var step_label := "第 %d 步" % (tutorial_step + 1)
	var message := "按住带蓝点的数字开始连线"
	if tutorial_step == 1:
		message = "继续拖过相邻数字，让总和达到 24"
	elif tutorial_step == 2:
		message = "草路已经长出，从新的道路边缘继续"
	var step_rect := Rect2(bubble.position + Vector2(18.0, 24.0), Vector2(92.0, 54.0))
	_draw_rounded_rect(step_rect, Color("#D9F7FC"), 23.0)
	_draw_centered_text(step_label, step_rect.get_center() + Vector2(0, 7), 19, Color("#249DB4"))
	_draw_centered_text(
		message,
		Vector2(bubble.position.x + 332.0, bubble.position.y + 64.0),
		25,
		COLOR_NUMBER
	)


func _tutorial_focus_cell() -> Vector2i:
	if tutorial_step == 1 and not selected_path.is_empty():
		return selected_path.back()
	var path := board.find_valid_path()
	if not path.is_empty():
		return path[0]
	return board.start_cell


func _draw_animals() -> void:
	var center := Vector2(animal_visual_cell.x + 0.5, animal_visual_cell.y + 0.5) * CELL_SIZE
	if not animal_route.is_empty():
		center.y += sin(ambient_time * 8.0 * PI) * 3.0
	else:
		center.y += sin(ambient_time * 2.1) * 2.6
	var breath := 1.0 + sin(ambient_time * 1.7) * 0.007
	var visual_size := Vector2(190.0 * (2.0 - breath), 235.0 * breath)
	var top_left := center + Vector2(-visual_size.x * 0.5, -180.0)
	top_left.x = clampf(top_left.x, 8.0, board.width * CELL_SIZE - visual_size.x - 8.0)
	var destination := Rect2(top_left, visual_size)
	draw_circle(center + Vector2(0.0, 18.0), 47.0, Color("#31515E24"))
	draw_texture_rect_region(
		_animal_texture_for_frame(animal_animation_frame),
		destination,
		ANIMAL_SOURCE_RECT
	)
	if board.rescued_partners() > 0:
		var partner_rect := Rect2(center + Vector2(35.0, -112.0), Vector2(82.0, 92.0))
		draw_texture_rect(TEXTURE_LOST_PARTNER, partner_rect, false)


func _animal_texture_for_frame(frame: int) -> Texture2D:
	match posmod(frame, 4):
		1:
			return TEXTURE_ANIMALS_WALK_LEFT
		3:
			return TEXTURE_ANIMALS_WALK_RIGHT
		_:
			return TEXTURE_ANIMALS


func _draw_waiting_partners() -> void:
	for cell in board.partner_cells:
		if board.partner_is_rescued(cell):
			continue
		var center := _cell_center(cell)
		var badge_center := center + Vector2(35.0, -35.0)
		draw_circle(badge_center + Vector2(0, 5), 43.0, Color("#31515E35"))
		draw_circle(badge_center, 41.0, Color("#FFF9EAF2"))
		draw_circle(badge_center, 41.0, Color("#45C9DF"), false, 5.0, true)
		var partner_rect := Rect2(badge_center - Vector2(35.0, 39.0), Vector2(70.0, 78.0))
		draw_texture_rect(TEXTURE_LOST_PARTNER, partner_rect, false)


func _refresh_dead_end_state() -> void:
	dead_end = not board.level_is_complete() and not board.has_valid_path()


func _sync_tutorial_step() -> void:
	if not bool(level_data.get("tutorial", false)):
		tutorial_step = -1
	elif board.days == 0:
		tutorial_step = 0
	elif board.days == 1:
		tutorial_step = 2
	else:
		tutorial_step = -1


func _emit_status() -> void:
	var label := "还差 %d" % (BoardModel.TARGET_SUM - selected_sum)
	var accent := COLOR_CYAN
	if selected_sum == 0:
		label = "从道路边缘开始"
	elif selected_sum == BoardModel.TARGET_SUM:
		label = "可以开路"
		accent = COLOR_SUCCESS
	elif selected_sum > BoardModel.TARGET_SUM:
		label = "超过 %d，向后拖动" % (selected_sum - BoardModel.TARGET_SUM)
		accent = COLOR_ERROR
	status_changed.emit(selected_sum, label, accent)


func _emit_session(message: String) -> void:
	session_changed.emit(board.level_name, board.days, message)


func _emit_objectives() -> void:
	objectives_changed.emit(board.rescued_partners(), board.total_partners())


func _emit_checkpoints() -> void:
	checkpoints_changed.emit(board.visited_checkpoints(), board.total_checkpoints())


func _emit_watchtowers() -> void:
	watchtowers_changed.emit(board.visited_watchtowers(), board.total_watchtowers())


func _draw_rounded_rect(
	rect: Rect2,
	fill: Color,
	radius: float,
	border := Color.TRANSPARENT,
	border_width := 0.0
) -> void:
	draw_style_box(_make_style(fill, border, border_width, radius), rect)


func _make_style(fill: Color, border: Color, border_width: float, radius: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(int(radius))
	if border_width > 0.0:
		style.border_color = border
		style.set_border_width_all(int(border_width))
	return style


func _draw_centered_text(text: String, center: Vector2, font_size: int, color: Color) -> void:
	text = Localization.text(text)
	var font := ThemeDB.fallback_font
	var width := maxf(1.0, font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	draw_string(
		font,
		Vector2(center.x - width * 0.5, center.y),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		color
	)
