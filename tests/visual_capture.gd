extends SceneTree
## Optional renderer-driven screenshots; run on an existing desktop, not --headless.
var game
func _initialize() -> void:
	call_deferred("run")
func shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var dir := OS.get_environment("JIGSAW_CAPTURE_DIR")
	if dir.is_empty():
		dir = "res://qa"
	var result := root.get_texture().get_image().save_png(dir.path_join(name + ".png"))
	print("SCREENSHOT ", name, " status=", result)
func run() -> void:
	root.size = Vector2i(1280, 900)
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.follow_pointer = false
	game.reveal_remaining = 5.0
	game._refresh_ui()
	await shot("01-reveal")
	game.seed_value = 20261027
	game._shuffle()
	await create_timer(0.85).timeout
	await shot("02-playing")
	game.act_on_slot(0)
	game.pieces[game.state.slots[0]].position = game._slot_center(4) + Vector2(22, -35)
	game.pieces[game.state.slots[0]].scale = Vector2.ONE * 1.035
	game.rotate_selected_piece()
	await create_timer(0.2).timeout
	await shot("03-selected")
	game.act_on_slot(4)
	await create_timer(0.3).timeout
	await shot("04-swapped")
	# Complete through the same public controller as real mouse input, with real tweens.
	game.set_process(true)
	for target in 9:
		var source: int = game.state.slots.find(target)
		if source != target:
			game.act_on_slot(source)
			game.act_on_slot(target)
			await create_timer(0.26).timeout
		if game.state.turns[target] != 0:
			game.act_on_slot(target)
			while game.state.turns[target] != 0:
				game.rotate_selected_piece()
				await create_timer(0.2).timeout
			game.act_on_slot(target)
			await create_timer(0.26).timeout
	assert(game.state.phase == game.State.Phase.COMPLETE)
	game.set_process(false)
	await shot("05-complete")
	root.size = Vector2i(800, 900)
	await process_frame
	game.restart_round()
	await shot("06-compact")
	print("NATIVE_CAPTURE_DONE")
	quit(0)
