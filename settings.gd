extends RefCounted
## Room rules shared by the authoritative match and the local preview.
const DEFAULTS: Dictionary[String, int] = {"duration": 120, "closing_duration": 30, "rounds": 3}

static func schema() -> Dictionary:
	return {
		"schema_format": 3, "settings_version": 1,
		"fields": {
			"duration": {"type": "int", "default": DEFAULTS.duration, "title": "首位完成时限（秒）", "audience": "room", "apply": "next_round", "min": 30, "max": 600, "control": "number"},
			"closing_duration": {"type": "int", "default": DEFAULTS.closing_duration, "title": "首位完成后倒计时（秒）", "audience": "room", "apply": "next_round", "min": 5, "max": 120, "control": "number"},
			"rounds": {"type": "int", "default": DEFAULTS.rounds, "title": "连续小回合数", "audience": "room", "apply": "next_round", "min": 1, "max": 10, "control": "number"}
		},
		"layout": [{"id": "room", "title": "拼图比赛", "expanded": true, "children": [{"field": "duration"}, {"field": "closing_duration"}, {"field": "rounds"}]}]
	}
