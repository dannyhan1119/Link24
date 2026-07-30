extends SceneTree

const SettingsStore = preload("res://src/model/settings_store.gd")
const Localization = preload("res://src/model/localization.gd")

var failures: Array[String] = []
var assertions := 0


func _initialize() -> void:
	var path := "/tmp/link24_settings_store_%d.cfg" % Time.get_ticks_usec()
	var settings := SettingsStore.new()
	settings.load_settings(path)
	_expect(settings.sound_enabled, "sound begins enabled")
	_expect(settings.vibration_enabled, "vibration begins enabled")
	_expect(not settings.reduced_motion, "reduced motion begins disabled")
	_expect(settings.set_sound_enabled(false) == OK, "sound preference saves")
	_expect(settings.set_vibration_enabled(false) == OK, "vibration preference saves")
	_expect(settings.set_reduced_motion(true) == OK, "reduced-motion preference saves")
	_expect(settings.set_language("en") == OK, "language preference saves")
	_expect(settings.set_language("unsupported") == ERR_INVALID_PARAMETER, "invalid locale is rejected")

	var reloaded := SettingsStore.new()
	reloaded.load_settings(path)
	_expect(not reloaded.sound_enabled, "sound preference survives reload")
	_expect(not reloaded.vibration_enabled, "vibration preference survives reload")
	_expect(reloaded.reduced_motion, "reduced-motion preference survives reload")
	_expect(reloaded.language == "en", "language preference survives reload")
	Localization.set_language(reloaded.language)
	_expect(
		Localization.text("第 11 关 · 沙丘瞭望  (1/10)").contains("Level 11 · Dune Watchtower"),
		"English localization translates embedded level titles"
	)
	_expect(Localization.text("第 6 天") == "Day 6", "English localization formats dynamic day labels")
	_expect(
		Localization.text("已撤回上一次开路，还可撤回 3 步")
		== "Undid the last path. Undo steps remaining: 3 steps",
		"English localization formats dynamic undo feedback"
	)
	_expect(
		Localization.text("用了 6 个迁徙日 · 伙伴 1/1 · 瞭望 1/1")
		== "Used 6 migration days · Partners 1/1 · Tower 1/1",
		"English localization formats dynamic completion feedback"
	)
	_expect(
		Localization.text("第一章完成") == "Chapter 1 Complete",
		"English localization covers dynamic chapter completion headings"
	)
	Localization.set_language("zh")
	_expect(Localization.text("绿洲家园") == "绿洲家园", "Chinese remains the default source locale")

	if failures.is_empty():
		print("PASS: %d settings assertions" % assertions)
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
