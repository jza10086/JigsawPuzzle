extends Control
const State = preload("res://scripts/puzzle_state.gd")
const Piece = preload("res://scripts/puzzle_piece.gd")
const ART = preload("res://assets/garden.svg")
const FONT = preload("res://assets/AtelierSans.otf")
const INK := Color("244b42")
const MUTED := Color("7b8e80")
const PAPER := Color("f5f2e9")
const GREEN := Color("286653")
const GOLD := Color("efbd59")

var state = State.new()
var pieces: Array[Node2D] = []
var board := Control.new()
var board_rect := Rect2()
var panel_rect := Rect2()
var cell := 200.0
var compact := false
var reveal_remaining := 5.0
var elapsed := 0.0
var seed_value := 0
var round_number := 0
var action_tween: Tween
var animation_epoch := 0
var ui := {}
var hover_slot := -1
var follow_pointer := true
var new_button: Button
var restart_button: Button

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var app_theme := Theme.new()
	app_theme.default_font = FONT
	app_theme.default_font_size = 18
	theme = app_theme
	board.mouse_filter = Control.MOUSE_FILTER_STOP
	board.gui_input.connect(_board_input)
	add_child(board)
	for i in 9:
		var piece = Piece.new()
		piece.artwork = ART
		piece.tile_id = i
		board.add_child(piece)
		pieces.append(piece)
	_create_ui()
	resized.connect(_layout)
	_layout()
	new_round()

func _create_ui() -> void:
	_label("brand", "MEMORY ATELIER", 14, MUTED)
	_label("title", "拾光拼图", 36, INK)
	_label("subtitle", "把一眼的美好，拼回完整。", 17, MUTED)
	_label("edition", "VOL. 01    /    花园午后", 15, MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	_label("board_name", "花园午后", 19, INK)
	_label("board_state", "观察完整画面", 14, MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	_label("phase", "01  /  记住这一刻", 15, GREEN)
	_label("heading", "记住这片花园", 29, INK)
	_label("description", "看一眼色彩与细节\n稍后，让九块画面重新相遇。", 17, MUTED)
	_label("hero", "05", 82, GREEN, HORIZONTAL_ALIGNMENT_CENTER)
	_label("hero_note", "秒后打乱", 16, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_label("time_label", "用时", 14, MUTED)
	_label("time_value", "00:00", 28, INK)
	_label("moves_label", "操作", 14, MUTED)
	_label("moves_value", "0", 28, INK)
	_label("left_title", "左键", 17, INK)
	_label("left_detail", "选中 · 放下 · 交换", 14, MUTED)
	_label("right_title", "右键", 17, INK)
	_label("right_detail", "选中后，顺时针旋转 90°", 14, MUTED)
	_label("hint", "位置与方向都正确，才算完成。", 14, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_label("footer", "慢一点，也没关系。每一块都有自己的位置。", 14, MUTED)
	_label("round", "3 × 3   ·   第一回", 14, MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	new_button = _button("换个开局", true)
	new_button.pressed.connect(new_round)
	restart_button = _button("重新记忆", false)
	restart_button.pressed.connect(restart_round)

func _label(key: String, content: String, font_size: int, color: Color, alignment := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var node := Label.new()
	node.text = content
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	node.horizontal_alignment = alignment
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(node)
	ui[key] = node

func _button(content: String, primary: bool) -> Button:
	var node := Button.new()
	node.text = content
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.add_theme_font_size_override("font_size", 17)
	for style_name in ["normal", "hover", "pressed", "focus"]:
		var bg := GREEN if primary else Color("f8f7f0")
		if style_name == "hover":
			bg = Color("357b63") if primary else Color("e9eee4")
		if style_name == "pressed":
			bg = Color("214f41") if primary else Color("dfe8dc")
		var style := _style(bg, 12)
		if not primary or style_name == "focus":
			style.border_color = GOLD if style_name == "focus" else Color("dae2d5")
			style.set_border_width_all(2 if style_name == "focus" else 1)
		node.add_theme_stylebox_override(style_name, style)
	node.add_theme_color_override("font_color", Color("fffdf7") if primary else GREEN)
	node.add_theme_color_override("font_hover_color", Color("fffdf7") if primary else GREEN)
	node.add_theme_color_override("font_pressed_color", Color("fffdf7") if primary else GREEN)
	add_child(node)
	return node

func _style(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	return style

func _place(key: String, rect: Rect2) -> void:
	ui[key].position = rect.position
	ui[key].size = rect.size

func _layout() -> void:
	if ui.is_empty():
		return
	var w := size.x
	var h := size.y
	compact = w / maxf(h, 1.0) < 1.22
	ui.hero.add_theme_font_size_override("font_size", 60 if compact else 82)
	var margin := 42.0 if not compact else 30.0
	_place("brand", Rect2(margin, 25, w - margin * 2, 24))
	_place("title", Rect2(margin, 50, 380, 54))
	_place("subtitle", Rect2(margin + 187, 67, 450, 32))
	ui.subtitle.visible = not compact
	_place("edition", Rect2(w - 350 - margin, 62, 350, 32))
	if not compact:
		var side := minf(h - 254.0, w - 456.0)
		board_rect = Rect2(margin + 12, 162, side, side)
		panel_rect = Rect2(board_rect.end.x + 42, 126, w - board_rect.end.x - 42 - margin, h - 194)
	else:
		var side := minf(w - margin * 2 - 24, h - 520)
		board_rect = Rect2((w - side) * 0.5, 151, side, side)
		panel_rect = Rect2(margin, board_rect.end.y + 30, w - margin * 2, h - board_rect.end.y - 95)
	cell = board_rect.size.x / 3.0
	board.position = board_rect.position
	board.size = board_rect.size
	_place("board_name", Rect2(board_rect.position.x, board_rect.position.y - 39, 200, 30))
	_place("board_state", Rect2(board_rect.end.x - 220, board_rect.position.y - 36, 220, 28))
	var p := panel_rect.position + Vector2(26, 24)
	var pw := panel_rect.size.x - 52
	if not compact:
		_place("phase", Rect2(p.x, p.y, pw, 28))
		_place("heading", Rect2(p.x, p.y + 40, pw, 48))
		_place("description", Rect2(p.x, p.y + 97, pw, 60))
		_place("hero", Rect2(p.x, p.y + 158, pw, 111))
		_place("hero_note", Rect2(p.x, p.y + 282, pw, 29))
		var sy := p.y + 323
		_place("time_label", Rect2(p.x + 14, sy, 110, 24))
		_place("time_value", Rect2(p.x + 14, sy + 25, 130, 42))
		_place("moves_label", Rect2(p.x + pw * 0.55, sy, 100, 24))
		_place("moves_value", Rect2(p.x + pw * 0.55, sy + 25, 110, 42))
		_place("left_title", Rect2(p.x + 43, sy + 104, pw - 43, 27))
		_place("left_detail", Rect2(p.x + 43, sy + 134, pw - 43, 26))
		_place("right_title", Rect2(p.x + 43, sy + 179, pw - 43, 27))
		_place("right_detail", Rect2(p.x + 43, sy + 209, pw - 43, 26))
		new_button.position = Vector2(p.x, panel_rect.end.y - 84)
		new_button.size = Vector2((pw - 10) * 0.51, 48)
		restart_button.position = Vector2(new_button.position.x + new_button.size.x + 10, new_button.position.y)
		restart_button.size = Vector2(pw - new_button.size.x - 10, 48)
		_place("hint", Rect2(p.x - 4, panel_rect.end.y - 31, pw + 8, 24))
	else:
		_place("phase", Rect2(p.x, p.y - 8, pw * 0.6, 28))
		_place("heading", Rect2(p.x, p.y + 24, pw * 0.6, 44))
		_place("description", Rect2(p.x, p.y + 70, pw * 0.56, 56))
		_place("hero", Rect2(p.x + pw * 0.64, p.y + 8, pw * 0.35, 100))
		_place("hero_note", Rect2(p.x + pw * 0.64, p.y + 105, pw * 0.35, 27))
		_place("time_label", Rect2(p.x, p.y + 140, 80, 25))
		_place("time_value", Rect2(p.x + 51, p.y + 133, 130, 42))
		_place("moves_label", Rect2(p.x + 190, p.y + 140, 70, 25))
		_place("moves_value", Rect2(p.x + 243, p.y + 133, 100, 42))
		new_button.position = Vector2(panel_rect.end.x - 254, panel_rect.end.y - 84)
		new_button.size = Vector2(112, 44)
		restart_button.position = Vector2(panel_rect.end.x - 132, panel_rect.end.y - 84)
		restart_button.size = Vector2(112, 44)
		_place("hint", Rect2(p.x, panel_rect.end.y - 28, pw, 24))
	for key in ["left_title", "left_detail", "right_title", "right_detail"]:
		ui[key].visible = not compact
	_place("footer", Rect2(margin, h - 46, w - margin * 2, 26))
	if compact:
		ui.footer.text = "左键：选中 / 放下 / 交换       右键：顺时针旋转"
	else:
		ui.footer.text = "慢一点，也没关系。每一块都有自己的位置。"
	_place("round", Rect2(w - margin - 230, h - 46, 230, 26))
	ui.round.visible = not compact
	# A resize safely settles an in-flight action before positioning pieces.
	_cancel_tween()
	if state.phase == State.Phase.SHUFFLING:
		state.begin_play()
	elif state.phase == State.Phase.PLAYING:
		state.settle()
	_sync_pieces()
	_refresh_ui()
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), PAPER)
	draw_circle(Vector2(size.x - 40, 30), 210, Color("edeedc"))
	draw_circle(Vector2(30, size.y + 10), 230, Color("efe9d9"))
	for i in 4:
		draw_arc(Vector2(size.x - 20, -15), 140 + i * 24, 0.0, PI, 48, Color(0.52, 0.64, 0.48, 0.1), 1.0)
	if board_rect.size.x <= 0:
		return
	var shadow := _style(Color(0.18, 0.28, 0.20, 0.10), 20)
	draw_style_box(shadow, Rect2(board_rect.position - Vector2(14, 10) + Vector2(0, 8), board_rect.size + Vector2(28, 28)))
	draw_style_box(_style(Color("fffdf6"), 20), board_rect.grow(14))
	draw_style_box(_style(Color("cfdbca"), 5), board_rect)
	for i in 9:
		var rect := Rect2(board_rect.position + Vector2(i % 3, i / 3) * cell + Vector2.ONE * 3, Vector2.ONE * (cell - 6))
		draw_style_box(_style(Color("dce4d4"), 2), rect)
		if state.selected_slot == i:
			draw_style_box(_style(Color("bdccbb"), 3), rect)
			_draw_corner_marks(rect.grow(-12), Color("fdfaf0"))
		elif hover_slot == i and state.selected_slot >= 0:
			draw_rect(rect, GOLD, false, 4)
	draw_style_box(_style(Color(0.19, 0.31, 0.21, 0.04), 23), Rect2(panel_rect.position + Vector2(0, 6), panel_rect.size))
	draw_style_box(_style(Color("fffdf7"), 23), panel_rect)
	if not compact:
		var p := panel_rect.position + Vector2(26, 24)
		var pw := panel_rect.size.x - 52
		var sy := p.y + 323
		draw_style_box(_style(Color("f1f3e9"), 13), Rect2(p.x, sy - 9, pw, 86))
		draw_line(Vector2(p.x + pw * 0.49, sy + 6), Vector2(p.x + pw * 0.49, sy + 58), Color("dce4d6"), 1)
		_draw_mouse(Vector2(p.x + 14, sy + 130), false)
		_draw_mouse(Vector2(p.x + 14, sy + 205), true)
	if state.phase == State.Phase.REVEAL:
		var rail := Rect2(board_rect.position.x, board_rect.end.y + 27, board_rect.size.x, 4)
		draw_style_box(_style(Color("dee4d6"), 2), rail)
		rail.size.x *= clampf(reveal_remaining / 5.0, 0, 1)
		draw_style_box(_style(GREEN, 2), rail)
	elif state.phase == State.Phase.COMPLETE:
		for i in 14:
			var x := board_rect.position.x + fmod(i * 131.0 + 27, board_rect.size.x)
			var y := board_rect.position.y - 22 - (i % 3) * 6
			draw_circle(Vector2(x, y), 3 if i % 2 else 4, GOLD if i % 2 else Color("83aa8e"))

func _draw_corner_marks(rect: Rect2, color: Color) -> void:
	for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
		var p: Vector2 = rect.position + corner * rect.size
		draw_line(p, p + Vector2(16 * (1 - 2 * corner.x), 0), color, 2)
		draw_line(p, p + Vector2(0, 16 * (1 - 2 * corner.y)), color, 2)

func _draw_mouse(center: Vector2, right: bool) -> void:
	var outline := _style(Color("edf1e6"), 12)
	outline.border_color = Color("b4c7b4")
	outline.set_border_width_all(1)
	draw_style_box(outline, Rect2(center - Vector2(13, 19), Vector2(26, 38)))
	draw_style_box(_style(GOLD if right else Color("84b09a"), 4), Rect2(center + Vector2(1 if right else -10, -15), Vector2(9, 13)))
	draw_line(center - Vector2(0, 16), center - Vector2(0, 2), Color("fffdf6"), 2)

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
	_sync_pieces()
	_refresh_ui()
	queue_redraw()

func _cancel_tween() -> void:
	animation_epoch += 1
	if action_tween and action_tween.is_valid():
		action_tween.kill()
	action_tween = null

func _sync_pieces() -> void:
	for slot in 9:
		var id: int = state.slots[slot]
		var piece = pieces[id]
		piece.side = cell
		piece.gap = 0.0 if state.phase == State.Phase.REVEAL or state.phase == State.Phase.COMPLETE else 5.0
		piece.position = _slot_center(slot)
		piece.rotation = state.turns[id] * PI * 0.5
		piece.scale = Vector2.ONE
		piece.set_lifted(slot == state.selected_slot)
		piece.queue_redraw()

func _slot_center(slot: int) -> Vector2:
	return Vector2(slot % 3 + 0.5, slot / 3 + 0.5) * cell

func _process(delta: float) -> void:
	if state.phase == State.Phase.REVEAL:
		reveal_remaining = maxf(0, reveal_remaining - delta)
		if reveal_remaining <= 0:
			_shuffle()
	elif state.phase == State.Phase.PLAYING:
		elapsed += delta
	if state.selected_slot >= 0 and not state.busy and follow_pointer:
		var piece = pieces[state.slots[state.selected_slot]]
		var mouse := board.get_local_mouse_position()
		var limit := cell * 0.35
		piece.position = mouse.clamp(Vector2.ONE * limit, board.size - Vector2.ONE * limit)
		piece.scale = Vector2.ONE * 1.035
	var local := board.get_local_mouse_position()
	var next_hover := _point_to_slot(local)
	if hover_slot != next_hover:
		hover_slot = next_hover
		queue_redraw()
	_refresh_ui()
	if state.phase == State.Phase.REVEAL:
		queue_redraw()

func _shuffle() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	state.shuffle_board(rng)
	for piece in pieces:
		piece.gap = 5.0
		piece.queue_redraw()
	action_tween = create_tween().set_parallel(true)
	action_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	for slot in 9:
		var id: int = state.slots[slot]
		action_tween.tween_property(pieces[id], "position", _slot_center(slot), 0.7)
		action_tween.tween_property(pieces[id], "rotation", state.turns[id] * PI * 0.5, 0.7)
	var epoch := animation_epoch
	action_tween.chain().tween_callback(func():
		if epoch == animation_epoch:
			state.begin_play()
			_refresh_ui()
			queue_redraw())
	_refresh_ui()

func _point_to_slot(point: Vector2) -> int:
	if not Rect2(Vector2.ZERO, board.size).has_point(point):
		return -1
	return int(point.y / cell) * 3 + int(point.x / cell)

func _board_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		act_on_slot(_point_to_slot(event.position))
		accept_event()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		rotate_selected_piece()
		get_viewport().set_input_as_handled()

func act_on_slot(slot: int) -> void:
	var action: Dictionary = state.click_slot(slot)
	match action.kind:
		"pick":
			pieces[action.id].set_lifted(true)
		"place":
			_animate_placement(action, false)
		"swap":
			_animate_placement(action, true)
	_refresh_ui()
	queue_redraw()

func _animate_placement(action: Dictionary, swapping: bool) -> void:
	var piece = pieces[action.id]
	piece.set_lifted(false)
	action_tween = create_tween().set_parallel(true)
	action_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var target: int = action.target if swapping else action.slot
	action_tween.tween_property(piece, "position", _slot_center(target), 0.22)
	action_tween.tween_property(piece, "scale", Vector2.ONE, 0.22)
	if swapping:
		action_tween.tween_property(pieces[action.other], "position", _slot_center(action.source), 0.22)
	var epoch := animation_epoch
	action_tween.chain().tween_callback(func(): _settle_action(epoch))

func rotate_selected_piece() -> void:
	var id: int = state.rotate_selected()
	if id < 0:
		return
	var piece = pieces[id]
	action_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	action_tween.tween_property(piece, "rotation", piece.rotation + PI * 0.5, 0.16)
	var epoch := animation_epoch
	action_tween.tween_callback(func(): _settle_action(epoch))
	_refresh_ui()

func _settle_action(epoch: int) -> void:
	if epoch != animation_epoch:
		return
	if state.settle():
		_sync_pieces()
	_refresh_ui()
	queue_redraw()

func _refresh_ui() -> void:
	if ui.is_empty():
		return
	ui.time_value.text = "%02d:%02d" % [int(elapsed) / 60, int(elapsed) % 60]
	ui.moves_value.text = str(state.operations)
	ui.round.text = "3 × 3   ·   第 %02d 回" % round_number
	match state.phase:
		State.Phase.REVEAL:
			ui.phase.text = "01  /  记住这一刻"
			ui.heading.text = "记住这片花园"
			ui.description.text = "看一眼色彩与细节\n稍后，让九块画面重新相遇。"
			ui.hero.text = "%02d" % maxi(1, ceili(reveal_remaining))
			ui.hero_note.text = "秒后打乱"
			ui.board_state.text = "观察完整画面"
			ui.hint.text = "位置与方向都正确，才算完成。"
		State.Phase.SHUFFLING:
			ui.phase.text = "02  /  打乱中"
			ui.heading.text = "记忆准备好了吗"
			ui.description.text = "九块画面，九个小小线索。\n马上开始。"
			ui.hero.text = "3 × 3"
			ui.hero_note.text = "位置与方向已打乱"
			ui.board_state.text = "正在打乱…"
		State.Phase.PLAYING:
			ui.phase.text = "02  /  让美好归位"
			ui.heading.text = "跟着记忆，慢慢拼"
			ui.description.text = "交换位置，转正方向。\n把花园还给这个午后。"
			ui.hero.text = "3 × 3"
			ui.hero_note.text = "九块画面 · 一个完整午后"
			ui.board_state.text = "已选中 · 右键旋转" if state.selected_slot >= 0 else "自由还原中"
			ui.hint.text = "点击原位放下，点击另一块交换。" if state.selected_slot >= 0 else "先左键选一块，再右键旋转。"
		State.Phase.COMPLETE:
			ui.phase.text = "03  /  完整的美好"
			ui.heading.text = "拼好了！"
			ui.description.text = "你留住了这一刻。\n再看一眼，花园依然晴朗。"
			ui.hero.text = "完成"
			ui.hero_note.text = "位置正确 · 方向正确"
			ui.board_state.text = "还原完成"
			ui.hint.text = "想再试一次？换个开局吧。"
