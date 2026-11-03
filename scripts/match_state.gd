extends RefCounted
## Host-only match rules. Times are monotonic milliseconds supplied by the caller.
## Each participant owns one puzzle; no client-supplied board or finish time is trusted.
const Puzzle: GDScript = preload("res://games/minigame/godot_party_default_jigsaw_puzzle/scripts/puzzle_state.gd")
enum Phase { PREPARE, PLAYING, CLOSING, INTERMISSION, FINISHED }
const PREPARE_MS: int = 5000
const INTERMISSION_MS: int = 6000

var ids: Array[String] = []
var boards: Dictionary[String, PuzzleState] = {}
var totals: Dictionary[String, int] = {}
var finished: Dictionary[String, int] = {}
var withdrawn: Dictionary[String, bool] = {}
var sequences: Dictionary[String, int] = {}
var round_rows: Array[Dictionary] = []
var history: Array[Dictionary] = []
var phase: Phase = Phase.PREPARE
var round_index: int = 0
var round_count: int
var duration_ms: int
var closing_ms: int
var seed_value: int
var phase_deadline: int = 0
var play_started: int = 0
var revision: int = 0

func configure(player_ids: Array[String], seed: int, settings: Dictionary) -> void:
	ids = player_ids.duplicate()
	seed_value = seed
	round_count = settings.rounds
	duration_ms = settings.duration * 1000
	closing_ms = settings.closing_duration * 1000
	for id: String in ids:
		boards[id] = Puzzle.new()
		totals[id] = 0
		finished[id] = -1
		withdrawn[id] = false
		sequences[id] = 0

func start(now: int) -> void:
	_begin_round(now)

func _begin_round(now: int) -> void:
	round_index += 1
	phase = Phase.PREPARE
	phase_deadline = now + PREPARE_MS
	round_rows.clear()
	# Identical openings within a round keep the race fair; the next round has a new seed.
	for id: String in ids:
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = seed_value + round_index * 104729
		boards[id].shuffle_board(rng)
		finished[id] = -1

func advance(now: int) -> void:
	if phase == Phase.PREPARE and now >= phase_deadline:
		play_started = now
		phase = Phase.PLAYING
		phase_deadline = now + duration_ms
		for id: String in ids:
			boards[id].begin_play()
	elif phase == Phase.PLAYING and now >= phase_deadline:
		_end_round(now, true)
	elif phase == Phase.CLOSING and now >= phase_deadline:
		_end_round(now, false)
	elif phase == Phase.INTERMISSION and now >= phase_deadline:
		_begin_round(now)

## Validate a logical action once at the host boundary. Late/repeated/wrong-round
## packets cannot edit the next round, another player's board, or a completed board.
func apply_action(id: String, data: Dictionary, now: int) -> bool:
	advance(now)
	if not boards.has(id) or withdrawn[id] or finished[id] >= 0:
		return false
	if phase != Phase.PLAYING and phase != Phase.CLOSING:
		return false
	if not data.get("round") is int or data.round != round_index:
		return false
	if not data.get("seq") is int or data.seq <= sequences[id]:
		return false
	if data.get("kind") != "click" and data.get("kind") != "rotate":
		return false
	if data.kind == "click" and (not data.get("slot") is int or data.slot < 0 or data.slot >= 9):
		return false
	sequences[id] = data.seq
	var puzzle: PuzzleState = boards[id]
	if data.kind == "click":
		var action: Dictionary = puzzle.click_slot(data.slot)
		if action.kind == "ignore":
			return false
	else:
		if puzzle.rotate_selected() < 0:
			return false
	if puzzle.settle():
		finished[id] = now - play_started
		if phase == Phase.PLAYING:
			phase = Phase.CLOSING
			phase_deadline = now + closing_ms
		if _everyone_done():
			_end_round(now, false)
	return true

func withdraw(id: String, now: int) -> void:
	withdrawn[id] = true
	boards[id].selected_slot = -1
	if (phase == Phase.PLAYING or phase == Phase.CLOSING) and _everyone_done():
		_end_round(now, false)

func _everyone_done() -> bool:
	for id: String in ids:
		if not withdrawn[id] and finished[id] < 0:
			return false
	return true

func _end_round(now: int, timed_out: bool) -> void:
	round_rows.clear()
	for id: String in ids:
		var rank_value: int = ids.size()
		var points: int = 1
		if timed_out:
			rank_value = 1
		elif finished[id] >= 0 and not withdrawn[id]:
			rank_value = 1
			for other: String in ids:
				if not withdrawn[other] and finished[other] >= 0 and finished[other] < finished[id]:
					rank_value += 1
			points = ids.size() + 1 - rank_value
		if withdrawn[id]:
			rank_value = 0
			points = 0
		totals[id] += points
		boards[id].selected_slot = -1
		round_rows.append({"player_id": id, "rank": rank_value, "points": points, "time": finished[id], "total": totals[id], "withdrawn": withdrawn[id]})
	history.append({"round": round_index, "timed_out": timed_out, "rows": round_rows.duplicate(true)})
	phase = Phase.FINISHED if round_index == round_count else Phase.INTERMISSION
	phase_deadline = now + INTERMISSION_MS

func rankings() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for id: String in ids:
		var rank_value: int = 1
		for other: String in ids:
			if not withdrawn[other] and totals[other] > totals[id]:
				rank_value += 1
		rows.append({"player_id": id, "rank": 0 if withdrawn[id] else rank_value,
			"status": "withdrawn" if withdrawn[id] else "completed",
			"metrics": {"score": totals[id]}})
	return rows

func snapshot(now: int) -> Dictionary:
	revision += 1
	var rows: Array[Dictionary] = []
	for id: String in ids:
		var puzzle: PuzzleState = boards[id]
		rows.append({"player_id": id, "slots": puzzle.slots.duplicate(), "turns": puzzle.turns.duplicate(),
			"selected": puzzle.selected_slot, "operations": puzzle.operations, "time": finished[id],
			"withdrawn": withdrawn[id], "total": totals[id]})
	return {"revision": revision, "phase": phase, "round": round_index, "rounds": round_count,
		"remaining_ms": maxi(0, phase_deadline - now), "players": rows,
		"round_rows": round_rows.duplicate(true), "rankings": rankings()}

## Host snapshots are external input too. Reject invalid identity/order or tile
## permutations before the view indexes meshes. Never replace a corrupt state with defaults.
static func valid_snapshot(data: Dictionary, player_ids: Array[String]) -> bool:
	for key: String in ["revision", "phase", "round", "rounds", "remaining_ms"]:
		if not data.get(key) is int:
			return false
	if data.revision < 1 or data.phase < Phase.PREPARE or data.phase > Phase.FINISHED or data.remaining_ms < 0:
		return false
	if data.round < 1 or data.round > data.rounds or data.rounds > 10:
		return false
	if not data.get("players") is Array or data.players.size() != player_ids.size():
		return false
	for index: int in player_ids.size():
		var row: Variant = data.players[index]
		if not row is Dictionary or row.get("player_id") != player_ids[index]:
			return false
		if not row.get("slots") is Array or row.slots.size() != 9 or not row.get("turns") is Array or row.turns.size() != 9:
			return false
		var seen: Array[int] = []
		for tile: Variant in row.slots:
			if not tile is int or tile < 0 or tile >= 9 or tile in seen:
				return false
			seen.append(tile)
		for turn: Variant in row.turns:
			if not turn is int or turn < 0 or turn > 3:
				return false
		for key: String in ["selected", "operations", "time", "total"]:
			if not row.get(key) is int:
				return false
		if row.selected < -1 or row.selected >= 9 or row.operations < 0 or row.time < -1 or row.total < 0 or not row.get("withdrawn") is bool:
			return false
	for key: String in ["round_rows", "rankings"]:
		if not data.get(key) is Array:
			return false
	if data.rankings.size() != player_ids.size() or data.round_rows.size() not in [0, player_ids.size()]:
		return false
	for index: int in player_ids.size():
		var rank: Variant = data.rankings[index]
		if not rank is Dictionary or rank.get("player_id") != player_ids[index] or not rank.get("rank") is int:
			return false
		if rank.rank < 0 or rank.rank > player_ids.size() or rank.get("status") not in ["completed", "withdrawn"]:
			return false
		if not rank.get("metrics") is Dictionary or not rank.metrics.get("score") is int or rank.metrics.score < 0:
			return false
		if not data.round_rows.is_empty():
			var row: Variant = data.round_rows[index]
			if not row is Dictionary or row.get("player_id") != player_ids[index]:
				return false
			for field: String in ["rank", "points", "time", "total"]:
				if not row.get(field) is int:
					return false
			if row.rank < 0 or row.rank > player_ids.size() or row.points < 0 or row.points > player_ids.size() or row.time < -1 or row.total < 0 or not row.get("withdrawn") is bool:
				return false
	return true
