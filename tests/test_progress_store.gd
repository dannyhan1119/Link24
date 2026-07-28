extends SceneTree

const ProgressStore = preload("res://src/model/progress_store.gd")

var failures: Array[String] = []
var assertions := 0
var test_path := ""


func _initialize() -> void:
	test_path = "/tmp/link24_progress_store_test_%d.cfg" % Time.get_ticks_usec()
	var store := ProgressStore.new()
	store.load_progress(test_path)
	_expect(store.unlocked_level >= 1, "progress always unlocks at least level one")
	_expect(store.complete_level(1, 7, 0) == OK, "level completion saves successfully")
	_expect(store.unlocked_level >= 2, "completing level one unlocks level two")
	_expect(store.is_completed(1), "completed level is recorded")
	_expect(store.best_days_for(1) == 7, "first completion stores its migration days")

	store.complete_level(1, 9, 0)
	_expect(store.best_days_for(1) == 7, "slower replay does not replace the best result")
	store.complete_level(1, 5, 1)
	_expect(store.best_days_for(1) == 5, "faster replay updates the best result")
	_expect(store.partners_for(1) == 1, "rescued partner progress is recorded")

	var reloaded := ProgressStore.new()
	reloaded.load_progress(test_path)
	_expect(reloaded.is_completed(1), "completion survives a disk reload")
	_expect(reloaded.is_unlocked(2), "unlocked level survives a disk reload")
	_expect(reloaded.best_days_for(1) == 5, "best days survive a disk reload")
	_expect(reloaded.partners_for(1) == 1, "partner result survives a disk reload")
	_expect(
		reloaded.complete_level(0, 1, 0) == ERR_INVALID_PARAMETER,
		"invalid level indices are rejected"
	)

	if failures.is_empty():
		print("PASS: %d progress-store assertions" % assertions)
		quit(0)
	else:
		for failure in failures:
			push_error("FAIL: %s" % failure)
		print("FAILED: %d of %d assertions" % [failures.size(), assertions])
		quit(1)


func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
