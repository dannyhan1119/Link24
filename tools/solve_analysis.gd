extends SceneTree

# 离线解空间分析脚本（只读关卡数据，不写存档）。
# 运行：
#   /Applications/Godot_mono.app/Contents/MacOS/Godot \
#     --headless --path . --script res://tools/solve_analysis.gd
#
# 输出四个指标：
#   1. 作者路线逐步分析（前沿数 / 有意义选择数 / 合法 24 路径总数与长度分布）
#   2. 真实最少天数（状态空间 BFS，超限退化为深度受限 DFS 探测更短解）
#   3. 未设计路径（与作者主/支路线零重叠的合法路径占比）
#   4. 模板依赖（作者路线各段数字组合频次）

const BoardModel = preload("res://src/model/board_model.gd")
const LevelCatalog = preload("res://src/model/level_catalog.gd")

const TARGET_SUM := 24
const DIRS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

const ENUM_NODE_CAP := 1000000      # 指标 1/3 单步路径枚举节点上限
const BFS_STATE_CAP := 200000       # 指标 2 状态空间上限
const BFS_TIME_CAP_MS := 20000      # 指标 2 单关 BFS 时间上限
const DFS_TIME_CAP_MS := 15000      # 指标 2 退化 DFS 追加时间上限
const BFS_MOVE_CAP := 400           # 单状态动作（合法路径）枚举上限
const BFS_ENUM_NODE_CAP := 200000   # BFS 内单状态枚举节点上限
const MAX_AVG_MEANINGFUL_CHOICES := 6.0
const MAX_AVG_DISJOINT_PERCENT := 40.0


func _initialize() -> void:
	var levels := LevelCatalog.playable_levels()
	print("绿洲迁徙 · 解空间分析 · %d 关" % levels.size())
	print("预算: 枚举节点上限=%d, BFS状态上限=%d, 单关BFS=%ds, 退化DFS=%ds, 单状态动作上限=%d" % [
		ENUM_NODE_CAP, BFS_STATE_CAP, BFS_TIME_CAP_MS / 1000, DFS_TIME_CAP_MS / 1000, BFS_MOVE_CAP,
	])

	var template_counts := {}
	var template_len_counts := {}
	var summaries: Array = []

	for li in levels.size():
		var level: Dictionary = levels[li]
		var rec := int(level["recommended_days"])
		print("")
		print("=== 关卡 %d/20 [%s] %s | 推荐 %d 天 | 检查点 %d ===" % [
			li + 1, str(level["id"]), str(level["name"]), rec,
			(level["checkpoint_cells"] as Array).size(),
		])

		var steps := _analyze_author_route(level)
		var segs := _segment_templates(level, template_counts, template_len_counts)
		print("  作者路线模板: %s" % ", ".join(segs))

		var search := _search_min_days(level)
		var shorter: bool = int(search["days"]) >= 0 and int(search["days"]) < rec
		match search["status"]:
			"exact":
				print("  最少天数: %d 天 (精确, BFS %d 状态, %.1fs)%s%s" % [
					search["days"], search["states"], search["ms"] / 1000.0,
					" <<< 比推荐短" if shorter else " (= 推荐)" if search["days"] == rec else " (> 推荐!)",
					" [枚举触顶,为近似值]" if search["approx"] else "",
				])
			"shorter_found":
				print("  最少天数: <= %d 天 (BFS 预算耗尽, 退化 DFS 找到 %d 天解, 比推荐 %d 短; 精确值未知)%s" % [
					search["days"], search["days"], rec,
					" [枚举触顶]" if search["approx"] else "",
				])
			"not_shorter":
				print("  最少天数: %d 天 (= 推荐; 预算内已证实不存在 <= %d 天的解, BFS %d 状态)%s" % [
					rec, rec - 1, search["states"],
					" [枚举触顶,结论为近似]" if search["approx"] else "",
				])
			_:
				print("  最少天数: 未知 (BFS %d 状态/%.1fs 与 DFS 均预算耗尽, 只确知 <= 推荐 %d 天)%s" % [
					search["states"], search["ms"] / 1000.0, rec,
					" [枚举触顶]" if search["approx"] else "",
				])

		summaries.append({
			"id": str(level["id"]),
			"name": str(level["name"]),
			"rec": rec,
			"steps": steps,
			"search": search,
		})

	_print_summary(summaries, template_counts, template_len_counts)
	var target_failures := _score_target_failures(summaries)
	if target_failures.is_empty():
		print("")
		print(
			"关卡质量校验: PASS（精确评分一致，选择密度与未设计路径均在阈值内）"
		)
	else:
		print("")
		print("关卡质量校验: FAIL")
		for failure in target_failures:
			print("  - %s" % failure)
	var validation_requested := "--validate" in OS.get_cmdline_user_args()
	quit(1 if validation_requested and not target_failures.is_empty() else 0)


func _score_target_failures(summaries: Array) -> PackedStringArray:
	var failures := PackedStringArray()
	for summary in summaries:
		var level_id := str(summary["id"])
		var level: Dictionary = {}
		for candidate in LevelCatalog.playable_levels():
			if str(candidate["id"]) == level_id:
				level = candidate
				break
		if level.is_empty():
			failures.append("%s 缺少关卡数据" % level_id)
			continue
		var search: Dictionary = summary["search"]
		if str(search["status"]) != "exact" or bool(search["approx"]):
			failures.append("%s 未得到可作为评分依据的精确最优解" % level_id)
			continue
		var solved_days := int(search["days"])
		var declared_optimal := int(level.get("optimal_days", 0))
		var recommended := int(level.get("recommended_days", 0))
		if declared_optimal != solved_days:
			failures.append(
				"%s optimal_days=%d，但求解器结果为 %d" % [
					level_id, declared_optimal, solved_days,
				]
			)
		if recommended != declared_optimal + 1:
			failures.append(
				"%s recommended_days=%d，应为 optimal_days+1=%d" % [
					level_id, recommended, declared_optimal + 1,
				]
			)
		var steps: Array = summary["steps"]
		var meaningful_sum := 0.0
		var disjoint_sum := 0.0
		var disjoint_count := 0
		for step in steps:
			meaningful_sum += float(step["meaningful"])
			if int(step["count"]) > 0:
				disjoint_sum += 100.0 * float(step["disjoint"]) / float(step["count"])
				disjoint_count += 1
		var meaningful_avg := meaningful_sum / maxf(1.0, float(steps.size()))
		var disjoint_avg := disjoint_sum / maxf(1.0, float(disjoint_count))
		if meaningful_avg > MAX_AVG_MEANINGFUL_CHOICES:
			failures.append(
				"%s 平均可行动前沿 %.1f，超过 %.1f 的选择密度上限" % [
					level_id, meaningful_avg, MAX_AVG_MEANINGFUL_CHOICES,
				]
			)
		if disjoint_avg > MAX_AVG_DISJOINT_PERCENT:
			failures.append(
				"%s 平均未设计路径 %.0f%%，超过 %.0f%% 的噪音上限" % [
					level_id, disjoint_avg, MAX_AVG_DISJOINT_PERCENT,
				]
			)
	return failures


# ---------------------------------------------------------------- 指标 1 & 3

func _analyze_author_route(level: Dictionary) -> Array:
	var board: RefCounted = BoardModel.new()
	board.load_level(level)
	var route := {}
	for raw in level["intended_paths"]:
		for cell in raw:
			route[cell] = true
	# Explicit rescue/watchtower detours are authored exploration, not accidental
	# filler noise. The metric only counts paths disjoint from all designed routes.
	for raw in level.get("branch_paths", []):
		for cell in raw:
			route[cell] = true
	var steps: Array = []
	var step_index := 0
	for raw in level["intended_paths"]:
		step_index += 1
		var frontier := _frontier_cells(board)
		var budget := {"n": 0}
		var meaningful := 0
		for cell in frontier:
			if _has_path_from(board, cell, budget):
				meaningful += 1
		var stats := _enumerate_paths(board, ENUM_NODE_CAP, 100000000, false, route)
		var count: int = stats["count"]
		var disjoint: int = stats["disjoint"]
		var pct := 100.0 * disjoint / count if count > 0 else 0.0
		print("  步骤%d: 前沿=%d 有意义选择=%d 合法路径=%s 长度[2:%d 3:%d 4:%d 5:%d 6+:%d] 未设计路径(不碰主/支路)=%d/%d (%.0f%%)%s" % [
			step_index, frontier.size(), meaningful,
			str(count) if count <= 100 else "100+(=%d)" % count,
			stats["hist"]["2"], stats["hist"]["3"], stats["hist"]["4"],
			stats["hist"]["5"], stats["hist"]["6+"],
			disjoint, count, pct,
			" [枚举触顶!]" if stats["capped"] else "",
		])
		steps.append({
			"frontier": frontier.size(),
			"meaningful": meaningful,
			"count": count,
			"disjoint": disjoint,
			"capped": stats["capped"],
		})
		var path: Array[Vector2i] = []
		for cell in raw:
			path.append(cell)
		if not board.apply_path(path):
			print("  !! 作者路线第 %d 段 apply_path 失败（与 tests 断言矛盾）" % step_index)
	return steps


# ------------------------------------------------------------------- 指标 4

func _segment_templates(level: Dictionary, template_counts: Dictionary, len_counts: Dictionary) -> Array:
	var board: RefCounted = BoardModel.new()
	board.load_level(level)
	var segs: Array = []
	for raw in level["intended_paths"]:
		var vals: Array = []
		for cell in raw:
			vals.append(board.value_at(cell))
		vals.sort()
		vals.reverse()
		var parts := PackedStringArray()
		for v in vals:
			parts.append(str(v))
		var key := "+".join(parts)
		segs.append("%s(%d格)" % [key, vals.size()])
		template_counts[key] = int(template_counts.get(key, 0)) + 1
		var len_key := "%d格段" % vals.size()
		len_counts[len_key] = int(len_counts.get(len_key, 0)) + 1
	return segs


# ------------------------------------------------------------------- 指标 2

func _search_min_days(level: Dictionary) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var board: RefCounted = BoardModel.new()
	board.load_level(level)
	var width: int = board.width
	var height: int = board.height
	var start_cell: Vector2i = board.start_cell
	var goal_cell: Vector2i = board.goal_cell
	var checkpoints: Array = level["checkpoint_cells"]
	var full_mask := (1 << checkpoints.size()) - 1
	var rec := int(level["recommended_days"])

	var result := {"status": "unknown", "days": -1, "states": 0, "ms": 0, "approx": false}

	var start_terrain: PackedInt32Array = board.terrain.duplicate()
	var queue: Array = [{"terrain": start_terrain, "cmask": 0, "days": 0}]
	var visited := {_state_key(start_terrain, 0): true}
	var head := 0
	var bfs_aborted := false

	while head < queue.size():
		if head >= BFS_STATE_CAP or Time.get_ticks_msec() - t0 > BFS_TIME_CAP_MS:
			bfs_aborted = true
			break
		var st: Dictionary = queue[head]
		head += 1
		board.terrain = st["terrain"]
		board.visited_checkpoint_cells = _mask_to_list(checkpoints, int(st["cmask"]))
		var stats := _enumerate_paths(board, BFS_ENUM_NODE_CAP, BFS_MOVE_CAP, true, {})
		if stats["capped"]:
			result["approx"] = true
		var seen_moves := {}
		for path in stats["paths"]:
			var mkey := _move_key(path, width)
			if seen_moves.has(mkey):
				continue
			seen_moves[mkey] = true
			var succ: PackedInt32Array = (st["terrain"] as PackedInt32Array).duplicate()
			var nmask: int = st["cmask"]
			for cell in path:
				succ[cell.y * width + cell.x] = BoardModel.Terrain.ROAD
				var ci := checkpoints.find(cell)
				if ci >= 0:
					nmask |= 1 << ci
			var skey := _state_key(succ, nmask)
			if visited.has(skey):
				continue
			visited[skey] = true
			var ndays: int = st["days"] + 1
			if nmask == full_mask and _goal_connected(succ, width, height, start_cell, goal_cell):
				result["status"] = "exact"
				result["days"] = ndays
				result["states"] = visited.size()
				result["ms"] = Time.get_ticks_msec() - t0
				return result
			queue.append({"terrain": succ, "cmask": nmask, "days": ndays})

	result["states"] = visited.size()
	result["ms"] = Time.get_ticks_msec() - t0

	if not bfs_aborted:
		# 队列耗尽仍未通关（动作上限截断才可能发生），按未知处理
		if result["approx"]:
			return result
		result["status"] = "not_shorter"  # 完整状态空间无解（理论上不会，作者路线保证有解）
		return result

	# BFS 预算耗尽：退化深度受限 DFS，探测是否存在比推荐更短的解
	var deadline := Time.get_ticks_msec() + DFS_TIME_CAP_MS
	var ctx := {
		"deadline": deadline,
		"aborted": false,
		"memo": {},
		"approx": result["approx"],
	}
	var found := _dfs_probe(
		board, checkpoints, full_mask, width, height, start_cell, goal_cell,
		start_terrain, 0, rec - 1, ctx
	)
	result["ms"] = Time.get_ticks_msec() - t0
	result["approx"] = ctx["approx"]
	if found:
		result["status"] = "shorter_found"
		result["days"] = rec - 1  # DFS 找到的是 <= rec-1 的某个解，深度上限即 rec-1
	elif not ctx["aborted"]:
		result["status"] = "not_shorter"
	return result


func _dfs_probe(
	board: RefCounted,
	checkpoints: Array,
	full_mask: int,
	width: int,
	height: int,
	start_cell: Vector2i,
	goal_cell: Vector2i,
	terrain: PackedInt32Array,
	cmask: int,
	depth_left: int,
	ctx: Dictionary
) -> bool:
	if ctx["aborted"] or depth_left <= 0:
		return false
	if Time.get_ticks_msec() > int(ctx["deadline"]):
		ctx["aborted"] = true
		return false
	var skey := _state_key(terrain, cmask)
	var memo: Dictionary = ctx["memo"]
	if memo.has(skey) and int(memo[skey]) >= depth_left:
		return false
	memo[skey] = depth_left

	board.terrain = terrain
	board.visited_checkpoint_cells = _mask_to_list(checkpoints, cmask)
	var stats := _enumerate_paths(board, BFS_ENUM_NODE_CAP, BFS_MOVE_CAP, true, {})
	if stats["capped"]:
		ctx["approx"] = true
	var seen_moves := {}
	for path in stats["paths"]:
		var mkey := _move_key(path, width)
		if seen_moves.has(mkey):
			continue
		seen_moves[mkey] = true
		var succ: PackedInt32Array = terrain.duplicate()
		var nmask := cmask
		for cell in path:
			succ[cell.y * width + cell.x] = BoardModel.Terrain.ROAD
			var ci := checkpoints.find(cell)
			if ci >= 0:
				nmask |= 1 << ci
		if nmask == full_mask and _goal_connected(succ, width, height, start_cell, goal_cell):
			return true
		if _dfs_probe(
			board, checkpoints, full_mask, width, height, start_cell, goal_cell,
			succ, nmask, depth_left - 1, ctx
		):
			return true
		if ctx["aborted"]:
			return false
	return false


# ------------------------------------------------------------------ 枚举工具

func _frontier_cells(board: RefCounted) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in board.height:
		for x in board.width:
			var cell := Vector2i(x, y)
			if board.is_frontier(cell):
				cells.append(cell)
	return cells


func _has_path_from(board: RefCounted, start: Vector2i, budget: Dictionary) -> bool:
	var working: Array[Vector2i] = []
	return _find_dfs(board, start, 0, working, budget)


func _find_dfs(
	board: RefCounted, cell: Vector2i, sum: int, working: Array[Vector2i], budget: Dictionary
) -> bool:
	budget["n"] = int(budget["n"]) + 1
	if int(budget["n"]) > ENUM_NODE_CAP:
		return false
	if not board.is_number_cell(cell) or cell in working:
		return false
	var next_sum: int = sum + board.value_at(cell)
	if next_sum > TARGET_SUM:
		return false
	working.append(cell)
	if next_sum == TARGET_SUM:
		var ok: bool = not board.path_violates_checkpoint_order(working)
		working.pop_back()
		return ok
	for direction in BoardModel.DIRECTIONS:
		if _find_dfs(board, cell + direction, next_sum, working, budget):
			working.pop_back()
			return true
	working.pop_back()
	return false


func _enumerate_paths(
	board: RefCounted, node_cap: int, count_cap: int, collect: bool, route: Dictionary
) -> Dictionary:
	var stats := {
		"nodes": 0,
		"capped": false,
		"count": 0,
		"disjoint": 0,
		"hist": {"2": 0, "3": 0, "4": 0, "5": 0, "6+": 0},
		"paths": [],
		"route": route,
	}
	for y in board.height:
		for x in board.width:
			var cell := Vector2i(x, y)
			if not board.is_frontier(cell):
				continue
			var working: Array[Vector2i] = []
			_enum_dfs(board, cell, 0, working, stats, node_cap, count_cap, collect)
			if stats["capped"]:
				return stats
	return stats


func _enum_dfs(
	board: RefCounted,
	cell: Vector2i,
	sum: int,
	working: Array[Vector2i],
	stats: Dictionary,
	node_cap: int,
	count_cap: int,
	collect: bool
) -> void:
	if stats["capped"]:
		return
	stats["nodes"] = int(stats["nodes"]) + 1
	if int(stats["nodes"]) > node_cap or int(stats["count"]) > count_cap:
		stats["capped"] = true
		return
	if not board.is_number_cell(cell) or cell in working:
		return
	var next_sum: int = sum + board.value_at(cell)
	if next_sum > TARGET_SUM:
		return
	working.append(cell)
	if next_sum == TARGET_SUM:
		if not board.path_violates_checkpoint_order(working):
			stats["count"] = int(stats["count"]) + 1
			var size := working.size()
			var key := str(size) if size <= 5 else "6+"
			stats["hist"][key] = int(stats["hist"][key]) + 1
			var overlapped := false
			for c in working:
				if (stats["route"] as Dictionary).has(c):
					overlapped = true
					break
			if not overlapped:
				stats["disjoint"] = int(stats["disjoint"]) + 1
			if collect:
				(stats["paths"] as Array).append(working.duplicate())
	else:
		for direction in BoardModel.DIRECTIONS:
			_enum_dfs(
				board, cell + direction, next_sum, working, stats, node_cap, count_cap, collect
			)
	working.pop_back()


# ------------------------------------------------------------------ 状态工具

func _state_key(terrain: PackedInt32Array, cmask: int) -> String:
	var bytes := PackedByteArray()
	bytes.resize(terrain.size() + 1)
	for i in terrain.size():
		bytes[i] = terrain[i]
	bytes[terrain.size()] = cmask
	return bytes.hex_encode()


func _move_key(path: Array, width: int) -> String:
	var indices: Array = []
	for cell in path:
		indices.append(cell.y * width + cell.x)
	indices.sort()
	var key := ""
	for i in indices:
		key += "%d," % i
	return key


func _mask_to_list(checkpoints: Array, mask: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in checkpoints.size():
		if mask & (1 << i):
			out.append(checkpoints[i])
	return out


func _goal_connected(
	terrain: PackedInt32Array, width: int, height: int, start_cell: Vector2i, goal_cell: Vector2i
) -> bool:
	var visited := {start_cell: true}
	var queue: Array[Vector2i] = [start_cell]
	var head := 0
	while head < queue.size():
		var current := queue[head]
		head += 1
		for direction in DIRS:
			var neighbor: Vector2i = current + direction
			if neighbor == goal_cell:
				return true
			if neighbor.x < 0 or neighbor.y < 0 or neighbor.x >= width or neighbor.y >= height:
				continue
			var t: int = terrain[neighbor.y * width + neighbor.x]
			if (
				(t == BoardModel.Terrain.ROAD or t == BoardModel.Terrain.START)
				and not visited.has(neighbor)
			):
				visited[neighbor] = true
				queue.append(neighbor)
	return false


# ------------------------------------------------------------------ 总计输出

func _print_summary(summaries: Array, template_counts: Dictionary, len_counts: Dictionary) -> void:
	print("")
	print("==================== 总计 ====================")
	print("")
	print("-- 模板依赖（20 关作者路线全部 %d 段）--" % _sum_values(template_counts))
	var keys := template_counts.keys()
	keys.sort_custom(func(a, b): return int(template_counts[a]) > int(template_counts[b]))
	for key in keys:
		print("  %-12s : %d 次" % [key, int(template_counts[key])])
	var len_keys := len_counts.keys()
	len_keys.sort()
	for key in len_keys:
		print("  %-12s : %d 次" % [key, int(len_counts[key])])

	print("")
	print("-- 每关汇总 --")
	print("  %-10s %-4s %-8s %-14s %-14s %-10s" % [
		"关卡", "推荐", "最少天数", "有意义选择avg", "选择数越界步数", "未设计路径avg%"
	])
	var shorter_levels: Array = []
	for s in summaries:
		var steps: Array = s["steps"]
		var m_sum := 0.0
		var out_of_range := 0
		var d_sum := 0.0
		var d_cnt := 0
		for st in steps:
			m_sum += st["meaningful"]
			if st["meaningful"] < 2 or st["meaningful"] > 4:
				out_of_range += 1
			if st["count"] > 0:
				d_sum += 100.0 * st["disjoint"] / st["count"]
				d_cnt += 1
		var m_avg: float = m_sum / max(1, steps.size())
		var d_avg: float = d_sum / max(1, d_cnt)
		var search: Dictionary = s["search"]
		var min_label := ""
		match search["status"]:
			"exact":
				min_label = str(search["days"])
				if int(search["days"]) < int(s["rec"]):
					shorter_levels.append(s["id"])
			"shorter_found":
				min_label = "<=%d?" % search["days"]
				shorter_levels.append(s["id"])
			"not_shorter":
				min_label = "%d(已证)" % s["rec"]
			_:
				min_label = "未知"
		print("  %-10s %-4d %-8s %-14.1f %-14d %-10.0f" % [
			s["id"], s["rec"], min_label, m_avg, out_of_range, d_avg,
		])

	print("")
	if shorter_levels.is_empty():
		print("-- 比推荐日更短的关卡: 无 --")
	else:
		print("-- 比推荐日更短的关卡: %s --" % ", ".join(shorter_levels))


func _sum_values(d: Dictionary) -> int:
	var total := 0
	for key in d:
		total += int(d[key])
	return total
