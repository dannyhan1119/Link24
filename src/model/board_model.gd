extends RefCounted
class_name MigrationBoardModel

enum Terrain {
	NUMBER,
	ROAD,
	BLOCKED,
	START,
	GOAL,
}

const TARGET_SUM := 24
const DIRECTIONS: Array[Vector2i] = [
	Vector2i.LEFT,
	Vector2i.RIGHT,
	Vector2i.UP,
	Vector2i.DOWN,
]
const RESHUFFLE_CHAIN_LENGTHS := [4, 3, 5, 2]
const RESHUFFLE_TEMPLATES := {
	2: [
		[12, 12],
	],
	3: [
		[12, 11, 1],
		[9, 8, 7],
		[11, 8, 5],
		[10, 9, 5],
		[12, 9, 3],
		[10, 7, 7],
	],
	4: [
		[11, 7, 4, 2],
		[10, 8, 5, 1],
		[9, 8, 4, 3],
		[8, 7, 6, 3],
		[7, 6, 6, 5],
		[9, 6, 5, 4],
	],
	5: [
		[8, 6, 5, 3, 2],
		[7, 6, 5, 4, 2],
		[6, 6, 5, 4, 3],
		[9, 5, 4, 3, 3],
		[8, 5, 4, 4, 3],
		[7, 5, 5, 4, 3],
	],
}

var width := 8
var height := 12
var level_name := ""
var numbers := PackedInt32Array()
var terrain := PackedInt32Array()
var start_cell := Vector2i.ZERO
var goal_cell := Vector2i.ZERO
var animal_cell := Vector2i.ZERO
var days := 0
var intended_paths: Array = []
var branch_path: Array[Vector2i] = []
var partner_cells: Array[Vector2i] = []
var rescued_partner_cells: Array[Vector2i] = []
var checkpoint_cells: Array[Vector2i] = []
var visited_checkpoint_cells: Array[Vector2i] = []
var watchtower_cells: Array[Vector2i] = []
var visited_watchtower_cells: Array[Vector2i] = []


func load_level(data: Dictionary) -> void:
	width = int(data.get("width", 8))
	height = int(data.get("height", 12))
	level_name = str(data.get("name", "测试地图"))
	numbers = data["numbers"].duplicate()
	terrain = data["terrain"].duplicate()
	start_cell = data["start"]
	goal_cell = data["goal"]
	animal_cell = start_cell
	days = 0
	intended_paths = data.get("intended_paths", []).duplicate(true)
	branch_path.clear()
	for cell in data.get("branch_path", []):
		branch_path.append(cell)
	partner_cells.clear()
	for cell in data.get("partner_cells", []):
		partner_cells.append(cell)
	rescued_partner_cells.clear()
	checkpoint_cells.clear()
	for cell in data.get("checkpoint_cells", []):
		checkpoint_cells.append(cell)
	visited_checkpoint_cells.clear()
	watchtower_cells.clear()
	for cell in data.get("watchtower_cells", []):
		watchtower_cells.append(cell)
	visited_watchtower_cells.clear()


func duplicate_state() -> MigrationBoardModel:
	var copy := MigrationBoardModel.new()
	copy.width = width
	copy.height = height
	copy.level_name = level_name
	copy.numbers = numbers.duplicate()
	copy.terrain = terrain.duplicate()
	copy.start_cell = start_cell
	copy.goal_cell = goal_cell
	copy.animal_cell = animal_cell
	copy.days = days
	copy.intended_paths = intended_paths.duplicate(true)
	copy.branch_path = branch_path.duplicate()
	copy.partner_cells = partner_cells.duplicate()
	copy.rescued_partner_cells = rescued_partner_cells.duplicate()
	copy.checkpoint_cells = checkpoint_cells.duplicate()
	copy.visited_checkpoint_cells = visited_checkpoint_cells.duplicate()
	copy.watchtower_cells = watchtower_cells.duplicate()
	copy.visited_watchtower_cells = visited_watchtower_cells.duplicate()
	return copy


func is_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


func goal_is_outside_board() -> bool:
	return not is_in_bounds(goal_cell)


func goal_entry_cells() -> Array[Vector2i]:
	var entries: Array[Vector2i] = []
	for direction in DIRECTIONS:
		var neighbor := goal_cell + direction
		if is_in_bounds(neighbor):
			entries.append(neighbor)
	return entries


func index_of(cell: Vector2i) -> int:
	return cell.y * width + cell.x


func terrain_at(cell: Vector2i) -> Terrain:
	if not is_in_bounds(cell):
		return Terrain.BLOCKED
	return terrain[index_of(cell)] as Terrain


func value_at(cell: Vector2i) -> int:
	if not is_in_bounds(cell):
		return 0
	return numbers[index_of(cell)]


func is_road_cell(cell: Vector2i) -> bool:
	var kind := terrain_at(cell)
	return kind == Terrain.ROAD or kind == Terrain.START


func is_number_cell(cell: Vector2i) -> bool:
	return terrain_at(cell) == Terrain.NUMBER and value_at(cell) > 0


func is_frontier(cell: Vector2i) -> bool:
	if not is_number_cell(cell):
		return false
	for direction in DIRECTIONS:
		if is_road_cell(cell + direction):
			return true
	return false


func path_sum(path: Array[Vector2i]) -> int:
	var total := 0
	for cell in path:
		total += value_at(cell)
	return total


func path_is_valid(path: Array[Vector2i], require_exact := true) -> bool:
	if path.is_empty() or not is_frontier(path[0]):
		return false
	var seen := {}
	for index in path.size():
		var cell := path[index]
		if not is_number_cell(cell) or seen.has(cell):
			return false
		seen[cell] = true
		if index > 0:
			var delta: Vector2i = cell - path[index - 1]
			if abs(delta.x) + abs(delta.y) != 1:
				return false
	var total := path_sum(path)
	var sum_is_valid := total == TARGET_SUM if require_exact else total <= TARGET_SUM
	return sum_is_valid and not path_violates_checkpoint_order(path)


func path_violates_checkpoint_order(path: Array[Vector2i]) -> bool:
	if checkpoint_cells.is_empty():
		return false
	var reached_checkpoints: Array[Vector2i] = visited_checkpoint_cells.duplicate()
	var entries := goal_entry_cells()
	for cell in path:
		if cell in checkpoint_cells and cell not in reached_checkpoints:
			reached_checkpoints.append(cell)
		if cell in entries and reached_checkpoints.size() < checkpoint_cells.size():
			return true
	return false


func road_route_to_frontier(first_cell: Vector2i) -> Array[Vector2i]:
	if not is_frontier(first_cell):
		return []
	var targets: Array[Vector2i] = []
	for direction in DIRECTIONS:
		var neighbor := first_cell + direction
		if is_road_cell(neighbor):
			targets.append(neighbor)
	return _find_road_route(animal_cell, targets)


func _find_road_route(from_cell: Vector2i, targets: Array[Vector2i]) -> Array[Vector2i]:
	if targets.is_empty() or not is_road_cell(from_cell):
		return []
	var target_lookup := {}
	for target in targets:
		target_lookup[target] = true
	var queue: Array[Vector2i] = [from_cell]
	var head := 0
	var previous := {from_cell: from_cell}
	var found := Vector2i(-1, -1)
	while head < queue.size():
		var current := queue[head]
		head += 1
		if target_lookup.has(current):
			found = current
			break
		for direction in DIRECTIONS:
			var neighbor := current + direction
			if is_road_cell(neighbor) and not previous.has(neighbor):
				previous[neighbor] = current
				queue.append(neighbor)
	if found.x < 0:
		return []
	var route: Array[Vector2i] = []
	var cursor := found
	while true:
		route.push_front(cursor)
		if cursor == from_cell:
			break
		cursor = previous[cursor]
	return route


func apply_path(path: Array[Vector2i]) -> bool:
	if not path_is_valid(path):
		return false
	for cell in path:
		var index := index_of(cell)
		terrain[index] = Terrain.ROAD
		numbers[index] = 0
		if cell in partner_cells and cell not in rescued_partner_cells:
			rescued_partner_cells.append(cell)
		if cell in checkpoint_cells and cell not in visited_checkpoint_cells:
			visited_checkpoint_cells.append(cell)
		if cell in watchtower_cells and cell not in visited_watchtower_cells:
			visited_watchtower_cells.append(cell)
	days += 1
	animal_cell = path.back()
	return true


func total_partners() -> int:
	return partner_cells.size()


func rescued_partners() -> int:
	return rescued_partner_cells.size()


func partner_is_rescued(cell: Vector2i) -> bool:
	return cell in rescued_partner_cells


func total_checkpoints() -> int:
	return checkpoint_cells.size()


func visited_checkpoints() -> int:
	return visited_checkpoint_cells.size()


func checkpoint_is_visited(cell: Vector2i) -> bool:
	return cell in visited_checkpoint_cells


func checkpoint_requirements_met() -> bool:
	return visited_checkpoint_cells.size() >= checkpoint_cells.size()


func total_watchtowers() -> int:
	return watchtower_cells.size()


func visited_watchtowers() -> int:
	return visited_watchtower_cells.size()


func watchtower_is_visited(cell: Vector2i) -> bool:
	return cell in visited_watchtower_cells


func goal_is_connected() -> bool:
	var queue: Array[Vector2i] = [start_cell]
	var head := 0
	var visited := {start_cell: true}
	while head < queue.size():
		var current := queue[head]
		head += 1
		for direction in DIRECTIONS:
			var neighbor := current + direction
			if neighbor == goal_cell:
				return true
			if is_road_cell(neighbor) and not visited.has(neighbor):
				visited[neighbor] = true
				queue.append(neighbor)
	return false


func level_is_complete() -> bool:
	return checkpoint_requirements_met() and goal_is_connected()


func find_valid_path() -> Array[Vector2i]:
	for y in height:
		for x in width:
			var cell := Vector2i(x, y)
			if not is_frontier(cell):
				continue
			var working: Array[Vector2i] = []
			var result: Array[Vector2i] = []
			if _find_path_depth_first(cell, 0, working, result):
				return result
	return []


func has_valid_path() -> bool:
	return not find_valid_path().is_empty()


func reshuffle_frontier_for_valid_path() -> bool:
	# Recovery should adapt to the remaining board instead of stamping the same
	# 7/8/9 answer into every dead end. Try several useful path lengths, choose a
	# deterministic template from the board state, and validate with the exact
	# gameplay rules before keeping any changed values.
	for target_size in RESHUFFLE_CHAIN_LENGTHS:
		var chains := _frontier_number_chains(int(target_size), 48)
		for chain_variant in chains:
			var chain: Array[Vector2i] = chain_variant
			if path_violates_checkpoint_order(chain):
				continue
			var templates: Array = RESHUFFLE_TEMPLATES[int(target_size)]
			var start_index := posmod(
				days
				+ chain[0].x * 7
				+ chain[0].y * 11
				+ chain.back().x * 13
				+ chain.back().y * 17,
				templates.size()
			)
			for template_offset in templates.size():
				var values: Array = templates[
					posmod(start_index + template_offset, templates.size())
				].duplicate()
				if posmod(chain[0].x + chain[0].y + days, 2) == 1:
					values.reverse()
				var previous_values := PackedInt32Array()
				for cell in chain:
					previous_values.append(value_at(cell))
				for index in chain.size():
					numbers[index_of(chain[index])] = int(values[index])
				if path_is_valid(chain):
					return true
				for index in chain.size():
					numbers[index_of(chain[index])] = previous_values[index]
	return false


func _frontier_number_chains(target_size: int, limit: int) -> Array:
	var chains: Array = []
	for y in height:
		for x in width:
			var cell := Vector2i(x, y)
			if not is_frontier(cell):
				continue
			var working: Array[Vector2i] = []
			_collect_number_chains(cell, target_size, working, chains, limit)
			if chains.size() >= limit:
				return chains
	return chains


func _collect_number_chains(
	cell: Vector2i,
	target_size: int,
	working: Array[Vector2i],
	results: Array,
	limit: int
) -> void:
	if results.size() >= limit:
		return
	if not is_number_cell(cell) or cell in working:
		return
	working.append(cell)
	if working.size() == target_size:
		results.append(working.duplicate())
		working.pop_back()
		return
	for direction in DIRECTIONS:
		_collect_number_chains(cell + direction, target_size, working, results, limit)
		if results.size() >= limit:
			break
	working.pop_back()


func _find_path_depth_first(
	cell: Vector2i,
	current_sum: int,
	working: Array[Vector2i],
	result: Array[Vector2i]
) -> bool:
	if not is_number_cell(cell) or cell in working:
		return false
	var next_sum := current_sum + value_at(cell)
	if next_sum > TARGET_SUM:
		return false
	working.append(cell)
	if next_sum == TARGET_SUM:
		if not path_violates_checkpoint_order(working):
			result.append_array(working)
		working.pop_back()
		return not result.is_empty()
	for direction in DIRECTIONS:
		var neighbor := cell + direction
		if _find_path_depth_first(neighbor, next_sum, working, result):
			working.pop_back()
			return true
	working.pop_back()
	return false
