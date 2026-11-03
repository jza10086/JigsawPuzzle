extends Control
## Local 3D puzzle presentation. The state model owns rules; this scene owns
## camera projection, tile animation and controls, without framework services.

signal completed(metrics: Dictionary)

const State: GDScript = preload("res://games/minigame/godot_party_default_jigsaw_puzzle/scripts/puzzle_state.gd")
const Piece: GDScript = preload("res://games/minigame/godot_party_default_jigsaw_puzzle/scripts/puzzle_piece.gd")
const ART: Texture2D = preload("res://games/minigame/godot_party_default_jigsaw_puzzle/assets/garden.svg")
const FONT: Font = preload("res://games/minigame/godot_party_default_jigsaw_puzzle/assets/AtelierSans.otf")
const TILE_HEIGHT: float = 0.10
const LIFT_HEIGHT: float = 0.75

var state: PuzzleState = State.new()
var pieces: Array[PuzzlePiece] = []
var board: SubViewportContainer
var board_view: SubViewport
var world: Node3D
var camera: Camera3D
var hover_frame: Node3D
var reveal_remaining: float = 5.0
var elapsed: float = 0.0
var seed_value: int = 0
var action_tween: Tween
var animation_epoch: int = 0
var hover_slot: int = -1
var follow_pointer: bool = true

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_create_view()
	_create_world()
	board.resized.connect(_frame_camera)
	_frame_camera()
	new_round()

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
	board_view.msaa_3d = Viewport.MSAA_4X
	board.add_child(board_view)

	var controls: Label = Label.new()
	controls.name = "Controls"
	controls.text = "左键：抬起 / 放下 / 交换\n右键：顺时针旋转 90°\nR：重新记忆    N：换个开局"
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
	world.name = "PuzzleTable"
	board_view.add_child(world)
	var environment_node: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("e4e9df")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("fff4dc")
	environment.ambient_light_energy = 0.25
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
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
	camera.position = Vector3(3.8, 9.5, 6.2)
	world.add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	_box(world, Vector3(200, 0.2, 200), Vector3(0, -0.65, 0), Color("d9e1d4"))
	_box(world, Vector3(6.5, 0.32, 6.5), Vector3(0, -0.16, 0), Color("b69a72"))
	_box(world, Vector3(6.12, 0.04, 6.12), Vector3(0, 0.005, 0), Color("566e5b"))
	for i: int in 9:
		var piece: PuzzlePiece = Piece.new()
		piece.name = "Tile%d" % i
		piece.artwork = ART
		piece.tile_id = i
		world.add_child(piece)
		pieces.append(piece)
	hover_frame = Node3D.new()
	world.add_child(hover_frame)
	for offset: float in [-0.98, 0.98]:
		_box(hover_frame, Vector3(0.035, 0.025, 1.98), Vector3(offset, 0, 0), Color("efbd59"))
		_box(hover_frame, Vector3(1.98, 0.025, 0.035), Vector3(0, 0, offset), Color("efbd59"))
	hover_frame.visible = false

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

func _frame_camera() -> void:
	if camera == null or board.size.y <= 0.0:
		return
	camera.size = maxf(9.5, 9.5 / (board.size.x / board.size.y))

func new_round() -> void:
	seed_value = int(Time.get_ticks_usec()) ^ randi()
	_start_reveal()

func restart_round() -> void:
	_start_reveal()

func _start_reveal() -> void:
	_cancel_tween()
	state.reset()
	reveal_remaining = 5.0
	elapsed = 0.0
	hover_slot = -1
	hover_frame.visible = false
	_sync_pieces()

func _cancel_tween() -> void:
	animation_epoch += 1
	if action_tween != null and action_tween.is_valid():
		action_tween.kill()
	action_tween = null

func _exit_tree() -> void:
	_cancel_tween()

func _sync_pieces() -> void:
	for slot: int in 9:
		var id: int = state.slots[slot]
		var piece: PuzzlePiece = pieces[id]
		piece.position = _slot_center(slot)
		piece.rotation.y = -state.turns[id] * PI * 0.5
		piece.set_lifted(slot == state.selected_slot)

func _slot_center(slot: int) -> Vector3:
	return Vector3((slot % 3 - 1) * 2.0, TILE_HEIGHT, (slot / 3 - 1) * 2.0)

## Project the pointer onto the horizontal board, independently of lifted tiles.
## The fixed camera always faces this plane, so the ray cannot be parallel.
func _board_point(point: Vector2, height: float) -> Vector3:
	var viewport_point: Vector2 = point * Vector2(board_view.size) / board.size
	var origin: Vector3 = camera.project_ray_origin(viewport_point)
	var direction: Vector3 = camera.project_ray_normal(viewport_point)
	return origin + direction * ((height - origin.y) / direction.y)

func _point_to_slot(point: Vector2) -> int:
	if not Rect2(Vector2.ZERO, board.size).has_point(point):
		return -1
	var hit: Vector3 = _board_point(point, TILE_HEIGHT + 0.1)
	if hit.x < -3.0 or hit.x >= 3.0 or hit.z < -3.0 or hit.z >= 3.0:
		return -1
	return int((hit.z + 3.0) / 2.0) * 3 + int((hit.x + 3.0) / 2.0)

func _process(delta: float) -> void:
	if state.phase == State.Phase.REVEAL:
		reveal_remaining = maxf(0.0, reveal_remaining - delta)
		if reveal_remaining <= 0.0:
			_shuffle()
	elif state.phase == State.Phase.PLAYING:
		elapsed += delta
	var pointer: Vector2 = board.get_local_mouse_position()
	if state.selected_slot >= 0 and not state.busy and follow_pointer:
		var piece: PuzzlePiece = pieces[state.slots[state.selected_slot]]
		var hit: Vector3 = _board_point(pointer, LIFT_HEIGHT + 0.1)
		piece.position = Vector3(clampf(hit.x, -2.0, 2.0), LIFT_HEIGHT, clampf(hit.z, -2.0, 2.0))
	hover_slot = _point_to_slot(pointer)
	hover_frame.visible = state.selected_slot >= 0 and not state.busy and hover_slot >= 0
	if hover_frame.visible:
		hover_frame.position = _slot_center(hover_slot) + Vector3(0, 0.12, 0)

func _shuffle() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	state.shuffle_board(rng)
	action_tween = create_tween().set_parallel(true)
	action_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	for slot: int in 9:
		var id: int = state.slots[slot]
		# Separate travel heights keep the thick tiles from sliding through each other.
		var target: Vector3 = _slot_center(slot)
		var travel_height: float = 0.4 + float(id) * 0.23
		action_tween.tween_property(pieces[id], "position:y", travel_height, 0.18)
		action_tween.tween_property(pieces[id], "position", Vector3(target.x, travel_height, target.z), 0.55).set_delay(0.18)
		action_tween.tween_property(pieces[id], "rotation:y", -state.turns[id] * PI * 0.5, 0.55).set_delay(0.18)
		action_tween.tween_property(pieces[id], "position:y", TILE_HEIGHT, 0.20).set_delay(0.73)
	var epoch: int = animation_epoch
	action_tween.chain().tween_callback(func() -> void:
		if epoch == animation_epoch:
			state.begin_play())

func _board_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			act_on_slot(_point_to_slot(event.position))
			board.accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			rotate_selected_piece()
			board.accept_event()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_R:
				restart_round()
				get_viewport().set_input_as_handled()
			KEY_N:
				new_round()
				get_viewport().set_input_as_handled()

func act_on_slot(slot: int) -> void:
	var action: Dictionary = state.click_slot(slot)
	match action.kind:
		"pick":
			pieces[action.id].set_lifted(true)
			pieces[action.id].position.y = LIFT_HEIGHT
		"place":
			_animate_placement(action, false)
		"swap":
			_animate_placement(action, true)

func _animate_placement(action: Dictionary, swapping: bool) -> void:
	var piece: PuzzlePiece = pieces[action.id]
	piece.set_lifted(false)
	action_tween = create_tween().set_parallel(true)
	action_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var target: int = action.target if swapping else action.slot
	var destination: Vector3 = _slot_center(target)
	action_tween.tween_property(piece, "position", Vector3(destination.x, LIFT_HEIGHT, destination.z), 0.22)
	if swapping:
		action_tween.tween_property(pieces[action.other], "position", _slot_center(action.source), 0.22)
	action_tween.chain().tween_property(piece, "position:y", TILE_HEIGHT, 0.14)
	var epoch: int = animation_epoch
	action_tween.chain().tween_callback(func() -> void: _settle_action(epoch))

func rotate_selected_piece() -> void:
	var id: int = state.rotate_selected()
	if id < 0:
		return
	var piece: PuzzlePiece = pieces[id]
	action_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	action_tween.tween_property(piece, "rotation:y", piece.rotation.y - PI * 0.5, 0.16)
	var epoch: int = animation_epoch
	action_tween.tween_callback(func() -> void: _settle_action(epoch))

func _settle_action(epoch: int) -> void:
	if epoch != animation_epoch:
		return
	if state.settle():
		_sync_pieces()
		completed.emit({"time": roundi(elapsed * 1000.0), "moves": state.operations})
