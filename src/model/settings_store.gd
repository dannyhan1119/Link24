extends RefCounted
class_name MigrationSettingsStore

const DEFAULT_SAVE_PATH := "user://link24_settings.cfg"
const SAVE_VERSION := 1

var save_path := DEFAULT_SAVE_PATH
var sound_enabled := true
var vibration_enabled := true
var reduced_motion := false
var language := "zh"


func load_settings(path := DEFAULT_SAVE_PATH) -> void:
	save_path = path
	var config := ConfigFile.new()
	if config.load(save_path) != OK:
		return
	sound_enabled = bool(config.get_value("accessibility", "sound_enabled", true))
	vibration_enabled = bool(config.get_value("accessibility", "vibration_enabled", true))
	reduced_motion = bool(config.get_value("accessibility", "reduced_motion", false))
	language = str(config.get_value("accessibility", "language", "zh"))
	if language not in ["zh", "en"]:
		language = "zh"


func save_settings() -> Error:
	var config := ConfigFile.new()
	config.set_value("meta", "version", SAVE_VERSION)
	config.set_value("accessibility", "sound_enabled", sound_enabled)
	config.set_value("accessibility", "vibration_enabled", vibration_enabled)
	config.set_value("accessibility", "reduced_motion", reduced_motion)
	config.set_value("accessibility", "language", language)
	return config.save(save_path)


func set_sound_enabled(enabled: bool) -> Error:
	sound_enabled = enabled
	return save_settings()


func set_vibration_enabled(enabled: bool) -> Error:
	vibration_enabled = enabled
	return save_settings()


func set_reduced_motion(enabled: bool) -> Error:
	reduced_motion = enabled
	return save_settings()


func set_language(value: String) -> Error:
	if value not in ["zh", "en"]:
		return ERR_INVALID_PARAMETER
	language = value
	return save_settings()
