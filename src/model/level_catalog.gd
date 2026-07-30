extends RefCounted
class_name MigrationLevelCatalog

const BoardModel = preload("res://src/model/board_model.gd")
const DEFAULT_WIDTH := 8
const DEFAULT_HEIGHT := 12
const OPTIMAL_DAYS := {
	"c1_l01": 6,
	"c1_l02": 5,
	"c1_l03": 6,
	"c1_l04": 6,
	"c1_l05": 6,
	"c1_l06": 4,
	"c1_l07": 6,
	"c1_l08": 4,
	"c1_l09": 6,
	"c1_l10": 6,
	"c2_l01": 5,
	"c2_l02": 6,
	"c2_l03": 4,
	"c2_l04": 5,
	"c2_l05": 6,
	"c2_l06": 4,
	"c2_l07": 5,
	"c2_l08": 6,
	"c2_l09": 5,
	"c2_l10": 6,
}


static func all_levels() -> Array[Dictionary]:
	var levels := playable_levels()
	levels.append(_make_stuck_level())
	return levels


static func playable_levels() -> Array[Dictionary]:
	var levels: Array[Dictionary] = []
	for chapter in chapter_definitions():
		levels.append_array(chapter["levels"])
	return levels


static func chapter_definitions() -> Array[Dictionary]:
	var definitions: Array[Dictionary] = [
		_make_chapter_definition(
			"chapter_1",
			1,
			1,
			"第一章 · 绿洲边缘",
			"学习开路，带队伍抵达第一片新绿洲",
			_chapter_one_specs(),
			Color("#37BFE4"),
			Color("#FFF9E8")
		),
		_make_chapter_definition(
			"chapter_2",
			2,
			11,
			"第二章 · 明亮沙丘",
			"在薄雾、伙伴与补给之间选择迁徙路线",
			_chapter_two_specs(),
			Color("#F2B94E"),
			Color("#FFF1C9")
		),
	]
	for chapter_index in definitions.size():
		definitions[chapter_index]["catalog_index"] = chapter_index
		definitions[chapter_index]["chapter_count"] = definitions.size()
	return definitions


static func chapter_definition(chapter_id: String) -> Dictionary:
	for chapter in chapter_definitions():
		if str(chapter["id"]) == chapter_id:
			return chapter
	return {}


static func chapter_levels(chapter_id: String) -> Array[Dictionary]:
	var chapter := chapter_definition(chapter_id)
	if chapter.is_empty():
		return []
	return chapter["levels"]


static func stuck_test_level() -> Dictionary:
	return _make_stuck_level()


static func _make_chapter_definition(
	chapter_id: String,
	chapter_number: int,
	global_start_index: int,
	title: String,
	subtitle: String,
	specs: Array[Dictionary],
	accent_color: Color,
	landscape_tint: Color
) -> Dictionary:
	var levels: Array[Dictionary] = []
	for spec in specs:
		levels.append(
			_make_chapter_level(spec, chapter_id, chapter_number, global_start_index)
		)
	if not levels.is_empty():
		levels.back()["is_chapter_final"] = true
	return {
		"id": chapter_id,
		"number": chapter_number,
		"title": title,
		"subtitle": subtitle,
		"accent_color": accent_color,
		"landscape_tint": landscape_tint,
		"levels": levels,
		"node_positions": _default_node_positions(),
	}


static func _make_chapter_level(
	spec: Dictionary,
	chapter_id: String,
	chapter_number: int,
	global_start_index: int
) -> Dictionary:
	var width := int(spec.get("width", DEFAULT_WIDTH))
	var height := int(spec.get("height", DEFAULT_HEIGHT))
	var data := _make_base(str(spec["name"]), int(spec["seed"]), width, height)
	var start: Vector2i = spec["start"]
	var goal: Vector2i = spec["goal"]
	_set_terrain(data, start, BoardModel.Terrain.START)

	var paths: Array = []
	var raw_paths: Array = spec["paths"]
	for path_index in raw_paths.size():
		var path: Array[Vector2i] = []
		for cell in raw_paths[path_index]:
			path.append(cell)
		var values := _segment_values(path.size(), path_index + int(spec["seed"]))
		for cell_index in path.size():
			_set_number(data, path[cell_index], values[cell_index])
		paths.append(path)

	for obstacle in spec.get("obstacles", []):
		_set_terrain(data, obstacle, BoardModel.Terrain.BLOCKED)

	var branch_paths: Array = []
	for raw_branch in spec.get("branch_paths", []):
		var branch: Array[Vector2i] = []
		for cell in raw_branch:
			branch.append(cell)
		var branch_values := _segment_values(branch.size(), int(spec["seed"]) + branch_paths.size() + 9)
		for cell_index in branch.size():
			_set_number(data, branch[cell_index], branch_values[cell_index])
		branch_paths.append(branch)

	var local_index := int(spec["index"])
	data["id"] = "c%d_l%02d" % [chapter_number, local_index]
	var level_id := str(data["id"])
	var optimal_days := int(OPTIMAL_DAYS.get(level_id, paths.size()))
	data["chapter_id"] = chapter_id
	data["chapter"] = chapter_number
	data["level_index"] = int(spec["index"])
	data["global_index"] = global_start_index + local_index - 1
	data["lesson"] = str(spec["lesson"])
	data["optimal_days"] = optimal_days
	# Story-mode efficiency allows one exploratory day; the exact optimum remains
	# visible as the mastery target and is verified by the offline solver.
	data["recommended_days"] = optimal_days + 1
	data["start"] = start
	data["goal"] = goal
	data["intended_paths"] = paths
	data["branch_paths"] = branch_paths
	data["branch_path"] = branch_paths[0] if not branch_paths.is_empty() else []
	data["partner_cells"] = spec.get("partner_cells", []).duplicate()
	data["checkpoint_cells"] = spec.get("checkpoint_cells", []).duplicate()
	data["watchtower_cells"] = spec.get("watchtower_cells", []).duplicate()
	data["watchtower_reveal_radius"] = int(spec.get("watchtower_reveal_radius", 5))
	data["fog_radius"] = int(spec.get("fog_radius", 0))
	data["tutorial"] = bool(spec.get("tutorial", false))
	data["is_chapter_final"] = false
	return data


static func _default_node_positions() -> Array[Vector2]:
	return [
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


static func _segment_values(length: int, variant: int) -> Array[int]:
	var options := {
		2: [
			[12, 12],
		],
		3: [
			[12, 11, 1],
			[12, 10, 2],
			[12, 9, 3],
			[12, 8, 4],
			[12, 7, 5],
			[11, 10, 3],
			[11, 9, 4],
			[11, 8, 5],
			[8, 8, 8],
			[10, 8, 6],
			[11, 7, 6],
			[9, 9, 6],
			[10, 9, 5],
			[10, 7, 7],
			[9, 8, 7],
		],
		4: [
			[9, 7, 5, 3],
			[6, 6, 5, 7],
			[12, 4, 3, 5],
			[8, 7, 4, 5],
			[11, 7, 4, 2],
			[10, 8, 5, 1],
			[9, 8, 4, 3],
			[8, 7, 6, 3],
			[7, 6, 6, 5],
			[9, 6, 5, 4],
			[10, 6, 4, 4],
			[11, 6, 5, 2],
		],
		5: [
			[4, 5, 6, 4, 5],
			[2, 5, 7, 6, 4],
			[3, 3, 6, 7, 5],
			[8, 4, 3, 4, 5],
			[8, 6, 5, 3, 2],
			[7, 6, 5, 4, 2],
			[6, 6, 5, 4, 3],
			[9, 5, 4, 3, 3],
			[8, 5, 4, 4, 3],
			[7, 5, 5, 4, 3],
			[10, 5, 4, 3, 2],
			[9, 6, 4, 3, 2],
		],
	}
	var candidates: Array = options.get(length, [])
	assert(not candidates.is_empty(), "Unsupported route segment length: %d" % length)
	var selected: Array = candidates[posmod(variant, candidates.size())]
	var values: Array[int] = []
	for value in selected:
		values.append(int(value))
	return values


static func _chapter_one_specs() -> Array[Dictionary]:
	return [
		{
			"index": 1,
			"name": "第 1 关 · 初次开路",
			"lesson": "从蓝点数字开始，连接相邻数字凑成 24",
			"seed": 3,
			"start": Vector2i(0, 11),
			"goal": Vector2i(6, -1),
			"tutorial": true,
			"paths": [
				[Vector2i(0, 10), Vector2i(1, 10), Vector2i(2, 10)],
				[Vector2i(2, 9), Vector2i(3, 9), Vector2i(4, 9)],
				[Vector2i(4, 8), Vector2i(4, 7), Vector2i(5, 7), Vector2i(6, 7)],
				[Vector2i(6, 6), Vector2i(6, 5), Vector2i(7, 5)],
				[Vector2i(7, 4), Vector2i(7, 3), Vector2i(7, 2)],
				[Vector2i(7, 1), Vector2i(6, 1), Vector2i(6, 0)],
			],
			"obstacles": [
				Vector2i(1, 8), Vector2i(2, 8), Vector2i(3, 7),
				Vector2i(5, 6), Vector2i(5, 5),
			],
		},
		{
			"index": 2,
			"name": "第 2 关 · 道路相邻",
			"lesson": "每段新路都要从已经连通的道路边缘出发",
			"seed": 5,
			"start": Vector2i(1, 11),
			"goal": Vector2i(1, -1),
			"paths": [
				[Vector2i(1, 10), Vector2i(1, 9), Vector2i(1, 8)],
				[Vector2i(1, 7), Vector2i(2, 7)],
				[Vector2i(2, 6), Vector2i(2, 5), Vector2i(1, 5)],
				[Vector2i(1, 4), Vector2i(1, 3), Vector2i(2, 3), Vector2i(2, 2)],
				[Vector2i(2, 1), Vector2i(1, 1), Vector2i(1, 0)],
			],
			"obstacles": [
				Vector2i(0, 8), Vector2i(2, 8), Vector2i(3, 6),
				Vector2i(0, 3), Vector2i(3, 2),
			],
		},
		{
			"index": 3,
			"name": "第 3 关 · 绕过岩石",
			"lesson": "路径可以转弯，但不能穿过岩石",
			"seed": 7,
			"start": Vector2i(6, 11),
			"goal": Vector2i(2, -1),
			"paths": [
				[Vector2i(6, 10), Vector2i(5, 10), Vector2i(4, 10)],
				[Vector2i(4, 9), Vector2i(4, 8), Vector2i(3, 8), Vector2i(2, 8)],
				[Vector2i(2, 7), Vector2i(1, 7), Vector2i(1, 6)],
				[Vector2i(1, 5), Vector2i(2, 5)],
				[Vector2i(2, 4), Vector2i(2, 3), Vector2i(3, 3)],
				[Vector2i(3, 2), Vector2i(2, 2), Vector2i(2, 1), Vector2i(2, 0)],
			],
			"obstacles": [
				Vector2i(5, 9), Vector2i(3, 9), Vector2i(3, 7),
				Vector2i(0, 6), Vector2i(3, 5), Vector2i(1, 3),
			],
		},
		{
			"index": 4,
			"name": "第 4 关 · 拖回修正",
			"lesson": "选错数字时，拖回上一格即可撤销末段",
			"seed": 9,
			"start": Vector2i(0, 11),
			"goal": Vector2i(7, -1),
			"paths": [
				[Vector2i(0, 10), Vector2i(1, 10), Vector2i(2, 10)],
				[Vector2i(2, 9), Vector2i(3, 9), Vector2i(3, 8), Vector2i(4, 8)],
				[Vector2i(4, 7), Vector2i(5, 7)],
				[Vector2i(5, 6), Vector2i(5, 5), Vector2i(6, 5)],
				[Vector2i(6, 4), Vector2i(7, 4), Vector2i(7, 3), Vector2i(6, 3)],
				[Vector2i(6, 2), Vector2i(7, 2), Vector2i(7, 1), Vector2i(7, 0)],
			],
			"obstacles": [
				Vector2i(1, 9), Vector2i(2, 8), Vector2i(4, 6),
				Vector2i(6, 6), Vector2i(5, 4),
			],
		},
		{
			"index": 5,
			"name": "第 5 关 · 两种选择",
			"lesson": "道路边缘可能同时出现多条合法的 24 路径",
			"seed": 11,
			"start": Vector2i(0, 11),
			"goal": Vector2i(6, -1),
			"paths": [
				[Vector2i(0, 10), Vector2i(1, 10), Vector2i(2, 10)],
				[Vector2i(2, 9), Vector2i(3, 9), Vector2i(4, 9)],
				[Vector2i(4, 8), Vector2i(4, 7), Vector2i(5, 7), Vector2i(6, 7)],
				[Vector2i(6, 6), Vector2i(6, 5), Vector2i(7, 5)],
				[Vector2i(7, 4), Vector2i(7, 3), Vector2i(7, 2)],
				[Vector2i(7, 1), Vector2i(6, 1), Vector2i(6, 0)],
			],
			"branch_paths": [
				[Vector2i(2, 11), Vector2i(3, 11)],
			],
			"obstacles": [
				Vector2i(1, 8), Vector2i(3, 8), Vector2i(5, 6), Vector2i(5, 5),
			],
		},
		{
			"index": 6,
			"name": "第 6 关 · 长路效率",
			"lesson": "较长的 24 路径能用同一天开出更多道路",
			"seed": 13,
			"start": Vector2i(0, 11),
			"goal": Vector2i(7, -1),
			"paths": [
				[Vector2i(0, 10), Vector2i(1, 10), Vector2i(2, 10), Vector2i(3, 10), Vector2i(3, 9)],
				[Vector2i(4, 9), Vector2i(5, 9), Vector2i(5, 8), Vector2i(6, 8), Vector2i(7, 8)],
				[Vector2i(7, 7), Vector2i(6, 7), Vector2i(5, 7), Vector2i(5, 6), Vector2i(4, 6)],
				[Vector2i(4, 5), Vector2i(4, 4), Vector2i(5, 4), Vector2i(6, 4), Vector2i(6, 3)],
				[Vector2i(6, 2), Vector2i(7, 2), Vector2i(7, 1), Vector2i(7, 0)],
			],
			"obstacles": [
				Vector2i(2, 9), Vector2i(4, 8), Vector2i(6, 6),
				Vector2i(3, 5), Vector2i(5, 3),
			],
		},
		{
			"index": 7,
			"name": "第 7 关 · 返回岔路",
			"lesson": "可以从旧道路的任意前沿继续开路",
			"seed": 15,
			"start": Vector2i(7, 11),
			"goal": Vector2i(1, -1),
			"paths": [
				[Vector2i(7, 10), Vector2i(6, 10), Vector2i(5, 10)],
				[Vector2i(5, 9), Vector2i(4, 9), Vector2i(3, 9)],
				[Vector2i(3, 8), Vector2i(3, 7), Vector2i(2, 7), Vector2i(1, 7)],
				[Vector2i(1, 6), Vector2i(2, 6), Vector2i(2, 5)],
				[Vector2i(2, 4), Vector2i(1, 4), Vector2i(1, 3)],
				[Vector2i(1, 2), Vector2i(2, 2), Vector2i(2, 1), Vector2i(1, 1), Vector2i(1, 0)],
			],
			"branch_paths": [
				[Vector2i(4, 10), Vector2i(4, 11)],
			],
			"obstacles": [
				Vector2i(6, 9), Vector2i(4, 8), Vector2i(2, 8),
				Vector2i(0, 6), Vector2i(3, 5), Vector2i(0, 3),
			],
		},
		{
			"index": 8,
			"name": "第 8 关 · 绕路取舍",
			"lesson": "偏离主路会增加迁徙日，但也能探索更多区域",
			"seed": 17,
			"start": Vector2i(3, 11),
			"goal": Vector2i(5, -1),
			"fog_radius": 2,
			"paths": [
				[Vector2i(3, 10), Vector2i(2, 10), Vector2i(2, 9)],
				[Vector2i(2, 8), Vector2i(3, 8), Vector2i(4, 8), Vector2i(4, 7)],
				[Vector2i(5, 7), Vector2i(6, 7), Vector2i(6, 6)],
				[Vector2i(6, 5), Vector2i(5, 5), Vector2i(4, 5)],
				[Vector2i(4, 4), Vector2i(4, 3), Vector2i(5, 3), Vector2i(6, 3)],
				[Vector2i(6, 2), Vector2i(5, 2), Vector2i(5, 1), Vector2i(5, 0)],
			],
			"branch_paths": [
				[Vector2i(3, 9), Vector2i(4, 9), Vector2i(5, 9)],
			],
			"partner_cells": [
				Vector2i(5, 9),
			],
			"obstacles": [
				Vector2i(1, 9), Vector2i(3, 7), Vector2i(5, 6),
				Vector2i(3, 5), Vector2i(5, 4), Vector2i(7, 3),
			],
		},
		{
			"index": 9,
			"name": "第 9 关 · 水塘补给",
			"lesson": "先连接蓝色水塘完成补给，再打开通往绿洲的出口",
			"seed": 19,
			"start": Vector2i(6, 11),
			"goal": Vector2i(3, -1),
			"fog_radius": 2,
			"paths": [
				[Vector2i(6, 10), Vector2i(6, 9), Vector2i(5, 9)],
				[Vector2i(5, 8), Vector2i(4, 8), Vector2i(3, 8), Vector2i(3, 7)],
				[Vector2i(3, 6), Vector2i(2, 6), Vector2i(2, 5)],
				[Vector2i(2, 4), Vector2i(3, 4), Vector2i(4, 4)],
				[Vector2i(4, 3), Vector2i(4, 2), Vector2i(3, 2)],
				[Vector2i(3, 1), Vector2i(3, 0)],
			],
			"checkpoint_cells": [
				Vector2i(3, 4),
			],
			"obstacles": [
				Vector2i(5, 10), Vector2i(7, 9), Vector2i(4, 9),
				Vector2i(2, 8), Vector2i(4, 7), Vector2i(1, 5),
				Vector2i(5, 4), Vector2i(2, 2), Vector2i(4, 1),
			],
		},
		{
			"index": 10,
			"name": "第 10 关 · 综合迁徙",
			"lesson": "综合使用长路径、转弯、分支与出口判断",
			"seed": 23,
			"start": Vector2i(0, 11),
			"goal": Vector2i(4, -1),
			"fog_radius": 2,
			"paths": [
				[Vector2i(0, 10), Vector2i(1, 10), Vector2i(2, 10), Vector2i(2, 9)],
				[Vector2i(3, 9), Vector2i(4, 9), Vector2i(5, 9)],
				[Vector2i(5, 8), Vector2i(5, 7), Vector2i(4, 7), Vector2i(3, 7), Vector2i(3, 6)],
				[Vector2i(2, 6), Vector2i(1, 6), Vector2i(1, 5)],
				[Vector2i(1, 4), Vector2i(2, 4), Vector2i(3, 4), Vector2i(4, 4)],
				[Vector2i(4, 3), Vector2i(5, 3), Vector2i(5, 2)],
				[Vector2i(5, 1), Vector2i(4, 1), Vector2i(4, 0)],
			],
			"branch_paths": [
				[Vector2i(2, 8), Vector2i(1, 8), Vector2i(1, 7)],
			],
			"obstacles": [
				Vector2i(1, 9), Vector2i(4, 8), Vector2i(6, 8),
				Vector2i(4, 6), Vector2i(0, 5), Vector2i(3, 3),
				Vector2i(6, 2), Vector2i(3, 1),
			],
		},
	]


static func _chapter_two_specs() -> Array[Dictionary]:
	# Chapter two is authored independently around its own optional rule:
	# reaching a watchtower costs a detour but permanently reveals a large fog
	# region. None of these layouts is mirrored from chapter one.
	return [
		{
			"index": 1,
			"name": "第 11 关 · 沙丘瞭望",
			"lesson": "绕路点亮瞭望塔，大片薄雾会从高处散开",
			"seed": 41,
			"start": Vector2i(1, 11),
			"goal": Vector2i(6, -1),
			"fog_radius": 2,
			"paths": [
				[Vector2i(1, 10), Vector2i(2, 10), Vector2i(2, 9)],
				[Vector2i(3, 9), Vector2i(4, 9), Vector2i(4, 8), Vector2i(5, 8)],
				[Vector2i(5, 7), Vector2i(5, 6), Vector2i(4, 6)],
				[Vector2i(4, 5), Vector2i(3, 5), Vector2i(3, 4), Vector2i(4, 4)],
				[Vector2i(5, 4), Vector2i(5, 3), Vector2i(6, 3)],
				[Vector2i(6, 2), Vector2i(6, 1), Vector2i(6, 0)],
			],
			"branch_paths": [
				[Vector2i(3, 8), Vector2i(2, 8), Vector2i(2, 7)],
			],
			"watchtower_cells": [Vector2i(2, 7)],
			"obstacles": [
				Vector2i(0, 9), Vector2i(1, 8), Vector2i(6, 8),
				Vector2i(2, 6), Vector2i(6, 5), Vector2i(2, 4),
			],
		},
		{
			"index": 2,
			"name": "第 12 关 · 高处来风",
			"lesson": "比较直达与瞭望绕路，用视野换取更稳的规划",
			"seed": 47,
			"start": Vector2i(6, 11),
			"goal": Vector2i(1, -1),
			"fog_radius": 2,
			"paths": [
				[Vector2i(6, 10), Vector2i(5, 10), Vector2i(5, 9)],
				[Vector2i(4, 9), Vector2i(3, 9), Vector2i(3, 8), Vector2i(2, 8)],
				[Vector2i(2, 7), Vector2i(2, 6), Vector2i(3, 6)],
				[Vector2i(3, 5), Vector2i(4, 5), Vector2i(4, 4)],
				[Vector2i(3, 4), Vector2i(2, 4), Vector2i(2, 3), Vector2i(1, 3)],
				[Vector2i(1, 2), Vector2i(1, 1), Vector2i(1, 0)],
			],
			"branch_paths": [
				[Vector2i(4, 8), Vector2i(5, 8), Vector2i(5, 7)],
			],
			"watchtower_cells": [Vector2i(5, 7)],
			"obstacles": [
				Vector2i(7, 9), Vector2i(6, 8), Vector2i(1, 8),
				Vector2i(5, 6), Vector2i(5, 4), Vector2i(0, 3),
			],
		},
		{
			"index": 3,
			"name": "第 13 关 · 水源与远景",
			"lesson": "水塘决定出口，瞭望塔决定你能提前看到多远",
			"seed": 53,
			"start": Vector2i(0, 11),
			"goal": Vector2i(4, -1),
			"fog_radius": 2,
			"paths": [
				[Vector2i(0, 10), Vector2i(1, 10), Vector2i(1, 9)],
				[Vector2i(2, 9), Vector2i(3, 9), Vector2i(3, 8), Vector2i(4, 8)],
				[Vector2i(4, 7), Vector2i(5, 7), Vector2i(5, 6)],
				[Vector2i(4, 6), Vector2i(3, 6), Vector2i(3, 5)],
				[Vector2i(3, 4), Vector2i(4, 4), Vector2i(4, 3), Vector2i(5, 3)],
				[Vector2i(5, 2), Vector2i(4, 2), Vector2i(4, 1), Vector2i(4, 0)],
			],
			"branch_paths": [
				[Vector2i(0, 9), Vector2i(0, 8), Vector2i(1, 8)],
			],
			"watchtower_cells": [Vector2i(1, 8)],
			"checkpoint_cells": [Vector2i(3, 5)],
			"obstacles": [
				Vector2i(2, 10), Vector2i(2, 8), Vector2i(6, 7),
				Vector2i(2, 6), Vector2i(5, 5), Vector2i(2, 3),
			],
		},
		{
			"index": 4,
			"name": "第 14 关 · 回望旧路",
			"lesson": "从旧道路折返瞭望点，再回到更有价值的前沿",
			"seed": 59,
			"start": Vector2i(7, 11),
			"goal": Vector2i(2, -1),
			"fog_radius": 2,
			"paths": [
				[Vector2i(7, 10), Vector2i(6, 10), Vector2i(5, 10), Vector2i(5, 9)],
				[Vector2i(4, 9), Vector2i(4, 8), Vector2i(3, 8)],
				[Vector2i(3, 7), Vector2i(2, 7), Vector2i(2, 6), Vector2i(1, 6)],
				[Vector2i(1, 5), Vector2i(2, 5), Vector2i(3, 5)],
				[Vector2i(3, 4), Vector2i(3, 3), Vector2i(2, 3)],
				[Vector2i(2, 2), Vector2i(1, 2), Vector2i(1, 1), Vector2i(2, 1), Vector2i(2, 0)],
			],
			"branch_paths": [
				[Vector2i(5, 8), Vector2i(6, 8), Vector2i(6, 7)],
			],
			"watchtower_cells": [Vector2i(6, 7)],
			"partner_cells": [Vector2i(6, 7)],
			"obstacles": [
				Vector2i(7, 9), Vector2i(2, 9), Vector2i(0, 7),
				Vector2i(4, 6), Vector2i(0, 5), Vector2i(4, 3),
			],
		},
		{
			"index": 5,
			"name": "第 15 关 · 双向取舍",
			"lesson": "伙伴与瞭望塔分居两侧，选择值得付出的迁徙日",
			"seed": 61,
			"start": Vector2i(3, 11),
			"goal": Vector2i(7, -1),
			"fog_radius": 2,
			"paths": [
				[Vector2i(3, 10), Vector2i(4, 10), Vector2i(4, 9)],
				[Vector2i(5, 9), Vector2i(6, 9), Vector2i(6, 8), Vector2i(7, 8)],
				[Vector2i(7, 7), Vector2i(6, 7), Vector2i(5, 7)],
				[Vector2i(5, 6), Vector2i(4, 6), Vector2i(4, 5), Vector2i(3, 5)],
				[Vector2i(3, 4), Vector2i(4, 4), Vector2i(5, 4)],
				[Vector2i(5, 3), Vector2i(6, 3), Vector2i(6, 2)],
				[Vector2i(7, 2), Vector2i(7, 1), Vector2i(7, 0)],
			],
			"branch_paths": [
				[Vector2i(3, 9), Vector2i(2, 9), Vector2i(2, 8)],
				[Vector2i(3, 6), Vector2i(2, 6), Vector2i(2, 5)],
			],
			"watchtower_cells": [Vector2i(2, 8)],
			"partner_cells": [Vector2i(2, 5)],
			"obstacles": [
				Vector2i(1, 10), Vector2i(1, 8), Vector2i(4, 8),
				Vector2i(1, 6), Vector2i(6, 6), Vector2i(1, 4),
			],
		},
		{
			"index": 6,
			"name": "第 16 关 · 长路穿沙",
			"lesson": "连续长路径快速推进，瞭望绕路提供全局判断",
			"seed": 67,
			"start": Vector2i(0, 11),
			"goal": Vector2i(5, -1),
			"fog_radius": 2,
			"paths": [
				[Vector2i(0, 10), Vector2i(1, 10), Vector2i(2, 10), Vector2i(2, 9), Vector2i(3, 9)],
				[Vector2i(3, 8), Vector2i(4, 8), Vector2i(5, 8), Vector2i(5, 7), Vector2i(6, 7)],
				[Vector2i(6, 6), Vector2i(5, 6), Vector2i(4, 6), Vector2i(4, 5), Vector2i(3, 5)],
				[Vector2i(3, 4), Vector2i(4, 4), Vector2i(5, 4), Vector2i(5, 3), Vector2i(6, 3)],
				[Vector2i(6, 2), Vector2i(5, 2), Vector2i(5, 1), Vector2i(5, 0)],
			],
			"branch_paths": [
				[Vector2i(4, 7), Vector2i(3, 7), Vector2i(3, 6)],
			],
			"watchtower_cells": [Vector2i(3, 6)],
			"obstacles": [
				Vector2i(1, 9), Vector2i(6, 9), Vector2i(2, 8),
				Vector2i(7, 6), Vector2i(2, 5), Vector2i(7, 4),
			],
		},
		{
			"index": 7,
			"name": "第 17 关 · 深雾救援",
			"lesson": "用瞭望视野定位伙伴，再从旧前沿展开救援",
			"seed": 71,
			"start": Vector2i(7, 11),
			"goal": Vector2i(0, -1),
			"fog_radius": 1,
			"watchtower_reveal_radius": 6,
			"paths": [
				[Vector2i(7, 10), Vector2i(6, 10), Vector2i(6, 9)],
				[Vector2i(5, 9), Vector2i(4, 9), Vector2i(4, 8), Vector2i(3, 8)],
				[Vector2i(3, 7), Vector2i(2, 7), Vector2i(2, 6)],
				[Vector2i(1, 6), Vector2i(1, 5), Vector2i(2, 5), Vector2i(3, 5)],
				[Vector2i(3, 4), Vector2i(2, 4), Vector2i(1, 4)],
				[Vector2i(1, 3), Vector2i(0, 3), Vector2i(0, 2)],
				[Vector2i(1, 2), Vector2i(1, 1), Vector2i(0, 1), Vector2i(0, 0)],
			],
			"branch_paths": [
				[Vector2i(2, 8), Vector2i(1, 8), Vector2i(1, 7)],
				[Vector2i(3, 6), Vector2i(4, 6), Vector2i(4, 5)],
			],
			"watchtower_cells": [Vector2i(1, 7)],
			"partner_cells": [Vector2i(4, 5)],
			"obstacles": [
				Vector2i(7, 8), Vector2i(5, 7), Vector2i(0, 7),
				Vector2i(5, 5), Vector2i(0, 5), Vector2i(4, 3),
			],
		},
		{
			"index": 8,
			"name": "第 18 关 · 水塘之后",
			"lesson": "先完成补给，再决定是否为远景多走一天",
			"seed": 73,
			"start": Vector2i(2, 11),
			"goal": Vector2i(6, -1),
			"fog_radius": 2,
			"paths": [
				[Vector2i(2, 10), Vector2i(3, 10), Vector2i(3, 9)],
				[Vector2i(4, 9), Vector2i(5, 9), Vector2i(5, 8), Vector2i(6, 8)],
				[Vector2i(6, 7), Vector2i(7, 7), Vector2i(7, 6)],
				[Vector2i(6, 6), Vector2i(5, 6), Vector2i(5, 5)],
				[Vector2i(5, 4), Vector2i(6, 4), Vector2i(6, 3), Vector2i(7, 3)],
				[Vector2i(7, 2), Vector2i(6, 2), Vector2i(6, 1), Vector2i(6, 0)],
			],
			"branch_paths": [
				[Vector2i(2, 9), Vector2i(1, 9), Vector2i(1, 8)],
			],
			"watchtower_cells": [Vector2i(1, 8)],
			"checkpoint_cells": [Vector2i(5, 5)],
			"obstacles": [
				Vector2i(1, 10), Vector2i(0, 9), Vector2i(4, 8),
				Vector2i(4, 6), Vector2i(7, 5), Vector2i(4, 3),
			],
		},
		{
			"index": 9,
			"name": "第 19 关 · 两座营地",
			"lesson": "在多个旧前沿间切换，兼顾瞭望与掉队伙伴",
			"seed": 79,
			"start": Vector2i(5, 11),
			"goal": Vector2i(3, -1),
			"fog_radius": 2,
			"paths": [
				[Vector2i(5, 10), Vector2i(4, 10), Vector2i(3, 10), Vector2i(3, 9)],
				[Vector2i(2, 9), Vector2i(1, 9), Vector2i(1, 8)],
				[Vector2i(1, 7), Vector2i(2, 7), Vector2i(3, 7), Vector2i(3, 6)],
				[Vector2i(4, 6), Vector2i(5, 6), Vector2i(5, 5)],
				[Vector2i(4, 5), Vector2i(3, 5), Vector2i(3, 4)],
				[Vector2i(3, 3), Vector2i(2, 3), Vector2i(2, 2), Vector2i(3, 2)],
				[Vector2i(3, 1), Vector2i(4, 1), Vector2i(4, 0), Vector2i(3, 0)],
			],
			"branch_paths": [
				[Vector2i(2, 8), Vector2i(3, 8), Vector2i(4, 8)],
				[Vector2i(6, 5), Vector2i(6, 4), Vector2i(5, 4)],
			],
			"watchtower_cells": [Vector2i(4, 8)],
			"partner_cells": [Vector2i(5, 4)],
			"obstacles": [
				Vector2i(6, 10), Vector2i(0, 8), Vector2i(5, 8),
				Vector2i(0, 6), Vector2i(6, 6), Vector2i(1, 4),
			],
		},
		{
			"index": 10,
			"name": "第 20 关 · 明亮尽头",
			"lesson": "综合瞭望、补给、伙伴与长路径完成最终迁徙",
			"seed": 83,
			"start": Vector2i(4, 11),
			"goal": Vector2i(4, -1),
			"fog_radius": 1,
			"watchtower_reveal_radius": 6,
			"paths": [
				[Vector2i(4, 10), Vector2i(5, 10), Vector2i(6, 10), Vector2i(6, 9)],
				[Vector2i(5, 9), Vector2i(4, 9), Vector2i(3, 9)],
				[Vector2i(3, 8), Vector2i(2, 8), Vector2i(2, 7), Vector2i(1, 7)],
				[Vector2i(1, 6), Vector2i(2, 6), Vector2i(3, 6)],
				[Vector2i(3, 5), Vector2i(4, 5), Vector2i(5, 5), Vector2i(5, 4)],
				[Vector2i(4, 4), Vector2i(3, 4), Vector2i(3, 3)],
				[Vector2i(3, 2), Vector2i(4, 2), Vector2i(4, 1), Vector2i(4, 0)],
			],
			"branch_paths": [
				[Vector2i(1, 8), Vector2i(0, 8), Vector2i(0, 7)],
				[Vector2i(6, 5), Vector2i(7, 5), Vector2i(7, 4)],
			],
			"watchtower_cells": [Vector2i(0, 7)],
			"partner_cells": [Vector2i(7, 4)],
			"checkpoint_cells": [Vector2i(3, 4)],
			"obstacles": [
				Vector2i(7, 9), Vector2i(0, 9), Vector2i(4, 8),
				Vector2i(0, 6), Vector2i(6, 6), Vector2i(2, 4),
			],
		},
	]


static func _make_stuck_level() -> Dictionary:
	var data := _make_base("内部测试 · 无路恢复", 29, DEFAULT_WIDTH, DEFAULT_HEIGHT)
	var start := Vector2i(0, 11)
	var goal := Vector2i(6, -1)
	_set_terrain(data, start, BoardModel.Terrain.START)
	_set_number(data, Vector2i(0, 10), 5)
	_set_number(data, Vector2i(1, 10), 6)
	_set_number(data, Vector2i(2, 10), 7)
	for obstacle in [
		Vector2i(0, 9),
		Vector2i(1, 9),
		Vector2i(1, 11),
		Vector2i(2, 9),
		Vector2i(2, 11),
		Vector2i(3, 10),
	]:
		_set_terrain(data, obstacle, BoardModel.Terrain.BLOCKED)
	data["chapter"] = 0
	data["chapter_id"] = "internal"
	data["id"] = "internal_stuck"
	data["level_index"] = 0
	data["global_index"] = 0
	data["lesson"] = "验证开局死路检测与恢复操作"
	data["recommended_days"] = 0
	data["optimal_days"] = 0
	data["start"] = start
	data["goal"] = goal
	data["intended_paths"] = []
	data["branch_paths"] = []
	data["branch_path"] = []
	data["partner_cells"] = []
	data["checkpoint_cells"] = []
	data["watchtower_cells"] = []
	data["watchtower_reveal_radius"] = 5
	data["fog_radius"] = 0
	data["tutorial"] = false
	data["is_chapter_final"] = false
	return data


static func _make_base(display_name: String, seed: int, width: int, height: int) -> Dictionary:
	var numbers := PackedInt32Array()
	var terrain := PackedInt32Array()
	numbers.resize(width * height)
	terrain.resize(width * height)
	for y in height:
		for x in width:
			var index := y * width + x
			# Filler cells are deliberate decoys rather than random solution
			# generators. Orthogonal neighbors alternate between a low (5/6)
			# and high (10/11) band, so filler-only chains cannot sum to 24;
			# authored routes and branches remain the source of meaningful moves.
			if posmod(x + y, 2) == 0:
				numbers[index] = 5 + posmod(x * 2 + y * 3 + seed, 2)
			else:
				numbers[index] = 10 + posmod(x * 3 + y * 2 + seed, 2)
			terrain[index] = BoardModel.Terrain.NUMBER
	return {
		"name": display_name,
		"width": width,
		"height": height,
		"numbers": numbers,
		"terrain": terrain,
	}


static func _set_number(data: Dictionary, cell: Vector2i, value: int) -> void:
	var numbers: PackedInt32Array = data["numbers"]
	var width := int(data["width"])
	numbers[cell.y * width + cell.x] = value
	data["numbers"] = numbers


static func _set_terrain(data: Dictionary, cell: Vector2i, value: int) -> void:
	var terrain: PackedInt32Array = data["terrain"]
	var numbers: PackedInt32Array = data["numbers"]
	var width := int(data["width"])
	var index := cell.y * width + cell.x
	terrain[index] = value
	if value != BoardModel.Terrain.NUMBER:
		numbers[index] = 0
	data["terrain"] = terrain
	data["numbers"] = numbers
