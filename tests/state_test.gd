extends SceneTree
## Standalone, dependency-free contract tests for the gameplay state machine.
const State = preload("res://scripts/puzzle_state.gd")
var checks := 0
var failures: Array[String] = []

func _init() -> void:
	_test_initial_and_phase_locks()
	_test_seeded_shuffle()
	_test_degenerate_shuffle_seeds()
	_test_selection_rotation_and_swapping()
	_test_repeated_busy_inputs()
	_test_restart_every_phase()
	_test_win_contract()
	_test_seeded_solvers()
	_test_randomized_action_sequences()
	if failures.is_empty():
		print("PASS: %d checks; 1,000 shuffled boards; 1,000 complete solves; 50,000 randomized actions." % checks)
		quit(0)
	else:
		for message in failures:
			push_error(message)
		print("FAIL: %d recorded failures / %d checks" % [failures.size(), checks])
		quit(1)

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition and failures.size() < 30:
		failures.append(message)

func snapshot(state) -> Array:
	return [state.slots.duplicate(), state.turns.duplicate(), state.selected_slot,
		state.operations, state.busy, state.phase]

func playing(seed_value: int = 42):
	var state = State.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	state.shuffle_board(rng)
	state.begin_play()
	return state

func _test_initial_and_phase_locks() -> void:
	var state = State.new()
	expect(state.invariant_holds(), "Initial state invariant")
	expect(state.phase == State.Phase.REVEAL, "Initial phase is reveal")
	expect(state.is_solved(), "Reveal presents complete original artwork")
	var before := snapshot(state)
	for i in 9:
		expect(state.click_slot(i).kind == "ignore", "Reveal blocks pickup")
	expect(state.rotate_selected() == -1, "Reveal blocks rotation")
	state.begin_play()
	expect(snapshot(state) == before, "Only shuffling may transition to play")
	var rng := RandomNumberGenerator.new()
	rng.seed = 18
	state.shuffle_board(rng)
	before = snapshot(state)
	for i in 9:
		expect(state.click_slot(i).kind == "ignore", "Shuffle blocks pickup")
	expect(state.rotate_selected() == -1, "Shuffle blocks rotation")
	expect(snapshot(state) == before, "Ignored shuffle inputs are side-effect free")
	state.begin_play()
	expect(state.phase == State.Phase.PLAYING and not state.busy, "Shuffle completion starts play")
	before = snapshot(state)
	for invalid in [-100, -1, 9, 100]:
		expect(state.click_slot(invalid).kind == "ignore", "Out-of-board slot ignored")
	expect(state.rotate_selected() == -1, "Right click with no selection ignored")
	expect(snapshot(state) == before, "Invalid inputs never count operations or change state")

func _test_seeded_shuffle() -> void:
	for seed_value in 1000:
		var state = State.new()
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		state.shuffle_board(rng)
		expect(state.invariant_holds(), "Permutation/turn bounds seed %d" % seed_value)
		expect(not state.is_solved(), "Shuffle cannot start solved seed %d" % seed_value)
		var moved := false
		for slot in 9:
			moved = moved or state.slots[slot] != slot
		expect(moved, "Shuffle changes placement seed %d" % seed_value)
		expect(state.turns.count(0) < 9, "Shuffle changes orientation seed %d" % seed_value)
		expect(state.phase == State.Phase.SHUFFLING and state.busy, "Shuffle is locked seed %d" % seed_value)
		expect(state.operations == 0 and state.selected_slot == -1, "Shuffle resets round counters")
		var repeat = State.new()
		rng.seed = seed_value
		repeat.shuffle_board(rng)
		expect(repeat.slots == state.slots and repeat.turns == state.turns, "Seed is reproducible")

func _test_degenerate_shuffle_seeds() -> void:
	# These seeds exercise identity-permutation and all-upright fallback branches
	# on Godot 4.7.2. Assertions retain the gameplay contract if Godot changes RNG.
	for seed_value in [463011, 1625137]:
		var state = State.new()
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		state.shuffle_board(rng)
		expect(state.invariant_holds(), "Degenerate seed keeps a valid permutation")
		expect(state.slots != [0, 1, 2, 3, 4, 5, 6, 7, 8], "Identity shuffle fallback forces a positional change")
		expect(state.turns.count(0) < 9, "All-upright shuffle fallback forces an orientation change")
		expect(not state.is_solved(), "Degenerate shuffle never starts solved")

func _test_selection_rotation_and_swapping() -> void:
	var state = playing()
	var before := snapshot(state)
	expect(state.rotate_selected() == -1, "Unselected right click no-op")
	expect(snapshot(state) == before, "Unselected right click does not mutate")
	var original_turns: Array = state.turns.duplicate()
	var original_slots: Array = state.slots.duplicate()
	var tile: int = state.slots[2]
	expect(state.click_slot(2).kind == "pick", "Left click picks up")
	expect(state.selected_slot == 2 and state.operations == 0, "Pickup stores source with zero cost")
	for quarter in 4:
		expect(state.rotate_selected() == tile, "Right click rotates picked identity")
		expect(state.turns[tile] == (original_turns[tile] + quarter + 1) % 4, "Clockwise turn is modulo four")
		state.settle()
	expect(state.turns == original_turns, "Four rotations restore all orientations")
	expect(state.operations == 4, "Each actual rotation counts once")
	expect(state.slots == original_slots, "Rotation never moves or duplicates tiles")
	var count_before: int = state.operations
	expect(state.click_slot(2).kind == "place", "Click original slot puts piece down")
	expect(state.selected_slot == -1, "Placement releases selection")
	state.settle()
	expect(state.slots == original_slots and state.operations == count_before, "Same-slot placement is free and preserves permutation")
	state.click_slot(2)
	state.rotate_selected()
	state.settle()
	var rotated_turns: Array = state.turns.duplicate()
	var target_tile: int = state.slots[7]
	var action: Dictionary = state.click_slot(7)
	expect(action.kind == "swap" and action.id == tile and action.other == target_tile, "Swap reports both identities")
	expect(state.slots[7] == tile and state.slots[2] == target_tile, "Swap exchanges exactly two identities")
	expect(state.turns == rotated_turns, "Orientations travel with tile identity through swaps")
	expect(state.selected_slot == -1, "Swap ends selection")
	expect(state.operations == count_before + 2, "One rotation and one swap add exactly two")
	state.settle()
	expect(state.invariant_holds(), "Swap preserves invariant")

func _test_repeated_busy_inputs() -> void:
	for operation in ["rotate", "place", "swap"]:
		var state = playing(58)
		state.click_slot(4)
		if operation == "rotate":
			state.rotate_selected()
		elif operation == "place":
			state.click_slot(4)
		else:
			state.click_slot(8)
		expect(state.busy, "%s starts animation lock" % operation)
		var before := snapshot(state)
		for repeat in 100:
			expect(state.click_slot(repeat % 9).kind == "ignore", "Rapid left clicks ignored during %s" % operation)
			expect(state.rotate_selected() == -1, "Rapid right clicks ignored during %s" % operation)
		expect(snapshot(state) == before, "Busy repeated clicks preserve exact snapshot during %s" % operation)
		state.settle()
		expect(not state.busy and state.invariant_holds(), "Animation settling safely unlocks %s" % operation)

func _test_restart_every_phase() -> void:
	for phase in [State.Phase.REVEAL, State.Phase.SHUFFLING, State.Phase.PLAYING, State.Phase.COMPLETE]:
		for selected in [false, true]:
			for busy in [false, true]:
				var state = playing(109)
				state.phase = phase
				state.selected_slot = 5 if selected else -1
				state.busy = busy
				state.operations = 79
				state.reset()
				expect(state.phase == State.Phase.REVEAL, "Restart returns to reveal at every phase")
				expect(state.selected_slot == -1 and not state.busy, "Restart clears selection and lock")
				expect(state.operations == 0 and state.is_solved(), "Restart resets operations and image")
				expect(state.invariant_holds(), "Restart restores invariant")
				state.settle() # A late caller must not turn reveal into a victory.
				state.begin_play() # A late shuffle completion must not skip new reveal.
				expect(state.phase == State.Phase.REVEAL, "Stale settle/begin calls cannot skip restarted reveal")

func _test_win_contract() -> void:
	for tile in 9:
		for wrong_turn in [1, 2, 3]:
			var state = State.new()
			state.phase = State.Phase.PLAYING
			state.turns[tile] = wrong_turn
			expect(not state.is_solved() and not state.settle(), "Correct locations but wrong orientation cannot win")
			expect(state.phase == State.Phase.PLAYING, "Wrong orientation remains playable")
	var state = State.new()
	state.phase = State.Phase.PLAYING
	state.slots[0] = 1
	state.slots[1] = 0
	expect(not state.is_solved() and not state.settle(), "Correct rotations but wrong locations cannot win")
	state.reset()
	state.phase = State.Phase.PLAYING
	state.turns[8] = 3
	state.click_slot(8)
	state.rotate_selected()
	expect(state.is_solved(), "Last quarter turn restores source")
	expect(not state.settle() and state.phase == State.Phase.PLAYING, "Held piece must be placed before completing")
	expect(state.click_slot(8).kind == "place", "Winning tile placed at source slot")
	expect(state.settle() and state.phase == State.Phase.COMPLETE, "All positions/orientations placed triggers victory")
	expect(state.operations == 1, "Winning placement remains free")
	var before := snapshot(state)
	for slot in 9:
		expect(state.click_slot(slot).kind == "ignore", "Completed state blocks pickup")
	expect(state.rotate_selected() == -1, "Completed state blocks right click")
	state.begin_play()
	expect(snapshot(state) == before, "Completed board is immutable until restart")

func _test_seeded_solvers() -> void:
	for seed_value in 1000:
		var state = playing(seed_value)
		var expected_operations := 0
		for slot in 9:
			if state.slots[slot] != slot:
				var source: int = state.slots.find(slot)
				expect(state.click_slot(source).kind == "pick", "Solver pickup")
				expect(state.click_slot(slot).kind == "swap", "Solver swap")
				expected_operations += 1
				state.settle()
		for slot in 9:
			if state.turns[slot] != 0:
				state.click_slot(slot)
				while state.turns[slot] != 0:
					state.rotate_selected()
					expected_operations += 1
					state.settle()
				state.click_slot(slot)
				state.settle()
		expect(state.is_solved() and state.phase == State.Phase.COMPLETE, "Deterministic solver wins seed %d" % seed_value)
		expect(state.operations == expected_operations, "Solver operation accounting seed %d" % seed_value)
		expect(state.selected_slot == -1 and state.invariant_holds(), "Solver terminal invariant seed %d" % seed_value)

func _test_randomized_action_sequences() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 773183
	for round_index in 100:
		var state = playing(round_index + 8000)
		for step in 500:
			var before := snapshot(state)
			var action: int = rng.randi_range(0, 11)
			if action < 7:
				var slot: int = rng.randi_range(-1, 9)
				var result: Dictionary = state.click_slot(slot)
				if result.kind == "ignore":
					expect(snapshot(state) == before, "Random ignored click is immutable")
			elif action < 9:
				if state.rotate_selected() == -1:
					expect(snapshot(state) == before, "Random ignored rotation is immutable")
			elif action < 11:
				state.settle()
			else:
				state.reset()
				state.shuffle_board(rng)
				state.begin_play()
			expect(state.invariant_holds(), "Random sequence invariant round %d step %d" % [round_index, step])
			expect(state.operations >= 0, "Random sequence operations nonnegative")
