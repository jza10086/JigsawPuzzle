extends Control
## Shared 3D match view and host clock. Transport is injected by party_round.gd;
## F6 uses one real local participant, leaving the other seven seats empty.
signal action_requested(data: Dictionary)
signal snapshot_ready(data: Dictionary)
signal match_completed(result: Dictionary)

const Match: GDScript = preload("res://games/minigame/godot_party_default_jigsaw_puzzle/scripts/match_state.gd")
const Settings: GDScript = preload("res://games/minigame/godot_party_default_jigsaw_puzzle/settings.gd")
const Piece: GDScript = preload("res://games/minigame/godot_party_default_jigsaw_puzzle/scripts/puzzle_piece.gd")
const ART: Texture2D = preload("res://games/minigame/godot_party_default_jigsaw_puzzle/assets/garden.svg")
const FONT: Font = preload("res://games/minigame/godot_party_default_jigsaw_puzzle/assets/AtelierSans.otf")
const SEATS: Array[int] = [0, 1, 2, 3, 5, 6, 7, 8]
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
var result_emitted: bool = false
var sequence: int = 0
var view: Dictionary = {}
var publish_clock: float = 0.0
var pieces: Array[PuzzlePiece] = []
var seats: Array[Node3D] = []
var nameplates: Array[Label3D] = []
var answer: Node3D
var center_sign: Label3D
var board: SubViewportContainer
var board_view: SubViewport
var world: Node3D
var camera: Camera3D
var hover_frame: Node3D
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
		configure([{"player_id": "preview", "name": "本机玩家", "color": "#438f78"}],
			"preview", true, randi(), Settings.DEFAULTS)
		action_requested.connect(func(data: Dictionary) -> void: submit_action(local_id, data))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_create_view()
	_create_world()
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

func _create_view() -> void:
	board = SubViewportContainer.new()
	board.stretch = true
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	board.gui_input.connect(_board_input)
	add_child(board)
	board_view = SubViewport.new()
	board_view.own_world_3d = true
	board_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	board.add_child(board_view)
	var controls: Label = Label.new()
	controls.name = "Controls"
	controls.text = "左键：抬起 / 放下 / 交换\n右键：顺时针旋转 90°\n滚轮：缩放 · 靠近自己的棋盘"
	controls.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	controls.offset_left = 28
	controls.offset_top = 28
	controls.offset_right = -28
	controls.offset_bottom = -28
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	controls.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	controls.add_theme_font_override("font", FONT)
	controls.add_theme_font_size_override("font_size", 22)
	controls.add_theme_color_override("font_color", Color("244b42"))
	controls.add_theme_color_override("font_outline_color", Color("f5f2e9"))
	controls.add_theme_constant_override("outline_size", 5)
	add_child(controls)

func _create_world() -> void:
	world = Node3D.new()
	world.name = "SharedPuzzleTable"
	board_view.add_child(world)
	var environment_node: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("e4e9df")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("fff4dc")
	environment.ambient_light_energy = 0.25
	environment_node.environment = environment
	world.add_child(environment_node)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-58, -28, 0)
	light.light_color = Color("fff4df")
	light.light_energy = 0.35
	light.shadow_enabled = true
	world.add_child(light)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	world.add_child(camera)
	camera.current = true
	_box(world, Vector3(200, 0.2, 200), Vector3(0, -0.8, 0), Color("d9e1d4"))
	_box(world, Vector3(23, 0.35, 23), Vector3(0, -0.42, 0.2), Color("b69a72"))
	for seat: int in 8:
		var area: Node3D = Node3D.new()
		area.name = "Seat%d" % (seat + 1)
		area.position = _seat_center(seat)
		world.add_child(area)
		seats.append(area)
		var color: Color = Color(players[seat].color) if seat < players.size() else Color("8b988a")
		_box(area, Vector3(6.65, 0.26, 6.65), Vector3(0, -0.13, 0), color)
		_box(area, Vector3(6.12, 0.04, 6.12), Vector3(0, 0.005, 0), Color("566e5b"))
		for tile: int in 9:
			var piece: PuzzlePiece = _piece(area, tile)
			piece.visible = seat < players.size()
			pieces.append(piece)
		var plate: Label3D = _sign(area, Vector3(0, 0.05, 3.8), 48)
		plate.text = "空位" if seat >= players.size() else players[seat].name
		nameplates.append(plate)
	answer = Node3D.new()
	answer.name = "Answer"
	world.add_child(answer)
	_box(world, Vector3(6.65, 0.26, 6.65), Vector3(0, -0.13, 0), Color("d5b36f"))
	for tile: int in 9:
		_piece(answer, tile)
	answer.visible = false
	center_sign = _sign(world, Vector3(0, 0.06, 3.8), 52)
	center_sign.text = "等待比赛开始"
	hover_frame = Node3D.new()
	world.add_child(hover_frame)
	for offset: float in [-0.98, 0.98]:
		_box(hover_frame, Vector3(0.035, 0.025, 1.98), Vector3(offset, 0, 0), Color("efbd59"))
		_box(hover_frame, Vector3(1.98, 0.025, 0.035), Vector3(0, 0, offset), Color("efbd59"))
	hover_frame.visible = false

func _piece(parent: Node3D, tile: int) -> PuzzlePiece:
	var piece: PuzzlePiece = Piece.new()
	piece.name = "Tile%d" % tile
	piece.artwork = ART
	piece.tile_id = tile
	parent.add_child(piece)
	piece.position = _slot_center(tile)
	return piece

func _sign(parent: Node3D, position_3d: Vector3, font_size: int) -> Label3D:
	var label: Label3D = Label3D.new()
	label.font = FONT
	label.font_size = font_size
	label.pixel_size = 0.01
	label.modulate = Color("244b42")
	label.outline_modulate = Color("f5f2e9")
	label.outline_size = 8
	label.rotation.x = -PI * 0.5
	label.position = position_3d
	parent.add_child(label)
	return label

func _box(parent: Node3D, dimensions: Vector3, center: Vector3, color: Color) -> void:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = dimensions
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = center
	parent.add_child(instance)

func _seat_center(seat: int) -> Vector3:
	var cell: int = SEATS[seat]
	return Vector3((cell % 3 - 1) * 8.0, 0, (cell / 3 - 1) * 8.0)

func _slot_center(slot: int) -> Vector3:
	return Vector3((slot % 3 - 1) * 2.0, TILE_HEIGHT, (slot / 3 - 1) * 2.0)

## Zero yaw keeps the whole board square to the camera. Zoom raises the pitch
## towards top-down and moves the focus to the local seat, without an abrupt cut.
func _update_camera() -> void:
	if camera == null or board.size.y <= 0.0:
		return
	var focus: Vector3 = Vector3.ZERO
	if local_seat >= 0:
		focus = Vector3.ZERO.lerp(_seat_center(local_seat), zoom_value)
	var pitch: float = deg_to_rad(lerpf(52.0, 88.0, zoom_value))
	camera.position = focus + Vector3(0, sin(pitch), cos(pitch)) * 40.0
	camera.look_at(focus)
	var extent: float = lerpf(24.5, 8.5, zoom_value)
	camera.size = maxf(extent, extent / (board.size.x / board.size.y))

func _board_point(point: Vector2, height: float) -> Vector3:
	var viewport_point: Vector2 = point * Vector2(board_view.size) / board.size
	var origin: Vector3 = camera.project_ray_origin(viewport_point)
	var direction: Vector3 = camera.project_ray_normal(viewport_point)
	return origin + direction * ((height - origin.y) / direction.y)

func _point_to_slot(point: Vector2) -> int:
	if local_seat < 0 or not Rect2(Vector2.ZERO, board.size).has_point(point):
		return -1
	var hit: Vector3 = _board_point(point, TILE_HEIGHT + 0.1) - _seat_center(local_seat)
	if hit.x < -3.0 or hit.x >= 3.0 or hit.z < -3.0 or hit.z >= 3.0:
		return -1
	return int((hit.z + 3.0) / 2.0) * 3 + int((hit.x + 3.0) / 2.0)

func _board_input(event: InputEvent) -> void:
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
	var heading: String = "第 %d / %d 轮" % [view.round, view.rounds]
	match view.phase:
		Match.Phase.PREPARE:
			center_sign.text = "%s · 记忆 %d 秒\n中央是答案，准备开始" % [heading, seconds]
		Match.Phase.PLAYING:
			center_sign.text = "%s · 剩余 %d 秒\n首位完成后公开答案" % [heading, seconds]
		Match.Phase.CLOSING:
			center_sign.text = "%s · 结算倒计时 %d 秒\n中央答案已公开" % [heading, seconds]
		Match.Phase.INTERMISSION:
			center_sign.text = "%s · 本轮结算\n%d 秒后开始下一轮" % [heading, seconds]
		Match.Phase.FINISHED:
			center_sign.text = "比赛结束 · 按总分排名\n同分并列"
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
		nameplates[seat].text = "%s · %d 分\n%s" % [name_text, row.total, progress]
		for slot: int in 9:
			var id: int = row.slots[slot]
			var piece: PuzzlePiece = pieces[seat * 9 + id]
			piece.set_lifted(slot == row.selected)
			if new_round:
				piece.position = _slot_center(slot)
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
			var target: Vector3 = _slot_center(slot)
			if slot == row.selected:
				target.y = LIFT_HEIGHT
				if seat == local_seat and follow_pointer:
					var hit: Vector3 = _board_point(pointer, LIFT_HEIGHT + 0.1) - _seat_center(seat)
					target.x = clampf(hit.x, -2.0, 2.0)
					target.z = clampf(hit.z, -2.0, 2.0)
			var piece: PuzzlePiece = pieces[seat * 9 + id]
			piece.position = piece.position.lerp(target, 1.0 - exp(-18.0 * delta))
			piece.rotation.y = lerp_angle(piece.rotation.y, -row.turns[id] * PI * 0.5, 1.0 - exp(-18.0 * delta))
	var hover: int = _point_to_slot(pointer)
	hover_frame.visible = local_seat >= 0 and hover >= 0 and view.players[local_seat].selected >= 0
	if hover_frame.visible:
		hover_frame.position = _seat_center(local_seat) + _slot_center(hover) + Vector3(0, 0.12, 0)
