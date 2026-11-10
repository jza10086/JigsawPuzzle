extends Control
## Shared 3D match view and host clock. Transport is injected by party_round.gd;
## F6 uses one real local participant, leaving the other seven seats empty.
signal action_requested(data: Dictionary)
signal snapshot_ready(data: Dictionary)
signal match_completed(result: Dictionary)
signal picture_failed(error: Error)

const Pictures: GDScript = preload("res://games/minigame/godot_party_default_jigsaw_puzzle/scripts/picture_library.gd")
var picture_stats: Pictures = Pictures.new()
## Empty only in standalone F6 preview. Formal play injects the framework host clock.
var host_clock: Callable

const Match: GDScript = preload("res://games/minigame/godot_party_default_jigsaw_puzzle/scripts/match_state.gd")
const Settings: GDScript = preload("res://games/minigame/godot_party_default_jigsaw_puzzle/settings.gd")
const TILE_HEIGHT: float = 0.10
const LIFT_HEIGHT: float = 0.75

var rules: Match = Match.new()
var players: Array[Dictionary] = []
var ids: Array[String] = []
var local_id: String = ""
var local_seat: int = -1
var is_host: bool = false
var configured: bool = false
var running: bool = false
## Absent only in the standalone scene preview.
var party_input: PartyInput
var result_emitted: bool = false
var sequence: int = 0
var view: Dictionary = {}
var publish_clock: float = 0.0
const TileScene: PackedScene = preload("res://games/minigame/godot_party_default_jigsaw_puzzle/puzzle_piece.tscn")
const DefaultText: Translation = preload("res://games/minigame/godot_party_default_jigsaw_puzzle/i18n/zh_Hans.po")
var i18n: RefCounted
var pieces: Array[PuzzlePiece] = []
var seats: Array[Node3D] = []
var nameplates: Array[Label3D] = []
@onready var answer: Node3D = %Answer
@onready var center_sign: Label3D = %CenterSign
@onready var board: Control = %Board
var board_view: Viewport
@onready var graphics_world: WorldEnvironment = %GraphicsWorld
@onready var graphics_sun: DirectionalLight3D = %GraphicsSun
@onready var world: Node3D = %World
@onready var camera: Camera3D = %Camera
@onready var hover_frame: Node3D = %HoverFrame
var zoom_target: float = 0.0
var zoom_value: float = 0.0
var follow_pointer: bool = true
@export_group("Camera Zoom")
## Far framing comes from the scene Camera's transform and FOV.
@export_range(1.0, 89.0, 0.1) var close_pitch_degrees: float = 88.0
@export_range(1.0, 30.0, 0.1) var close_extent: float = 8.5
@export_range(0.01, 1.0, 0.01) var zoom_step: float = 0.125
@export_range(1.0, 30.0, 0.1) var zoom_response: float = 10.0
var _overview_distance: float
var _overview_focus: Vector3
var _overview_rotation: Vector3

## Called before insertion into the scene tree with the session's fixed seat order.
func configure(roster: Array[Dictionary], my_id: String, host: bool, seed: int, settings: Dictionary) -> void:
	configured = true
	players = roster.duplicate(true)
	local_id = my_id
	is_host = host
	for player: Dictionary in players:
		ids.append(player.player_id)
	local_seat = ids.find(local_id)
	if is_host:
		rules.configure(ids, seed, settings)

func _ready() -> void:
	var preview: bool = not configured
	if preview:
		configure([{"player_id": "preview", "name": _hud_text(&"hud.preview_player"), "color": "#2962ff"}],
			"preview", true, randi(), Settings.DEFAULTS)
		action_requested.connect(func(data: Dictionary) -> void: submit_action(local_id, data))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_view = get_viewport()
	set_process(false)
	$GameHUD.hide()
	answer.hide()
	center_sign.text = _hud_text(&"hud.waiting")
	for index: int in 8:
		var area: Node3D = world.get_node("Seat%d" % (index + 1))
		seats.append(area)
		var plate: Label3D = area.get_node("Nameplate")
		nameplates.append(plate)
		if index >= players.size():
			continue
		plate.text = players[index].name
		area.get_node("Border").material_override.albedo_color = Color(players[index].color)
		for tile: int in 9:
			var piece: PuzzlePiece = TileScene.instantiate()
			piece.tile_id = tile
			area.add_child(piece)
			piece.position = _slot_center(index, tile)
			pieces.append(piece)
	_overview_distance = camera.position.length()
	_overview_focus = camera.position - camera.basis.z * _overview_distance
	_overview_rotation = camera.rotation
	_update_camera()
	if preview:
		start_match()

func start_match() -> void:
	if is_host:
		rules.picture_counts = picture_stats.counts.duplicate()
	running = true
	set_process(true)
	board.mouse_filter = Control.MOUSE_FILTER_STOP
	board.gui_input.connect(_board_input)
	board.resized.connect(_update_camera)
	$GameHUD.show()
	if is_host:
		rules.start(Time.get_ticks_msec())
		_publish()

func stop_match() -> void:
	running = false
	set_process(false)
	zoom_target = zoom_value
	if not is_node_ready():
		return
	hover_frame.hide()
	$GameHUD.hide()
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if board.gui_input.is_connected(_board_input):
		board.gui_input.disconnect(_board_input)
	if board.resized.is_connected(_update_camera):
		board.resized.disconnect(_update_camera)

func godot_party_graphics_targets() -> Dictionary:
	return {"world": graphics_world, "sun": graphics_sun, "materials_root": world}

func _seat_center(seat: int) -> Vector3:
	return seats[seat].global_position

func _slot_center(seat: int, slot: int) -> Vector3:
	return seats[seat].get_node("Slots").get_child(slot).position

func _hud_text(key: StringName, values: Dictionary = {}) -> String:
	return DefaultText.get_message(key).format(values) if i18n == null else i18n.text(key, values)

## Capture the editor's far camera once; zoom retains its yaw/roll and approaches
## the local seat. Near pitch and framing are explicit Inspector settings.
func _update_camera() -> void:
	if board.size.y <= 0.0:
		return
	var focus: Vector3 = _overview_focus
	if local_seat >= 0:
		focus = focus.lerp(_seat_center(local_seat), zoom_value)
	var pitch: float = lerpf(_overview_rotation.x, -deg_to_rad(close_pitch_degrees), zoom_value)
	var near_distance: float = close_extent / (2.0 * tan(deg_to_rad(camera.fov * 0.5)))
	var distance: float = lerpf(_overview_distance, near_distance, zoom_value)
	distance = maxf(distance, distance / (board.size.x / board.size.y))
	camera.rotation = Vector3(pitch, _overview_rotation.y, _overview_rotation.z)
	camera.position = focus + camera.basis.z * distance

func _board_point(point: Vector2, height: float) -> Vector3:
	var viewport_point: Vector2 = board.get_global_transform_with_canvas() * point
	var origin: Vector3 = camera.project_ray_origin(viewport_point)
	var direction: Vector3 = camera.project_ray_normal(viewport_point)
	return origin + direction * ((height - origin.y) / direction.y)

func _point_to_slot(point: Vector2) -> int:
	if local_seat < 0 or not Rect2(Vector2.ZERO, board.size).has_point(point):
		return -1
	var area: Node3D = seats[local_seat]
	var hit: Vector3 = area.to_local(_board_point(point, area.global_position.y + TILE_HEIGHT + 0.1))
	for slot: int in 9:
		var offset: Vector3 = hit - _slot_center(local_seat, slot)
		if absf(offset.x) < 1.0 and absf(offset.z) < 1.0:
			return slot
	return -1

func _board_input(event: InputEvent) -> void:
	if not running:
		return
	if party_input != null and party_input.input_blocked:
		return
	if not event is InputEventMouseButton or not event.pressed:
		return
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			zoom_target = clampf(zoom_target + zoom_step, 0.0, 1.0)
		MOUSE_BUTTON_WHEEL_DOWN:
			zoom_target = clampf(zoom_target - zoom_step, 0.0, 1.0)
		MOUSE_BUTTON_LEFT:
			var slot: int = _point_to_slot(event.position)
			if slot >= 0:
				_send_action({"kind": "click", "slot": slot})
		MOUSE_BUTTON_RIGHT:
			_send_action({"kind": "rotate"})
	board.accept_event()

func _send_action(data: Dictionary) -> void:
	if not running or local_seat < 0 or view.is_empty():
		return
	if view.phase not in [Match.Phase.PLAYING, Match.Phase.CLOSING]:
		return
	if view.players[local_seat].time >= 0 or view.players[local_seat].withdrawn:
		return
	sequence += 1
	data["seq"] = sequence
	data["round"] = view.round
	action_requested.emit(data)

## Identity comes from the transport, never from a claimed ID in the payload.
func receive_action(sender_peer: int, sender_ids: Array, data: Dictionary) -> void:
	if not running or not is_host:
		return
	for player: Dictionary in players:
		if player.peer_id == sender_peer and player.player_id in sender_ids:
			submit_action(player.player_id, data)
			return

func submit_action(id: String, data: Dictionary) -> void:
	if not running or not is_host:
		return
	rules.apply_action(id, data, Time.get_ticks_msec())
	_publish()

func withdraw_player(id: String) -> void:
	if is_host and running:
		rules.withdraw(id, Time.get_ticks_msec())
		_publish()

func _publish() -> void:
	var snapshot: Dictionary = rules.snapshot(Time.get_ticks_msec())
	snapshot["end_msec"] = rules.phase_deadline
	# Local host state is trusted; remote snapshots enter through receive_snapshot.
	_apply_view(snapshot)
	if running:
		snapshot_ready.emit(snapshot)

func receive_snapshot(data: Dictionary) -> bool:
	if not Match.valid_snapshot(data, ids):
		return false
	if view.is_empty() or data.revision > view.revision:
		if not view.is_empty() and (data.round < view.round or data.pictures.slice(0, view.round) != view.pictures):
			return false
		_apply_view(data)
	return true

func _picture_error(error: Error) -> void:
	stop_match()
	push_error("记忆拼图图画或统计读写失败：%s (%s)" % [error_string(error), picture_stats.path])
	picture_failed.emit(error)

func _apply_view(data: Dictionary) -> void:
	var new_round: bool = view.is_empty() or data.round != view.round
	if new_round:
		var texture: Texture2D = load(Pictures.ASSET_ROOT.path_join(data.pictures[-1] + ".svg"))
		if texture == null:
			_picture_error(ERR_CANT_OPEN)
			return
		var previous_round: int = 0 if view.is_empty() else int(view.round)
		var error: Error = picture_stats.record(data.pictures.slice(previous_round))
		if error != OK:
			_picture_error(error)
			return
		for piece: PuzzlePiece in pieces:
			piece.face_material.albedo_texture = texture
		for tile: int in 9:
			var reference: PuzzlePiece = answer.get_node("Tile%d" % tile)
			reference.face_material.albedo_texture = texture
	view = data.duplicate(true)
	answer.visible = view.phase != Match.Phase.PLAYING
	_update_countdown()
	for seat: int in players.size():
		var row: Dictionary = view.players[seat]
		var name_text: String = _hud_text(&"hud.local_player", {"player": players[seat].name}) if seat == local_seat else players[seat].name
		var progress: String = _hud_text(&"hud.incomplete") if row.time < 0 else _hud_text(&"hud.completed", {"time": String.num(float(row.time) / 1000.0, 2)})
		if row.withdrawn:
			progress = _hud_text(&"hud.withdrawn")
		if view.phase == Match.Phase.PREPARE:
			progress = _hud_text(&"hud.preparing")
		if not view.round_rows.is_empty():
			var result: Dictionary = view.round_rows[seat]
			progress = _hud_text(&"hud.round_rank", {"rank": result.rank, "points": result.points}) if not row.withdrawn else _hud_text(&"hud.withdrawn")
		if view.phase == Match.Phase.FINISHED and not row.withdrawn:
			progress = _hud_text(&"hud.total_rank", {"rank": view.rankings[seat].rank})
		nameplates[seat].text = _hud_text(&"hud.player", {"player": name_text, "score": row.total, "state": progress})
		for slot: int in 9:
			var id: int = row.slots[slot]
			var piece: PuzzlePiece = pieces[seat * 9 + id]
			piece.set_lifted(slot == row.selected)
			if new_round:
				piece.position = _slot_center(seat, slot)
				piece.rotation.y = -row.turns[id] * PI * 0.5

func _process(delta: float) -> void:
	zoom_value = lerpf(zoom_value, zoom_target, 1.0 - exp(-zoom_response * delta))
	_update_camera()
	if not running:
		return
	if is_host:
		var previous_phase: int = rules.phase
		var previous_round: int = rules.round_index
		rules.advance(Time.get_ticks_msec())
		if rules.phase != previous_phase or rules.round_index != previous_round:
			_publish()
			if not running:
				return
		if rules.phase == Match.Phase.FINISHED and Time.get_ticks_msec() >= rules.phase_deadline and not result_emitted:
			result_emitted = true
			match_completed.emit({"rankings": rules.rankings(), "game_data": {"rounds": rules.history.duplicate(true)}})
			return
	if view.is_empty():
		return
	_update_countdown()
	var pointer: Vector2 = board.get_local_mouse_position()
	for seat: int in players.size():
		var row: Dictionary = view.players[seat]
		for slot: int in 9:
			var id: int = row.slots[slot]
			var target: Vector3 = _slot_center(seat, slot)
			if slot == row.selected:
				target.y = LIFT_HEIGHT
				if seat == local_seat and follow_pointer:
					var hit: Vector3 = seats[seat].to_local(_board_point(pointer, _seat_center(seat).y + LIFT_HEIGHT + 0.1))
					target.x = clampf(hit.x, -2.0, 2.0)
					target.z = clampf(hit.z, -2.0, 2.0)
			var piece: PuzzlePiece = pieces[seat * 9 + id]
			piece.position = piece.position.lerp(target, 1.0 - exp(-18.0 * delta))
			piece.rotation.y = lerp_angle(piece.rotation.y, -row.turns[id] * PI * 0.5, 1.0 - exp(-18.0 * delta))
	var hover: int = _point_to_slot(pointer)
	hover_frame.visible = local_seat >= 0 and hover >= 0 and view.players[local_seat].selected >= 0
	if hover_frame.visible:
		hover_frame.position = seats[local_seat].to_global(_slot_center(local_seat, hover)) + Vector3(0, 0.12, 0)

func _update_countdown() -> void:
	var now: int = int(host_clock.call()) if host_clock.is_valid() else Time.get_ticks_msec()
	view.remaining_ms = maxi(0, view.end_msec - now)
	var seconds: int = ceili(float(view.remaining_ms) / 1000.0)
	var values: Dictionary = {"round": view.round, "total": view.rounds, "time": seconds}
	match view.phase:
		Match.Phase.PREPARE:
			center_sign.text = _hud_text(&"hud.prepare", values)
		Match.Phase.PLAYING:
			center_sign.text = _hud_text(&"hud.playing", values)
		Match.Phase.CLOSING:
			center_sign.text = _hud_text(&"hud.closing", values)
		Match.Phase.INTERMISSION:
			center_sign.text = _hud_text(&"hud.intermission", values)
		Match.Phase.FINISHED:
			center_sign.text = _hud_text(&"hud.finished")
