extends Control
## Package-local PartyAPI boundary. The game owns all rounds and scoring;
## only logical actions go to the host and only the host publishes board snapshots.
const Gameplay: PackedScene = preload("res://games/minigame/godot_party_default_jigsaw_puzzle/main.tscn")
const GameScript: GDScript = preload("res://games/minigame/godot_party_default_jigsaw_puzzle/scripts/main.gd")
const ACTION: StringName = &"jigsaw/action"
const SNAPSHOT: StringName = &"jigsaw/state"
var api: PartyAPI
var request: Dictionary
var game: GameScript
var active: bool = false

func party_setup(context: PartyAPI, config: Dictionary) -> void:
	api = context
	request = config.duplicate(true)

func _ready() -> void:
	if api == null:
		push_error("请从小游戏轮换启动多人比赛；局部预览请运行 main.tscn。")
		return
	var roster: Array[Dictionary] = []
	var local_id: String = ""
	for player: Dictionary in api.get_players():
		roster.append({"player_id": player.player_id, "peer_id": player.peer_id, "name": player.name,
			"color": api.get_appearance(player.player_id).color})
		if player.is_local:
			local_id = player.player_id
	game = Gameplay.instantiate()
	game.configure(roster, local_id, api.is_host(), api.get_seed(), api.get_settings())
	game.action_requested.connect(_send_action)
	game.snapshot_ready.connect(_broadcast)
	game.match_completed.connect(_finish)
	add_child(game)
	api.net.message_received.connect(_message)
	api.players_changed.connect(_players_changed)
	api.on_close(_close)
	var error: Error = api.mark_ready()
	if error != OK:
		_fail("jigsaw_ready", error)

func party_start() -> void:
	active = true
	game.start_match()
	_players_changed()

func _send_action(data: Dictionary) -> void:
	var error: Error = api.net.send_to_host(ACTION, data)
	if error != OK:
		_fail("jigsaw_action", error)

func _broadcast(data: Dictionary) -> void:
	var error: Error = api.net.broadcast(SNAPSHOT, data, false)
	if error != OK:
		_fail("jigsaw_snapshot", error)

func _message(sender: Dictionary, topic: StringName, payload: Variant) -> void:
	if not active or not payload is Dictionary:
		return
	if topic == SNAPSHOT and not api.is_host() and sender.peer_id == 1:
		if not game.receive_snapshot(payload):
			_fail("jigsaw_invalid_snapshot", ERR_INVALID_DATA)
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
	result["columns"] = [{"key": "score", "title": "总积分", "format": "integer"}]
	var error: Error = api.finish(result)
	if error != OK:
		_fail("jigsaw_result", error)

func _fail(code: String, error: Error) -> void:
	active = false
	game.stop_match()
	var report_error: Error = api.fail(code, error_string(error))
	if report_error != OK:
		push_error("%s: %s; reporting failed: %s" % [code, error_string(error), error_string(report_error)])

func party_stop(_reason: StringName) -> void:
	_close()

func _close() -> void:
	active = false
	game.stop_match()
	if api.net.message_received.is_connected(_message):
		api.net.message_received.disconnect(_message)
	if api.players_changed.is_connected(_players_changed):
		api.players_changed.disconnect(_players_changed)
