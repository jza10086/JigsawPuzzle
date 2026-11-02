extends RefCounted
## Add only settings that the game actually consumes.

static func schema() -> Dictionary:
	return {"schema_format": 3, "settings_version": 1, "fields": {}, "layout": []}
