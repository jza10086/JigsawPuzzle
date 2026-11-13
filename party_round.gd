extends Control

## Content-owned gameplay rules, independent of package compatibility.
static func party_definition() -> Dictionary:
	return {"player_counts": [1, 2, 3, 4, 5, 6, 7, 8]}

## Package-local PartyAPI boundary. The game owns all rounds and scoring;
## only logical actions go to the host; reliable events carry changed tiles and phase deadlines.
const GameScript: GDScript = preload("res://games/minigame/gp_jigsaw/scripts/main.gd")
const Pages: GDScript = preload("res://games/protocols/godot_party_default_protocol/round_pages.gd")
const Pictures: GDScript = preload("res://games/minigame/gp_jigsaw/scripts/picture_library.gd")
const ACTION: StringName = &"jigsaw/action"
const SNAPSHOT: StringName = &"jigsaw/state"
var api: PartyAPI
var request: Dictionary
var game: GameScript
@export var pages: Pages
var active: bool = false
var _closed: bool = false
var _published: Dictionary = {}
var _received: Dictionary = {}

func party_setup(context: PartyAPI, config: Dictionary) -> void:
	api = context
	request = config.duplicate(true)

	var roster: Array[Dictionary] = []
	var local_id: String = ""
	for player: Dictionary in api.get_players():
		roster.append({"player_id": player.player_id, "peer_id": player.peer_id, "name": player.name,
			"color": api.get_appearance(player.player_id).color})
		if player.is_local:
			local_id = player.player_id
	game = $Gameplay
	game.i18n = api.i18n
	game.party_input = api.input
	game.host_clock = api.net.host_time_msec
	game.configure(roster, local_id, api.is_host(), api.get_seed(), api.get_settings())
	game.action_requested.connect(_send_action)
	game.snapshot_ready.connect(_broadcast)
	game.match_completed.connect(_finish)
	game.picture_failed.connect(_picture_failed)

func _ready() -> void:
	add_to_group(&"party_minimal_hud")
	if api == null:
		push_error("请从小游戏轮换启动多人比赛；局部预览请运行 main.tscn。")
		return
	api.net.message_received.connect(_message)
	api.players_changed.connect(_players_changed)
	api.on_close(_close)
	# Only the formal entry opts into local persistence; F6 owns memory-only counts.
	var statistics: Pictures = Pictures.new()
	var error: Error = statistics.open(api.input.storage_directory())
	if error != OK:
		_fail("jigsaw_pictures", error)
		return
	game.picture_stats = statistics
	assert(pages != null, "Assign ProtocolPages in the game scene")
	error = pages.prepare(self, api, request, _start_gameplay)
	if error != OK:
		_fail("jigsaw_ready", error)

func party_start() -> void:
	pages.transport_started()

func godot_party_graphics_targets() -> Dictionary:
	return game.godot_party_graphics_targets()

func _start_gameplay() -> void:
	if _closed:
		return
	active = true
	game.start_match()
	_players_changed()

func _send_action(data: Dictionary) -> void:
	if not active:
		return
	var error: Error = api.net.send_to_host(ACTION, data)
	if error != OK:
		_fail("jigsaw_action", error)

func _broadcast(data: Dictionary) -> void:
	if not active:
		return
	var changed: Dictionary = {}
	for key: String in ["phase", "round", "rounds", "end_msec", "round_rows", "rankings"]:
		if not _published.has(key) or _published[key] != data[key]:
			changed[key] = data[key]
	var picture_count: int = _published.get("pictures", []).size()
	if data.pictures.size() > picture_count:
		changed["pictures_added"] = data.pictures.slice(picture_count)
	var rows: Dictionary = {}
	for index: int in data.players.size():
		var row: Dictionary = data.players[index]
		var previous: Dictionary = {} if _published.is_empty() else _published.players[index]
		var patch: Dictionary = {}
		for key: String in row:
			if key in ["slots", "turns"]:
				var cells: Dictionary = {}
				for cell: int in 9:
					if not previous.has(key) or previous[key][cell] != row[key][cell]:
						cells[cell] = row[key][cell]
				if not cells.is_empty():
					patch[key] = cells
			elif not previous.has(key) or previous[key] != row[key]:
				patch[key] = row[key]
		if not patch.is_empty():
			rows[index] = patch
	if not rows.is_empty():
		changed["players"] = rows
	if changed.is_empty():
		return
	changed["revision"] = data.revision
	var error: Error = api.net.broadcast(SNAPSHOT, changed, MultiplayerPeer.TRANSFER_MODE_RELIABLE, false)
	if error != OK:
		_fail("jigsaw_event", error)
		return
	_published = data.duplicate(true)

func _message(sender: Dictionary, topic: StringName, payload: Variant) -> void:
	if not active or not payload is Dictionary:
		return
	if topic == SNAPSHOT and not api.is_host() and sender.peer_id == 1:
		_receive_changes(payload)
	elif topic == ACTION and api.is_host():
		game.receive_action(sender.peer_id, sender.player_ids, payload)

func _players_changed() -> void:
	if not active or not api.is_host():
		return
	for player: Dictionary in api.get_players():
		if not player.connected and not game.rules.withdrawn[player.player_id]:
			game.withdraw_player(player.player_id)

func _finish(result: Dictionary) -> void:
	active = false
	game.stop_match()
	result["request_id"] = request.request_id
	result["reason"] = "completed"
	result["columns"] = [{"key": "score", "title": api.i18n.text(&"result.score"), "format": "integer"}]
	var error: Error = pages.present(result)
	if error != OK:
		_fail("jigsaw_result", error)

func _picture_failed(error: Error) -> void:
	_fail("jigsaw_pictures", error)

func _fail(code: String, error: Error) -> void:
	_close()
	var report_error: Error = api.fail(code, error_string(error))
	if report_error != OK:
		push_error("%s: %s; reporting failed: %s" % [code, error_string(error), error_string(report_error)])

func party_stop(_reason: StringName) -> void:
	_close()

func _close() -> void:
	if _closed:
		return
	_closed = true
	active = false
	# A scope may close after setup but before ready has created its pages.
	if game != null:
		game.stop_match()
		game.action_requested.disconnect(_send_action)
		game.snapshot_ready.disconnect(_broadcast)
		game.match_completed.disconnect(_finish)
		game.picture_failed.disconnect(_picture_failed)
	if pages != null:
		pages.stop()
	if api == null:
		return
	if api.net.message_received.is_connected(_message):
		api.net.message_received.disconnect(_message)
	if api.players_changed.is_connected(_players_changed):
		api.players_changed.disconnect(_players_changed)

func _receive_changes(payload: Dictionary) -> void:
	if not payload.get("revision") is int or payload.revision <= int(_received.get("revision", -1)):
		return
	var candidate: Dictionary = _received.duplicate(true)
	if candidate.is_empty():
		candidate = {"pictures": [], "players": []}
		for player: Dictionary in api.get_players():
			candidate.players.append({"player_id": player.player_id, "slots": [0,0,0,0,0,0,0,0,0], "turns": [0,0,0,0,0,0,0,0,0]})
	for key: String in payload:
		if key == "pictures_added":
			if not payload[key] is Array:
				_fail("jigsaw_event", ERR_INVALID_DATA)
				return
			candidate.pictures.append_array(payload[key])
		elif key == "players":
			if not payload[key] is Dictionary:
				_fail("jigsaw_event", ERR_INVALID_DATA)
				return
			for index: Variant in payload.players:
				if not index is int or index < 0 or index >= candidate.players.size() or not payload.players[index] is Dictionary:
					_fail("jigsaw_event", ERR_INVALID_DATA)
					return
				for field: String in payload.players[index]:
					var value: Variant = payload.players[index][field]
					if field in ["slots", "turns"]:
						if not value is Dictionary:
							_fail("jigsaw_event", ERR_INVALID_DATA)
							return
						for cell: Variant in value:
							if not cell is int or cell < 0 or cell >= 9:
								_fail("jigsaw_event", ERR_INVALID_DATA)
								return
							candidate.players[index][field][cell] = value[cell]
					else:
						candidate.players[index][field] = value
		elif key in ["revision", "phase", "round", "rounds", "end_msec", "round_rows", "rankings"]:
			candidate[key] = payload[key]
		else:
			_fail("jigsaw_event", ERR_INVALID_DATA)
			return
	if not candidate.get("end_msec") is int:
		_fail("jigsaw_event", ERR_INVALID_DATA)
		return
	candidate["remaining_ms"] = maxi(0, candidate.end_msec - api.net.host_time_msec())
	if not game.receive_snapshot(candidate):
		_fail("jigsaw_invalid_event", ERR_INVALID_DATA)
		return
	_received = candidate
