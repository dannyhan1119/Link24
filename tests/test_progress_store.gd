extends SceneTree

const ProgressStore = preload("res://src/model/progress_store.gd")
const LevelCatalog = preload("res://src/model/level_catalog.gd")

var failures: Array[String] = []
var assertions := 0
var test_path := ""


func _initialize() -> void:
	test_path = "/tmp/link24_progress_store_test_%d.cfg" % Time.get_ticks_usec()
	var chapters := LevelCatalog.chapter_definitions()
	var chapter_one: Dictionary = chapters[0]
	var chapter_two: Dictionary = chapters[1]
	var first_level_id := str(chapter_one["levels"][0]["id"])
	var second_level_id := str(chapter_one["levels"][1]["id"])
	var chapter_two_first_id := str(chapter_two["levels"][0]["id"])
	var store := ProgressStore.new()
	store.configure_chapters(chapters)
	store.load_progress(test_path)
	_expect(store.is_chapter_unlocked("chapter_1"), "progress always unlocks chapter one")
	_expect(not store.is_chapter_unlocked("chapter_2"), "chapter two begins locked")
	_expect(store.is_level_unlocked(first_level_id), "the first level begins unlocked")
	_expect(not store.is_level_unlocked(second_level_id), "the second level begins locked")
	_expect(store.complete_level(first_level_id, 7, 0) == OK, "level completion saves successfully")
	_expect(store.is_level_unlocked(second_level_id), "completing level one unlocks level two")
	_expect(store.is_completed(first_level_id), "completed level is recorded by stable ID")
	_expect(store.best_days_for(first_level_id) == 7, "first completion stores its migration days")
	var first_badges := store.badge_states_for(first_level_id)
	_expect(first_badges["arrival"], "completion earns the arrival badge")
	_expect(first_badges["efficient"], "recommended-day completion earns the efficiency badge")
	_expect(not first_badges["mastery"], "story allowance does not also earn exact mastery")

	store.complete_level(first_level_id, 9, 0)
	_expect(store.best_days_for(first_level_id) == 7, "slower replay does not replace the best result")
	store.complete_level(first_level_id, 5, 1)
	_expect(store.best_days_for(first_level_id) == 5, "faster replay updates the best result")
	_expect(store.partners_for(first_level_id) == 1, "rescued partner progress is recorded")
	_expect(store.level_badge_count(first_level_id) == 3, "an optimal replay completes all three badges")

	var eighth_level: Dictionary = chapter_one["levels"][7]
	var eighth_level_id := str(eighth_level["id"])
	store.complete_level(eighth_level_id, int(eighth_level["recommended_days"]), 0)
	_expect(store.level_badge_count(eighth_level_id) == 2, "partner level begins with two performance badges")
	store.complete_level(eighth_level_id, int(eighth_level["recommended_days"]), 1)
	_expect(store.level_badge_count(eighth_level_id) == 3, "rescued partner completes the exploration badge")
	_expect(store.chapter_badge_count("chapter_1") >= 6, "chapter vitality sums earned level badges")
	_expect(store.chapter_badge_total("chapter_1") == 30, "a ten-level chapter offers thirty vitality")
	_expect(store.chapter_resident_total("chapter_1") == 1, "chapter one home lists one rescue resident")
	_expect(store.chapter_resident_count("chapter_1") == 1, "rescued partner moves into the chapter home")
	var chapter_one_residents := store.chapter_residents("chapter_1")
	_expect(
		chapter_one_residents.size() == 1 and chapter_one_residents[0]["rescued"],
		"home resident collection exposes the rescued animal"
	)
	_expect(
		store.unlocked_decorations_for("chapter_1").size() >= 2,
		"earned vitality unlocks more than the default home decoration"
	)
	_expect(
		store.select_decoration("chapter_1", "festival_flags") == ERR_UNAVAILABLE,
		"locked home decorations cannot be selected early"
	)
	_expect(
		store.select_decoration("chapter_1", "wind_chimes") == OK,
		"an unlocked home decoration can be selected"
	)

	var tower_level: Dictionary = chapter_two["levels"][0]
	var tower_level_id := str(tower_level["id"])
	store.complete_level(tower_level_id, int(tower_level["optimal_days"]), 0, 0)
	_expect(
		not store.badge_states_for(tower_level_id)["mastery"],
		"chapter-two mastery requires its optional watchtower"
	)
	store.complete_level(tower_level_id, int(tower_level["optimal_days"]), 0, 1)
	_expect(store.watchtowers_for(tower_level_id) == 1, "watchtower exploration is recorded")
	_expect(
		store.badge_states_for(tower_level_id)["mastery"],
		"visiting the watchtower completes the exploration badge"
	)

	var reloaded := ProgressStore.new()
	reloaded.configure_chapters(chapters)
	reloaded.load_progress(test_path)
	_expect(reloaded.is_completed(first_level_id), "completion survives a disk reload")
	_expect(reloaded.is_level_unlocked(second_level_id), "unlocked level survives a disk reload")
	_expect(reloaded.best_days_for(first_level_id) == 5, "best days survive a disk reload")
	_expect(reloaded.partners_for(first_level_id) == 1, "partner result survives a disk reload")
	_expect(reloaded.watchtowers_for(tower_level_id) == 1, "watchtower result survives a disk reload")
	_expect(
		reloaded.selected_decoration_for("chapter_1") == "wind_chimes",
		"selected home decoration survives a disk reload"
	)
	_expect(
		reloaded.complete_level("missing_level", 1, 0) == ERR_INVALID_PARAMETER,
		"invalid level IDs are rejected"
	)

	for level in chapter_one["levels"]:
		reloaded.complete_level(str(level["id"]), int(level["recommended_days"]), 0)
	_expect(reloaded.is_chapter_completed("chapter_1"), "all first-chapter levels complete the chapter")
	_expect(reloaded.is_chapter_unlocked("chapter_2"), "finishing chapter one unlocks chapter two")
	_expect(reloaded.is_level_unlocked(chapter_two_first_id), "chapter two opens at its first level")
	_expect(reloaded.latest_unlocked_chapter_index() == 1, "resume selects the newest unlocked chapter")

	_test_legacy_migration(chapters)

	if failures.is_empty():
		print("PASS: %d progress-store assertions" % assertions)
		quit(0)
	else:
		for failure in failures:
			push_error("FAIL: %s" % failure)
		print("FAILED: %d of %d assertions" % [failures.size(), assertions])
		quit(1)


func _test_legacy_migration(chapters: Array[Dictionary]) -> void:
	var legacy_path := "/tmp/link24_progress_store_legacy_%d.cfg" % Time.get_ticks_usec()
	var legacy := ConfigFile.new()
	legacy.set_value("chapter_1", "unlocked_level", 3)
	legacy.set_value("completed", "1", true)
	legacy.set_value("best_days", "1", 6)
	legacy.set_value("partners", "1", 1)
	_expect(legacy.save(legacy_path) == OK, "legacy fixture saves successfully")

	var migrated := ProgressStore.new()
	migrated.configure_chapters(chapters)
	migrated.load_progress(legacy_path)
	var first_level_id := str(chapters[0]["levels"][0]["id"])
	var third_level_id := str(chapters[0]["levels"][2]["id"])
	_expect(migrated.is_completed(first_level_id), "legacy completion migrates to a stable level ID")
	_expect(migrated.best_days_for(first_level_id) == 6, "legacy best days migrate")
	_expect(migrated.partners_for(first_level_id) == 1, "legacy partner result migrates")
	_expect(migrated.is_level_unlocked(third_level_id), "legacy unlocked level count migrates")


func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
