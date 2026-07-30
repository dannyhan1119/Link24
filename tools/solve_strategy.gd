extends SceneTree

# 策略层精确分析（retrograde analysis）：全可达状态枚举 + 转移表 + DAG 上 DP。
# 运行：
#   /Applications/Godot_mono.app/Contents/MacOS/Godot \
#     --headless --path . --script res://tools/solve_strategy.gd
#
# 指标：
#   1. 全状态回溯标记：通关/死局/必胜/必败/未来风险态/一步陷阱态
#   2. 四种策略的精确死局概率与平均通关天数（DP，非模拟）
#      - 均匀随机：所有合法动作等概率
#      - 直奔出口：选"路径最深格（距起点曼哈顿最远）到出口入口格曼哈顿距离"最小的动作，并列等概率
#      - 前沿最大化：选"净新增前沿格（后继前沿数-当前前沿数）"最多的动作，并列等概率
#      - 前沿最小化：选净新增前沿格最少的动作，并列等概率
#   3. 通关末步前"能起步且路径含出口入口格"的前沿格数量分布；死局态前沿数分布

const BoardModel = preload("res://src/model/board_model.gd")
const LevelCatalog = preload("res://src/model/level_catalog.gd")

const TARGET_SUM := 24
const DIRS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

const STATE_CAP := 1200000       # 为后续关卡调整预留余量，当前 20 关均可精确覆盖
const TIME_CAP_MS := 420000      # 覆盖当前最慢关卡；可用 --time 覆盖
const MOVE_CAP := 400            # 单状态动作枚举上限
const ENUM_NODE_CAP := 200000    # 单状态枚举节点上限

const STRATEGIES := ["均匀随机", "直奔出口", "前沿最大", "前沿最小"]
const RANDOM_FAILURE_BANDS := {
	"c1_l01": Vector2(0.0, 0.0),
	"c1_l02": Vector2(0.0, 0.0),
	"c1_l03": Vector2(0.0, 0.0),
	"c1_l04": Vector2(15.0, 30.0),
	"c1_l05": Vector2(15.0, 30.0),
	"c1_l06": Vector2(15.0, 35.0),
	"c1_l07": Vector2(30.0, 50.0),
	"c1_l08": Vector2(30.0, 50.0),
	"c1_l09": Vector2(40.0, 60.0),
	"c1_l10": Vector2(45.0, 65.0),
	"c2_l01": Vector2(10.0, 30.0),
	"c2_l02": Vector2(15.0, 35.0),
	"c2_l03": Vector2(0.0, 20.0),
	"c2_l04": Vector2(25.0, 45.0),
	"c2_l05": Vector2(30.0, 50.0),
	"c2_l06": Vector2(20.0, 40.0),
	"c2_l07": Vector2(40.0, 60.0),
	"c2_l08": Vector2(55.0, 70.0),
	"c2_l09": Vector2(55.0, 70.0),
	"c2_l10": Vector2(60.0, 75.0),
}
const MAX_ADJACENT_RANDOM_FAILURE_JUMP := 25.0


func _initialize() -> void:
	var levels := LevelCatalog.playable_levels()
	# 可选：--only c2_l04,c2_l06 只跑指定关卡；--time 秒 --statecap N 覆盖预算
	var only := {}
	var time_cap := TIME_CAP_MS
	var state_cap := STATE_CAP
	var user_args := OS.get_cmdline_user_args()
	var validate := "--validate" in user_args
	for i in user_args.size():
		if user_args[i] == "--only" and i + 1 < user_args.size():
			for id_str in str(user_args[i + 1]).split(","):
				only[id_str.strip_edges()] = true
		elif user_args[i] == "--time" and i + 1 < user_args.size():
			time_cap = int(user_args[i + 1]) * 1000
		elif user_args[i] == "--statecap" and i + 1 < user_args.size():
			state_cap = int(user_args[i + 1])
	print("绿洲迁徙 · 策略层精确分析 · %d 关" % levels.size())
	print("预算: 状态上限=%d, 单关=%ds, 单状态动作上限=%d, 枚举节点上限=%d" % [
		state_cap, time_cap / 1000, MOVE_CAP, ENUM_NODE_CAP,
	])
	var summaries: Array = []
	for li in levels.size():
		if not only.is_empty() and not only.has(str(levels[li]["id"])):
			continue
		summaries.append(_analyze_level(levels[li], li, time_cap, state_cap))
	_print_summary(summaries)
	var inexact := false
	for summary in summaries:
		if bool(summary.get("aborted", false)) or bool(summary.get("approx", false)):
			inexact = true
	if validate and inexact:
		push_error("策略分析未完成精确枚举：存在预算耗尽或动作枚举截断")
		quit(1)
	else:
		if validate:
			var validation_failures := _validate_difficulty_curve(summaries)
			if not validation_failures.is_empty():
				for failure in validation_failures:
					push_error("策略难度校验失败: %s" % failure)
				quit(1)
				return
			print("策略分析精确性与难度曲线校验: PASS")
		quit(0)


func _analyze_level(level: Dictionary, li: int, time_cap := TIME_CAP_MS, state_cap := STATE_CAP) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var board: RefCounted = BoardModel.new()
	board.load_level(level)
	var width: int = board.width
	var height: int = board.height
	var start_cell: Vector2i = board.start_cell
	var goal_cell: Vector2i = board.goal_cell
	var entry: Vector2i = board.goal_entry_cells()[0]
	var checkpoints: Array = level["checkpoint_cells"]
	var full_mask := (1 << checkpoints.size()) - 1

	# ---- 全状态 BFS + 转移表 ----
	var terrains: Array = []              # Array[PackedInt32Array]
	var cmasks := PackedInt32Array()
	var frontier_of := PackedInt32Array()
	var complete := PackedByteArray()
	var entry_starts := PackedInt32Array()  # 该状态下"起步且路径含出口入口格"的前沿起点数
	var succ: Array = []                  # Array[PackedInt32Array] 后继状态 id
	var act_goal_key: Array = []          # 直奔出口键（越小越直奔）
	var act_fdelta: Array = []            # 净新增前沿格
	var id_of := {}

	var start_terrain: PackedInt32Array = board.terrain.duplicate()
	id_of[_state_key(start_terrain, 0)] = 0
	terrains.append(start_terrain)
	cmasks.append(0)
	board.terrain = start_terrain
	frontier_of.append(_frontier_count(board))
	complete.append(0)
	entry_starts.append(-1)
	succ.append(PackedInt32Array())
	act_goal_key.append(PackedInt32Array())
	act_fdelta.append(PackedInt32Array())

	var aborted := false
	var approx := false
	var head := 0
	while head < terrains.size():
		if head >= state_cap or Time.get_ticks_msec() - t0 > time_cap:
			aborted = true
			break
		var sid := head
		head += 1
		if complete[sid] == 1:
			continue  # 通关即终局，不再展开
		board.terrain = terrains[sid]
		board.visited_checkpoint_cells = _mask_to_list(checkpoints, cmasks[sid])
		var stats := _enumerate_paths(board, ENUM_NODE_CAP, MOVE_CAP, true, {})
		if stats["capped"]:
			approx = true
		var es_set := {}
		var seen_moves := {}
		var s_succ := PackedInt32Array()
		var s_gk := PackedInt32Array()
		var s_fd := PackedInt32Array()
		for path in stats["paths"]:
			var mkey := _move_key(path, width)
			if seen_moves.has(mkey):
				continue
			seen_moves[mkey] = true
			var succ_terrain: PackedInt32Array = (terrains[sid] as PackedInt32Array).duplicate()
			var nmask: int = cmasks[sid]
			for cell in path:
				succ_terrain[cell.y * width + cell.x] = BoardModel.Terrain.ROAD
				var ci := checkpoints.find(cell)
				if ci >= 0:
					nmask |= 1 << ci
			var skey := _state_key(succ_terrain, nmask)
			var nid: int
			if id_of.has(skey):
				nid = id_of[skey]
			else:
				nid = terrains.size()
				id_of[skey] = nid
				terrains.append(succ_terrain)
				cmasks.append(nmask)
				board.terrain = succ_terrain
				frontier_of.append(_frontier_count(board))
				var is_complete := (
					nmask == full_mask
					and _goal_connected(succ_terrain, width, height, start_cell, goal_cell)
				)
				complete.append(1 if is_complete else 0)
				entry_starts.append(-1)
				succ.append(PackedInt32Array())
				act_goal_key.append(PackedInt32Array())
				act_fdelta.append(PackedInt32Array())
			s_succ.append(nid)
			# 直奔出口键：路径最深格（离起点曼哈顿最远）到出口入口格的曼哈顿距离
			var best_d := 1 << 30
			var best_reach := -1
			for cell in path:
				var reach := absi(cell.x - start_cell.x) + absi(cell.y - start_cell.y)
				var d := absi(cell.x - entry.x) + absi(cell.y - entry.y)
				if reach > best_reach or (reach == best_reach and d < best_d):
					best_reach = reach
					best_d = d
			s_gk.append(best_d)
			s_fd.append(frontier_of[nid] - frontier_of[sid])
			if entry in path:
				es_set[path[0]] = true
		entry_starts[sid] = es_set.size()
		succ[sid] = s_succ
		act_goal_key[sid] = s_gk
		act_fdelta[sid] = s_fd

	var n: int = terrains.size()
	var bfs_ms := Time.get_ticks_msec() - t0
	var out := {
		"id": str(level["id"]),
		"name": str(level["name"]),
		"global_index": int(level["global_index"]),
		"rec": int(level["recommended_days"]),
		"aborted": aborted,
		"approx": approx,
		"states": n,
		"bfs_ms": bfs_ms,
	}
	if aborted:
		print("")
		print("=== 关卡 %d/20 [%s] %s ===" % [li + 1, out["id"], out["name"]])
		print("  !! 预算耗尽（已展开 %d 状态, %.1fs），跳过本关精确分析" % [n, bfs_ms / 1000.0])
		return out

	# ---- 逆拓扑回溯标记（道路只增，BFS 序即拓扑序，倒序处理）----
	var cw := PackedByteArray()  # canwin：存在动作通往可赢
	var cl := PackedByteArray()  # canlose：存在动作通往必败/死局
	cw.resize(n)
	cl.resize(n)
	var complete_cnt := 0
	var dead_cnt := 0
	for i in range(n - 1, -1, -1):
		if complete[i] == 1:
			cw[i] = 1
			complete_cnt += 1
			continue
		var s_succ: PackedInt32Array = succ[i]
		if s_succ.is_empty():
			cl[i] = 1
			dead_cnt += 1
			continue
		var any_win := false
		var any_lose := false
		for nid in s_succ:
			if cw[nid] == 1:
				any_win = true
			if cl[nid] == 1:
				any_lose = true
		cw[i] = 1 if any_win else 0
		cl[i] = 1 if any_lose else 0
	var win_cnt := 0
	var lose_cnt := 0
	var future_risk_cnt := 0
	for i in n:
		if complete[i] == 1:
			continue
		if cw[i] == 1 and cl[i] == 1:
			future_risk_cnt += 1
		elif cw[i] == 1:
			win_cnt += 1
		else:
			lose_cnt += 1

	# “未来可能失败”不等于“当前一步就不可逆”。单独统计当前动作中
	# 后继状态已经不再可赢的动作，才是玩家此刻真正会踩中的一步陷阱。
	var immediate_trap_cnt := 0
	var fatal_action_total := 0
	var action_total := 0
	var initial_safe_actions := 0
	var initial_fatal_actions := 0
	for i in n:
		if complete[i] == 1 or cw[i] == 0:
			continue
		var safe_actions := 0
		var fatal_actions := 0
		for nid in succ[i]:
			if cw[nid] == 1:
				safe_actions += 1
			else:
				fatal_actions += 1
		if safe_actions > 0 and fatal_actions > 0:
			immediate_trap_cnt += 1
		fatal_action_total += fatal_actions
		action_total += safe_actions + fatal_actions
		if i == 0:
			initial_safe_actions = safe_actions
			initial_fatal_actions = fatal_actions

	# ---- 四策略 DP（p_dead / 平均通关天数）----
	var p_dead := PackedFloat64Array()
	var q_win := PackedFloat64Array()
	var u_days := PackedFloat64Array()  # E[1{最终通关} * 剩余步数]
	p_dead.resize(n)
	q_win.resize(n)
	u_days.resize(n)
	var strat_results: Array = []
	for strat in 4:
		for i in range(n - 1, -1, -1):
			if complete[i] == 1:
				p_dead[i] = 0.0
				q_win[i] = 1.0
				u_days[i] = 0.0
				continue
			var s_succ: PackedInt32Array = succ[i]
			if s_succ.is_empty():
				p_dead[i] = 1.0
				q_win[i] = 0.0
				u_days[i] = 0.0
				continue
			# 选该策略的动作子集（并列等概率）
			var chosen := PackedInt32Array()
			if strat == 0:
				for a in s_succ.size():
					chosen.append(a)
			else:
				var keys: PackedInt32Array = act_goal_key[i] if strat == 1 else act_fdelta[i]
				var want: int = keys[0]
				for a in keys.size():
					if (strat == 1 or strat == 3) and keys[a] < want:
						want = keys[a]
					elif strat == 2 and keys[a] > want:
						want = keys[a]
				for a in keys.size():
					if keys[a] == want:
						chosen.append(a)
			var pd := 0.0
			var ud := 0.0
			for a in chosen:
				var nid: int = s_succ[a]
				pd += p_dead[nid]
				ud += q_win[nid] + u_days[nid]
			p_dead[i] = pd / chosen.size()
			q_win[i] = 1.0 - p_dead[i]
			u_days[i] = ud / chosen.size()
		strat_results.append({
			"p_dead": p_dead[0],
			"avg_days": u_days[0] / q_win[0] if q_win[0] > 0.0 else -1.0,
		})

	# ---- 指标 3：末步出口起点分布 & 死局前沿分布 ----
	var prefinal_hist := {}
	var prefinal_sum := 0
	var prefinal_cnt := 0
	for i in n:
		if complete[i] == 1:
			continue
		var reaches_exit := false
		for nid in succ[i]:
			if complete[nid] == 1:
				reaches_exit = true
				break
		if reaches_exit:
			var c: int = entry_starts[i]
			prefinal_hist[c] = int(prefinal_hist.get(c, 0)) + 1
			prefinal_sum += c
			prefinal_cnt += 1
	var dead_frontier_hist := {}
	var dead_frontier_sum := 0
	for i in n:
		if complete[i] == 0 and (succ[i] as PackedInt32Array).is_empty():
			var f: int = frontier_of[i]
			dead_frontier_hist[f] = int(dead_frontier_hist.get(f, 0)) + 1
			dead_frontier_sum += f

	out["complete_cnt"] = complete_cnt
	out["dead_cnt"] = dead_cnt
	out["win_cnt"] = win_cnt
	out["lose_cnt"] = lose_cnt
	out["future_risk_cnt"] = future_risk_cnt
	out["immediate_trap_cnt"] = immediate_trap_cnt
	out["fatal_action_total"] = fatal_action_total
	out["action_total"] = action_total
	out["initial_safe_actions"] = initial_safe_actions
	out["initial_fatal_actions"] = initial_fatal_actions
	out["strat"] = strat_results
	out["prefinal_hist"] = prefinal_hist
	out["prefinal_avg"] = float(prefinal_sum) / prefinal_cnt if prefinal_cnt > 0 else 0.0
	out["dead_frontier_hist"] = dead_frontier_hist
	out["dead_frontier_avg"] = float(dead_frontier_sum) / dead_cnt if dead_cnt > 0 else 0.0

	print("")
	print("=== 关卡 %d/20 [%s] %s | 推荐 %d 天 ===" % [
		li + 1, out["id"], out["name"], out["rec"],
	])
	var pct := 100.0 / n
	print("  状态: 总=%d (BFS %.1fs%s)%s" % [
		n, bfs_ms / 1000.0,
		", 枚举触顶→近似" if approx else "",
		"",
	])
	print("  标记: 通关终态=%d (%.1f%%) | 死局=%d (%.1f%%) | 必胜=%d (%.1f%%) | 必败(含死局)=%d (%.1f%%) | 未来风险=%d (%.1f%%) | 一步陷阱=%d (%.1f%%)" % [
		complete_cnt, complete_cnt * pct,
		dead_cnt, dead_cnt * pct,
		win_cnt, win_cnt * pct,
		lose_cnt, lose_cnt * pct,
		future_risk_cnt, future_risk_cnt * pct,
		immediate_trap_cnt, immediate_trap_cnt * pct,
	])
	print("  初始动作: 安全=%d | 一步致死=%d | 一步致死率=%.1f%%" % [
		initial_safe_actions,
		initial_fatal_actions,
		100.0 * initial_fatal_actions / maxi(1, initial_safe_actions + initial_fatal_actions),
	])
	print("  全局动作: 安全=%d | 一步致死=%d | 安全动作比例=%.1f%%" % [
		action_total - fatal_action_total,
		fatal_action_total,
		100.0 * (action_total - fatal_action_total) / maxi(1, action_total),
	])
	for si in 4:
		var r: Dictionary = strat_results[si]
		print("  策略[%s]: 死局概率=%.1f%%%s" % [
			STRATEGIES[si],
			float(r["p_dead"]) * 100.0,
			(
				", 通关平均 %.2f 天" % float(r["avg_days"])
				if float(r["avg_days"]) >= 0.0
				else ", 永不通关"
			),
		])
	print("  末步前可选出口起点数分布: %s (状态数=%d, 均=%.2f)" % [
		_hist_str(prefinal_hist), prefinal_cnt, float(out["prefinal_avg"]),
	])
	print("  死局态前沿数分布: %s (死局数=%d, 均=%.2f)" % [
		_hist_str(dead_frontier_hist), dead_cnt, float(out["dead_frontier_avg"]),
	])
	return out


# ------------------------------------------------------------------ 总计输出

func _print_summary(summaries: Array) -> void:
	print("")
	print("==================== 总计 ====================")
	print("")
	print("-- 20 关 × 四策略 死局概率(%) / 平均通关天数 --")
	print("  %-8s %-4s | %-14s %-14s %-14s %-14s | %-9s %-9s %-9s %-9s" % [
		"关卡", "推荐", "均匀随机", "直奔出口", "前沿最大", "前沿最小",
		"死局态%", "必败态%", "未来风险%", "一步陷阱%",
	])
	for s in summaries:
		if s["aborted"]:
			print("  %-8s %-4d | (预算耗尽, 已展开 %d 状态)" % [s["id"], s["rec"], s["states"]])
			continue
		var cells: Array = []
		for si in 4:
			var r: Dictionary = s["strat"][si]
			cells.append(
				"%.1f%%/%s" % [
					float(r["p_dead"]) * 100.0,
					(
						"%.1f天" % float(r["avg_days"])
						if float(r["avg_days"]) >= 0.0
						else "-"
					),
				]
			)
		var n: int = s["states"]
		print("  %-8s %-4d | %-14s %-14s %-14s %-14s | %-9.1f %-9.1f %-9.1f %-9.1f" % [
			s["id"], s["rec"],
			cells[0], cells[1], cells[2], cells[3],
			100.0 * int(s["dead_cnt"]) / n,
			100.0 * int(s["lose_cnt"]) / n,
			100.0 * int(s["future_risk_cnt"]) / n,
			100.0 * int(s["immediate_trap_cnt"]) / n,
		])
	print("")
	print("-- 动作安全性 --")
	print("  %-8s | %-8s %-8s %-10s %-12s" % [
		"关卡", "初始安全", "初始致死", "初始致死率", "全局安全动作%",
	])
	for s in summaries:
		if s["aborted"]:
			continue
		var safe := int(s["initial_safe_actions"])
		var fatal := int(s["initial_fatal_actions"])
		var action_total := int(s["action_total"])
		var fatal_action_total := int(s["fatal_action_total"])
		var initial_rate := "%.1f%%" % (100.0 * fatal / maxi(1, safe + fatal))
		var global_safe_rate := "%.1f%%" % (
			100.0 * (action_total - fatal_action_total) / maxi(1, action_total)
		)
		print("  %-8s | %-8d %-8d %-10s %-12s" % [
			s["id"],
			safe,
			fatal,
			initial_rate,
			global_safe_rate,
		])
	print("")
	print("-- 指标 3 汇总 --")
	print("  %-8s | %-30s | %-30s" % ["关卡", "末步前出口起点数(均/分布)", "死局前沿数(均/分布)"])
	for s in summaries:
		if s["aborted"]:
			continue
		print("  %-8s | %-30s | %-30s" % [
			s["id"],
			"%.2f %s" % [float(s["prefinal_avg"]), _hist_str(s["prefinal_hist"])],
			"%.2f %s" % [float(s["dead_frontier_avg"]), _hist_str(s["dead_frontier_hist"])],
		])


func _hist_str(hist: Dictionary) -> String:
	var keys := hist.keys()
	keys.sort()
	var parts := PackedStringArray()
	for k in keys:
		parts.append("%d:%d" % [int(k), int(hist[k])])
	return "{%s}" % ", ".join(parts)


func _validate_difficulty_curve(summaries: Array) -> PackedStringArray:
	var failures := PackedStringArray()
	var exact_summaries: Array = []
	for summary in summaries:
		if bool(summary.get("aborted", false)) or bool(summary.get("approx", false)):
			continue
		exact_summaries.append(summary)
		var level_id := str(summary["id"])
		var random_failure := float(summary["strat"][0]["p_dead"]) * 100.0
		var band: Vector2 = RANDOM_FAILURE_BANDS[level_id]
		if random_failure < band.x - 0.05 or random_failure > band.y + 0.05:
			failures.append(
				"%s 随机失败率 %.1f%% 不在 %.0f%%～%.0f%% 目标带"
				% [level_id, random_failure, band.x, band.y]
			)
		if int(summary["global_index"]) <= 3:
			if int(summary["future_risk_cnt"]) != 0 or int(summary["immediate_trap_cnt"]) != 0:
				failures.append("%s 教学流程仍包含隐藏致死分支" % level_id)
			if int(summary["initial_fatal_actions"]) != 0:
				failures.append("%s 开局仍包含一步致死动作" % level_id)
	exact_summaries.sort_custom(
		func(a, b) -> bool: return int(a["global_index"]) < int(b["global_index"])
	)
	for index in range(1, exact_summaries.size()):
		var previous: Dictionary = exact_summaries[index - 1]
		var current: Dictionary = exact_summaries[index]
		var previous_global := int(previous["global_index"])
		var current_global := int(current["global_index"])
		if current_global != previous_global + 1:
			continue
		if (previous_global - 1) / 10 != (current_global - 1) / 10:
			continue
		var previous_failure := float(previous["strat"][0]["p_dead"]) * 100.0
		var current_failure := float(current["strat"][0]["p_dead"]) * 100.0
		if absf(current_failure - previous_failure) > MAX_ADJACENT_RANDOM_FAILURE_JUMP:
			failures.append(
				"%s→%s 随机失败率跳变 %.1f 个百分点"
				% [previous["id"], current["id"], absf(current_failure - previous_failure)]
			)
	return failures


# ------------------------------------------------------------------ 枚举工具

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


func _frontier_count(board: RefCounted) -> int:
	var count := 0
	for y in board.height:
		for x in board.width:
			if board.is_frontier(Vector2i(x, y)):
				count += 1
	return count


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
