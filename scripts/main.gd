extends Control
## Local 3D puzzle presentation. The state model owns rules; this scene owns
## camera projection, tile animation and UI, without framework services.

signal completed(metrics: Dictionary)

const State: GDScript = preload("res://games/minigame/godot_party_default_jigsaw_puzzle/scripts/puzzle_state.gd")
const Piece: GDScript = preload("res://games/minigame/godot_party_default_jigsaw_puzzle/scripts/puzzle_piece.gd")
const ART: Texture2D = preload("res://games/minigame/godot_party_default_jigsaw_puzzle/assets/garden.svg")
const FONT: Font = preload("res://games/minigame/godot_party_default_jigsaw_puzzle/assets/AtelierSans.otf")
const INK: Color = Color("244b42")
const MUTED: Color = Color("7b8e80")
const GREEN: Color = Color("286653")
const TILE_HEIGHT: float = 0.10
const LIFT_HEIGHT: float = 0.75

var state: PuzzleState = State.new()
var pieces: Array[PuzzlePiece] = []
var board: SubViewportContainer
var board_view: SubViewport
var world: Node3D
var camera: Camera3D
var hover_frame: Node3D
var content: BoxContainer
var panel: PanelContainer
var ui: Dictionary[String, Label] = {}
var reveal_remaining: float = 5.0
var elapsed: float = 0.0
var seed_value: int = 0
var round_number: int = 0
var action_tween: Tween
var animation_epoch: int = 0
var hover_slot: int = -1
var follow_pointer: bool = true
var new_button: Button
var restart_button: Button

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var app_theme: Theme = Theme.new()
	app_theme.default_font = FONT
	app_theme.default_font_size = 22
	theme = app_theme
	_create_ui()
	_create_world()
	resized.connect(_layout)
	board.resized.connect(_frame_camera)
	_layout()
	new_round()

func _create_ui() -> void:
	var background: ColorRect = ColorRect.new()
	background.color = Color("f5f2e9")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 32)
	add_child(margin)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 20)
	margin.add_child(column)
	_label(column, "brand", "MEMORY ATELIER  /  3D", 18, MUTED)
	_label(column, "title", "拾光拼图 · 花园午后", 38, INK)
	content = BoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 24)
	column.add_child(content)
	board = SubViewportContainer.new()
	board.stretch = true
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	board.gui_input.connect(_board_input)
	content.add_child(board)
	board_view = SubViewport.new()
	board_view.own_world_3d = true
	board_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	board_view.msaa_3d = Viewport.MSAA_4X
	board.add_child(board_view)
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(Color("fffdf7"), 24))
	content.add_child(panel)
	var details: VBoxContainer = VBoxContainer.new()
	details.add_theme_constant_override("separation", 18)
	panel.add_child(details)
	_label(details, "phase", "", 19, GREEN)
	_label(details, "heading", "", 30, INK)
	_label(details, "description", "", 21, MUTED)
	_label(details, "hero", "", 58, GREEN)
	_label(details, "hero_note", "", 20, MUTED)
	var stats: HBoxContainer = HBoxContainer.new()
	stats.add_theme_constant_override("separation", 40)
	details.add_child(stats)
	_label(stats, "time_value", "", 26, INK)
	_label(stats, "moves_value", "", 26, INK)
	var spacer: Control = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.add_child(spacer)
	_label(details, "controls", "左键：抬起 / 放下 / 交换\n右键：顺时针旋转 90°", 20, INK)
	_label(details, "hint", "", 18, MUTED)
	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	details.add_child(buttons)
	new_button = _button(buttons, "换个开局", true)
	new_button.pressed.connect(new_round)
	restart_button = _button(buttons, "重新记忆", false)
	restart_button.pressed.connect(restart_round)
	_label(column, "footer", "五秒记住花园，再把九块画面归位。", 19, MUTED)

func _label(parent: Node, key: String, text: String, font_size: int, color: Color) -> void:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	ui[key] = label

func _style(color: Color, radius: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 24
	style.content_margin_bottom = 24
	return style

func _button(parent: Node, text: String, primary: bool) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size.y = 56
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for style_name: String in ["normal", "hover", "pressed", "focus"]:
		var color: Color = GREEN if primary else Color("e9eee4")
		if style_name == "hover":
			color = color.lightened(0.10)
		elif style_name == "pressed":
			color = color.darkened(0.10)
		var style: StyleBoxFlat = _style(color, 10)
		style.content_margin_top = 10
		style.content_margin_bottom = 10
		if style_name == "focus":
			style.border_color = Color("efbd59")
			style.set_border_width_all(3)
		button.add_theme_stylebox_override(style_name, style)
	for color_name: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(color_name, Color("fffdf7") if primary else INK)
	parent.add_child(button)
	return button

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

func _layout() -> void:
	var compact: bool = size.x < 1100.0
	content.vertical = compact
	panel.custom_minimum_size.x = 0.0 if compact else 440.0
	ui.description.visible = not compact
	ui.hero.visible = not compact
	ui.hero_note.visible = not compact
	ui.controls.visible = not compact
	_frame_camera()

func _frame_camera() -> void:
	if camera == null or board.size.y <= 0.0:
		return
	camera.size = maxf(9.5, 9.5 / (board.size.x / board.size.y))

func new_round() -> void:
	round_number += 1
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
	_refresh_ui()

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
	_refresh_ui()

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
			state.begin_play()
			_refresh_ui())
	_refresh_ui()

func _board_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			act_on_slot(_point_to_slot(event.position))
			board.accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			rotate_selected_piece()
			board.accept_event()

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
	_refresh_ui()

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
	_refresh_ui()

func _settle_action(epoch: int) -> void:
	if epoch != animation_epoch:
		return
	if state.settle():
		_sync_pieces()
		completed.emit({"time": roundi(elapsed * 1000.0), "moves": state.operations})
	_refresh_ui()

func _refresh_ui() -> void:
	ui.time_value.text = "用时 %02d:%02d" % [int(elapsed) / 60, int(elapsed) % 60]
	ui.moves_value.text = "操作 %d" % state.operations
	ui.footer.text = "左键：抬起 / 放下 / 交换    ·    右键：顺时针旋转    /    第 %02d 回" % round_number
	match state.phase:
		State.Phase.REVEAL:
			ui.phase.text = "01  /  记住这一刻"
			ui.heading.text = "记住这片花园"
			ui.description.text = "看一眼色彩与细节\n稍后，让九块画面重新相遇。"
			ui.hero.text = "%02d" % maxi(1, ceili(reveal_remaining))
			ui.hero_note.text = "秒后打乱"
			ui.hint.text = "%d 秒后打乱 · 位置与方向都正确才算完成。" % maxi(1, ceili(reveal_remaining))
		State.Phase.SHUFFLING:
			ui.phase.text = "02  /  打乱中"
			ui.heading.text = "记忆准备好了吗"
			ui.description.text = "九块画面，九个小小线索。\n马上开始。"
			ui.hero.text = "3 × 3"
			ui.hero_note.text = "位置与方向正在打乱"
			ui.hint.text = "拼块落下后开始计时。"
		State.Phase.PLAYING:
			ui.phase.text = "02  /  让美好归位"
			ui.heading.text = "跟着记忆，慢慢拼"
			ui.description.text = "交换位置，转正方向。\n把花园还给这个午后。"
			ui.hero.text = "3 × 3"
			ui.hero_note.text = "九块立体拼图 · 一个完整午后"
			ui.hint.text = "点击原位放下，点击另一格交换。" if state.selected_slot >= 0 else "先左键选一块，再右键旋转。"
		State.Phase.COMPLETE:
			ui.phase.text = "03  /  完整的美好"
			ui.heading.text = "拼好了！"
			ui.description.text = "你留住了这一刻。\n再看一眼，花园依然晴朗。"
			ui.hero.text = "完成"
			ui.hero_note.text = "位置正确 · 方向正确"
			ui.hint.text = "想再试一次？换个开局吧。"
