extends SceneTree
## Real scene/controller integration tests. Tweens run on the SceneTree clock.
const Scene = preload("res://main.tscn")
const State = preload("res://scripts/puzzle_state.gd")
var game
var checks := 0
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition and failures.size() < 40:
		failures.append(message)

func wait_for(seconds: float) -> void:
	await create_timer(seconds).timeout

func snapshot() -> Array:
	return [game.state.slots.duplicate(), game.state.turns.duplicate(),
		game.state.selected_slot, game.state.operations, game.state.phase, game.state.busy]

func start_play() -> void:
	game.restart_round()
	game._process(5.0)
	await wait_for(0.78)
	expect(game.state.phase == State.Phase.PLAYING and not game.state.busy, "Actual shuffle tween finishes and unlocks")

func _run() -> void:
	game = Scene.instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.follow_pointer = false
	game.restart_round()
	_test_reveal_boundary()
	await wait_for(0.78)
	expect(game.state.phase == State.Phase.PLAYING, "Five-second reveal advances through actual shuffle callback")
	expect(is_zero_approx(game.elapsed), "Shuffle animation is excluded from solve timing")
	game._process(1.25)
	expect(is_equal_approx(game.elapsed, 1.25), "Solve timer starts after shuffle")
	await _test_selection_and_input()
	await _test_restart_cancels_callbacks()
	await _test_full_solution()
	_test_layouts()
	game.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS: %d scene/controller checks, real tween callbacks, restart interruption, full solve, four layouts." % checks)
		quit(0)
	else:
		for message in failures:
			push_error(message)
		print("FAIL: %d failures / %d scene/controller checks" % [failures.size(), checks])
		quit(1)

func _test_reveal_boundary() -> void:
	expect(game.pieces.size() == 9, "Real scene constructs exactly nine pieces")
	expect(game.state.phase == State.Phase.REVEAL, "Scene starts in reveal")
	expect(is_equal_approx(game.reveal_remaining, 5.0), "Reveal starts at five seconds")
	expect(game.ui.hero.text == "05", "Visible countdown starts at 05")
	game.act_on_slot(0)
	game.rotate_selected_piece()
	expect(game.state.selected_slot == -1 and game.state.operations == 0, "Reveal rejects actual controller input")
	game._process(4.999)
	expect(game.state.phase == State.Phase.REVEAL and game.ui.hero.text == "01", "At 4.999 seconds original art remains visible")
	expect(is_zero_approx(game.elapsed), "Reveal does not count solve time")
	game._process(0.002)
	expect(game.state.phase == State.Phase.SHUFFLING and game.state.busy, "Five-second boundary starts locked shuffle")
	var before := snapshot()
	for i in 20:
		game.act_on_slot(i % 9)
		game.rotate_selected_piece()
	expect(snapshot() == before, "Shuffle ignores repeated controller inputs")

func _test_selection_and_input() -> void:
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	var before := snapshot()
	game._input(right)
	expect(snapshot() == before, "Actual right-button handler is a no-op without selection")
	var source := 4
	var identity: int = game.state.slots[source]
	game.act_on_slot(source)
	expect(game.state.selected_slot == source and game.pieces[identity].lifted, "Pickup lifts piece and retains source placeholder")
	expect(game.pieces[identity].z_index == 20, "Picked piece is above the board")
	var original_position: Vector2 = game.pieces[identity].position
	game.follow_pointer = true
	game._process(0.0)
	expect(game.pieces[identity].position != original_position, "Selected piece follows pointer instead of staying at source")
	expect(game.pieces[identity].scale.is_equal_approx(Vector2.ONE * 1.035), "Picked piece gains gentle elevation scale")
	expect(game.state.selected_slot == source, "Pointer movement preserves source slot")
	game.follow_pointer = false
	game._input(right)
	expect(game.state.busy and game.state.operations == 1, "Right-button handler begins one rotation")
	before = snapshot()
	for i in 30:
		game._input(right)
		game.act_on_slot(i % 9)
	expect(snapshot() == before, "Rapid rotation/clicks during rotation cannot mutate state")
	await wait_for(0.21)
	expect(not game.state.busy and game.state.selected_slot == source, "Rotation tween unlocks and keeps pickup")
	expect(is_equal_approx(fposmod(game.pieces[identity].rotation, TAU), game.state.turns[identity] * PI * 0.5), "Rendered rotation matches model orientation")
	game.act_on_slot(source)
	expect(game.state.busy and game.state.selected_slot == -1, "Same-slot release starts placement tween")
	await wait_for(0.27)
	expect(game.state.operations == 1, "Same-slot placement does not count an operation")
	expect(game.pieces[identity].position.is_equal_approx(game._slot_center(source)), "Placement returns picked tile to original center")
	expect(not game.pieces[identity].lifted and game.pieces[identity].scale.is_equal_approx(Vector2.ONE), "Placement clears elevation")
	game.act_on_slot(source)
	var other: int = game.state.slots[7]
	game.act_on_slot(7)
	before = snapshot()
	for i in 30:
		game.act_on_slot(i % 9)
		game.rotate_selected_piece()
	expect(snapshot() == before, "Rapid clicks while swapping are ignored")
	await wait_for(0.27)
	expect(game.state.operations == 2 and game.state.selected_slot == -1, "Swap counts once and ends pickup")
	expect(game.pieces[identity].position.is_equal_approx(game._slot_center(7)), "Selected piece reaches swap target")
	expect(game.pieces[other].position.is_equal_approx(game._slot_center(source)), "Other piece reaches vacated source")

func _test_restart_cancels_callbacks() -> void:
	for interrupted in ["reveal", "shuffle", "selection", "rotation", "swap"]:
		if interrupted == "reveal":
			game.restart_round()
			game._process(2.0)
		elif interrupted == "shuffle":
			game.restart_round()
			game._process(5.0)
		else:
			await start_play()
			game.act_on_slot(0)
			if interrupted == "rotation":
				game.rotate_selected_piece()
			elif interrupted == "swap":
				game.act_on_slot(8)
		var old_epoch: int = game.animation_epoch
		var previous_seed: int = game.seed_value
		game.restart_round()
		expect(game.animation_epoch > old_epoch, "Restart invalidates callback epoch during %s" % interrupted)
		expect(game.seed_value == previous_seed, "Restart preserves shuffle seed")
		await wait_for(0.8)
		expect(game.state.phase == State.Phase.REVEAL, "Old %s callback cannot escape new reveal" % interrupted)
		expect(game.state.is_solved() and not game.state.busy and game.state.selected_slot == -1, "Restart cleans board/lock/selection after %s" % interrupted)
		expect(game.state.operations == 0 and is_zero_approx(game.elapsed), "Restart clears counters after %s" % interrupted)
		expect(is_equal_approx(game.reveal_remaining, 5.0), "No stale countdown changes restarted reveal")
		for slot in 9:
			expect(game.pieces[slot].position.is_equal_approx(game._slot_center(slot)) and is_zero_approx(game.pieces[slot].rotation), "Restarted pieces stay aligned after %s" % interrupted)
			expect(not game.pieces[slot].lifted, "Restart clears lifted tile after %s" % interrupted)
	var old_round: int = game.round_number
	game.new_round()
	expect(game.round_number == old_round + 1 and game.state.phase == State.Phase.REVEAL, "New-round controller starts another reveal")

func _test_full_solution() -> void:
	await start_play()
	game._process(3.5)
	var expected_operations := 0
	for slot in 9:
		if game.state.slots[slot] != slot:
			game.act_on_slot(game.state.slots.find(slot))
			game.act_on_slot(slot)
			expected_operations += 1
			await wait_for(0.27)
	for slot in 9:
		if game.state.turns[slot] != 0:
			game.act_on_slot(slot)
			while game.state.turns[slot] != 0:
				game.rotate_selected_piece()
				expected_operations += 1
				await wait_for(0.21)
			game.act_on_slot(slot)
			await wait_for(0.27)
	expect(game.state.phase == State.Phase.COMPLETE and game.state.is_solved(), "Actual controller+tweens reach complete state")
	expect(game.state.operations == expected_operations, "Full controller solve counts actual swaps/rotations only")
	expect(game.ui.hero.text == "完成" and game.ui.board_state.text == "还原完成", "Win text reflects completion")
	for id in 9:
		expect(is_zero_approx(game.pieces[id].gap) and not game.pieces[id].lifted, "Win joins image and removes selection")
	var before := snapshot()
	var final_elapsed: float = game.elapsed
	game._process(120.0)
	for slot in 9:
		game.act_on_slot(slot)
	game.rotate_selected_piece()
	expect(snapshot() == before, "Completed controller rejects further gameplay input")
	expect(is_equal_approx(game.elapsed, final_elapsed), "Win freezes elapsed time")
	game.restart_round()
	expect(game.state.phase == State.Phase.REVEAL and game.state.operations == 0, "Restart works after completed round")

func content_rect(widget: Control) -> Rect2:
	# Labels often reserve wider boxes than their text (e.g. the time caption).
	# Use font-derived minimum extents and alignment, not empty box padding.
	var rect := widget.get_rect()
	if widget is Label:
		var minimum := widget.get_minimum_size()
		if widget.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER:
			rect.position.x += (rect.size.x - minimum.x) * 0.5
		elif widget.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT:
			rect.position.x += rect.size.x - minimum.x
		rect.size = minimum
	return rect

func _test_layouts() -> void:
	for viewport_size in [Vector2(1280, 900), Vector2(1600, 900), Vector2(720, 900), Vector2(900, 1200)]:
		game.size = viewport_size
		game._layout()
		var bounds := Rect2(Vector2.ZERO, viewport_size)
		var context := "%dx%d" % [viewport_size.x, viewport_size.y]
		expect(bounds.encloses(game.board_rect) and game.board_rect.size.x > 250, "Board is substantial and in bounds at %s" % context)
		expect(bounds.encloses(game.panel_rect), "Info panel stays in bounds at %s" % context)
		expect(not game.board_rect.intersects(game.panel_rect), "Board and info panel do not overlap at %s" % context)
		for slot in 9:
			expect(game._point_to_slot(game._slot_center(slot)) == slot, "Slot hit-test matches resized board at %s" % context)
		expect(game._point_to_slot(game.board.size) == -1 and game._point_to_slot(Vector2(-1, 0)) == -1, "Outside-board points are ignored at %s" % context)
		var widgets: Array = [game.ui.phase, game.ui.heading, game.ui.description, game.ui.hero,
			game.ui.hero_note, game.ui.time_label, game.ui.time_value, game.ui.moves_label,
			game.ui.moves_value, game.new_button, game.restart_button, game.ui.hint]
		if not game.compact:
			widgets.append_array([game.ui.left_title, game.ui.left_detail, game.ui.right_title, game.ui.right_detail])
		for widget in widgets:
			expect(bounds.encloses(widget.get_rect()), "Visible widget '%s' is within viewport at %s" % [widget.text, context])
			expect(game.panel_rect.grow(2).encloses(widget.get_rect()), "Visible widget '%s' is within panel at %s" % [widget.text, context])
		for i in widgets.size():
			for j in range(i + 1, widgets.size()):
				expect(not content_rect(widgets[i]).grow(-2).intersects(content_rect(widgets[j]).grow(-2)), "Widgets '%s' and '%s' do not overlap at %s" % [widgets[i].text, widgets[j].text, context])
