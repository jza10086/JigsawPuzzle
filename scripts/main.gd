extends Control
## Shared 3D match view and host clock. Transport is injected by party_round.gd;
## F6 uses one real local participant, leaving the other seven seats empty.
signal action_requested(data: Dictionary)
signal snapshot_ready(data: Dictionary)
signal match_completed(result: Dictionary)

const Match: GDScript = preload("res://games/minigame/godot_party_default_jigsaw_puzzle/scripts/match_state.gd")
const Settings: GDScript = preload("res://games/minigame/godot_party_default_jigsaw_puzzle/settings.gd")
const BOARD_SIZE: float = 6.65
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
		configure([{"player_id": "preview", "name": "本机玩家", "color": "#2962ff"}],
			"preview", true, randi(), Settings.DEFAULTS)
		action_requested.connect(func(data: Dictionary) -> void: submit_action(local_id, data))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_view = get_viewport()
	board.gui_input.connect(_board_input)
	answer.hide()
	center_sign.text = "等待比赛开始"
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
	board.resized.connect(_update_camera)
	_update_camera()
	if preview:
		start_match()

func start_match() -> void:
	running = true
	if is_host:
		rules.start(Time.get_ticks_msec())
		_publish()

func stop_match() -> void:
	running = false
	set_process(false)

func godot_party_graphics_targets() -> Dictionary:
	return {"world": graphics_world, "sun": graphics_sun, "materials_root": world}

func _seat_center(seat: int) -> Vector3:
	return seats[seat].global_position

func _slot_center(seat: int, slot: int) -> Vector3:
	return seats[seat].get_node("Slots").get_child(slot).position

func _hud_text(key: StringName, values: Dictionary) -> String:
	return DefaultText.get_message(key).format(values) if i18n == null else i18n.text(key, values)

## Zero yaw keeps the whole board square to the camera. Zoom raises the pitch
## towards top-down and moves the focus to the local seat, without an abrupt cut.
func _update_camera() -> void:
	if camera == null or board.size.y <= 0.0:
		return
	var focus: Vector3 = Vector3.ZERO
	if local_seat >= 0:
		focus = Vector3.ZERO.lerp(_seat_center(local_seat), zoom_value)
	var pitch: float = deg_to_rad(lerpf(68.0, 88.0, zoom_value))
	var extent: float = lerpf(24.5, 8.5, zoom_value)
	var framed_extent: float = maxf(extent, extent / (board.size.x / board.size.y))
	# Keep a fixed perspective lens; zoom moves the camera towards the board.
	var distance: float = framed_extent / (2.0 * tan(deg_to_rad(camera.fov * 0.5)))
	camera.position = focus + Vector3(0, sin(pitch), cos(pitch)) * distance
	camera.look_at(focus)

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
	if party_input != null and party_input.input_blocked:
		return
	if not event is InputEventMouseButton or not event.pressed:
		return
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			zoom_target = clampf(zoom_target + 0.125, 0.0, 1.0)
		MOUSE_BUTTON_WHEEL_DOWN:
			zoom_target = clampf(zoom_target - 0.125, 0.0, 1.0)
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
	# Local host state is trusted; remote snapshots enter through receive_snapshot.
	_apply_view(snapshot)
	snapshot_ready.emit(snapshot)

func receive_snapshot(data: Dictionary) -> bool:
	if not Match.valid_snapshot(data, ids):
		return false
	if view.is_empty() or data.revision > view.revision:
		_apply_view(data)
	return true

func _apply_view(data: Dictionary) -> void:
	var new_round: bool = view.is_empty() or data.round != view.round
	view = data.duplicate(true)
	answer.visible = view.phase != Match.Phase.PLAYING
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
			center_sign.text = "比赛结束 · 按总分排名 · 同分并列"
	for seat: int in players.size():
		var row: Dictionary = view.players[seat]
		var name_text: String = players[seat].name + ("（你）" if seat == local_seat else "")
		var progress: String = "未完成" if row.time < 0 else "%.2f 秒完成" % (float(row.time) / 1000.0)
		if row.withdrawn:
			progress = "已退出"
		if view.phase == Match.Phase.PREPARE:
			progress = "准备中"
		if not view.round_rows.is_empty():
			var result: Dictionary = view.round_rows[seat]
			progress = "本轮第 %d 名 +%d" % [result.rank, result.points] if not row.withdrawn else "已退出"
		if view.phase == Match.Phase.FINISHED and not row.withdrawn:
			progress = "总排名 第 %d 名" % view.rankings[seat].rank
		nameplates[seat].text = _hud_text(&"hud.player", {"player": name_text, "score": row.total, "state": progress})
		for slot: int in 9:
			var id: int = row.slots[slot]
			var piece: PuzzlePiece = pieces[seat * 9 + id]
			piece.set_lifted(slot == row.selected)
			if new_round:
				piece.position = _slot_center(seat, slot)
				piece.rotation.y = -row.turns[id] * PI * 0.5

func _process(delta: float) -> void:
	zoom_value = lerpf(zoom_value, zoom_target, 1.0 - exp(-10.0 * delta))
	_update_camera()
	if not running:
		return
	if is_host:
		rules.advance(Time.get_ticks_msec())
		publish_clock += delta
		if publish_clock >= 0.1:
			publish_clock = 0.0
			_publish()
			if not running:
				return
		if rules.phase == Match.Phase.FINISHED and Time.get_ticks_msec() >= rules.phase_deadline and not result_emitted:
			result_emitted = true
			match_completed.emit({"rankings": rules.rankings(), "game_data": {"rounds": rules.history.duplicate(true)}})
	if view.is_empty():
		return
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
