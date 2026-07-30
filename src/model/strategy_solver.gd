extends RefCounted
class_name MigrationStrategySolver

# Runtime-safe breadth-first search over road states. Unlike find_valid_path(),
# a returned move is backed by a complete sequence all the way to the oasis.

const DEFAULT_STATE_CAP := 12000
const DEFAULT_MOVE_CAP := 400
const DEFAULT_NODE_CAP := 200000


static func find_solution(
	board,
	state_cap := DEFAULT_STATE_CAP,
	move_cap := DEFAULT_MOVE_CAP,
	node_cap := DEFAULT_NODE_CAP
) -> Dictionary:
	if board.level_is_complete():
		return _result(true, true, true, [], 1)

	var initial = board.duplicate_state()
	var states: Array = [initial]
	var parents := PackedInt32Array([-1])
	var incoming_moves: Array = [[]]
	var ids := {_state_key(initial): 0}
	var head := 0
	var enumeration_exact := true

	while head < states.size():
		if head >= state_cap:
			return _result(false, false, enumeration_exact, [], states.size())
		var current = states[head]
		var enumeration := enumerate_valid_paths(current, move_cap, node_cap)
		if bool(enumeration["capped"]):
			enumeration_exact = false
		var paths: Array = enumeration["paths"]
		_sort_paths_for_authored_progress(paths, current)
		for raw_path in paths:
			var path := _typed_path(raw_path)
			var next = current.duplicate_state()
			if not next.apply_path(path):
				continue
			var key := _state_key(next)
			if ids.has(key):
				continue
			var next_id := states.size()
			ids[key] = next_id
			states.append(next)
			parents.append(head)
			incoming_moves.append(path)
			if next.level_is_complete():
				var sequence := _reconstruct_sequence(next_id, parents, incoming_moves)
				return _result(true, true, enumeration_exact, sequence, states.size())
		head += 1

	return _result(false, true, enumeration_exact, [], states.size())


static func find_winning_path(
	board,
	state_cap := DEFAULT_STATE_CAP,
	move_cap := DEFAULT_MOVE_CAP,
	node_cap := DEFAULT_NODE_CAP
) -> Array[Vector2i]:
	var result := find_solution(board, state_cap, move_cap, node_cap)
	if not bool(result["solved"]):
		return []
	var sequence: Array = result["sequence"]
	if sequence.is_empty():
		return []
	return _typed_path(sequence[0])


static func path_has_winning_continuation(
	board,
	path: Array[Vector2i],
	state_cap := DEFAULT_STATE_CAP
) -> bool:
	if not board.path_is_valid(path):
		return false
	var next = board.duplicate_state()
	if not next.apply_path(path):
		return false
	return bool(find_solution(next, state_cap)["solved"])


static func enumerate_valid_paths(board, move_cap := DEFAULT_MOVE_CAP, node_cap := DEFAULT_NODE_CAP) -> Dictionary:
	var result := {
		"paths": [],
		"nodes": 0,
		"capped": false,
	}
	for y in board.height:
		for x in board.width:
			var cell := Vector2i(x, y)
			if not board.is_frontier(cell):
				continue
			var working: Array[Vector2i] = []
			_enumerate_from(board, cell, 0, working, result, move_cap, node_cap)
			if bool(result["capped"]):
				return result
	return result


static func _enumerate_from(
	board,
	cell: Vector2i,
	current_sum: int,
	working: Array[Vector2i],
	result: Dictionary,
	move_cap: int,
	node_cap: int
) -> void:
	if bool(result["capped"]):
		return
	result["nodes"] = int(result["nodes"]) + 1
	if int(result["nodes"]) > node_cap or (result["paths"] as Array).size() >= move_cap:
		result["capped"] = true
		return
	if not board.is_number_cell(cell) or cell in working:
		return
	var next_sum: int = current_sum + board.value_at(cell)
	if next_sum > board.TARGET_SUM:
		return
	working.append(cell)
	if next_sum == board.TARGET_SUM:
		if not board.path_violates_checkpoint_order(working):
			(result["paths"] as Array).append(working.duplicate())
	else:
		for direction in board.DIRECTIONS:
			_enumerate_from(
				board,
				cell + direction,
				next_sum,
				working,
				result,
				move_cap,
				node_cap
			)
	working.pop_back()


static func _sort_paths_for_authored_progress(paths: Array, board) -> void:
	paths.sort_custom(
		func(a, b) -> bool:
			var a_path := _typed_path(a)
			var b_path := _typed_path(b)
			var a_score := _authored_score(a_path, board)
			var b_score := _authored_score(b_path, board)
			if a_score != b_score:
				return a_score > b_score
			return _goal_distance(a_path, board.goal_cell) < _goal_distance(b_path, board.goal_cell)
	)


static func _authored_score(path: Array[Vector2i], board) -> int:
	var path_cells := {}
	for cell in path:
		path_cells[cell] = true
	var best_overlap := 0
	var exact_match := false
	for raw_authored in board.intended_paths:
		var authored := _typed_path(raw_authored)
		var remaining := 0
		var overlap := 0
		for cell in authored:
			if board.is_number_cell(cell):
				remaining += 1
				if path_cells.has(cell):
					overlap += 1
		best_overlap = maxi(best_overlap, overlap)
		if remaining == path.size() and overlap == remaining:
			exact_match = true
	return (1000 if exact_match else 0) + best_overlap * 10 + path.size()


static func _goal_distance(path: Array[Vector2i], goal: Vector2i) -> int:
	var best := 1 << 30
	for cell in path:
		best = mini(best, absi(cell.x - goal.x) + absi(cell.y - goal.y))
	return best


static func _state_key(board) -> String:
	var checkpoint_mask := 0
	for index in board.checkpoint_cells.size():
		if board.checkpoint_cells[index] in board.visited_checkpoint_cells:
			checkpoint_mask |= 1 << index
	var bytes := PackedByteArray()
	bytes.resize(board.terrain.size() + 1)
	for index in board.terrain.size():
		bytes[index] = board.terrain[index]
	bytes[board.terrain.size()] = checkpoint_mask
	return bytes.hex_encode()


static func _reconstruct_sequence(
	state_id: int,
	parents: PackedInt32Array,
	incoming_moves: Array
) -> Array:
	var sequence: Array = []
	var cursor := state_id
	while cursor > 0:
		sequence.push_front(_typed_path(incoming_moves[cursor]))
		cursor = parents[cursor]
	return sequence


static func _result(
	solved: bool,
	exhausted: bool,
	exact: bool,
	sequence: Array,
	states: int
) -> Dictionary:
	return {
		"solved": solved,
		"exhausted": exhausted,
		"exact": exact,
		"sequence": sequence,
		"first_path": _typed_path(sequence[0]) if not sequence.is_empty() else [],
		"states": states,
	}


static func _typed_path(raw_path) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	for cell in raw_path:
		path.append(cell)
	return path
