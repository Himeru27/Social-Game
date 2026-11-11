extends Node
## Autoload "PlayerProfile": the local player's username + appearance.
## apply() = use for this session. save_profile() = persist to user://character.json.

signal profile_changed

const SAVE_PATH := "user://character.json"

var username := ""
var appearance: Dictionary = AppearanceData.default_for("male")


func _ready() -> void:
	username = "Guest%d" % (1000 + randi() % 9000)
	load_profile()


func apply(new_name: String, new_appearance: Dictionary) -> void:
	if AppearanceData.validate_username(new_name) == "":
		username = new_name
	appearance = AppearanceData.sanitize(new_appearance)
	profile_changed.emit()


func save_profile() -> bool:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("PlayerProfile: could not write %s" % SAVE_PATH)
		return false
	f.store_string(JSON.stringify({"version": 1, "username": username, "appearance": appearance}, "\t"))
	return true


func load_profile() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not (parsed is Dictionary):
		return
	var n := str(parsed.get("username", ""))
	if AppearanceData.validate_username(n) == "":
		username = n
	if parsed.get("appearance") is Dictionary:
		appearance = AppearanceData.sanitize(parsed["appearance"])
	profile_changed.emit()
