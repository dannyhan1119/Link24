extends RefCounted
class_name MigrationProgressStore

const DEFAULT_SAVE_PATH := "user://link24_progress.cfg"
const CHAPTER_LEVEL_COUNT := 10

var save_path := DEFAULT_SAVE_PATH
var unlocked_level := 1
var completed_levels: Dictionary = {}
var best_days: Dictionary = {}
var rescued_partners: Dictionary = {}


func load_progress(path := DEFAULT_SAVE_PATH) -> void:
	save_path = path
	unlocked_level = 1
	completed_levels.clear()
	best_days.clear()
	rescued_partners.clear()

	var config := ConfigFile.new()
	if config.load(save_path) != OK:
		return
	unlocked_level = clampi(
		int(config.get_value("chapter_1", "unlocked_level", 1)),
		1,
		CHAPTER_LEVEL_COUNT
	)
	for level_index in range(1, CHAPTER_LEVEL_COUNT + 1):
		var key := str(level_index)
		if bool(config.get_value("completed", key, false)):
			completed_levels[level_index] = true
		var stored_days := int(config.get_value("best_days", key, 0))
		if stored_days > 0:
			best_days[level_index] = stored_days
		var stored_partners := int(config.get_value("partners", key, 0))
		if stored_partners > 0:
			rescued_partners[level_index] = stored_partners


func complete_level(level_index: int, days: int, partners: int) -> Error:
	if level_index < 1 or level_index > CHAPTER_LEVEL_COUNT:
		return ERR_INVALID_PARAMETER
	completed_levels[level_index] = true
	if days > 0:
		var previous_best := int(best_days.get(level_index, 0))
		if previous_best == 0 or days < previous_best:
			best_days[level_index] = days
	if partners > int(rescued_partners.get(level_index, 0)):
		rescued_partners[level_index] = partners
	if level_index < CHAPTER_LEVEL_COUNT:
		unlocked_level = maxi(unlocked_level, level_index + 1)
	else:
		unlocked_level = CHAPTER_LEVEL_COUNT
	return save_progress()


func save_progress() -> Error:
	var config := ConfigFile.new()
	config.set_value("chapter_1", "unlocked_level", unlocked_level)
	for level_index in range(1, CHAPTER_LEVEL_COUNT + 1):
		var key := str(level_index)
		config.set_value("completed", key, completed_levels.has(level_index))
		config.set_value("best_days", key, int(best_days.get(level_index, 0)))
		config.set_value("partners", key, int(rescued_partners.get(level_index, 0)))
	return config.save(save_path)


func is_unlocked(level_index: int) -> bool:
	return level_index >= 1 and level_index <= unlocked_level


func is_completed(level_index: int) -> bool:
	return completed_levels.has(level_index)


func best_days_for(level_index: int) -> int:
	return int(best_days.get(level_index, 0))


func partners_for(level_index: int) -> int:
	return int(rescued_partners.get(level_index, 0))
