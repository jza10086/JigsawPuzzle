extends RefCounted
## The fixed artwork pool and this device's persistent play counts.
## The host draws from its own history; each peer records the host's round sequence once.
const IDS: Array[String] = ["harbor", "balloons", "desert", "snow", "forest", "space", "reef", "windmill", "city", "tea", "railway"]
const ASSET_ROOT: String = "res://games/minigame/godot_party_default_jigsaw_puzzle/assets/pictures/"
const STATS_PATH: String = "minigame/godot_party_default_jigsaw_puzzle/config/picture_stats.json"
var counts: Dictionary[String, int] = empty_counts()
## Empty until the formal entry explicitly opens persistent storage; F6 stays in memory.
var path: String

static func empty_counts() -> Dictionary[String, int]:
	var result: Dictionary[String, int] = {}
	for id: String in IDS:
		result[id] = 0
	return result

static func choose(plays: Dictionary[String, int], rng: RandomNumberGenerator) -> String:
	var minimum: int = plays[IDS[0]]
	var candidates: Array[String] = []
	for id: String in IDS:
		minimum = mini(minimum, plays[id])
	for id: String in IDS:
		if plays[id] == minimum:
			candidates.append(id)
	return candidates[rng.randi_range(0, candidates.size() - 1)]

func open(storage_root: String) -> Error:
	path = storage_root.path_join(STATS_PATH)
	if not FileAccess.file_exists(path):
		counts = empty_counts()
		return OK
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()
	var json: JSON = JSON.new()
	var error: Error = json.parse(file.get_as_text())
	if error != OK:
		push_error("%s:%d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return error
	var data: Variant = json.data
	if not data is Dictionary or data.get("version") != 1 or not data.get("plays") is Dictionary:
		return ERR_INVALID_DATA
	if data.plays.size() != IDS.size():
		return ERR_INVALID_DATA
	var loaded: Dictionary[String, int] = {}
	for id: String in IDS:
		var value: Variant = data.plays.get(id)
		if (not value is int and not value is float) or not is_finite(float(value)):
			return ERR_INVALID_DATA
		if value < 0 or value > 9007199254740990 or float(value) != floorf(float(value)):
			return ERR_INVALID_DATA
		loaded[id] = int(value)
	counts = loaded
	return OK

## Save before acknowledging the sequence locally. A failed write never resets counts.
func record(pictures: Array) -> Error:
	var next: Dictionary[String, int] = counts.duplicate()
	for id: String in pictures:
		next[id] += 1
	if path.is_empty():
		counts = next
		return OK
	var error: Error = DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if error != OK:
		return error
	var pending: String = path + ".pending"
	var file: FileAccess = FileAccess.open(pending, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"version": 1, "plays": next}, "\t") + "\n")
	file.flush()
	error = file.get_error()
	file.close()
	if error != OK:
		return error
	error = DirAccess.rename_absolute(pending, path)
	if error == OK:
		counts = next
	return error
