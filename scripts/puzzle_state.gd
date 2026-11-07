class_name PuzzleState
extends RefCounted
## Logical game state. Tile orientations are indexed by identity, never by slot.
enum Phase { REVEAL, SHUFFLING, PLAYING, COMPLETE }
const COUNT: int = 9
var phase: Phase = Phase.REVEAL
var slots: Array[int] = []
var turns: Array[int] = []
var selected_slot: int = -1
var operations: int = 0
var busy: bool = false

func _init() -> void:
	reset()

func reset() -> void:
	slots.clear()
	turns.clear()
	for i: int in COUNT:
		slots.append(i)
		turns.append(0)
	selected_slot = -1
	operations = 0
	busy = false
	phase = Phase.REVEAL

func shuffle_board(rng: RandomNumberGenerator) -> void:
	reset()
	phase = Phase.SHUFFLING
	for i: int in range(COUNT - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var temp: int = slots[i]
		slots[i] = slots[j]
		slots[j] = temp
	# Both placement and orientation must change, even for adversarial RNG output.
	var moved: bool = false
	for i: int in COUNT:
		moved = moved or slots[i] != i
		turns[i] = rng.randi_range(0, 3)
	if not moved:
		slots[0] = 1
		slots[1] = 0
	if turns.count(0) == COUNT:
		turns[rng.randi_range(0, COUNT - 1)] = 1
	busy = true

func begin_play() -> void:
	if phase == Phase.SHUFFLING:
		phase = Phase.PLAYING
		busy = false

func click_slot(slot: int) -> Dictionary:
	if phase != Phase.PLAYING or busy or slot < 0 or slot >= COUNT:
		return {"kind": "ignore"}
	if selected_slot == -1:
		selected_slot = slot
		return {"kind": "pick", "slot": slot, "id": slots[slot]}
	var source: int = selected_slot
	var tile: int = slots[source]
	selected_slot = -1
	busy = true
	if source == slot:
		return {"kind": "place", "slot": slot, "id": tile}
	var other: int = slots[slot]
	slots[source] = other
	slots[slot] = tile
	operations += 1
	return {"kind": "swap", "source": source, "target": slot, "id": tile, "other": other}

func rotate_selected() -> int:
	if phase != Phase.PLAYING or busy or selected_slot == -1:
		return -1
	var tile: int = slots[selected_slot]
	turns[tile] = (turns[tile] + 1) % 4
	operations += 1
	busy = true
	return tile

func settle() -> bool:
	busy = false
	if phase == Phase.PLAYING and selected_slot == -1 and is_solved():
		phase = Phase.COMPLETE
		return true
	return false

func is_solved() -> bool:
	for i: int in COUNT:
		if slots[i] != i or turns[i] != 0:
			return false
	return true

func invariant_holds() -> bool:
	if slots.size() != COUNT or turns.size() != COUNT:
		return false
	var sorted: Array[int] = slots.duplicate()
	sorted.sort()
	for i: int in COUNT:
		if sorted[i] != i or turns[i] < 0 or turns[i] > 3:
			return false
	return selected_slot >= -1 and selected_slot < COUNT
