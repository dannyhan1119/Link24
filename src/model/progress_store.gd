extends RefCounted
class_name MigrationProgressStore

const DEFAULT_SAVE_PATH := "user://link24_progress.cfg"
const SAVE_VERSION := 4
const DECORATION_TIERS := [
	{"id": "natural", "label": "自然绿洲", "points": 0},
	{"id": "wind_chimes", "label": "迁徙风铃", "points": 6},
	{"id": "flower_garden", "label": "彩色花圃", "points": 12},
	{"id": "shade_tent", "label": "伙伴凉棚", "points": 18},
	{"id": "star_lanterns", "label": "星光灯串", "points": 24},
	{"id": "festival_flags", "label": "庆典彩旗", "points": 30},
]
const RESIDENT_SPECIES := ["耳廓狐", "狐獴", "岩羊", "幼象", "长颈鹿"]

var save_path := DEFAULT_SAVE_PATH
var chapter_order: Array[String] = []
var chapter_level_ids: Dictionary = {}
var level_lookup: Dictionary = {}
var unlocked_levels: Dictionary = {}
var completed_levels: Dictionary = {}
var best_days: Dictionary = {}
var rescued_partners: Dictionary = {}
var explored_watchtowers: Dictionary = {}
var selected_decorations: Dictionary = {}


func configure_chapters(chapters: Array[Dictionary]) -> void:
	chapter_order.clear()
	chapter_level_ids.clear()
	level_lookup.clear()
	for chapter in chapters:
		var chapter_id := str(chapter["id"])
		chapter_order.append(chapter_id)
		var ids: Array[String] = []
		var levels: Array = chapter["levels"]
		for local_index in levels.size():
			var level: Dictionary = levels[local_index]
			var level_id := str(level["id"])
			ids.append(level_id)
			level_lookup[level_id] = {
				"chapter_id": chapter_id,
				"local_index": local_index,
				"level": level,
			}
		chapter_level_ids[chapter_id] = ids
	_normalize_unlocks()


func load_progress(path := DEFAULT_SAVE_PATH) -> void:
	save_path = path
	unlocked_levels.clear()
	completed_levels.clear()
	best_days.clear()
	rescued_partners.clear()
	explored_watchtowers.clear()
	selected_decorations.clear()
	_unlock_first_chapter()

	var config := ConfigFile.new()
	if config.load(save_path) != OK:
		return
	var version := int(config.get_value("meta", "version", 1))
	if version >= 2:
		_load_current_format(config)
	else:
		_load_legacy_first_chapter(config)
	_normalize_unlocks()
	if version < SAVE_VERSION:
		save_progress()


func complete_level(level_id: String, days: int, partners: int, watchtowers := 0) -> Error:
	if not level_lookup.has(level_id):
		return ERR_INVALID_PARAMETER
	var location: Dictionary = level_lookup[level_id]
	var chapter_id := str(location["chapter_id"])
	var local_index := int(location["local_index"])
	var ids: Array = chapter_level_ids[chapter_id]

	completed_levels[level_id] = true
	if days > 0:
		var previous_best := int(best_days.get(level_id, 0))
		if previous_best == 0 or days < previous_best:
			best_days[level_id] = days
	if partners > int(rescued_partners.get(level_id, 0)):
		rescued_partners[level_id] = partners
	if watchtowers > int(explored_watchtowers.get(level_id, 0)):
		explored_watchtowers[level_id] = watchtowers

	if local_index + 1 < ids.size():
		unlocked_levels[chapter_id] = maxi(
			int(unlocked_levels.get(chapter_id, 1)),
			local_index + 2
		)
	else:
		unlocked_levels[chapter_id] = ids.size()
		_unlock_chapter_after(chapter_id)
	return save_progress()


func save_progress() -> Error:
	var config := ConfigFile.new()
	config.set_value("meta", "version", SAVE_VERSION)
	for chapter_id in chapter_order:
		config.set_value(
			"unlocks",
			chapter_id,
			int(unlocked_levels.get(chapter_id, 0))
		)
	for level_id in level_lookup:
		config.set_value("completed", level_id, completed_levels.has(level_id))
		config.set_value("best_days", level_id, int(best_days.get(level_id, 0)))
		config.set_value("partners", level_id, int(rescued_partners.get(level_id, 0)))
		config.set_value("watchtowers", level_id, int(explored_watchtowers.get(level_id, 0)))
	for chapter_id in chapter_order:
		config.set_value(
			"home",
			"%s_decoration" % chapter_id,
			selected_decoration_for(chapter_id)
		)
	return config.save(save_path)


func is_chapter_unlocked(chapter_id: String) -> bool:
	return int(unlocked_levels.get(chapter_id, 0)) > 0


func is_chapter_completed(chapter_id: String) -> bool:
	var ids: Array = chapter_level_ids.get(chapter_id, [])
	if ids.is_empty():
		return false
	for level_id in ids:
		if not completed_levels.has(str(level_id)):
			return false
	return true


func unlocked_level_count(chapter_id: String) -> int:
	return int(unlocked_levels.get(chapter_id, 0))


func is_level_unlocked(level_id: String) -> bool:
	if not level_lookup.has(level_id):
		return false
	var location: Dictionary = level_lookup[level_id]
	var chapter_id := str(location["chapter_id"])
	return int(location["local_index"]) < unlocked_level_count(chapter_id)


func is_completed(level_id: String) -> bool:
	return completed_levels.has(level_id)


func best_days_for(level_id: String) -> int:
	return int(best_days.get(level_id, 0))


func partners_for(level_id: String) -> int:
	return int(rescued_partners.get(level_id, 0))


func watchtowers_for(level_id: String) -> int:
	return int(explored_watchtowers.get(level_id, 0))


func chapter_resident_total(chapter_id: String) -> int:
	var total := 0
	for level_id in chapter_level_ids.get(chapter_id, []):
		var level: Dictionary = level_lookup[str(level_id)]["level"]
		total += level.get("partner_cells", []).size()
	return total


func chapter_resident_count(chapter_id: String) -> int:
	var count := 0
	for level_id in chapter_level_ids.get(chapter_id, []):
		var level: Dictionary = level_lookup[str(level_id)]["level"]
		count += mini(
			partners_for(str(level_id)),
			level.get("partner_cells", []).size()
		)
	return count


func chapter_residents(chapter_id: String) -> Array[Dictionary]:
	var residents: Array[Dictionary] = []
	var species_index := 0
	for level_id_variant in chapter_level_ids.get(chapter_id, []):
		var level_id := str(level_id_variant)
		var level: Dictionary = level_lookup[level_id]["level"]
		var rescued_count := partners_for(level_id)
		for partner_index in level.get("partner_cells", []).size():
			residents.append({
				"id": "%s_partner_%d" % [level_id, partner_index + 1],
				"name": RESIDENT_SPECIES[species_index % RESIDENT_SPECIES.size()],
				"rescued": partner_index < rescued_count,
				"level_id": level_id,
			})
			species_index += 1
	return residents


func unlocked_decorations_for(chapter_id: String) -> Array[Dictionary]:
	var points := chapter_badge_count(chapter_id)
	var unlocked: Array[Dictionary] = []
	for tier in DECORATION_TIERS:
		if points >= int(tier["points"]):
			unlocked.append(tier.duplicate())
	return unlocked


func decoration_tiers() -> Array[Dictionary]:
	var tiers: Array[Dictionary] = []
	for tier in DECORATION_TIERS:
		tiers.append(tier.duplicate())
	return tiers


func selected_decoration_for(chapter_id: String) -> String:
	var unlocked := unlocked_decorations_for(chapter_id)
	if unlocked.is_empty():
		return "natural"
	var selected := str(selected_decorations.get(chapter_id, "natural"))
	for tier in unlocked:
		if str(tier["id"]) == selected:
			return selected
	return str(unlocked[0]["id"])


func select_decoration(chapter_id: String, decoration_id: String) -> Error:
	var allowed := false
	for tier in unlocked_decorations_for(chapter_id):
		if str(tier["id"]) == decoration_id:
			allowed = true
			break
	if not allowed:
		return ERR_UNAVAILABLE
	selected_decorations[chapter_id] = decoration_id
	return save_progress()


func badge_states_for(level_id: String) -> Dictionary:
	if not level_lookup.has(level_id):
		return {
			"arrival": false,
			"efficient": false,
			"mastery": false,
		}
	var level: Dictionary = level_lookup[level_id]["level"]
	var arrived := is_completed(level_id)
	var best := best_days_for(level_id)
	var recommended := int(level.get("recommended_days", 0))
	var optimal := int(level.get("optimal_days", recommended))
	var total_partners: int = level.get("partner_cells", []).size()
	var total_watchtowers: int = level.get("watchtower_cells", []).size()
	var mastery := false
	if total_partners > 0 or total_watchtowers > 0:
		mastery = (
			arrived
			and partners_for(level_id) >= total_partners
			and watchtowers_for(level_id) >= total_watchtowers
		)
	else:
		mastery = arrived and optimal > 0 and best > 0 and best <= optimal
	return {
		"arrival": arrived,
		"efficient": arrived and recommended > 0 and best > 0 and best <= recommended,
		"mastery": mastery,
	}


func badge_labels_for(level_id: String) -> PackedStringArray:
	if not level_lookup.has(level_id):
		return PackedStringArray(["抵达", "远行家", "先锋"])
	var level: Dictionary = level_lookup[level_id]["level"]
	var mastery_label := "先锋"
	if not level.get("watchtower_cells", []).is_empty():
		mastery_label = "探索"
	elif not level.get("partner_cells", []).is_empty():
		mastery_label = "伙伴"
	return PackedStringArray(["抵达", "远行家", mastery_label])


func level_badge_count(level_id: String) -> int:
	var states := badge_states_for(level_id)
	var count := 0
	for key in ["arrival", "efficient", "mastery"]:
		if bool(states.get(key, false)):
			count += 1
	return count


func chapter_badge_count(chapter_id: String) -> int:
	var count := 0
	for level_id in chapter_level_ids.get(chapter_id, []):
		count += level_badge_count(str(level_id))
	return count


func chapter_badge_total(chapter_id: String) -> int:
	return chapter_level_ids.get(chapter_id, []).size() * 3


func chapter_growth_stage(chapter_id: String) -> int:
	var total := chapter_badge_total(chapter_id)
	if total <= 0:
		return 0
	var count := chapter_badge_count(chapter_id)
	if count >= total:
		return 4
	if count * 5 >= total * 4:
		return 3
	if count * 5 >= total * 3:
		return 2
	if count * 3 >= total:
		return 1
	return 0


func latest_unlocked_chapter_index() -> int:
	var latest := 0
	for index in chapter_order.size():
		if is_chapter_unlocked(chapter_order[index]):
			latest = index
	return latest


func latest_unlocked_level_index(chapter_id: String) -> int:
	var ids: Array = chapter_level_ids.get(chapter_id, [])
	if ids.is_empty():
		return 0
	return clampi(unlocked_level_count(chapter_id) - 1, 0, ids.size() - 1)


func _load_current_format(config: ConfigFile) -> void:
	for chapter_id in chapter_order:
		unlocked_levels[chapter_id] = int(
			config.get_value("unlocks", chapter_id, unlocked_levels.get(chapter_id, 0))
		)
	for level_id in level_lookup:
		if bool(config.get_value("completed", level_id, false)):
			completed_levels[level_id] = true
		var stored_days := int(config.get_value("best_days", level_id, 0))
		if stored_days > 0:
			best_days[level_id] = stored_days
		var stored_partners := int(config.get_value("partners", level_id, 0))
		if stored_partners > 0:
			rescued_partners[level_id] = stored_partners
		var stored_watchtowers := int(config.get_value("watchtowers", level_id, 0))
		if stored_watchtowers > 0:
			explored_watchtowers[level_id] = stored_watchtowers
	for chapter_id in chapter_order:
		var decoration := str(
			config.get_value("home", "%s_decoration" % chapter_id, "natural")
		)
		selected_decorations[chapter_id] = decoration


func _load_legacy_first_chapter(config: ConfigFile) -> void:
	if chapter_order.is_empty():
		return
	var first_chapter_id := chapter_order[0]
	var ids: Array = chapter_level_ids.get(first_chapter_id, [])
	unlocked_levels[first_chapter_id] = clampi(
		int(config.get_value("chapter_1", "unlocked_level", 1)),
		1,
		maxi(1, ids.size())
	)
	for local_index in ids.size():
		var legacy_key := str(local_index + 1)
		var level_id := str(ids[local_index])
		if bool(config.get_value("completed", legacy_key, false)):
			completed_levels[level_id] = true
		var stored_days := int(config.get_value("best_days", legacy_key, 0))
		if stored_days > 0:
			best_days[level_id] = stored_days
		var stored_partners := int(config.get_value("partners", legacy_key, 0))
		if stored_partners > 0:
			rescued_partners[level_id] = stored_partners


func _unlock_first_chapter() -> void:
	if chapter_order.is_empty():
		return
	var first_chapter_id := chapter_order[0]
	unlocked_levels[first_chapter_id] = maxi(
		1,
		int(unlocked_levels.get(first_chapter_id, 0))
	)


func _unlock_chapter_after(chapter_id: String) -> void:
	var chapter_index := chapter_order.find(chapter_id)
	if chapter_index >= 0 and chapter_index + 1 < chapter_order.size():
		var next_chapter_id := chapter_order[chapter_index + 1]
		unlocked_levels[next_chapter_id] = maxi(
			1,
			int(unlocked_levels.get(next_chapter_id, 0))
		)


func _normalize_unlocks() -> void:
	_unlock_first_chapter()
	for chapter_index in chapter_order.size():
		var chapter_id := chapter_order[chapter_index]
		var ids: Array = chapter_level_ids.get(chapter_id, [])
		unlocked_levels[chapter_id] = clampi(
			int(unlocked_levels.get(chapter_id, 0)),
			0,
			ids.size()
		)
		if chapter_index == 0 and not ids.is_empty():
			unlocked_levels[chapter_id] = maxi(1, int(unlocked_levels[chapter_id]))
		if not ids.is_empty() and completed_levels.has(str(ids.back())):
			_unlock_chapter_after(chapter_id)
