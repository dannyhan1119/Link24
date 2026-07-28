extends RefCounted
class_name MigrationLevelCatalog

const BoardModel = preload("res://src/model/board_model.gd")
const WIDTH := 8
const HEIGHT := 12


static func all_levels() -> Array[Dictionary]:
	var levels := playable_levels()
	levels.append(_make_stuck_level())
	return levels


static func playable_levels() -> Array[Dictionary]:
	var levels: Array[Dictionary] = []
	for spec in _chapter_one_specs():
		levels.append(_make_chapter_level(spec))
	return levels


static func stuck_test_level() -> Dictionary:
	return _make_stuck_level()


static func _make_chapter_level(spec: Dictionary) -> Dictionary:
	var data := _make_base(str(spec["name"]), int(spec["seed"]))
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

	data["chapter"] = 1
	data["level_index"] = int(spec["index"])
	data["lesson"] = str(spec["lesson"])
	data["recommended_days"] = int(spec.get("recommended_days", paths.size()))
	data["start"] = start
	data["goal"] = goal
	data["intended_paths"] = paths
	data["branch_paths"] = branch_paths
	data["branch_path"] = branch_paths[0] if not branch_paths.is_empty() else []
	data["partner_cells"] = spec.get("partner_cells", []).duplicate()
	data["checkpoint_cells"] = spec.get("checkpoint_cells", []).duplicate()
	data["fog_radius"] = int(spec.get("fog_radius", 0))
	data["tutorial"] = bool(spec.get("tutorial", false))
	return data


static func _segment_values(length: int, variant: int) -> Array[int]:
	var options := {
		2: [
			[12, 12],
		],
		3: [
			[8, 8, 8],
			[10, 8, 6],
			[11, 7, 6],
			[9, 9, 6],
		],
		4: [
			[9, 7, 5, 3],
			[6, 6, 5, 7],
			[12, 4, 3, 5],
			[8, 7, 4, 5],
		],
		5: [
			[4, 5, 6, 4, 5],
			[2, 5, 7, 6, 4],
			[3, 3, 6, 7, 5],
			[8, 4, 3, 4, 5],
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
			"recommended_days": 6,
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
			"recommended_days": 5,
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
			"recommended_days": 6,
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
			"recommended_days": 6,
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
			"recommended_days": 6,
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
			"recommended_days": 5,
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
			"recommended_days": 6,
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
			"recommended_days": 6,
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
			"recommended_days": 6,
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
			"recommended_days": 7,
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


static func _make_stuck_level() -> Dictionary:
	var data := _make_base("内部测试 · 无路恢复", 29)
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
	data["level_index"] = 0
	data["lesson"] = "验证开局死路检测与恢复操作"
	data["recommended_days"] = 0
	data["start"] = start
	data["goal"] = goal
	data["intended_paths"] = []
	data["branch_paths"] = []
	data["branch_path"] = []
	data["partner_cells"] = []
	data["checkpoint_cells"] = []
	data["fog_radius"] = 0
	data["tutorial"] = false
	return data


static func _make_base(display_name: String, seed: int) -> Dictionary:
	var numbers := PackedInt32Array()
	var terrain := PackedInt32Array()
	numbers.resize(WIDTH * HEIGHT)
	terrain.resize(WIDTH * HEIGHT)
	for y in HEIGHT:
		for x in WIDTH:
			var index := y * WIDTH + x
			numbers[index] = 1 + posmod(x * 5 + y * 7 + seed, 12)
			terrain[index] = BoardModel.Terrain.NUMBER
	return {
		"name": display_name,
		"width": WIDTH,
		"height": HEIGHT,
		"numbers": numbers,
		"terrain": terrain,
	}


static func _set_number(data: Dictionary, cell: Vector2i, value: int) -> void:
	var numbers: PackedInt32Array = data["numbers"]
	numbers[cell.y * WIDTH + cell.x] = value
	data["numbers"] = numbers


static func _set_terrain(data: Dictionary, cell: Vector2i, value: int) -> void:
	var terrain: PackedInt32Array = data["terrain"]
	var numbers: PackedInt32Array = data["numbers"]
	var index := cell.y * WIDTH + cell.x
	terrain[index] = value
	if value != BoardModel.Terrain.NUMBER:
		numbers[index] = 0
	data["terrain"] = terrain
	data["numbers"] = numbers
